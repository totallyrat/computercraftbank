# FoxyOS

A working, touch-first digital economy and gaming network for ComputerCraft: Tweaked. Every device runs **FoxyOS** — the phone is the **Pocket** — and it includes personal banking, a Digital ID, ComputerCraftGaming (CCG) Bet Play, a Square-style merchant POS, an optional customer-facing order display, subscriptions, event tickets, customs, citizenships, visas, border gates, taxes, and a persistent central bank.

## What is included

| Program | Hardware | Purpose |
| --- | --- | --- |
| `bank_server.lua` | Advanced Computer + wireless/Ender modem + wired modem to its Vault | The Bank Core: balances, sessions, PINs, the inter-bank ledger, tax, CCG escrow, pay codes, companies, Easy Deployment. Everything else goes to its Vault |
| `bank_vault.lua` | Advanced Computer + wired modem to its Core | The Bank Vault: friends and chat, travel, events and tickets, app records, the Shop's orders, FoxMail, and since 11.2 every account's history and notifications |
| `pumpe.lua` | Advanced Pocket Computer + wireless modem | The Pocket: personal phone, payments, the CCG app (Bet Play and Home Mode), MyID (Digital ID, visas, countries, tax), events, tickets, subscriptions |
| `ccg.lua` | Advanced Computer + Ender modem + Advanced Monitor | ComputerCraftGaming Bet Play lobbies, game animations, Race track and Survivor arena; since 12.0 Home Mode, four free games for one player with a Pocket as the controller |
| `service_kiosk.lua` | (retired) | Since FoxyOS 13 the till is the Company app's **Sell** tab. An updated kiosk says so, pays out any money it still holds, and turns itself into a Pocket |
| `event_kiosk.lua` | Advanced Computer + wireless/Ender modem | Event creation, ticket inventory, release dates, presales and invitations, the queue's numbers, door admission |
| `admin_terminal.lua` | Advanced Computer + wireless/Ender modem | Government-only tax controls, account approval, balances, bans, tax demands, announcements |
| `border_controller.lua` | Advanced Computer + wireless/Ender modem | Checks travel codes, records visitors, and opens a redstone gate |
| `gps_anchor.lua` | Computer + wireless/Ender modem | Serves its own coordinates so every device can locate itself |
| `app_server.lua` | Advanced Computer + wireless/Ender modem | Hosts optional Pocket apps and serves every download, so the Bank never carries one |
| `internet_server.lua` | Advanced Computer + wireless/Ender modem | Holds and serves every website on the network. The Bank Vault keeps the names |
| `delivery_terminal.lua` | Advanced Computer or Advanced Pocket Computer + wireless/Ender modem; chests on networking cable for a pickup point | A company's delivery board: every Shop order, its stages, and DONE. Becomes a self-service pickup point that can sell on the spot |
| `shop.lua` | Downloaded to a Pocket from the App Browser | Online stores: a basket, home delivery or pickup, Foxy or another bank, live delivery tracking, cancelling and returns |
| `foxmail.lua` | Installed on every Pocket at sign-in | Email: an address at foxy.com for everybody, company domains, mail from kiosks and apps |
| `company.lua` | Downloaded to a Pocket from the App Browser | Start and run companies from the phone: products, the online store, what pickup points sell, and Delivery Mode |
| `foxy.lua` | Downloaded to a Pocket from the App Browser | The Foxy Account and the bank behind it: card, sub-accounts, Foxy Cash |
| `apps/` | Written here, published from inside the game | Apps that are not part of a release: `yap.lua`, a text social network, and `yapchat.lua`, private messages |
| `lib/` | Copied with every program | Shared UI, clock, storage, and networking code |

All screens support touch. Physical keyboard input also works.

## The Pocket

The Pocket (the PUMPE until FoxyOS 12) behaves like a small phone rather than a list of bank buttons:

- **Since 12.0 a Pocket belongs to its Foxy Account.** It starts on the lock screen of the account it was set up with — a big clock and the account's name — and the PIN is all it asks. There is no sign-in screen to reach from there; **Remove account** in Settings is how a phone changes hands.
- **Every device has a main colour** (12.0). Orange like the fox out of the box; the Pocket asks once, and Settings → **Main colour** changes it. Kiosks, terminals, consoles and servers pick theirs when they are set up and change it on one of their tabs (a kiosk's **Kiosk** tab, a terminal's **Setup** or **System**, a server's **Server**); the Bank Server and Vault keep the Bank's colours.

- **Start-up (FoxyOS 14).** A circle of your theme colour opens from the middle of the screen until it covers it, then black opens over it the same way — three times — and **POCKET** lands on black, followed by *Powered by FoxyOS* and the version. The same circles play while the Pocket updates or is installed: see **Automatic Internet Updates**.
- **Notices are banners** (FoxyOS 15). Something that worked, or did not, is a banner across the middle of the screen over whatever was there, opening from a line drawn out from the centre: its border and its words are **green** when something went right and **red** otherwise — errors, warnings and plain information alike. It is the same on every device.
- **Every app opens its own way** (FoxyOS 13). A motion in the app's colour grows out of the icon that was tapped and paints over the Home Screen, then holds a beat on the app's icon and name — about half a second. Friends ripples like a call coming in, Tickets closes in on a perforation, MyID scans a card, CCG boots like an arcade cabinet, Subs rises like a wave, Reminders shakes like a bell, Quick strikes like lightning, the App Browser lands in tiles and Settings closes like a shutter. Foxy has none since FoxyOS 15 (it opens straight onto the Bank, whose card drops in), FoxMail folds like an envelope, Shop rolls up an awning, Company opens its blinds, Internet sweeps like radar, Website Crafter types, BuckApp turns like a coin, Revolution spins and INVT unfolds like a card. Any other app gets one of five shapes, chosen from its id, so it always opens the same way.
- Onboarding asks one question first — a new account, or one you already have — then username, then PIN, and ends in a short guide to the phone: three steps (the home screen, your money in Foxy, your apps) with no Skip, ending on **Welcome to Foxy** (12.0 Final). **How Pocket Works** in Settings → Account re-opens the same guide at any time.
- Account setup performs the real device save, account refresh, and Bank Server discovery while showing **Setting up your Foxy Account** and **Preparing your Pocket**.
- The Home Screen lays out small icons in a grid with the app name underneath, the way a phone does, with phone-style status, app transitions, navigation and touch feedback. Every app fits on one page, with room to grow.
- Every Pocket screen is laid out against the Advanced Pocket Computer's native 26×20 character canvas. Buttons, messages, confirmations, activity, events, tickets, notifications, and subscriptions wrap onto readable lines instead of hiding labels beyond the edge.
- The **dock** sits under every app page: search first, then up to three favourites. An empty slot opens the picker, and so does **Edit Your Dock** in Settings.
- Unread counts appear as a badge in an icon's corner.
- **Foxy** is the bank. Since 9.4 the balance, your accounts, Foxy Cash, the Bet Wallet, Activity, cashing out and the Account ID all live in its bank section; there is no Bank app on the Home Screen. (It was BuckApp until 9.0, then a built-in Bank tab until 9.4.)
- **Friends** holds Messages, Friends and Urgent Contact, badged with whatever is waiting.
- **Tickets** holds events and your own tickets, bought through a queue since FoxyOS 13 (see *Tickets and the queue*); **MyID** holds everything the government does: your Digital ID, visas, the countries you run, and tax.
- Opening a ticket or a travel document tells the Bank what you are holding up, which is what lets a door or a border find you. It lapses twenty seconds after you close the screen.
- The **notification centre** is the last Home Screen page: one row per alert with a coloured bar for its kind, its title, the time it arrived, and the first line of the message. Read alerts fade, a tap opens one in full, and the list scrolls. A `!` in the page dots and a banner across the top of whatever app is open announce new ones.
- **CCG** (the Bet app until 12.0) has three tabs: **Home** plays Home Mode on your own console, **Bet** joins a lobby and needs the Foxy Account PIN every time, and **Scores** keeps your best at home. The Bet Wallet is in Foxy.
- After one minute without touch or keyboard activity, the Pocket opens its Lock Screen with the current in-game time and day. Opening it before two minutes needs no PIN; after two minutes, the Foxy Account PIN is verified by the Bank Server.
- **Turning the modem off leaves you signed in.** Settings → Network takes the phone off the network; since 9.5 that is all it does. The Home Screen, Settings and everything already downloaded keep working, the header reads **Offline** where the balance goes, and anything needing a server says so instead of hanging. A phone that starts up with the modem off opens the same way, under the name it last signed in as — a label, not a session, and the first thing it can do back on the network is sign in properly. Off the network the Lock Screen opens on a tap, because the PIN is checked by the Bank and there is no Bank to check it.

## MyID and the Digital ID (FoxyOS 12)

**MyID** is the government's app on the Pocket: **ID**, **Visas**, **Tax** and **Countries**. Tax demands are paid here too (Foxy's bank section points to it).

- **Get a Digital ID** on the ID tab: the name on your ID and your PIN. It waits for the government, and counts only once somebody confirms it at an **Admin Terminal** (People → **DIGITAL IDS**, CONFIRM or REFUSE with a reason). You are told either way; a refused ID can be asked for again, and keeps its code.
- Your **MyID Code** looks like `MY-7K2M-9QPA` — no 0, 1, O or I, so it can be read out loud. **Show my MyID Code** puts it on the screen, big.
- **Visas need a confirmed Digital ID.** The Bank refuses a visa application without one.
- **The MyID Verifier** is at every till (Company → **Sell** → **More** → **Verify a MyID**) and on the Event Kiosk's door. Type the code somebody says — dashes, case and the `MY` are optional — and it answers **VALID** with the registered name, or **NOT VALID** and why (waiting, refused, unknown, suspended). Nothing else about the account is shown.
- A verifier that types five codes that are nobody's has to wait a minute before the next, so it cannot be used to fish for names.

