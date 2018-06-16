-------------------------------------------------------------------------------
-- Yeah, this is a pretty nasty section, as is anything when it comes to
--  modding existing interfaces.
-------------------------------------------------------------------------------
local _, Me           = ...
local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local HISTORY_SIZE = 20

-------------------------------------------------------------------------------
local This = {
	hooked    = false;
	last_text = {};
	last_pos  = {};
	undoing   = false;
}

Me.EmoteProtection = This

local function GetEditBox( index )
	return _G["ChatFrame" .. index .. "EditBox"]
end

-------------------------------------------------------------------------------
function This.Init()
	This.OptionsChanged()
	This.db = Me.db.char.undo_history
	
	-- prime undo history
	for i = 1, NUM_CHAT_WINDOWS do
		if not This.db[i] then
			This.db[i] = {
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
function This.OnEditboxChange( editbox, user_input, chat_index )
	if not Me.db.global.emoteprotection then return end
	
	Me.db.global.emotewips[chat_index] = editbox:GetText()
end

-------------------------------------------------------------------------------
local function LoadUndo( index )
	local data = This.db[index]
	local editbox = GetEditBox( index )
	-- set the editbox text to the current undo data
	This.undoing = true
	
	editbox:SetText( data.history[data.position].text )
	editbox:SetCursorPosition( data.history[data.position].cursor )
	
	This.undoing = false
end

-------------------------------------------------------------------------------
function This.Undo( index )
	local data = This.db[index]
	if data.position == 1 then return end -- no more undo history.
	This.AddUndoHistory( index, true )
	if data.position == 1 then return end -- no more undo history.
	
	data.position = data.position - 1
	local editbox = GetEditBox( index )
	LoadUndo( index )
	
end

-------------------------------------------------------------------------------
function This.Redo( index )
	local data = This.db[index]
	if data.position == #data.history then return end -- no more history
	This.AddUndoHistory( index, true )
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
function This.AddUndoHistory( index, force, custom_text, custom_pos )
	local data = This.db[index]
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
function This.MyTextChanged( index, text, position, force )
	local editbox = GetEditBox(index)
	
	if text == "" then
		if This.last_text[index] then
			This.AddUndoHistory( index, true, This.last_text[index], This.last_pos[index] )
		end
	end
	
	This.last_text[index] = text
	This.last_pos[index]  = position
	
	This.AddUndoHistory( index, force, text, position )
end

-------------------------------------------------------------------------------
This.EditboxHooks = {
-------------------------------------------------------------------------------
	OnTextChanged = function( self, index, user_input )
		if not user_input then return end
		
		local editbox = GetEditBox(index)
		This.MyTextChanged( index, editbox:GetText(), editbox:GetCursorPosition(), false )
	end;
-------------------------------------------------------------------------------
	OnKeyDown = function( self, index, key )
	
		if IsControlKeyDown() then
			if key == "Z" then
				-- Undo
				This.Undo( index )
			elseif key == "Y" then
				-- Redo
				This.Redo( index )
			end
		end
	end;
-------------------------------------------------------------------------------
	OnShow = function( self, index )
		-- clean undo history
		This.MyTextChanged( index, "", 0, true )
	end;
-------------------------------------------------------------------------------
	OnHide = function( self, index )
		-- save emote if clicked off.
		local text = GetEditBox(index):GetText()
		This.MyTextChanged( index, "", 0, true )
	end;
}

-------------------------------------------------------------------------------
function This.Hook()
	if This.hooked then return end
	
	This.hooked = true
	
	-- hook all chatboxes
	for i = 1,10 do
		for script, handler in pairs( This.EditboxHooks ) do
			_G["ChatFrame" .. i .. "EditBox"]:HookScript( script,
				function( editbox, ... )
				
					-- we have global disable here.
					if not Me.db.global.emoteprotection then return end
					
					handler( editbox, i, ... )
				end)
		end
	end
end

-------------------------------------------------------------------------------
function This.OptionsChanged()
	if Me.db.global.emoteprotection then
		This.Hook()
	end
end
