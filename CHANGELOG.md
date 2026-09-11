# Changelog

## 9.3.0

The Bank is two computers, joined by a cable, and half the size.

**Why.** `bank_server.lua` had reached 287 KB. A ComputerCraft computer holds
1000 KiB and an update needs room for the installed copy and the staged one at
once, so the Bank was updating itself at 844 KiB of an 850 KiB ceiling: six
kilobytes from being a program that could no longer be updated over the air.
Pair Mode had existed since 9.0, but both halves ran this same file -- the
Vault carried 287 KB to use about 25 KB of it -- so having a partner saved the
Core nothing at all.

**What moved.** The Vault now runs its own program, `bank_vault.lua`. It holds
everything that is *about* an account without being its balance: friends and
conversations, Urgent Contact, territories, visas, border registers and the
scans people present to each other, events and tickets, and the records apps
keep. The Core keeps anything where being wrong means money is wrong --
balances, sessions, PINs, the ledger, tax, CCG escrow, pay codes, companies.

- **The Bank updates itself at 715 KiB instead of 844 KiB.** Room for data
  went from 156 KiB to 285 KiB.
- **Clients did not change.** A PUMPE asks the Bank, as it always has, and the
  Core answers or passes the question down the cable. Every action kept its
  name, its payload and its refusal codes.

**Pairing is wired, and there are no codes.**

- Put a wired modem on both Bank Servers and run cable between them. The
  pairing screen shuts the wireless modems, lists the Bank Servers answering
  on the cable, and pairs with the one you press. There is nothing to type: a
  code proves nothing the cable has not already proved.
- **Wireless pairing is refused.** The two halves now answer parts of the same
  request, so the link between them is on the path of a player's request
  rather than beside it. A wireless modem shares the air with every pocket
  computer on the server and stops existing when the chunk unloads.
- Whichever half holds the accounts stays the Core, so pairing can never
  strand a live ledger behind a half that does no banking. The computer that
  becomes the Vault fetches `bank_vault.lua` over the cable and restarts into
  it by itself.
- The dashboard shows the link, and its PAIR button pairs a replacement Vault
  if one is destroyed or a cable is cut.

**Three rules hold the split together.**

- **The Vault never touches a balance.** When something it owns has to move
  money -- a ticket bought, a note paid in a conversation -- it asks the Core,
  which does both sides of the move in one step under a move id. Asking twice
  with the same id returns the first answer rather than moving the money
  again, so a lost reply is harmless. A Vault that is broken, lying or
  switched off cannot invent money or lose any.
- **The Vault never decides who is asking.** The Core authenticates every
  request and passes down an identity. Session tokens and PINs stop at the
  Core and never travel.
- **A Bank with no Vault still banks.** Balances, transfers, pots, pay codes,
  the bet wallet and escrow all work with no Vault paired or with the cable
  cut; the Vault's own features say so plainly instead of failing oddly.

**The two hot paths never cross the cable.** `PUMPE_POLL` and
`ACCOUNT_SUMMARY` are called by every phone several times a second. Unread
counts, ringing calls and open scans are pushed up by the Vault as they
change, and the Core answers polls out of its own memory. A pushed entry
carries its own expiry, so a push that stops arriving cannot leave a phone
ringing forever.

**Easy Deployment moved back to the Core.** Through 9.2 the Vault held it, on
the reasoning that a Vault was idle and the Core was not. Both halves of that
died here: the Vault now answers player requests, and -- worse -- a Vault that
holds the installer is a Vault you cannot reinstall once it breaks.

**Upgrading.** A Bank arriving from 9.2 still holds every conversation,
territory, visa, event and app record in its own state file. Pairing a Vault
hands each table over and clears it, one at a time, acknowledged before the
Core lets go, so an interrupted handover leaves the data on the Core rather
than nowhere. It runs on every boot and is silent once there is nothing left
to move.

- `host_vault_split_test` checks that both halves agree on which routes the
  Vault answers, that no route exists on both, that the Core keeps none of
  what it handed over, that a PIN never crosses the cable and is checked
  before anything is forwarded, that a replayed move id moves money once, and
  that the poll asks the Vault nothing.
