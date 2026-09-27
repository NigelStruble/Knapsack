local _, ns = ...
local L, C = ns.L, ns.C

-- A small set of flat-styled controls, shared with Missing Buffs. They are built
-- from plain frames and color textures instead of Blizzard templates, so they
-- look the same on every client and next to EllesmereUI's windows.

local W = {}
ns.W = W

local _G = _G
local ipairs, type, tostring, tonumber = ipairs, type, tostring, tonumber
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

local COLORS = {
	window = { 0.06, 0.06, 0.08, 0.97 },
	title = { 0.11, 0.11, 0.14, 1 },
	border = { 0.3, 0.3, 0.35, 1 },
	panel = { 0.09, 0.09, 0.11, 1 },
	control = { 0.16, 0.16, 0.19, 1 },
	hover = { 0.24, 0.24, 0.29, 1 },
	accent = { 0.05, 0.82, 0.62, 1 }, -- EllesmereUI's default accent; see W.SetAccent
	selected = { 0.22, 0.38, 0.62, 0.7 },
	disabled = { 0.45, 0.45, 0.45, 1 },
}
W.COLORS = COLORS

local function Paint(texture, color)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end
W.Paint = Paint

function W.Background(frame, color, layer)
	local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetAllPoints()
	Paint(texture, color)
	return texture
end

function W.Border(frame, color)
	color = color or COLORS.border
	local edges = {}
	for i = 1, 4 do
		edges[i] = frame:CreateTexture(nil, "BORDER")
		Paint(edges[i], color)
	end
	edges[1]:SetPoint("TOPLEFT")
	edges[1]:SetPoint("TOPRIGHT")
	edges[1]:SetHeight(1)
	edges[2]:SetPoint("BOTTOMLEFT")
	edges[2]:SetPoint("BOTTOMRIGHT")
	edges[2]:SetHeight(1)
	edges[3]:SetPoint("TOPLEFT")
	edges[3]:SetPoint("BOTTOMLEFT")
	edges[3]:SetWidth(1)
	edges[4]:SetPoint("TOPRIGHT")
	edges[4]:SetPoint("BOTTOMRIGHT")
	edges[4]:SetWidth(1)
	return edges
end

local function ClickSound()
	C.PlaySound("U_CHAT_SCROLL_BUTTON", 1115)
end

local function CheckSound(checked)
	if checked then
		C.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
	else
		C.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
	end
end

--------------------------------------------------------------------------------
-- Refreshing: every control with a Refresh method is tracked, so the whole
-- window can be brought up to date after a profile change.
--------------------------------------------------------------------------------

local tracked = {}

function W.Track(widget)
	tracked[#tracked + 1] = widget
	return widget
end

function W.RefreshAll()
	for _, widget in ipairs(tracked) do
		widget:Refresh()
	end
end

--------------------------------------------------------------------------------
-- Tooltips
--------------------------------------------------------------------------------

function W.SetTooltip(frame, title, text)
	frame.tipTitle, frame.tipText = title, text
end

function W.ShowTooltip(frame)
	if not frame.tipTitle and not frame.tipText then
		return
	end
	GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
	GameTooltip:SetText(frame.tipTitle or "", 1, 1, 1)
	if frame.tipText then
		GameTooltip:AddLine(frame.tipText, 1, 0.82, 0, true)
	end
	GameTooltip:Show()
end

function W.HideTooltip(frame)
	if GameTooltip:IsOwned(frame) then
		GameTooltip:Hide()
	end
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

function W.Header(parent, text, width)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width or 340, 20)
	frame.text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.text:SetPoint("LEFT")
	frame.text:SetText(text)
	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetPoint("LEFT", frame.text, "RIGHT", 8, 0)
	line:SetPoint("RIGHT")
	line:SetHeight(1)
	line:SetColorTexture(1, 0.82, 0, 0.25)
	return frame
end

function W.Note(parent, text, width)
	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetWidth(width or 340)
	note:SetJustifyH("LEFT")
	note:SetTextColor(0.7, 0.7, 0.72)
	note:SetText(text)
	return note
