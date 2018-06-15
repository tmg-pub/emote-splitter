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

local AddonName, Me = ...

-- Create our main addon object. We're embedding AceAddon into the table that
LibStub("AceAddon-3.0"):NewAddon(  --  WoW provides us for our addon.
	-- Passing it into here as the first argument will let AceAddon know we
	Me, AddonName, -- want to use that object instead of creating a new one.
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
--    lang: Language index.
--    channel: Channel, whisper target, or BNet presenceID.
--
Me.chat_queue = {} -- This is a FIFO, first-in-first-out, 
                   --  queue[1] is the first to go.
                   --
-- This is a flag that tells us when the chat-queue system is busy. Or in
--  other words, it tells us when we're waiting on confirmation for our 
Me.chat_busy   = false -- messages being sent. This isn't used for messages
                       --  not queued (party/raid/whisper etc).
-------------------------------------------------------------------------------
-- Hooks for our chat throttler (libbw). We hook these functions because we
--  want all messages going through our chat queue system; this is mostly just
Me.throttler_hook_sendchat = nil -- to catch other addons trying to use
Me.throttler_hook_bnet     = nil --  these APIs.
                                 --
-- The throttle lib that we're using. This is pretty much always `libbw` unless
--  something might change in the future where we support multiple. As of right
Me.throttle_lib            = nil -- now though, libbw is the only one that 
                                 --  supports Battle.net messages.
-- You might have some questions, why I'm setting these table values to nil 
--  (which effectively does nothing), but it's just to keep things well 
--  defined up here.
-------------------------------------------------------------------------------
-- Our list of chat filters. This is a collection of functions that can be
--  added by other third parties to process messages before they're sent.
-- It's much cleaner or safer to do that with these rather than them hooking
--  SendChatMessage (or other functions) themselves, since it will be undefined
Me.chat_filters = {} -- if their hook fires before or after the message is
                     --  cut up by our functions.
-------------------------------------------------------------------------------
-- Fastpost is a special feature that lets us bypass the chat throttler
--  altogether. Normally, if you use the chat throttler for everything, there
--  might be a bit of a (noticable) delay to your messages when chatting
--  normally.
-- With a little bit of cheating, we allow direct use of SendChatMessage or
--  what have you every so often (defined by the period below).
-- The chat throttler libs leave some extra bandwidth for just this, so we're
-- just utilizing it.
local FASTPOST_PERIOD  = 0.5    -- 500 milliseconds. If they post faster than
                                -- that, then their subsequent messages will be
								-- passed to the throttler like normal.
-------------------------------------------------------------------------------
-- Time to allow the chat queue to wait for a message to be confirmed before we
local CHAT_TIMEOUT = 10.0 -- give up and show an error.
-------------------------------------------------------------------------------
-- We need to get a little bit creative when determining whether or not
-- something is an organic call to the WoW API or if we're coming from our own
-- system. For normal chat messages, we hide a little flag in the channel
-- argument ("#ES"); for Battle.net whispers, we hide this flag as an offset
-- to the presenceID. If the presenceID is >= this constant, then we're in the
local BNET_FLAG_OFFSET = 100000 -- throttler's message loop. Otherwise, we're
                                -- handling an organic call.
-------------------------------------------------------------------------------
-- The number of messages waiting to be handled by the chat throttler. This 
--  isn't the number of messages that we have queued in the chat-queue above, 
--  no; it's the number that we've already passed to the throttler. This might 
--  not even get past 0 during most normal use of the addon, as there is 
Me.messages_waiting = 0 -- usually plenty of excess bandwidth to send chat 
                        --  messages immediately.
-------------------------------------------------------------------------------
-- This is the last time when a post was posted using our "fast-post" hack.
Me.fastpost_time = 0 -- At least FASTPOST_PERIOD seconds must pass before we 
                     --  skip the throttler again.
-------------------------------------------------------------------------------
-- Normally this isn't touched. This was a special request from someone who
--  was having trouble using the stupid addon Tongues. Basically, this is used
--  to limit how much text can be sent in a single message, so then Tongues can
Me.max_message_length = 255 -- have some extra room to work with, making the 
                            --  message longer and such. It's wasteful, but
                            --  it works.
-- A lot of these definitions used to be straight local variables, but this is
--  a little bit cleaner, keeping things inside of this "Me" table, as well
--  as exposing it to the outside so we can do some easier diagnostics in case
--  something goes wrong down the line.
-------------------------------------------------------------------------------
-- We don't really need this but define it for good measure. Called when the
function Me:OnInitialize() end -- addon is first loaded by the game client.

-------------------------------------------------------------------------------
-- Our slash command /emotesplitter.
--
SlashCmdList["EMOTESPLITTER"] = function( msg )

	-- By default, with no arguments, we open up the configuration panel.
	if msg == "" then
		Me.Options_Show()
		return
	end
	
	-- Otherwise, parse out these arguments...
	-- A simple pattern to match words that are inbetween whitespace.
	local args = msg:gmatch( "%S+" ) --
	local arg1 = args()              -- Get first argument.
	local arg2 = args()              -- And then second argument.
	
	-- Command to change the maximum message length.
	-- /emotesplitter maxlen <number>
	if arg1:lower() == "maxlen" then
		-- Humans can be pretty nasty in what they give to you, so we do a
		-- little bit of sanitization here. Make sure it's a number, and then
		-- clamp the range to a reasonable amount.
		local v = tonumber(arg2) or 0 -- 40 might still be obnoxiously low,
		v = math.max( v, 40 )         --  floor, but who knows, maybe someone
		v = math.min( v, 255 )        --  might need that much extra room.
		-- It's is an obscure need anyway, so we don't really care too much.
		-- Our primary concern is probably trolls using this feature, to spam
		--  a lot of nonsense with tons of split messages. But that's what the
		--  ignore and report spam features are for, right?
		Me.max_message_length = v
		print( L( "Max message length set to {1}.", v ))
		return
	end
end
 
-------------------------------------------------------------------------------
-- Here's the real initialization code. This is called after all addons are 
function Me:OnEnable() -- initialized, and so is the game.

	-- We definitely cannot work if UnlimitedChatMessage is enabled at the
	--  same time. If we see that it's loaded, then we cancel our operation
	if UCM then -- in favor of it. Just print a notice instead. Better than 
		        --  everything just breaking.
		print( L["Emote Splitter cannot run with UnlimitedChatMessage enabled."] )
		
		-- We have UnlimitedChatMessage listed in the TOC file as an optional
		--  dependency. That's so this loads after it, so we can always catch
		--  this problem.
		return
	end
	-- Some miscellaneous things here.
	Me.Options_Init() -- Load our options and install the configuration 
	                    -- panel in the interface tab.
	SLASH_EMOTESPLITTER1 = "/emotesplitter" -- Setup our slash command.
	
	-- Message hooking. These first ones are the public message types that we
	--  want to hook for confirmation. They're the ones that can error out if
	--                           they're hit randomly by the server throttle.
	Me:RegisterEvent( "CHAT_MSG_SAY", function( ... )
		Me.TryConfirm( "SAY", select( 13, ... ))
	end)
	Me:RegisterEvent( "CHAT_MSG_EMOTE", function( ... )
		Me.TryConfirm( "EMOTE", select( 13, ... ))
	end)
	Me:RegisterEvent( "CHAT_MSG_YELL", function( ... )
		Me.TryConfirm( "YELL", select( 13, ... ))
	end)
	-- Battle.net whispers aren't affected by the server throttler, but they
	--  can still appear out of order if multiple are sent at once, so we send
	--  them "safely" too.
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM", function()
		Me.TryConfirm( "BNET", UnitGUID( "player" ))
	end)
	
	-- And finally we hook the system chat events, so we can catch when the
	--                         system tells us that a message failed to send.
	Me:RegisterEvent( "CHAT_MSG_SYSTEM", "OnChatMsgSystem" )
	
	-- Here's our main chat hooks for splitting messages.
	-- Using AceHook, a "raw" hook is when you completely replace the original
	--  function. Your callback fires when they try to call it, and it's up to
	--  you to call the original function which is stored as 
	--  `self.hooks.FunctionName`. In other words, it's a pre-hook that can
	Me:RawHook( "SendChatMessage", true ) -- modify or cancel the result.
	Me:RawHook( "BNSendWhisper", true )   -- 
	-- And here's a normal hook. It's still a pre-hook, in that it's called
	--  before the original function, but it can't cancel or modify the
	Me:Hook( "ChatEdit_OnShow", true ) -- arguments.
	
	-- We're unlocking the chat editboxes here. This may be redundant, because
	--  we also do it in the hook when the editbox shows, but it's for extra
	--  good measure - make sure that we are getting these unlocked. Some
	--  strange addon might even copy these values before the frame is even
	for i = 1, NUM_CHAT_WINDOWS do  -- shown... right?
		_G["ChatFrame" .. i .. "EditBox"]:SetMaxLetters( 0 )
		_G["ChatFrame" .. i .. "EditBox"]:SetMaxBytes( 0 )
	end
	
	-- We hook our cat throttler too, which is currently LIBBW from XRP's 
	--  author. This is so that messages that should be queued also go through
	--  our system first, rather than be passed directly to the throttler by
	Me.throttler_hook_sendchat = libbw.SendChatMessage -- other addons.
	libbw.SendChatMessage      = Me.LIBBW_SendChatMessage
	Me.throttler_hook_bnet     = libbw.BNSendWhisper
	libbw.BNSendWhisper        = Me.LIBBW_BNSendWhisper
	Me.throttle_lib            = libbw
	
	-- Here's where we add the feature to hide the failure messages in the
	-- chat frames, the failure messages that the system sends when your
	-- chat gets throttled.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM", 
		function( self, event, msg, sender )
			-- Someone might argue that we shouldn't hook this event at all
			--  if someone has this feature disabled, but let's be real;
			--  99% of people aren't going to turn this off anyway.
			if Me.db.global.hidefailed -- "Hide Failure Messages" option
			   and msg == ERR_CHAT_THROTTLED -- The localized string.
			   and sender == "" then -- Extra event verification.
			                         -- System has sender as "".
				-- Filter this message.
				return true
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
	-- This might be considered a bit primitive or dirty. Usually all of this
	--  stuff is defined in an XML file, and things like fonts and sizes are
	--  inherited from some of the standard font classes in play. But ...
	--  this is a lot easier and simpler to setup, this way.
	f.text = f:CreateFontString( nil, "OVERLAY" ) -- Unnamed, overlay layer.
	f.text:SetPoint( "BOTTOMLEFT" ) -- Bottom-left of the frame, which is
	                                -- 3 pixels from the edge of the screen.
	f.text:SetJustifyH( "LEFT" )    -- Align text with the left side.
	f.text:SetFont( "Fonts\\ARIALN.TTF", 10, "OUTLINE" ) 
	                                -- 10pt Outlined Arial Narrow
	f.text:SetText( L["Sending..."] ) -- Default text; this is overridden.
	f:Hide()                        -- Start hidden.
	f:SetFrameStrata( "DIALOG" )    -- DIALOG is a high strata that appears
	Me.sending_text = f             --  over most other normal things.
	
	Me.EmoteProtection.Init() -- Finally, we pass off our initialization to 
