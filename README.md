# PUMPE Ecosystem v5

A working, touch-first digital economy for ComputerCraft: Tweaked. It includes personal banking, merchant checkout, an optional customer-facing order display, proximity payments, subscriptions, event tickets, customs, citizenships, visas, border gates, taxes, and a persistent central bank.

## What is included

| Program | Hardware | Purpose |
| --- | --- | --- |
| `bank_server.lua` | Advanced Computer + wireless/Ender modem | Persistent database, request API, settlement, customs, visits, subscriptions, events, tax, live server dashboard |
| `pumpe.lua` | Advanced Pocket Computer + wireless modem | Personal phone, payments, Customs and Visas apps, events, tickets, tax, subscriptions |
| `service_kiosk.lua` | Advanced Computer + wireless/Ender modem | Touch POS, Quick Pay cart, codes, proximity requests, withdrawals, subscriptions |
| `event_kiosk.lua` | Advanced Computer + wireless/Ender modem | Event creation, ticket inventory, animated analytics, door admission |
| `tax_controller.lua` | Advanced Computer + wireless/Ender modem | Government-only periods, rates, revenue, deposits, audits, bank statistics |
| `border_controller.lua` | Advanced Computer + wireless/Ender modem | Checks travel codes, records visitors, and opens a redstone gate |
| `lib/` | Copied with every program | Shared UI, clock, storage, and networking code |

All screens support touch. Physical keyboard input also works.

## PUMPE phone experience

PUMPE now behaves like a small phone rather than a list of bank buttons:

- A three-page animated onboarding introduces PUMPE and creates or signs into a **Foxy Account**.
- Account setup performs the real device save, account refresh, and Bank Server discovery while showing **Setting up your Foxy Account** and **Preparing your PUMPE**.
- The Home Screen uses a roomy two-column, three-page app grid with phone-style status, app transitions, cards, navigation, touch feedback, and a home indicator.
- Every PUMPE screen is laid out against the Advanced Pocket Computer's native 26×20 character canvas. Buttons, messages, confirmations, activity, events, tickets, notifications, and subscriptions wrap onto readable lines instead of hiding labels beyond the edge.
- Wallet, Activity, Events, Tickets, Notifications, Visas, Customs, Tax, Subscriptions, and Settings open as individual apps.
- After one minute without touch or keyboard activity, PUMPE opens its Lock Screen with the current in-game time and day. Opening it before two minutes needs no PIN; after two minutes, the Foxy Account PIN is verified by the Bank Server.

### PUMPE Pay

PUMPE Pay presents three options in this order:

1. **Code Pay** accepts the kiosk's six-character payment code.
2. **Proximity Pay** broadcasts a fresh GPS position every two seconds while enabled, allowing a nearby Service Kiosk to send a payment request.
3. **Send Money** sends money to another Foxy Account username.

For Send Money, the entered amount is what the recipient receives. The sender pays that amount plus a 10% processing fee, rounded up to the nearest cent. The review screen shows **They Receive**, **Fee**, and **You Pay** before requesting the PIN. The Bank Server independently calculates the fee and enforces a separate `$2,000` recipient-amount limit per in-game day, so modifying the PUMPE client cannot bypass either rule.

## The new customer monitor

The Service Kiosk automatically finds the first attached **Advanced Monitor**. A single 1×1 monitor is enough; the kiosk sets it to text scale `0.5` and adapts to its actual resolution.

The customer display has five animated states:

1. Idle branding and a pulsing ready indicator.
2. A live receipt that updates immediately when the cashier taps a product.
3. Total, six-character payment code, and a live expiry countdown.
4. Proximity-payment approval status.
5. A full-screen paid/thank-you animation with the amount and customer name.

The kiosk remains fully usable without the monitor. Attach one later and tap **System → Rescan Monitor**.

## Easy Deployment

Only the first Bank Server needs the complete project copied locally. Every other computer needs just the standalone `startup.lua`.

### 1. Bootstrap the first Bank Server

1. Copy this complete folder to `/pumpe` on the one authoritative Bank Server.
2. Edit `/pumpe/config.lua` and change `government_key`.
3. Run `/pumpe/launcher bank`.
4. On its first launch, the Bank Server creates `/updates/`, stages every distributable script and library from its local project, and creates a sanitized public client config. Later launches re-sync those authoritative local files so clients receive the current version.
5. Tap **Restart Now**. Easy Deployment becomes available after that restart.

If a required source file is missing, the first-boot screen lists it and lets you rescan after adding it.

### 2. Install any other computer

