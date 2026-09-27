local _, ns = ...
local Categories = ns.Categories

-- What the search boxes understand. Words are separated by spaces, and an item
-- has to match every one of them:
--   part of a name   linen, wizard oil
--   a keyword        boe, bou, soulbound, tradable, junk, common, uncommon,
--                    rare, epic, legendary, gear, consumable, reagent,
--                    tradegoods, recipe, quest, new, charges, unusable
--   an item level    ilvl>30, ilvl>=30, ilvl<20, ilvl=25
-- A # in front of a word makes it a keyword only (#new); a ! turns a word
-- around (!soulbound).

local Search = {}
ns.Search = Search

local ipairs, lower, tonumber = ipairs, string.lower, tonumber
local CLASS = Categories.CLASS

local function Quality(quality)
	return function(rec, info)
		return (rec.quality or info.quality) == quality
	end
end

local function Class(...)
	local classes = {}
	for _, classID in ipairs({ ... }) do
		classes[classID] = true
	end
	return function(_, info)
		return classes[info.classID] == true
	end
end

local function Binding(bind)
	return function(rec, info)
		return Categories.HasBinding(bind, rec, info)
	end
end

local KEYWORDS = {
	boe = Binding("boe"),
	bou = Binding("bou"),
	soulbound = Binding("bound"),
	tradable = Binding("unbound"),
	tradeable = Binding("unbound"),
	junk = Quality(0),
	poor = Quality(0),
	common = Quality(1),
	uncommon = Quality(2),
	rare = Quality(3),
	epic = Quality(4),
	legendary = Quality(5),
	gear = function(_, info)
		return info.isGear == true
	end,
	consumable = Class(CLASS.Consumable),
	reagent = Class(CLASS.Reagent),
	tradegoods = Class(CLASS.Tradegoods, CLASS.Gem, CLASS.ItemEnhancement),
	recipe = Class(CLASS.Recipe),
	quest = function(rec, info)
		return rec.isQuest == true or info.classID == CLASS.Questitem
	end,
	new = function(rec)
		return rec.isNew == true
	end,
	charges = function(rec)
		return rec.charges ~= nil
	end,
	unusable = function(rec)
		return rec.unusable == true
	end,
}
KEYWORDS.consumables, KEYWORDS.reagents, KEYWORDS.recipes = KEYWORDS.consumable, KEYWORDS.reagent, KEYWORDS.recipe
KEYWORDS.equipment = KEYWORDS.gear
Search.KEYWORDS = KEYWORDS

local function ItemLevel(op, level)
	return function(_, info)
		local itemLevel = info.showLevel and info.itemLevel
		if not itemLevel then
			return false
		elseif op == ">" then
			return itemLevel > level
		elseif op == ">=" then
			return itemLevel >= level
		elseif op == "<" then
			return itemLevel < level
		elseif op == "<=" then
			return itemLevel <= level
		end
		return itemLevel == level
	end
end

local function Named(text)
	return function(rec)
		return (rec.sortName or ""):find(text, 1, true) ~= nil
	end
end

local function Never()
	return false
end

-- A test for records (with .info and .sortName, see Window.lua: Prepare), or
-- nil when the text has nothing to search for.
function Search.Compile(text)
	local tests = {}
	for word in lower(text or ""):gmatch("%S+") do
		local negate = #word > 1 and word:sub(1, 1) == "!"
		if negate then
			word = word:sub(2)
		end
		local test
		local op, level = word:match("^ilvl([<>]?=?)(%d+)$")
		if op then
			test = ItemLevel(op == "" and "=" or op, tonumber(level))
		elseif #word > 1 and word:sub(1, 1) == "#" then
			test = KEYWORDS[word:sub(2)] or Never
		else
			test = KEYWORDS[word] or Named(word)
		end
		if negate then
			local inner = test
			test = function(rec, info)
				return not inner(rec, info)
			end
		end
		tests[#tests + 1] = test
	end
	if #tests == 0 then
		return nil
	end
	return function(rec)
		local info = rec.info or {}
		for i = 1, #tests do
			if not tests[i](rec, info) then
				return false
			end
		end
		return true
	end
end
