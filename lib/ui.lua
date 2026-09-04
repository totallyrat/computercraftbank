local util = require("lib.util")

local ui = {}

local phoneStyle = false
local idleTimeoutMs
local idleHandler
local lastActivityMs = util.nowMs()
local idleHandling = false
local backgroundIntervalMs
local backgroundHandler
local backgroundRunning = false
local lastBackgroundMs = util.nowMs()

ui.theme = {
    background = colors.black,
    panel = colors.gray,
    panelAlt = colors.lightGray,
    ink = colors.white,
    muted = colors.lightGray,
    accent = colors.cyan,
    accentDark = colors.blue,
    success = colors.lime,
    danger = colors.red,
    warning = colors.orange,
    shadow = colors.gray,
}

function ui.usePhoneStyle(enabled)
    phoneStyle = enabled == true
end

function ui.noteActivity()
    lastActivityMs = util.nowMs()
end

function ui.idleForMs()
    return math.max(0, util.nowMs() - lastActivityMs)
end

function ui.setIdleLock(seconds, handler)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 or type(handler) ~= "function" then
        idleTimeoutMs, idleHandler = nil, nil
        return
    end
    idleTimeoutMs = seconds * 1000
    idleHandler = handler
    ui.noteActivity()
end

-- A hook every Scene:wait polls, whatever screen is open. Urgent Contact uses
-- it so an incoming call reaches the user from anywhere, the same way the
-- idle lock already takes over from anywhere. The handler returns true when
-- it painted over the screen, and the caller is woken so it redraws.
function ui.setBackgroundTask(seconds, handler)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 or type(handler) ~= "function" then
        backgroundIntervalMs, backgroundHandler = nil, nil
        return
    end
    backgroundIntervalMs = seconds * 1000
    backgroundHandler = handler
    lastBackgroundMs = util.nowMs()
end

local function keyBindings(entries)
    local bindings = {}
    if type(keys) ~= "table" then return bindings end
    for keyName, action in pairs(entries or {}) do
        local keyCode = keys[keyName]
        if type(keyCode) == "number" then bindings[keyCode] = action end
    end
    return bindings
end

local function surface(target)
    return target or term.current()
end

function ui.size(target)
    return surface(target).getSize()
end

function ui.isColor(target)
    return surface(target).isColor()
end

function ui.clear(target, background)
    target = surface(target)
    target.setBackgroundColor(background or ui.theme.background)
    target.setTextColor(ui.theme.ink)
    target.clear()
    target.setCursorPos(1, 1)
end

function ui.fill(target, x, y, width, height, background, character)
    target = surface(target)
    local sw, sh = target.getSize()
    x, y = math.floor(x), math.floor(y)
    width = math.max(0, math.min(math.floor(width), sw - x + 1))
    height = math.max(0, math.min(math.floor(height), sh - y + 1))
    if width <= 0 or height <= 0 then return end
    target.setBackgroundColor(background)
    local line = string.rep(character or " ", width)
    for row = y, y + height - 1 do
        if row >= 1 and row <= sh then
            target.setCursorPos(math.max(1, x), row)
            target.write(line)
        end
    end
end

function ui.text(target, x, y, value, foreground, background, maxWidth)
    target = surface(target)
    local sw, sh = target.getSize()
    if y < 1 or y > sh or x > sw then return end
    value = tostring(value or "")
    if maxWidth then value = value:sub(1, math.max(0, maxWidth)) end
    if x < 1 then
        value = value:sub(2 - x)
        x = 1
    end
    if #value > sw - x + 1 then value = value:sub(1, sw - x + 1) end
    if background then target.setBackgroundColor(background) end
    target.setTextColor(foreground or ui.theme.ink)
    target.setCursorPos(x, y)
    target.write(value)
end

