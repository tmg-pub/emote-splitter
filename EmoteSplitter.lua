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

local Main = EmoteSplitter
local L    = Main.Locale

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
Main.chat_queue  = {} -- This is a FIFO, first-in-first-out, 
                      --  queue[1] is the first to go.
                      --
-- This is a flag that tells us when the chat-queue system is busy. Or in
--  other words, it tells us when we're waiting on confirmation for our 
Main.chat_busy   = false -- messages being sent. This isn't used for messages
                         --  not queued (party/raid/whisper etc).
-------------------------------------------------------------------------------
-- Hooks for our chat throttler (libbw). We hook these functions because we
--  want all messages going through our chat queue system; this is mostly just
Main.throttler_hook_sendchat = nil -- to catch other addons trying to use
Main.throttler_hook_bnet     = nil --  these APIs.
                                   --
-- The throttle lib that we're using. This is pretty much always `libbw` unless
--  something might change in the future where we support multiple. As of right
Main.throttle_lib            = nil -- now though, libbw is the only one that 
                                   --  supports Battle.net messages.
-- You might have some questions, why I'm setting these table values to nil 
--  (which effectively does nothing), but it's just to keep things well 
--  defined up here.
-------------------------------------------------------------------------------
-- Our list of chat filters. This is a collection of functions that can be
--  added by other third parties to process messages before they're sent.
-- It's much cleaner or safer to do that with these rather than them hooking
--  SendChatMessage (or other functions) themselves, since it will be undefined
Main.chat_filters = {} -- if their hook fires before or after the message is
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
-- We need to get a little bit creative when determining whether or not
-- something is an organic call to the WoW API or if we're coming from our own
-- system. For normal chat messages, we hide a little flag in the channel
-- argument ("#ES"); for Battle.net whispers, we hide this flag as an offset
-- to the presenceID. If the presenceID is > this constant, then we're in the
local BNET_FLAG_OFFSET = 100000 -- throttler's message loop. Otherwise, we're
                                -- handling an organic call.
-------------------------------------------------------------------------------
-- The number of messages waiting to be handled by the chat throttler. This 
--  isn't the number of messages that we have queued in the chat-queue above, 
--  no; it's the number that we've already passed to the throttler. This might 
--  not even get past 0 during most normal use of the addon, as there is 
Main.messages_waiting = 0 -- usually plenty of excess bandwidth to send chat 
                          --  messages immediately.
-------------------------------------------------------------------------------
-- This is the last time when a post was posted using our "fast-post" hack.
Main.fastpost_time = 0 -- At least FASTPOST_PERIOD seconds must pass before we 
                       --  skip the throttler again.
-------------------------------------------------------------------------------
-- Normally this isn't touched. This was a special request from someone who
-- was having trouble using the stupid addon Tongues. Basically, this is used
-- to limit how much text can be sent in a single message, so then Tongues can
Main.max_message_length = 255 -- have some extra room to work with, making the 
                              -- message longer and such. It's wasteful, but it
							  -- works.
-- A lot of these definitions used to be straight local variables, but this is
--  a little bit cleaner, keeping things inside of this "Main" table, as well
--  as exposing it to the outside so we can do some easier diagnostics in case
--  something goes wrong down the line.
-------------------------------------------------------------------------------
-- We don't really need this but define it for good measure. Called when the
function Main:OnInitialize() end -- addon is first loaded by the game client.

-------------------------------------------------------------------------------
-- Our slash command /emotesplitter.
--
SlashCmdList["EMOTESPLITTER"] = function( msg ) 

	-- By default, with no arguments, we open up the configuration panel.
	if msg == "" then
		Main:Options_Show()
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
		Main.max_message_length = v
		print( L( "Max message length set to {1}.", v ))
		return
	end
end
 