end

--------------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------------

local function Button_OnEnter(self)
	Paint(self.bg, COLORS.hover)
	W.ShowTooltip(self)
end

local function Button_OnLeave(self)
	Paint(self.bg, self.selected and COLORS.selected or COLORS.control)
	W.HideTooltip(self)
end

function W.Button(parent, text, width, height, onClick, tooltip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width or 100, height or 22)
	button.bg = W.Background(button, COLORS.control)
	W.Border(button)
	button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 4, 0)
	button.text:SetPoint("RIGHT", -4, 0)
	button.text:SetText(text)
	button:SetScript("OnEnter", Button_OnEnter)
	button:SetScript("OnLeave", Button_OnLeave)
	button:SetScript("OnClick", function(self, mouseButton)
		ClickSound()
		if onClick then
			onClick(self, mouseButton)
		end
	end)
	button:SetScript("OnDisable", function(self)
		self.text:SetTextColor(COLORS.disabled[1], COLORS.disabled[2], COLORS.disabled[3])
	end)
	button:SetScript("OnEnable", function(self)
		self.text:SetTextColor(1, 1, 1)
	end)
	if tooltip then
		W.SetTooltip(button, text, tooltip)
	end
	function button:SetSelected(selected)
		self.selected = selected
		Paint(self.bg, selected and COLORS.selected or COLORS.control)
	end
	function button:SetActive(active)
		self:SetEnabled(active and true or false)
	end
	return button
end

--------------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------------

function W.Checkbox(parent, text, get, set, tooltip)
	local check = CreateFrame("Button", nil, parent)
	check:SetHeight(20)

	local box = CreateFrame("Frame", nil, check)
	box:SetSize(16, 16)
	box:SetPoint("LEFT")
	box.bg = W.Background(box, COLORS.control)
	W.Border(box)
	check.box = box

	check.mark = box:CreateTexture(nil, "ARTWORK")
	check.mark:SetPoint("TOPLEFT", 4, -4)
	check.mark:SetPoint("BOTTOMRIGHT", -4, 4)
	Paint(check.mark, COLORS.accent)

	check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	check.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
	check.label:SetJustifyH("LEFT")
	check.label:SetText(text)
	check:SetWidth(24 + max(20, check.label:GetStringWidth()))
	check.labelColor = { 1, 1, 1 }

	check.get, check.set = get, set
	if tooltip then
		W.SetTooltip(check, text, tooltip)
	end

	function check:Refresh()
		self.mark:SetShown(self.get() and true or false)
	end

	function check:SetLabelColor(r, g, b)
		self.labelColor[1], self.labelColor[2], self.labelColor[3] = r, g, b
		if self:IsEnabled() then
			self.label:SetTextColor(r, g, b)
		end
	end

	function check:SetActive(active)
		self:SetEnabled(active and true or false)
		if active then
			self.label:SetTextColor(self.labelColor[1], self.labelColor[2], self.labelColor[3])
			self.mark:SetAlpha(1)
		else
			self.label:SetTextColor(COLORS.disabled[1], COLORS.disabled[2], COLORS.disabled[3])
			self.mark:SetAlpha(0.4)
		end
	end

	check:SetScript("OnClick", function(self)
		local value = not self.get()
		CheckSound(value)
		self.set(value)
		self:Refresh()
	end)
	check:SetScript("OnEnter", function(self)
		Paint(self.box.bg, COLORS.hover)
		W.ShowTooltip(self)
	end)
	check:SetScript("OnLeave", function(self)
		Paint(self.box.bg, COLORS.control)
		W.HideTooltip(self)
	end)

	W.Track(check)
	check:Refresh()
	return check
end

--------------------------------------------------------------------------------
-- Slider with a box for typing the value
--------------------------------------------------------------------------------

local function RoundTo(value, step)
	if step >= 1 then
		return floor(value / step + 0.5) * step
	end
	return floor(value * 100 + 0.5) / 100
end

