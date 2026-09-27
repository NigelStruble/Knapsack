local _, ns = ...

-- Every string is written in English and looked up through L, so a missing
-- translation falls back to the English text. To translate, add a block for
-- the locale and assign only the strings that should change:
--
--   if GetLocale() == "deDE" then
--       L["Junk"] = "Plunder"
--   end
--
-- Item names, bag names and bank tab names come from the game client and never
-- need translating.

local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

ns.L = L
