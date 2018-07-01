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
--      messages and lazily verifying the response from the server.
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

local PLAYER_GUID = UnitGUID("player")

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

------------------------------------------------------------------------------
-- Here's our simple chat-queue system. 
--
-- Firstly we have the actual queue. This table contains the user's queued
--  chat messages they want to send.
--
-- Each entry has these fields. Note that these are the same arguments you'd
--  pass to SendChatMessage.
--    msg: The message text.
--    type: "SAY" or "EMOTE" etc.
--    arg3: Language index or club ID.
--    target: Channel, whisper target, BNet presence ID, or club stream ID.
--
Me.chat_queue = {} -- This is a FIFO, first-in-first-out, 
                   --  queue[1] is the first to go.
                   --
-- This is a flag that tells us when the chat-queue system is busy. Or in
--  other words, it tells us when we're waiting on confirmation for our 
Me.chat_busy   = false -- messages being sent. This isn't used for messages
                       --  not queued (party/raid/whisper etc).
-------------------------------------------------------------------------------
-- This is a collection of functions that can be added by other third parties 
--  to process messages before they're sent. It's much cleaner or safer to do 
--  that with these rather than them hooking SendChatMessage directly, since 
--  it will be undefined if their hook fires before or after the message is
Me.chat_hooks = {    -- cut up by our functions. We have a few hook points
	START     = {};  --  here. One before everything. One before it's queued
	QUEUE     = {};  --  and one more post-queue. You can't modify or stop
	POSTQUEUE = {};  --  messages in the POSTQUEUE hook.
}
Me.hook_stack = {} -- Our stack for hooks in case we're nesting things with
                   --  SendChatFromHook.
-------------------------------------------------------------------------------
-- We count failures when we get a chat error. Some of the errors we get
--  (particularly from the communities API) are vague, and we don't really
--  know if we should keep re-sending. This limit is to stop resending after
Me.failures = 0                                --  so many of those errors.
local FAILURE_LIMIT = 5                        --
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
local CHAT_TIMEOUT = 10.0                          -- community messages.
local CHAT_THROTTLE_WAIT = 3.0
-------------------------------------------------------------------------------
-- We need to get a little bit creative when determining whether or not
-- something is an organic call to the WoW API or if we're coming from our own
-- system. For normal chat messages, we hide a little flag in the channel
-- argument ("#ES"); for Battle.net whispers, we hide this flag as an offset
-- to the presenceID. If the presenceID is >= this constant, then we're in the
local BNET_FLAG_OFFSET = 100000 -- throttler's message loop. Otherwise, we're
                                -- handling an organic call.

-------------------------------------------------------------------------------
-- Normally this isn't touched. This was a special request from someone who
--  was having trouble using the stupid addon Tongues. Basically, this is used
--  to limit how much text can be sent in a single message, so then Tongues can
Me.max_message_length = 255 -- have some extra room to work with, making the 
                            --  message longer and such. It's wasteful, but
                            --                                    it works.
