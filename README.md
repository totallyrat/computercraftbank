# PUMPE Ecosystem

A working, touch-first digital economy and gaming network for ComputerCraft: Tweaked. It includes personal banking, ComputerCraftGaming (CCG) Bet Play, a Square-style merchant POS, an optional customer-facing order display, subscriptions, event tickets, customs, citizenships, visas, border gates, taxes, and a persistent central bank.

## What is included

| Program | Hardware | Purpose |
| --- | --- | --- |
| `bank_server.lua` | Advanced Computer + wireless/Ender modem | Persistent database, request API, banking, CCG settlement/physics, customs, subscriptions, events, tax, live dashboard |
| `pumpe.lua` | Advanced Pocket Computer + wireless modem | Personal phone, payments, Bet and Bet Wallet apps, Customs and Visas, events, tickets, tax, subscriptions |
| `ccg.lua` | Advanced Computer + Ender modem + Advanced Monitor | ComputerCraftGaming Bet Play lobbies, game animations, Race track, and Survivor arena |
| `service_kiosk.lua` | Advanced Computer + wireless/Ender modem | Square-style touch POS, favorites, products, receipts, payment codes, withdrawals, subscriptions |
| `event_kiosk.lua` | Advanced Computer + wireless/Ender modem | Event creation, ticket inventory, animated analytics, door admission |
| `admin_terminal.lua` | Advanced Computer + wireless/Ender modem | Government-only tax controls, account approval, balances, bans, tax demands, announcements |
| `border_controller.lua` | Advanced Computer + wireless/Ender modem | Checks travel codes, records visitors, and opens a redstone gate |
| `gps_anchor.lua` | Computer + wireless/Ender modem | Serves its own coordinates so every device can locate itself |
| `app_server.lua` | Advanced Computer + wireless/Ender modem | Hosts optional PUMPE apps and serves every download, so the Bank never carries one |
| `internet_server.lua` | Advanced Computer + wireless/Ender modem | Holds and serves every website on the network. The Bank Vault keeps the names |
| `delivery_terminal.lua` | Advanced Computer or Advanced Pocket Computer + wireless/Ender modem; chests on networking cable for a pickup point | A company's delivery board: every Shop order, its stages, and DONE. Becomes a self-service pickup point that can sell on the spot |
| `shop.lua` | Downloaded to a PUMPE from the App Browser | Online stores: a basket, home delivery or pickup, Foxy or another bank, live delivery tracking, cancelling and returns |
| `foxmail.lua` | Installed on every PUMPE at sign-in | Email: an address at foxy.com for everybody, company domains, mail from kiosks and apps |
| `company.lua` | Downloaded to a PUMPE from the App Browser | Start and run companies from the phone: products, the online store, what pickup points sell, and Delivery Mode |
| `foxy.lua` | Downloaded to a PUMPE from the App Browser | The Foxy Account and the bank behind it: card, sub-accounts, Foxy Cash |
| `apps/` | Written here, published from inside the game | Apps that are not part of a release: `yap.lua`, a text social network, and `yapchat.lua`, private messages |
| `lib/` | Copied with every program | Shared UI, clock, storage, and networking code |

All screens support touch. Physical keyboard input also works.

## PUMPE phone experience

PUMPE now behaves like a small phone rather than a list of bank buttons:

- Start-up spells **PUMPE** one letter at a time, then holds **Small yet Mighty** for two seconds. Installing a release is the opposite: since 10.0 the wordmark sits over a bar that fills for twenty seconds whether or not it needs to, because a release lands in about two and a phone that goes dark and comes back subtly different reads as a glitch rather than an update.
- Onboarding asks one question first — a new account, or one you already have — then username, then PIN, and ends in a six-step guide to the phone. **How PUMPE Works** in Settings re-opens the same guide at any time.
- Account setup performs the real device save, account refresh, and Bank Server discovery while showing **Setting up your Foxy Account** and **Preparing your PUMPE**.
- The Home Screen lays out small icons in a grid with the app name underneath, the way a phone does, with phone-style status, app transitions, navigation and touch feedback. Every app fits on one page, with room to grow.
- Every PUMPE screen is laid out against the Advanced Pocket Computer's native 26×20 character canvas. Buttons, messages, confirmations, activity, events, tickets, notifications, and subscriptions wrap onto readable lines instead of hiding labels beyond the edge.
- The **dock** sits under every app page: search first, then up to three favourites. An empty slot opens the picker, and so does **Edit Your Dock** in Settings.
- Unread counts appear as a badge in an icon's corner.
- **Foxy** is the bank. Since 9.4 the balance, your accounts, Foxy Cash, the Bet Wallet, Activity, cashing out and the Account ID all live in its bank section; there is no Bank app on the Home Screen. (It was BuckApp until 9.0, then a built-in Bank tab until 9.4.)
- **Friends** holds Messages, Friends and Urgent Contact, badged with whatever is waiting.
- **Tickets** holds events and your own tickets; **Customs** holds visas and territories.
- Opening a ticket or a travel document tells the Bank what you are holding up, which is what lets a door or a border find you. It lapses twenty seconds after you close the screen.
- The **notification centre** is the last Home Screen page: one row per alert with a coloured bar for its kind, its title, the time it arrived, and the first line of the message. Read alerts fade, a tap opens one in full, and the list scrolls. A `!` in the page dots and a banner across the top of whatever app is open announce new ones.
- **Bet** and **Bet Wallet** are separate apps. Bet requires the Foxy Account PIN every time it opens; Bet Wallet shows available and held game funds and requires the PIN for transfers.
- After one minute without touch or keyboard activity, PUMPE opens its Lock Screen with the current in-game time and day. Opening it before two minutes needs no PIN; after two minutes, the Foxy Account PIN is verified by the Bank Server.
- **Turning the modem off leaves you signed in.** Settings → Network takes the phone off the network; since 9.5 that is all it does. The Home Screen, Settings and everything already downloaded keep working, the header reads **Offline** where the balance goes, and anything needing a server says so instead of hanging. A phone that starts up with the modem off opens the same way, under the name it last signed in as — a label, not a session, and the first thing it can do back on the network is sign in properly. Off the network the Lock Screen opens on a tap, because the PIN is checked by the Bank and there is no Bank to check it.

