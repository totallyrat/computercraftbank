# In-game QA checklist

Run this after installing into a ComputerCraft world.

## Hardware preflight

- [ ] Bank Server has an open wireless or Ender modem.
- [ ] Every client resolves the `PUMPE_BANK_V5` Rednet host.
- [ ] Service Kiosk uses an Advanced Computer.
- [ ] Optional customer display is an Advanced Monitor and reports as connected under **S → Rescan Display**.
- [ ] CCG uses an Advanced Computer, an Ender/wireless modem, and an Advanced Monitor; test both a 1×1 monitor at scale `0.5` and the intended larger wall.

## Easy Deployment

- [ ] Install a fresh Bank from files on the computer drive and confirm the source files are moved—not duplicated—into `/pumpe` and `/updates` before the Bank launches.
- [ ] Upgrade a v6.0.1 Bank with duplicate runtime files in `/updates`; confirm Easy Deployment frees those copies before replacing `bank_server.lua`, then the Bank starts with no duplicate runtime or stale update folders.
- [ ] Confirm `/pumpe` contains only the Bank runtime, installer, config, and required libraries, while `/updates` contains one copy of each role-specific program plus `public/config.lua`.
- [ ] Keep the full release beside `startup.lua`, choose **Bank Server**, enter `4040`, and confirm it installs locally without trying to find a running Bank Server.
- [ ] Confirm the Bank launches immediately, creates `/updates/`, and reports **Easy Deployment online** without stopping at another menu.
- [ ] Replace a local distributable script, restart the Bank Server, and confirm its `/updates/` copy is refreshed.
- [ ] Copy only `startup.lua` to the root of a clean Advanced Computer, restart, and confirm the touch installer opens automatically.
- [ ] Install PUMPE and confirm the main script, config, installer, and all required `lib/` files arrive under `/pumpe`.
- [ ] Install **CCG Bet Console** and confirm `ccg.lua`, config, installer, and all required `lib/` files arrive under `/pumpe` and CCG starts after reboot.
- [ ] Restart after installation and confirm the selected role starts automatically.
- [ ] Enter a wrong protected code and confirm Bank Server and Tax Controller downloads are denied.
- [ ] Enter `4040` and confirm a protected role downloads successfully.
- [ ] Interrupt a download and confirm existing installed scripts remain unchanged.
- [ ] Confirm an unrelated existing `/startup.lua` is preserved.

## Automatic Internet Updates

- [ ] Enable ComputerCraft HTTP and allow the chosen HTTPS release domain.
- [ ] Set `update_manifest_url` in the Bank Server's local `config.lua`.
- [ ] Host the manifest and all listed files together with their relative paths intact.
- [ ] Start on an older version, publish a higher version, and confirm the dashboard changes from **CHECKING INTERNET** to **DOWNLOADING** and **RESTARTING**.
- [ ] Confirm the Bank Server database and custom government key survive the update.
- [ ] Corrupt one hosted file and confirm its checksum fails without replacing the installed release.
- [ ] Remove one manifest file and confirm the whole release is rejected.
- [ ] Start an older client and confirm it updates from the Bank Server and reboots before opening its role.
- [ ] Leave an older client dashboard open, publish a newer release, and confirm its live check installs and reboots without manual input.
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

- [ ] On a fresh PUMPE, complete all three onboarding pages and create a Foxy Account.
- [ ] Confirm **Setting up your Foxy Account** and **Preparing your PUMPE** animate without forcing an unnecessary reboot.
- [ ] On an Advanced Pocket Computer at its native 26×20 size, confirm every onboarding line, header, button label, and footer is fully visible.
- [ ] Confirm the Home Screen has four two-column app pages and every full app name is readable and opens the correct app.
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

## Failure handling

- [ ] Stop the Bank Server during a client request and confirm a timeout message appears.
- [ ] Restart the Bank Server and sign in again without data loss.
- [ ] Let a payment code expire and confirm no money moves.
- [ ] Disconnect the CCG console during a waiting lobby and confirm the five-minute expiry returns all wagers.
