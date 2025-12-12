-------------------------------------------------------------------------------
-- Some nice localization to make those other people in the world feel right
--  at home too.
-------------------------------------------------------------------------------

local _, Me = ...

-------------------------------------------------------------------------------
-- First of all, we have this table filled with localization strings.
-- In bigger projects, this can get quite massive. We don't have that many
-- strings, but we'll still use some decent practices so we don't have a bunch 
-- of stuff lying around in memory;
local Locales = { -- For example, we'll delete this big table after 
	enUS = {      --  we get what we want from it.
	
		-----------------------------------------------------------------------
		-- Any 'long string' entries need to be defined in here. Most of the
		-- keys are already english translations, and don't need to be defined
		-- here for English.
		-----------------------------------------------------------------------
		
	};
}

---------------------------------------------------------------------------
-- Other languages imported from Curse during packaging.
---------------------------------------------------------------------------

Locales.frFR = {
	-- The author note in the options panel.
	["by Tammya-MoonGuard"] = "Par Tammya-MoonGuard",
	-- This is printed in chat when your chat times out due to a disconnection issue or such.
	["Chat failed!"] = "Erreur d'envoi de message !",
	-- If UCM is installed, Emote Splitter disables itself and then prints this error in chat.
	["Emote Splitter cannot run with UnlimitedChatMessage enabled."] = "\"Emote Splitter\" ne peut fonctionner tant qu' \"UnlimitedChatMessage\" est activé.",
	-- Postfix Mark label in the options panel.
	["Postfix Mark"] = "Suffixes",
	-- Prefix Mark label in the options panel.
	["Prefix Mark"] = "Préfixes",
	-- The text for the prompt to continue sending a message.
	["Press enter to continue."] = "Appuyez sur Entrée pour continuer.",
	-- Emote Splitter can print this in chat when it starts re-sending a failed message. (Usually this notification is turned off.)
	["Resending..."] = "Nouvelle tentative d'envoi en cours....",
	-- Postfix Mark tooltip in the options panel.
	["Text added to the end of a message to mark that it's going to be continued. Leave blank to disable."] = [=[Texte ajouté à la fin de votre message pour signifier que celui-ci n'est pas terminé et sera continué. 



Par exemple : 

Message 1 - Aujourd'hui, j'ai été à ...

Message 2 - La Piscine.]=],
	-- Prefix Mark tooltip in the options panel.
	["Text to add to the beginning of a message to mark that it's continuing the last one. Leave blank to disable."] = [=[Texte ajouté au début de votre message pour signifier que celui-ci est la suite dû message d'avant. 



Par exemple : 

Message 1 - Aujourd'hui, j'ai été à 

Message 2 - ...la Piscine.]=],
	-- The version label in the options panel. {1} is replaced with the addon version like "1.3.4".
	["Version: {1}"] = "Version: {1}"
}
Locales.deDE = {
	["by Tammya-MoonGuard"] = "von Tammya-MoonGuard",
	["Chat failed!"] = "Chat Fehlgeschlagen!",
	["Emote Splitter cannot run with UnlimitedChatMessage enabled."] = "Emote Splitter ist nicht nutzbar mit UnlimitedChatmessage ",
	["Postfix Mark"] = "Postfix Zeichen",
	["Prefix Mark"] = "Prefix Zeichen",
	["Resending..."] = "Wiederhole...",
	["Text added to the end of a message to mark that it's going to be continued. Leave blank to disable."] = "Text an das Ende der Nachricht fügen um zu makieren das es noch weitergeht. Freilassen zum ausschalten",
	["Text to add to the beginning of a message to mark that it's continuing the last one. Leave blank to disable."] = "Text an den Anfang der Nachricht fügen um zu makieren das es zum letzten gehört . Freilassen zum ausschalten",
	["Version: {1}"] = "Version:{1}"
}
Locales.itIT = {
}
Locales.koKR = {
}
Locales.zhCN = {
	["by Tammya-MoonGuard"] = "作者：Tammya-月亮守卫（US）",
	["Chat failed!"] = "发送失败！",
	["Emote Splitter cannot run with UnlimitedChatMessage enabled."] = "Emote Splitter不能与UnlimitedChatMessage同时运行。",
	["Postfix Mark"] = "后缀标记",
	["Prefix Mark"] = "前缀标记",
	["Resending..."] = "重新发送中……",
	["Text added to the end of a message to mark that it's going to be continued. Leave blank to disable."] = "在信息末尾添加的用于标记其仍将继续的字符，如要禁用请留空。",
	["Text to add to the beginning of a message to mark that it's continuing the last one. Leave blank to disable."] = "在信息开始添加的用于标记其仍将继续的字符，如要禁用请留空。",
	["Version: {1}"] = "版本：{1}"
}
Locales.zhTW = {
	["by Tammya-MoonGuard"] = "作者：Tammya-月亮守衛（US）",
	["Chat failed!"] = "發送失敗！",
	["Emote Splitter cannot run with UnlimitedChatMessage enabled."] = "Emote Splitter不能與UnlimitedChatMessage同時運行。",
	["Postfix Mark"] = "後綴標記",
	["Prefix Mark"] = "前綴標記",
	["Resending..."] = "重新發送中……",
	["Text added to the end of a message to mark that it's going to be continued. Leave blank to disable."] = "在信息末尾添加的用於標記其仍將繼續的字符，如要禁用請留空。",
	["Text to add to the beginning of a message to mark that it's continuing the last one. Leave blank to disable."] = "在信息開始添加的用於標記其仍將繼續的字符，如要禁用請留空。",
	["Version: {1}"] = "版本：{1}"
}
Locales.ruRU = {
	["by Tammya-MoonGuard"] = "Автор: Tammya-MoonGuard",
	["Chat failed!"] = "Проблемы с подключением к чату!",
	["Emote Splitter cannot run with UnlimitedChatMessage enabled."] = "Emote Splitter не может быть запущен одновременно с UnlimitedChatMessage.",
	["Postfix Mark"] = "Постфикс",
	["Prefix Mark"] = "Префикс",
	["Resending..."] = "Повторная отправка...",
	["Text added to the end of a message to mark that it's going to be continued. Leave blank to disable."] = "Этот текст будет добавлен к концу Вашего сообщения,чтобы указать,что это сообщение будет продолжено в дальнейшем. Оставьте поле пустым,чтобы выключить эту функцию.",
	["Text to add to the beginning of a message to mark that it's continuing the last one. Leave blank to disable."] = "Этот текст будет добавлен в начале Вашего сообщения,чтобы указать,что это сообщение является продолжением предыдущего. Оставьте поле пустым,чтобы выключить эту функцию. ",
	["Version: {1}"] = "Версия: {1}"
}
Locales.esES = {
	["by Tammya-MoonGuard"] = "por Tammya-MoonGuard"
}
Locales.esMX = {
}
Locales.ptBR = {
}

