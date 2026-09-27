local _, ns = ...
local C, DB = ns.C, ns.DB

-- Makes the game use Satchel's windows: the bag keys and bag bar buttons,
-- ToggleAllBags (which EllesmereUI's data bars and Broker plugins call), and
-- the bags opening at a vendor, the bank or the mailbox. Blizzard's own bag
-- and bank windows are moved into a hidden frame, never hidden or changed,
-- which keeps their code (and the bank) working untainted.
--
-- If another bag addon is loaded (EllesmereUI Bags, Bagnon, ElvUI's bags, ...),
-- none of this happens: Satchel still records everything, and its windows open
-- with /satchel or a key binding instead.

local Takeover = {}
ns.Takeover = Takeover

local _G = _G

Takeover.bags = false -- Satchel handles the game's bags
Takeover.bank = false -- Satchel shows the bank instead of Blizzard's window
Takeover.other = nil -- the other bag addon that handles them, by name

local hidden = CreateFrame("Frame")
hidden:Hide()

-- The window (vendor, bank, mailbox, ...) whose opening opened the bags; its
-- closing closes them again. Nil when the player opened them.
local openedBy
local lastToggle

function Takeover.OpenedBy(name)
	openedBy = name
end

function Takeover.CloseIfOpenedBy(name)
	if openedBy and openedBy == name then
		ns.CloseBags()
	end
end

function Takeover.Closed()
	openedBy = nil
end

local function Toggle()
	-- One key press can arrive through two of the hooks below.
	local now = GetTime()
	if lastToggle == now then
		return
	end
	lastToggle = now
	openedBy = nil
	ns.ToggleBags()
end

local function FrameName(frame)
	return frame and frame.GetName and frame:GetName() or nil
end

local function HideBlizzardBags()
	for i = 1, 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame then
			frame:SetParent(hidden)
		end
	end
	if _G.ContainerFrameCombinedBags then
		_G.ContainerFrameCombinedBags:SetParent(hidden)
	end
end

function Takeover.Start()
	Takeover.other = C.OtherBagAddon()
	if Takeover.other or not DB.settings.replaceBags then
		return
	end
	Takeover.bags = true

	_G.ToggleAllBags = Toggle
	local function Hook(name, hook)
		if type(_G[name]) == "function" then
			hooksecurefunc(name, hook)
		end
	end
	Hook("ToggleBackpack", Toggle)
	Hook("ToggleBag", Toggle)
	Hook("ToggleKeyRing", Toggle) -- Classic: the keys are in the bags window
	Hook("OpenBackpack", function()
		ns.OpenBags()
	end)
	Hook("OpenAllBags", function(frame)
		if not ns.bags:IsShown() then
			openedBy = FrameName(frame)
			ns.OpenBags()
		end
	end)
	Hook("CloseAllBags", function(frame)
		local name = FrameName(frame)
		if not name or name == openedBy then
			ns.CloseBags()
		end
	end)
	HideBlizzardBags()

	-- Blizzard's bank window must stay "shown" while at the bank (depositing
	-- asks it which bank is open), so it is only moved out of sight.
	if DB.settings.replaceBank and _G.BankFrame then
		Takeover.bank = true
		_G.BankFrame:SetParent(hidden)
		-- On Forever the bank's "cost of the next tab" display listens for gold
		-- changes from login, and only stops when the bank window hides. Out of
		-- sight it never does, and a gold change away from the bank then hits
		-- an error in Blizzard's code (found by BetterBags, which does the same).
		local panel = _G.BankPanel
		if panel and panel.MoneyDisplay and panel.MoneyDisplay.UnregisterEvent then
			panel.MoneyDisplay:UnregisterEvent("PLAYER_MONEY")
		end
	end
end

-- For buying bank tabs and changing their settings, which only Blizzard's
-- window can do.
function Takeover.ToggleBlizzardBank()
	local bank = _G.BankFrame
	if not (Takeover.bank and bank) then
		return
	end
	if bank:GetParent() == hidden then
		bank:SetParent(UIParent)
		bank:Raise()
	else
		bank:SetParent(hidden)
	end
end

function Takeover.HideBlizzardBank()
	local bank = _G.BankFrame
	if Takeover.bank and bank and bank:GetParent() ~= hidden then
		bank:SetParent(hidden)
	end
end
