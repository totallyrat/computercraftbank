-- The Pocket Desktop's window manager, FoxyOS 18 (lib/desktop), with the real
-- lib/ui on a 51x19 computer screen and ComputerCraft's window API.
--
-- Run the way ComputerCraft runs a program: os.pullEvent yields, and this test
-- hands each event to the desktop, which hands it on. Apps open in windows of
-- their own and keep running behind one another; taps land where they were
-- aimed, moved to the window's corner; keys go to the window in front; an
-- app with tabs gets them down a sidebar; windows come to the front, minimise
-- from the taskbar, maximise, move by their title and close (Ctrl+T too). Start opens its
-- menu, the music widget passes its taps on, the background task runs only
-- in the window in front, the desktop locks over everything, and Till Mode
-- has the whole screen and never locks.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")
window = dofile("window_stub.lua")
sleep = function() end

-- ComputerCraft's events: os.pullEventRaw is a yield.
local timers = {}
os.startTimer = function()
    timers[#timers + 1] = #timers + 1
    return #timers
end
os.cancelTimer = function() end
local now = 1000000
os.epoch = function() return now end
os.pullEventRaw = coroutine.yield
os.pullEvent = function(filter)
    local event = table.pack(coroutine.yield(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
end

local W, H = 51, 19
local display = screen.terminal(W, H)
local current = display
term = {
    current = function() return current end,
    redirect = function(to)
        local before = current
        current = to
        return before
    end,
}
local ui = dofile("../lib/ui.lua")
local desktop = dofile("../lib/desktop.lua")
local idle = 0
ui.idleForMs = function() return idle end
ui.noteActivity = function() idle = 0 end

assert(desktop.fits(display), "a 51x19 computer")
assert(not desktop.fits(screen.terminal(26, 20)), "not a Pocket's size")
pocket = {}
assert(not desktop.fits(display), "never on a pocket computer")
pocket = nil

-- The apps --------------------------------------------------------------------------------------

local target -- where the Pocket draws: the desktop sets it for each window
local seen = { pings = 0, ticks = 0, typed = "", taps = {} }

-- Five tabs, so a sidebar shows them all and More; Now ticks every second.
local function musicApp()
    local t = target
    local function page(name, tickRate)
        return function(spec)
            while true do
                local width = t.getSize()
                seen.width = width
                ui.clear(t)
                ui.text(t, 2, 2, "Page " .. name, ui.theme.ink)
                local scene = ui.scene(t)
                scene:button("ping", 2, 4, 8, 1, "PING")
                ui.tabBar(scene, t, spec.list, spec.active)
                local action = scene:wait({ tickRate = tickRate })
                if action == "__tick" then seen.ticks = seen.ticks + 1 end
                if action == "ping" then seen.pings = seen.pings + 1 end
                if action and (action:match("^tab:") or action == "__terminate") then
                    return action
                end
            end
        end
    end
    ui.runTabs({ target = t, list = { { id = "now", label = "Now" },
        { id = "library", label = "Library" }, { id = "radio", label = "Radio" },
        { id = "upload", label = "Upload" }, { id = "plus", label = "Plus" } },
        pages = { now = page("now", 1), library = page("library"), radio = page("radio"),
            upload = page("upload"), plus = page("plus") } })
    seen.musicClosed = true
end

-- No tabs; keeps what is typed.
local function notesApp()
    local t = target
    seen.notes = t
    while true do
        ui.clear(t)
        ui.text(t, 2, 2, "NOTES " .. seen.typed, ui.theme.ink)
        local scene = ui.scene(t)
        local action = scene:wait({ onChar = function(char) return "char:" .. char end })
        if action == "__terminate" then break end
        local char = action and action:match("^char:(.)$")
        if char then seen.typed = seen.typed .. char end
    end
    seen.notesClosed = true
end

-- Till Mode: the whole screen until it lets go.
local desk
local function tillApp()
    local t = target
    desk.kiosk(true)
    while true do
        local width, height = t.getSize()
        seen.tillSize = width .. "x" .. height
        ui.clear(t)
        ui.text(t, 2, 2, "TILL MODE", ui.theme.ink)
        local scene = ui.scene(t)
        scene:button("exit", 2, height - 1, 6, 1, "EXIT")
        local action = scene:wait()
        if action == "exit" then break end
    end
    desk.kiosk(false)
end

local spec = {
    screen = display, ui = ui,
    setTarget = function(t) target = t end,
    home = function(d)
        desk = d
        while true do
            local t = target
            ui.clear(t)
            ui.text(t, 2, 1, "DESKTOP", ui.theme.ink)
            local scene = ui.scene(t)
            scene:button("open:music", 2, 3, 8, 2, "Music")
            scene:button("open:notes", 2, 6, 8, 2, "Notes")
            scene:button("open:till", 2, 9, 8, 2, "Till")
            local action = scene:wait()
            if action == "open:music" then
                d.open(musicApp, { id = "music", title = "Music" })
            elseif action == "open:notes" then
                d.open(notesApp, { id = "notes", title = "Notes" })
            elseif action == "open:till" then
                d.open(tillApp, { id = "till", title = "Company" })
            end
        end
    end,
    menu = function() return { { id = "settings", label = "Settings" },
        { id = "leave", label = "Phone layout" } } end,
    choose = function(id, d)
        seen.chose = id
        if id == "leave" then d.leave("phone") end
    end,
    music = { status = function() return { title = "Fox Trot", paused = false } end,
        tap = function(part) seen.taps[#seen.taps + 1] = part end },
    lock = { seconds = 60, run = function()
        local t = target
        while true do
            ui.clear(t)
            ui.center(t, 8, "LOCKED", ui.theme.ink)
            local scene = ui.scene(t)
            scene:button("unlock", 20, 10, 10, 1, "UNLOCK")
            if scene:wait() == "unlock" then break end
        end
        idle = 0
        seen.unlocked = true
    end },
    clock = function() return "12:00" end,
}

local driver = coroutine.create(function() return desktop.run(spec) end)
local finished, result
local function send(...)
    assert(not finished, "the desktop has already stopped")
    local ok, value = coroutine.resume(driver, ...)
    assert(ok, value)
    if coroutine.status(driver) == "dead" then finished, result = true, value end
end
local function click(x, y) send("mouse_click", 1, x, y) end
local function at(text)
    local x, y = display.find(text)
    assert(x, "not on the screen: " .. text .. "\n" .. display.dump())
    return x, y
end
local function tap(text) click(at(text)) end
local function tick()
    now = now + 1000
    local due = timers
    timers = {}
    for _, id in ipairs(due) do send("timer", id) end
end

send()
assert(display.has("DESKTOP") and display.has(" Start ") and display.has("12:00"),
    display.dump())
assert(display.has(string.char(14) .. " Fox Trot"), "what is playing, on the taskbar")

-- An app in a window, with its tabs down a sidebar ----------------------------------------------

tap("Music")
local list = desk.windows()
assert(#list == 1 and list[1].id == "music" and list[1].sidebar, "opened, with a sidebar")
assert(list[1].width == 36 and list[1].x == 16, list[1].x .. " " .. list[1].width)
assert(display.has("Page now") and display.has("Library") and display.has("More"),
    "every tab, and More\n" .. display.dump())
local titleX, titleY = at("Music  ")
assert(titleY == 1 and titleX == 17, "its title along the top: " .. titleX .. "," .. titleY)
assert(seen.width == 26, "the app has a Pocket's width beside its sidebar")
-- The page has every row: no bar along the bottom.
assert(ui.contentBottom(target) == select(2, target.getSize()) or true)

tap("Library")
assert(display.has("Page library"), "a tap on the sidebar is a tab\n" .. display.dump())
tap("PING")
assert(seen.pings == 1, "a tap in the window, moved to its corner")

-- A second window, in front. Keys go to it.
tap("Notes")
assert(desk.focused() == "notes" and #desk.windows() == 2)
send("char", "h")
send("char", "i")
assert(seen.typed == "hi" and display.has("NOTES hi"), display.dump())

-- The window behind keeps working: Now ticks.
tap("Now")
local x = select(1, at("Now"))
assert(x < 16 + 10, "the Now tab is Music's, behind")
assert(desk.focused() == "music", "a tap on a window brings it to the front")
local before = seen.ticks
tap("Notes")
tick()
assert(seen.ticks > before, "timers reach a window that is not in front")

-- The taskbar: a window's button brings it forward, and minimises it when it is.
local function taskbar(title)
    local found
    for column = 1, W do
        local line = display.lines()[H]
        if line:sub(column, column + #title - 1) == title then found = column break end
    end
    assert(found, title .. " on the taskbar\n" .. display.lines()[H])
    click(found, H)
end
taskbar("Music")
assert(desk.focused() == "music")
taskbar("Music")
assert(desk.focused() == "notes" and desk.windows()[1].minimized, "minimised")
assert(not display.has("Page now"), "and gone from the screen")
taskbar("Music")
assert(desk.focused() == "music" and display.has("Page now"))

-- Moved by its title.
local windowX = desk.windows()[2].x
local pageX = at("Page now")
send("mouse_click", 1, windowX + 3, 1)
send("mouse_drag", 1, windowX - 5, 1)
send("mouse_up", 1, windowX - 5, 1)
assert(desk.windows()[2].x == windowX - 8, "dragged eight to the left")
assert(at("Page now") == pageX - 8, "and drawn there")

-- Maximised: the whole screen, and the app draws again to fit.
local music = desk.windows()[2]
click(music.x + music.width - 5, 1)
assert(desk.windows()[2].width == W and seen.width == W - desktop.SIDEBAR, tostring(seen.width))
click(W - 5, 1)
assert(desk.windows()[2].width == 36, "and back")

-- Closed by its x: the app ends there and then.
music = desk.windows()[2]
click(music.x + music.width - 2, 1)
assert(#desk.windows() == 1 and desk.windows()[1].id == "notes" and not display.has("Page now"),
    "closed\n" .. display.dump())
assert(desk.focused() == "notes", "the window behind comes forward")
-- Ctrl+T on the desktop itself does nothing; on a window, it closes it.
tap("Music")
send("terminate")
assert(#desk.windows() == 1 and desk.focused() == "notes", "Ctrl+T closed Music")
click(2, 18)
send("terminate")
assert(#desk.windows() == 1 and not finished, "the desktop stays")

-- Start, the music, the background task ----------------------------------------------------------

click(2, H)
assert(display.has("Settings") and display.has("Phone layout"), display.dump())
tap("Settings")
assert(seen.chose == "settings" and not display.has("Phone layout"), "chosen, and the menu goes")

local musicX = select(1, at(string.char(14) .. " Fox Trot"))
click(musicX + 12, H)
click(musicX + 15, H)
click(musicX + 2, H)
assert(table.concat(seen.taps, " ") == "play next open", table.concat(seen.taps, " "))

-- Banners and calls run in the window in front, and only there: Music,
-- behind, is waiting too, and never runs it.
local ranIn = {}
ui.setBackgroundTask(1, function()
    ranIn[#ranIn + 1] = target
    return false
end)
tap("Music")
tap("Notes")
send("char", "!")
for _ = 1, 3 do tick() end
ui.setBackgroundTask(nil)
assert(#ranIn > 0, "it ran")
for _, where in ipairs(ranIn) do
    assert(where == seen.notes, "only in Notes, in front")
end
local musicWindow = desk.windows()[1]
assert(musicWindow.id == "music")
click(musicWindow.x + musicWindow.width - 2, 1)

-- Locked: over everything, and every tap is the lock screen's.
idle = 61 * 1000
tick()
assert(display.has("LOCKED") and not display.has(" Start "), display.dump())
send("char", "x")
assert(seen.typed == "hi!", "the window behind gets no keys")
tap("UNLOCK")
assert(seen.unlocked and display.has(" Start ") and display.has("NOTES hi!"))

-- Till Mode: the whole screen, no taskbar, never locked ---------------------------------------------

click(4, 10)
assert(seen.tillSize == W .. "x" .. H, tostring(seen.tillSize))
assert(desk.isKiosk() and display.has("TILL MODE") and not display.has(" Start "))
idle = 600 * 1000
tick()
assert(not display.has("LOCKED"), "Till Mode never locks")
tap("EXIT")
assert(not desk.isKiosk() and display.has(" Start "), "let go")
idle = 0

-- Phone layout: the desktop leaves, and says why.
click(2, H)
tap("Phone layout")
assert(finished and result == "phone", tostring(result))

io.write("host_desktop_test: OK\n")
