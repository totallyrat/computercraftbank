-- FoxyLogin and the app store on the Bank. An app is handed exactly what it
-- was approved for and nothing else, and it can keep records without the
-- Bank knowing what any of them mean.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, clock = 500, 20000000
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return clock end
os.getComputerID = function() return 1 end

fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return false end,
    isDir = function() return false end,
}
shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

local config = require("config")
-- Since 9.3 these routes are answered by the Vault, so the test stands up
-- both halves and lets the Core decide which one answers -- the same way the
-- server does. A stub Vault would be more forgiving than the real one.
local harness = require("bank_pair_harness")
local bank = harness.pair()
local actions = bank.actions
local state = bank.state
local vaultState = bank.vault_state

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local function register(name)
    return actions.REGISTER({ name = name, pin = "1234", gender = "Not set" })
end
local function as(who, extra)
    local payload = { session_token = who.session_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

local ana = register("Ana Fox")
local bo = register("Bo Wolf")
local cy = register("Cy Hare")
actions.FRIEND_REQUEST(as(ana, { account_id = bo.account.account_id }))
actions.FRIEND_RESPOND(as(bo, {
    account_id = ana.account.account_id, accept = true,
}))

-- FoxyLogin ------------------------------------------------------------------

assert(actions.FOXY_LOGIN_STATUS(as(ana, { app_id = "yap" })).approved == false,
    "nothing is signed in until it is approved")
rejected(actions.FOXY_LOGIN_APPROVE, "APP_REQUIRED", as(ana, { app_id = "" }))

local signedIn = actions.FOXY_LOGIN_APPROVE(as(ana, {
    app_id = "yap", app_name = "Yap", scopes = { "friends" },
})).profile
assert(signedIn.account_id == ana.account.account_id)
assert(signedIn.name == "Ana Fox", "name comes with every grant")
assert(#signedIn.friends == 1 and signedIn.friends[1].name == "Bo Wolf")
-- Only what was asked for.
assert(signedIn.balance == nil, "balance was not requested")
assert(signedIn.personal_number == nil, "the personal number was not either")

local wider = actions.FOXY_LOGIN_APPROVE(as(bo, {
    app_id = "yap", app_name = "Yap", scopes = { "balance", "number" },
})).profile
assert(wider.balance ~= nil and wider.personal_number ~= nil)
assert(wider.friends == nil, "friends were not asked for this time")

-- A scope nobody defined is dropped rather than honoured.
local odd = actions.FOXY_LOGIN_APPROVE(as(cy, {
    app_id = "yap", app_name = "Yap", scopes = { "everything", "friends" },
})).profile
assert(#odd.scopes == 2 and odd.scopes[1] == "name"
    and odd.scopes[2] == "friends", "unknown scopes are ignored")

-- Signing in again returns the same grant, which is what makes it one tap.
local repeated = actions.FOXY_LOGIN_STATUS(as(ana, { app_id = "yap" }))
assert(repeated.approved and repeated.app_name == "Yap")
assert(#repeated.scopes == 2)

local listed = actions.FOXY_LOGIN_LIST(as(ana)).apps
assert(#listed == 1 and listed[1].app_id == "yap")

-- App records ----------------------------------------------------------------

-- Signing in is what unlocks the store; an app nobody approved gets nothing.
rejected(actions.APP_DATA_LIST, "NOT_SIGNED_IN",
    as(ana, { app_id = "other", collection = "posts" }))

local post = actions.APP_DATA_PUT(as(ana, {
    app_id = "yap", collection = "posts", data = { body = "first yap" },
})).record
assert(post.author_name == "Ana Fox" and post.mine)
assert(post.reactions == 0 and post.reacted == false)

actions.APP_DATA_PUT(as(bo, {
    app_id = "yap", collection = "posts", data = { body = "second" },
}))
local feed = actions.APP_DATA_LIST(as(cy, {
    app_id = "yap", collection = "posts",
})).records
assert(#feed == 2 and feed[1].data.body == "second",
    "newest first, and everybody sees everybody")
assert(feed[1].mine == false, "a post is only yours if you wrote it")

-- Reactions are the one thing anybody can add to somebody else's record.
local liked = actions.APP_DATA_REACT(as(bo, {
    app_id = "yap", collection = "posts", id = post.id, on = true,
})).record
assert(liked.reactions == 1 and liked.reacted)
-- Liking twice is still one like.
assert(actions.APP_DATA_REACT(as(bo, {
    app_id = "yap", collection = "posts", id = post.id, on = true,
})).record.reactions == 1)
assert(actions.APP_DATA_REACT(as(cy, {
    app_id = "yap", collection = "posts", id = post.id, on = true,
})).record.reactions == 2)
assert(actions.APP_DATA_REACT(as(bo, {
    app_id = "yap", collection = "posts", id = post.id, on = false,
})).record.reactions == 1, "and it can be taken back")

-- Replies hang off a parent.
actions.APP_DATA_PUT(as(bo, {
    app_id = "yap", collection = "comments", parent = post.id,
    data = { body = "nice one" },
}))
actions.APP_DATA_PUT(as(cy, {
    app_id = "yap", collection = "comments", parent = "SOMETHING_ELSE",
    data = { body = "elsewhere" },
}))
local replies = actions.APP_DATA_LIST(as(ana, {
    app_id = "yap", collection = "comments", parent = post.id,
})).records
assert(#replies == 1 and replies[1].data.body == "nice one",
    "a parent filters the collection")

-- Editing and deleting are the author's alone.
rejected(actions.APP_DATA_PUT, "NOT_YOURS", as(bo, {
    app_id = "yap", collection = "posts", id = post.id,
    data = { body = "rewritten" },
}))
rejected(actions.APP_DATA_DELETE, "NOT_YOURS", as(bo, {
    app_id = "yap", collection = "posts", id = post.id,
}))
assert(actions.APP_DATA_PUT(as(ana, {
    app_id = "yap", collection = "posts", id = post.id,
    data = { body = "edited" },
})).record.data.body == "edited")
assert(actions.APP_DATA_DELETE(as(ana, {
    app_id = "yap", collection = "posts", id = post.id,
})).removed == post.id)
assert(#actions.APP_DATA_LIST(as(ana, {
    app_id = "yap", collection = "posts",
})).records == 1)

-- One app cannot read another's records.
actions.FOXY_LOGIN_APPROVE(as(ana, { app_id = "notes", app_name = "Notes" }))
assert(#actions.APP_DATA_LIST(as(ana, {
    app_id = "notes", collection = "posts",
})).records == 0, "collections are per app, not shared")

