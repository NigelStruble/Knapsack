-- A mock of the World of Warcraft API, enough to load Knapsack and drive it
-- from tests: the Retail engine (Retail and Forever) by default, or with
-- options.classic a Classic client (Burning Crusade Classic Anniversary): a
-- bank of one container and bank bags, a keyring, no C_TooltipInfo (tooltips
-- are read from a hidden GameTooltip's lines), and OnTooltipSetItem instead of
-- a working TooltipDataProcessor.
--
-- Frames accept any method (unknown ones do nothing); the static check with
-- the WoW API annotations catches misspelled methods instead. What matters for
-- the tests is modelled: visibility and OnShow/OnHide, scripts and hooks,
-- events, timers, containers, the bank and guild vault, tooltips and menus.
--
-- Two rules of the real client are enforced for Blizzard's container item
-- buttons (ContainerFrameItemButtonTemplate), because breaking them taints the
-- buttons in game:
--   * creating one in combat is recorded in state.violations,
--   * so is any addon code writing a field into one.

local Mock = {}

local format = string.format

--------------------------------------------------------------------------------
-- Item data
--------------------------------------------------------------------------------

-- [itemID] = { name, quality, classID, subClassID, sellPrice, icon, equipLoc }
Mock.ITEMS = {
	[6948] = { "Hearthstone", 1, 15, 0, 0, 134414 },
	[2589] = { "Linen Cloth", 1, 7, 5, 13, 132889 },
	[4306] = { "Silk Cloth", 1, 7, 5, 150, 132905 },
	[858] = { "Lesser Healing Potion", 1, 0, 1, 5, 134830 },
	[4540] = { "Tough Hunk of Bread", 1, 0, 5, 1, 133964 },
	[5635] = { "Sharp Claw", 0, 15, 0, 35, 134294 },
	[4865] = { "Ruined Pelt", 0, 15, 0, 5, 134353 },
	[3300] = { "Rabbit's Foot", 0, 15, 0, 20, 133854 },
	[2210] = { "Battered Buckler", 0, 4, 6, 3, 134955, "INVTYPE_SHIELD" },
	[1411] = { "Withered Staff", 0, 2, 10, 12, 135145, "INVTYPE_2HWEAPON" },
	[11000] = { "Shadowforge Key", 1, 12, 0, 0, 134248 },
	[2512] = { "Rough Arrow", 1, 6, 2, 0, 132382, "INVTYPE_AMMO" },
	[4496] = { "Small Brown Pouch", 1, 1, 0, 25, 133639, "INVTYPE_BAG" },
	[12345] = { "Green Sword of the Monkey", 2, 2, 7, 1000, 135274, "INVTYPE_WEAPON" },
	[7070] = { "Elemental Water", 2, 7, 10, 100, 134714 },
	[9999] = { "Mystery Trinket", 0, 15, 0, 7, 133434 },
	[17029] = { "Sacred Candle", 1, 5, 0, 37, 133750 },
	[20749] = { "Brilliant Wizard Oil", 1, 0, 8, 1000, 134727 },
	[10205] = { "Thick Plate Helm", 2, 4, 4, 900, 133126, "INVTYPE_HEAD" },
	[4336] = { "Black Silk Pack", 1, 1, 0, 500, 133655, "INVTYPE_BAG" },
	[16060] = { "Common White Shirt", 1, 4, 0, 1, 135022, "INVTYPE_BODY" },
	[13446] = { "Major Healing Potion", 1, 0, 1, 1000, 134834 },
	[4238] = { "Linen Bag", 1, 1, 0, 100, 133639, "INVTYPE_BAG" },
	[2101] = { "Light Quiver", 1, 11, 2, 1, 134407, "INVTYPE_BAG" },
	[5396] = { "Key to Searing Gorge", 1, 13, 0, 0, 134237 },
}

-- What the tuples above leave out: maxStack (default 20), level (item level,
-- default 10), spell (used on use), charges (a fresh one's), unusable (a red
-- "Requires" line in its tooltip for the test character), bind (how it binds:
-- 1 on pickup, 2 on equip, 3 on use; default 0, never).
Mock.ITEM_EXTRA = {
	[6948] = { maxStack = 1, spell = true, bind = 1 },
	[858] = { spell = true },
	[12345] = { maxStack = 1, level = 25, harmlessRed = true, bind = 2 },
	[13446] = { spell = true, unusable = true },
	[2210] = { maxStack = 1, level = 5 },
	[1411] = { maxStack = 1, level = 8 },
	[20749] = { maxStack = 1, spell = true, charges = 5 },
	[10205] = { maxStack = 1, level = 48, unusable = true, bind = 2 },
	[4336] = { maxStack = 1, level = 45 },
	[16060] = { maxStack = 1, level = 1 },
	[2512] = { maxStack = 200, family = 1 }, -- arrows: a quiver takes them
	[5396] = { maxStack = 1, family = 256 }, -- a key: the keyring takes it
}

function Mock.Extra(itemID)
	return Mock.ITEM_EXTRA[itemID] or {}
end

local QUALITY_COLORS = {
	[0] = { 0.62, 0.62, 0.62, "ff9d9d9d" },
	[1] = { 1, 1, 1, "ffffffff" },
	[2] = { 0.12, 1, 0, "ff1eff00" },
	[3] = { 0, 0.44, 0.87, "ff0070dd" },
	[4] = { 0.64, 0.21, 0.93, "ffa335ee" },
	[5] = { 1, 0.5, 0, "ffff8000" },
}

-- Links as Forever makes them. crafter: the GUID of the player who made the
-- item, which the game puts in the links of crafted items that do not stack
-- (Wizard Oil): "item:20744::::::::20:1487::::::::Player-4618-00AB97C1:".
function Mock.Link(itemID, crafter)
	local item = Mock.ITEMS[itemID]
	local color = QUALITY_COLORS[item and item[2] or 1][4]
	return format("|c%s|Hitem:%d::::::::60:1487::::::::%s:|h[%s]|h|r", color, itemID, crafter or "", item and item[1] or "Unknown")
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local Methods = {}

local function CallScript(frame, script, ...)
	local state = rawget(frame, "__state")
	local handler = frame.__scripts[script]
	if handler then
		state.CallProtected(handler, frame, ...)
	end
	for _, hook in ipairs(frame.__hooks[script] or {}) do
		state.CallProtected(hook, frame, ...)
	end
end
Mock.CallScript = CallScript

function Methods:GetName()
	return self.__name
end

function Methods:GetObjectType()
	return self.__type
end

function Methods:SetParent(parent)
	rawset(self, "__parent", parent)
end

function Methods:GetParent()
	return self.__parent
end

function Methods:SetID(id)
	rawset(self, "__id", id)
end

function Methods:GetID()
	return self.__id or 0
end

function Methods:Show()
	if not self.__shown then
		rawset(self, "__shown", true)
		CallScript(self, "OnShow")
	end
end

function Methods:Hide()
	if self.__shown then
		rawset(self, "__shown", false)
		CallScript(self, "OnHide")
	end
end

function Methods:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end

function Methods:IsShown()
	return self.__shown
end

function Methods:IsVisible()
	local frame = self
	while frame do
		if not frame.__shown then
			return false
		end
		frame = frame.__parent
	end
	return true
end

function Methods:SetScript(script, handler)
	self.__scripts[script] = handler
end

function Methods:GetScript(script)
	return self.__scripts[script]
end

function Methods:HookScript(script, handler)
	local hooks = self.__hooks[script] or {}
	hooks[#hooks + 1] = handler
	self.__hooks[script] = hooks
end

function Methods:RegisterEvent(event)
	if not self.__state.events[event] then
		error(format("Attempt to register unknown event \"%s\"", tostring(event)), 2)
	end
	self.__events[event] = true
end

function Methods:UnregisterEvent(event)
	self.__events[event] = nil
end

-- Only the player's events are ever fired for a unit here.
function Methods:RegisterUnitEvent(event)
	self:RegisterEvent(event)
end

function Methods:SetSize(width, height)
	rawset(self, "__width", width)
	rawset(self, "__height", height)
end

function Methods:SetWidth(width)
	rawset(self, "__width", width)
end

function Methods:SetHeight(height)
	rawset(self, "__height", height)
end

function Methods:GetWidth()
	return self.__width or 0
end

function Methods:GetHeight()
	return self.__height or 0
end

function Methods:GetSize()
	return self:GetWidth(), self:GetHeight()
end

function Methods:SetPoint(point, relativeTo, relativePoint, x, y)
	local points = self.__points
	if type(relativeTo) == "number" then
		relativeTo, relativePoint, x, y = self.__parent, point, relativeTo, relativePoint
	end
	points[#points + 1] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end

function Methods:ClearAllPoints()
	rawset(self, "__points", {})
end

function Methods:SetAllPoints(relativeTo)
	self:ClearAllPoints()
	self.__points[1] = { "ALL", relativeTo or self.__parent }
	rawset(self, "__allPoints", relativeTo or self.__parent)
end

function Methods:GetPoint(index)
	local p = self.__points[index or 1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
end

function Methods:GetNumPoints()
	return #self.__points
end

-- Positions are not laid out; these numbers only have to be plausible.
function Methods:GetLeft()
	return 100
end

function Methods:GetRight()
	return 100 + self:GetWidth()
end

function Methods:GetTop()
	return 700
end

function Methods:GetBottom()
	return 700 - self:GetHeight()
end

function Methods:SetScale(scale)
	rawset(self, "__scale", scale)
end

function Methods:GetScale()
	return self.__scale or 1
end

function Methods:GetEffectiveScale()
	return self:GetScale()
end

function Methods:SetAlpha(alpha)
	rawset(self, "__alpha", alpha)
end

function Methods:GetAlpha()
	return self.__alpha or 1
end

function Methods:SetFrameLevel(level)
	rawset(self, "__level", level)
end

function Methods:GetFrameLevel()
	return self.__level or 0
end

function Methods:EnableMouse(enable)
	rawset(self, "__mouse", enable and true or false)
end

function Methods:IsMouseEnabled()
	return self.__mouse or false
end

function Methods:IsMouseOver()
	return self.__state.mouseOver == self
end

function Methods:CreateTexture(name)
	return Mock.NewFrame(self.__state, "Texture", name, self)
end

function Methods:CreateFontString(name)
	return Mock.NewFrame(self.__state, "FontString", name, self)
end

-- Texture and FontString
function Methods:SetText(text)
	rawset(self, "__text", text ~= nil and tostring(text) or nil)
	if self.__scripts.OnTextChanged then
		CallScript(self, "OnTextChanged", true)
	end
end

function Methods:GetText()
	return self.__text
end

function Methods:GetStringWidth()
	local text = (self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "WW")
	return #text * 6
end

function Methods:GetStringHeight()
	return 12
end

function Methods:SetTextColor(r, g, b)
	rawset(self, "__textColor", { r, g, b })
end

function Methods:GetTextColor()
	local c = self.__textColor or { 1, 1, 1 }
	return c[1], c[2], c[3], 1
end

function Methods:SetTexture(texture)
	rawset(self, "__texture", texture)
end

function Methods:GetTexture()
	return self.__texture
end

function Methods:SetAtlas(atlas)
	rawset(self, "__atlas", atlas)
	return true
end

function Methods:SetColorTexture(r, g, b, a)
	rawset(self, "__color", { r, g, b, a })
end

function Methods:SetVertexColor(r, g, b)
	rawset(self, "__vertex", { r, g, b })
end

function Methods:SetDesaturated(desaturated)
	rawset(self, "__desaturated", desaturated and true or false)
end

function Methods:IsDesaturated()
	return self.__desaturated or false
end

-- Scroll frames, sliders, edit boxes
function Methods:SetScrollChild(child)
	rawset(self, "__scrollChild", child)
end

function Methods:SetMinMaxValues(low, high)
	rawset(self, "__min", low)
	rawset(self, "__max", high)
end

function Methods:GetMinMaxValues()
	return self.__min or 0, self.__max or 0
end

function Methods:SetValue(value)
	rawset(self, "__value", value)
	CallScript(self, "OnValueChanged", value)
end

function Methods:GetValue()
	return self.__value or 0
end

function Methods:SetEnabled(enabled)
	rawset(self, "__enabled", enabled and true or false)
end

function Methods:Enable()
	self:SetEnabled(true)
end

function Methods:Disable()
	self:SetEnabled(false)
end

function Methods:IsEnabled()
	return self.__enabled ~= false
end

-- Cooldowns
function Methods:SetCooldown(start, duration)
	rawset(self, "__cooldown", { start, duration })
end

function Methods:SetAttribute(name, value)
	self.__attributes = self.__attributes or {}
	self.__attributes[name] = value
end

function Methods:GetAttribute(name)
	return self.__attributes and self.__attributes[name]
end

-- Edit boxes and the keyboard
function Methods:SetFocus()
	if not self.__focus then
		rawset(self, "__focus", true)
		CallScript(self, "OnEditFocusGained")
	end
end

function Methods:ClearFocus()
	if self.__focus then
		rawset(self, "__focus", false)
		CallScript(self, "OnEditFocusLost")
	end
end

function Methods:HasFocus()
	return self.__focus or false
end

function Methods:StartMoving() end

function Methods:StopMovingOrSizing() end

local function Noop() end

-- Methods the addon calls that change nothing the tests look at. Anything not
-- here or in Methods is nil, as it would be on a real frame, so a misspelled
-- method still fails.
local NOOPS = {}
for _, name in ipairs({
	"SetMovable", "SetClampedToScreen", "SetToplevel", "SetFrameStrata", "RegisterForDrag", "RegisterForClicks",
	"SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFontObject", "SetTextInsets", "SetAutoFocus", "SetMaxLetters",
	"SetCursorPosition", "ClearFocus", "SetBlendMode", "SetTexCoord", "SetOrientation", "SetValueStep",
	"SetObeyStepOnDrag", "SetThumbTexture", "EnableMouseWheel", "SetDrawEdge", "Raise", "Lower",
	"SetFont", "SetVerticalScroll", "UnregisterAllEvents", "SetAnchorType", "Clear", "SetHighlightTexture",
	"SetNormalTexture", "SetPushedTexture", "SetMotionScriptsWhileDisabled", "SetFocus",
}) do
	NOOPS[name] = Noop
end

-- As in the client, a frame's metatable has a table of the widget's methods as
-- __index, so getmetatable(frame).__index.SetAlpha is the frame's own method
-- even where a template's mixin has put a different SetAlpha on the frame.
local methodIndex = setmetatable({}, {
	__index = function(_, key)
		return Methods[key] or NOOPS[key]
	end,
})

local frameMeta = { __index = methodIndex }

-- Blizzard's container item buttons: writing a field into one taints it.
local secureMeta = {
	__index = methodIndex,
	__newindex = function(frame, key, value)
		local state = rawget(frame, "__state")
		state.violations[#state.violations + 1] = "field written into a container item button: " .. tostring(key)
		rawset(frame, key, value)
	end,
}

function Mock.NewFrame(state, frameType, name, parent, template)
	local frame = {
		__state = state,
		__type = frameType,
		__name = name,
		__parent = parent,
		__scripts = {},
		__hooks = {},
		__events = {},
		__points = {},
		__shown = true,
		__template = template,
	}
	setmetatable(frame, frameMeta)
	state.frames[#state.frames + 1] = frame
	if name then
		state.env[name] = frame
	end
	return frame
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

-- Text as a tooltip draws it: without color codes, and with
-- |4singular:plural; after a number resolved ("5 Charges").
local function Drawn(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (text:gsub("(%d+)(%s*)|4([^:;]*):([^;]*);", function(number, space, one, many)
		return number .. space .. (tonumber(number) == 1 and one or many)
	end))
end

-- A tooltip. Its lines are { left, right, leftColor, rightColor }. The Retail
-- engine's tooltips only show an item's name and hand the item to the
-- TooltipDataProcessor post calls (state.tooltipCalls). A Classic client's
-- show every line of the item (state.TooltipData) and fire OnTooltipSetItem;
-- a named one (GameTooltipTemplate) also has its lines as font strings,
-- NameTextLeft1, NameTextRight1, ..., which is how addons read them.
local function NewTooltip(state, name)
	local tip = Mock.NewFrame(state, "GameTooltip", name)
	rawset(tip, "__shown", false)
	tip.lines = {}

	local function Render(self)
		if not (name and state.classic) then
			return
		end
		for i = 1, math.max(#self.lines, self.rendered or 0) do
			local line = self.lines[i]
			for _, side in ipairs({ "Left", "Right" }) do
				local key = name .. "Text" .. side .. i
				local fontString = rawget(state.env, key) or Mock.NewFrame(state, "FontString", key, self)
				local text = line and (side == "Left" and line.left or line.right)
				local color = line and (side == "Left" and line.leftColor or line.rightColor)
				rawset(fontString, "__text", text)
				rawset(fontString, "__textColor", color and { color.r, color.g, color.b } or nil)
				rawset(fontString, "__shown", text ~= nil)
			end
		end
		self.rendered = #self.lines
	end

	local function SetLines(self, lines)
		self.lines = lines
		Render(self)
	end

	function tip:SetOwner(owner)
		self:Hide()
		self.owner = owner
		self.item, self.itemLink = nil, nil
		SetLines(self, {})
	end

	function tip:GetOwner()
		return self.owner
	end

	function tip:IsOwned(frame)
		return self.owner == frame
	end

	function tip:ClearLines()
		self.item, self.itemLink = nil, nil
		SetLines(self, {})
	end

	function tip:NumLines()
		return #self.lines
	end

	-- name, link of the item shown.
	function tip:GetItem()
		if self.item then
			local data = Mock.ITEMS[self.item]
			return data and data[1], self.itemLink
		end
	end

	function tip:SetText(text)
		SetLines(self, { { left = tostring(text) } })
	end

	function tip:AddLine(text)
		assert(type(text) == "string" or type(text) == "number", "AddLine: text must be a string")
		self.lines[#self.lines + 1] = { left = tostring(text) }
		Render(self)
	end

	function tip:AddDoubleLine(left, right, lr, lg, lb)
		assert(type(left) == "string" or type(left) == "number", "AddDoubleLine: left text")
		assert(type(right) == "string" or type(right) == "number", "AddDoubleLine: right text")
		self.lines[#self.lines + 1] = { left = tostring(left), right = tostring(right), r = lr, g = lg, b = lb }
		Render(self)
	end

	-- item: the item where it is ({ id, count, charges }), for its charges.
	local function ShowItem(self, itemID, item)
		self.item = itemID
		self.itemLink = itemID and Mock.ITEMS[itemID] and Mock.Link(itemID, item and item.crafter)
		if state.classic then
			local data = state.TooltipData(itemID, item)
			local lines = {}
			for i, line in ipairs(data and data.lines or {}) do
				lines[i] = {
					left = line.leftText and Drawn(line.leftText),
					leftColor = line.leftColor,
					right = line.rightText and Drawn(line.rightText),
					rightColor = line.rightColor,
				}
			end
			SetLines(self, lines)
			CallScript(self, "OnTooltipSetItem")
			return
		end
		self.lines = { { left = Mock.ITEMS[itemID] and Mock.ITEMS[itemID][1] or "?" } }
		for _, call in ipairs(state.tooltipCalls) do
			call(self, { id = itemID, type = 0 })
		end
	end

	-- A Classic client shows nothing for the bank's own slots or the keyring
	-- here: Blizzard's code shows those as inventory slots.
	function tip:SetBagItem(bag, slot)
		if state.classic and bag < 0 then
			return
		end
		local item = Mock.Container(state, bag)
		item = item and item.items[slot]
		if item then
			ShowItem(self, item.id, item)
		end
	end

	function tip:SetHyperlink(link)
		ShowItem(self, tonumber(link:match("item:(%d+)")))
	end

	-- A worn bag, or on Classic also a bank or keyring slot (state.InventoryItem).
	function tip:SetInventoryItem(_, slot)
		local id, item = state.InventoryItem(slot)
		if id then
			ShowItem(self, id, item)
			return true
		end
		return false
	end

	function tip:SetInboxItem(index, attachment)
		local mail = state.mailbox[index]
		local item = mail and mail.items and mail.items[attachment or 1]
		if item then
			ShowItem(self, item.id, item)
		end
	end

	function tip:SetSendMailItem(attachment)
		local item = state.sendMail.items[attachment]
		if item then
			ShowItem(self, item.id, item)
		end
	end

	function tip:Show()
		rawset(self, "__shown", true)
	end

	function tip:Hide()
		rawset(self, "__shown", false)
	end

	-- The tooltip as text, one line per row: "left | right".
	function tip:Text()
		local rows = {}
		for i, line in ipairs(self.lines) do
			rows[i] = line.right and (line.left .. " | " .. line.right) or line.left
		end
		return table.concat(rows, "\n")
	end

	return tip
end

--------------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------------

local function NewDescription(kind, text, callback)
	local d = { kind = kind, text = text, callback = callback, children = {} }
	local function Add(child)
		d.children[#d.children + 1] = child
		return child
	end
	function d:CreateTitle(title)
		return Add(NewDescription("title", title))
	end
	function d:CreateButton(label, fn)
		return Add(NewDescription("button", label, fn))
	end
	function d:CreateDivider()
		return Add(NewDescription("divider"))
	end
	function d:Find(label)
		for _, child in ipairs(self.children) do
			if child.text == label then
				return child
			end
		end
	end
	return d
end

--------------------------------------------------------------------------------
-- Containers: state.containers[bag] = { size, family, name, items = { [slot] = { id, count, locked, quest, new } } }
--------------------------------------------------------------------------------

function Mock.Container(state, bag)
	if state.bankBags[bag] and (not state.atBank or state.bankLoading) then
		return nil -- away from the bank (or before its tabs arrive) the client does not know its contents
	end
	return state.containers[bag]
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local KNOWN_EVENTS = {
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "BAG_UPDATE",
	"BAG_UPDATE_DELAYED", "BAG_CONTAINER_UPDATE", "BAG_NEW_ITEMS_UPDATED", "BAG_UPDATE_COOLDOWN", "ITEM_LOCK_CHANGED",
	"PLAYER_MONEY", "PLAYER_LEVEL_UP", "PLAYER_GUILD_UPDATE", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "GUILDBANKFRAME_OPENED",
	"GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_TABS",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GET_ITEM_INFO_RECEIVED",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "MAIL_SHOW", "MAIL_CLOSED", "TRADE_SHOW", "TRADE_CLOSED",
	"AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED", "UI_SCALE_CHANGED",
	"DISPLAY_SIZE_CHANGED", "UNIT_SPELLCAST_SUCCEEDED", "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
}

-- Events only one kind of client has.
local RETAIL_EVENTS = { "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED" }
local CLASSIC_EVENTS = { "PLAYERBANKBAGSLOTS_CHANGED" }

-- The Classic bank's own slots and the keyring's, as inventory slots.
local BANK_INVENTORY, KEYRING_INVENTORY = 39, 85

-- What a Classic bank bag slot costs, by the number already bought.
Mock.BANK_SLOT_COSTS = { 1000, 10000, 100000, 250000, 250000, 250000, 250000 }

-- options.classic: a Classic client (Burning Crusade Classic Anniversary).
-- options.bankTabs: number of CharacterBankTab_N in the enum (9 on Forever).
-- options.toc: interface number (16001 = Forever, 20506 = Anniversary).
-- options.projectID: WOW_PROJECT_ID, if not the usual (1 Retail engine, 5
-- Classic); Forever's stopped matching Retail's in an October 2026 update.
function Mock.New(options)
	options = options or {}
	local classic = options.classic and true or false
	local state = {
		classic = classic,
		time = 1000,
		epoch = 1790000000,
		errors = {},
		violations = {},
		frames = {},
		timers = {},
		events = {},
		chat = {},
		menus = {},
		tooltipCalls = {},
		combat = false,
		mouseOver = nil,
		cursor = nil,
		held = nil,
		moves = {},
		mailbox = {},
		sendMail = { items = {} },
		sentMail = {},
		returnedMail = {},
		bagMoves = {},
		containers = {},
		bankBags = {},
		atBank = false,
		interaction = {},
		guild = nil,
		guildLoaded = {},
		guildQueries = {},
		requested = {},
		unloaded = {},
		closedBank = 0,
		used = {},
		loadedAddons = {},
		blizzard = {},
		money = 123456,
		player = { name = "Vedek", realm = "Doomhowl", class = "PRIEST", level = 60, faction = "Alliance" },
	}
	for _, event in ipairs(KNOWN_EVENTS) do
		state.events[event] = true
	end
	for _, event in ipairs(classic and CLASSIC_EVENTS or RETAIL_EVENTS) do
		state.events[event] = true
	end

	function state.CallProtected(func, ...)
		local ok, err = pcall(func, ...)
		if not ok then
			state.errors[#state.errors + 1] = tostring(err)
		end
	end

	local env = setmetatable({}, { __index = _G })
	env._G = env
	state.env = env

	-- Lua extras the client has
	env.strmatch = string.match
	env.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	env.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	env.tinsert = table.insert
	env.securecallfunction = function(func, ...)
		return func(...)
	end
	env.hooksecurefunc = function(a, b, c)
		local target, name, hook = env, a, b
		if type(a) == "table" then
			target, name, hook = a, b, c
		end
		local original = target[name]
		target[name] = function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results)
		end
	end

	-- Time
	env.GetTime = function()
		return state.time
	end
	env.time = function()
		return state.epoch + math.floor(state.time)
	end
	env.C_Timer = {
		After = function(delay, func)
			state.timers[#state.timers + 1] = { at = state.time + delay, func = func }
		end,
	}

	-- Client
	env.WOW_PROJECT_MAINLINE = 1
	env.WOW_PROJECT_ID = options.projectID or (classic and 5 or 1)
	env.GetBuildInfo = function()
		if classic then
			return "2.5.6", "12345", "Sep 1 2026", options.toc or 20506
		end
		return "1.16.0", "12345", "Sep 1 2026", options.toc or 16001
	end
	env.GetPhysicalScreenSize = function()
		return 1920, 1080
	end
	-- Global strings, as the English client has them.
	env.ITEM_SPELL_CHARGES = "%d |4Charge:Charges;"
	env.ITEM_SPELL_CHARGES_NONE = "No charges"
	env.DURABILITY_TEMPLATE = "Durability %d / %d"
	env.ITEM_DISENCHANT_NOT_DISENCHANTABLE = "Cannot be disenchanted"
	env.InCombatLockdown = function()
		return state.combat
	end
	env.issecretvalue = function()
		return false
	end
	env.Enum = {
		BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4 },
		PlayerInteractionType = { Banker = 8, GuildBanker = 10, Merchant = 5 },
		ItemClass = {
			Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6,
			Tradegoods = 7, ItemEnhancement = 8, Recipe = 9, Quiver = 11, Questitem = 12, Key = 13, Miscellaneous = 15,
		},
		TooltipDataType = { Item = 0 },
	}
	if classic then
		-- The bank's own slots (-1), the keyring (-2) and seven bank bag slots,
		-- containers 5 to 11. The client's enum is Retail's, and wrong for
		-- Classic: it lists a ReagentBag (5, the first bank bag), and its
		-- BankBag_N are one too high (BankBag_1 is 6), as BetterBags found.
		local BagIndex = env.Enum.BagIndex
		BagIndex.Bank, BagIndex.Keyring, BagIndex.ReagentBag = -1, -2, 5
		state.bankBags[-1] = true
		for i = 1, 7 do
			BagIndex["BankBag_" .. i] = 5 + i
			state.bankBags[4 + i] = true
		end
		env.NUM_BAG_SLOTS, env.NUM_BANKBAGSLOTS, env.NUM_BANKGENERIC_SLOTS = 4, 7, 28
		env.KEYRING = "Keyring"
	else
		env.Enum.BagIndex.ReagentBag = 5
		env.Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
		for i = 1, options.bankTabs or 9 do
			local bag = 5 + i
			env.Enum.BagIndex["CharacterBankTab_" .. i] = bag
			state.bankBags[bag] = true
		end
	end

	-- Frames
	env.UIParent = Mock.NewFrame(state, "Frame", "UIParent")
	env.UIParent:SetSize(1920, 1080)
	-- Blizzard's item buttons: onEnter shows the item in the tooltip, a click
	-- uses the item (recorded in state.used).
	local function SecureButton(frame, onEnter, onClick)
		if state.combat then
			state.violations[#state.violations + 1] = "container item button created in combat"
		end
		state.secureButtons = (state.secureButtons or 0) + 1
		frame.__scripts.OnEnter = function(self)
			env.GameTooltip:SetOwner(self, "ANCHOR_NONE")
			onEnter(self)
			env.GameTooltip:Show()
		end
		frame.__scripts.OnClick = onClick
		-- ItemButtonMixin:SetAlpha: only the icon and a few textures fade,
		-- the button itself (slot frame, shop-item glow) stays.
		rawset(frame, "SetAlpha", function(self, alpha)
			rawset(self, "__regionAlpha", alpha)
		end)
		setmetatable(frame, secureMeta)
	end

	-- Templates only one kind of client has.
	local CLASSIC_ONLY = { BankItemButtonGenericTemplate = true }
	local RETAIL_ONLY = { BankPanelPurchaseButtonScriptTemplate = true }
	env.CreateFrame = function(frameType, name, parent, template)
		if template and ((classic and RETAIL_ONLY[template]) or (not classic and CLASSIC_ONLY[template])) then
			error("CreateFrame: unknown template " .. template, 2)
		end
		if frameType == "GameTooltip" then
			return NewTooltip(state, name)
		end
		local frame = Mock.NewFrame(state, frameType, name, parent, template)
		if template and template:find("ContainerFrameItemButtonTemplate", 1, true) then
			-- The bag is the parent's ID. Classic shows a keyring item as the
			-- inventory slot it is.
			SecureButton(frame, function(self)
				local bag = self:GetParent():GetID()
				if classic and bag == -2 then
					env.GameTooltip:SetInventoryItem("player", env.KeyRingButtonIDToInvSlotID(self:GetID()))
				else
					env.GameTooltip:SetBagItem(bag, self:GetID())
				end
			end, function(self, button)
				state.used[#state.used + 1] = { bag = self:GetParent():GetID(), slot = self:GetID(), button = button }
			end)
		elseif template == "BankItemButtonGenericTemplate" then
			-- Classic's bank slots: always the bank's own container, whatever
			-- the parent, shown as inventory slots.
			SecureButton(frame, function(self)
				env.GameTooltip:SetInventoryItem("player", env.BankButtonIDToInvSlotID(self:GetID()))
			end, function(self, button)
				state.used[#state.used + 1] = { bag = -1, slot = self:GetID(), button = button }
			end)
		elseif template == "BankPanelPurchaseButtonScriptTemplate" then
			-- Blizzard's purchase button: its click opens the game's confirmation
			-- for the bank type in its "overrideBankType" attribute.
			frame.__scripts.OnClick = function(self)
				state.tabPrompt = self:GetAttribute("overrideBankType")
			end
		end
		return frame
	end
	env.GameTooltip = NewTooltip(state, "GameTooltip")
	env.ItemRefTooltip = NewTooltip(state, "ItemRefTooltip")
	env.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, message)
			state.chat[#state.chat + 1] = message
		end,
	}
	env.UISpecialFrames = {}
	env.SlashCmdList = {}
	env.GameFontHighlightSmall, env.GameFontNormal = {}, {}
	for i = 1, 13 do
		env.CreateFrame("Frame", "ContainerFrame" .. i, env.UIParent)
	end
	env.WorldFrame = env.CreateFrame("Frame", "WorldFrame")
	env.CreateFrame("Frame", "BankFrame", env.UIParent)
	if not classic then
		env.CreateFrame("Frame", "ContainerFrameCombinedBags", env.UIParent)
		-- Forever's bank panel, whose "cost of the next tab" display listens
		-- for gold changes from login.
		env.CreateFrame("Frame", "BankPanel", env.BankFrame)
		env.BankPanel.MoneyDisplay = env.CreateFrame("Frame", nil, env.BankPanel)
		env.BankPanel.MoneyDisplay:RegisterEvent("PLAYER_MONEY")
	end
	env.CreateFrame("Frame", "MerchantFrame", env.UIParent)
	env.ContainerFrameItemButton_CalculateItemTooltipAnchors = function() end
	env.HideUIPanel = function(frame)
		frame:Hide()
	end

	-- Blizzard's bag functions, which Knapsack hooks.
	for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag", "OpenBackpack", "OpenAllBags", "CloseAllBags" }) do
		env[name] = function()
			state.blizzard[name] = (state.blizzard[name] or 0) + 1
		end
	end
	if classic then
		-- The keyring button. Blizzard's code opens its own keyring window,
		-- without going through ToggleBag.
		env.ToggleKeyRing = function()
			state.blizzard.ToggleKeyRing = (state.blizzard.ToggleKeyRing or 0) + 1
		end
	end

	-- Player
	-- On Forever the second value is the character's surname.
	env.UnitName = function()
		return state.player.name, state.player.surname
	end
	env.UnitClass = function()
		return "Priest", state.player.class
	end
	env.UnitLevel = function()
		return state.player.level
	end
	env.UnitFactionGroup = function()
		return state.player.faction
	end
	env.GetRealmName = function()
		return state.player.realm
	end
	env.GetNormalizedRealmName = function()
		return state.player.realm
	end
	env.GetMoney = function()
		return state.money
	end
	env.IsInGuild = function()
		return state.guild ~= nil
	end
	env.GetGuildInfo = function()
		if state.guild then
			return state.guild.name, "Member", 3, nil
		end
	end
	env.RAID_CLASS_COLORS = {
		PRIEST = { r = 1, g = 1, b = 1 },
		MAGE = { r = 0.25, g = 0.78, b = 0.92 },
		WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
	}
	env.GetMoneyString = function(copper)
		return format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100)
	end

	-- Containers
	env.C_Container = {
		-- Classic says nothing of the keyring's size here: GetKeyRingSize does.
		GetContainerNumSlots = function(bag)
			if classic and bag == -2 then
				return 0
			end
			local c = Mock.Container(state, bag)
			return c and c.size or 0
		end,
		GetContainerNumFreeSlots = function(bag)
			local c = Mock.Container(state, bag)
			if not c then
				return 0, 0
			end
			local used = 0
			for _ in pairs(c.items) do
				used = used + 1
			end
			return c.size - used, c.family or 0
		end,
		GetContainerItemInfo = function(bag, slot)
			local c = Mock.Container(state, bag)
			local item = c and c.items[slot]
			if not item then
				return nil
			end
			local data = Mock.ITEMS[item.id]
			return {
				itemID = item.id,
				hyperlink = Mock.Link(item.id, item.crafter),
				stackCount = item.count or 1,
				quality = data and data[2],
				iconFileID = data and data[6],
				isLocked = item.locked or false,
				hasNoValue = data and data[5] == 0,
				isBound = item.bound or false,
			}
		end,
		GetContainerItemCooldown = function(bag, slot)
			local c = Mock.Container(state, bag)
			local item = c and c.items[slot]
			if item and item.cooldown then
				return item.cooldown[1], item.cooldown[2], 1
			end
			return 0, 0, 0
		end,
		GetContainerItemQuestInfo = function(bag, slot)
			local c = Mock.Container(state, bag)
			local item = c and c.items[slot]
			if item and item.quest then
				return { isQuestItem = true, questID = item.questID, isActive = item.questActive }
			end
			return { isQuestItem = false }
		end,
		GetBagName = function(bag)
			local c = Mock.Container(state, bag)
			return c and c.name
		end,
	}
	env.C_NewItems = {
		IsNewItem = function(bag, slot)
			local c = Mock.Container(state, bag)
			local item = c and c.items[slot]
			return item and item.new or false
		end,
		ClearAll = function()
			for _, c in pairs(state.containers) do
				for _, item in pairs(c.items) do
					item.new = nil
				end
			end
		end,
		RemoveNewItem = function(bag, slot)
			local c = Mock.Container(state, bag)
			local item = c and c.items[slot]
			if item then
				item.new = nil
			end
		end,
	}

	-- Moving items by hand. state.held is what the cursor holds: { bag, slot,
	-- count, id }; a split holds part of the stack. Stacks of the same item
	-- only go together with the same .bound, as soulbound and unbound items do
	-- not stack; anything else swaps places.
	local function PutDown(bag, slot)
		local held = state.held
		state.held, state.cursor = nil, nil
		local from, to = Mock.Container(state, held.bag), Mock.Container(state, bag)
		local source = from and from.items[held.slot]
		if not source or not to or (held.bag == bag and held.slot == slot) then
			return
		end
		local target = to.items[slot]
		local sourceCount = source.count or 1
		if not target then
			if held.count >= sourceCount then
				to.items[slot], from.items[held.slot] = source, nil
			else
				to.items[slot] = { id = source.id, count = held.count, bound = source.bound }
				source.count = sourceCount - held.count
			end
		elseif target.id == source.id and target.bound == source.bound then
			local most = Mock.Extra(source.id).maxStack or 20
			local moving = math.min(most - (target.count or 1), held.count)
			target.count = (target.count or 1) + moving
			source.count = sourceCount - moving
			if source.count <= 0 then
				from.items[held.slot] = nil
			end
		elseif held.count >= sourceCount then
			to.items[slot], from.items[held.slot] = source, target
		end
		state.moves[#state.moves + 1] = { from = held.bag .. "/" .. held.slot, to = bag .. "/" .. slot, count = held.count }
	end

	env.C_Container.PickupContainerItem = function(bag, slot)
		if state.held then
			PutDown(bag, slot)
			return
		end
		local c = Mock.Container(state, bag)
		local item = c and c.items[slot]
		if item then
			state.held = { bag = bag, slot = slot, count = item.count or 1, id = item.id }
			state.cursor = item.id
		end
	end
	env.C_Container.SplitContainerItem = function(bag, slot, count)
		local c = Mock.Container(state, bag)
		local item = c and c.items[slot]
		if item and not state.held and count > 0 and count < (item.count or 1) then
			state.held = { bag = bag, slot = slot, count = count, id = item.id }
			state.cursor = item.id
		end
	end
	if classic then
		-- The Classic bank: no C_Bank. state.bankBagSlots bank bag slots are
		-- bought (a bank bag in one is state.containers[4 + slot]); buying the
		-- next takes gold and fires PLAYERBANKBAGSLOTS_CHANGED.
		env.CloseBankFrame = function()
			state.closedBank = state.closedBank + 1
		end
		env.GetNumBankSlots = function()
			local bought = state.bankBagSlots or 0
			return bought, bought >= 7
		end
		env.GetBankSlotCost = function(bought)
			return Mock.BANK_SLOT_COSTS[(bought or 0) + 1] or 0
		end
		env.PurchaseSlot = function()
			local bought = state.bankBagSlots or 0
			local cost = env.GetBankSlotCost(bought)
			if not state.atBank or bought >= 7 or state.money < cost then
				return
			end
			state.bankBagSlots = bought + 1
			state.money = state.money - cost
			Mock.Fire(state, "PLAYERBANKBAGSLOTS_CHANGED")
			Mock.Fire(state, "PLAYER_MONEY")
		end
		env.BankButtonIDToInvSlotID = function(id, isBag)
			return isBag and (67 + id) or (BANK_INVENTORY + id)
		end
		env.KeyRingButtonIDToInvSlotID = function(id)
			return KEYRING_INVENTORY + id
		end
		-- The keyring: state.containers[-2], as big as it is.
		env.GetKeyRingSize = function()
			local c = state.containers[-2]
			return c and c.size or 0
		end
		env.IsKeyRingEnabled = function()
			return state.keyringEnabled ~= false
		end
	else
		env.C_Bank = {
			FetchPurchasedBankTabData = function()
				local tabs = {}
				for i = 1, options.bankTabs or 9 do
					local bag = 5 + i
					local c = state.containers[bag]
					if c and c.size > 0 then
						tabs[#tabs + 1] = { ID = bag, name = c.name or ("Tab " .. i), icon = 133000 + i }
					end
				end
				return tabs
			end,
			CloseBankFrame = function()
				state.closedBank = state.closedBank + 1
			end,
			-- The next tab: Forever's first one is free.
			CanPurchaseBankTab = function()
				return state.nextBankTab ~= false
			end,
			FetchNextPurchasableBankTabData = function()
				if state.nextBankTab == false then
					return nil
				end
				return state.nextBankTab or { tabCost = 0, canAfford = true, purchasePromptTitle = "Unlock Bank Tab", purchasePromptBody = "Your first bank tab is free." }
			end,
			-- Bought tabs: the bank tabs with slots (known before their contents).
			FetchNumPurchasedBankTabs = function()
				local count = 0
				for i = 1, options.bankTabs or 9 do
					local c = state.containers[5 + i]
					if c and c.size > 0 then
						count = count + 1
					end
				end
				return count
			end,
		}
	end
	env.C_PlayerInteractionManager = {
		IsInteractingWithNpcOfType = function(kind)
			return state.interaction[kind] or false
		end,
	}

	-- Items
	local function ItemID(item)
		if type(item) == "number" then
			return item
		end
		return tonumber(tostring(item):match("item:(%d+)"))
	end
	env.C_Item = {
		GetItemInfoInstant = function(item)
			local id = ItemID(item)
			local data = id and Mock.ITEMS[id]
			if not data then
				return nil
			end
			return id, "Type", "SubType", data[7] or "", data[6], data[3], data[4]
		end,
		GetItemInfo = function(item)
			local id = ItemID(item)
			local data = id and Mock.ITEMS[id]
			if not data or state.unloaded[id] then
				return nil
			end
			local extra = Mock.Extra(id)
			return data[1], Mock.Link(id), data[2], extra.level or 10, 1, "Type", "SubType", extra.maxStack or 20,
				data[7] or "", data[6], data[5], data[3], data[4], extra.bind or 0
		end,
		GetItemFamily = function(item)
			local id = ItemID(item)
			return id and Mock.Extra(id).family or 0
		end,
		GetDetailedItemLevelInfo = function(item)
			local id = ItemID(item)
			return id and Mock.ITEMS[id] and (Mock.Extra(id).level or 10)
		end,
		GetItemSpell = function(item)
			local id = ItemID(item)
			if id and Mock.Extra(id).spell then
				return "Use", 1000 + id
			end
		end,
		IsUsableItem = function(item)
			local id = ItemID(item)
			return not (id and Mock.Extra(id).unusable), false
		end,
		RequestLoadItemDataByID = function(id)
			state.requested[id] = true
		end,
		GetItemQualityColor = function(quality)
			local c = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
			return c[1], c[2], c[3], c[4]
		end,
		GetItemClassInfo = function(classID)
			return "Class" .. classID
		end,
	}
	env.C_Texture = {
		GetAtlasInfo = function()
			return {}
		end,
	}

	-- Tooltip data. What stops the test character using an item is red: for
	-- armor the armor type on the right ("Plate"), for anything else a
	-- "Requires" line. A bag slot's tooltip shows the charges left, in the
	-- form the game keeps the text before drawing it (a color code, and
	-- |4Charge:Charges; for the word); a link's leaves them out.
	local WHITE, RED = { r = 1, g = 1, b = 1 }, { r = 1, g = 0.125, b = 0.125 }
	local function TooltipData(id, item)
		local data = id and Mock.ITEMS[id]
		if not data then
			return nil
		end
		local extra = Mock.Extra(id)
		local q = QUALITY_COLORS[data[2]] or QUALITY_COLORS[1]
		local lines = { { leftText = data[1], leftColor = { r = q[1], g = q[2], b = q[3] } } }
		if extra.charges and item then
			local left = item.charges or extra.charges
			local text = left == 0 and "No charges" or ("|cffffffff" .. left .. " |4Charge:Charges;|r")
			lines[#lines + 1] = { leftText = text, leftColor = WHITE }
		end
		if extra.unusable and data[3] == 4 then
			lines[#lines + 1] = { leftText = "Head", leftColor = WHITE, rightText = "Plate", rightColor = RED }
		elseif extra.unusable then
			lines[#lines + 1] = { leftText = "Requires Level 70", leftColor = RED }
		end
		if extra.harmlessRed then
			lines[#lines + 1] = { leftText = "Durability 0 / 45", leftColor = RED }
			lines[#lines + 1] = { leftText = "Cannot be disenchanted", leftColor = RED }
		end
		return { type = 0, id = id, lines = lines }
	end
	-- Classic clients have no tooltip data: their tooltips draw these lines.
	state.TooltipData = TooltipData
	if not classic then
		env.C_TooltipInfo = {
			GetHyperlink = function(link)
				state.tooltipReads = (state.tooltipReads or 0) + 1
				return TooltipData(ItemID(link))
			end,
			GetBagItem = function(bag, slot)
				state.tooltipReads = (state.tooltipReads or 0) + 1
				local c = Mock.Container(state, bag)
				local item = c and c.items[slot]
				return item and TooltipData(item.id, item)
			end,
			GetInboxItem = function(index, attachment)
				local mail = state.mailbox[index]
				local item = mail and mail.items and mail.items[attachment]
				return item and TooltipData(item.id, item)
			end,
			GetSendMailItem = function(attachment)
				local item = state.sendMail.items[attachment]
				return item and TooltipData(item.id, item)
			end,
		}
	end

	-- The mailbox: state.mailbox = { { sender, subject, money, cod, daysLeft,
	-- returned, canDelete, items = { [attachment] = { id, count, charges } } } },
	-- of which the first 50 are shown. The mail being written: state.sendMail.
	env.ATTACHMENTS_MAX_RECEIVE, env.ATTACHMENTS_MAX_SEND = 16, 12
	env.GetInboxNumItems = function()
		return math.min(50, #state.mailbox), #state.mailbox
	end
	env.GetInboxHeaderInfo = function(index)
		local m = state.mailbox[index]
		if m then
			local count = 0
			for _ in pairs(m.items or {}) do
				count = count + 1
			end
			return 133000, nil, m.sender, m.subject, m.money or 0, m.cod or 0, m.daysLeft or 30, count > 0 and count or nil,
				false, m.returned or false, false, true, false
		end
	end
	env.GetInboxItem = function(index, attachment)
		local m = state.mailbox[index]
		local item = m and m.items and m.items[attachment]
		if item then
			local data = Mock.ITEMS[item.id]
			return data[1], item.id, data[6], item.count or 1, data[2], true
		end
	end
	env.GetInboxItemLink = function(index, attachment)
		local m = state.mailbox[index]
		local item = m and m.items and m.items[attachment]
		return item and Mock.Link(item.id, item.crafter)
	end
	env.InboxItemCanDelete = function(index)
		local m = state.mailbox[index]
		return m and (m.canDelete or m.returned) or false
	end
	env.ReturnInboxItem = function(index)
		state.returnedMail[#state.returnedMail + 1] = index
	end
	env.GetSendMailItem = function(attachment)
		local item = state.sendMail.items[attachment]
		if item then
			local data = Mock.ITEMS[item.id]
			return data[1], item.id, data[6], item.count or 1, data[2]
		end
	end
	env.GetSendMailItemLink = function(attachment)
		local item = state.sendMail.items[attachment]
		return item and Mock.Link(item.id, item.crafter)
	end
	env.GetSendMailMoney = function()
		return state.sendMail.money or 0
	end
	env.GetSendMailCOD = function()
		return state.sendMail.cod or 0
	end
	env.SendMail = function(recipient, subject)
		local count = 0
		for _ in pairs(state.sendMail.items) do
			count = count + 1
		end
		state.sentMail[#state.sentMail + 1] = { recipient = recipient, subject = subject, items = count }
	end
	-- The item on the cursor goes onto the mail being written, unless the game
	-- will not mail it (soulbound): then it stays on the cursor.
	env.ClickSendMailItemButton = function(index)
		local held = state.held
		local c = held and Mock.Container(state, held.bag)
		local item = c and c.items[held.slot]
		if item and not item.bound and not state.sendMail.items[index] then
			state.sendMail.items[index] = { id = item.id, count = item.count, bag = held.bag, slot = held.slot, charges = item.charges }
			item.locked = true
			state.held, state.cursor = nil, nil
		end
	end

	-- Bags worn in the bag slots, with the bag's item in
	-- state.containers[bag].bagItem. Their inventory slots: 30 + bag on the
	-- Retail engine; on Classic 19 + bag for the four bag slots and 63 + bag
	-- for the bank bag slots (68 to 74), which only answer at the bank.
	env.C_Container.ContainerIDToInventoryID = function(bag)
		if classic then
			if bag >= 1 and bag <= 4 then
				return 19 + bag
			elseif bag >= 5 and bag <= 11 then
				return 63 + bag
			end
		elseif bag >= 1 and bag <= 5 then
			return 30 + bag
		end
		error("not a bag slot: " .. tostring(bag))
	end
	-- What an inventory slot holds: a worn bag's item ID, or on Classic also a
	-- bank or keyring slot's item ID and the item.
	function state.InventoryItem(slot)
		if not classic then
			local c = state.containers[slot - 30]
			return c and c.bagItem
		end
		if slot >= 20 and slot <= 23 then
			local c = state.containers[slot - 19]
			return c and c.bagItem
		elseif slot >= 68 and slot <= 74 then
			local c = state.atBank and state.containers[slot - 63]
			return c and c.bagItem
		elseif slot > BANK_INVENTORY and slot <= BANK_INVENTORY + 28 then
			local c = Mock.Container(state, -1)
			local item = c and c.items[slot - BANK_INVENTORY]
			return item and item.id, item
		elseif slot > KEYRING_INVENTORY and slot <= KEYRING_INVENTORY + 32 then
			local c = state.containers[-2]
			local item = c and c.items[slot - KEYRING_INVENTORY]
			return item and item.id, item
		end
		return nil
	end
	env.GetInventoryItemLink = function(_, slot)
		local id = state.InventoryItem(slot)
		return id and Mock.Link(id)
	end
	env.GetInventoryItemTexture = function(_, slot)
		local id = state.InventoryItem(slot)
		return id and Mock.ITEMS[id][6]
	end
	env.PickupBagFromSlot = function(slot)
		state.bagMoves[#state.bagMoves + 1] = "pickup " .. slot
		state.cursor = (state.InventoryItem(slot))
	end
	env.PutItemInBag = function(slot)
		state.bagMoves[#state.bagMoves + 1] = "put " .. slot
		state.cursor = nil
	end
	env.PutItemInBackpack = function()
		state.bagMoves[#state.bagMoves + 1] = "put backpack"
		state.cursor = nil
	end

	-- Guild vault: state.guild = { name, money, tabs = { { name, icon, viewable, items = { [slot] = { id, count } } } } }
	env.GetNumGuildBankTabs = function()
		return state.guild and #state.guild.tabs or 0
	end
	env.GetGuildBankTabInfo = function(tab)
		local t = state.guild and state.guild.tabs[tab]
		if t then
			return t.name, t.icon or 133000, t.viewable ~= false, true, 0, 0, false
		end
	end
	env.QueryGuildBankTab = function(tab)
		state.guildQueries[#state.guildQueries + 1] = tab
	end
	env.GetGuildBankItemLink = function(tab, slot)
		local t = state.guild and state.guildLoaded[tab] and state.guild.tabs[tab]
		local item = t and t.items[slot]
		return item and Mock.Link(item.id)
	end
	env.GetGuildBankItemInfo = function(tab, slot)
		local t = state.guild and state.guildLoaded[tab] and state.guild.tabs[tab]
		local item = t and t.items[slot]
		if item then
			local data = Mock.ITEMS[item.id]
			return data[6], item.count or 1, false, false, data[2]
		end
	end
	env.GetGuildBankMoney = function()
		return state.guild and state.guild.money or 0
	end
	env.GetCurrentGuildBankTab = function()
		return state.guildCurrent or 1
	end

	-- Cursor and clicks
	env.GetCursorInfo = function()
		if state.cursor then
			return "item", state.cursor
		end
	end
	env.ClearCursor = function()
		state.cursor = nil
		state.held = nil -- a held item goes back where it came from
	end
	env.IsModifiedClick = function()
		return state.modified or false
	end
	env.IsShiftKeyDown = function()
		return state.shift or false
	end
	env.HandleModifiedItemClick = function(link)
		state.linked = link
		return true
	end

	-- Menus, tooltips, settings, addons
	env.MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local root = NewDescription("root")
			root.owner = owner
			generator(owner, root)
			state.menus[#state.menus + 1] = root
			return root
		end,
	}
	env.TooltipDataProcessor = {
		AddTooltipPostCall = function(_, func)
			state.tooltipCalls[#state.tooltipCalls + 1] = func
		end,
	}
	env.Settings = {
		RegisterCanvasLayoutCategory = function(panel, name)
			return { panel = panel, name = name }
		end,
		RegisterAddOnCategory = function() end,
	}
	env.C_AddOns = {
		IsAddOnLoaded = function(name)
			return state.loadedAddons[name] or false
		end,
		GetAddOnMetadata = function(_, field)
			if field == "Version" then
				return "1.0.0"
			end
		end,
	}
	env.SOUNDKIT = {}
	env.PlaySound = function() end

	return env, state
end

--------------------------------------------------------------------------------
-- Driving the client
--------------------------------------------------------------------------------

-- Loads every file of the addon's .toc into env, the way the client does:
-- each chunk gets (addonName, namespace).
function Mock.LoadAddon(env, state, dir, name)
	local ns = {}
	local toc = assert(io.open(dir .. "/" .. name .. ".toc", "r"))
	for line in toc:lines() do
		line = line:gsub("%s+$", "")
		if line ~= "" and not line:match("^#") then
			local path = dir .. "/" .. line:gsub("\\", "/")
			local chunk = assert(loadfile(path))
			setfenv(chunk, env)
			local ok, err = pcall(chunk, name, ns)
			if not ok then
				state.errors[#state.errors + 1] = path .. ": " .. tostring(err)
			end
		end
	end
	toc:close()
	return ns
end

function Mock.Fire(state, event, ...)
	for _, frame in ipairs(state.frames) do
		if frame.__events[event] then
			CallScript(frame, "OnEvent", event, ...)
		end
	end
end

-- Moves the clock forward, running timers that come due.
function Mock.Advance(state, seconds)
	local stop = state.time + seconds
	while true do
		local nextTimer, index
		for i, timer in ipairs(state.timers) do
			if timer.at <= stop and (not nextTimer or timer.at < nextTimer.at) then
				nextTimer, index = timer, i
			end
		end
		if not nextTimer then
			break
		end
		table.remove(state.timers, index)
		state.time = math.max(state.time, nextTimer.at)
		state.CallProtected(nextTimer.func)
	end
	state.time = stop
end

-- The server takes the mail that was sent: its items leave the bags, the
-- mail being written is cleared, and MAIL_SEND_SUCCESS fires.
function Mock.DeliverMail(state)
	for _, item in pairs(state.sendMail.items) do
		local c = state.containers[item.bag]
		if c then
			c.items[item.slot] = nil
		end
	end
	state.sendMail.items = {}
	Mock.Fire(state, "MAIL_SEND_SUCCESS")
end

-- The mouse enters a frame, as far as scripts are concerned.
function Mock.Enter(state, frame)
	state.mouseOver = frame
	CallScript(frame, "OnEnter")
end

function Mock.Leave(state, frame)
	if state.mouseOver == frame then
		state.mouseOver = nil
	end
	CallScript(frame, "OnLeave")
end

function Mock.Click(frame, button)
	CallScript(frame, "OnClick", button or "LeftButton")
end

return Mock
