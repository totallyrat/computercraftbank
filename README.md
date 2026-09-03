# PUMPE Ecosystem v6.2

A working, touch-first digital economy and gaming network for ComputerCraft: Tweaked. It includes personal banking, ComputerCraftGaming (CCG) Bet Play, a Square-style merchant POS, an optional customer-facing order display, subscriptions, event tickets, customs, citizenships, visas, border gates, taxes, and a persistent central bank.

## What is included

| Program | Hardware | Purpose |
| --- | --- | --- |
| `bank_server.lua` | Advanced Computer + wireless/Ender modem | Persistent database, request API, banking, CCG settlement/physics, customs, subscriptions, events, tax, live dashboard |
| `pumpe.lua` | Advanced Pocket Computer + wireless modem | Personal phone, payments, Bet and Bet Wallet apps, Customs and Visas, events, tickets, tax, subscriptions |
| `ccg.lua` | Advanced Computer + Ender modem + Advanced Monitor | ComputerCraftGaming Bet Play lobbies, game animations, Race track, and Survivor arena |
| `service_kiosk.lua` | Advanced Computer + wireless/Ender modem | Square-style touch POS, favorites, products, receipts, payment codes, withdrawals, subscriptions |
| `event_kiosk.lua` | Advanced Computer + wireless/Ender modem | Event creation, ticket inventory, animated analytics, door admission |
| `tax_controller.lua` | Advanced Computer + wireless/Ender modem | Government-only periods, rates, revenue, deposits, audits, bank statistics |
| `border_controller.lua` | Advanced Computer + wireless/Ender modem | Checks travel codes, records visitors, and opens a redstone gate |
| `lib/` | Copied with every program | Shared UI, clock, storage, and networking code |

All screens support touch. Physical keyboard input also works.

## PUMPE phone experience

PUMPE now behaves like a small phone rather than a list of bank buttons:

- A three-page animated onboarding introduces PUMPE and creates or signs into a **Foxy Account**.
- Account setup performs the real device save, account refresh, and Bank Server discovery while showing **Setting up your Foxy Account** and **Preparing your PUMPE**.
- The Home Screen uses a roomy two-column, four-page app grid with phone-style status, app transitions, cards, navigation, touch feedback, and a home indicator.
- Every PUMPE screen is laid out against the Advanced Pocket Computer's native 26×20 character canvas. Buttons, messages, confirmations, activity, events, tickets, notifications, and subscriptions wrap onto readable lines instead of hiding labels beyond the edge.
- The Home Screen opens on **Favourites**, up to four apps you choose yourself, then the app pages, then **Alerts**.
- **BuckApp** holds the balance, payments behind **Continue**, the Bet Wallet and Activity.
- **Friends** holds Messages, Friends and Urgent Contact, badged with whatever is waiting.
- **Tickets** holds events and your own tickets; **Customs** holds visas and territories.
- Alerts are part of the OS rather than an app: their own Home Screen page, a `!` in the page dots, and a banner across the top of whatever app is open when something new arrives.
- **Bet** and **Bet Wallet** are separate apps. Bet requires the Foxy Account PIN every time it opens; Bet Wallet shows available and held game funds and requires the PIN for transfers.
- After one minute without touch or keyboard activity, PUMPE opens its Lock Screen with the current in-game time and day. Opening it before two minutes needs no PIN; after two minutes, the Foxy Account PIN is verified by the Bank Server.

## Friends, Messages, and Urgent Contact

### Friends

Open **Friends** to see who you know, tap **Add** to search any Foxy Account by name, and accept or decline the requests waiting under **Requests**. Asking someone who already asked you makes you friends immediately rather than leaving two requests crossing.

Tapping a friend opens your chat with them. `X` removes them after a confirmation.

### Messages

**Messages** holds one chat per friend plus group chats of up to eight people. A direct chat is never duplicated, whoever starts it.

- **Message** opens the touch keyboard.
- **Money** offers **Send money**, **Ask for money**, and — when a friend has asked you — **Pay**.
- A money request stays in the transcript until it is paid or declined. Paying takes the PIN.
- A chat raises an alert only when it goes from read to unread, so a busy group never floods the Alerts list.

### Urgent Contact

**Urgent Contact** reaches a friend right now. They get a full-screen ring with **Accept** and **Decline** whatever app they had open, because the check runs in the shared wait loop rather than in any one screen.

Once accepted, both sides poll a live transcript several times a second, so a typed line appears on the other screen straight away. Inside a call you can send money, ask for money, and pay a request, all under the same PIN and fee rules as PUMPE Pay.