## Tickets and the queue (FoxyOS 13)

Tickets go on sale the way they do in real life.

- **A release.** An event can go on sale at a set day and time instead of straight away. Until then its card says **ON SALE DAY 48 18:00**; the event's page counts down and offers **Join the waiting room**.
- **The waiting room.** Everybody in it when the sale opens is put in a **random order** — arriving an hour early is no better than a minute early. Whoever arrives after the sale has opened joins at the back.
- **The queue.** A few people choose at a time (`ticket_queue_shoppers`, three by default), each with **two minutes** (`ticket_turn_ms`) on a turn that counts down on screen. Waiting shows how many are ahead and roughly how long. Keep the screen open: the Pocket stays awake while it waits and checks in every second, and somebody who stops checking in for thirty seconds (`ticket_queue_stale_ms`) loses their place.
- **Your turn.** Pick how many of each ticket type, pay once with your PIN, and the tickets arrive with **You're going!** A turn not used runs out and passes to the next person; **Leave** hands it on early.
- **A limit per person**, 1 to 10, set by the organizer and counted across every purchase.
- **Presales.** An organizer can open a presale before the general sale, for the people they **invite** — by FoxMail address or by name, at the Event Kiosk. The invitation goes out as **FoxMail from the organizer's own address** (and as a notification, which is all somebody without an address gets). It belongs to the person, not the message: forwarding it lets nobody else in. Invited people queue for the presale and go ahead of the general sale; everybody else waits for the general sale in its own waiting room.
- **Sold out** closes the queue. A sale an organizer changes — a new release time, a new limit, the presale taken away — applies straight away.

The Bank keeps the queue and works out who is next whenever somebody asks; nobody else's place, lottery draw or invitation is ever sent to a Pocket. A Pocket from before 13 cannot buy tickets until it updates: a purchase now has to be on your turn.

## INVT (FoxyOS 14)

**INVT** is in the App Browser, made by **Foxy**: invitations and small events — a party among friends, a café's quiz night. One price (free is a price), a number of spots, and no queue; the Tickets app is still there for the big ones. You sign in with **Foxy** (it asks to see your name and your friends).

- **The feed** lists every public event and the private ones you were invited to, soonest first, sliding in: when, who is hosting, the price, how many spots are left, and whether you are going.
- **Your tickets** are behind the ticket at the top of the feed: tap it and a drawer drags down with all of them; tap one for its code, and **Close** pushes the drawer back up.
- **A new event** is a ticket rising from the bottom to fill in: **title**, **when** (a day and a time), **about** (where, what to bring), **spots**, **price** (0 for free) and **public or private**. **Send it out** stamps it.
- **An event's page** has everything about it and **Join, free** or **Get tickets**: how many (up to **ten an account**, across purchases), then your PIN when it costs something — the money goes straight to the host. A ticket prints out with **YOU'RE GOING**.
- **Private events** only reach the people invited. The host invites **a friend** from their friends list, or anybody **by FoxMail address** — they are mailed from the host's own address when the host has one, and everybody invited is told on their Pocket.
- **Hosting:** **Guests** shows who is coming and who was invited, **Check in** takes the six-letter code from a guest's ticket (once), and **Cancel it** refunds everybody who paid — from the host, checked before any money moves, so a host who cannot cover it is told and nothing is half refunded.

The Bank's Vault keeps INVT's events and tickets. Only the INVT app may ask, and only for somebody who signed in to it with Foxy; the Core checks both on every request.

## Search, App Actions and QuickActions

Since 10.0 Simple, everything the phone can do is a **labelled action**. Opening an app is one; so is Foxy Cash, My Tickets or Network.

An app declares its own in its first lines, the same way a bank app declares itself:

```lua
-- PUMPE APP ACTION: cash | Foxy Cash | Send money to a friend
```

The phone reads that off the file rather than asking the app at runtime, because search has to know what an app does without running it. An app opened at an action receives it from `api.action()`, goes straight there, and closes when it is done.