-------------------------------------------------------------------------------
-- What we do now is take the enUS table, and then merge it with whatever
-- locale the client is using. Just paste it on top, and any untranslated
local locale_strings = Locales.enUS  -- strings will remain English.

do
	local client_locale = GetLocale() -- Gets the WoW locale.
	
	-- Skip this if they're using the English client, or if we don't support
	-- the locale they're using (no strings defined).
	if client_locale ~= "enUS" and Locales[client_locale] then
		-- Go through the foreign locale strings and overwrite the English
		--  entries. I hate using the word "foreign"; it seems like I'm
		--  treating non-English speakers as aliens, ehe...
		for k, v in pairs( Locales[client_locale] ) do
			locale_strings[k] = v
		end
	end
end

-------------------------------------------------------------------------------
-- Now we've got our merged table, so we can throw away the original data for
Locales = nil -- everything. Just blow up this old Locales table.

-------------------------------------------------------------------------------
-- And here we have the main Locale API. It's simple, but has some cool
Me.Locale = setmetatable( {}, { -- features. Normally, this table will be 
                                  --  stored in a local variable called L.

	-- If we access it like L["KEY"] or L.KEY then it's a direct lookup into
	--  our locale table. If it doesn't exist, then it uses the key directly.
	__index = function( table, key ) -- Most of the translations' keys are
		return locale_strings[key]   --  literal English translations.
		       or key
	end;
	
	-- If we treat the locale table like a function, then we can do 
	--  substitutions, like `L( "string {1}", value )`.
	__call = function( table, key, ... )
		-- First we get the translation. Note this isn't a raw access, so
		key = table[key] -- this goes through the __index metamethod 
		                 -- too if it doesn't exist.
		-- Pack args into a table; iterate over them.
		local args = {...}
		for i = 1, #args do
			-- And replace {1}, {2} etc with them.
			key = key:gsub( "{" .. i .. "}", args[i] )
		end
		return key
	end;
})