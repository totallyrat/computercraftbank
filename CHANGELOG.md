# Changelog

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
