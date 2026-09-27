-- Runs Knapsack against the mock client in tests/mock_wow.lua.
-- Usage, from the repository root:  lua5.1 tests/run_tests.lua

package.path = "tests/?.lua;" .. package.path
local Mock = require("mock_wow")

local ADDON_DIR = "Knapsack"
local ADDON = "Knapsack"
local passed, failed = 0, 0
local current

local function check(condition, message, ...)
	if condition then
		passed = passed + 1
	else
		failed = failed + 1
		print(("    FAIL [%s] " .. message):format(current, ...))
	end
	return condition
end

local function equal(actual, expected, what)
	return check(actual == expected, "%s: expected %s, got %s", what, tostring(expected), tostring(actual))
end

local function test(name, func)
	current = name
	local before = failed
	local ok, err = xpcall(func, debug.traceback)
	if not ok then
		failed = failed + 1
		print("    ERROR " .. tostring(err))
	end
	print(((ok and failed == before) and "ok     " or "FAILED ") .. name)
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function StandardBags(state)
	state.containers[0] = {
		size = 16,
		name = "Backpack",
		items = {
			[1] = { id = 6948 }, -- Hearthstone: Miscellaneous
			[2] = { id = 2589, count = 20 }, -- Linen Cloth: Trade Goods
			[3] = { id = 858, count = 5 }, -- Lesser Healing Potion: Consumables
			[4] = { id = 5635, count = 3 }, -- Sharp Claw: junk, 105c
			[5] = { id = 4865, count = 10 }, -- Ruined Pelt: junk, 50c
			[6] = { id = 3300 }, -- Rabbit's Foot: junk, 20c
			[7] = { id = 2210 }, -- Battered Buckler: grey armor, junk, 3c
			[8] = { id = 12345 }, -- green sword: Equipment
			[9] = { id = 11000, quest = true, questID = 123, questActive = false }, -- starts a quest
		},
	}
	state.containers[1] = { size = 16, name = "Linen Bag", items = { [1] = { id = 4540, count = 4 } } }
	state.containers[2] = { size = 20, family = 1, name = "Light Quiver", items = { [1] = { id = 2512, count = 200 } } }
end

local function Start(setup, options)
	local env, state = Mock.New(options)
	StandardBags(state)
	if setup then
		setup(env, state)
	end
	env.KnapsackDB = state.saved
	local ns = Mock.LoadAddon(env, state, ADDON_DIR, ADDON)
	Mock.Fire(state, "ADDON_LOADED", ADDON)
	Mock.Fire(state, "PLAYER_LOGIN")
	Mock.Fire(state, "PLAYER_ENTERING_WORLD", true, false)
	Mock.Advance(state, 1)
	return { env = env, state = state, ns = ns }
end