-------------------------------------------------------------------------------
-- Here's the real initialization code. This is called after all addons are 
function Main:OnEnable() -- initialized, and so is the game.

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
	Main.Options_Init() -- Load our options and install the configuration 
	                    -- panel in the interface tab.
	SLASH_EMOTESPLITTER1 = "/emotesplitter" -- Setup our slash command.
	
	-- Message hooking. These first ones are the public message types that we
	--  want to hook for confirmation. They're the ones that can error out if
	--  they're hit randomly by the server throttle.
	Main:RegisterEvent( "CHAT_MSG_SAY",   "OnChatMsgSay"   ) -- /s, /say
	Main:RegisterEvent( "CHAT_MSG_EMOTE", "OnChatMsgEmote" ) -- /e, /me
	Main:RegisterEvent( "CHAT_MSG_YELL",  "OnChatMsgYell"  ) -- /y, /yell
	-- Battle.net whispers aren't affected by the server throttler, but they
	--  can still appear out of order if multiple are sent at once, so we send
	--  them "slowly" too.
	Main:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM", "OnChatMsgBnInform" )
	-- And finally we hook the system chat events, so we can catch when the
	--  system tells us that a message failed to send.
	Main:RegisterEvent( "CHAT_MSG_SYSTEM", "OnChatMsgSystem" )
	
	-- Here's our main chat hooks for splitting messages.
	-- Using AceHook, a "raw" hook is when you completely replace the original
	--  function. Your callback fires when they try to call it, and it's up to
	--  you to call the original function which is stored as 
	-- `self.hooks.FunctionName`. In other words, it's a pre-hook that can
	Main:RawHook( "SendChatMessage", true ) -- modify or cancel the result.
	Main:RawHook( "BNSendWhisper", true )   -- 
	-- And here's a normal hook. It's still a pre-hook, in that it's called
	--  before the original function, but it can't cancel or modify the
	Main:Hook( "ChatEdit_OnShow", true ) -- arguments.
	
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
	Main.throttler_hook_sendchat = libbw.SendChatMessage -- other addons.
	libbw.SendChatMessage        = Main.LIBBW_SendChatMessage
	Main.throttler_hook_bnet     = libbw.BNSendWhisper
	libbw.BNSendWhisper          = Main.LIBBW_BNSendWhisper
	Main.throttle_lib            = libbw
	
	-- Here's where we add the feature to hide the failure messages in the
	-- chat frames, the failure messages that the system sends when your
	-- chat gets throttled.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM", 
		function( self, event, msg, sender )
			-- Someone might argue that we shouldn't hook this event at all
			--  if someone has this feature disabled, but let's be real;
			--  99% of people aren't going to turn this off anyway.
			if Main.db.global.hidefailed -- "Hide Failure Messages" option
			   and msg == ERR_CHAT_THROTTLED -- the localized string
			   and sender == "" then -- extra event verification. 
			                         -- System has sender as ""
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
	f:SetFrameStrata( "DIALOG" )    -- This is a high strata that appears over
	Main.sending_text = f           --  most other normal things.
	
	-- Finally, we pass off our initialization to the undo/redo feature.
	Main.EmoteProtection.Init()
end

-------------------------------------------------------------------------------
-- This is our hook for when a chat editbox is opened. Or in other words, when
function Main:ChatEdit_OnShow( self ) -- someone is about to type!
	self:SetMaxLetters( 0 ); -- We're just removing the character again here
	self:SetMaxBytes( 0 );   -- Extra prudency, in case some rogue addon, or
end                          --  even the Blizzard UI, messes with it.

-------------------------------------------------------------------------------
-- Chat filters are run on organic calls to SendChatMessage. In other words
--  they're used to process text that is send by the user before it gets
--  passed to the main system (which cuts it up and actually sends it.)
--
-- @param func Function with the signature( text, chatType, language, channel )
--             Return false to stop the message from being sent
--             Return nothing (nil) to have the filter do nothing
--             Otherwise, return text, chatType, language, channel to modify
--               certain arguments.
--
-- @returns true if added, false if already exists.
--
function Main:AddChatFilter( func )
	for k,v in pairs( Main.chat_filters ) do
		if v == func then return false end
	end
	
	table.insert( Main.chat_filters, func )