- `host_vault_migration_test` checks the handover, including that an
  interrupted one keeps the data and that the numbering counters travel --
  without them the Vault would start at one and write a second
  `CHAT00000001` over somebody's conversation.
- `tests/bank_pair_harness.lua` stands up both real programs and wires their
  two ends of the cable together. Every test of a moved feature runs through
  it, because a stub Vault is always more forgiving than the real one, and
  that is exactly how the "app has no id" bug reached a player.

## 9.2.3

The 3rd Party Bank Server and the CCG Server never updated themselves.

- **Neither called `net.autoUpdate`.** Every other role on the network keeps
  itself current; these two stayed on whatever release installed them. A 3rd
  Party Bank Server set up in 9.0 was still running the 9.0 file three
  releases later, and nothing on the network could move it. Both update
  themselves now, like everything else.
- **The builder stamped `PROGRAM_VERSION` from a list kept by hand**, and no
  program written after 9.0 was ever added to it, so `bank_app_server.lua`
  shipped for three releases calling itself 9.0.0 even where the bytes were
  current. The list is derived from what is actually published now.
- Both servers show the version they are running on their own dashboard. It
  was invisible on both, which is how one three releases behind looked fine.
- `host_program_version_test` checks that every published program carries the
  release it belongs to, and that every installable role calls
  `net.autoUpdate`. It reads the manifest and the installer rather than a
  list of its own, and fails against the 9.2.2 files.

## 9.2.2

Easy Deployment can no longer strand a computer on a role it does not know.

- It **updates itself on every boot**, not only the Bank's. A computer whose
  role was added to a release after its own copy was installed had no other
  way to learn about that role: the lookup failed, and the update that would
  have fixed it never ran because it only ran for the Bank.
- A boot marker naming an unknown role now **opens the role picker** instead
  of printing UNKNOWN ROLE and stopping. A computer always has somewhere to
  go.
- Together these are why a 3rd Party Bank Server installed before 9.2.1
  stayed broken after the Bank updated: the fix reached the network, but not
  the one computer that needed it. It heals itself now.

### Recovering a computer that is already stuck

A 3rd Party Bank Server sitting on the UNKNOWN ROLE screen predates this
fix, so it cannot fetch it. On that computer:

```
wget https://raw.githubusercontent.com/totallyrat/computercraftbank/main/startup.lua /pumpe/installer.lua
reboot
```

## 9.2.1

A 3rd Party Bank Server would not start after it was installed.

- Installing a role writes a boot marker naming it, and on the next reboot
  the installer looks that name up. `tpbank` was built as a role table
  inline at the point of install and never added to the role list, so the
  lookup failed and the computer refused to start with **UNKNOWN ROLE
  tpbank**.
- The same gap stopped it auto-updating: that path looks the name up too,
  and silently did nothing when it came back nil.
- It is a real, hidden role now -- hidden because it is reached through the
  BANK SERVER menu rather than the role list, not because it is any less of
  a role. There is one definition of it rather than two.
- `host_installer_roles_test` now checks that every role the installer can
  install is one it can find again, reading the installer's own tables so a
  role added in future is covered without anybody remembering to. It fails
  against the 9.2.0 file.

## 9.2.0

Apps can sell things, and there is a second third-party bank worth banking
with.

### In-app purchases

- `api.purchase{ id, name, amount }` sells something; add `period = "day"`
  and it is a subscription charged every in-game day until it is cancelled.
- The money goes to the account that published the app -- the company owner
  behind its developer account -- less **30% to the government**, taken by
  the Bank rather than trusted to the app or the seller.
- **The app never sees money, and is never told a purchase went through by
  anything but the Bank.** It reads `api.entitlements()`, which is the
  Bank's own record. An app cannot decide for itself that somebody has paid,
  and cannot see or claim another app's purchases.
- The phone prices it, shows the tax and who is being paid, and takes the
  PIN. A purchase is spending, so it is refused for the same reasons any
  other payment is -- a tax demand outstanding, or the money moved to
  another bank.
