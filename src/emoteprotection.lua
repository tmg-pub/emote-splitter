-------------------------------------------------------------------------------
-- Now we're getting into some nitty gritty stuff. This file hooks chatbox
--  input so we can save the text from being lost and add "undo" functionality.
-------------------------------------------------------------------------------
local _, Me           = ...
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-- This is how many entries we keep in the undo buffer. How many times you can
--  press Ctrl-Z. We have a fairly primitive setup in what's considered a
--  section of text worthy to become a new history entry, but it works out
--  well enough. I'm not even sure what sort of algorithm people use when it
local HISTORY_SIZE = 20  -- comes to things like that.
-------------------------------------------------------------------------------
-- We have our own little mini module here!
local This = {
	hooked    = false;  -- Chat boxes are hooked.
	last_text = {};     -- Last text per-chatbox, to see if things change.
	last_pos  = {};     -- Last cursor position per-chatbox, to see if it
	                    --  moves.
}

Me.EmoteProtection = This

-------------------------------------------------------------------------------
-- Returns the editbox for chat frame `index`.
--
local function GetEditBox( index )
	return _G["ChatFrame" .. index .. "EditBox"]
end

-------------------------------------------------------------------------------
-- Called from Emote Splitter's OnEnable.
--
function This.Init()
	This.db = Me.db.char.undo_history -- A shortcut
	
	-- Priming the undo history now. Things like this might seem a little
	--  wasteful sometimes, but the plus side to preparing data like this is
	--  that it removes a lot of checks later in the code where you would
	--  normally have to detect if table entries exist.
	for i = 1, NUM_CHAT_WINDOWS do
		if not This.db[i] then
			This.db[i] = {
				position = 1;
				history = {
					{ -- The first history entry.
						text   = "";
						cursor = 0;
					}
				}
			}
		end
	end
	
	-- We can use our options changed function for initialization as well!
	-- We handle the hooks in here, after checking if the system is enabled.
	-- That way, we don't have any dummy hooks in place if they load the UI
	--  with this feature disabled.
	This.OptionsChanged()
end

-------------------------------------------------------------------------------
-- Loads the selected history entry for chatbox[index]. Essentially this is
--  called after changing the data.position to do the actual chatbox update.
--
local function LoadUndo( index )
	-- Each chatbox has their own data.
	local data = This.db[index]
	local editbox = GetEditBox( index )
	
	-- One improvement we can do here is set the chat type as well. We're only
	--  saving text and cursor position.
	editbox:SetText( data.history[data.position].text )
	editbox:SetCursorPosition( data.history[data.position].cursor )
end

-------------------------------------------------------------------------------
-- Rewind one step in the undo history and update this chatbox.
--
-- index: Chatbox index.
function This.Undo( index )
	local data = This.db[index]
	if data.position == 1 then return end -- no more undo history.
	This.AddUndoHistory( index, true )
	
	-- I can't actually remember why I have to do this check twice. But it's
	--  important, okay?
	if data.position == 1 then return end -- no more undo history.
	
	data.position = data.position - 1
	local editbox = GetEditBox( index )
	LoadUndo( index )
	
end

-------------------------------------------------------------------------------
-- Step forward one pace (or try to) and update this chatbox.
--
-- index: Chatbox index.
function This.Redo( index )
	local data = This.db[index]
	if data.position == #data.history then return end -- no more history
	
	-- While we might have some redo entries left, the textbox might have 
	--  actually changed. If it did change, then this call erases the redo
	--  history in favor of keeping these new changes.
	-- We pass true to `force` to make this happen even if they have one or
	--  two characters added. That's just the way it is. If you change
	--  something in the past, the future is wiped out.
	This.AddUndoHistory( index, true )
	
	-- And that's why we check again here. I have no clue why we do it twice
	--  in Undo.
	if data.position == #data.history then return end
	
	data.position = data.position + 1
	local editbox = GetEditBox( index )
	LoadUndo( index )
end

-------------------------------------------------------------------------------
-- Add history to the undo buffer.
--
-- index: Chatbox index.
-- force: If false, only add if there is a somewhat reasonable change.
--        Set to true if you have a finished product, e.g. when closing
--        the chatbox or sending the message.
-- custom_text: Use this instead of GetText()
--
function This.AddUndoHistory( index, force, custom_text, custom_pos )
	local data = This.db[index]
	local editbox = GetEditBox( index )
	local text = custom_text or editbox:GetText()
	
	if text == data.history[data.position].text then return end
	
	-- Here's a nasty piece of magic. We're checking if the difference in text
	--  is considerable enough for a new history entry. That's 20 chars longer
	--  or shorter than the prevoius entry. We also don't really care about
	--  empty text.
	if not force and 
	     (math.abs(text:len() - data.history[data.position].text:len()) < 20 
	      and text ~= "") then
		return 
	end	
	
	-- Write new entry.
	data.position = data.position + 1
	data.history[data.position] = {
		text = text;
		cursor = custom_pos or editbox:GetCursorPosition();
	}
	
	-- Erase redo history.
	for i = data.position+1, #data.history do
		data.history[i] = nil
	end
	
	-- And then trim to size limit. Typically this only triggers once unless
	--  something weird happened. I like to use while loops for things like
	--  this anyway in case...something weird happens.
	while #data.history > HISTORY_SIZE do
		table.remove( data.history, 1 )
		data.position = data.position - 1
	end
