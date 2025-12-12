-------------------------------------------------------------------------------
-- Gopher
-- by Tammya-MoonGuard (Copyright 2018)
--
-- All Rights Reserved.
-------------------------------------------------------------------------------
-- This is our simple chat sender with a throttling feature.
-------------------------------------------------------------------------------
local Me = LibGopher.Internal
if not Me.load then return end

-- We have a basic chat throttler here. One might ask why we don't just use
--  ChatThrottleLib. We used to use libbw (a more bnet friendly CTL), but
--  there's a number of reasons it's our own implementation now.
-- (1) CTL doesn't support Bnet or community messages.
-- (2) CTL shares our bandwidth with addon data.
--     Our philosophy here is that chat text should have utmost priority, 
--      no matter how much data is being sent by addons. CTL splits data 
--      evenly between its different priorities. We want ALL of the bandwidth
--      while we're sending a chat message. Chat messages are not a regular
--      occurance so they can takeover the bandwidth.
-- (3) It's a pain in the ass to make it work right if you're hooking messages
--     from SendChatMessage, which COULD be from CTL, and then you have to deal
--     with the potential problem of feeding messages back into CTL after they
--     were already processed. We had a bit of a hacky solution for that before
--     which required hooks in CTL, but we don't do that anymore in preference
--     for this solution. This is more forward compatible.
-- The one little caveat to our little system, or Gopher's system in
--  general is when we intercept a chat message. When CTL sees addons sending
--  chat messages that haven't passed through its system, it subtracts from its
--  available bandwidth. This is a good thing, but the problem is when we
--  intercept a chat message /from/ CTL. In that case, we're breaking out of
--  their system, sending it on our own time... There's no easy way to detect
--  if we're pulling a message from CTL.
--
--  (0) CTL -> (1) _G.SendChatMessage -> Our Hook   (3) CTL's SCM Hook -> ...
--                                          |        ^
--                                          v        | 
--                                     (2) Gopher Queue --> (4) Wait --.
--                                              ^----------------------'
--
-- In (0) CTL subtracts from it's available bandwidth. It also does that in (3)
-- (3) has a check to see if it's executing from within CTL, but that check
--  fails if we reach (4) and break out of this execution path.
--
-- This could also look like this, if another addon loads before Gopher
--  that loads ChatThrottleLib:
--
-- (0) CTL -> (1) _G.SendChatMessage -> (2) CTL's hook -> (3) Our Hook
--                                                                  |
--                                                            .-----'
--                                                            v     
--                                       ... <-- (4) Our Queue (Might Wait)
--
-- This is a bit of a better execution path, except for we might be pushing
--  a little more over the chat limit, because CTL's hook is skipped when
--  the message is actually sent.
-------------------------------------------------------------------------------
-- Some configuration here. BPS is how many bytes per second it will send
--  messages at. Each message's byte size is the length of the message text 
--  plus MSG_OVERHEAD. We don't actually know the limits on the server side, so
--  we don't waste much time being very exact with our calculations.
-- BURST is how much bandwidth we can store if there is a period of inactivity.
local THROTTLE_BPS   = 1000
local THROTTLE_BURST = 2000
local TIMER_PERIOD   = 0.25
local MSG_OVERHEAD   = 25
-------------------------------------------------------------------------------
-- `bandwidth` is how many bytes we can send in the frame. It stores up to
--  THROTTLE_BURST over time. `bandwidth_time` is the last point in game time
--  when we added to the bandwidth.
-- During combat, we cut our limits in half too, because typically those are
--  a bit more strict in how much data extra data is flying around, because
--  a lot of it is already used up by your intense rotation.
Me.bandwidth       = 0
Me.bandwidth_time  = GetTime()
-------------------------------------------------------------------------------
-- A simple list of chat messages being queued. This uses the same format from
--  our chat queue outside, so the table items can be directly dropped into
--  here. It's a FIFO, [1] is the first to go, [#] is the last.
Me.out_chat_buffer = {}
-------------------------------------------------------------------------------
-- `send_queue_started` is when the sending loop is active, and may stay
--  active over multiple frames. `throttler_started` is only true if the
--  throttler is waiting in a timer. Technically, we don't need two variables
--  for this. We could merge them, but I feel that it's cleaner to have two,
--  especially moving forward if we add more things. Throttler_started is
--  basically just a flag so we don't call OnThrottlerStart multiple times.
Me.send_queue_started = false
Me.throttler_started  = false

local function MaxBandwidth()
	if InCombatLockdown() then
		return THROTTLE_BURST/2
	else
		return THROTTLE_BURST
	end
end