end                           --  the undo/redo feature.

-------------------------------------------------------------------------------
-- This is our hook for when a chat editbox is opened. Or in other words, when
function Me:ChatEdit_OnShow( editbox ) -- someone is about to type!
	editbox:SetMaxLetters( 0 ); -- We're just removing the limit again here.
	editbox:SetMaxBytes( 0 );   -- Extra prudency, in case some rogue addon, or
end                             --  even the Blizzard UI, messes with it.

-------------------------------------------------------------------------------
-- A simple function to iterate over a plain table, and return the key of any
local function FindTableValue( table, value ) -- first value that matches the
	for k, v in pairs( table ) do             -- argument. `key` also being an
		if v == value then return k end       -- index for array tables.
	end
	-- Otherwise, we don't return anything; or in other words, we return nil...
end

-------------------------------------------------------------------------------
-- Emote Splitter supports chat filters which are used during organic calls to
--  SendChatMessage. They're used to process text that's send by the user 
--  before it gets passed to the main system--which cuts it up (if it's that 
--  big) and actually sends it.
-- 
-- The reason for this is to avoid any more hooking of the SendChatMessage
--  function itself. Normally an addon would hook SendChatMessage if they want
--  to insert something (like replacing a certain keyword on the way out, or
--  removing text) but with Emote Splitter you don't know if you're going to
--  get your hook called before OR after the text is split up into smaller
--  sections. A clear problem with this, is that if you want to insert text,
--  and the emote is already cut up, then you're going to push text past the
--  255-character limit and some is going to get cut off. This is a problem
--  with Tongues, but we have the workaround with the /emotesplitter maxlen
--  command.
-- 
-- The signature for the callback function (filter_function) is
--
--   function( text, chat_type, language, channel )
--
-- Arguments passed to it are fairly straightforward, and the same are
--  passed to SendChatMessage.
--
--   text:      The message text.
--   chat_type: "SAY", "EMOTE" etc
--   language:  Language ID (a number)
--   channel:   Channel name or whisper target for WHISPER chatType.
--
--   Return false from this function to block the message from being send, to
--    discard it. Return nothing (nil) to have the filter do nothing, and let
--    the message pass through.
--   Otherwise, `return text, chatType, language, channel` to modify the chat
--    message. Take extra care to make sure that you're only setting these to
--    valid values.
--
-- This returns true if the filter was added, and false if it already exists.
--
-- Remove filters with RemoveChatFilter.
--
function Me.AddChatFilter( filter_function )
	if FindTableValue( Me.chat_filters, filter_function ) then
		return false
	end
	
	table.insert( Me.chat_filters, filter_function )
	return true
