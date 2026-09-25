-- FoxMail, 11.0, across a real Bank Core and Vault.
--
-- The rules that matter are about who may be whom: a person reads and sends
-- as their own address and their companies'; a Service Kiosk as its
-- company's; an app as its publisher's company's, and nothing else. The
-- Core knows who owns what, the Vault keeps the mail, and each is tested
-- against the real other half.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local mail = bank.vault.mail

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local rob = bank.register("Rob Hare", "9999")

local function as(who, extra) return bank.as(who, extra) end
local function send(who, extra) return bank.request("MAIL_SEND", as(who, extra)) end
local function inbox(who, address)
    return bank.request("MAIL_LIST", as(who, { address = address })).messages
end
local function notified(who, title)
    for _, note in ipairs(bank.notifications(who)) do
        if note.title == title then return note end
    end
    return nil
end

-- Companies, through a kiosk, the way they are made in the game.
local function company(owner, name)
    local made = bank.request("KIOSK_REGISTER", { name = name .. " Till" })
    local function till(extra)
        extra = extra or {}
        extra.terminal_id, extra.terminal_token =
            made.terminal_id, made.terminal_token
        return extra
    end
    local login = bank.request("KIOSK_OWNER_LOGIN", till({ name = owner.name,
        pin = owner.pin }))
    local created = bank.request("CREATE_COMPANY", till({
        owner_session = login.owner_session, company_name = name })).company
    bank.request("LINK_TERMINAL", till({ owner_session = login.owner_session,
        company_id = created.company_id }))
    return created, till
end
local foxGoods, foxTill = company(ana, "Fox Goods")
local wolfPack, wolfTill = company(kit, "Wolf Pack")

-- A person's own address ---------------------------------------------------------

local me = bank.request("MAIL_ME", as(kit))
assert(me.personal == nil and me.personal_domain == "foxy.com")
rejected(bank.request, "BAD_ADDRESS", "MAIL_CLAIM", as(kit, { name = "k" }))
rejected(bank.request, "BAD_ADDRESS", "MAIL_CLAIM", as(kit, { name = "kit wolf" }))
assert(bank.request("MAIL_CLAIM", as(kit, { name = "Kit" })).address
    == "kit@foxy.com", "lower-cased, at the Bank's domain")
rejected(bank.request, "HAS_ADDRESS", "MAIL_CLAIM", as(kit, { name = "kitty" }))
rejected(bank.request, "ADDRESS_TAKEN", "MAIL_CLAIM", as(ana, { name = "kit" }))
bank.request("MAIL_CLAIM", as(ana, { name = "ana" }))
bank.request("MAIL_CLAIM", as(rob, { name = "rob.hare" }))

-- A company's domain -------------------------------------------------------------------

rejected(bank.request, "NOT_OWNER", "MAIL_DOMAIN", as(kit, {
    company_id = foxGoods.company_id, domain = "foxgoods.com" }))
rejected(bank.request, "BAD_DOMAIN", "MAIL_DOMAIN", as(ana, {
    company_id = foxGoods.company_id, domain = "foxgoods" }))
rejected(bank.request, "DOMAIN_TAKEN", "MAIL_DOMAIN", as(ana, {
    company_id = foxGoods.company_id, domain = "foxy.com" }))
local domain = bank.request("MAIL_DOMAIN", as(ana, {
    company_id = foxGoods.company_id, domain = "FoxGoods.com", name = "hello" }))
assert(domain.domain == "foxgoods.com" and domain.address == "hello@foxgoods.com")
rejected(bank.request, "HAS_DOMAIN", "MAIL_DOMAIN", as(ana, {
    company_id = foxGoods.company_id, domain = "fox.shop" }))
rejected(bank.request, "DOMAIN_TAKEN", "MAIL_DOMAIN", as(kit, {
    company_id = wolfPack.company_id, domain = "foxgoods.com" }))
bank.request("MAIL_DOMAIN", as(kit, { company_id = wolfPack.company_id,
    domain = "wolfpack.com" }))