-------------------------------------------------------------------------------
-- Check the time and add to our bandwidth pool.
local function UpdateBandwidth()
	local time = GetTime()
	
	-- GetTime() doesn't change when you call it multiple times during the
	--  same frame, so if it's equal to our last time, then we're already up
	--  to date on bandwidth this frame.
	if time == Me.bandwidth_time then return end
	
	-- Chomp/libbw does this too:
	-- If the player's in combat, we cut down our rates by half. Naturally,
	--  there's going to be a lot going on when the player is killing or
	--  healing something, and we definitely don't want them to disconnect.
	-- Better safe than sorry!
	local bps, burst = THROTTLE_BPS, THROTTLE_BURST
	if InCombatLockdown() then
		bps   = bps / 2
		burst = burst / 2
	end
	
	-- We add BPS*TIME (seconds) to bandwidth and then cap it with our 
	--  burst limit.
	Me.bandwidth = math.min( Me.bandwidth + bps * (time-Me.bandwidth_time), burst )
	Me.bandwidth_time = time
end

-------------------------------------------------------------------------------
-- If the send calls error from invalid input for whatever reason (trying to
--  programatically send invalid chat type or similar situation) then the state
--                         of the throttler will be unstable, so we pcall them.
local function SafeCall( api, ... )
	local result, a = pcall( api, ... )
	if Me.debug_mode and not result then
		Me.DebugLog( "Send API error.", a )
	end
	
	if result then
		return a
	end
end

