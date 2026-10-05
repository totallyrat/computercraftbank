-- Shop Websites, FoxyOS 15, end to end against a real Bank.
--
-- Ana puts her store on the web from its Store page in the Company app:
-- an address, name.shop, pre-filled from the company's name. Kit's Pocket
-- opens it as the store itself -- Shop, locked to that store, with the
-- address where the tagline was. The Shop Apps of FoxyOS 14 are gone: the
-- Bank says so to a Company app that still offers one, and the App Server
-- takes what is left of them out of its catalogue.
-- (The Pocket's half -- a .shop address opened from Internet, and an
-- installed Shop App coming off -- is in host_settings_test.lua.)

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local phone = require("phone_app_harness")

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local function owner(action, extra)
    extra = extra or {}
    extra.app_id = "COMPANY"
    return bank.request(action, bank.as(ana, extra))
end
local company = owner("COMPANY_CREATE", { company_name = "Fox Goods" }).company
local id = company.company_id
owner("COMPANY_PRODUCT_ADD", { company_id = id, name = "Lamp", price = 12,
    kind = "one_time" })
owner("COMPANY_PRODUCT_SET", { company_id = id,
    item_id = bank.state.companies[id].quick_items[1].item_id, online = true,
    blurb = "Warm light" })

local kept = {}
local browsed = {}
local function companyApp(script)
    return phone.run({ bank = bank, who = ana, file = "../company.lua", script = script,
        app_id = "COMPANY", kept = kept,
        browse = function(domain) browsed[#browsed + 1] = domain end })
end

-- A closed store cannot have one ----------------------------------------------------------

local script = phone.script()
phone.push(script.actions, "company:1", "tab:store", function(seen)
    assert(phone.has(phone.last(seen), "Put it on the web"), "on the store's page")
    return "shopsite"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Choose an address"))
    assert(phone.has(frame, "foxgoods.shop"), "an example from the company's own name")
    return "make"
end, "back", "home", "home")
phone.push(script.inputs, "foxgoods")
local seen = companyApp(script)
assert(seen.inputs[1].mode == "domain" and seen.inputs[1].initial == "foxgoods",
    "typed on the keyboard with a full stop, pre-filled from the name")
assert(phone.said(seen, "Not changed").body == "Open the store first")
assert(bank.state.companies[id].shop_site == nil)

-- Open, it goes on the web ------------------------------------------------------------------

owner("COMPANY_SHOP_SETUP", { company_id = id, open = true })
script = phone.script()
phone.push(script.actions, "company:1", "tab:store", "shopsite", "make", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "YOUR ADDRESS") and phone.has(frame, "foxgoods.shop"),
        "the address, on the page")
    return "visit"
end, "rename", function(seen)
    assert(phone.has(phone.last(seen), "fox-goods.shop"), "renamed")
    return "back"
end, function(seen)
    assert(phone.has(phone.last(seen), "Web: fox-goods.shop"),
        "the store's page says where it is on the web")
    return "shopsite"
end, "down", "back", function(seen)
    assert(phone.has(phone.last(seen), "Put it on the web"), "and that it is not any more")
    return "home"
end, "home")
phone.push(script.inputs, "FoxGoods", "fox-goods")
phone.push(script.confirms, true)
seen = companyApp(script)
assert(phone.said(seen, "On the web").body == "foxgoods.shop", "typed in capitals, kept lower case")
assert(browsed[1] == "foxgoods.shop", "Open it opens it in the browser")
assert(phone.said(seen, "Taken down"))
assert(bank.state.companies[id].shop_site == nil)
rejected(bank.request, "NO_SUCH_SITE", "SHOP_SITE", { domain = "fox-goods.shop" })

-- Back up for Kit.
owner("COMPANY_SHOP_SITE", { company_id = id, site = "foxgoods" })

-- Kit opens it: the store's own front door, the address on top ---------------------------
-- What a Pocket runs for a .shop address: Shop, told the store and the address.

local found = bank.request("SHOP_SITE", { domain = "foxgoods.shop" })
local scratch = os.tmpname()
local handle = assert(io.open(scratch, "w"))
handle:write("local shop = assert(loadfile('../shop.lua'))()\n"
    .. "return function(api)\n"
    .. "    api.shop_store = " .. string.format("%q", found.company_id) .. "\n"
    .. "    api.domain = " .. string.format("%q", found.domain) .. "\n"
    .. "    return shop(api)\n"
    .. "end\n")
handle:close()
script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox Goods") and phone.has(frame, "Shop now"),
        "the store's own front door")
    assert(phone.has(frame, "foxgoods.shop"), "with its address where the tagline was")
    assert(not phone.has(frame, "Search stores"), "not every store there is")
    return "shop"
end, function(seen)
    assert(phone.has(phone.last(seen), "Lamp  $12"), "the store's products")
    return "back"
end, "home")
phone.run({ bank = bank, who = kit, file = scratch, script = script, app_id = "SHOP" })
os.remove(scratch)

-- Shop Apps are gone ----------------------------------------------------------------------

rejected(owner, "SHOP_APPS_RETIRED", "COMPANY_SHOP_APP", { company_id = id, name = "Fox" })
assert(not pcall(bank.request, "SHOP_APPS", {}), "and nobody lists them any more")

-- The App Server takes what is left of them out of its catalogue.
local files = {}
local function canonical(path)
    path = tostring(path or ""):gsub("/+", "/"):gsub("/$", "")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return canonical(tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", ""))
    end,
    exists = function(path) return files[canonical(path)] ~= nil end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function(path) files[canonical(path)] = nil end,
    open = function(path, mode)
        path = canonical(path)
        if mode and mode:find("r") then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end, close = function() end }
        end
        local chunks = {}
        return { write = function(v) chunks[#chunks + 1] = tostring(v) end,
            close = function() files[path] = table.concat(chunks) end }
    end,
}
shell = { getRunningProgram = function() return "/pumpe/app_server.lua" end }
term = { current = function() return { getSize = function() return 51, 19 end } end }
local realNet = package.loaded["lib.net"]
package.loaded["lib.net"] = { client = function()
    return { discover = function() return 1 end,
        request = function() error("the App Server has nothing to ask the Bank about stores") end }
end, autoUpdate = function() end }
PUMPE_TEST_MODE = true
local server = assert(loadfile("../app_server.lua"))()
PUMPE_TEST_MODE = nil
package.loaded["lib.net"] = realNet
server.state.apps["SA-" .. id] = { app_id = "SA-" .. id, name = "Fox Goods",
    developer_id = "SHOPAPP", shop_app = id, version = 3 }
server.state.apps.NOTES = { app_id = "NOTES", name = "Notes", developer_id = "DEV1", version = 1 }
server.state.order = { "SA-" .. id, "NOTES" }
files["/pumpe/appstore/SA-" .. id .. ".lua"] = "-- an old Shop App"
assert(server.retire_shop_apps() == 1)
assert(server.state.apps["SA-" .. id] == nil and not files["/pumpe/appstore/SA-" .. id .. ".lua"],
    "the Shop App and its file are gone")
assert(server.state.apps.NOTES and #server.state.order == 1, "and nothing else")
for _, app in ipairs(server.actions.APP_LIST({}).apps) do
    assert(not app.app_id:match("^SA%-"), "no Pocket is offered one again")
end
assert(server.retire_shop_apps() == 0, "once is enough")

print("host_shop_website_test: OK")
