local _, ns = ...
local L, C, DB, W = ns.L, ns.C, ns.DB, ns.W
local Categories = ns.Categories

-- The options window: General, Categories and Characters. /satchel options, the
-- cog in the bags window, or the game's AddOns options open it.

local Options = {}
ns.Options = Options

local _G = _G
local ipairs, pairs, format, max = ipairs, pairs, string.format, math.max

local WIDTH, HEIGHT = 660, 670
local ROW_HEIGHT = 22
local window, tabs
local pages = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Get(key)
	return function()
		return DB.settings[key]
	end
end

local function Set(key)
	return function(value)
		DB.Set(key, value)
		ns.Send("settings")
	end
end

-- Stacks widgets top to bottom. Without a height, text is measured.
local function NewColumn(parent, x, y)
	local column = { parent = parent, x = x, y = y }
	function column:Add(widget, height)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
		widget:Show()
		if not height then
			if widget.GetStringHeight then
				height = max(12, widget:GetStringHeight())
			else
				height = widget:GetHeight()
			end
		end
		self.y = self.y - height - 6
		return widget
	end
	function column:Skip(height)
		self.y = self.y - height
	end
	return column
end

local SORT_ITEMS = {
	{ value = "quality", text = L["Quality, then type and name"] },
	{ value = "name", text = L["Name"] },
	{ value = "type", text = L["Item type, then quality"] },
}

-- What each built-in category holds, for the Categories page.
local DESCRIPTIONS = {
	equipment = L["Weapons and armor, including rings, necklaces, trinkets and off-hands."],
	consumables = L["Food, drink, potions, elixirs, flasks, scrolls and bandages."],
	reagents = L["Spell reagents, such as Sacred Candles, Arcane Powder and Runes of Teleportation."],
	tradegoods = L["Materials for professions: cloth, leather, herbs, ore, gems and enchanting materials."],
	recipes = L["Recipes, patterns, plans, formulas and schematics."],
	quest = L["Quest items, and items that start a quest."],
	ammo = L["Arrows and bullets."],
	containers = L["Bags, quivers and ammo pouches you are carrying."],
	keys = C.KEYRING and L["Keys, including those on the keyring."] or L["Keys."],
	misc = L["Everything no other category takes. It cannot be hidden."],
	junk = L["Every Poor (grey) quality item, sorted by vendor value with the cheapest first, so the first item is always the one to throw away."],
}

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------

local takeoverNote