-------------------------------------------------------------------------------
-- This is the actual sending function, but it also has a bandwidth check.
-- If there's enough bandwidth, it sends the chat message and then subtracts
--  from the remaining bandwidth.
-- Input is in the chat queue format.
-- Returns true if the message was sent. False if there wasn't enough
--  bandwidth.
local function TryDispatchMessage( msg )

	-- MSG_OVERHEAD is a guesstimate of how much extra data is attached to the
	--  message to make it use more bytes of bandwidth; things like channel
	--  name, chat type, club id, etc.
	local size = (#msg.msg + MSG_OVERHEAD)
	if size > Me.bandwidth and Me.bandwidth < (MaxBandwidth() - 50) then 
		-- Not enough bandwidth.
		-- Note that this still goes through if bandwidth is insufficient if
		--  we're near the peak BURST. This is to account for sending
		--  max-length messages (4000 bytes) when our burst is only 2000
		--  or 1000.
		return "WAIT"
	end
   
   local hardware = Me.inside_hook or Me.triggered_from_keystroke
	
	local msgtype = msg.type
	
	Me.bandwidth = Me.bandwidth - size
	
	-- We also handle parsing the message type and then routing it to the
	--  different underlying APIs.
	if msgtype == "BNET" then
		-- Battle.net whisper.
		SafeCall( Me.hooks.BNSendWhisper, msg.target, msg.msg )
	elseif msgtype == "CLUB" then
		-- Community channel message.
		-- Our SendChatMessage hook also directs community "CHANNEL" messages
		--  to this chat type, as well as GUILD and OFFICER.
      if not hardware then return "PROMPT" end
      
      Me.addon_action_blocked = false
		SafeCall( Me.hooks.ClubSendMessage, msg.arg3, msg.target, msg.msg )
      if Me.addon_action_blocked then
         -- Going to lose some bandwidth here, but whatever.
         return "PROMPT"
      end
      
	elseif msgtype == "CLUBDELETE" then
      -- These probably need safety checks for the new 8.2.5 stuff, but
      --  they don't really have use cases currently.
		SafeCall( C_Club.DestroyMessage, msg.arg3, msg.target, msg.cmid )
	elseif msgtype == "CLUBEDIT" then
		SafeCall( C_Club.EditMessage, msg.arg3, msg.target, msg.cmid, msg.msg )
	else
		-- Otherwise, this is treated like a normal SendChatMessage message.
      
      if not hardware then
         -- CHANNEL is blocked if there isn't a hardware trigger.
         -- SAY and YELL are blocked too, but only if in the open world.
         if (msg.type == "CHANNEL")
            or ((msg.type == "SAY" or msg.type == "YELL")
                                  and not IsInInstance()) then
            return "PROMPT"
         end
      end
		
		-- Some chat types shouldn't allow metadata, but maybe there might be
		--  some odd use-case for it later?
		local meta = msg.meta
		if meta then
			-- Basically if the meta field is set, this message has metadata
			--  attached, and it comes in an array of pairs of entries that
			--  are `prefix` and `text`. The metadata chat type and target 
			--  mimic where the actual chat is going, and WoW guarantees that
			--  the metadata will always be received before the chat, so long
			--  as the call is made first.
			for i = 1, #meta, 2 do
				if type(meta[i]) == "function" then
					Me.bandwidth =
					       Me.bandwidth - (SafeCall( meta[i], meta[i+1] ) or 0)
				else
					SafeCall( C_ChatInfo.SendAddonMessage, meta[i], meta[i+1], 
				                                          msgtype, msg.target )
					Me.bandwidth = Me.bandwidth - #meta[i] - #meta[i+1]
				end
			end
		end
		
      Me.addon_action_blocked = false
		SafeCall( Me.hooks.SendChatMessage, msg.msg, msgtype, 
		                                                 msg.arg3, msg.target )
      if Me.addon_action_blocked then
         -- Going to lose some bandwidth here, but whatever.
         return "PROMPT"
      end
      
      
		-- For public chats that can trigger the server throttle, we measure
		--  the latency to help us out in severe situations where the client
		--  is nearly disconnecting (this helps to avoid double-posting).
		if msgtype == "SAY" or msgtype == "EMOTE" or msgtype == "YELL" then
			Me.StartLatencyRecording()
		end
	end
   
   Me.OnChatSent( msg )
	return "PASSED"
end

-------------------------------------------------------------------------------
-- Unfortunately, we gotta have this little ugly definition here, because we're
--  using some recursion below. RunSendQueue needs a reference to this, and
local ScheduleSendQueue -- ScheduleSendQueue needs a reference to RunSendQueue,
                        --  defined below.
-------------------------------------------------------------------------------
-- Our sending loop.
--
local function RunSendQueue()
	UpdateBandwidth()
	-- Try to send as many messages as possible. This is like a threaded loop.
	-- If it has to wait for more bandwidth, then it cuts execution and starts 
	while #Me.out_chat_buffer > 0 do --                  a timer to continue.
		local msg = Me.out_chat_buffer[1]
      local status = TryDispatchMessage( msg )
		if status == "PASSED" then
			table.remove( Me.out_chat_buffer, 1 )
			
			-- One thing I wish Lua had was a continue statement; with that,
			--  we could easily rework this function to not have two copies
			--  of ScheduleSendQueue in here.
			-- `slowpost` is an option where the send delay /always/ happens
			--  after sending a message. This effect just makes it so that
			--  your emotes don't show up in large chunks and are posted
			--  slower, one at a time, always.
			-- There's no benefit to it other than aesthetic preference.
			if msg.slowpost then
				ScheduleSendQueue()
				return
			end
      elseif status == "WAIT" then
			-- If there isn't any bandwidth, then we start a thread.
			ScheduleSendQueue()
			return
		elseif status == "PROMPT" then
         -- We need a hardware event to continue.
         Me.PromptForContinue()
			return
      end
	end
	
	-- This is a callback to the main code that lets it know we're done
	--  sending messages. It only triggers if we actually have delays.
	-- In other words, if execution reaches here without any timers,
	--  then the OnThrottlerStart/OnThrottlerStop aren't called.
	if Me.throttler_started then
		Me.throttler_started = false
		--*Me.OnThrottlerStop()
		Me.FireEvent( "THROTTLER_STOP" )
	end
	
	-- All done!
	Me.send_queue_started = false
end

-------------------------------------------------------------------------------
-- We delay execution of RunSendQueue, and restart it after our TIMER_PERIOD.
--
ScheduleSendQueue = function()
	-- Trigger this callback if we're first starting one of these delays.
	if not Me.throttler_started then
		Me.throttler_started = true
		--*Me.OnThrottlerStart()
		Me.FireEvent( "THROTTLER_START" )
	end
	
	C_Timer.After( TIMER_PERIOD, RunSendQueue )
end

function Me.PipeThrottlerKeystroke()
   Me.triggered_from_keystroke = true
   RunSendQueue()
   Me.triggered_from_keystroke = false
end

-------------------------------------------------------------------------------
-- Start outputting messages. Typical use is inserting entries into
--  `out_chat_buffer`, and then calling this. Can call as many times as you
--  want without problems. I always like to design APIs like this where there's
--  very little consequence to keeping your code outside down to a minimum.
local function StartSendQueue()
	if Me.send_queue_started then return end
	Me.send_queue_started = true
	RunSendQueue()
	
	-- `send_queue_started` may be false again here now. If it's not, then
	--  RunSendQueue triggered a timer and is waiting for more bandwidth, and
	--  will complete in the background. You can still freely add messages
	--  to the output buffer in the meanwhile.
end

-------------------------------------------------------------------------------
function Me.ThrottlerActive()
	return Me.throttler_started
end

-------------------------------------------------------------------------------
-- Output a chat message; throttle if necessary.
-- 
-- `msg` is in the same format as the ones in our chat queue outside.
--
-- This is the final step to sending out a message from our chat queue. Well,
--  technically it isn't, because we wait after sending certain types to make
--  sure that they made it through. If they don't,then we resend them.
function Me.CommitChat( msg )
	table.insert( Me.out_chat_buffer, msg )
	StartSendQueue()
end

-------------------------------------------------------------------------------
-- Returns what % of bandwidth is currently available.
--
-- Note, that when InCombatLockdown() this will return a max of 50.
--
function Me.ThrottlerHealth()
	UpdateBandwidth()
	return math.ceil(Me.bandwidth / THROTTLE_BURST * 100)
end

