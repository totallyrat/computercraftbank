# Changelog

## 8.1.2

Fixes the Bank Server dying on start-up right after 8.1.1 got it loading
again. **Reboot the Bank computer and it repairs itself.**

- `bank_server.lua:380: attempt to call a nil value (global 'logActivity')`.
  The depot bootstrap runs the moment the file is loaded, and when it drops a
  cache left over from an earlier release it logs that to the dashboard feed —
  but `logActivity` was declared 200 lines further down, so it was still nil.
  The feed and its logger now sit above the bootstrap.
- This was waiting to happen since the lazy depot cache landed in 7.x. It only
  fires when the Bank has cached role programs *and* the version changed, and
  8.1.1's load failure was hiding it.
- `tests/host_bank_bootstrap_test.lua` loads the Bank the way ComputerCraft
  does, with `PUMPE_TEST_MODE` off, so everything that runs before that guard
  is covered: a stale cache being dropped, an automatic-update restart, and a
  cache already stamped for the running release. `PUMPE_TEST_MODE` returns
  early, which is exactly why no existing test could see this.
- A static sweep for the same shape — anything the load-time path touches that
  is declared later — now comes back clean.

## 8.1.1

Fixes the Bank Server refusing to start. **8.0.0, 8.0.1 and 8.1.0 cannot run
the Bank; use this instead.**