1. Copy only the supplied `startup.lua` to the new computer as `/startup.lua`.
2. Attach a wireless or Ender modem, then restart the computer. You can also run `startup` immediately.
3. Tap the desired role.
4. Bank Server and Tax Controller downloads require code `4040`. Border Controller is available as an ordinary role.
5. The installer downloads and verifies the main program, `config.lua`, `launcher.lua`, `installer.lua`, and every required file under `lib/`.
6. After installation, it replaces its own marked `/startup.lua` with the selected role launcher. Tap **Reboot Now** and that role starts automatically.

Files are downloaded in verified chunks and staged before anything is replaced. A failed installation rolls back. Existing PUMPE data files are never touched, and an unrelated `/startup.lua` is preserved. The installed `/pumpe/installer.lua` is a manual copy of the one-file installer, so Easy Deployment can be reopened later. `config.lua` is replaced with the Bank Server's current role-appropriate configuration so every installed device connects correctly.

The first Bank Server cannot download itself because no deployment host exists yet. It must always be bootstrapped from the complete local package.

## Automatic Internet Updates

The Bank Server can now watch an HTTPS release folder for new PUMPE versions. It checks the small `release_manifest.json` every 10 seconds. When the manifest contains a newer semantic version, the server:

1. Downloads every required script into a private staging folder.
2. Rejects missing, unexpected, oversized, or path-traversing files.
3. Verifies every byte count and checksum.
4. Preserves the existing government key, release URL, and all other local configuration.
5. Atomically replaces the program files, rolling back if any move fails.
6. Replaces only its PUMPE-owned `/startup.lua` with the Bank Server role launcher, saves the database, and restarts immediately.
7. Detects the restart marker, bypasses Easy Deployment, and rebuilds `/updates/` while launching the Bank Server normally.

Installed PUMPEs, Service Kiosks, Event Kiosks, Tax Controllers, and Border Controllers quietly compare versions with the Bank Server whenever they start and continue checking from their live dashboards. If a newer version exists, they download, verify, install, and reboot automatically. Only the Bank Server contacts the public internet; clients update from its verified `/updates/` depot over Rednet.

The v5.3 release keeps the online manifest compatible with existing v5.2.1 Bank Servers. After the core update, the new server retrieves `border_controller.lua` from the same HTTPS release folder, verifies its release checksum, and places it in `/updates/`. A temporary download failure never sends an automatically restarting Bank Server back into Easy Deployment; it keeps serving and retries the Border Controller depot repair.

### Release source

This package is connected to the public `totallyrat/computercraftbank` GitHub repository. Bank Servers use:

```lua
auto_update = true,
update_manifest_url = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json",
update_channel = "stable",
update_check_seconds = 10,
```

The manifest and source files share the repository root. For example, `lib/update.lua` is available relative to the manifest as `lib/update.lua`. The Minecraft server's ComputerCraft HTTP configuration must allow HTTPS access to `raw.githubusercontent.com`.

### Publishing each new version

After editing the release and increasing `version` in `config.lua`, run:

```text
node tools/build_release_manifest.js
```

Commit or upload the changed source files and regenerated `release_manifest.json` together. The Bank Server will discover the higher version on its next check. Never publish a partially uploaded release with the new manifest first; upload the files first and the manifest last.

### Manual launching

You can still start any installed role manually:

```text
/pumpe/launcher bank
/pumpe/launcher pumpe
/pumpe/launcher service
/pumpe/launcher event
/pumpe/launcher tax
/pumpe/launcher border
```

To start a role automatically, create `/startup.lua` on that device:

```lua
shell.run("/pumpe/launcher.lua", "service")
```

Replace `service` with `bank`, `pumpe`, `event`, `tax`, or `border`.

## Hardware notes

### Bank Server

- Keep it on a dedicated computer.
- An Ender modem is ideal when devices are spread across dimensions.
- Data is saved atomically to `bank_data_v5.dat` beside the program.
- Back up that file. It contains the full economy.

### PUMPE

- Use an Advanced Pocket Computer with a wireless modem.
- The header clock uses ComputerCraft's in-game clock.
- Event cards and tickets show a live countdown calculated from `event_day` and `event_time`.
- Proximity Pay needs a normal ComputerCraft GPS network. While enabled, the PUMPE refreshes its position every two seconds while the app is running.

### Service Kiosk

- Use an Advanced Computer so every action can be tapped.
- Attach an Advanced Monitor directly or through a wired peripheral network.
- Quick Items belong to the linked company and therefore appear on every linked kiosk.
- A linked kiosk settles sales into the company owner's PUMPE balance. An unlinked kiosk uses its own local merchant balance.

### Event Kiosk

- Signs in with an ordinary PUMPE account.
- Event day is the in-game day number.
- Event time is entered as four digits (`1830` becomes `18:30`).