- A subscription nobody can pay for on a given day **stops** rather than
  running up a debt. Cancel one under Settings -> App Settings.
- Publishing an app is when the Bank is told who owns it, because it is the
  only moment anybody knows both the app id and the developer.

### Yap Social, and Yap Boost

- Yap is **Yap Social** now, and the first app with something to sell.
- **Yap Boost** puts your yaps above everything else in everybody's feed.
  Ten for one yap, or twenty a day for all of them.
- A boost bought on one yap lifts **that yap and nothing else**, and only
  your own -- otherwise anybody could push anybody's post to the top for ten
  dollars.
- A cancelled subscription stops boosting, because the app reads whether the
  entitlement is active rather than whether it exists.

### Revolution, and banks with terms of their own

- A bank app declares its own terms in its header, and its server enforces
  them:

  ```lua
  -- PUMPE BANK APP: Revolution
  -- PUMPE BANK CLEARING: 1
  -- PUMPE BANK FEE: 0
  ```

- **Revolution** is the first: no fee on anything, and one in-game hour
  before money is spendable. Slower than Foxy on purpose, and free where
  Foxy charges ten per cent.
- **Proximity pay** is what it is built around. Open a charge, hold your
  PUMPE out, and whoever is standing next to you pays it from theirs. No
  kiosk, no fee.
- Money that has not cleared cannot be spent or moved on, and a bank that
  declares no terms behaves exactly as BuckApp always has: no wait, no fee.
- Apps can ask the phone where it is with `api.position()`, which is what
  proximity pay needs. A network without GPS anchors gets nil rather than a
  guess.

## 9.1.0

ComputerCraftGaming moved to its own computer, which is what gives the Bank
room to grow again.

### CCG runs on a CCG Server now

- Lobbies, games, outcomes and the Survivor simulation all live in
  `ccg_server.lua`. Install it from Easy Deployment as **CCG SERVER**.
- It was a tenth of `bank_server.lua`, a file that had reached **849 KiB of
  the 850 KiB** a ComputerCraft computer can update itself through. The Bank
  is now at **823 KiB**, and any Bank change is possible again.
- The CCG console and the PUMPE's betting screens talk to the new server.
  The **Bet Wallet stays on the Bank**, because it is money.

### The Bank still owns every penny

The split is drawn so that the worst a rogue, broken or switched-off CCG
Server can do is freeze wagers and choose the wrong winner:

- A wager goes into **escrow on the Bank**. The CCG Server can put money in,
  and can say who won, and that is all it can do.
- **It never names an amount.** A settle carries only the winners; the Bank
  multiplies the stake it is already holding by its own copy of the game's
  multiplier. A server asking for a payout of its own choosing is ignored.
- A CCG Server proves itself once with the **operator code** -- the same code
  that installs a Bank -- before the Bank will settle anything for it.
- **Escrow nobody comes back for is refunded by the Bank**, on its own, after
  two hours. Switching the CCG Server off mid-round can no longer strand
  anybody's money.
- A settle the Bank does not answer leaves the lobby open and is retried,
  rather than being marked done while the money is still in escrow.

### Updating into it

- A wager sitting in a lobby when the Bank updates is **given back once**, on
  the first load that finds the old tables. Lobbies were a Bank record before
  9.1 and they are gone.
- Bet Wallets, holds and activity are untouched.

### Also

- The installer test picked roles by tapping a coordinate, so adding the CCG
  Server silently moved the target and it started tapping a different role.
  It picks by the on-screen number now, which does not move.
- The two console tests handed back the same fake server whatever they were
  asked for, so they would have passed with the console still pointed at the
  Bank. They check now.

## 9.0.1

A Bank in Pair Mode would not start.

- Both halves of a pair are one bank, so they share one bank code -- and the
  ledger hostname was claimed outside the Core/Vault branch, so **both**
  claimed `LEDGER_0001`. Whichever started second died with **"Hostname in
  use"**, which in practice was the server that typed the other's code.
