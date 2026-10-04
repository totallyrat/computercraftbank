-- INVT, FoxyOS 14, against a real Bank Core and Vault.
--
-- Small events by Foxy: one price, a number of spots, no queue. A public
-- event is in everybody's feed; a private one only reaches the people its
-- host invited, as friends or by FoxMail address. Up to ten tickets an
-- account, paid tickets with the PIN and the money to the host, and only
-- the INVT app -- signed in with Foxy -- may ask.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
os.time = function() return harness.time end
harness.time = 12

local host = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local sam = bank.register("Sam Hare", "4321")
local lee = bank.register("Lee Owl", "1111")
for _, who in ipairs({ host, kit, sam, lee }) do bank.fund(who, 500) end
local today = harness.day

local function signIn(who)
    bank.request("FOXY_LOGIN_APPROVE", bank.as(who, { app_id = "INVT",
        app_name = "INVT", scopes = { "name" } }))
end
local function invt(who, action, extra)
    extra = extra or {}
    extra.app_id = "INVT"
    return bank.request(action, bank.as(who, extra))
end

-- Only INVT, and only signed in --------------------------------------------------------

rejected(invt, "NOT_SIGNED_IN", host, "INVT_FEED")
signIn(host)
rejected(bank.request, "WRONG_APP", "INVT_FEED", bank.as(host, { app_id = "SHOP" }))
rejected(bank.request, "APP_REQUIRED", "INVT_FEED", bank.as(host))
for _, who in ipairs({ kit, sam, lee }) do signIn(who) end

-- Making events ---------------------------------------------------------------------------

rejected(invt, "INVALID_TITLE", host, "INVT_CREATE", { title = "x", day = today + 1,
    time = "18:00", spots = 5 })
rejected(invt, "INVALID_TIME", host, "INVT_CREATE", { title = "Party", day = today - 1,
    time = "18:00", spots = 5 })
rejected(invt, "INVALID_SPOTS", host, "INVT_CREATE", { title = "Party", day = today + 1,
    time = "18:00", spots = 0 })
local party = invt(host, "INVT_CREATE", { title = "Garden Party",
    description = "Bring snacks", day = today + 1, time = "18:00", spots = 12,
    price = 0, public = false }).event
local quiz = invt(host, "INVT_CREATE", { title = "Quiz Night", day = today + 2,
    time = "20:00", spots = 15, price = 5, public = true }).event
assert(party.host and party.left == 12 and not party.public and quiz.price == 5)