### Tax Controller

- Will refuse to unlock while the default government key is still configured.
- Government sessions expire automatically.
- Every deposit and tax movement is written to the bank transaction log.

### Border Controller

- Use an Advanced Computer with a wireless or Ender modem.
- During setup, sign into the Foxy Account that owns the destination territory and choose that territory.
- Travelers enter the eight-character code shown in their Visas app.
- Approved entry records the traveler as **Visiting**, shows the remaining stay and departure day, and powers the back redstone side for exactly five seconds.
- Citizenship and Free Roam are permanent. A temporary visa starts its approved stay on first entry and cannot be reused after that stay expires.

## First-run flow

### Bank

Start it once and leave it running. The touch dashboard shows account and transaction counts, recent activity, manual save, and safe shutdown.

### Personal PUMPE

Complete the animated introduction, choose **Set Up New Account**, set a four-digit PIN, and choose how PUMPE should address you. The resulting identity is called a **Foxy Account**, and new accounts receive the configured starting balance.

### Customs and Visas

Open **Customs** to create a territory. Its owner automatically receives citizenship and can grant permanent citizenship to other Foxy Accounts, review visa applications, and allow citizens of selected territories permanent Free Roam into the destination.

Open **Visas** to see citizenship and visa codes, active visits and departure days, Free Roam access, application history, or request a 1–30 in-game-day visa. The destination territory owner approves or declines each request in Customs.

### Service Kiosk

The kiosk registers itself, asks for its public name, then offers to link a company:

- Sign in with the company owner's PUMPE account.
- Select an owned company or create one.
- Add products under **Items**.
- Open **Quick Pay** and tap products to build the cart.

Skipping company setup is safe. You can link later under **System → Link Company**.

### Events

Sign in, create the event, then add one or more ticket types. Customers immediately see active future events in their PUMPE.

## Important behavior

- Payment codes expire after five minutes and can be cancelled by the cashier.
- Purchases above the configured PIN-free limit require the customer's PIN.
- Send Money always requires a PIN, charges the server-calculated 10% fee, and has a separate `$2,000` daily limit.
- PUMPE locks after 60 seconds of inactivity and begins requiring a PIN after 120 seconds.
- Ticket purchases always require a PIN and are limited to the configured quantity per purchase.
- A ticket code becomes invalid immediately after **Mark Used + Admit**.
- Subscriptions charge once per in-game day. Failed charges notify the customer and retry the next day.
- Sessions are kept in memory and expire after 12 hours by default. Restarting the Bank Server signs clients out without changing their data.
- The PUMPE stores only the last account name locally, never the PIN.
- Citizenship codes grant permanent entry to their own territory. They also grant permanent entry wherever that citizenship has active Free Roam.
- Temporary visa departure days are calculated by the Bank Server when the visa is first accepted at a Border Controller.

## Security reality check

This is strong for a Minecraft roleplay economy, not a real bank:

- PINs use the documented DJB2-style hash and are not cryptographically secure.
- The fixed deployment code `4040` is access friction, not serious security; Rednet exposes traffic to the Minecraft network.
- Anyone with filesystem access to the Bank Server can alter the database or configuration.
- ComputerCraft Rednet traffic is not end-to-end encrypted.

Protect the Bank Server physically, restrict shell access, change the government key, and keep backups.

## Project structure

```text
pumpe/
├── bank_server.lua
├── pumpe.lua
├── service_kiosk.lua
├── event_kiosk.lua
├── tax_controller.lua
├── border_controller.lua
├── startup.lua
├── installer.lua
├── launcher.lua
├── config.lua
├── release_manifest.json
├── tools/
│   └── build_release_manifest.js
└── lib/
    ├── net.lua
    ├── ui.lua
    ├── update.lua
    └── util.lua
```

## Troubleshooting

**Bank offline**

- Make sure the Bank Server started first.
- Confirm every device uses the same `protocol` and `hostname`.
- Check that a wireless or Ender modem is attached and enabled.

**Customer monitor is blank**

- It must be an Advanced Monitor, not a basic monitor.
- Tap **System → Rescan Monitor** after attaching it.
- If several color monitors are attached, the kiosk uses the first one found.

**Proximity Pay finds nobody**

- Build and name a ComputerCraft GPS network.
- Open **PUMPE Pay → Proximity Pay** and confirm it says **Broadcasting nearby**.
- The customer must be within the kiosk's 32-block search radius.

**Events show the wrong countdown**

- Event scheduling intentionally uses the Minecraft in-game day and time, not real-world time.
- Check the current day shown in the event creation flow.

## Version

PUMPE Ecosystem `5.3.0`.