- Lua allows 200 local variables per function, and a program's whole top level
  counts as one function. `bank_server.lua` sat at 187 through 7.1.0 and my
  two new government-key constants in 8.0.0 pushed it to 189, past what
  ComputerCraft's Lua accepts: `function at line 5257 has more than 200 local
  variables`, with nothing loading at all. `luac` on a desktop still accepted
  the same file, which is why the test suite never saw it.
- Related constants are now grouped into tables — deployment settings, the
  published file lists, the social limits and the dashboard's status — which
  brings the top level down to 162 with room to work in.
- `tests/host_local_limit_test.lua` measures every program the way the parser
  does and fails above 175, so this cannot reach a release again.
- Dropped two dead declarations found on the way: an unused online-update
  backup path, and an empty extra-file list the Bank iterated for its own
  role.

**Recovering a Bank that will not start:** reboot the computer. Easy
Deployment repairs the whole Bank runtime from the public manifest before
launching it, so one or two reboots brings it back on its own.

## 8.1.0

The first Bank Server no longer needs the release on a drive.

- Choosing **Bank Server** now downloads the Bank's runtime straight from the
  public release manifest over HTTPS, verified file by file and committed
  atomically. A clean computer needs nothing but `startup.lua`, which is the
  point of Easy Deployment: anyone can add the whole system to their world
  from one file.
- Only the Bank's own seven files are fetched. Role programs stay out of it —
  the Bank pulls each one into `/updates` on demand the first time somebody
  installs that role — so a first install moves about 320 KiB instead of
  600 KiB.
- A release package beside `startup.lua` is still the offline route. When HTTP
  is switched off or the manifest cannot be reached, Easy Deployment says
  **NO ONLINE RELEASE** with the reason and installs from the local package
  exactly as before.
- A published file that fails its checksum rolls the whole install back and
  starts nothing, same as every other install path.

## 8.0.1

Hardening for the update path itself. 8.0.0 installs correctly — a shipped
6.9.1, 7.0.1 and 7.1.0 updater each accept it, and a 7.1.0 Bank was walked
through the whole download, checksum, merge and commit against the published
files — but two ways for a device to strand itself were still open.

- **An updater that names no expected files no longer rejects the whole
  release.** It treated every published entry as unexpected, which is the bug
  that had every client silently falling back to the Bank's depot before 8.0.
  A caller with no list now checks each entry's shape — safe path, size,
  checksum — and installs what its role needs. An unsafe path is still
  refused.
- **The Bank writes out its own copy of the published file list again.** 8.0.0
  read it from `lib/update.lua` to keep the two from drifting, but that meant
  a Bank whose updater was older than its program got `nil` and could not
  update itself out of the skew — the exact failure that has cost this project
  three releases. The lists are kept in step by a test instead.

## 8.0.0

A rebuilt PUMPE home screen, a new start-up and sign-up, a clearer
notification centre, and an Easy Deployment that puts the phone first.

### The home screen

- Small icons in a grid with the app name underneath, the way a phone lays
  them out, instead of four large two-line tiles. Every app now fits on one
  page with room to grow, on a 26x20 pocket and on a wider screen alike.
- **Favourites became the dock.** The four you pick sit under every app page
  rather than taking a page of their own, so they are always one tap away. An
  empty dock slot opens the picker; so does **Edit Your Dock** in Settings.
- Unread counts sit in an icon's corner as a badge rather than replacing part
  of its label.
- The header carries your name and your balance; the notification centre is
  still the last page, and its dot turns to `!` when something is waiting.

### Start-up and sign-up

- The PUMPE now opens with its wordmark landing one letter at a time, three
  blinks, then **Small yet Mighty** before anything else happens.
- Sign-up asks one question first — new account, or one you already have —
  then username, then PIN, and ends in a six-step guide to the phone.
- **The guide lives in Settings** under *How PUMPE Works*, so it can be read
  again at any time rather than only once.
- The pronoun step is gone. Nothing displayed it, and the sign-up is three
  steps now.

### The notification centre

- Each alert is a row of its own: a coloured bar for its kind, the title, the
  time it arrived, and the first line of the message. Read alerts fade.
- **Tap an alert to read it in full** on its own screen.
- Longer than one screen now scrolls, instead of silently showing only what
  fit.

### Easy Deployment

- Checks for a newer Easy Deployment **before the menu opens**, on screen, and
  installs it if there is one. Roles that a release adds are therefore on the
  menu the first time it is drawn rather than the second.
- **The PUMPE gets the whole first screen**: a block-letter title, what the
  phone is for, and one button to install it. Every other role is behind the
  **down arrow** at the bottom.

### Fixes

- **The government key did not work.** Releases before 7.1 shipped
  `CHANGE-ME-GOVERNMENT-KEY` as the placeholder, and every Bank that
  self-updated kept it, because an update preserves local settings. The
  documented `Government1234` was therefore rejected on every Bank that
  reached 7.1 by updating rather than by a fresh install. A retired
  placeholder now means "unset", and a release can name a setting it is taking
  back (`config_resets`) so this cannot happen silently again.
- **Clients could never update themselves over the internet.** A role that
  passed no path list of its own made the validator treat every entry in
  `files` as unexpected and throw the whole release away, so every device fell
  back to the Bank's rednet depot without saying so. Roles now fall back to
  the published set, which is one shared list the Bank uses too.
- `lib/update.lua` carried a 154-line copy of itself, spliced into the middle
  of `fetchManifest`. It was harmless — the duplicates were identical — but it
  cost every device 5.8 KiB.
- Captions and alert text no longer inherit whatever background colour was set
  last, which put a red badge's colour behind the word "Friends".

## 7.1.0

The Tax Controller becomes the **Bank Admin Terminal**, and the government can
now talk to every PUMPE at once.

### Bank Admin Terminal

- New protected Easy Deployment role, downloaded with the same code as the
  Bank Server. It keeps every tax control the Tax Controller had — periods,
  rates, revenue, audits, state deposits, bank statistics — and adds the rest
  below.
- The government key now defaults to `Government1234` and is **changed from
  inside the terminal**. The live key lives in the Bank database rather than
  `config.lua`, so it no longer needs a file edited on the Bank.
- **Account approval** can be switched on, after which every new Foxy Account
  waits for approval before it can be used. Existing accounts are never held
  by switching it on.
- **Add money** and **remove money** on any account, both written to the
  transaction log and announced to the holder.
- **Ban** and unban an account. A ban ends the holder's live session at once.
- **Tax demands** of any amount. A demand is owed, not seized: it appears in
  the holder's BuckApp and is paid with their own PIN, so money never moves
  without them.

### System-wide announcements

- Announcements reach every account as an ordinary alert, and as either a
  **banner** across the top of whatever app is open, or a **full screen**
  notice that stays until **Continue** is pressed.
- A full screen announcement keeps returning until that phone acknowledges it,
  and acknowledging on one phone does not clear it for anyone else.

### The Tax Controller

- Retired. Install **Admin Terminal** on that computer instead.
- `tax_controller.lua` is still published, as a stub that says so. The release
  manifest's required list is frozen: Bank Servers older than 7.0.1 reject a
  manifest missing an entry they expect, so removing the file would strand
  them.

## 7.0.1

Fixes v7.0.0 being rejected outright by every Bank Server older than it.
**v7.0.0 cannot be installed; use this instead.**

- `extra_files` exists so a release can add a role without stranding older
  updaters, but it was validated *strictly*: an entry the updater did not
  recognise rejected the whole manifest, exactly like an unknown entry in
  `files`. Adding `gps_anchor.lua` in 7.0.0 therefore made the release
  uninstallable on 6.9.1 and earlier, which reported only `CHECK FAILED`.
- Optional arrays are now advisory. An updater installs the entries it knows
  and silently skips the rest, which is what the array was for.
- `extra_files` is frozen at `border_controller.lua` and `ccg.lua`, since
  Banks older than 7.0.1 still reject unknown entries there. Everything added
  from now on is published in a new `optional_files` array, which those Banks
  never read at all. Both are checked leniently from 7.0.1 onwards.
- Verified both ways: a 6.9.1 Bank accepts this release and installs 14 files,
  ignoring the anchor it does not know; a 7.0.1 Bank installs all 15.

## 7.0.0

Proximity Pay: a kiosk offers the bill to whoever is standing closest.

### GPS Anchors

- Added the **GPS Anchor** role to Easy Deployment. ComputerCraft can only
  work out where something is by trilaterating four hosts with known
  coordinates, so on a network with no constellation nothing can locate
  itself. Anchors are that constellation.
- An anchor reads its position from an existing constellation when one is
  there, and otherwise asks for the block coordinates directly. It answers the
  same `PING` ComputerCraft's own `gps host` answers, so vanilla programs see
  these anchors too.
- Place at least four in range of each other, spread out, with at least one at
  a different height.
- Added a signed number keypad so coordinates below zero can be typed.

### Proximity Pay

- Every PUMPE reports its position with the OS poll it already makes, and the
  Bank keeps the map. Positions older than `position_max_age_ms` are ignored.
- The Service Kiosk's new **NEARBY** button offers the cart to the closest
  PUMPE within `proximity_pay_radius` (default 16 blocks).
- That phone gets a full-screen offer with the merchant, the amount and the
  distance. **Not mine** passes the bill to the next nearest rather than
  cancelling the sale, so the wrong person declining does not cost the
  cashier anything.
- Accepting settles through the ordinary payment code, so the PIN rules,
  daily limits and transaction log are identical to every other payment. A
  charge is never made without a tap.

## 6.9.1

Fixes devices reporting 6.9.0 while still running the previous release's apps.

- **The Bank served a stale cached program.** `/updates` caches a role program
  when a client first installs that role, but nothing invalidated it when the
  Bank itself updated. A Bank that moved to 6.9.0 kept handing clients the
  6.3.0 `pumpe.lua` beside the new `config.lua`, so the phone reported 6.9.0
  with none of the new apps. The cache is now stamped with the release that
  filled it and dropped whenever that differs.
- **Clients never received `lib/update.lua`.** It was in the self-update file
  set but missing from the set the Bank serves over Rednet, so a client
  installed that way could not load the self-updater at all and stayed on the
  Bank fallback permanently. Every role now receives it.
- Added a guard against this whole class of fault: each role program is
  stamped with the release it was built for, and a device that finds its
  program and its `config.lua` disagreeing repairs itself immediately rather
  than waiting out the check interval.

## 6.9.0

The PUMPE stops being a list of banking screens and starts behaving like a
phone. Eight home screen apps become four, alerts move into the OS, and the
first page is yours.

### BuckApp

- Everything to do with money is now one app. It opens on your balance, puts
  payments behind **Continue**, and holds the **Bet Wallet** and **Activity**
  alongside them.
- The separate Wallet, Pay, Activity and Bet Wallet tiles are gone.

### Friends

- Messages, Friends and Urgent Contact are one app with a single home screen
  tile, badged with everything waiting inside it.

### Tickets and Customs

- **Tickets** holds both Browse Events and My Tickets.
- **Customs** holds both My Visas and Territories.

### Alerts in the OS

- The Notifications app is gone. Alerts are now a page of the Home Screen,
  reachable by swiping, with a `!` in the page dots when something is unread
  and **Mark all read** on the page itself.
- New alerts drop a **banner** across the top of whatever app is open, then
  the screen repaints underneath it. The backlog waiting at sign-in never
  banners.

### Favourites

- Page one of the Home Screen is now **Favourites**: up to four apps you pick,
  saved on the device. Tap **+ Edit** to choose them.

### Under the hood

- Added `PUMPE_POLL`, one Bank request that carries an incoming Urgent
  Contact, the newest unread alert for the banner, the balance and every
  badge. The OS polls this instead of making three separate calls.
- Both PUMPE tests now verify that every scripted tap lands on a button that
  is actually on screen. That immediately caught a button id collision
  between the Customs hub and the Visas screen inside it, which a drifting
  test would have hidden.

## 6.3.0

Every device now updates itself. The Bank Server is no longer the middleman
for updates, which removes the whole class of failure that broke 6.1.0
through 6.2.2.

- Each role — PUMPE, CCG, kiosks, controllers and the Bank itself — checks the
  public manifest at restart and every `client_update_check_seconds`
  (default 30), and downloads only the files its own role needs. A PUMPE
  fetches `pumpe.lua`, Easy Deployment and the shared libraries; it never
  downloads the Bank or another role's program.
- The Bank's `/updates` is now a cache rather than a stockpile. It fetches a
  role program the first time a client actually installs that role, and drops
  the cache whenever a release needs the room, since everything in it can be
  re-fetched.
- The worst-case update peak falls from 813 KiB to **577 KiB**, leaving
  423 KiB for account data instead of 187 KiB.
- Local configuration survives an update. Each device merges the published
  config over its own, so currency, limits and the government key are kept
  rather than reset to the published placeholder.
- Devices whose ComputerCraft HTTP access is switched off fall back to the
  Bank's rednet depot automatically, so restricting HTTP costs the update
  speed but never strands a device.
- Removed the depot stamp, the depot verifier and the staging-space reclaim
  added in 6.1.0-6.2.1. The new architecture makes all three unnecessary;
  `bank_server.lua` is about 4 KiB smaller despite gaining on-demand fetching.
- Replaced the release builder's update-peak guard, which modelled the old
  whole-release staging, with one that measures the largest single role.

## 6.2.3

- Fixed the Urgent Contact ring never appearing, in or out of an app. The
  shared wait loop created its tick timer before the background timer, so a
  screen that ticks every half second returned and cancelled the three-second
  ring check before it could mature, then started a fresh full-length one. It
  never fired once. The interval is now measured from a global timestamp, the
  way the idle lock always was, and the check also runs before waiting so a
  fast screen cannot starve it.

## 6.2.2

Fixes a PUMPE that crashed at launch with `attempt to call a nil value (field 'setBackgroundTask')`.

- **Root cause.** Easy Deployment's Bank repair path replaced only
  `bank_server.lua` and `lib/util.lua`, then bumped `config.lua` to the
  manifest version. The Bank therefore advertised a release it was not fully
  running: its depot was refreshed to the new programs while `lib/ui.lua`
  stayed behind, and clients installed a new `pumpe.lua` beside the Bank's old
  library. `ui.setBackgroundTask`, added in 6.2.0 for Urgent Contact, was the
  first function that made the mismatch fatal.
- The repair now replaces every shared runtime file — `bank_server.lua`,
  `installer.lua`, and all four libraries — and only reports the new version
  once all of them verified. A partial repair leaves the installed version
  alone so the normal updater finishes the job.
- Raised Easy Deployment's per-file repair ceiling from 256 KiB to 1 MiB.
  `bank_server.lua` passed 256 KiB, which would have silently stopped it being
  repaired at all.
- PUMPE no longer depends on a matching `lib/ui.lua` to start. When the shared
  library is older than the app, Urgent Contact rings from the Home Screen
  instead of taking the whole phone down at launch.
- Added a check that Easy Deployment's repair set covers every file the Bank
  serves to clients, so a partial repair cannot be reintroduced.

## 6.2.1

Fixes an online update that could not physically install. **v6.2.0 should not be used.**

- The Bank stages a complete second copy of the release beside the installed
  one before it commits anything. At v6.2.0 that peaked at 1018 KiB against
  ComputerCraft's 1000 KiB per-computer limit, so the download always failed
  and rolled back. v6.1.0 was already marginal, leaving only 87 KiB for
  account data, which is why Banks with real data never took it either.
- The Bank now reclaims `/updates` before staging when a release will not
  otherwise fit. Every program there is part of the download and is put back
  from the committed files afterwards, so it is the safe space to take. The
  peak drops to 794 KiB, leaving 206 KiB for account data.
- Added a pre-flight disk check. When a release genuinely cannot fit, the
  dashboard now reads **NEEDS n KiB FREE** and the activity log says how much
  is needed, instead of a bare **DOWNLOAD FAILED**.
- A Bank whose depot is missing or half-cleared now boots and repairs itself
  from the manifest instead of stopping at the Easy Deployment repair screen.
  Previously only `border_controller.lua` and `ccg.lua` were tolerated.
- Replaced the release builder's installed-size tripwire, which measured the
  wrong thing entirely and passed v6.2.0, with a guard on the real update
  peak. Publishing now fails if an update would leave under 150 KiB for
  account data.

## 6.2.0

PUMPE starts becoming a phone rather than a bank client. Three new apps join
the home screen: **Friends**, **Messages**, and **Urgent Contact**.

### Friends

- Added the Friends app: your friend list, a name search that finds any Foxy
  Account, and requests you can accept or decline.
- Asking someone who already asked you accepts immediately instead of leaving
  two requests crossing in the middle.
- Repeating a request never queues a second one or raises a second alert.
- The home screen badges Friends with the number of requests waiting.

### Messages

- Added the Messages app: one chat per friend, plus group chats of up to eight
  people.
- Tapping a friend in Friends opens the chat with them directly; a direct chat
  is never duplicated no matter who starts it.
- Messages raise an alert only when a chat goes from read to unread, so a busy
  group cannot flood the 50-entry Alerts list.
- **Send money** and **Ask for money** work inside any chat. A request sits in
  the transcript until it is paid or declined, and paying it takes the PIN.
- The home screen badges Messages with the number of unread messages.

### Urgent Contact

- Added Urgent Contact: reach a friend right now and they get a full-screen
  ring with **Accept** and **Decline**, whatever app they had open.
- Accepting opens a live chat both sides poll several times a second, so a
  typed line appears on the other screen straight away.
- Money moves inside a call too, with the same PIN and fee rules.
- **Hang up** ends it from either side. **Save** is a vote: the transcript is
  written into your normal chat only when both people have pressed it.
- An unanswered call becomes a missed call for both sides after 30 seconds.
- Calls are deliberately never written to the database. A Bank restart drops a
  live call the way a dropped connection would, and only a transcript both
  people agreed to save is kept.

### Under the hood

- Added `ui.setBackgroundTask`, a hook the shared wait loop polls from every
  screen. Urgent Contact uses it to ring from anywhere, the same way the idle
  lock already takes over from anywhere.
- Gave PUMPE Pay, Messages, and Urgent Contact one shared transfer path on the
  Bank, so the 10% processing fee, the `$2,000` daily limit, and the
  transaction log can never drift apart between them.
- Fixed the PUMPE home screen asking the Bank for a fresh summary twice a
  second: it had a five-second throttle and an unconditional refresh right
  after it. The same bug was fixed in the Event Kiosk and Tax Controller in
  6.1.0.
- Capped a conversation at 60 stored messages. Conversations are the first
  PUMPE feature that grows the database on its own, and at roughly 260 bytes a
  message this keeps a busy account well inside a ComputerCraft computer.
- Raised the release builder's footprint tripwire to 640 KiB and documented
  what it is for. It guards against the v6.0 regression that kept a second
  copy of the release in `/updates`; the real ComputerCraft ceiling is
  1000 KiB, and the compact Bank now measures 512 KiB.
- Added `urgent_ring_poll_seconds` to `config.lua`.

## 6.1.0

### CCG Auto Mode

- Added **Auto Mode** to the CCG Bet Console. Pick one game or **Rotate All Games**, type a stop code twice, and the console opens lobbies, starts each round once every joined player is ready, shows the result, and opens the next lobby on its own — forever.
- Auto Mode only turns off when that same code is typed back in. A wrong code leaves it running.
- Auto Mode is saved to the console, so a reboot or an automatic update comes back straight into the arena instead of the game menu.
- Added `ccg_auto_start_seconds` and `ccg_auto_next_seconds` to `config.lua` for the ready countdown and the pause between rounds.

### A cleaner update cycle

- Replaced the checksums that were pinned into `bank_server.lua` for `border_controller.lua` and `ccg.lua`. Both are now published in the manifest's `extra_files` array, downloaded in the same verified, atomic commit as everything else, and no longer need the release builder to rewrite Lua source.
- Kept the manifest's `files` array byte-compatible with the v5.2.1 updater, which rejects entries it does not recognise; older Bank Servers ignore `extra_files` and keep updating.
- Added a `/updates/.depot` stamp. A Bank that arrives from an older release verifies every depot program against the published manifest once, repairs whatever does not match, and stamps the depot instead of relying on hard-coded checksums.
- Made the release builder stamp `INSTALLER_VERSION` from `config.lua`, and made Easy Deployment trust the downloaded file's own version rather than the manifest's. A release published with a stale stamp used to reinstall the same bytes and reboot forever.
- Added `tools/run_tests.sh` and a publishing guard that fails if `release_manifest.json` does not match the files in the repository.

### Faster, quieter clients

- Clients now ask the Bank Server for its version over the connection they already hold and only launch Easy Deployment when a newer release actually exists. Every dashboard tick used to load the 45 KiB installer, make a public HTTPS request, and pull a full deployment manifest.
- Added `client_update_check_seconds` (default 60) so client checks are separate from the Bank's five-second internet poll.
- Stopped Easy Deployment from contacting the internet when booting an installed client role or running an automatic check. Only the Bank Server and an unassigned installer use the public manifest now, which is what the README always claimed.
- Fixed the Event Kiosk and Tax Controller dashboards asking the Bank for fresh statistics twice a second; both now refresh every five seconds and immediately after anything changes. The Border Controller dashboard polls visitor counts every five seconds instead of every second.

### Interface work

- Rebuilt the Easy Deployment role picker: a two-column card grid on wide screens, a single column on pocket-sized ones, the installed role and version in the footer, and a **START ROLE** button on a computer that already has one.
- Made the installation screen repaint only the parts that change instead of clearing the display for every 6 KiB chunk, so the progress bar no longer flickers.
- Rebuilt the CCG console layout around a shared header, content band, and footer, so lobbies, results, and the game picker fit a 1x1 monitor and a large wall equally well.
- Touch screens now flash a pressed button the same way mouse clicks always did.
- Confirmation dialogs wrap their text everywhere. Kiosks used to truncate the description to one line, hiding what the customer was approving.
- Made `ui.message`, the touch keyboard, and the PIN pad lay themselves out from the available height, so nothing is pushed off a short screen; the keyboard's space bar no longer overlaps **CANCEL**.
- Right-aligned the header clock and gave the Bank Server dashboard a third statistic (live CCG games) plus an Easy Deployment status line.

## 6.0.3

- Removed the Bet app's six-character lobby-code restriction. Its touch and physical-keyboard input now accepts letters and numbers with no fixed length.
- Added a horizontally scrolling code field so long mixed codes remain editable on the PUMPE's native 26×20 screen, while the complete normalized code is sent to the Bank.
- Left CCG lobby generation and console behavior unchanged; this patch is isolated to PUMPE input and shared rendering support.

## 6.0.2

- Cut the installed Bank Server footprint roughly in half by keeping Bank runtime files in `/pumpe` and role-specific deployment programs in `/updates`, with no second copy of the Bank, installer, configuration, or shared libraries.
- Made Easy Deployment move a same-drive first-Bank release directly into its compact final layout instead of copying the whole bundle through another staging copy.
- Added automatic recovery for full v6.0/v6.0.1 Banks: the updated installer removes safe legacy depot duplicates, installs the compact Bank program, preserves local configuration, and launches it without requiring the old Bank to start first.
- Added automatic cleanup for the old installer cache, redundant `/pumpe/startup.lua`, duplicate depot runtime files, and abandoned online-update staging or backup folders.
- Kept Easy Deployment behavior unchanged for clients: Bank and Tax remain protected by `4040`, while every role still receives checksum-verified files from the Bank.

## 6.0.1

- Fixed Bank Server and Easy Deployment startup crashes reporting `Too long without yielding` while checksumming large release files.
- Split checksum work into small cooperative slices so first-Bank local installation, `/updates/` repair, deployment manifests, and automatic internet updates keep yielding to ComputerCraft's scheduler without changing checksum values.
- Added a focused Easy Deployment repair for an installed Bank's shared checksum utility, allowing affected v6.0.0 Banks to reach and complete the normal v6.0.1 automatic update.

## 6.0.0

- Added **ComputerCraftGaming (CCG) Bet Play** as a new Easy Deployment role for an Advanced Computer, Ender/wireless modem, and any-size Advanced Monitor.
- Added the PIN-gated **Bet** app to PUMPE. Players enter the big-screen lobby code, choose a unique display name, select their pick, reserve a wager, and wait for the console to start the game.
- Added the separate **Bet Wallet** app with PIN-confirmed transfers to and from the Foxy Account, available balance, held balance, release times, and CCG activity history.
- Added exact 24-in-game-hour payout holds. Winning funds survive Bank restarts and release once into Bet Wallet; they never become spendable early merely because the day number rolled over.
- Added Bank-authoritative **Heads or Tails** with `2×` payouts and **Race** with six colored cars, a server-random finish order, a responsive animated track, and `3×` payouts.
- Added interactive **Survivor** with a PUMPE touch joystick, push action/cooldown, server-simulated movement and collisions, a shrinking circular platform, live big-screen positions, and a `3×` last-player-standing payout.
- Added wager escrow, pre-start leave/expiry refunds, single-settlement guards, short-lived PIN-unlocked Bet sessions, server-side wager bounds, and automatic Survivor refunds if a Bank restart interrupts the live simulation.
- Added CCG console restart recovery. A restored console resumes its active lobby or animation instead of getting trapped behind an already-active game.
- Kept the public release manifest compatible with older v5 Bank updaters. The new `ccg.lua` is downloaded into `/updates/` as a checksum-pinned deferred file and is then served normally through Easy Deployment.
- Expanded the PUMPE Home Screen to four readable 26×20 app pages and added complete 1×1-monitor, PUMPE Bet flow, CCG settlement, hold timing, odds, Survivor control, refund, deployment, and syntax coverage.
- Deferred Home Play and its standalone Pocket Computer controller to a future release, as requested.

## 5.4.0

- Removed Proximity Pay completely from PUMPE, Service Kiosk, Bank routes, GPS state, and active configuration.
- Rebuilt Service Kiosk as a Square-style touch POS with a permanent left receipt, **Favorited**, **All Products**, and **Subscriptions** tabs, `F` favorite controls, side paging, top-corner `+` product creation, and `S` settings.
- Added one-time and subscription product types. Empty-cart **PAY** now opens the touch amount keypad and asks which purchase type to create.
- Moved subscription consent to PUMPE: subscription codes show the per-day price, always require the customer's PIN, settle the first charge immediately, and schedule later daily charges.
- Made Easy Deployment update its own one-file installer directly from the public HTTPS manifest before showing its menu or booting a role.
- Made first-Bank installation entirely local. Easy Deployment verifies the complete release beside `startup.lua`, installs it to `/pumpe`, writes an installer-based boot entry, creates the update depot, and launches the Bank without discovering a nonexistent server or stopping for a second restart.
- Removed `launcher.lua` from all v5.4 runtime and deployment paths. A tiny manifest-compatible copy remains only to migrate Bank Servers whose v5.3 `/startup.lua` still points at it.
- Split Border Controller into explicit **Enter Territory** and **Exit Territory** actions. Temporary visas allow one entry plus its matching exit and then lock permanently, including early exits.
- Added a permanent-document cooldown to reduce citizenship and Free Roam code sharing, while allowing overdue temporary visitors to record their exit.
- Protected Border Controller territory changes and shutdown with server-verified owner PIN entry.
- Added host coverage for local Bank bootstrap, installer self-update, direct Bank restart, POS bounds, compact customer display, product favorites, subscription settlement, border enter/exit, temporary-visa locking, and permanent-code cooldowns.

## 5.3.0

- Added persistent territories, citizenships, one-way Free Roam policies, temporary visa applications, customs review, travel codes, and visitor records to the Bank Server.
- Added 26×20-native **Customs** and **Visas** apps to PUMPE, including permanent citizenship documents, application history, departure days, citizen management, visa review, and Free Roam controls.
- Added the Easy Deployment **Border Controller** role for Advanced Computers, with authenticated territory binding, eight-character travel-code checks, permanent and temporary stay results, and an exact five-second back redstone gate signal.
- Added automatic owner citizenship whenever a territory is created and permanent entry through a citizenship code whenever the destination accepts its source territory for Free Roam.
- Made temporary visas single-stay documents. Their approved day count begins at first border entry, expired documents are rejected, and active travelers remain marked **Visiting**.
- Fixed Bank Server online restarts so a downloaded standalone installer can never take over `/startup.lua`; the server writes a role launcher, marks the update restart, skips Easy Deployment, and relaunches immediately.
- Kept the release manifest compatible with v5.2.1 while adding a checksum-verified Border Controller depot fetch and background retry.
- Added host coverage for the complete territory/visa/border state flow, the five-second gate pulse, the new launcher role, and the expanded PUMPE screen flow.

## 5.2.1

- Reflowed PUMPE for the Advanced Pocket Computer's exact 26×20 character display.
- Replaced the cramped three-column Home Screen with a two-column, three-page app grid so every app name remains legible.
- Added pocket-safe word wrapping to phone buttons, messages, confirmations, onboarding cards, and dense app content.
- Reworked PUMPE Pay and Proximity Pay cards so their labels, status, daily limit, and processing fee are visible without clipping.
- Gave Wallet, Activity, Events, event ticket selection, owned tickets, Notifications, and Subscriptions roomier paged layouts with multi-line content.
- Added a full PUMPE host flow that checks every major app at 26×20 and fails if text or controls leave the screen or a button label needs truncation.

## 5.2.0

- Rebuilt PUMPE around a phone-style, touch-first Home Screen with app icons, two app pages, a status bar, home indicator, rounded cards, animated transitions, and phone styling across every PUMPE app.
- Renamed the customer identity throughout onboarding and settings to **Foxy Account**.
- Added a full three-page onboarding and animated **Setting up your Foxy Account**, **Securing your details**, and **Preparing your PUMPE** stages backed by real device-save, account-refresh, and server-discovery work.
- Reorganized PUMPE Pay into Code Pay, Proximity Pay, and Send Money.
- Increased active Proximity Pay GPS broadcasts to every two seconds and added an animated broadcast/paused screen.
- Added server-quoted Send Money reviews showing the recipient amount, 10% processing fee, total debit, and remaining daily limit.
- Added authoritative Bank Server enforcement of a separate `$2,000` daily Send Money limit, fee rounding that cannot be bypassed with tiny transfers, processing-fee accounting, and legacy-account migration.
- Added a global inactivity Lock Screen after one minute, with time/day display and Bank Server PIN verification after two minutes.
- Added host tests for phone rendering, global inactivity callbacks, transfer fee rounding, and daily-limit boundaries.

## 5.1.0

- Added automatic HTTPS release checks to the Bank Server.
- Added strict online manifest validation, fixed-origin relative downloads, byte limits, checksums, staging, rollback, and automatic restart.
- Preserved the Bank Server's local configuration and government key across internet updates.
- Added quiet version checks before every installed client role launches and while its dashboard remains open; newer Bank Server releases install and reboot automatically.
- Added `release_manifest.json` and a deterministic manifest builder for publishing new versions.
- Added live online-update status to the Bank Server dashboard.

## 5.0.2

- Renamed the standalone Easy Deployment entry point to `startup.lua`, so a new computer opens the touch installer automatically after restart.
- Kept `/pumpe/installer.lua` as the manual way to reopen Easy Deployment after installation.
- Made the Bank Server re-sync its authoritative local scripts into `/updates/` at launch, including upgrades from an existing depot.
- Fixed static pages and confirmation dialogs closing after an unintended 0.5-second timer.
- Reworked the Service Kiosk customer display to fit a 1×1 Advanced Monitor more cleanly at text scale `0.5`.
- Improved compact receipt rows, totals, payment codes, expiry status, and transaction animations.

## 5.0.1

- Added a standalone, touch-first Easy Deployment installer.
- Added protected Bank Server and Tax Controller downloads using code `4040`, enforced by the Bank Server.
- Added first-run Bank Server creation and staging of the authoritative `/updates/` depot.
- Added chunked Rednet downloads, per-file checksums, staging, rollback, and safe startup creation.
- Added automatic downloading of every required shared `lib/` module.
- Added sanitized public client configuration so public role installs do not expose the government key.
- Fixed the shared PUMPE PIN pad crash on key maps without `keys.escape`; Sign In and Create Account now use guarded keyboard bindings.

## 5.0.0

- Added an optional adaptive 1×1 Advanced Monitor customer display to Service Kiosks.
- Added live product, quantity, total, merchant, payment-code, expiry, and payer states.
- Added cart, code-reveal, waiting, success, boot, wipe, and touch-feedback animations.
- Rebuilt all Advanced Computer screens as touch-first interfaces.
- Added an always-visible PUMPE in-game clock.
- Added live event countdowns to event listings, ticket purchase screens, owned tickets, organizer lists, and analytics.
- Added cancellable five-minute payment codes.
- Added Quick Item management, linked-company onboarding, and late company linking.
- Added PUMPE proximity approval prompts and GPS freshness handling.
- Added event inventory, ticket purchase, sales analytics, and one-use door validation.
- Added declaration periods, Smart Declare, follow-up tax-difference payments, company audits, and state deposits.
- Added atomic persistent storage and in-memory expiring authentication sessions.
- Added a safe role launcher and deployment documentation.
