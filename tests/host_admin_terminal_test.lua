-- Bank Admin Terminal: the government key, account approval, balance
-- adjustments, bans, tax demands and system-wide announcements.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, currentEpoch = 300, 1000000
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return currentEpoch end
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

local function register(name, pin)
    local created = actions.REGISTER({ name = name, pin = pin, gender = "Not set" })
    return { token = created.session_token,
        id = created.account.account_id, name = name }
end
local function as(who, extra)
    local payload = { session_token = who.token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

-- The shipped default key works out of the box.
assert(config.government_key == "Government1234",
    "the documented starting key must be the configured one")
rejected(actions.GOVERNMENT_LOGIN, "BAD_KEY", { key = "wrong" })
local gov = actions.GOVERNMENT_LOGIN({ key = "Government1234" }).government_token

-- Releases before 7.1 shipped a placeholder here, and every Bank that
-- self-updated kept it, because an update preserves local settings. The
-- terminal then rejected the documented key forever. A retired placeholder
-- has to mean "unset", not "this is the live key".
config.government_key = "CHANGE-ME-GOVERNMENT-KEY"
rejected(actions.GOVERNMENT_LOGIN, "BAD_KEY",
    { key = "CHANGE-ME-GOVERNMENT-KEY" })
assert(actions.GOVERNMENT_LOGIN({ key = "Government1234" }).government_token,
    "the documented key works on a Bank still carrying the placeholder")
config.government_key = "Government1234"
local function admin(extra)
    local payload = { government_token = gov }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

-- The live key lives in the database, so it can be changed from the terminal.
rejected(actions.ADMIN_SET_KEY, "KEY_TOO_SHORT", admin({ new_key = "abc" }))
assert(actions.ADMIN_SET_KEY(admin({ new_key = "SecretKey99" })).ok)
rejected(actions.GOVERNMENT_LOGIN, "BAD_KEY", { key = "Government1234" })
assert(actions.GOVERNMENT_LOGIN({ key = "SecretKey99" }).government_token)

-- Balance controls.
local alice = register("Alice Fox", "1111")
local start = actions.ACCOUNT_SUMMARY(as(alice)).account.balance
actions.ADMIN_CREDIT(admin({
    account_id = alice.id, amount = 250, reason = "Grant" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == start + 250)
actions.ADMIN_DEBIT(admin({
    account_id = alice.id, amount = 100, reason = "Fine" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == start + 150)
rejected(actions.ADMIN_DEBIT, "INSUFFICIENT_FUNDS",
    admin({ account_id = alice.id, amount = 999999 }))

-- A tax demand is owed, not seized: the holder pays it with their own PIN.
actions.ADMIN_TAX_DEMAND(admin({
    account_id = alice.id, amount = 60, reason = "Late filing" }))
local owed = actions.TAX_DEMAND_STATUS(as(alice)).demand
assert(owed and owed.amount == 60 and owed.reason == "Late filing")
local before = actions.ACCOUNT_SUMMARY(as(alice)).account.balance
rejected(actions.PAY_TAX_DEMAND, "BAD_PIN", as(alice, { pin = "0000" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == before,
    "a wrong PIN must not move any money")
actions.PAY_TAX_DEMAND(as(alice, { pin = "1111" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == before - 60)
assert(actions.TAX_DEMAND_STATUS(as(alice)).demand == nil)
rejected(actions.PAY_TAX_DEMAND, "NOT_FOUND", as(alice, { pin = "1111" }))

-- Bans take effect at once and cut the live session.
actions.ADMIN_BAN(admin({ account_id = alice.id, banned = true }))
rejected(actions.ACCOUNT_SUMMARY, "SESSION_EXPIRED", as(alice))
rejected(actions.LOGIN, "ACCOUNT_BANNED", { name = "Alice Fox", pin = "1111" })
actions.ADMIN_BAN(admin({ account_id = alice.id, banned = false }))
assert(actions.LOGIN({ name = "Alice Fox", pin = "1111" }).session_token)

-- Account approval gates new accounts only while it is switched on.
assert(actions.ADMIN_SETTINGS(admin()).account_approval == false)
local open = register("Open Otter", "2222")
assert(actions.ACCOUNT_SUMMARY(as(open)).account, "approval off lets them in")

actions.ADMIN_SET_APPROVAL(admin({ enabled = true }))
local held = register("Held Hare", "3333")
rejected(actions.ACCOUNT_SUMMARY, "ACCOUNT_PENDING", as(held))
assert(actions.ADMIN_SETTINGS(admin()).pending_approvals == 1)
local pending = actions.ADMIN_ACCOUNTS(admin({ pending_only = true })).accounts
assert(#pending == 1 and pending[1].name == "Held Hare")
actions.ADMIN_APPROVE_ACCOUNT(admin({ account_id = held.id, approve = true }))
assert(actions.ACCOUNT_SUMMARY(as(held)).account, "approval lets them in")
assert(actions.ACCOUNT_SUMMARY(as(open)).account,
    "existing accounts are never held by switching approval on")

-- Announcements reach every account, both as an alert and through the poll.
local banner = actions.ADMIN_ANNOUNCE(admin({
    title = "Market closes at dusk", body = "Trade before then", mode = "banner",
})).announcement
assert(banner.mode == "banner")
local seen = actions.PUMPE_POLL(as(open)).announcement
assert(seen and seen.announcement_id == banner.announcement_id)
local alerts = actions.NOTIFICATIONS(as(open)).notifications
local found = false
for _, item in ipairs(alerts) do
    if item.title == "Market closes at dusk" then found = true end
end
assert(found, "an announcement is also an ordinary alert")

-- A full screen announcement keeps coming back until it is acknowledged.
local modal = actions.ADMIN_ANNOUNCE(admin({
    title = "Server restart", body = "In five minutes", mode = "modal",
})).announcement
assert(actions.PUMPE_POLL(as(open)).announcement.announcement_id
    == modal.announcement_id, "the newest unacknowledged one is shown")
assert(actions.PUMPE_POLL(as(open)).announcement.announcement_id
    == modal.announcement_id, "polling again does not dismiss it")
actions.ANNOUNCEMENT_ACK(as(open, { announcement_id = modal.announcement_id }))
assert(actions.PUMPE_POLL(as(open)).announcement.announcement_id
    == banner.announcement_id,
    "acknowledging one falls back to the older unread one")
actions.ANNOUNCEMENT_ACK(as(open, { announcement_id = banner.announcement_id }))
assert(actions.PUMPE_POLL(as(open)).announcement == nil)
assert(actions.PUMPE_POLL(as(held)).announcement,
    "acknowledging on one phone does not clear it for everyone")

-- None of this is reachable without a government session.
for _, action in ipairs({ "ADMIN_SET_KEY", "ADMIN_SET_APPROVAL", "ADMIN_CREDIT",
    "ADMIN_DEBIT", "ADMIN_BAN", "ADMIN_TAX_DEMAND", "ADMIN_ANNOUNCE",
    "ADMIN_ACCOUNTS", "ADMIN_SETTINGS" }) do
    rejected(actions[action], "GOVERNMENT_AUTH",
        { account_id = alice.id, amount = 5, title = "x", new_key = "abcdefg" })
end

-- The Admin Terminal is a protected download, like the Bank Server.
local adminFiles = bank.deployment_files("admin")
assert(adminFiles, "the admin role must be deployable")
local hasProgram, publicConfig = false, false
for _, file in ipairs(adminFiles) do
    if file.path == "admin_terminal.lua" then hasProgram = true end
    if file.path == "config.lua" and file.source == "config.lua" then
        publicConfig = true
    end
end
assert(hasProgram, "the admin role installs admin_terminal.lua")
assert(publicConfig,
    "a protected role receives the real config, not the sanitized one")

print("host_admin_terminal_test: OK")
