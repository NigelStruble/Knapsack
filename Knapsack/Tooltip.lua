local _, ns = ...
local L, C, DB = ns.L, ns.C, ns.DB

-- Adds how many of an item each of your characters, and each recorded guild
-- vault, holds to item tooltips:
--   Vedek        25 (bags 20, bank 3, mail 2)
--   Knights      40 (guild vault)
-- and, for items shown in Knapsack's windows, the charges and mail details the
-- game's own tooltip leaves out.

local Tooltip = {}
ns.Tooltip = Tooltip

local _G = _G
local pairs, ipairs, format, sort, concat, pcall, wipe = pairs, ipairs, string.format, table.sort, table.concat, pcall, wipe

-- Item counts per source, [source] = { [itemID] = count }, where a source is
-- "bags:Name-Realm", "bank:Name-Realm" or "guild:Guild-Realm". A source is
-- counted again only after it changes, so hovering stays cheap.
local counts = {}

local function Add(items, result)
	for _, item in pairs(items or {}) do
		local id = C.ItemIDFromLink(item.link)
		if id then
			result[id] = (result[id] or 0) + (item.count or 1)
		end
	end
end

-- containers: a character's .bags or .bank, or a guild's .tabs.
local function Counts(source, containers)
	local result = counts[source]
	if not result then
		result = {}
		for _, container in pairs(containers or {}) do
			Add(container.items, result)
		end
		counts[source] = result
	end
	return result
end

