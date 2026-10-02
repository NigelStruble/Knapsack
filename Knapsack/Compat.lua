local _, ns = ...
local L = ns.L

-- Thin wrappers around the WoW API. Knapsack runs on the Retail engine (Retail
-- itself, and WoW: Forever, which is Classic content on the Retail client) and
-- on the Classic clients (Burning Crusade Classic Anniversary). The Classic
-- clients have a bank of one container and bank bags instead of bank tabs, a
-- keyring, and older tooltips: C_TooltipInfo is missing and
-- TooltipDataProcessor exists but does not work, so tooltips are read from a
-- hidden tooltip and added to through OnTooltipSetItem.

local C = {}
ns.C = C

local _G = _G
local select, type, pcall, ipairs, tonumber = select, type, pcall, ipairs, tonumber
local floor, format = math.floor, string.format

--------------------------------------------------------------------------------
-- Game version
--------------------------------------------------------------------------------

C.toc = select(4, GetBuildInfo()) or 0
-- Forever reports a 1.6x interface number (16001).
C.isForever = C.toc >= 16000 and C.toc < 20000
-- Retail (interface 100000 and up) and Forever run the Retail engine; every
-- other interface number is a Classic client (Anniversary is 20506). The
-- interface number decides, as in Questie, not WOW_PROJECT_ID: a Forever
-- update (October 2026) made Forever's project ID differ from Retail's.
C.isClassic = not C.isForever and C.toc > 0 and C.toc < 100000

--------------------------------------------------------------------------------
-- Secret values
--------------------------------------------------------------------------------

-- Some API results are "secret" in combat on Retail and Forever: addon code
-- may not compare, format or join them. Anything that could be secret goes
-- through Clean first, which turns a secret into nil.
local issecretvalue = _G.issecretvalue

