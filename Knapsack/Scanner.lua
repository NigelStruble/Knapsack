local _, ns = ...
local C, DB = ns.C, ns.DB

-- Reads the bags, bank and guild vault, and keeps a snapshot of each in the
-- saved data, so they can be looked at from other characters and away from
-- the bank.
--
-- A container snapshot:
--   { size = 16, family = 0, items = { [slot] = { link = "...", count = 5, quality = 1 } } }
-- Items with charges also have .charges, the number left, and soulbound items
-- .bound.
-- A character stores .bags and .bank as [bagID] = container (containers have
-- .name, bags and Classic bank bags also the .link of the bag itself, bank
-- tabs an .icon), plus .bagsTime and .bankTime, and on Classic .bankBagSlots,
-- the bank bag slots bought. The mail is in .mail (see Mail.lua). A guild
-- vault stores .tabs[tab] = { name, icon, viewable, items, time }, .money and
-- .time.

local Scanner = {}
ns.Scanner = Scanner

local _G = _G
local ipairs, pairs, next, wipe, time, sort = ipairs, pairs, next, wipe, time, table.sort
local tremove = table.remove

--------------------------------------------------------------------------------
-- Reading containers
--------------------------------------------------------------------------------

-- extra: also note what only matters in the live bags (locked items, quest
-- items); none of it is saved.
local function ReadContainer(bag, extra)
	local size = C.NumSlots(bag)
	local container = { size = size, family = size > 0 and C.BagFamily(bag) or 0, items = {} }
	if size > 0 then
		container.name = C.Clean(C.BagName(bag))
		container.link = C.BagLink(bag) -- the bag itself, if it is one worn in a slot
	end
	for slot = 1, size do
		local info = C.ContainerItem(bag, slot)
		local link = info and C.Clean(info.hyperlink)
		if link then
			local item = { link = link, count = info.stackCount or 1, quality = C.Clean(info.quality) }
			item.charges = ns.Items.Charges(link, info.itemID, C.BagTooltip, bag, slot)
			item.bound = C.Clean(info.isBound) and true or nil -- soulbound, so not Bind on Equip any more
			if extra then
				item.itemID = info.itemID
				item.icon = info.iconFileID
				item.locked = info.isLocked
				local quest = C.QuestInfo(bag, slot)
				if quest then
					item.isQuest = (quest.isQuestItem or quest.questID) and true or false
					item.questStarter = (quest.questID and not quest.isActive) and true or false
				end
			end
			container.items[slot] = item
		end
	end
	return container
end

local function ReadContainers(bags, extra)
	local containers = {}
	for _, bag in ipairs(bags) do
		local container = ReadContainer(bag, extra)
		if container.size > 0 then
			containers[bag] = container
		end
	end
	return containers
end

-- The copy that goes in the saved data, without the live-only fields.
local function Strip(containers)
	local copy = {}
	for bag, container in pairs(containers) do
		local items = {}
		for slot, item in pairs(container.items) do
			items[slot] = { link = item.link, count = item.count, quality = item.quality, charges = item.charges, bound = item.bound }
		end
		copy[bag] = {
			size = container.size,
			family = container.family,
			items = items,
			name = container.name,
			icon = container.icon,
			link = container.link,
		}
	end
	return copy
end
Scanner.Strip = Strip

--------------------------------------------------------------------------------
-- Records: one per item, for windows to sort and draw
--------------------------------------------------------------------------------

function Scanner.Records(containers, live)
	local records = {}
	for bag, container in pairs(containers) do
		for slot, item in pairs(container.items) do
			records[#records + 1] = {
				link = item.link,
				count = item.count or 1,
				quality = item.quality,
				charges = item.charges,
				bound = item.bound,
				itemID = item.itemID,
				icon = item.icon,
				bag = bag,
				slot = slot,
				position = bag * 1000 + slot,
				live = live,
				locked = item.locked,
				isQuest = item.isQuest,
				questStarter = item.questStarter,
			}
		end
	end
	return records