- **Hang up** at the bottom ends the call from either side.
- **Save** at the top is a *vote*. The transcript is written into your normal chat only once both people have pressed it; one vote alone saves nothing.
- An unanswered call becomes a missed call for both sides after 30 seconds.

Calls are never written to the database. A Bank Server restart drops a live call the way a dropped connection would, and only a transcript both people agreed to save is kept.

### PUMPE Pay

PUMPE Pay presents two options:

1. **Code Pay** accepts the kiosk's six-character payment code.
2. **Send Money** sends money to another Foxy Account username.

For Send Money, the entered amount is what the recipient receives. The sender pays that amount plus a 10% processing fee, rounded up to the nearest cent. The review screen shows **They Receive**, **Fee**, and **You Pay** before requesting the PIN. The Bank Server independently calculates the fee and enforces a separate `$2,000` recipient-amount limit per in-game day, so modifying the PUMPE client cannot bypass either rule.

## ComputerCraftGaming Bet Play

CCG is a shared big-screen gaming system. Create a lobby on `ccg.lua`, then players open **Bet** on their PUMPE, verify their PIN, enter the screen's alphanumeric lobby code, choose a display name, make their pick, and set a wager from their Bet Wallet.

Three games are included:

1. **Heads or Tails** — pick a side. A correct pick pays `2×` the wager.
2. **Race** — pick one of six red, orange, yellow, green, blue, or purple cars. The six-lane animated race has a server-random winner and pays `3×`.
3. **Survivor** — use the PUMPE touch joystick to move and **PUSH** nearby players from a shrinking circular platform. The last player standing receives `3×` their wager.

The Bank Server is authoritative. It generates chance-game outcomes, reserves wagers, simulates Survivor positions and pushes, decides the winner, and settles each lobby once. A modified PUMPE or CCG console cannot submit its preferred result. Waiting lobbies expire after five minutes and return every reserved wager; a Bank restart during an active Survivor round also refunds everyone rather than guessing a winner.

Winnings do not enter the normal Foxy Account directly. They enter **Holding** for exactly 24 in-game hours, including the original stake in the advertised multiplier, then release into the **Bet Wallet**. Bet Wallet money can be transferred back to the Foxy Account in any positive amount. Adding or cashing out money requires the account PIN. CCG uses fictional PUMPE game currency only.

Home Play and its Pocket Computer controller are intentionally deferred to a later update; v6.2.0 contains the complete Bet Play mode.

### Auto Mode

Auto Mode turns a CCG console into an unattended arcade cabinet. Tap **AUTO MODE // NON-STOP** on the game picker, choose one game or **Rotate All Games**, then type a stop code twice.

From then on the console runs by itself:

1. It opens a lobby and shows the join code.
2. When every player who joined is **READY**, a countdown starts (`ccg_auto_start_seconds`, default 15). The operator can still tap **START** to begin immediately.
3. The game plays and settles as usual.
4. The result stays up for `ccg_auto_next_seconds` (default 8), then the next lobby opens.
5. If nobody joins before a lobby expires, every reserved wager is returned and a fresh lobby opens straight away.

Auto Mode never stops on its own. **STOP AUTO** asks for the code entered when the mode was started; a wrong code leaves it running. The setting is saved to the console, so a restart — including one caused by an automatic update — comes back into Auto Mode instead of the game menu. Rotate mode remembers which game is next across restarts.

## The new customer monitor

The Service Kiosk automatically finds the first attached **Advanced Monitor**. A single 1×1 monitor is enough; the kiosk sets it to text scale `0.5` and adapts to its actual resolution.

The customer display has four animated states:

1. Idle branding and a pulsing ready indicator.
2. A live receipt that updates immediately when the cashier taps a product.
3. Total, six-character payment code, and a live expiry countdown.
4. A full-screen paid or subscription-active animation with the amount and customer name.

The kiosk remains fully usable without the monitor. Attach one later and tap **S → Rescan Display**.

## Easy Deployment

Only the first Bank Server needs the complete release copied locally. Every other computer needs just one standalone file. `startup.lua` and `installer.lua` are identical; use `startup.lua` at the computer root for automatic launch, or run `installer.lua` manually.

### 1. Bootstrap the first Bank Server

1. Keep `startup.lua` beside the complete release on the one authoritative Bank Server.
2. Edit the local `config.lua` and change `government_key`.
3. Run `startup`, choose **Bank Server**, and enter `4040`.
4. Easy Deployment verifies the complete local bundle, moves same-drive files directly into the compact Bank layout, writes an installer-based `/startup.lua`, and launches `bank_server.lua` immediately. It never tries to discover a Bank Server that does not exist yet.
5. `/pumpe` keeps only the Bank runtime, installer, config, and shared libraries. `/updates` keeps one copy of each role-specific program plus the sanitized public client config; shared runtime files are served directly without duplication.

