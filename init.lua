
-- Create our main addon object. This file needs to be loaded first so the 
--  other files can populate this object with their sub-sections and what not.
EmoteSplitter = LibStub("AceAddon-3.0"):NewAddon( "EmoteSplitter", 

	-- Mixins:
	"AceHook-3.0",  --> We use AceHook to hook the game's chat message
	               --    functions.
	"AceEvent-3.0"  --> And we use AceEvent for listening to the game's 
	               --    chat message events, among other things we might
	               --    want to spy on.
)
