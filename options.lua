
local _, Me = ...
local L = Me.Locale

local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-------------------------------------------------------------------------------
local DB_DEFAULTS = {
	global = {
		premark         = "»";
		postmark        = "»";
		fastpost        = true;
		hidefailed      = true;
		showsending     = true;
		emoteprotection = true;
	};
	char = {
		undo_history = {
			-- undo history for emote protection.
			-- [chatbox index] = {
			--   position = position in buffer to next write to
			--   history[index, highest=newest] = {
			--     text = chat text
			--     cursor = cursor position
			--   }
			-- }
		};
	};
}

-------------------------------------------------------------------------------
local OPTIONS_TABLE = {
	type = "group";
	name = "Emote Splitter";
	args = {
		desc = {
			order = 10;
			name = L( "Version: {1}", GetAddOnMetadata( "EmoteSplitter", "Version" )) 
			       .. "|n" .. L["by Tammya-Moonguard"];
			type = "description";
		};
		
		postmark = {
			name = "Postfix Mark";
			desc = "Text to postfix split emotes. Leave blank to disable.";
			order = 20;
			type = "input";
			set = function( info, val ) Me.db.global.postmark = val:sub( 1, 10 ) end;
			get = function( info ) return Me.db.global.postmark end;
		};
		
		desc1 = {
			name = "";
			type = "description";
			order = 21;
		};
		
		premark = {
			name = "Prefix Mark";
			desc = "Text to prefix continued emotes. Leave blank to disable.";
			order = 22;
			type = "input"; 
			set = function( info, val ) Me.db.global.premark = val:sub( 1, 10 ) end;
			get = function( info ) return Me.db.global.premark end;
		};
		
		desc2 = {
			name = "";
			type = "description";
			order = 23;
		};
		
		fastpost = {
			name = "Fast Post";
			desc = "Causes the system to cheat a little to allow quicker posts. -Technically-, it's less stable (in that you may DC when posting a lot), but it would be very rare. If disabled, then you may see short delays (not from your latency) when posting.";
			order = 30;
			type = "toggle";
			width = "full";
			set = function( info, val ) Me.db.global.fastpost = val end;
			get = function( info ) return Me.db.global.fastpost end;
		};
		
		hidefailed = {
			name = "Hide Failure Messages";
			desc = "Hide the system messages when your chat is throttled.";
			order = 40;
			type = "toggle";
			width = "full";
			set = function( info, val ) Me.db.global.hidefailed = val end;
			get = function( info ) return Me.db.global.hidefailed end;
		};
		
		showsending = {
			name = "Show Sending Indicator";
			desc = "Show an indicator on the bottom-left corner of the screen when posts are currently being sent.";
			order = 50;
			type = "toggle";
			width = "full";
			set = function( info, val ) Me.db.global.showsending = val end;
			get = function( info ) return Me.db.global.showsending end;
		};
		
		emoteprotection = {
			name = "Undo / Emote Protection";
			desc = "Adds |cffffff00Ctrl-Z|r and |cffffff00Ctrl-Y|r keybinds to edit boxes for undo/redo functionality. This is especially for rescuing longer emotes if you click off accidentally or disconnect. If you lose your emote, |cffffff00Ctrl-Z|r!";
			order = 60;
			type = "toggle";
			width = "full";
			set = function( info, val ) 
				Me.db.global.emoteprotection = val 
				Me.EmoteProtection.OptionsChanged()
			end;
			get = function( info ) return Me.db.global.emoteprotection end;
		};
		
	};
}

-------------------------------------------------------------------------------
function Me.Options_Init()
	Me.db = LibStub( "AceDB-3.0" ):New( "EmoteSplitterSaved", 
	                                      DB_DEFAULTS, true )
	AceConfig:RegisterOptionsTable( "EmoteSplitter", OPTIONS_TABLE )
	AceConfigDialog:AddToBlizOptions( "EmoteSplitter", "Emote Splitter" )
end

-------------------------------------------------------------------------------
function Me.Options_Show() 
	InterfaceOptionsFrame_OpenToCategory( "Emote Splitter" )
	InterfaceOptionsFrame_OpenToCategory( "Emote Splitter" )
end