-------------------------------------------------------------------------------
-- Patch 8.0 gives us some more values here. From testing, the community API
--  lets you send messages that are as long as 4000 characters. The textboxes
--  are still limited to 255 characters, but we bump this up to a nice 400
--  characters per message. If you have too big of a value, then it just makes
--  the user interface unmanagable, since you cannot partially scroll past one
--  of the messages. Each message is one scroll tick.
-- This is also a thing with BNet whispers. I'm not 100% sure what the limit is
--  for those, but it's not as low as 255.
Me.club_chunk_size  = 400
Me.bnet_chunk_size  = 400
Me.guild_chunk_size = 400
-------------------------------------------------------------------------------
-- And finally... any chat type keys found in here will override the chunk
--  size for a certain chat type. This is used by RP Link, for custom chat
--  types that split on the 400 mark.
Me.chunk_size_overrides = {}
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
-- A lot of these definitions used to be straight local variables, but this is
--  a little bit cleaner, keeping things inside of this "Me" table, as well
--  as exposing it to the outside so we can do some easier diagnostics in case
--  something goes wrong down the line. Another great plus to exposing
--  everything like this is that other addons can see what we're doing. Sure,
--  the proper way is to make an API for something, but when it comes to the
--  modding scene, things can get pretty hacky, and it helps a bit to allow
--  others to mess with your code from the outside if they need to.
-------------------------------------------------------------------------------
-- We don't really need this but define it for good measure. Called when the
function Me:OnInitialize() end -- addon is first loaded by the game client.

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
		Me.max_message_length = v  -- ignore and report spam features are for,
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
	
	PLAYER_GUID = UnitGUID( "player" ) -- Just in case...
	
	-- Some miscellaneous things here.
	-- See options.lua. This is initializing our configuration database, so 
	Me.Options_Init() -- it's needed before we can access Me.db.etc.
	
	-- Adding slash commands to the game is fairly straightforward. First you
	--  add a function to the SlashCmdList table, and then you assign the 
	--  command to the global SLASH_XYZ1. You can add more aliases with 
	SLASH_EMOTESPLITTER1 = "/emotesplitter" -- SLASH_XYZ2 or SLASH_XYZ3 etc.
	
	-- Message hooking. These first ones are the public message types that we
	--  want to hook for confirmation. They're the ones that can error out if
	--                           they're hit randomly by the server throttle.
	Me:RegisterEvent( "CHAT_MSG_SAY", function( ... )
		-- We're only interested in a couple of things, and that's the message
		-- type, and the user GUID. Param13 of ... is GUID.
		Me.TryConfirm( "SAY", select( 13, ... ))
	end)
	Me:RegisterEvent( "CHAT_MSG_EMOTE", function( ... )
		Me.TryConfirm( "EMOTE", select( 13, ... ))
	end)
	Me:RegisterEvent( "CHAT_MSG_YELL", function( ... )
		Me.TryConfirm( "YELL", select( 13, ... ))
	end)
	if C_Club then -- 7.x compat
		-- In 8.0, GUILD and OFFICER chat are no longer normie communication
		--  channels. They're just routed into the community API internally.
		-- The worst part about this is that they still show up (as of writing)
		--  as CHAT_MSG_GUILD or CHAT_MSG_OFFICER and don't show any sort of
		--  indication of what channel within the guild they're from.
		Me:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL", Me.OnChatMsgCommunitiesChannel )
		Me:RegisterEvent( "CHAT_MSG_GUILD", Me.OnChatMsgGuildOfficer )
		Me:RegisterEvent( "CHAT_MSG_OFFICER", Me.OnChatMsgGuildOfficer )
		Me:RegisterEvent( "CLUB_ERROR", Me.OnClubError )
	end
	-- Battle.net whispers aren't affected by the server throttler, but they
	--  can still appear out of order if multiple are sent at once, so we send
	--  them "safely" too.
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM", function()
		Me.TryConfirm( "BNET", PLAYER_GUID )
	end)
	
	-- This bug hasn't been fixed for a while. I didn't even know they had a
	--  dedicated message for this.
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE", 
	                  Me.OnChatMsgBnOffline )
	
	-- And finally we hook the system chat events, so we can catch when the
	--                         system tells us that a message failed to send.
	Me:RegisterEvent( "CHAT_MSG_SYSTEM", Me.OnChatMsgSystem )
	
	-- Here's our main chat hooks for splitting messages.
	-- Using AceHook, a "raw" hook is when you completely replace the original
	--  function. Your callback fires when they try to call it, and it's up to
	--  you to call the original function which is stored as 
	--  `Me.hooks.FunctionName`. In other words, it's a pre-hook that can
	Me:RawHook( "SendChatMessage", Me.SendChatMessageHook, true ) -- modify or cancel the result.
	Me:RawHook( "BNSendWhisper", Me.BNSendWhisperHook, true  )   -- 
	if C_Club then -- 7.x compat
		Me:RawHook( C_Club, "SendMessage", Me.ClubSendMessageHook, true )   -- 
	end
	-- And here's a normal hook. It's still a pre-hook, in that it's called
	--  before the original function, but it can't cancel or modify the
	Me:Hook( "ChatEdit_OnShow", true ) -- arguments.
	
	-- We're unlocking the chat editboxes here. This may be redundant, because
	--  we also do it in the hook when the editbox shows, but it's for extra
	--  good measure - make sure that we are getting these unlocked. Some
	--  strange addon might even copy these values before the frame is even
	for i = 1, NUM_CHAT_WINDOWS do  -- shown... right?
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
	
	-- Here's where we add the feature to hide the failure messages in the
	-- chat frames, the failure messages that the system sends when your
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM", -- chat gets
		function( _, _, msg, sender )                   --  throttled.
			-- Someone might argue that we shouldn't hook this event at all
			--  if someone has this feature disabled, but let's be real;
			--  99% of people aren't going to turn this off anyway.
			if Me.db.global.hidefailed --> "Hide Failure Messages" option
			   and msg == ERR_CHAT_THROTTLED --> The localized string.
			   and sender == "" then --> Extra event verification.
			                         -- (System has sender as "").
				-- Returning true from these callbacks block the message
				return true -- from showing up.
			end
		end)
	
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
	
	---------------------------------------------------------------------------
	-- And now our compatibility code.
	---------------------------------------------------------------------------
	Me.MisspelledCompatibility()
	Me.TonguesCompatibility()
end

