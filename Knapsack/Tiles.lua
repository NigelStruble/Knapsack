local _, ns = ...
local L, C, W, DB = ns.L, ns.C, ns.W, ns.DB

-- Item tiles: how an item looks in a window (icon, quality border, stack
-- count, item level or a mail item's time left, vendor value, cooldown,
-- new-item glow, quest marker, red for items the character cannot use).
--
-- A tile never handles clicks on the player's own items itself. For an item in
-- the player's bags (or bank, at the bank), one of Blizzard's own container
-- item buttons (ContainerFrameItemButtonTemplate, or on Classic
-- BankItemButtonGenericTemplate for the bank's own slots) lies over the tile,
-- invisible, so using, moving, selling, splitting and depositing items all run
-- Blizzard's own code, exactly as in the default bags. To keep that code
-- untainted, those buttons:
--   * are only ever created out of combat (one per bag slot, kept for good),
--   * get their bag from their parent's ID and their slot from their own ID,
--     both set once when they are created,
--   * are never written into: everything Knapsack tracks about them lives in
--     the tables in this file.
-- Tiles for other characters, snapshots and the guild vault show the item's
-- tooltip themselves and handle shift-click (link) and control-click (try on).

local Tiles = {}
ns.Tiles = Tiles

local _G = _G
local ipairs, setmetatable, getmetatable, format, tremove, floor = ipairs, setmetatable, getmetatable, string.format, table.remove, math.floor

local QUESTION_MARK = 134400
local QUEST_BANG = _G.TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local GLOW_ATLAS = "bags-glow-white"
local hasGlowAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(GLOW_ATLAS) ~= nil
local BORDER_PLAIN = { 0.2, 0.2, 0.22 }
local BORDER_QUEST = { 1, 0.82, 0 }
local SLOT_BG = { 0.05, 0.05, 0.06, 0.9 }
local FREE_BG = { 0.12, 0.12, 0.14, 0.9 }
local UNUSABLE = { 1, 0.3, 0.3 }
local DIMMED = 0.25

--------------------------------------------------------------------------------
-- Tooltips for tiles that handle the mouse themselves
--------------------------------------------------------------------------------

local function Anchor(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	local calculate = _G.ContainerFrameItemButton_CalculateItemTooltipAnchors
	if calculate then
		calculate(owner, GameTooltip)
	else
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	end
end

local function ShowTooltip(tile)
	local rec, free = tile.record, tile.free
	if rec then
		Anchor(tile)
		if rec.live and rec.bag then
			C.SetTooltipBagItem(GameTooltip, rec.bag, rec.slot)
		else
			GameTooltip:SetHyperlink(rec.link)
		end
		GameTooltip:Show()
	elseif free then
		GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
		GameTooltip:SetText(free.name or L["Free slots"], 1, 1, 1)
		GameTooltip:AddLine(format(L["%d free slots"], free.count), 0.8, 0.8, 0.8)
		if free.live then
			GameTooltip:AddLine(L["Drop an item here to put it in an empty slot."], 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end
end

local function Tile_OnEnter(self)
	self.hover:Show()
	ShowTooltip(self)
end

local function Tile_OnLeave(self)
	self.hover:Hide()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function Tile_OnClick(self, button)
	local rec = self.record
	if not rec then
		return
	end
	if button == "MiddleButton" then
		ns.Categories.Unassign(rec.itemID)
	elseif IsModifiedClick() then
		HandleModifiedItemClick(rec.link)
	end
end

--------------------------------------------------------------------------------
-- Tiles
--------------------------------------------------------------------------------

local pool = {}
local isTile = setmetatable({}, { __mode = "k" })

local function SetBorder(tile, r, g, b)
	for _, edge in ipairs(tile.border) do
		edge:SetColorTexture(r, g, b, 1)
	end
end

-- The quality border is a whole number of screen pixels at any scale (a
-- fraction of a pixel can come out as nothing), and the icon sits inside it.
local function SizeBorder(tile)
	local pixels = DB.settings.borderSize or 2
	local size = pixels * C.PixelSize(tile)
	if tile.borderSize == size then
		return
	end
	tile.borderSize = size
	local edges = tile.border
	edges[1]:SetHeight(size)
	edges[2]:SetHeight(size)
	edges[3]:SetWidth(size)
	edges[4]:SetWidth(size)
	tile.icon:ClearAllPoints()
	tile.icon:SetPoint("TOPLEFT", size, -size)
	tile.icon:SetPoint("BOTTOMRIGHT", -size, size)
	local inset = size + 1
	tile.count:ClearAllPoints()
	tile.count:SetPoint("BOTTOMRIGHT", -inset, inset)
	tile.value:ClearAllPoints()
	tile.value:SetPoint("BOTTOMLEFT", inset, inset)
	tile.level:ClearAllPoints()
	tile.level:SetPoint("TOPLEFT", inset, -inset)
	tile.quest:ClearAllPoints()
	tile.quest:SetPoint("TOPRIGHT", -size, -size)
end

local function NewTile()
	local tile = CreateFrame("Button", nil, UIParent)
	tile:RegisterForClicks("AnyUp")
	tile.bg = tile:CreateTexture(nil, "BACKGROUND")
	tile.bg:SetAllPoints()
	tile.icon = tile:CreateTexture(nil, "ARTWORK")
	tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tile.border = W.Border(tile, BORDER_PLAIN)

	tile.cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
	tile.cooldown:SetAllPoints(tile.icon)

	-- Text and markers sit above the cooldown swipe.
	local overlay = CreateFrame("Frame", nil, tile)
	overlay:SetAllPoints()
	tile.overlay = overlay
	tile.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	tile.count:SetJustifyH("RIGHT")
	tile.value = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	tile.value:SetJustifyH("LEFT")
	tile.level = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	tile.level:SetJustifyH("LEFT")
	tile.quest = overlay:CreateTexture(nil, "OVERLAY")
	tile.quest:SetTexture(QUEST_BANG)
	tile.quest:SetSize(14, 14)
	tile.glow = overlay:CreateTexture(nil, "OVERLAY")
	tile.glow:SetAllPoints()
	if hasGlowAtlas then
		tile.glow:SetAtlas(GLOW_ATLAS)
	else
		tile.glow:SetColorTexture(1, 1, 1, 0.3)
	end
	tile.glow:SetBlendMode("ADD")
	tile.hover = overlay:CreateTexture(nil, "OVERLAY")
	tile.hover:SetAllPoints()
	tile.hover:SetColorTexture(1, 1, 1, 0.14)

	tile:SetScript("OnEnter", Tile_OnEnter)
	tile:SetScript("OnLeave", Tile_OnLeave)
	tile:SetScript("OnClick", Tile_OnClick)
	isTile[tile] = true
	return tile
end

function Tiles.Acquire(parent, level)
	local tile = tremove(pool) or NewTile()
	tile:SetParent(parent)
	tile:SetFrameLevel(level)
	tile.cooldown:SetFrameLevel(level + 1)
	tile.overlay:SetFrameLevel(level + 2)
	tile:EnableMouse(true)
	tile:SetAlpha(1)
	tile:Show()
	return tile
end

function Tiles.Release(tile)
	Tiles.Secure.Detach(tile)
	tile:Hide()
	tile:ClearAllPoints()
	tile.record, tile.free = nil, nil
	if GameTooltip:IsOwned(tile) then
		GameTooltip:Hide()
	end
	pool[#pool + 1] = tile
end

function Tiles.UpdateCooldown(tile)
	local rec = tile.record
	if rec and rec.live and rec.bag then
		local start, duration, enable = C.ItemCooldown(rec.bag, rec.slot)
		start, duration = C.Clean(start), C.Clean(duration)
		if start and duration and duration > 0 and start > 0 and enable ~= 0 then
			tile.cooldown:SetCooldown(start, duration)
			tile.cooldown:Show()
			return
		end
	end
	tile.cooldown:Hide()
end

-- A merged tile (see Window.lua: merging) stands for several stacks.
local function IsNew(rec)
	local stacks = rec.stacks
	if not stacks then
		return C.IsNewItem(rec.bag, rec.slot)
	end
	for _, stack in ipairs(stacks) do
		if C.IsNewItem(stack.bag, stack.slot) then
			return true
		end
	end
	return false
end

local function CountText(count)
	if count >= 10000 then
		return floor(count / 1000) .. "k"
	end
	return count > 1 and count or ""
end

-- Draws an item. rec comes from a window (see Window.lua: Prepare).
function Tiles.Set(tile, rec, size)
	tile.record, tile.free = rec, nil
	tile:SetSize(size, size)
	SizeBorder(tile)
	tile.bg:SetColorTexture(SLOT_BG[1], SLOT_BG[2], SLOT_BG[3], SLOT_BG[4])

	local info = rec.info
	tile.icon:SetTexture(rec.icon or (info and info.icon) or QUESTION_MARK)
	-- Locked items (being moved) are colorless; items the character cannot
	-- use are colorless and red.
	tile.icon:SetDesaturated((rec.locked or rec.unusable) and true or false)
	if rec.unusable then
		tile.icon:SetVertexColor(UNUSABLE[1], UNUSABLE[2], UNUSABLE[3])
	else
		tile.icon:SetVertexColor(1, 1, 1)
	end
	tile.icon:Show()

	local quality = rec.quality
	if rec.isQuest then
		SetBorder(tile, BORDER_QUEST[1], BORDER_QUEST[2], BORDER_QUEST[3])
	elseif quality and quality ~= 1 then
		SetBorder(tile, C.QualityColor(quality))
	else
		SetBorder(tile, BORDER_PLAIN[1], BORDER_PLAIN[2], BORDER_PLAIN[3])
	end

	tile.count:SetText(CountText(rec.count))
	-- Bottom left: a junk item's value, or "BoE" / "BoU" on items that can
	-- still be traded (junk never binds, so the two do not meet).
	tile.value:SetTextColor(1, 1, 1)
	if rec.showValue and rec.value and rec.value > 0 then
		tile.value:SetText(C.ShortMoney(rec.value))
	elseif DB.settings.bindMarker and info and ns.Categories.HasBinding("boe", rec, info) then
		tile.value:SetText(L["BoE"])
		tile.value:SetTextColor(0.45, 1, 0.45)
	elseif DB.settings.bindMarker and info and ns.Categories.HasBinding("bou", rec, info) then
		tile.value:SetText(L["BoU"])
		tile.value:SetTextColor(0.45, 1, 0.45)
	else
		tile.value:SetText("")
	end
	-- Top left: how long a mail item has left, or the item level of gear.
	local level = info and info.showLevel and info.itemLevel
	if rec.expires then
		local left = rec.expires - time()
		tile.level:SetText(C.ShortTime(left))
		if left < 86400 then
			tile.level:SetTextColor(1, 0.25, 0.25)
		elseif left < 3 * 86400 then
			tile.level:SetTextColor(1, 0.6, 0.1)
		else
			tile.level:SetTextColor(0.9, 0.9, 0.9)
		end
	elseif level and level > 0 and DB.settings.itemLevel then
		tile.level:SetText(level)
		tile.level:SetTextColor(C.QualityColor(quality or 1))
	else
		tile.level:SetText("")
	end
	tile.quest:SetShown(rec.questStarter and true or false)

	-- New items glow until the mouse passes over them, like the default bags.
	if rec.live and C.isBag[rec.bag] and IsNew(rec) then
		tile.glow:SetVertexColor(C.QualityColor(quality and quality > 1 and quality or 1))
		tile.glow:Show()
	else
		tile.glow:Hide()
	end
	Tiles.UpdateCooldown(tile)
	tile.hover:Hide()
end

-- Draws the free slots of one bag family: entry = { count, bag, slot, name, live }.
function Tiles.SetFree(tile, entry, size)
	tile.record, tile.free = nil, entry
	tile:SetSize(size, size)
	SizeBorder(tile)
	tile.bg:SetColorTexture(FREE_BG[1], FREE_BG[2], FREE_BG[3], FREE_BG[4])
	tile.icon:Hide()
	SetBorder(tile, BORDER_PLAIN[1], BORDER_PLAIN[2], BORDER_PLAIN[3])
	tile.count:SetText(entry.count)
	tile.value:SetText("")
	tile.level:SetText("")
	tile.quest:Hide()
	tile.glow:Hide()
	tile.cooldown:Hide()
	tile.hover:Hide()
end

-- Dims tiles that do not match the search.
function Tiles.SetMatch(tile, match)
	tile:SetAlpha(match and 1 or DIMMED)
end

--------------------------------------------------------------------------------
-- Blizzard's item buttons over the tiles
--------------------------------------------------------------------------------

local Secure = {}
Tiles.Secure = Secure

local holders = {} -- [bag] = frame whose ID is the bag, parent of its buttons
local buttons = {} -- [bag] = { [slot] = button }
local tileOf = setmetatable({}, { __mode = "k" }) -- [button] = the tile it lies over
local buttonOf = setmetatable({}, { __mode = "k" }) -- [tile] = its button

-- True when a button was needed in combat, where none can be made. Windows
-- redraw after combat to put the missing ones in.
Secure.short = false

local function Secure_OnEnter(button)
	local tile = tileOf[button]
	if not tile then
		return
	end
	tile.hover:Show()
	-- Blizzard's code just cleared the new-item flag of the button's slot; a
	-- merged tile clears its other stacks too.
	tile.glow:Hide()
	local stacks = tile.record and tile.record.stacks
	if stacks then
		for _, stack in ipairs(stacks) do
			C.RemoveNewItem(stack.bag, stack.slot)
		end
	end
	if tile.free then
		ShowTooltip(tile)
	end
end

local function Secure_OnLeave(button)
	local tile = tileOf[button]
	if tile then
		tile.hover:Hide()
	end
end

local function Secure_OnMouseUp(button, mouseButton)
	if mouseButton ~= "MiddleButton" then
		return
	end
	local tile = tileOf[button]
	local rec = tile and tile.record
	if rec then
		ns.Categories.Unassign(rec.itemID)
	end
end

-- Buttons for these bags live in parent (a window's content frame), so they
-- are clipped by its scrolling and hidden with it.
function Secure.SetParent(bags, parent)
	for _, bag in ipairs(bags) do
		if not holders[bag] then
			local holder = CreateFrame("Frame", nil, parent)
			holder:SetID(bag)
			holder:SetSize(1, 1)
			holder:SetPoint("TOPLEFT")
			holders[bag] = holder
		end
	end
end

local function Create(bag, slot)
	local holder = holders[bag]
	if not holder or InCombatLockdown() then
		return nil
	end
	-- The Classic bank's own slots have their own template; bags and bank bags
	-- (and Retail's bank tabs) use the bags' one.
	local template = (bag == C.BANK_CONTAINER) and "BankItemButtonGenericTemplate" or "ContainerFrameItemButtonTemplate"
	local button = CreateFrame("ItemButton", nil, holder, template)
	button:SetID(slot)
	-- The tile underneath draws everything, so the button is made invisible,
	-- with the frame's own SetAlpha: the template's SetAlpha (ItemButtonMixin)
	-- only fades the icon and count, and would leave its slot frame and the
	-- blue shop-item glow showing over the tile.
	getmetatable(button).__index.SetAlpha(button, 0)
	-- Let the mouse wheel reach the window's scrolling.
	button:SetScript("OnMouseWheel", nil)
	button:EnableMouseWheel(false)
	button:HookScript("OnEnter", Secure_OnEnter)
	button:HookScript("OnLeave", Secure_OnLeave)
	button:HookScript("OnMouseUp", Secure_OnMouseUp)
	button:Hide()
	buttons[bag] = buttons[bag] or {}
	buttons[bag][slot] = button
	return button
end

-- Makes the buttons for slots 1 to count of a bag, out of combat.
function Secure.Prepare(bag, count)
	for slot = 1, count do
		if not (buttons[bag] and buttons[bag][slot]) and not Create(bag, slot) then
			Secure.short = true
			return false
		end
	end
	return true
end

function Secure.Get(bag, slot)
	return buttons[bag] and buttons[bag][slot]
end

-- Lays the button for bag/slot over the tile. Returns nil (and the tile keeps
-- the mouse) when the button cannot be made yet because of combat.
function Secure.Attach(tile, bag, slot)
	local button = Secure.Get(bag, slot) or Create(bag, slot)
	if not button then
		Secure.short = true
		return nil
	end
	local previous = tileOf[button]
	if previous and previous ~= tile then
		buttonOf[previous] = nil
		previous:EnableMouse(true)
	end
	button:ClearAllPoints()
	button:SetAllPoints(tile)
	button:SetFrameLevel(tile:GetFrameLevel() + 5)
	button:Show()
	tileOf[button] = tile
	buttonOf[tile] = button
	tile:EnableMouse(false)
	return button
end

function Secure.Detach(tile)
	local button = buttonOf[tile]
	if not button then
		return
	end
	buttonOf[tile] = nil
	tile:EnableMouse(true)
	if tileOf[button] == tile then
		tileOf[button] = nil
		button:Hide()
		button:ClearAllPoints()
	end
end

function Secure.Attached(tile)
	return buttonOf[tile]
end

-- The item shown by a tile, or by the tile under one of Blizzard's buttons,
-- for adding to its tooltip (see Tooltip.lua). Nil for anything else.
function Tiles.RecordFor(frame)
	if not frame then
		return nil
	end
	local tile = tileOf[frame] or (isTile[frame] and frame)
	return tile and tile.record
end
