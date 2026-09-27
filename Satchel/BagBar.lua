local _, ns = ...
local L, C, W, Items = ns.L, ns.C, ns.W, ns.Items

-- The bag slots along the bottom of a window, for changing bags with the
-- game's own bag bar and bank window hidden:
--   bags window   the backpack and the four bag slots (and the reagent bag,
--                 when one is worn)
--   bank window   Classic only: the bank's own slots and the bank bag slots;
--                 those not bought yet are red, and clicking one buys the next
-- They work like the game's: drop a bag on a slot to wear it there, drag a
-- bag off its slot to move or remove it, click a slot with an item held to
-- put the item in that bag. Pointing at a slot shows which items are in that
-- bag. Another character's bags are shown too, as they were, without the
-- dragging.

local BagBar = {}
ns.BagBar = BagBar

local _G = _G
local ipairs, pairs, format = ipairs, pairs, string.format

local SIZE, GAP = 30, 4
BagBar.HEIGHT = SIZE + 6

local BACKPACK = (_G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.Backpack) or 0
local REAGENT_BAG = C.REAGENT_BAG -- none on Classic
local BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local BANK_ICON = "Interface\\Icons\\INV_Box_01"
local EMPTY_ICON = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08" -- a bag recorded before its look was
BagBar.ICON = BACKPACK_ICON
BagBar.BANK_ICON = BANK_ICON

--------------------------------------------------------------------------------
-- A slot
--------------------------------------------------------------------------------

-- Classic: buys the next bank bag slot, after asking. The game only sells
-- them in order, so any slot not bought yet buys the next one.
local function BuyBankBagSlot()
	local cost = C.BankBagSlotCost()
	if not cost then
		return
	end
	if GetMoney() < cost then
		ns.Print(format(L["The next bank bag slot costs %s. You do not have enough gold."], C.Money(cost)))
		return
	end
	W.Confirm(format(L["Buy a bank bag slot for %s?"], C.Money(cost)), C.BuyBankBagSlot)
end

