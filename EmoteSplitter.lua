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


-- See you on Moon Guard! :)
--                ~              ~   The Great Sea ~                  ~
--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^--^-