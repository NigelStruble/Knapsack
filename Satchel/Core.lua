local ADDON, ns = ...
local L, C, DB = ns.L, ns.C, ns.DB
local Scanner, Tiles = ns.Scanner, ns.Tiles

-- Startup, opening and closing the windows, and the /satchel command.

local _G = _G
local ipairs, lower, format = ipairs, string.lower, string.format

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. L["Satchel"] .. "|r: " .. message)
end
ns.Print = Print

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

function ns.OpenBags()
	local bags = ns.bags
	if bags and not bags:IsShown() then
		bags.ownerKey = DB.PlayerKey()
		bags:Show()
	end
end

function ns.CloseBags()
	if ns.bags then
		ns.bags:Hide()
	end
end

function ns.ToggleBags()
	if ns.bags and ns.bags:IsShown() then
		ns.CloseBags()
	else
		ns.OpenBags()
	end
end

-- Shows whose bank or guild vault a window shows, or closes it if it already
-- shows that.
local function ToggleWindow(window, owner)
	if window:IsShown() and window.ownerKey == owner then
		window:Hide()
		return
	end
	window.ownerKey = owner
	if window:IsShown() then
		window:Refresh()
	else
		window:Show()
	end
end

function ns.ToggleBank(owner)
	ToggleWindow(ns.bank, owner or DB.PlayerKey())
end

function ns.ToggleGuild(key)
	if not key then
		local char = DB.PlayerCharacter()
		key = char and char.guild
	end
	ToggleWindow(ns.guild, key or ns.guild:DefaultOwner())
end

function ns.ToggleMail(owner)
	ToggleWindow(ns.mail, owner or DB.PlayerKey())
end

-- The Find window, searching for text (or what it searched for last).
function ns.OpenFind(text)
	local find = ns.find
	find:Show()
	find:Raise()
	if text and text ~= "" then
		find.searchBox:SetText(text)
	end
	find.searchBox:SetFocus()
end

function ns.ToggleFind()
	if ns.find:IsShown() then
		ns.find:Hide()
	else
		ns.OpenFind()
	end
end

-- Key bindings (Bindings.xml) and the addon compartment on the minimap.
_G.BINDING_HEADER_SATCHEL = L["Satchel"]
_G.BINDING_NAME_SATCHEL_BAGS = L["Bags"]
_G.BINDING_NAME_SATCHEL_BANK = L["Bank"]
_G.BINDING_NAME_SATCHEL_MAIL = L["Mail"]
_G.BINDING_NAME_SATCHEL_GUILD = L["Guild Vault"]
_G.BINDING_NAME_SATCHEL_FIND = L["Find an item on all your characters"]

function _G.Satchel_ToggleBags()
	ns.ToggleBags()
end

function _G.Satchel_ToggleBank()
	ns.ToggleBank()
end

function _G.Satchel_ToggleGuild()
	ns.ToggleGuild()
end

function _G.Satchel_ToggleMail()
	ns.ToggleMail()
end

function _G.Satchel_ToggleFind()
	ns.ToggleFind()
end

function _G.Satchel_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		ns.Options.Toggle()
	else
		ns.ToggleBags()
	end
end

