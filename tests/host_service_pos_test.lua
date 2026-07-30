-- 51x19 Square-style cashier layout plus the compact 1x1 customer display.

local WIDTH, HEIGHT = 51, 19
local actions = {
    "tab:all",
    "favorite:P1",
    "tab:subscriptions",
    "settings",
    "close",
}
local buttonLabels, requests = {}, {}

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local terminal = { getSize = function() return WIDTH, HEIGHT end }
local monitor = {
    getSize = function() return 14, 10 end,
    isColor = function() return true end,
    setTextScale = function(scale) assert(scale == 0.5) end,
    setCursorBlink = function() end,
}
term = { current = function() return terminal end }
peripheral = {
    find = function(kind, filter)
        assert(kind == "monitor")
        assert(filter("right", monitor))
        return monitor
    end,
}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
}
shell = {
    getRunningProgram = function() return "/pumpe/service_kiosk.lua" end,
}
sleep = function() end

package.loaded.config = {
    version = "5.4.0",
    currency = "$",
    payment_code_ttl_ms = 300000,
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local products = {
    {
        item_id = "P1", name = "Espresso", price = 4,
        kind = "one_time", favorite = false,
    },
    {
        item_id = "P2", name = "Cookie", price = 3,
        kind = "one_time", favorite = true,
    },
    {
        item_id = "P3", name = "Coffee Pass", price = 12,
        kind = "subscription", favorite = true,
    },
}
package.loaded["lib.util"] = {
    loadTable = function()
        return {
            terminal_id = "TERM1",
            terminal_token = "TOKEN",
            name = "Fox Cafe",
        }
    end,
    saveTable = function() end,
    copy = copy,
    money = function(value, symbol)
        return (symbol or "$") .. string.format("%.2f", tonumber(value) or 0)
    end,
    formatClock = function() return "12:00" end,
    nowMs = function() return 1000 end,
    roundMoney = function(value)
        if not value then return nil end
        return math.floor(value * 100 + 0.5) / 100
    end,
    page = function(items, requestedPage, pageSize)
        local pages = math.max(1, math.ceil(#items / pageSize))
        local page = math.max(1, math.min(requestedPage or 1, pages))
        local output = {}
        local first = (page - 1) * pageSize + 1
        for index = first, math.min(#items, first + pageSize - 1) do
            output[#output + 1] = items[index]
        end
        return output, page, pages
    end,
}

local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "KIOSK_REGISTER" then
            return {
                terminal_id = "TERM1",
                terminal_token = "TOKEN",
                name = "Fox Cafe",
            }
        elseif action == "KIOSK_STATE" then
            return {
                terminal = {
                    terminal_id = "TERM1",
                    name = "Fox Cafe",
                    balance = 100,
                    sales_total = 250,
                },
                company = {
                    company_id = "COMP1",
                    name = "Fox Cafe",
                    tax_id = "TX-CAFE",
                },
                products = copy(products),
            }
        elseif action == "SET_PRODUCT_FAVORITE" then
            assert(payload.item_id == "P1")
            products[1].favorite = payload.favorite
            return { products = copy(products) }
        end
        error("Unexpected request: " .. tostring(action))
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
}

local ui = {
    theme = {
        background = colors.black, panel = colors.gray,
        panelAlt = colors.lightGray, ink = colors.white,
        muted = colors.lightGray, accent = colors.cyan,
        accentDark = colors.blue, success = colors.lime,
        danger = colors.red, warning = colors.orange,
        shadow = colors.gray,
    },
}

local function dimensions(surface)
    return surface.getSize()
end
local function assertBox(surface, label, x, y, width, height)
    local screenWidth, screenHeight = dimensions(surface)
    assert(x >= 1 and y >= 1, label .. " starts outside screen")
    assert(width >= 1 and height >= 1, label .. " is empty")
    assert(x + width - 1 <= screenWidth, label .. " exceeds width")
    assert(y + height - 1 <= screenHeight, label .. " exceeds height")
end
local function wrap(value, width)
    value, width = tostring(value or ""), math.max(1, width)
    local lines = {}
    for line in (value .. "\n"):gmatch("(.-)\n") do
        while #line > width do
            lines[#lines + 1] = line:sub(1, width)
            line = line:sub(width + 1)
        end
        lines[#lines + 1] = line
    end
    return lines
end

function ui.clear() end
function ui.boot(_, product, subtitle)
    assert(#product <= WIDTH and #subtitle <= WIDTH)
end
function ui.fill(surface, x, y, width, height)
    assertBox(surface, "fill", x, y, width, height)
end
function ui.text(surface, x, y, value, _, _, maximum)
    local width, height = dimensions(surface)
    assert(x >= 1 and x <= width and y >= 1 and y <= height)
    assert(#tostring(value or "") <= math.min(maximum or width, width - x + 1),
        "text is clipped: " .. tostring(value))
end
function ui.center(surface, y, value)
    local width, height = dimensions(surface)
    assert(y >= 1 and y <= height)
    assert(#tostring(value or "") <= width)
end
function ui.card(surface, x, y, width, height)
    assertBox(surface, "card", x, y, width, height)
end
function ui.header(_, title, subtitle)
    assert(#tostring(title or "") <= WIDTH - 3)
    assert(#tostring(subtitle or "") <= WIDTH - 3)
end
function ui.truncate(value, maximum)
    return tostring(value or ""):sub(1, math.max(0, maximum))
end
function ui.confirm() return true end
function ui.message() end
function ui.networkError(_, err) error(err) end

function ui.scene(surface)
    local scene = {}
    function scene:button(_, x, y, width, height, label)
        assertBox(surface, "button", x, y, width, height)
        assert(#wrap(label, math.max(1, width - 2)) <= height,
            "button label clipped: " .. tostring(label))
        buttonLabels[#buttonLabels + 1] = tostring(label or "")
    end
    function scene:wait()
        local action = table.remove(actions, 1)
        assert(action, "POS requested an unexpected action")
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

assert(loadfile("../service_kiosk.lua"))()
assert(#actions == 0)

local function contains(items, expected)
    for _, item in ipairs(items) do
        if item == expected then return true end
    end
    return false
end
assert(contains(buttonLabels, "Favorited"))
assert(contains(buttonLabels, "All Products"))
assert(contains(buttonLabels, "Subscriptions"))
assert(contains(buttonLabels, "+"))
assert(contains(buttonLabels, "S"))
assert(contains(buttonLabels, "PAY"))
assert(contains(buttonLabels, "F"))
assert(contains(requests, "SET_PRODUCT_FAVORITE"))

print("host_service_pos_test: OK")
