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

local L      = Me.Locale -- Easy access to our locale data.
local Gopher = LibGopher

-- Compatibility shim: some older addons call `ChatFrame_GetMessageEventFilters()`
-- which was removed/changed in newer clients. Define a safe stub so those
-- addons don't throw a hard error. We return an empty table or delegate to
-- a chatframe method when available.
if type( ChatFrame_GetMessageEventFilters ) ~= "function" then
	ChatFrame_GetMessageEventFilters = function( ... )
		-- If any chatframe exposes a helper, prefer that.
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local cf = _G["ChatFrame" .. i]
			if cf and type( cf.GetMessageEventFilters ) == "function" then
				return cf:GetMessageEventFilters()
			end
		end
		-- Fallback: return an empty table so callers can iterate safely.
		return {}
	end
end

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
		Gopher:SetChunkSizeOverride( "OTHER", v )
		print( L( "Max message length set to {1}.", v ))         -- right?
		return
	end
	
	-- Enable/disable debug logging for split messages
	if arg1:lower() == "debug" then
		Gopher.debug_log = not Gopher.debug_log
		print(string.format("SplitMessage debug logging: %s", Gopher.debug_log and "ON" or "OFF"))
		return
	end
end

-------------------------------------------------------------------------------
-- Here's the real initialization code. This is called after all addons are 
--                                     -- initialized, and so is the game.
function Me:OnEnable()

	-- Some miscellaneous things here.
	-- See options.lua. This is initializing our configuration database, so 
	Me.Options_Init() -- it's needed before we can access Me.db.etc.
	
	-- Adding slash commands to the game is fairly straightforward. First you
	--  add a function to the SlashCmdList table, and then you assign the 
	--  command to the global SLASH_XYZ1. You can add more aliases with 
	SLASH_EMOTESPLITTER1 = "/emotesplitter" -- SLASH_XYZ2 or SLASH_XYZ3 etc.
	
	-- Gopher events.
	Gopher.Listen( "SEND_START",      Me.Gopher_SEND_START      )
	Gopher.Listen( "SEND_DONE",       Me.Gopher_SEND_DONE       )
	Gopher.Listen( "SEND_DEATH",      Me.Gopher_SEND_DEATH      )
	Gopher.Listen( "SEND_FAIL",       Me.Gopher_SEND_FAIL       )
	Gopher.Listen( "SEND_CONFIRMED",  Me.Gopher_SEND_CONFIRMED  )
	Gopher.Listen( "SEND_RECOVER",    Me.Gopher_SEND_RECOVER    )
	Gopher.Listen( "THROTTLER_START", Me.Gopher_THROTTLER_START )
	Gopher.Listen( "THROTTLER_STOP",  Me.Gopher_THROTTLER_STOP  )
	
	---------------------------------------------------------------------------
	-- The community API and Battle.net whispers let you send messages that are
	--  as long as 4000 characters. SendChatMessage is limited to 255
	--  characters, but we bump the others up to a nice 400 characters. If you
	--  have too big of a value, then it just makes the user interface 
	--  unmanagable, since you cannot partially scroll past one of the
	--  messages. Each message is one scroll tick. 
	--  other chat types. The chunk size will be 
	--  `override[type] or default[type] or override.OTHER or default.OTHER`.
	Gopher.Internal.default_chunk_sizes.BNET    = 400
	Gopher.Internal.default_chunk_sizes.CLUB    = 400
--	if Gopher.Internal.clubs then
--		Gopher.Internal.default_chunk_sizes.GUILD   = 400
--		Gopher.Internal.default_chunk_sizes.OFFICER = 400
--	end
	
