local ADDON, ns = ...
local W = ns.W

-- Matches EllesmereUI's look through its skinning API (SKINNING_API.md in the
-- EllesmereUI folder). Without EllesmereUI, or with its third-party skinning
-- turned off for Satchel, nothing here runs and the flat default look stays.

local Skin = {}
ns.Skin = Skin

local ipairs, pcall, wipe = ipairs, pcall, wipe

local S -- EllesmereUI's skin primitives, once it hands them over
local waiting = {} -- skin functions for frames built before that

-- A failing skin call must never break a window.
local function Try(fn, ...)
	local ok = pcall(fn, ...)
	return ok
end

-- fn(S) runs now if EllesmereUI's skin is available, or as soon as it is.
function Skin.Apply(fn)
	if S then
		Try(fn, S)
	else
		waiting[#waiting + 1] = fn
	end
end

function Skin.Active()
	return S ~= nil
end

local function TakeAccent()
	if S and S.GetAccentColor then
		local ok, r, g, b = pcall(S.GetAccentColor)
		if ok and r then
			W.SetAccent(r, g, b)
		end
	end
end

-- Re-fonts a FontString to the user's EllesmereUI font, if there is one.
function Skin.Font(fontString)
	if S and S.Font then
		Try(S.Font, fontString)
	end
end

if EllesmereUI and EllesmereUI.RegisterSkin then
	EllesmereUI.RegisterSkin(ADDON, function(skin)
		S = skin
		TakeAccent()
		for _, fn in ipairs(waiting) do
			Try(fn, S)
		end
		wipe(waiting)
		if S.OnLooksChanged then
			Try(S.OnLooksChanged, function()
				TakeAccent()
				ns.Send("looks")
			end)
		end
	end)
end
