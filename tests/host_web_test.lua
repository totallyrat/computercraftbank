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

local PAGES = {
    { title = "Fox Den", blocks = {
        { kind = "title", text = "Welcome" },
        { kind = "text", text = "The best den on the server." },
    } },
    { title = "Prices", blocks = {
        { kind = "text", text = "Everything is free." },
    } },
}

-- Publishing --------------------------------------------------------------------

webRejected("BAD_WEB_TOKEN", "WEB_PUBLISH",
    { domain = "foxden", token = "WEB-made-up", pages = PAGES })

-- A ticket for a name you do own does not let you publish to one you do not.
local kitSite = bank.request("WEB_RESERVE", bank.as(kit, { domain = "kitden" }))
local kitTicket = bank.request("WEB_TOKEN", bank.as(kit, { domain = "kitden" }))
webRejected("BAD_WEB_TOKEN", "WEB_PUBLISH",
    { domain = "foxden", token = kitTicket.token, pages = PAGES })

local ticket = bank.request("WEB_TOKEN", bank.as(ana, { domain = "foxden" }))
local published = web("WEB_PUBLISH",
    { domain = "foxden", token = ticket.token, pages = PAGES })
assert(published.pages == 2 and published.revision == 1)

-- One publish per ticket. A copied ticket is worth exactly what the owner
-- already used it for.
webRejected("BAD_WEB_TOKEN", "WEB_PUBLISH",
    { domain = "foxden", token = ticket.token, pages = PAGES })

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
assert(live.title == "Fox Den" and #live.blocks == 2)
assert(#live.pages == 2 and live.pages[2] == "Prices",
    "and the sub pages are listed so a reader can get to them")
assert(web("WEB_SITE", { domain = "foxden", page = 2 }).title == "Prices")

webRejected("NO_SUCH_DOMAIN", "WEB_SITE", { domain = "nobodyshome" })
-- Reserved but never published: still preparing rather than broken.
assert(web("WEB_SITE", { domain = "kitden" }).preparing,
    "a reserved name nobody has published to reads as preparing, not as a"
        .. " mistake by the visitor")

local directory = web("WEB_DIRECTORY", {})
assert(directory.total == 1 and directory.sites[1].domain == "foxden")

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
assert(not moved.preparing and moved.title == "Fox Den",
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
assert(web("WEB_DIRECTORY", {}).total == 0)

-- What the server will hold ----------------------------------------------------------

local tooMany = {}
for index = 1, 6 do
    tooMany[index] = { title = "Page " .. index, blocks = {} }
end
local moreTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
webRejected("TOO_MANY_PAGES", "WEB_PUBLISH",
    { domain = "foxhouse", token = moreTicket.token, pages = tooMany })

-- A page with nothing on it is refused rather than stored as a blank.
local blankTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
webRejected("BAD_PAGE", "WEB_PUBLISH", { domain = "foxhouse",
    token = blankTicket.token, pages = { { title = "", blocks = {} } } })

-- And a wall of text is cut to what a pocket screen can hold rather than
-- being taken whole.
local longTicket = bank.request("WEB_TOKEN",
    bank.as(ana, { domain = "foxhouse" }))
web("WEB_PUBLISH", { domain = "foxhouse", token = longTicket.token,
    pages = { { title = "Long", blocks = {
        { kind = "text", text = string.rep("x", 5000) },
        { kind = "text", text = "   " },
    } } } })
harness.day = harness.day + 1
local trimmed = web("WEB_SITE", { domain = "foxhouse" })
assert(#trimmed.blocks == 1, "an empty line is dropped, not stored")
assert(#trimmed.blocks[1].text <= (config.max_web_text or 240),
    "and a 5000 character paragraph is cut to what the format allows")

print("host_web_test: OK")
