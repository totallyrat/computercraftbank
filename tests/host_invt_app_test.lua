-- The INVT app, FoxyOS 14, on a 26x20 Pocket against a real Bank Core and Vault.
--
-- Ana fills in a ticket that rises from the bottom -- a private garden
-- party -- and invites Kit from her friends. Kit finds it in the feed, takes
-- three free tickets, and pulls them down from the ticket at the top of the
-- feed. Lee pays for a public quiz with their PIN. Every screen is bounds
-- checked, and every tap has to land on something that is there.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local bank = harness.pair()
local phone = require("phone_app_harness")
os.time = function() return 12 end

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local lee = bank.register("Lee Owl", "1111")
bank.fund(lee, 100)
bank.request("FRIEND_REQUEST", bank.as(ana, { name = "Kit Wolf" }))
bank.request("FRIEND_REQUEST", bank.as(kit, { name = "Ana Fox" }))
local today = harness.day

local function run(who, script, extra)
    extra = extra or {}
    return phone.run({ bank = bank, who = who, file = "../invt.lua", script = script,
        app_id = "INVT", wanted = extra.wanted,
        -- Signing in with Foxy, as the phone does it: the Bank records it.
        login = function(spec)
            assert(spec.name == "INVT")
            return bank.request("FOXY_LOGIN_APPROVE", bank.as(who, { app_id = "INVT",
                app_name = spec.name, scopes = spec.scopes })).profile
        end })
end

-- Ana makes a private party and invites Kit --------------------------------------------------

local script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "No tickets yet"), "the ticket at the top of the feed")
    return "new"
end, function(seen)
    assert(phone.has(phone.last(seen), "Fill in the ticket"))
    return "title"
end, "when", "about", "spots", "who", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Garden Party") and phone.has(frame, "Private")
        and phone.has(frame, "Day " .. (today + 1) .. " 18:30"), "the ticket, filled in")
    return "create"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "PRIVATE") and phone.has(frame, "Invite"),
        "on its own page, the host's tools")
    return "invite"
end, "pick:1", function(seen)
    assert(phone.has(phone.last(seen), "Kit Wolf"), "a friend to pick")
    return "pick:1"
end, "back", "__terminate")
phone.push(script.inputs, "Garden Party", tostring(today + 1), "1830", "Bring snacks", "6")
local seen = run(ana, script)
assert(phone.said(seen, "Private").body == "Now invite people")
assert(phone.said(seen, "Invited").body == "Kit Wolf")
local party
for _, event in pairs(bank.vault_state.invt.events) do party = event end
assert(party.title == "Garden Party" and party.day == today + 1 and party.time == "18:30"
    and party.spots == 6 and party.price == 0 and party.public == false)
assert(party.invites[kit.id], "Kit is invited")

-- Kit takes three tickets and pulls them down ---------------------------------------------

script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Garden Party"), "in Kit's feed now")
    return "event:1"
end, function(seen)
    assert(phone.has(phone.last(seen), "Join, free"))
    return "get"
end, "more", "more", function(seen)
    assert(phone.has(phone.last(seen), "3"))
    return "go"
end, function(seen)
    assert(phone.has(phone.last(seen), "You have 3 tickets"))
    return "back"
end, function(seen)
    assert(phone.has(phone.last(seen), "Your tickets: 3"), "the ticket at the top counts them")
    return "drawer"
end, function(seen)
    assert(phone.has(phone.last(seen), "3 held"), "pulled down: all of them")
    return "ticket:1"
end, function(seen)
    assert(phone.has(phone.last(seen), "SHOW AT THE DOOR"))
    return "back"
end, "close", "__terminate")
seen = run(kit, script)
assert(phone.said(seen, "You're going!"))
assert(party.going[kit.id] == 3 and party.taken == 3)

-- Lee pays for a public quiz -------------------------------------------------------------------

bank.request("FOXY_LOGIN_APPROVE", bank.as(ana, { app_id = "INVT", app_name = "INVT" }))
local quiz = bank.request("INVT_CREATE", bank.as(ana, { app_id = "INVT", title = "Quiz Night",
    day = today + 2, time = "20:00", spots = 20, price = 5, public = true })).event
script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Quiz Night") and not phone.has(frame, "Garden Party"),
        "the public quiz, and not somebody else's party")
    return "event:1"
end, "get", "more", function(seen)
    assert(phone.has(phone.last(seen), "Pay $10"))
    return "go"
end, "back", "__terminate")
phone.push(script.pins, "1111")
seen = phone.run({ bank = bank, who = lee, file = "../invt.lua", script = script,
    app_id = "INVT", login = function(spec)
        return bank.request("FOXY_LOGIN_APPROVE", bank.as(lee, { app_id = "INVT",
            app_name = spec.name, scopes = spec.scopes })).profile
    end })
assert(bank.balanceOf(lee) == 590 and bank.balanceOf(ana) == 510, "10 from Lee to Ana")

-- Declining to sign in leaves nothing behind.
script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Sign in with Foxy"))
    return "back"
end)
phone.run({ bank = bank, who = lee, file = "../invt.lua", script = script, app_id = "INVT",
    login = function() return nil end })

print("host_invt_app_test: OK")
