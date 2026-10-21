# FoxyOS

**A whole digital world for ComputerCraft: Tweaked.** FoxyOS turns a Minecraft server into a working economy and social network: a central bank, a phone in everybody's pocket, shops that deliver, events with ticket queues, countries with visas and border gates, casinos, live radio, cloud storage, a web of player-made websites, and an app store anybody can publish to.

Every computer in it runs FoxyOS. The phone is the **Pocket**; on a standing computer it becomes the **Pocket Desktop**. Everything is touch-first, and a keyboard works too.

> **FoxyOS 18** brings **FoxyMusic+** and **Offline Listening**, a Music Server that keeps playing when the Bank is down, the **Pocket Desktop**, and a new way to set up a Pocket, with a guide that runs on the Home Screen itself. **18.1** adds **Trivia** to the CCG Casino, all or nothing, and the casino table's controls on its own computer. See [`CHANGELOG.md`](CHANGELOG.md).

## Contents

- [Quick start](#quick-start)
- [What runs where](#what-runs-where)
- [The Pocket](#the-pocket)
- [The Pocket Desktop](#the-pocket-desktop)
- [Money](#money)
- [Music and radio](#music-and-radio)
- [Selling: companies, tills and the Shop](#selling-companies-tills-and-the-shop)
- [Events and tickets](#events-and-tickets)
- [Countries, visas and borders](#countries-visas-and-borders)
- [CCG: casinos and Home Mode](#ccg-casinos-and-home-mode)
- [The web](#the-web)
- [Building apps](#building-apps)
- [Running the network](#running-the-network)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [The repository](#the-repository)

---

## Quick start

Every computer is set up the same way: put **Easy Deployment** on it and pick what it should be.

```
wget https://raw.githubusercontent.com/totallyrat/computercraftbank/main/startup.lua startup.lua
startup
```

ComputerCraft's HTTP must be allowed to reach `raw.githubusercontent.com`. Then build the world in this order:

1. **The Bank.** On an empty world, Easy Deployment offers **GET THE BANK SERVER** (operator code `4040`). Give it a second Advanced Computer as its **Vault**, joined by wired modems and networking cable, and pair them from the Bank's screen. Change the government key from the **Admin Terminal** before anyone else plays.
2. **The services.** An **App Server** (apps and downloads), five or more **Cloud Servers** (FoxyCloud files and songs), and four or more **GPS Anchors** (anything that finds a person needs them).
3. **Pockets** for everybody. A new Pocket walks its owner through setting up.
4. **Anything else you want:** a Music Server and Music Players, a CCG Server and casino tables, an Internet Server, Event Kiosks, Border Controllers, Delivery Terminals, an Admin Terminal for the government.

Everything updates itself from this repository from then on. When a release says to update in an order, the Bank always goes first.

## What runs where

**The backbone**

| Program | Hardware | What it does |
| --- | --- | --- |
| Bank Server (`bank_server.lua`) | Advanced Computer + wireless/Ender modem + wired modem | The **Core**: balances, sessions, PINs, the ledger, tax, escrow, pay codes, companies |
| Bank Vault (`bank_vault.lua`) | Advanced Computer + wired modem | The **Vault**: friends and chats, travel, events, app records, orders, FoxMail, history and notifications |
| App Server (`app_server.lua`) | Advanced Computer + modem | Hosts every Pocket app and game, and serves every download |
| Cloud Server (`cloud_server.lua`) | Computer + modem | Holds pieces of FoxyCloud files and of the Music Library. Run five or more |
| GPS Anchor (`gps_anchor.lua`) | Computer + wireless modem | Tells every device where it is. Run four or more |
| Admin Terminal (`admin_terminal.lua`) | Advanced Computer + modem | The government: tax, approvals, balances, bans, announcements |

**What people use**

| Program | Hardware | What it does |
| --- | --- | --- |
| Pocket (`pumpe.lua`) | Advanced Pocket Computer + wireless modem, or an Advanced Computer for the Pocket Desktop | The phone, and on a computer the desktop and the shop till |
| Music Server (`music_server.lua`) | Advanced Computer + modem | The Music Library and the radio stations |
| Music Player (`music_player.lua`) | Advanced Computer + modem + speakers (a monitor if you like) | Plays the library and the radios for the person signed in |
| CCG Server (`ccg_server.lua`) | Advanced Computer + modem | Deals every casino table's games |
| CCG Casino (`ccg_casino.lua`) | Advanced Computer + Ender modem + Advanced Monitor + speakers | A casino table a company runs |
| CCG Home (`ccg_home.lua`) | Advanced Computer + Ender modem + Advanced Monitor | Free arcade games at home, with a Pocket as the controller |
| Event Kiosk (`event_kiosk.lua`) | Advanced Computer + modem | Creates events and admits people at the door |
| Border Controller (`border_controller.lua`) | Advanced Computer + modem | Checks travel papers and opens a redstone gate |
| Delivery Terminal (`delivery_terminal.lua`) | Advanced Computer or Pocket Computer + modem; chests for a pickup point | A company's order board, or a self-service pickup point |
| Internet Server (`internet_server.lua`) | Advanced Computer + modem | Holds and serves every website |
| 3rd Party Bank Server (`bank_app_server.lua`) | Advanced Computer + modem | Hosts somebody else's bank |

**Apps the Pocket gets from the App Server.** Foxy (the bank), FoxMail, Yap!, FoxyCloud and Music arrive by themselves. Company, Shop, INVT, Internet, Website Crafter, BuckApp and Revolution are in the App Browser.

Retired: the **Service Kiosk** became the Company app's till, the **Tax Controller** became the Admin Terminal, and the original **CCG** split into CCG Casino and CCG Home. Each one says so when it starts and offers the way forward.

---

## The Pocket

A Pocket behaves like a phone. It belongs to one Foxy Account, opens on that account's lock screen, and asks only for the PIN. **Remove account** in Settings is how a Pocket changes hands.

### Setting up, and the guide

A new Pocket is set up a step at a time, with dots along the bottom:

1. **Hello**, in a few languages, over the Pocket's name.
2. **Get started** makes a new Foxy Account (a username and a PIN), or **I have an account** signs in.
3. **Your colour.** Every device has a main colour, orange out of the box.
4. **Your number**: a free phone number, or later in Messages.
5. **You're all set.**

Then the Home Screen shows you round itself. A yellow bubble lights up one thing at a time: turning a page, the notification centre, search, Foxy, the dock and locking. It points at each one and waits for you to tap exactly that thing. **Skip** ends the guide, and **Settings → Account → How Pocket Works** starts it again.

### The Home Screen

- **Apps in a grid**, each with an icon: 8×6 pixels in a light grey frame, drawn by its author in **Icon Creator**. Unread counts are badges in the corner.
- **The dock** under every page: a search bar, then up to three favourites. An empty slot opens the picker.
- **Search** finds apps, the things apps can do (Foxy Cash, My Tickets…) and every setting, suggesting as you type. Anything not installed is one tap away in the App Browser.
- **The notification centre** is the last page. A `!` in the page dots means something new.
- **Every app opens its own way.** A motion in the app's colour grows from its icon: Friends ripples, Tickets closes on a perforation, Settings shuts like a shutter, and so on.
- **A new download pops up.** Getting an app from the App Browser takes you straight to the page where it landed, and its icon pops into place.
- **Banners.** Notices open across the middle of the screen, green when something worked and red when it didn't. Calls and verification codes arrive at the top with **Accept**/**Decline** or **Paste**, over whatever is open, and that app keeps working underneath.

### Built in

| App | What it holds |
| --- | --- |
| **Friends** | Your friends, requests, and **Urgent Contact**: a live call with a typed transcript, money inside the call, and a transcript saved only if both people agree |
| **Messages** | Chats and groups (up to eight). Request or send money in a bubble. The **Phone** tab has your number |
| **Tickets** | Events and the tickets you hold |
| **MyID** | Your Digital ID, visas, the countries you run, and tax |
| **CCG** | Casino tables, My Casino, Home Mode and scores |
| **Subs** | Every subscription, kiosk or plan, in one list |
| **Reminders** and **Quick** | Reminders in in-game hours; QuickActions string app actions together, on demand or daily |
| **Apps** | The App Browser |
| **Settings** | Phone, Apps and Account: colour, network, updates, storage, the Pocket Desktop, app permissions, Dev Mode, Beta Updates |

**Phone numbers.** Sending a message or making a call needs a number of your own; reading never does. Call or text any number, friend or not. A company has a number too, and so does every radio station. A day allows **40 messages and 10 calls**, more with FoxyCloud+.

### Locking, and going offline

After a minute untouched the Pocket shows its lock screen. Before two minutes a tap opens it; after that it wants the PIN, which the Bank checks. **Settings → Network** takes the Pocket off the network without signing you out: everything already on it keeps working, the header says **Offline**, and anything that needs a server says so.

### Apps by Foxy

- **Foxy**: your bank. Your card and balance, extra accounts (Savings, Rent…), **Foxy Cash** to friends, **Security** (parcels waiting, *Is this you?* questions), and moving money to other banks.
- **FoxMail**: an address at `foxy.com` for everybody, company domains with up to five addresses, and mail from apps and organisers.
- **Yap!**: a feed of 140-character posts, private chats behind your PIN that vanish a day after they're read, and **Yap Map**, where friends in GPS range are listed with their coordinates.
- **FoxyCloud**: your Foxy Account, your plan, and your files on every device: notes, text, MIDI, songs, anything dropped on the screen. Share any file with a six-letter code.
- **Music**: the remote for your Music Players, uploads, and FoxyMusic+.
- **Company**, **Shop**, **INVT**, **Internet** and **Website Crafter** are covered in their own sections below.

---

## The Pocket Desktop

The Pocket on a standing computer, built in, with nothing extra to download. It runs on an Advanced Computer (never a pocket computer) whose screen is at least 39 columns wide. A Pocket on a screen that size asks once when it starts. **Settings → Phone → Pocket Desktop** switches it on and off, and **Start → Phone layout** goes back to the phone's Home Screen.

- **The desktop** shows who is signed in, their balance, and every app as an icon.
- **Every app opens in a window of its own** and keeps running when another is in front: a window behind still ticks, polls and plays. Tap a window to bring it forward and drag it by its title. **_** minimises, **o** fills the screen, and **x** closes. **Ctrl+T** closes the window in front.
- **Tabs down a sidebar.** An app with tabs shows all of them down the left of its window, and the page gets the rows the bottom bar used.
- **The taskbar**: **Start** (Search, Notifications, Settings, Lock, Phone layout, Close Pocket), a button for each window, the music, and the clock.
- **Music right there.** With a speaker beside the computer, the desktop is one of your Music Players, called *Your Name's Desktop*, and plays through it. Without one, the taskbar shows and controls your Music Player.
- **It locks over everything**, and banners and calls arrive in the window in front.
- **Till Mode** runs only here, filling the whole screen.

---

## Money

FoxyOS uses fictional currency. The Bank makes money only for new accounts (a starting balance), giveaway prizes, and what the government adds.

### A Foxy Account

**Foxy** is the bank. Your main balance, extra accounts, activity, cash-outs and your **Account ID** are all there. **Foxy Cash** sends money to a friend instantly for a 2% fee paid by the sender, with no daily ceiling, because only friends can be reached.

### Paying in person: Foxy Pay

A till offers the bill to **whoever is standing closest**. Their Pocket shows the merchant, the amount and the distance, and they pay with their PIN. **Not mine** passes it to the next nearest person. A company's owner is never offered their own bill.

**Portable Mode** turns it round for a till carried to the customer. **Find** asks the nearest Pocket *are you the customer?* first, then the finished basket goes to that same Pocket to pay.

Foxy Pay, ticket scanning, border checks and everything else that finds a person need **GPS Anchors**: four or more computers with exact coordinates (F3), spread out, at least one at a different height. Opening a ticket or a travel document is what makes a Pocket findable. That stops twenty seconds after the screen closes.

### Plans

**The free plan**: 100 KB of FoxyCloud, 40 messages and 10 calls a day, 10 songs from the Music Library a day, 2 uploads.

| | FoxyMusic+ | FoxyCloud+ Tier 1 | FoxyCloud+ Tier 2 |
| --- | --- | --- | --- |
| Every 5 days | 100 | 500 | 1000 |
| Songs and uploads | unlimited | unlimited | unlimited |
| Offline Listening | ✓ | – | – |
| FoxyCloud storage | – | 25 MB | 50 MB |
| Messages / calls a day | – | 500 / 100 | unlimited |
| No Foxy Cash fee, early tickets, music on your casino tables | – | ✓ | ✓ |

FoxyMusic+ is joined in the Music app and FoxyCloud+ in FoxyCloud, both with your PIN, and both appear in **Subs** beside everything else. A cancelled plan lasts until the day you paid for. Moving up a FoxyCloud+ tier costs the difference and keeps your renewal day; moving down happens when it renews.

### Subscriptions, codes and limits

- A shop can sell daily or every-few-days subscriptions at its till. You confirm one with your PIN, and **Subs** lists and cancels it.
- **Pay codes** are for people who bank somewhere other than Foxy. A Foxy Account pays with Foxy Pay instead; codes still work for cashing out and starting a subscription.
- A tax demand blocks your own spending until it is paid. You can still be paid.

### Other banks

A **3rd Party Bank Server** hosts any app that declares itself a bank (`-- PUMPE BANK APP: Name`), with its own logins, its own clearing time and its own fee. **BuckApp** and **Revolution** (no fees, one hour to clear, proximity pay) ship with the App Server.

Every account at every bank has a sixteen-digit **Account ID**; the first four digits name the bank. **Bank Transfer** moves everything you have to another Account ID and closes the account behind it. **Bring money in** and **Bring it back here** let one bank app ask the Pocket to move money from another, behind the Pocket's own PIN prompt. A transfer whose answer never arrived is settled later, never guessed at.

### The government

The **Admin Terminal** (operator code, then the government key) approves new accounts if you want approval, adds and removes money, bans, issues **tax demands** (paid in MyID with the holder's own PIN), confirms Digital IDs, and sends announcements: a banner, a full screen, or a text thread with one person. Every movement is logged.

---

## Music and radio

Songs are **DFPWM1a** (`.dfpwm`, 48 kHz, 6000 bytes a second). Their pieces live on the Cloud Servers and are fetched a step ahead of the speaker.

### The Music Server

One per world, registered with the operator code. Its screen has:

- **Library**: every track, by kind: **Song**, **Host** (talk between songs), **Ad** and **Giveaway** (a clip that starts a giveaway). Drop `.dfpwm` files on its screen or **IMPORT** them from a disk, with a title, an artist and the name to credit.
- **Radios**: stations with a name, a colour and their own phone number. Choose the songs in rotation, the hosts, ads and giveaway clips, and the dials: how chatty, how many ads, how often a giveaway, specials on or off. **GIVEAWAY NOW**, **NON-STOP NOW** and **SKIP** act straight away.
- **Status**: every Music Player and what it is playing.

### Radios are live

Everybody listening hears the same moment. After each song comes a break: a host, a giveaway now and then, or ads every few songs. A host can bring in a special: **20 MINUTE NON-STOP**, a **DOUBLE PLAY** by one artist, or a **THROWBACK** to the oldest songs in rotation. Radios are always free.

**Giveaways.** When a giveaway clip plays, Now Playing shows **GIVEAWAY! Call 482-7316** with a countdown. A call costs 50, and every call is another entry. When the lines close, one caller wins a random 100 to 500, paid by the Bank.

### Music Players and the Music app

A **Music Player** is a computer with speakers that you sign in to once with your Foxy name and PIN. Its screen has **Now Playing**, **Library**, **Radio** and **Upload** (drop a song on the screen or pick one from a disk), and a monitor beside it shows what's on from across the room.

The **Music** app on every Pocket is the remote: pick a player, then play, queue, tune in, pause, skip and set the volume. It uploads songs from the Pocket, from its screen or from FoxyCloud, and its **Upload → FoxyMusic+** joins the plan. A library song counts against your day when it starts; radios never count.

### Offline Listening

With **FoxyMusic+**, tap **v** beside a song in a Music Player's Library to keep it on that player (16 MB a player; **\*** removes it). A kept song plays from the player's own disk. While the Music Server is off, the Library shows only what is kept and plays it from the player's own screen. Kept songs keep playing for 10 in-game days after FoxyMusic+ was last confirmed. They are deleted when the plan ends or the player signs out.

### When the Bank is down

The Music Server stores its own songs on the Cloud Servers and hands out its own tickets to read them. It remembers who signed in and what their plan allows. So with the Bank unreachable, radios play on, library songs play and count, uploads go in, and a Pocket that signed in within 12 hours is still believed. Players and Pockets remember where the Music Server is.

Only **giveaways** wait for the Bank, because the Bank pays the prize. The Bank is also needed to register the Music Server, for a player's first sign-in, and for unlocking a Pocket with its PIN.

---

## Selling: companies, tills and the Shop

### Companies

**Company** (App Browser) is where an owner starts companies and runs them. A company has:

- **Sell**: the till.
- **Products**: what every till and the online store sell.
- **Store**: the online store, its pickup points and its phone number.
- **Deals**: a store-wide sale, free delivery, and discount codes.

**Delivery Mode** lists every parcel out for delivery across your companies.

### The till

**Sell** works on a Pocket for selling on the spot: product tiles under **Favs**, **Items** and **Daily**, the bag along the bottom, and **Charge** for Foxy Pay or a pay code. **More** verifies a MyID, charges a custom amount, and finds customer screens.

On a standing computer it spreads out: the receipt down the left and the products on the right. Every colour **Advanced Monitor** attached becomes a **customer screen** showing the welcome, the order as it's rung up, *check your Pocket*, and **PAID** with a thank-you by name.

**Till Mode** is the till on its own, for a counter, and needs the **Pocket Desktop**. It fills the whole screen, never locks, ignores Ctrl+T, and asks for the owner's PIN to leave, so a customer can't walk off with the computer behind it.

### The Shop

Open a store from Company → **Store**: a colour, a tagline, which products are online, home delivery (with a fee) and/or pickup. Then:

- **Buying.** The **Shop** app lists every open store. At checkout choose where (a saved place, *where I am now*, coordinates or a pickup point), see the Bank's price with any sale, code and delivery, then pay with Foxy or another bank's Account ID and PIN.
- **Tracking.** The **Delivery** tab follows each order live, and every step is also a notification.
- **Cancelling and returns.** An order can be cancelled until it confirms two in-game hours later (the Bank holds the money until then, if the store allows cancelling). It can be returned for at least five in-game days.
- **name.shop.** A store can have a web address that opens the store itself, from the Internet app.

### Delivery Terminals and pickup points

A **Delivery Terminal** linked to a company shows every order. Tap one to move it through its stages (or type your own), and **DONE** tells the buyer it arrived.

It can also run a **pickup point**: one chest customers open, plus any number of **lockers** behind a wall, all on wired modems and networking cable. Couriers enter a parcel's delivery code to stock it. Buyers enter their six-digit code, confirm **It's me** on their Pocket, and the parcel comes out. **Me** finds your orders by name, and **Store** sells what is in the lockers on the spot. In Pickup mode the keyboard is the customer's: Ctrl+T does nothing, and a reboot comes back to the counter.

---

## Events and tickets

Tickets go on sale the way they do in real life:

- **A release time.** Before it, the event counts down and offers **Join the waiting room**.
- **A fair queue.** Everyone in the waiting room when sales open is shuffled, so arriving early doesn't help. A few people at a time get two minutes to choose, and the Pocket stays awake while it waits.
- **Presales** for people the organiser invites by FoxMail or by name, before the general sale.
- **A limit per person**, and **sold out** closes the queue.

Organisers use the **Event Kiosk**: create events and ticket types, set the sale and presale, and admit people at the door by code or with **PROXIMITY SCAN**.

**INVT** (App Browser) is for small things like a party or a quiz night: one price (free is fine), a number of spots, public or private, no queue. The host invites friends or FoxMail addresses, checks guests in, and can cancel with full refunds.

---

## Countries, visas and borders

- **MyID → ID**: apply for a **Digital ID**, confirmed by the government at the Admin Terminal. Your **MyID Code** (`MY-7K2M-9QPA`) can be read out loud and checked by anyone with the **MyID Verifier**, at tills and Event Kiosks.
- **MyID → Countries**: create a country. Its owner grants citizenship, reviews visa applications, and allows citizens of other countries **Free Roam**.
- **MyID → Visas**: your citizenships and visas, and applications for a 1–30 in-game-day visa. A visa needs a confirmed Digital ID.
- **Border Controllers** check a traveller's eight-character code, or with **PROXIMITY VISA** whoever is nearest with papers on screen, and power a redstone gate. A visa allows one entry and its matching exit. Citizenship and Free Roam can be reused, with a cooldown against code sharing.

---

## CCG: casinos and Home Mode

**CCG Casino.** A table run by one of your companies, set up on the computer's own screen. It plays **Roulette**, **Blackjack**, **Heads or Tails**, **Poker** (Hold'em against the dealer) and **Trivia**, dealt by the **CCG Server**.

- **Playing.** Players sit down from the CCG app's **Bet** tab with the table's code, using their PIN.
- **Running it.** **My Casino** lets the owner run the table on **Auto** or deal it themselves, and move casino money in and out. The table's own computer has the same controls (not the money) behind the owner's PIN, and locks after a minute untouched.
- **Trivia** is all or nothing. Your first answer is your stake; each right answer makes the pot 1.5x and a wrong one loses it. **TAKE** it between questions. Ten in a row is paid out for you. **Trivia mode** skips the wheel and asks question after question, on one topic or all of them. Questions come from [Open Trivia DB](https://opentdb.com) when the CCG Server has HTTP, from 108 built-in ones when it does not, and from your company's own: write them in **My Casino → TRIVIA → Our questions**, or drop a `.txt` on the table's computer with one per line, `Question | right | wrong | wrong | wrong`, and `# Topic` lines between.
- **Music.** **MIDI** files, or **DFPWM** from the Music Library (a song on repeat or a live radio, with FoxyCloud+).
- **The money stays at the Bank.** Wagers are held there, and winnings sit in **Holding** for a day before reaching the **Bet Wallet**.
- **Losses.** A table that pays out more than it has borrows from the Bank, up to a limit, and pays the Bank back before it shows profit.

**CCG Home** needs no server and no Bank. Press **HOME MODE**, type the six-digit code into **CCG → Home** on your Pocket, and the Pocket becomes the controller. It has **Snake**, **Meteors**, **Simon** and **2048**, plus games from the **Game Browser** (the App Server ships **Brick Breaker**). Games are published from Dev Mode, and `brickbreaker.lua` shows how to write one.

---

## The web

Three separate pieces:

- **Website Crafter** (a Pocket app): you write a site as Lua, from templates, and **Check** compiles it.
- **The Bank Vault** keeps the register of names, two per account. A new site opens two in-game hours after you reserve its name.
- **The Internet Server** holds the pages.

The **Internet** app opens a site by name. **A page is a visit**: the Pocket fetches it, runs it in a sandbox with no files, network, peripherals or `load`, and deletes it afterwards. A page can ask who you are (Foxy sign-in, name only) and can keep records on the Bank, but it can never see your money. Publishing goes through a one-shot ticket from the Bank, so an Internet Server can be run by anybody without being trusted.

---

## Building apps

An app is one Lua file returning one function. It gets an `api` table and nothing else: it never sees the session token, the PIN or the device file.

```lua
-- PUMPE APP: Notes
-- PUMPE APP ACTION: new | New note | Write something down
return function(api)
    -- api.ui, api.util, api.target, api.config, api.colors
    -- api.request(action, payload, silent)   as the signed-in account
    -- api.account(), api.refresh(), api.money(value), api.running()
    -- api.action()                            the action it was opened at
end
```

**Publishing.** **Settings → Apps → Dev Mode → Become a developer**, put the file in `/apps/` on that computer, then tap it in Dev Mode. It goes to every Pocket's App Browser with an icon you paint in **Icon Creator**. Republishing updates it, and Pockets fetch updates by themselves. Choose **Game** instead and it goes to the CCG Game Browser.

**What an app can ask for**, with the owner always having the last word:

| Call | What it does |
| --- | --- |
| `api.login{ name, scopes }` | Foxy sign-in: one consent sheet, then a profile with only the fields granted (`name`, `number`, `friends`, `balance`) |
| `api.pin(reason)` | The Pocket's own PIN pad; returns true or false |
| `api.notifications.ask()` / `.send{}` | Banners, asked for once. Fullscreen only if the owner turns it on in App Settings |
| `api.vercode.ask(title)` | A six-digit code sent to Messages from the app's publisher, with **Paste** |
| `api.call{}` | The Pocket's Urgent Contact ring |
| `api.purchase{}` | In-app purchases, one-off or subscription. The publisher is paid, 30% goes to the government, and the Bank keeps the record |
| `api.mail.send{}` | Mail from an address on the publisher's company domain |
| `api.save()` / `api.load()` | Up to 8 KB on this Pocket, deleted with the app |
| `api.screens()` | Customer monitors on a standing computer |
| `api.desktop.kiosk(on)` | On the Pocket Desktop, the whole screen until it lets go |

**Layout.** Use `ui.runTabs{}` and `ui.tabBar()` for an app made of tabs: a floating bar along the bottom on a Pocket, a sidebar on the Pocket Desktop, automatically. **Settings → App Settings** lists every permission an app has asked for. `apps/README.md` has the full contract.

---

## Running the network

### The Bank: Core and Vault

A Bank is two computers joined by a **wired modem** and networking cable. Start both and pair from the pairing screen; wireless pairing is refused on purpose. The split is by what a thing is:

- **The Core** holds anything where a mistake means money is wrong: balances, sessions, PINs, the ledger, tax, escrow, pay codes, companies.
- **The Vault** holds everything that is merely *about* an account: friends and chats, travel, events and tickets, app records, Shop orders, FoxMail, and every account's history and notifications.

The Vault never touches a balance and never decides who is asking: the Core authenticates every request. A Bank with no Vault still banks. The Core updates its Vault over the cable, so both always run the same release, and **PAIR** on the Bank replaces a lost Vault.

Back up `bank_data_v5.dat` beside the Core's program: it is the economy.

### Easy Deployment

`startup.lua` sets up any computer straight from this repository, checking every file against the release manifest. The Pocket is the first choice. Type anything to search the rest (`shop`, `casino`, `music`, `web`, `pickup`…). The Bank Server and Admin Terminal need the operator code `4040`.

A computer that already has a program offers **OPEN** or **REINSTALL**. Local `config.lua` settings and data files are kept, and only the Bank ever gets the government key.

To start a program by hand: `/pumpe/installer.lua --boot <name>`. The names are `pumpe`, `bank`, `vault`, `tpbank`, `admin`, `apps`, `cloud`, `anchor`, `music`, `musicplayer`, `ccgserver`, `ccgcasino`, `ccghome`, `event`, `border`, `delivery` and `internet`.

### Updates

Every device updates itself from the public manifest, downloading only the files its own role needs. Each download is staged, checked by size and checksum, and swapped in all at once or not at all, and local settings are kept.

- **Servers and kiosks** update unattended, under the **FOXY** screen.
- **The Pocket downloads first, then asks**: the release's name, what changed, and **Install** or **Cancel & Delete**. **Settings → Updates** has Check now and Automatic.
- **Prioritize Updates** lets a full Pocket take apps off to fit a release, and puts them back afterwards.
- **Beta Updates**: any device can sign up for betas, numbered halfway to the release they precede (FoxyOS 15 Beta is 14.5). Betas have a manifest of their own under `beta/`.
- **Apps** update themselves every ten minutes on the Home Screen.

Computers in this world have 50 MB each. A Pocket's update peaks under 1 MB and the Bank Core's under 800 KiB, and the release builder refuses a release that would leave less than 150 KiB for data anywhere.

### Configuration

`config.lua` holds the world's settings. A device's own copy survives updates. Some of the useful ones:

| Setting | Default | What it is |
| --- | --- | --- |
| `currency` | `$` | The currency sign |
| `starting_balance` | 500 | A new account's money |
| `send_money_fee_rate`, `send_money_daily_limit` | 10%, 2000 | Transfers inside chats and calls |
| `foxy_cash_fee_rate` | 2% | Foxy Cash |
| `pumpe_lock_seconds`, `pumpe_pin_seconds` | 60, 120 | When a Pocket locks, and when it wants the PIN |
| `ccg_casino_credit` | 10,000 | How far an owner's casinos may borrow, together |
| `ccg_trivia_multiplier`, `ccg_trivia_max_streak` | 1.5, 10 | Trivia's pot per right answer, and the streak that pays out |
| `ccg_trivia_online` | true | Questions from Open Trivia DB when the CCG Server has HTTP |
| `ccg_console_lock_seconds` | 60 | When a CCG Casino's own screen locks |
| `session_ttl_ms` | 12 hours | How long a sign-in lasts |
| `foxymusic_plus_price`, `foxymusic_plus_days` | 100, 5 | FoxyMusic+ |
| `music_offline_bytes` | 16 MB | Offline Listening room per Music Player |
| `phone_call_price`, `giveaway_prize`, `giveaway_seconds` | 50, 100–500, 180 | Radio giveaways |
| `ticket_queue_shoppers`, `ticket_turn_ms` | 3, 2 minutes | The ticket queue |

### Hardware notes

- **Ender modems** are best for anything players reach from far away or across dimensions.
- **Monitors** for customer screens and casino tables must be colour (Advanced) ones, and they run at text scale `0.5`, from 1×1 up to a wall.
- **Event times** are in-game: event day is the in-game day number, and `1830` means 18:30.
- **The Admin Terminal**'s government key starts as `Government1234`. Change it from the terminal.

---

## Security

This is strong for a Minecraft roleplay economy, not a real bank:

- PINs are hashed with a DJB2-style hash, which is not cryptographically secure.
- The operator code `4040` is friction, not security, and Rednet traffic is not encrypted.
- Anyone with shell access to the Bank Server can change its data.

Protect the Bank's computers physically, restrict shell access, change the government key, and keep backups. Within the game, the rules are enforced at the Bank, not on the Pocket: prices, payouts, limits and permissions are worked out server-side, so editing a client changes nothing.

---

## Troubleshooting

**"Bank offline"**: check the Bank is running, every device has a modem attached, and every device uses the same `protocol` and `hostname` in `config.lua`.

**A program fails with a `nil value` error**: its program and its `lib/` files are from different releases. Reinstall it from Easy Deployment, which downloads them together.

**The Bank won't start because it's out of space**: at its shell (hold Ctrl+T), `delete /updates` and `reboot`. If it still won't start, run the rescue. It never touches balances.

```
wget run https://raw.githubusercontent.com/totallyrat/computercraftbank/main/tools/bank_rescue.lua
```

**A computer turned into a Bank after setup** (an install from before 12.0): wipe it and set it up again.

```
delete /startup.lua
delete /pumpe
wget https://raw.githubusercontent.com/totallyrat/computercraftbank/main/startup.lua startup.lua
reboot
```

**Foxy Pay, scanning or borders do nothing**: there aren't four working GPS Anchors yet.

**A customer screen is blank**: it must be an Advanced Monitor. Use **More → Customer screens** at the till after attaching it.

**Songs won't upload or play**: the Cloud Servers must be running, and updated before the Music Server.

**Till Mode won't start**: it needs the Pocket Desktop, on a computer. Turn it on in **Settings → Phone**.

**Someone can't be messaged**: Messages and Urgent Contact need a phone number to send, and Urgent Contact refuses a second call while either person is already in one.

**Event countdowns look wrong**: events use the in-game day and time, not real-world time.

---

## The repository

```text
*.lua                      every program and every Foxy app, as readable source
lib/                       shared code: ui, net, util, update, music, desktop
apps/README.md             the app contract, for app authors
dist/                      what computers actually download: the same files without comments
release_manifest.json      the current release, read by every device
beta/                      a beta's own dist/ and manifest, while there is one
tools/                     the release builder, the comment stripper, the test runner, the Bank rescue
tests/                     host-side tests
CHANGELOG.md               what changed in every release
QA_CHECKLIST.md            what to try in a real world after a release
```

**Tests.** `tools/run_tests.sh` runs every test with any Lua 5.2+ interpreter; ComputerCraft isn't needed. The tests cover:
- the Bank;
- casinos;
- FoxyCloud;
- music, radio and Offline Listening;
- the Pocket Desktop;
- the guide;
- updates and Easy Deployment;
- screen layouts at Pocket, computer and monitor sizes.

**Releasing.**
1. Edit the source and raise `version` in `config.lua`.
2. Add a `## <version>` section to the top of `CHANGELOG.md`. Its bold lead-ins become the headlines a Pocket shows.
3. Run `node tools/build_release_manifest.js` (or `--beta` for an x.5.y beta), then `tools/run_tests.sh`.
4. Commit the source, `dist/` and the manifest together. Never edit `dist/` by hand.

---

**FoxyOS 18.1**, release `18.1.0`.
