# In-game QA checklist

Run this after installing into a ComputerCraft world.

## Hardware preflight

- [ ] Bank Server has an open wireless or Ender modem.
- [ ] **Both Bank Servers have a wired modem, joined by networking cable, with both modems right-clicked so they light up.** A Bank is two computers since 9.3 and they will not pair over the air.

## 11.1

### App Browser

- [ ] On an App Server that has been running since before 11.0, let it take 11.1. Within a minute or so of restarting it should restart once more by itself (it is fetching what it was missing). Confirm the App Browser then lists **FoxMail** and **Company**, both by PUMPE, alongside Shop, Internet and the rest.
- [ ] Install **Company** from the App Browser on a PUMPE.

### Pickup points

- [ ] A pickup point still on 11.0: type any code and confirm it says it needs its update. Leave Pickup mode with the staff PIN, let the board update, and start Pickup mode again.
- [ ] Order to the pickup point. On the Delivery Terminal, open the order and confirm it shows a **Delivery code**; in the Company app's **Delivery** tab, confirm it only appears once the order is at **Out for delivery**, with the same code.
- [ ] At the counter, **ENTER CODE** with the delivery code, put the parcel in the pickup chest, **STOCKED**. Confirm the buyer gets their code and STAFF has no STOCK A PARCEL any more.
- [ ] Type the buyer's code. Confirm the buyer's PUMPE shows **Is this you?** over whatever app is open, and nothing comes out yet. Answer **It's me** with the PIN and confirm the parcel comes out within a few seconds.
- [ ] Again with another order: answer **Not me**. Confirm the counter says not confirmed, the buyer is told a new code, and the old code no longer works.
- [ ] Again, and ignore the question. After two minutes the counter gives up and nothing comes out.
- [ ] In Foxy's **Security** tab, pre-confirm a parcel with the PIN. Confirm its code now opens it straight away with no question, and that after taking it back (tap it again) the question returns.
- [ ] Leave a pickup point alone for a minute with a newer release published, and confirm it shows **UPDATING, ONE MOMENT**, restarts, and comes back to the counter still locked.

### Selling at a pickup point

- [ ] In the Company app → the company → **Points**, open the point, confirm **Open the store here** refuses with nothing on sale, add something (pick a product, type e.g. `apple`, how many a sale, a price), and open it.
- [ ] At the counter, STAFF → **RESTOCK STORE** with apples in the pickup chest; confirm they go into a locker that already holds something rather than an empty one.
- [ ] Confirm **STORE: BUY NOW** appears on the counter within twenty seconds, lists the offer and how many are left, and a locker holding a parcel is not counted.
- [ ] Buy with **Foxy Pay** (GPS anchors needed): confirm the PUMPE is asked to pay, the items come out into the pickup chest with the redstone pulse, and the owner is notified of the sale.
- [ ] Buy with **ANOTHER BANK: CODE** from Revolution and confirm the same.
- [ ] Take items out of the stock locker by hand while a customer is paying, and confirm the counter says how many came out and the owner gets **Pickup sale came up short** with who is owed what.

### The Company app

- [ ] **+ Start a company**, add a product, rename it, change its price, favourite it, put it in the Shop app. Confirm the company's Service Kiosk shows the same products.
- [ ] On **Store**, open the store, change the colour, tagline, fee, cancelling and returns; confirm the Shop app reflects each.
- [ ] In **Delivery**, open a home delivery on the way: confirm the coordinates, the distance and direction (with GPS), and that **Delivered** with a note marks it done for the buyer.
- [ ] Sign in as somebody who owns no company and confirm the Company app lists nothing and Delivery says to start a company first.

## 11.0

### Cancelling and returns

- [ ] On the store's kiosk (S → ONLINE STORE), confirm **CANCELLING OFF** and **RETURNS: 5 DAYS** to start with, and that 3 days is refused.
- [ ] Turn cancelling on. Order from a PUMPE and confirm the kiosk shows the money as waiting, not in the owner's balance, and that the order's page offers **Cancel order** with the time left.
- [ ] Cancel it. Confirm the buyer has every coin back, both sides are notified, and the Delivery Terminal shows it cancelled.
- [ ] Order again and wait two in-game hours. Confirm the owner is paid then, and the order can no longer be cancelled.
- [ ] Mark it DONE, then from the order's page press **Return it** with a reason. Confirm the owner is notified and the return is at the top of the Delivery Terminal (under any open orders).
- [ ] **REFUND RETURN** and confirm the money moves from the owner to the buyer. Do another and **DECLINE** it, and confirm the buyer sees the reason.
- [ ] **CANCEL + REFUND** an open order at the Delivery Terminal and confirm the buyer is refunded.
- [ ] Pay from Revolution, cancel, and confirm the refund lands in the Revolution account.

### FoxMail

- [ ] Sign in on a fresh PUMPE and confirm **FoxMail** is on the Home Screen without visiting the App Browser.
- [ ] Claim an address; confirm the keyboard has @ and a full stop. Try to claim one somebody else has.
- [ ] As a company owner, register a domain on the **Me** tab, add a second address, and switch between them.
- [ ] Write from one PUMPE to another; confirm a notification arrives, the inbox shows it bold until read, and **Reply** fills in the address and "Re:".
- [ ] On the company's Service Kiosk, open **S → COMPANY MAIL**, read the company's mail and reply from it. Confirm the owner's personal mail is not there.
- [ ] Publish an app that calls `api.mail.send` from the company domain and confirm the mail arrives marked with the app's name; confirm it cannot send from anybody else's address.

### Tabs, home and search

- [ ] Open Foxy, Friends, Tickets, Customs, Shop, FoxMail, Revolution, BuckApp and Website Crafter; confirm each has its tabs along the bottom and that the top-left mark goes home from every tab.
- [ ] From search, open **My tickets** and **Foxy Cash** and confirm each opens on that tab or action.
- [ ] Confirm the search bar sits above the dock, the dock takes four favourites, and typing "fox" lists Foxy, Foxy Cash and FoxMail under the field before pressing anything.

### Bank Vault updates

- [ ] With a paired Bank on 11.0, publish a newer release. Confirm the Core updates itself, then within a minute or so the Vault's dashboard says it is receiving the release over the cable, restarts, and shows the new version.
- [ ] Confirm the Vault kept its own settings in config.lua, and that its data (chats, mail, orders) is all still there.
- [ ] Unpair the Vault and confirm it goes back to checking for updates on its own.

## Shop (10.2)

- [ ] On a Service Kiosk linked to a company, open **S → ONLINE STORE**. Confirm **OPEN STORE** is refused with nothing online, and again with neither home delivery nor pickup on.
- [ ] Put two products online, pick a colour and a tagline, turn home delivery on with a fee, and open. Confirm a subscription product cannot be put online.
- [ ] Install **Shop** from the App Browser on a second account's PUMPE. Confirm the store is listed in its colour, and that searching a word from its tagline finds it.
- [ ] Add two of one product and one of another, take one back out in the basket, and check out to **Where I am now** with GPS anchors up. Keep it as **Home**. Confirm the total includes the fee and the Foxy balance drops by exactly that.
- [ ] Check out again and confirm **Home** is offered as one tap.
- [ ] Try to buy from your own store with the owner's PUMPE and confirm it is refused.
- [ ] Install a **Delivery Terminal** (Easy Deployment → other roles) and link it with the owner's name and PIN. Confirm the order is on the board.
- [ ] Move the order to **Packing**, then to a stage in your own words. Keep the buyer's **Delivery** page open meanwhile and confirm it changes by itself within a few seconds, and that each step also arrives as a notification.
- [ ] Press **DONE** with a note. Confirm the buyer is notified and the order page shows the note.
- [ ] Run the same terminal on an Advanced Pocket Computer and confirm the board and the order screen fit.

