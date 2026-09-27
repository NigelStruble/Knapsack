local _, ns = ...
local L, C, DB, W, Items = ns.L, ns.C, ns.DB, ns.W, ns.Items

-- Moving a whole category at once, from a category title's right-click menu:
--   at the bank     "Put all in the bank" (bags) and "Take all out of the
--                   bank" (bank)
--   at a mailbox    "Mail all to" one of your characters, a mail at a time
-- Moves are the game's own pick-up and put-down, as if by hand (like
-- Stack.lua): a batch at a time, waiting for the server between batches, and
-- they stop in combat or when something is picked up.

local Transfer = {}
ns.Transfer = Transfer

local ipairs, format, floor, ceil, insert = ipairs, string.format, math.floor, math.ceil, table.insert

local BATCH = 12 -- items moved per round
local ROUND_WAIT = 1.5 -- seconds to wait for the server before looking anyway
local SEND_WAIT = 30 -- seconds to wait for a mail to go
local MAX_ROUNDS = 40
local MAX_TRIES = 3 -- times an item is tried before it is left where it is

local job -- the move in progress

function Transfer.Running()
	return job ~= nil
end

local function Finish(message)
	job = nil
	if message then
		ns.Print(message)
	end
	ns.Send("transfer", false)
end

-- The items behind a window section: { bag, slot, link, bound }, every stack
-- of a merged tile included.
local function ItemsOf(section)
	local items = {}
	for _, rec in ipairs(section.records or {}) do
		for _, stack in ipairs(rec.stacks or { rec }) do
			if stack.bag and stack.slot then
				items[#items + 1] = { bag = stack.bag, slot = stack.slot, link = stack.link, bound = stack.bound, tries = 0 }
			end
		end
	end
	return items
end
Transfer.ItemsOf = ItemsOf

-- The item still in its slot, and free to move: its container info.
local function StillThere(item)
	local info = C.ContainerItem(item.bag, item.slot)
	if info and C.Clean(info.hyperlink) == item.link then
		return info
	end
	return nil
end

local function Blocked()
	if InCombatLockdown() then
		return L["Stopped moving items: you are in combat."]
	elseif GetCursorInfo() then
		return L["Stopped moving items: you are holding an item."]
	end
	return nil
end

--------------------------------------------------------------------------------
-- Between bags and bank
--------------------------------------------------------------------------------

-- Special bags only take some items (quivers take arrows, soul bags soul
-- shards): an item's family has a bit in common with the bag's.
local function SharesBit(a, b)
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then
			return true
		end
		a, b = floor(a / 2), floor(b / 2)
	end
	return false
end

local function ItemFamily(itemID)
	local get = _G.C_Item and _G.C_Item.GetItemFamily or _G.GetItemFamily
	local ok, family = pcall(get, itemID)
	return ok and C.Clean(family) or 0
end

-- The free slots and partial stacks of the containers moved into.
local function Room(bags)
	local free, partial = {}, {}
	for _, bag in ipairs(bags) do
		local size = C.NumSlots(bag)
		if size > 0 then
			local family = C.BagFamily(bag)
			for slot = 1, size do
				local info = C.ContainerItem(bag, slot)
				local link = info and C.Clean(info.hyperlink)
				if not info then
					free[#free + 1] = { bag = bag, slot = slot, family = family }
				elseif link and not info.isLocked then
					local most = Items.Get(link, info.itemID).maxStack
					local count = C.Clean(info.stackCount) or 1
					if most and count < most then
						partial[link] = partial[link] or {}
						insert(partial[link], { bag = bag, slot = slot, room = most - count })
					end
				end
			end
		end
	end
	return free, partial
end

-- Where an item goes: onto a partial stack of it with room for all of it, or
-- an empty slot that takes it (a special bag that takes it first).
local function Target(free, partial, link, count, itemID)
	for _, stack in ipairs(partial[link] or {}) do
		if stack.room >= count then
			stack.room = 0 -- one item per stack a round
			return stack
		end
	end
	local family = ItemFamily(itemID)
	local plain
	for i, slot in ipairs(free) do
		if slot.family ~= 0 and family > 0 and SharesBit(family, slot.family) then
			return table.remove(free, i)
		elseif slot.family == 0 and not plain then
			plain = i
		end
	end
	return plain and table.remove(free, plain) or nil
end

local MoveRound

local function Wait(round, next)
	job.waiting = round
	C_Timer.After(ROUND_WAIT, function()
		if job and job.waiting == round then
			next()
		end
	end)
end

function MoveRound()
	if not job then
		return
	end
	job.waiting = nil
	local blocked = Blocked()
	if blocked then
		Finish(blocked)
		return
	end
	if not ns.Scanner.BankOpen() then
		Finish(L["Stopped moving items: the bank closed."])
		return
	end
	-- Right after the bank opens its tabs may not be there yet: wait for them.
	if job.toBank and ns.Scanner.BankState() == "loading" then
		job.round = job.round + 1
		if job.round >= 10 then
			Finish(L["The bank did not finish loading. Try again in a moment."])
		else
			Wait(job.round, MoveRound)
		end
		return
	end
	local free, partial = Room(job.targets)
	local left, moved, noRoom = {}, 0, 0
	for _, item in ipairs(job.items) do
		local info = StillThere(item)
		if not info then
			if item.tries > 0 then
				job.moved = job.moved + 1 -- it went
			end
		elseif info.isLocked or moved >= BATCH then
			left[#left + 1] = item
		elseif item.tries >= MAX_TRIES then
			job.failed = job.failed + 1
		else
			local target = Target(free, partial, item.link, C.Clean(info.stackCount) or 1, info.itemID)
			if target then
				C.PickupContainerItem(item.bag, item.slot)
				C.PickupContainerItem(target.bag, target.slot)
				if GetCursorInfo() then
					ClearCursor() -- it goes back where it was
				end
				item.tries = item.tries + 1
				moved = moved + 1
				left[#left + 1] = item
			else
				noRoom = noRoom + 1
			end
		end
	end
	job.items = left
	job.round = job.round + 1
	if #left == 0 or (moved == 0 and noRoom > 0) or job.round >= MAX_ROUNDS then
		local message = format(L["Moved %d items to the %s."], job.moved, job.where)
		if noRoom > 0 then
			message = message .. " " .. format(L["No room for %d more."], noRoom)
		elseif job.failed > 0 or #left > 0 then
			message = message .. " " .. format(L["%d could not be moved."], job.failed + #left)
		end
		Finish(message)
		return
	end
	Wait(job.round, MoveRound)
end

-- Moves items into the given containers: into the bank at the bank, or back
-- into the bags. where names them for the message.
function Transfer.Move(items, targets, where)
	if job or ns.Stack.Running() then
		return
	end
	local blocked = Blocked()
	if blocked or #items == 0 then
		if blocked then
			ns.Print(blocked)
		end
		return
	end
	local toBank = targets == C.BANK_BAGS
	if toBank and ns.Scanner.BankState() == "none" then
		ns.Print(L["This character has no bank tab yet: unlock it in the bank window first."])
		return
	end
	job = { kind = "move", items = items, targets = targets, where = where, toBank = toBank, round = 0, moved = 0, failed = 0 }
	ns.Send("transfer", true)
	MoveRound()
end

--------------------------------------------------------------------------------
-- Into the mail
--------------------------------------------------------------------------------

local function MaxAttachments()
	return _G.ATTACHMENTS_MAX_SEND or 12
end

local MailRound

-- Sends what is attached, then waits for the game to say it went.
local function SendNow()
	if not job then
		return
	end
	local attached = 0
	for index = 1, MaxAttachments() do
		if GetSendMailItem(index) then
			attached = attached + 1
		end
	end
	if attached == 0 then
		Finish(format(L["Mailed %d items to %s."], job.sent, job.recipient))
		return
	end
	job.attached = attached
	job.sending = (job.sending or 0) + 1
	local sending = job.sending
	SendMail(job.recipient, job.subject, "")
	C_Timer.After(SEND_WAIT, function()
		if job and job.sending == sending then
			Finish(L["Stopped mailing: the mail was not sent."])
		end
	end)
end

function MailRound()
	if not job then
		return
	end
	local blocked = Blocked()
	if blocked then
		Finish(blocked)
		return
	end
	if not ns.Mail.IsOpen() then
		Finish(L["Stopped mailing: the mailbox closed."])
		return
	end
	local index, max, left = 1, MaxAttachments(), {}
	for _, item in ipairs(job.items) do
		while index <= max and GetSendMailItem(index) do
			index = index + 1
		end
		local info = StillThere(item)
		if info and (index > max or info.isLocked) then
			left[#left + 1] = item -- the next mail
		elseif info then
			C.PickupContainerItem(item.bag, item.slot)
			ClickSendMailItemButton(index)
			if GetCursorInfo() then
				ClearCursor() -- the game would not take it (soulbound, conjured)
				job.refused = job.refused + 1
			else
				index = index + 1
			end
		end
	end
	job.items = left
	-- Give the attachments a moment to arrive, then send.
	C_Timer.After(0.5, SendNow)
end

-- Mails items to one of your characters: recipient as the game takes it
-- ("Vedex Vicious"), subject the category's name.
function Transfer.Mail(items, recipient, subject)
	if job or ns.Stack.Running() then
		return
	end
	local blocked = Blocked()
	if blocked then
		ns.Print(blocked)
		return
	end
	-- Only these items go: not something already on the mail being written.
	for index = 1, MaxAttachments() do
		if GetSendMailItem(index) then
			ns.Print(L["Send or clear the mail you are writing first."])
			return
		end
	end
	job = { kind = "mail", items = items, recipient = recipient, subject = subject, sent = 0, refused = 0 }
	ns.Send("transfer", true)
	MailRound()
end

C.On("MAIL_SEND_SUCCESS", function()
	if not (job and job.kind == "mail" and job.attached) then
		return
	end
	job.sent = job.sent + job.attached
	job.attached, job.sending = nil, nil
	if #job.items > 0 then
		C_Timer.After(0.5, MailRound)
	else
		local message = format(L["Mailed %d items to %s."], job.sent, job.recipient)
		if job.refused > 0 then
			message = message .. " " .. format(L["%d could not be mailed."], job.refused)
		end
		Finish(message)
	end
end)

C.On("MAIL_FAILED", function()
	if job and job.kind == "mail" and job.attached then
		Finish(L["Stopped mailing: the game would not send the mail."])
	end
end)

C.On("MAIL_CLOSED", function()
	if job and job.kind == "mail" then
		Finish(L["Stopped mailing: the mailbox closed."])
	end
end)

C.On("PLAYER_REGEN_DISABLED", function()
	if job then
		Finish(L["Stopped moving items: you are in combat."])
	end
end)

-- The next round starts as soon as the bags have settled after the last one.
C.On("BAG_UPDATE_DELAYED", function()
	if job and job.kind == "move" and job.waiting then
		local round = job.waiting
		C_Timer.After(0.1, function()
			if job and job.waiting == round then
				MoveRound()
			end
		end)
	end
end)

--------------------------------------------------------------------------------
-- The category menu
--------------------------------------------------------------------------------

-- Your characters mail can go to from here: same realm and faction.
local function MailChoices()
	local player = DB.Player()
	local me = DB.PlayerCharacter()
	local choices = {}
	if not player then
		return choices
	end
	for _, entry in ipairs(DB.CharacterList()) do
		local char = entry.char
		local realm = entry.key:match("%-(.+)$")
		if entry.key ~= player.key and char.name and realm == player.realm
			and (not char.faction or not me or not me.faction or char.faction == me.faction) then
			choices[#choices + 1] = {
				key = entry.key,
				name = DB.FullName(char),
				text = C.ColorText(DB.DisplayName(char), C.ClassColor(char.class)),
			}
		end
	end
	return choices
end

local function ConfirmMail(section, choice)
	local items = {}
	for _, item in ipairs(ItemsOf(section)) do
		if not item.bound then
			items[#items + 1] = item
		end
	end
	if #items == 0 then
		ns.Print(format(L["Nothing in %s can be mailed: it is all soulbound."], section.title))
		return
	end
	W.Confirm(format(L["Mail %d items from %s to %s? That takes %d mails."], #items, section.title, choice.text,
		ceil(#items / MaxAttachments())), function()
		Transfer.Mail(items, choice.name, section.title)
	end)
end

-- Adds the moves that make sense here to a category title's menu. Returns
-- true if it added any.
function Transfer.AddToMenu(root, window, section)
	if not window.live or job then
		return false
	end
	local added = false
	if ns.Scanner.BankOpen() then
		if window.kind == "bags" then
			root:CreateButton(L["Put all in the bank"], function()
				Transfer.Move(ItemsOf(section), C.BANK_BAGS, L["bank"])
			end)
			added = true
		elseif window.kind == "bank" then
			root:CreateButton(L["Take all out of the bank"], function()
				Transfer.Move(ItemsOf(section), C.BAGS, L["bags"])
			end)
			added = true
		end
	end
	if window.kind == "bags" and ns.Mail.IsOpen() then
		local choices = MailChoices()
		if #choices > 0 then
			local mailTo = root:CreateButton(L["Mail all to"])
			for _, choice in ipairs(choices) do
				mailTo:CreateButton(choice.text, function()
					ConfirmMail(section, choice)
				end)
			end
			added = true
		end
	end
	return added
end