-- Records are small on purpose.
rejected(actions.APP_DATA_PUT, "RECORD_TOO_BIG", as(ana, {
    app_id = "yap", collection = "posts",
    data = { body = string.rep("x", config.max_app_record_bytes + 50) },
}))
rejected(actions.APP_DATA_PUT, "BAD_COLLECTION", as(ana, {
    app_id = "yap", collection = "not a name", data = {},
}))

-- Private records ------------------------------------------------------------
-- A record with an audience is visible to the author and the people named in
-- it, and to nobody else -- not even by asking for it by id.

local secret = actions.APP_DATA_PUT(as(ana, {
    app_id = "yap", collection = "dm", data = { body = "just for you" },
    audience = { ana.account.account_id, bo.account.account_id },
    expire_after_days = 1,
})).record
assert(secret.private, "a record with an audience says so")

assert(#actions.APP_DATA_LIST(as(bo, {
    app_id = "yap", collection = "dm",
})).records == 1, "somebody in the audience sees it")
assert(#actions.APP_DATA_LIST(as(cy, {
    app_id = "yap", collection = "dm",
})).records == 0, "somebody outside it does not")

-- Nor can an outsider reach it by id.
rejected(actions.APP_DATA_DELETE, "NOT_FOUND", as(cy, {
    app_id = "yap", collection = "dm", id = secret.id,
}))
rejected(actions.APP_DATA_REACT, "NOT_FOUND", as(cy, {
    app_id = "yap", collection = "dm", id = secret.id, on = true,
}))
rejected(actions.APP_DATA_PUT, "NOT_FOUND", as(cy, {
    app_id = "yap", collection = "dm", id = secret.id, data = { body = "no" },
}))

-- Reading is what starts the clock. The author reading it back is not a
-- read receipt, or a message would expire the moment it was sent.
assert(#actions.APP_DATA_READ(as(ana, {
    app_id = "yap", collection = "dm", id = secret.id,
})).read == 0, "reading your own record back does not count")
assert(actions.APP_DATA_LIST(as(ana, {
    app_id = "yap", collection = "dm",
})).records[1].expires_day == nil, "so nothing is scheduled to go yet")