- The name is now claimed only by the half that runs `ledgerLoop`. Even
  without the clash a Vault holding it would have been a black hole: a name
  answered by nobody, so transfers into the bank would have gone nowhere.
- The reason this shipped: `host_pair_mode_test` loads both Banks in test
  mode, which returns before any hosting happens, and `host_bank_bootstrap_test`
  stubbed `rednet.host` as a no-op that could never fail. Nothing exercised
  the startup block against ComputerCraft's actual rule. `host_pair_hosting_test`
  now boots both halves on one network with a rednet that throws
  "Hostname in use" the way the real one does, and it fails against the
  9.0.0 file.

## 9.0.0

The Bank can run on two computers, banks other than Foxy can exist, and money
moves between them.

### Pair Mode: two computers, one bank

- A Bank Server asks **Solo** or **Pair** the first time it starts. A Bank
  that has already been answered comes straight up the way it was left.
- In Pair Mode both servers show a six-digit code and both can type the
  other's. Whichever way round you do it, they pair.
- **The split is not down the middle, on purpose.** Everyday banking is a hot
  path where a second radio hop would be felt on every balance check, so the
  Core keeps all of it. What moves to the Vault is the heavy, cold work: the
  update depot and the app record store. That is what was actually crowding
  the Bank's disk and making banking queue behind file transfers.
- Which half is which is decided by **where the data already is**: the server
  holding the accounts stays the Core, whoever typed. A fresh computer can
  never demote a live ledger to a Vault.
- Clients never learn any of this. The depot answers from a different
  computer, which rednet already resolves by name, and app records reach the
  Vault through the Core.
- A Vault only answers the Core it is paired to.

### Banks that are not Foxy

- **Bank Servers are no longer locked.** Pressing one asks which kind it is.
  Foxy's still wants `4040`; a 3rd Party Bank Server does not, because there
  is nothing behind it that could reach the Foxy ledger.
- A 3rd Party Bank Server asks the App Server which **Bank Apps** exist and
  hosts the one you choose. An app declares itself a bank in its own first
  lines -- `-- PUMPE BANK APP: BuckApp` -- and that is the whole
  registration.
- Third-party banks have **their own logins**. A Foxy Account is not an
  account there, and a Foxy session is refused. They also mint no money: an
  account opens empty and everything in it arrived from somewhere.

### The Account ID, and Bank Transfer

- Every account at every bank now has a **sixteen-digit Account ID**, the
  first four digits naming the bank that holds it. It is the one thing every
  bank on the network agrees on, and it is enough on its own to find where
  money lives.
- **Bank Transfer** moves everything you have to any Account ID. Your bank
  account here closes behind it, so the Bank tab will not open, and the same
  feature from the other bank brings it home -- money arriving is what
  reopens an account.
- A transfer is done in three steps, each safe to repeat: the money leaves
  the balance into a pending record, the far bank is asked to credit it under
  an id it will only honour once, and only an acknowledged credit clears the
  record.
- **An unanswered transfer is never given back on a guess.** A refusal
  carries a code, so nothing was applied and the money returns. Silence
  carries none, so the money stays parked and is settled later by asking the
  far bank whether it ever saw the id. Refunding on silence is how a transfer
  creates money out of nothing, and an earlier draft of this code did exactly
  that until the test caught it.
- Money that lands in a closed account follows it. About twenty places in the
  Bank credit an account, and sealing every one of them is the kind of change
  that misses one, so anything that arrives is forwarded instead.

### BuckApp is a bank now

- BuckApp is **no longer preinstalled**. It left the home screen to become a
  bank of its own, installable from the App Browser, running on the new bank
  infrastructure.
- What is built into the phone in its place is simply your Foxy bank account,
  under the name **Bank**. It stays built in because paying somebody, the Bet
  Wallet and your activity live nowhere else, and a phone that had to
  download an app before it could pay anyone would be a worse phone.

### The new Settings app

- Settings is a paged list now. 9.0 added enough to it that the old fixed
  layout stopped fitting a 20-row pocket screen.
