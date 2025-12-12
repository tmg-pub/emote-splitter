   -------------------------------------------------------------------------------
-- Gopher
-- by Tammya-MoonGuard (Copyright 2018)
--
-- All Rights Reserved.
--
-- See api.lua for the public API.
--
-- Here are the key features that this library provides:
--   * Allows SendChatMessage  and  other  similar methods  to  accept messages
--      larger than  255  characters,  and automatically  split  them up.  Also
--      splits up messages with "\n" or  literal newlines in them to be sent as
--      their own message.
--   * Robust message queue system  which  re-sends failed messages.  Sometimes
--      the server might give you  an  error  if  you send messages immediately
--      after the last.  Gopher works around that by saving  your  messages and
--      verifying the response from the server.
--   * Support  for  all  chat types.  Alongside  public  messages,  Gopher  is
--      compatible  with  the  other  chat  channels.  Gopher also ensures that
--      messages will  be  received in order that they're sent,  and corrects a
--      quirk with Battle.net whispers. Weak support for global channels.
--   * Seamless feel. Gopher should feel like there's nothing going on.
--     It hides  any error messages from  the  client,  and  provides  its  own
--      throttle library to ensure that outgoing chat is your #1 priority.
-----------------------------------------------------------------------------^-

local VERSION = 14

if IsLoggedIn() then
   error( "Gopher can't be loaded on demand!" )
end

local Me

if LibGopher then
   Me = LibGopher.Internal
   if Me.VERSION >= VERSION then
      Me.load = false
      -- Already loaded.
      return
   end
   
   ---------------------------------------------------------------------------
   -- Cleanup here. Double check everything!
   ---------------------------------------------------------------------------
   --if Gopher.VERSION == 1 then
   --
   --end

   ---------------------------------------------------------------------------
else
   LibGopher = {
      Internal = {}
   }
   
   Me = LibGopher.Internal
end

Me.VERSION = VERSION
Me.load    = true

-------------------------------------------------------------------------------
-- Here's our chat-queue system. 
--
-- Firstly we have the actual queue. This table contains the user's queued
--  chat messages they want to send.
--
-- Each entry has these fields. Most of these are the arguments you may pass
--  to SendChatMessage.
--    msg: The message text.
--    type: "SAY" or "EMOTE" etc.
--    arg3: Language index or club ID.
--    target: Channel, whisper target, BNet presence ID, or club stream ID.
--    prio: Message priority (lower numbers are sent before higher numbers).
--    id: Unique message ID. In the future this will help coordinate between
--         queues.
-- We have multiple channels to send messages of different types, since they
--  use different verification methods. For example, you can send a club 
--  message and a say message at the same time. This may be undesirable due
--  to unpredictable message ordering, but you can prevent that by inserting
--  a BREAK in the queue. (See QueueBreak)
--  
-- Queue 1: SAY, EMOTE, YELL, BNET
-- Confirmation: CHAT_MSG_SAY, CHAT_MSG_EMOTE, CHAT_MSG_YELL, 
--                CHAT_MSG_BN_WHISPER_INFORM
-- Failure: CHAT_MSG_SYSTEM
-- Fatal: CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE
--
-- Queue 2: GUILD, OFFICER, CLUB
-- Confirmation: CHAT_MSG_GUILD, CHAT_MSG_OFFICER, 
--                CHAT_MSG_COMMUNITIES_CHANNEL
-- Failure: CLUB_ERROR
-- Queue 3: DELETE/EDIT
-- Confirmation: CLUB_MSG_UPDATED
-- Failure: CLUB_ERROR
--
-- This is so that if you do SendChatMessage and then C_Club.SendMessage
--  at the same time, we can send both of these messages together. It's
--  mostly a feature meant to help Cross RP send its messages in unison.
--  Minimal improvement for normal cases.
Me.chat_queue    = {}
Me.channels_busy = {}
Me.message_id    = 1
Me.NUM_CHANNELS  = 3
-------------------------------------------------------------------------------
-- The way we dequeue is a little complex. It's not a plain FIFO anymore.
-- Firstly we sort by priority, lower numbers are sent before higher numbers.
-- Then, we try to keep our channels busy, and different channel types can
--  be sent in tandem. If you want to pair messages together, use a queue
--  break to halt the system until everything is free.
--
-- The guarantees provided are:
--   Chat messages of higher priorities are sent before lower priority.
--   Each channel's messages will always be sent and arrive in-order.
--   Using queue BREAKS, you can also guarantee message ordering cross-channel
--    or send messages together.
--
Me.traffic_priority = 1
-------------------------------------------------------------------------------
-- We have a system so third parties can process chat or listen for 
--  other Gopher events. It's much cleaner or safer to do chat processing with
--  these rather than them hooking SendChatMessage directly, since it will be
--  undefined if their hook fires before or after the message is cut up by our
Me.event_hooks = {    -- functions.

   -- CHAT_NEW is when the chat system processes a new message. This is
   --  when the message is fresh from SendChatMessage and no operations have
   --  been done with it yet. This event is skipped when Gopher is
   --  "suppressed".
   CHAT_NEW       = {};
   
   -- CHAT_QUEUE is when the chat system is about to queue a message which has
   --  gone through the cutter and other processes. CHAT_POSTQUEUE is after 
   --  the message is queued, and meant for post-hooks that trigger after the
   --  queue call.
   CHAT_QUEUE     = {};
   CHAT_POSTQUEUE = {};
   
   -- SEND_START is when the chat system becomes active and its trying to send
   --  messages and empty the queue.
   SEND_START     = {};
   
   -- SEND_FAIL is when the chat system detects a throttle failure or such,
   --  and will be working to recover or re-send. RECOVER is triggered when
   --  it retries.
   SEND_FAIL      = {};
   SEND_RECOVER   = {};
   
   -- SEND_DEATH is when the chat system timed out and a hard reset is done 
   --  to recover.
   SEND_DEATH     = {};
   
   -- SEND_CONFIRMED is when the chat system has successfully sent and
   --  confirmed a message. The callback arguments will contain the message 
   --  sent.
   SEND_CONFIRMED = {};
   
   -- SEND_DONE is when the chat system has emptied its queue and goes back
   --  to being idle.
   SEND_DONE      = {};
   
   -- Called when messages are being sent and there need to be delays to not
   --  overrun bandwidth.
   THROTTLER_START = {};
   THROTTLER_STOP  = {};
}

Me.hook_stack = {} -- Our stack for hooks in case we're nesting things with
                   --  AddChatFromStartEvent.
-------------------------------------------------------------------------------
-- We count failures when we get a chat error. Some of the errors we get
--  (particularly from the communities API) are vague, and we don't really
--  know if we should keep re-sending. This limit is to stop resending after
Me.channel_failures = {}                       --  so many of those errors.
Me.FAILURE_LIMIT = 5                           --
-------------------------------------------------------------------------------
-- Settings for the timers in the chat queue. CHAT_TIMEOUT is how much time it
--  will wait before assuming that something went wrong. In an ideal setup,
--  this is typically unnecessary, because chat messages are guaranteed to make
--  the server give you a response, be it the chat event or an error. If you
--  don't get a response, then you disconnect. However, if something goes wrong
--  on our end, we could typically be waiting forever for nothing, which is
--  what this is for. In other words, it's not a timeout for latency, it's a
--  timeout before assuming we screwed up.
-- CHAT_THROTTLE_WAIT is for when we intercept an error. We wait this many
--  seconds before resuming. We also have some latency detection code to
--  add on top, but this is the minimum value. The latency value isn't used or
--  necessary when we know that our message didn't send, like when sending
Me.CHAT_TIMEOUT       = 10.0                          -- community messages.
Me.CHAT_THROTTLE_WAIT = 3.0
-------------------------------------------------------------------------------
-- How big to split chunks. The chunk size will be 
--  `override[type] or default[type] or override.OTHER or default.OTHER`.
Me.default_chunk_sizes = {
   OTHER   = 255;
}

-------------------------------------------------------------------------------
-- Any chat type keys found in here will override the chunk size for a certain 
--  chat type. This is especially used by Cross RP for custom fake chat types 
--  that split on the 400 mark.
Me.chunk_size_overrides = {}

-- This overrides the next chat message's chunk size no questions asked.
Me.next_chunk_size = nil

-------------------------------------------------------------------------------
-- We do some latency tracking ourselves, since the one provided by the game
--  isn't very accurate at all when it comes to recent events. The one in the
--  game is only updated every 30 seconds. We need an accurate latency value
--  immediately to detect lag spikes and then delay our handlers accordingly.
-- We measure latency by setting `recording` to the time we send a chat
Me.latency           = 0.1  -- message, and then get the time difference 
Me.latency_recording = nil  --         when we receive a server event.
                            -- Our value is in seconds.