## Search, App Actions and QuickActions

Since 10.0 Simple, everything the phone can do is a **labelled action**. Opening an app is one; so is Foxy Cash, My Tickets or Network.

An app declares its own in its first lines, the same way a bank app declares itself:

```lua
-- PUMPE APP ACTION: cash | Foxy Cash | Send money to a friend
```

The phone reads that off the file rather than asking the app at runtime, because search has to know what an app does without running it. An app opened at an action receives it from `api.action()`, goes straight there, and closes when it is done.

- **Search** has a slim bar of its own just above the dock, on every page (since 11.0 — it used to take a dock slot, so the dock is four favourites now). It finds apps, app actions and every setting, ranking a name that starts with what you typed above one that merely contains it. **Suggestions appear under the field as you type** — "fox" already offers Foxy, Foxy Cash and FoxMail — and tapping one goes straight there; DONE shows every match. What is not installed is one tap further on, in the App Browser with the same words already filled in.
- **Settings** and the **App Browser** have their own search bars over the same lists.
- **QuickActions** strings app actions together. Add steps, add a **Repeat** to multiply the step above it, then run it yourself or have it run every day at an hour you pick. A QuickAction can sit on the Home Screen as an icon that does something rather than opening something.
- **Reminders** arrive as a banner or as a full screen alert, set in in-game hours from now.

Reminders and QuickActions are kept on the phone and fired by the Home Screen's own tick. A PUMPE that is switched off, or sitting on its lock screen, is not reminding anybody — it catches up when the Home Screen is next open.

## How apps are laid out, since 11.0

**Tabs along the bottom are the standard.** An app with more than one part puts its parts in a row on the bottom line, the way Shop did first, and **the mark at the top left (`<PUMPE`) goes home** from any of them.

| App | Tabs |
| --- | --- |
| Foxy | Bank, Account |
| FoxMail | Inbox, Sent, Write, Me |
| Shop | Stores, Delivery, Places |
| Friends | Chats (with the unread count), Friends, Urgent |
| Tickets | Events, My tickets |
| Customs | Visas, Territories |
| Revolution | Take, Pay, Account |
| BuckApp | Money, Account |
| Website Crafter | Sites, New |

An app with one screen — Internet, Tax, Subs, Reminders, QuickActions, Settings — keeps its **< Home** button rather than tabs it has nothing to put in. An app opened at an action from search opens on that tab.

For app authors, `ui.tabBar(scene, target, tabs, active, color)` draws the bar (each tab as wide as its label needs, the rest shared out) and `ui.runTabs{ list = , pages = , start = , once = }` runs an app made of tab pages; a tab listed in `once` is a thing to do — write a message, place a call — rather than a place to be.

`ui.input` has two more keyboards: `mode = "email"` (with `@`, `.` and `_`) and `mode = "text"` (with `' , . ?`), both typing lower case from the touch keys. And `suggest = function(value) return { { label =, detail = }, ... } end` lists suggestions under the field as you type; tapping one returns the text *and* the item.

## FoxMail

New in 11.0, and installed on every PUMPE at sign-in, like Foxy.

- **Your address.** Everybody can claim one at `foxy.com` — 2 to 16 letters, numbers, dots, dashes or underscores. Anybody with an address can write to anybody else.
- **Company email.** A company's owner registers a domain for it on FoxMail's **Me** tab — `revolution.com`, say — and up to five addresses on it (`hello@`, `support@`...). The owner reads and sends as them beside their own address: the Me tab switches between them. `foxy.com` is the Bank's own and cannot be taken.
- **At the till.** A Service Kiosk linked to the company reads and writes the company's addresses from **S → COMPANY MAIL**, and nobody's personal mail.
- **From apps.** `api.mail.send{ from = "news@yourcompany.com", to = "kit@foxy.com", subject = "...", body = "..." }` sends from an address on the domain of the company that **published the app**, and no other; fifty a day per app, however many phones it runs on.

Limits, because mail is the first thing here anybody can make more of just by typing: thirty messages per inbox (the oldest goes), fifteen in Sent, 300 letters a message, five recipients, forty sent a day per address. Mail is kept on the Vault in a file of its own, and a message sent to three people is stored once.

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

### Paying, since 9.4

The PUMPE itself no longer offers a way to pay. A Foxy account has two:

1. **Foxy Pay** — stand in front of a kiosk and it finds you. This is what Proximity Pay is called now, and it works the same way.
2. **Foxy Cash** — inside the Foxy app, to a friend, at a flat fee and no daily ceiling. The ceiling is what the friendship replaces: you cannot reach a stranger.

**Code Pay is extinct on a Foxy account.** Typing a kiosk code is refused by the Bank, not merely hidden by the phone, so editing the client changes nothing. Paying a kiosk with its code is what an account at Revolution or another third-party bank does.

Two codes still work on a Foxy account, because neither is the thing Foxy Pay replaced: **cashing out** at a kiosk, which is a kiosk handing you money, and **starting a subscription**, which is an arrangement you can see and cancel in Subs.

Foxy Pay is a route of its own rather than a flag on the code route. An offer is *addressed* — the kiosk chose who may pay it — so the Bank checks the offer, never the client's word for how it came by the code.

## ComputerCraftGaming Bet Play

CCG is a shared big-screen gaming system. Create a lobby on `ccg.lua`, then players open **Bet** on their PUMPE, verify their PIN, enter the screen's alphanumeric lobby code, choose a display name, make their pick, and set a wager from their Bet Wallet.

Three games are included:

1. **Heads or Tails** — pick a side. A correct pick pays `2×` the wager.
2. **Race** — pick one of six red, orange, yellow, green, blue, or purple cars. The six-lane animated race has a server-random winner and pays `3×`.
3. **Survivor** — use the PUMPE touch joystick to move and **PUSH** nearby players from a shrinking circular platform. The last player standing receives `3×` their wager.

Since 9.1 the games run on their own computer — a **CCG Server** — while the money stays on the Bank. The CCG Server generates chance-game outcomes, simulates Survivor, decides the winner and settles each lobby once; a modified PUMPE or CCG console still cannot submit its preferred result.

What it cannot do is touch money. A wager sits in **escrow on the Bank**, and a settle carries only the list of winners — the Bank multiplies the stake it is already holding by its own copy of the game's multiplier, so a CCG Server can pick the wrong winner but cannot invent a payout. It registers with the Bank once using the operator code before the Bank will settle for it at all.

Waiting lobbies expire after five minutes and return every reserved wager, and a CCG Server restart during an active Survivor round refunds everyone rather than guessing a winner. If a CCG Server is switched off holding wagers, the Bank refunds that escrow itself after two hours.

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

## Foxy Pay

A Service Kiosk offers the bill to whoever is standing closest. Tap **NEARBY** with a cart built, and the nearest PUMPE gets a full-screen offer showing the merchant, the amount and the distance. Since 9.4 this is how a Foxy account pays a shop, and **Portable Mode is on by default** — the basket is built on the customer's phone rather than on a second screen.

**Not mine** passes the bill to the next nearest person rather than cancelling the sale, so someone declining an offer meant for the person behind them costs the cashier nothing. PIN rules, daily limits and the transaction log are identical to every other payment, and nothing is ever charged without a tap.

You need a live Foxy bank account for it. An account that has moved its money to another bank is refused, and told where its money went.

### GPS Anchors come first

ComputerCraft can only work out where something is by trilaterating **four** hosts with known coordinates. A world with no GPS constellation cannot locate anything at all, so Foxy Pay does nothing until anchors exist.

1. Install the **GPS Anchor** role on four or more computers with wireless modems.
2. Spread them out, and put at least one at a different height — four anchors in a flat line cannot resolve a position.
3. Give each one its exact block coordinates (press F3 in game). An anchor reads them from an existing constellation if one is already running.
4. Every device then locates itself and reports its position to the Bank, which keeps the map.

Anchors answer the same request ComputerCraft's own `gps host` answers, so ordinary GPS programs work against them too. Positions older than `position_max_age_ms` are ignored, so a PUMPE that has gone offline is never charged.

### Portable Mode

A kiosk carried to the customer has no second screen to show them what they are buying, so **Portable Mode** (POS Settings) turns the sale around: the customer is found *first*.

1. Tap **FIND**. The nearest PUMPE is asked "are you the customer?"
2. They tap **That is me**, and their name appears at the top of the receipt.
3. The operator rings up the items as normal.
4. **PAY** sends the finished basket to that same PUMPE, itemised, and they confirm again with their PIN.

Two confirmations replace the customer display: one to take the sale, one to pay it. A basket that has been rung up never changes hands — backing out ends the sale and kills its payment code, rather than offering somebody else's shopping to whoever is standing closest.

### Proximity Ticket Scanning

**PROXIMITY SCAN** on the Event Kiosk asks whoever is nearest with a ticket for *that event* on their screen. They accept on their own PUMPE, the name lands on the organiser's screen, and the ticket is stamped used. A used ticket stops being held up, so it cannot be scanned twice.

### Proximity Visa

**PROXIMITY VISA** on the Border Controller stays on once toggled, asking whoever is nearest with a travel document on screen. Accepting runs the ordinary border check, so entry rules, cooldowns, visits and Free Roam are identical to typing the code in; already being inside makes the crossing an exit. The gate pulses redstone for **two seconds**, which is why the PUMPE popup tells the traveller to stand close before accepting.

Opening a ticket or a travel document is what makes a PUMPE findable. The claim lapses `present_max_age_ms` after that screen last checked in, so closing it stops you being scanned.

## Two computers, and banks that are not Foxy

### Pair Mode

A Bank is two computers joined by a **wired modem**. Put one on each Bank Server, run networking cable between them, and start them both: the pairing screen shuts the wireless modems, lists the Bank Servers answering on the cable, and pairs with the one you press. There is nothing to type — a code proves nothing the cable has not already proved.

Wireless pairing is refused on purpose. Since 9.3 the two halves answer parts of the same request, so the link between them sits on the path of a player's request rather than beside it, and a wireless modem shares the air with every pocket computer on the server and stops existing when the chunk unloads.

The split is by what a thing **is**, not by how busy it is:

| | Holds |
| --- | --- |
| **Core** (`bank_server.lua`) | Anything where being wrong means money is wrong: balances, sessions, PINs, the ledger, tax, CCG escrow, pay codes, companies and kiosks. Plus Easy Deployment. |
| **Vault** (`bank_vault.lua`) | Everything that is merely *about* an account: friends and conversations, Urgent Contact, territories and visas, border registers and scans, events and tickets, and the records apps keep. |

Three rules make that safe. The Vault never touches a balance — when something it owns has to move money it asks the Core, under a move id that makes a lost reply harmless. The Vault never decides who is asking — the Core authenticates every request and passes down an identity, so session tokens and PINs never travel. And a Bank with no Vault still banks: the money keeps working, and the Vault's own features say so plainly until you pair one.

Which half is which is decided by where the data already is: the server holding the accounts stays the Core, whoever pressed the button. The one that becomes the Vault fetches `bank_vault.lua` over the cable and restarts into it by itself. Clients never learn any of this — a PUMPE asks the Bank, as it always has.

If a Vault is destroyed or a cable is cut, the Bank Server's dashboard shows it, and its **PAIR** button pairs a replacement.