### Pickup points

- [ ] Build one: a Delivery Terminal with a wireless modem for the Bank and a wired modem joined by networking cable to three chests, each with its own wired modem. One chest is reachable from the front; the other two are behind a wall.
- [ ] Press **PICKUP**, name it, set a staff PIN, choose the reachable chest as the pickup chest and **BACK** for redstone with a lamp behind the computer. Confirm the terminal switches to **COLLECT YOUR ORDER**.
- [ ] Turn pickup on for the store, and check out to the pickup point from another PUMPE. Confirm the checkout shows the six-digit code and adds no delivery fee.
- [ ] Type the code before the parcel is stocked and confirm it says the order has not arrived yet.
- [ ] Tap **STAFF**, enter the PIN, **STOCK A PARCEL**, pick the order, put the items in the pickup chest and press **STOCKED**. Confirm the pickup chest empties into a walled-off chest, and the buyer gets a notification with the code.
- [ ] Drop a block of dirt in the pickup chest, then type the code. Confirm the dirt went into a spare locker, the parcel came out into the pickup chest, and the lamp flashed.
- [ ] Type the same code again and confirm it is refused. Type five wrong codes and confirm the sixth attempt is told to wait.
- [ ] Hold **Ctrl+T** and confirm nothing happens. Hold **Ctrl+R**, then immediately hold **Ctrl+T** while it restarts, and confirm it comes back to **COLLECT YOUR ORDER**, never the shell.
- [ ] Enter five wrong staff PINs and confirm the staff door stays locked even to the right PIN, across a reboot. Then sign in as the company owner instead and set a new PIN.
- [ ] **LEAVE PICKUP MODE** and confirm Ctrl+T works normally on the board again.

### Paying from another bank

- [ ] With Revolution running, check out to a pickup point paying with **Another bank**, the Revolution Account ID and the Revolution PIN. Confirm the Revolution balance drops and the Foxy balance does not.
- [ ] Put a product costing a fraction in the basket and confirm the app says another bank pays whole amounts before asking for any PIN.
- [ ] Enter a wrong Revolution PIN and confirm nothing moves. Enter five and confirm charges on that account are locked.
- [ ] Confirm the Shop app remembered the Account ID for the next checkout, and never the PIN.

### Web pages (10.2)

- [ ] Publish a page that uses `api.data("PUT", ...)` and `api.data("LIST", ...)`, and confirm a second reader sees the first reader's record.
- [ ] Publish a page that asks `api.login{ scopes = { "balance" } }` and confirm the sheet only asks for your name, and the page never learns your balance.

## Foxy is the bank (9.4)

- [ ] Sign in on a fresh PUMPE and confirm **Foxy** installs itself and appears on the Home Screen without visiting the App Browser.
- [ ] Confirm there is no **Bank** app on the Home Screen, and that Settings has no **Account ID** entry.
- [ ] In Foxy → Bank, scroll the column and confirm the balance, your accounts, Foxy Cash, **Bet Wallet**, **Activity**, **Cash out with a code** and **Account ID + Transfer** are all reachable.
- [ ] Deposit into the Bet Wallet from Foxy, then join a CCG game and confirm the wallet funds it.
- [ ] With a tax demand open, confirm it appears at the top of the bank column and that spending is refused until it is paid.
- [ ] Transfer everything to another bank, then confirm Foxy's bank section says where the money went and still offers the Account ID.

## Paying (9.4)

- [ ] Build a cart on a Service Kiosk and confirm **Portable Mode is already on** for a kiosk that has never been configured.
- [ ] Stand in front of it and confirm the basket arrives on the PUMPE as **FOXY PAY**, and that paying it works.
- [ ] Confirm a second PUMPE standing further away cannot pay that offer.
- [ ] Confirm a kiosk sale code cannot be typed anywhere on a Foxy account — there should be no screen for it, and the Bank refuses it.
- [ ] Confirm a **withdrawal** code still works from Foxy → Bank → Cash out with a code.
- [ ] Confirm a **subscription** code still starts a subscription, and that it appears in Subs.
- [ ] On Revolution: use **Pay kiosk by code** with a Foxy kiosk's code, confirm the quote shows the merchant and fee, and that paying it credits the shop and charges the Revolution account.
- [ ] Confirm Revolution's own **Pay nearby** still works between two Revolution accounts.

## Pair Mode (9.3)

- [ ] Start a Bank Server with no wired modem and confirm it says so and offers **BANK ONLY** rather than pairing over the air.
- [ ] Attach the cable, press **CHECK AGAIN**, and confirm the other Bank Server appears as **PAIR WITH COMPUTER #n** with no code to type.
- [ ] Press it and confirm the server holding the accounts stays the **Core** and the other restarts by itself into **PUMPE BANK VAULT**.
- [ ] Pair the other way round — press the button on the empty server instead — and confirm the live ledger still ends up the Core.
- [ ] On a Bank upgraded from 9.2, confirm the activity feed reports handing each record set to the Vault, and that conversations, friends, territories, visas and tickets all still read back on a PUMPE afterwards.
- [ ] Confirm the Bank Server dashboard shows **VAULT #n LINKED OVER CABLE**.
- [ ] Pull the cable and confirm: balances, Send Money, pay codes and the bet wallet still work; Messages, Urgent Contact, Travel, tickets and app data report the Vault is not answering rather than failing oddly; and no money is lost.
- [ ] Reconnect and confirm everything resumes without a restart.
- [ ] Break the Vault deliberately (`delete /pumpe` and reinstall it), press **PAIR** on the Bank Server dashboard, and confirm a replacement pairs.
- [ ] Confirm Easy Deployment still answers from the **Core** while the Vault is down — that is what lets you rebuild the Vault at all.
- [ ] Send money inside a conversation and confirm the 10% processing fee is charged, exactly as Send Money charges it.
- [ ] Every client resolves the `PUMPE_BANK_V5` Rednet host.
- [ ] Service Kiosk uses an Advanced Computer.
- [ ] Optional customer display is an Advanced Monitor and reports as connected under **S → Rescan Display**.
- [ ] CCG uses an Advanced Computer, an Ender/wireless modem, and an Advanced Monitor; test both a 1×1 monitor at scale `0.5` and the intended larger wall.

## Easy Deployment

