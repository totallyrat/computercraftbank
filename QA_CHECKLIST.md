# In-game QA checklist

Run this after installing into a ComputerCraft world.

## Hardware preflight

- [ ] Bank Server has an open wireless or Ender modem.
- [ ] Every client resolves the `PUMPE_BANK_V5` Rednet host.
- [ ] Service Kiosk uses an Advanced Computer.
- [ ] Optional customer display is an Advanced Monitor and reports as connected under **System**.
- [ ] GPS hosts exist if Proximity Pay will be tested.

## Easy Deployment

- [ ] Start the first Bank Server without `/updates/` and confirm it creates and stages the depot.
- [ ] Restart and confirm the server activity feed says **Easy Deployment online**.
- [ ] Replace a local distributable script, restart the Bank Server, and confirm its `/updates/` copy is refreshed.
- [ ] Copy only `startup.lua` to the root of a clean Advanced Computer, restart, and confirm the touch installer opens automatically.
- [ ] Install PUMPE and confirm the main script, config, launcher, installer, and all three `lib/` files arrive under `/pumpe`.
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

## Core banking

- [ ] Create two accounts and confirm each starts with the configured balance.
- [ ] Restart the Bank Server and confirm both accounts still exist.
- [ ] Send money and confirm both balances and histories update once.
- [ ] Try a wrong PIN and an insufficient balance.
- [ ] Open Sign In and Create Account PIN pads on a Pocket Computer and confirm both touch and physical digit entry work without an error.

## Service Kiosk and monitor

- [ ] Register and link a company.
- [ ] Add at least three Quick Items.
- [ ] On a 1×1 Advanced Monitor at text scale `0.5`, confirm names, quantities, prices, and the total fit without overlap.
- [ ] Tap the same item twice and confirm the monitor shows `2x`.
- [ ] Clear the cart and confirm the monitor resets.
- [ ] Create a payment code, cancel it, and confirm the PUMPE cannot redeem it.
- [ ] Create another code, pay it, and confirm the paid animation and merchant balance.
- [ ] Detach the monitor and confirm the kiosk continues working.
- [ ] Reattach it, tap **Rescan Monitor**, and confirm the idle screen returns.

## Proximity

- [ ] Open a customer's PUMPE dashboard near the kiosk.
- [ ] Start Proximity Pay and confirm the correct customer and distance.
- [ ] Decline once, then approve a second request with a PIN.

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