**Updates travel down the cable (11.0).** When the Core runs a newer release than its Vault, it sends the Vault that release over the pair cable — the Vault's program and the shared files, each checked against the published manifest — and the Vault installs it the way an internet update is installed (its own `config.lua` settings kept, every file swapped in or none) and restarts. A paired Vault no longer fetches its own, so the two halves always run the same release; an unpaired one still updates itself. The Vault takes a release only from its own Core, and only a newer one.

### Third-party banks

Bank Servers are no longer locked. Pressing one asks which kind it is:

| | Needs `4040` | What it is |
| --- | --- | --- |
| **Foxy Bank Server** | yes | The economy itself |
| **3rd Party Bank Server** | no | Hosts somebody's own Bank App |

A 3rd Party Bank Server asks the App Server which apps declare themselves banks and hosts the one you choose. An app declares itself in its own first lines:

```lua
-- PUMPE BANK APP: BuckApp
```

Third-party banks have their own logins — a Foxy Account is not an account there — and mint no money: an account opens empty.

Since 9.2 a bank also sets its own terms in the same header — `PUMPE BANK CLEARING` in in-game hours and `PUMPE BANK FEE` as a percentage — and its server enforces them. **Revolution** is the first to use them: no fee on anything, one hour to clear, and proximity pay built for taking money in person. Hold your PUMPE out and whoever is standing next to you pays from theirs.

### The Account ID

Every account at every bank has a sixteen-digit **Account ID**, the first four digits naming the bank holding it. It is the one thing every bank agrees on, and enough on its own to find where money lives.

**Bank Transfer** (Foxy → Bank → Account ID + Transfer) moves everything you have to any Account ID. Your account here closes behind it — Foxy's bank section will not open — and the same feature from the other bank brings it home. Money arriving is what reopens an account.

A transfer never gives money back on a guess. A bank that *refuses* answers with a code, so nothing was applied and the money returns. A bank that says *nothing* might have applied it or not, so the money stays parked and is settled later by asking whether that transfer id was ever seen.

### Fast Bank Transfer, since 9.5

Nobody should have to read sixteen digits off one screen and type them into another. A bank app asks the phone where else its owner keeps money, and the phone answers — it is the phone, it knows what is installed and whose account it is signed into.

- **Bringing money in.** Revolution offers this the moment you open an account, and keeps a Bring in button beside Move out. Pick Foxy and the PUMPE itself makes the two Bank calls, behind its own confirmation screen and its own PIN prompt. The app is told an amount arrived and nothing else — never the session token, never the PIN.
- **Going home.** Foxy cannot reach into Revolution and take money out: the bank holding money is the only one that can authorise it leaving. So Foxy asks the phone to open that bank with this account's own ID as the destination, and that bank pushes. Foxy's bank section offers this under **Bring money in**, and a closed account offers it as **Bring it back here** under the name of the bank the money went to.
- A bank is never offered a transfer to itself, and an app the phone opened cannot open another one.

## Foxy, the App Browser and the App Server

### Foxy

Foxy is the Foxy Account and the bank behind it, and it is **not** built into the phone — you get it from the App Browser. Since 9.0 **BuckApp is not preinstalled either**: it became a bank of its own, installable from the App Browser and hosted on a 3rd Party Bank Server.

- **Bank** opens on your card, drawn on screen with your name across the front, and your balance underneath.
- Under the balance are **your accounts**. `+ New account` opens another one — Savings, Rent, Holiday — and opening one lets you move money to any of your others. It never leaves your account, and closing an account hands its money straight back.
- Under the accounts is **Foxy Cash**: instant, a 2% fee, no daily ceiling, and friends only. Add someone in Friends first. The fee is the sender's; your friend receives the whole amount.
- **Account** changes your name and your PIN.

Savings are not a hiding place. While a tax demand is outstanding you cannot move money out of your main balance, only back into it.

### The App Browser

**Apps** on the Home Screen lists everything the App Server is offering. That is whatever is on the App Server's own disk: it ships Foxy, BuckApp, Revolution, Website Crafter, Internet, Shop, FoxMail and Company, and since 11.1 an App Server that is up to date still checks it has every one of them and fetches any it is missing. (Before 11.1 an App Server only ever downloaded the files its old updater knew about, so apps added after it was set up — FoxMail among them — never reached its disk or the App Browser.) Installing one downloads it in verified chunks and puts it on your Home Screen beside the built-in apps; a download whose size or checksum does not match what was advertised is thrown away rather than run, and an app that crashes is caught and hands you back the phone.

Every byte comes from the App Server, never from the Bank — that is what the machine is for. The Bank is asked one question, once, when something is published: is this developer real.

### FoxyLogin

An app knows who is using it with one line:

```lua
local me = api.login({ name = "Yap", scopes = { "friends" } })
if not me then return end          -- they said no
```

The phone slides up a Foxy sheet naming the app and listing exactly what it will see, and waits for a tap. Approve once and it never asks again. The app receives a profile with only the fields it asked for — `name` always, then any of `number`, `friends` and `balance` — and never the session token. The app id comes from the install rather than the app's own code, so nothing can ask for another app's grant.

**Settings → Connected Apps** lists what you have signed into, what each one can see, and takes it back.

Signed-in apps also get a small store on the Bank for posts, comments or anything else: records are owned by whoever wrote them, reactions are the one thing anybody can add to somebody else's, and collections are per app. A record can also name an **audience**, which makes it private to those people, and be given a life in days that starts the moment somebody reads it — that is what makes a message disappear.

### What else an app can ask for

Three more APIs, each a single call, and each one where the owner rather than the app has the last word.

**The Pin API.** `api.pin("Unlock Yap Chat")` puts the PUMPE's own PIN pad up and hands the app back true or false. The app never sees the PIN.

**The Notification API.** `api.notifications.ask()` asks once and remembers the answer, a refusal included, so an app cannot put the question up every time it starts. `api.notifications.send{ ... }` then sends a banner — or a fullscreen alert, but only where the owner allowed one. Across accounts it works between friends only, with a daily budget.