-- The feed: public for everybody, private only for the invited.
local function feedOf(who)
    local titles = {}
    for _, event in ipairs(invt(who, "INVT_FEED").events) do titles[#titles + 1] = event.title end
    return table.concat(titles, ",")
end
assert(feedOf(host) == "Garden Party,Quiz Night", "the host sees both, soonest first")
assert(feedOf(kit) == "Quiz Night", "a private party is nobody else's business")
rejected(invt, "NOT_INVITED", kit, "INVT_EVENT", { invt_id = party.invt_id })
rejected(invt, "NOT_INVITED", kit, "INVT_JOIN", { invt_id = party.invt_id, quantity = 1 })

-- Inviting: a friend, and somebody by FoxMail -------------------------------------------------

rejected(invt, "NOT_FRIENDS", host, "INVT_INVITE", { invt_id = party.invt_id,
    account_id = kit.id })
bank.request("FRIEND_REQUEST", bank.as(host, { name = "Kit Wolf" }))
bank.request("FRIEND_REQUEST", bank.as(kit, { name = "Ana Fox" }))
local friends = invt(host, "INVT_FRIENDS").friends
assert(#friends == 1 and friends[1].name == "Kit Wolf", "friends to pick from")
invt(host, "INVT_INVITE", { invt_id = party.invt_id, account_id = kit.id })
rejected(invt, "ALREADY_INVITED", host, "INVT_INVITE", { invt_id = party.invt_id,
    account_id = kit.id })
bank.request("MAIL_CLAIM", bank.as(host, { name = "ana" }))
bank.request("MAIL_CLAIM", bank.as(sam, { name = "sam" }))
rejected(invt, "NO_SUCH_ADDRESS", host, "INVT_INVITE", { invt_id = party.invt_id,
    address = "nobody@foxy.com" })
local byMail = invt(host, "INVT_INVITE", { invt_id = party.invt_id,
    address = "SAM@foxy.com" }).invited
assert(byMail.name == "Sam Hare" and byMail.mailed, "invited by FoxMail, and mailed")
local inbox = bank.request("MAIL_LIST", bank.as(sam, { address = "sam@foxy.com" }))
assert(inbox.messages[1].from == "ana@foxy.com"
    and inbox.messages[1].subject == "You're invited: Garden Party")
rejected(invt, "NOT_OWNER", kit, "INVT_INVITE", { invt_id = party.invt_id,
    address = "sam@foxy.com" })
assert(feedOf(kit) == "Garden Party,Quiz Night", "invited, it is in the feed")
assert(invt(kit, "INVT_EVENT", { invt_id = party.invt_id }).event.invited)
assert(invt(kit, "INVT_EVENT", { invt_id = party.invt_id }).event.guests == nil,
    "the guest list is the host's")

-- Tickets ------------------------------------------------------------------------------------

local joined = invt(kit, "INVT_JOIN", { invt_id = party.invt_id, quantity = 3 })
assert(#joined.codes == 3 and joined.total == 0 and joined.event.mine == 3,
    "free, no PIN, three tickets")
rejected(invt, "LIMIT_REACHED", kit, "INVT_JOIN", { invt_id = party.invt_id, quantity = 8 })
invt(kit, "INVT_JOIN", { invt_id = party.invt_id, quantity = 7 })
rejected(invt, "LIMIT_REACHED", kit, "INVT_JOIN", { invt_id = party.invt_id, quantity = 1 })
rejected(invt, "SOLD_OUT", sam, "INVT_JOIN", { invt_id = party.invt_id, quantity = 3 })
invt(sam, "INVT_JOIN", { invt_id = party.invt_id, quantity = 2 })
rejected(invt, "OWN_EVENT", host, "INVT_JOIN", { invt_id = party.invt_id, quantity = 1 })

-- Paid: through the PIN, the money to the host.
rejected(invt, "PIN_REQUIRED", lee, "INVT_JOIN", { invt_id = quiz.invt_id, quantity = 2 })
rejected(invt, "BAD_PIN", lee, "INVT_BUY", { invt_id = quiz.invt_id, quantity = 2,
    pin = "0000" })
local bought = invt(lee, "INVT_BUY", { invt_id = quiz.invt_id, quantity = 2, pin = "1111" })
assert(bought.total == 10 and #bought.codes == 2)
assert(bank.balanceOf(lee) == 990 and bank.balanceOf(host) == 1010, "5 each, to Ana")

-- The drawer: your tickets, soonest first, with their codes.
local mine = invt(kit, "INVT_TICKETS").tickets
assert(#mine == 10 and mine[1].title == "Garden Party" and #mine[1].code == 6)
assert(invt(kit, "INVT_FEED").tickets == 10, "the feed knows how many you hold")

-- The host's view: who is coming, who was invited.
local hostView = invt(host, "INVT_EVENT", { invt_id = party.invt_id }).event
assert(hostView.taken == 12 and hostView.left == 0 and #hostView.guests == 2)
assert(#hostView.invites == 2 and hostView.invites[1].going)

-- At the door.
local door = invt(host, "INVT_CHECKIN", { invt_id = party.invt_id, code = mine[1].code })
assert(door.valid and door.name == "Kit Wolf")
local again = invt(host, "INVT_CHECKIN", { invt_id = party.invt_id, code = mine[1].code })
assert(not again.valid and again.already, "a ticket gets in once")
assert(not invt(host, "INVT_CHECKIN", { invt_id = party.invt_id, code = "ZZZZZZ" }).valid)
rejected(invt, "NOT_OWNER", kit, "INVT_CHECKIN", { invt_id = party.invt_id, code = "ZZZZZZ" })

-- Calling it off refunds whoever paid -----------------------------------------------------

rejected(invt, "NOT_OWNER", lee, "INVT_CANCEL", { invt_id = quiz.invt_id })
local cancelled = invt(host, "INVT_CANCEL", { invt_id = quiz.invt_id })
assert(cancelled.refunded == 10 and bank.balanceOf(lee) == 1000
    and bank.balanceOf(host) == 1000, "Lee has their 10 back")
assert(feedOf(lee) == "", "and the event is gone from the feed")
rejected(invt, "NOT_FOUND", lee, "INVT_EVENT", { invt_id = quiz.invt_id })

-- A host who cannot cover the refunds is told before anything moves.
local gig = invt(host, "INVT_CREATE", { title = "Gig", day = today + 3, time = "21:00",
    spots = 50, price = 100, public = true }).event
invt(lee, "INVT_BUY", { invt_id = gig.invt_id, quantity = 1, pin = "1111" })
invt(kit, "INVT_BUY", { invt_id = gig.invt_id, quantity = 1, pin = "5678" })
-- Enough for one refund, not for both: nobody is refunded and the gig stays.
bank.state.accounts[host.id].balance = 150
local leeBefore, kitBefore = bank.balanceOf(lee), bank.balanceOf(kit)
rejected(invt, "INSUFFICIENT_FUNDS", host, "INVT_CANCEL", { invt_id = gig.invt_id })
assert(bank.balanceOf(lee) == leeBefore and bank.balanceOf(kit) == kitBefore
    and bank.balanceOf(host) == 150, "nothing moved, not even half of it")
assert(invt(lee, "INVT_EVENT", { invt_id = gig.invt_id }).event.title == "Gig")

print("host_invt_test: OK")
