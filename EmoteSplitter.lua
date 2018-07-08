-------------------------------------------------------------------------------
-- Emote Splitter
-- by Tammya-MoonGuard (2018)
--
--                      A l l  R i g h t s  R e s e r v e d
--
-- Allows you to easily paste long emotes in the chat window. Now with 2000%
--  more code comments. Look at all this purport! How much is too much? I hope
--  you view with 4-space tabs...
-- .
--  ✧･ﾟ: *✧･ﾟ♬ Let me take you on a ride down Emote Splitter lane. ♬･ﾟ: *✧･ﾟ:*
--                                                                           '
-- Here are the key features that this addon provides. (This is sort of a goal
--  list of what should be expected of it.)
--   * Robust message queue system which re-sends failed messages. Sometimes
--      the server might give you an error if you send messages immediately
--      after the last. Emote Splitter works around that by saving your
--      messages and verifying the response from the server.
--   * Support for all chat types. Alongside public messages, Emote Splitter
--      is compatible with the other chat channels. Battle.net 
--      (or Blizzard w/e) also have (or had) a bug where messages might appear
--      out of order, so those are queued like public messages too - sends
--      one at a time to make sure they're all right. Weak support for 
--      global channels, because those are harder to test without spamming
--      everyone.
--   * Seamless feel. Emote Splitter should feel like there's nothing going on
--      It hides any error messages from the client, and also supports slightly
--      abusing the chat throttler addons to speed up message posting.
--   * Protection from your emotes getting lost (ctrl-z). A bit of a niche
--      feature. Perhaps it could use a little work in how the undo/redo works
--      but honestly that's complicated. The main purpose of this is to save
--      emotes from being lost. For example, if you disconnect, or if you
--      accidentally close the editbox, you can open it right back up, press
--      ctrl-z, and get your work back.
-----------------------------------------------------------------------------^-

-- Good code comments don't tell you the obvious. Good code tells you what's
--  going on already. You want your comments to offer a fresh perspective, or
--  just tell you something interesting. I read that in the Java manual. Ever
--  written Java? Their principles and manual are actually pretty nice, and
--  I don't think they get enough credit for it.
-- Each addon is passed in from the parent the addon name (the folder name, 
--  EmoteSplitter, no spaces), and a special table. We use this table to pass
local AddonName, Me = ...  -- around info from our other files.


-- We're embedding our "AceAddon" into that table. 
LibStub("AceAddon-3.0"):NewAddon(-- AceAddon lets us do that
	-- by passing it into here as the first argument, so it doesn't create
	Me, AddonName, -- an empty one.
	"AceHook-3.0",  --> We use AceHook to hook the game's chat message
	               --    functions.
	"AceEvent-3.0"  --> And we use AceEvent for listening to the game's 
	               --    chat message events, among other things we might
	               --    want to spy on.
)

-- We expose our API and internals to the world as `EmoteSplitter`.
EmoteSplitter = Me

local L = Me.Locale -- Easy access to our locale data.

-------------------------------------------------------------------------------
-- Our slash command /emotesplitter.
--
SlashCmdList["EMOTESPLITTER"] = function( msg )

	-- By default, with no arguments, we open up the configuration panel.
	-- Might want to trim msg of whitespace. Or maybe test if you can even pass
	--  pure whitespace to a chat command. Oh well though. I doubt a lot of
	--  people will use the chat command for getting to the options anyway.
	if msg == "" then
		Me.Options_Show()
		return
	end
	
	-- Using a simple pattern here to parse out arguments. %s+ matches 
	--  whitespace "words", %S+ matches "non-whitespace" words.
	local args = msg:gmatch( "%S+" ) -- Might seem a little weird doing it like
	local arg1 = args()              --  this, but sometimes lua iterators can
	local arg2 = args()              --  make odd code like this.
	
	-- Command to change the maximum message length.
	--                                    /emotesplitter maxlen <number>
	if arg1:lower() == "maxlen" then
		-- Humans can be pretty nasty in what they give to you, and it might
		--  not even be on purpose. I'd say that a /lot/ of code in the world
		--  is just there to sanitize what human's give computers.
		local v = tonumber(arg2) or 0 -- 40 might still be obnoxiously low,
		v = math.max( v, 40 )         --  floor, but who knows, maybe someone
		v = math.min( v, 255 )        --  might need that much extra room.
		-- It's is an obscure need anyway, so we don't really care too much.
		-- Our primary concern is probably trolls using this feature, to spam
		--  a lot of nonsense with tons of split messages. But that's what the
		--Me.max_message_length = v  -- ignore and report spam features are for,
		Gopher:SetChunkSize( "OTHER", v )
		print( L( "Max message length set to {1}.", v ))         -- right?
		return
	end
