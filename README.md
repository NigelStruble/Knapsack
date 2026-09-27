# Satchel

A bag addon for WoW: Forever and Burning Crusade Classic Anniversary. Items
are sorted into categories, all grey items go into a Junk category sorted by
vendor value, and the bank, the mail, the guild vault and your other
characters' bags can be looked at from anywhere.

## Features

- **Categories.** Equipment, Consumables, Reagents, Trade Goods, Recipes, Quest
  Items, Ammo, Bags, Keys, Miscellaneous and Junk. You can hide, rename and
  reorder them, and make your own.
- **Junk.** Every Poor (grey) item goes into Junk, whatever kind of item it is.
  Junk is sorted by what the whole stack sells for, cheapest first, so the
  first junk item is always the one to throw away. Each junk item shows its
  value, and the category title shows the total.
- **Your own categories.** A category can take items by quality, item type,
  binding (such as Bind on Equip gear that is not bound yet) or part of their
  name, and you can drop any item onto a category's title to keep it there.
- **Find anything.** Type part of an item's name to see every place you have
  it: each character's bags, bank and mail, and your guild vaults.
- **Search keywords.** Every search box also takes words such as `boe`,
  `soulbound`, `junk`, `epic`, `gear` or `ilvl>30` (see
  [Searching](#searching)).
- **New items first.** What you just looted goes in a New section at the top
  of the bags until you close them.
- **Tradable at a glance.** Items that are Bind on Equip or Bind on Use and
  not bound yet say BoE or BoU in the corner.
- **Move a whole category.** At the bank, put a whole category in the bank or
  take it out; at a mailbox, mail a whole category to one of your characters.
- **Merged stacks.** All stacks of an item show as one tile with the total,
  even when different players made them. Using a merged tile uses the
  smallest stack first, and for items with charges (such as Wizard Oil) the
  one with the fewest charges left; its tooltip lists the charges of each.
  Gear always shows piece by piece, and everything in your bags shows stack by
  stack while a mailbox's send page, a trade, the auction house, the bank or
  the guild vault is open, since those take one stack at a time.
- **Charges on other characters' items.** The game only shows an item's
  charges for your own bags, so Satchel records them, and other characters'
  items show theirs in the tooltip.
- **Combine stacks.** One click fills up partial stacks of the same item, so
  they take fewer slots, in the bags or, at the bank, in the bank. At the bank,
  shift-click fills them up from the other side first: the bank's partial
  stacks from your bags, or your bags' from the bank.
- **Item level and usability.** Gear shows its item level, and items your
  character cannot use (gear it cannot wear or wield, recipes it cannot learn,
  items it is too low level or unskilled for) are red.
- **Everyone's gold.** Point at your gold in the bags to see every character's
  gold and the total.
- **The bank from anywhere.** The bank is recorded each time you visit it. At
  the bank, Satchel is the bank; anywhere else it shows the bank as it was,
  and how long ago that was.
- **The mail from anywhere.** Each character's mailbox is recorded at the
  mailbox, and every item shows how long until it goes back to its sender (or
  is deleted). Mail your characters send each other shows in the other's
  mailbox at once, without visiting it, and so does mail they return to each
  other, or that goes back because nobody collected it in time.
- **The guild vault from anywhere.** Every tab you can see is recorded each
  time you open the vault, with the guild's gold.
- **Bag slots.** Your bag slots can be shown under the bags, to change bags
  with the game's own bag bar hidden. On Anniversary the bank's bag slots can
  be shown under the bank the same way, and more of them bought there.
- **The keyring** (Anniversary). Keys on the keyring show in the bags window,
  in Keys. The keyring grows by four slots as it fills, so its empty slots are
  not counted or shown as free space.
- **Other characters.** Each character's bags are recorded while you play it,
  and its bank when it visits one. Pick any of them in the bags window.
- **Tooltips.** Item tooltips list how many each character carries, keeps in
  the bank and has waiting in the mail, and how many are in your guild vaults.
- **Works like the default bags.** Using, selling, depositing, splitting stacks,
  dragging, linking in chat, cooldowns and the glow on new items all behave as
  they do in the game's own bags, because the game's own item buttons do the
  work.
- **EllesmereUI's skin.** If EllesmereUI is installed, Satchel uses its skin,
  so the windows follow your EllesmereUI theme and accent color.

## Supported game versions

| Game | Folder | Interface |
|---|---|---|
| WoW: Forever | `_classic_beta_` (beta) | 16001 |
| Burning Crusade Classic Anniversary | `_anniversary_` | 20506 |
| Retail (Midnight) | `_retail_` | 120100, 120105 |

On Retail, the Warband bank is not shown.

## Installing

1. Copy the `Satchel` folder into the game's AddOns folder, for example
   `World of Warcraft\_classic_beta_\Interface\AddOns\Satchel` or
   `World of Warcraft\_anniversary_\Interface\AddOns\Satchel`, and restart the
   game (a new addon is only found at start-up, not by `/reload`).
2. In the AddOns list, turn off any other bag addon, such as BetterBags,
   Bagnon, AdiBags or Baganator. If you use ElvUI, turn off its bags: ElvUI's
   options, **Bags**, **Enable**.

That's all. The bag keys, the bag buttons, and anything else that opens the
bags (such as data bars and broker plugins) now open Satchel.

If another bag addon is still on, Satchel leaves the bags to it and says so in
chat. It still records your bank, guild vault and characters, and `/satchel`
opens its windows to look at them.

## Using it

### The bags window

- **Top:** whose bags you are looking at, **Bank**, **Mail**, **Vault**,
  search, **Find** (the magnifier: search every character), **Combine
  stacks** (the broom), options and close.
- **Combine stacks:** the broom combines partial stacks in the bags (in the
  bank window, in the bank). Shift-click it at the bank to fill them up from
  the other side first: in the bank window, the bank's partial stacks take
  what your bags have of the same item; in the bags window, your bags' partial
  stacks take what the bank has. The other side's smallest stacks go first,
  and soulbound and unbound stacks are never mixed.
- **Moving it:** drag any empty part of the window: the top, the space between
  items, or the bottom.
- **Categories** that fit side by side share a row.
- **Items:** the stack count (the total, for merged stacks) is bottom right,
  the item level of gear top left, and a junk item's value bottom left. Using
  or selling a merged tile takes its smallest stack first, or the item with the
  fewest charges left.
- **Free:** the last tile shows your free slots. Drop an item on it to put the
  item in an empty slot. Quivers and other special bags get their own tile;
  the keyring's empty slots are not shown.
- **Category titles:** drop an item on a title to keep that item in that
  category from now on. Middle-click the item to put it back where it would go
  on its own. Right-click a title to hide it or move it, and:
  - at the bank, **Put all in the bank** (in the bags) or **Take all out of
    the bank** (in the bank) moves every item of that category;
  - at a mailbox, **Mail all to** sends every item of that category that can
    be mailed to one of your characters, twelve to a mail, after asking.
  These moves stop if you enter combat or pick something up.
- **New:** items you just got sit at the top until you close the bags, even
  after you have looked at them.
- **Bottom:** the bag slots button, used and total slots (quivers, soul bags,
  profession bags and the keyring are not counted) and your gold. Point at the
  gold for every character's gold.
- **Bag slots:** the backpack button at the bottom left shows your bag slots
  under the items. Drop a bag on a slot to wear it there, drag a bag off its
  slot to move or remove it, or click a slot with an item held to put the item
  in that bag. Point at a slot to see which items are in that bag. Other
  characters' bags show as they were when last played.

### The bank

At a banker, Satchel's bank window opens next to your bags and is the bank:
right-click an item in the bank to take it out, right-click an item in your
bags to put it in, or drag items between the two. Drop items on the bank's
**Free** tile to put them in the bank.

The **Blizzard** button shows the game's own bank window, which you need for
buying more bank tabs and changing their settings. On Forever a new
character's first bank tab (48 slots) is free but has to be unlocked: the bank
window then shows the game's own words about it and an **Unlock bank tab**
button, which goes through the game's confirmation like the game's own bank
window does. Right after the bank opens, its tabs can take a moment to arrive:
the bank window says it is loading, and moving a category into the bank waits
for it.

Away from the bank, the **Bank** button (or `/satchel bank`) shows the bank as
it was when you were last there. Other characters' banks are shown the same
way, once they have visited a bank with Satchel on.

On Anniversary the bank is its own 28 slots and up to seven bank bags, shown
together like the bags. Items dropped on the **Free** tile go into the bank's
own slots first. The button at the bottom left of the bank window shows the
bank's bag slots: the bank's own slots, then the seven bank bag slots. They
work like the bag slots under the bags (drop a bag on one, drag a bag off it,
click one with an item held to put the item in). Slots not bought yet are red;
clicking one buys the next slot, after saying what it costs. The **Blizzard**
button shows the game's own bank window; hiding it again ends the visit, as
closing it does in the game.

### The mail

The **Mail** button (or `/satchel mail`) shows what waits in a character's
mailbox, sorted into categories like the bags, with the items that go back
soonest first. The corner of each item shows the time left: red under a day,
orange under three days. Its tooltip says who it is from, and whether it goes
back to them or is deleted when the time runs out (mail that already came back
once, and mail from the auction house, is deleted).

A mailbox is recorded each time that character opens one. Mail between your
characters is added as it is sent, so an item mailed to an alt shows in the
alt's mail at once. The same goes for mail one of them returns to another, and
for mail that goes back to its sender because it was not collected in time.
Mail from other players only shows once the character has been to a mailbox.

### Searching

The search box in each window dims what does not match; Find (below) shows
only what does. The x at the end of the box (or Escape) empties it and gives
the keyboard back to the game. Both take the same words, and an item must
match all of them:

| Type | Finds |
|---|---|
| `linen`, `wizard oil` | Items with that in their name |
| `boe`, `bou` | Bind on Equip / Bind on Use items not bound yet |
| `soulbound`, `tradable` | Items that are soulbound, or not |
| `junk`, `common`, `uncommon`, `rare`, `epic`, `legendary` | Items of that quality |
| `gear`, `consumable`, `reagent`, `tradegoods`, `recipe`, `quest` | Items of that kind |
| `new`, `charges`, `unusable` | New items, items with charges, items you cannot use |
| `ilvl>30`, `ilvl<=20`, `ilvl=25` | Gear by item level |
| `!soulbound` | `!` turns a word around |
| `#new` | `#` means the keyword, not a name |

### Finding an item

The magnifier in the bags window (or `/satchel find linen`) opens **Find**.
Type at least two letters of an item's name and it shows every place you have
that item, one section per place: each character's bags, bank and mail, and
each guild vault, starting with the character you are playing. The footer adds
them all up, and each item's tooltip says who has how many.

### The guild vault

Open the guild vault once and Satchel records every tab you can see. It asks
the server for one tab after another, so leave the vault open for a few
seconds. Tabs you cannot see are not recorded. The **Vault** button then shows
the vault from anywhere, with the guild's gold and when it was recorded.

### Other characters

Log in each character once with Satchel on, and visit a bank with it. After
that, choose it at the top of the bags or bank window. Its items show their
tooltips and can be shift-clicked into chat.

## Commands and keys

| Command | Does |
|---|---|
| `/satchel` | Open or close the bags |
| `/satchel bank` | Open or close the bank |
| `/satchel mail` | Open or close the mail |
| `/satchel vault` | Open or close the guild vault |
| `/satchel find linen` | Find an item on all your characters |
| `/satchel stack` | Combine partial stacks in the bags |
| `/satchel stack bank` | Combine partial stacks in the bank (at the bank) |
| `/satchel fill` | Fill partial stacks in the bags from the bank, then combine (at the bank) |
| `/satchel fill bank` | Fill partial stacks in the bank from the bags, then combine (at the bank) |
| `/satchel charges` | Show the charges line of each item in your bags as the game gives it, and the charges Satchel reads from it (for reporting problems) |
| `/satchel options` | Open or close the options |

Keys can be set in the game's key bindings, under **Satchel**. In the addon
compartment by the minimap, left-click opens the bags and right-click the
options.

## Options

- **General:** whether Satchel replaces the bags and the bank (after a
  `/reload`), items per row, item size, scale, whether small categories share
  a row, merging stacks, new items first, item levels, the BoE / BoU marks,
  red for items you cannot use, the width of the quality border (in screen
  pixels, so it stays sharp at any scale), how items are sorted, the junk
  options and the tooltip counts.
- **Categories:** show, hide, rename and reorder categories; make your own with
  rules for quality, item type, binding and name; forget items dropped into a
  category. For a group of Bind on Equip items you can still sell, make a
  category and set only its Binding to "Bind on Equip, not bound yet".
- **Characters:** forget characters and guild vaults you no longer play. On
  Forever, **Show surnames** shows your characters' first and last names
  everywhere; characters that share a first name always show both.

## Development

```
Satchel/
  Satchel.toc     Interface numbers and load order
  Bindings.xml    Key bindings
  Locales.lua     Strings (English; other languages can be added here)
  Compat.lua      Game version, API wrappers, events
  Database.lua    Saved data, characters and guilds
  Items.lua       Item details (name, quality, vendor price, item level),
                  loaded on demand; items you cannot use; items with charges
  Categories.lua  Built-in and custom categories, and which one an item goes in
  Search.lua      What the search boxes understand (names, keywords, levels)
  Sort.lua        The order of items within a category
  Scanner.lua     Reading and recording the bags, bank and guild vault
  Mail.lua        Reading and recording the mail, and mail between characters
  Stack.lua       Combining partial stacks
  Widgets.lua     Flat controls, shared with Missing Buffs
  Transfer.lua    Moving a whole category into the bank, out of it, or by mail
  Skin.lua        EllesmereUI's skin, when it is installed
  Tiles.lua       Item tiles, and Blizzard's item buttons over them
  BagBar.lua      The bag slots under the bags (and on Anniversary the bank)
  Window.lua      The bags, bank, mail and guild vault windows
  Takeover.lua    Making the game open Satchel instead of its own bags
  Tooltip.lua     Counts per character in item tooltips
  Options.lua     The options window
  Core.lua        Startup and /satchel
tests/            Tests run against a mock of the WoW API
```

Run the tests with Lua 5.1 from the repository root:

```
lua5.1 tests/run_tests.lua
```

The mock also records breaking the rules for Blizzard's item buttons
(creating one in combat, or writing into one), and the tests fail if that
happens. It plays the Retail engine by default; `Mock.New({ classic = true })`
makes it an Anniversary client (a bank of one container and bank bags, a
keyring, no `C_TooltipInfo`, `OnTooltipSetItem`), which the "Classic:" tests
use.

While developing, you can link the `Satchel` folder into the game's AddOns
folder (a directory junction or symbolic link) instead of copying it, so
changes show up after a `/reload`.

When a patch changes the interface number, add the new number to the
`## Interface:` line in `Satchel.toc`.