- [ ] Run `tools/run_tests.sh` and confirm every host-side test passes before touching a world.
- [ ] Install a fresh Bank from files on the computer drive and confirm the source files are moved—not duplicated—into `/pumpe` and `/updates` before the Bank launches.
- [ ] Upgrade a v6.0.1 Bank with duplicate runtime files in `/updates`; confirm Easy Deployment frees those copies before replacing `bank_server.lua`, then the Bank starts with no duplicate runtime or stale update folders.
- [ ] Confirm `/pumpe` contains only the Bank runtime, installer, config, and required libraries, while `/updates` contains one copy of each role-specific program plus `public/config.lua`.
- [ ] On a clean computer holding **only** `startup.lua`, with HTTP allowed, choose **Bank Server**, enter `4040`, and confirm it downloads and verifies the Bank from the public manifest without any release package or running Bank.
- [ ] Confirm that install pulls only the Bank's own files — no `pumpe.lua`, `ccg.lua` or other role program — and that the Bank still starts with **Easy Deployment online**.
- [ ] Install a client role from that Bank and confirm the role program is fetched into `/updates` on demand at that moment.
- [ ] Switch HTTP off, keep the full release beside `startup.lua`, choose **Bank Server**, enter `4040`, and confirm it reports **NO ONLINE RELEASE** and then installs locally without trying to find a running Bank Server.
- [ ] With neither HTTP nor a local release, confirm it reports **LOCAL BANK FILES MISSING** rather than installing something half-formed.
- [ ] Confirm the Bank launches immediately, creates `/updates/`, and reports **Easy Deployment online** without stopping at another menu.
- [ ] Replace a local distributable script, restart the Bank Server, and confirm its `/updates/` copy is refreshed.
- [ ] Copy only `startup.lua` to the root of a clean Advanced Computer, restart, and confirm the touch installer opens automatically.
- [ ] Confirm **CHECKING FOR UPDATES** appears before the menu, and that it then reports either **UP TO DATE**, the newer release, or **UPDATE CHECK OFFLINE**.
- [ ] Publish a newer Easy Deployment, open it, and confirm it installs itself and reboots so a role added by that release is on the menu the first time it is drawn.
- [ ] Confirm the first screen is **PERSONAL PUMPE** with the block-letter title and one install button, and that the down arrow is the only way to the other roles.
- [ ] From the other roles, confirm **^ BACK** returns to the PUMPE screen.
- [ ] Install PUMPE and confirm the main script, config, installer, and all required `lib/` files arrive under `/pumpe`.
- [ ] Install **CCG Bet Console** and confirm `ccg.lua`, config, installer, and all required `lib/` files arrive under `/pumpe` and CCG starts after reboot.
- [ ] Restart after installation and confirm the selected role starts automatically.
- [ ] Enter a wrong protected code and confirm Bank Server and Admin Terminal downloads are denied.
- [ ] On a 26x20 pocket screen, page through the other roles and confirm every one is reachable, **APP SERVER** included.
- [ ] Enter `4040` and confirm a protected role downloads successfully.
- [ ] Interrupt a download and confirm existing installed scripts remain unchanged.
- [ ] Confirm an unrelated existing `/startup.lua` is preserved.
- [ ] Open Easy Deployment on a computer that already has a role and confirm the footer names that role and version, and that **START ROLE** relaunches it without reinstalling.
- [ ] Watch an installation and confirm the progress bar advances smoothly instead of flickering between chunks.
- [ ] Reboot an installed client role with the Minecraft server's HTTP access disabled and confirm it starts without pausing for an internet request.

## Automatic Internet Updates

- [ ] Enable ComputerCraft HTTP and allow the chosen HTTPS release domain.
- [ ] Set `update_manifest_url` in the Bank Server's local `config.lua`.
- [ ] Host the manifest and all listed files together with their relative paths intact.
- [ ] Start on an older version, publish a higher version, and confirm the dashboard changes from **CHECKING INTERNET** to **DOWNLOADING** and **RESTARTING**.
- [ ] Confirm the Bank Server database and custom government key survive the update.
- [ ] Corrupt one hosted file and confirm its checksum fails without replacing the installed release.
- [ ] On a nearly full Bank, publish a new release and confirm the dashboard reclaims `/updates`, logs how much it freed, and completes the update.
- [ ] Fill the Bank so no release can fit and confirm the dashboard reads **NEEDS n KiB FREE** rather than **DOWNLOAD FAILED**, and that account data is untouched.
- [ ] Replace one shared library on the Bank with an older copy, restart it, and confirm Easy Deployment repairs the whole runtime rather than only `bank_server.lua`, and that `config.lua` reports the new version only once every file verified.
- [ ] Put a newer `pumpe.lua` beside an older `lib/ui.lua` on a PUMPE and confirm it still starts, with Urgent Contact ringing from the Home Screen.
- [ ] Publish a new release, let the Bank take it, then install a role from it and confirm the client receives that release's program rather than a cached older one.
- [ ] Replace a client's program with an older release's copy and confirm it repairs itself on the next check instead of running mismatched.
- [ ] Clear `/updates` by hand, restart the Bank, and confirm it still starts and repairs the depot online instead of stopping at the Easy Deployment repair screen.
- [ ] Remove one manifest file and confirm the whole release is rejected.
- [ ] Start an older client and confirm it updates from the Bank Server and reboots before opening its role.
- [ ] Leave an older client dashboard open, publish a newer release, and confirm its live check installs and reboots without manual input.
- [ ] With the Bank on the current version, leave a client dashboard open and confirm it does not repeatedly launch Easy Deployment; only a cheap version probe should run.
- [ ] Confirm `release_manifest.json` lists `border_controller.lua` and `ccg.lua` under `extra_files`, never under `files`.
- [ ] Update a Bank from a release that predates `extra_files`, then confirm it reports **VERIFYING DEPOT**, refreshes `/updates/ccg.lua` and `/updates/border_controller.lua`, and writes `/updates/.depot`.
- [ ] Delete `/updates/.depot` and corrupt one depot program; confirm the next check repairs it from the manifest and stamps the depot again.
- [ ] Publish a release whose `startup.lua` carries an older `INSTALLER_VERSION` and confirm Easy Deployment refuses it instead of rebooting in a loop.
- [ ] With HTTP enabled, publish a new release and confirm a PUMPE, kiosk and CCG console each install it **directly from the manifest**, without the Bank's rednet depot being used. Before 8.0 every client silently fell back to the depot.
- [ ] Take a Bank that reached 7.1 by self-updating, open the Admin Terminal, and confirm `Government1234` is accepted. Confirm a key deliberately set in `config.lua` is still honoured.
- [ ] Leave an unassigned Easy Deployment file on a clean computer, publish a newer release, restart it, and confirm the installer updates itself before showing the role list.
- [ ] Confirm a Bank update reboots directly back into the Bank without displaying Easy Deployment or depending on an active deployment server.

## Core banking

- [ ] Create two accounts and confirm each starts with the configured balance.
- [ ] Restart the Bank Server and confirm both accounts still exist.
- [ ] Send `$100` and confirm the review shows `$100` received, `$10` fee, and `$110` paid.
- [ ] Confirm the sender history records the transfer and processing fee separately while the recipient receives exactly `$100`.
- [ ] Send up to a total of `$2,000` in one in-game day, then confirm one additional cent is rejected by the Bank Server.
- [ ] Advance to the next in-game day and confirm the Send Money limit resets.
- [ ] Try a wrong PIN and an insufficient balance.
- [ ] Open Sign In and Set Up New Account PIN pads on a Pocket Computer and confirm both touch and physical digit entry work without an error.

## PUMPE phone experience

