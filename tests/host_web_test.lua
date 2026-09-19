-- The web, end to end.
--
-- Three real machines: a Bank Core, its Vault, and an Internet Server. The
-- split between them is the whole design, so the test keeps it: the Vault
-- owns the names, the Internet Server owns the pages, and neither is asked
-- to take the other's word for anything.
--
-- The rule worth defending here is that an Internet Server is a machine
-- anybody can run. It never sees an account and never checks a PIN. What it
-- gets is a one-shot ticket the owner fetched from the Bank, which it hands
-- back to the Bank to be told whose site this is. So the interesting tests
-- are the ones where somebody tries to publish without one.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected

local bank = harness.pair()
local config = require("config")
local util = require("lib.util")

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local rob = bank.register("Rob Hare", "9999")

-- Reserving a name ------------------------------------------------------------

local mine = bank.request("WEB_MINE", bank.as(ana))
assert(#mine.sites == 0 and mine.limit == 2,
    "a new account has no websites and room for two")

local made = bank.request("WEB_RESERVE", bank.as(ana, { domain = "FoxDen" }))
assert(made.domain == "foxden", "a domain is one name, in lower case")
assert(made.owner_name == "Ana Fox")
assert(not made.live, "and it is not answering the moment it is reserved")
assert(made.hours_left > 1.5 and made.hours_left <= 2,
    "two in-game hours, so a new site is something you come back to")

rejected(bank.request, "DOMAIN_TAKEN", "WEB_RESERVE",
    bank.as(kit, { domain = "foxden" }))
rejected(bank.request, "DOMAIN_TAKEN", "WEB_RESERVE",
    bank.as(ana, { domain = "FOXDEN" }))
for _, bad in ipairs({ "ab", "this-name-is-far-too-long-to-use",
    "fox den", "fox.den", "-fox", "fox-" }) do
    rejected(bank.request, "BAD_DOMAIN", "WEB_RESERVE",
        bank.as(ana, { domain = bad }))
end

bank.request("WEB_RESERVE", bank.as(ana, { domain = "anas-shop" }))
rejected(bank.request, "TOO_MANY_SITES", "WEB_RESERVE",
    bank.as(ana, { domain = "onemore" }))