If a required source file is missing, the first-boot screen lists it and lets you rescan after adding it.

### 2. Install any other computer

1. Copy only the supplied `startup.lua` to the new computer as `/startup.lua`.
2. Attach a wireless or Ender modem, then restart the computer. You can also run `startup` immediately.
3. Tap the desired role.
4. Bank Server and Tax Controller downloads require code `4040`. Border Controller and **CCG Bet Console** are available as ordinary roles.
5. The installer downloads and verifies the main program, `config.lua`, `installer.lua`, and every required file under `lib/`.
6. After installation, it replaces its own marked `/startup.lua` with a direct `installer.lua --boot <role>` entry. Tap **Reboot Now** and that role starts automatically.

Files are downloaded in verified chunks and staged before anything is replaced. A failed installation rolls back. Existing PUMPE data files are never touched, and an unrelated `/startup.lua` is preserved. The installed `/pumpe/installer.lua` is both the permanent boot manager and the one-file Easy Deployment menu.

An unassigned installer checks the public HTTPS manifest and safely replaces itself when a newer installer exists, so a clean computer learns about newly added roles such as Border Controller without first becoming another device type. Booting an already installed client role never contacts the internet — that copy of `installer.lua` arrives from the Bank Server's verified depot instead, and the role starts without waiting on an HTTPS round trip.

The role picker shows the role and version this computer already has, and offers **START ROLE** so an installed computer can be relaunched without reinstalling anything.

The first Bank Server cannot download itself because no deployment host exists yet. It must always be bootstrapped from the complete local package.

## Automatic Internet Updates

The Bank Server watches an HTTPS release folder for new PUMPE versions. It checks the small `release_manifest.json` every few seconds. When the manifest contains a newer semantic version, the server:

1. Downloads every required script into a private staging folder.
2. Rejects missing, unexpected, oversized, or path-traversing files.
3. Verifies every byte count and checksum.
4. Preserves the existing government key, release URL, and all other local configuration.
5. Atomically replaces the program files, rolling back if any move fails.
6. Refreshes `/pumpe/installer.lua`, writes a direct Bank boot entry, saves the database, and restarts immediately.
7. Detects the restart marker, bypasses every menu, compacts `/updates/`, and launches the Bank Server normally.

Every role updates itself. A PUMPE, CCG console, kiosk, controller or Bank checks the public manifest when it starts and every `client_update_check_seconds` (default 30), then downloads **only the files that role needs** — its own program, Easy Deployment and the shared libraries. Nothing downloads another role's program.

Local configuration survives: each device merges the published config over its own, so your currency, limits and government key are preserved rather than reset to the published placeholder.

The Bank Server's `/updates` is a cache, not a stockpile. It fetches a role program the first time a client installs that role, and drops the cache whenever a release needs the room. A device whose ComputerCraft HTTP access is switched off falls back to that depot over Rednet, so restricting HTTP costs update speed but never strands a device.

Because each device stages only its own role, the worst-case update peaks at about 577 KiB of ComputerCraft's 1000 KiB computer, leaving roughly 423 KiB for account data.

### Manifest layout

The manifest's `files` array stays byte-compatible with v5.2.1 Bank Servers, whose updater rejects any entry it does not already know. Anything added since then — currently `border_controller.lua` and `ccg.lua` — is published in a second `extra_files` array:

- Older Bank Servers ignore `extra_files` entirely and keep updating from `files`.
- Current Bank Servers download both arrays into the same staged, checksum-verified, atomic commit.

`launcher.lua` is retained only as a migration bridge for older startup entries; v6 installations and normal boots do not use it.

A Bank Server that arrives from a release which published fewer files still has old copies in `/updates/`. On its next check it compares every depot program against the manifest describing the version it is running, re-downloads whatever does not match, and writes `/updates/.depot` so the check does not repeat. Nothing is pinned in Lua source, and a temporary download failure simply leaves the depot unstamped for the next attempt.

### Release source

This package is connected to the public `totallyrat/computercraftbank` GitHub repository. Bank Servers use:

```lua
auto_update = true,
update_manifest_url = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json",
update_channel = "stable",
update_check_seconds = 5,
client_update_check_seconds = 60,
```

