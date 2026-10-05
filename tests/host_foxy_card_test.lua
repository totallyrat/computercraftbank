-- Foxy, FoxyOS 15: no intro, and the Foxy Bank card drops in.
--
-- Foxy opens straight onto what it was opened for: the FOXY wordmark that
-- swept in first is gone. On the Bank, the card comes down from the top
-- and is done in two seconds -- once each time Foxy is opened. Over to
-- another tab and back, it is simply there. Against a real Bank.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local bank = harness.pair()
local phone = require("phone_app_harness")
local ana = bank.register("Ana Fox", "1234")

local slept = 0
sleep = function(seconds) slept = slept + (tonumber(seconds) or 0) end
local marks = {}

-- Opened from the Home Screen: straight onto the Bank, the card drops once.
local script = phone.script()
phone.push(script.actions, function(seen)
    marks.first = slept
    local frame = phone.last(seen)
    assert(phone.has(frame, "Foxy Bank") and phone.has(frame, "BALANCE"),
        "it opens on the Bank")
    assert(phone.has(frame, "FOXY"), "with the card on it")
    return "tab:security"
end, function()
    marks.security = slept
    return "tab:bank"
end, function(seen)
    marks.back = slept
    assert(phone.has(phone.last(seen), "FOXY"), "the card is there, drawn at once")
    return "home"
end)
local seen = phone.run({ bank = bank, who = ana, file = "../foxy.lua", script = script,
    app_id = "FOXY" })
assert(not phone.has(seen.frames[1], "small bank, big vault"), "no intro first")
assert(math.abs(marks.first - 2) < 0.001,
    "the card takes two seconds, and nothing else waits before it: " .. marks.first)
assert(marks.back == marks.security, "back on the Bank from another tab: no drop")

-- Opened again: it drops again. Opened at the Bank from a QuickAction too.
slept = 0
script = phone.script()
phone.push(script.actions, function()
    marks.again = slept
    return "home"
end)
phone.run({ bank = bank, who = ana, file = "../foxy.lua", script = script,
    app_id = "FOXY", wanted = "bank" })
assert(math.abs(marks.again - 2) < 0.001, "each time Foxy is opened")

-- Opened on another tab: nothing waits at all until the Bank is shown.
slept = 0
script = phone.script()
phone.push(script.actions, function()
    marks.account = slept
    return "tab:bank"
end, function()
    marks.bankLater = slept
    return "home"
end)
phone.run({ bank = bank, who = ana, file = "../foxy.lua", script = script,
    app_id = "FOXY", wanted = "account" })
assert(marks.account == 0, "the Account tab opens at once")
assert(math.abs(marks.bankLater - 2) < 0.001, "and the card drops the first time the Bank is shown")

print("host_foxy_card_test: OK")
