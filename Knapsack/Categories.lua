local _, ns = ...
local L, DB = ns.L, ns.DB

-- Categories decide which section of a window an item goes in. An item goes to
-- the first of these that takes it:
--   1. the category it was dragged into (an item assignment)
--   2. a custom category whose rules match, in list order
--   3. Junk, if the item is Poor (grey) quality
--   4. Quest Items
--   5. the category for its item type (Equipment, Consumables, ...)
--   6. Miscellaneous
-- Hidden categories are skipped, so their items fall through to the next one.
-- Sections are shown in list order, which the user can change.
--
-- Saved in DB.categories:
--   order   category keys, in display order
--   hidden  [key] = true
--   names   [key] = new name, for renamed categories
--   custom  [key] = { name, quality, class, text, bind }; rules left out match
--           anything, a category without rules only holds items dragged into it.
--           bind: "boe" and "bou" (Bind on Equip / on Use, not bound yet),
--           "bound" (soulbound) or "unbound"
--   items   [itemID] = key, items dragged into a category
--   nextID  number for the next custom category key

local Categories = {}
ns.Categories = Categories

local _G = _G
local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local lower, tinsert, tremove = string.lower, table.insert, table.remove

local ItemClass = (_G.Enum and _G.Enum.ItemClass) or {}
local function Class(name, fallback)
	return ItemClass[name] or fallback
end

Categories.CLASS = {
	Consumable = Class("Consumable", 0),
	Container = Class("Container", 1),
	Weapon = Class("Weapon", 2),
	Gem = Class("Gem", 3),
	Armor = Class("Armor", 4),
	Reagent = Class("Reagent", 5),
	Projectile = Class("Projectile", 6),
	Tradegoods = Class("Tradegoods", 7),
	ItemEnhancement = Class("ItemEnhancement", 8),
	Recipe = Class("Recipe", 9),
	Quiver = Class("Quiver", 11),
	Questitem = Class("Questitem", 12),
	Key = Class("Key", 13),
	Miscellaneous = Class("Miscellaneous", 15),
}
local CLASS = Categories.CLASS

-- In default display order.
local BUILT_IN = {
	{ key = "equipment", name = L["Equipment"], classes = { CLASS.Weapon, CLASS.Armor } },
	{ key = "consumables", name = L["Consumables"], classes = { CLASS.Consumable } },
	-- Spell reagents (Sacred Candles, Arcane Powder, Runes of Teleportation).
	{ key = "reagents", name = L["Reagents"], classes = { CLASS.Reagent } },
	{ key = "tradegoods", name = L["Trade Goods"], classes = { CLASS.Tradegoods, CLASS.Gem, CLASS.ItemEnhancement } },
	{ key = "recipes", name = L["Recipes"], classes = { CLASS.Recipe } },
	{ key = "quest", name = L["Quest Items"] },
	{ key = "ammo", name = L["Ammo"], classes = { CLASS.Projectile } },
	{ key = "containers", name = L["Bags"], classes = { CLASS.Container, CLASS.Quiver } },
	-- Keys, on Classic also those on the keyring.
	{ key = "keys", name = L["Keys"], classes = { CLASS.Key } },
	{ key = "misc", name = L["Miscellaneous"] },
	{ key = "junk", name = L["Junk"] },
}

local builtIn = {} -- [key] = definition
local keyForClass = {} -- [classID] = key
for _, def in ipairs(BUILT_IN) do
	builtIn[def.key] = def
	for _, classID in ipairs(def.classes or {}) do
		keyForClass[classID] = def.key
	end
end

-- Miscellaneous catches whatever nothing else takes, so it cannot be hidden.
Categories.CATCH_ALL = "misc"

--------------------------------------------------------------------------------
-- Saved state
--------------------------------------------------------------------------------

local function State()
	local state = DB.categories
	for _, key in ipairs({ "order", "hidden", "names", "custom", "items" }) do
		if type(state[key]) ~= "table" then
			state[key] = {}
		end
	end
	state.nextID = state.nextID or 1
	return state
end