function W.Slider(parent, text, minValue, maxValue, step, get, set, opts)
	opts = opts or {}
	local width = opts.width or 240
	local formatValue = opts.format or tostring
	local parseValue = opts.parse or tonumber

	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 40)
	holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	holder.label:SetPoint("TOPLEFT")
	holder.label:SetText(text)
	if opts.tooltip then
		W.SetTooltip(holder, text, opts.tooltip)
		holder:SetScript("OnEnter", W.ShowTooltip)
		holder:SetScript("OnLeave", W.HideTooltip)
	end

	local slider = CreateFrame("Slider", nil, holder)
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("TOPLEFT", 0, -18)
	slider:SetSize(width - 60, 16)
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	if slider.SetObeyStepOnDrag then
		slider:SetObeyStepOnDrag(true)
	end
	slider:EnableMouse(true)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	Paint(track, COLORS.control)
	local thumb = slider:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(10, 16)
	Paint(thumb, COLORS.accent)
	slider:SetThumbTexture(thumb)
	holder.slider = slider

	local box = CreateFrame("EditBox", nil, holder)
	box:SetPoint("LEFT", slider, "RIGHT", 8, 0)
	box:SetSize(52, 18)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	box:SetJustifyH("CENTER")
	W.Background(box, COLORS.control)
	W.Border(box)
	holder.box = box

	function holder:Refresh()
		local value = get() or minValue
		self.updating = true
		slider:SetValue(value)
		self.updating = false
		box:SetText(formatValue(value))
	end

	function holder:SetActive(active)
		slider:EnableMouse(active and true or false)
		box:EnableMouse(active and true or false)
		self:SetAlpha(active and 1 or 0.45)
	end

	slider:SetScript("OnValueChanged", function(_, value)
		value = RoundTo(value, step)
		box:SetText(formatValue(value))
		if not holder.updating then
			set(value)
		end
	end)
	box:SetScript("OnEnterPressed", function(self)
		local value = parseValue(self:GetText())
		if value then
			set(RoundTo(min(maxValue, max(minValue, value)), step))
		end
		holder:Refresh()
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self)
		holder:Refresh()
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", function()
		holder:Refresh()
	end)

	W.Track(holder)
	holder:Refresh()
	return holder
end

--------------------------------------------------------------------------------
-- Dropdown with a shared pop-up list
--------------------------------------------------------------------------------

local MENU_ROWS = 16
local MENU_ROW_HEIGHT = 18
local menu

local function MenuButton_OnClick(self)
	local owner, item = menu.owner, self.item
	menu:Hide()
	if owner and item then
		ClickSound()
		owner.set(item.value)
		owner:Refresh()
	end
end

local function MenuButton_OnEnter(self)
	local item = self.item
	if item and item.tooltip then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(item.text, 1, 1, 1)
		GameTooltip:AddLine(item.tooltip, 1, 0.82, 0, true)
		GameTooltip:Show()
	end
end

local function MenuButton_OnLeave(self)
	W.HideTooltip(self)
end

local function CreateMenuButton(index)
	local button = CreateFrame("Button", nil, menu)
	button:SetHeight(MENU_ROW_HEIGHT)
	button:SetPoint("TOPLEFT", 4, -4 - (index - 1) * MENU_ROW_HEIGHT)
	button:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
	-- The highlight layer is drawn over the text, so it only tints.
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.12)
	button.highlight = highlight
	button.check = button:CreateTexture(nil, "ARTWORK")
	button.check:SetSize(6, 6)
	button.check:SetPoint("LEFT", 5, 0)
	Paint(button.check, COLORS.accent)
	button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 16, 0)
	button.text:SetPoint("RIGHT", -4, 0)
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	button:SetScript("OnClick", MenuButton_OnClick)
	button:SetScript("OnEnter", MenuButton_OnEnter)
	button:SetScript("OnLeave", MenuButton_OnLeave)
	menu.buttons[index] = button
	return button
end