The manifest and source files share the repository root. For example, `lib/update.lua` is available relative to the manifest as `lib/update.lua`. The Minecraft server's ComputerCraft HTTP configuration must allow HTTPS access to `raw.githubusercontent.com`.

### Publishing each new version

After editing the release and increasing `version` in `config.lua`, run:

```text
node tools/build_release_manifest.js
tools/run_tests.sh
```

The builder is the only step. It copies `startup.lua` to `installer.lua`, stamps `INSTALLER_VERSION` from `config.lua`, and regenerates `release_manifest.json` with both file arrays. It never rewrites program source, and nothing has to be checksummed by hand.

`tests/host_release_manifest_test.lua` then fails the suite if the manifest, the version stamp, or the two entry points have drifted from the files in the repository — so a stale manifest cannot be published by accident.

Commit or upload the changed source files and regenerated `release_manifest.json` together. The Bank Server will discover the higher version on its next check. Never publish a partially uploaded release with the new manifest first; upload the files first and the manifest last.

### Manual launching

You can start any installed role manually through Easy Deployment:

```text
/pumpe/installer.lua --boot bank
/pumpe/installer.lua --boot pumpe
/pumpe/installer.lua --boot service
/pumpe/installer.lua --boot event
/pumpe/installer.lua --boot tax
/pumpe/installer.lua --boot border
/pumpe/installer.lua --boot ccg
```

To start a role automatically, create `/startup.lua` on that device:

```lua
shell.run("/pumpe/installer.lua", "--boot", "service")
```

Replace `service` with `bank`, `pumpe`, `event`, `tax`, `border`, or `ccg`.

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

### CCG Bet Console

- Use an Advanced Computer with an Ender modem and an Advanced Monitor.
- The console sets the monitor to text scale `0.5` and responsively supports a 1×1 monitor or a larger wall.
- Lobby codes, ready states, coin flips, six race lanes, the shrinking Survivor ring, players, and results all render on the monitor.
- Touch **Start** only after every displayed player is ready. Heads or Tails and Race support one or more players; Survivor requires at least two.
- **Auto Mode** does that waiting for you and keeps opening the next lobby. It stops only for the code entered when it was started.
- The console stores only its server-issued ID/token. It never stores PUMPE PINs or decides payouts.

### Service Kiosk

- Use an Advanced Computer so every action can be tapped.
- Attach an Advanced Monitor directly or through a wired peripheral network.
- Products and favorites belong to the linked company and therefore appear on every linked kiosk.
- The cashier always opens on the receipt-and-products POS. Use the top tabs for **Favorited**, **All Products**, and **Subscriptions**, `+` to add a product, and `S` for settings.
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
- The operator explicitly chooses **Enter Territory** or **Exit Territory** before entering the travel code. Every approved action powers the back redstone side for exactly five seconds.
- A temporary visa permits one entry and its matching exit. That exit closes the visit and locks the visa even when approved days remain.
- Citizenship and Free Roam remain reusable, but a server-enforced cooldown prevents rapid code sharing. Changing territory or closing a configured controller requires the territory owner's PIN.

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
- Press `+`, enter a product and price, then choose **One Time** or **Subscription**.
- Favorite products with the `F` control. Tap products to build the receipt on the left and use the side buttons to page through larger catalogs.
- **PAY** also works with an empty receipt: enter a custom amount on the touch keypad, then choose **One Time** or **Subscription**.

Skipping company setup is safe. You can link later under **S → Link Company**.

### Events

Sign in, create the event, then add one or more ticket types. Customers immediately see active future events in their PUMPE.

### CCG

Install **CCG Bet Console**, attach the monitor and modem, and select a game. Players fund **Bet Wallet** from their PUMPE, open the PIN-gated **Bet** app, enter the lobby code and a player name, then choose their wager. The big-screen operator starts the round when everyone shows **READY**.

## Important behavior

