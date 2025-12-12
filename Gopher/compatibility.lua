-------------------------------------------------------------------------------
-- Gopher
-- by Tammya-MoonGuard (Copyright 2018)
--
-- All Rights Reserved.
-------------------------------------------------------------------------------
local Me = LibGopher.Internal
if not Me.load then return end

-------------------------------------------------------------------------------
-- This is executed on the next frame after PLAYER_LOGIN, so any addons should 
--                                                     be initialized already.
function Me.AddCompatibilityLayers()
	Me.UCMCompatibility()
	Me.MisspelledCompatibility()
	Me.TonguesCompatibility()
end

-------------------------------------------------------------------------------
-- Compatibility for UnlimitedChatMessage.
--
function Me.UCMCompatibility()
	if Me.compatibility_ucm then return end
	if not UCM then return end -- No UCM
	if UCM.core.hooks.SendChatMessage then
		Me.compatibility_ucm = true
		-- Basically... we just shut down most of UCM. Just the chatbox
		--  extension code is left.
		UCM.core:Unhook( "SendChatMessage" )
	end
end

-------------------------------------------------------------------------------
-- Handle compatibility for the Misspelled addon.
--
function Me.MisspelledCompatibility()
	if Me.compatibility_misspelled then return end
	if not Misspelled then return end
	if not Misspelled.hooks or not Misspelled.hooks.SendChatMessage then 
		-- Something changed.
		return
	end
	
	Me.compatibility_misspelled = true
	
	-- The Misspelled addon inserts color codes that are removed in its own
	--  hooks to SendChatMessage. This isn't ideal, because it can set up its
	--  hooks in the wrong "spot". In other words, its hooks might execute 
	--  AFTER we've already cut up the message to proper sizes, meaning that 
	--  it's going to make our slices even smaller, filled with a lot of empty
	--  space.
	-- What we do in here is unhook that code and then do it ourselves in one
	Misspelled:Unhook( "SendChatMessage" )	      -- of our own chat filters. 
	Me.Listen( "CHAT_NEW", function( event, text, ... )
		text = Misspelled:RemoveHighlighting( text )
		return text, ...
	end)
end

-------------------------------------------------------------------------------
-- This isn't /really/ compatible, as Tongues' protocol doesn't even support
--  split messages.
function Me.TonguesCompatibility()
	if Me.compatibility_tongues then return end
	if not Tongues then return end -- No Tongues.
	
	Me.compatibility_tongues = true
	
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
		Me.AddChatFromStartEvent( ... )
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
	
	Me.Listen( "CHAT_NEW", function( event, msg, type, _, target )
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
