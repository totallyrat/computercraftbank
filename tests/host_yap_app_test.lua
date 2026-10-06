-- Yap!, FoxyOS 16, on a 26x20 Pocket against a real Bank Core and Vault.
--
-- Ana signs up -- Foxy sends her a VerCode, she types it -- posts, gets a
-- like and a reply in, hides from Yap Map, and writes to Kit behind her PIN.
-- Kit signs up on his own Pocket, finds Ana's yap above a stranger's, reads
-- her message, and sees where Ana was before she hid. Every screen is bounds
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
bank.request("FRIEND_REQUEST", bank.as(ana, { name = "Kit Wolf" }))
bank.request("FRIEND_REQUEST", bank.as(kit, { name = "Ana Fox" }))

-- What the phone hands Yap! beyond the basics, the way the phone does it.
local notified, called = {}, {}
local function extras(who)
    return {
        notifications = function(api)
            return { ask = function() return true end,
                send = function(spec) notified[#notified + 1] = spec return true end }
        end,
        call = function() return function(spec) called[#called + 1] = spec end end,
        -- As the Pocket: ask the Bank to send one, then a box to type it in.
        vercode = function(api, ui, surface)
            return { ask = function(title)
                local sent, err = api.request("VERCODE_SEND", {})
                if not sent then return nil, err end
                local typed = ui.input(surface, title or "Your code", { mode = "integer" })
                if not typed then return nil, "Cancelled" end
                local ok, checkError = api.request("VERCODE_CHECK", { code = typed })
                return ok and true or nil, checkError
            end }
        end,
    }
end
local function run(who, script, kept, extra)
    extra = extra or {}
    return phone.run({ bank = bank, who = who, file = "../yap.lua", script = script,
        app_id = "YAP", kept = kept, wanted = extra.wanted, api = extras(who),
        pin = function() return extra.pin ~= false end,
        login = function(spec)
            assert(spec.name == "Yap!")
            return bank.request("FOXY_LOGIN_APPROVE", bank.as(who, { app_id = "YAP",
                app_name = spec.name, scopes = spec.scopes })).profile
        end })
end
-- The code Foxy just sent, read the way the Pocket's banner gets it.
local function codeFor(who)
    return function()
        return bank.request("PUMPE_POLL", bank.as(who)).latest.code
    end
end

-- Lee, who is nobody's friend, posted first.
bank.request("FOXY_LOGIN_APPROVE", bank.as(lee, { app_id = "YAP", app_name = "Yap!",
    scopes = { "friends" } }))
bank.request("APP_DATA_PUT", bank.as(lee, { app_id = "YAP", collection = "posts",
    data = { body = "stranger danger" } }))
-- Kit uses Yap! (on another Pocket, signed in) and is by the GPS Anchors.
bank.request("FOXY_LOGIN_APPROVE", bank.as(kit, { app_id = "YAP", app_name = "Yap!",
    scopes = { "friends" } }))
bank.request("REPORT_POSITION", bank.as(kit, { position = { x = 40.2, y = 70, z = -12.8 } }))

-- Ana signs up, posts, and is liked -------------------------------------------------------

local anaKept = {}
local script = phone.script()
local kitId = kit.id
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Sign up") and phone.has(frame, "Hi Ana Fox"),
        "the first time, Yap! asks for a VerCode")
    return "send"
end, function(seen)
    assert(phone.has(phone.last(seen), "1 yap"), "only Lee's, so far")
    return "new"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "2 yaps") and phone.has(frame, "Hello foxes"))
    return "post:1"
end, function(seen)
    assert(phone.has(phone.last(seen), "0 likes"))
    return "like"
end, "reply", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "1 like") and phone.has(frame, "first!"),
        "the like, and the reply under it")
    return "back"
end, "tab:map", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Kit Wolf") and phone.has(frame, "40 70 -13"),
        "Kit is in a Coordinate Zone, with coordinates")
    assert(not phone.has(frame, "Lee Owl"), "Lee is not a friend")
    assert(phone.has(frame, "Not in a zone"), "and Ana is not")
    return "hide"