end

-------------------------------------------------------------------------------
-- Remove a chat filter.
--
-- @param func Function reference of a filter that was added.
-- @returns true if removed, false if doesn't exist.
--
function Main:RemoveChatFilter( func )
	for k,v in pairs( Main.chat_filters ) do
		if v == func then
			table.remove( Main.chat_filters, k )
			return true
		end
	end
	
	return false
end

-------------------------------------------------------------------------------
-- Get the list of chat filters.
--
-- The table returned should not be modified.
--
function Main:GetChatFilters()
	return Main.chat_filters
end

-------------------------------------------------------------------------------
-- Hook for LIBBW SendChatMessage
-------------------------------------------------------------------------------
function Main.LIBBW_SendChatMessage( self, text, kind, lang, target, ... ) 
	-- This is an organic call; we don't call this directly.
	
	-- if it's a public emote, then send through our system
	kind = kind:upper()
	if kind == "SAY" or kind == "EMOTE" or kind == "YELL" then
		-- send through our public queue
		self:SendChat( text, kind, lang )
		return
	end
	
	-- otherwise, pass directly to the throttler
	
	-- we mark the target parameter to flag that we're inside the throttler
	Main.throttler_hook_sendchat( self, text, kind, lang, "#ES" .. (target or ""), ... )
end

-------------------------------------------------------------------------------
-- Hook for LIBBW BNSendWhisper
-------------------------------------------------------------------------------
function Main.LIBBW_BNSendWhisper( self, presenceID, text, ... )
	-- This is an organic call; we don't call this directly.
	
	-- pass all bnet whispers through our system
	self:SendChat( text, "BNET", nil, presenceID )
end

-------------------------------------------------------------------------------
-- Function for splitting messages on newlines.
--
-- @param msg Message text.
-- @param func Function to call for each split message found.
--
-- @returns true if the message was split, and false if there were no newlines
--               found. If false, the `func` wouldn't have been called.
-------------------------------------------------------------------------------
function Main:SplitNewlines( msg, func )
	 
	-- Convert "\n" to LF
	msg = msg:gsub( "\\n", "\n" )
	
	if msg:find( "\n" ) then
		for splitmsg in msg:gmatch( "[^\n]+" ) do
			func( splitmsg )
		end
		return true
	end
end
  
-------------------------------------------------------------------------------
-- Hook for API BNSendWhisper
-------------------------------------------------------------------------------
function Main:BNSendWhisper( presenceID, messageText ) 
	
	if presenceID >= BNET_FLAG_OFFSET then
		-- this message has gone through the system already and is ready to be sent
		
		self.hooks.BNSendWhisper( presenceID - BNET_FLAG_OFFSET, messageText )
		return
	end
	
	-- split newlines
	if self:SplitNewlines( messageText, 
				function( msg ) 
					self:BNSendWhisper( presenceID, msg ) 
				end ) then
		return
	end
	
	local chunks = self:SplitMessage( messageText )

	for i = 1, #chunks do
		self:SendChat( chunks[i], "BNET", nil, presenceID )
	end 
end
 
-------------------------------------------------------------------------------
-- Hook for API SendChatMessage
-------------------------------------------------------------------------------
function Main:SendChatMessage( msg, chatType, language, channel )
 
	if channel and tostring(channel):find( "#ES" ) then
		-- this message has gone through the system already and is ready to be sent
		
		self.hooks.SendChatMessage( msg, chatType, language, channel:sub(4) )
		return
	end
	
	-- otherwise, this is an organic call,
	-- and we want to adjust it and transfer it to our queue and CTL
	chatType = chatType:upper()
	
	for _, filter in ipairs( Main.chat_filters ) do
		local a, b, c, d = filter( msg, chatType, language, channel )
		 
		if a == false then
			-- false was returned
			return
		elseif a then
			-- non-nil
			msg, chatType, language, channel = a, b, c, d
		end
	end
	
	-- split newlines
	if self:SplitNewlines( msg, 
				function( msg ) 
					self:SendChatMessage( msg, chatType, language, channel ) 
				end ) then
		return
	end 
	
	local chunks = self:SplitMessage( msg )

	for i = 1, #chunks do
		self:SendChat( chunks[i], chatType, language, channel )
	end