**The Urgent Contact API.** `api.call{ account_id = ..., name = ... }` raises the same fullscreen ring the PUMPE raises for Urgent Contact. The ring says which app is calling and who is, both labels coming from the install rather than the app.

**Settings → App Settings** lists every app that has ever asked for a permission, whatever the answer was, and is where you change your mind. **Fullscreen notifications are switched on there and nowhere else**: an app cannot ask for them, and blocking notifications takes fullscreen with it.

### In-app purchases

An app can sell things. The money goes to the account that published it, less **30% to the government**, and the Bank keeps the record — an app is never told it has been paid by anything but the Bank, so it cannot decide for itself. One-off purchases and daily subscriptions both work; a subscription that cannot be charged stops rather than running up a debt, and is cancelled under **Settings → App Settings**.

**Yap Boost** is the first: ten dollars to lift one yap above everything in the feed, or twenty a day to lift them all.

`apps/README.md` has the full contract.

### Dev Mode: writing your own app

1. Open **POS Settings** on a Service Kiosk and tap **ENTER DEV MODE**. That registers a developer account against the kiosk's company owner and creates `/apps/` on that computer.
2. Put a `.lua` file in `/apps/`.
3. Open **Dev Mode** again, tap the file, give it a name and a description, and launch it.

It appears in every PUMPE's App Browser. Republishing the same file is an update rather than a second copy, and the app keeps its place and its download count. An app belongs to whoever published it: nobody else can overwrite or delete it, and a developer can delete their own from the App Browser.

An app is one file returning one function:

```lua
-- PUMPE APP: Notes
return function(api)
    -- api.ui, api.util, api.target, api.config, api.colors
    -- api.request(action, payload, silent)  as the signed-in account
    -- api.account(), api.refresh(), api.money(value), api.running()
end
```

It is handed that `api` table and nothing else. It can draw, and it can make requests as the signed-in account, but it never sees the session token or the device file.

## The new customer monitor

The Service Kiosk automatically finds the first attached **Advanced Monitor**. A single 1×1 monitor is enough; the kiosk sets it to text scale `0.5` and adapts to its actual resolution.

The customer display has four animated states:

1. Idle branding and a pulsing ready indicator.
2. A live receipt that updates immediately when the cashier taps a product.
3. Total, six-character payment code, and a live expiry countdown.
4. A full-screen paid or subscription-active animation with the amount and customer name.

The kiosk remains fully usable without the monitor. Attach one later and tap **S → Rescan Display**.

## The web

New in 10.0. Three pieces, deliberately separate.

- **Website Crafter** (a PUMPE app) is where a website is written, as code. The draft is kept on the phone, so it works with no Internet Server anywhere on the network.
- **The Bank Vault** keeps the register of names. Reserving a domain is what makes it yours, and a name means the same thing to everybody because there is one register. Two websites per account.
- **The Internet Server** holds the pages and serves them. Install it from Easy Deployment → SERVERS.

### A website is a program

Since 10.1, a website is Lua, not a page of text. It returns a function; the phone calls it with one `api` table and nothing else:

```lua
return function(api)
    local ui, target = api.ui, api.target
    ui.clear(target)
    ui.header(target, api.domain, "A website", "")
    ui.wrappedText(target, 2, 6, "Hello from the web.", 24, 3, ui.theme.ink)
end
```

**An app lives on your phone. A page is a visit.** The phone fetches the source when you open it, writes it down, runs it, and deletes it — whether the page returned, errored, or you closed it. Anything a previous visit left behind is swept at start-up.

**What a page cannot reach is the point.** It runs in an environment with no `fs`, no `http`, no `rednet`, no `shell`, no `peripheral` and no `load` — absent, not restricted. It does not get the whole `ui` library either: `ui.pin` returns the owner's PIN in the clear. And it gets nothing of the Bank.

The one exception is **Foxy Signin**. `api.login{}` raises the same consent sheet an app raises, and the grant is filed under the domain — signing into one site says nothing about any other. A page can know who you are; it can never know what you have.

The phone opens websites, not the Internet app: an app has no filesystem and no `load`, and giving one either so it could browse would hand every app the means to run whatever it downloads.

**Website Crafter** is a line editor with templates to start from, including a working Foxy page. Its **Check** button asks the Internet Server to compile the source — the only machine in the chain that can — so a page that does not parse fails for its author rather than for every reader. The server refuses to store one either way.

### Reserving a name

In Website Crafter, pick a name — 3 to 20 letters, numbers or dashes, no dots. The letters land one at a time, the screen says **You're in, [your name]**, and the domain appears on a card.

A new site takes **two in-game hours** to open. Until then, going to it in the Internet app says *We're still preparing. Come back soon.* Editing a live site takes it down for **half an in-game hour**, which is what stops a page changing under a reader mid-sentence. You can rename a domain or delete a website at any time, live or not.

### Publishing, and why the Internet Server is not trusted

An Internet Server is a machine anybody can run. It never sees an account and never checks a PIN.

1. The PUMPE asks the Bank for a **one-shot ticket** for a domain it owns.
2. It hands the ticket to the Internet Server with the pages.
3. The Internet Server takes the ticket back to the Bank, which burns it and says whose site it is.

So anyone can lie to an Internet Server about who they are, and nobody can produce a ticket for a name they do not own. A copied ticket is worth exactly one publish.

Pages are filed under the **site**, not under the name. Renaming a domain moves the website with it; a name somebody else picks up later starts empty rather than inheriting the last owner's pages.

There is no directory. The Internet app is an address bar and a short history — you type a domain, the way you would say one out loud.

### For app authors

