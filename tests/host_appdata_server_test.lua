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

-- Revoking closes the door again.
actions.FOXY_LOGIN_REVOKE(as(ana, { app_id = "yap" }))
assert(actions.FOXY_LOGIN_STATUS(as(ana, { app_id = "yap" })).approved == false)
rejected(actions.APP_DATA_LIST, "NOT_SIGNED_IN",
    as(ana, { app_id = "yap", collection = "posts" }))

print("host_appdata_server_test: OK")