end

local g_replacement_patterns = {
	-- note that there is a maximum of 9 of these allowed due to the replaced code
	"(|cff[0-9a-f]+|H[^|]+|h[^|]+|h|r)"; -- permissable chat links w/ color code
	--"%[.-%]"; -- addon chat links (idea needs further review since some people use [[ ]] for ooc marks and it could be a huge "word")
}

-------------------------------------------------------------------------------
-- Split a message to fit in 255-character chunks.
-- 
-- @param text Text to split.
-- @returns Table of split messages.
-------------------------------------------------------------------------------
function Main:SplitMessage( text )

	-- misspelled inserts color codes that are removed in its own hooks
	-- ideally, we'd just have misspelled do this, but (afaik) there's not a 
	-- way to reliably hook SendChatMessage before everything else does 
	if Misspelled then
		text = Misspelled:RemoveHighlighting( text )
	end

	local replaced_links = {}
	local chunks = {}
	
	if text:len() < Main.max_message_length then
		-- fits in a single message.
		table.insert( chunks, text )
		return chunks
	end
	 
	for index, pattern in ipairs( g_replacement_patterns ) do
		text = text:gsub( pattern, function( link )
			table.insert( replaced_links, link )
			return "\001\002" .. index .. string.rep( "\002", link:len() - 4 ) .. "\003"
		end)
	end 
	 
	local premark = self.db.global.premark
	local postmark = self.db.global.postmark
	
	if premark ~= "" then premark = premark .. " " end
	if postmark ~= "" then postmark = " " .. postmark end
	
	while( text:len() > Main.max_message_length ) do
		-- we could start at 256, but that's scary :)
		
		for i = Main.max_message_length - postmark:len(), 1, -1 do
			local ch = string.byte( text, i )
			
			if ch == 32 or ch == 1 then -- space or start of link
				
				-- offset to discard space at split or keep something else
				local offset = 0
				if ch == 32 then offset = 1 end
				
				table.insert( chunks, text:sub( 1, i-1 ) .. postmark )
				text = premark .. text:sub( i+offset )
				
				break
			end
			
			if i <= 12 then
				-- there is a -really- long word
				
				-- in this case, we just break the message at any valid character start
				for i = Main.max_message_length - postmark:len(), 1, -1 do
					local ch = string.byte( text, i )
					if (ch >= 32 and ch < 128) -- ascii char
					   or (ch >= 192) then -- utf8 start code
					   
						table.insert( chunks, text:sub( 1, i-1 ) .. postmark )
						text = premark .. text:sub( i )
						break
					end
					
					if i == 1 then
						-- likely some abuse in play
						error( "This shouldn't happen." )
					end
				end 
				
				break
			end
			
		end
	end

	-- and the final chunk
	table.insert( chunks, text )
	
	-- put links back
	local link_count = 0
	for index,_ in ipairs( g_replacement_patterns ) do
			
		for i = 1, #chunks do 
			chunks[i] = chunks[i]:gsub("\001\002" .. index .. "\002*\003", function(link)
				link_count = link_count + 1
				return replaced_links[link_count] 
			end)
			 
			
		end
	end
	
	return chunks
end

-------------------------------------------------------------------------------
-- Show the sending indicator with a state of "SENDING".
-------------------------------------------------------------------------------
function Main:SendingText_ShowSending()
	if self.db.global.showsending then
		self.sending_text.text:SetTextColor( 1,1,1,1 )
		self.sending_text.text:SetText( "Sending... " )
		self.sending_text:Show()
	end
end

