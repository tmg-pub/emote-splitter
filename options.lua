
local Main = EmoteSplitter
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local g_loaded = false

-------------------------------------------------------------------------------
local DB_DEFAULTS = {
	global = {
		premark = "»";
		postmark = "»";
		fastpost = true;
		hidefailed = true;
		showsending = true;
	};
}

-------------------------------------------------------------------------------
local OPTIONS_TABLE = {
	type = "group";
	name = "EmoteSplitter";
	args = {
		desc = { 
			order = 10;
			name = "Version: " .. GetAddOnMetadata( "EmoteSplitter", "Version" ) .. "|nby Tammya-MoonGuard";
			type = "description";
		};
		
		postmark = {
			name = "Postfix Mark";
			desc = "Text to postfix split emotes. Leave blank to disable.";
			order = 20;
			type = "input"; 
			set = function( info, val ) Main.db.global.postmark = val:sub( 1, 10 ) end;
			get = function( info ) return Main.db.global.postmark end;
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
			set = function( info, val ) Main.db.global.premark = val:sub( 1, 10 ) end;
			get = function( info ) return Main.db.global.premark end;
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
			set = function( info, val ) Main.db.global.fastpost = val end;
			get = function( info ) return Main.db.global.fastpost end;
		};
		
		hidefailed = {
			name = "Hide Failure Messages";
			desc = "Hide the system messages when your chat is throttled.";
			order = 40;
			type = "toggle";
			width = "full";
			set = function( info, val ) Main.db.global.hidefailed = val end;
			get = function( info ) return Main.db.global.hidefailed end;
		};
		
		showsending = {
			name = "Show Sending Indicator";
			desc = "Show an indicator on the bottom-left corner of the screen when posts are currently being sent.";
			order = 50;
			type = "toggle";
			width = "full";
			set = function( info, val ) Main.db.global.showsending = val end;
			get = function( info ) return Main.db.global.showsending end;
		}
		
	};
}

-------------------------------------------------------------------------------
function Main:Options_Init()
	self.db = LibStub( "AceDB-3.0" ):New( 
					"EmoteSplitterSaved", DB_DEFAULTS, true )
	AceConfig:RegisterOptionsTable( "EmoteSplitter", OPTIONS_TABLE )
	AceConfigDialog:AddToBlizOptions( "EmoteSplitter", "Emote Splitter" )
end

-------------------------------------------------------------------------------
function Main:Options_Show() 
	InterfaceOptionsFrame_OpenToCategory( "Emote Splitter" )
end