- Payment codes expire after five minutes and can be cancelled by the cashier.
- Purchases above the configured PIN-free limit require the customer's PIN.
- Send Money always requires a PIN, charges the server-calculated 10% fee, and has a separate `$2,000` daily limit. Money sent inside Messages or Urgent Contact uses the same server-side path, so the fee, the limit, and the transaction log are identical everywhere.
- You can only message or reach someone who is already a friend.
- A conversation keeps its most recent 60 messages.
- PUMPE locks after 60 seconds of inactivity and begins requiring a PIN after 120 seconds.
- Ticket purchases always require a PIN and are limited to the configured quantity per purchase.
- A ticket code becomes invalid immediately after **Mark Used + Admit**.
- Subscription codes are confirmed with the customer's PIN inside PUMPE. The first charge settles immediately; later charges run once per in-game day. Failed charges notify the customer and retry the next day.
- Sessions are kept in memory and expire after 12 hours by default. Restarting the Bank Server signs clients out without changing their data.
- The PUMPE stores only the last account name locally, never the PIN.
- Citizenship codes grant permanent entry to their own territory. They also grant permanent entry wherever that citizenship has active Free Roam.
- Temporary visa departure days are calculated by the Bank Server on entry, and the document locks permanently after its recorded exit.
- CCG wagers leave Bet Wallet when they are marked ready. Leaving or expiring before a round starts returns the full wager.
- CCG payouts are `2×` for Heads or Tails and `3×` for Race or Survivor. Winning payouts remain held for one complete in-game day before entering the available Bet Wallet balance.
- CCG Auto Mode starts a round only when every player who joined is ready, and returns every wager if a lobby expires empty. It cannot be turned off without its stop code.
- Bet Wallet funds are separate from the normal Foxy Account until the player explicitly transfers them. Both transfer directions require the PIN.

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
├── ccg.lua
├── startup.lua
├── installer.lua
├── launcher.lua
├── config.lua
├── release_manifest.json
├── tools/
│   └── build_release_manifest.js
├── tools/
│   ├── build_release_manifest.js
│   └── run_tests.sh
└── lib/
    ├── net.lua
    ├── ui.lua
    ├── update.lua
    └── util.lua
```

## Tests

`tools/run_tests.sh` runs every host-side test with any Lua 5.2+ interpreter; ComputerCraft is not required. They cover the Bank routes, CCG settlement and Auto Mode, the update manifest, Easy Deployment, and screen layout at pocket, computer, and monitor sizes.

## Troubleshooting

**Bank offline**

- Make sure the Bank Server started first.
- Confirm every device uses the same `protocol` and `hostname`.
- Check that a wireless or Ender modem is attached and enabled.

**The dashboard says NEEDS n KiB FREE**

- A release cannot fit beside the installed one plus the database. The Bank already reclaims `/updates` automatically; if it still does not fit, back up `bank_data_v5.dat` and remove anything unrelated from the Bank computer.
- Upgrading from v6.1.0 or earlier is the tight case, because those versions stage the release without reclaiming anything. Running `delete /updates` in the Bank's terminal — **without rebooting it** — gives the running server room to finish the update, and it rebuilds `/updates` itself once the new version starts.

**Bank says there is no space**

- Restart through the latest Easy Deployment file. It removes safe v6.0/v6.0.1 duplicates before replacing the Bank, so the old Bank does not need to launch first.
- A compact installation is about 515 KiB before account data, against ComputerCraft's default 1000 KiB per-computer limit. Chats add to the database over time, which is why a conversation keeps only its most recent 60 messages.
- An online update briefly needs room for a second copy of the release. The Bank reclaims `/updates` first when it has to, so the peak is about 794 KiB and roughly 206 KiB stays free for account data. `tools/build_release_manifest.js` refuses to publish a release that would not leave that much. Do not manually copy the Bank runtime back into `/updates`; it is served directly from `/pumpe`.

**Customer monitor is blank**

- It must be an Advanced Monitor, not a basic monitor.
- Tap **S → Rescan Display** after attaching it.
- If several color monitors are attached, the kiosk uses the first one found.

**Events show the wrong countdown**

- Event scheduling intentionally uses the Minecraft in-game day and time, not real-world time.
- Check the current day shown in the event creation flow.

**A PUMPE fails to start with a `nil value` error**

- Its program and the shared `lib/` are from different releases. Run Easy Deployment on that computer and reinstall the role; it downloads the program and every library together.
- If several devices show it, the Bank Server itself is serving mismatched files. Restart the Bank so Easy Deployment repairs its whole runtime, then let the clients update again.

**A friend cannot be messaged or reached**

- Messages and Urgent Contact are friends-only. Add them under **Friends** first.
- Urgent Contact refuses a second call while either person already has one open.

**CCG lobby will not start**

- Every listed player must show **READY** after selecting a pick and reserving a wager.
- Survivor requires at least two ready players.
- Confirm the PUMPE has available Bet Wallet funds, not only funds still in Holding.
- In Auto Mode the countdown only begins once every joined player is ready; a single player still picking holds the round.

**Auto Mode will not turn off**

- That is the design. **STOP AUTO** needs the exact code typed when the mode was started.
- If the code is lost, stop the CCG program from the computer's terminal and delete `ccg_device.dat` beside it. The console re-registers on the next start.

## Version

PUMPE Ecosystem `6.2.2`.
