-- Handing the records over, once.
--
-- A Bank upgrading from 9.2 is still holding every conversation, territory,
-- visa, event and app record in its own state file, because until 9.3 that
-- is where they lived. Pairing a Vault has to move them across and then let
-- go -- and the order matters: acknowledged first, dropped second, so an
-- interrupted handover leaves the data on the Core rather than nowhere.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local core, vault = bank.core, bank.vault

local alice = bank.register("Alice Fox", "1111")
local bob = bank.register("Bob Wolf", "2222")

-- A Bank as 9.2 left it: the records on the Core, and the social half of an
-- account sitting on the account itself.
local state = bank.state
state.conversations = {
    CHAT00000007 = {
        conversation_id = "CHAT00000007",
        kind = "direct",
        member_ids = { alice.id, bob.id },
        members = { [alice.id] = { last_read_seq = 1 },
                    [bob.id] = { last_read_seq = 0 } },
        messages = { { seq = 1, sender_id = alice.id, kind = "text",
                       body = "brought from 9.2", at = 1 } },
        next_seq = 2,
        last_at = 1,
    },
}
state.direct_conversations = { [alice.id .. "|" .. bob.id] = "CHAT00000007" }
state.territories = {
    TER000003 = {
        territory_id = "TER000003", name = "Old Country",
        owner_account_id = alice.id,
        citizen_account_ids = { [alice.id] = true },
        free_roam_territory_ids = {},
        status = "active", created_day = 1,
    },
}
state.territory_names = { ["old country"] = "TER000003" }
state.events = {
    EVT000002 = {
        event_id = "EVT000002", title = "Harvest Fair",
        organizer_account_id = alice.id, ticket_type_ids = {},
        status = "active", event_day = 999, event_time = "12:00",
        location = "Square", description = "",
    },
}
state.app_data = { yap = { posts = { items = {}, sequence = 4 } } }
state.sequence.conversation = 7
state.sequence.territory = 3
state.sequence.event = 2
state.accounts[alice.id].friends = { [bob.id] = true }
state.accounts[bob.id].friends = { [alice.id] = true }
state.accounts[alice.id].conversation_ids = { CHAT00000007 = true }
state.accounts[bob.id].conversation_ids = { CHAT00000007 = true }
state.accounts[alice.id].government_conversation_id = nil

-- An interrupted handover keeps the data ---------------------------------------
-- The cable dropping halfway must not be the moment a server's history stops
-- existing. Nothing is dropped here until the Vault has said it has it.
bank.unplug()
local handed, why = core.pair.migrate()
assert(not handed and why, "a failed handover reports rather than pretending")
assert(state.conversations.CHAT00000007,
    "and the Core still has the conversation, because the Vault never"
        .. " confirmed it")
assert(state.accounts[alice.id].friends[bob.id],
    "and still has the friendship")
bank.replug()

-- The real handover ---------------------------------------------------------------
assert(core.pair.migrate(), "with a Vault answering, it goes across")

for _, name in ipairs({ "conversations", "direct_conversations", "territories",
    "territory_names", "events", "app_data" }) do
    assert(state[name] == nil,
        "the Core let go of " .. name .. " once the Vault confirmed it")
end
for _, field in ipairs({ "friends", "conversation_ids" }) do
    assert(state.accounts[alice.id][field] == nil,
        "and let go of the account's " .. field)
end

assert(bank.vault_state.conversations.CHAT00000007,
    "the Vault has the conversation")
assert(bank.vault_state.territories.TER000003, "and the territory")
assert(bank.vault_state.events.EVT000002, "and the event")
assert(bank.vault_state.holders[alice.id].friends[bob.id],
    "and the friendship, under the person it belongs to")

-- The counters have to travel too, or the Vault starts numbering at one and
-- writes a second CHAT00000001 over somebody's conversation.
assert(bank.vault_state.sequence.conversation == 7,
    "the Vault carries on numbering where the Core stopped")
assert(bank.vault_state.sequence.territory == 3)
assert(state.sequence.conversation == nil,
    "and the Core stops keeping a counter for something it no longer writes")

-- What moved is usable, not just present -------------------------------------------
local listed = bank.request("CHAT_LIST", bank.as(alice)).conversations
assert(#listed == 1 and listed[1].conversation_id == "CHAT00000007",
    "the conversation reads back through the Core exactly as before")
assert(listed[1].title == "Bob Wolf", "with the other person's name on it")

local opened = bank.request("CHAT_OPEN",
    bank.as(bob, { conversation_id = "CHAT00000007" }))
assert(#opened.messages == 1 and opened.messages[1].body == "brought from 9.2",
    "and the message that was written in 9.2 is still readable")

local friends = bank.request("FRIEND_OVERVIEW", bank.as(alice)).friends
assert(#friends == 1 and friends[1].name == "Bob Wolf",
    "and the friendship survived the move with a name attached")

local mine = bank.request("CUSTOMS_OVERVIEW", bank.as(alice)).territories
assert(#mine == 1 and mine[1].name == "Old Country",
    "and so did the territory")

-- A new conversation must not collide with the numbering it inherited.
local fresh = bank.request("CHAT_START",
    bank.as(alice, { account_ids = { bob.id } })).conversation
assert(fresh.conversation_id == "CHAT00000007",
    "a direct chat that already exists is still the same one")

-- Running it again is harmless ------------------------------------------------------
assert(core.pair.migrate(), "a second handover has nothing to do")
assert(bank.vault_state.conversations.CHAT00000007,
    "and does not undo the first one")

print("host_vault_migration_test: OK")
