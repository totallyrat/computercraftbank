-- Host-side render smoke test for the three important screen sizes.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

os.day = function() return 1 end
os.time = function() return 12 end
os.epoch = function() return 1 end
os.getComputerID = function() return 1 end

local function mockTerminal(width, height)
    local cursorX, cursorY = 1, 1
    return {
        getSize = function() return width, height end,
        isColor = function() return true end,
        setBackgroundColor = function() end,
        setTextColor = function() end,
        clear = function() end,
        setCursorBlink = function() end,
        setCursorPos = function(x, y)
            assert(x >= 1 and x <= width, "cursor x out of bounds")
            assert(y >= 1 and y <= height, "cursor y out of bounds")
            cursorX, cursorY = x, y
        end,
        write = function(value)
            assert(cursorX + #tostring(value) - 1 <= width,
                "write exceeds screen width")
        end,
    }
end

term = { current = function() return mockTerminal(51, 19) end }

local ui = require("lib.ui")

-- The floating tab bar, 12.0: a pill on the row above the bottom, clear of
-- both sides and of the bottom row, holding three parts and More.
local four = { { id = "stores", label = "Stores" },
    { id = "delivery", label = "Delivery", short = "Deliv" },
    { id = "places", label = "Places" }, { id = "orders", label = "Orders" } }