end, function(seen)
    assert(phone.has(phone.last(seen), "You (hidden)") and phone.has(phone.last(seen), "Show me"))
    return "tab:chat"
end, function(seen)
    assert(phone.has(phone.last(seen), "Kit Wolf"), "friends, after the PIN")
    return "open:" .. kitId
end, "send", function(seen)
    assert(phone.has(phone.last(seen), "> see you at the den"))
    return "call"
end, "back", "home")
phone.push(script.inputs, codeFor(ana), "Hello foxes", "first!", "see you at the den")
phone.push(script.confirms, true)
local seen = run(ana, script, anaKept)
assert(phone.said(seen, "Hidden"), "Hide me, done")
assert(next(anaKept.value.verified), "signed up: not asked again on this Pocket")
assert(#notified == 1 and notified[1].account_id == kit.id and notified[1].body
    == "see you at the den", "Kit is told about the message")
assert(#called == 1 and called[1].account_id == kit.id, "Call rings Kit")
-- Private: Lee, who also uses Yap!, cannot read Ana and Kit's thread.
local util = require("lib.util")
local low, high = ana.id, kit.id
if low > high then low, high = high, low end
local thread = "dm" .. util.checksum(low .. "|" .. high)
assert(#bank.request("APP_DATA_LIST", bank.as(lee, { app_id = "YAP",
    collection = thread })).records == 0, "only the two of them can read it")
assert(#bank.request("APP_DATA_LIST", bank.as(kit, { app_id = "YAP",
    collection = thread })).records == 1, "and Kit can")
-- The code came from Foxy, in Messages.
local foxy
for _, chat in ipairs(bank.request("CHAT_LIST", bank.as(ana)).conversations) do
    if chat.title == "Foxy" then foxy = chat end
end
assert(foxy and foxy.kind == "publisher", "the code arrived as a message from Foxy")

-- Signed up already: straight to the feed. A wrong PIN keeps Chat shut.
script = phone.script()
phone.push(script.actions, function(seen)
    assert(not phone.has(phone.last(seen), "Sign up"), "no second VerCode")
    return "tab:chat"
end, function(seen)
    assert(phone.has(phone.last(seen), "Hello foxes"), "back on the feed")
    return "home"
end)
run(ana, script, anaKept, { pin = false })

-- Kit, on his own Pocket ---------------------------------------------------------------------

script = phone.script()
phone.push(script.actions, "send", function(seen)
    local frame = phone.last(seen)
    local mine, stranger
    for index, value in ipairs(frame) do
        if value == "Hello foxes" then mine = mine or index end
        if value == "stranger danger" then stranger = stranger or index end
    end
    assert(mine and stranger and mine < stranger, "a friend's yap before a stranger's")
    return "tab:chat"
end, function(seen)
    assert(phone.has(phone.last(seen), "1 new"), "Ana's message is waiting")
    return "open:" .. ana.id
end, function(seen)
    assert(phone.has(phone.last(seen), "< see you at the den"))
    return "back"
end, function(seen)
    assert(not phone.has(phone.last(seen), "1 new"), "read now")
    return "tab:map"
end, function(seen)
    assert(not phone.has(phone.last(seen), "Ana Fox"), "Ana hid, so Kit cannot see her")
    assert(phone.has(phone.last(seen), "40 70 -13"), "Kit sees where he is")
    return "home"
end)
phone.push(script.inputs, codeFor(kit))
run(kit, script, {})
-- A wrong code is not a sign-up.
script = phone.script()
phone.push(script.actions, "send", "back")
phone.push(script.inputs, "000000")
local tried = run(lee, script, {})
assert(phone.said(tried, "Not signed up"), "a wrong code is refused")

-- Opened on Yap Map, from search.
script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Yap Map"), "the map action opens the map")
    return "home"
end)
run(ana, script, anaKept, { wanted = "map" })

print("host_yap_app_test: OK")
