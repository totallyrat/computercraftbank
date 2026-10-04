-- Shop Apps, FoxyOS 14: a store's own app, end to end, against a real Bank.
--
-- Ana turns one on from her store's page in the Company app. The App Server
-- asks the Bank which stores have one and builds each from the Shop app,
-- locked to its store, listed under the company's name. Kit installs it: it
-- opens on the store's own front door, not the list of every store. Taken
-- down, it leaves the App Browser.

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
local lamp = owner("COMPANY_PRODUCT_ADD", { company_id = id, name = "Lamp", price = 12,
    kind = "one_time" })
owner("COMPANY_PRODUCT_SET", { company_id = id,
    item_id = bank.state.companies[id].quick_items[1].item_id, online = true,
    blurb = "Warm light" })

-- Only for an open store, and only its owner.
rejected(owner, "STORE_CLOSED", "COMPANY_SHOP_APP", { company_id = id, name = "Fox" })
owner("COMPANY_SHOP_SETUP", { company_id = id, open = true })
rejected(bank.request, "NOT_OWNER", "COMPANY_SHOP_APP", bank.as(kit, {
    app_id = "COMPANY", company_id = id, name = "Mine" }))

-- In the Company app: Store, then Make a Shop App ------------------------------------------

local script = phone.script()
phone.push(script.actions, "company:1", "tab:store", function(seen)
    assert(phone.has(phone.last(seen), "Make a Shop App"), "on the store's page")
    return "shopapp"
end, "make", function(seen)
    assert(phone.has(phone.last(seen), "Take it down"), "made")
    return "about"
end, "back", "home", "home")
phone.push(script.inputs, "Fox Goods", "Lamps and more")
local seen = phone.run({ bank = bank, who = ana, file = "../company.lua", script = script,
    app_id = "COMPANY" })
assert(phone.said(seen, "Shop App ready"))
local made = bank.state.companies[id].shop_app
assert(made and made.name == "Fox Goods" and made.description == "Lamps and more")

-- The App Server builds it -----------------------------------------------------------------

local files = { ["/pumpe/shop.lua"] = assert(io.open("../shop.lua")):read("a") }
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
        request = function(_, action, payload)
            local ok, result = pcall(bank.request, action, payload)
            if ok then return result end
            return nil, type(result) == "table" and result.message or tostring(result)
        end }
end, autoUpdate = function() end }
PUMPE_TEST_MODE = true
local server = assert(loadfile("../app_server.lua"))()
PUMPE_TEST_MODE = nil
package.loaded["lib.net"] = realNet

assert(server.sync_shop_apps(), "the App Server asked the Bank")
local appId = "SA-" .. id
local listed
for _, app in ipairs(server.actions.APP_LIST({}).apps) do
    if app.app_id == appId then listed = app end
end
assert(listed and listed.name == "Fox Goods" and listed.author == "Fox Goods"
    and listed.description == "Lamps and more", "in the App Browser, by its company")
local body = files["/pumpe/appstore/" .. appId .. ".lua"]
assert(body:match("^%-%- PUMPE APP: Fox Goods\n"), "its own name on top")
local actionsDeclared = 0
for line in body:gmatch("[^\n]+") do
    if line:match("^%-%-%s*PUMPE APP ACTION:") then actionsDeclared = actionsDeclared + 1 end
end
assert(actionsDeclared == 1, "its own action, not Shop's")
-- Nothing changed: no new version for anybody to download.
server.sync_shop_apps()
assert(server.state.apps[appId].version == 1)

-- Kit runs it: the store's front door ----------------------------------------------------------

local scratch = os.tmpname()
local handle = assert(io.open(scratch, "w"))
handle:write(body)
handle:close()
script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox Goods") and phone.has(frame, "Shop now"),
        "the store's own front door")
    assert(not phone.has(frame, "Search stores"), "not every store there is")
    assert(phone.has(frame, "Store") and phone.has(frame, "Delivery"), "with its tabs")
    return "shop"
end, function(seen)
    assert(phone.has(phone.last(seen), "Lamp  $12"), "the store's products")
    return "back"
end, "home")
phone.run({ bank = bank, who = kit, file = scratch, script = script, app_id = appId })
os.remove(scratch)

-- Taken down: gone from the App Browser ------------------------------------------------------

owner("COMPANY_SHOP_APP", { company_id = id, enabled = false })
server.sync_shop_apps()
assert(server.state.apps[appId] == nil and not files["/pumpe/appstore/" .. appId .. ".lua"],
    "the store took its app down")

print("host_shop_app_test: OK")
