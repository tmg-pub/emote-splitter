
local Main            = EmoteSplitter
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local HISTORY_SIZE = 20

-------------------------------------------------------------------------------
local Me = {
	hooked    = false;
	last_text = {};
	last_pos  = {};
}

-- for stopping hooks
local g_undoing = false

Main.EmoteProtection = Me

local function GetEditBox( index )
	return _G["ChatFrame" .. index .. "EditBox"]
end

-------------------------------------------------------------------------------
function Me.Init()
	Me.OptionsChanged()
	Me.db = Main.db.char.undo_history
	
	-- prime undo history
	for i = 1, 10 do
		if not Me.db[i] then
			Me.db[i] = {
				position = 1;
				history = {
					{
						text   = "";
						cursor = 0;
					}
				}
			}
		end
	end
end

-------------------------------------------------------------------------------
function Me.OnEditboxChange( editbox, user_input, chat_index )
	if not Main.db.global.emoteprotection then return end
	
	Main.db.global.emotewips[chat_index] = editbox:GetText()
end

-------------------------------------------------------------------------------
local function LoadUndo( index )
	local data = Me.db[index]
	local editbox = GetEditBox( index )
	-- set the editbox text to the current undo data
	g_undoing = true
	
	editbox:SetText( data.history[data.position].text )
	editbox:SetCursorPosition( data.history[data.position].cursor )
	
	g_undoing = false
end

-------------------------------------------------------------------------------
function Me.Undo( index )
	local data = Me.db[index]
	if data.position == 1 then return end -- no more undo history.
	Me.AddUndoHistory( index, true )
	if data.position == 1 then return end -- no more undo history.
	
	data.position = data.position - 1
	local editbox = GetEditBox( index )
	LoadUndo( index )
	
end

-------------------------------------------------------------------------------
function Me.Redo( index )
	local data = Me.db[index]
	if data.position == #data.history then return end -- no more history
	Me.AddUndoHistory( index, true )
	if data.position == #data.history then return end -- cant redo here.
	
	data.position = data.position + 1
	local editbox = GetEditBox( index )
	LoadUndo( index )
end

-------------------------------------------------------------------------------
-- Add history to the undo buffer.
--
-- @param index Chatbox index.
-- @param force If false, only add if there is a somewhat reasonable change.
--               Set to true if you have a finished product, e.g. when closing
--               the chatbox or sending the message.
-- @param custom_text Use this instead of GetText()
--
function Me.AddUndoHistory( index, force, custom_text, custom_pos )
	local data = Me.db[index]
	local editbox = GetEditBox( index )
	local text = custom_text or editbox:GetText()
	
	if text == data.history[data.position].text then return end
	if not force and (math.abs(text:len() - data.history[data.position].text:len()) < 20 and text ~= "") then return end	
	
	-- write new entry
	data.position = data.position + 1
	data.history[data.position] = {
		text = text;
		cursor = custom_pos or editbox:GetCursorPosition();
	}
	
	-- invalidate redo
	for i = data.position+1, #data.history do
		data.history[i] = nil
	end
	
	-- and then trim to size limit
	while #data.history > HISTORY_SIZE do
		table.remove( data.history, 1 )
		data.position = data.position - 1
	end
end

-------------------------------------------------------------------------------
function Me.MyTextChanged( index, text, position, force )
	local editbox = GetEditBox(index)
	
	if text == "" then
		if Me.last_text[index] then
			Me.AddUndoHistory( index, true, Me.last_text[index], Me.last_pos[index] )
		end
	end
	
	Me.last_text[index] = text
	Me.last_pos[index]  = position
	
	Me.AddUndoHistory( index, force, text, position )
end

-------------------------------------------------------------------------------
Me.EditboxHooks = {
-------------------------------------------------------------------------------
	OnTextChanged = function( self, index, user_input )
		if not user_input then return end
		
		local editbox = GetEditBox(index)
		Me.MyTextChanged( index, editbox:GetText(), editbox:GetCursorPosition(), false )
	end;
-------------------------------------------------------------------------------
	OnKeyDown = function( self, index, key )
	
		if IsControlKeyDown() then
			if key == "Z" then
				-- Undo
				Me.Undo( index )
			elseif key == "Y" then
				-- Redo
				Me.Redo( index )
			end
		end
	end;
-------------------------------------------------------------------------------
	OnShow = function( self, index )
		-- clean undo history
		Me.MyTextChanged( index, "", 0, true )
	end;
-------------------------------------------------------------------------------
	OnHide = function( self, index )
		-- save emote if clicked off.
		local text = GetEditBox(index):GetText()
		Me.MyTextChanged( index, "", 0, true )
	end;
-------------------------------------------------------------------------------
--	OnEscapePressed = function( self, index )
--		Me.AddUndoHistory( index, true )
--	end
}

-------------------------------------------------------------------------------
function Me.Hook()
	if Me.hooked then return end
	
	Me.hooked = true
	
	-- hook all chatboxes
	for i = 1,10 do
		for script, handler in pairs( Me.EditboxHooks ) do
			_G["ChatFrame" .. i .. "EditBox"]:HookScript( script,
				function( editbox, ... )
				
					-- we have global disable here.
					if not Main.db.global.emoteprotection then return end
					
					handler( editbox, i, ... )
				end)
		end
	end
end

-------------------------------------------------------------------------------
function Me.OptionsChanged()
	if Main.db.global.emoteprotection then
		Me.Hook()
	end
end
