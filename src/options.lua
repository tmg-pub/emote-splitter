-------------------------------------------------------------------------------
-- This file sets up AceConfig in the Interface panel, as well as handles
--  creating the database for our options.
-------------------------------------------------------------------------------

-- Two arguments passed to the file are addonName and a table we can use to
local _, Me = ... -- share things between files.
local L = Me.Locale -- Easy access to our locale.

-- All of our libs are already safely present from embeds.xml running first.
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local Gopher          = LibGopher

-------------------------------------------------------------------------------
-- Another lib we're using in here is AceDB. It's initialized using a table
--  like this. Anything present here is the "default" option. AceDB saves any
--  value that you assign to it after the database is made, but if you try and
--  read a value that isn't set, it reads from this default table instead.
local DB_DEFAULTS = {
	-- The `global` table is applied to the player's account, globally.
	-- When you assign things to the global table, all of their characters
	--  share it.
	global = {
		-- This is the text that appends/prepends messages that have been split
		--  by our message splitter. An empty string ("") will disable that
		premark         = "»"; -- feature.
		postmark        = "»";
		
		-- This option hides failure messages in the chatbox, like the system
		hidefailed      = true;  -- message you get when your chat is throttled.
		
		-- This option enables the "Sending..." indicator at the corner of the
		showsending     = true;  -- screen.
		
		-- slowpost causes the throttler to always start after sending a
		--  message. In other words, when you're sending a message to a private
		--  channel, it'll always be sent in smaller chunks. It's merely an
		slowpost        = false;  -- aesthetic change.
		
		-- This option enables ctrl-z/ctrl-y functionality in the editbox.
		-- It's called protection and not something like undo because it's
		--  designed to protect your emotes if you disconnect.
		emoteprotection = true;
		
		-- EXPERIMENTAL: Prefer splitting long messages at quotation marks
		--  instead of whitespace. When enabled, dialogue wrapped in quotes
		--  will stay together across chunks. Off by default.
		quote_aware_split = false;
		
		-- Track if user has acknowledged the CrossRP warning
		crossrp_warning_acknowledged = false;

	};
	-- The `char` table is unique per character, meaning that each character
	--  the player has can store different data.
	char = {
		-- We use this section to store the undo history. Doesn't make much
		--  sense to have undo history shared by other characters, now does
		--  it? One nasty thing about this is that if you play one character,
		--  and then stop playing it for a while, you're going to keep that
		--  undo history cluttering up save data indefinitely. Maybe we should
		--  add a feature to purge other histories after so long.
		undo_history = {
			-- This is structured like this:
			--   First we index this with the chatbox number. There are up to
			--    ten chatboxs. The usual one in the lower left corner is
			--    chatbox 1. Layout of the entries looks like this:
			--
			-- [indexed by chatbox]
			--   position: Position in the buffer to next write to.
			--   history: Table of entries. Highest = newest.
			--     text: Chat text.
			--     cursor: Cursor position.
		};
	};
}