end

-------------------------------------------------------------------------------
-- Called from the various hooks to track changes in the chatbox text.
--
-- index: Index of chatbox.
-- text: Text of chatbox (might be overridden with "" for some events where
--       the chatbox closes/opens).
-- position: Cursor position.
-- force: Force history update for this event, even if the text is empty.
--
function This.MyTextChanged( index, text, position, force )
	local editbox = GetEditBox(index)
	-- This kind of stuff is typically very confusing to get right, and riddled
	--  with errors very similar to "off by one" problems, where you just gotta
	--  test it and tweak it until it works right. I mean look at this:
	
	if text == "" then
		-- What are we even doing?? We track the last_text value because when
		--  the user closes the chatbox, the text is basically eviscerated. We
		--  keep a copy of it here from the last keypress so that we can add
		--  an undo entry from their finished result. They probably want to
		--  save that, right? This system is more designed to save the user
		--  from losing their work than anything, from accidentally closing the
		--  editbox or getting disconnected while typing.
		if This.last_text[index] then
			This.AddUndoHistory( index, true, 
			                     This.last_text[index], This.last_pos[index] )
		end
	end
	
	-- And then after we save that text above... we still want to add another
	--  entry which is basically empty when we first open the chatbox. That
	--  way, when someone undoes something on the first node after, it 
	--  typing, it doesn't immediately show up with the last typed message. 
	--  It'll show up with empty text first before that.
	This.last_text[index] = text
	This.last_pos[index]  = position
	
	This.AddUndoHistory( index, force, text, position )
end

-------------------------------------------------------------------------------
-- These are hooks for the chat edit boxes. Each of these methods are passed
--  to HookScript during initialization for each of the chat editboxes.
This.EditboxHooks = {
-------------------------------------------------------------------------------
	OnTextChanged = function( self, index, user_input )
		-- `user_input` means that this chatbox changed from an actual 
		--  keypress. If it's false, then this was done from SetText. We exit
		--  out in that case so we don't trigger anything when we're pasting in
		--  a history entry with SetText.
		if not user_input then return end
		local editbox = GetEditBox(index)
		This.MyTextChanged( index, editbox:GetText(), 
		                    editbox:GetCursorPosition(), false )
	end;
-------------------------------------------------------------------------------
	OnKeyDown = function( self, index, key )
		-- Key down also works with key repetitions, meaning you'll receive
		--  multiple of these events if the key is held down.
		if IsControlKeyDown() then
			if key == "Z" then
				-- Undo.
				This.Undo( index )
			elseif key == "Y" then
				-- Redo.
				This.Redo( index )
			end
		end
	end;
-------------------------------------------------------------------------------
	OnShow = function( self, index )
		-- When we open a chat editbox, we want to add a nice and empty history
		--  entry to jump back to. We aren't sure if the text is cleared yet
		--  during this, so we pass the values manually.
		This.MyTextChanged( index, "", 0, true )
	end;
-------------------------------------------------------------------------------
	OnHide = function( self, index )
		-- Typically the above isn't needed since we are adding an empty entry
		--  in the bottom here. This is done for a different purpose though.
		-- When the editbox closes this should add two entries typically.
		-- One is the final text, and then the other is the empty entry. This
		--  is mainly to save their finished emote before it gets overwritten.
		This.MyTextChanged( index, "", 0, true )
	end;
}

-------------------------------------------------------------------------------
-- Go through the chatboxes and add our hooks.
--
function This.Hook()
	if This.hooked then return end
	
	This.hooked = true
	
	for i = 1,NUM_CHAT_WINDOWS do
		for script, handler in pairs( This.EditboxHooks ) do
			_G["ChatFrame" .. i .. "EditBox"]:HookScript( script,
				function( editbox, ... )
				
					-- Instead of having a check in each of the handlers, we
					--  just have a global disable right here!
					if not Me.db.global.emoteprotection then return end
					
					-- And then we forward to the handler.
					handler( editbox, i, ... )
				end)
		end
	end
end

-------------------------------------------------------------------------------
-- Called at start to load options, and from the options panel to re-load
--  options.
--
function This.OptionsChanged()
	-- We only have one option though, enable/disable.
	if Me.db.global.emoteprotection then
		This.Hook()
	end
end
