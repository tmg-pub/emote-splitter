-------------------------------------------------------------------------------
-- Gopher
-- by Tammya-MoonGuard (Copyright 2018)
--
-- All Rights Reserved.
-------------------------------------------------------------------------------
local Internal = LibGopher.Internal
if not Internal.load then return end
local Gopher = LibGopher

-------------------------------------------------------------------------------
-- This file describes  the  public API.  You can still  use  internal stuff if
--  you're daring,  but  of  course there are the usual warnings that come with
--  doing that.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Returns the revision number that's loaded.
--
function Gopher.GetVersion()
	return Internal.Version
end

-------------------------------------------------------------------------------
-- Gopher exposes  a  number  of  its  execution points via events.  These  are
--  primarily  for  third party addons to monitor or adjust text that's sent by
--  the user at different points throughout our system.
-- 
-- The reason for this  is  to  avoid any more hooking  of  the SendChatMessage
--  function itself.  Normally an addon would hook SendChatMessage if they want
--  to  insert something  (like replacing a certain keyword on the way out,  or
--  removing text) but with Gopher you don't know  if  you're going to get your
--  hook called before OR after the text is split up into smaller sections. 
-- A clear problem with this, is that if you want to insert text,  and the text
--  is already cut up, then you're going to push text past  the  255-character 
--  limit and some is going to get cut off.
-- 
-- There are also a number of other events that Gopher exposes for your
--  consumption.
-------------------------------------------------------------------------------
-- CHAT EVENTS
--
-- Callback function signature for these is 
--                  `( event, text, chat_type, arg3, target )`
--
-- These are similar to what you might see passed to SendChatMessage.
--   event     Gopher event name. e.g. CHAT_NEW, CHAT_QUEUE...
--   text      Message text.
--   chat_type "SAY", "EMOTE",  etc.,  also  includes custom types  "BNET"  and
--              "CLUB".  You  should  also  watch  out  for  third-party addons
--              (Cross RP) that  add  custom  chat types like  "RP", "RP2" etc.
--   arg3      Language ID, club ID, or unused.
--   target    A channel anme, a  whisper target, bnetAccountID, stream ID,  or
--              unused.
--
-- Return `false` from  your callback to block the  message from being sent--to
--    discard it.  Return nil to do nothing, and let  the message pass through.
--   Otherwise,  `return text, chat_type, arg3, target`   to  modify  the  chat
--    message.  Take extra  care to make sure that you're only setting these to
--    valid values.
--
-- CHAT_NEW is when Gopher starts processing a  new message.  This is  when the
--  message is fresh from SendChatMessage and no operations have been done with
--  it yet. This event is skipped when Gopher is "suppressed".
--
-- CHAT_QUEUE is when the chat system is about  to  queue  a  message which has
--  gone through the cutter and other processes. 
--
-- CHAT_POSTQUEUE is after the message is queued, and meant for post-hooks that
--  trigger after  the queue call.  This one cannot modify  the message and the
--  return values are ignored.
--
-------------------------------------------------------------------------------
-- SEND QUEUE EVENTS
--
-- SEND_START is when  the  chat system  becomes active and  is  trying to send
--  messages and empty  the queue.  It's paired with SEND_DONE when  the system
--  goes back to being idle. No extra callback arguments.
--
-- SEND_FAIL is when the chat system detects a server throttle failure or such,
--  and it will be working to recover or re-send.
--
--     Args: ( event, text, chat_type, arg3, target )
--
-- SEND_RECOVER is when the chat queue is done waiting to retry after a failure
--  and is starting back up again. No extra callback arguments.
--
-- SEND_CONFIRMED  is  when the chat system sees  a  chat event from the server
--  and has  confirmed one  of  your messages going through.  The callback args
--  describe the message that was confirmed.  This is only triggered for queued
--  types, and not private types like WHISPER or RAID.
--
--     Args: ( event, text, chat_type, arg3, target )
--
-- SEND_DEATH is  when  the  chat system times  out  from  an  error or extreme
--  latency, and cancels everything.  It's unsure whether  or  not  the current
--  message will be going through. Gopher passes its pending chat queue to this
--  event before it wipes it.
--
--     Args: ( event, chat_queue )
--
-- SEND_DONE is when the chat system  is done sending  any pending messages and
--  goes back to being idle. No extra callback arguments.
--
-------------------------------------------------------------------------------
-- THROTTLER EVENTS
--
-- THROTTLER_START  is  when the outgoing chat throttler inserts a delay to not
--  overrun bandwidth. No extra callback arguments.
--
-- THROTTLER_STOP is when the chat throttler empties its queue.  This  is  only
--  triggered if it had to wait.  It's not triggered  if  all messages are sent
--  instantly. No extra callback arguments.
--
-- Returns `true` if the hook was added, and `false` if it already exists.
--
-------------------------------------------------------------------------------
-- success = Gopher.Listen( event, callback )
--
-- Listen for  a  Gopher event.  Returns true  on  success,  false  if  already
--  listening.
--
Gopher.Listen = Internal.Listen

