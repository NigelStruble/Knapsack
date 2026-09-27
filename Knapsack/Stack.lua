local _, ns = ...
local L, C, Items = ns.L, ns.C, ns.Items

-- Combine stacks: fills up partial stacks of the same item, so they take fewer
-- slots, in the bags or (at the bank) in the bank. Filling (shift-click, at
-- the bank) first fills one side's partial stacks from the other side's stacks
-- of the same item, the bank's from the bags or the bags' from the bank, and
-- then combines what is left on that side.
--
-- The moves are the game's own pick-up and put-down, as if done by hand: out
-- of combat, with nothing on the cursor, in rounds, waiting for the server to
-- finish one round before the next. A round never uses a slot twice. When
-- combining, it pairs the smallest stack of an item with the largest, the next
-- smallest with the next largest, and so on. When filling, it pairs the
-- fullest partial stack with the other side's smallest stack, so the stacks
-- here fill up and the other side's small stacks go first.

local Stack = {}
ns.Stack = Stack

local ipairs, pairs, sort, min, max, format = ipairs, pairs, table.sort, math.min, math.max, string.format

local MAX_ROUNDS = 20
local ROUND_WAIT = 1.5 -- seconds to wait for the server before trying anyway

-- The run in progress: { bags, where, from, fromWhere, round, moves, filled, tried }.
local job

function Stack.Running(where)
	return job ~= nil and (where == nil or job.where == where)
end

-- The stacks of each item that can take more (partial) or all of them, and
-- whether any slot is still locked by a move the server has not finished.
-- Soulbound and unbound stacks of an item never go together, so they are
-- kept apart.
local function Read(bags, partial)
	local groups, locked = {}, false
	for _, bag in ipairs(bags) do
		for slot = 1, C.NumSlots(bag) do
			local info = C.ContainerItem(bag, slot)
			local link = info and C.Clean(info.hyperlink)
			local count = info and C.Clean(info.stackCount)
			if link and count then
				local most = Items.Get(link, info.itemID).maxStack
				if most and most > 1 and (count < most or not partial) then
					if info.isLocked then
						locked = true
					else
						local key = C.Clean(info.isBound) and (link .. "|bound") or link
						local list = groups[key]
						if not list then
							list = {}
							groups[key] = list
						end
						list[#list + 1] = { bag = bag, slot = slot, count = count, max = most, position = bag * 1000 + slot }
					end
				end
			end
		end
	end
	return groups, locked
end

local function Smallest(a, b)
	if a.count ~= b.count then
		return a.count < b.count
	end
	return a.position < b.position
end

local function Fullest(a, b)
	if a.count ~= b.count then
		return a.count > b.count
	end
	return a.position < b.position
end

-- Two stacks the game still will not put together would only swap places:
-- each pair of slots and counts is tried once.
local function Key(key, a, b)
	return format("%s|%d|%d|%d|%d", key, min(a.position, b.position), max(a.position, b.position), min(a.count, b.count), max(a.count, b.count))
end

-- Puts as much of source onto target as fits. Returns 1 for a move made, 0 if
-- this pair was tried before.
local function Move(key, source, target)
	local tried = Key(key, source, target)
	if job.tried[tried] then
		return 0
	end
	job.tried[tried] = true
	local room = target.max - target.count
	if source.count > room then
		C.SplitContainerItem(source.bag, source.slot, room)
	else
		C.PickupContainerItem(source.bag, source.slot)
	end
	C.PickupContainerItem(target.bag, target.slot)
	if GetCursorInfo() then
		ClearCursor() -- whatever is left goes back where it came from
	end
	return 1
end

local function CombineRound(groups)
	local moves = 0
	for key, list in pairs(groups) do
		if #list > 1 then
			sort(list, Smallest)
			local low, high = 1, #list
			while low < high do
				moves = moves + Move(key, list[low], list[high])
				low, high = low + 1, high - 1
			end
		end
	end
	return moves
end

-- targets: this side's partial stacks; sources: the other side's stacks.
local function FillRound(targets, sources)
	local moves = 0
	for key, here in pairs(targets) do
		local there = sources[key]
		if there then
			sort(here, Fullest)
			sort(there, Smallest)
			for i = 1, min(#here, #there) do
				moves = moves + Move(key, there[i], here[i])
			end
		end
	end
	return moves
end

local function Finish(message)
	local done = job
	job = nil
	if message then
		ns.Print(message)
	elseif done.filled > 0 then
		ns.Print(format(L["Filled up stacks in the %s from the %s."], done.where == "bank" and L["bank"] or L["bags"],
			done.fromWhere == "bank" and L["bank"] or L["bags"]))
	elseif done.moves > 0 then
		ns.Print(L["Stacks combined."])
	elseif done.from then
		ns.Print(L["No stacks to fill up or combine."])
	else
		ns.Print(L["No stacks to combine."])
	end
	ns.Send("stacking", false)
end

local Round

local function Wait(round)
	job.waiting = round
	C_Timer.After(ROUND_WAIT, function()
		if job and job.waiting == round then
			Round()
		end
	end)
end

function Round()
	if not job then
		return
	end
	job.waiting = nil
	if InCombatLockdown() then
		Finish(L["Stopped combining stacks: you are in combat."])
		return
	end
	if GetCursorInfo() then
		Finish(L["Stopped combining stacks: you are holding an item."])
		return
	end
	local groups, locked = Read(job.bags, true)
	local moves = 0
	if job.from then
		-- Filling first; combining once nothing more comes from the other side
		-- and the last moves have settled.
		local sources, sourcesLocked = Read(job.from, false)
		locked = locked or sourcesLocked
		moves = FillRound(groups, sources)
		job.filled = job.filled + moves
		if moves == 0 and not locked then
			moves = CombineRound(groups)
		end
	else
		moves = CombineRound(groups)
	end
	job.moves = job.moves + moves
	job.round = job.round + 1
	if moves == 0 and not locked then
		Finish()
	elseif job.round >= MAX_ROUNDS then
		Finish(L["Stopped combining stacks: the game is not answering. Try again."])
	else
		Wait(job.round)
	end
end

-- where: "bags", or "bank" at the bank. fill: first fill that side's partial
-- stacks from the other side (at the bank).
function Stack.Start(where, fill)
	if job or ns.Transfer.Running() then
		return
	end
	if InCombatLockdown() then
		ns.Print(L["Stacks cannot be combined in combat."])
		return
	end
	local bank = ns.Scanner.BankOpen()
	if where == "bank" and not bank then
		ns.Print(L["Stacks in the bank can only be combined at the bank."])
		return
	end
	if fill and not bank then
		ns.Print(L["Stacks in the bags can only be filled up from the bank at the bank."])
		return
	end
	job = { bags = where == "bank" and C.BANK_BAGS or C.BAGS, where = where, round = 0, moves = 0, filled = 0, tried = {} }
	if fill then
		job.fromWhere = where == "bank" and "bags" or "bank"
		job.from = where == "bank" and C.BAGS or C.BANK_BAGS
	end
	ns.Send("stacking", true)
	Round()
end

-- The next round starts as soon as the bags have settled after the last one.
C.On("BAG_UPDATE_DELAYED", function()
	if job and job.waiting then
		local round = job.waiting
		C_Timer.After(0.1, function()
			if job and job.waiting == round then
				Round()
			end
		end)
	end
end)

C.On("PLAYER_REGEN_DISABLED", function()
	if job then
		Finish(L["Stopped combining stacks: you are in combat."])
	end
end)