-------------------------------------------------------------------------------
-- This is our hook for when a chat editbox is opened. Or in other words, when
function Me:ChatEdit_OnShow( editbox ) -- someone is about to type!
	editbox:SetMaxLetters( 0 ); -- We're just removing the limit again here.
	editbox:SetMaxBytes( 0 );   -- Extra prudency, in case some rogue addon, or
	                            --  even the Blizzard UI, messes with it.
	if editbox.SetVisibleTextByteLimit then  -- 7.x compat
		editbox:SetVisibleTextByteLimit( 0 ) --
	end										 --
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
-- Emote Splitter supports chat hooks which are used during calls to
--  SendChatMessage. They're used to monitor or adjust text that's sent by the
--  user at different points throughout our system.
-- 
-- The reason for this is to avoid any more hooking of the SendChatMessage
--  function itself. Normally an addon would hook SendChatMessage if they want
--  to insert something (like replacing a certain keyword on the way out, or
--  removing text) but with Emote Splitter you don't know if you're going to
--  get your hook called before OR after the text is split up into smaller
--  sections. A clear problem with this, is that if you want to insert text,
--  and the emote is already cut up, then you're going to push text past the
--  255-character limit and some is going to get cut off.
-- 
-- The signature for the callback function (func) is:
--
--   function( text, chat_type, arg3, target )
--
-- Arguments passed to it are fairly straightforward, and the same are
--  passed to SendChatMessage.
--
--   text:      The message text.
--   chat_type: "SAY", "EMOTE" etc, also includes our custom 
--               types "BNET", "CLUB".
--   arg3:      Language ID (a number), or club ID
--   target:    Depending on chat_type this is either a channel name, a
--               whisper target, a presence ID, or a community stream ID.
--
--   Return false from this function to block the message from being sent--to
--    discard it. Return nil to do nothing, and let the message pass through.
--   Otherwise, `return text, chat_type, arg3, target` to modify the chat
--    message. Take extra care to make sure that you're only setting these to
--    valid values.
--
-- `point` is where you will hook the system. This can be:
-- "START" - Hook at the start, the message is raw and hasn't been cut up yet.
-- "QUEUE" - Called before the message is about to be queued. This is a cut
--            and primped message and this hook may trigger multiple times
--            for a single longer message.
-- "POSTQUEUE" - Called right after the message is queued. Sometimes ordering
--                matters. You can't cancel or change the message from in
--                here, and return values are ignored.
--
-- Returns true if the filter was added, and false if it already exists.
--
function Me.AddChatHook( point, func )
	if not Me.chat_hooks[point] then
		error( "Unknown chat hook point." )
	end
	
	if FindTableValue( Me.chat_hooks[point], func ) then
		return false
	end
	
	table.insert( Me.chat_hooks[point], func )
	return true
end

-------------------------------------------------------------------------------
-- You can also easily remove chat hooks with this. Just pass in your args that
--  you gave to AddChatHook.
--
-- Returns true if the filter was removed, and false if it wasn't found.
--
function Me.RemoveChatHook( point, func )
	if not Me.chat_hooks[point] then
		error( "Unknown chat hook point." )
	end
	
	local index = FindTableValue( Me.chat_hooks[point], func )
	if index then
		table.remove( Me.chat_hooks[point], index )
		return true
	end
	
	return false
end

-------------------------------------------------------------------------------
-- You can also view the list of chat filters with this. This returns a direct
--  reference to the internal table which shouldn't be touched from the 
--  outside. This might seem like an unnecessary API feature, but someone might
function Me.GetChatHooks( point ) -- write something that 'previews' outgoing
	return Me.chat_hooks[point]   -- messages, and would use this to apply the    
end                            -- chat filters themselves and see how it works 
                              -- out.
