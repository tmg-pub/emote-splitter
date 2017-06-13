-------------------------------------------------------------------------------
-- EmoteSplitter by Tammya-MoonGuard
--
-- Allows you to easily paste long emotes in the chat window.
-------------------------------------------------------------------------------

local Main = LibStub("AceAddon-3.0"):NewAddon( "EmoteSplitter", 
		"AceHook-3.0", "AceEvent-3.0" )
		
EmoteSplitter = Main

local g_chat_queue  = {}
local g_chat_timer  = nil
local g_chat_busy   = false
local g_chat_failed = false

local g_throttler_hook_sendchat
local g_throttler_hook_bnet

local g_throttle_lib

local g_chat_filters = {}

local FASTPOST_PERIOD  = 0.5    -- period between fastposts allowed
local BNET_FLAG_OFFSET = 100000 -- added to presence IDs to signal we're in the throttler

Main.messages_waiting = 0
Main.fastpost_time = 0
Main.max_message_length = 255

--[[
local debug_print_serial = 1
local function debug_print( ... )
	print( debug_print_serial, GetTime(), ... )
	debug_print_serial = debug_print_serial + 1	
end]]

-------------------------------------------------------------------------------
-- Initialization.
-------------------------------------------------------------------------------
function Main:OnInitialize()
end 

-------------------------------------------------------------------------------
-- Slash command.
-------------------------------------------------------------------------------
SlashCmdList["EMOTESPLITTER"] = function( msg ) 
	-- Open options panel.
	
	Main:Options_Show()
end
 
-------------------------------------------------------------------------------
-- Post-initialization
-------------------------------------------------------------------------------
function Main:OnEnable() 
	
	if UCM then
		-- Disable if UCM is found.
		print( "EmoteSplitter cannot run with UnlimitedChatMessage enabled." )
		return
	end
	
	-- Setup options and register slash command.
	self:Options_Init()
	SLASH_EMOTESPLITTER1 = "/emotesplitter"
	
	-- Hook events to verify that chat messages are sent.
	self:RegisterEvent( "CHAT_MSG_SAY", "OnChatMsgSay" )
	self:RegisterEvent( "CHAT_MSG_EMOTE", "OnChatMsgEmote" )
	self:RegisterEvent( "CHAT_MSG_YELL", "OnChatMsgYell" )
	self:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM", "OnChatMsgBnInform" ) 
	self:RegisterEvent( "CHAT_MSG_SYSTEM", "OnChatMsgSystem" ) 
	
	-- Chat hooks for splitting messages.
	self:RawHook( "SendChatMessage", true )
	self:RawHook( "BNSendWhisper", true )
	self:Hook( "ChatEdit_OnShow", true )
	
	-- Unlock chat boxes. 
	for i = 1, NUM_CHAT_WINDOWS do
		_G["ChatFrame" .. i .. "EditBox"]:SetMaxLetters( 0 )
		_G["ChatFrame" .. i .. "EditBox"]:SetMaxBytes( 0 )
	end
	 
	-- Hook libbw.
	g_throttler_hook_sendchat = libbw.SendChatMessage 
	libbw.SendChatMessage     = Main.LIBBW_SendChatMessage
	g_throttler_hook_bnet     = libbw.BNSendWhisper
	libbw.BNSendWhisper       = Main.LIBBW_BNSendWhisper
	g_throttle_lib = libbw
	
	-- Filter for throttle messages.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM", function( self, event, msg, sender )
		if Main.db.global.hidefailed and msg == ERR_CHAT_THROTTLED and sender == "" then
			
			return true
		end
	end )
	
	-- Create sending indicator.
	self.sending_text = CreateFrame( "Frame", nil, UIParent );
	self.sending_text:SetPoint( "BOTTOMLEFT", 3, 3 )
	self.sending_text:SetSize( 200, 20 )
	self.sending_text.text = self.sending_text:CreateFontString( nil, "OVERLAY" )
	self.sending_text.text:SetPoint( "BOTTOMLEFT" )
	self.sending_text.text:SetJustifyH( "LEFT" )
	self.sending_text.text:SetFont( "Fonts\\ARIALN.TTF", 10, "OUTLINE" )
	self.sending_text.text:SetText( "Sending..." )
	self.sending_text:Hide()
	self.sending_text:SetFrameStrata( "DIALOG" )
	 
