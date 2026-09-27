local _, ns = ...
local C, DB, Items = ns.C, ns.DB, ns.Items

-- Each character's mail: read whenever that character is at a mailbox, and
-- added to as your characters send each other mail (and return it), so what
-- waits in whose mailbox, and when it goes back, can be seen from anywhere.
--
-- char.mail = {
--   time   when the mailbox was last read (nil if it never was)
--   more   mails the mailbox did not show (it shows 50 at most)
--   mails  { mail, ... }
-- }
-- mail = {
--   sender, subject, money, cod
--   expires   time() it goes back to the sender, or is deleted
--   returns   true: it goes back to the sender then; false: it is deleted
--   returned  it came back to this character
--   sent      time() one of your characters sent or returned it, for mail
--             not yet seen in the mailbox
--   items     { { link, count, quality, charges }, ... }
-- }

local Mail = {}
ns.Mail = Mail

local _G = _G
local ipairs, pairs, time, floor, max, lower, tinsert = ipairs, pairs, time, math.floor, math.max, string.lower, table.insert

local DAY = 86400
local KEEP_DAYS, COD_DAYS = 30, 3 -- how long mail waits, and cash on delivery mail

local function MaxReceive()
	return _G.ATTACHMENTS_MAX_RECEIVE or 16
end

local function MaxSend()
	return _G.ATTACHMENTS_MAX_SEND or 12
end

-- A mail's items, with the link of each (made up from the item ID when the
-- game has no link yet).
local function Attachment(itemID, link, count, quality, charges)
	itemID = C.Clean(itemID)
	if not itemID then
		return nil
	end
	link = C.Clean(link) or select(2, C.ItemInfo(itemID)) or ("item:" .. itemID)
	return { link = link, count = C.Clean(count) or 1, quality = C.Clean(quality), charges = charges }
end

--------------------------------------------------------------------------------
-- Whose mail
--------------------------------------------------------------------------------

-- The names mail can call a character by, lower case: "vedex", and on
-- Forever, where characters have surnames, "vedex vicious".
local function NamesOf(char)
	local names = { lower(char.name) }
	if char.surname then
		names[2] = lower(char.name .. " " .. char.surname)
		names[3] = lower(DB.FullName(char))
	end
	return names
end