-- The lines for an item, as { left, right, r, g, b }, or nil.
function Tooltip.Lines(itemID)
	local player = DB.Player()
	local playerKey, realm = player and player.key, player and player.realmName

	local chars = {}
	for key, char in pairs(DB.characters) do
		local bags = Counts("bags:" .. key, char.bags)[itemID] or 0
		local bank = Counts("bank:" .. key, char.bank)[itemID] or 0
		local mail = ns.Mail.Count(key, itemID)
		if bags + bank + mail > 0 then
			chars[#chars + 1] = { key = key, char = char, bags = bags, bank = bank, mail = mail }
		end
	end
	local guilds = {}
	for key, guild in pairs(DB.guilds) do
		local n = Counts("guild:" .. key, guild.tabs)[itemID] or 0
		if n > 0 then
			guilds[#guilds + 1] = { key = key, guild = guild, count = n }
		end
	end
	if #chars == 0 and #guilds == 0 then
		return nil
	end

	sort(chars, function(a, b)
		if a.key == playerKey or b.key == playerKey then
			return a.key == playerKey
		end
		return a.key < b.key
	end)
	sort(guilds, function(a, b)
		return a.key < b.key
	end)

	local lines, total = {}, 0
	for _, entry in ipairs(chars) do
		local char = entry.char
		local detail = {}
		if entry.bags > 0 then
			detail[#detail + 1] = format(L["bags %d"], entry.bags)
		end
		if entry.bank > 0 then
			detail[#detail + 1] = format(L["bank %d"], entry.bank)
		end
		if entry.mail > 0 then
			detail[#detail + 1] = format(L["mail %d"], entry.mail)
		end
		local name = DB.DisplayName(char) or entry.key
		if char.realm and char.realm ~= realm then
			name = name .. " - " .. char.realm
		end
		local r, g, b = C.ClassColor(char.class)
		local count = entry.bags + entry.bank + entry.mail
		lines[#lines + 1] = { name, format("%d (%s)", count, concat(detail, ", ")), r, g, b }
		total = total + count
	end
	for _, entry in ipairs(guilds) do
		lines[#lines + 1] = { entry.guild.name or entry.key, format("%d (%s)", entry.count, L["guild vault"]), 0.25, 1, 0.25 }
		total = total + entry.count
	end
	if #lines > 1 then
		lines[#lines + 1] = { L["Total"], tostring(total), 1, 0.82, 0 }
	end
	return lines
end

-- The gold of every recorded character, most first, and the total: the
-- tooltip of the gold in the bags window.
function Tooltip.ShowGold(owner)
	local player = DB.Player()
	local playerKey, realm = player and player.key, player and player.realmName
	local list, total = {}, 0
	for key, char in pairs(DB.characters) do
		local money = key == playerKey and GetMoney() or char.money
		if money then
			list[#list + 1] = { key = key, char = char, money = money }
			total = total + money
		end
	end
	sort(list, function(a, b)
		if a.money ~= b.money then
			return a.money > b.money
		end
		return a.key < b.key
	end)

	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 6)
	GameTooltip:SetText(L["Gold"], 1, 1, 1)
	for _, entry in ipairs(list) do
		local char = entry.char
		local name = DB.DisplayName(char) or entry.key
		if char.realm and char.realm ~= realm then
			name = name .. " - " .. char.realm
		end
		local r, g, b = C.ClassColor(char.class)
		GameTooltip:AddDoubleLine(name, C.Money(entry.money), r, g, b, 1, 1, 1)
	end
	if #list > 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["Total"], C.Money(total), 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function AddLines(tooltip, itemID)
	local lines = Tooltip.Lines(itemID)
	if not lines then
		return
	end
	tooltip:AddLine(" ")
	for _, line in ipairs(lines) do
		tooltip:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], 1, 1, 1)
	end
end

local function ChargesText(charges)
	if charges <= 0 then
		return _G.ITEM_SPELL_CHARGES_NONE or L["No charges"]
	end
	return format(_G.ITEM_SPELL_CHARGES or "%d |4Charge:Charges;", charges)
end

-- Charges the game's tooltip leaves out: those of an item recorded from
-- another character's bags or the bank (a link's tooltip has none), and, on a
-- merged tile, those of every item in it.
local function AddCharges(tooltip)
	local rec = ns.Tiles.RecordFor(tooltip:GetOwner())
	if not rec then
		return
	end
	if rec.stacks then
		local list = {}
		for _, stack in ipairs(rec.stacks) do
			if stack.charges then
				list[#list + 1] = stack.charges
			end
		end
		if #list > 1 then
			sort(list)
			local text = format(L["Charges: %s"], concat(list, ", "))
			if rec.live and rec.charges then
				text = text .. "  " .. format(L["(the one with %d is used first)"], rec.charges)
			end
			tooltip:AddLine(text, 1, 1, 1, true)
			return
		end
	end
	if rec.charges and not rec.live then
		tooltip:AddLine(ChargesText(rec.charges), 1, 1, 1)
	end
end

-- Who a mail item is from, and when it goes back.
local function AddMail(tooltip)
	local rec = ns.Tiles.RecordFor(tooltip:GetOwner())
	local mail = rec and rec.mail
	if not mail then
		return
	end
	tooltip:AddLine(" ")
	if mail.sender then
		tooltip:AddLine(format(L["Mail from %s"], mail.sender), 1, 0.82, 0)
	end
	if mail.subject and mail.subject ~= "" then
		tooltip:AddLine(mail.subject, 0.8, 0.8, 0.8, true)
	end
	if (mail.cod or 0) > 0 then
		tooltip:AddLine(format(L["Cash on delivery: %s"], C.Money(mail.cod)), 1, 0.4, 0.4)
	end
	local left = (mail.expires or 0) - time()
	local r, g, b = 0.9, 0.9, 0.9
	if left < 86400 then
		r, g, b = 1, 0.25, 0.25
	elseif left < 3 * 86400 then
		r, g, b = 1, 0.6, 0.1
	end
	if mail.returns then
		tooltip:AddLine(format(L["Goes back to %s in %s"], mail.sender or L["the sender"], C.TimeLeft(left)), r, g, b)
	else
		tooltip:AddLine(format(L["Deleted in %s"], C.TimeLeft(left)), r, g, b)
	end
	if mail.expired then
		tooltip:AddLine(L["Went back to this character, not collected in time."], 0.6, 0.6, 0.6, true)
	elseif mail.sent then
		tooltip:AddLine(format(L["Mailed %s by one of your characters; not seen in the mailbox yet."], C.TimeAgo(mail.sent)), 0.6, 0.6, 0.6, true)
	end
end

function Tooltip.Start()
	ns.Listen("bags", function(key)
		counts["bags:" .. tostring(key)] = nil
	end)
	ns.Listen("bank", function(key)
		counts["bank:" .. tostring(key)] = nil
	end)
	ns.Listen("guild", function(key)
		counts["guild:" .. tostring(key)] = nil
	end)
	ns.Listen("characters", function()
		wipe(counts)
	end)
	ns.Listen("guilds", function()
		wipe(counts)
	end)

	local function Extend(tooltip, itemID)
		if tooltip ~= _G.GameTooltip and tooltip ~= _G.ItemRefTooltip then
			return -- not Knapsack's own scanning tooltip, nor anyone else's
		end
		pcall(AddCharges, tooltip)
		pcall(AddMail, tooltip)
		if DB.settings.tooltipCounts and itemID then
			pcall(AddLines, tooltip, itemID)
		end
	end

	-- Classic clients have TooltipDataProcessor, but it does not work there:
	-- they get OnTooltipSetItem instead.
	local processor = _G.TooltipDataProcessor
	local types = _G.Enum and _G.Enum.TooltipDataType
	if not C.isClassic and processor and processor.AddTooltipPostCall and types and types.Item then
		processor.AddTooltipPostCall(types.Item, function(tooltip, data)
			Extend(tooltip, data and C.Clean(data.id))
		end)
		return
	end
	for _, tooltip in ipairs({ _G.GameTooltip, _G.ItemRefTooltip }) do
		if tooltip and tooltip.HookScript then
			tooltip:HookScript("OnTooltipSetItem", function(self)
				local _, link = self:GetItem()
				Extend(self, C.ItemIDFromLink(C.Clean(link)))
			end)
		end
	end
end
