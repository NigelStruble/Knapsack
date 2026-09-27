local _, ns = ...
local C = ns.C

-- Item details for display, sorting and categories, cached by item link.
-- What C_Item.GetItemInfoInstant knows (icon, item class) is there at once. The
-- name, quality and vendor price come from GetItemInfo, which is empty until
-- the client has loaded the item; those are requested, and "items" is sent
-- when they arrive so open windows can redraw.

local Items = {}
ns.Items = Items

local _G = _G
local ipairs, type, lower = ipairs, type, string.lower

local ItemClass = (_G.Enum and _G.Enum.ItemClass) or {}
local WEAPON, ARMOR, RECIPE = ItemClass.Weapon or 2, ItemClass.Armor or 4, ItemClass.Recipe or 9

-- Equipment slots that are not worn gear, and worn gear without an item level
-- worth showing.
local NOT_GEAR = { [""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true }
local NO_LEVEL = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

local cache = {} -- [link] = info
local waiting = {} -- [itemID] = true while a load is requested

local function Complete(info, link)
	local name, _, quality, itemLevel, _, _, _, maxStack, _, _, sellPrice, _, _, bindType = C.ItemInfo(link)
	if not name then
		return false
	end
	info.name = name
	info.lowerName = lower(name)
	info.quality = quality
	info.itemLevel = C.DetailedItemLevel(link) or itemLevel
	info.maxStack = maxStack
	info.sellPrice = sellPrice or 0
	info.bindType = bindType -- Enum.ItemBind: 1 on pickup, 2 on equip, 3 on use, 4 quest
	info.complete = true
	return true
end

-- itemID is the fallback for links that are not item links (caged pets,
-- keystones). The returned table is shared; do not change it.
--   isGear     worn equipment: weapons and armor, rings, trinkets, ...
--   showLevel  gear whose item level is worth showing (not shirts, tabards)
function Items.Get(link, itemID)
	local info = cache[link]
	if info and info.complete then
		return info
	end
	if not info then
		info = {}
		local id, _, _, equipLoc, icon, classID, subClassID = C.ItemInfoInstant(link)
		if not id and itemID then
			id, _, _, equipLoc, icon, classID, subClassID = C.ItemInfoInstant(itemID)
		end
		info.itemID = id or itemID or C.ItemIDFromLink(link)
		info.equipLoc, info.icon = equipLoc, icon
		info.classID, info.subClassID = classID, subClassID
		info.isGear = (classID == WEAPON or classID == ARMOR) and not NOT_GEAR[equipLoc or ""]
		info.showLevel = info.isGear and not NO_LEVEL[equipLoc]
		local name = C.NameFromLink(link)
		info.name = name
		info.lowerName = name and lower(name) or ""
		cache[link] = info
	end
	if not Complete(info, link) and info.itemID and not waiting[info.itemID] then
		waiting[info.itemID] = true
		C.RequestItem(info.itemID)
	end
	return info
end

C.On("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
	if itemID and waiting[itemID] then
		if success == false then
			return -- the server has no such item: it is not asked for again
		end
		waiting[itemID] = nil
		ns.Send("items")
	end
end)

--------------------------------------------------------------------------------
-- Items the character cannot use
--------------------------------------------------------------------------------

-- The game writes what stops you using an item in red in its tooltip: a level,
-- class or skill you do not have, armor you cannot wear ("Plate"), a weapon
-- you cannot wield ("Sword"). A few red lines say nothing about using it.
local IGNORED = {}
for _, key in ipairs({ "ITEM_SCRAPABLE_NOT", "ITEM_DISENCHANT_NOT_DISENCHANTABLE", "CANNOT_UNEQUIP_COMBAT" }) do
	local text = _G[key]
	if type(text) == "string" then
		IGNORED[text] = true
	end
end
local DURABILITY = C.FormatPatterns(_G.DURABILITY_TEMPLATE) -- red when broken, still wearable

local function IsRed(color)
	if type(color) ~= "table" then
		return false
	end
	local r, g, b = C.Clean(color.r), C.Clean(color.g), C.Clean(color.b)
	return (r and g and b and r > 0.9 and g < 0.2 and b < 0.2) and true or false
end

local function HasRedLine(lines)
	for _, line in ipairs(lines) do
		if IsRed(line.leftColor) then
			local text = C.Clean(line.leftText)
			if not (text and (IGNORED[text] or C.MatchesAny(text, DURABILITY))) then
				return true
			end
		end
		if IsRed(line.rightColor) then
			return true
		end
	end
	return false
end

local unusable = {} -- [link] = true or false, for the logged-in character

-- True when the logged-in character cannot use the item: gear it cannot wear
-- or wield, recipes it cannot learn, and items it lacks the level or skill to
-- use. Nil while that cannot be told yet (the item has not loaded).
function Items.Unusable(link, info)
	local known = unusable[link]
	if known ~= nil then
		return known
	end
	if not info.complete then
		return nil
	end
	local result = false
	if info.classID == RECIPE then
		-- A recipe's tooltip shows what it makes, red lines included, so ask
		-- the game directly.
		local usable = C.IsUsableItem(link)
		if usable == nil then
			return nil
		end
		result = not usable
	elseif info.isGear or C.ItemSpell(link) then
		local lines = C.LinkTooltip(link)
		if not lines then
			return nil
		end
		result = HasRedLine(lines)
	end
	unusable[link] = result
	return result
end

-- Levels, skills and recipes change what can be used.
local function Relearn()
	_G.wipe(unusable)
	ns.Send("items")
end
for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB" }) do
	C.On(event, C.Debounce(0.5, Relearn))
end

--------------------------------------------------------------------------------
-- Items with charges
--------------------------------------------------------------------------------

-- Items such as Wizard Oil have charges, and each one can have a different
-- number left. Only the tooltip of the item in its bag slot says how many
-- ("5 Charges"); a link's tooltip leaves them out. So the bags and bank are
-- read with their charges, which are recorded with the rest (see Scanner.lua).
local CHARGES = C.FormatPatterns(lower(_G.ITEM_SPELL_CHARGES or "%d |4Charge:Charges;"))
local NO_CHARGES = lower(_G.ITEM_SPELL_CHARGES_NONE or "No charges")

local hasCharges = {} -- [itemID] = true or false
local chargeSpells = {} -- [spellID] = true for the spells of items with charges

-- The number of charges a tooltip line gives, or nil.
local function ChargesIn(text)
	text = C.Clean(text)
	if type(text) ~= "string" then
		return nil
	end
	text = lower(C.PlainText(text))
	if text == NO_CHARGES then
		return 0
	end
	return C.MatchNumber(text, CHARGES)
end
Items.ChargesIn = ChargesIn

-- The charges left on an item, or nil for an item without charges. read(a, b)
-- gives the tooltip lines of the item where it is: C.BagTooltip(bag, slot),
-- C.InboxTooltip(mail, attachment), C.SendMailTooltip(attachment). itemID may
-- be nil. Each kind of item's tooltip is read once to learn whether it has
-- charges; after that only those with charges are read.
function Items.Charges(link, itemID, read, a, b)
	local info = Items.Get(link, itemID)
	local id = info.itemID
	if not id or info.isGear or hasCharges[id] == false then
		return nil
	end
	if hasCharges[id] == nil and not info.complete then
		return nil -- read again once the item has loaded
	end
	local lines = read(a, b)
	if not lines then
		return nil
	end
	for _, line in ipairs(lines) do
		local left = ChargesIn(line.leftText)
		if left then
			if not hasCharges[id] then
				hasCharges[id] = true
				local _, spellID = C.ItemSpell(link)
				if spellID then
					chargeSpells[spellID] = true
				end
			end
			return left
		end
	end
	hasCharges[id] = false
	return nil
end

-- Whether a spell the player cast may have used up a charge.
function Items.IsChargeSpell(spellID)
	return spellID ~= nil and chargeSpells[spellID] == true
end