- [ ] On a fresh PUMPE, confirm start-up spells **PUMPE** one letter at a time, blinks three times, then holds **Small yet Mighty**.
- [ ] Confirm onboarding asks new-or-existing first, then username, then PIN twice, and that mismatched PINs are refused.
- [ ] Complete the six-step guide, then re-open it from Settings under **How PUMPE Works** and confirm **Done** returns to Settings.
- [ ] Confirm **Skip** on the guide during sign-up still leaves the account signed in.
- [ ] Confirm **Setting up your Foxy Account** and **Preparing your PUMPE** animate without forcing an unnecessary reboot.
- [ ] On an Advanced Pocket Computer at its native 26×20 size, confirm every onboarding line, header, button label, and footer is fully visible.
- [ ] Confirm every app icon fits on one Home Screen page, that each name under an icon is readable, and that tapping either the icon or its name opens the right app.
- [ ] Confirm PUMPE Pay contains only Code Pay and Send Money.
- [ ] Confirm both cards are fully readable and Send Money shows the 10% processing fee and `$2,000` daily limit.
- [ ] Open Wallet, Activity, Events, Tickets, Notifications, and Subscriptions with long sample names and confirm content wraps without overlapping controls or the footer.
- [ ] Trigger a long payment confirmation and error message and confirm every line remains readable until the user responds or the message completes.
- [ ] Leave the PUMPE untouched for 60 seconds and confirm the Lock Screen appears with the correct in-game time and day.
- [ ] Open it before 120 seconds and confirm no PIN is required.
- [ ] Lock it again, wait beyond 120 seconds, and confirm a wrong PIN stays locked while the correct PIN opens PUMPE.
- [ ] Confirm touch, keyboard, PIN-pad, and text-entry activity each reset the inactivity timer.

## ComputerCraftGaming

- [ ] Open **Bet** and confirm it asks for the Foxy Account PIN before showing the lobby-code screen; a wrong PIN must not open the app.
- [ ] Enter a lobby code longer than 24 characters with mixed letters and numbers. Confirm the field scrolls as you type and the PUMPE joins with the complete code.
- [ ] Open **Bet Wallet**, transfer money in with the PIN, and confirm the normal Foxy Account and Bet Wallet balances change by exactly the same amount in opposite directions.
- [ ] Transfer a partial Bet Wallet balance back to the Foxy Account with the PIN and confirm held winnings cannot be withdrawn early.
- [ ] Create a Heads or Tails lobby, join from two PUMPEs with different display names/picks, place wagers, and confirm the screen lists both as **READY**.
- [ ] Start Heads or Tails and confirm the big-screen flip, PUMPE waiting animation, server-selected result, exactly `2×` winning payout, and losing wager settlement.
- [ ] Create a Race lobby, place wagers across all six colors, and confirm all six animated lanes remain visible on a 1×1 monitor and the winning color receives exactly `3×`.
- [ ] Create a Survivor lobby and confirm **Start** stays disabled with fewer than two ready players.
- [ ] In Survivor, use each joystick direction and **PUSH** from multiple PUMPEs. Confirm the screen tracks movement, rapid Push taps respect cooldown, the ring shrinks, eliminated players switch to spectating, and the last player receives exactly `3×`.
- [ ] Win a round near the end of an in-game day. Confirm the payout remains in **Holding** through the day rollover and releases only after a complete 24 in-game hours at the shown day/time.
- [ ] Leave a waiting lobby and let another waiting lobby expire. Confirm each reserved wager is refunded exactly once.
- [ ] Restart the CCG computer during a lobby and confirm it resumes that lobby. Restart the Bank during Survivor and confirm every wager is refunded instead of selecting an arbitrary winner.
- [ ] Attempt to alter the CCG/PUMPE payload with a preferred outcome, payout, or winner and confirm the Bank ignores it and settles only its own result.
- [ ] Confirm Home Play is not shown in this release; only Bet Play is installed.

### Auto Mode

- [ ] Start Auto Mode on one game, confirm it asks for the stop code twice, and refuse a mismatch.
- [ ] Join with one PUMPE, mark ready, and confirm the console counts down and starts the round with no operator input.
- [ ] Confirm the result screen counts down and the next lobby opens with a new join code.
- [ ] Let a lobby expire with nobody joined and confirm a fresh lobby opens instead of returning to the game menu.
- [ ] Tap **STOP AUTO**, enter a wrong code, and confirm Auto Mode keeps running.
- [ ] Enter the correct code and confirm the console returns to the game picker and cancels the open lobby with refunds.
- [ ] Start Auto Mode with **Rotate All Games**, reboot the console, and confirm it resumes Auto Mode on the next game instead of showing the menu.
- [ ] Confirm Survivor rounds in Auto Mode wait for at least two ready players.

## PUMPE home screen

- [ ] Confirm the dock starts empty with four **+** slots, and that tapping one opens the picker.
- [ ] Pick four apps, confirm they appear in the dock on every page, and confirm they survive a restart.
- [ ] Try to pick a fifth and confirm it is refused until one is removed.
- [ ] Confirm **Edit Your Dock** in Settings opens the same picker.
- [ ] With unread messages waiting, confirm the count appears as a badge in the Friends icon's corner, both in the grid and in the dock.
- [ ] Confirm BuckApp opens on the balance and reaches payments, the Bet Wallet and Activity.
- [ ] Confirm Friends reaches Messages, Friends and Urgent Contact, and badges what is waiting.
- [ ] Confirm Tickets reaches both events and your tickets, and Customs reaches both visas and territories.
- [ ] Page to the notification centre and confirm unread alerts are bright with a coloured bar, read ones are faded, and each shows its arrival time.
- [ ] Tap an alert and confirm the whole message opens on its own screen with **< Alerts** to return.
- [ ] With more alerts than fit, confirm **v** and **^** scroll the list and are greyed out at each end.
- [ ] Confirm **Mark all read** fades every row and clears the `!` in the page dots.
- [ ] Have someone send you money while a different app is open and confirm a banner drops across the top, then the screen repaints.
- [ ] Sign in with unread alerts already waiting and confirm no banner storm.

## Friends, Messages, and Urgent Contact

### Friends

- [ ] Search a partial name and confirm the match appears and your own account never does.
- [ ] Send a request, confirm the other PUMPE shows a Friends badge and an alert, and accept it.
- [ ] Send the same request twice and confirm only one alert arrives.
- [ ] Have both people request each other and confirm they become friends immediately.
- [ ] Decline a request and confirm neither side gains a friend.
- [ ] Remove a friend and confirm they disappear from both lists.

### Messages

- [ ] Start a chat from Friends and from Messages and confirm both open the same conversation.
- [ ] Send a message and confirm the other PUMPE badges Messages and raises one alert.
- [ ] Send several more without opening the chat and confirm no further alerts arrive.
- [ ] Open the chat and confirm the badge clears.
- [ ] Ask for money, confirm the request appears for the other person, pay it with the PIN, and check both balances moved by the amount plus the 10% fee.
- [ ] Decline a money request and confirm no money moves.
- [ ] Create a group of three, send a message, and confirm both other PUMPEs are notified.
- [ ] In a group, confirm Send money asks who to pay.

### Urgent Contact

- [ ] Reach a friend while their PUMPE sits on a different app, and confirm the full-screen ring takes over.
- [ ] Decline and confirm the caller is told.
- [ ] Accept, type from both sides, and confirm each line appears on the other screen within about a second.
- [ ] Send money and pay a request inside the call and confirm the PIN is required.
- [ ] Press Save on one PUMPE only, hang up, and confirm nothing was written to Messages.
- [ ] Press Save on both, hang up, and confirm the transcript appears in the direct chat.
- [ ] Hang up from each side in turn and confirm the other side is told.
- [ ] Leave a call unanswered for 30 seconds and confirm both sides get a missed-call alert.
- [ ] Start a call, restart the Bank Server, and confirm the call ends rather than hanging.
- [ ] Confirm a second call is refused while one is already open.

## Foxy