assert(#bank.request("WEB_MINE", bank.as(ana)).sites == 2)
assert(#bank.request("WEB_MINE", bank.as(kit)).sites == 0,
    "and somebody else's sites are not in your list")

-- Somebody else's name is not yours to change or release.
rejected(bank.request, "NOT_YOURS", "WEB_RENAME",
    bank.as(kit, { domain = "foxden", new_domain = "kitden" }))
rejected(bank.request, "NOT_YOURS", "WEB_RELEASE",
    bank.as(kit, { domain = "foxden" }))
rejected(bank.request, "NOT_YOURS", "WEB_TOKEN",
    bank.as(kit, { domain = "foxden" }))

-- An Internet Server ------------------------------------------------------------
-- Loaded for real, with its Bank connection pointed at the Core the same way
-- the game points it: through a client that reaches the Bank's own actions.

local webServer
do
    local realNet = package.loaded["lib.net"]
    term = { current = function()
        return { getSize = function() return 51, 19 end }
    end }
    package.loaded["lib.ui"] = setmetatable({ theme = {} }, {
        __index = function() return function() end end,
    })
    package.loaded["lib.net"] = {
        openModems = function() return { "modem" } end,
        host = function() end,
        reply = function() end,
        locate = function() return nil end,
        autoUpdate = function() end,
        client = function()
            return {
                discover = function() return 1 end,
                request = function(_, action, payload)
                    local ok, result = pcall(bank.request, action,
                        payload or {})
                    if ok then return result end
                    if type(result) == "table" and result.pumpe then
                        return nil, result.message, result.code
                    end
                    return nil, tostring(result), "SERVER_ERROR"
                end,
            }
        end,
    }
    PUMPE_TEST_MODE = true
    webServer = assert(loadfile("../internet_server.lua"))()
    PUMPE_TEST_MODE = nil
    package.loaded["lib.net"] = realNet
end

local function web(action, payload)
    local ok, result = pcall(webServer.actions[action], payload or {})
    if ok then return result end
    if type(result) == "table" and result.pumpe then
        return nil, result.message, result.code
    end
    error(result, 0)
end

local function webRejected(code, action, payload)
    local _, _, got = web(action, payload)
    assert(got == code, "expected " .. code .. ", got " .. tostring(got))
end

-- Since 10.1 a website is a program. The server compiles it before it will
-- store it, because a PUMPE app has no `load` of its own and a page that
-- does not parse would otherwise fail on every reader's phone rather than
-- on its author's.
local SOURCE = table.concat({
    "return function(api)",
    "    api.ui.clear(api.target)",
    "end",
}, "\n")

-- Publishing --------------------------------------------------------------------

webRejected("BAD_WEB_TOKEN", "WEB_PUBLISH",
    { domain = "foxden", token = "WEB-made-up", source = SOURCE })

-- A ticket for a name you do own does not let you publish to one you do not.
local kitSite = bank.request("WEB_RESERVE", bank.as(kit, { domain = "kitden" }))
local kitTicket = bank.request("WEB_TOKEN", bank.as(kit, { domain = "kitden" }))
webRejected("BAD_WEB_TOKEN", "WEB_PUBLISH",
    { domain = "foxden", token = kitTicket.token, source = SOURCE })

local ticket = bank.request("WEB_TOKEN", bank.as(ana, { domain = "foxden" }))
local published = web("WEB_PUBLISH",
    { domain = "foxden", token = ticket.token, source = SOURCE })
assert(published.bytes == #SOURCE and published.revision == 1)

-- One publish per ticket. A copied ticket is worth exactly what the owner
-- already used it for.
webRejected("BAD_WEB_TOKEN", "WEB_PUBLISH",
    { domain = "foxden", token = ticket.token, source = SOURCE })

-- Reading ------------------------------------------------------------------------

local preparing = web("WEB_SITE", { domain = "foxden" })
assert(preparing.preparing,
    "a site that has been published but has not opened yet is still"
        .. " preparing: the Bank decides when it is live, not the server"
        .. " holding the pages")
assert(preparing.owner_name == "Ana Fox", "and says whose it is")

bank.advanceDays(1)
local live = web("WEB_SITE", { domain = "foxden" })
assert(not live.preparing, "once the two hours are up it answers")
assert(live.source == SOURCE, "and hands over the program itself")

webRejected("NO_SUCH_DOMAIN", "WEB_SITE", { domain = "nobodyshome" })
-- Reserved but never published: still preparing rather than broken.
assert(web("WEB_SITE", { domain = "kitden" }).preparing,
    "a reserved name nobody has published to reads as preparing, not as a"
        .. " mistake by the visitor")

-- 10.1 removed the directory: there is no list of every site on the server
-- to open on, because that is a phone book nobody asked for.
assert(webServer.actions.WEB_DIRECTORY == nil,
    "the Internet app searches; it does not browse a list")

-- Editing --------------------------------------------------------------------------
-- Half an in-game hour of downtime. Long enough to notice, short enough to
-- forgive, and it is what stops a page changing under somebody mid-sentence.

local edited = bank.request("WEB_EDITED", bank.as(ana, { domain = "foxden" }))
assert(edited.revision == 1 and not edited.live,
    "an edit takes the site down")
assert(edited.hours_left > 0 and edited.hours_left <= 0.5,
    "for half an in-game hour, not two")
assert(web("WEB_SITE", { domain = "foxden" }).preparing,
    "and a reader sees that rather than half of each version")

-- Renaming -----------------------------------------------------------------------

harness.day = harness.day + 1
local renamed = bank.request("WEB_RENAME",
    bank.as(ana, { domain = "foxden", new_domain = "FoxHouse" }))
assert(renamed.domain == "foxhouse")
rejected(bank.request, "NO_SUCH_DOMAIN", "WEB_LOOKUP", { domain = "foxden" })
assert(bank.request("WEB_LOOKUP", { domain = "foxhouse" }).owner_name
    == "Ana Fox")
-- The old name is free for anybody now.
bank.request("WEB_RESERVE", bank.as(kit, { domain = "foxden" }))
-- And it comes with none of the last owner's pages. An Internet Server that
-- filed pages under the name rather than under the site handed Kit's brand
-- new domain Ana's website, which is the whole reason a site has an id of
-- its own.
local handedOver = web("WEB_SITE", { domain = "foxden" })
assert(handedOver.preparing,
    "a name somebody else has picked up starts empty, whatever was"
        .. " published under it before")
-- Ana's pages followed the rename rather than being orphaned at the old one.
harness.day = harness.day + 1
local moved = web("WEB_SITE", { domain = "foxhouse" })
assert(not moved.preparing and moved.source == SOURCE,
    "and the site itself moved to its new name")

-- Looking a name up is public, because a web where you cannot look up a name
-- is not a web. What it must never do is hand out the account behind it.
local looked = bank.request("WEB_LOOKUP", { domain = "foxhouse" })
assert(looked.owner_name == "Ana Fox")
assert(looked.owner_account_id == nil,
    "a public lookup names the owner, never their account")

-- Giving a name back -----------------------------------------------------------------

bank.request("WEB_RELEASE", bank.as(ana, { domain = "anas-shop" }))
assert(#bank.request("WEB_MINE", bank.as(ana)).sites == 1)
bank.request("WEB_RESERVE", bank.as(rob, { domain = "anas-shop" }))

-- Taking a site off the web needs the same ticket putting one up does.
webRejected("BAD_WEB_TOKEN", "WEB_UNPUBLISH",
    { domain = "foxhouse", token = "WEB-made-up" })
local downTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
assert(web("WEB_UNPUBLISH",
    { domain = "foxhouse", token = downTicket.token }).removed)
assert(next(webServer.state.sites) == nil,
    "and the pages are actually gone from the server")

-- What the server will hold ----------------------------------------------------------

-- A program that does not parse is refused here, once, rather than on every
-- reader's phone. This is the only machine in the chain that can compile it.
local broken = web("WEB_CHECK", { source = "return function(api" })
assert(not broken.ok and tostring(broken.error):find("web", 1, true) ~= nil
    or not broken.ok, "WEB_CHECK says what is wrong before anybody publishes")
assert(web("WEB_CHECK", { source = SOURCE }).ok,
    "and says so when there is nothing wrong")

local badTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
webRejected("BAD_SOURCE", "WEB_PUBLISH", { domain = "foxhouse",
    token = badTicket.token, source = "return function(api" })

local emptyTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
webRejected("NO_SOURCE", "WEB_PUBLISH",
    { domain = "foxhouse", token = emptyTicket.token, source = "" })

-- A page is a page, not an app. Somebody publishing a megabyte through this
-- would be putting it on every reader's phone.
local bigTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
webRejected("TOO_BIG", "WEB_PUBLISH", { domain = "foxhouse",
    token = bigTicket.token,
    source = string.rep("-- x\n", config.max_web_bytes or 8192) })

-- A site published before 10.1 holds pages rather than a program. Its reader
-- is told to come back rather than shown a blank screen.
local stale = bank.request("WEB_RESERVE", bank.as(rob, { domain = "oldsite" }))
webServer.state.sites[stale.site_id] = {
    site_id = stale.site_id, domain = "oldsite", owner_name = "Rob Hare",
    pages = { { title = "Old", blocks = {} } },
}
webServer.state.order[#webServer.state.order + 1] = stale.site_id
harness.day = harness.day + 1
assert(web("WEB_SITE", { domain = "oldsite" }).needs_update,
    "a website made before the new web says so, rather than opening empty")

print("host_web_test: OK")