- **Network.** Turn the modem off and the PUMPE leaves the bank network:
  everything that needs the Bank stops, and what is already on the phone
  still opens. The switch is on the client itself, so signing in and the lock
  screen are covered too rather than only the screens that went through one
  wrapper.
- **Storage.** What is free, and what the phone is holding, app by app.
- **Updates.** Turn automatic updates off and this PUMPE stays on the version
  it has. Kept on the device rather than in `config.lua`, which an update
  rewrites.

### Also

- `lib/util.lua` gained the Account ID format and the apply-once rule,
  shared by Foxy and every third-party bank. It went there rather than into a
  library of its own because a brand new `lib/` file would be downloaded by
  nobody: an updater fetches the shared files it was built knowing about, so
  a Bank updating into 9.0 would have landed without it and failed to load.

## 8.5.0

Three APIs any app can use, the App Settings screen that governs them, and
Yap Chat, which uses all three. Also the fix for Yap not being able to post.

### Fixed: an app could not write anything

- Every app request reached the Bank without the id the app was installed
  under, so posting, liking, replying and deleting all came back **"That app
  has no id"**. Yap shipped in 8.4.0 unable to post.
- `api.request` now stamps the app id onto every call. It is copied onto a
  fresh payload rather than into the app's own table, so an app still cannot
  name itself, or reach another app's data by claiming its id.
- The test that missed this was the cause: its fake Bank accepted a request
  the real Bank rejects. It now enforces the id, and fails against the 8.4.0
  code.

### The Pin API

- `api.pin("Unlock Yap Chat")` puts the PUMPE's own PIN pad up and returns
  true or false. The app never sees the PIN, so it cannot store or replay
  one.
- Five wrong guesses shut the API for a couple of minutes. The app holding it
  is the thing being defended against, not the person typing.

### The Notification API

- `api.notifications.ask()` asks once and remembers the answer — including a
  refusal, so an app cannot put the question up again every time it starts.
- `api.notifications.send{ account_id =, title =, body =, style = }` sends a
  banner, or a fullscreen alert where that is allowed. Across accounts it
  only works between friends, with a daily budget per app per sender.
- Every app alert says which app it came from, on the banner and in the
  notification centre, so one is never mistaken for the Bank's own.

### App Settings

- **Settings -> App Settings** lists every app that has ever asked for a
  permission, whatever the answer was, so a "no" can become a "yes" later.
- **Fullscreen notifications are turned on here and nowhere else.** An app
  cannot ask for them; `style = "fullscreen"` arrives as a banner until the
  owner switches it on. Blocking notifications takes fullscreen with it, and
  allowing them again does not quietly bring it back.

### The Urgent Contact API

- `api.call{ account_id =, name = }` raises the same fullscreen ring the
  PUMPE raises for Urgent Contact.
- The ring says which app is calling and who is. Both labels come from the
  install and from the Bank rather than from the app, so an app cannot pass
  its call off as the PUMPE's own.
- The PUMPE's own Urgent Contact and an app's call now run the same code
  rather than two copies that drift.

### Private and disappearing records

- A record written with an `audience` is visible to its author and the people
  named in it, and to nobody else — not by listing, and not by asking for it
  by id.
- A record written with `expire_after_days` goes that many days after
  somebody **reads** it, on every phone at once. `APP_DATA_READ` is what
  starts that clock; reading your own record back does not count, or a
  message would expire the moment it was sent. Nobody opened it, it is still
  there tomorrow.

### Yap Chat

- Private messages between Foxy friends, and the app that uses all three new
  APIs.
- Notifications are asked for before the app is told a single thing about the
  account.
- The whole app sits behind your PIN, so a phone left on a desk is not an
  open inbox.
- A message you have read is gone a day later, on both phones.
- A call button in every conversation.
- Like Yap, it is **not** published: it lives in `apps/` for you to install
  and publish from your own company in the game.

### Also

- A new host test refuses a local that is used above its own declaration.
  That mistake compiles, passes every other test, and only fails in the
  world as "attempt to call a nil value" — it had already shipped twice.
  It caught a third instance in this release before it left the repository.