- [ ] Install the **App Server** role, confirm it starts and reports Foxy already in its catalogue.
- [ ] On a PUMPE open **Apps**, confirm Foxy is listed, install it, and confirm the bar fills and the tick draws before it lands on the Home Screen.
- [ ] Open Foxy and confirm the wordmark sweeps in, then the home page offers **Bank** and **Account**.
- [ ] In Bank, confirm the card shows your name and a grouped card number, that the light band sweeps across it once, and that your balance is underneath.
- [ ] Tap `+ New account`, name it, and confirm it appears under the balance with a zero balance.
- [ ] Move money from Main into it and confirm both balances change by the same amount and the total is unchanged.
- [ ] Move it back, then close the account, and confirm the money returns to Main.
- [ ] Scroll to **Foxy Cash**. With no friends, confirm it says so rather than offering a broken send.
- [ ] Add a friend, send them money, and confirm the fee is 2%, that they receive the whole amount, and that the sender pays amount + fee.
- [ ] Confirm Foxy Cash refuses somebody who is not a friend.
- [ ] Send more than the old `send_money_daily_limit` in one go and confirm Foxy Cash has no ceiling.
- [ ] Change your name in **Account**, confirm the old name frees up and the new one can be paid.
- [ ] Change your PIN and confirm the old one stops working everywhere.
- [ ] Issue a tax demand and confirm Foxy Cash and moving money out of Main are both refused, while moving savings back into Main still works.

## The App Browser and Dev Mode

- [ ] With the App Server stopped, open **Apps** and confirm it says the server is offline rather than hanging.
- [ ] Watch the Bank's dashboard while a PUMPE downloads an app and confirm the Bank is not involved.
- [ ] In POS Settings tap **ENTER DEV MODE**, enter the company owner's PIN, and confirm `/apps/` is created.
- [ ] Confirm a kiosk with no company linked is told to link one first.
- [ ] Put a `.lua` file in `/apps/`, publish it with a name and description, and confirm it appears in every PUMPE's App Browser.
- [ ] Install it on a PUMPE, open it from the Home Screen, and confirm it runs.
- [ ] Edit the file, publish again, and confirm the App Browser offers **Update** and the version number rises rather than a second copy appearing.
- [ ] Publish something that is not valid Lua and confirm the App Server refuses it before any PUMPE sees it.
- [ ] Publish an app that errors on purpose and confirm the PUMPE reports it and returns to the Home Screen instead of crashing.
- [ ] Delete your own app from the App Browser and confirm it leaves the catalogue; confirm somebody else's cannot be deleted.
- [ ] **Remove from PUMPE** an installed app and confirm it leaves the Home Screen but stays in the store.
- [ ] Open **BuckApp** and confirm the closing-down banner and that **Move to Foxy** opens the App Browser.

## FoxyLogin and Yap

- [ ] Publish `apps/yap.lua` from Dev Mode and install it on a PUMPE.
- [ ] Open it and confirm the Foxy sheet slides up, names Yap, and lists your account name and who your friends are — and nothing else.
- [ ] Tap **Not now** and confirm the app closes without signing in.
- [ ] Open it again, approve, and confirm it goes straight in the next time with no second question.
- [ ] Confirm **Settings → Connected Apps** lists Yap, and that signing out of it there makes the app ask again.
- [ ] Post something and confirm it appears at the top of your own feed.
- [ ] From a friend's PUMPE, confirm your post is marked with `*` and sits above every stranger's, even one posted more recently.
- [ ] Like a post from another PUMPE and confirm the count rises on both; unlike it and confirm it falls.
- [ ] Like the same post twice and confirm it stays at one.
- [ ] Reply to a post and confirm the reply shows under it for everybody.
- [ ] Confirm you can delete your own post and cannot delete somebody else's.
- [ ] Scroll with the two buttons on the right edge and confirm the posts never draw underneath them.
- [ ] Post the longest text the composer allows and confirm the feed truncates it with `..` rather than overflowing.

## In-app purchases

- [ ] Publish an app from a Dev Mode kiosk linked to a company, and confirm the Bank records who owns it (a second publish re-tries if the Bank was offline).
- [ ] Buy something in an app and confirm the sheet names the app, the price, the tax and who is being paid **before** asking for the PIN.
- [ ] Enter the wrong PIN and confirm nobody is charged.
- [ ] Confirm the buyer is down the full price, the publisher is up 70%, and government revenue is up 30%.
- [ ] Buy while a tax demand is outstanding and confirm it is refused like any other payment.
- [ ] Start a subscription, wait an in-game day, and confirm it is charged again and split the same way.
- [ ] Cancel it under **Settings → App Settings** and confirm it stops.
- [ ] Let a subscription come due with too little money and confirm it stops rather than overdrawing.
- [ ] Confirm one app cannot see another app's purchases.

## Yap Boost

- [ ] Open one of your own yaps and confirm **Boost this yap** is offered; open somebody else's and confirm it is not.
- [ ] Buy the $10 boost and confirm that yap rises above your friends' in the feed, marked with `^`.
- [ ] Confirm your **other** yaps did not rise — a one-off covers one yap.
- [ ] Buy the $20 a day boost and confirm every yap you post rises.
- [ ] Cancel it and confirm your yaps drop back.

## Revolution

- [ ] Install **Revolution** from the App Browser and host it on a 3rd Party Bank Server.
- [ ] Confirm the server reports one hour of clearing and no fee.
- [ ] Move money in from Foxy with your Account ID, and confirm it shows as **clearing** rather than available.
- [ ] Confirm it cannot be spent or moved on until it clears.
- [ ] Wait one in-game hour and confirm it becomes available.
- [ ] Send money to another Revolution account and confirm **no fee** is taken, unlike Foxy's ten per cent.
- [ ] Open a charge with **Take a payment**, stand next to another Revolution user, and confirm their **Pay** screen finds it.
- [ ] Walk far away and confirm the charge is no longer found.
- [ ] Pay it and confirm the payer is down exactly the price, and the taker sees it clearing.
- [ ] Try to pay the same charge twice and confirm it is gone.
- [ ] Try to pay your own charge and confirm it is refused.
- [ ] With no GPS anchors on the network, confirm both screens say so rather than failing oddly.

## CCG Server

- [ ] Install **CCG SERVER** from Easy Deployment and confirm it asks for the operator code once, then comes up without asking again.
- [ ] Enter the wrong code and confirm it refuses.
- [ ] With no CCG Server running, open Bet on a PUMPE and confirm it says no CCG Server is running rather than hanging.
- [ ] Start the CCG Server, register a console, and run a full Heads or Tails round: join, wager, start, settle. Confirm the winner's payout is exactly the wager times two.
- [ ] Run a Race round and confirm the payout is the wager times three.
- [ ] Run a Survivor round with two players and confirm it settles on a winner.
- [ ] Confirm the Bet Wallet still deposits and withdraws from the **Bank**, with the CCG Server switched off.
- [ ] Leave a lobby after wagering and confirm the stake returns to the Bet Wallet.
- [ ] Cancel a lobby from the console and confirm every wager returns.
- [ ] **Switch the CCG Server off with wagers in an open lobby.** Confirm the money is not in the wallet yet, wait two in-game hours, and confirm the Bank gives it back on its own.
- [ ] Restart the CCG Server during a Survivor round and confirm everyone is refunded rather than a winner being guessed.
- [ ] Update a Bank that had a lobby open at 9.0 and confirm the wagers are returned once, with a line in the activity feed.

