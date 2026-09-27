local _, ns = ...
local C = ns.C

-- Everything is saved account-wide in KnapsackDB:
--   settings    options; only changed values are saved (see DEFAULTS)
--   categories  order, hidden and renamed categories, custom categories and
--               items dragged into a category (see Categories.lua)
--   characters  each character's bags, bank and mail, by "Name-Realm"
--               ("First Last-Realm" on Forever, see DB.Player)
--   guilds      guild vault snapshots, by "Guild-Realm"
--   positions   where each window was left

local DB = {}
ns.DB = DB

local _G = _G
local pairs, ipairs, type, select, rawset, sort, lower = pairs, ipairs, type, select, rawset, table.sort, string.lower

DB.DEFAULTS = {
	replaceBags = true, -- take over the game's bags
	replaceBank = true, -- show the bank in Knapsack instead of Blizzard's window
	columns = 12, -- items per row in the bags window
	bankColumns = 14, -- items per row in the bank and guild vault windows
	tileSize = 36,
	scale = 1,
	compact = true, -- small categories side by side
	borderSize = 2, -- quality border, in screen pixels
	itemLevel = true, -- item level on gear
	unusableTint = true, -- red, colorless icons for items the character cannot use
	mergeStacks = true, -- one tile for all stacks of an item
	bindMarker = true, -- "BoE" / "BoU" on items that can still be traded
	newFirst = true, -- a New section at the top of the bags until they close
	bagBar = false, -- bag slots under the bags
	bankBar = false, -- bank bag slots under the bank (Classic)
	sortMode = "quality", -- "quality", "name" or "type"
	junkByValue = true, -- junk sorted by vendor value, cheapest first
	junkValueText = true, -- vendor value shown on junk items
	tooltipCounts = true, -- other characters' counts in item tooltips
	showSurnames = false, -- "Vedek Md", not "Vedek" (Forever); shown anyway to tell apart two with one first name
}

local VERSION = 1

-- Until KnapsackDB loads, everything reads empty tables and the defaults.
DB.settings = setmetatable({}, { __index = DB.DEFAULTS })
DB.categories, DB.characters, DB.guilds, DB.positions = {}, {}, {}, {}

function DB.Load()
	local saved = _G.KnapsackDB
	if type(saved) ~= "table" then
		saved = {}
		_G.KnapsackDB = saved
	end
	saved.version = saved.version or VERSION
	for _, key in ipairs({ "settings", "categories", "characters", "guilds", "positions" }) do
		if type(saved[key]) ~= "table" then
			saved[key] = {}
		end
	end
	DB.settings = setmetatable(saved.settings, { __index = DB.DEFAULTS })
	DB.categories = saved.categories
	DB.characters = saved.characters
	DB.guilds = saved.guilds
	DB.positions = saved.positions
end

function DB.Set(key, value)
	if value == DB.DEFAULTS[key] then
		value = nil -- keep the saved file to what differs from the defaults
	end
	rawset(DB.settings, key, value)
end

--------------------------------------------------------------------------------
-- Change notifications
--------------------------------------------------------------------------------

-- Modules announce what changed ("bags", "bank", "guild", "items", "settings",
-- "categories", ...) and windows or the tooltip refresh themselves.
local listeners = {}