end

-------------------------------------------------------------------------------
-- You can also easily remove chat filters with this. Just pass in your
--  function reference that you had given to AddChatFilter.
--
-- This returns true if the filter was removed, and false if it wasn't found.
--
function Me.RemoveChatFilter( filter_function )
	local index = FindTableValue( Me.chat_filters, filter_function )
	if index then
		table.remove( Me.chat_filters, index )
		return true
	end
	
	return false
end

-------------------------------------------------------------------------------
-- You can also view the list of chat filters with this. This returns a direct
--  reference to the internal table which shouldn't be touched from the 
--  outside. This might seem like an unnecessary API feature, but someone might
function Me.GetChatFilters() -- write something that 'previews' outgoing
	return Me.chat_filters   -- messages, and would use this to apply the    
end                          -- chat filters themselves and see how it works 
                             -- out.
-------------------------------------------------------------------------------
-- This is our hook for LIBBW's SendChatMessage
--
function Me.LIBBW_SendChatMessage( libself, text, kind, lang, target, ... ) 
	-- This is an organic call from outside, as we don't call this hooked
	-- function directly. It's something else calling it.
	
	-- We just want to catch if it's a "public emote" or one of the public chat
	kind = kind:upper() -- types, which we want to pass to our queue instead of
	if kind == "SAY" or kind == "EMOTE" -- letting them go through.
	   or kind == "YELL" then
		Me.SendChat( text, kind, lang )
		return
	end
	
	-- If it's another chat type, we pass it directly back to the throttler.
	-- We don't really take a lot of care with messages being passed to the
	--  throttler directly by addons, and can assume that they don't need them
	--  to be cut up or anything.
	-- We just need to mark the target (channel) parameter to signal that we
	--  had this message looked at. The #ES flag prefixing the target argument
	--  is what our SendChatMessage hook looks for to know that the message
	--  is a call from the throttler lib rather than organic.
	Me.throttler_hook_sendchat( libself, text, kind, lang, 
	                            "#ES" .. (target or ""), ... )