-------------------------------------------------------------------------------
-- success = Gopher.StopListening( event, callback )
--
-- Stop listening  to an event.  Removes `callback`  from  this event's handler
--      list. Returns true on success, false if the callback wasn't registered.
Gopher.StopListening = Internal.StopListening

-------------------------------------------------------------------------------
-- handler_list = Gopher.GetEventListeners( event )
--
-- You  can  also view the list  of  event listeners  with this. This returns a
--  direct reference  to the internal table which shouldn't be touched from the
--  outside. Use with caution.  Other addons might not expect you to be messing
--                                                        with their functions.
Gopher.GetEventListeners = Internal.GetEventHooks

-------------------------------------------------------------------------------
-- Gopher.AddChatFromNewEvent( msg, chat_type, arg3, target )
--
-- Sends chat from inside one of the CHAT_NEW handlers.  This  should  only  be
--  used from "CHAT_NEW" listeners.
--
-- `msg`, `chat_type`, `arg3`, `target`: The new chat message.
--
-- For whatever reason,  we  have this special API  so  that CHAT_NEW listeners
--  can spawn  new messages.  Presumably, they're  discarding  the original, or
--  they're attaching some metadata that's whispered or something.
-- Very weird uses, but this is literally just for Tongues.
-- Chat messages that are spawned using this do  not  go  through your CHAT_NEW
--  event listener twice. When they're processed, the filter list resumes right
--  after where yours was.
-- If  you  DO  want to make  a  completely fresh message that goes through the
--       entire chain again, just make a direct call to the Blizzard functions.
Gopher.AddChatFromNewEvent = Internal.AddChatFromStartEvent

-------------------------------------------------------------------------------
-- Gopher.Suppress()
--
-- Disables the chat filters for the next chat message.
--
-- Sometimes you  might want  to send  a  chat message  that  bypasses Gopher's
--  filters. This is dangerous, and you should know what you're doing.
-- Basically,  it's for  funky protocol stuff where you don't want your message
--  to be touched, or even cut up.  You'll  get  errors  if  you  try  to  send
--  messages too big.
-- Messages that bypass the splitter still  go  through  Gopher's  queue system
--  with all guarantee's attached. CHAT_NEW is skipped, but QUEUE and POSTQUEUE
--  still trigger.
-- Calling  this affects  the  next intercepted chat message only  and  then it
--                                                               resets itself.
Gopher.Suppress = Internal.Suppress

-------------------------------------------------------------------------------
-- Gopher.PauseQueue()
--
-- This lets you pause the  chat queue  so  you can load  it up  with  messages
--  first, mainly for you to insert different priorities without the lower ones
--  firing  before  you're  done  feeding the queue.  This automatically resets
--  itself,  and you need to call  it  for each message added.  Call StartQueue
--                                            when you're done adding messages.
Gopher.PauseQueue = Internal.PauseQueue

-------------------------------------------------------------------------------
-- Gopher.SetTrafficPriority( priority )
-- priority = Gopher.GetTrafficPriority()
--
-- priority: What priority to use for the next intercepted chat message. Higher
--            numbers are sent later than lower numbers.
--
-- This is a feature added  mainly for Cross RP,  to  keep the text  protocol's
--  traffic away from clogging chat text from going through. Higher numbers are
--  always sent after lower priority numbers. (1 is highest priority.)
-- If you're  just  sending chat,  you likely  won't ever need  this. It's also
--  automatically reset after sending a chat message, and you  need to  call it
--  each time you want to send a low  priority  message. More  importantly, you
--           don't need to worry about resetting it back to what it was before.
Gopher.SetTrafficPriority = Internal.SetTrafficPriority
Gopher.GetTrafficPriority = Internal.GetTrafficPriority