end

-------------------------------------------------------------------------------
-- Hook for when a chat editbox is opened.
-------------------------------------------------------------------------------
function Main:ChatEdit_OnShow( self )
	-- Remove character limit. (In case it was replaced by some addon.)
	self:SetMaxLetters( 0 );
	self:SetMaxBytes( 0 );
end

-------------------------------------------------------------------------------
-- Add a chat filter.
--
-- Chat filters are run on organic calls to SendChatMessage. In other words
-- they're used to process text that is send by the user before it gets
-- passed to the main system (which cuts it up and actually sends it.)
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
	for k,v in pairs( g_chat_filters ) do
		if v == func then return false end
	end
	
	table.insert( g_chat_filters, func )
end

-------------------------------------------------------------------------------
-- Remove a chat filter.
--
-- @param func Function reference of a filter that was added.
-- @returns true if removed, false if doesn't exist.
--
function Main:RemoveChatFilter( func )
	for k,v in pairs( g_chat_filters ) do
		if v == func then
			table.remove( g_chat_filters, k )
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
	return g_chat_filters
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
	g_throttler_hook_sendchat( self, text, kind, lang, "#ES" .. (target or ""), ... )
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
	
	for _, filter in ipairs( g_chat_filters ) do
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
	
	if not g_chat_busy and self.messages_waiting == 0 then
		self:SendingText_Hide()
	end
end

-------------------------------------------------------------------------------
function Main:SetChatTimer( func, delay )
	self:StopChatTimer()
	
	local timer = {
		cancel = false;
		func = func;
		tag = math.random(1,1000);
	}
	
	timer.callback = function()
		if timer.cancel then return end 
		Main[timer.func]( Main )
	end
	
	C_Timer.After( delay, timer.callback ) 
	g_chat_timer = timer
end

function Main:StopChatTimer()
	if g_chat_timer then 
		g_chat_timer.cancel = true 
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
		table.insert( g_chat_queue, { msg=msg, type=type, lang=lang, channel=channel } )
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
			g_throttler_hook_bnet( g_throttle_lib, channel + BNET_FLAG_OFFSET, msg, "ALERT", nil, OnCTL_Sent )
		else
			g_throttler_hook_sendchat( g_throttle_lib, msg, kind, lang, "#ES" .. (channel or ""), "ALERT", nil, OnCTL_Sent )
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
	if g_chat_busy then return end -- already started
	if #g_chat_queue == 0 then return end -- no messages waiting
	g_chat_busy = true
	 
	self:ChatQueue()
end

-------------------------------------------------------------------------------
-- Send the next message in the chat queue.
-------------------------------------------------------------------------------
function Main:ChatQueue()
	 
	if #g_chat_queue == 0 then 
		g_chat_busy = false
		self:SendingText_Hide()
		return 
	end
	
	self:SendingText_ShowSending()
	
	local c = g_chat_queue[1]
	
	self:SetChatTimer( "ChatTimeout", 10 )
	self:CommitChat( c.msg, c.type, c.lang, c.channel ) 
end

-------------------------------------------------------------------------------
-- (Timer) Sending chat timed out.
-------------------------------------------------------------------------------
function Main:ChatTimeout() 
	g_chat_queue = {}
	g_chat_busy = false
	self:SendingText_Hide()
	print( "|cffff0000<Chat failed!>|r" )
end

-------------------------------------------------------------------------------
-- Called when we confirm that a message was sent.
-------------------------------------------------------------------------------
function Main:ChatConfirmed()
	self:StopChatTimer()
	
	table.remove( g_chat_queue, 1 )
	
	self:ChatQueue()
end

-------------------------------------------------------------------------------
-- Called when we get a throttled error.
-------------------------------------------------------------------------------
function Main:ChatFailed() 
	self:SetChatTimer( "ChatFailedRetry", 3 ) 
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
	if #g_chat_queue == 0 then return end
	local cq = g_chat_queue[1]
	
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

	if #g_chat_queue == 0 then 
		-- we aren't expecting anything
		return 
	end
	
	if message == ERR_CHAT_THROTTLED and sender == "" then
		-- we got a throttle error, and we want to retry
		self:ChatFailed()
	end
end