- **Search** has a slim bar of its own just above the dock, on every page (since 11.0 — it used to take a dock slot, so the dock is four favourites now). It finds apps, app actions and every setting, ranking a name that starts with what you typed above one that merely contains it. **Suggestions appear under the field as you type** — "fox" already offers Foxy, Foxy Cash and FoxMail — and tapping one goes straight there; DONE shows every match. What is not installed is one tap further on, in the App Browser with the same words already filled in.
- The **App Browser** has its own search bar over the same list. (Settings' own search went with its More page in 12.0 Final; the home search finds every setting.)
- **QuickActions** strings app actions together. Add steps, add a **Repeat** to multiply the step above it, then run it yourself or have it run every day at an hour you pick. A QuickAction can sit on the Home Screen as an icon that does something rather than opening something.
- **Reminders** arrive as a banner or as a full screen alert, set in in-game hours from now.

Reminders and QuickActions are kept on the phone and fired by the Home Screen's own tick. A Pocket that is switched off, or sitting on its lock screen, is not reminding anybody — it catches up when the Home Screen is next open.

## How apps are laid out, since 11.0

**Tabs along the bottom are the standard.** An app with more than one part puts its parts in a row on the bottom line, the way Shop did first, and **the mark at the top left (**Pocket**) goes home** from any of them.

**Since 12.0 the tabs float.** They sit in a pill on the row above the bottom, clear of both sides and of the bottom row. The same bar is on every kiosk, terminal and server — there without the home mark, because a kiosk has no home screen to go back to.

**12.0 Final: only the tabs a program needs.** Two, three or four, all on the bar — no More page. Everything More used to hold is on a tab. (The bar still grows a **More** past four tabs, for an app somebody writes with more; nothing that ships has that many.)

| App | Tabs |
| --- | --- |
| Foxy | Bank, Security, Account |
| FoxMail | Inbox, Sent, Write, Me |
| Shop | Stores, Delivery, Places |
| Internet | Go, Saved, Recent — the address box suggests sites you know as you type |
| CCG | Home, Bet, Scores |
| Company | Sell, Products, Store, Deals — the till is Sell; pickup points open from Store |
| Settings | Phone, Apps, Account — Close Pocket is on Account |
| Friends | Chats (with the unread count), Friends, Urgent |
| Tickets | Events, My tickets |
| MyID | ID, Visas, Tax, Countries |
| Revolution | Take, Pay, Account |
| BuckApp | Money, Account |
| Website Crafter | Sites, New |

| Kiosk, terminal or server | Tabs |
| --- | --- |
| Delivery Terminal | Open, Done, Setup (pickup point, link company, colour, close) |
| Pickup point (a Delivery Terminal in Pickup mode) | Collect, Store, Me |
| Event Kiosk | Home (with colour, log out and close), Events, Door |
| Border Controller | Gate, Scan, Owner |
| Admin Terminal | Tax, People, Inbox, System (controls, system, colour, lock) |
| Every server | Status, Activity, Server |

An app with one screen — Internet, Tax, Subs, Reminders, QuickActions, Settings — keeps its **< Home** button rather than tabs it has nothing to put in. An app opened at an action from search opens on that tab.

For app authors, `ui.tabBar(scene, target, tabs, active, color)` draws the bar (each tab as wide as its label needs, the rest shared out) and `ui.runTabs{ list = , pages = , start = , once = }` runs an app made of tab pages; a tab listed in `once` is a thing to do — write a message, place a call — rather than a place to be.

`ui.input` has two more keyboards: `mode = "email"` (with `@`, `.` and `_`) and `mode = "text"` (with `' , . ?`), both typing lower case from the touch keys. And `suggest = function(value) return { { label =, detail = }, ... } end` lists suggestions under the field as you type; tapping one returns the text *and* the item.

## FoxMail

New in 11.0, and installed on every Pocket at sign-in, like Foxy.

- **Your address.** Everybody can claim one at `foxy.com` — 2 to 16 letters, numbers, dots, dashes or underscores. Anybody with an address can write to anybody else.
- **Company email.** A company's owner registers a domain for it on FoxMail's **Me** tab — `revolution.com`, say — and up to five addresses on it (`hello@`, `support@`...). The owner reads and sends as them beside their own address: the Me tab switches between them. `foxy.com` is the Bank's own and cannot be taken.
- **At the till.** The company's addresses are in FoxMail on the owner's Pocket, so a till needs no mailbox of its own (FoxyOS 13).
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

Once accepted, both sides poll a live transcript several times a second, so a typed line appears on the other screen straight away. Inside a call you can send money, ask for money, and pay a request, all under the same PIN and fee rules as any other payment.

- **Hang up** at the bottom ends the call from either side.
- **Save** at the top is a *vote*. The transcript is written into your normal chat only once both people have pressed it; one vote alone saves nothing.
- An unanswered call becomes a missed call for both sides after 30 seconds.

Calls are never written to the database. A Bank Server restart drops a live call the way a dropped connection would, and only a transcript both people agreed to save is kept.

### Paying, since 9.4

The Pocket itself no longer offers a way to pay. A Foxy account has two:

1. **Foxy Pay** — stand in front of a kiosk and it finds you. This is what Proximity Pay is called now, and it works the same way.
2. **Foxy Cash** — inside the Foxy app, to a friend, at a flat fee and no daily ceiling. The ceiling is what the friendship replaces: you cannot reach a stranger.

**Code Pay is extinct on a Foxy account.** Typing a kiosk code is refused by the Bank, not merely hidden by the phone, so editing the client changes nothing. Paying a kiosk with its code is what an account at Revolution or another third-party bank does.

Two codes still work on a Foxy account, because neither is the thing Foxy Pay replaced: **cashing out** at a kiosk, which is a kiosk handing you money, and **starting a subscription**, which is an arrangement you can see and cancel in Subs.

Foxy Pay is a route of its own rather than a flag on the code route. An offer is *addressed* — the kiosk chose who may pay it — so the Bank checks the offer, never the client's word for how it came by the code.

## ComputerCraftGaming Bet Play

CCG is a shared big-screen gaming system. Create a lobby on `ccg.lua`, then players open **Bet** on their Pocket, verify their PIN, enter the screen's alphanumeric lobby code, choose a display name, make their pick, and set a wager from their Bet Wallet.

Three games are included:

1. **Heads or Tails** — pick a side. A correct pick pays `2×` the wager.
2. **Race** — pick one of six red, orange, yellow, green, blue, or purple cars. The six-lane animated race has a server-random winner and pays `3×`.
3. **Survivor** — use the Pocket touch joystick to move and **PUSH** nearby players from a shrinking circular platform. The last player standing receives `3×` their wager.

Since 9.1 the games run on their own computer — a **CCG Server** — while the money stays on the Bank. The CCG Server generates chance-game outcomes, simulates Survivor, decides the winner and settles each lobby once; a modified Pocket or CCG console still cannot submit its preferred result.

What it cannot do is touch money. A wager sits in **escrow on the Bank**, and a settle carries only the list of winners — the Bank multiplies the stake it is already holding by its own copy of the game's multiplier, so a CCG Server can pick the wrong winner but cannot invent a payout. It registers with the Bank once using the operator code before the Bank will settle for it at all.

Waiting lobbies expire after five minutes and return every reserved wager, and a CCG Server restart during an active Survivor round refunds everyone rather than guessing a winner. If a CCG Server is switched off holding wagers, the Bank refunds that escrow itself after two hours.

Winnings do not enter the normal Foxy Account directly. They enter **Holding** for exactly 24 in-game hours, including the original stake in the advertised multiplier, then release into the **Bet Wallet**. Bet Wallet money can be transferred back to the Foxy Account in any positive amount. Adding or cashing out money requires the account PIN. CCG uses fictional game currency only.

### Home Mode (12.0)

Four games made for one player — **Snake**, **Meteors**, **Simon** and **2048** — free: no lobby, no wager, and no CCG Server. The console runs them and your Pocket is the controller.

1. On the console, press **HOME MODE** and enter its **Home PIN**. The owner sets it on the console's first start; a console that was already running asks on its first start after 12.0 (never over an arena in Auto Mode, which has to come back by itself).
2. The console shows a **six digit code**. Open **CCG → Home** on your Pocket and type it.
3. Your Pocket shows the games, then a pad: arrows and **A** (arrow keys and Space work too). The game is on the big screen, the score on your phone.

**Games from the Game Browser (12.0 Final).** Home Mode plays more than the four: **CCG → Home → Game Browser** on the paired Pocket lists the App Server's games, and **Get it** has the console fetch one — in pieces, checked against what the App Server says it is — and keep it beside the four, with its own best score. Up to twelve; **Remove** takes one off. Only in Home Mode: Bet Play is untouched. The App Server ships **Brick Breaker**, and `brickbreaker.lua` is the example for writing one.

A game is published from **Dev Mode** in the Pocket's Settings: the first time a file goes out, it asks **App or Game**, and a game goes to the CCG's Game Browser instead of the Pocket's App Browser. A game is a file that returns one table — `new(width, height, random)`, `input(state, key)`, `tick(state)`, `speed(state)`, `draw(state, screen)`; `state.score`, `state.over` and `state.status` are read from it — and it runs in a box on the console: it is handed maths, strings, tables, colours and a board to paint (`screen.fill`, `screen.text`, clipped to the board), and nothing that reaches the disk, the network or the monitor. A game that errors ends its round and the console carries on; the console only ever reads plain copies of the score, the end and the status.

**The console always starts (12.0 Final).** A console opens on a menu — **HOME MODE** and **BET PLAY** — with what it found on the network: the CCG Server and the Bank. Home Mode needs neither. Bet Play signs the console in to its CCG Server when it is opened, and says exactly what is missing if there is none. A new console asks for its main colour and Home PIN before anything else.

One controller at a time. Five wrong codes and the console shows a new one. **Unpair** on the phone, closing the app, or **EXIT** on the console lets it go, and it shows a new code for the next player. The best score at each game is kept on the console; **Scores** on the phone keeps yours. A console that cannot reach the CCG Server still offers Home Mode, and its main colour is changed with **COLOR** on the pairing screen, behind the PIN.

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

A till offers the bill to whoever is standing closest. **Charge → Foxy Pay** with a basket built, and the nearest Pocket gets a full-screen offer showing the merchant, the amount and the distance. Since 9.4 this is how a Foxy account pays a shop. The company's owner is never offered their own bill (FoxyOS 13): a till is usually the owner's own Pocket, or a computer signed in as them, so theirs is very often the nearest account of all.

**Not mine** passes the bill to the next nearest person rather than cancelling the sale, so someone declining an offer meant for the person behind them costs the cashier nothing. PIN rules, daily limits and the transaction log are identical to every other payment, and nothing is ever charged without a tap.

You need a live Foxy bank account for it. An account that has moved its money to another bank is refused, and told where its money went.

### GPS Anchors come first

ComputerCraft can only work out where something is by trilaterating **four** hosts with known coordinates. A world with no GPS constellation cannot locate anything at all, so Foxy Pay does nothing until anchors exist.

1. Install the **GPS Anchor** role on four or more computers with wireless modems.
2. Spread them out, and put at least one at a different height — four anchors in a flat line cannot resolve a position.
3. Give each one its exact block coordinates (press F3 in game). An anchor reads them from an existing constellation if one is already running.
4. Every device then locates itself and reports its position to the Bank, which keeps the map.

Anchors answer the same request ComputerCraft's own `gps host` answers, so ordinary GPS programs work against them too. Positions older than `position_max_age_ms` are ignored, so a Pocket that has gone offline is never charged.

### Portable Mode

A till carried to the customer has no second screen to show them what they are buying, so the sale can be turned around: the customer is found *first*.

1. Tap **Find** (on a wide screen, **Customer**). The nearest Pocket is asked "are you the customer?"
2. They tap **That is me**, and their name appears at the top of the receipt.
3. The operator rings up the items as normal.
4. **Charge** sends the finished basket to that same Pocket, itemised, and they confirm again with their PIN.

Two confirmations replace the customer display: one to take the sale, one to pay it. A basket that has been rung up never changes hands — backing out ends the sale and kills its payment code, rather than offering somebody else's shopping to whoever is standing closest.

### Proximity Ticket Scanning

**PROXIMITY SCAN** on the Event Kiosk asks whoever is nearest with a ticket for *that event* on their screen. They accept on their own Pocket, the name lands on the organiser's screen, and the ticket is stamped used. A used ticket stops being held up, so it cannot be scanned twice.

### Proximity Visa

**PROXIMITY VISA** on the Border Controller stays on once toggled, asking whoever is nearest with a travel document on screen. Accepting runs the ordinary border check, so entry rules, cooldowns, visits and Free Roam are identical to typing the code in; already being inside makes the crossing an exit. The gate pulses redstone for **two seconds**, which is why the Pocket popup tells the traveller to stand close before accepting.

Opening a ticket or a travel document is what makes a Pocket findable. The claim lapses `present_max_age_ms` after that screen last checked in, so closing it stops you being scanned.

## Two computers, and banks that are not Foxy

### Pair Mode

A Bank is two computers joined by a **wired modem**. Put one on each Bank Server, run networking cable between them, and start them both: the pairing screen shuts the wireless modems, lists the Bank Servers answering on the cable, and pairs with the one you press. There is nothing to type — a code proves nothing the cable has not already proved.

Wireless pairing is refused on purpose. Since 9.3 the two halves answer parts of the same request, so the link between them sits on the path of a player's request rather than beside it, and a wireless modem shares the air with every pocket computer on the server and stops existing when the chunk unloads.

The split is by what a thing **is**, not by how busy it is:

| | Holds |
| --- | --- |
| **Core** (`bank_server.lua`) | Anything where being wrong means money is wrong: balances, sessions, PINs, the ledger, tax, CCG escrow, pay codes, companies and kiosks. Plus Easy Deployment. |
| **Vault** (`bank_vault.lua`) | Everything that is merely *about* an account: friends and conversations, Urgent Contact, territories and visas, border registers and scans, events and tickets, the records apps keep, Shop orders, FoxMail — and since 11.2, each account's transaction history and notifications. |

Three rules make that safe. The Vault never touches a balance — when something it owns has to move money it asks the Core, under a move id that makes a lost reply harmless. The Vault never decides who is asking — the Core authenticates every request and passes down an identity, so session tokens and PINs never travel. And a Bank with no Vault still banks: the money keeps working, and the Vault's own features say so plainly until you pair one.

Which half is which is decided by where the data already is: the server holding the accounts stays the Core, whoever pressed the button. The one that becomes the Vault fetches `bank_vault.lua` over the cable and restarts into it by itself. Clients never learn any of this — a Pocket asks the Bank, as it always has.

If a Vault is destroyed or a cable is cut, the Bank Server's dashboard shows it, and its **PAIR** button pairs a replacement.

**History and notifications are the Vault's (11.2).** They are what a bank accumulates for ever, and until 11.2 the Core kept them in the same file as the money — three thousand transactions and fifty notifications per account — until they filled its disk and it would not start. Now every transaction and notification goes down the cable to the Vault, which keeps each account's newest thirty transactions and twenty notifications in a small file of its own (`records/<account>.dat`), so saving one person's never rewrites anybody else's. The Core keeps what money needs: balances, each account's unread count and newest notification (so a phone's poll never crosses the cable), and a day-by-day income tally that tax periods add up. Records wait in an outbox the Core saves with the money, so a Vault that is away — or still on an older release — loses nothing; Foxy's Activity and the phone's notifications show waiting records too, and the dashboard counts them. The Vault ignores a record it already has, so sending one twice is harmless.