## 8.4.0

FoxyLogin, a store apps can keep things in, and the first real app written
against both.

### FoxyLogin

- One line is the whole integration:

  ```lua
  local me = api.login({ name = "Yap", scopes = { "friends" } })
  if not me then return end
  ```

- The phone slides up a Foxy sheet naming the app and listing exactly what it
  will see, and waits for a tap. Approve once and it never asks again — the
  second time is straight through, the way a quick sign-in should be.
- The app is handed a profile with **only** the fields it asked for. Scopes
  are `name` (always), `number`, `friends` and `balance`; anything else is
  dropped rather than honoured.
- The app id comes from the install, not from the app's own code, so nothing
  can ask for another app's grant.
- **Settings -> Connected Apps** lists what you have signed into and what each
  one can see, and takes it back.

### A store for apps

- A signed-in app gets a small store on the Bank: `APP_DATA_PUT`,
  `APP_DATA_LIST`, `APP_DATA_DELETE` and `APP_DATA_REACT`. The Bank has no
  idea what any of it means.
- Records are owned by whoever wrote them. Reactions are the one thing anybody
  can add to somebody else's record, which is enough to build likes on.
- Collections are per app, so one app can never read another's.
- Records are small on purpose and the oldest fall off the end. `config.lua`
  holds the limits. This is a notice board, not a database.

### apps/

- A new folder in the repository where apps are written. Nothing in it is part
  of a release: the manifest does not carry it and the App Server does not
  ship it. Copy a file onto a kiosk's `/apps/`, publish it from Dev Mode, and
  it appears in every App Browser.
- `apps/README.md` documents the whole app contract: what `api` gives you,
  FoxyLogin, the data store, and the 26x20 screen every app has to fit.

### Yap

- The first real app. A text social network: post, like, reply.
- The feed puts **your friends first**, then everybody else, each newest
  first. A friend's post carries a `*` and their name in green.
- Scrolling is two tall buttons down the **right-hand edge**, so the posts
  never run under them. `+` at the bottom writes one.
- Tap a post for the whole thing, its replies, and Like. Your own posts can be
  deleted.
- It is deliberately **not published**: `apps/yap.lua` is yours to install and
  publish from your own company.

## 8.3.0

Foxy, an App Browser, an App Server, and a way for anyone to write apps for
the PUMPE. BuckApp keeps working, with a notice on it.

### Foxy

- A new app that puts the Foxy Account and the bank behind it in one place.
  It is **not** built into the phone: you get it from the App Browser, so it
  can move faster than the PUMPE underneath it.
- **Bank** opens on your card, drawn on screen with your name across the front
  and a number that reads like a card rather than an account id, with a light
  band that sweeps across it as it lands. Your balance sits under it.
- **Sub-accounts.** Under the balance are your accounts, and `+ New account`
  makes another — Savings, Rent, Holiday, whatever you name it. Open one to
  move money to any of your others; it never leaves your account, and closing
  one hands its money straight back.
- **Foxy Cash**, under the accounts. Instant, a **2% fee**, and no daily
  ceiling — but only to your friends. Add someone in Friends first. The fee is
  the sender's; your friend gets the whole amount.
- **Account** changes your name and your PIN, with more to come.
- Savings are not a hiding place: while a tax demand is outstanding you cannot
  move money out of your main balance, only back into it.

### BuckApp

- Still works, and will through the next update. It now carries a banner
  saying it is closing down, and a **Move to Foxy** button that opens the App
  Browser.

### The App Browser and the App Server

- **Apps** is a new built-in app: a catalogue of optional apps that are not
  part of the base phone. Installing one shows a filling bar and a tick that
  draws itself; it then sits on your Home Screen like any other app.
- Every byte comes from a **new App Server role**, never from the Bank. That
  is the whole point of the machine: a busy download cannot slow banking down.
  The Bank is asked exactly one question, once, when something is published.
- A download is checked against the size and checksum the store advertised. A
  damaged one is thrown away rather than run.
- An app that crashes is caught: it says so and hands you back the phone.
- The App Server ships with Foxy, so a fresh world has something to download
  before anybody has written anything.