-- You might have some questions, why I'm setting some table values to nil 
--  (which effectively does nothing), but it's just to keep things well 
--  defined up here.
-------------------------------------------------------------------------------
-- Hide system messages when chat is throttled.
Me.hide_failure_messages = true
-------------------------------------------------------------------------------
-- A lot of these definitions used to be straight local variables, but this is
--  a little bit cleaner, keeping things inside of this table, as well
--  as exposing it to the outside so we can do some easier diagnostics in case
--  something goes wrong down the line. Another great plus to exposing
--  everything like this is that other addons can see what we're doing. Sure,
--  the proper way is to make an API for something, but when it comes to the
--  modding scene, things can get pretty hacky, and it helps a bit to allow
--  others to mess with your code from the outside if they need to.
-------------------------------------------------------------------------------
-- The splitmarks are the marks that are added to the start or end of mesages
--  to signal that they are being continued. If everything used the same one
--                            one could even easily piece together messages.
Me.splitmark_start = "»"
Me.splitmark_end   = "»"
-------------------------------------------------------------------------------
local QUEUED_TYPES = { -- These are the types that aren't passed directly to
   SAY     = 1; --  the throttler for output. They're queued and sent
   EMOTE   = 1; --  one at a time, so that we can verify if they went
   YELL    = 1; --  through or not.
   BNET    = 1;     
   GUILD   = 2; -- We handle GUILD and OFFICER like this too since
   OFFICER = 2; --  they're also treated like club channels in 8.0.
   CLUB    = 2; -- Essentially, anything that can fail from throttle
                          --  or other issues should be put in here.
   CLUBEDIT   = 3; -- V3 adds these, which are basically delete and edit
   CLUBDELETE = 3; --  tasks.
}                      
-- In 1.4.2 we also have a few different queue types to send traffic with
--  different handlers at the same time.

-- [[7.x compat]] We don't handle GUILD/OFFICER like this.
if not C_Club then
   QUEUED_TYPES.GUILD   = nil;
   QUEUED_TYPES.OFFICER = nil;
end
-------------------------------------------------------------------------------
-- Metadata is addon data that's coupled with text messages. For example, you
--  can add metadata to a raid message, and it appears as an addon message
--  right before it. The game guarantees that this data will always be seen
--                                                  before the chat message.
Me.metadata = {
   -- Each entry is a table that contains:
   -- 
}

-------------------------------------------------------------------------------
Me.frame = Me.frame or CreateFrame( "Frame" )
Me.frame:UnregisterAllEvents()
Me.frame:RegisterEvent( "PLAYER_LOGIN" )

-------------------------------------------------------------------------------
-- Setting this early so that we can localize it during PLAYER_LOGIN.
Me.continue_frame_label = "Press enter to continue."

-------------------------------------------------------------------------------
-- Called after player login (or reload). Time to set things up.
function Me.OnLogin()
   -- Delay this a little so we give time for their own OnLogin to trigger.
   C_Timer.After( 0.01, Me.AddCompatibilityLayers )
   Me.PLAYER_GUID = UnitGUID("player")

   Me.SetupContinueFrame()
   
   -- Message hooking. These first ones are the public message types that we
   --  want to hook for confirmation. They're the ones that can error out if
   --                           they're hit randomly by the server throttle.
   Me.frame:RegisterEvent( "CHAT_MSG_SAY"   )
   Me.frame:RegisterEvent( "CHAT_MSG_EMOTE" )
   Me.frame:RegisterEvent( "CHAT_MSG_YELL"  )
   
   if C_Club then -- 7.x compat
      -- In 8.0, GUILD and OFFICER chat are no longer normie communication
      --  channels. They're just routed into the community API internally.
      -- Sometimes the game uses the old guild channels though, as the 
      --  Battle.net platform can go down sometimes, and it falls back to
      --  the game's channels.
      Me.frame:RegisterEvent( "CLUB_MESSAGE_ADDED"   )
      Me.frame:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL" )
      Me.frame:RegisterEvent( "CHAT_MSG_GUILD"       )
      Me.frame:RegisterEvent( "CHAT_MSG_OFFICER"     )
      Me.frame:RegisterEvent( "CLUB_ERROR"           )
      Me.frame:RegisterEvent( "CLUB_MESSAGE_UPDATED" )
   end
   
   -- Battle.net whispers do have a throttle if you send too many, and they're
   --  also affected by the very stupid Battle.net misordering quirk. Send one
   --  at a time to be safe.
   Me.frame:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM" )
   
   -- I didn't even know they had a dedicated event for this.
   Me.frame:RegisterEvent( "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE" )
   
   -- And finally we hook the system chat events, so we can catch when the
   --                         system tells us that a message failed to send.
   Me.frame:RegisterEvent( "CHAT_MSG_SYSTEM" )
   
   -- v12: Catch addon blocked event; this may happen unexpectedly when some
   --  addon is trying to send chat. That means we need to break out of the
   --           throttler loop and way for a hardware event trigger to resume.
   Me.frame:RegisterEvent( "ADDON_ACTION_BLOCKED" )
   
   -- Here's where we add the feature to hide the failure messages in the
   -- chat frames, the failure messages that the system sends when your chat gets throttled
   local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
   AddFilter("CHAT_MSG_SYSTEM",
       function(_, _, msg, sender )
         -- `ERR_CHAT_THROTTLED` is the localized string.
         if Me.hide_failure_messages and msg == ERR_CHAT_THROTTLED then 
            -- Returning true from these callbacks block the message
            return true -- from showing up.
         end
      end)
   
   Me.DebugLog( "Initialized." )
end

-------------------------------------------------------------------------------
function Me.SetupContinueFrame()
   Me.continue_frame = Me.continue_frame
                       or CreateFrame( "Frame", nil, UIParent )
   Me.continue_frame:Hide()
                       
   Me.continue_frame:SetScript( "OnUpdate", function( self )
      if LAST_ACTIVE_CHAT_EDIT_BOX then
         self:SetAllPoints( LAST_ACTIVE_CHAT_EDIT_BOX )
      end
   end)
   
   Me.continue_frame.text = Me.continue_frame.text
                            or Me.continue_frame:CreateFontString()

   local text = Me.continue_frame.text
   text:SetFontObject( GameFontNormal )
   text:SetAllPoints()
      
   -- Make the continue overlay clickable as a fallback when Enter doesn't
   -- trigger ChatFrame_OpenChat on some clients or when other addons steal
   -- focus. Clicking will simulate the hardware keystroke to resume sending.
   Me.continue_frame:EnableMouse( true )
   Me.continue_frame:SetScript( "OnMouseDown", function()
      Me.HideContinueFrame()
      Me.PipeThrottlerKeystroke()
   end)
   Me.continue_frame:SetFrameStrata( "DIALOG" )

   -- Hook chat editboxes' OnEnterPressed so pressing Enter will resume the
   -- throttler when the continue prompt is shown. This is guarded so we only
   -- hook them once.
   if not Me._continue_enter_hooked then
      Me._continue_enter_hooked = true
      for i = 1, (NUM_CHAT_WINDOWS or 10) do
         local editbox = _G["ChatFrame" .. i .. "EditBox"]
         if editbox and editbox.HookScript then
            editbox:HookScript( "OnEnterPressed", function()
               if Me.prompt_continue and (Me.intercept_enter == nil or Me.intercept_enter) then
                  Me.DebugLog( "EditBox OnEnterPressed - forcing throttler resume." )
                  Me.HideContinueFrame()
                  Me.PipeThrottlerKeystroke()
               end
            end)
         end
      end
      -- Try hooking some common alternate editboxes (Communities)
      if CommunitiesFrame and CommunitiesFrame.ChatEditBox and CommunitiesFrame.ChatEditBox.HookScript then
         CommunitiesFrame.ChatEditBox:HookScript( "OnEnterPressed", function()
            if Me.prompt_continue and (Me.intercept_enter == nil or Me.intercept_enter) then
               Me.HideContinueFrame()
               Me.PipeThrottlerKeystroke()
            end
         end)
      end
   end
end

-------------------------------------------------------------------------------
function Me.ShowContinueFrame()
   Me.continue_frame:Show()
   Me.continue_frame.text:SetText( Me.continue_frame_label )
end

-------------------------------------------------------------------------------
function Me.HideContinueFrame()
   Me.continue_frame:Hide()
end