**UPDATE VAULT (12.0).** While the Vault runs an older release than the Bank, the Bank Server's **Server** tab shows **UPDATE VAULT** next to **RE-PAIR**, and its status says why the last try did not go. Pressing it sends the release over the cable with every step on screen. Since 12.0 a Vault clears what it kept from being a Bank Server — the old `/updates` download cache, unfinished staging, `bank_server.lua` — at boot and before every update, and reports its free space; a full disk is refused with how much it needs. A Vault from before 12.0 that says its disk is full needs that done by hand once: hold Ctrl+T on it, type `delete /updates`, then `reboot`.

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

Since 9.2 a bank also sets its own terms in the same header — `PUMPE BANK CLEARING` in in-game hours and `PUMPE BANK FEE` as a percentage — and its server enforces them. **Revolution** is the first to use them: no fee on anything, one hour to clear, and proximity pay built for taking money in person. Hold your Pocket out and whoever is standing next to you pays from theirs.

### The Account ID

Every account at every bank has a sixteen-digit **Account ID**, the first four digits naming the bank holding it. It is the one thing every bank agrees on, and enough on its own to find where money lives.

**Bank Transfer** (Foxy → Bank → Account ID + Transfer) moves everything you have to any Account ID. Your account here closes behind it — Foxy's bank section will not open — and the same feature from the other bank brings it home. Money arriving is what reopens an account.

A transfer never gives money back on a guess. A bank that *refuses* answers with a code, so nothing was applied and the money returns. A bank that says *nothing* might have applied it or not, so the money stays parked and is settled later by asking whether that transfer id was ever seen.

### Fast Bank Transfer, since 9.5

Nobody should have to read sixteen digits off one screen and type them into another. A bank app asks the phone where else its owner keeps money, and the phone answers — it is the phone, it knows what is installed and whose account it is signed into.

- **Bringing money in.** Revolution offers this the moment you open an account, and keeps a Bring in button beside Move out. Pick Foxy and the Pocket itself makes the two Bank calls, behind its own confirmation screen and its own PIN prompt. The app is told an amount arrived and nothing else — never the session token, never the PIN.
- **Going home.** Foxy cannot reach into Revolution and take money out: the bank holding money is the only one that can authorise it leaving. So Foxy asks the phone to open that bank with this account's own ID as the destination, and that bank pushes. Foxy's bank section offers this under **Bring money in**, and a closed account offers it as **Bring it back here** under the name of the bank the money went to.
- A bank is never offered a transfer to itself, and an app the phone opened cannot open another one.

## Foxy, the App Browser and the App Server

### Foxy

Foxy is the Foxy Account and the bank behind it, and it is **not** built into the phone — you get it from the App Browser. Since 9.0 **BuckApp is not preinstalled either**: it became a bank of its own, installable from the App Browser and hosted on a 3rd Party Bank Server.

- **Foxy opens straight away** (FoxyOS 15): no intro first. **Bank** opens on your card, drawn on screen with your name across the front, and your balance underneath. The card drops in from the top and is done in two seconds, once each time Foxy is opened — back from another tab, it is simply there.
- Under the balance are **your accounts**. `+ New account` opens another one — Savings, Rent, Holiday — and opening one lets you move money to any of your others. It never leaves your account, and closing an account hands its money straight back.
- Under the accounts is **Foxy Cash**: instant, a 2% fee, no daily ceiling, and friends only. Add someone in Friends first. The fee is the sender's; your friend receives the whole amount.
- **Account** changes your name and your PIN.

Savings are not a hiding place. While a tax demand is outstanding you cannot move money out of your main balance, only back into it.

### The App Browser

**The front page (FoxyOS 15).** **Apps** opens on two carousels: **Latest**, the five newest apps — numbered as they first reach the App Server, so an update does not make an old app new — and **Trending**, the five downloaded most in the last week of in-game days. They turn by themselves, taking turns every few seconds, with dots under the label and **<** **>** to turn them by hand; tapping a card opens that app. **Explore** at the bottom lists every app, A to Z, four a page, with search, and the search bar on the front page goes straight there. Download counts per day started with FoxyOS 14.1, so on an older App Server Trending falls back to all-time downloads.

The App Browser lists everything the App Server is offering. That is whatever is on the App Server's own disk: it ships Foxy, BuckApp, Revolution, Website Crafter, Internet, Shop, FoxMail and Company, and since 11.1 an App Server that is up to date still checks it has every one of them and fetches any it is missing. (Before 11.1 an App Server only ever downloaded the files its old updater knew about, so apps added after it was set up — FoxMail among them — never reached its disk or the App Browser.) Installing one downloads it in verified chunks and puts it on your Home Screen beside the built-in apps; a download whose size or checksum does not match what was advertised is thrown away rather than run, and an app that crashes is caught and hands you back the phone.

**Apps update themselves (12.0 Final).** Every ten minutes on the Home Screen, while on the network, the Pocket asks the App Server for its apps' versions and quietly fetches any that changed — the apps a release ships, and apps whose author published a new version — with a banner saying which. An update keeps the app's place on the Home Screen and whatever it saved; the new file is written beside the old one first, so a full disk or a damaged download leaves the app as it was, to be tried again next time.

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

**The Pin API.** `api.pin("Unlock Yap Chat")` puts the Pocket's own PIN pad up and hands the app back true or false. The app never sees the PIN.

**The Notification API.** `api.notifications.ask()` asks once and remembers the answer, a refusal included, so an app cannot put the question up every time it starts. `api.notifications.send{ ... }` then sends a banner — or a fullscreen alert, but only where the owner allowed one. Across accounts it works between friends only, with a daily budget.

**The Urgent Contact API.** `api.call{ account_id = ..., name = ... }` raises the same fullscreen ring the Pocket raises for Urgent Contact. The ring says which app is calling and who is, both labels coming from the install rather than the app.

**Settings → App Settings** lists every app that has ever asked for a permission, whatever the answer was, and is where you change your mind. **Fullscreen notifications are switched on there and nowhere else**: an app cannot ask for them, and blocking notifications takes fullscreen with it.

### In-app purchases

An app can sell things. The money goes to the account that published it, less **30% to the government**, and the Bank keeps the record — an app is never told it has been paid by anything but the Bank, so it cannot decide for itself. One-off purchases and daily subscriptions both work; a subscription that cannot be charged stops rather than running up a debt, and is cancelled under **Settings → App Settings**.

**Yap Boost** is the first: ten dollars to lift one yap above everything in the feed, or twenty a day to lift them all.

`apps/README.md` has the full contract.

### Dev Mode: writing your own app

1. Open **Settings → Apps → Dev Mode** on a Pocket and tap **Become a developer** (FoxyOS 13: it was on the Service Kiosk). That registers a developer account for your Foxy Account, with your PIN.
2. Put a `.lua` file in `/apps/` on that computer — a Pocket on a standing computer is the comfortable way to write one.
3. Open **Dev Mode** again, tap the file, give it a name and a description, and it goes out.

A kiosk that turns itself into a Pocket moves the apps it had in Dev Mode to `/apps/` and remembers which it published, so republishing one is still an update.

It appears in every Pocket's App Browser. Republishing the same file is an update rather than a second copy, and the app keeps its place and its download count. An app belongs to whoever published it: nobody else can overwrite or delete it, and a developer can delete their own from the App Browser.

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

## The till (FoxyOS 13)

The Service Kiosk has merged with the Company app in the Pocket. A company's till is its **Sell** tab, the first of four (Sell, Products, Store, Deals), and **Point of Sale** in search opens it straight away — on a standing computer, onto the till it last sold at.

**Till mode (FoxyOS 14)** is the till on its own, for a counter. It has a tab of its own on the Company app's front page (**Companies, Till mode, Delivery**), an App Action (**Till mode** in search), and the first entry under a Sell tab's **More**. The till fills the screen with no tabs, the Pocket **never locks** while it is open, and leaving — **Exit**, or a terminate from the keyboard — asks for the owner's PIN, so a customer at a standing till cannot walk off with the Pocket behind it.

