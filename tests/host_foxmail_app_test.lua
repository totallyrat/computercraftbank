-- The FoxMail app on a 26x20 PUMPE, against a real Bank Core and Vault.
--
-- Signing up, writing, reading, replying from a company address, switching
-- between addresses, and adding one -- each driven by taps, each checked
-- against what the Vault ended up holding.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local phone = require("phone_app_harness")
local mail = bank.vault.mail

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local rob = bank.register("Rob Hare", "9999")

-- Ana owns Fox Goods, which already has a domain.
local made = bank.request("KIOSK_REGISTER", { name = "Till" })
local function till(extra)
    extra = extra or {}
    extra.terminal_id, extra.terminal_token = made.terminal_id, made.terminal_token
    return extra
end
local login = bank.request("KIOSK_OWNER_LOGIN", till({ name = "Ana Fox", pin = "1234" }))
local company = bank.request("CREATE_COMPANY", till({
    owner_session = login.owner_session, company_name = "Fox Goods" })).company
bank.request("MAIL_CLAIM", bank.as(ana, { name = "ana" }))
bank.request("MAIL_DOMAIN", bank.as(ana, { company_id = company.company_id,
    domain = "foxgoods.com", name = "hello" }))

local function run(who, script, extra)
    extra = extra or {}
    return phone.run({ bank = bank, who = who, file = "../foxmail.lua",
        script = script, wanted = extra.wanted, kept = extra.kept,
        app_id = "MAIL" })
end
local function inputMode(seen, title)
    for _, input in ipairs(seen.inputs) do
        if input.title == title then return input.mode, input.initial end
    end
end

-- Kit, first time: an address, then a first message ---------------------------------

local kitKept = {}
local script = phone.script()
phone.push(script.actions, "claim")
phone.push(script.inputs, "kit")
-- The inbox is empty; Write.
phone.push(script.actions, "tab:write")
phone.push(script.inputs, "hello@foxgoods.com", "Lamp?", "is the lamp in stock?")
phone.push(script.confirms, true)
-- Straight to Sent, where it is.
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "To hello@foxgoods.com"))
    return "home"
end)
local seen = run(kit, script, { kept = kitKept })
assert(phone.said(seen, "You're in").body == "kit@foxy.com")
local mode, suggestion = inputMode(seen, "Your address")
assert(mode == "email" and suggestion == "kit.wolf",
    "the address box has @ and . on it, and suggests a name")
assert(inputMode(seen, "To") == "email" and inputMode(seen, "Message") == "text",
    "addresses and sentences each get a keyboard that can type them")
assert(phone.said(seen, "Sent"))
assert(kitKept.value.current == "kit@foxy.com", "and the app remembers it")

-- Ana: her own inbox first, then her company's --------------------------------------------

local anaKept = {}
script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "ana@foxy.com"),
        "her own address shows first")
    return "tab:me"
end, function(seen)
    assert(phone.has(phone.last(seen), "Fox Goods  1 new"),
        "the Me tab shows her company's address, with mail waiting")
    return "pick:2"
end)
-- Switched: the company inbox, with Kit's message, unread.
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "hello@foxgoods.com (1)"),
        "switched, with the count of what is waiting")
    return "open:1"
end, function(seen)
    assert(phone.has(phone.last(seen), "is the lamp in stock?"), "the message reads")
    return "reply"
end)
phone.push(script.inputs, function(seen)
    local _, to = inputMode(seen, "To")
    assert(to == "kit@foxy.com", "a reply is addressed to whoever wrote")
    return to
end, function(seen)
    local _, subject = inputMode(seen, "Subject")
    assert(subject == "Re: Lamp?")
    return subject
end, "yes, two left")
phone.push(script.confirms, true)
-- Back on the inbox, which keeps itself up to date.
phone.push(script.actions, "__tick", "home")
seen = run(ana, script, { kept = anaKept })
assert(anaKept.value.current == "hello@foxgoods.com", "the address she switched to is kept")
local kitsInbox = bank.request("MAIL_LIST", bank.as(kit, { address = "kit@foxy.com" })).messages
assert(kitsInbox[1].from == "hello@foxgoods.com" and kitsInbox[1].subject == "Re: Lamp?")
assert(mail.messages[kitsInbox[1].id].reply_to, "and it is marked as a reply")

-- Next time she opens it, she is where she left off; she adds an address.
script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "hello@foxgoods.com"), "where she left off")
    return "tab:me"
end, "pick:3")
phone.push(script.inputs, "support")
phone.push(script.actions, "home")
seen = run(ana, script, { kept = anaKept })
assert(phone.said(seen, "Added").body == "support@foxgoods.com")
assert(inputMode(seen, "New address") == "email")

-- Kit reads the reply and deletes it ----------------------------------------------------------

script = phone.script()
phone.push(script.actions, "open:1", "delete")
phone.push(script.confirms, true)
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Nothing here yet."), "the inbox is empty again")
    return "home"
end)
run(kit, script, { kept = kitKept })

-- From search: "Write an email" goes straight to writing -------------------------------------

script = phone.script()
phone.push(script.inputs, "ana@foxy.com", "Hi", "just saying hi")
phone.push(script.confirms, false)
phone.push(script.actions, "home")
seen = run(kit, script, { kept = kitKept, wanted = "write" })
assert(not phone.said(seen, "Sent"), "Not yet sends nothing")

-- Somebody with no address and no company, who does not want one ----------------------------

script = phone.script()
phone.push(script.actions, "back")
run(rob, script)
assert(not mail.personal[rob.id], "nothing was made for them")

print("host_foxmail_app_test: OK")