end

-------------------------------------------------------------------------------
-- Here's our hook for LIBBW's BNSendWhisper
--
function Me.LIBBW_BNSendWhisper( libself, presenceID, text, ... )
	-- Like above, we don't call this directly. It's an organic call that we
	--  want to reroute to our chat queue. BNet whispers aren't affected by the
	--  server throttler, but we still handle them like they are, since there's
	--  an issue with them being sent out-of-order sometimes if you send them
	--  all at once.
	-- Basically, by having Emote Splitter installed, then any messages sent
	--  by addons through Libbw's API are ensured to be in the right order when
	Me.SendChat( text, "BNET", nil, presenceID ) -- received.
	
	-- In the future ChatThrottleLib might also have a BNet whisper function
	--  (which in turn a lot of addons might use) which libbw should also take
	--  control of.
end

-------------------------------------------------------------------------------
-- Function for splitting text on newlines or newline markers (literal "\n").
--
-- Returns a table of lines found in the text {line1, line2, ...}. Doesn't 
--  include any newline characters or marks in the results. If there aren't any
--  newlines, then this is going to just return { text }.
--                               --
function Me.SplitLines( text ) --
	-- We merge "\n" into LF too. This might seem a little bit unwieldy, right?
	-- Like, you're wondering what if the user pastes something
	--  like C:\nothing\etc... into their chatbox to send to someone. It'll be
	--          ^---.
	--  caught by this and treated like a newline.
	-- Truth is, is that the user can't actually type \n. Even without any
	--  addons, typing "\n" will cut off the rest of your message without 
	--  question. It's just a quirk in the API. Probably some security measure
	--  or some such for prudency? We're just making use of that quirk so
	--                            -- people can easily type a newline mark.
	msg = msg:gsub( "\\n", "\n" ) --
	                              --
	-- It's pretty straightforward to split the message now, we just use a 
	local lines = {}                       -- simple pattern and toss it 
	for line in msg:gmatch( "[^\n]+" ) do  --  into a table.
		table.insert( lines, line )        --
	end                                    --
	                                       --
	-- We used to handle this a bit differently, which was pretty nasty in
	--  regard to chat filters and such. It's a /little/ more complex now,
	return lines -- but a much better solution in the end.