- **It works on the Pocket itself**, for selling on the spot: products as tiles under **Favs**, **Items** and **Daily**, a bag along the bottom with the total on **Charge**, and **Find** to find the customer first. **More** has **Verify a MyID**, **Custom amount** (once or daily) and the customer screens.
- **It is made for a standing computer.** Install the Pocket on an Advanced Computer with a wireless modem, sign in as the owner, open Company → Sell, and the till spreads out: the receipt down the left, the products on the right.
- **Add screens.** Every colour **Advanced Monitor** attached to that computer is a customer screen, at text scale `0.5`, from a 1×1 up: the welcome with a pulse, the order as it is rung up, Foxy Pay's *check your Pocket*, the code to type into another bank's app, and **PAID** with a thank you by name. A tap on a customer screen never presses anything on the till. **More → Customer screens** looks again after one is attached.
- **Charge** offers **Foxy Pay** to the nearest Pocket (it needs GPS anchors) or a **pay code** for somebody who banks elsewhere. A customer found first gets the basket on their own Pocket.
- The device is one of the company's **tills** on the Bank: a terminal like a kiosk was, linked to the company from the start, recognised every time the app comes back. Sales are paid into the owner's account. A company keeps up to twelve; the one nobody has used longest is let go to make room.

**An old Service Kiosk** updates like everything else and then shows *"The Service Kiosk has merged with the Company app in the Pocket"* with **DOWNLOAD POCKET**, which turns the computer into a Pocket through Easy Deployment, keeping its customer monitor. A kiosk that was never linked to a company still holds money of its own; it offers **WITHDRAW $… FIRST**, a code typed into Foxy, so nothing is left on a machine nobody will open again. Easy Deployment no longer offers the Service Kiosk; `shop`, `till` and `kiosk` find the Pocket.

## The web

New in 10.0. Three pieces, deliberately separate.

- **Website Crafter** (a Pocket app) is where a website is written, as code. The draft is kept on the phone, so it works with no Internet Server anywhere on the network.
- **The Bank Vault** keeps the register of names. Reserving a domain is what makes it yours, and a name means the same thing to everybody because there is one register. Two websites per account.
- **The Internet Server** holds the pages and serves them. Install it from Easy Deployment: search for `internet`.

A store is at **name.shop** since FoxyOS 15: not a website on the Internet Server but the store itself, opened by the Pocket (see **Shop Websites**).

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

1. The Pocket asks the Bank for a **one-shot ticket** for a domain it owns.
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

A store belongs to a company, so it is opened from the **Company app** on the owner's Pocket (the company, then **Store**).

- **Colour** — one of thirteen. The store's cards, buttons and order screens are painted in it on every buyer's phone.
- **Tagline** — what the store sells, in a line. Search reads it as well as the name.
- **Products** — choose which products are online. Subscriptions stay at the till: they are not something anybody delivers.
- **Home delivery**, with a **fee** (0 for free), and/or **pickup** at the company's pickup points.
- **Open.** A store with nothing online, or no way to deliver, cannot open.

The money for every order goes to the company owner's Foxy account, fee included, with a **New order** notification.

### Cancelling and returns (11.0)

- **Returns.** Every order can be returned for at least **five days** after it arrives; the store's **Returns** setting allows up to thirty. The buyer asks from the order's page in Shop, with a reason. The store sees it at the top of its Delivery Terminal and presses **REFUND RETURN** once the goods are back — the whole order, delivery included, comes out of the owner's account — or **DECLINE** with a reason the buyer is told.
- **Cancelling.** An order **confirms two hours** after checkout. With **CANCELLING ON**, a buyer can cancel until then from the order's page. While an order can be cancelled, the Bank holds its money rather than the store, so a cancellation is always refunded in full; the Company app shows what is waiting, and the store is paid the moment the order confirms. The Delivery Terminal shows *Buyer can cancel for 1h 20m*, so staff know not to ship it yet.
- **The store refunds.** **CANCEL + REFUND** on any open order at the Delivery Terminal — sold out, say.
- Refunds go back to whichever bank paid. One to another bank is retried until that bank answers, and lands in the buyer's Foxy account if that bank refuses it outright.
- A store's terms are fixed when somebody pays; changing them changes new orders only.
- **The two hours and five days are in-game time**, like every clock in the Shop. A Minecraft day is twenty real minutes, so that is about 1m40s and 1h40m of real time. `shop_confirm_hours`, `shop_min_return_days` and `shop_max_return_days` in `config.lua` change them.

### Discounts (12.0)

Set up in the Company app: the company, then **Deals**. Since 12.0 Final the sale and codes count at the company's pickup points too (see *Building a pickup point*).

- **A sale** takes a percentage off everything in the store, up to 90%.
- **Free delivery** on home deliveries — always, or when what is paid (after discounts) reaches an amount.
- **Codes**, typed by a buyer at checkout: a percentage *or* an amount off, and/or free delivery, with a number of uses (0 for no limit). Up to twenty per store, kept in capitals; switch one off without deleting it. Codes are never listed on the storefront — handing them out is the store's business.

The Bank works out every price: the sale first, then the code on what is left, then delivery. A code that does not work is refused at checkout rather than quietly ignored. An order a code makes free moves no money — no other bank is asked for nothing — and can still be cancelled while the store allows it. Every order keeps what was taken off and the code, and the buyer's order page says what they saved.

### Buying

The **Shop** app lists every open store; tap one, tap products to add them, then **Checkout**:

1. **Where.** A place you kept, *Where I am now* (needs GPS anchors), typed coordinates, or one of the store's pickup points. A new address can be kept, by name, **on the phone only** — the Bank sees an address once, on the order it belongs to.
2. **Checkout** (12.0) shows what the Bank says it comes to — items, the sale, a code, delivery or *Free* — and has a box for a discount code.
3. **How.** Foxy, or **another bank** by its 16-digit Account ID. Another bank pays whole amounts only, because the inter-bank ledger does. Nothing to pay skips this.
4. **Your PIN.** Foxy's, or your own bank's. The price always comes from the store's list at the Bank; the basket the phone sends is item ids and quantities.

Paying from another bank is a charge Foxy asks that bank to make. The PIN goes to that bank and nowhere else; only the Foxy Core may ask; five wrong PINs lock charges on that account for ten minutes. A charge that got no answer is never guessed at — if it turns out it landed, it is refunded by itself.

The **Delivery** tab lists your orders, open first, and follows each one live: it asks again every few seconds while it is open. Every step the store takes is also a notification.

### Shop Websites (FoxyOS 15)

A store has an address on the web: **name.shop**. On the store's page in the Company app, **Put it on the web** asks for the name, pre-filled from the company's; the Bank keeps it, one store to an address, and the store has to be open. Anybody types it into **Internet** — whose keyboard has a full stop since 15 — and the store opens as itself: Shop, locked to that store, on its **front door** in the store's colours with the address where the tagline was. **Open it**, **Change the address** and **Take it down** are on the same page.

No website can be called this: every other domain is one word with no dot in it, so the `.shop` names never collide with the Internet Server's. A Pocket opens one without the Internet Server at all — the Bank says which store is at the address — and runs its own Shop app if it has it, or fetches Shop from the App Server for the visit and holds it **in memory**, keeping nothing.

They replaced FoxyOS 14's **Shop Apps**, which were the same thing as an app of its own, about 27 KB on every Pocket that installed one. Since 15 the App Server takes any that are left out of its catalogue when it starts, a Pocket takes its own copy off at sign-in — saving the store's address in Internet if it has one, and saying so — and the Bank tells a Company app from before 15 that Shop Apps are websites now.

### The Company app (11.1)

**Company** is in the App Browser, from FoxyOS. It is where an owner starts companies, sells, and runs them. Its front page has three tabs: **Companies**, **Till mode** (see *The till*) and **Delivery**:

- **Companies** lists yours: products, whether the store is open. **+ Start a company** makes a new one.
- Inside one, **Sell** is the till (see *The till*). **Products** adds, renames, reprices and deletes products, favourites them for the till, and puts them in the Shop app with a line under the name. They are the same products every till of the company sells.
- **Store** is the online store: open or closed, colour, tagline, home delivery and its fee, cancelling, and the return window — and **Pickup points**, which opens the company's points: the switch that lets buyers pick up, and what each point sells on the spot (see below).
- **Deals** (12.0): the sale, free delivery and discount codes — see *Discounts* above.
- **Delivery** — Delivery Mode — lists everything **Out for delivery** across your companies. A parcel for a pickup point shows its **delivery code** and the point; a home delivery shows its coordinates, how far and which way (it needs GPS anchors), and a **Delivered** button with an optional note.

Only the Company app can run a company — every other app on a phone uses the same session — and the Bank checks on every request that the person asking owns the company named.

### The Delivery Terminal

A new role in Easy Deployment. Link it to the company once with the owner's Foxy name and PIN.

The board shows every order, open ones first. Tap one to move it on: a **premade stage** (Order received, Packing, Packed, Out for delivery, At the pickup point) or **your own words**. **DONE** tells the buyer it arrived, with an optional note — *left by the door*. An order for a pickup point shows its **delivery code** — what the courier types at the point.

It lays itself out for an Advanced Computer in a warehouse and an Advanced Pocket Computer in a driver's hand.

### Building a pickup point

A pickup point is one Delivery Terminal, one chest customers can open — the **pickup chest** — and any number of **lockers**: chests behind a wall that only the computer can reach.

