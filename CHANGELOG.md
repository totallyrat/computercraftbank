# Changelog

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