end

-------------------------------------------------------------------------------
-- Our hook for SendChatMessage in the WoW API. This is where the magic begins.
--
function Me:SendChatMessage( msg, chatType, language, channel )
	
	-- First of all, without a little bit of "special care" we don't really
	--  know what's calling this. It could either be from the outside, an
	--  organic call (from the chatbox, etc), or, from the chat throttler.
	-- Ideally, we'd have a function in the chat throttler that we could call,
	--  which would tell us that we're inside of the chat throttler. That's
	--  just a huge headache though (to maintain), if we're to insert things 
	--  in there. We want to keep our code and practices all in our own files. 
	--  This way is a little more dirty, but it's also a lot more flexible when
	--  it comes to playing nicely with the chat throttler lib.
	-- How we do it? Simple. We just add a little code to the channel argument.
	-- We prefix it with #ES to signal that this message is not organic, and
	--  was handled by our system already.
	if channel and tostring(channel):find( "#ES" ) then
		-- So if we find that flag, clip it off, and then let this message fly.
		Me.hooks.SendChatMessage( msg, chatType, language, channel:sub(4) )
		return
	end
	
	-- Otherwise, this is actually an organic call, a new patient ready for
	--  some rigorous surgery. We start with a little bit of housekeeping here.
	chatType = chatType:upper() -- We check the chatType often, so may as well
	                            --  make it a fixed term before we continue.
	-- Here's where we run our chat filters. See AddChatFilter for a more
	--  rigorous discussion on them.
	for _, filter in ipairs( Me.chat_filters ) do
		local a, b, c, d = filter( msg, chatType, language, channel )
		
		-- If a chat filter returns `false` then we cancel this message. 
		if a == false then  --
			return          -- Just discard it.
		elseif a then       --
			-- Otherwise, if it's non-nil, we assume that they're changing
			--  the arguments on their end, so we replace them with the
			msg, chatType, language, channel = a, b, c, d -- return values.
		end
		
		-- If the filter returned nil, then we don't do anything to the
		--  message.
	end
	
	-- Now we cut this message up into potentially several pieces. First we're
	--  passing it through this line splitting function, which gives us a table
	msg = Me.SplitLines( msg )  -- of lines, or just { msg } if there aren't
	                              --  any newlines.
	-- And we iterate over each, pass them to our main splitting function (the
	--  one that cuts them to 255-character lengths), and then feed them off
	--  to our main chat queue system. That call might even bypass our queue
	--  or the throttler, and directly send the message if the conditions
	for _, line in ipairs( msg ) do             -- are right. But, otherwise
		local chunks = Me.SplitMessage( line )   -- this message has to wait
		for i = 1, #chunks do                     -- its turn.
			Me.SendChat( chunks[i], chatType, language, channel )
		end
	end
