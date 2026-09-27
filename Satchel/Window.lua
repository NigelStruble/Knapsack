local _, ns = ...
local L, C, DB = ns.L, ns.C, ns.DB
local Items, Categories, Sort, Scanner, Tiles, W, Skin = ns.Items, ns.Categories, ns.Sort, ns.Scanner, ns.Tiles, ns.W, ns.Skin
local Mail, BagBar = ns.Mail, ns.BagBar

-- The bags, bank, mail and guild vault windows. Bags, bank and mail show their
-- items in sections by category; the guild vault shows one section per tab.
-- Each window shows one owner: a character, or a guild for the vault. The
-- logged-in character's bags (and bank, while at the bank) are live; the rest
-- comes from the snapshots in the saved data.

local Window = {}
ns.Window = Window

local _G = _G
local ipairs, pairs, format, lower, sort = ipairs, pairs, string.format, string.lower, table.sort
local min, max, ceil, floor, tremove = math.min, math.max, math.ceil, math.floor, table.remove

local PAD = 8
local HEADER_H = 32
local FOOTER_H = 24
local TITLE_H = 18
local GAP = 4
local SECTION_GAP = 14
local ROW_GAP = 6
local MIN_WIDTH = 420
local SCROLLBAR = 12
local SEARCH_MIN, SEARCH_MAX = 60, 180
local COMBINE_ICON = "bags-button-autosort-up"
local COMBINE_FALLBACK = "Interface\\Icons\\INV_Misc_Bag_08"
local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon" -- where the client has no search atlas

local KINDS = {
	bags = {
		frameName = "SatchelBagsFrame",
		title = L["Bags"],
		columns = "columns",
		anchor = "BOTTOMRIGHT",
		x = -90,
		y = 110,
	},
	bank = {
		frameName = "SatchelBankFrame",
		title = L["Bank"],
		columns = "bankColumns",
		anchor = "TOPLEFT",
		x = 50,
		y = -110,
	},
	guild = {
		frameName = "SatchelGuildFrame",
		title = L["Guild Vault"],
		columns = "bankColumns",
		anchor = "TOPLEFT",
		x = 90,
		y = -150,
	},
	mail = {
		frameName = "SatchelMailFrame",
		title = L["Mail"],
		columns = "bankColumns",
		anchor = "TOPLEFT",
		x = 70,
		y = -130,
	},
	-- Every character's items at once: typing searches them all.
	find = {
		frameName = "SatchelFindFrame",
		title = L["Find"],
		columns = "bankColumns",
		anchor = "TOPLEFT",
		x = 110,
		y = -170,
		finder = true,
	},
}

local MIN_FIND = 2 -- letters to type before the Find window searches

local prototype = {}

--------------------------------------------------------------------------------
-- Building sections
--------------------------------------------------------------------------------

-- Fills in what sorting and drawing need (see Sort.lua for the sort fields).
local function Prepare(records)
	for _, rec in ipairs(records) do
		local info = Items.Get(rec.link, rec.itemID)
		rec.info = info
		rec.itemID = rec.itemID or info.itemID
		rec.quality = rec.quality or info.quality
		rec.sortQuality = rec.quality or -1
		rec.sortName = info.lowerName or ""
		rec.sortClass = info.classID or 99
		rec.sortSub = info.subClassID or 99
		if info.complete then
			rec.value = (info.sellPrice or 0) * rec.count
		else
			rec.value = nil
		end
	end
end
Window.Prepare = Prepare

--------------------------------------------------------------------------------
-- Merging
--------------------------------------------------------------------------------

-- All stacks of an item can be shown as one tile with their total. Gear is
-- not merged: every piece is looked at on its own.
local function Mergeable(rec)
	return not rec.info.isGear
end

-- Items that are the same apart from who made them (Wizard Oils from two
-- enchanters) merge: the maker is in the link, as a player GUID.
local function MergeKey(rec)
	return (rec.link:gsub("Player%-%d+%-%x+", ""))
end

-- The tile of merged stacks is the stack that should be used up first, with
-- .count the total and .stacks all of them: of items with charges (Wizard
-- Oil), the one with the fewest charges left; of other items, the smallest
-- stack. An item with no charges left goes last, as it cannot be used.
local NO_CHARGES = math.huge

local function Charges(rec)
	local charges = rec.charges
	if not charges or charges <= 0 then
		return NO_CHARGES
	end
	return charges
end

local function UseFirst(a, b)
	local ca, cb = Charges(a), Charges(b)
	if ca ~= cb then
		return ca < cb
	end
	if a.count ~= b.count then
		return a.count < b.count
	end
	return a.position < b.position
end