assert(#actions.APP_DATA_READ(as(bo, {
    app_id = "yap", collection = "dm", ids = { secret.id },
})).read == 1)
local afterRead = actions.APP_DATA_LIST(as(ana, {
    app_id = "yap", collection = "dm",
})).records[1]
assert(afterRead.expires_day == currentDay + 1,
    "read on day " .. currentDay .. " means gone on day " .. (currentDay + 1))
assert(afterRead.seen, "the sender can tell it was read")

-- And a day later it really is gone, for both of them.
currentDay = currentDay + 1
assert(#actions.APP_DATA_LIST(as(ana, {
    app_id = "yap", collection = "dm",
})).records == 0, "the sender's copy went too")
assert(#actions.APP_DATA_LIST(as(bo, {
    app_id = "yap", collection = "dm",
})).records == 0)

-- An unread message is still there tomorrow.
local unread = actions.APP_DATA_PUT(as(ana, {
    app_id = "yap", collection = "dm", data = { body = "unopened" },
    audience = { ana.account.account_id, bo.account.account_id },
    expire_after_days = 1,
})).record
currentDay = currentDay + 3
assert(#actions.APP_DATA_LIST(as(bo, {
    app_id = "yap", collection = "dm",
})).records == 1, "nothing expires until it has been read")
actions.APP_DATA_READ(as(bo, {
    app_id = "yap", collection = "dm", id = unread.id,
}))
currentDay = currentDay + 1
assert(#actions.APP_DATA_LIST(as(bo, {
    app_id = "yap", collection = "dm",
})).records == 0)

-- Permissions and notifications ------------------------------------------------

-- Asking is deliberately possible before signing in: it exposes nothing, and
-- sending is what needs the grant.
local asked = actions.APP_PERMISSION_ASK(as(bo, {
    app_id = "chat", app_name = "Yap Chat",
})).permission
assert(asked.notifications == "unset" and asked.fullscreen == false)

-- An app that was refused cannot nag its way to a yes.
actions.APP_PERMISSION_ASK(as(bo, {
    app_id = "chat", app_name = "Yap Chat", allow = false,
}))
assert(actions.APP_PERMISSION_ASK(as(bo, {
    app_id = "chat", app_name = "Yap Chat", allow = true,
})).permission.notifications == "denied", "the first answer stands")

-- The owner can change their mind, which is what App Settings is for.
assert(actions.APP_PERMISSION_SET(as(bo, {
    app_id = "chat", notifications = true,
})).permission.notifications == "granted")

-- Fullscreen is the owner's switch and nothing else's.
assert(actions.APP_PERMISSION_SET(as(bo, {
    app_id = "chat", fullscreen = true,
})).permission.fullscreen == true)

actions.FOXY_LOGIN_APPROVE(as(ana, { app_id = "chat", app_name = "Yap Chat" }))
actions.FOXY_LOGIN_APPROVE(as(bo, { app_id = "chat", app_name = "Yap Chat" }))
actions.FOXY_LOGIN_APPROVE(as(cy, { app_id = "chat", app_name = "Yap Chat" }))

local sent = actions.APP_NOTIFY(as(ana, {
    app_id = "chat", account_id = bo.account.account_id,
    title = "Ana Fox", body = "you there?", style = "fullscreen",
}))
assert(sent.sent and sent.style == "fullscreen",
    "bo turned fullscreen on, so it arrives that way")

-- Turning notifications off takes fullscreen with it.
actions.APP_PERMISSION_SET(as(bo, { app_id = "chat", notifications = false }))
assert(actions.APP_PERMISSION_LIST(as(bo)).apps[1].fullscreen == false)
rejected(actions.APP_NOTIFY, "NO_PERMISSION", as(ana, {
    app_id = "chat", account_id = bo.account.account_id, body = "hello",
}))

-- Back on, but banners only: the sender does not get to be louder than the
-- recipient allowed.
actions.APP_PERMISSION_SET(as(bo, { app_id = "chat", notifications = true }))
assert(actions.APP_NOTIFY(as(ana, {
    app_id = "chat", account_id = bo.account.account_id,
    body = "hello", style = "fullscreen",
})).style == "banner", "fullscreen is the owner's setting, not the sender's")