local function RenderMenu()
	local items = menu.items
	local rows = min(#items, MENU_ROWS)
	local current = menu.owner.get()
	for i = 1, rows do
		local button = menu.buttons[i] or CreateMenuButton(i)
		local item = items[i + menu.offset]
		button.item = item
		button.text:SetText(item.text)
		if item.color then
			button.text:SetTextColor(item.color[1], item.color[2], item.color[3])
		else
			button.text:SetTextColor(1, 1, 1)
		end
		button.check:SetShown(item.value == current)
		button:Show()
	end
	for i = rows + 1, #menu.buttons do
		menu.buttons[i]:Hide()
	end
	local more = #items > MENU_ROWS
	menu.more:SetShown(more)
	menu:SetHeight(rows * MENU_ROW_HEIGHT + 8 + (more and 14 or 0))
end

local function CreateMenu()
	menu = CreateFrame("Frame", "KnapsackDropDownMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:EnableMouseWheel(true)
	menu:Hide()
	W.Background(menu, COLORS.panel)
	W.Border(menu, COLORS.accent)
	menu.buttons = {}
	menu.offset = 0

	menu.more = menu:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	menu.more:SetPoint("BOTTOMRIGHT", -8, 4)
	menu.more:SetTextColor(0.6, 0.6, 0.6)
	menu.more:SetText(L["(scroll for more)"])

	-- A click anywhere else closes the list.
	local catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN")
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", function()
		menu:Hide()
	end)
	catcher:Hide()
	menu.catcher = catcher

	menu:SetScript("OnHide", function(self)
		self.catcher:Hide()
		self.owner = nil
	end)
	menu:SetScript("OnMouseWheel", function(self, delta)
		self.offset = min(max(0, #self.items - MENU_ROWS), max(0, self.offset - delta))
		RenderMenu()
	end)
end

function W.ToggleMenu(dropdown)
	if not menu then
		CreateMenu()
	end
	if menu:IsShown() and menu.owner == dropdown then
		menu:Hide()
		return
	end
	menu:Hide()
	local items = dropdown:GetItems()
	if #items == 0 then
		return
	end
	menu.owner = dropdown
	menu.items = items
	menu.offset = 0
	local current = dropdown.get()
	for i, item in ipairs(items) do
		if item.value == current and i > MENU_ROWS then
			menu.offset = min(i - MENU_ROWS, #items - MENU_ROWS)
			break
		end
	end
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", dropdown.button, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(max(dropdown.button:GetWidth(), 160))
	RenderMenu()
	menu.catcher:Show()
	menu:Show()
	menu:Raise()
end

function W.CloseMenu()
	if menu then
		menu:Hide()
	end
end

-- items: list of { value = ..., text = ..., color = {r, g, b}, tooltip = ... },
-- or a function returning such a list.
function W.Dropdown(parent, text, width, items, get, set, opts)
	opts = opts or {}
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, text and 40 or 22)
	if text then
		holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		holder.label:SetPoint("TOPLEFT")
		holder.label:SetText(text)
	end

	local button = CreateFrame("Button", nil, holder)
	button:SetPoint("BOTTOMLEFT")
	button:SetSize(width, 22)
	button.bg = W.Background(button, COLORS.control)
	W.Border(button)
	button.text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	button.text:SetPoint("LEFT", 6, 0)
	button.text:SetPoint("RIGHT", -20, 0)
	button.text:SetJustifyH("LEFT")
	button.text:SetWordWrap(false)
	button.arrow = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	button.arrow:SetPoint("RIGHT", -7, 0)
	button.arrow:SetText("v")
	button:SetScript("OnClick", function()
		ClickSound()
		W.ToggleMenu(holder)
	end)
	button:SetScript("OnEnter", function(self)
		Paint(self.bg, COLORS.hover)
		W.ShowTooltip(holder)
	end)
	button:SetScript("OnLeave", function(self)
		Paint(self.bg, COLORS.control)
		W.HideTooltip(holder)
	end)
	holder.button = button
	holder.items = items
	holder.get, holder.set = get, set
	if opts.tooltip then
		W.SetTooltip(holder, text, opts.tooltip)
	end

	function holder:GetItems()
		local list = self.items
		if type(list) == "function" then
			list = list()
		end
		return list or {}
	end

	function holder:Refresh()
		local value = self.get()
		local label = opts.placeholder or ""
		for _, item in ipairs(self:GetItems()) do
			if item.value == value then
				label = item.text
				break
			end
		end
		self.button.text:SetText(label)
	end

	function holder:SetActive(active)
		button:EnableMouse(active and true or false)
		self:SetAlpha(active and 1 or 0.45)
	end

	W.Track(holder)
	holder:Refresh()
	return holder
end

--------------------------------------------------------------------------------
-- Edit box
--------------------------------------------------------------------------------

-- opts.enterOnly: only commit on Enter (for actions such as "create").
function W.EditBox(parent, text, width, get, set, opts)
	opts = opts or {}
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, text and 40 or 22)
	if text then
		holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		holder.label:SetPoint("TOPLEFT")
		holder.label:SetText(text)
	end
	if opts.tooltip then
		W.SetTooltip(holder, text, opts.tooltip)
	end

	local box = CreateFrame("EditBox", nil, holder)
	box:SetPoint("BOTTOMLEFT")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	box:SetTextInsets(6, 6, 0, 0)
	if opts.maxLetters then
		box:SetMaxLetters(opts.maxLetters)
	end
	box.bg = W.Background(box, COLORS.control)
	W.Border(box)
	holder.box = box

	function holder:Refresh()
		if get then
			box:SetText(get() or "")
			box:SetCursorPosition(0)
		end
	end

	function holder:SetActive(active)
		box:EnableMouse(active and true or false)
		if not active then
			box:ClearFocus()
		end
		self:SetAlpha(active and 1 or 0.45)
	end

	local function Commit(self)
		if set then
			set(self:GetText())
		end
	end

	box:SetScript("OnEnterPressed", function(self)
		Commit(self)
		self:ClearFocus()
		holder:Refresh()
	end)
	box:SetScript("OnEscapePressed", function(self)
		holder:Refresh()
		self:ClearFocus()
	end)
	if not opts.enterOnly then
		box:SetScript("OnEditFocusLost", function(self)
			Commit(self)
		end)
	end
	box:SetScript("OnEnter", function()
		W.ShowTooltip(holder)
	end)
	box:SetScript("OnLeave", function()
		W.HideTooltip(holder)
	end)

	if get then
		W.Track(holder)
		holder:Refresh()
	end
	return holder
end

--------------------------------------------------------------------------------
-- Scroll frame with a thin scroll bar
--------------------------------------------------------------------------------

function W.ScrollFrame(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(10, 10)
	scroll:SetScrollChild(content)
	scroll.content = content

	local bar = CreateFrame("Slider", nil, scroll)
	bar:SetOrientation("VERTICAL")
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)
	bar:SetWidth(8)
	W.Background(bar, COLORS.panel)
	local thumb = bar:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(8, 40)
	Paint(thumb, COLORS.border)
	bar:SetThumbTexture(thumb)
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	bar:SetValue(0)
	bar:Hide()
	bar:SetScript("OnValueChanged", function(_, value)
		scroll:SetVerticalScroll(value)
	end)
	scroll.bar = bar

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		bar:SetValue(bar:GetValue() - delta * 40)
	end)

	-- visible: the height the scroll frame is about to have, when whoever
	-- sized it knows it; right after a resize its own height can still be the
	-- old one. Less than a pixel over is the game rounding frame sizes, not
	-- something to scroll.
	function scroll:UpdateRange(visible)
		local range = content:GetHeight() - (visible or self:GetHeight())
		if range < 1 then
			range = 0
		end
		bar:SetMinMaxValues(0, range)
		bar:SetShown(range > 0)
		if bar:GetValue() > range then
			bar:SetValue(range)
		end
	end

	function scroll:SetContentHeight(height, visible)
		content:SetHeight(max(1, height))
		self:UpdateRange(visible)
	end

	scroll:SetScript("OnSizeChanged", function(self, width)
		content:SetWidth(max(1, width - 12))
		self:UpdateRange()
	end)

	return scroll, content
end

--------------------------------------------------------------------------------
-- Window and tabs
--------------------------------------------------------------------------------

function W.Window(name, title, width, height)
	local frame = CreateFrame("Frame", name, UIParent)
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	W.Background(frame, COLORS.window)
	W.Border(frame)

	local bar = frame:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(28)
	Paint(bar, COLORS.title)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", 12, -7)
	frame.title:SetText(title)

	frame.close = W.Button(frame, "X", 24, 20, function()
		frame:Hide()
	end)
	frame.close:SetPoint("TOPRIGHT", -5, -5)

	-- Escape closes the window.
	_G.tinsert(_G.UISpecialFrames, name)
	frame:Hide()
	return frame
end

function W.Tabs(window, labels, onSelect)
	local tabs = { onSelect = onSelect }
	local x = 10
	for i, label in ipairs(labels) do
		local tab = W.Button(window, label, 118, 24, function()
			W.SelectTab(tabs, i)
		end)
		tab:SetPoint("TOPLEFT", x, -36)
		x = x + 122
		tabs[i] = tab
	end
	return tabs
end

function W.SelectTab(tabs, index)
	W.CloseMenu()
	for i, tab in ipairs(tabs) do
		tab:SetSelected(i == index)
	end
	tabs.current = index
	tabs.onSelect(index)
end

--------------------------------------------------------------------------------
-- Yes / No question
--------------------------------------------------------------------------------

function W.Confirm(text, onAccept)
	local dialog = W.confirmDialog
	if not dialog then
		dialog = CreateFrame("Frame", "KnapsackConfirmDialog", UIParent)
		dialog:SetSize(340, 120)
		dialog:SetPoint("CENTER", 0, 140)
		dialog:SetFrameStrata("FULLSCREEN_DIALOG")
		dialog:SetToplevel(true)
		dialog:EnableMouse(true)
		W.Background(dialog, COLORS.window)
		W.Border(dialog, COLORS.accent)
		dialog.text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		dialog.text:SetPoint("TOPLEFT", 16, -18)
		dialog.text:SetPoint("TOPRIGHT", -16, -18)
		dialog.text:SetJustifyH("CENTER")
		dialog.yes = W.Button(dialog, L["Yes"], 110, 22, function()
			local accept = dialog.onAccept
			dialog:Hide()
			if accept then
				accept()
			end
		end)
		dialog.yes:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -6, 14)
		dialog.no = W.Button(dialog, L["No"], 110, 22, function()
			dialog:Hide()
		end)
		dialog.no:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 6, 14)
		_G.tinsert(_G.UISpecialFrames, "KnapsackConfirmDialog")
		W.confirmDialog = dialog
	end
	dialog.text:SetText(text)
	dialog.onAccept = onAccept
	dialog:Show()
	dialog:Raise()
end

--------------------------------------------------------------------------------
-- Accent color and icon buttons
--------------------------------------------------------------------------------

-- With EllesmereUI installed its accent color replaces the default (Skin.lua).
-- Controls built afterwards use it.
function W.SetAccent(r, g, b)
	local accent = COLORS.accent
	accent[1], accent[2], accent[3] = r, g, b
end

-- A square button showing an atlas or a texture, for window headers. isAtlas
-- may be the texture to show instead where the client lacks the atlas.
function W.IconButton(parent, size, icon, isAtlas, onClick, title, text)
	local button = W.Button(parent, "", size, size, onClick)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("CENTER")
	button.icon:SetSize(size - 8, size - 8)
	if isAtlas then
		C.SetIcon(button.icon, icon, type(isAtlas) == "string" and isAtlas or 134400)
	else
		button.icon:SetTexture(icon)
	end
	if title then
		W.SetTooltip(button, title, text)
	end
	return button
end