function _G.Satchel_OnAddonCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Satchel"], 1, 1, 1)
	GameTooltip:AddLine(L["Left-click: bags"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: options"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function _G.Satchel_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- Blizzard's item buttons, made ahead of time out of combat
--------------------------------------------------------------------------------

local function PrepareButtons(bags)
	if InCombatLockdown() then
		Tiles.Secure.short = true
		return
	end
	for _, bag in ipairs(bags) do
		local size = C.NumSlots(bag)
		if size > 0 then
			Tiles.Secure.Prepare(bag, size)
		end
	end
end

C.On("PLAYER_REGEN_ENABLED", function()
	if not Tiles.Secure.short then
		return
	end
	Tiles.Secure.short = false
	PrepareButtons(C.BAGS)
	for _, window in ipairs({ ns.bags, ns.bank }) do
		if window:IsShown() then
			window:Refresh()
		end
	end
end)

--------------------------------------------------------------------------------
-- Keeping the windows up to date
--------------------------------------------------------------------------------

local function Windows()
	return { ns.bags, ns.bank, ns.guild, ns.mail, ns.find }
end

local function RefreshAll()
	for _, window in ipairs(Windows()) do
		window:QueueRefresh()
	end
end
ns.RefreshAll = RefreshAll

local function Listen()
	ns.Listen("bags", function(key)
		if ns.bags.ownerKey == key then
			ns.bags:QueueRefresh()
		end
		-- A bigger bag brings new slots: their buttons are made now, while
		-- that is still possible, not when an item lands there in combat.
		if key == DB.PlayerKey() and not InCombatLockdown() then
			PrepareButtons(C.BAGS)
		end
	end)
	ns.Listen("bank", function(key)
		if ns.bank.ownerKey == key then
			ns.bank:QueueRefresh()
		end
	end)
	ns.Listen("guild", function(key)
		if ns.guild.ownerKey == key or not ns.guild.ownerKey then
			ns.guild:QueueRefresh()
		end
		ns.bags:QueueRefresh() -- the Vault button
	end)
	ns.Listen("money", function()
		ns.bags:QueueRefresh()
	end)
	-- Mail sent to another character changes that character's mailbox, and
	-- mail that goes back changes the sender's: the window is drawn again
	-- whoever it shows.
	ns.Listen("mail", function()
		ns.mail:QueueRefresh()
	end)
	-- The Find window shows everything, so any change can change it.
	for _, what in ipairs({ "bags", "bank", "mail", "guild" }) do
		ns.Listen(what, function()
			ns.find:QueueRefresh()
		end)
	end
	ns.Listen("cooldowns", function()
		ns.bags:UpdateCooldowns()
		ns.bank:UpdateCooldowns()
	end)
	for _, what in ipairs({ "items", "categories", "characters", "guilds", "guildChanged" }) do
		ns.Listen(what, RefreshAll)
	end
	ns.Listen("settings", function()
		for _, window in ipairs(Windows()) do
			window:ApplyScale()
			window:QueueRefresh()
		end
	end)
	-- Stacks merge again, or come apart, as a mailbox, trade, auction house,
	-- bank or guild vault opens and closes.
	ns.Listen("panels", function()
		ns.bags:QueueRefresh()
		ns.bank:QueueRefresh()
	end)
	ns.Listen("stacking", function()
		for _, window in ipairs({ ns.bags, ns.bank }) do
			window.combineButton:SetActive(not ns.Stack.Running())
		end
	end)
	-- Borders are sized in screen pixels.
	C.On("UI_SCALE_CHANGED", RefreshAll)
	C.On("DISPLAY_SIZE_CHANGED", RefreshAll)

	-- Bank buttons are made as the bank is drawn, only for the slots in use:
	-- nine full tabs would be close to nine hundred buttons.
	ns.Listen("bankOpened", function()
		if ns.Takeover.bank then
			ns.bank.autoOpened = true
			ns.bank.ownerKey = DB.PlayerKey()
			if ns.bank:IsShown() then
				ns.bank:Refresh()
			else
				ns.bank:Show()
			end
			if not ns.bags:IsShown() then
				ns.Takeover.OpenedBy("BankFrame")
				ns.OpenBags()
			end
		else
			ns.bank:QueueRefresh()
		end
	end)
	ns.Listen("bankClosed", function()
		ns.Takeover.HideBlizzardBank()
		if ns.bank.autoOpened then
			ns.bank.autoOpened = nil
			ns.bank:Hide()
		else
			ns.bank:QueueRefresh()
		end
		ns.Takeover.CloseIfOpenedBy("BankFrame")
	end)
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

C.On("ADDON_LOADED", function(_, name)
	if name == ADDON then
		DB.Load()
		ns.Categories.Normalize()
	end
end)

C.On("PLAYER_LOGIN", function()
	DB.UpdatePlayerInfo()

	ns.bags = ns.Window.Create("bags")
	ns.bank = ns.Window.Create("bank")
	ns.guild = ns.Window.Create("guild")
	ns.mail = ns.Window.Create("mail")
	ns.find = ns.Window.Create("find")
	ns.bags.OnClosed = function()
		C.ClearNewItems()
		ns.Takeover.Closed()
	end
	-- Closing Satchel's bank window ends the visit, like closing Blizzard's.
	ns.bank.OnClosed = function(window)
		window.autoOpened = nil
		if ns.Takeover.bank and Scanner.BankOpen() then
			C.CloseBank()
		end
	end

	-- Each step on its own: one failing must not stop the others.
	local call = _G.securecallfunction or pcall
	call(Listen)
	call(ns.Takeover.Start)
	call(ns.Tooltip.Start)
	call(ns.Mail.Start)
	call(ns.Options.Register)
	C_Timer.After(0.5, function()
		PrepareButtons(C.BAGS)
	end)

	if ns.Takeover.other then
		Print(format(L["%s is handling your bags, so Satchel only records your bank, guild vault and characters. Type /satchel to see them."], ns.Takeover.other))
	end
end)

--------------------------------------------------------------------------------
-- /satchel
--------------------------------------------------------------------------------

-- /satchel charges: every item in the bags whose tooltip mentions charges,
-- the tooltip line as the game gives it (escape codes shown), and the charges
-- Satchel reads from it. For reporting problems.
local function ShowCharges()
	local found = 0
	for _, bag in ipairs(C.BAGS) do
		for slot = 1, C.NumSlots(bag) do
			local info = C.ContainerItem(bag, slot)
			local link = info and C.Clean(info.hyperlink)
			for _, line in ipairs(link and C.BagTooltip(bag, slot) or {}) do
				local text = C.Clean(line.leftText)
				if type(text) == "string" and lower(text):find("charge", 1, true) then
					found = found + 1
					Print(format("%s %d/%d: \"%s\" = %s", link, bag, slot, text:gsub("|", "||"),
						tostring(ns.Items.ChargesIn(text))))
				end
			end
		end
	end
	if found == 0 then
		Print(L["No item in your bags has a tooltip line about charges."])
	end
end

_G.SLASH_SATCHEL1 = "/satchel"
_G.SlashCmdList.SATCHEL = function(message)
	-- The first word is the command; the rest keeps its case (item names).
	local word, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local command = lower(word or "")
	rest = rest or ""
	if command == "" or command == "bags" then
		ns.ToggleBags()
	elseif command == "bank" then
		ns.ToggleBank()
	elseif command == "vault" or command == "guild" then
		ns.ToggleGuild()
	elseif command == "mail" then
		ns.ToggleMail()
	elseif command == "find" or command == "search" then
		ns.OpenFind(rest)
	elseif command == "stack" then
		ns.Stack.Start(lower(rest) == "bank" and "bank" or "bags")
	elseif command == "fill" then
		ns.Stack.Start(lower(rest) == "bank" and "bank" or "bags", true)
	elseif command == "charges" then
		ShowCharges()
	elseif command == "options" or command == "config" then
		ns.Options.Toggle()
	else
		Print(L["commands:"])
		Print("  /satchel - " .. L["bags"])
		Print("  /satchel bank - " .. L["bank"])
		Print("  /satchel mail - " .. L["mail"])
		Print("  /satchel vault - " .. L["guild vault"])
		Print("  /satchel find <name> - " .. L["find an item on all your characters"])
		Print("  /satchel stack - " .. L["combine partial stacks in the bags"])
		Print("  /satchel stack bank - " .. L["combine partial stacks in the bank, at the bank"])
		Print("  /satchel fill - " .. L["fill partial stacks in the bags from the bank, at the bank"])
		Print("  /satchel fill bank - " .. L["fill partial stacks in the bank from the bags, at the bank"])
		Print("  /satchel options - " .. L["options"])
	end
end