local function Slot_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if self.forSale then
		GameTooltip:SetText(L["Bank bag slot, not bought yet"], 1, 1, 1)
		local cost = self.live and C.BankBagSlotCost()
		if cost then
			GameTooltip:AddLine(format(L["The next one costs %s."], C.Money(cost)), 1, 1, 1)
			GameTooltip:AddLine(L["Click to buy it."], 0.6, 0.6, 0.6)
		elseif not self.live then
			GameTooltip:AddLine(L["Bank bag slots are bought at a banker."], 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
		return
	end
	local shown = false
	if self.live and self.inventorySlot then
		shown = GameTooltip:SetInventoryItem("player", self.inventorySlot) and true or false
	elseif self.link then
		GameTooltip:SetHyperlink(self.link)
		shown = true
	end
	if not shown then
		local title = L["Empty bag slot"]
		if self.bag == BACKPACK then
			title = L["Backpack"]
		elseif self.bag == C.BANK_CONTAINER then
			title = L["Bank"]
		end
		GameTooltip:SetText(title, 1, 1, 1)
	end
	if self.size and self.size > 0 then
		GameTooltip:AddLine(format(L["%d of %d slots used"], self.used, self.size), 0.8, 0.8, 0.8)
	end
	if self.live and self.inventorySlot then
		GameTooltip:AddLine(L["Drop a bag here to wear it in this slot. Drag a bag away to move or remove it."], 0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
	self.window:HighlightBag(self.bag)
end

local function Slot_OnLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
	self.window:HighlightBag(nil)
end

-- Whatever the cursor holds goes in: a bag is worn in the slot, any other
-- item goes into the bag (into the first free slot of the Classic bank's own
-- slots).
local function PutIn(self)
	if not self.live or self.forSale then
		return
	end
	if self.bag == BACKPACK then
		PutItemInBackpack()
	elseif self.bag == C.BANK_CONTAINER then
		if self.freeSlot then
			C.PickupContainerItem(self.bag, self.freeSlot)
		end
	elseif self.inventorySlot then
		PutItemInBag(self.inventorySlot)
	end
end

local function Slot_OnClick(self)
	if self.forSale then
		if self.live then
			BuyBankBagSlot()
		end
	elseif GetCursorInfo() then
		PutIn(self)
	elseif self.live and self.inventorySlot and self.link then
		PickupBagFromSlot(self.inventorySlot)
	end
end

local function Slot_OnDragStart(self)
	if self.live and self.inventorySlot and self.link and not self.forSale then
		PickupBagFromSlot(self.inventorySlot)
	end
end

local function NewSlot(bar, bag)
	local slot = CreateFrame("Button", nil, bar)
	slot:SetSize(SIZE, SIZE)
	slot:RegisterForClicks("LeftButtonUp")
	slot:RegisterForDrag("LeftButton")
	slot.bg = W.Background(slot, W.COLORS.control)
	slot.icon = slot:CreateTexture(nil, "ARTWORK")
	slot.icon:SetPoint("TOPLEFT", 1, -1)
	slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	slot.border = W.Border(slot)
	slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
	local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.14)
	slot.bag = bag
	slot.window = bar.window
	slot:SetScript("OnEnter", Slot_OnEnter)
	slot:SetScript("OnLeave", Slot_OnLeave)
	slot:SetScript("OnClick", Slot_OnClick)
	slot:SetScript("OnDragStart", Slot_OnDragStart)
	slot:SetScript("OnReceiveDrag", PutIn)
	return slot
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

-- bags: the bags whose slots the bar shows, C.BAGS or C.BANK_BAGS.
function BagBar.Create(window, bags)
	local bar = CreateFrame("Frame", nil, window)
	bar:SetHeight(SIZE)
	bar.window = window
	bar.slots = {}
	local bankBag = 0
	for _, bag in ipairs(bags) do
		if bag ~= C.KEYRING then -- a keyring is not a bag slot
			local slot = NewSlot(bar, bag)
			if C.isClassic and C.isBankBag[bag] and bag ~= C.BANK_CONTAINER then
				bankBag = bankBag + 1
				slot.bankBag = bankBag -- which bank bag slot, for buying them in order
			end
			bar.slots[#bar.slots + 1] = slot
		end
	end
	bar:Hide()
	return bar
end

local function SetBorder(slot, r, g, b)
	for _, edge in ipairs(slot.border) do
		edge:SetColorTexture(r, g, b, 1)
	end
end

local function FirstFree(container)
	for slot = 1, container and container.size or 0 do
		if not container.items[slot] then
			return slot
		end
	end
	return nil
end

-- containers: the bags being shown ([bag] = container, see Scanner.lua);
-- live: the player's own, which can be changed; bankBagSlots: on Classic, the
-- bank bag slots bought (nil if not known).
function BagBar.Update(bar, containers, live, bankBagSlots)
	local x = 0
	for _, slot in ipairs(bar.slots) do
		local bag = slot.bag
		local container = containers[bag]
		local size = container and container.size or 0
		-- The reagent bag slot only shows with a reagent bag in it: not every
		-- game has one.
		local show = bag ~= REAGENT_BAG or size > 0
		slot:SetShown(show)
		if show then
			local used = 0
			for _ in pairs(container and container.items or {}) do
				used = used + 1
			end
			slot.live, slot.size, slot.used = live, size, used
			slot.forSale = slot.bankBag ~= nil and bankBagSlots ~= nil and slot.bankBag > bankBagSlots
			slot.inventorySlot = not slot.forSale and C.BagInventorySlot(bag) or nil
			slot.link = container and container.link
			slot.freeSlot = bag == C.BANK_CONTAINER and FirstFree(container) or nil
			local icon, quality
			if bag == BACKPACK then
				icon = BACKPACK_ICON
			elseif bag == C.BANK_CONTAINER then
				icon = BANK_ICON
			elseif slot.link then
				local info = Items.Get(slot.link)
				icon, quality = info.icon, info.quality
			elseif size > 0 then
				icon = BAG_ICON
			end
			slot.icon:SetTexture(icon or EMPTY_ICON)
			slot.icon:SetDesaturated(icon == nil)
			slot.icon:SetAlpha(icon and 1 or 0.4)
			if slot.forSale then
				slot.icon:SetVertexColor(1, 0.1, 0.1)
				slot.icon:SetAlpha(0.8)
			else
				slot.icon:SetVertexColor(1, 1, 1)
			end
			slot.count:SetText(size > 0 and size or "")
			if quality and quality > 1 then
				SetBorder(slot, C.QualityColor(quality))
			else
				local color = W.COLORS.border
				SetBorder(slot, color[1], color[2], color[3])
			end
			slot:ClearAllPoints()
			slot:SetPoint("LEFT", bar, "LEFT", x, 0)
			x = x + SIZE + GAP
		end
	end
	bar:SetWidth(math.max(1, x - GAP))
end