function C.Clean(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

--------------------------------------------------------------------------------
-- Containers
--------------------------------------------------------------------------------

local BagIndex = (_G.Enum and _G.Enum.BagIndex) or {}
local Container = _G.C_Container

-- The backpack and the four bag slots, then Retail's reagent bag, or the
-- Classic keyring. An empty bag slot reports 0 slots and is skipped.
--
-- Classic clients have Retail's enum, which is wrong for them: it lists a
-- ReagentBag that Classic does not have (its number, 5, is the first bank
-- bag's), and its BankBag_N are one too high (BankBag_1 is 6; BetterBags
-- subtracts 1, ElvUI counts from NUM_BAG_SLOTS). Neither is used there.
C.BAGS = {}
for bag = BagIndex.Backpack or 0, BagIndex.Bag_4 or 4 do
	C.BAGS[#C.BAGS + 1] = bag
end
C.REAGENT_BAG = not C.isClassic and BagIndex.ReagentBag or nil
if C.REAGENT_BAG then
	C.BAGS[#C.BAGS + 1] = C.REAGENT_BAG
end
C.KEYRING = C.isClassic and (BagIndex.Keyring or -2) or nil
if C.KEYRING then
	C.BAGS[#C.BAGS + 1] = C.KEYRING
end

-- The bank. On the Retail engine: character bank tabs, six on Retail and nine
-- on Forever, read from the enum by name, so a different count needs no
-- changes here (Forever's enum also lists Warband bank tabs, but Forever has
-- no Warband bank). On Classic: the bank's own container and the bank bags,
-- which come right after the four bag slots (5 to 11).
C.BANK_BAGS = {}
if C.isClassic then
	C.BANK_CONTAINER = BagIndex.Bank or -1
	C.BANK_BAGS[1] = C.BANK_CONTAINER
	local bagSlots = _G.NUM_BAG_SLOTS or 4
	for i = 1, _G.NUM_BANKBAGSLOTS or 7 do
		C.BANK_BAGS[#C.BANK_BAGS + 1] = bagSlots + i
	end
else
	local i = 1
	while BagIndex["CharacterBankTab_" .. i] do
		C.BANK_BAGS[#C.BANK_BAGS + 1] = BagIndex["CharacterBankTab_" .. i]
		i = i + 1
	end
end

C.isBag, C.isBankBag = {}, {}
for _, bag in ipairs(C.BAGS) do
	C.isBag[bag] = true
end
for _, bag in ipairs(C.BANK_BAGS) do
	C.isBankBag[bag] = true
end

-- The keyring holds only keys: the item family bit of keys. The game does not
-- give it as the keyring's family, so it is set here.
C.KEYRING_FAMILY = 0x100

function C.NumSlots(bag)
	if bag == C.KEYRING then
		local enabled = _G.IsKeyRingEnabled
		if (enabled and not enabled()) or not _G.GetKeyRingSize then
			return 0
		end
		return _G.GetKeyRingSize() or 0
	end
	return Container.GetContainerNumSlots(bag) or 0
end

-- 0 for normal bags, a bit field for bags that only hold some kinds of items
-- (quivers, ammo pouches, soul bags, herb bags, the keyring, ...).
function C.BagFamily(bag)
	if bag == C.KEYRING then
		return C.KEYRING_FAMILY
	end
	local _, family = Container.GetContainerNumFreeSlots(bag)
	return family or 0
end

function C.ContainerItem(bag, slot)
	return Container.GetContainerItemInfo(bag, slot)
end

-- The functions below are guarded: they are also asked about bank tabs, the
-- Classic keyring and the Classic bank's own slots, which not every client
-- may accept.

-- start, duration, enable.
function C.ItemCooldown(bag, slot)
	local ok, start, duration, enable = pcall(Container.GetContainerItemCooldown, bag, slot)
	if ok then
		return start, duration, enable
	end
	return 0, 0, 0
end

function C.QuestInfo(bag, slot)
	if Container.GetContainerItemQuestInfo then
		local ok, info = pcall(Container.GetContainerItemQuestInfo, bag, slot)
		return ok and info or nil
	end
	return nil
end

function C.IsNewItem(bag, slot)
	local newItems = _G.C_NewItems
	if not (newItems and newItems.IsNewItem) then
		return false
	end
	local ok, new = pcall(newItems.IsNewItem, bag, slot)
	return (ok and new) and true or false
end

function C.RemoveNewItem(bag, slot)
	local newItems = _G.C_NewItems
	if newItems and newItems.RemoveNewItem then
		pcall(newItems.RemoveNewItem, bag, slot)
	end
end

-- Moving items, as if by hand: pick up a slot (or put down what the cursor
-- holds), or pick up part of a stack.
function C.PickupContainerItem(bag, slot)
	Container.PickupContainerItem(bag, slot)
end

function C.SplitContainerItem(bag, slot, count)
	Container.SplitContainerItem(bag, slot, count)
end

-- The name of the bag in a bag slot ("Traveler's Backpack", "Backpack").
-- Guarded like QuestInfo: bank tabs are asked too.
function C.BagName(bag)
	if bag == C.BANK_CONTAINER then
		return L["Bank"]
	elseif bag == C.KEYRING then
		return _G.KEYRING or L["Keyring"]
	end
	local get = Container.GetBagName or _G.GetBagName
	if get then
		local ok, name = pcall(get, bag)
		return ok and name or nil
	end
	return nil
end

function C.ClearNewItems()
	local newItems = _G.C_NewItems
	if newItems and newItems.ClearAll then
		newItems.ClearAll()
	end
end

-- Names and icons of the purchased character bank tabs, by bag ID.
function C.BankTabs()
	local tabs = {}
	local bank = _G.C_Bank
	local bankType = _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character
	if bank and bank.FetchPurchasedBankTabData and bankType then
		local data = bank.FetchPurchasedBankTabData(bankType)
		if type(data) == "table" then
			for i, tab in ipairs(data) do
				local bag = (tab.ID and C.isBankBag[tab.ID] and tab.ID) or C.BANK_BAGS[i]
				if bag then
					tabs[bag] = { name = tab.name, icon = tab.icon }
				end
			end
		end
	end
	return tabs
end

function C.CloseBank()
	local bank = _G.C_Bank
	local close = (bank and bank.CloseBankFrame) or _G.CloseBankFrame
	if close then
		close()
	end
end

-- The next character bank tab that can be had, as the game describes it
-- ({ tabCost, canAfford, purchasePromptTitle, purchasePromptBody, ... }; on
-- Forever a new character's first tab is free), or nil if none can.
function C.NextBankTab()
	local bank = _G.C_Bank
	local bankType = _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character
	if not (bank and bank.CanPurchaseBankTab and bank.FetchNextPurchasableBankTabData and bankType) then
		return nil
	end
	local ok, can = pcall(bank.CanPurchaseBankTab, bankType)
	if not ok or not C.Clean(can) then
		return nil
	end
	local fetched, data = pcall(bank.FetchNextPurchasableBankTabData, bankType)
	return fetched and type(data) == "table" and data or nil
end

-- How many character bank tabs the character has (bought, or given free), or
-- nil if the client cannot say.
function C.BankTabCount()
	local bank = _G.C_Bank
	local bankType = _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character
	if bank and bank.FetchNumPurchasedBankTabs and bankType then
		local ok, count = pcall(bank.FetchNumPurchasedBankTabs, bankType)
		if ok then
			return C.Clean(count)
		end
	end
	return nil
end

-- The inventory slot a bag is worn in (the four bag slots, a reagent bag, and
-- on Classic the bank bag slots), or nil for what is not a bag in a slot: the
-- backpack, the keyring, the Classic bank's own slots and Retail's bank tabs.
function C.BagInventorySlot(bag)
	local get = Container.ContainerIDToInventoryID or _G.ContainerIDToInventoryID
	local worn = C.isBag[bag] or (C.isClassic and C.isBankBag[bag])
	if not worn or not get or bag == (BagIndex.Backpack or 0) or bag == C.KEYRING or bag == C.BANK_CONTAINER then
		return nil
	end
	local ok, slot = pcall(get, bag)
	return ok and C.Clean(slot) or nil
end

-- Classic: how many bank bag slots the character has bought, and whether
-- that is all of them. Nil on the Retail engine.
function C.BankBagSlots()
	if not (C.isClassic and _G.GetNumBankSlots) then
		return nil
	end
	local ok, bought, full = pcall(_G.GetNumBankSlots)
	if not ok then
		return nil
	end
	return C.Clean(bought) or 0, C.Clean(full) and true or false
end

-- Classic: what the next bank bag slot costs.
function C.BankBagSlotCost()
	local bought = C.BankBagSlots()
	if not (bought and _G.GetBankSlotCost) then
		return nil
	end
	local ok, cost = pcall(_G.GetBankSlotCost, bought)
	return ok and C.Clean(cost) or nil
end

-- Classic: buys the next bank bag slot, at the bank.
function C.BuyBankBagSlot()
	if _G.PurchaseSlot then
		_G.PurchaseSlot()
	end
end

-- The link of the bag worn in a bag slot, or nil.
function C.BagLink(bag)
	local slot = C.BagInventorySlot(bag)
	return slot and C.Clean(GetInventoryItemLink("player", slot)) or nil
end

--------------------------------------------------------------------------------
-- Guild bank
--------------------------------------------------------------------------------

C.hasGuildBank = type(_G.GetNumGuildBankTabs) == "function"
C.GUILD_BANK_SLOTS = _G.MAX_GUILDBANK_SLOTS_PER_TAB or 98

--------------------------------------------------------------------------------
-- NPC interactions
--------------------------------------------------------------------------------

local Interaction = _G.C_PlayerInteractionManager
local InteractionType = (_G.Enum and _G.Enum.PlayerInteractionType) or {}
C.BANKER = InteractionType.Banker
C.GUILD_BANKER = InteractionType.GuildBanker

local function Interacting(kind)
	if not (kind and Interaction and Interaction.IsInteractingWithNpcOfType) then
		return false
	end
	local ok, result = pcall(Interaction.IsInteractingWithNpcOfType, kind)
	return ok and C.Clean(result) == true
end

function C.AtBank()
	return Interacting(C.BANKER)
end

function C.AtGuildBank()
	return Interacting(C.GUILD_BANKER)
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

local Item = _G.C_Item

-- itemID, type, subType, equipLoc, icon, classID, subClassID. Always
-- available, even for items the client has not loaded yet.
function C.ItemInfoInstant(item)
	if Item and Item.GetItemInfoInstant then
		return Item.GetItemInfoInstant(item)
	end
	return _G.GetItemInfoInstant(item)
end

-- name, link, quality, itemLevel, minLevel, type, subType, maxStack, equipLoc,
-- icon, sellPrice, ... Returns nothing until the client has the item's data.
function C.ItemInfo(item)
	if Item and Item.GetItemInfo then
		return Item.GetItemInfo(item)
	end
	return _G.GetItemInfo(item)
end

function C.RequestItem(itemID)
	if Item and Item.RequestLoadItemDataByID then
		Item.RequestLoadItemDataByID(itemID)
	end
end

function C.QualityColor(quality)
	if quality and Item and Item.GetItemQualityColor then
		local r, g, b = Item.GetItemQualityColor(quality)
		if r then
			return r, g, b
		end
	end
	local color = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

function C.ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)"))
end

-- The name shown in the link, [like this].
function C.NameFromLink(link)
	return link and link:match("|h%[(.-)%]|h")
end

-- The item level the item actually has (upgrades and scaling included), or nil.
function C.DetailedItemLevel(link)
	local get = (Item and Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
	if get then
		local ok, level = pcall(get, link)
		if ok then
			return C.Clean(level)
		end
	end
	return nil
end

-- The spell an item casts when used (name, spellID), or nil.
function C.ItemSpell(item)
	local get = (Item and Item.GetItemSpell) or _G.GetItemSpell
	if get then
		local ok, name, id = pcall(get, item)
		if ok and C.Clean(name) then
			return name, C.Clean(id)
		end
	end
	return nil
end

-- Whether the character can use the item, or nil when the client cannot say.
function C.IsUsableItem(item)
	local get = (Item and Item.IsUsableItem) or _G.IsUsableItem
	if get then
		local ok, usable = pcall(get, item)
		if ok then
			return C.Clean(usable) and true or false
		end
	end
	return nil
end

-- The lines of an item's tooltip, without showing it: { leftText, leftColor,
-- rightText, rightColor } each, or nil when there are none. The Retail engine
-- has them as data (C_TooltipInfo.GetBagItem and so on); clients without
-- C_TooltipInfo (Classic) fill a hidden tooltip with the matching Set method,
-- which is then read line by line.
local function TooltipLines(getter, ...)
	local get = _G.C_TooltipInfo[getter]
	if not get then
		return nil
	end
	local ok, data = pcall(get, ...)
	if ok and type(data) == "table" and type(data.lines) == "table" and #data.lines > 0 then
		return data.lines
	end
	return nil
end

local SCAN = "KnapsackScanTooltip"
local scanTip

local function ScanLines(method, ...)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", SCAN, nil, "GameTooltipTemplate")
	end
	local tip = scanTip
	tip:SetOwner(_G.WorldFrame, "ANCHOR_NONE")
	tip:ClearLines()
	if not tip[method] or not pcall(tip[method], tip, ...) then
		tip:Hide()
		return nil
	end
	local lines = {}
	for i = 1, tip:NumLines() or 0 do
		local line = {}
		local left, right = _G[SCAN .. "TextLeft" .. i], _G[SCAN .. "TextRight" .. i]
		if left then
			local r, g, b = left:GetTextColor()
			line.leftText, line.leftColor = left:GetText(), { r = r, g = g, b = b }
		end
		if right and right:IsShown() then
			local r, g, b = right:GetTextColor()
			line.rightText, line.rightColor = right:GetText(), { r = r, g = g, b = b }
		end
		lines[i] = line
	end
	tip:Hide()
	return #lines > 0 and lines or nil
end

-- getter is the C_TooltipInfo function ("GetBagItem"), from which the
-- tooltip's own method is named ("SetBagItem").
local function Lines(getter, ...)
	if _G.C_TooltipInfo then
		return TooltipLines(getter, ...)
	end
	return ScanLines((getter:gsub("^Get", "Set")), ...)
end

-- The tooltip of a link: the item as it is made, without charges used up.
function C.LinkTooltip(link)
	return Lines("GetHyperlink", link)
end

-- On Classic the bank's own slots and the keyring's are inventory slots to a
-- tooltip, the way Blizzard's bank and keyring show them. Nil for the rest.
local function TooltipInventorySlot(bag, slot)
	if not C.isClassic then
		return nil
	end
	local get
	if bag == C.BANK_CONTAINER then
		get = _G.BankButtonIDToInvSlotID
	elseif bag == C.KEYRING then
		get = _G.KeyRingButtonIDToInvSlotID
	end
	if get then
		local ok, inventorySlot = pcall(get, slot)
		return ok and C.Clean(inventorySlot) or nil
	end
	return nil
end

-- The tooltip of the item in a bag slot (charges left, durability).
function C.BagTooltip(bag, slot)
	local inventorySlot = TooltipInventorySlot(bag, slot)
	if inventorySlot then
		return Lines("GetInventoryItem", "player", inventorySlot)
	end
	return Lines("GetBagItem", bag, slot)
end

-- The tooltip of an item attached to a mail in the mailbox.
function C.InboxTooltip(index, attachment)
	return Lines("GetInboxItem", index, attachment)
end

-- The tooltip of an item attached to the mail being written.
function C.SendMailTooltip(attachment)
	return Lines("GetSendMailItem", attachment)
end

-- Shows the item in a bag slot in a tooltip.
function C.SetTooltipBagItem(tooltip, bag, slot)
	local inventorySlot = TooltipInventorySlot(bag, slot)
	if inventorySlot then
		return tooltip:SetInventoryItem("player", inventorySlot)
	end
	return tooltip:SetBagItem(bag, slot)
end

-- Sets a texture to an atlas the client has, or else to a file.
function C.SetIcon(texture, atlas, file)
	local textures = _G.C_Texture
	if atlas and textures and textures.GetAtlasInfo and textures.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
	end
end

-- Lua patterns that match what a Blizzard format string prints, such as
-- ITEM_SPELL_CHARGES ("%d |4Charge:Charges;") matching "5 Charges" and
-- "1 Charge". A |4singular:plural; choice gives one pattern per form. Each
-- %d and %s is captured.
function C.FormatPatterns(fmt)
	local patterns = {}
	if type(fmt) ~= "string" or fmt == "" then
		return patterns
	end
	local texts = { fmt }
	local forms = fmt:match("|4([^;]*);")
	if forms then
		texts = {}
		for form in forms:gmatch("[^:]+") do
			texts[#texts + 1] = (fmt:gsub("|4[^;]*;", (form:gsub("%%", "%%%%")), 1))
		end
	end
	for _, text in ipairs(texts) do
		local p = text:gsub("%%%%", "\2"):gsub("%%%d*%$?[%d%.]*([ds])", "\3%1")
		p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
		p = p:gsub("\3d", "(%%d+)"):gsub("\3s", "(.+)"):gsub("\2", "%%%%")
		patterns[#patterns + 1] = "^" .. p .. "$"
	end
	return patterns
end

function C.MatchesAny(text, patterns)
	for _, pattern in ipairs(patterns) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

-- Tooltip data can hold text the way the game keeps it, before a tooltip
-- draws it: with color codes, and with |4singular:plural; after a number
-- ("4 |4Charge:Charges;"). This returns the text as it would be drawn.
function C.PlainText(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
	text = text:gsub("(%d+)(%s*)|4([^;]*);", function(number, space, forms)
		local list = {}
		for form in forms:gmatch("[^:]+") do
			list[#list + 1] = form
		end
		return number .. space .. ((tonumber(number) == 1 and list[1]) or list[#list] or "")
	end)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The first number in text, if text matches one of the patterns.
function C.MatchNumber(text, patterns)
	for _, pattern in ipairs(patterns) do
		local number = text:match(pattern)
		if number then
			return tonumber(number)
		end
	end
	return nil
end

-- The size of one screen pixel in a frame's own units, so a border can be a
-- whole number of pixels at any UI scale.
function C.PixelSize(frame)
	local _, height = (_G.GetPhysicalScreenSize or function() end)()
	local scale = frame and frame:GetEffectiveScale()
	if not height or height <= 0 or not scale or scale <= 0 then
		return 1
	end
	return 768 / height / scale
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function Byte(value)
	return floor(value * 255 + 0.5)
end

function C.ColorText(text, r, g, b)
	return format("|cff%02x%02x%02x%s|r", Byte(r), Byte(g), Byte(b), text)
end

function C.ClassColor(class)
	local custom, raid = _G.CUSTOM_CLASS_COLORS, _G.RAID_CLASS_COLORS
	local color = class and ((custom and custom[class]) or (raid and raid[class]))
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

-- Money with coin icons, "12 [g] 34 [s] 56 [c]".
function C.Money(copper)
	copper = copper or 0
	if _G.GetMoneyString then
		return _G.GetMoneyString(copper, true)
	end
	local currency = _G.C_CurrencyInfo
	if currency and currency.GetCoinTextureString then
		return currency.GetCoinTextureString(copper)
	end
	return C.ShortMoney(copper)
end

local GOLD, SILVER, COPPER = "|cffffd100%dg|r", "|cffc7c7cf%ds|r", "|cffeda55f%dc|r"

-- Only the largest coin, for the corner of an item tile: "12g", "34s", "56c".
function C.ShortMoney(copper)
	copper = floor(copper or 0)
	if copper >= 10000 then
		return format(GOLD, floor(copper / 10000))
	elseif copper >= 100 then
		return format(SILVER, floor(copper / 100))
	end
	return format(COPPER, copper)
end

-- Time left, in its largest unit, for the corner of an item: "29d", "5h", "12m".
function C.ShortTime(seconds)
	seconds = seconds or 0
	if seconds >= 86400 then
		return format(L["%dd"], floor(seconds / 86400))
	elseif seconds >= 3600 then
		return format(L["%dh"], floor(seconds / 3600))
	end
	return format(L["%dm"], math.max(0, floor(seconds / 60)))
end

-- Time left in words: "29 days", "5 hours", "12 minutes".
function C.TimeLeft(seconds)
	seconds = seconds or 0
	if seconds >= 86400 then
		local days = floor(seconds / 86400)
		return format(days == 1 and L["%d day"] or L["%d days"], days)
	elseif seconds >= 3600 then
		local hours = floor(seconds / 3600)
		return format(hours == 1 and L["%d hour"] or L["%d hours"], hours)
	end
	local minutes = math.max(1, floor(seconds / 60))
	return format(minutes == 1 and L["%d minute"] or L["%d minutes"], minutes)
end

function C.TimeAgo(timestamp)
	if not timestamp then
		return L["never"]
	end
	local seconds = time() - timestamp
	if seconds < 60 then
		return L["just now"]
	elseif seconds < 3600 then
		return format(L["%d min ago"], floor(seconds / 60))
	elseif seconds < 86400 then
		local hours = floor(seconds / 3600)
		return format(hours == 1 and L["%d hour ago"] or L["%d hours ago"], hours)
	end
	local days = floor(seconds / 86400)
	return format(days == 1 and L["%d day ago"] or L["%d days ago"], days)
end

--------------------------------------------------------------------------------
-- Other bag addons
--------------------------------------------------------------------------------

-- If one of these handles the bags, Knapsack leaves them alone and only records
-- and shows the bank, guild vault and other characters.
local BAG_ADDONS = {
	{ "EllesmereUIBags", "EllesmereUI Bags" },
	{ "Bagnon", "Bagnon" },
	{ "BetterBags", "BetterBags" },
	{ "AdiBags", "AdiBags" },
	{ "ArkInventory", "ArkInventory" },
	{ "Baganator", "Baganator" },
	{ "Combuctor", "Combuctor" },
	{ "Inventorian", "Inventorian" },
	{ "LiteBag", "LiteBag" },
	{ "Sorted", "Sorted" },
	{ "Satchel", "Satchel" }, -- another bag addon for WoW: Forever (not this one)
}

local function AddOnLoaded(name)
	local addOns = _G.C_AddOns
	if addOns and addOns.IsAddOnLoaded then
		return (addOns.IsAddOnLoaded(name))
	end
	return _G.IsAddOnLoaded and (_G.IsAddOnLoaded(name))
end
C.AddOnLoaded = AddOnLoaded

function C.OtherBagAddon()
	for _, entry in ipairs(BAG_ADDONS) do
		if AddOnLoaded(entry[1]) then
			return entry[2]
		end
	end
	local elv = _G.ElvUI and _G.ElvUI[1]
	local private = elv and elv.private
	if private and private.bags and private.bags.enable then
		return "ElvUI"
	end
	return nil
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

-- Newer clients throw an error when asked for an event they do not have, so
-- every registration is guarded. Returns false if the event does not exist.
function C.RegisterEvent(frame, event)
	return (pcall(frame.RegisterEvent, frame, event))
end

-- One event frame for the whole addon; any number of handlers per event.
-- securecallfunction reports a failing handler without stopping the others.
local eventFrame = CreateFrame("Frame")
local handlers = {}
local call = _G.securecallfunction or function(func, ...)
	return func(...)
end

function C.On(event, handler)
	local list = handlers[event]
	if not list then
		if not C.RegisterEvent(eventFrame, event) then
			return false
		end
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = handler
	return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	for i = 1, #list do
		call(list[i], event, ...)
	end
end)

-- Returns a function that runs fn once, delay seconds after the first of any
-- number of calls. Folds bursts of events (BAG_UPDATE fires once per bag, loot
-- fires several) into one update.
function C.Debounce(delay, fn)
	local pending = false
	local function Run()
		pending = false
		fn()
	end
	return function()
		if not pending then
			pending = true
			C_Timer.After(delay, Run)
		end
	end
end

function C.AddOnMetadata(addon, field)
	local addOns = _G.C_AddOns
	if addOns and addOns.GetAddOnMetadata then
		return addOns.GetAddOnMetadata(addon, field)
	end
	return _G.GetAddOnMetadata and _G.GetAddOnMetadata(addon, field)
end

-- Adds a page to the game's AddOns options.
function C.RegisterOptionsPanel(panel, name)
	local settings = _G.Settings
	if settings and settings.RegisterCanvasLayoutCategory and settings.RegisterAddOnCategory then
		local category = settings.RegisterCanvasLayoutCategory(panel, name)
		settings.RegisterAddOnCategory(category)
		return category
	end
	if _G.InterfaceOptions_AddCategory then
		panel.name = name
		_G.InterfaceOptions_AddCategory(panel)
		return panel
	end
	return nil
end

function C.PlaySound(kit, fallback)
	local sounds = _G.SOUNDKIT
	local id = (sounds and sounds[kit]) or fallback
	if id and _G.PlaySound then
		pcall(_G.PlaySound, id)
	end
end
