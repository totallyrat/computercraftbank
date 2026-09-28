-- The real lib/ui on a screen that remembers what was drawn on it.
--
-- Most tests replace lib/ui with a stub that records calls. That is quick,
-- and it is also more forgiving than the real thing: a stub scene takes any
-- tap it is told to, whatever is really on the screen. This harness keeps
-- the real library and gives it a terminal made of a character grid, so a
-- test can read the screen back, and it drives the program with the events
-- ComputerCraft would send -- a tap is aimed at a button by id through the
-- real scene's own hit test, so it lands only on something that is there.
--
-- screen.terminal(width, height) -> a terminal (or monitor) that keeps a grid
-- screen.install(options) -> loads the real lib/ui and wires os.pullEvent to
--   a script. Steps: "<button id>" taps it, { char = "x" }, { key = n },
--   { tick = true } fires the timer the screen is waiting on, { raw = {...} }
--   sends an event as is, and a function(state) returns one of those.

local screen = {}

colors = colors or {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
colours = colours or colors
keys = keys or { enter = 257, backspace = 259, escape = 256, up = 265, down = 264,
    left = 263, right = 262, space = 32, tab = 258, delete = 261, home = 268,
    ["end"] = 269 }

function screen.terminal(width, height)
    local grid = {}
    local cursorX, cursorY = 1, 1
    local text, back = colors.white, colors.black
    local function wipe()
        for y = 1, height do
            grid[y] = {}
            for x = 1, width do grid[y][x] = " " end
        end
    end
    wipe()
    local t = {}
    t.getSize = function() return width, height end
    t.isColor = function() return true end
    t.isColour = t.isColor
    t.setTextScale = function() end
    t.getTextScale = function() return 0.5 end
    t.setCursorBlink = function() end
    t.getCursorPos = function() return cursorX, cursorY end
    t.setCursorPos = function(x, y) cursorX, cursorY = math.floor(x), math.floor(y) end
    t.setTextColor = function(color) text = color end
    t.setTextColour = t.setTextColor
    t.getTextColor = function() return text end
    t.getTextColour = t.getTextColor
    t.setBackgroundColor = function(color) back = color end
    t.setBackgroundColour = t.setBackgroundColor
    t.getBackgroundColor = function() return back end
    t.getBackgroundColour = t.getBackgroundColor
    t.clear = wipe
    t.clearLine = function()
        if grid[cursorY] then
            for x = 1, width do grid[cursorY][x] = " " end
        end
    end
    t.write = function(value)
        value = tostring(value)
        for index = 1, #value do
            local x = cursorX + index - 1
            if grid[cursorY] and x >= 1 and x <= width then
                grid[cursorY][x] = value:sub(index, index)
            end
        end
        cursorX = cursorX + #value
    end
    t.blit = function(value) t.write(value) end
    t.scroll = function(lines)
        for _ = 1, lines do
            table.remove(grid, 1)
            local row = {}
            for x = 1, width do row[x] = " " end
            grid[#grid + 1] = row
        end
    end
    -- For the test: what is on the screen now.
    t.lines = function()
        local out = {}
        for y = 1, height do out[y] = table.concat(grid[y]) end
        return out
    end
    t.has = function(wanted)
        for y = 1, height do
            if table.concat(grid[y]):find(wanted, 1, true) then return true end
        end
        return false
    end
    t.dump = function() return table.concat(t.lines(), "\n") end
    return t
end

-- options: display (the terminal the program draws on), event ("mouse_click"
-- or "monitor_touch"), steps (the script). Returns the real ui and a state
-- table: state.scene is the last scene drawn, state.seen every step taken.
function screen.install(options)
    local state = { steps = options.steps or {}, seen = {}, timers = {},
        display = options.display }
    local timerId = 0
    os.startTimer = function(seconds)
        timerId = timerId + 1
        state.timers[#state.timers + 1] = timerId
        return timerId
    end
    os.cancelTimer = function() end
    sleep = function() end

    -- The real library, loaded fresh against whatever lib.util the test
    -- has put in place.
    local ui = dofile("../lib/ui.lua")
    -- Taps go to the scene that is waiting, which is not always the last one
    -- drawn: a screen can paint a sample in a second scene.
    local Scene = getmetatable(ui.scene(options.display)).__index
    local realWait = Scene.wait
    Scene.wait = function(self, ...)
        state.scene = self
        return realWait(self, ...)
    end

    local function tapAt(id)
        local scene = state.scene
        assert(scene, "tapped " .. tostring(id) .. " before anything was drawn")
        for index = #scene.buttons, 1, -1 do
            local button = scene.buttons[index]
            if button.id == id then
                -- The hit test is the real one: the button that answers at
                -- this spot must be the one asked for.
                for y = button.y1, button.y2 do
                    for x = button.x1, button.x2 do
                        if scene:hit(x, y) == id then return x, y end
                    end
                end
            end
        end
        local shown = {}
        for _, button in ipairs(scene.buttons) do shown[#shown + 1] = tostring(button.id) end
        error("tapped " .. tostring(id) .. ", which is not on the screen. There is: "
            .. table.concat(shown, ", ") .. "\n" .. state.display.dump(), 0)
    end

    os.pullEvent = function(filter)
        local step = table.remove(state.steps, 1)
        if step == nil then
            error("the program waited for input that never came. The screen:\n"
                .. state.display.dump(), 0)
        end
        if type(step) == "function" then step = step(state) end
        state.seen[#state.seen + 1] = step
        local timersBefore = state.timers
        state.timers = {}
        if type(step) == "string" then
            local x, y = tapAt(step)
            if options.event == "mouse_click" then return "mouse_click", 1, x, y end
            return "monitor_touch", "top", x, y
        elseif step.char then
            return "char", step.char
        elseif step.key then
            return "key", step.key, false
        elseif step.tick then
            -- The first timer the screen started while it waited is its own
            -- tick; the rest are idle and background timers.
            return "timer", timersBefore[1] or 0
        elseif step.raw then
            return table.unpack(step.raw)
        elseif step.terminate then
            error("Terminated", 0)
        end
        error("unknown step", 0)
    end
    os.pullEventRaw = os.pullEvent
    return ui, state
end

-- Typing: each character as its own event, then Enter.
function screen.typed(text)
    local steps = {}
    for index = 1, #text do steps[#steps + 1] = { char = text:sub(index, index) } end
    steps[#steps + 1] = { key = keys.enter }
    return steps
end

function screen.push(queue, ...)
    for _, entry in ipairs({ ... }) do
        if type(entry) == "table" and entry[1] ~= nil and not entry.char then
            for _, inner in ipairs(entry) do queue[#queue + 1] = inner end
        else
            queue[#queue + 1] = entry
        end
    end
end

return screen