### Dev Mode

- **Dev Mode** in the Service Kiosk's settings. Entering it registers a
  developer account against the kiosk's company owner and creates an `/apps/`
  folder on that computer.
- Drop a `.lua` file in there, open Dev Mode again, give it a name and a
  description, and launch it. It appears in every PUMPE's App Browser.
- Republishing the same file updates the app rather than making a second copy,
  and it keeps its place and its download count.
- An app belongs to whoever published it. Nobody else can overwrite or delete
  it, and a developer can delete their own from the App Browser.
- An app is one file returning one function. It is handed an `api` table and
  nothing else: it can draw and it can make requests as the signed-in account,
  but it never sees the session token or the device file.

### Fixed on the way

- Installing an app deleted the file it had just downloaded, so nothing was
  ever really installed.
- The Easy Deployment role list dropped whatever ran off the bottom of a
  narrow screen. With the App Server added that was the App Server itself; the
  list pages now.
- The Service Kiosk's settings grid ran into its own footer once it had eight
  entries.

## 8.2.0

Proximity everywhere, a portable kiosk, and a government that can write to
one person instead of shouting at everyone.

### Proximity Ticket Scanning

- **PROXIMITY SCAN** on the Event Kiosk. Turn it on at the door and the Bank
  asks whoever is nearest with a ticket for *that event* on their screen. They
  accept on their own PUMPE, the name appears on the organiser's screen, and
  the ticket is stamped used. Nobody reads an eight character code out loud.
- A PUMPE showing a ticket now tells the Bank what it is holding up. That
  claim lapses on its own after twenty seconds, so closing the ticket stops
  you being scannable.
- A used ticket stops being held up, so it cannot be scanned twice.

### Proximity Visa

- **PROXIMITY VISA** on the Border Controller. Left on, the gate keeps asking
  whoever is nearest with a travel document on screen.
- Accepting runs the ordinary border check, so entry rules, cooldowns, visits
  and Free Roam behave exactly as typing the code in by hand. Already inside
  means the crossing is an exit; there are no Enter/Exit buttons at a gate.
- The gate pulses redstone for **two seconds**, and the PUMPE popup says so:
  *stand close before you accept*.

### Portable Mode for the Service Kiosk

- A new toggle in POS Settings. A kiosk carried to the customer has no second
  screen to show them, so the sale finds the customer **before** anything is
  rung up: **FIND** asks the nearest PUMPE, they say "That is me", their name
  appears on the receipt, and the operator adds the items.
- Pressing PAY sends the finished basket to that same PUMPE, itemised, and
  they confirm a second time with their PIN. Two confirmations replace the
  customer display.
- A basket already rung up never changes hands. Backing out ends the sale and
  kills its pay code rather than offering somebody else's shopping to a
  stranger standing closer.

### Government messages

- The Admin Terminal can now aim an announcement at **one account** — banner,
  full screen, or a **text message** — as well as at everyone.
- A text message opens a thread between the state and that account. They can
  answer, the terminal can answer back, and **MESSAGES** on the dashboard
  lists every thread with the ones waiting on a reply highlighted.
- Only the government moves money in that thread: it can ask for money or
  send money, and the holder can settle what is asked. They cannot bill the
  state or send it money. Good for a speeding ticket.
- Money paid to a government demand goes to tax revenue, not to another
  account.

### Payments stop while a tax demand is outstanding

- A tax demand handed out as a fine can no longer be dodged by spending the
  balance first. Code payments, sending money, ticket purchases, visa fees,
  the Bet Wallet and Bet all refuse with **Settle your tax demand first**.
- Being paid still works, and so does settling the demand. Paying the
  government inside a government thread is never blocked either.

### Fixed on the way

- CLEAR and NEARBY were drawn at the same spot on the POS receipt, so CLEAR
  could never be tapped. They share the row properly now.
- The Admin Terminal's dashboard ran its last row of buttons off the bottom of
  a 51x19 Advanced Computer once the list passed ten entries. Three columns.

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
