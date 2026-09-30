-- MyID, FoxyOS 12, against a real Bank Core and Vault.
--
-- A Digital ID is asked for with a PIN from the Pocket itself, waits for the
-- government, and only counts once confirmed at an Admin Terminal. The MyID
-- Verifier -- a Service Kiosk, or an organizer at an Event Kiosk -- is told
-- whether a code is a confirmed ID and whose, and a verifier that keeps
-- typing codes that are nobody's has to wait. Visas need a confirmed ID.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()

local kit = bank.register("Kit Wolf", "5678")
local ana = bank.register("Ana Fox", "1234")
local government = bank.fund(ana, 10)
local function asGovernment(extra)
    extra = extra or {}
    extra.government_token = government
    return extra
end

-- Signing up ---------------------------------------------------------------------------

assert(bank.request("MYID_STATUS", bank.as(kit)).myid == nil, "nobody has one to start with")
local fromApp = bank.as(kit, { name = "Kit Wolf", pin = "5678" })
fromApp.app_id = "APP00001"
rejected(bank.request, "WRONG_APP", "MYID_APPLY", fromApp)
rejected(bank.request, "BAD_PIN", "MYID_APPLY", bank.as(kit, { name = "Kit Wolf", pin = "0000" }))
rejected(bank.request, "BAD_NAME", "MYID_APPLY", bank.as(kit, { name = "K", pin = "5678" }))
local asked = bank.request("MYID_APPLY", bank.as(kit, { name = "Kit Wolf", pin = "5678" })).myid
assert(asked.status == "pending" and asked.name == "Kit Wolf", "it waits for the government")
assert(asked.code:match("^MY%-[A-Z2-9][A-Z2-9][A-Z2-9][A-Z2-9]%-[A-Z2-9][A-Z2-9][A-Z2-9][A-Z2-9]$"),
    "a MyID Code: " .. asked.code)
assert(not asked.code:find("[01OI]", 4), "with nothing that reads as something else")
rejected(bank.request, "WAITING", "MYID_APPLY", bank.as(kit, { name = "Kit", pin = "5678" }))

-- Before it is confirmed, it does not count.
local till = bank.request("KIOSK_REGISTER", { name = "Till" })
local function atTill(extra)
    extra = extra or {}
    extra.terminal_id, extra.terminal_token = till.terminal_id, till.terminal_token
    return extra
end
local early = bank.request("MYID_VERIFY", atTill({ code = asked.code }))
assert(early.valid == false and early.status == "pending", "a code waiting to be confirmed is not valid")
assert(early.name == nil, "and says nobody's name")

-- The government ------------------------------------------------------------------------

rejected(bank.request, "GOVERNMENT_AUTH", "ADMIN_MYID_LIST", { government_token = "guess" })
local waiting = bank.request("ADMIN_MYID_LIST", asGovernment()).ids
assert(#waiting == 1 and waiting[1].account_name == "Kit Wolf"
    and waiting[1].code == asked.code, "the Admin Terminal lists who is waiting")
rejected(bank.request, "GOVERNMENT_AUTH", "ADMIN_MYID_DECIDE", { account_id = kit.id })
rejected(bank.request, "GOVERNMENT_AUTH", "ADMIN_MYID_DECIDE", bank.as(kit, { account_id = kit.id }))
assert(bank.request("MYID_STATUS", bank.as(kit)).myid.status == "pending",
    "nobody but the government confirms an ID, the person least of all")
local confirmed = bank.request("ADMIN_MYID_DECIDE", asGovernment({
    account_id = kit.id })).myid
assert(confirmed.status == "active" and confirmed.confirmed_day, "confirmed")
assert(bank.notifications(kit)[1].body:find(asked.code, 1, true), "Kit is told their code")
rejected(bank.request, "NOT_WAITING", "ADMIN_MYID_DECIDE", asGovernment({ account_id = kit.id }))
rejected(bank.request, "HAVE_ONE", "MYID_APPLY", bank.as(kit, { name = "Kit", pin = "5678" }))
assert(#bank.request("ADMIN_MYID_LIST", asGovernment()).ids == 0, "nobody waiting now")

-- Refused, then asked for again: the same code, waiting again.
bank.request("MYID_APPLY", bank.as(ana, { name = "Ana", pin = "1234" }))
rejected(bank.request, "NO_REASON", "ADMIN_MYID_DECIDE", asGovernment({
    account_id = ana.id, approve = false }))
local refused = bank.request("ADMIN_MYID_DECIDE", asGovernment({ account_id = ana.id,
    approve = false, reason = "Use your full name" })).myid
assert(refused.status == "rejected" and refused.reason == "Use your full name")
assert(bank.notifications(ana)[1].title == "Digital ID refused")
local again = bank.request("MYID_APPLY", bank.as(ana, { name = "Ana Fox", pin = "1234" })).myid
assert(again.status == "pending" and again.code == refused.code, "asked for again, the same code")

-- The MyID Verifier -----------------------------------------------------------------------

local valid = bank.request("MYID_VERIFY", atTill({ code = asked.code }))
assert(valid.valid and valid.name == "Kit Wolf" and valid.code == asked.code,
    "a confirmed code says whose it is")
local loose = asked.code:gsub("%-", ""):lower()
assert(bank.request("MYID_VERIFY", atTill({ code = loose })).valid,
    "however it is typed: " .. loose)
assert(bank.request("MYID_VERIFY", atTill({ code = loose:sub(3) })).valid, "or without MY")
-- An organizer at an Event Kiosk asks as themselves.
assert(bank.request("MYID_VERIFY", bank.as(ana, { code = asked.code })).name == "Kit Wolf")
rejected(bank.request, "SESSION_EXPIRED", "MYID_VERIFY", { code = asked.code })

-- Fishing for names: five codes that are nobody's, and the verifier waits.
for _ = 1, 5 do
    local nobody = bank.request("MYID_VERIFY", atTill({ code = "MY-ZZZZ-ZZZZ" }))
    assert(nobody.valid == false and nobody.status == "unknown" and not nobody.name)
end
rejected(bank.request, "TRY_LATER", "MYID_VERIFY", atTill({ code = asked.code }))
assert(bank.request("MYID_VERIFY", bank.as(ana, { code = asked.code })).valid,
    "another verifier is not held up by this one")
bank.advanceMs(61 * 1000)
assert(bank.request("MYID_VERIFY", atTill({ code = asked.code })).valid, "a minute later")

-- A suspended account's ID does not count.
bank.core.state.accounts[kit.id].frozen = true
local frozen = bank.request("MYID_VERIFY", atTill({ code = asked.code }))
assert(frozen.valid == false and frozen.status == "suspended")
bank.core.state.accounts[kit.id].frozen = nil

print("host_myid_test: OK")