end

-------------------------------------------------------------------------------
-- Here's the real initialization code. This is called after all addons are 
--                                     -- initialized, and so is the game.
function Me:OnEnable()
	-- We definitely cannot work if UnlimitedChatMessage is enabled at the
	--  same time. If we see that it's loaded, then we cancel our operation
	if UCM then -- in favor of it. Just print a notice instead. Better than 
		        --  everything just breaking.
		-- We have UnlimitedChatMessage listed in the TOC file as an optional
		--  dependency. That's so this loads after it, so we can always catch
		--  this problem.
		print( L["Emote Splitter cannot run with UnlimitedChatMessage enabled."] )
		-- Now, we /could/ just hack up UCM in here and disable it ourselves,
		--  but I think this is a bit more of a nice approach...
		return
	end
	
	-- Some miscellaneous things here.
	-- See options.lua. This is initializing our configuration database, so 
	Me.Options_Init() -- it's needed before we can access Me.db.etc.
	
	-- Adding slash commands to the game is fairly straightforward. First you
	--  add a function to the SlashCmdList table, and then you assign the 
	--  command to the global SLASH_XYZ1. You can add more aliases with 
	SLASH_EMOTESPLITTER1 = "/emotesplitter" -- SLASH_XYZ2 or SLASH_XYZ3 etc.
	
	-- Unlock the chat editboxes when they show.
	hooksecurefunc( "ChatEdit_OnShow", Me.ChatEdit_OnShow ) 
	
	-- We're unlocking the chat editboxes here. This may be redundant, because
	--  we also do it in the hook when the editbox shows, but it's for extra
	--  good measure - make sure that we are getting these unlocked. Some
	--  strange addon might even copy these values before the frame is even
	for i = 1, NUM_CHAT_WINDOWS do                       -- shown... right?
		local editbox = _G["ChatFrame" .. i .. "EditBox"]
		editbox:SetMaxLetters( 0 )
		editbox:SetMaxBytes( 0 )
		-- A Blizzard dev added this function just for us. Without this, it
		--  would be absolute hell to get this addon to work with the default
		--  chat boxes, if not impossible. I'd have to create a whole new
		--  chatting interface.
		if editbox.SetVisibleTextByteLimit then  -- 7.x compat
			editbox:SetVisibleTextByteLimit( 0 )
		end
	end
	
	-- Our community chat hack entry.
	Me.UnlockCommunitiesChat()
	
	-- A nice little sending indicator that appears at the bottom left corner.
	--  This indicator shows when the system is busy sending, or waiting a bit
	--  after getting throttled. Just a general indicator to let you know that
	--  "things are working". If it gets stuck there, then something's wrong.
	local f = CreateFrame( "Frame", "EmoteSplitterSending", UIParent );
	f:SetPoint( "BOTTOMLEFT", 3, 3 ) -- Bottom-left corner, 3 pixels from the
	                                --   edge.
	f:SetSize( 200, 20 )          -- 200x20 pixels dimensions. Doesn't really 
	                              --  matter as the text just sits on top.
	f:EnableMouse( false )        -- Click-through.
	
	-- This is set up in indicator.xml.
	Me.sending_text = EmoteSplitterSending
	
	-- Initialize other modules here.
	Me.EmoteProtection.Init()