## Pair Mode

- [ ] On a fresh Bank Server confirm it asks **SOLO** or **PAIR** before it starts, and that choosing SOLO behaves exactly like every Bank before 9.0.
- [ ] Choose PAIR on a Bank that already has accounts, open a second Bank Server, choose PAIR there, and type the first one's code into it. Confirm they pair.
- [ ] Confirm the server holding the accounts became the **Core** and the new one the **Vault**.
- [ ] Repeat the other way round — type the *empty* server's code into the *live* one — and confirm the live one is still the Core. A fresh computer must never demote a live ledger.
- [ ] With the pair up, install a role from Easy Deployment and confirm the download is served by the Vault, not the Core.
- [ ] Open an app that keeps records (Yap) and confirm posting works, then confirm the Core's `/pumpe` holds no app data.
- [ ] Stop the Vault and confirm app records report the Vault is offline rather than appearing empty.
- [ ] Restart both and confirm they come back paired without asking again.
- [ ] Confirm **both** halves actually start. 9.0.0 killed whichever started second with "Hostname in use" because both claimed the ledger name.
- [ ] Confirm a Bank Transfer *into* this bank still works with the pair up, which is what proves the ledger name is held by the Core rather than by nobody.
- [ ] Confirm banking (balance, Send Money, Pay) is unaffected by stopping the Vault.

## Third-party banks

- [ ] Press **BANK SERVER** in Easy Deployment and confirm it asks which kind before anything else.
- [ ] Confirm **FOXY BANK SERVER** still asks for `4040` and **3RD PARTY BANK SERVER** asks for nothing.
- [ ] With no Bank Apps published, confirm the 3rd Party server explains what a Bank App is instead of showing an empty list.
- [ ] Install **BuckApp** from the App Browser on a PUMPE, open it with no BuckApp server running, and confirm it says so rather than hanging.
- [ ] Start a 3rd Party Bank Server, choose BuckApp, and confirm the PUMPE app finds it.
- [ ] **Reboot that computer** and confirm it comes straight back up rather than reporting UNKNOWN ROLE. That was broken from 9.0 to 9.2.0.
- [ ] Write a boot marker naming a role that does not exist, reboot, and confirm the computer checks for an update and then opens the role picker rather than stopping dead.
- [ ] Publish a newer release and confirm the 3rd Party Bank Server auto-updates like every other role. It never did before 9.2.3.
- [ ] Confirm its dashboard shows the version it is running, and that the version matches the rest of the network.
- [ ] Do the same for the CCG Server.
- [ ] Open a BuckApp account and confirm it opens **empty** — a third-party bank mints no money.
- [ ] Confirm your Foxy name and PIN do **not** sign you in to BuckApp.
- [ ] Confirm BuckApp is no longer on the home screen of a fresh PUMPE, and that the built-in **Bank** tab still has Continue, Bet Wallet and Activity.

## Bank Transfer

- [ ] Confirm your Account ID is sixteen digits and is shown in Foxy → Bank → Account ID + Transfer.
- [ ] Transfer everything from Foxy to your BuckApp Account ID. Confirm the amount arrives, and that the total money across both banks is unchanged.
- [ ] Confirm **Foxy's bank section no longer opens** and says where the money went.
- [ ] Confirm Send Money, Pay and every other spending feature refuse while the money is elsewhere.
- [ ] Confirm somebody sending you money is told your account has moved rather than the money vanishing into it.
- [ ] Transfer back from BuckApp to your Foxy Account ID and confirm Foxy's bank section reopens with the money in it.
- [ ] Type an Account ID at a bank that is not running and confirm it says so and takes nothing.
- [ ] Enter the wrong PIN and confirm nothing leaves the account.
- [ ] Stop the receiving Bank Server *mid-transfer* and confirm the money is reported as held rather than lost, and that it settles or returns on its own within a minute.

## Settings

- [ ] Confirm Settings lists Network, Storage, Updates, App Settings, Connected Apps, How PUMPE Works, Edit Your Dock, Sign Out and Close PUMPE, paging if the screen is short.
- [ ] Open **Storage** and confirm it reports free space and lists each installed app with its size.

## The modem switch (9.5)

- [ ] Turn the **modem off** and confirm you are **still signed in**: the Home Screen still opens, the header reads **Offline** where the balance was, and you are not sent back to the welcome screen.
- [ ] Confirm Settings still opens and still reaches **Network**, so the radio can be turned back on.
- [ ] Open an app you downloaded and confirm it still opens.
- [ ] Open something that needs a server — Foxy's bank, the App Browser, Tax — and confirm it says the modem is off immediately rather than pausing.
- [ ] With the modem off, confirm the Lock Screen opens on a tap instead of asking for a PIN it cannot check.
- [ ] Turn the modem back on and confirm banking works again **without signing in again**.
- [ ] Restart a PUMPE with the modem off. Confirm it opens on the Home Screen under your name rather than the welcome screen, and that Settings → Network still turns the radio back on.
- [ ] After that restart, confirm opening the App Browser or a bank app does **not** quietly put the radio back on: turn it on deliberately, and only then should anything reach the network.

## Updates (9.5)

- [ ] Publish a newer release and confirm the PUMPE shows a **fullscreen alert** listing what changed, with **Update now** and **Later**.
- [ ] Confirm the list matches the new release's changelog headlines, and the alert names the release (for example `10.0 Pre`).
- [ ] Tap **Later** and confirm nothing installs and the alert does not come back on its own.
- [ ] Open **Settings → Updates**, tap **Check now**, and confirm the same alert comes back.
- [ ] Tap **Update now** and confirm the phone downloads, restarts and comes back on the new version.
- [ ] Switch Updates to **Install automatically**, publish another release, and confirm it installs without asking.
- [ ] Confirm a Bank Server, App Server and kiosk all update themselves silently — none of them should be waiting for a tap.
- [ ] With the modem off, confirm the PUMPE does not check for releases at all and Settings → Updates says so.

## The web as code (10.1)

- [ ] In Website Crafter, make a website and pick the **Foxy** template. Confirm the editor shows it a line at a time.
- [ ] Tap **Check** and confirm it says the program parses. Break a line on purpose, check again, and confirm it names what is wrong.
- [ ] Confirm publishing broken code is refused by the Internet Server rather than accepted.
- [ ] Publish the Foxy page, wait for it to open, and visit it from **another** PUMPE. Confirm it draws, and that **Sign in with Foxy** raises the consent sheet and then shows your name.
- [ ] Confirm the Internet app opens on an address bar and a short history, with **no list of every site**.
- [ ] While a page is open, confirm `/pumpe/web/` on that computer holds the file; leave the page and confirm it is gone.
- [ ] Restart a PUMPE and confirm `/pumpe/web/` is empty.
- [ ] Publish a website that tries `fs.delete("/")` and confirm it stops with an error rather than doing anything.
- [ ] Open a site that was published before 10.1 and confirm it says its owner has to publish it again.

## Search and App Actions (10.0 Simple)

- [ ] Confirm the dock shows **search** first and three favourites after it, on every Home Screen page.
- [ ] Search for `cash` and confirm **Foxy Cash** is offered. Tap it and confirm Foxy opens **at Foxy Cash**, not at its front door, and closes when you leave it.
- [ ] Search for `modem` and confirm **Network** is offered under Settings; tap it and confirm you land on the modem switch.
- [ ] Search for something that is not installed and confirm **Look in the App Browser** carries the words over.
- [ ] In Settings, search `up` and confirm only Updates is left. Clear it and confirm the full list returns.
- [ ] In the App Browser, search for part of an app's name and confirm the list narrows.
- [ ] Confirm the Home Screen holds twelve apps per page rather than nine.

