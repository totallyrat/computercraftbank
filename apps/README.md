# PUMPE apps

Apps in this folder are written here and published from inside the game. They
are **not** part of a release: nothing here is in `release_manifest.json`, and
the App Server does not ship them. To put one on your network:

1. Copy the file onto a Service Kiosk, into the `/apps/` folder that Dev Mode
   creates.
2. Open **POS Settings → DEV MODE**, tap the file, give it a name and a
   description, and launch it.
3. It appears in every PUMPE's **App Browser**.

| App | What it is |
| --- | --- |
| `yap.lua` | A text social network: posts, likes, replies. Friends float to the top of the feed. |
| `yapchat.lua` | Private messages between Foxy friends, behind your PIN, gone a day after you read them. Uses all three of the APIs below. |

## Writing one

An app is one file that returns one function. The PUMPE calls it with an
`api` table and nothing else — no session token, no device file, no access to
another app's data.

```lua
-- PUMPE APP: Notes
return function(api)
    local ui, util, target = api.ui, api.util, api.target
    ui.clear(target)
    ui.header(target, "Notes", api.account().name, util.formatClock())
    local scene = ui.scene(target)
    scene:button("back", 1, 20, 8, 1, "< Home", { background = ui.theme.panel })
    scene:wait()
end
```

### What `api` gives you

| Field | What it does |
| --- | --- |
| `api.ui`, `api.util`, `api.colors` | The same libraries the phone draws itself with |
| `api.target` | The screen to draw on |
| `api.config` | The network's configuration |
| `api.money(value)` | Formats an amount in the network's currency |
| `api.account()` | The signed-in account, as the phone sees it |
| `api.refresh()` | Re-reads that account from the Bank |
| `api.running()` | False once the PUMPE is shutting down — check it in every loop |
| `api.request(action, payload, silent)` | A Bank request, made as the signed-in account |
| `api.login(spec)` | FoxyLogin. See below |
| `api.pin(reason)` | Ask for the owner's PIN. See **The Pin API** |
| `api.notifications` | `.ask()`, `.allowed()`, `.send(spec)`. See **The Notification API** |
| `api.call(spec)` | Raise the PUMPE's Urgent Contact ring. See **The Urgent Contact API** |
| `api.app_id` | This app's id, assigned when it was published |

`api.request` stamps your app id onto every call it makes, so you never pass
`app_id` yourself — and cannot pass somebody else's.

Return from the function to go back to the Home Screen. If your app errors,
the phone catches it, says so, and hands the user back their PUMPE.

## FoxyLogin

One line, and the phone does the rest:

```lua
local me = api.login({ name = "Yap", scopes = { "friends" } })
if not me then return end          -- they said no
```

The phone slides up a Foxy sheet listing exactly what your app will see and
waits for a tap. Approve once and it never asks again; **Settings → Connected
Apps** is where that can be taken back.

`api.login` returns a profile, or `nil` if it was refused:

| Scope | Adds to the profile |
| --- | --- |
| *(always)* | `account_id`, `name`, `scopes` |
| `number` | `personal_number` |
| `friends` | `friends`, a list of `{ account_id, name }` |
| `balance` | `balance` |

The app id comes from the install, not from your code, so nothing can ask for
another app's grant.

## Keeping data

Signed-in apps get a small store on the Bank. Records are owned by whoever
wrote them; reactions are the one thing anybody can add to somebody else's.

```lua
-- write
api.request("APP_DATA_PUT", { collection = "posts", data = { body = text } })

-- read, newest first
local listed = api.request("APP_DATA_LIST", { collection = "posts", limit = 40 })

-- replies to one record
api.request("APP_DATA_LIST", { collection = "comments", parent = post.id })

-- like and unlike
api.request("APP_DATA_REACT", { collection = "posts", id = post.id, on = true })

-- only your own
api.request("APP_DATA_DELETE", { collection = "posts", id = post.id })
```

Each record carries `id`, `data`, `author_id`, `author_name`, `created_day`,
`created_time`, `reactions` (a count), `reacted` (did you) and `mine`.

Limits live in `config.lua`: `max_app_records` per collection,
`max_app_record_bytes` per record, `max_app_reactions` per record. Oldest
records fall off the end when a collection is full. This is a notice board,
not a database.

### Private records, and ones that go away

A record written with an `audience` is visible to its author and to the
people named in it, and to nobody else — not even by asking for it by id.
One written with `expire_after_days` disappears that many days after
somebody **reads** it, on every phone at once. A record nobody opened is
still there tomorrow.

```lua
api.request("APP_DATA_PUT", {
    collection = thread,
    data = { body = text },
    audience = { me.account_id, friend.account_id },  -- these two, nobody else
    expire_after_days = 1,                            -- a day after it is read
})

-- Reading is what starts the clock. Your own records do not count.
api.request("APP_DATA_READ", { collection = thread, ids = { id1, id2 } })
```

Such a record also carries `private`, `read` (have you), `seen` (has anybody)
and `expires_day`.

## The Pin API

For anything the owner would not want a passer-by to read:

```lua
if not api.pin("Unlock Yap Chat") then return end
```

The phone collects the PIN and checks it with the Bank. Your app is handed
`true` or `false` and never sees the PIN itself, so it cannot store or replay
one. Five wrong guesses and the API shuts for a couple of minutes — the app
holding it is the thing being defended against.

## The Notification API

Interrupting somebody is a separate question from signing them in, so it is
asked separately:

```lua
api.notifications.ask()        -- puts the question up once, remembers the answer
api.notifications.allowed()    -- true if they said yes, without asking again

api.notifications.send({
    account_id = friend.account_id,   -- omit to notify the owner
    title = me.name,
    body = "you there?",
    style = "fullscreen",             -- a request, not a decision
})
```

A refusal is remembered too: an app cannot put the question up again every
time it starts. The owner can revisit it in **Settings → App Settings**,
where every app that has ever asked is listed.

**Fullscreen is the owner's switch, not yours.** `style = "fullscreen"`
arrives as a banner unless they turned fullscreen on for your app in App
Settings, and turning notifications off takes fullscreen with it. Sending
across accounts only works between friends, and there is a daily budget per
app per sender.

## The Urgent Contact API

The same fullscreen ring the PUMPE raises for Urgent Contact, from your app:

```lua
api.call({ account_id = friend.account_id, name = friend.name })
```

Their screen says which app is calling and who is. Both labels come from the
install and the Bank rather than from your code, so an app cannot pass its
call off as the PUMPE's own.

## Fitting the screen

A PUMPE is **26x20 characters**. Every draw is bounds-checked in the host
tests, so a label that runs off the edge is a failure rather than a smudge.
Use `ui.truncate`, `ui.wrap` and `ui.wrappedText`, and measure against the
real width rather than assuming 26 — an app can also run on a wider screen.
