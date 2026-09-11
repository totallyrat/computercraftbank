-- The Core/Vault split, and the rules that make it safe.
--
-- 9.3 cut the Bank in half. The half that holds money is bank_server.lua and
-- the half that holds everything else is bank_vault.lua, and between them is
-- a cable. Almost everything that could go wrong with that arrangement is
-- silent: a route that exists on one side and not the other simply stops
-- working; a Vault that is trusted to say who is asking is a Vault that can
-- be lied to; a cable that drops mid-payment is money in neither account.
--
-- So this file is not about features. It is about the seam.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local core, vault = bank.core, bank.vault
local rejected = harness.rejected

-- 1. Both sides agree on what the Vault answers ---------------------------------
-- The Core refuses to forward anything not in pair.routes, and the Vault
-- refuses anything it has no handler for. Either list drifting from the
-- other is a route that quietly stops existing, which is the sort of thing
-- that reaches a player rather than a test.

local missingOnVault = {}
for action in pairs(core.routes) do
    if not vault.actions[action] then
        missingOnVault[#missingOnVault + 1] = action
    end
end
assert(#missingOnVault == 0,
    "the Core forwards these, but the Vault cannot answer them: "
        .. table.concat(missingOnVault, ", "))

local missingOnCore = {}
for action in pairs(vault.actions) do
    -- VAULT_* are the Core's own errands, not routes a client can ask for.
    if not action:find("^VAULT_") and not core.routes[action] then
        missingOnCore[#missingOnCore + 1] = action
    end
end
assert(#missingOnCore == 0,
    "the Vault answers these, but nothing on the Core forwards them, so no"
        .. " client can reach them: " .. table.concat(missingOnCore, ", "))

-- And a route the Core forwards must not also exist on the Core, or which
-- copy answers depends on load order rather than on intent.
local both = {}
for action in pairs(core.routes) do
    if core.actions[action] then both[#both + 1] = action end
end
assert(#both == 0,
    "these exist on both halves, so which one answers is an accident: "
        .. table.concat(both, ", "))

-- 2. The Core keeps none of what it handed over -----------------------------------
-- The whole point of the split was the Bank's size. A table left behind on
-- the Core is both a second copy of the truth and the bytes back again.

for _, name in ipairs({ "conversations", "direct_conversations", "territories",
    "visas", "visits", "visa_applications", "border_controllers", "events",
    "tickets", "ticket_types", "app_data" }) do
    assert(bank.state[name] == nil,
        "a fresh Core must not create " .. name .. ": it belongs to the Vault")
end

local alice = bank.register("Alice Fox", "1111")
local bob = bank.register("Bob Wolf", "2222")
for _, field in ipairs({ "friends", "friend_requests_in", "conversation_ids" }) do
    assert(bank.state.accounts[alice.id][field] == nil,
        "an account on the Core must not carry " .. field)
end

-- 3. Who is asking is decided on the Core, never on the Vault ---------------------

bank.request("FRIEND_REQUEST", bank.as(alice, { account_id = bob.id }))
bank.request("FRIEND_RESPOND", bank.as(bob, { account_id = alice.id,
    accept = true }))
local chat = bank.request("CHAT_START",
    bank.as(alice, { account_ids = { bob.id } })).conversation

-- A session token never reaches the Vault, so a Vault that was lied to has
-- nothing to check the lie against -- and nothing to be fooled by.
local sawToken, sawPin = false, false
local realAsk = core.pair.ask
core.pair.ask = function(action, payload, timeout)
    local forwarded = payload and payload.payload or {}
    if forwarded.session_token ~= nil then sawToken = true end
    if forwarded.pin ~= nil then sawPin = true end
    return realAsk(action, payload, timeout)
end

bank.fund(alice, 500)
bank.request("CHAT_SEND_MONEY", bank.as(alice, {
    conversation_id = chat.conversation_id, amount = 50, pin = "1111" }))
assert(not sawToken, "a session token must never cross the cable")
assert(not sawPin, "and neither must a PIN")
core.pair.ask = realAsk

-- A wrong PIN is refused here, before anything is forwarded at all.
local forwardedDuringBadPin = 0
core.pair.ask = function(action, payload, timeout)
    forwardedDuringBadPin = forwardedDuringBadPin + 1
    return realAsk(action, payload, timeout)
end
rejected(bank.request, "BAD_PIN", "CHAT_SEND_MONEY", bank.as(alice, {
    conversation_id = chat.conversation_id, amount = 10, pin = "9999" }))
assert(forwardedDuringBadPin == 0,
    "a request with a bad PIN must not reach the Vault at all")
core.pair.ask = realAsk

-- The Vault answers its own Core and nobody else. Rednet ids are as strong
-- as anything else here, and without the check any computer on the network
-- could read every conversation by asking nicely.
rejected(vault.vault.VAULT_CALL, "NOT_MY_CORE",
    { action = "CHAT_LIST", caller = { account_id = alice.id } }, 99)
rejected(vault.vault.VAULT_CALL, "NO_CALLER", { action = "CHAT_LIST" },
    bank.core_id)

-- 4. Money is only ever moved by the Core ------------------------------------------

local worldBefore = bank.balanceOf(alice) + bank.balanceOf(bob)
    + (bank.state.tax_revenue or 0) + (bank.state.processing_fee_revenue or 0)

-- The cable dropping mid-payment must leave the money where it was, not in
-- neither account.
bank.unplug()
rejected(bank.request, "VAULT_OFFLINE", "CHAT_SEND_MONEY", bank.as(alice, {
    conversation_id = chat.conversation_id, amount = 25, pin = "1111" }))
local worldAfter = bank.balanceOf(alice) + bank.balanceOf(bob)
    + (bank.state.tax_revenue or 0) + (bank.state.processing_fee_revenue or 0)
assert(worldBefore == worldAfter,
    "an outage must not create or destroy money: " .. worldBefore .. " -> "
        .. worldAfter)

-- Banking itself keeps working with no Vault at all. This is the promise the
-- split rests on: the Vault is where the extras live, not the money.
local sent = bank.request("SEND_MONEY", bank.as(alice,
    { recipient = "Bob Wolf", amount = 20, pin = "1111" }))
assert(sent.amount == 20, "Send Money works with the Vault unplugged")
assert(bank.request("ACCOUNT_SUMMARY", bank.as(alice)).account.balance,
    "so does reading your own balance")
assert(bank.request("PUMPE_POLL", bank.as(alice)).balance,
    "and so does the OS poll")
bank.replug()

-- Asking the Core to move money twice under one id moves it once. A lost
-- reply is the case this exists for: the Vault cannot tell a lost reply from
-- a refusal, so it must be safe to ask again.
local twiceBefore = bank.balanceOf(alice)
local move = { move_id = "REPLAY1", from = alice.id, to = bob.id, amount = 10 }
core.pair.actions.CORE_MOVE(move, bank.vault_id)
local once = bank.balanceOf(alice)
core.pair.actions.CORE_MOVE(move, bank.vault_id)
assert(bank.balanceOf(alice) == once,
    "the same move id must not move the money a second time")
assert(twiceBefore - once == 10, "and the first one did move it")

-- Only the Vault may ask for any of that.
rejected(core.pair.actions.CORE_MOVE, "NOT_MY_PARTNER",
    { move_id = "X", from = alice.id, to = bob.id, amount = 1 }, 99)
rejected(core.pair.actions.CORE_GOV_PAY, "NOT_MY_PARTNER",
    { move_id = "Y", account_id = alice.id, amount = 1 }, 99)
rejected(core.pair.actions.CORE_VERIFY_PIN, "NOT_MY_PARTNER",
    { account_id = alice.id, pin = "1111" }, 99)

-- 5. The poll never crosses the cable -----------------------------------------------
-- Every PUMPE calls this several times a second. A cable hop inside it would
-- be felt on every phone on the server, so the Vault pushes what is waiting
-- and the Core answers out of its own memory.

local hops = 0
core.pair.ask = function(action, payload, timeout)
    hops = hops + 1
    return realAsk(action, payload, timeout)
end
bank.request("PUMPE_POLL", bank.as(alice))
bank.request("ACCOUNT_SUMMARY", bank.as(alice))
assert(hops == 0,
    "PUMPE_POLL and ACCOUNT_SUMMARY must answer without the Vault, and they"
        .. " asked it " .. hops .. " time(s)")
core.pair.ask = realAsk

-- What is waiting does reach the phone, by being pushed rather than pulled.
bank.request("URGENT_CALL", bank.as(alice, { account_id = bob.id }))
bank.sync()
local polled = bank.request("PUMPE_POLL", bank.as(bob))
assert(polled.call and polled.call.other_name == "Alice Fox",
    "a ringing call reaches the person being called through the Core's copy")

-- And a pushed entry cannot outlive its ring: if the Vault stops pushing,
-- the Core stops showing it rather than ringing forever.
bank.state.accounts[bob.id].waiting.call_expires_at = 0
assert(bank.request("PUMPE_POLL", bank.as(bob)).call == nil,
    "an expired push stops ringing even if nothing came to clear it")

print("host_vault_split_test: OK")
