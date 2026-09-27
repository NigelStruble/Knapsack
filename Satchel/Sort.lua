local _, ns = ...

-- Order of the items inside a section. Every comparison ends on the item's
-- position (bag and slot), so equal items never swap places between redraws.
--
-- Records are sorted on fields filled in by the window before sorting:
--   sortQuality  quality, or -1 while unknown
--   sortName     lower-case name ("" while unknown)
--   sortClass    item class, sortSub subclass (99 while unknown)
--   count        stack size
--   value        vendor value of the whole stack, or nil while unknown
--   position     bag * 1000 + slot (tab * 1000 + slot in the guild vault)
--   expires      when a mail goes back or is deleted (mail only)

local Sort = {}
ns.Sort = Sort

local sort = table.sort

local function Tail(a, b)
	if a.count ~= b.count then
		return a.count > b.count
	end
	return a.position < b.position
end

local COMPARE = {}

-- Best quality first, then by type and name.
COMPARE.quality = function(a, b)
	if a.sortQuality ~= b.sortQuality then
		return a.sortQuality > b.sortQuality
	end
	if a.sortClass ~= b.sortClass then
		return a.sortClass < b.sortClass
	end
	if a.sortSub ~= b.sortSub then
		return a.sortSub < b.sortSub
	end
	if a.sortName ~= b.sortName then
		return a.sortName < b.sortName
	end
	return Tail(a, b)
end

COMPARE.name = function(a, b)
	if a.sortName ~= b.sortName then
		return a.sortName < b.sortName
	end
	if a.sortQuality ~= b.sortQuality then
		return a.sortQuality > b.sortQuality
	end
	return Tail(a, b)
end

COMPARE.type = function(a, b)
	if a.sortClass ~= b.sortClass then
		return a.sortClass < b.sortClass
	end
	if a.sortSub ~= b.sortSub then
		return a.sortSub < b.sortSub
	end
	if a.sortQuality ~= b.sortQuality then
		return a.sortQuality > b.sortQuality
	end
	if a.sortName ~= b.sortName then
		return a.sortName < b.sortName
	end
	return Tail(a, b)
end

-- Cheapest stack first, so the item to throw away is always the first one.
-- Items whose price the client has not loaded yet go last until it arrives.
COMPARE.value = function(a, b)
	local va, vb = a.value, b.value
	if va ~= vb then
		if va == nil then
			return false
		elseif vb == nil then
			return true
		end
		return va < vb
	end
	if a.sortName ~= b.sortName then
		return a.sortName < b.sortName
	end
	return Tail(a, b)
end

-- Guild vault tabs keep the order the guild arranged them in.
COMPARE.position = function(a, b)
	return a.position < b.position
end

-- Mail: what goes back (or is deleted) soonest first.
COMPARE.expires = function(a, b)
	local ea, eb = a.expires or 0, b.expires or 0
	if ea ~= eb then
		return ea < eb
	end
	return COMPARE.quality(a, b)
end

Sort.MODES = { "quality", "name", "type" }

function Sort.Items(list, mode)
	sort(list, COMPARE[mode] or COMPARE.quality)
end