- Put a **wired modem on every chest**, the pickup chest included, and run **networking cable** from all of them to a wired modem on the computer. ComputerCraft's `pushItems` only moves items between inventories on one wired network. (Chests touching the computer directly also work — but not a mix of both.)
- Give the computer a wireless or Ender modem as well, for the Bank.
- On the board's **Setup** tab, press **SET UP A PICKUP POINT**: a name buyers see at checkout, a staff PIN, which chest is the pickup chest, and optionally a side to pulse redstone when a parcel comes out (a door, a lamp, a bell).

Then it runs itself:

- **The counter (12.0 Final)** has three tabs: **Collect** (the code box), **Store** and **Me**, with **STAFF** under them.
- **Delivering (11.1).** The courier taps **ENTER CODE** and types the parcel's **delivery code** — from the Delivery Terminal or Delivery Mode in the Company app — then puts it in the pickup chest and presses **STOCKED**. The terminal moves it into an empty locker and tells the Bank which; the buyer gets a notification with their code. No staff PIN: whoever has the parcel has its code, and the code opens nothing else.
- **Collecting.** The buyer taps **ENTER CODE** and types the six digits from their phone. Then **Foxy Security**: their Pocket asks *Is this you?* over whatever is open, and they answer **It's me** with their PIN — or **Not me**, and the parcel stays in and their code changes. The terminal waits up to two minutes, then moves the parcel from its locker into the pickup chest. Anything somebody left in the pickup chest is moved into a spare locker first.
- **Pre-confirming.** Foxy's **Security** tab lists every parcel waiting at a pickup point and any question waiting to be answered. Confirm one ahead of time and, for thirty minutes, its code opens it without asking. Tapping it again takes that back.
- **Me (12.0 Final).** No code to hand? **Me → TYPE YOUR NAME**, and your Pocket asks *Is this you?* — **It's me** with your PIN shows the counter your orders for that point. One that has arrived comes out with a tap (you just said yes, so it does not ask again). One still on its way can be made **ready**: when it arrives its code opens it without asking. **< DONE** signs you out, and so does walking away for a minute. Only your own orders, only on that counter; **Not me** shows it nothing. A person's Pocket is asked at most once a minute, and names nobody has count as wrong codes.
- **Buying on the spot (11.1).** A pickup point can sell what it has: the counter's **Store** tab lists what is on sale and how many are left — at the company's sale price since 12.0 Final, with **I HAVE A DISCOUNT CODE** before paying (the Bank works the price out as the Shop app's checkout does, and a code used here counts its use) — the customer picks one and pays with **Foxy Pay** (needs GPS anchors) or **a code for another bank**, and it comes out into the pickup chest. What it sells — a name, the game item (`oak_log`, or `create:cogwheel` for a mod), how many a sale, the price — is set up per point in the Company app's **Store → Pickup points**. Stock is whatever is in the lockers that is not somebody's parcel; staff put it in through the pickup chest with **STAFF → RESTOCK STORE**, which fills lockers already in use first so empty ones stay free for parcels. The money goes to the owner like any sale at a till. If a sale comes up short — a locker emptied by hand while the customer paid — the customer is told and the owner is notified who is owed what; that refund is the owner's to make.
- **Five wrong codes** a minute per pickup point, then it waits. **Five wrong staff PINs** lock the staff door for five minutes; the count survives a reboot. The company owner can always sign in instead of using the PIN.
- **Updates.** A pickup point updates itself after a minute with nobody at the counter, from the counter screen, so nobody is ever halfway through anything. (Pickup points on 11.0 never updated in Pickup mode; after 11.1 lands, they tell customers to fetch staff until staff leave Pickup mode once.)

**Pickup mode keeps customers out of the shell.** Whoever is at a pickup point's keyboard is a customer, and the shell could empty every locker. In Pickup mode Ctrl+T does nothing; a reboot comes straight back to the counter before Easy Deployment does anything else; an error pauses the counter rather than ending the program; and leaving takes the staff PIN. Ctrl+R and Ctrl+S cannot be stopped by any program — they only bring the counter back. Keep the lockers out of reach, and protect the blocks themselves the way you would protect any shop.

## Easy Deployment

Since 12.0 Easy Deployment is a downloader. One file, `startup.lua`, sets up any computer: everything it installs comes straight from the published release on GitHub, and every file is checked against the release manifest before anything is replaced. It asks no Bank Server for anything. It needs ComputerCraft's HTTP switched on, as the Bank's own updates already do.

### Setting up a computer

1. Put Easy Deployment on it as `/startup.lua`:

   ```
   wget https://raw.githubusercontent.com/totallyrat/computercraftbank/main/startup.lua startup.lua
   ```

2. Run `startup` (or restart the computer).
3. **The Pocket has the first screen** — unless this is a new world. On a computer with nothing installed and a modem, Easy Deployment first asks the network for a Bank; if none answers, the first screen is **Welcome to Foxy** (12.0 Final), and **GET THE BANK SERVER** fetches it from GitHub (operator's code `4040`). **NOT NOW** goes to the Pocket. Otherwise tap **INSTALL POCKET**, or press Enter.
4. **Anything else: press the down arrow, or just start typing.** A search box opens and the results change with every key. It reads keywords as well as names — `shop` finds the Pocket (the till is in its Company app), `casino` the CCG Bet Console, `web` the Internet Server, `pickup` the Delivery Terminal. Up/down move through the results; Enter or a tap opens one. Up from the first result, or Backspace on an empty box, goes back to the Pocket.
5. Every program gets the same full screen as the Pocket, with one big **INSTALL** button. The **Bank Server** (Foxy's) and the **Admin Terminal** ask for the operator's code, `4040`. The 3rd Party Bank Server is its own entry and needs no code.
6. It downloads the program, `config.lua`, the shared `lib/` files and its own copy as `/pumpe/installer.lua`, writes `/startup.lua` to boot through that copy, and restarts into the program.

A computer that already has a program shows it: **OPEN** starts it and **REINSTALL** downloads it again. A reinstall keeps the computer's own `config.lua` settings. Only the Bank Server ever gets the government key: every other program's config has it removed. Data files are never touched, and a `/startup.lua` that is your own program is kept — the installed program then starts straight away instead.

The first Bank in a world is installed the same way — **Bank Server**, code `4040` — and needs nothing but `startup.lua`. Change `government_key` in `/pumpe/config.lua` before anyone uses it. A **Bank Vault** installs like anything else; cable it to the Bank and pair from the Bank as before.

### Booting

`/startup.lua` runs `/pumpe/installer.lua --boot <program>`. On the way up, Easy Deployment replaces itself if the release has a newer one, installs a newer release of the program if there is one, then starts **the program beside itself**. That is `/pumpe` on everything Easy Deployment set up, and wherever a Bank built by hand keeps its files: booting never assumes `/pumpe` and never rewrites `/startup.lua`, so a Bank laid out differently still updates and starts. With no internet it starts what it has. A Bank Vault is the exception to updating on the way up: its Core updates it over the cable to the Core's own release, so the two halves never run different releases. A Delivery Terminal in Pickup mode ignores Ctrl+T from the first moment and restarts if its program ever ends.

`installer.lua --auto <program>` installs a newer release and restarts, and does nothing otherwise. `lib/net.lua` uses it when a program cannot update itself.

**Why it changed (11.2).** Until 12.0 every device got Easy Deployment from the Bank over Rednet, and the Bank found its own copy by a phrase that the Bank's program contained too. On a Bank whose program sat where that copy belongs, every device it set up was given the Bank's program as its installer — the install screen said PERSONAL PUMPE, and after the restart it was a Bank Server, whatever had been picked. A downloader cannot be handed the wrong program by a Bank. The Bank still answers old installers on devices with HTTP switched off, and since 12.0 Pre it only ever hands out a file that *starts* with `-- PUMPE EASY DEPLOYMENT`.

A computer that turned into a Bank that way is fixed by wiping and setting it up again:

```
delete /startup.lua
delete /pumpe
wget https://raw.githubusercontent.com/totallyrat/computercraftbank/main/startup.lua startup.lua
reboot
```

## Automatic Internet Updates

The Bank Server watches an HTTPS release folder for new FoxyOS versions. It checks the small `release_manifest.json` every few seconds. When the manifest contains a newer semantic version, the server:

1. Downloads every required script into a private staging folder.
2. Rejects missing, unexpected, oversized, or path-traversing files.
3. Verifies every byte count and checksum.
4. Preserves the existing government key, release URL, and all other local configuration.
5. Atomically replaces the program files, rolling back if any move fails.
6. Refreshes `/pumpe/installer.lua`, writes a direct Bank boot entry, saves the database, and restarts immediately.
7. Detects the restart marker, bypasses every menu, clears any `/updates/` an older release left behind, and launches the Bank Server normally.

Every role updates itself. A Pocket, CCG console, kiosk, controller or Bank checks the public manifest when it starts and every `client_update_check_seconds` (default 30), then downloads **only the files that role needs** — its own program, Easy Deployment and the shared libraries. Nothing downloads another role's program.

**Since 11.1, up to date also means complete.** Which files a role installs is decided by the updater that is running, and a release that adds a file to a role is installed by the updater from before it, which has never heard of that file. So an unattended device that is already current checks it has every file its role needs and downloads only the missing ones. A Pocket is not asked about this: nothing is new.

**The FoxyOS update screen (FoxyOS 12).** Every device downloads the same way, Easy Deployment included: **FOXY** blinks in the middle of the screen, and a thin bar along the bottom edge fills as the files arrive.

**The Pocket has its own (FoxyOS 14).** A Pocket downloads under its circles — the theme colour opening from the middle, then black — with the same thin bar, asks under **POCKET**, and installing plays the circles for **fifteen seconds**, the bar filling under them, before it restarts into its start-up. Easy Deployment plays the circles too when it installs the Pocket. Every other device keeps FOXY.

**The Pocket downloads first, then asks.** The release is downloaded and checked into a staging folder under the update screen, then the screen slides up into the question: the release's name, its version, what it is, and two buttons — **Install** and **Cancel & Delete**. Install swaps the files in and restarts; Cancel & Delete throws the download away and leaves the phone as it was, and it asks again next time it starts. Settings → Updates has a Check now button and the Automatic switch for anyone who wants no question. Every other role is unattended — there is nobody in front of a Bank Server to tap Install — so everything except the Pocket still updates itself without asking, under the same screen.

**Beta Updates on every device (FoxyOS 15.1).** Every server, kiosk, terminal and console can sign up too: **BETA UPDATES** on a server's Server tab (the App Server, Internet Server, CCG Server, 3rd Party Bank Server, GPS Anchor and the Bank), **BETA** beside Create on the Event Kiosk, **Beta Updates** on the Delivery Terminal's Setup tab, the Border Controller's Owner tab (behind the owner PIN) and the Admin Terminal's System tab, and **BETA** in the bottom row of the CCG's Home Mode settings. One screen does it everywhere: whether the device is signed up, what it runs, and Sign up or Leave, each asked first. The choice is `beta_updates.dat` beside the device's programs, so an update never takes it away. Signed up, a device looks for the release first and then the beta, and installs a beta by itself the way it installs a release — there is nobody to ask. **The Bank** is signed up on the Core, whose screen warns that every Pocket uses it; its Vault follows it as always, sent the beta the Core runs from the beta's own manifest. A Pocket that cannot read the manifest and asks the Bank what it runs never takes a beta the Bank is on.

**Beta Updates (FoxyOS 14.1).** Settings on a Pocket has a **Beta Updates** tab. Sign up and the Pocket gets the next FoxyOS before everybody else, before it has been tested: the tab shows the newest beta with a button to get it, and a Pocket that is signed up also looks for betas by itself, after the release. A beta is numbered half way to the release it comes before — **FoxyOS 15 Beta is 14.5** — and a Pocket reads a minor version of 5 as a beta wherever it finds one: it installs one only if it signed up, and always asks first, even with automatic updates on. Betas are published in a manifest of their own, `beta/release_manifest.json` beside the release's (`beta_manifest_url` in `config.lua`), on the `beta` channel, so the Bank, every server and every Pocket that did not sign up never see one; looking for a beta also never falls back to the Bank's depot, which holds the release. Leaving keeps the beta you have until the full release, which is newer, arrives the usual way. If a beta will not start, run `installer` and install the Pocket again: that is the release. On a beta, the apps FoxyOS ships — Foxy, FoxMail, Company, Shop, Internet and the rest — come from the beta manifest too, fetched at sign-in for the ones the Pocket has, and the ten-minute app updates leave them alone until the Pocket is on a release again, when the App Server's copies replace them. Between betas, `beta/` is removed from the repository, and the tab says there is none.

What the phone shows comes from the manifest: a `label` naming the release and a `changes` array of headlines. Both are derived by the release builder from files in this repository — the label from `release_name` in `config.lua`, the headlines from the top section of `CHANGELOG.md` — so they cannot drift from the release they describe. `release_name` is the one config value an update replaces rather than preserves; every other local setting still survives.

Local configuration survives: each device merges the published config over its own, so your currency, limits and government key are preserved rather than reset to the published defaults. A release can name a setting it is taking back — `config_resets` in `config.lua` — and a device still carrying exactly that stale value adopts the new default instead. That is how the retired `CHANGE-ME-GOVERNMENT-KEY` placeholder is cleared.

The Bank Server still answers installers from before 12.0 over Rednet, which only a device with ComputerCraft's HTTP switched off still asks. Its own runtime it serves from `/pumpe`; any other program it fetches from the release when one is asked for and keeps **in memory** — until 11.2 it kept them in `/updates` on its own disk, which is half of how a Core filled up. Since 12.0 a device with HTTP switched off cannot be set up or updated: Easy Deployment downloads from GitHub.

**Published without comments (11.2).** The Core, the Vault, the shared libraries, since FoxyOS 12 the Pocket's own program, and since FoxyOS 13 the apps the App Server ships are downloaded from `dist/`: the same files built by `tools/build_release_manifest.js` with their comments and indentation taken out — a third of every one of them was prose for whoever reads this repository. Every line stays on the line it came from, so an error a computer reports still names the right line here, and `tests/host_dist_build_test.lua` proves each one compiles to exactly the same bytecode as its source. Comments that code reads are kept: the installer is published as it is, for its `-- PUMPE EASY DEPLOYMENT` line, and a stripped app keeps every `-- PUMPE ...` header line (its name, its App Actions, a bank's terms) on the line it was. Edit the source, never `dist/`; the builder rewrites it.

Because each device stages only its own role, the worst-case update is about 723 KiB of ComputerCraft's 1,000,000-byte computer — a Pocket, which holds a downloaded release while it asks — and the Bank Core's is about 691 KiB, leaving it roughly 286 KiB for its data (the release builder prints the current figures). A Pocket keeps its apps beside that: about 48 KiB for Foxy and FoxMail, about 203 KiB with every app FoxyOS ships, which leaves a Pocket with all of them about 50 KiB to spare while it updates. (FoxyOS 14's Shop Apps added about 27 KiB each; since 15 a store is a website and costs a Pocket nothing.) FoxyOS 13's till doubled the Company app, which is why the apps are stripped now too. And the Core's data no longer grows with time: since 9.3 everything that grows without limit — conversations, events, tickets, app records, the domain register, and since 11.2 history and notifications — lives on the Vault.

### Manifest layout

The manifest's `files` array stays byte-compatible with v5.2.1 Bank Servers, whose updater rejects any entry it does not already know. Anything added since then — currently `border_controller.lua` and `ccg.lua` — is published in a second `extra_files` array:

- Older Bank Servers ignore `extra_files` entirely and keep updating from `files`.
- Current Bank Servers download every array into the same staged, checksum-verified, atomic commit.

`extra_files` is frozen at `border_controller.lua` and `ccg.lua`. Bank Servers older than 7.0.1 reject any entry there they do not already recognise, so a new role added to it would make the release uninstallable for them. Anything added from now on goes in `optional_files`, which those Bank Servers never read, and which newer ones check leniently: an entry an updater does not know is skipped rather than rejected.

`launcher.lua` is retained only as a migration bridge for older startup entries; v6 installations and normal boots do not use it.

### Release source

This package is connected to the public `totallyrat/computercraftbank` GitHub repository. Bank Servers use:

```lua
auto_update = true,
update_manifest_url = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json",
update_channel = "stable",
update_check_seconds = 5,
client_update_check_seconds = 60,
```

Every file a computer downloads is in `dist/`, next to the manifest: for example `lib/update.lua` is published as `dist/lib/update.lua`. Since FoxyOS 14.1 that includes the files that are not stripped, copied there as they are, because between two releases the readable source at the root is the next one being written — a beta, for a start — and must not change what the release serves. A beta is the same layout under `beta/`. The Minecraft server's ComputerCraft HTTP configuration must allow HTTPS access to `raw.githubusercontent.com`.

### Publishing each new version

After editing the release and increasing `version` in `config.lua`, run:

```text
node tools/build_release_manifest.js
tools/run_tests.sh
```

The builder is the only step. It copies `startup.lua` to `installer.lua`, stamps `INSTALLER_VERSION` from `config.lua`, and regenerates `release_manifest.json` with both file arrays. It never rewrites program source, and nothing has to be checksummed by hand.

A beta is built with `node tools/build_release_manifest.js --beta`, from a `config.lua` whose version is a beta (x.5.y). It writes only `beta/` — its own `dist/` and `release_manifest.json` — and leaves the release, `installer.lua` and the root `startup.lua` alone, because a new computer is set up by downloading that file straight from the repository. The builder refuses a beta version without `--beta`, and `--beta` without one.

`tests/host_release_manifest_test.lua` then fails the suite if the manifest, the version stamp, or the two entry points have drifted from the files in the repository — so a stale manifest cannot be published by accident.

Commit or upload the changed source files and regenerated `release_manifest.json` together. The Bank Server will discover the higher version on its next check. Never publish a partially uploaded release with the new manifest first; upload the files first and the manifest last.

### Manual launching

You can start any installed program through Easy Deployment:

```text
/pumpe/installer.lua --boot pumpe
```

Program names are `pumpe`, `service`, `delivery`, `event`, `border`, `bank`, `vault`, `tpbank`, `admin`, `ccg`, `ccgserver`, `anchor`, `apps` and `internet`. To start one automatically, `/startup.lua` on that device is:

```lua
shell.run("/pumpe/installer.lua", "--boot", "service")
```

Running `/pumpe/installer.lua` with nothing after it opens the menu.

## Hardware notes

### Bank Server

- Keep it on a dedicated computer.
- An Ender modem is ideal when devices are spread across dimensions.
- Data is saved atomically to `bank_data_v5.dat` beside the program.
- Back up that file. It contains the full economy.

### Pocket

- Use an Advanced Pocket Computer with a wireless modem.
- The header clock uses ComputerCraft's in-game clock.
- Event cards and tickets show a live countdown calculated from `event_day` and `event_time`.

### CCG Bet Console

- Use an Advanced Computer with an Ender modem and an Advanced Monitor.
- The console sets the monitor to text scale `0.5` and responsively supports a 1×1 monitor or a larger wall.
- Lobby codes, ready states, coin flips, six race lanes, the shrinking Survivor ring, players, and results all render on the monitor.
- Touch **Start** only after every displayed player is ready. Heads or Tails and Race support one or more players; Survivor requires at least two.
- **Auto Mode** does that waiting for you and keeps opening the next lobby. It stops only for the code entered when it was started.
- The console stores only its server-issued ID/token. It never stores Pocket PINs or decides payouts.

### A till (the Pocket on a standing computer)

- Use an Advanced Computer with a wireless modem, and install **Pocket** on it. Sign in as the company's owner, then Company → **Sell**.
- Attach Advanced Monitors directly or through a wired peripheral network; every colour one is a customer screen.
- Foxy Pay needs GPS anchors, like everything that finds a person.
- The Pocket locks after a minute without a tap, like any Pocket; the customer screens keep showing the welcome.

### Event Kiosk

- Signs in with an ordinary Foxy Account.
- Event day is the in-game day number.
- Event time is entered as four digits (`1830` becomes `18:30`).
- An event's page has **SALE** (when tickets go on sale, and how many each person may buy) and **PRESALE** (when it opens, and who is invited), and shows who is in line and choosing.

### Bank Admin Terminal

- Downloaded with the same protected code as the Bank Server.
- The government key starts as `Government1234` and is changed from inside the terminal. The live key is kept in the Bank database, so it never needs a file edited on the Bank. A Bank that reached 7.1 by updating kept the old `CHANGE-ME-GOVERNMENT-KEY` placeholder in its config and rejected the documented key; from 8.0 a retired placeholder means "unset" and `Government1234` works.
- **Controls** holds account approval and the key. With approval on, every new Foxy Account waits until it is approved; accounts that already exist are never held.
- **Accounts** finds any account and can add money, remove money, issue a tax demand, ban or unban, and approve it.
- A tax demand is owed rather than seized. It appears in the holder's MyID app (Tax) and is paid with their own PIN, so money never moves without them. **While one is outstanding, that account's payment features are switched off** — code payments, sending money, ticket purchases, visa fees, the Bet Wallet and Bet all refuse — so a fine cannot be dodged by spending the balance first. Being paid still works, and so does settling the demand.
- An announcement can be aimed at **one account** as well as at everyone: banner, full screen, or a **text message**.
- A text message opens a thread between the state and that account. They can answer, the terminal answers back, and **MESSAGES** lists every thread with the ones waiting on a reply highlighted. Only the government moves money there — it can ask for money or send it, and the holder can settle what is asked, but cannot bill the state. That is what makes it usable as a speeding ticket.
- **Announce** sends every Pocket either a banner or a full screen notice that stays until **Continue** is pressed. Either way it also arrives as an ordinary alert.
- Government sessions expire automatically, and every movement is written to the bank transaction log.

The Tax Controller was retired in 7.1.0. Install **Admin Terminal** on that computer instead; running the old program now says so.

### Border Controller

- Use an Advanced Computer with a wireless or Ender modem.
- During setup, sign into the Foxy Account that owns the destination territory and choose that territory.
- Travelers enter the eight-character code shown in MyID → Visas.
- The operator explicitly chooses **Enter Territory** or **Exit Territory** before entering the travel code. Every approved action powers the back redstone side for exactly five seconds.
- A temporary visa permits one entry and its matching exit. That exit closes the visit and locks the visa even when approved days remain.
- Citizenship and Free Roam remain reusable, but a server-enforced cooldown prevents rapid code sharing. Changing territory or closing a configured controller requires the territory owner's PIN.

## First-run flow

### Bank

Start it once and leave it running. The touch dashboard shows account and transaction counts, recent activity, manual save, and safe shutdown.

### Pocket

Complete the animated introduction, choose **Set Up New Account**, set a four-digit PIN, and choose how the Pocket should address you. The resulting identity is called a **Foxy Account**, and new accounts receive the configured starting balance.

### MyID: countries and visas

Open **MyID → Countries** to create a country. Its owner automatically receives citizenship and can grant permanent citizenship to other Foxy Accounts, review visa applications, and allow citizens of selected territories permanent Free Roam into the destination.

Open **MyID → Visas** to see citizenship and visa codes, active visits and departure days, Free Roam access, application history, or request a 1–30 in-game-day visa. The destination country's owner approves or declines each request in MyID → Countries. Asking for a visa needs a confirmed Digital ID.

### A till

Install the Pocket, sign in as the owner, install **Company** from the App Browser, and start a company. Add products on **Products**, star the ones you sell most, then **Sell**. Attach a monitor for the customer whenever you like.

### Events

Sign in, create the event — tickets on sale **now**, or **later** at a day and time, and how many each person may buy — then add one or more ticket types. Customers see active future events in their Pocket straight away, with when they go on sale. For a presale, open the event and tap **PRESALE**: set when it opens, then **+ INVITE** people by FoxMail address or by name.

### CCG

Install **CCG Bet Console**, attach the monitor and modem, and select a game. Players fund **Bet Wallet** from their Pocket, open the PIN-gated **Bet** app, enter the lobby code and a player name, then choose their wager. The big-screen operator starts the round when everyone shows **READY**.

## Important behavior

- Payment codes expire after five minutes and can be cancelled by the cashier.
- Purchases above the configured PIN-free limit require the customer's PIN.
- Money sent inside Messages or Urgent Contact goes through the Bank's one transfer path, so the server-calculated 10% fee, the `$2,000` daily limit and the transaction log are identical everywhere. Foxy Cash is the only way to start one from the phone since 9.4, and it reaches friends only.
- You can only message or reach someone who is already a friend.
- A conversation keeps its most recent 60 messages.
- The Pocket locks after 60 seconds of inactivity and begins requiring a PIN after 120 seconds.
- Ticket purchases always require a PIN and are limited to the configured quantity per purchase.
- A ticket code becomes invalid immediately after **Mark Used + Admit**.
- Subscription codes are confirmed with the customer's PIN inside the Pocket. The first charge settles immediately; later charges run once per in-game day. Failed charges notify the customer and retry the next day.
- Sessions are kept in memory and expire after 12 hours by default. Restarting the Bank Server signs clients out without changing their data.
- The Pocket stores only the last account name locally, never the PIN and never a session token.
- A Pocket asks before it installs a release, and lists what changed. Every unattended role still updates itself.
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

**The Bank will not start: out of space**

This is what 11.2 fixes, but a Bank that is already full has to be given room once before it can install it. At the Bank's shell (hold Ctrl+T if it is stuck restarting):

```
delete /updates
reboot
```

`/updates` is only a cache of other computers' programs, and nothing needs it any more. On the way back up Easy Deployment replaces the Bank's program with 11.2 before it starts, and 11.2 moves the history to the Vault and keeps the disk clear from then on. If the Bank still cannot start, run the rescue on it:

```
wget run https://raw.githubusercontent.com/totallyrat/computercraftbank/main/tools/bank_rescue.lua
```

It deletes what can be fetched again, and only if that is not enough trims transaction history and notifications to the newest thirty and twenty per account — what 11.2 keeps anyway. Balances and everything else that is money are never touched. Then `reboot`.

- A Core's installation is about 312 KiB before its data, against ComputerCraft's default 1000 KiB per computer. An update briefly needs room for a second copy, so it peaks at about 623 KiB. `tools/build_release_manifest.js` refuses to publish a release that would not leave 150 KiB for data on any computer.
- If a save ever does not fit, the Bank gives up history still waiting for the Vault rather than money, and says so on the dashboard.
- ComputerCraft's disk limit is a server setting: `computer_space_limit` in the CC:Tweaked server config. A busy server can raise it; nothing here depends on the default.

**Customer screen is blank**

- It must be an Advanced Monitor, not a basic monitor.
- At the till, **More → Customer screens** after attaching it. Every colour monitor on the computer is used.
- The till draws on it while Sell is open; leave the till and it holds what it last showed.

**Events show the wrong countdown**

- Event scheduling intentionally uses the Minecraft in-game day and time, not real-world time.
- Check the current day shown in the event creation flow.

**A Pocket fails to start with a `nil value` error**

- Its program and the shared `lib/` are from different releases. Run Easy Deployment on that computer and reinstall the role; it downloads the program and every library together.
- Reinstalling from Easy Deployment downloads the program and every library from the same release.

**A friend cannot be messaged or reached**

- Messages and Urgent Contact are friends-only. Add them under **Friends** first.
- Urgent Contact refuses a second call while either person already has one open.

**CCG lobby will not start**

- Every listed player must show **READY** after selecting a pick and reserving a wager.
- Survivor requires at least two ready players.
- Confirm the Pocket has available Bet Wallet funds, not only funds still in Holding.
- In Auto Mode the countdown only begins once every joined player is ready; a single player still picking holds the round.

**Auto Mode will not turn off**

- That is the design. **STOP AUTO** needs the exact code typed when the mode was started.
- If the code is lost, stop the CCG program from the computer's terminal and delete `ccg_device.dat` beside it. The console re-registers on the next start.

## Version

FoxyOS 14 — release `14.0.0`.
