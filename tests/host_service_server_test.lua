-- Bank-side product catalog, favorites, and PUMPE-confirmed subscriptions.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

os.day = function() return 200 end
os.time = function() return 12 end
os.epoch = function() return 987654321 end
os.getComputerID = function() return 1 end

fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return false end,
    isDir = function() return false end,
}
shell = {
    getRunningProgram = function() return "/pumpe/bank_server.lua" end,
}

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = bank.actions

local owner = actions.REGISTER({
    name = "Cafe Owner", pin = "1234", gender = "Not set",
})
local customer = actions.REGISTER({
    name = "Coffee Fan", pin = "2468", gender = "Not set",
})
local kiosk = actions.KIOSK_REGISTER({ name = "Fox Cafe" })
local auth = {
    terminal_id = kiosk.terminal_id,
    terminal_token = kiosk.terminal_token,
}

local added = actions.ADD_PRODUCT({
    terminal_id = auth.terminal_id,
    terminal_token = auth.terminal_token,
    name = "Coffee Pass",
    price = 25,
    kind = "subscription",
})
assert(added.item.kind == "subscription")
assert(added.item.favorite == false)

local favorite = actions.SET_PRODUCT_FAVORITE({
    terminal_id = auth.terminal_id,
    terminal_token = auth.terminal_token,
    item_id = added.item.item_id,
    favorite = true,
})
assert(favorite.item.favorite)

local state = actions.KIOSK_STATE(auth)
assert(#state.products == 1)
assert(state.products[1].name == "Coffee Pass")
assert(state.products[1].favorite)

local code = actions.CREATE_PAY_CODE({
    terminal_id = auth.terminal_id,
    terminal_token = auth.terminal_token,
    amount = 25,
    purchase_type = "subscription",
    description = "Coffee Pass",
    items = {
        { name = "Coffee Pass", price = 25, quantity = 1 },
    },
})
assert(code.kind == "subscription")

local preview = actions.PAY_CODE_PREVIEW({
    session_token = customer.session_token,
    code = code.code,
})
assert(preview.kind == "subscription")
assert(preview.pin_required)

local paid = actions.PAY_CODE_CONFIRM({
    session_token = customer.session_token,
    code = code.code,
    pin = "2468",
})
assert(paid.kind == "subscription")
assert(paid.subscription_id)
assert(paid.balance == 475)

local subscriptions = actions.LIST_SUBSCRIPTIONS({
    session_token = customer.session_token,
})
assert(#subscriptions.subscriptions == 1)
assert(subscriptions.subscriptions[1].amount == 25)
assert(subscriptions.subscriptions[1].next_charge_day == 201)

local updatedState = actions.KIOSK_STATE(auth)
assert(updatedState.terminal.balance == 25)
assert(actions.PROXIMITY_FIND == nil)
assert(actions.PROXIMITY_REQUEST == nil)
assert(actions.GPS_UPDATE == nil)

local removed = actions.REMOVE_PRODUCT({
    terminal_id = auth.terminal_id,
    terminal_token = auth.terminal_token,
    item_id = added.item.item_id,
})
assert(#removed.products == 0)

-- Keep the owner session live so host-side account setup is also exercised.
assert(owner.account.name == "Cafe Owner")

print("host_service_server_test: OK")