- `api.web(action, payload)` reaches the Internet Server. There is one per network, so there is nothing to address.
- `api.browse(domain)` opens a website. The phone runs it, sandboxed; the app never sees the code.
- `api.save(table)` / `api.load()` keep something on this phone — one file per app, up to 8 KB, deleted with the app. The Bank's app records are for things other people have to see.
- A **website** gets `api.data(action, payload)` since 10.2: `PUT`, `LIST`, `READ`, `DELETE` and `REACT` on the Bank's app records, filed under `WEB-` and its own domain. A page cannot name another site's records, and `private = true` on a `PUT` keeps a record to the signed-in reader.
- `api.login{}` from a website only ever grants the reader's **name**. Since 10.2 a page asking for `balance` or `friends` gets the name and nothing else.

## Shop

New in 10.2. Buying something no longer means walking to the store.

### Opening a store

A store belongs to a company, so it is opened from a **Service Kiosk linked to that company** (`S` for settings, then **ONLINE STORE**), or since 11.1 from the **Company app** on the owner's phone (the company, then **Store**).

- **Colour** — one of thirteen. The store's cards, buttons and order screens are painted in it on every buyer's phone.
- **Tagline** — what the store sells, in a line. Search reads it as well as the name.
- **Products** — choose which products are online. Subscriptions stay at the till: they are not something anybody delivers.
- **Home delivery**, with a **fee** (0 for free), and/or **pickup** at the company's pickup points.
- **Open.** A store with nothing online, or no way to deliver, cannot open.

The money for every order goes to the company owner's Foxy account, fee included, with a **New order** notification.

### Cancelling and returns (11.0)

- **Returns.** Every order can be returned for at least **five days** after it arrives; the kiosk's **RETURNS** button sets up to thirty. The buyer asks from the order's page in Shop, with a reason. The store sees it at the top of its Delivery Terminal and presses **REFUND RETURN** once the goods are back — the whole order, delivery included, comes out of the owner's account — or **DECLINE** with a reason the buyer is told.
- **Cancelling.** An order **confirms two hours** after checkout. With **CANCELLING ON**, a buyer can cancel until then from the order's page. While an order can be cancelled, the Bank holds its money rather than the store, so a cancellation is always refunded in full; the kiosk shows what is waiting, and the store is paid the moment the order confirms. The Delivery Terminal shows *Buyer can cancel for 1h 20m*, so staff know not to ship it yet.
- **The store refunds.** **CANCEL + REFUND** on any open order at the Delivery Terminal — sold out, say.
- Refunds go back to whichever bank paid. One to another bank is retried until that bank answers, and lands in the buyer's Foxy account if that bank refuses it outright.
- A store's terms are fixed when somebody pays; changing them changes new orders only.
- **The two hours and five days are in-game time**, like every clock in the Shop. A Minecraft day is twenty real minutes, so that is about 1m40s and 1h40m of real time. `shop_confirm_hours`, `shop_min_return_days` and `shop_max_return_days` in `config.lua` change them.

### Buying

The **Shop** app lists every open store; tap one, tap products to add them, then **Checkout**:

1. **Where.** A place you kept, *Where I am now* (needs GPS anchors), typed coordinates, or one of the store's pickup points. A new address can be kept, by name, **on the phone only** — the Bank sees an address once, on the order it belongs to.
2. **How.** Foxy, or **another bank** by its 16-digit Account ID. Another bank pays whole amounts only, because the inter-bank ledger does.
3. **Your PIN.** Foxy's, or your own bank's. The price always comes from the store's list at the Bank; the basket the phone sends is item ids and quantities.

Paying from another bank is a charge Foxy asks that bank to make. The PIN goes to that bank and nowhere else; only the Foxy Core may ask; five wrong PINs lock charges on that account for ten minutes. A charge that got no answer is never guessed at — if it turns out it landed, it is refunded by itself.

The **Delivery** tab lists your orders, open first, and follows each one live: it asks again every few seconds while it is open. Every step the store takes is also a notification.

### The Company app (11.1)

**Company** is in the App Browser, from PUMPE. It is where an owner starts companies, sees them and runs them without walking to a kiosk:

- **Companies** lists yours: products, whether the store is open. **+ Start a company** makes a new one.
- Inside one, **Products** adds, renames, reprices and deletes products, favourites them for the till, and puts them in the Shop app with a line under the name. They are the same products every kiosk of the company sells.
- **Store** is the online store: open or closed, colour, tagline, home delivery and its fee, pickup points, cancelling, and the return window.
- **Points** lists the company's pickup points and what each one sells on the spot (see below).
- **Delivery** — Delivery Mode — lists everything **Out for delivery** across your companies. A parcel for a pickup point shows its **delivery code** and the point; a home delivery shows its coordinates, how far and which way (it needs GPS anchors), and a **Delivered** button with an optional note.

What stays on the kiosk is what belongs to that machine: linking it, withdrawals from it, Dev Mode. Only the Company app can run a company — every other app on a phone uses the same session — and the Bank checks on every request that the person asking owns the company named.

### The Delivery Terminal

A new role in Easy Deployment. Link it to the company once with the owner's Foxy name and PIN, the same way a kiosk is linked.

The board shows every order, open ones first. Tap one to move it on: a **premade stage** (Order received, Packing, Packed, Out for delivery, At the pickup point) or **your own words**. **DONE** tells the buyer it arrived, with an optional note — *left by the door*. An order for a pickup point shows its **delivery code** — what the courier types at the point.

It lays itself out for an Advanced Computer in a warehouse and an Advanced Pocket Computer in a driver's hand.

### Building a pickup point

A pickup point is one Delivery Terminal, one chest customers can open — the **pickup chest** — and any number of **lockers**: chests behind a wall that only the computer can reach.

- Put a **wired modem on every chest**, the pickup chest included, and run **networking cable** from all of them to a wired modem on the computer. ComputerCraft's `pushItems` only moves items between inventories on one wired network. (Chests touching the computer directly also work — but not a mix of both.)
- Give the computer a wireless or Ender modem as well, for the Bank.
- Press **PICKUP** on the board: a name buyers see at checkout, a staff PIN, which chest is the pickup chest, and optionally a side to pulse redstone when a parcel comes out (a door, a lamp, a bell).