end

-------------------------------------------------------------------------------
-- This is our hook for when a chat editbox is opened. Or in other words, when
function Me.ChatEdit_OnShow( editbox ) -- someone is about to type!
	editbox:SetMaxLetters( 0 ); -- We're just removing the limit again here.
	editbox:SetMaxBytes( 0 );   -- Extra prudency, in case some rogue addon, or
	                            --  even the Blizzard UI, messes with it.
	if editbox.SetVisibleTextByteLimit then  -- 7.x compat
		editbox:SetVisibleTextByteLimit( 0 ) --
	end										 --
end 

-------------------------------------------------------------------------------
-- These few functions control the sending indicator, the indicator that pops
--  up on at bottom left corner of the screen to tell you the status of the
--  queue system. First up, this one shows the indicator for a state of
--                                    -- "SENDING".
function Me.SendingText_ShowSending()
	if not Me.db.global.showsending then return end
	local t = Me.sending_text
	t.text:SetTextColor( 1,1,1,1 ) -- There's just nothing like
	t.text:SetText( "Sending... " ) -- hard white text.
	t:Show()
end

-------------------------------------------------------------------------------
-- And this one sets it to a failed state (FAILED/WAITING). This shows up when
--                                   -- we're throttled by the server, and
function Me.SendingText_ShowFailed() --  we're waiting a few seconds before
	if not Me.db.global.showsending then return end -- retrying sending.
	local t = Me.sending_text
	-- We've got a spicy color here for you kids. 
	--        This is called "fire engine" from audrey613 on colourlovers.com!
	t.text:SetTextColor( 239/255,19/255,19/255,1 ) -- #EF1313 or 239,19,19
	t.text:SetText( "Waiting..." )
	t:Show()
end

-------------------------------------------------------------------------------
-- Hide the sending indicator. Called after the system goes back to an idle 
--                             -- state.
function Me.SendingText_Hide()
	Me.sending_text:Hide()
end