-------------------------------------------------------------------------------
-- Okay, now for WHATEVER reason, a filter function can dispatch new chat
--  messages entirely. Presumably, they're discarding the original.
-- Typical use is returning `false` from their filter function, after calling
--  this multiple times to split the chat message into multiple ones. They
--  can keep the original too if they want, and use this to send metadata or
--  something.
-- Chat messages that are spawned using this do not go through your message
--  filter twice. When they're processed, the filter list resumes right after
--  where yours was.
-- If you DO want to make a completely fresh message that goes through the
--  entire chain again, just make a direct call to ProcessIncomingChat.
-- Look, just use your imagination. This is literally for our broken af 
--  Tongues compatibility layer.
--
-- msg, chat_type, arg3, target: The new chat message.
--
-- This should only be used from "START" hooks.
--
function Me.SendChatFromHook( msg, chat_type, arg3, target )
	local filter_index = 0
	local filter = Me.hook_stack[#Me.hook_stack]
	if filter then
		for k,v in pairs( Me.chat_hooks["START"] ) do
			if v == filter then
				filter_index = k
				break
			end
		end
	end
	
	Me.ProcessIncomingChat( msg, chat_type, arg3, target, filter_index + 1 )
end

-------------------------------------------------------------------------------
-- Sometimes you might want to send a chat message that bypasses 
--  Emote Splitter's filters. This is dangerous, and you should know what 
--  you're doing.
-- Basically, it's for funky protocol stuff where you don't want your message
--  to be touched, or even cut up. You'll get errors if you try to send
--  messages too big on the normal channels.
-- Messages that bypass the splitter still go through Emote Splitter's queue
--  system.
function Me.Suppress()
	Me.suppress = true
end

-------------------------------------------------------------------------------
-- Causes Emote Splitter to use this chunk size when cutting up messages of
--  this chat type.
-- Pass nil as size to remove an override.
--
function Me.SetChunkSizeOverride( chat_type, chunk_size )
	Me.chunk_size_overrides[chat_type] = chunk_size
end

-------------------------------------------------------------------------------
-- Function for splitting text on newlines or newline markers (literal "\n").
--
-- Returns a table of lines found in the text {line1, line2, ...}. Doesn't 
--  include any newline characters or marks in the results. If there aren't any
--  newlines, then this is going to just return { text }.
--                               --
function Me.SplitLines( text )   --
	-- We still want to send empty messages for AFK, DND, etc.
	if text == "" then return {""} end
	-- We merge "\n" into LF too. This might seem a little bit unwieldy, right?
	-- Like, you're wondering what if the user pastes something
	--  like C:\nothing\etc... into their chatbox to send to someone. It'll be
	--          ^---.
	--  caught by this and treated like a newline.
	-- Truth is, is that the user can't actually type \n. Even without any
	--  addons, typing "\n" will cut off the rest of your message without 
	--  question. It's just a quirk in the API. Probably some security measure
	--  or some such for prudency? We're just making use of that quirk so
	--                             -- people can easily type a newline mark.
	text = text:gsub( "\\n", "\n" ) --
	                                --
	-- It's pretty straightforward to split the message now, we just use a 
	local lines = {}                        -- simple pattern and toss it 
	for line in text:gmatch( "[^\n]+" ) do  --  into a table.
		table.insert( lines, line )         --
	end                                     --
	                                        --
	-- We used to handle this a bit differently, which was pretty nasty in
	--  regard to chat filters and such. It's a /little/ more complex now,
	return lines -- but a much better solution in the end.
end

-------------------------------------------------------------------------------
-- Our hooks just basically do some routing, rearrange the parameters for our
-- main ProcessIncomingChat function.
--
function Me.SendChatMessageHook( msg, chat_type, language, channel )
	print( msg, "-", chat_type, "-", language, "-", channel )
	Me.ProcessIncomingChat( msg, chat_type, language, channel )
end

function Me.BNSendWhisperHook( presence_id, message_text ) 
	Me.ProcessIncomingChat( message_text, "BNET", nil, presence_id )
end

function Me.ClubSendMessageHook( club_id, stream_id, message )
	Me.ProcessIncomingChat( message, "CLUB", club_id, stream_id )
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

function Me.ExecuteHooks( point, a, b, c, d, start )
	start = start or 1
	for index = start, #Me.chat_hooks[point] do
		table.insert( Me.hook_stack, Me.chat_hooks[point][index] )
		local a2, b2, c2, d2 = Me.chat_hooks[point][index]( a, b, c, d )
		table.remove( Me.hook_stack )
		-- If a chat hook returns `false` then we cancel this message. 
		if a2 == false then
			return false
		elseif a2 then
			-- Otherwise, if it's non-nil, we assume that they're changing
			--  the arguments on their end, so we replace them with the
			a, b, c, d = a2, b2, c2, d2 -- return values.
		end
		-- If the hook returned nil, then we don't do anything to the
		--  message.
	end
	return a, b, c, d
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
function Me.ProcessIncomingChat( msg, chat_type, arg3, target, hook_start )
	if Me.suppress then
		-- We don't touch suppressed messages.
		Me.suppress = false
		Me.ExecuteHooks( "QUEUE", msg, chat_type, arg3, target )
		Me.QueueChat( msg, chat_type, arg3, target )
		Me.ExecuteHooks( "POSTQUEUE", msg, chat_type, arg3, target )
		return
	end
	
	msg = tostring(msg or "")
	
	msg, chat_type, arg3, target = 
		Me.ExecuteHooks( "START", msg, chat_type, arg3, target, hook_start )
	if msg == false then return end
	
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
	local chunk_size = Me.max_message_length
	if chat_type == "CHANNEL" then
		-- Chat type CHANNEL can either be a normal legacy chat channel, or the
		--  user can be typing in a chat channel that's linked to a community
		--  channel. This is only done through the normal chatbox. If you type
		--  in the community panel, it goes straight to C_Club:SendMessage.
		local _, channel_name = GetChannelName( target )
		if channel_name then
			-- GetChannelName returns a specific string for club channels:
			--   Community:<club ID>:<stream ID>
			local club_id, stream_id = channel_name:match( "Community:(%d+):(%d+)" )
			if club_id then
				-- This is a community message, reroute this message to use
				--  C_Club directly...
				chat_type  = "CLUB"
				arg3       = club_id
				target     = stream_id
				chunk_size = Me.club_chunk_size
			end
		end
	elseif chat_type == "GUILD" or chat_type == "OFFICER" then
		-- For GUILD and OFFICER, we want to reroute these too to use the
		--  Club API so we can take advantage of it just like we do with
		--  channels. GUILD and OFFICER are already using the Club API
		--  internally at some point, and guilds have their own club ID
		--  and streams.
		if C_Club then -- 7.x compat
			local club_id, stream_id = 
				GetGuildStream( chat_type == "GUILD" 
									and Enum.ClubStreamType.Guild 
									or Enum.ClubStreamType.Officer )
			if not club_id then
				-- The client right now doesn't actually print this message, so
				--  we're helping it out a little bit. If it does start printing
				--  it on its own, then remove this.
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
			chunk_size = Me.guild_chunk_size
		end
	elseif chat_type == "BNET" then
		-- BNet messages also have an increased max-message-length. I
		--  wonder when they might extend this limit in SendChatMessage.
		chunk_size = Me.bnet_chunk_size
	elseif chat_type == "CLUB" then
		-- If we reach here, this message is from typing directly in the
		--  communities panel.
		chunk_size = Me.club_chunk_size
	end
	
	local chunk_size_override = Me.chunk_size_overrides[chat_type]
	if chunk_size_override then chunk_size = chunk_size_override end
	
	-- And we iterate over each, pass them to our main splitting function 
	--  (the one that cuts them to smaller chunks), and then feed them off
	--  to our main chat queue system. That call might even bypass our queue
	--  or the throttler, and directly send the message if the conditions
	--  are right. But, otherwise this message has to wait its turn.
	for _, line in ipairs( msg ) do
		local chunks = Me.SplitMessage( line, chunk_size )
		for i = 1, #chunks do
			local chunk_msg, chunk_type, chunk_arg3, chunk_target =
				Me.ExecuteHooks( "QUEUE", chunks[i], chat_type, arg3, target )
				print('sending')
			if chunk_msg then
				Me.QueueChat( chunk_msg, chunk_type, chunk_arg3, chunk_target )
				Me.ExecuteHooks( "POSTQUEUE", chunk_msg, chunk_type, chunk_arg3, chunk_target )
			end
		end
	end
end

-------------------------------------------------------------------------------
-- This table contains patterns for strings that we want to keep whole after
--  the message is cut up in SplitMessage. Chat links can have spaces in them
--  but if they're matched by this, then they'll be protected.
local CHAT_REPLACEMENT_PATTERNS = {
	-- The code below only supports 9 of these (because it uses a single digit
	--  to represent them in the text).
	-- Right now we just have this pattern, for catching chat links.
	-- Who knows how the chat function works in WoW, but it has vigorous checks
	--  (apparently) to allow any valid link, along with the exact color code
	--  for them.
	"(|cff[0-9a-f]+|H[^|]+|h[^|]+|h|r)"; -- RegEx's are pretty cool,
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
}

-------------------------------------------------------------------------------
-- Here's our main message splitting function. You pass in text, and it spits
--  out a table of smaller message (or the whole message, if it's small
--                                 -- enough.)
function Me.SplitMessage( text, chunk_size )
	chunk_size = chunk_size or Me.max_message_length
	
	-- For short messages we can not waste any time and return immediately
	if text:len() <= chunk_size then -- if they can fit within a
		return {text}                -- chunk already.
	end	                             -- A nice shortcut.
	
	
	-- Otherwise, we gotta get our hands dirty. We want to preserve links (or
	--  other defined things in the future) from being split apart by the
	--  cutting code below. We do that by turning them to solid strings that
	local replaced_links = {} -- contain an ID code for reversing at the end.
	                          --
	for index, pattern in ipairs( CHAT_REPLACEMENT_PATTERNS ) do
		text = text:gsub( pattern, function( link )
			-- This turns something like "[Chat Link]" into "12x22222223",
			--  essentially obliterating that space in there so this "word"
			--  is kept whole. The x there is used to identify the pattern
			--  that matched it. We save the original text in replaced_links
			--  one on top of the other. The index is used to know which
			--  replacement list to pull from.
			-- replaced_links is a table of lists, and we index it by this `x`.
			-- In here, we just throw it on whichever list this pattern belongs
			replaced_links[index] = replaced_links[index] or {} -- to.
			table.insert( replaced_links[index], link )
			return "\001\002" .. index 
			       .. ("\002"):rep( link:len() - 4 ) .. "\003"
		end)
	end
	
	-- A little bit of preprocessing goes a long way somtimes, like this, where
	--  we add whitespace directly to the premark and postmark rather than
	local premark = Me.db.global.premark  -- applying it separately below in 
	local postmark = Me.db.global.postmark -- the loop.
	if premark ~= "" then            -- If they are empty strings, then they're
		premark = premark .. " "     --  disabled. This all works smoothly
	end                              --  below in the main part.
	if postmark ~= "" then           --
		postmark = " " .. postmark   --
	end                              --
	
	local chunks = {} -- Our collection of text chunks. The return value. We'll
	                  --  fill it with each section that we cut up.
	while( text:len() > chunk_size ) do
		-- While in this loop, we're dealing with `text` that is too big to fit
		--  in a single chunk (max 255 characters or whatever the override is
		--  set to [we'll use the 255 figure everywhere to keep things
		--  simple]).
		-- We actually start our scan at character 256, because when we do the
		--  split, we're excluding that character. Either deleting it, if it's
		--  whitespace, or cutting right before it.
		-- We scan backwards for whitespace or an otherwise suitable place to
		--  break the message.
		for i = chunk_size+1 - postmark:len(), 1, -1 do
			--                          ^^^^^^^^^^^^^^^^
			-- Don't forget to leave some extra room for the postmark.
			local ch = string.byte( text, i )
			
			-- We split on spaces (ascii 32) or a start of a link (inserted
			if ch == 32 or ch == 1 then -- above).
				
				-- If it's a space, then we discard it.
				-- Otherwise we want to preserve this character and keep it in
				local offset = 0                -- the next chunk.
				if ch == 32 then offset = 1 end --
				
				-- An interesting note here is for people who like to do
				--  certain punctuation like ". . ." where you have spaces
				--  between your periods. It's kind of ugly to split on that
				--  but there's a special charcter called "no-break space" that
				--  you can use instead to keep that term a whole word.
				-- I'm considering writing an addon that automatically fixes up
				--  your text with some preferential things like that.
				table.insert( chunks, text:sub( 1, i-1 ) .. postmark )
				text = premark .. text:sub( i+offset )
				break
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
				for i = chunk_size+1 - postmark:len(), 1, -1 do
					local ch = text:byte(i)
					
					-- Now we're searching for any normal ASCII character, or
					--  any start of a UTF-8 character. UTF-8 bit format for 
					--  the first byte in a multi-byte character is always 
					--  `11xxxxxx` the following bytes are all `10xxxxxx`, so
					if (ch >= 32 and ch < 128)  --  our resulting criteria is 
					   or (ch >= 192) then      --  [32-128] and [192+].
						table.insert( chunks, text:sub( 1, i-1 ) .. postmark )
						text = premark .. text:sub( i )
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
				
				break -- <- Make sure that we aren't repeating the outer loop.
			end
		end
	end

	-- `text` is now the final chunk that can fit just fine, so we throw that
	table.insert( chunks, text ) -- in too!
	
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
-- Our simple little thing to handle timeouts for the chat queue. This calls
-- `func` after `delay` seconds, and also has a feature so you can cancel the 
--                                      -- timer. This is designed so you only
function Me.SetChatTimer( func, delay ) --  have one timer running at once. If
	Me.StopChatTimer()                  --  you call this again then it cancels
	                                     -- any existing timer before making a
	local timer = {     -- We're doing a  -- new one.
		cancel = false; --  little bit of closure magic here. I've got mixed
	}                   --  feelings about closures.  One one hand, they're
	                            -- pretty neat; you can do some cool things.
	C_Timer.After( delay, function() -- Lots of things happening in the
		if not timer.cancel then     --  background. On the other hand, they
			func()                 -- may lead to some odd problems, memory
		end                     -- leaks and such, hard to track down. Most of
	end)                      -- the data is invisible and difficult to
	                          -- diagnose.
	Me.chat_timer = timer     --             But hey, they're fun!
end                           --
-------------------------------------------------------------------------------
function Me.StopChatTimer()         -- And to cancel the timer, we just set the
	if Me.chat_timer then           -- cancel flag in the saved timer struct.
		Me.chat_timer.cancel = true --
	end                             --
end                                 --
                                    --								
-------------------------------------------------------------------------------
local QUEUED_TYPES = {  -- These are the types that aren't passed directly to
	SAY     = true;     --  the throttler for output. They're queued and sent
	EMOTE   = true;     --  one at a time, so that we can verify if they went
	CLUB    = true;     --  through or not.
	BNET    = true;     -- We handle GUILD and OFFICER like this too since
	GUILD   = true;     -- they're also treated like club channels in 8.0.
	OFFICER = true;     -- Essentially, anything that can fail from throttle
}                       --  or other issues should be put in here.

-- [[7.x compat]] Remove this after 7.x; we don't handle GUILD/OFFICER like
if not C_Club then             -- this.
	QUEUED_TYPES.GUILD = nil;
	QUEUED_TYPES.OFFICER = nil;
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
	
	local msg_pack = {
		msg    = msg;
		type   = type;
		arg3   = arg3;
		target = target;
	}
	
	-- Now we've got two paths here. One leads to the chat queue, the other
	--  will directly send the messages that don't need to be queued.
	--  SAY, EMOTE, and YELL are affected by the server throttler. BNET isn't,
	--  but we treat it the same way to correct the out-of-order bug.
	if QUEUED_TYPES[type] then        -- (As of writing, I'm assuming
	                                  --  that's still a thing.)
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
		
		-- It looks like we're all good to queue this puppy up and start the
		table.insert( Me.chat_queue, msg_pack )  -- system.
		Me.StartChat()
		
	else -- For other message types like party, raid, whispers, channels, we
		 -- aren't going to be affected by the server throttler, so we go
		Me.CommitChat( msg_pack )  -- straight to putting these
	end                            --  messages out on the line.
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
	if not Me.chat_busy then
		Me.SendingText_Hide()
	end
end

-------------------------------------------------------------------------------
-- Execute the chat queue.
--
function Me.StartChat()
	-- It's safe to call this function whenever for whatever. If the queue is
	--  already started, or if the queue is empty, it does nothing.
	if Me.chat_busy then return end
	if #Me.chat_queue == 0 then return end
	Me.chat_busy = true
	Me.failures = 0
	
	-- I always like APIs that have simple checks like that in place. Sure it
	--  might be a /little/ bit less efficient at times, but the resulting code
	--  on the outside as a result is usually much cleaner. Boilerplate belongs
	--  in the library, right? First thing we do when the system starts is
	--  send the first message in the chat queue. Like this.
	Me.ChatQueue()
end

-------------------------------------------------------------------------------
-- Send the next message in the chat queue.
--
function Me.ChatQueue()
	
	-- This is like the "continue" function for our chat queue system.
	-- First we're checking if we're done. If we are, then the queue goes
	if #Me.chat_queue == 0 then -- back to idle mode.
		Me.chat_busy = false
		Me.SendingText_Hide()
		return 
	end
	
	-- Otherwise, we're gonna send another message. 
	Me.SendingText_ShowSending() 
	
	-- We fetch the first entry in the chat queue and then "commit" it. Once
	--  it's sent like that, we're waiting for an event from the server to 
	--  continue. This can continue in three ways.
	-- (1) We see that our message has been sent, by seeing it mirrored back
	--  from the server, and then we delete this message and send the next
	--  one in the queue.
	-- (2) The server throttles us, and we get an error. We intercept that
	--  error, wait a little bit, and then retry sending this message. This
	--  step can repeat indefinitely, but usually only happens once or twice.
	-- (3) The chat timer below times out before we get any sort of response.
	--  This happens under heavy latency or when something prevents our
	--  message from being sent (and we don't know it). One known case of that
	--  is sending a BNet message to an offline player. It's difficult to 
	local c = Me.chat_queue[1]              -- intercept that sort of failure.
	Me.SetChatTimer( Me.ChatDeath, CHAT_TIMEOUT ) 
	Me.CommitChat( c )
end

-------------------------------------------------------------------------------
-- Timer callback for when chat times out.
--                        -- This is a bit of a fatal error, due to
function Me.ChatDeath()   --  disconnecting or other high latency issues. (Or
	Me.chat_queue = {}    --  some sort of corner case with the chat sending.)
	Me.chat_busy = false
	Me.SendingText_Hide()
	
	-- I feel like we should wrap these types of print calls in something to
	--  standardize the formatting and such.
	print( "|cffff0000<" .. L["Chat failed!"] .. ">|r" )
end

-------------------------------------------------------------------------------
-- These two functions are called from our event handlers. 
-- This one is called when we confirm a message was sent. The other is called
--                            when we see we've gotten a "throttled" error.
-- The `dont_remove` argument means that we have modified the chat_queue
--  outside, and shouldn't do table.remove in here.
function Me.ChatConfirmed( dont_remove )
	
	Me.StopLatencyRecording()
	Me.failures = 0
	
	-- Cancelling either the main 10-second timeout, or the throttled warning
	--  timeout (see below).
	Me.StopChatTimer()               -- Upon success, we just pop the chat
	if not dont_remove then          --  queue and continue as normal.
		table.remove( Me.chat_queue, 1 )
	end
	Me.ChatQueue()
end

-------------------------------------------------------------------------------
-- Upon failure, we wait a little while, and then retry sending the same
function Me.ChatFailed( from_club )                         --  message.
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
	
	-- With the 8.0 update, Emote Splitter also supports communities, which
	--  give a more clear signal that the chat failed that's purely from
	--  the throttler, so we don't account for latency.
	local wait_time
	if from_club then
		wait_time = CHAT_THROTTLE_WAIT
	else
		wait_time = math.min( 10, math.max( 1.5 + Me.GetLatency(), CHAT_THROTTLE_WAIT ))
	end
	
	Me.SetChatTimer( Me.ChatFailedRetry, wait_time )
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
	
	Me.ChatQueue()
end

-------------------------------------------------------------------------------
-- This is called by our chat events, to try and confirm messages that have
-- been commit from our queue.
--
-- kind: Type of chat message the event handles. e.g. SAY, EMOTE, etc.
-- guid: GUID of the player that sent the message.
--
function Me.TryConfirm( kind, guid )
	local cq = Me.chat_queue[1]
	if not cq then return end   -- The chat queue is empty. Maybe we should
	                            -- also break out of here if chat_busy is 
								-- false?
	-- See if we received a message of the type that we sent.
	if cq.type ~= kind then return end
	
	-- It'd be better if we could verify the message contents, to make sure
	--  that we caught the right event, but lots of things can change the 
	--  resulting message, especially on the server side (for example, if
	--  you're drunk, or if you send %t which gets replaced by your target).
	-- So... we just do it blind, instead. If we send two SAY messages and
	--  and EMOTE in order, then we wait for two SAY events and one EMOTE
	if guid == PLAYER_GUID then -- event for confirmation.
		Me.ChatConfirmed()
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
	if #Me.chat_queue == 0 then -- If the queue isn't started, then we aren't
		                        -- expecting anything.
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
		Me.ChatFailed() -- it and then continue as normal.
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
		Me.ChatFailed( true )
	end
end

function Me.OnChatMsgBnOffline( event, ... )
	local c = Me.chat_queue[1]
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
		
		-- Passing true here skips the table.remove inside.
		Me.ChatConfirmed( true )
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
	local cq = Me.chat_queue[1]
	if not cq then return end
	
	if guid ~= PLAYER_GUID then return end
	event = event:sub( 10 )
	
	-- Typically cq.type will always be CLUB for these, but we handle this
	--  anyway.
	if cq.type == event then
		Me.ChatConfirmed()
	elseif cq.type == "CLUB" and cq.arg3 == GetGuildClub() then
		-- arg3 is the club ID, and if it's the guild club, then our CLUB
		--  message is indeed expecting OFFICER or GUILD chat type.
		Me.ChatConfirmed()
	end
end

-------------------------------------------------------------------------------
-- Hook for when we received a message on a community channel.
--
function Me.OnChatMsgCommunitiesChannel( event, _,_,_,_,_,_,_,_,_,_,_, 
                                         guid, bn_sender_id )
	local cq = Me.chat_queue[1]
	if not cq then return end
	if cq.type ~= "CLUB" then return end
	
	-- This event seems to show up in a few formats. Thankfully, it always
	--  shows up when you receive a club message, regardless of whether or not
	--  you have subscribed to that channel in your chatboxes. One gotcha with
	--  this message is that it's split between Battle.net (or "Blizzard Chat"
	--  I guess..) and regular chat messages. For BNet ones the guid is nil,
	--  and the argument after is the BNet presence ID instead.
	-- We have a few extra checks down there for prudency, in case something
	--  changes in the future.
	if guid and guid == PLAYER_GUID then
		Me.ChatConfirmed()
	elseif bn_sender_id and bn_sender_id ~= 0 and BNIsSelf(bn_sender_id) then
		Me.ChatConfirmed()
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

-------------------------------------------------------------------------------
-- Handle compatibility for the Misspelled addon.
--
function Me.MisspelledCompatibility()
	if not Misspelled then return end -- (Not installed.)
	
	-- The Misspelled addon inserts color codes that are removed in its own
	--  hooks to SendChatMessage. This isn't ideal, because it can set up its
	--  hooks in the wrong "spot". In other words, its hooks might execute 
	--  AFTER we've already cut up the message to proper sizes, meaning that 
	--  it's going to make our slices even smaller, filled with a lot of empty
	--  space.
	-- What we do in here is unhook that code and then do it ourselves in one
	Misspelled:Unhook( "SendChatMessage" )	      -- of our own chat filters. 
	Me.AddChatHook( "START", function( text, chat_type, arg3, target )
		text = Misspelled:RemoveHighlighting( text )
		return text, chat_type, arg3, target
	end)
end

-------------------------------------------------------------------------------
-- Please read the following comments in your most maniacal voice, complete
--  with evil cackles. I almost gave up several times on this, and it's not
--  /really/ compatible, as I doubt Tongues' protocol even supports split
--  messages.
--
function Me.TonguesCompatibility()
	if not Tongues then return end -- No Tongues.
	
	-- First... we want to kill Tongues' SendChatMessage hook. All it does is 
	--  pass execution to HandleSend. We'll unhook their SendChatMessage hook
	--  by turning HandleSend into a dummy function, and then hook HandleSend
	--  ourselves...
	local stolen_handle_send = Tongues.HandleSend
	local tongues_hook = Tongues.Hooks.Send
	Tongues.HandleSend = function( self, msg, type, langid, lang, channel )
		tongues_hook( msg, type, langid, channel )
	end
	
	-- We reset their saved function for their hook with something that
	--  lets us know that they want to make a call to it. Why is this even
	--  necessary...? Don't question it!
	local tongues_is_calling_send = false
	local outside_send_function = function( ... )
		tongues_is_calling_send = true
		-- We use pcall to ignore errors, so tongues_is_calling_send doesn't
		--  get stuck, and it's likely that we'll run into a handful of errors
		--  if we have Tongues loaded.
		local a,b,c,d = ...
		pcall( SendChatMessage, a, b, c, d )
		tongues_is_calling_send = false
	end
	
	Tongues.Hooks.Send = outside_send_function
	
	-- Now... inside of our chat filter, we know if we're doing an organic call
	--  or not... If it is, we replace this hook temporarily to use our most
	--  special function SendChatFromHook...
	
	local inside_send_function = function( ... )
		Me.SendChatFromHook( ... )
	end
	
	local tongues_accepted_types = {
		SAY           = true;
		EMOTE         = true;
		YELL          = true;
		PARTY         = true;
		GUILD         = true;
		OFFICER       = true;
		RAID          = true;
		RAID_WARNING  = true;
		INSTANCE_CHAT = true;
		BATTLEGROUND  = true;
		WHISPER       = true;
		CHANNEL       = true;
	}
	
	Me.AddChatHook( "START", function( msg, type, _, target )
		if not tongues_accepted_types[type:upper()] then
			-- Don't send any special types through tongues.
			return
		end
		
		if tongues_is_calling_send then
			-- If Tongues is calling this, then we just skip our filter.
			return
		end
		
		-- And then replace the hook and call their handle send.
		Tongues.Hooks.Send = inside_send_function
		
		local langID, lang = GetSpeaking() -- Tongues adds this global.
		
		-- We need to use pcall, otherwise our Hooks.Send is going to be
		--  botched if we break out of here from an error.
		pcall( stolen_handle_send, Tongues, msg, type, langID, lang, target )
		
		-- And then put it back...
		Tongues.Hooks.Send = outside_send_function
		
		-- :)
		return false
	end)
end

-- See you on Moon Guard! :)
--                ~              ~   The Great Sea ~                  ~
--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^-