-- One grant is not a licence to alert the whole server. Cy allows the app
-- and is still out of reach, because Cy is not Ana's friend.
actions.APP_PERMISSION_ASK(as(cy, {
    app_id = "chat", app_name = "Yap Chat", allow = true,
}))
rejected(actions.APP_NOTIFY, "NOT_FRIENDS", as(ana, {
    app_id = "chat", account_id = cy.account.account_id, body = "hi",
}))

-- The alert says which app it came from.
local inbox = bank.state.accounts[bo.account.account_id].notifications
assert(inbox[1].app_name == "Yap Chat" and inbox[1].kind == "app")

-- The Pin API ------------------------------------------------------------------

assert(actions.PIN_CHECK(as(ana, { app_id = "chat", pin = "1234" })).ok)
rejected(actions.PIN_CHECK, "BAD_PIN", as(ana, { app_id = "chat", pin = "9999" }))
-- An app that has not been signed into cannot use it to grind at the PIN.
rejected(actions.PIN_CHECK, "NOT_SIGNED_IN",
    as(ana, { app_id = "nobody", pin = "1234" }))
-- Nor can one that has: five wrong guesses and it is shut for a while.
for _ = 1, 5 do
    pcall(actions.PIN_CHECK, as(cy, { app_id = "chat", pin = "0000" }))
end
rejected(actions.PIN_CHECK, "TOO_MANY", as(cy, { app_id = "chat", pin = "1234" }))

-- An app cannot fill the Bank a collection at a time -------------------------
-- A chat app keeps one collection per conversation, so this is the limit
-- that actually bites. Emptied collections give their slot back.

local limit = config.max_app_collections
for index = 1, limit do
    actions.APP_DATA_PUT(as(ana, {
        app_id = "notes", collection = "box" .. index,
        data = { body = "x" },
    }))
end
rejected(actions.APP_DATA_PUT, "TOO_MANY", as(ana, {
    app_id = "notes", collection = "onemore", data = { body = "x" },
}))

-- An existing one still works while the app is at its limit.
assert(actions.APP_DATA_PUT(as(ana, {
    app_id = "notes", collection = "box1", data = { body = "still fine" },
})).record ~= nil, "being full does not break the collections you have")

-- Empty one out and the slot comes back, which is what makes disappearing
-- messages sustainable.
local box = actions.APP_DATA_LIST(as(ana, {
    app_id = "notes", collection = "box2",
})).records
for _, record in ipairs(box) do
    actions.APP_DATA_DELETE(as(ana, {
        app_id = "notes", collection = "box2", id = record.id,
    }))
end
assert(actions.APP_DATA_PUT(as(ana, {
    app_id = "notes", collection = "onemore", data = { body = "x" },
})).record ~= nil, "an emptied collection gives its slot back")

-- In-app purchases ---------------------------------------------------------------
-- What matters here is where the money goes: thirty per cent to the
-- government, the rest to whoever published the app, and an entitlement the
-- app cannot write for itself.

-- Cy publishes an app, through a company they own. A developer account is
-- made at a kiosk linked to that company, which is what ties an app to
-- somebody who can be paid.
local company = actions.CREATE_COMPANY({
    owner_session = cy.session_token, company_name = "Cy Software",
}).company
local kiosk = actions.KIOSK_REGISTER({ name = "Cy Kiosk" })
actions.LINK_TERMINAL({
    terminal_id = kiosk.terminal_id, terminal_token = kiosk.terminal_token,
    owner_session = cy.session_token, company_id = company.company_id,
})
local dev = actions.DEV_REGISTER({
    terminal_id = kiosk.terminal_id, terminal_token = kiosk.terminal_token,
    pin = "1234",
})
actions.APP_OWNER_SET({
    app_id = "yap", app_name = "Yap",
    developer_id = dev.developer_id, developer_token = dev.developer_token,
})

-- Somebody who has not signed into the app cannot buy anything in it.
local stranger = register("Dee Lark")
rejected(actions.APP_PURCHASE, "NOT_SIGNED_IN", as(stranger, {
    app_id = "yap", product_id = "boost", name = "Boost", amount = 10,
    pin = "1234",
}))

local quote = actions.APP_PURCHASE_QUOTE(as(bo, {
    app_id = "yap", product_id = "boost", name = "Yap Boost", amount = 10,
}))
assert(quote.tax == 3 and quote.to_seller == 7,
    "thirty per cent is tax: got tax " .. tostring(quote.tax))