--	if not C_Club then -- [7.x compat]
--		-- 7.x doesn't use GUILD and OFFICER like this.
--		Gopher.Internal.default_chunk_sizes.GUILD   = nil
--		Gopher.Internal.default_chunk_sizes.OFFICER = nil
--	end

	-- Localize the continuation prompt label.
	Gopher.Internal.continue_frame_label = L["Press enter to continue."]

	-- Unlock the chat editboxes when they show.

	-- Zaphon fix: updated for WoW 11.2.7: ChatEdit_OnShow no longer exists as a global function.
	-- Instead, we hook the OnShow script for each chat edit box individually.
	-- This is the modern way to handle chat edit box events since functions were
	-- moved to ChatFrameEditBox mixins.
	
	-- Hook all chat frames including whisper windows (ChatFrame11+)
	-- WoW allows up to 20 chat frames total
	for i = 1, 20 do
		local editbox = _G["ChatFrame" .. i .. "EditBox"]
		if editbox then
			editbox:HookScript("OnShow", Me.ChatEdit_OnShow)
		end
	end
	
	-- We're unlocking the chat editboxes here. This may be redundant, because
	--  we also do it in the hook when the editbox shows, but it's for extra
	--  good measure - make sure that we are getting these unlocked. Some
	--  strange addon might even copy these values before the frame is even
	for i = 1, 20 do                       -- shown... right?
		local editbox = _G["ChatFrame" .. i .. "EditBox"]
		if editbox then
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
	end
	
	-- Hook whisper window creation (FCF = Floating Chat Frame)
	-- This is critical for WoW 11.2+ where whisper tabs are created dynamically
	-- and don't trigger the initial OnShow hooks above. When a whisper window
	-- is created, we need to unlock its editbox and set up the OnShow hook.
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function(chatType, chatTarget, sourceChatFrame, selectWindow)
			-- Give the frame a moment to be fully created, then unlock its editbox
			C_Timer.After(0.1, function()
				for i = 1, 50 do
					local editbox = _G["ChatFrame" .. i .. "EditBox"]
					if editbox then
						Me.ChatEdit_OnShow(editbox)
						-- Also hook OnShow if not already hooked
						if not Me.hooks["ChatFrame"..i.."EditBox_OnShow"] then
							Me.hooks["ChatFrame"..i.."EditBox_OnShow"] = true
							editbox:HookScript("OnShow", Me.ChatEdit_OnShow)
						end
					end
				end
			end)
		end)
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
	--Me.ExtendTRPNPCChat()
	
	-- Check for CrossRP compatibility issue and warn user (only once)
	if C_AddOns.IsAddOnLoaded("CrossRP") and not Me.db.global.crossrp_warning_acknowledged then
		-- Register the dialog if it doesn't exist yet
		StaticPopupDialogs["EMOTESPLITTER_CROSSRP_WARNING"] = {
			text = "WARNING: CrossRP Detected\n\nCrossRP is known to break Emote Splitter's functionality. Please disable CrossRP if you want Emote Splitter to work correctly.",
			button1 = "OK",
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
			OnAccept = function()
				-- Mark that the user has acknowledged this warning
				Me.db.global.crossrp_warning_acknowledged = true
			end,
		}
		StaticPopup_Show("EMOTESPLITTER_CROSSRP_WARNING")
	end
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
	-- In WoW 11.2.7+, there's also a character limit for visible text
	-- Try to set that as well if the method exists
	if editbox.SetVisibleTextCharLimit then
		editbox:SetVisibleTextCharLimit( 0 )
	end
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
function Me.Gopher_SEND_START()
	Me.SendingText_ShowSending()
end

-------------------------------------------------------------------------------
function Me.Gopher_SEND_DONE()
	Me.SendingText_Hide()
end

-------------------------------------------------------------------------------
function Me.Gopher_SEND_DEATH()
	Me.SendingText_Hide()
	
	-- I feel like we should wrap these types of print calls in something to
	--  standardize the formatting and such.
	print( "|cffff0000<" .. L["Chat failed!"] .. ">|r" )
end

-------------------------------------------------------------------------------
function Me.Gopher_SEND_FAIL()
	Me.SendingText_ShowFailed()  -- We also update our little indicator to show
end
-------------------------------------------------------------------------------
function Me.Gopher_SEND_CONFIRMED()
	Me.SendingText_ShowSending()
end

-------------------------------------------------------------------------------
function Me.Gopher_SEND_RECOVER()

	-- We have an option to hide any sort of failure messages during
	--  semi-normal operation. If that's disabled, then we tell the user when
	--  we're resending their message. Otherwise, it's a seamless operation.
	if not Me.db.global.hidefailed then -- All errors are hidden and everything
		                                -- happens in the background.
		print( "|cffff00ff<" .. L["Resending..."] .. ">" )
	end
	Me.SendingText_ShowSending()
end