for _, size in ipairs({ { 26, 20 }, { 51, 19 }, { 39, 13 } }) do
    local width, height = size[1], size[2]
    local display = mockTerminal(width, height)
    ui.usePhoneStyle(true)
    ui.clear(display)
    ui.header(display, "Shop", "Tabs", "12:00")
    local bar = ui.scene(display)
    ui.tabBar(bar, display, four, "delivery", colors.orange)
    local seen = {}
    for x = 1, width do seen[#seen + 1] = bar:hit(x, height - 1) or "gap" end
    assert(seen[1] == "gap" and seen[2] == "gap" and seen[width] == "gap"
        and seen[width - 1] == "gap", "it stops short of both sides")
    assert(seen[3] == "tab:stores" and seen[width - 2] == "tab:more",
        "three parts, then More: " .. table.concat(seen, ","))
    local found = {}
    for _, id in ipairs(seen) do found[id] = true end
    assert(found["tab:delivery"] and found["tab:places"] and not found["tab:orders"],
        "the fourth part is behind More")
    for x = 1, width do
        assert(bar:hit(x, height) == nil, "the bottom row is left clear")
    end
    assert(ui.contentBottom(display) == height - 2)
    assert(bar:hit(1, 1) == "home" and bar:hit(4, 1) == "home",
        "the PUMPE mark at the top left goes home")
    -- A part behind More lights More up.
    local behind = ui.scene(display)
    ui.tabBar(behind, display, four, "orders")
    ui.usePhoneStyle(false)
end

-- Two parts still get More, for what a program adds and for search.
do
    local display = mockTerminal(26, 20)
    local bar = ui.scene(display)
    ui.tabBar(bar, display, { { id = "a", label = "Take" },
        { id = "b", label = "Pay" } }, "a")
    local ids = {}
    for x = 1, 26 do local id = bar:hit(x, 19) if id then ids[id] = true end end
    assert(ids["tab:a"] and ids["tab:b"] and ids["tab:more"])
end

-- What the bar draws: every label inside its slot, the lit one in the main
-- colour's writing colour.
do
    local writes = {}
    local display = mockTerminal(26, 20)
    local realWrite = display.write
    local cursorY, fg, bg = 1, nil, nil
    display.setCursorPos = function(x, y) cursorY = y end
    display.setTextColor = function(c) fg = c end
    display.setBackgroundColor = function(c) bg = c end
    display.write = function(value)
        writes[#writes + 1] = { y = cursorY, text = value, fg = fg, bg = bg }
    end
    ui.setMainColor("purple")
    ui.tabBar(ui.scene(display), display, four, "stores")
    local lit
    for _, write in ipairs(writes) do
        if write.y == 19 and write.text:sub(1, 5) == "Store" then lit = write end
    end
    assert(lit and lit.bg == colors.purple and lit.fg == colors.white,
        "white on purple")
    ui.setMainColor("orange")
    writes = {}
    ui.tabBar(ui.scene(display), display, four, "stores")
    for _, write in ipairs(writes) do
        if write.y == 19 and write.text:sub(1, 5) == "Store" then lit = write end
    end
    assert(lit.bg == colors.orange and lit.fg == colors.black, "black on orange")
end

-- The main colour: orange unless chosen, and what everything is drawn in.
do
    assert(ui.mainColor == "orange" and ui.theme.accent == colors.orange,
        "orange by default, like the fox")
    assert(ui.setMainColor("blue") and ui.theme.accent == colors.blue
        and ui.theme.accentInk == colors.white)
    assert(not ui.setMainColor("plaid") and ui.mainColor == "blue",
        "an unknown colour changes nothing")
    local files = {}
    fs = { combine = function(a, b) return a .. "/" .. b end,
        exists = function(path) return files[path] ~= nil end }
    local util = require("lib.util")
    local realLoad, realSave = util.loadTable, util.saveTable
    util.loadTable = function(path, fallback) return files[path] or fallback end
    util.saveTable = function(path, value) files[path] = value end
    ui.setMainColor("orange")
    assert(not ui.hasMainColor("/pumpe") and ui.useMainColor("/pumpe") == "orange")
    assert(ui.saveMainColor("/pumpe", "lime") and ui.hasMainColor("/pumpe"))
    ui.setMainColor("orange")
    assert(ui.useMainColor("/pumpe") == "lime" and ui.theme.accent == colors.lime,
        "the choice is kept beside the program")
    files["/pumpe/main_color.dat"] = { color = "nonsense" }
    assert(ui.useMainColor("/pumpe") == "orange", "a bad file is orange")
    util.loadTable, util.saveTable = realLoad, realSave
    fs = nil
end

-- The tab host: each page returns what was tapped. A "once" tab is a thing
-- to do, after which the tab before it comes back; anything that is not a
-- known tab leaves, and is handed back to whoever opened the app.
do
    local visited, refreshed = {}, 0
    local script = { "tab:urgent", "ignored", "tab:people", "tab:nowhere" }
    local function page(name)
        return function(spec)
            visited[#visited + 1] = name .. ":" .. spec.active
            return table.remove(script, 1)
        end
    end
    local left = ui.runTabs({
        list = { { id = "chats", label = "Chats" }, { id = "people", label = "Friends" },
            { id = "urgent", label = "Urgent" } },
        start = "chats",
        pages = { chats = page("chats"), people = page("people"),
            urgent = page("urgent") },
        once = { urgent = true },
        refresh = function() refreshed = refreshed + 1 end,
    })
    assert(table.concat(visited, ",")
        == "chats:chats,urgent:urgent,chats:chats,people:people",
        "urgent ran once and chats came back: " .. table.concat(visited, ","))
    assert(left == "tab:nowhere", "an unknown tab leaves the app")
    assert(refreshed == 4, "the labels are refreshed before every page")
end

local wrapped = ui.wrap(
    "Processing fees and payment totals stay readable on pocket screens", 22)
assert(#wrapped == 4)
for _, line in ipairs(wrapped) do
    assert(#line <= 22, "wrapped copy exceeds the pocket content width")
end

for _, dimensions in ipairs({ { 26, 20 }, { 51, 19 }, { 29, 12 } }) do
    local display = mockTerminal(dimensions[1], dimensions[2])
    ui.clear(display)
    ui.header(display, "PUMPE TEST", "Responsive screen", "12:00")
    ui.card(display, 2, 5, dimensions[1] - 2, 3, colors.cyan)
    ui.progress(display, 3, 8, dimensions[1] - 4, 5, 10)
    local scene = ui.scene(display)
    scene:button("left", 2, 10, math.floor((dimensions[1] - 3) / 2),
        2, "LEFT")
    scene:button("right", math.floor(dimensions[1] / 2) + 1, 10,
        math.floor((dimensions[1] - 2) / 2), 2, "RIGHT")
    assert(scene:hit(2, 10) == "left")
    assert(scene:hit(math.floor(dimensions[1] / 2) + 1, 10) == "right")

    -- A hotspot is a tap target with nothing painted in it, so an icon's
    -- caption can share the icon's target without a panel behind the words.
    scene:hotspot("left", 2, 13, 6, 1)
    assert(scene:hit(4, 13) == "left", "a hotspot takes taps like a button")
end

-- The 8.0 wordmark. It reports failure rather than painting a half word when
-- the screen cannot hold it, so callers can fall back to plain text.
sleep = function() end
assert(ui.wordmark(mockTerminal(26, 20), 2, "PUMPE", 5, colors.cyan),
    "PUMPE fits the block face on a pocket screen")
assert(ui.wordmark(mockTerminal(51, 19), 2, "PUMPE", 0, colors.cyan),
    "drawing no letters yet is still a fit")
assert(not ui.wordmark(mockTerminal(12, 20), 2, "PUMPE", 5, colors.cyan),
    "a screen too narrow reports the miss")
assert(not ui.wordmark(mockTerminal(26, 20), 18, "PUMPE", 5, colors.cyan),
    "a wordmark that would run off the bottom reports the miss")
assert(not ui.wordmark(mockTerminal(51, 19), 2, "BANK", 4, colors.cyan),
    "a letter with no glyph reports the miss instead of drawing a gap")

-- The start-up runs the same beats on a screen too small for the block face.
for _, dimensions in ipairs({ { 26, 20 }, { 51, 19 }, { 12, 8 } }) do
    ui.splash(mockTerminal(dimensions[1], dimensions[2]), "PUMPE",
        "Small yet Mighty", { blinks = 3, hold = 0, step = 0,
            footnote = "v8.0.0" })
end

-- Regression test: older key maps may not expose keys.escape. The previous
-- PIN screen built a table with a nil key and crashed as soon as Sign In or
-- Create Account opened the pad.
keys = { backspace = 14, enter = 28 }
sleep = function() end
local timerId = 0
os.startTimer = function()
    timerId = timerId + 1
    return timerId
end

local function pinWithEvents(events)
    local index = 0
    os.pullEvent = function()
        index = index + 1
        assert(events[index], "PIN pad requested too many events")
        return table.unpack(events[index])
    end
    return ui.pin(mockTerminal(26, 20), "ACCOUNT PIN", true)
end

assert(pinWithEvents({
    { "char", "1" }, { "char", "2" },
    { "char", "3" }, { "char", "4" },
}) == "1234")

assert(pinWithEvents({
    { "mouse_click", 1, 4, 11 },
    { "mouse_click", 1, 11, 11 },
    { "mouse_click", 1, 18, 11 },
    { "mouse_click", 1, 4, 13 },
}) == "1234")

-- The More page. Nothing typed: what is behind More. Typing: every part
-- and every extra, best match first. Picking returns its id.
local function moreWith(events, spec)
    local index = 0
    os.pullEvent = function()
        index = index + 1
        local event = events[index]
        assert(event, "More asked for more events than the script has")
        if type(event) == "function" then event = event() end
        return table.unpack(event)
    end
    return ui.moreMenu(mockTerminal(26, 20), spec)
end
keys.up, keys.down, keys.numPadEnter = 200, 208, 156
local shopSpec = { title = "Shop", active = "stores", list = {
        { id = "stores", label = "Stores" }, { id = "cart", label = "Basket" },
        { id = "orders", label = "Orders" }, { id = "returns", label = "Returns",
            hint = "Send something back" }, { id = "saved", label = "Saved" } },
    more = { { id = "help", label = "How the Shop works", hint = "Help" } } }
assert(moreWith({ { "key", 28 } }, shopSpec) == "tab:returns",
    "the first thing behind More is suggested first")
assert(moreWith({ { "key", 208 }, { "key", 208 }, { "key", 28 } }, shopSpec)
    == "help", "then the rest, and the extras after the parts")
assert(moreWith({ { "char", "b" }, { "char", "a" }, { "key", 28 } }, shopSpec)
    == "tab:cart", "typing searches the parts on the bar too")
assert(moreWith({ { "char", "s" }, { "char", "e" }, { "char", "n" },
    { "char", "d" }, { "key", 28 } }, shopSpec) == "tab:returns",
    "and what they are for")
assert(moreWith({ { "key", 14 } }, shopSpec) == "tab:stores",
    "backspace on an empty search goes back to the page")
assert(moreWith({ { "mouse_click", 1, 5, 19 } }, shopSpec) == "tab:stores",
    "the bar is still there")
assert(moreWith({ { "mouse_click", 1, 5, 8 } }, shopSpec) == "tab:returns",
    "a tap on a suggestion opens it")

-- runTabs opens More itself, and an extra with a function runs and comes
-- back to the page it was opened from.
do
    local ran = 0
    local visited = {}
    local script = { "tab:more", "tab:more", "done" }
    os.pullEvent = function() return "key", 28 end
    local left = ui.runTabs({
        list = { { id = "a", label = "A" }, { id = "b", label = "B" },
            { id = "c", label = "C" }, { id = "d", label = "D" } },
        more = { { id = "about", label = "About" } },
        actions = { about = function() ran = ran + 1 end },
        pages = {
            a = function(spec) visited[#visited + 1] = "a" return table.remove(script, 1) end,
            d = function(spec)
                visited[#visited + 1] = "d"
                -- Enter picks the first suggestion again: now "about" is
                -- first, since "d" is the page this is opened from.
                os.pullEvent = (function()
                    local events = { { "key", 208 }, { "key", 28 } }
                    return function() return table.unpack(table.remove(events, 1)) end
                end)()
                return table.remove(script, 1)
            end,
        },
    })
    assert(table.concat(visited, ",") == "a,d,d" and ran == 1 and left == "done",
        "More opened a page, then ran an extra and came back: "
            .. table.concat(visited, ",") .. " " .. ran)
end

-- Long CCG codes use the same touch/keyboard code field without inheriting
-- the normal 24-character text-input ceiling. The field keeps the newest
-- characters visible while preserving the complete value.
local longCode = "cCg2026LongScreenCode987654321"
local inputEvents = {}
for index = 1, #longCode do
    inputEvents[#inputEvents + 1] = { "char", longCode:sub(index, index) }
end
inputEvents[#inputEvents + 1] = { "key", keys.enter }
local inputIndex = 0
os.pullEvent = function()
    inputIndex = inputIndex + 1
    assert(inputEvents[inputIndex], "code input requested too many events")
    return table.unpack(inputEvents[inputIndex])
end
assert(ui.input(mockTerminal(26, 20), "Join CCG", {
    hint = "Letters + numbers",
    mode = "code",
    maxLength = math.huge,
    scrollToEnd = true,
}) == string.upper(longCode))

-- 11.0: an email address typed on the pocket keyboard. The email layout has
-- @ and a full stop on it; the keys are drawn in capitals but type lower
-- case, and a real keyboard types exactly what it types. On a 26x20 screen
-- the keys are two wide from x=4, and the last two rows are y=17 and 18.
local function key(index, row) return { "mouse_click", 1, 4 + (index - 1) * 2, row } end
local mailEvents = {
    key(8, 17),   -- K
    key(10, 17),  -- @
    key(4, 17),   -- F
    key(8, 18),   -- .
    key(3, 18),   -- C
    { "char", "X" },
    { "key", keys.enter },
}
local mailIndex = 0
os.startTimer = os.startTimer or function() return 0 end
os.pullEvent = function()
    mailIndex = mailIndex + 1
    assert(mailEvents[mailIndex], "email input requested too many events")
    return table.unpack(mailEvents[mailIndex])
end
local typedMail = (ui.input(mockTerminal(26, 20), "To", { hint = "Address",
    mode = "email", maxLength = 40 }))
assert(typedMail == "k@f.cX")

-- 11.0: suggestions under the field. Type "fo", let the cursor blink once,
-- and tap the second suggestion -- row 9 on a pocket screen with a hint,
-- the field taking rows 5 to 7.
local suggestCalls = 0
local suggestEvents = {
    { "char", "f" }, { "char", "o" }, { "timer", 0 },
    { "mouse_click", 1, 10, 9 },
}
local suggestIndex = 0
os.startTimer = function() return 0 end
os.pullEvent = function()
    suggestIndex = suggestIndex + 1
    assert(suggestEvents[suggestIndex], "suggest input requested too many events")
    return table.unpack(suggestEvents[suggestIndex])
end
local typedSearch, chosen = ui.input(mockTerminal(26, 20), "Search", {
    hint = "Apps", maxLength = 24,
    suggest = function(value)
        suggestCalls = suggestCalls + 1
        return { { label = value .. "xy", detail = "App" },
            { label = "Foxy Cash", detail = "Foxy" } }
    end,
})
assert(typedSearch == "fo" and chosen and chosen.label == "Foxy Cash",
    "tapping a suggestion returns it")
assert(suggestCalls == 2, "worked out once per change of text, not per blink: "
    .. suggestCalls)

-- The PUMPE can opt into phone styling without changing the kiosk UI.
ui.usePhoneStyle(true)
local phoneDisplay = mockTerminal(26, 20)
ui.header(phoneDisplay, "Foxy Account", "Adam", "12:00")
local phoneScene = ui.scene(phoneDisplay)
phoneScene:button("pay", 3, 8, 6, 3, "P\nPay", {
    background = colors.blue,
})
assert(phoneScene:hit(4, 9) == "pay")
phoneScene:button("code", 2, 12, 24, 3,
    "Code Pay\nEnter a six-character\nkiosk code", {
        background = colors.blue,
    })
assert(phoneScene:hit(12, 13) == "code")
ui.message(phoneDisplay, "success", "Transfer completed safely",
    "The recipient received the payment and your daily limit was updated.")
ui.usePhoneStyle(false)

-- The shared wait loop triggers the opt-in lock callback after true global
-- inactivity, even when screens redraw on their own tick timers.
local nowMs, lastTimer, lockCount = 1000, 0, 0
os.epoch = function() return nowMs end
os.startTimer = function()
    lastTimer = lastTimer + 1
    return lastTimer
end
ui.setIdleLock(1, function(elapsed)
    assert(elapsed >= 1000)
    lockCount = lockCount + 1
end)
os.pullEvent = function()
    nowMs = 2001
    return "timer", lastTimer
end
assert(ui.scene(mockTerminal(26, 20)):wait() == "__idle")
assert(lockCount == 1)
ui.setIdleLock(nil)

nowMs, lockCount = 3000, 0
ui.setIdleLock(1, function() lockCount = lockCount + 1 end)
local overdueScene = ui.scene(mockTerminal(26, 20))
overdueScene:button("open", 2, 5, 10, 2, "OPEN")
os.pullEvent = function()
    nowMs = 4001
    return "mouse_click", 1, 3, 5
end
assert(overdueScene:wait() == "__idle")
assert(lockCount == 1)
ui.setIdleLock(nil)

-- Static pages must wait for a real choice. Previously Scene:wait started an
-- implicit 0.5 second timer, causing confirmations and read-only pages to
-- disappear before their buttons could be read.
os.startTimer = function()
    error("static confirmation unexpectedly started a timer")
end
os.pullEvent = function()
    return "mouse_click", 1, 16, 17
end
ui.usePhoneStyle(true)
assert(ui.confirm(mockTerminal(26, 20), "REVIEW PAYMENT",
    "Corner Service Kiosk requests a payment with a detailed description"
        .. " that must remain readable before approval.",
    "PAY", "BACK") == true)
ui.usePhoneStyle(false)
assert(ui.confirm(mockTerminal(26, 20), "CONFIRM", "Keep this page open?",
    "YES", "NO") == true)

-- Regression: a screen that ticks faster than the background interval used to
-- starve it completely. Every tick returned and cancelled the background
-- timer, and the next wait started a fresh full-length one, so Urgent Contact
-- never rang on any screen.
local clock = 10000
os.epoch = function() return clock end
local timers, nextTimer = {}, 0
os.startTimer = function(seconds)
    nextTimer = nextTimer + 1
    timers[nextTimer] = clock + seconds * 1000
    return nextTimer
end
os.cancelTimer = function(id) timers[id] = nil end

local rings = 0
ui.setBackgroundTask(3, function()
    rings = rings + 1
    return false
end)

-- Fire whichever timer is due first, exactly as ComputerCraft would.
os.pullEvent = function()
    local soonest, soonestAt
    for id, at in pairs(timers) do
        if not soonestAt or at < soonestAt or (at == soonestAt and id < soonest) then
            soonest, soonestAt = id, at
        end
    end
    clock = math.max(clock, soonestAt)
    timers[soonest] = nil
    return "timer", soonest
end

-- Ten seconds of a half-second screen: the 3s task must run, not be starved.
local elapsedStart = clock
while clock - elapsedStart < 10000 do
    ui.scene(mockTerminal(26, 20)):wait({ tickRate = 0.5 })
end
assert(rings >= 2,
    "a 3s background task must still run on a 0.5s screen (ran " .. rings .. ")")
assert(rings <= 5, "it must not run far more often than its interval")
ui.setBackgroundTask(nil)

-- The start-up screen, timed ------------------------------------------------
-- 10.0 made the normal boot short: the letters land, the tagline holds for
-- two seconds, and the phone is yours. The long screen belongs to an update
-- and only to an update, so the boot must not quietly grow back.
local slept = 0
sleep = function(seconds) slept = slept + (tonumber(seconds) or 0) end
local splashTarget = mockTerminal(26, 20)
ui.splash(splashTarget, "PUMPE", "Small yet Mighty",
    { footnote = "v10.0.0", blinks = 0, hold = 2 })
assert(slept < 3.2, "the boot splash took " .. slept
    .. "s; the letters plus a two second tagline is the whole of it")
assert(slept >= 2, "and the tagline is actually held, not flashed")

local blinked = 0
sleep = function(seconds) blinked = blinked + (tonumber(seconds) or 0) end
ui.splash(splashTarget, "PUMPE", "Small yet Mighty", { hold = 2 })
assert(blinked > slept,
    "blinks = 0 has to actually skip the blink; `options.blinks or 3` would"
        .. " keep three of them if it were written `blinks and ... or 3`")
sleep = function() end

print("host_ui_test: OK")
