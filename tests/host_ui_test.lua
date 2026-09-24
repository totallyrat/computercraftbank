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

-- The bottom tab bar, 11.0: every app's parts in one row, each tab as wide
-- as its label needs, the leftovers shared out, and home at the top left.
for _, size in ipairs({ { 26, 20 }, { 51, 19 } }) do
    local display = mockTerminal(size[1], size[2])
    ui.usePhoneStyle(true)
    ui.clear(display)
    ui.header(display, "Shop", "Tabs", "12:00")
    local bar = ui.scene(display)
    ui.tabBar(bar, display, { { id = "stores", label = "Stores" },
        { id = "delivery", label = "Delivery" },
        { id = "places", label = "Places" } }, "delivery", colors.orange)
    assert(bar:hit(1, size[2]) == "tab:stores")
    assert(bar:hit(size[1], size[2]) == "tab:places", "the row is filled to the edge")
    local seen = {}
    for x = 1, size[1] do seen[bar:hit(x, size[2]) or "gap"] = true end
    assert(seen["tab:delivery"] and not seen.gap, "no gaps between tabs")
    assert(bar:hit(1, 1) == "home" and bar:hit(4, 1) == "home",
        "the PUMPE mark at the top left goes home")
    -- More tabs than fit: equal shares, still the whole row.
    local crowded = ui.scene(display)
    ui.tabBar(crowded, display, { { id = "a", label = "Messages" },
        { id = "b", label = "Friends" }, { id = "c", label = "Urgent" },
        { id = "d", label = "Requests" } }, "a")
    assert(crowded:hit(size[1], size[2]) == "tab:d")
    ui.usePhoneStyle(false)
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