-- The key of one of your characters from a name as mail shows or takes it:
-- "Vedex", "Vedex Vicious", or either with "-Realm" after it. homeRealm is the
-- realm of a name without one. Nil for anyone else. The second value is the
-- surname the name gave, for a character whose surname is not known yet.
local function CharacterKey(text, homeRealm)
	text = C.Clean(text)
	if type(text) ~= "string" then
		return nil
	end
	local original = text:match("^%s*(.-)%s*$")
	text = lower(original)
	if text == "" then
		return nil
	end
	homeRealm = homeRealm and lower(homeRealm)
	local byFirstName, guesses, surname = {}, {}, nil
	for key, char in pairs(DB.characters) do
		local keyRealm = key:match("%-(.+)$")
		if char.name and keyRealm then
			keyRealm = lower(keyRealm)
			local realmName = char.realm and lower(char.realm)
			local function Named(name)
				return (text == name and keyRealm == homeRealm) or text == name .. "-" .. keyRealm
					or (realmName and text == name .. "-" .. realmName)
			end
			local names = NamesOf(char)
			for i = 2, #names do
				if Named(names[i]) then
					return key -- first and last name: only one character
				end
			end
			if Named(names[1]) then
				byFirstName[#byFirstName + 1] = key
			end
			-- A surname not known yet: the first name decides.
			if not char.surname and keyRealm == homeRealm then
				local bare = (original:match("^(.-)%-") or original):match("^%s*(.-)%s*$")
				local first, rest = bare:match("^(%S+)%s+(%S+)$")
				if first and lower(first) == lower(char.name) then
					guesses[#guesses + 1] = key
					surname = rest
				end
			end
		end
	end
	-- A first name alone only says who, when one character has it.
	if #byFirstName > 0 then
		return #byFirstName == 1 and byFirstName[1] or nil
	end
	if #guesses == 1 then
		return guesses[1], surname
	end
	return nil
end
Mail.CharacterKey = CharacterKey

local function RealmOf(key)
	return key and key:match("%-(.+)$")
end

--------------------------------------------------------------------------------
-- Reading the mailbox
--------------------------------------------------------------------------------

local mailOpen = false
local changed = false -- the mailbox changed and has not been recorded yet

-- Whether the character is at a mailbox.
function Mail.IsOpen()
	return mailOpen
end

local function Header(index)
	local _, _, sender, subject, money, cod, daysLeft, hasItem, _, wasReturned = GetInboxHeaderInfo(index)
	local mail = {
		sender = C.Clean(sender),
		subject = C.Clean(subject),
		money = C.Clean(money) or 0,
		cod = C.Clean(cod) or 0,
		expires = time() + floor((C.Clean(daysLeft) or 0) * DAY),
		returned = C.Clean(wasReturned) and true or nil,
		-- Mail that can be deleted instead of returned (mail that already
		-- came back, mail from the auction house) is deleted when it expires.
		returns = not C.Clean(InboxItemCanDelete(index)),
	}
	if C.Clean(hasItem) then
		mail.items = {}
		for attachment = 1, MaxReceive() do
			local _, itemID, _, count, quality = GetInboxItem(index, attachment)
			local link = C.Clean(itemID) and GetInboxItemLink(index, attachment)
			local item = Attachment(itemID, link, count, quality)
			if item then
				item.charges = Items.Charges(item.link, C.Clean(itemID), C.InboxTooltip, index, attachment)
				mail.items[#mail.items + 1] = item
			end
		end
	end
	return mail
end

function Mail.Save()
	if not changed then
		return
	end
	changed = false
	local char = DB.PlayerCharacter()
	if not char then
		return
	end
	local shown, total = GetInboxNumItems()
	shown, total = C.Clean(shown) or 0, C.Clean(total) or 0
	local mails = {}
	for index = 1, shown do
		mails[#mails + 1] = Header(index)
	end
	char.mail = { time = time(), more = max(0, total - shown), mails = mails }
	ns.Send("mail", DB.PlayerKey())
end

local QueueSave = C.Debounce(0.3, Mail.Save)

C.On("MAIL_SHOW", function()
	mailOpen = true
end)
-- A change not recorded yet is recorded as the mailbox closes.
C.On("MAIL_CLOSED", function()
	Mail.Save()
	mailOpen = false
end)
-- The mailbox has arrived, or changed (an item taken, a mail deleted). Only
-- at the mailbox does the game know what is in it.
C.On("MAIL_INBOX_UPDATE", function()
	if mailOpen then
		changed = true
		QueueSave()
	end
end)

--------------------------------------------------------------------------------
-- Mail between your characters
--------------------------------------------------------------------------------

-- Adds a mail to one of your characters' mailboxes, as sent now.
local function Deliver(key, mail)
	local char = DB.Character(key)
	if not char then
		return
	end
	local now = time()
	mail.sent = now
	mail.expires = now + ((mail.cod or 0) > 0 and COD_DAYS or KEEP_DAYS) * DAY
	char.mail = char.mail or {}
	char.mail.mails = char.mail.mails or {}
	tinsert(char.mail.mails, mail)
	ns.Send("mail", key)
end

-- The logged-in character's name as mail shows it: "Vedek Md" on Forever.
local function PlayerMailName()
	local char = DB.PlayerCharacter()
	return char and char.name and DB.FullName(char) or (DB.Player() and DB.Player().name)
end

-- The mail being sent, noted when it is sent and delivered once the game says
-- it went: { key, mail, surname }.
local outgoing

local function Sending(recipient, subject)
	outgoing = nil
	local player = DB.Player()
	if not player then
		return
	end
	local key, surname = CharacterKey(recipient, player.realm)
	if not key or key == player.key then
		return
	end
	local items = {}
	for attachment = 1, MaxSend() do
		local _, itemID, _, count, quality = GetSendMailItem(attachment)
		local link = C.Clean(itemID) and GetSendMailItemLink(attachment)
		local item = Attachment(itemID, link, count, quality)
		if item then
			item.charges = Items.Charges(item.link, C.Clean(itemID), C.SendMailTooltip, attachment)
			items[#items + 1] = item
		end
	end
	outgoing = {
		key = key,
		surname = surname,
		mail = {
			sender = PlayerMailName(),
			subject = C.Clean(subject),
			money = C.Clean(GetSendMailMoney()) or 0,
			cod = C.Clean(GetSendMailCOD()) or 0,
			items = #items > 0 and items or nil,
			returns = true,
		},
	}
end

-- A mail returned to one of your characters goes into its mailbox.
local function Returning(index)
	local player = DB.Player()
	if not player or C.Clean(InboxItemCanDelete(index)) then
		return -- nothing to return: the mail can only be deleted
	end
	local mail = Header(index)
	local key = CharacterKey(mail.sender, player.realm)
	if not key or key == player.key then
		return
	end
	Deliver(key, {
		sender = PlayerMailName(),
		subject = mail.subject,
		money = mail.money,
		cod = 0,
		items = mail.items,
		returned = true,
		returns = false,
	})
end

function Mail.Start()
	if _G.SendMail then
		hooksecurefunc("SendMail", Sending)
	end
	if _G.ReturnInboxItem then
		hooksecurefunc("ReturnInboxItem", Returning)
	end
end

C.On("MAIL_SEND_SUCCESS", function()
	local sending = outgoing
	outgoing = nil
	if not sending then
		return
	end
	-- The mail went to "First Last": that is the character's surname, until
	-- it logs in and says so itself.
	local char = DB.Character(sending.key)
	if char and sending.surname and not char.surname then
		char.surname = sending.surname
	end
	Deliver(sending.key, sending.mail)
end)
C.On("MAIL_FAILED", function()
	outgoing = nil
end)

--------------------------------------------------------------------------------
-- What is in a mailbox now
--------------------------------------------------------------------------------

-- The mails in a character's mailbox now, or nil if nothing is known about it:
-- the recorded mails that have not expired, and mail it sent to your other
-- characters that has gone back to it since its mailbox was last read.
function Mail.List(key)
	local char = DB.Character(key)
	if not char then
		return nil
	end
	local now = time()
	local list, known = {}, char.mail ~= nil
	local readAt = char.mail and char.mail.time or 0
	for _, mail in ipairs(char.mail and char.mail.mails or {}) do
		if (mail.expires or 0) > now then
			list[#list + 1] = mail
		end
	end
	for otherKey, other in pairs(DB.characters) do
		if otherKey ~= key and other.mail then
			for _, mail in ipairs(other.mail.mails or {}) do
				local expires = mail.expires or 0
				if mail.returns and expires <= now and expires > readAt and expires + KEEP_DAYS * DAY > now
					and CharacterKey(mail.sender, RealmOf(otherKey)) == key then
					list[#list + 1] = {
						sender = other.name and DB.FullName(other) or otherKey,
						subject = mail.subject,
						money = mail.money,
						cod = 0,
						items = mail.items,
						returned = true,
						returns = false,
						expires = expires + KEEP_DAYS * DAY,
						sent = expires,
						expired = true,
					}
					known = true
				end
			end
		end
	end
	return known and list or nil
end

-- One record per item, for a window (see Scanner.Records).
function Mail.Records(mails)
	local records = {}
	for m, mail in ipairs(mails) do
		for i, item in ipairs(mail.items or {}) do
			records[#records + 1] = {
				link = item.link,
				count = item.count or 1,
				quality = item.quality,
				charges = item.charges,
				mail = mail,
				expires = mail.expires,
				position = m * 100 + i,
			}
		end
	end
	return records
end

-- Items, mails and money in a list of mails.
function Mail.Totals(mails)
	local items, money = 0, 0
	for _, mail in ipairs(mails) do
		items = items + #(mail.items or {})
		money = money + (mail.money or 0)
	end
	return items, #mails, money
end

-- How many of an item wait in a character's mailbox.
function Mail.Count(key, itemID)
	local count = 0
	for _, mail in ipairs(Mail.List(key) or {}) do
		for _, item in ipairs(mail.items or {}) do
			if C.ItemIDFromLink(item.link) == itemID then
				count = count + (item.count or 1)
			end
		end
	end
	return count
end