end

function Scanner.GuildRecords(guild)
	local records = {}
	for tab, stored in pairs(guild and guild.tabs or {}) do
		for slot, item in pairs(stored.items or {}) do
			records[#records + 1] = {
				link = item.link,
				count = item.count or 1,
				quality = item.quality,
				tab = tab,
				position = tab * 1000 + slot,
			}
		end
	end
	return records
end

-- Used and total slots of normal bags, and the free slots of each bag family:
-- free[family] = { count, bag, slot, name, family } where bag and slot are the
-- first free one and name is that bag's name. The Classic keyring is left out:
-- it grows by four slots whenever it fills up, so it always has a few free
-- ones, which are not room anything else can use.
function Scanner.Space(containers)
	local used, total, free = 0, 0, {}
	local bags = {}
	for bag in pairs(containers) do
		if bag ~= C.KEYRING then
			bags[#bags + 1] = bag
		end
	end
	sort(bags)
	for _, bag in ipairs(bags) do
		local container = containers[bag]
		local family = container.family or 0
		for slot = 1, container.size or 0 do
			if container.items[slot] then
				if family == 0 then
					used = used + 1
				end
			else
				local entry = free[family]
				if not entry then
					entry = { count = 0, bag = bag, slot = slot, name = container.name, family = family }
					free[family] = entry
				end
				entry.count = entry.count + 1
			end
		end
		if family == 0 then
			total = total + (container.size or 0)
		end
	end
	return used, total, free
end

--------------------------------------------------------------------------------
-- The player's bags
--------------------------------------------------------------------------------

local liveBags
local bagsDirty = true

-- Between leaving the world (a loading screen, or logging out) and entering
-- it again, the client may already have emptied the bags and gold: nothing is
-- recorded then, or a logout would record a character with empty bags.
local inWorld = false

-- The latest read of the player's bags (read again after any change).
function Scanner.LiveBags()
	if bagsDirty or not liveBags then
		liveBags = ReadContainers(C.BAGS, true)
		bagsDirty = false
	end
	return liveBags
end

function Scanner.SaveBags()
	-- The backpack always has slots; none means the bags are not loaded.
	if not inWorld or C.NumSlots(C.BAGS[1]) == 0 then
		return
	end
	local char = DB.PlayerCharacter()
	if not char then
		return
	end
	char.bags = Strip(Scanner.LiveBags())
	char.bagsTime = time()
	ns.Send("bags", DB.PlayerKey())
end

local QueueBags = C.Debounce(0.1, Scanner.SaveBags)

function Scanner.BagsChanged()
	bagsDirty = true
	QueueBags()
end

--------------------------------------------------------------------------------
-- Item panels
--------------------------------------------------------------------------------

-- Windows that take items from the bags one slot at a time: the mailbox's
-- send page, trade, the auction house, the bank and the guild vault. A merged
-- tile only hands over the stack under it, so while one of these is open the
-- live bags show every stack on its own (see Window.lua). "panels" is sent
-- when that changes.
local panels = {}

local function SetPanel(key, open)
	open = open and true or nil
	if panels[key] == open then
		return
	end
	panels[key] = open
	ns.Send("panels")
end

function Scanner.PanelOpen()
	return next(panels) ~= nil
end

-- Only the send page of the mailbox counts. Its frame may load with the
-- mailbox, so it is looked for each time the mailbox opens.
local sendMailHooked = false

local function SendMailFrame()
	local frame = _G.SendMailFrame
	if frame and not sendMailHooked and frame.HookScript then
		sendMailHooked = true
		frame:HookScript("OnShow", function()
			SetPanel("mail", true)
		end)
		frame:HookScript("OnHide", function()
			SetPanel("mail", false)
		end)
	end
	return sendMailHooked and frame or nil
end

C.On("MAIL_SHOW", function()
	local frame = SendMailFrame()
	SetPanel("mail", not frame or frame:IsShown())
end)
C.On("MAIL_CLOSED", function()
	SetPanel("mail", false)
end)
C.On("TRADE_SHOW", function()
	SetPanel("trade", true)
end)
C.On("TRADE_CLOSED", function()
	SetPanel("trade", false)
end)
C.On("AUCTION_HOUSE_SHOW", function()
	SetPanel("auction", true)
end)
C.On("AUCTION_HOUSE_CLOSED", function()
	SetPanel("auction", false)
end)

--------------------------------------------------------------------------------
-- The bank
--------------------------------------------------------------------------------

local bankOpen = false

function Scanner.BankOpen()
	return bankOpen
end

-- The player's bank tabs, read now. Only meaningful at the bank.
function Scanner.LiveBank()
	local containers = ReadContainers(C.BANK_BAGS, true)
	local tabs = C.BankTabs()
	for bag, container in pairs(containers) do
		local tab = tabs[bag]
		if tab then
			container.name, container.icon = tab.name, tab.icon
		end
	end
	return containers
end

-- The bank as the client has it right now, at the bank: "ready", "loading"
-- (its tabs have not arrived yet: a moment after the bank opens) or "none"
-- (the character has no bank tab yet: on Forever even the free first one has
-- to be unlocked). Nil away from the bank. Until the bank has been open a
-- couple of seconds, no tabs means they have not arrived.
local GRACE = 2
local bankOpenedAt = 0

function Scanner.BankState()
	if not bankOpen then
		return nil
	end
	for _, bag in ipairs(C.BANK_BAGS) do
		if C.NumSlots(bag) > 0 then
			return "ready"
		end
	end
	if GetTime() - bankOpenedAt >= GRACE and C.BankTabCount() == 0 then
		return "none"
	end
	return "loading"
end

function Scanner.SaveBank()
	-- Away from the bank the client does not know its contents: never save then.
	-- Nor while it is still loading: that would record an empty bank.
	if not bankOpen or not inWorld or Scanner.BankState() == "loading" then
		return
	end
	local char = DB.PlayerCharacter()
	if not char then
		return
	end
	char.bank = Strip(Scanner.LiveBank())
	char.bankTime = time()
	char.bankBagSlots = C.BankBagSlots()
	ns.Send("bank", DB.PlayerKey())
end

local QueueBank = C.Debounce(0.1, Scanner.SaveBank)

-- The bank's tabs can arrive a moment after the bank opens: it is looked at
-- again until they have (up to ten seconds), then recorded and redrawn.
local function WaitForBank(tries)
	if not bankOpen then
		return
	end
	if Scanner.BankState() == "loading" and tries > 0 then
		C_Timer.After(0.5, function()
			WaitForBank(tries - 1)
		end)
	else
		Scanner.SaveBank()
		ns.Send("bank", DB.PlayerKey())
	end
end

local function BankOpened()
	if bankOpen then
		return
	end
	bankOpen = true
	bankOpenedAt = GetTime()
	SetPanel("bank", true)
	ns.Send("bankOpened")
	QueueBank()
	WaitForBank(20)
	-- Items can follow a moment after the tabs.
	C_Timer.After(1.5, Scanner.SaveBank)
end

local function BankClosed()
	if not bankOpen then
		return
	end
	bankOpen = false
	SetPanel("bank", false)
	ns.Send("bankClosed")
end

--------------------------------------------------------------------------------
-- The guild vault
--------------------------------------------------------------------------------

-- The server only sends a vault tab when asked (QueryGuildBankTab), and only
-- while the vault is open. Every viewable tab is asked for, one after another;
-- a tab is saved once it has arrived.

local guildOpen = false
local tabsLoaded = {} -- [tab] = true once the server has sent it this visit
local queriedAt = {} -- [tab] = GetTime() of our request
local queue = {}
local waitingTab

function Scanner.GuildOpen()
	return guildOpen
end

function Scanner.SaveGuild()
	if not guildOpen or not inWorld then
		return
	end
	local key = DB.PlayerGuildKey()
	if not key then
		return
	end
	local guild = DB.Guild(key, true)
	guild.name = C.Clean((GetGuildInfo("player"))) or guild.name
	local player = DB.Player()
	guild.realm = player and player.realmName or guild.realm
	guild.faction = UnitFactionGroup("player")
	guild.money = C.Clean(GetGuildBankMoney()) or guild.money
	guild.time = time()
	guild.tabs = guild.tabs or {}

	local numTabs = GetNumGuildBankTabs() or 0
	for tab = 1, numTabs do
		local name, icon, viewable = GetGuildBankTabInfo(tab)
		local stored = guild.tabs[tab] or {}
		guild.tabs[tab] = stored
		stored.name, stored.icon, stored.viewable = name, icon, viewable and true or false
		if viewable and tabsLoaded[tab] then
			local items, count = {}, 0
			for slot = 1, C.GUILD_BANK_SLOTS do
				local link = C.Clean(GetGuildBankItemLink(tab, slot))
				if link then
					local _, stack, _, _, quality = GetGuildBankItemInfo(tab, slot)
					items[slot] = { link = link, count = stack or 1, quality = C.Clean(quality) }
					count = count + 1
				end
			end
			-- An empty read just after asking may only mean the tab has not
			-- arrived yet; keep the old snapshot until the answer is trusted.
			local settled = GetTime() - (queriedAt[tab] or 0) >= 2
			if count > 0 or settled or not stored.items or not next(stored.items) then
				stored.items = items
				stored.time = time()
			end
		end
	end
	for tab = #guild.tabs, numTabs + 1, -1 do
		guild.tabs[tab] = nil
	end

	local char = DB.PlayerCharacter()
	if char then
		char.guild = key
	end
	ns.Send("guild", key)
end

local QueueGuild = C.Debounce(0.2, Scanner.SaveGuild)

local function QueryNext()
	waitingTab = nil
	if not guildOpen then
		return
	end
	local tab = tremove(queue, 1)
	if not tab then
		return
	end
	waitingTab = tab
	queriedAt[tab] = GetTime()
	QueryGuildBankTab(tab)
	-- If the server never answers, move on.
	C_Timer.After(3, function()
		if waitingTab == tab then
			QueryNext()
		end
	end)
end

local function GuildOpened()
	if guildOpen or not C.hasGuildBank then
		return
	end
	guildOpen = true
	SetPanel("guild", true)
	wipe(tabsLoaded)
	wipe(queriedAt)
	wipe(queue)
	for tab = 1, GetNumGuildBankTabs() or 0 do
		local _, _, viewable = GetGuildBankTabInfo(tab)
		if viewable then
			queue[#queue + 1] = tab
		end
	end
	QueryNext()
	-- Settled reads of every asked tab.
	C_Timer.After(2.5, QueueGuild)
end

local function GuildClosed()
	guildOpen = false
	SetPanel("guild", false)
	waitingTab = nil
	wipe(queue)
end

local function GuildSlotsChanged()
	if not guildOpen then
		return
	end
	local current = _G.GetCurrentGuildBankTab and _G.GetCurrentGuildBankTab()
	if current and current > 0 then
		tabsLoaded[current] = true -- the tab the game's window shows is loaded
	end
	if waitingTab then
		tabsLoaded[waitingTab] = true
		waitingTab = false
		C_Timer.After(0.3, QueryNext)
	end
	QueueGuild()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

C.On("PLAYER_ENTERING_WORLD", function()
	inWorld = true
	DB.UpdatePlayerInfo()
	Scanner.BagsChanged()
end)

C.On("PLAYER_LEAVING_WORLD", function()
	inWorld = false
end)

C.On("BAG_UPDATE", function(_, bag)
	if C.isBag[bag] then
		Scanner.BagsChanged()
	elseif C.isBankBag[bag] and bankOpen then
		QueueBank()
	end
end)

C.On("BAG_UPDATE_DELAYED", function()
	Scanner.BagsChanged()
	if bankOpen then
		QueueBank()
	end
end)

C.On("ITEM_LOCK_CHANGED", function(_, bag)
	if bag and C.isBankBag[bag] then
		if bankOpen then
			QueueBank()
		end
	else
		Scanner.BagsChanged()
	end
end)

-- Using up a charge may not change anything else in the bags, so after the
-- player casts the spell of an item with charges the bags are read again.
do
	local casts = CreateFrame("Frame")
	if pcall(casts.RegisterUnitEvent, casts, "UNIT_SPELLCAST_SUCCEEDED", "player") then
		casts:SetScript("OnEvent", function(_, _, unit, _, spellID)
			if unit == "player" and ns.Items.IsChargeSpell(C.Clean(spellID)) then
				C_Timer.After(0.5, Scanner.BagsChanged)
			end
		end)
	end
end

-- Items that had not loaded when the bags were read (their charges could not
-- be read yet) are read again once they have.
ns.Listen("items", function()
	Scanner.BagsChanged()
	if bankOpen then
		QueueBank()
	end
end)

C.On("BAG_NEW_ITEMS_UPDATED", Scanner.BagsChanged)
C.On("BAG_CONTAINER_UPDATE", Scanner.BagsChanged)
C.On("BAG_UPDATE_COOLDOWN", function()
	ns.Send("cooldowns")
end)

C.On("PLAYER_MONEY", function()
	local char = inWorld and DB.PlayerCharacter()
	if char then
		char.money = GetMoney()
		ns.Send("money", DB.PlayerKey())
	end
end)

C.On("PLAYER_LEVEL_UP", function(_, level)
	local char = DB.PlayerCharacter()
	if char then
		char.level = C.Clean(level) or UnitLevel("player")
	end
end)

C.On("PLAYER_GUILD_UPDATE", function(_, unit)
	if inWorld and (unit == nil or unit == "player") then
		DB.UpdatePlayerInfo()
		ns.Send("guildChanged")
	end
end)

-- Nothing else is recorded at logout: by then the bags are empty and the gold
-- is 0. Every change was recorded as it happened.
C.On("PLAYER_LOGOUT", function()
	local char = DB.PlayerCharacter()
	if char then
		char.seen = time()
	end
end)

C.On("BANKFRAME_OPENED", BankOpened)
C.On("BANKFRAME_CLOSED", BankClosed)
C.On("PLAYERBANKSLOTS_CHANGED", function()
	if bankOpen then
		QueueBank()
	end
end)
-- Classic: a bank bag slot bought, or a bank bag put in or taken out.
C.On("PLAYERBANKBAGSLOTS_CHANGED", function()
	if bankOpen then
		QueueBank()
	end
end)
-- A tab bought or unlocked: recorded, and the bank window drawn again even
-- if the new tab is still empty.
C.On("BANK_TABS_CHANGED", function()
	if bankOpen then
		QueueBank()
		ns.Send("bank", DB.PlayerKey())
	end
end)
C.On("BANK_TAB_SETTINGS_UPDATED", function()
	if bankOpen then
		QueueBank()
	end
end)

C.On("GUILDBANKFRAME_OPENED", GuildOpened)
C.On("GUILDBANKFRAME_CLOSED", GuildClosed)
C.On("GUILDBANKBAGSLOTS_CHANGED", GuildSlotsChanged)
C.On("GUILDBANK_UPDATE_MONEY", function()
	if guildOpen then
		QueueGuild()
	end
end)
C.On("GUILDBANK_UPDATE_TABS", function()
	if guildOpen then
		QueueGuild()
	end
end)

C.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, kind)
	kind = C.Clean(kind)
	if kind == nil then
		return
	end
	if kind == C.BANKER then
		BankOpened()
	elseif kind == C.GUILD_BANKER then
		GuildOpened()
	end
end)

C.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, kind)
	kind = C.Clean(kind)
	if kind == nil then
		return
	end
	if kind == C.BANKER then
		BankClosed()
	elseif kind == C.GUILD_BANKER then
		GuildClosed()
	end
end)