-------------------------------------------------------------------------------
-- Gopher.QueueBreak( priority )
--
-- Inserts a BREAK into the queue. Breaks are special messages that don't allow
--  grouping across themselves. These have  limited purpose, but Cross RP  uses
--  them to group messages together with the club channels.
--
-- `priority` is where the break will be inserted, what traffic priority.
--  Defaults to 1, which is most likely always what you want.
--
-- Examples:
--   SAY   HELLO         \ Sent together, as they're different channels.
--   CLUB  RELAY_HELLO   /
--   CLUB  SOMETHING     \ Sent together with next batch.
--   SAY   HELLO         / 
--   CLUB  RELAY_HELLO   - This RELAY message is sent too late, and by itself.
--
--   SAY   HELLO         \ Sent together, as they're different channels.
--   CLUB  RELAY_HELLO   /
--   CLUB  SOMETHING     \ Tries to send together with next batch.
--   BREAK               -- CUTS grouping.
--   SAY   HELLO         \ Sent together properly.
--   CLUB  RELAY_HELLO   /
--
-- This may have more uses in the future. Another example.
--   SAY   HELLO        -> Sent on first batch.
--   BREAK              -> Waits for message confirmation.
--   CLUB  YES          -> Sent in order one after another.
--   CLUB  YES          -
--   CLUB  YES          - If the break wasn't there, all of these could be sent
--   CLUB  YES          -  while  that  important  HELLO  up  there  was  still
--                      -  pending. See?
--
-- What  BREAK  also  does  is  waits for  the throttler  to catch up  on BURST
--  bandwidth, essentially making it guaranteed that you're going to be sending
--  your grouped messages in a tight pair.
--
Gopher.QueueBreak = Internal.QueueBreak

-------------------------------------------------------------------------------
-- Gopher.SetChunkSizeOverride( string chat_type, int chunk_size )
--
-- chat_type: "SAY", "EMOTE", "BNET", etc.
-- chunk_size: How many  characters to  allow  in  each  chunk  when cutting up
--              messages of this type.
-- Causes  Gopher  to use this chunk size when cutting up messages of this chat
--  type.
-- Pass nil as size to remove an override.
-- Pass "OTHER" as the `chat_type` to override all default settings.
-- Chunk size is computed as:
--  `overrides[type] or defaults[type] or overrides.OTHER or defaults.OTHER`
-- `defaults` is the internal default chunk sizes.
--
Gopher.SetChunkSizeOverride = Internal.SetChunkSizeOverride

-------------------------------------------------------------------------------
-- Gopher.SetTempChunkSize( int chunk_size )
--
-- chunk_size: How many characters allowed  in  the chunks for the next message
--              intercepted.
--
-- This is a  global  override for  chunk size. It applies  to  the  next  chat
--  message only and does not need to be reset.
Gopher.SetTempChunkSize = Internal.SetTempChunkSize

-------------------------------------------------------------------------------
-- Gopher.SetSplitmarks( start, end, [bool sticky] )
-- start, end = Gopher.GetSplitmarks( [bool sticky] )
--
-- Sets the marks that appear at the start or end of chunks that signal a split
--  in the message.
--
-- start: Text to prefix chunks that continue the previous.
-- end: Text to append to chunks that are continued in the next one.
-- sticky: If true, this will persist for  all future messages. If false,  this
--          call will only apply to the next chat message.
-- Pass `nil` to start or end to ignore the value. Pass  `false` to remove  the
--  setting.
--
Gopher.SetSplitmarks = Internal.SetSplitmarks
Gopher.GetSplitmarks = Internal.GetSplitmarks

-------------------------------------------------------------------------------
-- Gopher.SetPadding( prefix, suffix )
-- prefix, suffix = Gopher.GetPadding()
-- 
-- This  controls  adding  a prefix or  suffix to any  chunk  outputted through
--  Gopher.  For  example, if you  set  prefix to "|| "  and then  send a  long
--  message, all of the chunks will start with "|| ".
--
-- This applies to the next chat message only, and you don't need to reset it.
-- If you do want to reset it, pass `false`, `nil` makes the argument ignored.
--
Gopher.SetPadding = Internal.SetPadding
Gopher.GetPadding = Internal.GetPadding

-------------------------------------------------------------------------------
-- Gopher.StartQueue()
-- 
-- Starts the  chat  queue. Call this after you  send chat messages if you used
--  PauseQueue.
--
Gopher.StartQueue = Internal.StartQueue

-------------------------------------------------------------------------------
-- busy = Gopher.AnyChannelsBusy()
-- busy = Gopher.AllChannelsBusy()
-- busy = Gopher.SendingActive()
-- 
-- Returns true if any or all of the chat queue channels  are busy waiting  for
--  a chat  message  to  be confirmed. Both  of  these might  return  false (if
--  waiting for a break or something), but SendingActive will still return true
--  if the queue isn't empty and is active.
--
Gopher.AnyChannelsBusy = Internal.AnyChannelsBusy
Gopher.AllChannelsBusy = Internal.AllChannelsBusy
Gopher.SendingActive   = Internal.SendingActive

-------------------------------------------------------------------------------
-- latency = Gopher.GetLatency()
--
-- Returns the latency value Gopher has recorded (seconds).
--
Gopher.GetLatency = Internal.GetLatency

-------------------------------------------------------------------------------
-- health = Gopher.ThrottlerHealth()
--
-- Returns what % of bandwidth is currently available.
--
-- When InCombatLockdown() this will return a max of 50.
--
Gopher.ThrottlerHealth = Internal.ThrottlerHealth