## Reminders and QuickActions (10.0 Simple)

- [ ] Set a reminder for one in-game hour from now as a **banner**. Wait it out on the Home Screen and confirm it drops in and goes.
- [ ] Set another as a **full screen alert** and confirm it waits for Got it.
- [ ] Confirm a reminder that has fired is marked Done and does not come back.
- [ ] Build a QuickAction with a **Tell me** step and a **Repeat x3**, run it on demand, and confirm the banner appears three times.
- [ ] Add an **Open** step pointing at an app action and confirm running the QuickAction opens that app there.
- [ ] Set a QuickAction to run every day at the current hour, leave the Home Screen open, and confirm it runs once and not again until the next in-game day.
- [ ] Put a QuickAction on the Home Screen and confirm its icon runs it rather than opening anything.
- [ ] Delete a QuickAction that was on the Home Screen and confirm the icon goes with it.

## The web (10.0)

- [ ] From Easy Deployment, open **SERVERS** and confirm it lists Bank Server, Bank Vault, App Server, Internet Server and CCG Server.
- [ ] Install **INTERNET SERVER** on a fresh computer and confirm its terminal comes up saying nothing is published yet.
- [ ] Install **BANK VAULT** on a fresh computer straight from that tab. Confirm it starts, says it is not paired, and that pairing from the Bank Server over the cable then works -- with nothing downloaded from the Bank.
- [ ] Install **Website Crafter** and the **Internet** app from the App Browser.
- [ ] In Website Crafter, reserve a domain. Confirm the letters land one at a time, that it says **You're in, [your name]**, and that the domain appears on a card.
- [ ] Confirm a name somebody else already has is refused, and so are `ab`, `two words`, `a.name` and `-dash`.
- [ ] Reserve a second domain, then confirm a third is refused: two per account.
- [ ] Start from a template, change a line, and publish.
- [ ] In the Internet app on **another** PUMPE, go to the domain and confirm it says **We're still preparing. Come back soon.**
- [ ] Wait two in-game hours and confirm the site opens and runs.
- [ ] Edit the site and publish again. Confirm it goes down for half an in-game hour and comes back with the change.
- [ ] Rename the domain. Confirm the website follows the new name, and that reserving the old name on another account gives an empty site rather than the first owner's pages.
- [ ] Delete a website and confirm the name is free for somebody else.
- [ ] Turn the Internet Server off. Confirm Website Crafter still opens, still edits and still saves, and that the Internet app says no Internet Server is running.

## Start-up and updating (10.0)

- [ ] Start a PUMPE and confirm the letters land, the tagline holds about two seconds, and the Home Screen follows -- no blinking wordmark.
- [ ] Publish a release, accept the update, and confirm the wordmark sits over a filling bar for about twenty seconds before the phone restarts.
- [ ] Confirm a Bank Server, App Server and Internet Server all update without any twenty second screen: those are unattended machines.

## Fast Bank Transfer (9.5)

- [ ] With money in Foxy, install **Revolution** and open an account. Confirm it offers to bring your money over and lists **Foxy** with the right balance.
- [ ] Pick Foxy and confirm the **PUMPE's own** sheet appears, asks for your PIN, and that Revolution never asks for it.
- [ ] Confirm the whole balance arrives at Revolution, that the total money across both banks is unchanged, and that Foxy's bank section says where the money went.
- [ ] In Foxy, tap **Bring it back here** and confirm the phone opens Revolution, which asks for its **own** PIN and pushes the money home.
- [ ] Confirm the money is back in Foxy and the account is open again.
- [ ] Confirm a bank app is never offered a transfer to itself, and that **Foxy** appears once in the list rather than twice.
- [ ] Cancel the PUMPE's sheet, or type the wrong PIN, and confirm nothing moves.

## App permissions and App Settings

- [ ] Publish `apps/yapchat.lua` from Dev Mode and install it on two PUMPEs whose owners are Foxy friends.
- [ ] Open it and confirm the notifications question comes up **before** the Foxy sign-in sheet.
- [ ] Tap **Not now**, then reopen the app, and confirm it does not ask again.
- [ ] Confirm **Settings → App Settings** lists Yap Chat as blocked, and that allowing it there makes notifications work without the app asking again.
- [ ] With notifications blocked, send a message from the other PUMPE and confirm nothing arrives and the sender is told why.
- [ ] Turn **Fullscreen: on** in App Settings, send a message, and confirm the recipient gets the fullscreen alert with Yap Chat's name on it.
- [ ] Block notifications again and confirm **Fullscreen** goes off with them, and that re-allowing notifications leaves fullscreen off.
- [ ] Confirm an app banner shows the app's name beside the title, so it is not mistaken for the Bank's own.
- [ ] Tap **Forget this app** and confirm it disappears from App Settings and asks from scratch next time.

## Yap Chat

- [ ] Open the app and confirm it asks for your PIN before showing any message.
- [ ] Enter the wrong PIN and confirm it refuses and closes rather than opening the inbox.
- [ ] Enter the wrong PIN five times and confirm the app is locked out for a couple of minutes, then works again.
- [ ] Send a message and confirm it arrives on the friend's PUMPE and nowhere else — check a third PUMPE cannot see it.
- [ ] Confirm the conversation opens at the newest message rather than the oldest.
- [ ] Read a message, wait one in-game day, reopen the conversation on **both** PUMPEs, and confirm it is gone from each.
- [ ] Leave a message unread, wait three in-game days, and confirm it is still there.
- [ ] Tap **Call** in a conversation and confirm the other PUMPE rings fullscreen, saying **YAP CHAT CALL** and who is calling.
- [ ] Accept the call and confirm it behaves exactly like an Urgent Contact.
- [ ] Confirm the chat list shows an unread count for a friend who has messaged you.
- [ ] Send the longest message the composer allows and confirm the conversation truncates rather than overflowing.

## Regression: an app can write at all

- [ ] In Yap, post something, like a post and reply to one, and confirm none of them reports **That app has no id** — that was the 8.4.0 bug.

## Proximity Ticket Scanning

- [ ] With four GPS anchors up, open a ticket on a PUMPE, turn on **PROXIMITY SCAN** at the Event Kiosk, and confirm the holder is asked and not somebody standing closer without a ticket.
- [ ] Accept on the PUMPE and confirm the name and ticket type land on the organiser's screen and the ticket reads USED.
- [ ] Scan again with the same ticket open and confirm it reports nobody nearby rather than admitting twice.
- [ ] Close the ticket, wait past `present_max_age_ms`, and confirm scanning no longer finds that PUMPE.
- [ ] Decline on the PUMPE and confirm the ask moves to the next person with a ticket up.

## Proximity Visa

- [ ] Turn on **PROXIMITY VISA**, open a travel document on a PUMPE, and confirm the traveller is asked.
- [ ] Confirm the popup warns that the gate opens for two seconds and to stand close.
- [ ] Accept and confirm the gate pulses redstone for two seconds, then closes.
- [ ] Confirm the first crossing records an entry and the next one records an exit, with no Enter/Exit buttons pressed.
- [ ] Try it with a document for another territory and confirm it is refused with a reason, and the gate stays shut.
- [ ] Leave it running with nobody nearby and confirm it keeps searching rather than stopping.

