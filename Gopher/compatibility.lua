-------------------------------------------------------------------------------
-- Gopher
-- by Tammya-MoonGuard (Copyright 2018)
--
-- All Rights Reserved.
-------------------------------------------------------------------------------
local Me = LibGopher.Internal
if not Me.load then return end

-------------------------------------------------------------------------------
-- This is executed one second after PLAYER_LOGIN, so any addons should be
--                                                        initialized already.
function Me.AddCompatibilityLayers()
	if Me.compat then return end
	Me.compat = VERSION
	
	Me.UCMCompatibility()
end

-------------------------------------------------------------------------------
function Me.UCMCompatibility()
	if not UCM then return end -- No UCM
	if UCM.core.hooks.SendChatMessage then
		-- Unhook UCM's system.
		UCM.core:Unhook( "SendChatMessage" )
	end
end