-------------------------------------------------------------------------------
-- active = Gopher.ThrottlerActive()
--
-- Returns true if the chat throttler is currently waiting through a delay.
--
Gopher.ThrottlerActive = Internal.ThrottlerActive

-------------------------------------------------------------------------------
-- Gopher.HideFailureMessages( hide )
-- 
-- Pass true to suppress the system messages when your chat is throttled by the
--  server. This is on by default,  and usually  only turned off for diagnostic
--  purposes.
--
Gopher.HideFailureMessages = Internal.HideFailureMessages

-------------------------------------------------------------------------------
-- Gopher.AddMetadata( prefix, text, [perchunk] )
-- Gopher.AddMetadata( function, arg, [perchunk] )
--
-- Certain messages  can have  metadata attached.  This should only be used for
--  non-queued types that are guaranteed to go through  such as normal whispers
--  and party chat. `prefix`  is the addon data prefix used. `text` is the text
--  to send (which must be 255 bytes or less).
-- Basically  these args  are passed  to  SendAddonMessage, with the `kind` and
--  `target` fields of that matching the SendChatMessage arguments used.
-- This data  will always  be  received before the other end processes the chat
--  message that's attached to it. `perchunk`  will make it so that the data is
--  duplicated/re-sent  for  each chunk  delivered.  If it's  not set, then the
--  metadata will only be sent once, for the very next chunk.
-- Example, with perchunk set for a message that's split  into two  chunks, the
--  events will look like this:
--    CHAT_MSG_ADDON (metadata)
--    CHAT_MSG_RAID  (message chunk 1)
--    CHAT_MSG_ADDON (same metadata) <- omitted if perchunk is false
--    CHAT_MSG_RAID  (message chunk 2)
-- The reason this function exists is for coupling the data like that.
--  SendChatMessage  is  hooked  and  throttled, so  it's not guaranteed that a
--  normal  SendAddonMessage  call  will  actually  be  called right before the
--  desired SendChatMessage call to couple the data together.
-- For example:
--     SendChatMessage( "hello", "RAID" )
--     SendAddonMessage( "prefix1", "secret data", "RAID" )
--     SendChatMessage( "world", "RAID" )
--   On the receiving end, the events might look like
--     CHAT_MSG_ADDON ("prefix1", "secret data")
--     CHAT_MSG_RAID ("hello")
--     CHAT_MSG_RAID ("world")
--   due to the first RAID message being queued when the throttler is busy.
--   For the desired result of having the metadata attached to a  raid message,
--    it should look like this:
--     SendChatMessage( "hello", "RAID" )
--     Gopher.AddMetadata( "prefix1", "secret data" )
--     SendChatMessage( "world", "RAID" )
--   The metadata will automatically copy the  next chat message's distribution
--    type.
-- If  a  `function`  is  specified,   then   Gopher   doesn't   actually   use
--  SendAddonMessage, and instead calls this function, assuming that it will do
--  so. This function should return how many bytes of data are sent, for proper
--  load throttling. Note that the function is called with pcall, and to debug,
--                                              you need to use Gopher.Debug().
Gopher.AddMetadata = Internal.AddMetadata

-------------------------------------------------------------------------------
-- Gopher.Timer_Start( slot, mode, period, func, ... )
-- Gopher.Timer_Cancel( slot )
--
-- Gopher's timer helpers. These  are useful for a good number of applications,
--  with semi-automatic handling for canceling and updating timers. 
-- Timer_Cancel will stop any existing timer slot from triggering.
--
-- slot: A string that identifies this timer "channel".
-- mode: How this timer works  or reacts to  additional  start  calls when it's
--        already ticking.
--   "push" = Cancel existing slot and wait for the new period to expire.
--            (i.e. "push back execution")
--   "ignore" = Ignore any new start calls if the slot is ticking arleady.
--   "duplicate" = Forget previous timer, leave it running, and make a  new one
--                  You can't cancel forgotten timers.
--   "cooldown" = This triggers instantly and sets a cooldown. Additional calls
--                 during the cooldown period are merged into a single  call at
--                 the end of the cooldonw period. This  may trigger inside the
--                 Timer_Start call as it can bypass C_Timer.After.
-- period: Period  in seconds when  the  timer will trigger. Tiny  values  will
--          always trigger on the next frame, unless using "cooldown" mode.
-- func: Timer callback function.
-- ...: Passed to the timer callback function.
--
Gopher.Timer_Start  = Internal.Timer_Start
Gopher.Timer_Cancel = Internal.Timer_Cancel

-------------------------------------------------------------------------------
-- Enable or  disable debug mode,  which causes  some debug information  to  be
--                      printed to chat, including errors from event listeners.
function Gopher.Debug( setting )
	if setting == nil then setting = true end
	if setting == false then setting = nil end
	Gopher.Internal.debug_mode = true
end

--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~