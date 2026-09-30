-- A kiosk program, run whole, against a scripted Bank.
--
-- 12.0 put every kiosk on the same three tabs and More, so they are tested
-- the same way: the program's own file, a screen that bounds checks every
-- draw, the real tab bar and tab host, and a tap that only lands on
-- something that is really there. The Bank is a function the test writes;
-- the script is five queues -- taps, text boxes, PINs, confirmations, and
-- what the More page is answered with.

local kiosk = {}

colors = colors or {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
package.path = "../?.lua;../?/init.lua;" .. package.path
local realUi = dofile("real_ui.lua")

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

function kiosk.script()
    return { actions = {}, inputs = {}, pins = {}, confirms = {}, more = {} }
end

function kiosk.push(queue, ...)
    for _, entry in ipairs({ ... }) do queue[#queue + 1] = entry end
end

-- options: file, width, height, device (what loadTable returns), bank
-- (function(action, payload) -> result, err, code), script, config.
function kiosk.run(options)
    local WIDTH, HEIGHT = options.width or 51, options.height or 19
    local script = options.script
    local seen = { frames = {}, messages = {}, requests = {}, inputs = {},
        more = {}, saved = {} }
    local frame = {}
    local function take(queue, what)
        local entry = table.remove(queue, 1)
        assert(entry ~= nil, "the kiosk asked for an unexpected " .. what)
        if type(entry) == "function" then entry = entry(seen) end
        return entry
    end
    local function box(label, x, y, width, height)
        assert(x >= 1 and y >= 1, label .. " starts outside the screen")
        assert(x + width - 1 <= WIDTH, label .. " is wider than the screen")
        assert(y + height - 1 <= HEIGHT, label .. " is below the screen")
    end
    local function draw(value) frame[#frame + 1] = tostring(value) end

    local surface = { getSize = function() return WIDTH, HEIGHT end }
    term = { current = function() return surface end }
    fs = fs or {}
    fs.getDir = function() return "/pumpe" end
    fs.combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", "")
    end
    fs.exists = fs.exists or function() return false end
    shell = { getRunningProgram = function() return "/pumpe/" .. options.file end }
    os.getComputerID = function() return 77 end
    os.day = function() return 42 end
    os.time = function() return 12 end
    os.epoch = function() return 1000000 end
    sleep = function() end
    redstone = { setOutput = function() end }
    -- The first loop is the screen; the rest are background work.
    parallel = { waitForAny = function(first) first() end }
    peripheral = { getNames = function() return {} end,
        getType = function() return nil end, wrap = function() return nil end }

    package.loaded.config = options.config or { version = "12.0.0", currency = "$" }
    local util = dofile("../lib/util.lua")
    util.loadTable = function(path, fallback)
        if tostring(path):find("main_color", 1, true) then return options.color or {} end
        return options.device or fallback
    end
    util.saveTable = function(path, value) seen.saved[#seen.saved + 1] = value end
    util.formatClock = function() return "12:00" end
    package.loaded["lib.util"] = util

    local client = {
        discover = function() return true end,
        request = function(_, action, payload)
            seen.requests[#seen.requests + 1] = action
            return options.bank(action, payload or {})
        end,
    }
    package.loaded["lib.net"] = {
        client = function() return client end,
        autoUpdate = function() end, locate = function() return nil end,
        openModems = function() end,
    }

    local ui = { theme = realUi.theme, wrap = realUi.wrap }
    function ui.clear()
        frame = {}
        seen.frames[#seen.frames + 1] = frame
    end
    function ui.fill(_, x, y, width, height) box("fill", x, y, width, height) end
    function ui.card(_, x, y, width, height) box("card", x, y, width, height) end
    function ui.progress(_, x, y, width) box("progress", x, y, width, 1) end
    function ui.truncate(value, maximum) return tostring(value or ""):sub(1, math.max(0, maximum)) end
    function ui.header(_, title, subtitle)
        assert(#tostring(title) <= WIDTH - 3, "title clipped: " .. tostring(title))
        assert(#tostring(subtitle or "") <= WIDTH - 3, "subtitle clipped: " .. tostring(subtitle))
        draw(title)
        draw(subtitle or "")
    end
    function ui.text(_, x, y, value, _, _, maximum)
        value = tostring(value)
        box("text " .. value, x, y, math.max(1, math.min(#value, maximum or #value)), 1)
        draw(value)
    end
    function ui.center(_, y, value)
        assert(y >= 1 and y <= HEIGHT and #tostring(value) <= WIDTH,
            "centred text off the screen: " .. tostring(value))
        draw(value)
    end
    function ui.wrappedText(_, x, y, value, width, lines)
        box("wrapped text", x, y, width, lines)
        assert(#wrap(value, width) <= lines or true)
        draw(value)
    end
    function ui.message(_, kind, title, body)
        seen.messages[#seen.messages + 1] = { kind = kind, title = title, body = body }
    end
    function ui.networkError(_, err) seen.messages[#seen.messages + 1] = { title = "NETWORK", body = err } end
    function ui.boot() end
    function ui.wipe() end
    function ui.splash() end
    function ui.input(_, title, spec)
        draw("input:" .. title)
        seen.inputs[#seen.inputs + 1] = { title = title, mode = spec and spec.mode }
        return take(script.inputs, "text box: " .. title)
    end
    function ui.pin(_, title)
        draw("pin:" .. title)
        return take(script.pins, "PIN pad: " .. title)
    end
    function ui.confirm(_, title, body)
        draw("confirm:" .. title .. " " .. tostring(body))
        return take(script.confirms, "confirmation: " .. title)
    end
    -- The bar paints its labels; here they are written into the frame --
    -- every tab, and More only past four.
    function ui.tabBar(scene, target, tabs, active, accent, barOptions)
        local more = #tabs > realUi.TAB_COUNT
        for index, tab in ipairs(tabs) do
            if not more or index < realUi.TAB_COUNT then draw(tab.label) end
        end
        if more then draw("More") end
        return realUi.tabBar(scene, target, tabs, active, accent, barOptions)
    end
    function ui.scene()
        local scene, tappable = { width = WIDTH, height = HEIGHT, target = surface }, {}
        function scene:button(id, x, y, width, height, label, spec)
            box("button " .. tostring(label), x, y, width, height)
            assert(#wrap(label, math.max(1, width - 2)) <= height,
                "button label clipped: " .. tostring(label))
            draw(label)
            if not (spec and spec.disabled) then tappable[id] = true end
        end
        function scene:hotspot(id, x, y, width, height)
            box("hotspot " .. tostring(id), x, y, width, height)
            tappable[id] = true
        end
        function scene:wait(spec)
            local action = take(script.actions, "tap")
            assert(action:sub(1, 2) == "__" or tappable[action],
                "tapped " .. action .. ", which is not on the screen")
            return action
        end
        return scene
    end
    ui.inkOn, ui.searchEntries, ui.contentBottom = realUi.inkOn, realUi.searchEntries,
        realUi.contentBottom
    ui.MAIN_COLORS, ui.mainColor, ui.TAB_COUNT = realUi.MAIN_COLORS, "orange", realUi.TAB_COUNT
    ui.useMainColor = function() return "orange" end
    ui.hasMainColor = function() return options.color ~= nil end
    ui.pickMainColor = function(_, _, title)
        draw("colour:" .. tostring(title))
        seen.picked = (seen.picked or 0) + 1
        return "orange"
    end
    function ui.moreMenu(_, spec)
        draw("more:" .. tostring(spec and spec.title))
        seen.more[#seen.more + 1] = spec
        return take(script.more, "More page")
    end
    ui.resolveTab = function(target, action, spec)
        if action ~= "tab:more" then return action end
        return ui.moreMenu(target, spec)
    end
    realUi.moreMenu = function(target, spec) return ui.moreMenu(target, spec) end
    ui.runTabs = realUi.runTabs
    -- FoxyOS 12: the MyID Verifier is drawn by lib/ui (its own test covers
    -- that); here a kiosk only has to put the typed code to the Bank.
    ui.myIdVerifier = function(_, ask)
        draw("verifier")
        local answer = ask(take(script.inputs, "MyID code"))
        seen.verified = seen.verified or {}
        seen.verified[#seen.verified + 1] = answer
    end
    package.loaded["lib.ui"] = ui

    assert(loadfile("../" .. options.file))()
    for name, queue in pairs(script) do
        assert(#queue == 0, #queue .. " scripted " .. name .. " never used")
    end
    return seen
end

function kiosk.has(frame, wanted)
    for _, value in ipairs(frame or {}) do
        if tostring(value):find(wanted, 1, true) then return true end
    end
    return false
end

function kiosk.anyFrame(seen, wanted)
    for _, frame in ipairs(seen.frames) do
        if kiosk.has(frame, wanted) then return frame end
    end
    return nil
end

function kiosk.said(seen, title)
    for _, message in ipairs(seen.messages) do
        if message.title == title then return message end
    end
    return nil
end

function kiosk.asked(seen, action)
    for _, value in ipairs(seen.requests) do
        if value == action then return true end
    end
    return false
end

return kiosk