local function TakeoverText()
	local takeover = ns.Takeover
	if takeover.other then
		-- ElvUI stays; only its bags are turned off.
		local how = takeover.other == "ElvUI" and L["Turn off Bags in ElvUI's options to use Satchel's bags."]
			or format(L["Turn %s off in the AddOns list to use Satchel's bags."], takeover.other)
		return format(L["%s is handling your bags, so Satchel only records your bank, guild vault and characters."], takeover.other) .. " " .. how
	end
	local parts = {}
	parts[#parts + 1] = takeover.bags and L["Satchel is your bags."] or L["Satchel is not replacing the bags."]
	parts[#parts + 1] = takeover.bank and L["Satchel is your bank."] or L["The game's bank window is used at the bank."]
	parts[#parts + 1] = L["Changes to these two take effect after /reload."]
	return table.concat(parts, " ")
end

local function BuildGeneral(page)
	local left = NewColumn(page, 16, -8)
	left:Add(W.Header(page, L["Windows"], 300))
	left:Add(W.Checkbox(page, L["Use Satchel for the bags"], Get("replaceBags"), Set("replaceBags"),
		L["Satchel opens with the bag keys, the bag buttons, at vendors, and from anything else that opens the bags, such as data bars. Takes effect after /reload."]))
	left:Add(W.Checkbox(page, L["Use Satchel for the bank"], Get("replaceBank"), Set("replaceBank"),
		L["At the bank, Satchel shows the bank instead of the game's bank window. Takes effect after /reload."]))
	takeoverNote = left:Add(W.Note(page, TakeoverText(), 300))
	left:Skip(6)
	left:Add(W.Header(page, L["Layout"], 300))
	left:Add(W.Slider(page, L["Items per row in the bags"], 6, 24, 1, Get("columns"), Set("columns")))
	left:Add(W.Slider(page, L["Items per row in the bank and guild vault"], 6, 24, 1, Get("bankColumns"), Set("bankColumns")))
	left:Add(W.Slider(page, L["Item size"], 28, 48, 1, Get("tileSize"), Set("tileSize")))
	left:Add(W.Slider(page, L["Scale"], 0.6, 1.6, 0.05, Get("scale"), Set("scale"), {
		format = function(value)
			return format("%.2f", value)
		end,
	}))
	left:Add(W.Checkbox(page, L["Put small categories side by side"], Get("compact"), Set("compact"),
		L["Otherwise every category starts on its own row."]))

	local right = NewColumn(page, 340, -8)
	right:Add(W.Header(page, L["Items"], 300))
	right:Add(W.Checkbox(page, L["Merge stacks of the same item"], Get("mergeStacks"), Set("mergeStacks"),
		L["All stacks of an item show as one, with the total. Using it takes from the smallest stack first, or, for items with charges such as Wizard Oil, the one with the fewest charges left. Gear always shows piece by piece, and everything in your bags shows stack by stack while a mailbox, trade, auction house, bank or guild vault is open."]))
	right:Add(W.Checkbox(page, L["Put new items first"], Get("newFirst"), Set("newFirst"),
		L["Items you just got go in a New section at the top of the bags until you close them."]))
	right:Add(W.Checkbox(page, L["Show the item level on gear"], Get("itemLevel"), Set("itemLevel"),
		L["Weapons and armor, including rings, necklaces, trinkets and off-hands."]))
	right:Add(W.Checkbox(page, L["Mark items you can still trade"], Get("bindMarker"), Set("bindMarker"),
		L["BoE (Bind on Equip) or BoU (Bind on Use) in the corner of items that are not soulbound yet."]))
	right:Add(W.Checkbox(page, L["Red for items you cannot use"], Get("unusableTint"), Set("unusableTint"),
		L["Gear you cannot wear or wield, recipes you cannot learn and items you are not high enough level or skilled enough to use, for the character you are playing."]))
	right:Add(W.Slider(page, L["Quality border, in screen pixels"], 1, 4, 1, Get("borderSize"), Set("borderSize")))
	right:Skip(6)
	right:Add(W.Header(page, L["Sorting"], 300))
	right:Add(W.Dropdown(page, L["Sort items in a category by"], 240, SORT_ITEMS, Get("sortMode"), Set("sortMode")))
	right:Skip(6)
	right:Add(W.Header(page, L["Junk"], 300))
	right:Add(W.Checkbox(page, L["Sort junk by vendor value, cheapest first"], Get("junkByValue"), Set("junkByValue"),
		L["The first junk item is always the one worth the least, whole stack included."]))
	right:Add(W.Checkbox(page, L["Show the vendor value on junk items"], Get("junkValueText"), Set("junkValueText")))
	right:Skip(6)
	right:Add(W.Header(page, L["Tooltips"], 300))
	right:Add(W.Checkbox(page, L["Show how many each character has"], Get("tooltipCounts"), Set("tooltipCounts"),
		L["Item tooltips list how many your characters carry and keep in their bank, and how many are in your guild vaults."]))
	right:Skip(6)
	right:Add(W.Header(page, L["Tips"], 300))
	right:Add(W.Note(page, L["Drop an item on a category's title in the bags to keep it in that category. Middle-click the item to undo it."], 300))
	right:Add(W.Note(page, L["Point at your gold in the bags to see every character's gold."], 300))
	right:Add(W.Note(page, L["The bank, mailbox and guild vault are recorded each time you visit them, and every character's bags each time you play them. Mail between your characters is recorded as it is sent."], 300))
end

--------------------------------------------------------------------------------
-- Categories
--------------------------------------------------------------------------------

local selectedKey
local listScroll, listContent
local rows = {}
local detail = {}

local function Row_OnClick(row)
	selectedKey = row.key
	W.CloseMenu()
	Options:RefreshCategories()
end

local function RowCheck_OnClick(check)
	local key = check:GetParent().key
	if key == Categories.CATCH_ALL then
		return
	end
	local hidden = not Categories.IsHidden(key)
	C.PlaySound(hidden and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON", hidden and 857 or 856)
	Categories.SetHidden(key, hidden)
	Options:RefreshCategories()
end

local function CreateRow()
	local row = CreateFrame("Button", nil, listContent)
	row:SetHeight(ROW_HEIGHT)
	row.selectedBg = W.Background(row, W.COLORS.selected)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.07)

	local check = CreateFrame("Button", nil, row)
	check:SetSize(14, 14)
	check:SetPoint("LEFT", 6, 0)
	W.Background(check, W.COLORS.control)
	W.Border(check)
	check.mark = check:CreateTexture(nil, "ARTWORK")
	check.mark:SetPoint("TOPLEFT", 3, -3)
	check.mark:SetPoint("BOTTOMRIGHT", -3, 3)
	W.Paint(check.mark, W.COLORS.accent)
	check:SetScript("OnClick", RowCheck_OnClick)
	W.SetTooltip(check, L["Shown"], L["Hidden categories are skipped: their items go to the next category that takes them."])
	check:SetScript("OnEnter", W.ShowTooltip)
	check:SetScript("OnLeave", W.HideTooltip)
	row.check = check

	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", check, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -86, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)

	row.down = W.Button(row, L["Down"], 42, 16, function(self)
		Categories.Move(self:GetParent().key, 1)
		Options:RefreshCategories()
	end)
	row.down:SetPoint("RIGHT", -4, 0)
	row.up = W.Button(row, L["Up"], 32, 16, function(self)
		Categories.Move(self:GetParent().key, -1)
		Options:RefreshCategories()
	end)
	row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)

	row:SetScript("OnClick", Row_OnClick)
	rows[#rows + 1] = row
	return row
end

local function AssignedCount(key)
	local count = 0
	for _, assigned in pairs(DB.categories.items or {}) do
		if assigned == key then
			count = count + 1
		end
	end
	return count
end

function Options:RefreshCategories()
	if not listContent then
		return
	end
	local list = Categories.List()
	if not selectedKey or not Categories.Exists(selectedKey) then
		selectedKey = list[1] and list[1].key
	end
	local y = 0
	for i, entry in ipairs(list) do
		local row = rows[i] or CreateRow()
		row.key = entry.key
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", listContent, "RIGHT", 0, 0)
		row.text:SetText(entry.name .. (entry.custom and "  |cff808080" .. L["custom"] .. "|r" or ""))
		row.text:SetTextColor(entry.hidden and 0.5 or 1, entry.hidden and 0.5 or 1, entry.hidden and 0.5 or 1)
		row.check.mark:SetShown(not entry.hidden)
		row.check:SetShown(entry.key ~= Categories.CATCH_ALL)
		row.selectedBg:SetShown(entry.key == selectedKey)
		row:Show()
		y = y + ROW_HEIGHT
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	listScroll:SetContentHeight(y)
	self:RefreshDetail()
end

function Options:RefreshDetail()
	if not detail.title then
		return
	end
	local key = selectedKey
	local custom = key and Categories.Custom(key)
	detail.title:SetText(key and Categories.Name(key) or "")
	detail.description:SetText(custom and L["A category of your own. It takes every item that matches all of its rules, and items dropped on its title. With no rules it only holds dropped items. For a Bind on Equip group, set Binding and leave the rest."] or DESCRIPTIONS[key] or "")
	for _, widget in ipairs(detail.customOnly) do
		widget:SetShown(custom ~= nil)
	end
	local assigned = key and AssignedCount(key) or 0
	detail.assigned:SetText(format(L["Items dropped into this category: %d"], assigned))
	detail.forget:SetActive(assigned > 0)
	W.RefreshAll()
end

local function Selected(field)
	return function()
		local custom = selectedKey and Categories.Custom(selectedKey)
		if field == "name" then
			return selectedKey and Categories.Name(selectedKey) or ""
		end
		if not custom then
			return false
		end
		if field == "text" then
			return custom.text or ""
		end
		local value = custom[field]
		if value == nil then
			return false
		end
		return value
	end
end

local function SetRule(field)
	return function(value)
		local custom = selectedKey and Categories.Custom(selectedKey)
		if not custom then
			return
		end
		local rules = { quality = custom.quality, class = custom.class, text = custom.text, bind = custom.bind }
		if value == false or value == "" then
			value = nil
		end
		rules[field] = value
		Categories.SetRules(selectedKey, rules)
		Options:RefreshCategories()
	end
end

local function BuildCategories(page)
	listScroll, listContent = W.ScrollFrame(page)
	listScroll:SetPoint("TOPLEFT", 12, -8)
	listScroll:SetPoint("BOTTOMLEFT", 12, 40)
	listScroll:SetWidth(270)
	W.Background(listScroll, W.COLORS.panel)

	local new = W.Button(page, L["New category"], 130, 22, function()
		selectedKey = Categories.AddCustom(L["New category"], {})
		Options:RefreshCategories()
	end, L["Adds a category of your own. Give it rules, such as a quality or an item type, or drop items on its title."])
	new:SetPoint("BOTTOMLEFT", 12, 10)

	local x = 300
	local column = NewColumn(page, x, -8)
	detail.title = column:Add(page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"), 22)
	detail.description = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	detail.description:SetWidth(330)
	detail.description:SetJustifyH("LEFT")
	detail.description:SetTextColor(0.75, 0.75, 0.78)
	column:Add(detail.description, 58)

	column:Add(W.EditBox(page, L["Name"], 240, Selected("name"), function(text)
		if selectedKey then
			Categories.Rename(selectedKey, text)
			Options:RefreshCategories()
		end
	end, { tooltip = L["Leave empty to go back to the original name."] }))

	detail.customOnly = {}
	local function Custom(widget)
		detail.customOnly[#detail.customOnly + 1] = widget
		return widget
	end
	Custom(column:Add(W.Dropdown(page, L["Quality"], 240, Categories.QualityChoices, Selected("quality"), SetRule("quality"))))
	Custom(column:Add(W.Dropdown(page, L["Item type"], 240, Categories.ClassChoices, Selected("class"), SetRule("class"))))
	Custom(column:Add(W.Dropdown(page, L["Binding"], 240, Categories.BindChoices, Selected("bind"), SetRule("bind"), {
		tooltip = L["Bind on Equip, not bound yet: gear and other items you can still sell or give away."],
	})))
	Custom(column:Add(W.EditBox(page, L["Name contains"], 240, Selected("text"), SetRule("text"), {
		tooltip = L["Only items with this in their name. Not case sensitive."],
	})))
	column:Skip(4)
	detail.assigned = column:Add(page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"), 14)
	detail.forget = column:Add(W.Button(page, L["Forget dropped items"], 160, 22, function()
		local key = selectedKey
		for itemID, assigned in pairs(DB.categories.items or {}) do
			if assigned == key then
				Categories.Unassign(itemID)
			end
		end
		Options:RefreshCategories()
	end, L["Items dropped into this category go back to where they would go on their own."]))
	column:Skip(8)
	Custom(column:Add(W.Button(page, L["Delete category"], 160, 22, function()
		local key = selectedKey
		W.Confirm(format(L["Delete the category \"%s\"?"], Categories.Name(key)), function()
			Categories.DeleteCustom(key)
			selectedKey = nil
			Options:RefreshCategories()
		end)
	end)))
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------

local peopleScroll, peopleContent
local peopleRows = {}

local function CreatePersonRow()
	local row = CreateFrame("Frame", nil, peopleContent)
	row:SetHeight(34)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", 6, -3)
	row.info = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.info:SetTextColor(0.6, 0.6, 0.62)
	row.delete = W.Button(row, L["Forget"], 64, 20, function(self)
		local parent = self:GetParent()
		W.Confirm(format(L["Forget everything recorded for %s?"], parent.label), function()
			if parent.guildKey then
				DB.DeleteGuild(parent.guildKey)
			else
				DB.DeleteCharacter(parent.charKey)
			end
			Options:RefreshCharacters()
		end)
	end)
	row.delete:SetPoint("RIGHT", -6, 0)
	peopleRows[#peopleRows + 1] = row
	return row
end

function Options:RefreshCharacters()
	if not peopleContent then
		return
	end
	local index, y = 0, 0
	local function Row()
		index = index + 1
		local row = peopleRows[index] or CreatePersonRow()
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", peopleContent, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", peopleContent, "RIGHT", 0, 0)
		row:Show()
		y = y + 38
		return row
	end
	local playerKey = DB.PlayerKey()
	for _, entry in ipairs(DB.CharacterList()) do
		local char = entry.char
		local row = Row()
		row.charKey, row.guildKey = entry.key, nil
		row.label = DB.DisplayName(char) or entry.key
		row.name:SetText(C.ColorText(row.label, C.ClassColor(char.class)) .. "  |cff808080" .. (char.realm or "") .. (char.level and ("  " .. format(L["level %d"], char.level)) or "") .. "|r")
		local mailTime = char.mail and char.mail.time
		row.info:SetText(format(L["bags %s, bank %s, mailbox %s"], char.bagsTime and C.TimeAgo(char.bagsTime) or L["never"],
			char.bankTime and C.TimeAgo(char.bankTime) or L["never"], mailTime and C.TimeAgo(mailTime) or L["never"]))
		row.delete:SetActive(entry.key ~= playerKey)
	end
	y = y + 10
	for _, entry in ipairs(DB.GuildList()) do
		local guild = entry.guild
		local row = Row()
		row.charKey, row.guildKey = nil, entry.key
		row.label = guild.name or entry.key
		row.name:SetText("|cff40ff40" .. row.label .. "|r  |cff808080" .. (guild.realm or "") .. "  " .. L["guild vault"] .. "|r")
		row.info:SetText(format(L["recorded %s"], C.TimeAgo(guild.time)))
		row.delete:SetActive(true)
	end
	for i = index + 1, #peopleRows do
		peopleRows[i]:Hide()
	end
	peopleScroll:SetContentHeight(y)
end

local function BuildCharacters(page)
	local note = W.Note(page, L["Characters and guild vaults Satchel has recorded. Forget the ones you no longer play; a character comes back the next time you log in with it."], 620)
	note:SetPoint("TOPLEFT", 16, -8)
	local top = -40
	-- Surnames exist on Forever only.
	if C.isForever then
		local surnames = W.Checkbox(page, L["Show surnames"], Get("showSurnames"), function(value)
			Set("showSurnames")(value)
			Options:RefreshCharacters()
		end, L["Show your characters' first and last names everywhere, not just their first names. Characters that share a first name always show both."])
		surnames:SetPoint("TOPLEFT", 16, -34)
		top = -62
	end
	peopleScroll, peopleContent = W.ScrollFrame(page)
	peopleScroll:SetPoint("TOPLEFT", 12, top)
	peopleScroll:SetPoint("BOTTOMRIGHT", -12, 10)
	W.Background(peopleScroll, W.COLORS.panel)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local TAB_KEYS = { "general", "categories", "characters" }

function Options:Build()
	local version = C.AddOnMetadata("Satchel", "Version")
	window = W.Window("SatchelOptionsFrame", L["Satchel"] .. (version and ("  |cff808080" .. version .. "|r") or ""), WIDTH, HEIGHT)
	for i = 1, #TAB_KEYS do
		local page = CreateFrame("Frame", nil, window)
		page:SetPoint("TOPLEFT", 0, -66)
		page:SetPoint("BOTTOMRIGHT", 0, 8)
		page:Hide()
		pages[i] = page
	end
	BuildGeneral(pages[1])
	BuildCategories(pages[2])
	BuildCharacters(pages[3])

	tabs = W.Tabs(window, { L["General"], L["Categories"], L["Characters"] }, function(index)
		for i, page in ipairs(pages) do
			page:SetShown(i == index)
		end
		if index == 2 then
			Options:RefreshCategories()
		elseif index == 3 then
			Options:RefreshCharacters()
		end
	end)
	W.SelectTab(tabs, 1)

	ns.Skin.Apply(function(S)
		if S.Shell then
			S.Shell(window)
		end
	end)
	ns.Listen("categories", function()
		if window:IsShown() then
			Options:RefreshCategories()
		end
	end)
end

function Options:Refresh()
	if not window then
		return
	end
	takeoverNote:SetText(TakeoverText())
	W.RefreshAll()
	self:RefreshCategories()
	self:RefreshCharacters()
end

-- tab: "general", "categories" or "characters".
function Options.Open(tab)
	if not window then
		Options:Build()
	end
	Options:Refresh()
	window:Show()
	window:Raise()
	for i, key in ipairs(TAB_KEYS) do
		if key == tab then
			W.SelectTab(tabs, i)
		end
	end
end

function Options.Toggle()
	if window and window:IsShown() then
		window:Hide()
	else
		Options.Open()
	end
end

-- A page in the game's own AddOns options that opens the window.
function Options.Register()
	local panel = CreateFrame("Frame")
	panel.name = L["Satchel"]
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L["Satchel"])
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(520)
	text:SetJustifyH("LEFT")
	text:SetText(L["The settings are in their own window. You can also open it by typing /satchel options."])
	local open = W.Button(panel, L["Open the Satchel options"], 220, 26, function()
		if not InCombatLockdown() then
			if _G.SettingsPanel and _G.SettingsPanel:IsShown() then
				HideUIPanel(_G.SettingsPanel)
			end
		end
		Options.Open()
	end)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	C.RegisterOptionsPanel(panel, L["Satchel"])
end