function ns.Listen(what, callback)
	local list = listeners[what]
	if not list then
		list = {}
		listeners[what] = list
	end
	list[#list + 1] = callback
end

function ns.Send(what, ...)
	local list = listeners[what]
	if list then
		for i = 1, #list do
			list[i](...)
		end
	end
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------

-- Forever characters also have a surname, which UnitName gives as its second
-- value (on Retail that is the realm, and nil for the player). Mail and chat
-- call them by both: "Vedek Md". Characters can share a first name, so on
-- Forever a character's key is "First Last-Realm"; elsewhere "Name-Realm".
DB.SURNAME_SEPARATOR = (_G.Constants and _G.Constants.CharacterNameSeparatorConsts
	and _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "

local function PlayerSurname()
	if not C.isForever then
		return nil
	end
	local _, surname = (_G.UnitNameUnmodified or UnitName)("player")
	surname = C.Clean(surname)
	if type(surname) == "string" and surname ~= "" then
		return surname
	end
	return nil
end

-- The logged-in character: { name, surname, realm, realmName, key }. Nil
-- until the client knows the realm (PLAYER_LOGIN).
function DB.Player()
	if not DB.player then
		local name = C.Clean((UnitName("player")))
		local realm = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
		if not name or not realm or realm == "" then
			return nil
		end
		local surname = PlayerSurname()
		DB.player = {
			name = name,
			surname = surname,
			realm = realm,
			realmName = GetRealmName() or realm,
			key = (surname and (name .. " " .. surname) or name) .. "-" .. realm,
		}
	end
	return DB.player
end

function DB.PlayerKey()
	local player = DB.Player()
	return player and player.key
end

function DB.Character(key, create)
	local char = key and DB.characters[key]
	if not char and create and key then
		char = {}
		DB.characters[key] = char
	end
	return char
end

-- Before surnames were part of the key, a Forever character was saved as
-- "Name-Realm": its record moves to "First Last-Realm" the first time it is
-- looked up, unless that record belongs to another character with the same
-- first name.
local function MoveOldRecord(player)
	if not player.surname or DB.characters[player.key] then
		return
	end
	local oldKey = player.name .. "-" .. player.realm
	local old = DB.characters[oldKey]
	if old and (not old.surname or lower(old.surname) == lower(player.surname)) then
		DB.characters[player.key] = old
		DB.characters[oldKey] = nil
	end
end

function DB.PlayerCharacter()
	local player = DB.Player()
	if not player then
		return nil
	end
	MoveOldRecord(player)
	return DB.Character(player.key, true)
end

-- The player's guild as "Guild-Realm", false when not in a guild, or nil when
-- the client has not loaded the guild yet.
function DB.PlayerGuildKey()
	if not IsInGuild() then
		return false
	end
	local name, _, _, realm = GetGuildInfo("player")
	name, realm = C.Clean(name), C.Clean(realm)
	if not name then
		return nil
	end
	local player = DB.Player()
	return name .. "-" .. (realm or (player and player.realm) or "")
end

-- A character's name as mail and chat show it: "Vedek Md", or "Vedek".
function DB.FullName(char)
	if char.surname then
		return char.name .. DB.SURNAME_SEPARATOR .. char.surname
	end
	return char.name
end

-- The name to show for a character: its first name, or first and last when
-- surnames are shown, or when another character has the same first name.
function DB.DisplayName(char)
	if not char.surname then
		return char.name
	end
	if DB.settings.showSurnames then
		return DB.FullName(char)
	end
	for _, other in pairs(DB.characters) do
		if other ~= char and other.name == char.name then
			return DB.FullName(char)
		end
	end
	return char.name
end

function DB.UpdatePlayerInfo()
	local player = DB.Player()
	local char = player and DB.PlayerCharacter()
	if not player or not char then
		return
	end
	char.name = player.name
	char.surname = player.surname or char.surname
	char.realm = player.realmName
	char.class = select(2, UnitClass("player"))
	char.level = UnitLevel("player")
	char.faction = UnitFactionGroup("player")
	char.money = GetMoney()
	local guild = DB.PlayerGuildKey()
	if guild ~= nil then
		char.guild = guild or nil
	end
	char.seen = time()
end

-- Every stored character, sorted by realm then name: { key, char }.
function DB.CharacterList()
	local list = {}
	for key, char in pairs(DB.characters) do
		list[#list + 1] = { key = key, char = char }
	end
	sort(list, function(a, b)
		local ra, rb = a.char.realm or "", b.char.realm or ""
		if ra ~= rb then
			return ra < rb
		end
		local na, nb = a.char.name or a.key, b.char.name or b.key
		if na ~= nb then
			return na < nb
		end
		return (a.char.surname or "") < (b.char.surname or "")
	end)
	return list
end

function DB.DeleteCharacter(key)
	DB.characters[key] = nil
	ns.Send("characters")
end

--------------------------------------------------------------------------------
-- Guilds
--------------------------------------------------------------------------------

function DB.Guild(key, create)
	local guild = key and DB.guilds[key]
	if not guild and create and key then
		guild = { tabs = {} }
		DB.guilds[key] = guild
	end
	return guild
end

function DB.GuildList()
	local list = {}
	for key, guild in pairs(DB.guilds) do
		list[#list + 1] = { key = key, guild = guild }
	end
	sort(list, function(a, b)
		return (a.guild.name or a.key) < (b.guild.name or b.key)
	end)
	return list
end

function DB.DeleteGuild(key)
	DB.guilds[key] = nil
	ns.Send("guilds")
end