local function NoErrors(client)
	for _, err in ipairs(client.state.errors) do
		print("    Lua error: " .. err)
	end
	for _, violation in ipairs(client.state.violations) do
		print("    Taint rule broken: " .. violation)
	end
	check(#client.state.errors == 0, "%d Lua error(s)", #client.state.errors)
	check(#client.state.violations == 0, "%d taint rule(s) broken", #client.state.violations)
	client.state.errors = {}
end

local function OpenBags(client)
	client.state.time = client.state.time + 1
	client.env.ToggleAllBags()
	Mock.Advance(client.state, 0.2)
	return client.ns.bags
end

-- Section titles of a window, in order, without counts and money.
local function Titles(window)
	local titles = {}
	for i, title in ipairs(window.titles) do
		titles[i] = title.section.title
	end
	return table.concat(titles, ", ")
end

local function Section(window, key)
	for _, title in ipairs(window.titles) do
		if title.section.key == key then
			return title.section, title
		end
	end
end

local function Names(records)
	local names = {}
	for i, rec in ipairs(records) do
		names[i] = rec.info.name
	end
	return table.concat(names, ", ")
end

local function TileFor(window, itemID)
	for _, tile in ipairs(window.tiles) do
		if tile.record and tile.record.itemID == itemID then
			return tile
		end
	end
end

local function Other(saved)
	saved.characters = saved.characters or {}
	saved.characters["Aria-Doomhowl"] = {
		name = "Aria",
		realm = "Doomhowl",
		class = "MAGE",
		level = 42,
		money = 50000,
		guild = "Knights-Doomhowl",
		bagsTime = 1790000000 - 7200,
		bags = {
			[0] = {
				size = 16,
				family = 0,
				items = {
					[1] = { link = Mock.Link(2589), count = 7, quality = 1 },
					[2] = { link = Mock.Link(5635), count = 1, quality = 0 },
				},
			},
		},
		bankTime = 1790000000 - 86400 * 3,
		bank = {
			[6] = {
				size = 98,
				family = 0,
				name = "Tab 1",
				items = { [5] = { link = Mock.Link(2589), count = 40, quality = 1 } },
			},
		},
	}
	return saved
end

--------------------------------------------------------------------------------
-- Loading and taking over
--------------------------------------------------------------------------------

test("loads cleanly and takes over the bags and bank", function()
	local client = Start()
	NoErrors(client)
	local env, ns = client.env, client.ns
	check(ns.bags and ns.bank and ns.guild, "three windows")
	check(ns.Takeover.bags, "bags taken over")
	check(ns.Takeover.bank, "bank taken over")
	check(env.ContainerFrame1:GetParent() ~= env.UIParent, "Blizzard's bags moved out of sight")
	check(env.BankFrame:GetParent() ~= env.UIParent, "Blizzard's bank moved out of sight")
	check(env.BankFrame:IsShown(), "but never hidden")
	check((client.state.secureButtons or 0) >= 34, "item buttons prepared for every bag slot")
end)

test("ToggleAllBags opens and closes the bags", function()
	local client = Start()
	local bags = OpenBags(client)
	check(bags:IsShown(), "open")
	equal(client.state.blizzard.ToggleAllBags, nil, "Blizzard's own toggle not used")
	OpenBags(client)
	check(not bags:IsShown(), "closed")
	NoErrors(client)
end)

test("one key press through two hooks toggles once", function()
	local client = Start()
	client.env.ToggleAllBags()
	client.env.ToggleBackpack()
	check(client.ns.bags:IsShown(), "still open")
end)

test("a vendor opens and closes the bags, but not bags the player opened", function()
	local client = Start()
	local env, bags = client.env, client.ns.bags
	env.OpenAllBags(env.MerchantFrame)
	check(bags:IsShown(), "opened by the vendor")
	env.CloseAllBags(env.MerchantFrame)
	check(not bags:IsShown(), "closed with the vendor")
	OpenBags(client)
	env.OpenAllBags(env.MerchantFrame)
	env.CloseAllBags(env.MerchantFrame)
	check(bags:IsShown(), "the player's own bags stay open")
	NoErrors(client)
end)

test("another bag addon: Knapsack only records", function()
	local client = Start(function(_, state)
		state.loadedAddons.EllesmereUIBags = true
	end)
	local env, ns = client.env, client.ns
	check(not ns.Takeover.bags, "not taken over")
	equal(ns.Takeover.other, "EllesmereUI Bags", "names the other addon")
	env.ToggleAllBags()
	equal(client.state.blizzard.ToggleAllBags, 1, "the game's own toggle still runs")
	check(not ns.bags:IsShown(), "Knapsack stays closed")
	check(client.state.chat[1] and client.state.chat[1]:find("EllesmereUI Bags", 1, true), "says why in chat")
	env.SlashCmdList.KNAPSACK("")
	check(ns.bags:IsShown(), "/knapsack opens it")
	Mock.Fire(client.state, "BAG_UPDATE", 0)
	Mock.Advance(client.state, 1)
	check(env.KnapsackDB.characters["Vedek-Doomhowl"].bags[0], "bags still recorded")
	NoErrors(client)
end)

test("the other bag addon named Satchel is another bag addon", function()
	local client = Start(function(_, state)
		state.loadedAddons.Satchel = true
	end)
	check(not client.ns.Takeover.bags, "not taken over")
	equal(client.ns.Takeover.other, "Satchel", "names it")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Categories and sorting
--------------------------------------------------------------------------------

test("items go into categories, junk last, free space at the end", function()
	local client = Start()
	local bags = OpenBags(client)
	equal(Titles(bags), "Equipment, Consumables, Trade Goods, Quest Items, Ammo, Miscellaneous, Junk, Free", "sections")
	equal(Names(Section(bags, "equipment").records), "Green Sword of the Monkey", "grey armor is junk, not equipment")
	equal(Names(Section(bags, "consumables").records), "Lesser Healing Potion, Tough Hunk of Bread", "consumables")
	equal(Names(Section(bags, "quest").records), "Shadowforge Key", "quest item")
	NoErrors(client)
end)

test("spell reagents have their own category", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 17029, count = 12 }
	end)
	local bags = OpenBags(client)
	equal(Names(Section(bags, "reagents").records), "Sacred Candle", "reagents")
	check(not Names(Section(bags, "tradegoods").records):find("Candle", 1, true), "not with the cloth")
	NoErrors(client)
end)

test("junk is sorted by vendor value, cheapest first", function()
	local client = Start()
	local bags = OpenBags(client)
	local junk, title = Section(bags, "junk")
	equal(Names(junk.records), "Battered Buckler, Rabbit's Foot, Ruined Pelt, Sharp Claw", "order (3c, 20c, 50c, 105c)")
	equal(junk.money, 178, "total value")
	check(title.text:GetText():find("0g 1s 78c", 1, true), "total in the title: " .. tostring(title.text:GetText()))
	local tile = TileFor(bags, 4865)
	equal(Plain(tile.value:GetText()), "50c", "value of the whole stack on the item")
	equal(Plain(TileFor(bags, 5635).value:GetText()), "1s", "only the largest coin")
	equal(TileFor(bags, 858).value:GetText(), "", "no value on other items")
	NoErrors(client)
end)

test("junk whose price is not loaded yet goes last until it arrives", function()
	local client = Start(function(_, state)
		state.unloaded[9999] = true
		state.containers[0].items[10] = { id = 9999 }
	end)
	local state = client.state
	local bags = OpenBags(client)
	-- The quality comes from the bag, so it is junk already.
	equal(Names(Section(bags, "junk").records), "Battered Buckler, Rabbit's Foot, Ruined Pelt, Sharp Claw, Mystery Trinket", "unknown price last")
	check(state.requested[9999], "the item was asked for")
	state.unloaded[9999] = nil
	Mock.Fire(state, "GET_ITEM_INFO_RECEIVED", 9999, true)
	Mock.Advance(state, 0.2)
	equal(Names(Section(bags, "junk").records), "Battered Buckler, Mystery Trinket, Rabbit's Foot, Ruined Pelt, Sharp Claw", "sorted by its price (7c)")
	NoErrors(client)
end)

test("junk sorted like the rest when the option is off", function()
	local client = Start(function(_, state)
		state.saved = { settings = { junkByValue = false, sortMode = "name" } }
	end)
	local bags = OpenBags(client)
	equal(Names(Section(bags, "junk").records), "Battered Buckler, Rabbit's Foot, Ruined Pelt, Sharp Claw", "by name")
	client.ns.DB.Set("junkValueText", false)
	client.ns.Send("settings")
	Mock.Advance(client.state, 0.2)
	equal(TileFor(bags, 4865).value:GetText(), "", "no value text")
end)

test("hiding Junk sends grey items back to their type", function()
	local client = Start()
	local ns = client.ns
	ns.Categories.SetHidden("junk", true)
	local bags = OpenBags(client)
	check(not Section(bags, "junk"), "no junk section")
	equal(Names(Section(bags, "equipment").records), "Green Sword of the Monkey, Battered Buckler", "grey armor is equipment again")
	check(Names(Section(bags, "misc").records):find("Sharp Claw", 1, true), "grey misc in Miscellaneous")
	NoErrors(client)
end)

test("custom categories take items by their rules", function()
	local client = Start()
	local Categories = client.ns.Categories
	local green = Categories.AddCustom("Greens", { quality = 2 })
	local cloth = Categories.AddCustom("Cloth", { text = "CLOTH" })
	local empty = Categories.AddCustom("Keepers", {})
	local bags = OpenBags(client)
	equal(Names(Section(bags, green).records), "Green Sword of the Monkey", "quality rule")
	equal(Names(Section(bags, cloth).records), "Linen Cloth", "name rule, not case sensitive")
	check(not Section(bags, empty), "a category without rules is empty")
	check(not Section(bags, "equipment"), "equipment is left empty")
	local list = Categories.List()
	equal(list[#list - 1].key, "misc", "new categories go before Miscellaneous")
	Categories.DeleteCustom(green)
	Mock.Advance(client.state, 0.2)
	check(Section(bags, "equipment"), "deleting gives the item back")
	NoErrors(client)
end)

test("dropping an item on a title keeps it there; middle-click undoes it", function()
	local client = Start()
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	local _, title = Section(bags, "consumables")
	state.cursor = 6948 -- Hearthstone on the cursor
	Mock.CallScript(title, "OnReceiveDrag")
	equal(state.cursor, nil, "cursor cleared")
	Mock.Advance(state, 0.2)
	equal(Names(Section(bags, "consumables").records), "Lesser Healing Potion, Tough Hunk of Bread, Hearthstone", "moved")
	equal(ns.Categories.Assigned(6948), "consumables", "remembered")

	local tile = TileFor(bags, 6948)
	local button = ns.Tiles.Secure.Attached(tile)
	Mock.CallScript(button, "OnMouseUp", "MiddleButton")
	Mock.Advance(state, 0.2)
	equal(ns.Categories.Assigned(6948), nil, "forgotten")
	check(Names(Section(bags, "misc").records):find("Hearthstone", 1, true), "back in Miscellaneous")
	NoErrors(client)
end)

test("category title menu", function()
	local client = Start()
	local bags = OpenBags(client)
	local _, title = Section(bags, "junk")
	Mock.Click(title, "RightButton")
	local menu = client.state.menus[#client.state.menus]
	check(menu and menu:Find("Hide this category"), "menu with hide")
	menu:Find("Move up").callback()
	Mock.Advance(client.state, 0.2)
	equal(Titles(bags), "Equipment, Consumables, Trade Goods, Quest Items, Ammo, Junk, Miscellaneous, Free", "moved up")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Blizzard's item buttons
--------------------------------------------------------------------------------

test("every live item has Blizzard's button for its bag slot", function()
	local client = Start()
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	local attached = 0
	for _, tile in ipairs(bags.tiles) do
		local button = ns.Tiles.Secure.Attached(tile)
		if button then
			attached = attached + 1
			check(not tile:IsMouseEnabled(), "the tile leaves the mouse to the button")
			if tile.record then
				equal(button:GetParent():GetID(), tile.record.bag, "bag from the parent")
				equal(button:GetID(), tile.record.slot, "slot")
			end
		end
	end
	equal(attached, #bags.tiles, "all tiles")
	local tile = TileFor(bags, 6948)
	Mock.Click(ns.Tiles.Secure.Attached(tile), "RightButton")
	local used = state.used[1]
	check(used and used.bag == 0 and used.slot == 1, "clicking runs Blizzard's code for that slot")
	NoErrors(client)
end)

test("the free space tile holds the first free slot's button", function()
	local client = Start()
	local bags = OpenBags(client)
	local free = Section(bags, "free").free
	equal(#free, 2, "normal bags and the quiver")
	equal(free[1].count, 22, "free normal slots")
	equal(free[1].bag .. "/" .. free[1].slot, "0/10", "first free slot")
	equal(free[2].count, 19, "free quiver slots")
	local found
	for _, tile in ipairs(bags.tiles) do
		if tile.free == free[1] then
			found = client.ns.Tiles.Secure.Attached(tile)
		end
	end
	check(found and found:GetID() == 10 and found:GetParent():GetID() == 0, "drop target for items")
	equal(bags.footer:GetText(), "10/32 slots", "footer counts normal bags")
end)

test("no buttons are made in combat; they come after it", function()
	local client = Start(function(_, state)
		state.combat = true
	end)
	local state, ns = client.state, client.ns
	equal(state.secureButtons or 0, 0, "none made at login in combat")
	local bags = OpenBags(client)
	check(#bags.tiles > 0, "items still shown")
	local tile = TileFor(bags, 6948)
	check(not ns.Tiles.Secure.Attached(tile), "no button yet")
	check(tile:IsMouseEnabled(), "the tile shows the tooltip itself")
	Mock.Enter(state, tile)
	equal(client.env.GameTooltip.item, 6948, "tooltip")
	state.combat = false
	Mock.Fire(state, "PLAYER_REGEN_ENABLED")
	check(ns.Tiles.Secure.Attached(TileFor(bags, 6948)), "button after combat")
	NoErrors(client)
end)

test("new items glow until the mouse passes over them", function()
	local client = Start(function(_, state)
		state.containers[0].items[2].new = true
	end)
	local bags = OpenBags(client)
	local tile = TileFor(bags, 2589)
	check(tile.glow:IsShown(), "glows")
	check(not TileFor(bags, 858).glow:IsShown(), "old items do not")
	Mock.Enter(client.state, client.ns.Tiles.Secure.Attached(tile))
	check(not tile.glow:IsShown(), "stops on hover")
	check(tile.hover:IsShown(), "hover highlight")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Snapshots, other characters
--------------------------------------------------------------------------------

test("the bags are recorded for other characters to see", function()
	local client = Start()
	local state, env = client.state, client.env
	state.containers[1].items[2] = { id = 4306, count = 3 }
	Mock.Fire(state, "BAG_UPDATE", 1)
	Mock.Advance(state, 0.5)
	local char = env.KnapsackDB.characters["Vedek-Doomhowl"]
	equal(char.class, "PRIEST", "class")
	equal(char.money, 123456, "money")
	local item = char.bags[1].items[2]
	check(item and item.link:find("Silk Cloth", 1, true) and item.count == 3, "new item recorded")
	check(char.bags[0].items[1].locked == nil, "live-only fields are not saved")
	NoErrors(client)
end)

test("another character's bags, from the snapshot", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local ns = client.ns
	local bags = OpenBags(client)
	bags:SetOwner("Aria-Doomhowl")
	equal(Titles(bags), "Trade Goods, Junk, Free", "her sections")
	local tile = TileFor(bags, 2589)
	check(not ns.Tiles.Secure.Attached(tile), "no item buttons for other characters")
	check(tile:IsMouseEnabled(), "the tile handles the mouse")
	Mock.Enter(client.state, tile)
	equal(client.env.GameTooltip.item, 2589, "tooltip from the link")
	client.state.modified = true
	Mock.Click(tile, "LeftButton")
	check(client.state.linked and client.state.linked:find("Linen Cloth", 1, true), "shift-click links it")
	check(bags.footer:GetText():find("2 hours ago", 1, true), "when it was recorded: " .. bags.footer:GetText())
	equal(bags.money:GetText(), "5g 0s 0c", "her money")
	-- Choices list everyone.
	local choices = bags:OwnerChoices()
	equal(#choices, 2, "two characters")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- The bank
--------------------------------------------------------------------------------

local function Bank(state)
	state.containers[6] = { size = 98, name = "Tab One", items = { [1] = { id = 4306, count = 20 }, [2] = { id = 7070, count = 5 } } }
	state.containers[7] = { size = 98, name = "Tab Two", items = { [3] = { id = 5635, count = 2 } } }
end

local function VisitBank(client)
	local state = client.state
	state.atBank = true
	state.interaction[8] = true
	Mock.Fire(state, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
	Mock.Advance(state, 2)
end

local function LeaveBank(client)
	local state = client.state
	state.atBank = false
	state.interaction[8] = nil
	Mock.Fire(state, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
	Mock.Advance(state, 0.5)
end

test("the bank is recorded at the bank and shown live there", function()
	local client = Start(function(_, state)
		Bank(state)
	end)
	local state, env, ns = client.state, client.env, client.ns
	VisitBank(client)
	local char = env.KnapsackDB.characters["Vedek-Doomhowl"]
	check(char.bank and char.bank[6] and char.bank[7], "both tabs recorded")
	equal(char.bank[6].name, "Tab One", "tab name")
	check(ns.bank:IsShown(), "bank window opened")
	check(ns.bags:IsShown(), "bags opened with it")
	local tile = TileFor(ns.bank, 4306)
	local button = tile and ns.Tiles.Secure.Attached(tile)
	check(button and button:GetParent():GetID() == 6 and button:GetID() == 1, "Blizzard's button for the bank slot")
	equal(Titles(ns.bank), "Trade Goods, Junk, Free", "bank by category")
	equal(ns.bank.footer:GetText(), "3/196 slots", "slots")
	LeaveBank(client)
	check(not ns.bank:IsShown(), "closes when leaving")
	check(not ns.bags:IsShown(), "bags close too")
	NoErrors(client)
end)

test("bank buttons only for slots in use, plus a drop target", function()
	local client = Start(function(_, state)
		Bank(state)
	end)
	local state, ns = client.state, client.ns
	local before = state.secureButtons
	VisitBank(client)
	equal(state.secureButtons - before, 4, "three items and the free space, not 196 slots")
	local free = Section(ns.bank, "free").free[1]
	equal(free.count, 193, "free bank slots")
	equal(free.bag .. "/" .. free.slot, "6/3", "first free bank slot")
	local target
	for _, tile in ipairs(ns.bank.tiles) do
		if tile.free then
			target = ns.Tiles.Secure.Attached(tile)
		end
	end
	check(target and target:GetParent():GetID() == 6 and target:GetID() == 3, "items dropped there go into the bank")
	NoErrors(client)
end)

test("closing Knapsack's bank window ends the visit", function()
	local client = Start(function(_, state)
		Bank(state)
	end)
	VisitBank(client)
	client.ns.bank:Hide()
	equal(client.state.closedBank, 1, "C_Bank.CloseBankFrame")
	LeaveBank(client)
	equal(client.state.closedBank, 1, "only once")
	NoErrors(client)
end)

test("the bank from anywhere, and never recorded away from it", function()
	local client = Start(function(_, state)
		Bank(state)
	end)
	local state, env, ns = client.state, client.env, client.ns
	VisitBank(client)
	LeaveBank(client)
	state.containers[6].items[1] = nil -- the client forgets once away
	Mock.Fire(state, "BAG_UPDATE", 6)
	Mock.Advance(state, 1)
	check(env.KnapsackDB.characters["Vedek-Doomhowl"].bank[6].items[1], "snapshot kept")
	state.time = state.time + 3600
	ns.ToggleBank()
	check(ns.bank:IsShown(), "opens away from the bank")
	local tile = TileFor(ns.bank, 4306)
	check(tile and not ns.Tiles.Secure.Attached(tile), "from the snapshot, without item buttons")
	check(ns.bank.footer:GetText():find("updated", 1, true), "says when")
	NoErrors(client)
end)

test("another character's bank from the bags window", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local bags = OpenBags(client)
	bags:SetOwner("Aria-Doomhowl")
	Mock.Click(bags.buttons[1])
	local bank = client.ns.bank
	check(bank:IsShown(), "bank window")
	equal(bank.ownerKey, "Aria-Doomhowl", "hers")
	equal(Titles(bank), "Trade Goods, Free", "her bank")
	check(bank.footer:GetText():find("3 days ago", 1, true), "age: " .. bank.footer:GetText())
	NoErrors(client)
end)

test("without the bank takeover the game's bank window is used", function()
	local client = Start(function(_, state)
		Bank(state)
		state.saved = { settings = { replaceBank = false } }
	end)
	local env, ns = client.env, client.ns
	check(not ns.Takeover.bank, "not taken over")
	equal(env.BankFrame:GetParent(), env.UIParent, "Blizzard's bank left alone")
	VisitBank(client)
	check(not ns.bank:IsShown(), "Knapsack's bank stays closed")
	check(env.KnapsackDB.characters["Vedek-Doomhowl"].bank[6], "but it is recorded")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- The guild vault
--------------------------------------------------------------------------------

local function Guild(state)
	state.guild = {
		name = "Knights",
		money = 9876543,
		tabs = {
			{ name = "Mats", items = { [1] = { id = 2589, count = 200 }, [14] = { id = 4306, count = 20 } } },
			{ name = "Officers", viewable = false, items = { [1] = { id = 12345 } } },
			{ name = "Potions", items = { [2] = { id = 858, count = 20 } } },
		},
	}
end

local function OpenVault(client)
	local state = client.state
	state.interaction[10] = true
	Mock.Fire(state, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
end

-- The server answers the last request.
local function Serve(client)
	local state = client.state
	local tab = state.guildQueries[#state.guildQueries]
	state.guildLoaded[tab] = true
	Mock.Fire(state, "GUILDBANKBAGSLOTS_CHANGED")
	Mock.Advance(state, 0.5)
	return tab
end

test("every tab of the guild vault it can see is recorded", function()
	local client = Start(function(_, state)
		Guild(state)
	end)
	local state, env, ns = client.state, client.env, client.ns
	OpenVault(client)
	equal(state.guildQueries[1], 1, "asks for the first tab")
	equal(Serve(client), 1, "first answer")
	equal(state.guildQueries[2], 3, "then the next viewable tab, skipping Officers")
	Serve(client)
	Mock.Advance(state, 3)
	local guild = env.KnapsackDB.guilds["Knights-Doomhowl"]
	check(guild, "recorded")
	equal(guild.money, 9876543, "money")
	equal(guild.tabs[1].items[14].count, 20, "tab 1")
	equal(guild.tabs[3].items[2].count, 20, "tab 3")
	check(not guild.tabs[2].items, "not the tab it cannot see")
	equal(env.KnapsackDB.characters["Vedek-Doomhowl"].guild, "Knights-Doomhowl", "the character's guild")

	ns.ToggleGuild()
	local window = ns.guild
	check(window:IsShown(), "vault window")
	equal(Titles(window), "Mats, Potions", "one section per tab")
	equal(window.money:GetText(), "987g 65s 43c", "guild money")
	NoErrors(client)
end)

test("an empty read right after asking keeps the old tab", function()
	local client = Start(function(_, state)
		Guild(state)
		state.saved = {
			guilds = {
				["Knights-Doomhowl"] = {
					name = "Knights",
					tabs = { { name = "Mats", viewable = true, items = { [1] = { link = Mock.Link(2589), count = 100 } } } },
				},
			},
		}
	end)
	local state, env = client.state, client.env
	OpenVault(client)
	-- An answer arrives, but it was for something else: tab 1 is not loaded.
	Mock.Fire(state, "GUILDBANKBAGSLOTS_CHANGED")
	Mock.Advance(state, 0.5)
	local tab = env.KnapsackDB.guilds["Knights-Doomhowl"].tabs[1]
	equal(tab.items[1] and tab.items[1].count, 100, "old snapshot kept")
	NoErrors(client)
end)

test("the Vault button follows the character's guild", function()
	local client = Start(function(_, state)
		state.saved = Other({})
		state.saved.guilds = { ["Knights-Doomhowl"] = { name = "Knights", time = 1790000000, tabs = {} } }
	end)
	local bags = OpenBags(client)
	local vault = client.ns.bags.vaultButton
	check(not vault:IsEnabled(), "Vedek has no guild")
	bags:SetOwner("Aria-Doomhowl")
	check(vault:IsEnabled(), "Aria does")
	Mock.Click(vault)
	check(client.ns.guild:IsShown(), "opens her vault")
	check(client.ns.guild.message:IsShown(), "which is empty")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Tooltips, search, layout
--------------------------------------------------------------------------------

test("tooltips list every character's and vault's count", function()
	local client = Start(function(_, state)
		state.saved = Other({})
		state.saved.guilds = {
			["Knights-Doomhowl"] = {
				name = "Knights",
				tabs = { { items = { [1] = { link = Mock.Link(2589), count = 200 } } } },
			},
		}
	end)
	local tip = client.env.GameTooltip
	tip:SetOwner(client.env.UIParent)
	tip:SetHyperlink(Mock.Link(2589))
	local text = Plain(tip:Text())
	check(text:find("Vedek | 20 (bags 20)", 1, true), "mine\n" .. text)
	check(text:find("Aria | 47 (bags 7, bank 40)", 1, true), "hers\n" .. text)
	check(text:find("Knights | 200 (guild vault)", 1, true), "vault\n" .. text)
	check(text:find("Total | 267", 1, true), "total\n" .. text)
	client.ns.DB.Set("tooltipCounts", false)
	tip:SetHyperlink(Mock.Link(2589))
	equal(#tip.lines, 1, "can be turned off")
	NoErrors(client)
end)

test("search dims what does not match", function()
	local client = Start()
	local bags = OpenBags(client)
	bags.searchBox:SetText("cloth")
	equal(TileFor(bags, 2589):GetAlpha(), 1, "Linen Cloth matches")
	check(TileFor(bags, 858):GetAlpha() < 1, "potion dimmed")
	bags.searchBox:SetText("")
	equal(TileFor(bags, 858):GetAlpha(), 1, "cleared")
end)

test("small categories sit side by side", function()
	local client = Start()
	local bags = OpenBags(client)
	local _, equipment = Section(bags, "equipment")
	local _, consumables = Section(bags, "consumables")
	local _, ey = select(2, equipment:GetPoint())
	local x1, y1 = select(4, equipment:GetPoint())
	local x2, y2 = select(4, consumables:GetPoint())
	equal(y1, y2, "same row")
	check(x2 > x1, "consumables to the right")
	client.ns.DB.Set("compact", false)
	client.ns.Send("settings")
	Mock.Advance(client.state, 0.2)
	local _, consumables2 = Section(bags, "consumables")
	local _, y3 = select(4, consumables2:GetPoint())
	check(y3 < y1, "each on its own row when off")
	NoErrors(client)
end)

test("the scroll bar only shows when the items do not fit", function()
	local client = Start(function(_, state)
		state.mailbox = { { sender = "Aria", subject = "Hi", daysLeft = 5 } } -- a letter: the window shows a message
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	check(not bags.scroll.bar:IsShown(), "the bags fit")
	Mock.Fire(state, "MAIL_SHOW")
	Mock.Fire(state, "MAIL_INBOX_UPDATE")
	Mock.Fire(state, "MAIL_CLOSED")
	ns.ToggleMail()
	check(ns.mail.message:IsShown() and not ns.mail.scroll.bar:IsShown(), "a message fits too")
	local swords = {}
	for slot = 1, 260 do
		swords[slot] = { id = 12345 } -- gear is never merged: 260 tiles
	end
	state.containers[3] = { size = 260, name = "Big Bag", items = swords }
	Mock.Fire(state, "BAG_UPDATE", 3)
	Mock.Advance(state, 1)
	check(bags.scroll.bar:IsShown(), "shown when they do not")
	NoErrors(client)
end)

test("columns and item size set the width", function()
	local client = Start()
	local bags = OpenBags(client)
	local width = bags:GetWidth()
	client.ns.DB.Set("columns", 16)
	client.ns.Send("settings")
	Mock.Advance(client.state, 0.2)
	check(bags:GetWidth() > width, "wider")
	equal(bags:GetWidth(), 16 * 36 + 15 * 4 + 16, "16 items of 36 with 4 between, plus the edges")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Options and skinning
--------------------------------------------------------------------------------

test("the options window works", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local ns = client.ns
	ns.Options.Open("categories")
	check(_G.KnapsackOptionsFrame == nil, "no globals leak into the test runner")
	local frame = client.env.KnapsackOptionsFrame
	check(frame and frame:IsShown(), "open")
	local key = ns.Categories.AddCustom("Test", { class = 7 })
	ns.Options:RefreshCategories()
	ns.Options.Open("characters")
	ns.Options.Toggle()
	check(not frame:IsShown(), "toggles closed")
	check(ns.Categories.Custom(key).class == 7, "rules kept")
	NoErrors(client)
end)

test("EllesmereUI's skin is used when it is there", function()
	local calls = {}
	local client = Start(function(env)
		env.EllesmereUI = {
			RegisterSkin = function(name, callback)
				calls.name = name
				calls.callback = callback
			end,
		}
	end)
	equal(calls.name, "Knapsack", "registered")
	local shells, boxes = 0, 0
	calls.callback({
		Shell = function()
			shells = shells + 1
		end,
		EditBox = function()
			boxes = boxes + 1
		end,
		Button = function() end,
		CloseButton = function() end,
		GetAccentColor = function()
			return 1, 0, 0
		end,
	})
	equal(shells, 5, "the five windows")
	equal(boxes, 5, "their search boxes")
	equal(client.ns.W.COLORS.accent[1], 1, "the accent color")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- First in-game report (2026-09-26)
--------------------------------------------------------------------------------

local function near(a, b)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

local function Refresh(client)
	client.ns.Send("settings")
	Mock.Advance(client.state, 0.2)
end

local function Setting(client, key, value)
	client.ns.DB.Set(key, value)
	Refresh(client)
end

-- How many tiles show the item.
local function TileCount(window, itemID)
	local n = 0
	for _, tile in ipairs(window.tiles) do
		if tile.record and tile.record.itemID == itemID then
			n = n + 1
		end
	end
	return n
end

-- Stack sizes of an item across the given bags, smallest first: "7,20".
local function Stacks(state, itemID)
	local counts = {}
	for _, c in pairs(state.containers) do
		for _, item in pairs(c.items) do
			if item.id == itemID then
				counts[#counts + 1] = item.count or 1
			end
		end
	end
	table.sort(counts)
	return table.concat(counts, ",")
end

-- Lets the server answer rounds of moves.
local function Settle(client, rounds)
	for _ = 1, rounds or 5 do
		Mock.Fire(client.state, "BAG_UPDATE_DELAYED")
		Mock.Advance(client.state, 0.3)
	end
end

test("Blizzard's item buttons are invisible, not just their icons", function()
	local client = Start()
	local bags = OpenBags(client)
	local checked = 0
	for _, tile in ipairs(bags.tiles) do
		local button = client.ns.Tiles.Secure.Attached(tile)
		if button then
			checked = checked + 1
			equal(button:GetAlpha(), 0, "the button's own alpha")
		end
	end
	check(checked >= 10, "every item's button")
	NoErrors(client)
end)

test("logging out keeps the recorded bags and gold", function()
	local client = Start()
	local state, env = client.state, client.env
	local char = env.KnapsackDB.characters["Vedek-Doomhowl"]
	check(char.bags[0] and char.bags[0].items[1], "recorded while playing")
	-- On the way out the client empties the bags and the gold.
	Mock.Fire(state, "PLAYER_LEAVING_WORLD")
	state.containers = {}
	state.money = 0
	Mock.Fire(state, "BAG_UPDATE", 0)
	Mock.Fire(state, "BAG_UPDATE_DELAYED")
	Mock.Fire(state, "PLAYER_MONEY")
	Mock.Fire(state, "PLAYER_GUILD_UPDATE", "player")
	Mock.Advance(state, 1)
	Mock.Fire(state, "PLAYER_LOGOUT")
	check(char.bags[0] and char.bags[0].items[1] and char.bags[0].items[1].link:find("Hearthstone", 1, true), "bags kept")
	equal(char.money, 123456, "gold kept")
	check(char.seen, "last seen")
	NoErrors(client)
end)

test("bags not loaded yet do not replace the recorded ones", function()
	local saved
	local client = Start(function(_, state)
		saved = {
			characters = {
				["Vedek-Doomhowl"] = {
					name = "Vedek",
					bags = { [0] = { size = 16, family = 0, items = { [1] = { link = Mock.Link(6948), count = 1, quality = 1 } } } },
				},
			},
		}
		state.saved = saved
		state.containers = {} -- the client has not sent the bags yet
	end)
	local state = client.state
	local char = client.env.KnapsackDB.characters["Vedek-Doomhowl"]
	check(char.bags[0] and char.bags[0].items[1], "last session's bags kept at login")
	StandardBags(state)
	Mock.Fire(state, "BAG_UPDATE", 0)
	Mock.Advance(state, 1)
	check(char.bags[1] and char.bags[0].items[2], "recorded once they arrive")
	NoErrors(client)
end)

test("the whole window can be dragged, and the header has room for it", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local bags = OpenBags(client)
	check(bags:GetScript("OnDragStart"), "the window itself")
	check(bags.header:GetScript("OnDragStart"), "the header")
	check(bags.moneyButton:GetScript("OnDragStart"), "the gold")
	local width = bags.searchBox:GetWidth()
	check(width >= 60 and width <= 180, "the search box leaves room: " .. width)
	Mock.CallScript(bags, "OnDragStop")
	check(client.env.KnapsackDB.positions.KnapsackBagsFrame, "the new position is kept")
	check(bags.combineButton:IsShown(), "combine stacks, for the player's bags")
	bags:SetOwner("Aria-Doomhowl")
	check(not bags.combineButton:IsShown(), "not for other characters")
	NoErrors(client)
end)

test("the quality border is whole screen pixels, with the icon inside", function()
	local client = Start()
	local bags = OpenBags(client)
	local pixel = 768 / 1080
	local tile = TileFor(bags, 12345)
	check(near(tile.border[1]:GetHeight(), 2 * pixel), "two pixels: " .. tostring(tile.border[1]:GetHeight()))
	check(near(tile.border[3]:GetWidth(), 2 * pixel), "on every side")
	local _, _, _, x, y = tile.icon:GetPoint(1)
	check(near(x, 2 * pixel) and near(y, -2 * pixel), "the icon inside it")
	equal(tile.border[1].__color[2], 1, "green for an uncommon item")
	Setting(client, "borderSize", 3)
	tile = TileFor(bags, 12345)
	check(near(tile.border[1]:GetHeight(), 3 * pixel), "three pixels")
	-- It keeps its size in pixels when the window is scaled.
	Setting(client, "scale", 1.5)
	tile = TileFor(bags, 12345)
	tile.GetEffectiveScale = function()
		return 1.5
	end
	client.ns.Tiles.Set(tile, tile.record, 36)
	check(near(tile.border[1]:GetHeight(), 3 * pixel / 1.5), "still three pixels")
	NoErrors(client)
end)

test("item levels on gear", function()
	local client = Start(function(_, state)
		state.containers[1].items[5] = { id = 16060 } -- a shirt
		state.containers[1].items[6] = { id = 4336 } -- a bag
	end)
	local bags = OpenBags(client)
	equal(TileFor(bags, 12345).level:GetText(), "25", "the sword")
	equal(TileFor(bags, 2210).level:GetText(), "5", "grey armor too")
	equal(TileFor(bags, 2589).level:GetText(), "", "not on cloth")
	equal(TileFor(bags, 16060).level:GetText(), "", "not on a shirt")
	equal(TileFor(bags, 4336).level:GetText(), "", "not on a bag")
	Setting(client, "itemLevel", false)
	equal(TileFor(bags, 12345).level:GetText(), "", "can be turned off")
	NoErrors(client)
end)

test("items the character cannot use are red", function()
	local client = Start(function(_, state)
		state.containers[1].items[5] = { id = 10205 } -- plate, and Vedek is a priest
		state.containers[1].items[6] = { id = 13446, count = 2 } -- a potion above his level
		state.saved = Other({})
		state.saved.characters["Aria-Doomhowl"].bags[0].items[3] = { link = Mock.Link(10205), count = 1, quality = 2 }
	end)
	local bags = OpenBags(client)
	local helm = TileFor(bags, 10205)
	check(helm.record.unusable, "plate")
	check(helm.icon:IsDesaturated(), "colorless")
	equal(helm.icon.__vertex[2], 0.3, "and red")
	check(TileFor(bags, 13446).record.unusable, "a potion above the character's level")
	local sword = TileFor(bags, 12345)
	check(not sword.record.unusable, "not for red durability or disenchant lines")
	check(not sword.icon:IsDesaturated(), "in color")
	equal(sword.icon.__vertex[2], 1, "untinted")
	check(not TileFor(bags, 2589).record.unusable, "cloth")
	bags:SetOwner("Aria-Doomhowl")
	check(not TileFor(bags, 10205).record.unusable, "not on other characters' items")
	bags:SetOwner(client.ns.DB.PlayerKey())
	Setting(client, "unusableTint", false)
	check(not TileFor(bags, 10205).icon:IsDesaturated(), "can be turned off")
	NoErrors(client)
end)

test("stacks of the same item show as one", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 2589, count = 5 }
		state.containers[1].items[3] = { id = 2589, count = 12 }
	end)
	local ns = client.ns
	local bags = OpenBags(client)
	local records = Section(bags, "tradegoods").records
	equal(#records, 1, "one tile")
	equal(records[1].count, 37, "the total")
	equal(#records[1].stacks, 3, "three stacks")
	equal(TileFor(bags, 2589).count:GetText(), "37", "shown")
	local button = ns.Tiles.Secure.Attached(TileFor(bags, 2589))
	check(button:GetParent():GetID() == 1 and button:GetID() == 2, "using it takes the smallest stack first")
	Setting(client, "mergeStacks", false)
	equal(TileCount(bags, 2589), 3, "can be turned off")
	NoErrors(client)
end)

test("gear is never merged; potions are", function()
	local client = Start(function(_, state)
		state.containers[1].items[4] = { id = 12345 } -- a second sword
		state.containers[1].items[5] = { id = 858, count = 3 } -- potions have a spell, but no charges
	end)
	local bags = OpenBags(client)
	equal(TileCount(bags, 12345), 2, "each sword on its own")
	equal(TileCount(bags, 858), 1, "potions merged")
	equal(TileFor(bags, 858).count:GetText(), "8", "5 and 3")
	NoErrors(client)
end)

test("merged items with charges use the one with the fewest left", function()
	-- Oils made by different enchanters have different links.
	local A, B = "Player-4618-00AB97C1", "Player-4618-007DCB49"
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 20749, charges = 5, crafter = A } -- Brilliant Wizard Oil
		state.containers[1].items[3] = { id = 20749, charges = 2, crafter = B }
		state.containers[1].items[4] = { id = 20749, charges = 0 } -- kept with no charges: cannot be used
		state.containers[1].items[5] = { id = 20749, charges = 4, crafter = A }
	end)
	local state, env, ns = client.state, client.env, client.ns
	local bags = OpenBags(client)
	equal(TileCount(bags, 20749), 1, "one tile")
	local tile = TileFor(bags, 20749)
	equal(tile.count:GetText(), "4", "four oils")
	local button = ns.Tiles.Secure.Attached(tile)
	check(button:GetParent():GetID() == 1 and button:GetID() == 3, "using it uses the oil with 2 charges")
	Mock.Enter(state, button)
	local text = Plain(env.GameTooltip:Text())
	check(text:find("Charges: 0, 2, 4, 5  (the one with 2 is used first)", 1, true), "every oil's charges\n" .. text)

	-- Used down to 1 charge, it is still the one; used up, the next fewest.
	state.containers[1].items[3].charges = 1
	Mock.Fire(state, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1000 + 20749)
	Mock.Advance(state, 1)
	button = ns.Tiles.Secure.Attached(TileFor(bags, 20749))
	equal(button:GetID(), 3, "still the one with the fewest")
	equal(env.KnapsackDB.characters["Vedek-Doomhowl"].bags[1].items[3].charges, 1, "recorded after the cast")
	state.containers[1].items[3] = nil
	Mock.Fire(state, "BAG_UPDATE", 1)
	Mock.Advance(state, 1)
	button = ns.Tiles.Secure.Attached(TileFor(bags, 20749))
	equal(button:GetID(), 5, "then the one with 4")
	NoErrors(client)
end)

test("other characters' items show their recorded charges", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 20749, charges = 3 }
		state.saved = Other({})
		local items = state.saved.characters["Aria-Doomhowl"].bags[0].items
		items[3] = { link = Mock.Link(20749), count = 1, quality = 1, charges = 4 }
		items[4] = { link = Mock.Link(20749), count = 1, quality = 1, charges = 1 }
		items[5] = { link = Mock.Link(20749), count = 1, quality = 1 } -- recorded before charges were
	end)
	local state, env = client.state, client.env
	equal(env.KnapsackDB.characters["Vedek-Doomhowl"].bags[1].items[2].charges, 3, "charges are recorded")
	local bags = OpenBags(client)
	bags:SetOwner("Aria-Doomhowl")
	Mock.Enter(state, TileFor(bags, 20749))
	local text = Plain(env.GameTooltip:Text())
	check(text:find("Charges: 1, 4", 1, true), "hers, merged\n" .. text)
	check(not text:find("used first", 1, true), "nothing is used from here")
	Mock.Leave(state, TileFor(bags, 20749))
	client.ns.DB.Set("mergeStacks", false)
	Refresh(client)
	for _, tile in ipairs(bags.tiles) do
		if tile.record and tile.record.charges == 4 then
			Mock.Enter(state, tile)
		end
	end
	text = Plain(env.GameTooltip:Text())
	check(text:find("4 |4Charge:Charges;", 1, true), "one of hers on its own\n" .. text)
	NoErrors(client)
end)

test("other characters' stacks are merged too", function()
	local client = Start(function(_, state)
		state.saved = Other({})
		state.saved.characters["Aria-Doomhowl"].bags[0].items[3] = { link = Mock.Link(2589), count = 20, quality = 1 }
	end)
	local bags = OpenBags(client)
	bags:SetOwner("Aria-Doomhowl")
	equal(TileCount(bags, 2589), 1, "one tile")
	equal(TileFor(bags, 2589).count:GetText(), "27", "the total")
	-- Her merged tile still shows the item's tooltip.
	Mock.Enter(client.state, TileFor(bags, 2589))
	equal(client.env.GameTooltip.item, 2589, "tooltip")
	NoErrors(client)
end)

test("merging stops while a mailbox, trade, auction house or bank is open", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 2589, count = 5 }
		Bank(state)
	end)
	local state = client.state
	local bags = OpenBags(client)
	equal(TileCount(bags, 2589), 1, "merged")
	for _, pair in ipairs({ { "MAIL_SHOW", "MAIL_CLOSED" }, { "TRADE_SHOW", "TRADE_CLOSED" }, { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" } }) do
		Mock.Fire(state, pair[1])
		Mock.Advance(state, 0.2)
		equal(TileCount(bags, 2589), 2, "apart: " .. pair[1])
		local button = client.ns.Tiles.Secure.Attached(TileFor(bags, 2589))
		check(button, "each stack has its own button")
		Mock.Fire(state, pair[2])
		Mock.Advance(state, 0.2)
		equal(TileCount(bags, 2589), 1, "merged again: " .. pair[2])
	end
	VisitBank(client)
	equal(TileCount(bags, 2589), 2, "apart at the bank")
	LeaveBank(client)
	check(bags:IsShown(), "the player's own bags stay open")
	equal(TileCount(bags, 2589), 1, "merged after it")
	NoErrors(client)
end)

test("only the mailbox's send page stops merging", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 2589, count = 5 }
	end)
	local state, env = client.state, client.env
	local send = env.CreateFrame("Frame", "SendMailFrame", env.UIParent)
	send:Hide()
	local bags = OpenBags(client)
	Mock.Fire(state, "MAIL_SHOW")
	Mock.Advance(state, 0.2)
	equal(TileCount(bags, 2589), 1, "the inbox does not")
	send:Show()
	Mock.Advance(state, 0.2)
	equal(TileCount(bags, 2589), 2, "the send page does")
	send:Hide()
	Mock.Advance(state, 0.2)
	equal(TileCount(bags, 2589), 1, "back to the inbox")
	NoErrors(client)
end)

test("a merged tile glows for any new stack, and hovering clears them all", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 2589, count = 5 }
		state.containers[0].items[2].new = true -- the stack of 20, not the one under the tile
	end)
	local state = client.state
	local bags = OpenBags(client)
	local tile = TileFor(bags, 2589)
	check(tile.glow:IsShown(), "glows")
	Mock.Enter(state, client.ns.Tiles.Secure.Attached(tile))
	check(not state.containers[0].items[2].new, "every stack is seen")
	client.ns.bags:Refresh()
	check(not TileFor(bags, 2589).glow:IsShown(), "and stays that way")
	NoErrors(client)
end)

test("combine stacks fills up partial stacks", function()
	local client = Start(function(_, state)
		state.containers[0].items[2].count = 7 -- Linen Cloth 7 + 8 + 16
		state.containers[1].items[2] = { id = 2589, count = 8 }
		state.containers[1].items[3] = { id = 2589, count = 16 }
		state.containers[1].items[4] = { id = 4306, count = 15 } -- Silk Cloth 15 + 12
		state.containers[1].items[5] = { id = 4306, count = 12 }
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	Mock.Click(bags.combineButton)
	check(not bags.combineButton:IsEnabled(), "the button waits while it runs")
	Settle(client)
	equal(Stacks(state, 2589), "11,20", "Linen Cloth")
	equal(Stacks(state, 4306), "7,20", "Silk Cloth")
	check(not ns.Stack.Running(), "done")
	check(bags.combineButton:IsEnabled(), "the button is back")
	check(state.chat[#state.chat]:find("Stacks combined", 1, true), "says so")
	equal(state.cursor, nil, "nothing left on the cursor")
	NoErrors(client)
end)

test("combine stacks: nothing to do, combat, stacks that will not go together", function()
	local client = Start()
	local state, ns = client.state, client.ns
	ns.Stack.Start("bags")
	check(state.chat[#state.chat]:find("No stacks to combine", 1, true), "nothing to do")
	equal(#state.moves, 0, "no moves")

	state.containers[0].items[10] = { id = 2589, count = 7, bound = true }
	state.containers[1].items[2] = { id = 2589, count = 8 }
	state.combat = true
	ns.Stack.Start("bags")
	check(not ns.Stack.Running(), "not in combat")
	check(state.chat[#state.chat]:find("combat", 1, true), "says why")
	equal(#state.moves, 0, "nothing moved")
	state.combat = false

	-- Soulbound and unbound stacks never go together (they would only swap
	-- places), so they are left alone.
	ns.Stack.Start("bags")
	Settle(client)
	check(not ns.Stack.Running(), "finished")
	equal(#state.moves, 0, "not even tried")
	check(state.chat[#state.chat]:find("No stacks to combine", 1, true), "nothing to combine")
	NoErrors(client)
end)

test("combine stacks in the bank, at the bank", function()
	local client = Start(function(_, state)
		Bank(state)
		state.containers[7].items[4] = { id = 4306, count = 5 }
		state.containers[7].items[5] = { id = 4306, count = 6 }
	end)
	local state, ns = client.state, client.ns
	ns.Stack.Start("bank")
	check(state.chat[#state.chat]:find("at the bank", 1, true), "not away from it")
	VisitBank(client)
	check(ns.bank.combineButton:IsShown(), "a button at the bank")
	Mock.Click(ns.bank.combineButton)
	Settle(client)
	equal(Stacks(state, 4306), "11,20", "Silk Cloth in the bank")
	LeaveBank(client)
	ns.ToggleBank()
	check(not ns.bank.combineButton:IsShown(), "no button away from the bank")
	NoErrors(client)
end)

test("shift-clicking the bank's broom fills its partial stacks from the bags", function()
	local client = Start(function(_, state)
		Bank(state) -- Silk Cloth 20 (full) and Elemental Water 5 in tab one, Sharp Claw 2 in tab two
		state.containers[1].items[2] = { id = 7070, count = 3 }
		state.containers[1].items[3] = { id = 7070, count = 20 }
		state.containers[1].items[4] = { id = 7070, count = 2, bound = true } -- never goes onto unbound water
		state.containers[1].items[5] = { id = 4306, count = 4 } -- the bank's silk is full already
	end)
	local state, ns = client.state, client.ns
	VisitBank(client)
	check(ns.bank.combineButton.tipText:find("Shift-click", 1, true), "the tooltip says how")
	state.shift = true
	Mock.Click(ns.bank.combineButton)
	state.shift = false
	Settle(client)
	check(not ns.Stack.Running(), "done")
	equal(state.containers[6].items[2].count, 20, "the bank's water is full")
	equal(Stacks(state, 7070), "2,8,20", "the bags' smallest water went first; the soulbound water stayed")
	equal(state.containers[1].items[2], nil, "a bag slot freed")
	equal(Stacks(state, 5635), "5", "the bank's claws took the bags' claws")
	equal(state.containers[0].items[4], nil, "none left in the bags")
	equal(state.containers[1].items[5].count, 4, "silk stays: nothing to fill")
	check(state.chat[#state.chat]:find("Filled up stacks in the bank from the bags", 1, true), "says so: " .. state.chat[#state.chat])
	equal(state.cursor, nil, "nothing left on the cursor")
	NoErrors(client)
end)

test("shift-clicking the bags' broom at the bank fills them from the bank", function()
	local client = Start(function(_, state)
		Bank(state)
		state.containers[6].items[4] = { id = 858, count = 7 } -- Lesser Healing Potions; the bags have 5
		state.containers[6].items[5] = { id = 858, count = 12 }
		state.containers[1].items[2] = { id = 4306, count = 3 } -- silk: the bags' partial stacks
		state.containers[1].items[3] = { id = 4306, count = 4 }
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	state.shift = true
	Mock.Click(bags.combineButton)
	check(state.chat[#state.chat]:find("at the bank", 1, true), "only at the bank: " .. state.chat[#state.chat])
	equal(#state.moves, 0, "nothing moved away from it")
	VisitBank(client)
	Mock.Click(bags.combineButton)
	state.shift = false
	Settle(client)
	equal(state.containers[0].items[3].count, 20, "the bags' potions are full")
	equal(Stacks(state, 858), "4,20", "the bank's smaller stack went first")
	-- The bags' silk (3 and 4) is filled from the bank's full stack of 20.
	equal(Stacks(state, 4306), "7,20", "the bags' silk filled up")
	equal(state.containers[6].items[1], nil, "all of the bank's silk went")
	equal(Stacks(state, 5635), "5", "the bags' claws took the bank's")
	check(state.chat[#state.chat]:find("Filled up stacks in the bags from the bank", 1, true), "says so: " .. state.chat[#state.chat])
	NoErrors(client)
end)

test("pointing at the gold lists every character's gold", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local bags = OpenBags(client)
	local tip = client.env.GameTooltip
	Mock.Enter(client.state, bags.moneyButton)
	check(tip:IsShown(), "tooltip")
	local text = Plain(tip:Text())
	check(text:find("Vedek | 12g 34s 56c", 1, true), "mine\n" .. text)
	check(text:find("Aria | 5g 0s 0c", 1, true), "hers\n" .. text)
	check(text:find("Total | 17g 34s 56c", 1, true), "total\n" .. text)
	check((text:find("Vedek", 1, true) or 99) < (text:find("Aria", 1, true) or 0), "most first")
	Mock.Leave(client.state, bags.moneyButton)
	check(not tip:IsShown(), "hidden again")
	NoErrors(client)
end)

test("charges and other tooltip lines are recognised", function()
	local client = Start()
	local C = client.ns.C
	local charges = C.FormatPatterns("%d |4Charge:Charges;")
	equal(#charges, 2, "one pattern per form")
	check(C.MatchesAny("5 Charges", charges), "5 Charges")
	check(C.MatchesAny("1 Charge", charges), "1 Charge")
	equal(C.MatchNumber("12 Charges", charges), 12, "the number")
	equal(C.MatchNumber("1 Charge", charges), 1, "one")
	equal(C.MatchNumber("Charges", charges), nil, "no number")
	-- Tooltip data may hold the text as drawn, or as the game keeps it.
	local ChargesIn = client.ns.Items.ChargesIn
	equal(ChargesIn("4 Charges"), 4, "as drawn")
	equal(ChargesIn("1 Charge"), 1, "one, as drawn")
	equal(ChargesIn("4 |4Charge:Charges;"), 4, "before drawing")
	equal(ChargesIn("1 |4Charge:Charges;"), 1, "one, before drawing")
	equal(ChargesIn("|cffffffff5 |4Charge:Charges;|r"), 5, "with a color code")
	equal(ChargesIn("|cnIQ1:3 Charges|r"), 3, "with a named color")
	equal(ChargesIn("No charges"), 0, "none left")
	equal(ChargesIn("Use: Increases spell damage by up to 8."), nil, "other lines")
	equal(ChargesIn("20 Slot Bag"), nil, "bag sizes")
	check(not C.MatchesAny("10 Armor", charges), "not other numbers")
	check(not C.MatchesAny("20 Slot Bag", charges), "not bag sizes")
	check(C.MatchesAny("Durability 0 / 45", C.FormatPatterns("Durability %d / %d")), "durability")
	check(C.MatchesAny("Costs 5% more", C.FormatPatterns("Costs %d%% more")), "a literal percent")
	NoErrors(client)
end)

test("charges are read once the item has loaded", function()
	local client = Start(function(_, state)
		state.unloaded[20749] = true
		state.containers[1].items[2] = { id = 20749, charges = 3 }
	end)
	local state, env = client.state, client.env
	local saved = env.KnapsackDB.characters["Vedek-Doomhowl"].bags[1].items[2]
	equal(saved.charges, nil, "not before")
	check(state.requested[20749], "the item was asked for")
	state.unloaded[20749] = nil
	Mock.Fire(state, "GET_ITEM_INFO_RECEIVED", 20749, true)
	Mock.Advance(state, 1)
	saved = env.KnapsackDB.characters["Vedek-Doomhowl"].bags[1].items[2]
	equal(saved.charges, 3, "recorded once it has loaded")
	NoErrors(client)
end)

test("an item the server does not have is not asked for again and again", function()
	local client = Start(function(_, state)
		state.unloaded[9999] = true
		state.containers[0].items[10] = { id = 9999 }
	end)
	local state = client.state
	local asked = 0
	local request = client.env.C_Item.RequestLoadItemDataByID
	client.env.C_Item.RequestLoadItemDataByID = function(id)
		asked = asked + 1
		request(id)
	end
	Mock.Fire(state, "GET_ITEM_INFO_RECEIVED", 9999, false)
	Mock.Advance(state, 1)
	Mock.Fire(state, "BAG_UPDATE", 0)
	Mock.Advance(state, 1)
	equal(asked, 0, "given up on")
	NoErrors(client)
end)

test("/knapsack charges shows what the game gives and what is read from it", function()
	local client = Start(function(_, state)
		state.containers[1].items[2] = { id = 20749, charges = 4 }
	end)
	local state = client.state
	client.env.SlashCmdList.KNAPSACK("charges")
	local line = state.chat[#state.chat]
	check(line:find("1/2", 1, true), "the slot: " .. line)
	check(line:find("||4Charge:Charges;", 1, true), "the line as given, escape codes shown: " .. line)
	check(line:find("= 4", 1, true), "what is read: " .. line)
	client.state.containers[1].items[2] = nil
	client.env.SlashCmdList.KNAPSACK("charges")
	check(state.chat[#state.chat]:find("No item", 1, true), "says when there is none")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Binding, and finding an item anywhere
--------------------------------------------------------------------------------

test("a category of Bind on Equip items that are not bound yet", function()
	local client = Start(function(_, state)
		state.containers[1].items[4] = { id = 12345, bound = true } -- a second sword, worn once
		state.containers[1].items[5] = { id = 10205 } -- plate, Bind on Equip
	end)
	local ns = client.ns
	local boe = ns.Categories.AddCustom("BoE", { bind = "boe" })
	local bags = OpenBags(client)
	equal(Names(Section(bags, boe).records), "Green Sword of the Monkey, Thick Plate Helm", "the unbound Bind on Equip gear")
	equal(Names(Section(bags, "equipment").records), "Green Sword of the Monkey", "the bound sword stays with the rest")
	equal(client.env.KnapsackDB.characters["Vedek-Doomhowl"].bags[1].items[4].bound, true, "soulbound is recorded")
	-- The other binding choices are rules too.
	ns.Categories.SetRules(boe, { bind = "bound" })
	Mock.Advance(client.state, 0.2)
	equal(Names(Section(bags, boe).records), "Green Sword of the Monkey", "only the soulbound sword")
	NoErrors(client)
end)

local function WithGuild(state)
	state.saved = Other({})
	state.saved.guilds = {
		["Knights-Doomhowl"] = { name = "Knights", time = 1790000000, tabs = { { name = "Mats", items = { [3] = { link = Mock.Link(2589), count = 200 } } } } },
	}
	state.saved.characters["Aria-Doomhowl"].mail = {
		time = 1790000000,
		mails = { { sender = "Vedek", expires = 1790000000 + 86400 * 10, returns = true, items = { { link = Mock.Link(2589), count = 5 } } } },
	}
end

test("Find searches every character, the mail and the guild vaults", function()
	local client = Start(function(_, state)
		WithGuild(state)
	end)
	local state, env, ns = client.state, client.env, client.ns
	env.SlashCmdList.KNAPSACK("find Linen")
	Mock.Advance(state, 0.5)
	local find = ns.find
	check(find:IsShown(), "the Find window")
	local titles = {}
	for i, title in ipairs(find.titles) do
		titles[i] = Plain(title.section.title)
	end
	equal(table.concat(titles, "; "), "Vedek: bags; Aria: bags; Aria: bank; Aria: mail; Knights: guild vault", "every place with Linen Cloth, mine first")
	equal(find.footer:GetText(), "272 found in 5 places", "how many in all")
	local tile = TileFor(find, 2589)
	Mock.Enter(state, tile)
	check(Plain(env.GameTooltip:Text()):find("Aria | 52 (bags 7, bank 40, mail 5)", 1, true), "the tooltip says where the rest is")

	find.searchBox:SetText("zzz")
	Mock.Advance(state, 0.5)
	check(find.message:IsShown() and find.message:GetText():find("zzz", 1, true), "says when nothing has that name")
	find.searchBox:SetText("l")
	Mock.Advance(state, 0.5)
	equal(#find.tiles, 0, "one letter is not searched")
	NoErrors(client)
end)

test("the magnifier in the bags finds what the bags are searching for", function()
	local client = Start(function(_, state)
		WithGuild(state)
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	bags.searchBox:SetText("cloth")
	Mock.Click(bags.findButton)
	Mock.Advance(state, 0.5)
	check(ns.find:IsShown(), "opens Find")
	equal(ns.find.searchBox:GetText(), "cloth", "with the same text")
	check(TileFor(ns.find, 2589), "and the results")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Search keywords, trade marks, new items, moving a category
--------------------------------------------------------------------------------

-- Names of the items whose tiles are not dimmed.
local function Lit(window)
	local names = {}
	for _, tile in ipairs(window.tiles) do
		if tile.record and tile:GetAlpha() == 1 then
			names[#names + 1] = tile.record.info.name
		end
	end
	table.sort(names)
	return table.concat(names, ", ")
end

test("search keywords", function()
	local client = Start(function(_, state)
		state.containers[1].items[4] = { id = 12345, bound = true } -- a sword worn once
	end)
	local bags = OpenBags(client)
	local function Search(text)
		bags.searchBox:SetText(text)
		return Lit(bags)
	end
	equal(Search("boe"), "Green Sword of the Monkey", "boe: the sword not bound yet, not the worn one")
	equal(Search("soulbound"), "Green Sword of the Monkey", "soulbound: the worn one")
	equal(Search("junk"), "Battered Buckler, Rabbit's Foot, Ruined Pelt, Sharp Claw", "junk")
	equal(Search("ilvl>20"), "Green Sword of the Monkey, Green Sword of the Monkey", "item level")
	equal(Search("ilvl<10 gear"), "Battered Buckler", "item level and gear")
	equal(Search("linen cloth"), "Linen Cloth", "several words")
	check(not Search("!junk"):find("Pelt", 1, true), "! turns a word around")
	equal(Search("#linen"), "", "# means a keyword, and linen is not one")
	equal(Search("epic"), "", "no epics")
	equal(Search(""), Lit(bags), "nothing typed: everything")
	NoErrors(client)
end)

test("Find understands the keywords too", function()
	local client = Start(function(_, state)
		WithGuild(state)
	end)
	client.ns.OpenFind("boe")
	Mock.Advance(client.state, 0.5)
	check(TileFor(client.ns.find, 12345), "the unbound sword")
	equal(TileFor(client.ns.find, 2589), nil, "no cloth")
	NoErrors(client)
end)

test("items that can still be traded say BoE", function()
	local client = Start(function(_, state)
		state.containers[1].items[4] = { id = 12345, bound = true }
	end)
	local bags = OpenBags(client)
	local unbound, bound
	for _, tile in ipairs(bags.tiles) do
		if tile.record and tile.record.itemID == 12345 then
			if tile.record.bound then
				bound = tile
			else
				unbound = tile
			end
		end
	end
	equal(unbound.value:GetText(), "BoE", "not bound yet")
	equal(bound.value:GetText(), "", "soulbound")
	equal(TileFor(bags, 2589).value:GetText(), "", "cloth never binds")
	Setting(client, "bindMarker", false)
	equal(TileFor(bags, 12345).value:GetText(), "", "can be turned off")
	NoErrors(client)
end)

test("new items go first until the bags close", function()
	local client = Start(function(_, state)
		state.containers[0].items[2].new = true -- Linen Cloth
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	equal(Titles(bags):match("^[^,]+"), "New", "a New section first")
	equal(Names(Section(bags, "new").records), "Linen Cloth", "with the new cloth")
	check(not Section(bags, "tradegoods"), "not also in Trade Goods")
	-- Pointing at it clears the game's new-item flag.
	Mock.Enter(state, ns.Tiles.Secure.Attached(TileFor(bags, 2589)))
	state.containers[0].items[2].new = nil
	bags:Refresh()
	check(Section(bags, "new"), "still new after a look")
	OpenBags(client) -- closes
	OpenBags(client)
	check(not Section(bags, "new"), "not after the bags closed")
	check(Names(Section(bags, "tradegoods").records):find("Linen", 1, true), "back in its category")
	state.containers[0].items[3].new = true
	Setting(client, "newFirst", false)
	check(not Section(bags, "new"), "can be turned off")
	NoErrors(client)
end)

-- Right-clicks a category's title and picks a menu entry.
local function MenuEntry(client, window, key, label)
	local _, title = Section(window, key)
	Mock.Click(title, "RightButton")
	local menu = client.state.menus[#client.state.menus]
	for _, child in ipairs(menu.children) do
		if child.text and Plain(child.text) == label then
			return child
		end
	end
end

test("a whole category into the bank and back out", function()
	local client = Start(function(_, state)
		Bank(state)
		state.containers[1].items[2] = { id = 4306, count = 5 } -- Silk Cloth, to go on the bank's 20
		state.containers[1].items[3] = { id = 7070, count = 2 } -- Elemental Water, onto the bank's 5
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	check(not MenuEntry(client, bags, "tradegoods", "Put all in the bank"), "only at the bank")
	VisitBank(client)
	local entry = MenuEntry(client, bags, "tradegoods", "Put all in the bank")
	check(entry, "at the bank")
	entry.callback()
	Settle(client)
	check(not Section(bags, "tradegoods"), "no trade goods left in the bags")
	check(state.containers[6].items[3] and state.containers[6].items[3].id == 2589, "Linen Cloth went to a free bank slot")
	local silk = state.containers[6].items[4]
	check(state.containers[6].items[1].count == 20 and silk and silk.id == 4306 and silk.count == 5, "the silk too: the bank's silk stack is full")
	equal(state.containers[6].items[2].count, 7, "Elemental Water onto its part stack")
	check(state.chat[#state.chat]:find("Moved 3 items to the bank", 1, true), "says so: " .. state.chat[#state.chat])
	-- The arrows are not trade goods: they stay in the quiver.
	equal(state.containers[2].items[1].id, 2512, "arrows stay")

	entry = MenuEntry(client, ns.bank, "tradegoods", "Take all out of the bank")
	check(entry, "and out again from the bank window")
	entry.callback()
	Settle(client)
	check(Section(bags, "tradegoods"), "back in the bags")
	for _, item in pairs(state.containers[2].items) do
		equal(item.id, 2512, "nothing but arrows in the quiver")
	end
	NoErrors(client)
end)

test("a bank still loading is waited for, and not recorded empty", function()
	local client = Start(function(_, state)
		Bank(state)
		state.saved = {
			characters = {
				["Vedek-Doomhowl"] = { name = "Vedek", bankTime = 1790000000, bank = { [6] = { size = 98, family = 0, items = { [1] = { link = Mock.Link(4306), count = 20 } } } } },
			},
		}
	end)
	local state, env, ns = client.state, client.env, client.ns
	state.bankLoading = true -- the tabs arrive a moment after the bank opens
	VisitBank(client)
	check(ns.bank.message:IsShown() and ns.bank.message:GetText():find("loading", 1, true), "the bank says it is loading")
	check(env.KnapsackDB.characters["Vedek-Doomhowl"].bank[6].items[1], "the recorded bank is kept meanwhile")
	local entry = MenuEntry(client, ns.bags, "tradegoods", "Put all in the bank")
	entry.callback()
	Mock.Advance(state, 1)
	check(ns.Transfer.Running(), "putting things in waits for it")
	state.bankLoading = false
	Mock.Fire(state, "BAG_UPDATE_DELAYED")
	Settle(client)
	check(not ns.Transfer.Running(), "then goes ahead")
	check(state.containers[6].items[3] and state.containers[6].items[3].id == 2589, "the cloth is in the bank")
	check(not ns.bank.message:IsShown(), "the bank shows its items")
	NoErrors(client)
end)

test("a new character's free first bank tab is unlocked from Knapsack", function()
	local client = Start() -- no bank tab yet
	local state, env, ns = client.state, client.env, client.ns
	VisitBank(client)
	Mock.Advance(state, 1)
	local bank = ns.bank
	local text = bank.message:GetText() or ""
	check(text:find("Your first bank tab is free.", 1, true), "the game's own words: " .. text)
	check(not text:lower():find("buy", 1, true), "no talk of buying a free tab")
	check(bank.unlockButton:IsShown(), "an unlock button")
	equal(bank.unlockButton.text:GetText(), "Unlock bank tab", "that says unlock")
	MenuEntry(client, ns.bags, "tradegoods", "Put all in the bank").callback()
	check(state.chat[#state.chat]:find("unlock it in the bank window", 1, true), "putting things in says so: " .. state.chat[#state.chat])
	check(not ns.Transfer.Running(), "nothing moves")

	-- The click goes to Blizzard's own purchase button, which asks the game.
	Mock.Click(bank.unlockButton.secure)
	equal(state.tabPrompt, 0, "the game's confirmation, for the character bank")
	state.containers[6] = { size = 48, items = {} } -- the game gives the tab
	Mock.Fire(state, "BANK_TABS_CHANGED")
	Mock.Advance(state, 0.5)
	check(not bank.unlockButton:IsShown(), "no button once it is there")
	equal(bank.footer:GetText(), "0/48 slots", "48 empty slots")
	check(not env.BankPanel.MoneyDisplay.__events.PLAYER_MONEY, "Blizzard's hidden tab cost display no longer listens for gold")
	NoErrors(client)
end)

test("a bank tab that costs gold says so", function()
	local client = Start(function(_, state)
		state.nextBankTab = { tabCost = 50000, canAfford = true, purchasePromptBody = "Buy another bank tab?" }
	end)
	VisitBank(client)
	Mock.Advance(client.state, 1)
	local bank = client.ns.bank
	check(bank.message:GetText():find("It costs 5g 0s 0c.", 1, true), "the cost: " .. bank.message:GetText())
	equal(bank.unlockButton.text:GetText(), "Buy bank tab", "a buy button")
	NoErrors(client)
end)

test("the x in the search box clears it and lets go of the keyboard", function()
	local client = Start()
	local bags = OpenBags(client)
	local box = bags.searchBox
	check(not box.clear:IsShown(), "hidden when there is nothing to clear")
	box:SetFocus()
	check(box.clear:IsShown(), "shown while the box has the keyboard")
	box:SetText("cloth")
	check(TileFor(bags, 858):GetAlpha() < 1, "searching")
	Mock.Click(box.clear)
	equal(box:GetText(), "", "emptied")
	check(not box:HasFocus(), "the keyboard is let go")
	check(not box.clear:IsShown(), "and the x hides")
	equal(TileFor(bags, 858):GetAlpha(), 1, "everything shows again")
	NoErrors(client)
end)

test("mail a whole category to one of your characters", function()
	local client = Start(function(_, state)
		state.saved = Other({})
		-- 14 stacks of cloth: two mails.
		for slot = 1, 13 do
			state.containers[1].items[slot + 1] = { id = 4306, count = slot }
		end
		state.containers[1].items[15] = { id = 2589, count = 1, bound = true } -- cannot be mailed
	end)
	local state, env, ns = client.state, client.env, client.ns
	local bags = OpenBags(client)
	Mock.Fire(state, "MAIL_SHOW")
	Mock.Advance(state, 0.2)
	local mailTo = MenuEntry(client, bags, "tradegoods", "Mail all to")
	check(mailTo, "at the mailbox")
	local aria
	for _, child in ipairs(mailTo.children) do
		if Plain(child.text) == "Aria" then
			aria = child
		end
	end
	check(aria, "to Aria")
	aria.callback()
	local dialog = env.KnapsackConfirmDialog
	check(dialog:IsShown() and dialog.text:GetText():find("Mail 14 items", 1, true), "asks first: " .. tostring(dialog.text:GetText()))
	Mock.Click(dialog.yes)
	Mock.Advance(state, 1)
	equal(#state.sentMail, 1, "the first mail")
	equal(state.sentMail[1].recipient, "Aria", "to her")
	equal(state.sentMail[1].items, 12, "full")
	Mock.DeliverMail(state)
	Mock.Advance(state, 2)
	equal(#state.sentMail, 2, "the second mail")
	equal(state.sentMail[2].items, 2, "the rest")
	Mock.DeliverMail(state)
	Mock.Advance(state, 1)
	check(state.chat[#state.chat]:find("Mailed 14 items to Aria", 1, true), "says so: " .. state.chat[#state.chat])
	local mails = env.KnapsackDB.characters["Aria-Doomhowl"].mail.mails
	equal(#mails, 2, "both in her mail")
	check(state.containers[1].items[15], "the soulbound cloth stayed")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Bag slots
--------------------------------------------------------------------------------

local function WornBags(state)
	state.containers[1].bagItem = 4238 -- Linen Bag
	state.containers[2].bagItem = 2101 -- Light Quiver
end

test("the bag slots show the bags worn, and change them", function()
	local client = Start(function(_, state)
		WornBags(state)
	end)
	local state, env = client.state, client.env
	local bags = OpenBags(client)
	check(not bags.bagBar:IsShown(), "hidden at first")
	local height = bags:GetHeight()
	Mock.Click(bags.bagToggle)
	check(bags.bagBar:IsShown(), "shown")
	equal(env.KnapsackDB.settings.bagBar, true, "remembered")
	check(bags:GetHeight() > height, "the window makes room for them")
	local slots = bags.bagBar.slots
	equal(slots[1].bag, 0, "the backpack first")
	check(slots[2].link and slots[2].link:find("Linen Bag", 1, true), "the bag in the first bag slot")
	equal(slots[2].count:GetText(), "16", "its size")
	equal(slots[4].link, nil, "an empty bag slot")
	check(not slots[6]:IsShown(), "no reagent bag slot without a reagent bag")

	-- Pointing at a bag shows its items.
	Mock.Enter(state, slots[2])
	equal(env.GameTooltip.item, 4238, "the bag's tooltip")
	equal(TileFor(bags, 4540):GetAlpha(), 1, "the bread is in it")
	check(TileFor(bags, 2589):GetAlpha() < 1, "the cloth is not")
	Mock.Leave(state, slots[2])
	equal(TileFor(bags, 2589):GetAlpha(), 1, "back to normal")

	-- Changing bags, as with the game's own bag slots.
	Mock.CallScript(slots[2], "OnDragStart")
	equal(state.bagMoves[1], "pickup 31", "a bag is picked up")
	Mock.CallScript(slots[4], "OnReceiveDrag")
	equal(state.bagMoves[2], "put 33", "and put in another slot")
	state.cursor = 2589
	Mock.Click(slots[1])
	equal(state.bagMoves[3], "put backpack", "an item clicked onto the backpack goes into it")
	Mock.Click(bags.bagToggle)
	check(not bags.bagBar:IsShown(), "hidden again")
	NoErrors(client)
end)

test("another character's bag slots, as recorded", function()
	local client = Start(function(_, state)
		WornBags(state)
		state.saved = Other({ settings = { bagBar = true } })
		state.saved.characters["Aria-Doomhowl"].bags[1] = { size = 10, family = 0, items = {}, link = Mock.Link(4238) }
	end)
	local state = client.state
	local bags = OpenBags(client)
	check(bags.bagBar:IsShown(), "shown")
	bags:SetOwner("Aria-Doomhowl")
	local slot = bags.bagBar.slots[2]
	check(slot.link and slot.link:find("Linen Bag", 1, true), "her bag")
	equal(slot.count:GetText(), "10", "its size")
	Mock.CallScript(slot, "OnDragStart")
	equal(#state.bagMoves, 0, "not something to pick up")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Mail
--------------------------------------------------------------------------------

local function OpenMailbox(client, mails)
	local state = client.state
	state.mailbox = mails
	Mock.Fire(state, "MAIL_SHOW")
	Mock.Fire(state, "MAIL_INBOX_UPDATE")
	Mock.Advance(state, 0.5)
end

local function TooltipOf(client, tile)
	Mock.Enter(client.state, tile)
	return Plain(client.env.GameTooltip:Text())
end

test("the mailbox is recorded, with when each item goes back", function()
	local client = Start()
	local state, env, ns = client.state, client.env, client.ns
	OpenMailbox(client, {
		{ sender = "Aria", subject = "Cloth", daysLeft = 29.5, items = { { id = 2589, count = 20 }, { id = 4306, count = 5 } } },
		{ sender = "Auction House", subject = "Auction won", daysLeft = 0.51, canDelete = true, items = { { id = 12345 } } },
		{ sender = "Aria", subject = "Gold", money = 50000, daysLeft = 10 },
		{ sender = "Aria", subject = "Pay me", cod = 20000, daysLeft = 2.5, items = { { id = 20749, charges = 2 } } },
	})
	Mock.Fire(state, "MAIL_CLOSED")
	local mail = env.KnapsackDB.characters["Vedek-Doomhowl"].mail
	check(mail and #mail.mails == 4, "four mails")
	equal(mail.mails[4].items[1].charges, 2, "charges of mailed items too")

	ns.ToggleMail()
	local window = ns.mail
	check(window:IsShown(), "the mail window")
	equal(Titles(window), "Equipment, Consumables, Trade Goods", "by category")
	equal(TileFor(window, 12345).level:GetText(), "12h", "time left on the item, not its item level")
	equal(TileFor(window, 2589).level:GetText(), "29d", "cloth")
	equal(TileFor(window, 20749).level:GetText(), "2d", "the cash on delivery oil")
	local text = TooltipOf(client, TileFor(window, 12345))
	check(text:find("Mail from Auction House", 1, true), "who from\n" .. text)
	check(text:find("Deleted in 12 hours", 1, true), "auction mail is deleted\n" .. text)
	text = TooltipOf(client, TileFor(window, 2589))
	check(text:find("Goes back to Aria in 29 days", 1, true), "player mail goes back\n" .. text)
	text = TooltipOf(client, TileFor(window, 20749))
	check(text:find("Cash on delivery: 2g 0s 0c", 1, true), "cash on delivery\n" .. text)
	check(text:find("2 |4Charge:Charges;", 1, true), "charges\n" .. text)
	check(window.footer:GetText():find("4 items, 4 mails", 1, true), "footer: " .. window.footer:GetText())
	equal(window.money:GetText(), "5g 0s 0c", "gold in the mail")

	-- Taking items out changes what is recorded.
	Mock.Fire(state, "MAIL_SHOW")
	table.remove(state.mailbox, 1)
	Mock.Fire(state, "MAIL_INBOX_UPDATE")
	Mock.Advance(state, 0.5)
	equal(TileFor(window, 2589), nil, "the cloth was taken")
	NoErrors(client)
end)

test("a mailbox closed at once is still recorded", function()
	local client = Start()
	local state, env = client.state, client.env
	state.mailbox = { { sender = "Aria", subject = "Quick", daysLeft = 5, items = { { id = 2589, count = 2 } } } }
	Mock.Fire(state, "MAIL_SHOW")
	Mock.Fire(state, "MAIL_INBOX_UPDATE")
	Mock.Fire(state, "MAIL_CLOSED")
	local mail = env.KnapsackDB.characters["Vedek-Doomhowl"].mail
	check(mail and #mail.mails == 1, "recorded as it closed")
	Mock.Advance(state, 1)
	NoErrors(client)
end)

test("the mailbox is not recorded away from it", function()
	local client = Start()
	local state, env = client.state, client.env
	state.mailbox = { { sender = "Aria", subject = "Hi", items = { { id = 2589 } } } }
	Mock.Fire(state, "MAIL_INBOX_UPDATE")
	Mock.Advance(state, 0.5)
	equal(env.KnapsackDB.characters["Vedek-Doomhowl"].mail, nil, "nothing recorded")
	client.ns.ToggleMail()
	check(client.ns.mail.message:IsShown(), "says so")
	NoErrors(client)
end)

test("mail sent to another of your characters is in its mailbox at once", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local state, env, ns = client.state, client.env, client.ns
	state.sendMail = { items = { [1] = { id = 20749, charges = 3 }, [3] = { id = 2589, count = 10 } }, money = 1000 }
	env.SendMail("aria", "Oil for you", "")
	Mock.Fire(state, "MAIL_SEND_SUCCESS")
	Mock.Advance(state, 0.2)
	local mails = env.KnapsackDB.characters["Aria-Doomhowl"].mail.mails
	equal(#mails, 1, "in her mailbox")
	equal(mails[1].sender, "Vedek", "from me")
	equal(mails[1].items[1].charges, 3, "with the oil's charges")
	check(mails[1].returns, "goes back if not collected")

	ns.ToggleMail("Aria-Doomhowl")
	local text = TooltipOf(client, TileFor(ns.mail, 2589))
	check(text:find("Goes back to Vedek in", 1, true), "when\n" .. text)
	check(text:find("not seen in the mailbox yet", 1, true), "not seen yet\n" .. text)
	check(text:find("Aria | 57 (bags 7, bank 40, mail 10)", 1, true), "counted with her items\n" .. text)

	-- Not to strangers, and not when sending fails.
	env.SendMail("Stranger", "Hi", "")
	Mock.Fire(state, "MAIL_SEND_SUCCESS")
	env.SendMail("Aria-Doomhowl", "Again", "")
	Mock.Fire(state, "MAIL_FAILED")
	Mock.Fire(state, "MAIL_SEND_SUCCESS")
	equal(#env.KnapsackDB.characters["Aria-Doomhowl"].mail.mails, 1, "nothing else delivered")
	equal(#state.sentMail, 3, "the game's own SendMail still ran")
	NoErrors(client)
end)

test("Forever surnames: mail to \"First Last\" reaches your character", function()
	local client = Start(function(_, state)
		state.player.surname = "Md"
		state.saved = Other({})
		-- Mail from "Vedek Md" she did not collect in time.
		state.saved.characters["Aria-Doomhowl"].mail = {
			time = 1790000000 - 40 * 86400,
			mails = { { sender = "Vedek Md", expires = 1790000000 - 86400, returns = true, items = { { link = Mock.Link(4306), count = 1 } } } },
		}
	end)
	local state, env = client.state, client.env
	local chars = env.KnapsackDB.characters
	equal(client.ns.DB.PlayerKey(), "Vedek Md-Doomhowl", "recorded as First Last")
	equal(chars["Vedek Md-Doomhowl"].surname, "Md", "my surname is recorded")
	check(chars["Vedek Md-Doomhowl"].bags[0], "with my bags")
	client.ns.ToggleMail()
	check(TileFor(client.ns.mail, 4306), "mail from \"Vedek Md\" came back to me")
	-- How many mails she has been sent.
	local function Send(to)
		env.SendMail(to, "Hi", "")
		Mock.Fire(state, "MAIL_SEND_SUCCESS")
		local sent = 0
		for _, mail in ipairs(chars["Aria-Doomhowl"].mail.mails) do
			if mail.sent then
				sent = sent + 1
			end
		end
		return sent
	end
	state.sendMail = { items = { [1] = { id = 2589, count = 1 } } }
	-- Her surname is not known yet: the first name decides, and her surname
	-- is learned from the mail.
	equal(Send("Aria Brightwind"), 1, "to First Last")
	equal(chars["Aria-Doomhowl"].surname, "Brightwind", "her surname learned")
	equal(chars["Aria-Doomhowl"].mail.mails[2].sender, "Vedek Md", "from First Last")
	equal(Send("aria brightwind-Doomhowl"), 2, "with the realm, in any case")
	equal(Send("Aria"), 3, "by first name")
	equal(Send("Aria Smith"), 3, "not someone else with her first name")
	NoErrors(client)
end)

test("a record from before surnames moves to First Last", function()
	local client = Start(function(_, state)
		state.player.surname = "Md"
		state.saved = {
			characters = {
				["Vedek-Doomhowl"] = { name = "Vedek", money = 5, bankTime = 1790000000, bank = { [6] = { size = 98, family = 0, items = {} } } },
			},
		}
	end)
	local chars = client.env.KnapsackDB.characters
	equal(chars["Vedek-Doomhowl"], nil, "the old record is gone")
	local char = chars["Vedek Md-Doomhowl"]
	check(char and char.bank and char.bank[6], "its bank moved with it")
	NoErrors(client)

	-- An old record that another Vedek's mail named differently stays his.
	client = Start(function(_, state)
		state.player.surname = "Md"
		state.saved = { characters = { ["Vedek-Doomhowl"] = { name = "Vedek", surname = "Smith" } } }
	end)
	chars = client.env.KnapsackDB.characters
	check(chars["Vedek-Doomhowl"], "Vedek Smith's record is left alone")
	check(chars["Vedek Md-Doomhowl"], "Vedek Md has his own")
	NoErrors(client)
end)

test("characters with the same first name are kept apart and named in full", function()
	local client = Start(function(_, state)
		state.player.surname = "Md"
		state.saved = Other({})
		local chars = state.saved.characters
		chars["Aria-Doomhowl"].surname = "Brightwind"
		chars["Vedek Smith-Doomhowl"] = {
			name = "Vedek",
			surname = "Smith",
			realm = "Doomhowl",
			class = "WARRIOR",
			bags = { [0] = { size = 16, family = 0, items = { [1] = { link = Mock.Link(2589), count = 3 } } } },
		}
	end)
	local state, env, ns = client.state, client.env, client.ns
	local bags = OpenBags(client)
	local names = {}
	for _, choice in ipairs(bags:OwnerChoices()) do
		names[#names + 1] = Plain(choice.text)
	end
	table.sort(names)
	equal(table.concat(names, ", "), "Aria, Vedek Md, Vedek Smith", "both Vedeks in full; Aria's first name is enough")
	local tip = env.GameTooltip
	tip:SetOwner(env.UIParent)
	tip:SetHyperlink(Mock.Link(2589))
	local text = Plain(tip:Text())
	check(text:find("Vedek Md | 20 (bags 20)", 1, true) and text:find("Vedek Smith | 3 (bags 3)", 1, true), "counted apart\n" .. text)

	-- Surnames everywhere, when asked for.
	ns.DB.Set("showSurnames", true)
	names = {}
	for _, choice in ipairs(bags:OwnerChoices()) do
		names[#names + 1] = Plain(choice.text)
	end
	table.sort(names)
	equal(table.concat(names, ", "), "Aria Brightwind, Vedek Md, Vedek Smith", "every surname shown")

	-- Mail to "Vedek" could be for either: it goes to neither.
	state.sendMail = { items = { [1] = { id = 2589, count = 1 } } }
	env.SendMail("Vedek", "Which one?", "")
	Mock.Fire(state, "MAIL_SEND_SUCCESS")
	equal(env.KnapsackDB.characters["Vedek Smith-Doomhowl"].mail, nil, "not recorded for a guess")
	env.SendMail("Vedek Smith", "For you", "")
	Mock.Fire(state, "MAIL_SEND_SUCCESS")
	local mail = env.KnapsackDB.characters["Vedek Smith-Doomhowl"].mail
	check(mail and #mail.mails == 1 and mail.mails[1].sender == "Vedek Md", "Vedek Md's mail to Vedek Smith")
	NoErrors(client)
end)

test("the dropdown highlight does not hide the names", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local bags = OpenBags(client)
	Mock.Click(bags.owner.button)
	local menu = client.env.KnapsackDropDownMenu
	check(menu and menu:IsShown(), "the list opened")
	local highlight = menu.buttons[1].highlight
	check(highlight.__color[4] < 0.5, "only a tint over the name and check mark")
	NoErrors(client)
end)

test("mail not collected in time goes back to its sender", function()
	local now = 1790000000
	local client = Start(function(_, state)
		state.saved = Other({})
		state.saved.characters["Aria-Doomhowl"].mail = {
			time = now - 40 * 86400,
			mails = {
				{ sender = "Vedek", subject = "Old", expires = now - 5 * 86400, returns = true, items = { { link = Mock.Link(2589), count = 3 } } },
				{ sender = "Vedek", subject = "New", expires = now + 20 * 86400, returns = true, items = { { link = Mock.Link(4306), count = 2 } } },
				{ sender = "Someone", subject = "Gone", expires = now - 86400, returns = false, items = { { link = Mock.Link(858) } } },
			},
		}
	end)
	local ns = client.ns
	ns.ToggleMail("Aria-Doomhowl")
	check(TileFor(ns.mail, 4306), "hers: what has not expired")
	equal(TileFor(ns.mail, 2589), nil, "not what went back")
	equal(TileFor(ns.mail, 858), nil, "nor what was deleted")
	ns.ToggleMail("Vedek-Doomhowl")
	local tile = TileFor(ns.mail, 2589)
	check(tile, "the cloth is back in my mailbox")
	local text = TooltipOf(client, tile)
	check(text:find("Deleted in 24 days", 1, true), "returned mail is deleted 30 days after it came back\n" .. text)
	check(text:find("not collected in time", 1, true), "why it is there\n" .. text)
	NoErrors(client)
end)

test("returning a mail from one of your characters puts it in theirs", function()
	local client = Start(function(_, state)
		state.saved = Other({})
	end)
	local state, env = client.state, client.env
	OpenMailbox(client, {
		{ sender = "Aria", subject = "Here", daysLeft = 20, items = { { id = 4306, count = 4 } } },
		{ sender = "Aria", subject = "Returned already", daysLeft = 20, returned = true, items = { { id = 858 } } },
	})
	env.ReturnInboxItem(1)
	env.ReturnInboxItem(2) -- mail that came back cannot go back again
	Mock.Advance(state, 0.2)
	local mails = env.KnapsackDB.characters["Aria-Doomhowl"].mail.mails
	equal(#mails, 1, "back in her mailbox")
	equal(mails[1].sender, "Vedek", "from me")
	check(mails[1].returned and not mails[1].returns, "deleted when it expires")
	equal(mails[1].items[1].count, 4, "the silk")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Classic (Burning Crusade Classic Anniversary)
--------------------------------------------------------------------------------

-- A key on the keyring.
local function ClassicBags(state)
	state.containers[-2] = { size = 32, items = { [1] = { id = 5396 } } }
end

-- The bank's own 28 slots, and a bank bag in the first of two bank bag slots
-- bought.
local function ClassicBank(state)
	state.containers[-1] = { size = 28, items = { [1] = { id = 4306, count = 20 }, [2] = { id = 7070, count = 5 } } }
	state.containers[5] = { size = 16, name = "Linen Bag", bagItem = 4238, items = { [3] = { id = 5635, count = 2 } } }
	state.bankBagSlots = 2
end

local function StartClassic(setup)
	return Start(function(env, state)
		ClassicBags(state)
		if setup then
			setup(env, state)
		end
	end, { classic = true })
end

-- Classic's bank opens and closes with BANKFRAME_OPENED and BANKFRAME_CLOSED.
local function VisitClassicBank(client)
	client.state.atBank = true
	Mock.Fire(client.state, "BANKFRAME_OPENED")
	Mock.Advance(client.state, 2)
end

local function LeaveClassicBank(client)
	client.state.atBank = false
	Mock.Fire(client.state, "BANKFRAME_CLOSED")
	Mock.Advance(client.state, 0.5)
end

test("Classic: loads cleanly and takes over the bags and bank", function()
	local client = StartClassic()
	NoErrors(client)
	local state, env, ns = client.state, client.env, client.ns
	check(ns.C.isClassic and not ns.C.isForever, "a Classic client")
	check(ns.Takeover.bags and ns.Takeover.bank, "bags and bank taken over")
	check(env.BankFrame:GetParent() ~= env.UIParent, "Blizzard's bank moved out of sight")
	equal(env.C_TooltipInfo, nil, "no tooltip data on Classic")
	equal(#state.tooltipCalls, 0, "TooltipDataProcessor not relied on")
	check((state.secureButtons or 0) >= 16 + 16 + 20 + 32, "item buttons for every bag slot, the keyring's too")
	equal(ns.bank.unlockButton, nil, "no bank tab to unlock")
	-- The keyring button opens and closes Knapsack's bags, once a press.
	state.time = state.time + 1
	env.ToggleKeyRing()
	check(ns.bags:IsShown(), "the keyring button opens the bags")
	state.time = state.time + 1
	env.ToggleKeyRing()
	check(not ns.bags:IsShown(), "and closes them")
	NoErrors(client)
end)

test("Classic: keys on the keyring are in Keys; its free slots are not free space", function()
	local client = StartClassic()
	local state, env, ns = client.state, client.env, client.ns
	local bags = OpenBags(client)
	equal(Titles(bags), "Equipment, Consumables, Trade Goods, Quest Items, Ammo, Keys, Miscellaneous, Junk, Free", "sections")
	equal(Names(Section(bags, "keys").records), "Key to Searing Gorge", "the key")
	local button = ns.Tiles.Secure.Attached(TileFor(bags, 5396))
	check(button and button:GetParent():GetID() == -2 and button:GetID() == 1, "Blizzard's button for the keyring slot")
	equal(bags.footer:GetText(), "10/32 slots", "the keyring is not bag space")
	-- The keyring grows as keys are added, so it always has a few free slots.
	local free = Section(bags, "free").free
	for _, entry in ipairs(free) do
		check(entry.bag ~= -2, "no free tile for the keyring")
	end
	equal(#free, 2, "the bags' and the quiver's free slots only")
	check(#bags.bagBar.slots == 5, "no keyring among the bag slots")
	-- The key's tooltip, the way Blizzard's keyring shows it.
	Mock.Enter(state, button)
	local text = Plain(env.GameTooltip:Text())
	check(text:find("Key to Searing Gorge", 1, true), "the key's tooltip\n" .. text)
	check(text:find("Vedek | 1 (bags 1)", 1, true), "and who has it\n" .. text)
	local lines = ns.C.BagTooltip(-2, 1)
	check(lines and lines[1].leftText == "Key to Searing Gorge", "its tooltip lines can be read, for charges")
	local char = env.KnapsackDB.characters["Vedek-Doomhowl"]
	check(char.bags[-2] and char.bags[-2].family == 256, "recorded, as the keyring")
	NoErrors(client)
end)

test("Classic: with ElvUI's bags on Knapsack only records; with them off it takes over", function()
	local client = StartClassic(function(env)
		env.ElvUI = { { private = { bags = { enable = true } } } }
	end)
	local ns = client.ns
	check(not ns.Takeover.bags, "not taken over")
	equal(ns.Takeover.other, "ElvUI", "names ElvUI")
	ns.Options.Open("general")
	local found = false
	for _, frame in ipairs(client.state.frames) do
		local text = rawget(frame, "__text")
		if text and text:find("Turn off Bags in ElvUI's options", 1, true) then
			found = true
		end
	end
	check(found, "the options say how to change that")
	NoErrors(client)

	client = StartClassic(function(env)
		env.ElvUI = { { private = { bags = { enable = false } } } }
	end)
	check(client.ns.Takeover.bags and client.ns.Takeover.other == nil, "taken over with ElvUI's bags off")
	NoErrors(client)
end)

test("Classic: no keyring where the game has it turned off", function()
	local client = StartClassic(function(_, state)
		state.keyringEnabled = false
		state.containers[-2].items = {}
	end)
	local bags = OpenBags(client)
	for _, entry in ipairs(Section(bags, "free").free) do
		check(entry.family ~= 256, "no keyring space")
	end
	equal(client.env.KnapsackDB.characters["Vedek-Doomhowl"].bags[-2], nil, "nothing recorded for it")
	NoErrors(client)
end)

test("Classic: the bank's own slots and bank bags, recorded and shown", function()
	local client = StartClassic(function(_, state)
		ClassicBank(state)
		state.containers[-1].items[4] = { id = 20749, charges = 2 }
	end)
	local state, env, ns = client.state, client.env, client.ns
	VisitClassicBank(client)
	check(ns.bank:IsShown() and ns.bags:IsShown(), "the bank window opened, and the bags")
	local char = env.KnapsackDB.characters["Vedek-Doomhowl"]
	check(char.bank and char.bank[-1] and char.bank[5], "the bank's own slots and the bank bag recorded")
	check(char.bank[5].link and char.bank[5].link:find("Linen Bag", 1, true), "the bank bag itself")
	equal(char.bankBagSlots, 2, "bank bag slots bought")
	equal(char.bank[-1].items[4].charges, 2, "charges in the bank's own slots")
	equal(Titles(ns.bank), "Consumables, Trade Goods, Junk, Free", "by category")
	equal(ns.bank.footer:GetText(), "4/44 slots", "28 of its own and 16 in the bag")
	local button = ns.Tiles.Secure.Attached(TileFor(ns.bank, 4306))
	check(button and button.__template == "BankItemButtonGenericTemplate" and button:GetID() == 1, "Blizzard's bank slot button")
	local bagButton = ns.Tiles.Secure.Attached(TileFor(ns.bank, 5635))
	check(bagButton and bagButton.__template == "ContainerFrameItemButtonTemplate" and bagButton:GetParent():GetID() == 5,
		"a bag's button for the bank bag")
	local free = Section(ns.bank, "free").free[1]
	equal(free.bag .. "/" .. free.slot, "-1/3", "items dropped go into the bank's own slots first")
	-- A bank slot's tooltip: the item, and who has how many.
	Mock.Enter(state, button)
	local text = Plain(env.GameTooltip:Text())
	check(text:find("Silk Cloth", 1, true) and text:find("Vedek | 20 (bank 20)", 1, true), "tooltip with counts\n" .. text)
	Mock.Leave(state, button)
	-- Closing Knapsack's bank window ends the visit.
	ns.bank:Hide()
	equal(state.closedBank, 1, "CloseBankFrame")
	LeaveClassicBank(client)
	state.time = state.time + 3600
	ns.ToggleBank()
	local tile = TileFor(ns.bank, 4306)
	check(tile and not ns.Tiles.Secure.Attached(tile), "the recorded bank away from it")
	NoErrors(client)
end)

test("Classic: charges and unusable items are read from the game's tooltip lines", function()
	local client = StartClassic(function(_, state)
		state.containers[1].items[2] = { id = 20749, charges = 5 }
		state.containers[1].items[3] = { id = 20749, charges = 3 }
		state.containers[1].items[5] = { id = 10205 } -- plate, and Vedek is a priest
		state.containers[1].items[6] = { id = 13446, count = 2 } -- a potion above his level
	end)
	local env = client.env
	local bags = OpenBags(client)
	local oil = TileFor(bags, 20749)
	check(oil and oil.record.stacks and #oil.record.stacks == 2, "one tile for both oils")
	equal(oil and oil.record.charges, 3, "the one with the fewest charges is used first")
	local items = env.KnapsackDB.characters["Vedek-Doomhowl"].bags[1].items
	equal(items[2].charges, 5, "recorded")
	equal(items[3].charges, 3, "both")
	check(TileFor(bags, 10205).record.unusable, "plate: red on the right")
	check(TileFor(bags, 13446).record.unusable, "a potion above the character's level: a red line")
	check(not TileFor(bags, 12345).record.unusable, "not for red durability or disenchant lines")
	check(env.KnapsackScanTooltip and not env.KnapsackScanTooltip:IsShown(), "read with a hidden tooltip")
	NoErrors(client)
end)

test("Classic: item tooltips list every character's count", function()
	local client = StartClassic(function(_, state)
		state.saved = Other({})
	end)
	local state, env = client.state, client.env
	local bags = OpenBags(client)
	Mock.Enter(state, client.ns.Tiles.Secure.Attached(TileFor(bags, 2589)))
	local text = Plain(env.GameTooltip:Text())
	check(text:find("Vedek | 20 (bags 20)", 1, true), "mine\n" .. text)
	check(text:find("Aria | 47 (bags 7, bank 40)", 1, true), "hers\n" .. text)
	check(text:find("Total | 67", 1, true), "total\n" .. text)
	env.ItemRefTooltip:SetOwner(env.UIParent)
	env.ItemRefTooltip:SetHyperlink(Mock.Link(2589))
	text = Plain(env.ItemRefTooltip:Text())
	check(text:find("Aria | 47", 1, true), "a link's tooltip too\n" .. text)
	NoErrors(client)
end)

test("Classic: a whole category into the bank and back out", function()
	local client = StartClassic(function(_, state)
		ClassicBank(state)
	end)
	local state, ns = client.state, client.ns
	local bags = OpenBags(client)
	VisitClassicBank(client)
	local entry = MenuEntry(client, bags, "tradegoods", "Put all in the bank")
	check(entry, "at the bank")
	entry.callback()
	Settle(client)
	check(not Section(bags, "tradegoods"), "no trade goods left in the bags")
	local moved = state.containers[-1].items[3]
	check(moved and moved.id == 2589, "the cloth went into the bank's own slots")
	check(state.chat[#state.chat]:find("Moved 1 items to the bank", 1, true), "says so: " .. state.chat[#state.chat])
	entry = MenuEntry(client, ns.bank, "tradegoods", "Take all out of the bank")
	check(entry, "and out again from the bank window")
	entry.callback()
	Settle(client)
	local left = state.containers[-1].items
	check(not left[1] and not left[2] and not left[3], "out of the bank's own slots")
	check(Section(bags, "tradegoods"), "back in the bags")
	NoErrors(client)
end)

test("Classic: combine stacks in the bank's own slots and bank bags", function()
	local client = StartClassic(function(_, state)
		ClassicBank(state)
		state.containers[-1].items[3] = { id = 4306, count = 5 }
		state.containers[5].items[4] = { id = 4306, count = 6 }
	end)
	local state, ns = client.state, client.ns
	VisitClassicBank(client)
	Mock.Click(ns.bank.combineButton)
	Settle(client)
	equal(Stacks(state, 4306), "11,20", "Silk Cloth in the bank")
	NoErrors(client)
end)

test("Classic: /knapsack fill bank fills the bank's own slots and bank bags from the bags", function()
	local client = StartClassic(function(_, state)
		ClassicBank(state) -- Elemental Water 5 in the bank's own slots, Sharp Claw 2 in the bank bag
		state.containers[1].items[2] = { id = 7070, count = 10 }
	end)
	local state, env = client.state, client.env
	VisitClassicBank(client)
	env.SlashCmdList.KNAPSACK("fill bank")
	Settle(client)
	equal(state.containers[-1].items[2].count, 15, "the water in the bank's own slots")
	equal(state.containers[1].items[2], nil, "all of the bags' water went")
	equal(state.containers[5].items[3].count, 5, "the claws in the bank bag took the bags' claws")
	equal(state.containers[0].items[4], nil, "none left in the bags")
	NoErrors(client)
end)

test("Classic: the bank's bag slots change bank bags and buy more", function()
	local client = StartClassic(function(_, state)
		ClassicBank(state)
		state.saved = { settings = { bankBar = true } }
	end)
	local state, env, ns = client.state, client.env, client.ns
	VisitClassicBank(client)
	local bank = ns.bank
	check(bank.bagBar and bank.bagBar:IsShown(), "shown")
	local slots = bank.bagBar.slots
	equal(#slots, 8, "the bank's own slots and seven bank bag slots")
	equal(slots[1].bag, -1, "the bank's own slots first")
	equal(slots[1].count:GetText(), "28", "how many")
	check(slots[2].link and slots[2].link:find("Linen Bag", 1, true), "the bag in the first bank bag slot")
	check(not slots[3].forSale and slots[3].link == nil, "a bought slot without a bag")
	check(slots[4].forSale and slots[8].forSale, "slots not bought yet")

	-- Pointing at the bank's own slots shows their items.
	Mock.Enter(state, slots[1])
	equal(TileFor(bank, 4306):GetAlpha(), 1, "the silk is in them")
	check(TileFor(bank, 5635):GetAlpha() < 1, "the claws are not")
	Mock.Leave(state, slots[1])

	-- Changing bank bags, as with the game's own.
	Mock.CallScript(slots[2], "OnDragStart")
	equal(state.bagMoves[1], "pickup 68", "a bank bag is picked up")
	Mock.CallScript(slots[3], "OnReceiveDrag")
	equal(state.bagMoves[2], "put 69", "and put in another bank bag slot")
	-- An item clicked onto the bank's own slots goes into the first free one.
	env.C_Container.PickupContainerItem(0, 2) -- the Linen Cloth
	Mock.Click(slots[1])
	local moved = state.containers[-1].items[3]
	check(moved and moved.id == 2589, "into the bank")

	-- Buying the next bank bag slot, after asking.
	Mock.Enter(state, slots[6])
	local text = Plain(env.GameTooltip:Text())
	check(text:find("costs 10g 0s 0c", 1, true), "what the next one costs\n" .. text)
	Mock.Leave(state, slots[6])
	Mock.Click(slots[6])
	local dialog = env.KnapsackConfirmDialog
	check(dialog and dialog:IsShown() and dialog.text:GetText():find("10g 0s 0c", 1, true), "asks first")
	Mock.Click(dialog.yes)
	Mock.Advance(state, 1)
	equal(state.bankBagSlots, 3, "bought")
	equal(state.money, 123456 - 100000, "for its price")
	check(not slots[4].forSale and slots[5].forSale, "the next slot is bought, not the one clicked")
	-- Without the gold for the next one it says so, and asks nothing.
	state.money = 5
	Mock.Click(slots[5])
	check(not dialog:IsShown(), "no question")
	check(state.chat[#state.chat]:find("not have enough gold", 1, true), "says why: " .. state.chat[#state.chat])

	-- Away from the bank the slots are as recorded, and nothing is bought.
	LeaveClassicBank(client)
	ns.ToggleBank()
	check(bank.bagBar:IsShown() and slots[5].forSale and not slots[5].live, "as recorded")
	Mock.Click(slots[5])
	check(not dialog:IsShown(), "nothing to buy away from the bank")
	Mock.Click(bank.bagToggle)
	check(not bank.bagBar:IsShown(), "hidden with its button")
	equal(env.KnapsackDB.settings.bankBar, false, "remembered")
	NoErrors(client)
end)

test("Classic: a bag goes into the bank bag slot it is dropped on", function()
	-- One bank bag slot bought, with no bag in it yet.
	local client = StartClassic(function(_, state)
		state.containers[-1] = { size = 28, items = {} }
		state.bankBagSlots = 1
		state.saved = { settings = { bankBar = true } }
	end)
	local state, ns = client.state, client.ns
	equal(table.concat(ns.C.BANK_BAGS, ","), "-1,5,6,7,8,9,10,11", "the bank's containers, not the enum's")
	VisitClassicBank(client)
	local slots = ns.bank.bagBar.slots
	local first = slots[2]
	equal(first.bag, 5, "the first bank bag slot is container 5")
	check(first:IsShown() and not first.forSale, "shown, and bought, though empty")
	check(slots[3].forSale, "the second is not bought")
	state.cursor = 4238 -- a Linen Bag held
	Mock.CallScript(first, "OnReceiveDrag")
	equal(state.bagMoves[1], "put 68", "into the first bank bag slot")
	NoErrors(client)
end)

test("Classic: the mailbox is read through the game's tooltip lines too", function()
	local client = StartClassic()
	OpenMailbox(client, {
		{ sender = "Aria", subject = "Oil", daysLeft = 10, items = { { id = 20749, charges = 2 } } },
	})
	Mock.Fire(client.state, "MAIL_CLOSED")
	local mail = client.env.KnapsackDB.characters["Vedek-Doomhowl"].mail
	equal(mail and mail.mails[1].items[1].charges, 2, "charges of mailed items")
	NoErrors(client)
end)

--------------------------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