-------------------------------------------------------------------------------
-- These are callbacks from the throttler (throttler.lua). They're only called
--  when we're sending a lot of chat, and the throttler has delayed for a bit.
--
function Me.Gopher_THROTTLER_START()
	Me.SendingText_ShowSending()
end

-------------------------------------------------------------------------------
-- And this is after all messages are sent.
function Me.Gopher_THROTTLER_STOP()
	if not Gopher.AnyChannelsBusy() then
		Me.SendingText_Hide()
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
	CommunitiesFrame.ChatEditBox:SetVisibleTextByteLimit( 0 )
end

-------------------------------------------------------------------------------
-- Code for unlocking the TRP NPC frame.
-- Note to TRP authors: if you want to disable this functionality (due to TRP
--  doing something internally instead), set 
--  `EmoteSpliter.Internal.disable_trp_npc_extension`.
--
function Me.ExtendTRPNPCChat()
	if not TRP3_API then return end
	if Me.disable_trp_npc_extension then
		-- Another addon has disabled this, to handle it themselves.
		return
	end
	
	-- Callback for when the enter key is pressed or the send button is
	--  clicked.
	local function SendChat()
		local name    = strtrim( TRP3_NPCTalk.name:GetText() )
		local channel = TRP3_NPCTalk.channelDropdown:GetSelectedValue()
		local msg     = TRP3_NPCTalk.messageText.scroll.text:GetText()
		
		-- Quit if there is no message or there isn't a name.
		if #msg == 0 or #name == 0 then return end
		
		-- We're using TRP3's localization to get the "says:" string, etc.
		local padding = ""
		if channel == "MONSTER_SAY" then
			padding = TRP3_API.loc.NPC_TALK_SAY_PATTERN .. " "
		elseif channel == "MONSTER_YELL" then
			padding = TRP3_API.loc.NPC_TALK_YELL_PATTERN .. " "
		elseif channel == "MONSTER_WHISPER" then
			padding = TRP3_API.loc.NPC_TALK_WHISPER_PATTERN .. " "
		end
		
		-- Using Gopher's padding, to make it so that every split message is 
		--  prefixed with the npc name and action string.
		LibGopher.SetPadding( TRP3_API.chat.configNPCTalkPrefix()
		                                            .. name .. " " .. padding )
		print( msg )
		-- Gopher will pick up SendChatMessage and split the message 
		--  accordingly.
		SendChatMessage( msg, "EMOTE" )
		TRP3_NPCTalk.messageText.scroll.text:SetText( "" )
	end
	
	-- Callback for when anything is modifying the potential text length. This
	--  is also overwriting some other things like when the channel type is
	--  changed.
	local function OnTextChanged()
		local hasname = #strtrim(TRP3_NPCTalk.name:GetText()) > 0
		local hasmsg = #strtrim(TRP3_NPCTalk.messageText.scroll.text:GetText()) > 0
		
		if hasname and hasmsg then
			TRP3_NPCTalk.send:Enable()
		else
			TRP3_NPCTalk.send:Disable()
		end
	end
	
	TRP3_API.events.listenToEvent( TRP3_API.events.WORKFLOW_ON_FINISH, 
	                                                                 function()
		-- Replace the NPC chat frame's scripts.
		local send_button      = TRP3_NPCTalk.send
		local channel_dropdown = TRP3_NPCTalk.channelDropdown
		local message_text     = TRP3_NPCTalk.messageText.scroll.text
		local npc_name         = TRP3_NPCTalk.name
		
		send_button:SetScript( "OnClick", SendChat )
		message_text:SetScript( "OnEnterPressed", SendChat )
		message_text:SetScript( "OnEnterPressed", SendChat )
		
		-- Todo: find a nice compatible way to overwrite the channel dropdown
		--  callback.
		channel_dropdown.callback = OnTextChanged
		message_text:HookScript( "OnTextChanged", OnTextChanged )
		message_text:HookScript( "OnEditFocusGained", OnTextChanged )
		npc_name:HookScript( "OnTextChanged", OnTextChanged )
		npc_name:HookScript( "OnEditFocusGained", OnTextChanged )
		
		-- Hide the character limit, since there isn't one anymore. Maybe we 
		--  could just show the total characters?
		TRP3_NPCTalk.charactersCounter:Hide()
	end)
end

-- See you on Moon Guard! :)
--                ~              ~   The Great Sea ~                  ~
--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^-