-------------------------------------------------------------------------------
-- This is for AceConfig. You lay out the options in here, and then they're
--  magically laid out in a UI for the user. Easy and simple!
local OPTIONS_TABLE = {

	-- This is the very top-level right here. As we go deeper into the `args`
	--  we get more nested in the UI. There are also ways to control this stuff
	--  through a command line interface, but I'm not familiar with it.
	-- This "group" encapsulates everything, and it will show up as
	--  Emote Splitter in the interface options.
	type = "group";
	name = "Emote Splitter";
	args = {
		-----------------------------------------------------------------------
		-- A "description" type entry just adds text to the panel. We're using
		desc = { -- one here to display version info and author. 
			-- The `order` value controls where these entities show up. Since 
			--  these are associateive keys in the table, this is necessary, 
			--  because otherwise LUA can  order these keys randomly
			order = 10; --  internally.
			-- Our little locale lookup function allows substitutions like 
			-- this. {1} is replaced with our addon version.
			-- `name` for description sections contains the text to fill the
			name = L( "Version: {1}", -- widget with.
			          C_AddOns.GetAddOnMetadata( "EmoteSplitter", "Version" ))
			       .. "|n" .. L["Updated by Lorthendor-MoonGuard, original code by Tammya-MoonGuard"];
			type = "description";
		};
		-----------------------------------------------------------------------
		-- CrossRP compatibility warning
		crossrp_warning = (function()
			if C_AddOns.IsAddOnLoaded("CrossRP") then
				return {
					order = 15;
					name = "|cffff0000WARNING: CrossRP Detected|r\n|cffff6600CrossRP is known to break Emote Splitter's functionality. Please disable CrossRP if you want Emote Splitter to work correctly.|r";
					type = "description";
					width = "full";
				}
			end
			return nil
		end)();
		-----------------------------------------------------------------------
		-- Each of these entries adds an element to the configuration UI, and
		--  they each control one of the options in our database.
		postmark = {
			-- Here's an example of an `input` entry, which is a textbox. This
			--  one controls the mark that we add to the end of messages when
			--  they're split and contined in the next one.
			-- `name` is the visible label above the textbox component.
			-- `desc` is the tooltip text that shows up when you hover over.
			name  = L["Postfix Mark"];
			desc  = L["Text added to the end of a message to mark that it's going to be continued. Leave blank to disable."];
			order = 20;
			type  = "input";
			
			-- These types of components have setters and getters. `get` is
			--  called once when the panel is opened, and then again after
			--  `set` is called to update the value you see after typing.
			-- This is fairly straightforward. In `set` we update our database
			--  with the new value. In `get` we read it.
			-- `info` is a table all about where we are in the config tree.
			--  It has things like this option's name, as well as its parents'
			--  names. We don't really use it. A good use for it is if we had
			--  like ten copies of this node, for ten different text strings
			--  that all work the same way (like with the clipping to 10
			--  characters max). In that case, we'd define the function outside
			--  and then reference the info table to know what we're supposed
			--  to write to. You can name these table entries to match your
			--  database entries to make things easy. I'm pretty sure you can
			--  set an `arg` item in here too, which is copied to info.
			set = function( info, val )
				-- Clip to a max of 10 characters.
				Me.db.global.postmark = val:sub( 1, 10 )
				Me.Options_Apply()
			end;
			get = function( info )
				return Me.db.global.postmark
			end;
		};
		-----------------------------------------------------------------------
		-- An empty `description` section like this is to just add a new line.
		-- Personally, I don't really like how AceConfig lays options out
		--  sometimes. I think it could use a feature to tell the layout system
		--  to add a newline after an option. For other items like check boxes
		--  you can set the width to full, to take up the whole line, but for
		desc1 = {                 -- text boxes (like above) it's going to be 
			name  = "";            -- stretched all the way across if you do 
			type  = "description"; --  that. SO, we just add this node here to 
			order = 21;            --  add a new line.
		};                         --
		-----------------------------------------------------------------------
		-- It was a bit of a design choice at first to have these separated.
		--  Like, most of the time the premark is going to match the postmark.
		--  Just seems better that way, in my opinion. But of course someone
		--  might want them to be different, or disable half of them. That's
		--  okay too. I considered having a checkbox to allow them to be
		--  different, but in the end that might be a bit of needless work
		premark = { -- for this simpler solution that's elegant enough already.
			name  = L["Prefix Mark"];
			-- I don't really like to split up lines that are just long
			--  strings. Makes it harder to read and even harder to manage.
			desc  = L["Text to add to the beginning of a message to mark that it's continuing the last one. Leave blank to disable."];
			order = 22;
			type  = "input";
			-- I'd say this is one of the greater strengths of scripting
			--  languages. Easy to pass around data and manipulate it. While
			--  strong typing is nice and efficient, and even a bit safer and
			--  less error prone, the ability to create an anonymous function
			--  like this and directly assign it to a table value is something
			--  that's arguably a lot cleaner than some of the other solutions
			set = function( info, val )          -- there are with lower level 
				Me.db.global.premark = val:sub( 1, 10 )         -- languages.
				Me.Options_Apply()
			end;
			get = function( info )
				return Me.db.global.premark
			end;
		};
		-----------------------------------------------------------------------
		-- Just like above, a dummy section to add a newline.
		desc2 = { name = ""; type = "description"; order = 23; };
		-----------------------------------------------------------------------
		-- Here's a checkbox node, `type` "toggle". `name` is still the label
		--  or caption for it, and `desc` is the tooltip text. We set the
		--  `width` to "full" to make it span the whole line. You can't really
		--  see the width for checkboxes (in the default UI at least) so this
		--  makes an easy way to keep your options in a neat list. Maybe it's
		hidefailed = {  -- not the best practice, but it looks better to me.
			name  = L["Hide Failure Messages"];
			desc  = L["Hide the system messages when your chat is throttled."];
			order = 40;
			type  = "toggle";
			width = "full";
			-- For "toggle" nodes, val is just a simple boolean value. As soon
			--  as you click it, `set` is called, and then `get`. The checkbox
			--  will follow what you return in `get`, and won't really toggle
			--  unless you allow it.
			set = function( info, val ) 
				Me.db.global.hidefailed = val 
				Me.Options_Apply()
			end;
			get = function( info ) return Me.db.global.hidefailed end;
		};
		-----------------------------------------------------------------------
		-- If we had a good handful of these checkboxes, I'd probably rewrite
		--  some of this, using a function to set up these sections instead of
		--  writing out all the data for each one. For example, order could be
		--  incremented automatically, and the only custom fields there are in
		--  here are `name`, `desc` and the index in the global table. That
		showsending = { -- index could match the node name even.
			name  = L["Show Sending Indicator"];
			desc  = L["Show an indicator on the bottom-left corner of the screen when posts are currently being sent."];
			order = 50;
			type  = "toggle";
			width = "full";
			set = function( info, val ) Me.db.global.showsending = val end;
			get = function( info ) return Me.db.global.showsending end;
		};


		-----------------------------------------------------------------------
		-- I was tempted to do that actually - make a nice, clean,
		--  toggle-making function. But here we have a prime example of why
		--  that's not the best idea. When you have the code typed out like
		--  this in full (which honestly isn't that bad if there's only a few
		--  instances of it being repeated), you have a lot more control. You 
		--  can change any value. Like here, in the setter function, we can
		--  notify the emote protection module.
		emoteprotection = {
			name  = L["Undo / Emote Protection"];
			desc  = L["Adds |cffffff00Ctrl-Z|r and |cffffff00Ctrl-Y|r keybinds to edit boxes for undo/redo functionality. This is especially for rescuing longer emotes if you click off accidentally or disconnect. If you lose your emote, |cffffff00Ctrl-Z|r!"];
			order = 60;
			type  = "toggle";
			width = "full";
			set = function( info, val ) 
				Me.db.global.emoteprotection = val 
				Me.EmoteProtection.OptionsChanged()
			end;
			get = function( info ) return Me.db.global.emoteprotection end;
		};
		
		-----------------------------------------------------------------------
		-- EXPERIMENTAL: Quote-aware splitting option
		quote_aware_split = {
			name  = L["Quote-Aware Splitting (Experimental)"];
			desc  = L["|cffff0000[EXPERIMENTAL]|r When enabled, long messages are split at quotation marks instead of whitespace. This keeps dialogue together across chunks. Disable this option to use the original splitting behavior."];
			order = 65;
			type  = "toggle";
			width = "full";
			set = function( info, val )
				Me.db.global.quote_aware_split = val
			end;
			get = function( info ) return Me.db.global.quote_aware_split end;
		};
		
		-----------------------------------------------------------------------
		-- I always struggle with trying to make things concise. Too little
		--  text or vague terms and the user won't understand. Too much
		--  clarification, and they just get confused or overwhelmed.
		--  This is where communication skills come into play, hm? Gotta think
		--  like an idiot to write for an idiot.
		--[[ This may be re-implemented later, but it's not a great investment.
		slowpost = {
			name  = L["Slow Post"];
			desc  = L["A purely aesthetic option to make Emote Splitter post only one or two messages at a time instead of all at once."];
			order = 70;
			type  = "toggle";
			width = "full";
			set = function( info, val ) 
				Me.db.global.slowpost = val 
			end;
			get = function( info ) return Me.db.global.slowpost end;
		};]]
		
	};
}

