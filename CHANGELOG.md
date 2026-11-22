# Changelog

## 1.1.0

- **Sort by price.** **Sort items in a category by** can now sort by what each whole stack is worth, most or least valuable first. **Price to sort by** picks the vendor price, or the auction price from Auctionator or TradeSkillMaster; an item they have no price for uses its vendor price, and its tooltip says so. As in Junk, each item shows its price and each category title its total. **Show the price on each item** turns off the prices on the items, and the totals stay. BoE and BoU marks move to the top corner to make room, and a thousand gold or more shows as 1.5k.
- **Gear you have worn** has a small green check in the corner, so gear you keep for another set stands out from gear you only picked up. Copies are told apart: of two of the same sword, only the one you wore is marked, and its tooltip says "You have worn this." Gear in an equipment set counts as worn too. Gear you wore before this version counts once you put it on again. **Mark gear you have worn** turns the check off.
- **Worn gear in searches and your own categories.** The search keywords `worn` and `unworn` find either kind, and a category of your own can take only gear you have worn, or only gear you have not, with its new **Worn** rule: a ready-made list of gear to sell.
- **Equipment Sets**, a new category first in the bags, holds the gear of your equipment sets, so it never mixes with gear to sell, not even grey gear in Junk. On Forever these are the game's own sets, made in the character sheet's Equipment Manager or with ItemRack Forever, which keeps its sets there. On Anniversary they are ItemRack's sets; an ItemRack set takes the very item saved in it, with its enchant and gems. Your bank and your other characters' bags show it too, once Knapsack has seen them with this version. Your own categories and items dropped on a title still come first, and it can be hidden like any category. If you had moved Equipment, the new category goes just before it.
- **Nothing moves under the mouse while the bags are open.** 1.0.1 kept a gap where an item left, but icons could still move as other things changed. Now:
  - **Loot** landing in the bags, such as a disenchant's dust, moves nothing. A stack it lands on stays where it is and glows.
  - **An item that comes in** takes the first empty slot in its own category, so potions you buy go where the old ones were. Otherwise it goes in **Just added**, a new section at the very end, into an empty slot there if it has one. A category's title menu (at the bank or a mailbox) moves its items in Just added too.
  - **Levelling up**, or changing specialization, no longer rearranges the bags.
  - **The free space** no longer disappears when the bags are full: it shows 0, so opening a clam to free a slot just turns it into 1.
  - **The window grows downward** while it stays open. It used to grow upward from its bottom-right corner, which moved every icon whenever a row was added. Near the bottom of the screen it scrolls instead, and closing it puts it back where you left it.
  - **Categories keep their width**, so a title whose count or total changes no longer slides the categories beside it, and Just added starts a row of its own.
- **The open bags and bank follow every change again.** Since Forever's patch of November 20 the game can leave out the realm's name. Knapsack then could not tell which character you were playing, so it saved nothing and the open windows stopped changing: a sold item stayed, and gear you put on kept its old icon. Now your character keeps its own record without the realm, even when another of your characters has the same name on another realm.

## 1.0.1

- **Forever is told apart by its interface number.** A Forever update changed its project ID, and Knapsack took Forever for a Classic client, with errors at login.
- **Items keep their places** while the bags or bank stay open: an item you sell, deposit or use up leaves a gap instead of the rest moving. Closing the window tidies up. Turn it off with **Keep items in place while a window is open**.
- **The bank, mail, guild vault and Find windows** show their name in the header, after the character menu.

## 1.0.0

- First release.