-------------------------------------------------------------------------------
-- This is our main entry into our chat queue. Basically we have the same
--  parameters as the SendChatMessage API. For BNet whispers, set `type` to 
--  "BNET" and `channel` to the presenceID.
-- Normal parameters:
--  msg     = Message text
--  type    = Message type, e.g "SAY", "EMOTE", "BNET", "CLUB", etc.
--  arg3    = Language index or club ID.
--  target  = Whisper target, presence ID, channel name, or stream ID.
--
function Me.QueueChat( msg, type, arg3, target )
	type = type:upper()
	
	local my_prio = 1 -- todo
	local my_tag = "chat"
		
	local msg_pack = {
		msg    = msg;
		type   = type;
		arg3   = arg3;
		target = target;
		id     = Me.message_id;
		prio   = Me.traffic_priority;
	}
	Me.message_id = Me.message_id + 1
	
	local queue_index = QUEUED_TYPES[type]
	
	-- Now we've got two paths here. One leads to the chat queue, the other
	--  will directly send the messages that don't need to be queued.
	--  SAY, EMOTE, and YELL are affected by the server throttler. BNET isn't,
	--  but we treat it the same way to correct the out-of-order bug.
	if queue_index then
		-- A certain problem with this queue is that sometimes we'll be stuck
		--  waiting for a response from the server, but nothing is coming
		--  because we weren't actually able to send the chat message. There's
		--  no easy way to tell if a chat message is valid, or if the player 
		--  was talking to a valid recipient etc. In the future we might handle
		--  the "player not found" message or what have you for battle.net
		--  messages. Otherwise, we need to do our best to make sure that this
		--  is a valid message, ourselves.
		-- First of all, we can't send an empty message.
		if msg == "" then return end
		-- Secondly, we can't send swastikas. The server just rejects these
		--  silently, and your chat gets discarded.
		if msg:find( "卍" ) or msg:find( "卐" ) then return end
		if UnitIsDeadOrGhost( "player" ) and (type == "SAY" 
		--[[ Thirdly, we can't send  ]]    or type == "EMOTE" 
		--[[ public chat while dead. ]]    or type == "YELL") then 
			-- We still want them to see the error, which they won't normally
			--  see if we don't do it manually, since we're blocking
			--                                    SendChatMessage.
			UIErrorsFrame:AddMessage( ERR_CHAT_WHILE_DEAD, 1.0, 0.1, 0.1, 1.0 )
			return
		end
		
		ChatQueueInsert( msg_pack )
		
		if Me.queue_paused then
			Me.queue_paused = false
			return
		end
		Me.StartQueue()
		
	else -- For other message types like party, raid, whispers, channels, we
		 -- aren't going to be affected by the server throttler, so we go
		Me.CommitChat( msg_pack )  -- straight to putting these
	end                            --  messages out on the line.
end   

function Me.AnyChannelsBusy()
	for i = 1,MY_NUM_CHANNELS do
		if Me.channels_busy[i] then return true end
	end
end

function Me.AllChannelsBusy()
	for i = 1,MY_NUM_CHANNELS do
		if not Me.channels_busy[i] then return false end
	end
	return true
end

-------------------------------------------------------------------------------
-- These are callbacks from the throttler (throttler.lua). They're only called
--  when we're sending a lot of chat, and the throttler has delayed for a bit.
--
function Me.OnThrottlerStart()
	Me.SendingText_ShowSending()
end

-- And this is after all messages are sent.
function Me.OnThrottlerStop()
	if not Me.AnyChannelsBusy() then
		Me.SendingText_Hide()
	end
end

-------------------------------------------------------------------------------
-- Execute the chat queue.
--
function Me.StartQueue()
	-- It's safe to call this function whenever for whatever. If the queue is
	--  already started, or if the queue is empty, it does nothing.
	
	-- I always like APIs that have simple checks like that in place. Sure it
	--  might be a /little/ bit less efficient at times, but the resulting code
	--  on the outside as a result is usually much cleaner. Boilerplate belongs
	--  in the library, right? First thing we do when the system starts is
	--  send the first message in the chat queue. Like this.
	Me.ChatQueueNext()
end

-------------------------------------------------------------------------------
-- Send the next message in the chat queue.
--
function Me.ChatQueueNext()
	
	-- This is like the "continue" function for our chat queue system.
	-- First we're checking if we're done. If we are, then the queue goes
	if #Me.chat_queue == 0 then -- back to idle mode.
		if not Me.AnyChannelsBusy() then
			Me.SendingText_Hide()
			Me.failures = 0
		end
		return
	end
	
	-- Otherwise, we're gonna send another message. 
	Me.SendingText_ShowSending()
	
	local i = 1
	while i <= #Me.chat_queue do
		local q = Me.chat_queue[i]
		if q.type == "BREAK" then
			if Me.AnyChannelsBusy() then
				break
			else
				if Me.ThrottlerHealth() < 25 then
					Me.Timer_Start( "throttle_break", "ignore", 0.1, 
					                                         Me.ChatQueueNext )
					return
				end
				table.remove( Me.chat_queue, i )
			end
		else
			local channel = QUEUED_TYPES[q.type]
			if not Me.channels_busy[channel] then
				Me.Timer_Start( "channel_"..channel, "push", CHAT_TIMEOUT, 
				                                        Me.ChatDeath, channel )
				Me.CommitChat( q )
				Me.channels_busy[channel] = q
				if Me.AllChannelsBusy() then
					break
				end
			end
			i = i + 1
		end
	end
	
	if not Me.AnyChannelsBusy() then
		--@debug@
		if #Me.chat_queue ~= 0 then
			error( "Chat queue not empty when returning from ChatQueueNext" )
		end
		--@end-debug@
		Me.SendingText_Hide()
		Me.failures = 0
	end
	
	-- We fetch the first entry in the chat queue and then "commit" it. Once
	--  it's sent like that, we're waiting for an event from the server to 
	--  continue. This can continue in three ways.
	-- (1) We see that our message has been sent, by seeing it mirrored back
	--  from the server, and then we delete this message and send the next
	--  one in the queue.
	-- (2) The server throttles us, and we get an error. We intercept that
	--  error, wait a little bit, and then retry sending this message. This
	--  step can repeat indefinitely, but usually only happens once or twice.
	-- (3) The chat timer times out before we get any sort of response.
	--  This happens under heavy latency or when something prevents our
	--  message from being sent (and we don't know it). We want to do a hard
	--  reset in that case so we don't get stuck in a failed state.
end

-------------------------------------------------------------------------------
-- Timer callback for when chat times out.
--                        -- This is a fatal error due to timeout. At this
--                        --  point, we've waited extremely long for a message.
function Me.ChatDeath()   -- Something went wrong or the user is suffering from
	Me.chat_queue = {}    --  intense latency. We just want to reset 
	--Me.chat_busy = false  --  completely to recover.
	for i = 1, MY_NUM_CHANNELS do
		Me.channels_busy[i] = nil
	end
	Me.SendingText_Hide()
	
	-- I feel like we should wrap these types of print calls in something to
	--  standardize the formatting and such.
	print( "|cffff0000<" .. L["Chat failed!"] .. ">|r" )
end

-------------------------------------------------------------------------------
-- These two functions are called from our event handlers. 
-- This one is called when we confirm a message was sent. The other is called
--                            when we see we've gotten a "throttled" error.
function Me.ChatConfirmed( channel )
	
	Me.StopLatencyRecording()
	Me.failures = 0
	Me.channels_busy[channel] = nil
	
	-- Cancelling either the main 10-second timeout, or the throttled warning
	--  timeout (see below).
	Me.Timer_Cancel( "channel_"..channel )
	
	Me.ChatQueueNext()
end

-------------------------------------------------------------------------------
-- Upon failure, we wait a little while, and then retry sending the same
function Me.ChatFailed( channel )                         --  message.
	-- A bit of a random formula here... When ChatFailed is called, we don't
	--  actually know if the chat failed or not quite yet. You can get the
	--  throttle error as a pure warning, and the chat message will still go
	--  through. There can be a large gap between the chat event and that
	--  though, so we need to wait to see if we get the chat message still.
	-- The amount of time we wait is at least CHAT_THROTTLE_WAIT (3) seconds, 
	--  or more if they have high latency, a maximum of ten seconds. This might 
	--  be a bother to  people who get a lag spike though, so maybe we should 
	--  limit this to be less? They DID get the chat throttled message after
	--  all.
	
	-- We don't want to get stuck waiting forever if this error /isn't/ caused
	--  by some sort of throttle, so we count the errors and die after waiting
	--  for so many.
	Me.failures = Me.failures + 1
	if Me.failures >= FAILURE_LIMIT then
		Me.ChatDeath()
		return
	end
	
	Me.channels_busy[channel] = nil
	
	-- With the 8.0 update, Emote Splitter also supports communities, which
	--  give a more clear signal that the chat failed that's purely from
	--  the throttler, so we don't account for latency.
	local wait_time
	if channel == CHANNEL_CLUB then -- CLUB channels
		wait_time = CHAT_THROTTLE_WAIT
	else
		wait_time = math.min( 10, math.max( 1.5 + Me.GetLatency(),
		                                                  CHAT_THROTTLE_WAIT ))
	end
	
	Me.Timer_Start( "channel_"..channel, "push", wait_time,
	                                              Me.ChatFailedRetry, channel )
	Me.SendingText_ShowFailed()  -- We also update our little indicator to show
end                              --  this.

-------------------------------------------------------------------------------
-- For restarting the chat queue after a failure.
--
function Me.ChatFailedRetry()
	-- We have an option to hide any sort of failure messages during
	--  semi-normal operation. If that's disabled, then we tell the user when
	--  we're resending their message. Otherwise, it's a seamless operation.
	if not Me.db.global.hidefailed then -- All errors are hidden and everything
		                                -- happens in the background.
		print( "|cffff00ff<" .. L["Resending..."] .. ">" )
	end
	
	Me.ChatQueueNext()
end

local function RemoveFromTable( target, value )
	for k, v in ipairs( target ) do
		if v == value then
			table.remove( target, k )
			return
		end
	end
end

-------------------------------------------------------------------------------
-- This is called by our chat events, to try and confirm messages that have
-- been commit from our queue.
--
-- kind: Type of chat message the event handles. e.g. SAY, EMOTE, etc.
-- guid: GUID of the player that sent the message.
--
function Me.TryConfirm( kind, guid )
	local channel = QUEUED_TYPES[kind]
	if not channel then return end
	
	-- It'd be better if we could verify the message contents, to make sure
	--  that we caught the right event, but lots of things can change the 
	--  resulting message, especially on the server side (for example, if
	--  you're drunk, or if you send %t which gets replaced by your target).
	-- So... we just do it blind, instead. If we send two SAY messages and
	--  and EMOTE in order, then we wait for two SAY events and one EMOTE
	if Me.channels_busy[channel] and kind == Me.channels_busy[channel].type 
						                           and guid == Me.PLAYER_GUID then
		-- Confirmed this channel.
		RemoveFromTable( Me.chat_queue, Me.channels_busy[channel] )
		Me.ChatConfirmed( channel )
	end
end

-------------------------------------------------------------------------------
-- We measure the time from when a message is sent, to the time we receive
--                                   -- a server event that corresponds to
function Me.StartLatencyRecording()  --  that message.
	Me.latency_recording = GetTime()
end

-------------------------------------------------------------------------------
-- When we have that value, the length between the event and the start, then
--  we don't quite set our latency value directly unless it's higher. If it's
--  higher, then there's likely some sort of latency spike, and we can
--  probably expect another one soonish. If it's lower, then we ease the
function Me.StopLatencyRecording()           -- latency value towards it
	if not Me.latency_recording then return end      -- (only use 25%).
	
	local time = GetTime() - Me.latency_recording
	
	-- Of course we do assume that something is quite wrong if we have a
	--  value greater than 10 seconds. Things like this have their pros and
	--  cons though. This might open up room for logical errors, where,
	--  normally, the code would break, because somewhere along the line we
	--  had a huge value of minutes or hours. Clamping it like this eliminates
	--  the visibility of such a bug. The pro of this, though? The user at
	--  least won't experience that problem. I think our logic is pretty solid
	time = math.min( time, 10 )                                    -- though.
	if time > Me.latency then
		Me.latency = time
	else
		-- I use this interpolation pattern a lot. A * x + B * (1-x). If you
		--  want to be super efficient, you can also do A + (B-A) * x. Things
		--  like that are more important when you're dealing with archaic
		--  system where multiplies are quite a bit more expensive than
		Me.latency = Me.latency * 0.80 + time * 0.20       -- addition.
		
		-- It's a bit sad how everything you program for these days has tons
		--  of power.
	end
	
	-- This value is either a time (game time), or nil. If it's nil, then the
	--  recording isn't active.
	Me.latency_recording = nil
end

-------------------------------------------------------------------------------
-- Read the last latency value, with some checks.
--
function Me.GetLatency()
	local _, _, latency_home = GetNetStats()
	
	-- The game's latency recording is still decent enough for a floor value.
	-- And our ceiling is 10 seconds. Anything higher than that, and you're
	--  probably going to be seeing a lot of other timeout problems...
	local latency = math.max( Me.latency, latency_home/1000 ) 
	latency = math.min( latency, 10.0 )     --        ^^^^^
	                                          --  milliseconds
	return latency
end

-------------------------------------------------------------------------------
-- Our handle for the CHAT_MSG_SYSTEM event.
--
function Me.OnChatMsgSystem( event, message, sender, _, _, target )
	-- We're just looking out in here for throttle errors.
	--if #Me.chat_queue == 0 then -- If the queue isn't started, then we aren't
		                        -- expecting anything.
	if not Me.channels_busy[CHANNEL_SAY] then
		return
	end
	
	-- We check message against this localized string, so if people are on a
	--  different locale, it should still work fine. As far as I know there
	--  isn't going to be anything that may slightly modify the message to make
	--  this not work.
	if message == ERR_CHAT_THROTTLED and sender == "" then
		-- Something to think about and probably be wary of is this system
		--  error popping up randomly and throwing off our latency measurement.
		-- We still have a minimal safety net at least to avoid any problems
		--  of this being too low. Also, as far as I'm aware, we're personally
		--  handling anything that can cause this error, so it's in our field.
		-- Still, something of a concern, that.
		Me.StopLatencyRecording()
		
		-- So we got a throttle error here, and we want to retry.
		-- Actually, this doesn't necessarily mean that we need to retry. It's
		--  a bit of a shitty situation that Blizzard has for us.
		-- ERR_CHAT_THROTTLED is used as both a warning as an error. If your
		--  chat message is discarded, you will always get this system error,
		--  once per message lost. BUT you can also get this error as a
		--  warning. If you send a lot of chat, you may get it, but all of your
		--  messages will go through anyway.
		-- We don't know if this is a warning or a failed message, so to be
		--  safe (as much as we can be), we wait for a few seconds before
		--  assuming that the message was indeed lost. It'd be nice if they
		--  actually gave us a different error if the message was actually
		--  lost.
		-- If you have crazy bad latency, Emote Splitter might accidentally
		--  send two of one of your messages, because there was a big enough
		--  gap between a "warning" version of this, and then your actual
		--  chat message. In other words, this error can show up seconds before
		--  your chat message shows up.
		-- If we do see the chat confirmed during our waiting period, we cancel
		Me.ChatFailed( CHANNEL_SAY ) -- it and then continue as normal.
	end
end

-------------------------------------------------------------------------------
-- Our hook for when the client gets an error back from one of the community
-- features.
function Me.OnClubError( event, action, error, club_type )
	if #Me.chat_queue == 0 then
		-- We aren't expecting anything.
		return 
	end
	
	-- This will match the error that happens when you get throttled by the
	--  server from sending chat messages too quickly. This error is vague
	--  though and still matches some other things, like when the stream is
	--  missing. Hopefully in the future the vagueness disappears so we know
	--  what sort of error we're dealing with, but for now, we assume it is
	--  a throttle, and then retry a number of times. We have a failure
	--  counter that will stop us if we try too many times (where we assume
	--  it's something else causing the error).
	if action == Enum.ClubActionType.ErrorClubActionCreateMessage 
	   and error == Enum.ClubErrorType.ErrorCommunitiesUnknown then
		Me.ChatFailed( CHANNEL_CLUB )
	end
end

-------------------------------------------------------------------------------
function Me.OnChatMsgBnOffline( event, ... )
	local c = Me.channels_busy[CHANNEL_BNET]
	if not c then
		-- We aren't expecting anything.
		return
	end
	
	local senderID = select( 13, ... )
	
	if c.type == "BNET" and c.target == senderID then
		-- Can't send messages to this person. We might have additional
		--  messages in the queue though, so we don't quite kill ourselves yet.
		-- We just filter out any messages that are to this person.
		local i = 1
		while Me.chat_queue[i] do
			local c = Me.chat_queue[i]
			if c.type == "BNET" and c.target == senderID then
				table.remove( Me.chat_queue, i )
			else
				i = i + 1
			end
		end
		
		Me.ChatConfirmed( CHANNEL_BNET )
	end
	
	-- Something to note about this, because it's potentially dangerous. It
	--  just so happens to work out all right, currently, but that might change
	--  in the future.
	-- If you send a message to someone offline, then the offline
	--  event usually (?) happens immediately. I'm not sure if it's actually
	--  guaranteed to happen, but what happens is that this event triggers
	--  INSIDE the chat queue, so calling ChatConfirmed /before/ we're
	--  actually outside of our sending hook/system/everything. Just keep that
	--  in mind and change things accordingly if it causes trouble.
end

-------------------------------------------------------------------------------
-- Our hook for CHAT_MSG_GUILD and CHAT_MSG_OFFICER.
--
function Me.OnChatMsgGuildOfficer( event, _,_,_,_,_,_,_,_,_,_,_, guid )

	-- These are a fun couple of events, and very messy to deal with. Maybe the
	--  API might get some improvements in the future, but as of right now
	--  these show up without any sort of data what club channel they're coming
	--  from. We just sort of gloss over everything.
	
	local cq = Me.channels_busy[CHANNEL_CLUB]
	if cq and guid == Me.PLAYER_GUID then
		-- confirmed this channel
		event = event:sub( 10 )
		
		-- Typically cq.type will always be CLUB for these, but we handle this
		--  anyway.
		if (cq.type == event) 
		   or (cq.type == "CLUB" and cq.arg3 == GetGuildClub()) then
			RemoveFromTable( Me.chat_queue, cq )
			Me.ChatConfirmed( CHANNEL_CLUB )
		end
	end
end

-------------------------------------------------------------------------------
-- Hook for when we received a message on a community channel.
--
function Me.OnChatMsgCommunitiesChannel( event, _,_,_,_,_,_,_,_,_,_,_, 
                                         guid, bn_sender_id )
	local cq = Me.channels_busy[CHANNEL_CLUB]
	if not cq then return end
	
	-- This event seems to show up in a few formats. Thankfully, it always
	--  shows up when you receive a club message, regardless of whether or not
	--  you have subscribed to that channel in your chatboxes. One gotcha with
	--  this message is that it's split between Battle.net and regular chat 
	--  messages. For BNet ones the guid is nil, and the argument after is the
	--  BNet account ID instead.
	-- We have a few extra checks down there for prudency, in case something
	--  changes in the future.
	if (guid and guid == Me.PLAYER_GUID)
	   or (bn_sender_id and bn_sender_id ~= 0 and BNIsSelf(bn_sender_id)) then
		RemoveFromTable( Me.chat_queue, cq )
		Me.ChatConfirmed( CHANNEL_CLUB )
	end
end

-------------------------------------------------------------------------------
-- Unlock the community chatbox.
--
function Me.UnlockCommunitiesChat()
	if not C_Club then return end -- 7.x compat
	
	if not CommunitiesFrame then
		-- The Blizzard Communities addon isn't loaded yet. We'll wait until
		--  it is.
		Me:RegisterEvent( "ADDON_LOADED", function( event, addon )
			if addon == "Blizzard_Communities" then
				Me:UnregisterEvent( "ADDON_LOADED" )
				Me.UnlockCommunitiesChat()
				-- Anonymous functions like this are pretty handy, huh?
			end
		end)
		return
	end
	CommunitiesFrame.ChatEditBox:SetMaxBytes( 0 )
	CommunitiesFrame.ChatEditBox:SetMaxLetters( 0 )
	if CommunitiesFrame.ChatEditBox.SetVisibleTextByteLimit then
		-- remove this check when we're sure this is going to exist.
		CommunitiesFrame.ChatEditBox:SetVisibleTextByteLimit( 0 )
	end
end


-- See you on Moon Guard! :)
--                ~              ~   The Great Sea ~                  ~
--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^-