Then it runs itself:

- **Delivering (11.1).** The courier taps **ENTER CODE** and types the parcel's **delivery code** — from the Delivery Terminal or Delivery Mode in the Company app — then puts it in the pickup chest and presses **STOCKED**. The terminal moves it into an empty locker and tells the Bank which; the buyer gets a notification with their code. No staff PIN: whoever has the parcel has its code, and the code opens nothing else.
- **Collecting.** The buyer taps **ENTER CODE** and types the six digits from their phone. Then **Foxy Security**: their PUMPE asks *Is this you?* over whatever is open, and they answer **It's me** with their PIN — or **Not me**, and the parcel stays in and their code changes. The terminal waits up to two minutes, then moves the parcel from its locker into the pickup chest. Anything somebody left in the pickup chest is moved into a spare locker first.
- **Pre-confirming.** Foxy's **Security** tab lists every parcel waiting at a pickup point and any question waiting to be answered. Confirm one ahead of time and, for thirty minutes, its code opens it without asking. Tapping it again takes that back.
- **Buying on the spot (11.1).** A pickup point can sell what it has: **STORE: BUY NOW** at the counter lists what is on sale and how many are left, the customer picks one and pays with **Foxy Pay** (needs GPS anchors) or **a code for another bank**, and it comes out into the pickup chest. What it sells — a name, the game item (`oak_log`, or `create:cogwheel` for a mod), how many a sale, the price — is set up per point in the Company app's **Points**. Stock is whatever is in the lockers that is not somebody's parcel; staff put it in through the pickup chest with **STAFF → RESTOCK STORE**, which fills lockers already in use first so empty ones stay free for parcels. The money goes to the owner like any kiosk sale. If a sale comes up short — a locker emptied by hand while the customer paid — the customer is told and the owner is notified who is owed what; that refund is the owner's to make.
- **Five wrong codes** a minute per pickup point, then it waits. **Five wrong staff PINs** lock the staff door for five minutes; the count survives a reboot. The company owner can always sign in instead of using the PIN.
- **Updates.** A pickup point updates itself after a minute with nobody at the counter, from the counter screen, so nobody is ever halfway through anything. (Pickup points on 11.0 never updated in Pickup mode; after 11.1 lands, they tell customers to fetch staff until staff leave Pickup mode once.)

**Pickup mode keeps customers out of the shell.** Whoever is at a pickup point's keyboard is a customer, and the shell could empty every locker. In Pickup mode Ctrl+T does nothing; a reboot comes straight back to the counter before Easy Deployment does anything else; an error pauses the counter rather than ending the program; and leaving takes the staff PIN. Ctrl+R and Ctrl+S cannot be stopped by any program — they only bring the counter back. Keep the lockers out of reach, and protect the blocks themselves the way you would protect any shop.

## Easy Deployment

Only the first Bank Server needs the complete release copied locally. Every other computer needs just one standalone file. `startup.lua` and `installer.lua` are identical; use `startup.lua` at the computer root for automatic launch, or run `installer.lua` manually.

### 1. Bootstrap the first Bank Server

1. Keep `startup.lua` beside the complete release on the one authoritative Bank Server.
2. Edit the local `config.lua` and change `government_key`.
3. Run `startup`, choose **Bank Server**, then **Foxy Bank Server**, and enter `4040`. (A **3rd Party Bank Server** is the other choice and needs no code.)
4. Easy Deployment verifies the complete local bundle, moves same-drive files directly into the compact Bank layout, writes an installer-based `/startup.lua`, and launches `bank_server.lua` immediately. It never tries to discover a Bank Server that does not exist yet.
5. `/pumpe` keeps only the Bank runtime, installer, config, and shared libraries. `/updates` keeps one copy of each role-specific program plus the sanitized public client config; shared runtime files are served directly without duplication.

If a required source file is missing, the first-boot screen lists it and lets you rescan after adding it.

### The Servers tab

Since 10.0 the machines that run the network live behind one card in the role list: **Bank Server**, **Bank Vault**, **App Server**, **Internet Server** and **CCG Server**.

**Bank Vault** is a choice you can pick now. It used to be something only a Bank could make — pairing handed the computer the program — so a Vault could not exist before a Bank was willing to serve it one. It installs from the release like any other role; put a wired modem on both Bank Servers, run cable between them, and pair from the Bank Server as before.

### 2. Install any other computer

1. Copy only the supplied `startup.lua` to the new computer as `/startup.lua`.
2. Attach a wireless or Ender modem, then restart the computer. You can also run `startup` immediately.
3. Tap the desired role.
4. **Personal PUMPE** has the first screen to itself; press the down arrow for every other role. Bank Server and Admin Terminal downloads require code `4040`. Border Controller, **CCG Bet Console** and **GPS Anchor** are ordinary roles.
5. The installer downloads and verifies the main program, `config.lua`, `installer.lua`, and every required file under `lib/`.
6. After installation, it replaces its own marked `/startup.lua` with a direct `installer.lua --boot <role>` entry. Tap **Reboot Now** and that role starts automatically.

Files are downloaded in verified chunks and staged before anything is replaced. A failed installation rolls back. Existing PUMPE data files are never touched, and an unrelated `/startup.lua` is preserved. The installed `/pumpe/installer.lua` is both the permanent boot manager and the one-file Easy Deployment menu.

Easy Deployment checks the public HTTPS manifest on screen before the menu opens and safely replaces itself when a newer installer exists, so a clean computer learns about newly added roles such as Border Controller without first becoming another device type. Booting an already installed client role never contacts the internet — that copy of `installer.lua` arrives from the Bank Server's verified depot instead, and the role starts without waiting on an HTTPS round trip.

The role picker shows the role and version this computer already has, and offers **START ROLE** so an installed computer can be relaunched without reinstalling anything.

