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
PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = bank.actions

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

-- Revoking closes the door again.
actions.FOXY_LOGIN_REVOKE(as(ana, { app_id = "yap" }))
assert(actions.FOXY_LOGIN_STATUS(as(ana, { app_id = "yap" })).approved == false)
rejected(actions.APP_DATA_LIST, "NOT_SIGNED_IN",
    as(ana, { app_id = "yap", collection = "posts" }))

print("host_appdata_server_test: OK")