-------------------------------------------------------------------------------
-- Show the sending indicator with a state of "FAILED/WAITING"
-------------------------------------------------------------------------------
function Main:SendingText_ShowFailed()
	if self.db.global.showsending then
		self.sending_text.text:SetTextColor( 1,0,0,1 )
		self.sending_text.text:SetText( "Waiting..." )
		self.sending_text:Show()
	end
end

-------------------------------------------------------------------------------
-- Hide the sending indicator.
-------------------------------------------------------------------------------
function Main:SendingText_Hide()
	self.sending_text:Hide()
end

-------------------------------------------------------------------------------
-- Callback for when a message is put out on the line by the throttler.
-------------------------------------------------------------------------------
local function OnCTL_Sent()
	local self = Main
	self.messages_waiting = self.messages_waiting - 1
	
	if not Main.chat_busy and self.messages_waiting == 0 then
		self:SendingText_Hide()
	end
end

-------------------------------------------------------------------------------
function Main.SetChatTimer( func, delay )
	Main.StopChatTimer()
	
	local timer = {
		cancel = false;
		func = func;
	}
	
	timer.callback = function()
		if timer.cancel then return end 
		Main[timer.func]( Main )
	end
	
	C_Timer.After( delay, timer.callback )
	
	Main.chat_timer = timer
end

function Main.StopChatTimer()
	if Main.chat_timer then
		Main.chat_timer.cancel = true 
	end 
end

-------------------------------------------------------------------------------
-- Queue a chat message to be sent through our system.
--
-- For BNet whispers, set `type` to "BNET" and `channel` to the presenceID.
--
-- @param msg Message text
-- @param type Message type, e.g "SAY", "EMOTE", etc.
-- @param lang Language index.
-- @param channel Channel or whisper target.
-------------------------------------------------------------------------------
function Main:SendChat( msg, type, lang, channel )
	type = type:upper()
	
	if type == "SAY" or type == "EMOTE" or type == "YELL" or type == "BNET" then
		if msg == "" then return end
		if msg:find( "卍" ) or msg:find( "卐" ) then return end -- sending these silently fails
		
		-- say and emote have problematic throttling
		table.insert( Main.chat_queue, { msg=msg, type=type, lang=lang, channel=channel } )
		self:StartChat()
	else
		
		self:CommitChat( msg, type, lang, channel )
	end
end

-------------------------------------------------------------------------------
-- Send a chat message (or pass it to the throttler).
--
-- @param msg     Message text.
-- @param type    Message type, e.g "SAY", "EMOTE", etc.
-- @param lang    Language index.
-- @param channel Channel or whisper target.
-------------------------------------------------------------------------------
function Main:CommitChat( msg, kind, lang, channel )
	self.messages_waiting = self.messages_waiting + 1
	if self.db.global.fastpost and self.messages_waiting == 1 
	   and GetTime() - self.fastpost_time > FASTPOST_PERIOD then
	   
		self.fastpost_time = GetTime()
		self.messages_waiting = 0

		if kind == "BNET" then
			self.hooks.BNSendWhisper( channel, msg )
		else
			self.hooks.SendChatMessage( msg, kind, lang, channel )
		end
	else
		-- libbw:

		if kind == "BNET" then
			Main.throttler_hook_bnet( Main.throttle_lib, channel + BNET_FLAG_OFFSET, msg, "ALERT", nil, OnCTL_Sent )
		else
			Main.throttler_hook_sendchat( Main.throttle_lib, msg, kind, lang, "#ES" .. (channel or ""), "ALERT", nil, OnCTL_Sent )
		end
		
		if self.messages_waiting > 0 then
			self:SendingText_ShowSending()
		end 
	end
end

-------------------------------------------------------------------------------
-- Execute the chat queue.
-------------------------------------------------------------------------------
function Main:StartChat()
	if Main.chat_busy then return end -- already started
	if #Main.chat_queue == 0 then return end -- no messages waiting
	Main.chat_busy = true
	 
	self:ChatQueue()
end