## Portable Mode

- [ ] Turn **PORTABLE MODE** on in POS Settings and confirm the receipt's NEARBY button becomes FIND.
- [ ] Tap **FIND**, accept on the nearest PUMPE, and confirm their name appears at the top of the receipt before any product is added.
- [ ] Ring up items, press PAY, and confirm the PUMPE shows each line and the total, then asks for the PIN.
- [ ] Confirm the money moves only after that second confirmation.
- [ ] Back out on the PUMPE after the basket arrives and confirm the sale ends rather than being offered to someone else, and that its payment code stops working.
- [ ] Turn Portable Mode off and confirm NEARBY and payment codes behave as before.

## Government messages

- [ ] From an account in the Admin Terminal, send **ANNOUNCE TO THEM** as a banner and confirm only that account sees it.
- [ ] Send one as full screen and confirm it stays until Continue, and that nobody else gets it.
- [ ] Send a **TEXT MESSAGE** and confirm a Government thread appears in that PUMPE's Messages.
- [ ] Reply from the PUMPE and confirm it reaches the terminal, and that **MESSAGES** on the dashboard highlights the thread as waiting.
- [ ] Confirm the PUMPE cannot ask the Government for money or send it money in that thread.
- [ ] Ask for money from the terminal, pay it from the PUMPE, and confirm the balance drops and tax revenue rises.
- [ ] Send money from the terminal and confirm the balance rises.
- [ ] Confirm every government message lands in the one thread rather than making a new chat each time.

## Payment lockout under a tax demand

- [ ] Issue a tax demand and confirm code payments, sending money, buying a ticket, a visa fee, and the Bet Wallet all refuse with a message naming the demand.
- [ ] Confirm the account can still *receive* money.
- [ ] Pay the demand and confirm every payment feature works again immediately.
- [ ] Issue a government money request as well as a demand and confirm the request can still be paid.

## Proximity Pay

- [ ] Install four GPS Anchors with wireless modems, spread out and not all at one height, and confirm each reports the coordinates you typed.
- [ ] Run `gps locate` on an ordinary computer in range and confirm it resolves.
- [ ] Confirm a kiosk with no fix refuses **NEARBY** and says to add anchors.
- [ ] Stand two PUMPEs at different distances, tap **NEARBY**, and confirm the closer one gets the full-screen offer.
- [ ] Tap **Not mine** and confirm the offer moves to the second PUMPE and disappears from the first.
- [ ] Decline on both and confirm the kiosk reports nobody nearby rather than charging anyone.
- [ ] Accept an offer and confirm the PIN rules and daily limits match a normal code payment, and the transaction log matches.
- [ ] Walk far away, wait for the position to go stale, and confirm you stop being offered payments.

## Service Kiosk and monitor

- [ ] Register and link a company.
- [ ] Add at least three one-time products and one subscription product.
- [ ] Confirm the top tabs are **Favorited**, **All Products**, and **Subscriptions**.
- [ ] Toggle `F` beside products and confirm the Favorited tab updates.
- [ ] Add enough products to require the right-side page buttons and confirm every product remains reachable.
- [ ] Confirm the receipt stays on the left and **PAY** stays at its bottom.
- [ ] On a 1×1 Advanced Monitor at text scale `0.5`, confirm names, quantities, prices, and the total fit without overlap.
- [ ] Tap the same item twice and confirm the monitor shows `2x`.
- [ ] Clear the cart and confirm the monitor resets.
- [ ] Create a payment code, cancel it, and confirm the PUMPE cannot redeem it.
- [ ] Create another code, pay it, and confirm the paid animation and merchant balance.
- [ ] Press **PAY** with an empty receipt, enter a custom amount on the keypad, and complete both One Time and Subscription flows.
- [ ] Create a subscription code, enter it in PUMPE, confirm the amount per day, and verify PIN confirmation creates the subscription.
- [ ] Detach the monitor and confirm the kiosk continues working.
- [ ] Reattach it, tap **S → Rescan Display**, and confirm the idle screen returns.

## Bank Admin Terminal

- [ ] Install **Admin Terminal** with code `4040` and sign in with `Government1234`.
- [ ] Change the key from Controls, confirm the old key is refused and the new one works, and confirm it survives a Bank restart.
- [ ] Add money to an account and confirm the holder is notified and the transaction log matches.
- [ ] Remove more money than an account holds and confirm it is refused.
- [ ] Issue a tax demand, confirm it appears in the holder's BuckApp, that a wrong PIN moves nothing, and that paying it clears the demand.
- [ ] Ban an account and confirm its PUMPE session ends at once and it cannot sign back in. Unban and confirm it works again.
- [ ] Switch account approval on, create a new account, and confirm it waits. Confirm existing accounts are unaffected. Approve it and confirm it works.
- [ ] Send a banner announcement and confirm every PUMPE shows the banner and keeps it in Alerts.
- [ ] Send a full screen announcement and confirm it stays until **Continue**, returns if dismissed by restarting the PUMPE, and that acknowledging on one phone leaves it waiting on another.
- [ ] Run the retired Tax Controller and confirm it points at the Admin Terminal instead of failing.

## Border Controller

- [ ] Enter a temporary visa, confirm a second entry is denied, then use **Exit Territory** and confirm the visa locks even with days remaining.
- [ ] Confirm an overdue temporary visitor can still exit and close the visit.
- [ ] Enter and exit with citizenship, then confirm immediate reuse is blocked by the permanent-code cooldown.
- [ ] Confirm **Change Territory**, **Close**, and caught terminate attempts remain locked until the correct territory-owner PIN is entered.
- [ ] Confirm every approved enter or exit action powers back redstone for exactly five seconds.

## Events

- [ ] Create an event in the future with two ticket types.
- [ ] Confirm PUMPE and Event Kiosk countdowns agree.
- [ ] Buy tickets and confirm stock, revenue, and balance all update once.
- [ ] Validate a ticket, mark it used, then confirm a second scan is blocked.

## Tax and subscriptions

- [ ] Create a daily subscription and advance one in-game day.
- [ ] Confirm exactly one charge and one customer notification.
- [ ] Change the government key, open a tax period, and file a declaration.
- [ ] Underpay once and confirm the PUMPE offers to settle the difference.
- [ ] Issue a State Deposit and verify its audit-history entry.

## Interface

- [ ] Tap buttons on the CCG and Service Kiosk monitors and confirm each press flashes before acting.
- [ ] Open a kiosk payment confirmation with a long description and confirm the whole description wraps instead of being cut to one line.
- [ ] Open the touch keyboard on a PUMPE, a computer, and a monitor. Confirm every key row, **SPACE**, **CANCEL**, and **DONE** are visible and do not overlap.
- [ ] Open the PIN pad on each screen size and confirm all twelve keys and **BACK** stay on screen.
- [ ] Confirm the Bank Server dashboard shows accounts, payments, live CCG games, the internet update status, and the Easy Deployment status.
- [ ] Leave the Event Kiosk, Tax Controller, and Border Controller dashboards open and confirm the clock still blinks while the Bank is queried only every five seconds.

## Failure handling

- [ ] Stop the Bank Server during a client request and confirm a timeout message appears.
- [ ] Restart the Bank Server and sign in again without data loss.
- [ ] Let a payment code expire and confirm no money moves.
- [ ] Disconnect the CCG console during a waiting lobby and confirm the five-minute expiry returns all wagers.