rejected(bank.request, "NOT_OWNER", "MAIL_ADDRESS", as(kit, {
    domain = "foxgoods.com", name = "sneaky" }))
bank.request("MAIL_ADDRESS", as(ana, { domain = "foxgoods.com", name = "support" }))
for _, name in ipairs({ "sales", "news", "jobs" }) do
    bank.request("MAIL_ADDRESS", as(ana, { domain = "foxgoods.com", name = name }))
end
rejected(bank.request, "TOO_MANY_ADDRESSES", "MAIL_ADDRESS", as(ana, {
    domain = "foxgoods.com", name = "more" }))

-- Ana has her own address and her company's, and sees them together: that
-- is what "more than one account at once" is.
me = bank.request("MAIL_ME", as(ana))
assert(me.personal == "ana@foxy.com")
assert(me.addresses[1].address == "ana@foxy.com", "her own first")
assert(#me.addresses == 6, "and her company's five")
assert(me.companies[1].domain == "foxgoods.com")
assert(#bank.request("MAIL_ME", as(rob)).addresses == 1, "Rob has only his own")

-- Sending, reading, replying -------------------------------------------------------------

rejected(bank.request, "NOT_YOURS", "MAIL_SEND", as(kit, {
    from = "hello@foxgoods.com", to = "rob.hare@foxy.com", subject = "Hi" }))
rejected(bank.request, "NO_SUCH_ADDRESS", "MAIL_SEND", as(kit, {
    from = "kit@foxy.com", to = "nobody@foxy.com", subject = "Hi" }))
rejected(bank.request, "EMPTY_MAIL", "MAIL_SEND", as(kit, {
    from = "kit@foxy.com", to = "hello@foxgoods.com" }))
rejected(bank.request, "TOO_MANY_RECIPIENTS", "MAIL_SEND", as(ana, {
    from = "hello@foxgoods.com", subject = "All of us",
    to = "kit@foxy.com, rob.hare@foxy.com, ana@foxy.com, support@foxgoods.com,"
        .. " sales@foxgoods.com, news@foxgoods.com" }))

local sent = send(kit, { from = "kit@foxy.com", to = "HELLO@foxgoods.com",
    subject = "Where is my lamp?", body = "Ordered it on day 300." })
assert(sent.to[1] == "hello@foxgoods.com")
assert(notified(ana, "Mail to hello@foxgoods.com"),
    "a company's mail is the owner's to hear about")
rejected(bank.request, "NOT_YOURS", "MAIL_LIST", as(kit, { address = "hello@foxgoods.com" }))
local waiting = inbox(ana, "hello@foxgoods.com")
assert(#waiting == 1 and not waiting[1].read and waiting[1].from == "kit@foxy.com")
rejected(bank.request, "NOT_YOURS", "MAIL_READ", as(rob, {
    address = "hello@foxgoods.com", id = waiting[1].id }))
local opened = bank.request("MAIL_READ", as(ana, { address = "hello@foxgoods.com",
    id = waiting[1].id })).message
assert(opened.body == "Ordered it on day 300.")
assert(inbox(ana, "hello@foxgoods.com")[1].read, "and it is read now")

send(ana, { from = "hello@foxgoods.com", to = "kit@foxy.com",
    subject = "Re: Where is my lamp?", body = "On its way.", reply_to = opened.id })
local reply = inbox(kit, "kit@foxy.com")[1]
assert(reply.from == "hello@foxgoods.com" and reply.subject == "Re: Where is my lamp?")
assert(notified(kit, "Mail to kit@foxy.com"), "a person hears about their own")
assert(bank.request("MAIL_LIST", as(kit, { address = "kit@foxy.com",
    box = "sent" })).messages[1].subject == "Where is my lamp?", "and has a Sent box")

-- A Service Kiosk is its company ---------------------------------------------------------

local tillMail = bank.request("KIOSK_MAIL_ME", foxTill())
assert(#tillMail.addresses == 5 and tillMail.personal == nil,
    "the till sees the company's addresses and nobody's own")
bank.request("KIOSK_MAIL_SEND", foxTill({ from = "support@foxgoods.com",
    to = "kit@foxy.com", subject = "Your receipt" }))
rejected(bank.request, "NOT_YOURS", "KIOSK_MAIL_SEND", wolfTill({
    from = "support@foxgoods.com", to = "kit@foxy.com", subject = "Fake" }))
rejected(bank.request, "NOT_YOURS", "KIOSK_MAIL_LIST", wolfTill({
    address = "hello@foxgoods.com" }))
assert(#bank.request("KIOSK_MAIL_LIST", foxTill({ address = "hello@foxgoods.com" }))
    .messages == 1, "and reads what came in")

-- An app sends as its publisher's company, and only that ------------------------------------

bank.state.app_owners = { FOXAPP = { account_id = ana.id, name = "Ana Fox",
    app_name = "Fox Goods" } }
local fromApp = bank.request("MAIL_APP_SEND", as(kit, { app_id = "FOXAPP",
    from = "news@foxgoods.com", to = "kit@foxy.com", subject = "Sale on!" }))
assert(fromApp.id)
local arrived = inbox(kit, "kit@foxy.com")[1]
assert(arrived.subject == "Sale on!" and arrived.app_name == "Fox Goods",
    "marked as sent by the app")
rejected(bank.request, "NOT_YOURS", "MAIL_APP_SEND", as(kit, { app_id = "FOXAPP",
    from = "kit@foxy.com", to = "rob.hare@foxy.com", subject = "Hi" }))
rejected(bank.request, "NOT_YOURS", "MAIL_APP_SEND", as(kit, { app_id = "FOXAPP",
    from = "hello@wolfpack.com", to = "rob.hare@foxy.com", subject = "Hi" }))
rejected(bank.request, "NOT_PUBLISHED", "MAIL_APP_SEND", as(kit, {
    app_id = "NOBODY", from = "news@foxgoods.com", to = "kit@foxy.com",
    subject = "Hi" }))
bank.state.app_mail.FOXAPP.count = 50
rejected(bank.request, "MAIL_LIMIT", "MAIL_APP_SEND", as(kit, { app_id = "FOXAPP",
    from = "news@foxgoods.com", to = "kit@foxy.com", subject = "Too many" }))

-- Keeping it small -------------------------------------------------------------------------

-- A mailbox keeps its newest thirty; a message shared by two boxes stays
-- until both have let it go.
local shared = send(rob, { from = "rob.hare@foxy.com",
    to = "kit@foxy.com, ana@foxy.com", subject = "Both of you" }).id
for index = 1, 30 do
    send(ana, { from = "ana@foxy.com", to = "kit@foxy.com",
        subject = "Note " .. index })
end
local kept = inbox(kit, "kit@foxy.com")
assert(#kept == 30 and kept[1].subject == "Note 30", "the newest thirty")
assert(mail.messages[shared], "still in Ana's inbox and Rob's Sent")
bank.request("MAIL_DELETE", as(ana, { address = "ana@foxy.com", id = shared }))
assert(mail.messages[shared], "still in Rob's Sent")
bank.request("MAIL_DELETE", as(rob, { address = "rob.hare@foxy.com", id = shared }))
assert(not mail.messages[shared], "and gone once nobody holds it")
rejected(bank.request, "NO_SUCH_MAIL", "MAIL_READ", as(rob, {
    address = "rob.hare@foxy.com", id = shared }))

-- Forty a day from one address: thirty notes already, ten more.
for _ = 1, 10 do
    send(ana, { from = "ana@foxy.com", to = "rob.hare@foxy.com", subject = "Hi" })
end
rejected(bank.request, "MAIL_LIMIT", "MAIL_SEND", as(ana, { from = "ana@foxy.com",
    to = "rob.hare@foxy.com", subject = "One too many" }))
bank.advanceDays(1)
send(ana, { from = "ana@foxy.com", to = "rob.hare@foxy.com", subject = "Tomorrow" })

print("host_mail_test: OK")