The first Bank Server has no deployment host to download from, so Easy Deployment fetches its runtime straight from the public release manifest over HTTPS — a clean computer needs nothing but `startup.lua`. It downloads only the Bank's own seven files; role programs are pulled into `/updates` on demand the first time somebody installs that role. If HTTP is switched off or the manifest cannot be reached, it says so and falls back to a complete release package sitting beside `startup.lua`.

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

**Since 11.1, up to date also means complete.** Which files a role installs is decided by the updater that is running, and a release that adds a file to a role is installed by the updater from before it, which has never heard of that file. So an unattended device that is already current checks it has every file its role needs and downloads only the missing ones. A PUMPE is not asked about this: nothing is new.

**Since 9.5, the PUMPE asks first.** When a release lands the phone fills the screen with what changed and waits for an answer: Update now, or Later. Later holds until the phone restarts, and Settings → Updates has a Check now button in the meantime. The same screen switches the phone to Automatic for anyone who prefers the old behaviour. Every other role is unattended — there is nobody in front of a Bank Server to tap Update — so everything except the PUMPE still updates itself silently.

What the phone shows comes from the manifest: a `label` naming the release and a `changes` array of headlines. Both are derived by the release builder from files in this repository — the label from `release_name` in `config.lua`, the headlines from the top section of `CHANGELOG.md` — so they cannot drift from the release they describe. `release_name` is the one config value an update replaces rather than preserves; every other local setting still survives.

Local configuration survives: each device merges the published config over its own, so your currency, limits and government key are preserved rather than reset to the published defaults. A release can name a setting it is taking back — `config_resets` in `config.lua` — and a device still carrying exactly that stale value adopts the new default instead. That is how the retired `CHANGE-ME-GOVERNMENT-KEY` placeholder is cleared.

The Bank Server's `/updates` is a cache, not a stockpile. It fetches a role program the first time a client installs that role, and drops the cache whenever a release needs the room. A device whose ComputerCraft HTTP access is switched off falls back to that depot over Rednet, so restricting HTTP costs update speed but never strands a device.

Because each device stages only its own role, the worst-case update peaks at about 846 KiB of ComputerCraft's 1000 KiB computer, leaving roughly 154 KiB for account data (the release builder prints the current figure). The largest role is the Bank Core as of 11.1. That headroom is the Bank Core's alone: since 9.3 everything that grows without limit -- conversations, events, tickets, app records, and now the domain register -- lives on the Vault.

### Manifest layout

The manifest's `files` array stays byte-compatible with v5.2.1 Bank Servers, whose updater rejects any entry it does not already know. Anything added since then — currently `border_controller.lua` and `ccg.lua` — is published in a second `extra_files` array:

- Older Bank Servers ignore `extra_files` entirely and keep updating from `files`.
- Current Bank Servers download every array into the same staged, checksum-verified, atomic commit.

`extra_files` is frozen at `border_controller.lua` and `ccg.lua`. Bank Servers older than 7.0.1 reject any entry there they do not already recognise, so a new role added to it would make the release uninstallable for them. Anything added from now on goes in `optional_files`, which those Bank Servers never read, and which newer ones check leniently: an entry an updater does not know is skipped rather than rejected.

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

### Bank Admin Terminal

- Downloaded with the same protected code as the Bank Server.
- The government key starts as `Government1234` and is changed from inside the terminal. The live key is kept in the Bank database, so it never needs a file edited on the Bank. A Bank that reached 7.1 by updating kept the old `CHANGE-ME-GOVERNMENT-KEY` placeholder in its config and rejected the documented key; from 8.0 a retired placeholder means "unset" and `Government1234` works.
- **Controls** holds account approval and the key. With approval on, every new Foxy Account waits until it is approved; accounts that already exist are never held.
- **Accounts** finds any account and can add money, remove money, issue a tax demand, ban or unban, and approve it.
- A tax demand is owed rather than seized. It appears in the holder's BuckApp and is paid with their own PIN, so money never moves without them. **While one is outstanding, that account's payment features are switched off** — code payments, sending money, ticket purchases, visa fees, the Bet Wallet and Bet all refuse — so a fine cannot be dodged by spending the balance first. Being paid still works, and so does settling the demand.
- An announcement can be aimed at **one account** as well as at everyone: banner, full screen, or a **text message**.
- A text message opens a thread between the state and that account. They can answer, the terminal answers back, and **MESSAGES** lists every thread with the ones waiting on a reply highlighted. Only the government moves money there — it can ask for money or send it, and the holder can settle what is asked, but cannot bill the state. That is what makes it usable as a speeding ticket.
- **Announce** sends every PUMPE either a banner or a full screen notice that stays until **Continue** is pressed. Either way it also arrives as an ordinary alert.
- Government sessions expire automatically, and every movement is written to the bank transaction log.

The Tax Controller was retired in 7.1.0. Install **Admin Terminal** on that computer instead; running the old program now says so.

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
- Money sent inside Messages or Urgent Contact goes through the Bank's one transfer path, so the server-calculated 10% fee, the `$2,000` daily limit and the transaction log are identical everywhere. Foxy Cash is the only way to start one from the phone since 9.4, and it reaches friends only.
- You can only message or reach someone who is already a friend.
- A conversation keeps its most recent 60 messages.
- PUMPE locks after 60 seconds of inactivity and begins requiring a PIN after 120 seconds.
- Ticket purchases always require a PIN and are limited to the configured quantity per purchase.
- A ticket code becomes invalid immediately after **Mark Used + Admit**.
- Subscription codes are confirmed with the customer's PIN inside PUMPE. The first charge settles immediately; later charges run once per in-game day. Failed charges notify the customer and retry the next day.
- Sessions are kept in memory and expire after 12 hours by default. Restarting the Bank Server signs clients out without changing their data.
- The PUMPE stores only the last account name locally, never the PIN and never a session token.
- A PUMPE asks before it installs a release, and lists what changed. Every unattended role still updates itself.
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

PUMPE Ecosystem `10.1.0`.