-------------------------------------------------------------------------------
-- Initialize our options module (if you can consider it a module). 
--                          -- Called from OnEnable in the main code.
function Me.Options_Init()

	-- `EmoteSplitterSaved` is defined in the TOC file. This variable is saved
	--  and loaded for us automatically. Care must be taken that this is called
	--  /after/ the addon loads, otherwise you might get some undefined
	--  behavior. The third param is the default profile. We don't use profiles
	--  but you can pass a name in here for the name of it, or `true`, like
	--  this, to save it as "Default". Maybe that's also a localized value?
	Me.db = LibStub( "AceDB-3.0" ):New( "EmoteSplitterSaved", 
	                                       DB_DEFAULTS, true )
	-- "EmoteSplitter" is our options ID.
	AceConfig:RegisterOptionsTable( "EmoteSplitter", OPTIONS_TABLE )
	AceConfigDialog:AddToBlizOptions( "EmoteSplitter", "Emote Splitter" )
	
	Me.Options_Apply()
end

-------------------------------------------------------------------------------
-- Call when certain options change that need to be passed to Gopher and such.
function Me.Options_Apply()
	Gopher.HideFailureMessages( Me.db.global.hidefailed )
	Gopher.SetSplitmarks( Me.db.global.premark, Me.db.global.postmark, true )

end

-------------------------------------------------------------------------------
-- Open up the Emote Splitter options in the Interface panel.
--
function Me.Options_Show() 
	-- A little bit of a dirty hack. The first time you open up the Interface
	--  panel, it's initializing or something, and won't open the page you
	--  want. So, we call this twice. We don't really need to call it twice
	--  after the first time, but it's a bit of needless work to add some kind
	--  of check when it doesn't really matter, does it? Nobody's gonna notice
	--  it setting up your options page twice.
	Settings.OpenToCategory( "Emote Splitter" )
end