-------------------------------------------------------------------------------
function Me.OnGameEvent( frame, event, ... )
   if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_EMOTE"
                                              or event == "CHAT_MSG_YELL" then
      Me.TryConfirm( event:sub( 10 ), select( 12, ... ))
   elseif event == "CLUB_MESSAGE_ADDED" then
      -- Version 8: Using CLUB_MESSAGE_ADDED instead of old event (which
      --  doesn't trigger all the time anymore).
      Me.OnClubMessageAdded( event, ... )
   elseif event == "CLUB_MESSAGE_ADDED" then
      -- Version 9: Using this for channels in chatbox.
      Me.OnChatMsgCommunitiesChannel( event, ... )
   elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
      Me.OnChatMsgGuildOfficer( event, ... )
   elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
      Me.TryConfirm( "BNET", Me.PLAYER_GUID )
   elseif event == "CLUB_ERROR" then
      Me.OnClubError( event, ... )
   elseif event == "CLUB_MESSAGE_UPDATED" then
      Me.OnClubMessageUpdated( event, ... )
   elseif event == "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE" then
      Me.OnChatMsgBnOffline( event, ... )
   elseif event == "CHAT_MSG_SYSTEM" then
      Me.OnChatMsgSystem( event, ... )
   elseif event == "ADDON_ACTION_BLOCKED" then
      -- This is a simple flag set when we see this event. It should be cleared
      --  before testing a function and checked right after. This event is
      --  triggered immediately in the execution path of calling the blocked
      --  function.
      Me.addon_action_blocked = true
   elseif event == "PLAYER_LOGIN" then
      Me.OnLogin()
   end
end

Me.frame:SetScript( "OnEvent", Me.OnGameEvent )

-------------------------------------------------------------------------------
function Me.HideFailureMessages( hide )
   Me.hide_failure_messages = hide
end

-------------------------------------------------------------------------------
-- A simple function to iterate over a plain table, and return the key of any
local function FindTableValue( table, value ) -- first value that matches the
   for k, v in pairs( table ) do             -- argument. `key` also being an
      if v == value then return k end       -- index for array tables.
   end
   -- Otherwise, we don't return anything; or in other words, we return nil...
end

-------------------------------------------------------------------------------
-- Add an event listener. See api.lua for extensive documentation.
function Me.Listen( event, func )
   if not Me.event_hooks[event] then
      error( "Invalid event." )
   end
   
   if FindTableValue( Me.event_hooks[event], func ) then
      return false
   end
   
   table.insert( Me.event_hooks[event], func )
   return true
end

-------------------------------------------------------------------------------
-- You can also easily remove event hooks with this. Just pass in your args 
--  that you gave to Listen.
--
-- Returns `true` if the hook was removed, and `false` if it wasn't found.
--
function Me.StopListening( event, func )
   if not Me.event_hooks[event] then
      error( "Invalid event." )
   end
   
   local index = FindTableValue( Me.event_hooks[event], func )
   if index then
      table.remove( Me.event_hooks[event], index )
      return true
   end
   
   return false
end

-------------------------------------------------------------------------------
-- You can also view the list of event hooks with this. This returns a direct
--  reference to the internal table which shouldn't be touched from the 
--  outside. Use with caution. Other addons might not expect you to be messing
--                                                     with their functions.
function Me.GetEventHooks( event ) 
   return Me.event_hooks[event] 
end

-------------------------------------------------------------------------------
-- Okay, now for whatever reason, we have this special API so that CHAT_NEW
--  listeners can spawn new messages. Presumably, they're discarding the 
--  original, or they're attaching some metadata that's whispered or something.
-- Very weird uses, but look, this is literally just for Tongues.
-- Chat messages that are spawned using this do not go through your CHAT_NEW
--  event listener twice. When they're processed, the filter list resumes right
--  after where yours was.
-- If you DO want to make a completely fresh message that goes through the
--  entire chain again, just make a direct call to AddChat.
--
-- `msg`, `chat_type`, `arg3`, `target`: The new chat message.
--
-- This should only be used from "CHAT_NEW" hooks.
--
function Me.AddChatFromStartEvent( msg, chat_type, arg3, target )
   local filter_index = 0
   local filter = Me.hook_stack[#Me.hook_stack]
   if filter then
      for k,v in pairs( Me.event_hooks["CHAT_NEW"] ) do
         if v == filter then
            filter_index = k
            break
         end
      end
   end
   
   Me.AddChat( msg, chat_type, arg3, target, filter_index + 1 )
end

-------------------------------------------------------------------------------
-- Sometimes you might want to send a chat message that bypasses Gopher's
--  filters. This is dangerous, and you should know what you're doing.
-- Basically, it's for funky protocol stuff where you don't want your message
--  to be touched, or even cut up. You'll get errors if you try to send
--  messages too big.
-- Messages that bypass the splitter still go through Gopher's queue system
--  with all guarantee's attached. CHAT_NEW is skipped, but QUEUE and POSTQUEUE
--  still trigger.
-- Calling this affects the next intercepted chat message only and then it
--  resets itself.
function Me.Suppress()
   Me.suppress = true
end

-------------------------------------------------------------------------------
-- This lets you pause the chat queue so you can load it up with messages
--  first, mainly for you to insert different priorities without the lower ones
--  firing before you're done feeding the queue. This automatically resets
--  itself, and you need to call it for each message added. Call StartQueue
--  when you're done adding messages.
--
function Me.PauseQueue()
   Me.queue_paused = true
end

-------------------------------------------------------------------------------
-- This is a feature added mainly for Cross RP, to keep the text protocol's
--  traffic away from clogging chat text from going through. Higher numbers are
--  always sent after lower priority numbers. (1 is highest priority)
-- If you're just sending chat, you likely won't ever need this. It's also
--  automatically reset after sending a chat message, and you need to call it
--  each time you want to send a low priority message.
function Me.SetTrafficPriority( priority )
   Me.traffic_priority = priority
end

function Me.GetTrafficPriority()
   return Me.traffic_priority
end

-------------------------------------------------------------------------------
-- Insert an entry into the chat queue, respecting priority.
--
local function ChatQueueInsert( entry )
   local insert_index = #Me.chat_queue+1
   for k, v in ipairs( Me.chat_queue ) do
      if v.prio > entry.prio then
         insert_index = k
         break
      end
   end
   table.insert( Me.chat_queue, insert_index, entry )
end

-------------------------------------------------------------------------------
-- Inserts a BREAK into the queue. This is a special message that doesn't allow
--  grouping across the break. This has limited purpose, but Cross RP uses it
--  to group messages together with the club channels.
--
-- Examples:
--   SAY   HELLO         \ Sent together, as they're different channels
--   CLUB  RELAY_HELLO   /
--   CLUB  SOMETHING     \ Sent together with next batch.
--   SAY   HELLO         / 
--   CLUB  RELAY_HELLO   - This RELAY message is sent too late, and by itself.
--
--   SAY   HELLO         \ Sent together, as they're different channels
--   CLUB  RELAY_HELLO   /
--   CLUB  SOMETHING     \ Sent together with next batch.
--   BREAK               -- Cuts grouping.
--   SAY   HELLO         \ Sent together properly.
--   CLUB  RELAY_HELLO   /
--
-- This may have more uses in the future. Another example.
--   SAY   HELLO        -> Sent on first batch.
--   BREAK              -> Waits for queue to empty
--   CLUB  YES          -> Sent in order one after another.
--   CLUB  YES          -
--   CLUB  YES          - If the break wasn't there, all of these could be
--   CLUB  YES          -  sent while that important HELLO up there was still
--                      -  pending. See?
--
-- What BREAK also does is waits for the throttler to catch up on BURST
--  bandwidth, essentially making it guaranteed that you're going to be sending
--  your grouped messages in a tight pair.
--
function Me.QueueBreak( priority )
   priority = priority or 1
   ChatQueueInsert({ 
      type = "BREAK";
      prio = priority;
      id = Me.message_id;
   })
   Me.message_id = Me.message_id + 1
end

-------------------------------------------------------------------------------
function Me.DeleteClubMessage( club, stream, message_id )
   Me.QueueCustom( { 
      msg  = ""; -- For the throttler. :)
      arg3 = club;
      target = stream;
      type = "CLUBDELETE";
      prio = 1;
      cmid  = message_id;
      id = Me.message_id;
   })
end

-------------------------------------------------------------------------------
function Me.EditClubMessage( club, stream, message_id, text )
   Me.QueueCustom({
      msg  = text;
      arg3 = club;
      target = stream;
      type = "CLUBEDIT";
      prio = 1;
      cmid  = message_id;
      id = Me.message_id;
   })
end

-------------------------------------------------------------------------------
-- Causes Gopher to use this chunk size when cutting up messages of this chat
--  type.
-- Pass nil as size to remove an override.
-- Pass "OTHER" as the `chat_type` to override all default settings.
-- Chunk size is calculated as:
--  `overrides[type] or defaults[type] or overrides.OTHER or defaults.OTHER`
-- `defaults` is the internal default chunk sizes.
--
function Me.SetChunkSizeOverride( chat_type, chunk_size )
   Me.chunk_size_overrides[chat_type] = chunk_size
end

-------------------------------------------------------------------------------
function Me.SetTempChunkSize( chunk_size )
   Me.next_chunk_size = chunk_size
end

local function FalseIsNil( value )
   if value == false then
      return nil
   else
      return value
   end
end

-------------------------------------------------------------------------------
function Me.SetSplitmarks( pre, post, sticky )
   local key_pre, key_post = "splitmark_start", "splitmark_end"
   if not sticky then
      key_pre = key_pre .. "_temp"
      key_post = key_post .. "_temp"
   end
   
   if pre ~= nil then
      Me[key_pre] = FalseIsNil( pre )
   end
   
   if post ~= nil then
      Me[key_post] = FalseIsNil( post )
   end
end

-------------------------------------------------------------------------------
function Me.GetSplitmarks( sticky )
   if sticky then
      return Me.splitmark_start, Me.splitmark_end
   else
      return Me.splitmark_start_temp, Me.splitmark_end_temp
   end
end

-------------------------------------------------------------------------------
function Me.SetPadding( prefix, suffix )
   if prefix ~= nil then
      Me.chunk_prefix = FalseIsNil( prefix )
   end
   
   if suffix ~= nil then
      Me.chunk_suffix = FalseIsNil( suffix )
   end
end

-------------------------------------------------------------------------------
function Me.GetPadding()
   return Me.chunk_prefix, Me.chunk_suffix
end

-------------------------------------------------------------------------------
-- Certain messages can have metadata attached. Only allowed for non-queued
--  types that are guaranteed to go through, like normal whispers and party
--  chat. `prefix` is the addon data prefix used. `text` is the text to send
--  which must be 255 bytes or less.
-- This data will always be received before the other end processes the chat
--  message that's attached to it. `perchunk` will make it so that the data is
--  duplicated/re-sent for each chunk delivered. If it's not set, then the
--                  metadata will only be sent once, for the very next chunk.
function Me.AddMetadata( prefix, text, perchunk )
   local m = Me.metadata
   m[#m+1] = prefix
   m[#m+1] = text
   m[#m+1] = perchunk
end

-------------------------------------------------------------------------------
-- Function for splitting text on newlines or newline markers (literal "\n").
--
-- Returns a table of lines found in the text {line1, line2, ...}. Doesn't 
--  include any newline characters or marks in the results. If there aren't any
--  newlines, then this is going to just return { text }.
--                               --
function Me.SplitLines( text )   --
   -- We merge "\n" into LF too. This might seem a little bit unwieldy, right?
   -- Like, you're wondering what if the user pastes something
   --  like "C:\nothing\etc..." into their chatbox to send to someone. It'll
   --          ^---.
   --  be caught by this and treated like a newline.
   -- Truth is, is that the user can't actually type "\n". Even without any
   --  addons, typing "\n" will cut off the rest of your message without 
   --  question. It's just a quirk in the API. Probably some security measure
   --  or some such for prudence? We're just making use of that quirk so
   --                             -- people can easily type a newline mark.
   text = text:gsub( "\\n", "\n" ) --
                                   --
   -- It's pretty straightforward to split the message now, we just use a 
   local lines = {}                        -- simple pattern and toss it 
   for line in text:gmatch( "[^\n]+" ) do  --  into a table.
      table.insert( lines, line )         --
   end                                     --
                                           --
   -- We still want to send empty messages for AFK, DND, etc.
   if #lines == 0 then
      lines[1] = ""
   end
   -- We used to handle this a bit differently, which was pretty nasty in
   --  regard to chat filters and such. It's a /little/ more complex now,
   return lines -- but a much better solution in the end.
end

-------------------------------------------------------------------------------
-- Our hooks just basically do some routing, rearrange the parameters for our
-- main AddChat function.
--
function Me.SendChatMessageHook( msg, chat_type, language, channel )
   -- Inside this execution path, we're typically (and should be) triggered by
   --  a hardware event so we can use all chat types. In 8.2.5, some chat types
   --  are restricted with no hardware event, such as /say, /yell, and channel.
   -- We can detect that error later down the line and then prompt for a
   --  keystroke in the throttler.
   Me.inside_hook = "CHAT"
   Me.AddChat( msg, chat_type or "SAY", language, channel )
   Me.inside_hook = nil
end

function Me.BNSendWhisperHook( presence_id, message_text ) 
   Me.inside_hook = "BNET"
   Me.AddChat( message_text, "BNET", nil, presence_id )
   Me.inside_hook = nil
end

function Me.ClubSendMessageHook( club_id, stream_id, message )
   Me.inside_hook = "CLUB"
   Me.AddChat( message, "CLUB", club_id, stream_id )
   Me.inside_hook = nil
end

-------------------------------------------------------------------------------
-- Returns the club ID for the user's guild, or nil if they aren't in a guild
--  or if it can't otherwise find it.
--
local function GetGuildClub()
   -- This is kind of poor that we have to do this scan for every chat
   --  message. But it helps to think about it like some sort of block of
   --  generic code that has to be run for sending chat. Chat isn't all
   --  that common though, so we can get away with stuff like this.
   for _, club in pairs( C_Club.GetSubscribedClubs() ) do
      if club.clubType == Enum.ClubType.Guild then
         return club.clubId
      end
   end
end

-------------------------------------------------------------------------------
-- Gets the stream for the main "GUILD" channel or "OFFICER" channel.
-- Type is from Enum.ClubStreamType, and it should be
--  Enum.ClubStreamType.Guild or Enum.ClubStreamType.Officer
-- Returns nil if not in a guild or if it can't find it.
local function GetGuildStream( type )
   local guild_club = GetGuildClub()
   if guild_club then
      for _, stream in pairs( C_Club.GetStreams( guild_club )) do
         if stream.streamType == type then
            return guild_club, stream.streamId
         end
      end
   end
end

function Me.FireEventEx( event, start, ... )
   start = start or 1
   local a1, a2, a3, a4, a5, a6 = ...
   for index = start, #Me.event_hooks[event] do
      table.insert( Me.hook_stack, Me.event_hooks[event][index] )
      local status, r1, r2, r3, r4, r5, r6 = 
         pcall( Me.event_hooks[event][index], event, a1, a2, a3, a4, a5, a6 )
      
      table.remove( Me.hook_stack )
      
      -- [1] is pcall status, [2] is first return value
      if status then
         -- If an event hook returns `false` then we cancel the chain.
         if r1 == false then
            return false
         elseif r1 then
            -- Otherwise, if it's non-nil, we assume that they're changing
            --  the arguments on their end, so we replace them with the
            --  return values.
            a1, a2, a3, a4, a5, a6 = r1, r2, r3, r4, r5, r6
         end
         -- If the hook returned nil, then we don't do anything to the
         --  event args.
      else
         -- The hook errored
         Me.DebugLog( "Listener error.", r1 )
      end
   end
   return a1, a2, a3, a4, a5, a6
end

function Me.FireEvent( event, ... )
   return Me.FireEventEx( event, 1, ... )
end

function Me.ResetState()
   Me.suppress             = nil
   Me.queue_paused         = nil
   Me.next_chunk_size      = nil
   Me.splitmark_end_temp   = nil
   Me.splitmark_start_temp = nil
   Me.chunk_prefix         = nil
   Me.chunk_suffix         = nil
   wipe( Me.metadata )
end

-------------------------------------------------------------------------------
-- This is where the magic happens...
--
-- Our parameters don't only accept the ones from SendChatMessage.
-- We also add the chat type "BNET" where target is the presence ID, and "CLUB"
--  where arg3 is the club ID, and target is the stream ID.
--
-- `hook_start` is for SendChatFromFilter where the filter function is
--  spawning new chat messages.
--
function Me.AddChat( msg, chat_type, arg3, target, hook_start )
   if Me.suppress then
      -- We don't touch suppressed messages.
      Me.FireEvent( "CHAT_QUEUE", msg, chat_type, arg3, target )
      Me.QueueChat( msg, chat_type, arg3, target )
      Me.FireEvent( "CHAT_POSTQUEUE", msg, chat_type, arg3, target )
      Me.ResetState()
      return
   end
   
   msg = tostring( msg or "" )
   
   msg, chat_type, arg3, target = 
      Me.FireEventEx( "CHAT_NEW", hook_start, msg, chat_type, arg3, target )
      
   if msg == false then
      Me.ResetState()
      return
   end
   
   -- Now we cut this message up into potentially several pieces. First we're
   --  passing it through this line splitting function, which gives us a table
   msg = Me.SplitLines( msg )  -- of lines, or just { msg } if there aren't
                                 --  any newlines.
   chat_type = chat_type:upper()
   -- We do some work here in rerouting some messages to avoid using
   --  SendChatMessage, specifically with ones that use the Club API. It's
   --  probably sending it there internally, but we can do that ourselves
   --  so we can take advantage of the fact that the Club API allows a 
   --  larger max message length. By default we split those types of messages
   --  up at the 400 character mark rather than 255.
   local chunk_size = Me.chunk_size_overrides[chat_type]
                         or Me.default_chunk_sizes[chat_type]
                         or Me.chunk_size_overrides.OTHER
                         or Me.default_chunk_sizes.OTHER
   if chat_type == "CHANNEL" then
      -- Chat type CHANNEL can either be a normal legacy chat channel, or the
      --  user can be typing in a chat channel that's linked to a community
      --  channel. This is only done through the normal chatbox. If you type
      --  in the community panel, it goes straight to C_Club:SendMessage.
      local _, channel_name,_, is_club = GetChannelName( target )
      if channel_name and is_club then
         -- GetChannelName returns a specific string for club channels:
         --   Community:<club ID>:<stream ID>
         local club_id, stream_id = 
                               channel_name:match( "Community:(%d+):(%d+)" )
         
         -- This is a community message, reroute this message to use
         --  C_Club directly...
         chat_type  = "CLUB"
         arg3       = tonumber(club_id)
         target     = tonumber(stream_id)
         chunk_size = Me.chunk_size_overrides.CLUB
                    or Me.default_chunk_sizes.CLUB
                    or Me.chunk_size_overrides.OTHER
                    or Me.default_chunk_sizes.OTHER
      end
   elseif chat_type == "GUILD" or chat_type == "OFFICER" then
      -- For GUILD and OFFICER, we want to reroute these too to use the
      --  Club API so we can take advantage of it just like we do with
      --  channels. GUILD and OFFICER are already using the Club API
      --  internally at some point, and guilds have their own club ID
      --  and streams.
      --[[
      if C_Club and Me.clubs then -- [7.x compat]
         local club_id, stream_id = 
            GetGuildStream( chat_type == "GUILD" 
                           and Enum.ClubStreamType.Guild 
                           or Enum.ClubStreamType.Officer )
         if not club_id then
            -- The client right now doesn't actually print this message, so
            --  we're helping it out a little bit. If it does start
            --  printing it on its own, then remove this.
            local info = ChatTypeInfo["SYSTEM"];
            DEFAULT_CHAT_FRAME:AddMessage( ERR_GUILD_PLAYER_NOT_IN_GUILD, 
                                           info.r, info.g, info.b, 
                                    info.id );
            -- They aren't in a guild though, so we cancel this message
            --  from being queued.
            return
         end
         chat_type  = "CLUB"
         arg3       = club_id
         target     = stream_id
      end]]
   end
   
   if Me.next_chunk_size then
      chunk_size = Me.next_chunk_size
   end
   
   -- And we iterate over each, pass them to our main splitting function 
   --  (the one that cuts them to smaller chunks), and then feed them off
   --  to our main chat queue system. That call might even bypass our queue
   --  or the throttler, and directly send the message if the conditions
   --  are right. But, otherwise this message has to wait its turn.
   for _, line in ipairs( msg ) do
      local chunks = Me.SplitMessage( line, chunk_size )
      for i = 1, #chunks do
         local chunk_msg, chunk_type, chunk_arg3, chunk_target =
            Me.FireEvent( "CHAT_QUEUE", chunks[i], chat_type, arg3, target )
            
         if chunk_msg then
            Me.QueueChat( chunk_msg, chunk_type, chunk_arg3, chunk_target )
            Me.FireEvent( "CHAT_POSTQUEUE", chunk_msg, chunk_type, 
                                                 chunk_arg3, chunk_target )
         end
      end
   end
   
   Me.ResetState()
end

-------------------------------------------------------------------------------
-- This table contains patterns for strings that we want to keep whole after
--  the message is cut up in SplitMessage. Chat links can have spaces in them
--  but if they're matched by this, then they'll be protected.
Me.chat_replacement_patterns = {
   -- The code below only supports 9 of these (because it uses a single digit
   --  to represent them in the text).
   -- Right now we just have this pattern, for catching chat links.
   -- Who knows how the chat function works in WoW, but it has vigorous checks
   --  (apparently) to allow any valid link, along with the exact color code
   --  for them.
   "(|cff[0-9a-f]+|H[^|]+|h(.-)|h|r)"; -- RegEx's are pretty cool,
                                        --  aren't they?
   -- I had an idea to also keep addon links intact, but there haven't really
   --  been any complaints, and this could potentially result in some breakage
   --  from people typing a long message (which breaks the limit) surrounded
   --  by brackets (perhaps an OOC message).
   --
   -- Like this: "%[.-%]";
   --
   -- A little note here, that the code below will break if there is a match
   -- that's shorter than 4 (or 5?) characters.

   -- 1/7/24 updates:
   -- Capture the text part of a link to use it to compute length. WoW allows long links
   -- to be sent in a single message, so we'll use the actual text length only when
   -- checking the length.
   
   -- In addition, some links contain "|A" codes in the text, so we will match with non
   -- greedy dot instead of non-pipe chars. 
}

-------------------------------------------------------------------------------
-- Here's our main message splitting function. You pass in text, and it spits
--  out a table of smaller message (or the whole message, if it's small
--  enough.)
-- text: Text to split up.
-- chunk_size: Size of the chunks to output. 
--             Defaults to Me.default_chunk_sizes.OTHER
-- splitmark_start: The text to add to the start of messages 2..N.
-- splitmark_end:   The text to add to the end of messages 1..N-1.
-- chunk_prefix: Text to prepend all chunks returned, e.g. "NPC says: "
-- chunk_suffix: Text to append to all chunks returned.
--
function Me.SplitMessage( text, chunk_size, splitmark_start, splitmark_end,
                                                   chunk_prefix, chunk_suffix )
   chunk_size      = chunk_size or Me.default_chunk_sizes.OTHER
   chunk_prefix    = chunk_prefix or Me.chunk_prefix or ""
   chunk_suffix    = chunk_suffix or Me.chunk_suffix or ""
   splitmark_start = splitmark_start or Me.splitmark_start_temp
                                                   or Me.splitmark_start or ""
   splitmark_end   = splitmark_end or Me.splitmark_end_temp
                                                     or Me.splitmark_end or ""
   local pad_len   = chunk_prefix:len() + chunk_suffix:len()
   
   -- For short messages we can not waste any time and return immediately
   --                 if they can fit within a chunk already. A nice shortcut.
   -- I acknowledge that this shortcut will not detect messages with long link metadata
   -- to fit within a single message.
   --if text:len() + pad_len <= chunk_size then
  --    return { chunk_prefix .. text .. chunk_suffix }
   --end
   
   -- Otherwise, we gotta get our hands dirty. We want to preserve links (or
   --  other defined things in the future) from being split apart by the
   --  cutting code below. We do that by turning them to solid strings that
   local replaced_links = {} -- contain an ID code for reversing at the end.
                             --
   
   for index, pattern in ipairs( Me.chat_replacement_patterns ) do
      text = text:gsub( pattern, function( link, textpart )
         -- This turns something like "[Chat Link]" into "12x22222223",
         --  essentially obliterating that space in there so this "word"
         --  is kept whole. The x there is used to identify the pattern
         --  that matched it. We save the original text in replaced_links
         --  one on top of the other. The index is used to know which
         --  replacement list to pull from.
         -- replaced_links is a table of lists, and we index it by this `x`.
         -- In here, we just throw it on whichever list this pattern belongs

         -- 1/7/24:
         -- We replace the complete link string with a string that matches the length
         -- of the visible text part. For example, linking a level 5 Elemental Lariat with
         -- 3 gems is over 270ish chars by itself. WoW probably only checks the visible
         -- length of the message when enforcing limits.
         -- We're reducing the text size here, then splitting happens, then we expand it
         -- back to the original size.
         replaced_links[index] = replaced_links[index] or {} -- to.
         table.insert( replaced_links[index], link )
         return "\001\002" .. index 
                .. ("\002"):rep( textpart:len() - 4 ) .. "\003"
      end)
   end
   
   -- A little bit of preprocessing goes a long way somtimes, like this, where
   --  we add whitespace directly to the splitmarks rather than applying it 
   if splitmark_start ~= "" then              -- separately below in the loop.
      splitmark_start = splitmark_start .. " "
   end                                       -- If they are empty strings,
   if splitmark_end ~= "" then               --  then they're disabled. This 
      splitmark_end = " " .. splitmark_end  --  all works smoothly below in 
   end                                       --  the main part.
   
   local chunks = {} -- Our collection of text chunks. The return value. We'll
                     --  fill it with each section that we cut up.
   while( text:len() + pad_len > chunk_size ) do
      -- While in this loop, we're dealing with `text` that is too big to fit
      --  in a single chunk (max 255 characters or whatever the override is
      --  set to [we'll use the 255 figure everywhere to keep things
      --  simple]).
      -- We actually start our scan at character 256, because when we do the
      --  split, we're excluding that character. Either deleting it, if it's
      --  whitespace, or cutting right before it.
      -- We scan backwards for whitespace or an otherwise suitable place to
      --  break the message.
      local quote_aware = Me.db and Me.db.global and Me.db.global.quote_aware_split
      local split_at = nil
      local split_offset = 0
      local quote_size = 0  -- Track size of quote character (1 for ASCII, 3 for UTF-8)
      -- Debug helpers (uncomment to trace splitting)
      -- if quote_aware then
      --    print("DEBUG: quote_aware_split ENABLED, chunk_size=" .. chunk_size .. ", text_len=" .. text:len())
      --    print("DEBUG: first 50 chars: " .. text:sub(1, 50))
      --    print(string.format("DEBUG: Position 1 char: 0x%02x, Position 2: 0x%02x", string.byte(text, 1) or 0, string.byte(text, 2) or 0))
      -- end
      
      -- Try to get quote_aware_split from EmoteSplitter addon if available
      if not quote_aware and _G.EmoteSplitter and _G.EmoteSplitter.db then
         quote_aware = _G.EmoteSplitter.db.global and _G.EmoteSplitter.db.global.quote_aware_split
      end
      
      -- Debug logging removed after verification
      
      for i = chunk_size+1 - splitmark_end:len() - pad_len, 1, -1 do
         --               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
         -- Don't forget to leave some extra room!
         local ch = string.byte( text, i )
         
         -- Check for quotation marks if quote_aware_split is enabled
         if quote_aware then
            if ch == 34 then -- ASCII straight quote (")
               -- print("DEBUG: Found STRAIGHT quote at position " .. i)
               split_at = i
               split_offset = 0
               quote_size = 1  -- ASCII quote is 1 byte
               break  -- Use quote immediately
            elseif ch == 0xE2 then -- potential UTF-8 smart double quote
               local byte2 = string.byte( text, i+1 )
               local byte3 = string.byte( text, i+2 )
               -- Only treat double quotes (E2 80 9C/9D) as split points.
               -- Do NOT split on single curly quotes (E2 80 98/99) so words like
               -- "here's" stay intact.
               if byte2 == 0x80 and (byte3 == 0x9C or byte3 == 0x9D) then
                  -- print(string.format("DEBUG: Found SMART double quote at position %d, bytes: 0x%02x 0x%02x 0x%02x", i, ch, byte2 or 0, byte3 or 0))
                  split_at = i
                  split_offset = 0
                  quote_size = 3  -- UTF-8 smart quote is 3 bytes
                  break  -- Use quote immediately
               end
            end
         end
         
         -- We split on spaces (ascii 32) or a start of a link (inserted
         if ch == 32 or ch == 1 then -- above).
            
            -- If it's a space, then we discard it.
            -- Otherwise we want to preserve this character and keep it in
            local offset = 0                -- the next chunk.
            if ch == 32 then offset = 1 end --
            
            if quote_aware then
               -- Record space but continue scanning for a quote; fallback to this space later if no quote found
               if not split_at then
                  split_at = i
                  split_offset = offset
               end
            else
               -- Original behaviour: break on first space when quote awareness is off
               split_at = i
               split_offset = offset
               break
            end
         end
         
         -- If the scan reaches all the way to the last bits of the string,
         if i <= 16 then  -- then that means there's a REALLY long word.
            -- In that case, we just break the message wherever. We just
            --  need to take care to not break UTF-8 character strings.
            -- Who knows, maybe it might not even be abuse. Maybe it's
            --  just a really long sentence of Kanji glyphs or something??
            -- (I don't know how Japanese works.)
            --
            -- We're starting over this train.
            for i = chunk_size+1 - splitmark_end:len() - pad_len, 1, -1 do
               local ch = text:byte(i)
               
               -- Now we're searching for any normal ASCII character, or
               --  any start of a UTF-8 character. UTF-8 bit format for 
               --  the first byte in a multi-byte character is always 
               --  `11xxxxxx` the following bytes are all `10xxxxxx`, so
               if (ch >= 32 and ch < 128)  --  our resulting criteria is 
                       or (ch >= 192) then  --  [32-128] and [192+].
                  table.insert( chunks, chunk_prefix 
                                         .. text:sub( 1, i-1 ) 
                                           .. splitmark_end  
                                             .. chunk_suffix )
                  text = splitmark_start .. text:sub( i )
                  break
               end
               -- We could have done this search in the above loop, keep
               --  track of where the first valid character is, keep 
               --  things DRY, but this is a heavy corner case, and we
               --  don't need to slow down the above loop for it.
               
               -- If we reach halfway through the text without finding a
               --  valid character to split at, then there is some clear 
               --  abuse going on. (Actually, we should have found one in
               if i <= 128 then  -- the first few bytes.)
                  return {""}   -- In this case, we just obliterate
               end               --  whatever nonsense we were fed.
            end                   -- No mercy.
            
            break -- Make sure that we aren't repeating the outer loop.
         end
      end
      
      -- Now perform the split if we found a split point
      if split_at then
         if quote_size > 0 then
            -- Split at quote: exclude quote from first chunk, include in second chunk
            -- This keeps opening quotes with their dialogue
            table.insert( chunks, chunk_prefix .. text:sub( 1, split_at - 1 ) 
                                         .. splitmark_end .. chunk_suffix )
            -- Include the quote at the start of the second chunk
            text = splitmark_start .. text:sub( split_at )
         else
            -- Split at space: discard the space as before
            table.insert( chunks, chunk_prefix .. text:sub( 1, split_at - 1 ) 
                                         .. splitmark_end .. chunk_suffix )
            text = splitmark_start .. text:sub( split_at + split_offset )
         end
      end
   end

   -- `text` is now the final chunk that can fit just fine, so we throw that
   table.insert( chunks, chunk_prefix .. text .. chunk_suffix ) -- in too!
   
   -- We gotta put the links back in the text now.
   -- This is neat, isn't it? We allow up to 9 replacement patterns (and any
   --  more is gonna be pushing it). Simple enough, we grab strings from the
   --  saved values and increment whichever index we're using.
   local counters = {1,1,1, 1,1,1, 1,1,1}
   
   for i = 1, #chunks do 
      chunks[i] = chunks[i]:gsub("\001\002(%d)\002*\003", function(index)
         -- Now, you could just write
         --  `index = tonumber(index)` to convert this number, but we
         --  can do a dumb trick. Since it's a single digit, we just
         --  steal the ASCII value directly, and subtract 48 (ascii for 0)
         index = index:byte(1) - 48 -- from it. I imagine this is way 
                                    --  faster than tonumber(index).
         -- But honestly little hacks like this which show little to no
         --  performance gain in practice (this code is hardly called)
         --  just makes the code uglier. It's just something to keep in
         --  mind when doing more performance intensive operations.
         -- Anyway, we needed a number value to index our counters and
         local text = replaced_links[index][counters[index]] -- replaced
         counters[index] = counters[index] + 1              -- links table.
         
         -- We really shouldn't be /missing/ our replacement value. If this
         --  happens, then there's likely malicious text in the string we
         --  got. A valid case of this actually happening without anyone
         --  being deliberate is some sort of addon inserting hidden data
         --  into the message which they forgot to (or haven't yet) removed.
         return text or "" -- They could be removing it shortly after in
      end)                  --  some hooks or something.
   end
   
   return chunks
end

-------------------------------------------------------------------------------
-- This is our main entry into our chat queue. Basically we have the same
--  parameters as the SendChatMessage API. For BNet whispers, set `type` to 
--  "BNET" and `target` to the bnetAccountID. For Club messages, `type` is 
--  "CLUB", `arg3` is the club ID, and `target` is the stream ID.
-- Normal parameters:
--  msg     = Message text
--  type    = Message type, e.g "SAY", "EMOTE", "BNET", "CLUB", etc.
--  arg3    = Language index or club ID.
--  target  = Whisper target, bnetAccountID, channel name, or stream ID.
--
function Me.QueueChat( msg, type, arg3, target )
   type = type:upper()
   
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
         return
      end
      
      Me.StartQueue()
      
   else
      -- For other message types like party, raid, whispers, channels, we
      --  aren't going to be affected by the server throttler, so we go
      --                 straight to putting these messages out on the line.
      -- New in v10: metadata. For each non-queued message that's sent, there
      --  may be metadata that's attached. By principle of the design/system,
      --  this can't really be used on queued messages, because then you're
      --                       mixing guaranteed/non-guaranteed deliveries.
      if #Me.metadata > 0 then
         -- Metadata is stored under the `meta` key of each message pack.
         -- The contents are a list of `prefix` and `text` pairs, for 
         --  SendAddonMessage.
         local meta    = {}
         local source  = Me.metadata
         msg_pack.meta = meta
         
         local i = 1
         while i <= #source do
            -- The metadata source table is currently 3 entries per set.
            -- [i+0] and [i+1] is the addon message prefix and text, and is
            --                                stored in the message pack.
            meta[#meta+1] = source[i]
            meta[#meta+1] = source[i+1]
            
            -- [i+2] is a flag to copy the data for each chunk sent, so the
            --  data appears on the receiving end before each CHAT_MSG
            --  event, rather than just the first one.
            if not source[i+2] then
               -- If it's not removed here, then it will be removed when
               --  ResetState() is called after everything is queued.
               table.remove( source, i )
               table.remove( source, i )
               table.remove( source, i )
            else
               i = i + 3
            end
         end
      end
      Me.CommitChat( msg_pack )
   end                            
end

function Me.QueueCustom( custom )
   custom.id = Me.message_id
   Me.message_id = Me.message_id + 1
   ChatQueueInsert( custom )
   if Me.queue_paused then return end
   Me.StartQueue()
end

function Me.AnyChannelsBusy()
   for i = 1, Me.NUM_CHANNELS do
      if Me.channels_busy[i] then return true end
   end
end

function Me.AllChannelsBusy()
   for i = 1, Me.NUM_CHANNELS do
      if not Me.channels_busy[i] then return false end
   end
   return true
end

function Me.SendingActive()
   return Me.sending_active
end

-------------------------------------------------------------------------------
-- Execute the chat queue.
--
function Me.StartQueue()
   Me.queue_paused = false
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
      if not Me.AnyChannelsBusy() and Me.sending_active then
         Me.FireEvent( "SEND_DONE" )
         Me.failures       = 0
         Me.sending_active = false
      end
      return
   end
   
   if not Me.sending_active then
      Me.sending_active = true
      Me.FireEvent( "SEND_START" )
   end
   -- Otherwise, we're gonna send another message. 
   
   local i = 1
   while i <= #Me.chat_queue do
      local q = Me.chat_queue[i]
      if q.type == "BREAK" then
         if Me.AnyChannelsBusy() then
            break
         else
            if Me.ThrottlerHealth() < 25 then
               Me.Timer_Start( "gopher_throttle_break", "ignore", 0.1, 
                                                        Me.ChatQueueNext )
               return
            end
            table.remove( Me.chat_queue, i )
         end
      else
         local channel = QUEUED_TYPES[q.type]
         if not Me.channels_busy[channel] then
    --        Me.Timer_Start( "gopher_channel_"..channel, "push", 
    --                               Me.CHAT_TIMEOUT, Me.ChatDeath, channel )
            Me.channels_busy[channel] = q
            -- Some of our error handlers can trigger immediately when you
            --  try to send a chat message, like the club types or the
            --  offline whisper notice for Bnet. In that case we obviously
            --  don't want our failure handlers to treat it like a normal
            --  failure - we aren't done in here yet.
            Me.inside_chat_queue = true
            Me.CommitChat( q )
            Me.inside_chat_queue = false
            -- If it errored above, the channels_busy entry will be cleared
            --  again and allow us to continue.
            if Me.AllChannelsBusy() then
               break
            end
         end
         i = i + 1
      end
   end
   
   if not Me.AnyChannelsBusy() and Me.sending_active then
      Me.FireEvent( "SEND_DONE" )
      Me.failures = 0
      Me.sending_active = false
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
-- This is called from the throttler when a chat message is released from the
--  queue and put out onto the line. We need to wait until here to start our
--  timeout timers, because some messages might take significant delays due to
--  needing a keypress to resume.
function Me.OnChatSent( msg )
   local channel = QUEUED_TYPES[ msg.type ]
   if not channel then
      -- This is an unqueued message, which aren't babysat.
      return
   end
   
   Me.Timer_Start( "gopher_channel_"..channel, "push", 
                          Me.CHAT_TIMEOUT, Me.ChatDeath, channel )
end

-------------------------------------------------------------------------------
-- Timer callback for when chat times out.
-- This is a fatal error due to timeout. At this point, we've waited extremely
--  long for a message. Something went wrong or the user is suffering from
--  intense latency. We just want to reset completely to recover.
function Me.ChatDeath() 
   Me.FireEvent( "SEND_DEATH", Me.chat_queue )
   
   if Me.debug_mode then
      Me.DebugLog( "Chat death!" )
      print( "  Channels busy:", not not Me.channels_busy[1], 
                                not not Me.channels_busy[2] )
      print( "  Copying chat queue to GOPHER_DUMP_CHATQUEUE." )
      GOPHER_DUMP_CHATQUEUE = {}
      
      for _, v in ipairs( Me.chat_queue ) do
         table.insert( GOPHER_DUMP_CHATQUEUE, v )
      end
   end
   wipe( Me.chat_queue )
   Me.sending_active = false
   for i = 1, Me.NUM_CHANNELS do
      Me.channels_busy[i] = nil
   end
   
end

-------------------------------------------------------------------------------
-- These two functions are called from our event handlers. 
-- This one is called when we confirm a message was sent. The other is called
--                            when we see we've gotten a "throttled" error.
function Me.ChatConfirmed( channel, skip_event )
   Me.StopLatencyRecording()
   Me.channel_failures[channel] = nil
   
   if not skip_event then
      Me.FireEvent( "SEND_CONFIRMED", Me.channels_busy[channel] )
   end
   Me.channels_busy[channel] = nil
   
   -- Cancelling either the main 10-second timeout, or the throttled warning
   --  timeout (see below).
   Me.Timer_Cancel( "gopher_channel_"..channel )
   
   -- This might be from inside of the chat queue for some types, like the
   --  bnet offline inform which happens instantly.
   if not Me.inside_chat_queue then
      Me.ChatQueueNext()
   end
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
   Me.channel_failures[channel] = (Me.channel_failures[channel] or 0) + 1
   if Me.channel_failures[channel] >= Me.FAILURE_LIMIT then
      Me.ChatDeath()
      return
   end
   
   Me.FireEvent( "SEND_FAIL", Me.channels_busy[channel] )
   
   -- With the 8.0 update, Emote Splitter also supports communities, which
   --  give a more clear signal that the chat failed that's purely from
   --  the throttler, so we don't account for latency.
   local wait_time
   if channel == 2 then -- CLUB channels
      wait_time = Me.CHAT_THROTTLE_WAIT
   else
      wait_time = math.min( 10, math.max( 1.5 + Me.GetLatency(),
                                                     Me.CHAT_THROTTLE_WAIT ))
   end
   
   Me.Timer_Start( "gopher_channel_"..channel, "push", wait_time,
                                                 Me.ChatFailedRetry, channel )
end                          

-------------------------------------------------------------------------------
-- For restarting the chat queue after a failure.
--
function Me.ChatFailedRetry( channel )
   Me.FireEvent( "SEND_RECOVER", Me.channels_busy[channel] )
   Me.channels_busy[channel] = nil
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
   
   if time <= 0.001 then
      -- Something went wrong and we stopped in the same frame.
      Me.latency_recording = nil
      return
   end
   
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
   if not Me.channels_busy[1] then
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
      Me.ChatFailed( 1 ) -- it and then continue as normal.
   end
end

-------------------------------------------------------------------------------
function Me.OnClubMessageUpdated( event, club, stream, message_id )
   local c = Me.channels_busy[3]
   if not c then return end
   -- We could also verify that message_id matches in our queue, but honestly
   --  those message ids are WILD and I'm not sure if there's some sort of 
   --  precision error that might come into play.
   if club == c.arg3 and stream == c.target then
      local info = C_Club.GetMessageInfo( club, stream, message_id )
      -- This is a little bit iffy, because someone else could modify one
      --  of your messages at the same time you're doing one of these tasks
      --  and confuse it.
      
      if info.author.isSelf then
         RemoveFromTable( Me.chat_queue, Me.channels_busy[3] )
         Me.ChatConfirmed( 3 )
      end
   end
end

-------------------------------------------------------------------------------
-- Our hook for when the client gets an error back from one of the community
-- features.
function Me.OnClubError( event, action, error, club_type )
   Me.DebugLog( "Club error.", action, error, club_type )
   
   -- This will match the error that happens when you get throttled by the
   --  server from sending chat messages too quickly. This error is vague
   --  though and still matches some other things, like when the stream is
   --  missing. Hopefully in the future the vagueness disappears so we know
   --  what sort of error we're dealing with, but for now, we assume it is a
   --  throttle, and then retry a number of times. We have a failure counter
   --  that will stop us if we try too many times (where we assume it's 
   --  something else causing the error).
   if Me.channels_busy[2]
           and action == Enum.ClubActionType.ErrorClubActionCreateMessage then
      Me.ChatFailed( 2 )
      return
   end
   
   local c = Me.channels_busy[3]
   if not c then return end
   if c.type == "CLUBEDIT" 
        and action == Enum.ClubActionType.ErrorClubActionEditMessage 
         or c.type == "CLUBDELETE" 
          and action == Enum.ClubActionType.ErrorClubActionDestroyMessage then
      Me.ChatFailed( 3 )
      return
   end
end

-------------------------------------------------------------------------------
function Me.OnChatMsgBnOffline( event, ... )
   local c = Me.channels_busy[1]
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
      
      Me.ChatConfirmed( 1, true )
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

   -- 9/27/18 - As of today chatting to guild can end up in three events:
   --   CHAT_MSG_GUILD
   --   CHAT_MSG_OFFICER
   --   CHAT_MSG_COMMUNITIES_CHANNEL
   --
   -- The third happens when you chat in a channel that isn't the standard
   --  Guild/Officer channels that come with a guild. The first two can be
   --  triggered by using the community chat or the normal chatbox chat.
   --  CHAT_MSG_COMMUNITIES_CHANNEL is never used for the default guild
   --  channels, despite the underlying system sharing the same community
   --  setup. Sometimes clubs can go offline and then the game is probably
   --  just using the old chat channels.
   -- In VERSION 7 we also don't reroute to the community channels in the
   --  splitter, as this allows better compatibility with other addons and
   --  other corner cases (at the sacrifice of a larger character limit).
   
   local cq = Me.channels_busy[2]
   if cq and guid == Me.PLAYER_GUID then
      event = event:sub( 10 )
      
      -- `cq.type` /may/ be "CLUB", or "GUILD" or "OFFICER" depending on how
      --  the user sent the message.
      if (cq.type == event) 
              or (cq.type == "CLUB" and cq.arg3 == GetGuildClub()) then
         RemoveFromTable( Me.chat_queue, cq )
         Me.ChatConfirmed( 2 )
      end
   end
end

-------------------------------------------------------------------------------
-- Hook for when we received a message on a community channel.
--
function Me.OnChatMsgCommunitiesChannel( event, _,_,_,_,_,_,_,_,_,_,_, 
                                         guid, bn_sender_id )
   local cq = Me.channels_busy[2]
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
      Me.ChatConfirmed( 2 )
   end
end

-------------------------------------------------------------------------------
-- 12/11/18, VERSION 8: Club channels that aren't added to the chatbox no
--  longer trigger CHAT_MSG_COMMUNITIES_CHANNEL. We need to handle them through
--  this (more convoluted) event.
--
function Me.OnClubMessageAdded( event, club_id, stream_id, message_id )
   local cq = Me.channels_busy[2]
   if not cq then return end
   
   local message = C_Club.GetMessageInfo( club_id, stream_id, message_id )
   
   if cq.type == "CLUB" and cq.arg3 == club_id and cq.target == stream_id 
                                                and message.author.isSelf then
      RemoveFromTable( Me.chat_queue, cq )
      Me.ChatConfirmed( 2 )
   end
end

-------------------------------------------------------------------------------
-- Returns true if the message queue has entries that need hardware events to
--  send, such as /say in the open world (8.2.5).
function Me.HasProtectedMessagesQueued()
   local count = 0
   for _, q in pairs( Me.chat_queue ) do
      if ((q.type == "SAY" or q.type == "YELL") and not IsInInstance())
                                or q.type == "CHANNEL" or q.type == "CLUB" then
         count = count + 1
         if count >= 2 then
            return true
         end
      end
   end
end

-------------------------------------------------------------------------------
-- We hook when the chatbox is opened to use as a trigger for continuing the
--  chat message queue when sending protected messages. This is a post hook so
--  we aren't adding unnecessary taint to the UI, and we just close the chat
--  edit box if we want to block it.
function Me.OnOpenChat( ... )
   if Me.TryContinuePrompt() then
      if ACTIVE_CHAT_EDIT_BOX and ACTIVE_CHAT_EDIT_BOX.text ~= "/" then
         ACTIVE_CHAT_EDIT_BOX:Hide()
      end
      
      -- The community frame uses this to steal focus from the normal chatbox.
      -- Instead of the normal chat edit box appearing, it instead sets the
      --  focus to this, or the community panel input.
      if CHAT_FOCUS_OVERRIDE then
         CHAT_FOCUS_OVERRIDE:ClearFocus()
      end
   end
   --[[
   if Me.prompt_continue then
   
      
      
      if Me.prompt_continue and Me.ThrottlerHealth() > 30 then
         Me.prompt_continue = false
         Me.HideContinueFrame()
         Me.PipeThrottlerKeystroke()
      end
      
   end]]
end

function Me.TryContinuePrompt()
   if Me.prompt_continue and Me.ThrottlerHealth() > 30 then
      Me.prompt_continue = false
      Me.HideContinueFrame()
      Me.PipeThrottlerKeystroke()
      return true
   end
end

-------------------------------------------------------------------------------
function Me.PromptForContinue()
   Me.prompt_continue = true
   Me.ShowContinueFrame()
end

-------------------------------------------------------------------------------
-- Hooks
-------------------------------------------------------------------------------
-- VERSION 7: We hook the chat functions as soon as possible. This is riskier
--  for future compatibility and may introduce some quirks, but this allows us
--  finer control over the chat system, and better compatibility with other
--  addons that hook the chat system directly to insert or remove text. Ideally
--  those addons should be using Gopher hooks, but probably not a realistic
--  expectation. For any addons that need special compatibility care, we add
--                                            support in compatibility.lua.
Me.hooks = Me.hooks or {}

if not Me.hooks.SendChatMessage then
   Me.hooks.SendChatMessage = C_ChatInfo.SendChatMessage
   -- We pass this through an anonymous function so that we can upgrade it
   --  later. In other words we don't want a static reference to
   --  SendChatMessageHook, because that function might change when we 
   --  load a newer version.
   function C_ChatInfo.SendChatMessage( ... )
      return Me.SendChatMessageHook( ... )
   end
end

if not Me.hooks.BNSendWhisper then
   Me.hooks.BNSendWhisper = BNSendWhisper
   function BNSendWhisper( ... )
      return Me.BNSendWhisperHook( ... )
   end
end

if not Me.hooks.ChatFrame_OpenChat then
   Me.hooks.ChatFrame_OpenChat = true
   -- Hook ChatFrameUtil.OpenChat to intercept Enter key presses when the
   -- continue prompt is shown. This allows pressing Enter to resume sending.
   hooksecurefunc(ChatFrameUtil, "OpenChat", function( ... )
      Me.OnOpenChat( ... )
   end)
end

if C_Club then -- [7.x compat]
   if not Me.hooks.ClubSendMessage then
      Me.hooks.ClubSendMessage = C_Club.SendMessage
      C_Club.SendMessage = function( ... )
         return Me.ClubSendMessageHook( ... )
      end
   end
end

-------------------------------------------------------------------------------
-- Timer API
-------------------------------------------------------------------------------
Me.timers = {}
Me.last_triggered = {}

function Me.Timer_NotOnCD( slot, period )
   if not Me.last_triggered[slot] then return true end
   local time_to_next = (Me.last_triggered[slot] or (-period)) + period - GetTime()
   if time_to_next <= 0 then
      return true
   end
end

-- slot = string ID
-- mode = how this timer works or reacts to additional start calls
--          "push" = cancel existing and wait for the new period to expire
--          "ignore" = ignore the new call
--          "duplicate" = leave previous timer running and make new one
--          "cooldown" = this triggers instantly with a cooldown, 
--                       additional calls during the cooldown period are 
--                       merged into a single call at the end of the
--                       cooldown period. This may trigger inside
--                       this call.
function Me.Timer_Start( slot, mode, period, func, ... )
   if mode == "cooldown" and not Me.timers[slot] then
      local time_to_next = (Me.last_triggered[slot] or (-period)) + period - GetTime()
      if time_to_next <= 0 then
         Me.last_triggered[slot] = GetTime()
         func()
         return
      end
      
      -- cooldown remains, ignore or schedule it
      mode = "ignore"
      period = time_to_next
   end
   
   if Me.timers[slot] then
      if mode == "push" then
         Me.timers[slot].cancel = true
      elseif mode == "duplicate" then
         
      else -- ignore/cooldown/default
         return
      end
   end
   
   local this_timer = {
      cancel = false;
   }
   
   local args = {...}
   
   Me.timers[slot] = this_timer
   C_Timer.After( period, function()
      if this_timer.cancel then return end
      Me.timers[slot] = nil
      Me.last_triggered[slot] = GetTime()
      func( unpack( args ))
   end)
end

function Me.Timer_Cancel( slot )
   if Me.timers[slot] then
      Me.timers[slot].cancel = true
      Me.timers[slot] = nil
   end
end

-------------------------------------------------------------------------------
function Me.DebugLog( ... )
   if not Me.debug_mode then return end
   
   print( "[Gopher-Debug]", ... )
end

-- See you on Moon Guard! :)
--                ~              ~   The Great Sea ~                  ~
--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^-