assert(quote.seller == "Cy Hare", "and the rest goes to who published it")

local function money(who)
    return bank.state.accounts[who.account.account_id].balance
end
local buyerBefore, sellerBefore = money(bo), money(cy)
local taxBefore = bank.state.tax_revenue

rejected(actions.APP_PURCHASE, "BAD_PIN", as(bo, {
    app_id = "yap", product_id = "boost", name = "Yap Boost", amount = 10,
    pin = "0000",
}))
assert(money(bo) == buyerBefore, "a wrong PIN pays nobody")

local bought = actions.APP_PURCHASE(as(bo, {
    app_id = "yap", product_id = "boost", name = "Yap Boost", amount = 10,
    pin = "1234", target = "YAP000003",
}))
assert(bought.paid == 10 and bought.tax == 3)
assert(money(bo) == buyerBefore - 10, "the buyer paid ten")
assert(money(cy) == sellerBefore + 7, "the seller got seven")
assert(bank.state.tax_revenue == taxBefore + 3,
    "and the government got three")

-- The entitlement is the Bank's record, and carries what it was bought for.
local owned = actions.APP_ENTITLEMENTS(as(bo, { app_id = "yap" })).entitlements
assert(#owned == 1 and owned[1].product_id == "boost")
assert(owned[1].target == "YAP000003", "a one-off knows what it covers")
assert(not owned[1].subscription)
-- And it belongs to the app that sold it, not to every app.
actions.FOXY_LOGIN_APPROVE(as(bo, { app_id = "other", app_name = "Other" }))
assert(#actions.APP_ENTITLEMENTS(as(bo, { app_id = "other" })).entitlements == 0,
    "one app cannot see, or claim, another's purchases")

-- Subscriptions -------------------------------------------------------------------

local subscribed = actions.APP_PURCHASE(as(bo, {
    app_id = "yap", product_id = "boost_all", name = "Boost All",
    amount = 20, period = "day", pin = "1234",
}))
assert(subscribed.bought.subscription and subscribed.bought.period == "day")
rejected(actions.APP_PURCHASE, "ALREADY_SUBSCRIBED", as(bo, {
    app_id = "yap", product_id = "boost_all", name = "Boost All",
    amount = 20, period = "day", pin = "1234",
}))

-- A day passes and it is charged again, split the same way.
local beforeDay, sellerDay = money(bo), money(cy)
local taxDay = bank.state.tax_revenue
currentDay = currentDay + 1
bank.appstore.chargeSubscriptions(currentDay)
assert(money(bo) == beforeDay - 20, "a day costs twenty")
assert(money(cy) == sellerDay + 14 and bank.state.tax_revenue == taxDay + 6,
    "split seventy thirty every day, not just the first")

-- Cancelling stops it.
actions.APP_SUBSCRIPTION_CANCEL(as(bo, {
    app_id = "yap", product_id = "boost_all",
}))
local afterCancel = money(bo)
currentDay = currentDay + 1
bank.appstore.chargeSubscriptions(currentDay)
assert(money(bo) == afterCancel, "a cancelled subscription is not charged")

-- A subscription nobody can pay for stops rather than running up a debt.
actions.APP_PURCHASE(as(bo, {
    app_id = "yap", product_id = "boost_all", name = "Boost All",
    amount = 20, period = "day", pin = "1234",
}))
bank.state.accounts[bo.account.account_id].balance = 5
currentDay = currentDay + 1
bank.appstore.chargeSubscriptions(currentDay)
assert(bank.state.accounts[bo.account.account_id].balance == 5,
    "it does not take what is not there")
local after = actions.APP_ENTITLEMENTS(as(bo, { app_id = "yap" })).entitlements
for _, entry in ipairs(after) do
    if entry.product_id == "boost_all" then
        assert(not entry.active, "and stops instead")
    end
end

-- Revoking closes the door again.
actions.FOXY_LOGIN_REVOKE(as(ana, { app_id = "yap" }))
assert(actions.FOXY_LOGIN_STATUS(as(ana, { app_id = "yap" })).approved == false)
rejected(actions.APP_DATA_LIST, "NOT_SIGNED_IN",
    as(ana, { app_id = "yap", collection = "posts" }))

print("host_appdata_server_test: OK")