-- Every built-in and custom category appears in the order exactly once. New
-- built-ins (from an update) go just before Miscellaneous.
function Categories.Normalize()
	local state = State()
	local seen, order = {}, {}
	for _, key in ipairs(state.order) do
		if not seen[key] and (builtIn[key] or state.custom[key]) then
			seen[key] = true
			order[#order + 1] = key
		end
	end
	for _, def in ipairs(BUILT_IN) do
		if not seen[def.key] then
			seen[def.key] = true
			local at = #order + 1
			if def.key ~= "misc" and def.key ~= "junk" then
				for i, key in ipairs(order) do
					if key == "misc" then
						at = i
						break
					end
				end
			end
			tinsert(order, at, def.key)
		end
	end
	for key in pairs(state.custom) do
		if not seen[key] then
			seen[key] = true
			order[#order + 1] = key
		end
	end
	state.order = order
	state.hidden[Categories.CATCH_ALL] = nil
	return state
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Categories.Exists(key)
	return builtIn[key] ~= nil or State().custom[key] ~= nil
end

function Categories.IsBuiltIn(key)
	return builtIn[key] ~= nil
end

function Categories.IsCustom(key)
	return State().custom[key] ~= nil
end

function Categories.Name(key)
	local state = State()
	if state.names[key] then
		return state.names[key]
	end
	local custom = state.custom[key]
	if custom then
		return custom.name or key
	end
	return builtIn[key] and builtIn[key].name or tostring(key)
end

function Categories.IsHidden(key)
	return State().hidden[key] == true
end

function Categories.Custom(key)
	return State().custom[key]
end

-- { key, name, hidden, custom } for every category, in display order.
function Categories.List()
	local state = Categories.Normalize()
	local list = {}
	for _, key in ipairs(state.order) do
		list[#list + 1] = {
			key = key,
			name = Categories.Name(key),
			hidden = state.hidden[key] == true,
			custom = state.custom[key] ~= nil,
		}
	end
	return list
end

-- Display position of every category: [key] = index.
function Categories.OrderIndex()
	local index = {}
	for i, key in ipairs(Categories.Normalize().order) do
		index[key] = i
	end
	return index
end

--------------------------------------------------------------------------------
-- Changing
--------------------------------------------------------------------------------

local function Changed()
	ns.Send("categories")
end

function Categories.SetHidden(key, hidden)
	if key == Categories.CATCH_ALL then
		return
	end
	State().hidden[key] = hidden and true or nil
	Changed()
end

-- An empty name restores the original one.
function Categories.Rename(key, name)
	local state = State()
	if name == "" then
		name = nil
	end
	if state.custom[key] then
		state.custom[key].name = name or state.custom[key].name
		state.names[key] = nil
	else
		state.names[key] = name
	end
	Changed()
end

function Categories.Move(key, delta)
	local order = Categories.Normalize().order
	for i, k in ipairs(order) do
		if k == key then
			local target = i + delta
			if target >= 1 and target <= #order then
				order[i], order[target] = order[target], order[i]
				Changed()
			end
			return
		end
	end
end

-- rules: { quality = n, class = n, text = "...", bind = "boe" }, each optional.
function Categories.AddCustom(name, rules)
	local state = State()
	local key = "custom" .. state.nextID
	state.nextID = state.nextID + 1
	state.custom[key] = { name = name }
	Categories.SetRules(key, rules)
	-- New categories go just before Miscellaneous.
	local order = Categories.Normalize().order
	for i, k in ipairs(order) do
		if k == key then
			tremove(order, i)
			break
		end
	end
	local at = #order + 1
	for i, k in ipairs(order) do
		if k == Categories.CATCH_ALL then
			at = i
			break
		end
	end
	tinsert(order, at, key)
	Changed()
	return key
end

function Categories.SetRules(key, rules)
	local custom = State().custom[key]
	if not custom then
		return
	end
	rules = rules or {}
	custom.quality = rules.quality
	custom.class = rules.class
	custom.bind = rules.bind
	local text = rules.text
	custom.text = (type(text) == "string" and text ~= "") and text or nil
	Changed()
end

function Categories.DeleteCustom(key)
	local state = State()
	if not state.custom[key] then
		return
	end
	state.custom[key] = nil
	state.hidden[key] = nil
	state.names[key] = nil
	for itemID, assigned in pairs(state.items) do
		if assigned == key then
			state.items[itemID] = nil
		end
	end
	Categories.Normalize()
	Changed()
end

--------------------------------------------------------------------------------
-- Items dragged into a category
--------------------------------------------------------------------------------

function Categories.Assign(itemID, key)
	if not itemID or not Categories.Exists(key) then
		return
	end
	State().items[itemID] = key
	Changed()
end

function Categories.Unassign(itemID)
	local items = State().items
	if itemID and items[itemID] then
		items[itemID] = nil
		Changed()
		return true
	end
	return false
end

function Categories.Assigned(itemID)
	return itemID and State().items[itemID]
end

function Categories.ClearAssignments()
	State().items = {}
	Changed()
end

--------------------------------------------------------------------------------
-- Classifying
--------------------------------------------------------------------------------

local ItemBind = (_G.Enum and _G.Enum.ItemBind) or {}
local BIND_ON_EQUIP, BIND_ON_USE = ItemBind.OnEquip or 2, ItemBind.OnUse or 3

-- Whether an item has a binding: rec.bound is set for soulbound items, and
-- info.bindType says how an item binds (known once it has loaded).
function Categories.HasBinding(bind, rec, info)
	if bind == "bound" then
		return rec.bound == true
	elseif bind == "unbound" then
		return not rec.bound
	elseif bind == "boe" then
		return info.bindType == BIND_ON_EQUIP and not rec.bound
	elseif bind == "bou" then
		return info.bindType == BIND_ON_USE and not rec.bound
	end
	return true
end

local function Matches(rule, quality, info, rec)
	local text = rule.text
	if rule.quality == nil and rule.class == nil and not text and rule.bind == nil then
		return false -- no rules: only items dragged into it
	end
	if rule.quality ~= nil and quality ~= rule.quality then
		return false
	end
	if rule.class ~= nil and info.classID ~= rule.class then
		return false
	end
	if text and not (info.lowerName or ""):find(lower(text), 1, true) then
		return false
	end
	if rule.bind ~= nil and not Categories.HasBinding(rule.bind, rec, info) then
		return false
	end
	return true
end

-- rec: { itemID, quality, isQuest, bound }; info: from Items.Get. Returns a key.
function Categories.Classify(rec, info)
	local state = State()
	local hidden = state.hidden
	local itemID = rec.itemID or info.itemID
	local assigned = itemID and state.items[itemID]
	if assigned and not hidden[assigned] and Categories.Exists(assigned) then
		return assigned
	end
	local quality = rec.quality or info.quality
	for _, key in ipairs(state.order) do
		local custom = state.custom[key]
		if custom and not hidden[key] and Matches(custom, quality, info, rec) then
			return key
		end
	end
	if quality == 0 and not hidden.junk then
		return "junk"
	end
	if (rec.isQuest or info.classID == CLASS.Questitem) and not hidden.quest then
		return "quest"
	end
	local key = keyForClass[info.classID]
	if key and not hidden[key] then
		return key
	end
	return Categories.CATCH_ALL
end

--------------------------------------------------------------------------------
-- Choices for the custom category editor
--------------------------------------------------------------------------------

function Categories.QualityChoices()
	local list = { { value = false, text = L["Any quality"] } }
	local names = {
		[0] = _G.ITEM_QUALITY0_DESC or "Poor",
		[1] = _G.ITEM_QUALITY1_DESC or "Common",
		[2] = _G.ITEM_QUALITY2_DESC or "Uncommon",
		[3] = _G.ITEM_QUALITY3_DESC or "Rare",
		[4] = _G.ITEM_QUALITY4_DESC or "Epic",
		[5] = _G.ITEM_QUALITY5_DESC or "Legendary",
	}
	for quality = 0, 5 do
		local r, g, b = ns.C.QualityColor(quality)
		list[#list + 1] = { value = quality, text = names[quality], color = { r, g, b } }
	end
	return list
end

function Categories.BindChoices()
	return {
		{ value = false, text = L["Any binding"] },
		{ value = "boe", text = L["Bind on Equip, not bound yet"], tooltip = L["Items you can still sell on the auction house or give away."] },
		{ value = "bou", text = L["Bind on Use, not bound yet"] },
		{ value = "bound", text = L["Soulbound"] },
		{ value = "unbound", text = L["Not soulbound"], tooltip = L["Anything that can still be traded, including items that never bind."] },
	}
end

function Categories.ClassChoices()
	local list = { { value = false, text = L["Any type"] } }
	local order = {
		CLASS.Weapon, CLASS.Armor, CLASS.Consumable, CLASS.Tradegoods, CLASS.Reagent,
		CLASS.Recipe, CLASS.Questitem, CLASS.Projectile, CLASS.Container, CLASS.Quiver,
		CLASS.Gem, CLASS.ItemEnhancement, CLASS.Key, CLASS.Miscellaneous,
	}
	local getName = _G.C_Item and _G.C_Item.GetItemClassInfo or _G.GetItemClassInfo
	for _, classID in ipairs(order) do
		local name = getName and getName(classID)
		if name and name ~= "" then
			list[#list + 1] = { value = classID, text = name }
		end
	end
	return list
end