local function Merge(records)
	local groups, merged = {}, {}
	for _, rec in ipairs(records) do
		if Mergeable(rec) then
			local key = MergeKey(rec)
			rec.mergeKey = key
			local group = groups[key]
			if group then
				group[#group + 1] = rec
			else
				groups[key] = { rec }
				merged[#merged + 1] = rec
			end
		else
			merged[#merged + 1] = rec
		end
	end
	for i, rec in ipairs(merged) do
		local group = rec.mergeKey and groups[rec.mergeKey]
		if group and group[1] == rec and #group > 1 then
			sort(group, UseFirst)
			local first, total = group[1], 0
			for _, stack in ipairs(group) do
				total = total + stack.count
				if stack.isNew then
					first.isNew = true
				end
			end
			first.stacks = group
			first.count = total
			if first.value then
				first.value = (first.info.sellPrice or 0) * total
			end
			merged[i] = first
		end
	end
	return merged
end
Window.Merge = Merge

-- Whether a window's records are merged. The live bags and bank are not
-- while a mailbox, trade, auction house, bank or guild vault is open (see
-- Scanner.PanelOpen): those take a merged tile's first stack only.
local function Merging(live)
	return DB.settings.mergeStacks and not (live and Scanner.PanelOpen())
end

-- One section per category that has items, in the category list's order.
-- opts.merge: merge stacks; opts.own: the logged-in character's items, so
-- items it cannot use can be marked; opts.sortMode: one order for every
-- category, junk included; opts.newFirst: new items (rec.isNew) in a New
-- section before the rest.
local function CategorySections(records, opts)
	opts = opts or {}
	Prepare(records)
	if opts.merge then
		records = Merge(records)
	end
	local tint = opts.own and DB.settings.unusableTint
	for _, rec in ipairs(records) do
		rec.unusable = tint and Items.Unusable(rec.link, rec.info) or false
	end
	local new
	if opts.newFirst then
		local rest = {}
		new = {}
		for _, rec in ipairs(records) do
			local list = rec.isNew and new or rest
			list[#list + 1] = rec
		end
		records = rest
	end
	local groups = {}
	for _, rec in ipairs(records) do
		local key = Categories.Classify(rec, rec.info)
		rec.category = key
		local list = groups[key]
		if not list then
			list = {}
			groups[key] = list
		end
		list[#list + 1] = rec
	end
	local settings = DB.settings
	local sections = {}
	for _, entry in ipairs(Categories.List()) do
		local list = groups[entry.key]
		if list then
			local section = { key = entry.key, title = entry.name, records = list, category = true }
			if entry.key == "junk" then
				Sort.Items(list, opts.sortMode or (settings.junkByValue and "value") or settings.sortMode)
				local total = 0
				for _, rec in ipairs(list) do
					total = total + (rec.value or 0)
					rec.showValue = settings.junkValueText
				end
				section.money = total
			else
				Sort.Items(list, opts.sortMode or settings.sortMode)
			end
			sections[#sections + 1] = section
		end
	end
	if new and #new > 0 then
		Sort.Items(new, opts.sortMode or settings.sortMode)
		table.insert(sections, 1, { key = "new", title = L["New"], records = new })
	end
	return sections
end
Window.CategorySections = CategorySections

-- New items: those the game marks new, and they stay new until the bags
-- close, even once looked at, so they do not jump back into their categories
-- while being looked at.
function prototype:MarkNew(records)
	local recent = self.recent
	for _, rec in ipairs(records) do
		if C.IsNewItem(rec.bag, rec.slot) then
			recent[rec.position] = rec.link
		end
		rec.isNew = recent[rec.position] == rec.link
	end
end

-- The free space of each bag family, as one "Free" section.
local function FreeSection(free, live)
	local entries = {}
	for _, entry in pairs(free) do
		entry.live = live
		entries[#entries + 1] = entry
	end
	if #entries == 0 then
		return nil
	end
	sort(entries, function(a, b)
		return a.family < b.family
	end)
	return { key = "free", title = L["Free"], free = entries }
end

local function CharacterName(key)
	local char = DB.Character(key)
	if not char then
		return key or "?"
	end
	return C.ColorText(DB.DisplayName(char) or key, C.ClassColor(char.class))
end

function prototype:BagsModel()
	local key = self.ownerKey
	local char = DB.Character(key)
	local live = key == DB.PlayerKey()
	local containers = live and Scanner.LiveBags() or (char and char.bags)
	if not containers then
		return { message = format(L["Nothing recorded for %s yet."], CharacterName(key)) }
	end
	local records = Scanner.Records(containers, live)
	if live then
		self:MarkNew(records)
	end
	local sections = CategorySections(records, { merge = Merging(live), own = live, newFirst = live and DB.settings.newFirst })
	local used, total, free = Scanner.Space(containers)
	sections[#sections + 1] = FreeSection(free, live)
	local footer = format(L["%d/%d slots"], used, total)
	if not live then
		footer = footer .. "  |cff808080" .. format(L["updated %s"], C.TimeAgo(char.bagsTime)) .. "|r"
	end
	return {
		sections = sections,
		footer = footer,
		money = live and GetMoney() or char.money,
		live = live,
		containers = containers, -- for the bag slots
	}
end

function prototype:MailModel()
	local key = self.ownerKey
	local mails = Mail.List(key)
	if not mails then
		return {
			message = format(L["Nothing is known about %s's mail yet. Open a mailbox once with this character, or send it something from another."], CharacterName(key)),
		}
	end
	local sections = CategorySections(Mail.Records(mails), { own = key == DB.PlayerKey(), sortMode = "expires" })
	local items, count, money = Mail.Totals(mails)
	local char = DB.Character(key)
	local footer = format(items == 1 and L["%d item"] or L["%d items"], items) .. ", " .. format(count == 1 and L["%d mail"] or L["%d mails"], count)
	local more = char.mail and char.mail.more or 0
	if more > 0 then
		footer = footer .. "  |cffffd100" .. format(L["%d more waiting"], more) .. "|r"
	end
	local seen = char.mail and char.mail.time
	footer = footer .. "  |cff808080" .. (seen and format(L["mailbox seen %s"], C.TimeAgo(seen)) or L["mailbox not seen yet"]) .. "|r"
	local message
	if count == 0 then
		message = L["The mailbox is empty."]
	elseif items == 0 then
		message = L["No items in the mail, only letters or gold."]
	end
	return { sections = sections, footer = footer, money = money > 0 and money or nil, message = message }
end

function prototype:BankModel()
	local key = self.ownerKey
	local char = DB.Character(key)
	local live = key == DB.PlayerKey() and Scanner.BankOpen()
	if live then
		local state = Scanner.BankState()
		if state == "none" then
			-- The game says what the first tab takes: on Forever it is free.
			local tab = C.NextBankTab()
			local text = L["This character has no bank tab yet."]
			local cost = tab and C.Clean(tab.tabCost)
			if tab then
				text = C.Clean(tab.purchasePromptBody) or text
				local title = C.Clean(tab.purchasePromptTitle)
				if title and title ~= "" then
					text = "|cffffd100" .. title .. "|r\n" .. text
				end
				if cost and cost > 0 then
					text = text .. "\n" .. format(L["It costs %s."], C.Money(cost))
				end
			end
			return { live = true, message = text, unlock = tab ~= nil, unlockCost = cost }
		elseif state == "loading" then
			return { live = true, message = L["The bank is still loading..."] }
		end
	end
	local containers = live and Scanner.LiveBank() or (char and char.bank)
	if not containers then
		return {
			message = format(L["%s's bank has not been recorded yet. Visit a banker once with this character."], CharacterName(key)),
		}
	end
	local own = key == DB.PlayerKey()
	local sections = CategorySections(Scanner.Records(containers, live), { merge = Merging(live), own = own })
	local used, total, free = Scanner.Space(containers)
	local message = #sections == 0 and L["The bank is empty."] or nil
	-- At the bank, items dragged onto the free space go into the bank.
	sections[#sections + 1] = FreeSection(free, live)
	local footer = format(L["%d/%d slots"], used, total)
	if not live then
		footer = footer .. "  |cff808080" .. format(L["updated %s"], C.TimeAgo(char.bankTime)) .. "|r"
	end
	return {
		sections = sections,
		footer = footer,
		live = live,
		message = message,
		containers = containers, -- for the bank bag slots (Classic)
		bankBagSlots = live and C.BankBagSlots() or (char and char.bankBagSlots),
	}
end

function prototype:GuildModel()
	local guild = DB.Guild(self.ownerKey)
	if not guild then
		return { message = L["No guild vault recorded yet. Open your guild vault once to record it."] }
	end
	local records = Scanner.GuildRecords(guild)
	Prepare(records)
	local byTab = {}
	for _, rec in ipairs(records) do
		local list = byTab[rec.tab]
		if not list then
			list = {}
			byTab[rec.tab] = list
		end
		list[#list + 1] = rec
	end
	local sections, unseen = {}, 0
	for tab = 1, #(guild.tabs or {}) do
		local stored = guild.tabs[tab]
		local list = byTab[tab]
		if list then
			sort(list, function(a, b)
				return a.position < b.position
			end)
			sections[#sections + 1] = { key = "tab" .. tab, title = stored.name or format(L["Tab %d"], tab), records = list }
		elseif stored.viewable and not stored.items then
			unseen = unseen + 1
		end
	end
	local footer = format(L["updated %s"], C.TimeAgo(guild.time))
	if unseen > 0 then
		footer = footer .. "  |cff808080" .. format(L["%d tabs not seen yet"], unseen) .. "|r"
	end
	if #sections == 0 then
		return { footer = footer, money = guild.money, message = L["The guild vault is empty, or none of its tabs could be seen."] }
	end
	return { sections = sections, footer = footer, money = guild.money }
end

--------------------------------------------------------------------------------
-- Finding an item anywhere
--------------------------------------------------------------------------------

-- Everywhere your items are, as { title, records }: each character's bags,
-- bank and mail (the logged-in character first), then each guild vault.
local function Places()
	local places = {}
	local playerKey = DB.PlayerKey()
	local characters = DB.CharacterList()
	for i, entry in ipairs(characters) do
		if entry.key == playerKey then
			table.insert(characters, 1, tremove(characters, i))
			break
		end
	end
	for _, entry in ipairs(characters) do
		local key, char = entry.key, entry.char
		local own = key == playerKey
		local name = C.ColorText(DB.DisplayName(char) or key, C.ClassColor(char.class))
		local bags = own and Scanner.LiveBags() or char.bags
		if bags then
			places[#places + 1] = { title = format(L["%s: bags"], name), records = Scanner.Records(bags) }
		end
		local bank = (own and Scanner.BankOpen()) and Scanner.LiveBank() or char.bank
		if bank then
			places[#places + 1] = { title = format(L["%s: bank"], name), records = Scanner.Records(bank) }
		end
		local mails = Mail.List(key)
		if mails then
			places[#places + 1] = { title = format(L["%s: mail"], name), records = Mail.Records(mails) }
		end
	end
	for _, entry in ipairs(DB.GuildList()) do
		local name = "|cff40ff40" .. (entry.guild.name or entry.key) .. "|r"
		places[#places + 1] = { title = format(L["%s: guild vault"], name), records = Scanner.GuildRecords(entry.guild) }
	end
	return places
end

function prototype:FindModel()
	local test = self.searchTest
	if not test or #self.search < MIN_FIND then
		return { message = L["Type part of an item's name to find it on all your characters: in their bags, banks and mail, and in your guild vaults. Keywords work too: boe, soulbound, epic, ilvl>30 and more (point at the box)."] }
	end
	local sections, total = {}, 0
	for i, place in ipairs(Places()) do
		local records = place.records
		Prepare(records)
		local found = {}
		for _, rec in ipairs(records) do
			if test(rec) then
				found[#found + 1] = rec
			end
		end
		if #found > 0 then
			if DB.settings.mergeStacks then
				found = Merge(found)
			end
			Sort.Items(found, DB.settings.sortMode)
			for _, rec in ipairs(found) do
				total = total + rec.count
			end
			sections[#sections + 1] = { key = "place" .. i, title = place.title, records = found }
		end
	end
	if #sections == 0 then
		return { message = format(L["None of your characters has anything called \"%s\"."], self.searchText) }
	end
	return { sections = sections, footer = format(L["%d found in %d places"], total, #sections) }
end

function prototype:BuildModel()
	if self.kind == "bags" then
		return self:BagsModel()
	elseif self.kind == "bank" then
		return self:BankModel()
	elseif self.kind == "mail" then
		return self:MailModel()
	elseif self.kind == "find" then
		return self:FindModel()
	end
	return self:GuildModel()
end

--------------------------------------------------------------------------------
-- Section titles
--------------------------------------------------------------------------------

local titlePool = {}

local function Title_OnEnter(self)
	local section = self.section
	if not section or not section.category then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(section.title, 1, 1, 1)
	GameTooltip:AddLine(L["Drop an item here to keep that item in this category."], 0.8, 0.8, 0.8, true)
	GameTooltip:AddLine(L["Middle-click an item to put it back where it belongs."], 0.8, 0.8, 0.8, true)
	GameTooltip:AddLine(L["Right-click for more: at the bank or a mailbox, to move the whole category."], 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function Title_OnLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

-- An item held on the cursor and dropped on a title goes to that category.
local function Title_TakeItem(self)
	local section = self.section
	local kind, itemID = GetCursorInfo()
	if section and section.category and kind == "item" and itemID then
		ClearCursor()
		Categories.Assign(itemID, section.key)
		return true
	end
	return false
end

local function Title_OnClick(self, button)
	if Title_TakeItem(self) then
		return
	end
	local section = self.section
	if button ~= "RightButton" or not section or not section.category then
		return
	end
	local key = section.key
	local window = self.window
	MenuUtil.CreateContextMenu(self, function(_, root)
		root:CreateTitle(Categories.Name(key))
		-- At the bank or a mailbox: move the whole category.
		if window and ns.Transfer.AddToMenu(root, window, section) then
			root:CreateDivider()
		end
		if key ~= Categories.CATCH_ALL then
			root:CreateButton(L["Hide this category"], function()
				Categories.SetHidden(key, true)
			end)
		end
		root:CreateButton(L["Move up"], function()
			Categories.Move(key, -1)
		end)
		root:CreateButton(L["Move down"], function()
			Categories.Move(key, 1)
		end)
		root:CreateButton(L["Category settings..."], function()
			ns.Options.Open("categories")
		end)
	end)
end

local function NewTitle()
	local title = CreateFrame("Button", nil, UIParent)
	title:RegisterForClicks("AnyUp")
	title.text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title.text:SetPoint("LEFT", 1, 0)
	title.text:SetJustifyH("LEFT")
	title.text:SetWordWrap(false)
	title:SetScript("OnEnter", Title_OnEnter)
	title:SetScript("OnLeave", Title_OnLeave)
	title:SetScript("OnClick", Title_OnClick)
	title:SetScript("OnReceiveDrag", Title_TakeItem)
	Skin.Font(title.text)
	return title
end

function prototype:AcquireTitle(section)
	local title = tremove(titlePool) or NewTitle()
	title:SetParent(self.content)
	title:SetHeight(TITLE_H)
	title.section, title.window = section, self
	local count
	if section.free then
		count = 0
		for _, entry in ipairs(section.free) do
			count = count + entry.count
		end
	else
		count = #section.records
	end
	local text = section.title .. "  |cff808080" .. count .. "|r"
	if section.money and section.money > 0 then
		text = text .. "   " .. C.Money(section.money)
	end
	title.text:SetText(text)
	title.width = floor(title.text:GetStringWidth() + 6)
	title:EnableMouse(section.category == true)
	title:Show()
	self.titles[#self.titles + 1] = title
	return title
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function prototype:ReleaseAll()
	for i = #self.tiles, 1, -1 do
		Tiles.Release(self.tiles[i])
		self.tiles[i] = nil
	end
	for i = #self.titles, 1, -1 do
		local title = self.titles[i]
		title:Hide()
		title:ClearAllPoints()
		title.section = nil
		titlePool[#titlePool + 1] = title
		self.titles[i] = nil
	end
end

function prototype:Draw(model)
	self:ReleaseAll()
	self.live = model.live and true or false -- its items can be used and moved
	local settings = DB.settings
	local size = settings.tileSize
	local columns = max(4, settings[self.spec.columns] or 12)
	local fullWidth = columns * size + (columns - 1) * GAP
	local content = self.content
	local level = content:GetFrameLevel() + 2
	local compact = settings.compact
	local x, y, rowHeight = 0, 0, 0

	local sections = model.sections or {}
	for _, section in ipairs(sections) do
		local items = section.records or section.free
		local count = #items
		local cols = min(count, columns)
		local rows = ceil(count / cols)
		local title = self:AcquireTitle(section)
		local width = min(fullWidth, max(cols * size + (cols - 1) * GAP, title.width))
		local height = TITLE_H + rows * size + (rows - 1) * GAP
		if x > 0 and (not compact or x + width > fullWidth) then
			y = y + rowHeight + ROW_GAP
			x, rowHeight = 0, 0
		end
		title:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		title:SetWidth(width)
		for i, item in ipairs(items) do
			local tile = Tiles.Acquire(content, level)
			if section.free then
				Tiles.SetFree(tile, item, size)
			else
				Tiles.Set(tile, item, size)
			end
			local col, row = (i - 1) % cols, floor((i - 1) / cols)
			tile:SetPoint("TOPLEFT", content, "TOPLEFT", x + col * (size + GAP), -(y + TITLE_H + row * (size + GAP)))
			if model.live and item.bag and item.slot then
				Tiles.Secure.Attach(tile, item.bag, item.slot)
			end
			self.tiles[#self.tiles + 1] = tile
		end
		x = x + width + SECTION_GAP
		rowHeight = max(rowHeight, height)
	end
	local contentHeight = y + rowHeight

	if model.message then
		self.message:SetText(model.message)
		self.message:SetWidth(max(fullWidth, MIN_WIDTH - 2 * PAD) - 20)
		self.message:ClearAllPoints()
		self.message:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -(contentHeight + (contentHeight > 0 and 10 or 16)))
		self.message:Show()
		contentHeight = contentHeight + ceil(self.message:GetStringHeight()) + 32
	else
		self.message:Hide()
	end
	-- The bank's first tab, when the character has none yet.
	local unlock = self.unlockButton
	if unlock then
		unlock:SetShown(model.unlock and model.message ~= nil)
		if unlock:IsShown() then
			unlock.text:SetText((model.unlockCost or 0) > 0 and L["Buy bank tab"] or L["Unlock bank tab"])
			unlock:ClearAllPoints()
			unlock:SetPoint("TOPLEFT", self.message, "BOTTOMLEFT", 0, -10)
			contentHeight = contentHeight + 34
		end
	end

	self.footer:SetText(model.footer or "")
	self.money:SetText(model.money and C.Money(model.money) or "")
	self.moneyButton:SetWidth(max(1, floor(self.money:GetStringWidth() + 4)))

	-- The bag slots, between the items and the footer.
	local bar = self.bagBar
	local barHeight = 0
	if bar then
		local wanted = settings[self.barSetting] and true or false
		local show = wanted and model.containers ~= nil
		bar:SetShown(show)
		self.bagToggle:SetSelected(wanted)
		if show then
			BagBar.Update(bar, model.containers, model.live, model.bankBagSlots)
			barHeight = BagBar.HEIGHT
		end
	end
	self.scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 6 + barHeight)

	-- Size the window to its contents, scrolling past most of the screen height.
	local scale = self:GetScale()
	local screen = UIParent:GetHeight() / scale
	local chrome = HEADER_H + FOOTER_H + 10 + barHeight
	local visible = max(min(contentHeight, floor(screen * 0.8) - chrome), 40)
	local scrolling = contentHeight > visible
	local width = max(MIN_WIDTH, fullWidth + 2 * PAD + (scrolling and SCROLLBAR or 0))
	self:SetSize(width, visible + chrome)
	self.scroll:SetContentHeight(contentHeight, visible)
	self:LayoutHeader()

	self:ApplySearch()
	self:CheckTooltip()
end

-- A redraw can move Blizzard's buttons out from under the mouse; a tooltip
-- left behind for one of them would point at the wrong item.
function prototype:CheckTooltip()
	local owner = GameTooltip:GetOwner()
	if not owner then
		return
	end
	for _, tile in ipairs(self.tiles) do
		local button = Tiles.Secure.Attached(tile)
		if button == owner then
			if not button:IsMouseOver() then
				GameTooltip:Hide()
			end
			return
		end
	end
end

-- Whether a tile shows an item in the given bag (any of its stacks, when
-- merged), or that bag's free space.
local function InBag(tile, bag)
	local rec = tile.record
	if not rec then
		return tile.free ~= nil and tile.free.bag == bag
	end
	for _, stack in ipairs(rec.stacks or { rec }) do
		if stack.bag == bag then
			return true
		end
	end
	return false
end

-- Dims the tiles that do not match the search (see Search.lua), or, while the
-- mouse is on one of the bag slots, the items that are not in that bag.
function prototype:ApplySearch()
	local test, bag = self.searchTest, self.highlightBag
	for _, tile in ipairs(self.tiles) do
		local rec = tile.record
		local match = not test or (rec ~= nil and test(rec))
		if bag ~= nil then
			match = InBag(tile, bag)
		end
		Tiles.SetMatch(tile, match)
	end
end

function prototype:HighlightBag(bag)
	self.highlightBag = bag
	self:ApplySearch()
end

-- In the Find window typing searches everything again; elsewhere it dims
-- what does not match.
function prototype:SetSearch(text)
	self.searchText = text or ""
	self.search = lower(self.searchText)
	self.searchTest = ns.Search.Compile(self.search)
	if self.spec.finder then
		self:QueueFind()
	else
		self:ApplySearch()
	end
end

function prototype:UpdateCooldowns()
	for _, tile in ipairs(self.tiles) do
		Tiles.UpdateCooldown(tile)
	end
end

function prototype:Refresh()
	if not self:IsShown() then
		self.dirty = true
		return
	end
	self.dirty = false
	self:UpdateHeader()
	self:Draw(self:BuildModel())
end

--------------------------------------------------------------------------------
-- Owner (whose bags, bank or guild vault)
--------------------------------------------------------------------------------

function prototype:DefaultOwner()
	if self.kind ~= "guild" then
		return DB.PlayerKey()
	end
	local char = DB.PlayerCharacter()
	if char and char.guild and DB.Guild(char.guild) then
		return char.guild
	end
	local list = DB.GuildList()
	return list[1] and list[1].key
end

function prototype:OwnerChoices()
	local choices = {}
	local player = DB.Player()
	local realm = player and player.realmName
	if self.kind == "guild" then
		for _, entry in ipairs(DB.GuildList()) do
			local text = entry.guild.name or entry.key
			if entry.guild.realm and entry.guild.realm ~= realm then
				text = text .. " |cff808080- " .. entry.guild.realm .. "|r"
			end
			choices[#choices + 1] = { value = entry.key, text = text }
		end
	else
		for _, entry in ipairs(DB.CharacterList()) do
			local char = entry.char
			local text = C.ColorText(DB.DisplayName(char) or entry.key, C.ClassColor(char.class))
			if char.realm and char.realm ~= realm then
				text = text .. " |cff808080- " .. char.realm .. "|r"
			end
			choices[#choices + 1] = { value = entry.key, text = text }
		end
	end
	return choices
end

function prototype:SetOwner(key)
	self.ownerKey = key or self:DefaultOwner()
	self.owner:Refresh()
	self:Refresh()
end

-- Header pieces that depend on the owner.
function prototype:UpdateHeader()
	local key = self.ownerKey
	local valid
	if self.kind == "guild" then
		valid = key ~= nil and DB.Guild(key) ~= nil
	else
		valid = key ~= nil and (key == DB.PlayerKey() or DB.Character(key) ~= nil)
	end
	if not valid then
		self.ownerKey = self:DefaultOwner()
	end
	self.owner:Refresh()
	if self.vaultButton then
		local char = DB.Character(self.ownerKey)
		self.vaultButton:SetActive(char and char.guild and DB.Guild(char.guild) ~= nil)
	end
	local own = self.ownerKey == DB.PlayerKey()
	if self.blizzardButton then
		self.blizzardButton:SetShown((ns.Takeover.bank and Scanner.BankOpen() and own) and true or false)
	end
	if self.combineButton then
		-- The bags can always be tidied; the bank only while at the bank.
		local show = own and (self.kind == "bags" or Scanner.BankOpen())
		self.combineButton:SetShown(show and true or false)
		self.combineButton:SetActive(not ns.Stack.Running())
	end
	self:LayoutHeader()
end

-- Buttons go left and right along the header; the search box takes what is
-- left in between, up to SEARCH_MAX, so a wide window keeps an empty stretch
-- of header to drag it by.
function prototype:LayoutHeader()
	local header = self.header
	local left = PAD
	for _, widget in ipairs(self.leftWidgets) do
		if widget:IsShown() then
			widget:ClearAllPoints()
			widget:SetPoint("LEFT", header, "LEFT", left, 0)
			left = left + widget:GetWidth() + 4
		end
	end
	local right = 3
	for _, widget in ipairs(self.rightWidgets) do
		if widget:IsShown() then
			widget:ClearAllPoints()
			widget:SetPoint("RIGHT", header, "RIGHT", -right, 0)
			right = right + widget:GetWidth() + 4
		end
	end
	local room = self:GetWidth() - left - right - 8
	self.searchBox:ClearAllPoints()
	self.searchBox:SetPoint("RIGHT", header, "RIGHT", -(right + 4), 0)
	if self.spec.finder then
		self.searchBox:SetPoint("LEFT", header, "LEFT", left, 0) -- the whole header is for typing
	else
		self.searchBox:SetWidth(max(SEARCH_MIN, min(SEARCH_MAX, room)))
	end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------

function prototype:RestorePosition()
	local spec = self.spec
	local saved = DB.positions[spec.frameName]
	self:ClearAllPoints()
	if type(saved) == "table" and saved[1] then
		self:SetPoint(saved[1], UIParent, saved[1], saved[2] or 0, saved[3] or 0)
	else
		self:SetPoint(spec.anchor, UIParent, spec.anchor, spec.x, spec.y)
	end
end

-- The bags keep their bottom-right corner in place as they grow and shrink,
-- the other windows their top-left corner.
function prototype:SavePosition()
	local anchor = self.spec.anchor
	local scale = self:GetScale()
	local x, y
	if anchor == "BOTTOMRIGHT" then
		x = (self:GetRight() or 0) - UIParent:GetWidth() / scale
		y = self:GetBottom() or 0
	else
		x = self:GetLeft() or 0
		y = (self:GetTop() or 0) - UIParent:GetHeight() / scale
	end
	self:ClearAllPoints()
	self:SetPoint(anchor, UIParent, anchor, x, y)
	DB.positions[self.spec.frameName] = { anchor, x, y }
end

function prototype:ApplyScale()
	self:SetScale(DB.settings.scale)
	self:RestorePosition()
end

--------------------------------------------------------------------------------
-- Creating a window
--------------------------------------------------------------------------------

local function SearchBox(parent, window)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetHeight(20)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	box.bg = W.Background(box, W.COLORS.control)
	W.Border(box)
	box.icon = box:CreateTexture(nil, "OVERLAY")
	C.SetIcon(box.icon, "common-search-magnifyingglass", SEARCH_ICON)
	box.icon:SetSize(11, 11)
	box.icon:SetPoint("LEFT", 5, 0)
	box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.placeholder:SetPoint("LEFT", 18, 0)
	box.placeholder:SetText(L["Search"])

	-- The x at the end empties the box and lets go of the keyboard, like
	-- Escape does. It shows while there is text, or the box has the keyboard.
	box:SetTextInsets(18, 20, 0, 0)
	local clear = CreateFrame("Button", nil, box)
	clear:SetSize(16, 16)
	clear:SetPoint("RIGHT", -2, 0)
	clear.icon = clear:CreateTexture(nil, "ARTWORK")
	C.SetIcon(clear.icon, "common-search-clearbutton", "Interface\\FriendsFrame\\ClearBroadcastIcon")
	clear.icon:SetSize(10, 10)
	clear.icon:SetPoint("CENTER")
	clear.icon:SetAlpha(0.6)
	clear:SetScript("OnEnter", function(self)
		self.icon:SetAlpha(1)
	end)
	clear:SetScript("OnLeave", function(self)
		self.icon:SetAlpha(0.6)
	end)
	clear:SetScript("OnClick", function()
		box:SetText("")
		box:ClearFocus()
	end)
	clear:Hide()
	box.clear = clear
	local function UpdateClear(self)
		self.clear:SetShown(self:GetText() ~= "" or self:HasFocus())
	end

	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText()
		self.placeholder:SetShown(text == "")
		UpdateClear(self)
		window:SetSearch(text)
	end)
	box:SetScript("OnEditFocusGained", UpdateClear)
	box:SetScript("OnEditFocusLost", UpdateClear)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	-- What can be typed (see Search.lua).
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L["Search"], 1, 1, 1)
		GameTooltip:AddLine(L["Part of a name, or a keyword:"], 0.8, 0.8, 0.8)
		GameTooltip:AddLine("boe, bou, soulbound, tradable, junk, common, uncommon, rare, epic, legendary, gear, consumable, reagent, tradegoods, recipe, quest, new, charges, unusable", 1, 0.82, 0, true)
		GameTooltip:AddLine(L["An item level: ilvl>30, ilvl<=20. Several words must all match. ! turns a word around: !soulbound."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", W.HideTooltip)
	return box
end

-- Unlocking (or buying) a bank tab has to happen in the game's own secure
-- code: Blizzard's purchase button (BankPanelPurchaseButtonScriptTemplate,
-- whose click opens the game's confirmation, which does it) lies over a
-- button that looks like the rest. Without it, the game's bank window does.
local function UnlockButton(parent)
	local button = W.Button(parent, L["Unlock bank tab"], 150, 24)
	local bankType = _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character
	local ok, secure = pcall(CreateFrame, "Button", nil, button, "BankPanelPurchaseButtonScriptTemplate")
	if ok and secure and bankType then
		secure:SetAttribute("overrideBankType", bankType)
		secure:SetAllPoints(button)
		secure:SetFrameLevel(button:GetFrameLevel() + 2)
		secure:HookScript("OnEnter", function()
			button:GetScript("OnEnter")(button)
		end)
		secure:HookScript("OnLeave", function()
			button:GetScript("OnLeave")(button)
		end)
		button.secure = secure
	else
		button:SetScript("OnClick", function()
			ns.Takeover.ToggleBlizzardBank()
		end)
	end
	button:Hide()
	return button
end

-- Blizzard's broom (its "Clean Up Bags" button) is a whole button, frame and
-- all, so it looks tiny at button size. Its frame is cropped off, so the
-- broom fills Satchel's button.
local BROOM_CROP = 0.14

local function Broom(texture)
	texture:SetSize(18, 18)
	local atlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(COMBINE_ICON)
	local file = atlas and (atlas.file or atlas.filename)
	if file and atlas.leftTexCoord then
		local l, r, t, b = atlas.leftTexCoord, atlas.rightTexCoord, atlas.topTexCoord, atlas.bottomTexCoord
		local x, y = (r - l) * BROOM_CROP, (b - t) * BROOM_CROP
		texture:SetTexture(file)
		texture:SetTexCoord(l + x, r - x, t + y, b - y)
	elseif atlas then
		texture:SetAtlas(COMBINE_ICON)
	else
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

function Window.Create(kind)
	local spec = KINDS[kind]
	local frame = CreateFrame("Frame", spec.frameName, UIParent)
	for name, method in pairs(prototype) do
		frame[name] = method
	end
	frame.kind, frame.spec = kind, spec
	frame.tiles, frame.titles, frame.buttons = {}, {}, {}
	frame.search, frame.searchText = "", ""
	frame.recent = {} -- [bag * 1000 + slot] = link, new items until the window closes
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetSize(MIN_WIDTH, 200)
	frame:SetScale(DB.settings.scale)
	frame:RestorePosition()

	W.Background(frame, W.COLORS.window)
	W.Border(frame)
	local bar = frame:CreateTexture(nil, "BORDER")
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(HEADER_H - 1)
	W.Paint(bar, W.COLORS.title)

	-- Drag any empty part of the window to move it: the header, the space
	-- between items and categories, or the footer.
	local function StartMoving()
		frame:StartMoving()
	end
	local function StopMoving()
		frame:StopMovingOrSizing()
		frame:SavePosition()
	end
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", StartMoving)
	frame:SetScript("OnDragStop", StopMoving)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_H)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", StartMoving)
	header:SetScript("OnDragStop", StopMoving)
	frame.header = header

	local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	frame.close = close

	frame.owner = W.Dropdown(header, nil, 130, function()
		return frame:OwnerChoices()
	end, function()
		return frame.ownerKey
	end, function(value)
		frame:SetOwner(value)
	end, { placeholder = spec.title })
	W.SetTooltip(frame.owner, spec.title, kind == "guild" and L["Choose which guild vault to look at."]
		or L["Choose whose items to look at. Other characters show what they had when you last played them."])

	-- LayoutHeader places these, left to right and right to left. The Find
	-- window is for everyone at once: no owner.
	frame.leftWidgets, frame.rightWidgets = { frame.owner }, { close }
	if spec.finder then
		frame.owner:Hide()
		frame.leftWidgets = {}
	end
	local function AddButton(button, onRight)
		local list = onRight and frame.rightWidgets or frame.leftWidgets
		list[#list + 1] = button
		frame.buttons[#frame.buttons + 1] = button
		return button
	end

	if kind == "bags" then
		AddButton(W.Button(header, L["Bank"], 44, 22, function()
			ns.ToggleBank(frame.ownerKey)
		end, L["Show this character's bank, from anywhere."]))
		AddButton(W.Button(header, L["Mail"], 40, 22, function()
			ns.ToggleMail(frame.ownerKey)
		end, L["Show what waits in this character's mailbox, and when it goes back. Recorded at the mailbox, and when your characters mail each other."]))
		if C.hasGuildBank then
			frame.vaultButton = AddButton(W.Button(header, L["Vault"], 44, 22, function()
				local char = DB.Character(frame.ownerKey)
				ns.ToggleGuild(char and char.guild)
			end, L["Show this character's guild vault as it was when last opened. Open the guild vault once to record it."]))
			-- Keep the tooltip when disabled, so it can say why.
			frame.vaultButton:SetMotionScriptsWhileDisabled(true)
		end
		AddButton(W.IconButton(header, 22, "questlog-icon-setting", "Interface\\Icons\\INV_Misc_Gear_01", function()
			ns.Options.Toggle()
		end, L["Options"]), true)
	elseif kind == "bank" then
		frame.blizzardButton = AddButton(W.Button(header, L["Blizzard"], 60, 22, function()
			ns.Takeover.ToggleBlizzardBank()
		end, C.isClassic and L["Show the game's own bank window. Hiding it again ends the visit to the bank."]
			or L["Show the game's own bank window, to buy bank tabs or change their settings."]))
	end
	if kind == "bags" or kind == "bank" then
		-- Shift-click, at the bank: fill this side's partial stacks from the
		-- other side first.
		local text = kind == "bank"
			and (L["Fills up partial stacks of the same item in the bank, so they take fewer slots."] .. "\n"
				.. L["Shift-click to fill them up from your bags first."])
			or (L["Fills up partial stacks of the same item, so they take fewer slots."] .. "\n"
				.. L["Shift-click at the bank to fill them up from the bank first."])
		frame.combineButton = AddButton(W.IconButton(header, 22, COMBINE_FALLBACK, false, function()
			ns.Stack.Start(kind, IsShiftKeyDown())
		end, L["Combine stacks"], text), true)
		Broom(frame.combineButton.icon)
		frame.combineButton:SetMotionScriptsWhileDisabled(true)
	end
	if kind == "bags" then
		frame.findButton = AddButton(W.IconButton(header, 22, "common-search-magnifyingglass", SEARCH_ICON, function()
			ns.OpenFind(frame.searchBox:GetText())
		end, L["Find"], L["Find an item on all your characters: in their bags, banks and mail, and in your guild vaults."]), true)
	end

	frame.searchBox = SearchBox(header, frame)
	if spec.finder then
		frame.searchBox.placeholder:SetText(L["Name of the item to find"])
	end

	local scroll, content = W.ScrollFrame(frame)
	scroll:SetPoint("TOPLEFT", PAD, -(HEADER_H + 4))
	scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 6)
	frame.scroll, frame.content = scroll, content

	-- Blizzard's buttons for the live items live inside the scrolling content.
	if kind == "bags" then
		Tiles.Secure.SetParent(C.BAGS, content)
	elseif kind == "bank" then
		Tiles.Secure.SetParent(C.BANK_BAGS, content)
	end

	frame.message = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.message:SetJustifyH("LEFT")
	frame.message:SetTextColor(0.7, 0.7, 0.72)
	-- Classic has no bank tabs to unlock.
	if kind == "bank" and not C.isClassic then
		frame.unlockButton = UnlockButton(content)
		frame.buttons[#frame.buttons + 1] = frame.unlockButton
	end

	frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.footer:SetPoint("BOTTOMLEFT", PAD, 8)

	-- The bags have their bag slots, and on Classic the bank its bank bag
	-- slots, shown and hidden with a button at the start of the footer.
	local bags, barTitle, barText, barIcon
	if kind == "bags" then
		frame.barSetting = "bagBar"
		bags, barIcon = C.BAGS, BagBar.ICON
		barTitle, barText = L["Bags"], L["Show or hide your bag slots, to change bags."]
	elseif kind == "bank" and C.isClassic then
		frame.barSetting = "bankBar"
		bags, barIcon = C.BANK_BAGS, BagBar.BANK_ICON
		barTitle, barText = L["Bank bags"], L["Show or hide the bank's bag slots, to change bank bags or buy more slots."]
	end
	if bags then
		frame.bagBar = BagBar.Create(frame, bags)
		frame.bagBar:SetPoint("BOTTOMLEFT", PAD, FOOTER_H + 4)
		frame.bagToggle = W.IconButton(frame, 18, barIcon, false, function()
			DB.Set(frame.barSetting, not DB.settings[frame.barSetting])
			frame:Refresh()
		end, barTitle, barText)
		frame.bagToggle:SetPoint("BOTTOMLEFT", PAD, 4)
		frame.bagToggle.icon:SetSize(14, 14)
		frame.buttons[#frame.buttons + 1] = frame.bagToggle
		frame.footer:ClearAllPoints()
		frame.footer:SetPoint("LEFT", frame.bagToggle, "RIGHT", 6, 0)
	end

	-- The gold. In the bags, pointing at it lists every character's gold.
	local moneyButton = CreateFrame("Button", nil, frame)
	moneyButton:SetPoint("BOTTOMRIGHT", -PAD, 4)
	moneyButton:SetSize(1, 18)
	frame.money = moneyButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.money:SetPoint("RIGHT")
	frame.moneyButton = moneyButton
	if kind == "bags" then
		moneyButton:EnableMouse(true)
		moneyButton:SetScript("OnEnter", ns.Tooltip.ShowGold)
		moneyButton:SetScript("OnLeave", W.HideTooltip)
		moneyButton:RegisterForDrag("LeftButton")
		moneyButton:SetScript("OnDragStart", StartMoving)
		moneyButton:SetScript("OnDragStop", StopMoving)
	else
		moneyButton:EnableMouse(false)
	end

	frame.QueueRefresh = C.Debounce(0.05, function()
		frame:Refresh()
	end)
	-- Searching every character is not done on every key press.
	frame.QueueFind = C.Debounce(0.2, function()
		frame:Refresh()
	end)
	-- The time left on mail counts down while the window is open.
	if kind == "mail" then
		local elapsed = 0
		frame:SetScript("OnUpdate", function(self, delta)
			elapsed = elapsed + delta
			if elapsed >= 60 then
				elapsed = 0
				self:Refresh()
			end
		end)
	end
	frame:SetScript("OnShow", function(self)
		self:Refresh()
		if self.spec.finder then
			self.searchBox:SetFocus()
		end
	end)
	frame:SetScript("OnHide", function(self)
		self.recent = {}
		if self.OnClosed then
			self:OnClosed()
		end
	end)

	_G.tinsert(_G.UISpecialFrames, spec.frameName)
	frame:Hide()

	Skin.Apply(function(S)
		if S.Shell then
			S.Shell(frame, { bottomBar = FOOTER_H + 4 })
		end
		if S.CloseButton then
			S.CloseButton(close)
		end
		if S.EditBox then
			S.EditBox(frame.searchBox)
		end
		if S.Button then
			S.Button(frame.owner.button)
			for _, button in ipairs(frame.buttons) do
				S.Button(button, { "icon" })
			end
		end
		Skin.Font(frame.footer)
		Skin.Font(frame.money)
		Skin.Font(frame.message)
	end)
	return frame
end
