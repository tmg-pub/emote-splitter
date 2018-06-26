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
local locale_set = {}
--@localization(locale="frFR", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.frFR = locale_set
--@localization(locale="deDE", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.deDE = locale_set
--@localization(locale="itIT", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.itIT = locale_set
--@localization(locale="koKR", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.koKR = locale_set
--@localization(locale="zhCN", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.zhCN = locale_set
--@localization(locale="zhTW", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.zhTW = locale_set
--@localization(locale="ruRU", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.ruRU = locale_set
--@localization(locale="esES", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.esES = locale_set
--@localization(locale="esMX", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.esMX = locale_set
--@localization(locale="ptBR", format="lua_table", table-name="locale_set", handle-unlocalized="ignore")@
Locales.ptBR = locale_set

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