end

-------------------------------------------------------------------------------
-- Our hook for BNSendWhisper in the WoW API.
--
function Me:BNSendWhisper( presenceID, messageText ) 
	
	-- In SendChatMessage, we have the channel parameter that we can abuse to
	-- signal that we're not in an organic call. For BNet messages, we flag
	if presenceID >= BNET_FLAG_OFFSET then -- this by adding BNET_FLAG_OFFSET
		                                  -- to the presence ID.
		-- So here we know that this message is ready to be put out on the
		-- line.             Just don't forget to clean up our flag here.
		Me.hooks.BNSendWhisper( presenceID - BNET_FLAG_OFFSET, messageText )
		return
	end
	
	-- We run our chat filters on Bnet whispers too, despite them using a bit
	--  of a different API. This isn't so DRY, in that it's mostly a hacked up
	--  copy of the code for SendChatMessage, but it's not too bad.
	for _, filter in ipairs( Me.chat_filters ) do
		local a, b, c, d = filter( messageText, "BNET", nil, presenceID )
		
		if a == false then -- Mostly the same operation in here like we did
			return         --  in the normal chat version. Just we rearrange
		elseif a then      --  or ignore some arguments a bit.
			messageText, _, _, presenceID = a, b, c, d
		end
	end
	
	-- Most of this code layout is quite identical to the flow in the
	--  SendChatMessage function. Some might argue that things should be more
	--  DRY, and this is bad practice, but I say that the plus side to doing
	--  things a little WET (Write Everything Twice/Waste Everyone's Time)
	--  means that it's easier to be more flexible, should there be a need 
	--  for it. I guess another reason for WET code is efficiency. More
	--  customized handlers rather than one handler that's slower which
	--  has a lot more ifs and thens.
	-- We have a special custom chat type "BNET" which our system handles to
	messageText = Me.SplitLines( messageText )   -- pass this message to the
	for _, line in ipairs( messageText ) do       -- BNet side of message
		local chunks = Me.SplitMessage( line )    --  things.
		for i = 1, #chunks do
			Me.SendChat( chunks[i], "BNET", nil, presenceID )
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
function Me.SplitMessage( text )   --
	-- The Misspelled addon inserts color codes that are removed in its own
	--  hooks to SendChatMessage. This isn't ideal, because it can set up its
	--  hooks in the wrong "spot". In other words, its hooks might execute 
	--  AFTER we've already cut up the message to proper sizes, meaning that 
	--  it's going to make our slices even smaller, filled with a lot of empty
	--  space.
	-- An ideal fix is to get some Emote Splitter support in Misspelled, and
	--  have them use one of our chat filters instead. Otherwise, we're stuck
	--  with the less efficient version, calling RemoveHighlighting in here.
	if Misspelled then -- This is poor because it's going to be called again
		text = Misspelled:RemoveHighlighting( text ) -- by Misspelled
	end                                         -- (and just waste time).

	-- For short messages we can not waste any time and return immediately
	if text:len() <= Me.max_message_length then -- if they can fit within a
		return {text}                          --   chunk already.
	end	                                      -- A nice shortcut.
	
	
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
			return "\001\002" .. index .. string.rep( "\002", link:len() - 4 ) .. "\003"
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
	while( text:len() > Me.max_message_length ) do
		-- While in this loop, we're dealing with `text` that is too big to fit
		--  in a single chunk (max 255 characters or whatever the override is
		--  set to [we'll use the 255 figure everywhere to keep things
		--  simple]).
		-- We actually start our scan at character 256, because when we do the
		--  split, we're excluding that character. Either deleting it, if it's
		--  whitespace, or cutting right before it.
		-- We scan backwards for whitespace or an otherwise suitable place to
		--  break the message.
		for i = Me.max_message_length+1 - postmark:len(), 1, -1 do
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
				for i = Me.max_message_length+1 - postmark:len(), 1, -1 do
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
	if Me.db.global.showsending then return end -- retrying sending.
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
	self.sending_text:Hide()
end

-------------------------------------------------------------------------------
-- Our callback function for when the chat throttler puts out one of our
--  messages. We don't really care about the parameters. I don't really like
--  this a whole lot, to be honest. It's not really "robust". Just imagine if
--  there's some sort of error somewhere. We're going to be stuck with this
--  counter at non-zero, with our system locking up because it thinks it's
--  busy. Could really use something on the side to check up on this, to make
--                           -- sure that it's not getting stuck.
local function OnCTL_Sent()
	-- I'm not 100% sure why we even have this little system, but as far as I
	--  know, it's meant for the FastPost feature, which is used to bypass
	--  the throttler at times when it's not busy.
	Me.messages_waiting = Me.messages_waiting - 1
	
	-- The sending indicator shows up under two conditions. One is when the
	--  throttler is busy. It's shown when we return from the throttle lib
	--  with messages waiting (messages_waiting ~= 0). Most of the time it's
	--  shown because the system is busy (chat_busy = true).
	if not Me.chat_busy and Me.messages_waiting == 0 then
		Me.SendingText_Hide()
	end
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
	end                       -- the data is invisible and difficult to
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
-- This is our main entry into our chat queue. Basically we have the same
--  parameters as the SendChatMessage API. For BNet whispers, set `type` to 
--  "BNET" and `channel` to the presenceID.
-- Normal parameters:
--  msg     = Message text
--  type    = Message type, e.g "SAY", "EMOTE", etc.
--  lang    = Language index.
--  channel = Channel or whisper target.
--
function Me.SendChat( msg, type, lang, channel )
	type = type:upper()
	
	-- Now we've got two paths here. One leads to the chat queue, the other
	--  will directly send the messages that don't need to be queued.
	--  SAY, EMOTE, and YELL are affected by the server throttler. BNET isn't,
	--  but we treat it the same way to correct the out-of-order bug.
	if type == "SAY" or type == "EMOTE"         -- (As of writing, I'm assuming
	   or type == "YELL" or type == "BNET" then --  that's still a thing.)
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
		--[[ public chat while dead. ]]    or type == "YELL") then return end
		
		table.insert( Me.chat_queue, {     -- It looks like we're all good to
			msg = msg, type = type,        --  queue this puppy and start up
			lang = lang, channel = channel --  the system.
		})                                 --
		Me.StartChat()                    --
		
	else -- For other message types like party, raid, whispers, channels, we
		 -- aren't going to be affected by the server throttler, so we go
		Me.CommitChat( msg, type, lang, channel ) -- straight to putting these
	end                                          -- messages out on the line.
end                                           

-------------------------------------------------------------------------------
-- This is our function to finally send message out on the line directly.
-- Same parameters as SendChatMessage, with the exception of the special
--  `kind` "BNET" which represents a BNet whisper, where channel is the
--  presenceID. Some people say that you shouldn't repeat yourself in
--  documentation, but really, if someone jumps to one part, they don't have
--  to jump to another part to read more (unless they want to learn even MORE.)
--
function Me.CommitChat( msg, kind, lang, channel )

	-- This is our message counter. Keeps track of how many messages are
	--  waiting to be sent in the throttler.
	Me.messages_waiting = Me.messages_waiting + 1
	
	-- Basically, that allows us to see when the throttler isn't busy. It's
	--  important for our "fast post" feature. If that's enabled, then we can
	--  bypass the chat system every so often--defined as 500 milliseconds
	if Me.db.global.fastpost and Me.messages_waiting == 1 -- as of writing.
	   and GetTime() - Me.fastpost_time > FASTPOST_PERIOD then 
		-- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
		-- Personally, I love this pattern of checking if time is past a
		--  certain record, and then resetting it with the time, to make
		--                              these sorts of checks.
		self.fastpost_time = GetTime()
		
		-- We're only in here if message_waiting == 1, so we're removing that
		self.messages_waiting = 0 -- and then sending our message directly to
		                          -- the chat API.
		if kind == "BNET" then
			self.hooks.BNSendWhisper( channel, msg ) -- Kind of weird that they
		else                      -- have `presenceID` before `msg`, isn't it?
			self.hooks.SendChatMessage( msg, kind, lang, channel )
		end
	else
		-- If we didn't meet the "fastpost" criteria, then we're going to
		--  pass this message to the chat throttler lib we're using (libbw).
		if kind == "BNET" then
			-- For BNET messages, we add a certain constant to the presenceID
			--  to have a signal for our code that this message is coming from
			--  the channeler, and not organic, so we don't process it a second
			--  time.
			Me.throttler_hook_bnet( Me.throttle_lib, 
			                        channel + BNET_FLAG_OFFSET, 
									msg, "ALERT", nil, OnCTL_Sent )
		else
			-- For other messages, we prefix the channel with "#ES" to signal
			--                                                like above.
			Me.throttler_hook_sendchat( Me.throttle_lib, msg, 
			                            kind, lang, "#ES" .. (channel or ""), 
										"ALERT", nil, OnCTL_Sent )
		end
		
		-- The chat throttle lib can call OnCTL_Sent inside of the above
		--  functions if there is enough bandwidth to send the messages
		--  immediately. This is very common, so it's often that
		if Me.messages_waiting > 0 then  -- messages_waiting will be 0 here.
			Me.SendingText_ShowSending()
		end 
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
	Me.SetChatTimer( Me.ChatTimeout, CHAT_TIMEOUT ) 
	Me.CommitChat( c.msg, c.type, c.lang, c.channel )
end

-------------------------------------------------------------------------------
-- Timer callback for when chat times out.
--                        -- This is a bit of a fatal error, due to
function Me.ChatTimeout() --  disconnecting or other high latency issues. (Or
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
function Me.ChatConfirmed()   
	Me.StopChatTimer()               -- Upon success, we just pop the chat
	table.remove( Me.chat_queue, 1 ) --  queue and continue as normal.
	Me.ChatQueue()
end
----------------------------------- Upon failure, we wait a little while, and
function Me.ChatFailed()         --  then retry sending the same message.
	Me.SetChatTimer( Me.ChatFailedRetry, 3 )
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
	if guid == UnitGUID( "player" ) then -- event for confirmation.
		Me.ChatConfirmed()
	end
end

-------------------------------------------------------------------------------
-- Our handle for the CHAT_MSG_SYSTEM event.
--
function Me:OnChatMsgSystem( event, message, sender, _, _, target )
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
		-- So we got a throttle error here, and we want to retry.
		-- An bizarre note to take into account here is that ChatConfirmed 
		--  may STILL trigger after this error shows up. We have a few seconds
		--  of delay to try and avoid that corner case, but otherwise with some
		--  crazy bad luck and latency, you might be seeing some double
		--  messages being sent.
		-- If we do get a chat confirmed during our "waiting" period, we cancel
		Me.ChatFailed() -- it and then continue as normal.
	end
end

-- See you on Moon Guard! :)
--                ~              ~   The Great Sea ~                  ~
--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^-