-------------------------------------------------------------------------------
-- Send the next message in the chat queue.
-------------------------------------------------------------------------------
function Main:ChatQueue()
	 
	if #Main.chat_queue == 0 then 
		Main.chat_busy = false
		self:SendingText_Hide()
		return 
	end
	
	self:SendingText_ShowSending()
	
	local c = Main.chat_queue[1]
	
	Main.SetChatTimer( "ChatTimeout", 10 )
	self:CommitChat( c.msg, c.type, c.lang, c.channel )
end

-------------------------------------------------------------------------------
-- (Timer) Sending chat timed out.
-------------------------------------------------------------------------------
function Main:ChatTimeout() 
	Main.chat_queue = {}
	Main.chat_busy = false
	self:SendingText_Hide()
	print( "|cffff0000<Chat failed!>|r" )
end

-------------------------------------------------------------------------------
-- Called when we confirm that a message was sent.
-------------------------------------------------------------------------------
function Main:ChatConfirmed()
	Main.StopChatTimer()
	
	table.remove( Main.chat_queue, 1 )
	
	self:ChatQueue()
end

-------------------------------------------------------------------------------
-- Called when we get a throttled error.
-------------------------------------------------------------------------------
function Main:ChatFailed() 
	Main.SetChatTimer( "ChatFailedRetry", 3 ) 
	--print( "|cffff0000<Chat failed; waiting...>" )
	self:SendingText_ShowFailed() 
end

-------------------------------------------------------------------------------
-- (Timer) Restart the chat queue after a failure.
-------------------------------------------------------------------------------
function Main:ChatFailedRetry()
	if not Main.db.global.hidefailed then
		print( "|cffff00ff<Resending...>" )
	end
	
	self:ChatQueue()
end

-------------------------------------------------------------------------------
-- Called by the chat events. Try to confirm that we have successfully sent
-- a message in the queue.
--
-- @param kind Type of chat message the event handles. e.g. SAY, EMOTE, etc.
-- @param guid GUID of the player that sent the message.
-------------------------------------------------------------------------------
function Main:TryConfirm( kind, guid )
	if #Main.chat_queue == 0 then return end
	local cq = Main.chat_queue[1]
	
	-- see if we received a message of the type that we sent
	if cq.type ~= kind then return end
	
	-- we don't verify the message contents because it can be affected if the player is drunk
	if guid == UnitGUID( "player" ) then
		self:ChatConfirmed()
	end
end

-------------------------------------------------------------------------------
-- CHAT_MSG_SAY event.
-------------------------------------------------------------------------------
function Main:OnChatMsgSay( event, message, sender, _, _, _, _, _, _, _, _, _, guid )
	self:TryConfirm( "SAY", guid )
end

-------------------------------------------------------------------------------
-- CHAT_MSG_EMOTE event.
-------------------------------------------------------------------------------
function Main:OnChatMsgEmote( event, message, sender, _, _, _, _, _, _, _, _, _, guid )
	self:TryConfirm( "EMOTE", guid )
end

-------------------------------------------------------------------------------
-- CHAT_MSG_YELL event.
-------------------------------------------------------------------------------
function Main:OnChatMsgYell( event, message, sender, _, _, _, _, _, _, _, _, _, guid )
	self:TryConfirm( "YELL", guid )
end

-------------------------------------------------------------------------------
-- CHAT_MSG_BN_WHISPER_INFORM event.
-------------------------------------------------------------------------------
function Main:OnChatMsgBnInform()
	self:TryConfirm( "BNET", UnitGUID( "player" ))
end

-------------------------------------------------------------------------------
-- CHAT_MSG_SYSTEM event
-------------------------------------------------------------------------------
function Main:OnChatMsgSystem( event, message, sender, _, _, target )

	if #Main.chat_queue == 0 then 
		-- we aren't expecting anything
		return 
	end
	
	if message == ERR_CHAT_THROTTLED and sender == "" then
		-- we got a throttle error, and we want to retry
		self:ChatFailed()
	end
end