function ui.center(target, y, value, foreground, background, maxWidth)
    target = surface(target)
    local width = target.getSize()
    value = tostring(value or "")
    if maxWidth and #value > maxWidth then value = value:sub(1, maxWidth) end
    ui.text(target, math.max(1, math.floor((width - #value) / 2) + 1), y,
        value, foreground, background)
end

function ui.truncate(value, length)
    value = tostring(value or "")
    if #value <= length then return value end
    if length <= 2 then return value:sub(1, length) end
    return value:sub(1, length - 2) .. ".."
end

function ui.wrap(value, width)
    width = math.max(1, math.floor(tonumber(width) or 1))
    value = tostring(value or "")
    local lines = {}
    for paragraph in (value .. "\n"):gmatch("(.-)\n") do
        paragraph = util.trim(paragraph)
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            while #paragraph > width do
                local breakAt
                for index = width, 1, -1 do
                    if paragraph:sub(index, index) == " " then
                        breakAt = index
                        break
                    end
                end
                if not breakAt or breakAt < math.floor(width / 2) then
                    breakAt = width
                end
                lines[#lines + 1] = util.trim(paragraph:sub(1, breakAt))
                paragraph = util.trim(paragraph:sub(breakAt + 1))
            end
            if paragraph ~= "" then lines[#lines + 1] = paragraph end
        end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function ui.wrappedText(target, x, y, value, width, maxLines,
    foreground, background)
    width = math.max(1, math.floor(tonumber(width) or 1))
    maxLines = math.max(1, math.floor(tonumber(maxLines) or 1))
    local lines = ui.wrap(value, width)
    if #lines > maxLines then
        while #lines > maxLines do table.remove(lines) end
        lines[maxLines] = ui.truncate(lines[maxLines] .. "..", width)
    end
    for index, line in ipairs(lines) do
        ui.text(target, x, y + index - 1, line,
            foreground, background, width)
    end
    return #lines
end

function ui.header(target, title, subtitle, clockText)
    target = surface(target)
    local width = target.getSize()
    if phoneStyle then
        ui.fill(target, 1, 1, width, 3, ui.theme.background)
        ui.text(target, 2, 1, "PUMPE", ui.theme.muted, ui.theme.background)
        local clock = clockText or util.formatClock()
        ui.center(target, 1, clock, ui.theme.ink, ui.theme.background)
        ui.text(target, math.max(1, width - 2), 1, "[]",
            ui.theme.success, ui.theme.background)
        ui.text(target, 2, 2, ui.truncate(title, width - 3),
            ui.theme.ink, ui.theme.background)
        if subtitle then
            ui.text(target, 2, 3, ui.truncate(subtitle, width - 3),
                ui.theme.muted, ui.theme.background)
        end
        return
    end
    ui.fill(target, 1, 1, width, subtitle and 3 or 2, ui.theme.panel)
    local titleWidth = clockText and (width - #clockText - 3) or (width - 3)
    ui.text(target, 2, 1, ui.truncate(title, math.max(1, titleWidth)),
        ui.theme.ink, ui.theme.panel)
    if clockText then
        ui.text(target, math.max(1, width - #clockText + 1), 1, clockText,
            ui.theme.accent, ui.theme.panel)
    end
    if subtitle then
        ui.text(target, 2, 2, ui.truncate(subtitle, width - 3),
            ui.theme.muted, ui.theme.panel)
    end
    ui.fill(target, 1, subtitle and 3 or 2, width, 1, ui.theme.accent)
end

local Scene = {}
Scene.__index = Scene

function ui.scene(target)
    target = surface(target)
    local width, height = target.getSize()
    return setmetatable({
        target = target,
        width = width,
        height = height,
        buttons = {},
    }, Scene)
end

function Scene:button(id, x, y, width, height, label, options)
    options = options or {}
    width, height = math.max(1, width), math.max(1, height)
    local background = options.background or ui.theme.panel
    local foreground = options.foreground or ui.theme.ink
    if options.disabled then
        background, foreground = colors.gray, colors.lightGray
    end

    if options.shadow and x + width <= self.width and y + height <= self.height then
        ui.fill(self.target, x + 1, y + 1, width, height, ui.theme.shadow)
    end
    ui.fill(self.target, x, y, width, height, background)
    if phoneStyle and height >= 2 and width >= 4 then
        ui.fill(self.target, x, y, 1, 1, ui.theme.background)
        ui.fill(self.target, x + width - 1, y, 1, 1, ui.theme.background)
        ui.fill(self.target, x, y + height - 1, 1, 1, ui.theme.background)
        ui.fill(self.target, x + width - 1, y + height - 1,
            1, 1, ui.theme.background)
    end

    local labelWidth = math.max(1, width - 2)
    local lines = ui.wrap(label or "", labelWidth)
    if #lines > height then
        while #lines > height do table.remove(lines) end
        lines[height] = ui.truncate(lines[height] .. "..", labelWidth)
    end
    local firstY = y + math.floor((height - #lines) / 2)
    for index, line in ipairs(lines) do
        local textX = x + math.max(0, math.floor((width - #line) / 2))
        ui.text(self.target, textX, firstY + index - 1, line, foreground, background)
    end

    if not options.disabled then
        self.buttons[#self.buttons + 1] = {
            id = id, x1 = x, y1 = y,
            x2 = x + width - 1, y2 = y + height - 1,
            background = background,
        }
    end
end

function Scene:hit(x, y)
    for index = #self.buttons, 1, -1 do
        local button = self.buttons[index]
        if x >= button.x1 and x <= button.x2
            and y >= button.y1 and y <= button.y2 then
            return button.id, button
        end
    end
    return nil
end

function Scene:wait(options)
    options = options or {}
    local timer
    if options.tickRate then
        timer = os.startTimer(options.tickRate)
    end
    local idleTimer

    local function cancelTimer(timerId)
        if timerId and os.cancelTimer then pcall(os.cancelTimer, timerId) end
    end

    local backgroundTimer

    local function backgroundDue()
        if not backgroundIntervalMs or not backgroundHandler
            or backgroundRunning then return nil end
        return math.max(0, backgroundIntervalMs
            - (util.nowMs() - lastBackgroundMs))
    end

    local function scheduleBackgroundTimer()
        local remaining = backgroundDue()
        if not remaining then return nil end
        return os.startTimer(math.max(0.05, remaining / 1000))
    end

    local function runBackgroundTask()
        local remaining = backgroundDue()
        if not remaining or remaining > 0 then return false end
        lastBackgroundMs = util.nowMs()
        backgroundRunning = true
        local ok, tookOver = pcall(backgroundHandler)
        backgroundRunning = false
        lastBackgroundMs = util.nowMs()
        if not ok then error(tookOver, 0) end
        return tookOver == true
    end

    local function scheduleIdleTimer()
        if not idleTimeoutMs or not idleHandler or idleHandling then return nil end
        local remaining = math.max(50, idleTimeoutMs - ui.idleForMs())
        return os.startTimer(remaining / 1000)
    end

    local function finish(action)
        cancelTimer(timer)
        cancelTimer(idleTimer)
        cancelTimer(backgroundTimer)
        return action
    end

    local function recordActivity()
        if idleHandling then return end
        ui.noteActivity()
        cancelTimer(idleTimer)
        idleTimer = scheduleIdleTimer()
    end

    local function handleIdle()
        if idleHandling or not idleTimeoutMs or not idleHandler
            or ui.idleForMs() < idleTimeoutMs then return false end
        idleHandling = true
        local ok, err = pcall(idleHandler, ui.idleForMs())
        idleHandling = false
        ui.noteActivity()
        if not ok then error(err, 0) end
        return true
    end

    -- Run it before waiting too, so a screen that ticks faster than the
    -- interval still lets the task through.
    if runBackgroundTask() then return finish("__wake") end
    idleTimer = scheduleIdleTimer()
    backgroundTimer = scheduleBackgroundTimer()
    while true do
        local event = { os.pullEvent() }
        if event[1] == "mouse_click" or event[1] == "monitor_touch" then
            if handleIdle() then return finish("__idle") end
            recordActivity()
            local action, button = self:hit(event[3], event[4])
            if action then
                if options.flash ~= false then
                    ui.fill(self.target, button.x1, button.y1,
                        button.x2 - button.x1 + 1,
                        button.y2 - button.y1 + 1, ui.theme.accentDark)
                    sleep(0.04)
                end
                return finish(action)
            end
        elseif event[1] == "key" then
            if handleIdle() then return finish("__idle") end
            recordActivity()
            local action = options.keys and options.keys[event[2]]
            if action then return finish(action) end
        elseif event[1] == "char" then
            if handleIdle() then return finish("__idle") end
            recordActivity()
            local action = options.onChar and options.onChar(event[2])
            if action then return finish(action) end
        elseif backgroundTimer and event[1] == "timer"
            and event[2] == backgroundTimer then
            if runBackgroundTask() then return finish("__wake") end
            backgroundTimer = scheduleBackgroundTimer()
        elseif idleTimer and event[1] == "timer" and event[2] == idleTimer then
            if handleIdle() then return finish("__idle") end
            idleTimer = scheduleIdleTimer()
        elseif timer and event[1] == "timer" and event[2] == timer then
            if handleIdle() then return finish("__idle") end
            return finish("__tick")
        elseif event[1] == "terminate" then
            return finish("__terminate")
        end
    end
end

function ui.progress(target, x, y, width, value, maximum, foreground, background)
    maximum = maximum == 0 and 1 or maximum
    local fraction = util.clamp((value or 0) / (maximum or 1), 0, 1)
    ui.fill(target, x, y, width, 1, background or colors.gray)
    ui.fill(target, x, y, math.floor(width * fraction + 0.5), 1,
        foreground or ui.theme.accent)
end

function ui.card(target, x, y, width, height, accent)
    ui.fill(target, x, y, width, height, ui.theme.panel)
    ui.fill(target, x, y, 1, height, accent or ui.theme.accent)
    if phoneStyle and width >= 4 and height >= 2 then
        ui.fill(target, x, y, 1, 1, ui.theme.background)
        ui.fill(target, x + width - 1, y, 1, 1, ui.theme.background)
        ui.fill(target, x, y + height - 1, 1, 1, ui.theme.background)
        ui.fill(target, x + width - 1, y + height - 1,
            1, 1, ui.theme.background)
    end
end

function ui.wipe(target, title)
    target = surface(target)
    local width, height = target.getSize()
    target.setCursorBlink(false)
    for row = 1, height do
        ui.fill(target, 1, row, width, 1,
            row % 2 == 0 and ui.theme.panel or ui.theme.background)
        if row % 3 == 0 then sleep(0.01) end
    end
    if title then
        ui.center(target, math.max(1, math.floor(height / 2)), title,
            ui.theme.accent, ui.theme.background)
        sleep(0.15)
    end
    ui.clear(target)
end

function ui.boot(target, product, subtitle)
    target = surface(target)
    local width, height = target.getSize()
    ui.clear(target)
    local centerY = math.max(3, math.floor(height / 2) - 1)
    for step = 1, 4 do
        ui.clear(target)
        ui.center(target, centerY, product, ui.theme.ink)
        ui.center(target, centerY + 1, subtitle or "PUMPE ECOSYSTEM",
            ui.theme.muted)
        local barWidth = math.max(8, math.min(width - 6, 28))
        ui.progress(target, math.floor((width - barWidth) / 2) + 1,
            centerY + 3, barWidth, step, 4, ui.theme.accent, ui.theme.panel)
        sleep(0.09)
    end
end

function ui.message(target, kind, title, body, duration)
    target = surface(target)
    local width, height = target.getSize()
    local color = kind == "success" and ui.theme.success
        or kind == "warning" and ui.theme.warning
        or kind == "error" and ui.theme.danger
        or ui.theme.accent
    local mark = kind == "success" and "OK"
        or kind == "error" and "!"
        or kind == "warning" and "!"
        or "i"

    -- Wrap first, then centre the finished block, so long messages read the
    -- same way on a 26x20 pocket screen and a wide kiosk.
    local contentWidth = math.max(4, width - 4)
    local titleLines = ui.wrap(title, contentWidth)
    local bodyLines = body and ui.wrap(body, contentWidth) or {}
    local function blockHeight()
        return 3 + #titleLines + (#bodyLines > 0 and 1 + #bodyLines or 0)
    end
    local function trimTo(lines)
        lines[#lines] = ui.truncate(lines[#lines] .. "..", contentWidth)
    end
    while blockHeight() > height and #bodyLines > 0 do
        table.remove(bodyLines)
        if #bodyLines > 0 then trimTo(bodyLines) end
    end
    while blockHeight() > height and #titleLines > 1 do
        table.remove(titleLines)
        trimTo(titleLines)
    end

    ui.fill(target, 1, 1, width, height, ui.theme.background)
    local y = math.max(1, math.floor((height - blockHeight()) / 2) + 1)
    for size = 1, 3 do
        ui.fill(target, math.floor((width - size * 3) / 2) + 1, y, size * 3, 2,
            color)
        sleep(0.05)
    end
    ui.center(target, y, mark, colors.black, color)
    local row = y + 3
    for _, line in ipairs(titleLines) do
        ui.center(target, row, line, color)
        row = row + 1
    end
    if #bodyLines > 0 then
        row = row + 1
        for _, line in ipairs(bodyLines) do
            ui.center(target, row, line, ui.theme.muted)
            row = row + 1
        end
    end
    sleep(duration or 0.8)
end

local function keyboardRows(mode)
    if mode == "integer" then return { "123", "456", "789", "-0<" } end
    if mode == "number" then return { "123", "456", "789", ".0<" } end
    if mode == "code" then return { "1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM<" } end
    return { "1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM-_<" }
end

function ui.input(target, title, options)
    target = surface(target)
    options = options or {}
    local width, height = target.getSize()
    local value = tostring(options.initial or "")
    local maxLength = options.maxLength or 24
    local rows = keyboardRows(options.mode)
    local blink = true

    while true do
        ui.clear(target)
        ui.header(target, title, options.hint)
        local fieldY = options.hint and 5 or 4
        ui.fill(target, 2, fieldY, width - 2, 3, ui.theme.panel)
        local shown = value
        if options.mask then shown = string.rep(options.mask, #value) end
        local visibleLength = width - 5
        if options.scrollToEnd and #shown > visibleLength then
            shown = "<" .. shown:sub(-(visibleLength - 1))
        else
            shown = ui.truncate(shown, visibleLength)
        end
        ui.text(target, 3, fieldY + 1, shown .. (blink and "_" or " "),
            ui.theme.ink, ui.theme.panel, width - 4)

        -- Lay the screen out from the bottom up so the action row, the space
        -- bar, and the keyboard always fit whatever height the surface has.
        local actionHeight = height >= 18 and 2 or 1
        local actionY = height - actionHeight + 1
        local spaceY = options.allowSpace and actionY - 1 or nil
        local keyBottom = (spaceY or actionY) - 1
        local startY = math.max(fieldY + 3, keyBottom - #rows + 1)
        local scene = ui.scene(target)
        for rowIndex, row in ipairs(rows) do
            local y = startY + rowIndex - 1
            if y <= keyBottom then
                local keyWidth = math.max(1, math.floor((width - 2) / #row))
                local totalWidth = keyWidth * #row
                local startX = math.floor((width - totalWidth) / 2) + 1
                for index = 1, #row do
                    local key = row:sub(index, index)
                    scene:button("key:" .. key, startX + (index - 1) * keyWidth,
                        y, keyWidth, 1, key, {
                            background = key == "<" and ui.theme.danger
                                or ui.theme.panelAlt,
                            foreground = key == "<" and colors.white
                                or colors.black,
                        })
                end
            end
        end
        if spaceY then
            scene:button("space", 2, spaceY, width - 2, 1, "SPACE",
                { background = ui.theme.panel })
        end
        local half = math.floor((width - 2) / 2)
        scene:button("cancel", 2, actionY, half, actionHeight, "CANCEL",
            { background = ui.theme.panel })
        scene:button("ok", 2 + half, actionY, width - 2 - half, actionHeight,
            "DONE", { background = ui.theme.accentDark })

        local action = scene:wait({
            tickRate = 0.4,
            onChar = function(character)
                return "typed:" .. character
            end,
            keys = keyBindings({
                backspace = "backspace",
                enter = "ok",
                numPadEnter = "ok",
                escape = "cancel",
            }),
            flash = false,
        })
        if action == "__tick" then
            blink = not blink
        elseif action == "cancel" or action == "__terminate" then
            return nil
        elseif action == "ok" then
            local trimmed = options.keepSpaces and value or util.trim(value)
            if #trimmed >= (options.minLength or 1) then return trimmed end
        elseif action == "space" and #value < maxLength then
            value = value .. " "
        elseif action == "backspace" or action == "key:<" then
            value = value:sub(1, -2)
        else
            local key = action and action:match("^key:(.)$")
            local typed = action and action:match("^typed:(.)$")
            local character = key or typed
            if character and character ~= "<" and #value < maxLength then
                if options.mode == "integer" then
                    -- A minus sign only means anything at the front.
                    if character:match("%d") then
                        value = value .. character
                    elseif character == "-" and #value == 0 then
                        value = "-"
                    end
                elseif options.mode == "number" then
                    if character:match("%d") or (character == "." and not value:find("%.")) then
                        value = value .. character
                    end
                elseif options.mode == "code" then
                    if character:match("[%w]") then value = value .. string.upper(character) end
                else
                    value = value .. character
                end
            end
        end
    end
end

function ui.pin(target, title, allowCancel)
    target = surface(target)
    local width, height = target.getSize()
    local value = ""
    local layout = {
        { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
        { "C", "0", "<" },
    }
    while true do
        ui.clear(target)
        ui.header(target, title or "ENTER PIN", "Four digits")
        ui.center(target, 5, string.rep("* ", #value) .. string.rep("- ", 4 - #value),
            ui.theme.accent)
        local scene = ui.scene(target)
        local buttonWidth = math.max(5, math.min(10, math.floor((width - 6) / 3)))
        local gridWidth = buttonWidth * 3 + 2
        local startX = math.floor((width - gridWidth) / 2) + 1
        local bottom = allowCancel and height - 1 or height
        local startY = math.max(7, math.floor((height - 8) / 2) + 5)
        local rowStep = startY + 6 <= bottom and 2 or 1
        if startY + rowStep * 3 > bottom then
            startY = math.max(4, bottom - rowStep * 3)
        end
        for row = 1, 4 do
            for column = 1, 3 do
                local label = layout[row][column]
                scene:button("pin:" .. label,
                    startX + (column - 1) * (buttonWidth + 1),
                    startY + (row - 1) * rowStep, buttonWidth, 1, label, {
                        background = label == "C" and ui.theme.danger
                            or label == "<" and ui.theme.panel
                            or ui.theme.panelAlt,
                        foreground = label:match("%d") and colors.black or colors.white,
                    })
            end
        end
        if allowCancel then
            scene:button("cancel", 2, height, math.min(8, width - 2), 1, "BACK",
                { background = ui.theme.panel })
        end
        local action = scene:wait({
            keys = keyBindings({
                backspace = "pin:<",
                escape = "cancel",
            }),
            onChar = function(character)
                if character:match("%d") then return "pin:" .. character end
            end,
            flash = false,
        })
        if action == "cancel" or action == "__terminate" then return nil end
        local key = action and action:match("^pin:(.)$")
        if key == "C" then
            value = ""
        elseif key == "<" then
            value = value:sub(1, -2)
        elseif key and key:match("%d") and #value < 4 then
            value = value .. key
            if #value == 4 then
                sleep(0.08)
                return value
            end
        end
    end
end

function ui.confirm(target, title, body, yesLabel, noLabel)
    target = surface(target)
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, title)
    -- Every confirmation wraps now. Kiosks used to truncate the description to
    -- a single line, hiding what the customer was actually approving.
    local lines = ui.wrap(body or "", math.max(4, width - 4))
    local bodyY = math.max(5, math.floor((height - 3 - #lines) / 2) + 1)
    local maxBodyLines = math.max(1, height - 4 - bodyY)
    if #lines > maxBodyLines then
        while #lines > maxBodyLines do table.remove(lines) end
        lines[maxBodyLines] = ui.truncate(lines[maxBodyLines] .. "..", width - 4)
    end
    for index, line in ipairs(lines) do
        ui.center(target, bodyY + index - 1, line, ui.theme.ink)
    end
    local scene = ui.scene(target)
    local buttonWidth = math.max(8, math.floor((width - 6) / 2))
    scene:button("no", 2, height - 3, buttonWidth, 2, noLabel or "NO",
        { background = ui.theme.panel })
    scene:button("yes", width - buttonWidth, height - 3, buttonWidth, 2,
        yesLabel or "YES", { background = ui.theme.accentDark })
    return scene:wait({ keys = keyBindings({
        y = "yes",
        n = "no",
        escape = "no",
    }) }) == "yes"
end

function ui.networkError(target, err)
    ui.message(target, "error", "CONNECTION FAILED", err or "Try again", 1.1)
end

return ui
