-- The Pocket Desktop, FoxyOS 18: the Pocket on a standing computer's screen,
-- with a desktop, and every app in a window of its own.
--
-- Each window runs its app in a coroutine of its own, the way ComputerCraft's
-- multishell runs programs: what the app draws goes to its window; a tap on
-- the window comes to it moved to the window's corner; keys go to the window
-- in front; and everything else -- timers, rednet, speakers -- goes to every
-- window, so one behind keeps working. Nothing draws on the screen itself.
-- Every window keeps its own picture, and the screen is put together from
-- them, back to front, whenever one of them changed.
--
-- The desktop is a window too, at the back, as big as the screen above the
-- taskbar: the Pocket draws its icons there (spec.home). The taskbar along
-- the bottom row has Start, a button for each window, the music playing and
-- the clock. An app with tabs has them down a sidebar on its window's left
-- rather than along the bottom (ui.tabBar, through ui.setSidebar): its window
-- widens to make room the first time. A modal -- the lock screen -- covers
-- everything and takes every tap and key; a kiosk window (Till Mode) fills
-- the screen and keeps it until it lets go. A window's x, or Ctrl+T, ends its
-- app there and then.
--
-- desktop.run(spec) runs it until the desktop's own window ends or
-- desk.leave(why) is called, and returns why. spec:
--   screen     the terminal to draw on (term.current() at start)
--   ui         lib/ui
--   setTarget  function(t): where the Pocket draws -- the window being run
--   home       function(desk): the desktop window's program
--   menu       function() -> { { id, label }... }: Start's menu
--   choose     function(id, desk): one of them, run in the background
--   music      { status() -> { title, paused } or nil, tap(part, desk) }
--   services   { function()... }: run in the background, given every event
--   lock       { seconds = n, run = function() }: the lock screen, as a modal
--   clock      function() -> "12:00"
--   running    function() -> false to stop

local desktop = { SIDEBAR = 10, BODY_WIDTH = 26, MIN_WIDTH = 39, MIN_HEIGHT = 13 }

-- A standing computer's screen, wide enough for a window and some desktop.
-- A pocket computer never: it is a Pocket already.
function desktop.fits(screen)
    if rawget(_G, "pocket") ~= nil then return false end
    if type(rawget(_G, "window")) ~= "table" or not screen then return false end
    local ok, width, height = pcall(screen.getSize)
    return ok and width >= desktop.MIN_WIDTH and height >= desktop.MIN_HEIGHT
end

local INPUT = { key = true, key_up = true, char = true, paste = true,
    file_transfer = true, monitor_touch = true, terminate = true }
local MOUSE = { mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true }

function desktop.run(spec)
    local ui, screen = spec.ui, spec.screen
    local theme = ui.theme
    local W, H = screen.getSize()
    local TOP = H - 1 -- rows above the taskbar
    local SIDE = desktop.SIDEBAR
    local tasks, services, pending = {}, {}, {}
    local home, modal, kiosk, focused, current
    local dirty, composing = true, false
    local capture, drag, menu
    local leaving, why
    local desk = { width = W, height = H }

    -- Every drawing call on a window marks the screen as needing putting
    -- together again. A window inside one draws through it, so this catches
    -- the app's drawing too.
    local function watch(frame)
        for _, name in ipairs({ "write", "blit", "clear", "clearLine", "scroll" }) do
            local real = frame[name]
            frame[name] = function(...)
                if not composing then dirty = true end
                return real(...)
            end
        end
        return frame
    end

    local function front()
        return modal or kiosk or focused or home
    end

    -- Where a window's app draws, relative to its frame.
    local function bodyAt(task)
        if task.kind ~= "app" then return 1, 1 end
        local left = (task.side and not task.kiosk) and SIDE + 1 or 1
        return left, task.kiosk and 1 or 2
    end

    local function geometry(task)
        local left, top = bodyAt(task)
        local width = task.kiosk and W or task.w
        local height = task.kiosk and H or TOP
        task.frame.reposition(task.kiosk and 1 or task.x, 1, width, height)
        task.body.reposition(left, top, width - left + 1, height - top + 1)
        dirty = true
    end

    local function focus(task)
        if not task or task.dead then task = nil end
        if task and task.kind == "app" then
            for index, other in ipairs(tasks) do
                if other == task then table.remove(tasks, index) break end
            end
            tasks[#tasks + 1] = task
            task.minimized = false
        end
        focused = task and task.kind == "app" and task or nil
        if ui.setForeground then ui.setForeground(front().body) end
        dirty = true
    end

    -- The topmost window that is not minimized, or the desktop.
    local function topWindow()
        for index = #tasks, 1, -1 do
            local task = tasks[index]
            if task.kind == "app" and not task.minimized and not task.dead then return task end
        end
        return nil
    end

    local function close(task)
        task.dead = true
        if ui.setSidebar then ui.setSidebar(task.body, nil) end
        for index, other in ipairs(tasks) do
            if other == task then table.remove(tasks, index) break end
        end
        if capture == task then capture = nil end
        if drag and drag.task == task then drag = nil end
        if modal == task then modal = nil end
        if kiosk == task then kiosk = nil end
        if task == home then leaving = true end
        if focused == task or not focused then focus(topWindow()) end
        if ui.setForeground then ui.setForeground(front().body) end
        dirty = true
    end

    local function resume(task, event)
        if task.dead then return end
        local before = current
        current = task
        -- Something in the background draws, if it draws, on the desktop.
        local surface = task.body or home.body
        spec.setTarget(surface)
        local previous = term.redirect(surface)
        local ok, filter
        if event then
            ok, filter = coroutine.resume(task.co, table.unpack(event, 1, event.n or #event))
        else
            ok, filter = coroutine.resume(task.co)
        end
        term.redirect(previous)
        current = before
        spec.setTarget(before and before.body or home.body)
        if not ok then
            task.error = filter
            desk.error = filter
            close(task)
        elseif coroutine.status(task.co) == "dead" then
            close(task)
        else
            task.filter = filter
        end
    end

    local function deliver(task, event)
        if not task or task.dead then return end
        if task.filter ~= nil and task.filter ~= event[1] and event[1] ~= "terminate" then
            return
        end
        resume(task, event)
    end

    -- A tap, moved to the window's own corner. Left of a window's app is its
    -- sidebar, at columns 0 and below.
    local function moved(event, task)
        local left, top = bodyAt(task)
        local x0 = task.kind == "app" and not task.kiosk and task.x or 1
        local copy = { event[1], event[2], event[3] - x0 - left + 2, event[4] - top + 1, n = 4 }
        return copy
    end

    local function newTask(kind, run, options)
        options = options or {}
        local task = { kind = kind, title = tostring(options.title or ""), id = options.id,
            co = coroutine.create(run) }
        if kind == "home" then
            task.frame = watch(window.create(screen, 1, 1, W, TOP, false))
            task.body = task.frame
        elseif kind == "modal" then
            task.frame = watch(window.create(screen, 1, 1, W, H, false))
            task.body = task.frame
        elseif kind == "app" then
            local open = 0
            for _, other in ipairs(tasks) do
                if other.kind == "app" and not other.dead then open = open + 1 end
            end
            task.w = math.min(W, tonumber(options.width) or desktop.BODY_WIDTH)
            task.x = math.max(1, W - task.w + 1 - (open % 4) * 3)
            task.frame = watch(window.create(screen, task.x, 1, task.w, TOP, false))
            task.body = window.create(task.frame, 1, 2, task.w, TOP - 1, true)
            -- The sidebar: made the first time the app draws its tabs.
            if ui.setSidebar then
                ui.setSidebar(task.body, { width = SIDE, open = function()
                    if task.kiosk then return nil end
                    if not task.side then
                        task.side = true
                        if not task.maximized then
                            task.w = math.min(W, task.w + SIDE)
                            task.x = math.max(1, math.min(task.x, W - task.w + 1))
                        end
                        geometry(task)
                    end
                    return task.frame, SIDE + 1, 2
                end })
            end
        end
        return task
    end

    local function start(task)
        if task.kind == "service" then
            services[#services + 1] = task
        elseif task.kind == "modal" then
            modal = task
        elseif task.kind == "app" then
            tasks[#tasks + 1] = task
            focus(task)
        end
        resume(task)
    end

    -- The desktop, to the Pocket and its apps ----------------------------------------------------

    -- An app in a window of its own. One window per `options.id`: asked again,
    -- that window comes to the front.
    function desk.open(run, options)
        options = options or {}
        if options.id then
            for _, task in ipairs(tasks) do
                if task.id == options.id and not task.dead then
                    pending[#pending + 1] = { focus = task }
                    return task
                end
            end
        end
        local task = newTask("app", run, options)
        pending[#pending + 1] = task
        return task
    end

    -- Over everything, with every tap and key, until it returns.
    function desk.modal(run)
        local task = newTask("modal", run)
        pending[#pending + 1] = task
        return task
    end

    -- Something to do in the background, with every event.
    function desk.spawn(run)
        local task = { kind = "service", co = coroutine.create(run), body = nil }
        pending[#pending + 1] = task
        return task
    end

    -- Till Mode: the window asking fills the screen -- no title, no sidebar,
    -- no taskbar -- and keeps it until it lets go. The desktop never locks
    -- while it does.
    function desk.kiosk(on)
        local task = current
        if not task or task.kind ~= "app" then return false end
        if on and not task.kiosk then
            if kiosk and kiosk ~= task then return false end
            task.kiosk, kiosk = true, task
            geometry(task)
            focus(task)
        elseif not on and task.kiosk then
            task.kiosk, kiosk = false, nil
            geometry(task)
            focus(task)
        end
        return true
    end

    function desk.isKiosk() return kiosk ~= nil end

    function desk.leave(reason)
        leaving, why = true, reason
    end

    function desk.windows()
        local list = {}
        for _, task in ipairs(tasks) do
            if task.kind == "app" and not task.dead then
                list[#list + 1] = { id = task.id, title = task.title, minimized = task.minimized,
                    focused = task == focused, kiosk = task.kiosk, x = task.x, width = task.w,
                    sidebar = task.side == true }
            end
        end
        return list
    end

    desk.focused = function() return focused and focused.id end

    -- Putting the screen together --------------------------------------------------------------

    local function buttonsOf(task)
        local w = task.w
        return { { "min", w - 8, "_" }, { "max", w - 5, task.maximized and "=" or "o" },
            { "close", w - 2, "x" } }
    end

    local function paintTitle(task)
        local on = task == focused
        local back = on and theme.accent or theme.panel
        local ink = on and (theme.accentInk or ui.inkOn(back)) or theme.ink
        ui.fill(task.frame, 1, 1, task.w, 1, back)
        ui.text(task.frame, 2, 1, ui.truncate(task.title, math.max(1, task.w - 11)), ink, back)
        for _, button in ipairs(buttonsOf(task)) do
            local danger = button[1] == "close"
            ui.text(task.frame, button[2], 1, " " .. button[3] .. " ",
                danger and colors.white or ink, danger and theme.danger or back)
        end
    end

    -- The taskbar: Start, a button for each window, the music, the clock.
    -- Windows that do not fit share one "+n" button, which brings them
    -- forward in turn.
    local MUSIC_X = W - 23
    local function taskbarItems()
        local open, items = {}, {}
        for _, task in ipairs(tasks) do
            if task.kind == "app" and not task.dead then open[#open + 1] = task end
        end
        local last = (spec.music and MUSIC_X - 2 or W - 6)
        local fits = math.max(0, math.floor((last - 9 + 2) / 9))
        for index, task in ipairs(open) do
            local x = 9 + (index - 1) * 9
            if index > fits or (index == fits and #open > fits) then
                items[#items + 1] = { task = open[index], x = x, w = 4,
                    label = "+" .. (#open - index + 1) }
                break
            end
            items[#items + 1] = { task = task, x = x, w = 8 }
        end
        return items
    end

    local function paintTaskbar()
        ui.fill(screen, 1, H, W, 1, theme.panel)
        ui.text(screen, 1, H, " Start ", theme.accentInk or ui.inkOn(theme.accent), theme.accent)
        for _, item in ipairs(taskbarItems()) do
            local on = item.task == focused and not item.label
            local back = on and theme.accentDark or theme.panelAlt or theme.panel
            local label = item.label or ui.truncate(item.task.title, item.w - 2)
            ui.text(screen, item.x, H, " " .. label .. string.rep(" ", item.w - 1 - #label),
                item.task.minimized and theme.muted or (on and colors.white or theme.ink), back)
        end
        local now = spec.music and spec.music.status and spec.music.status()
        if now then
            ui.text(screen, MUSIC_X, H, string.char(14) .. " " .. ui.truncate(tostring(now.title
                or "Music"), 9), theme.ink, theme.panel)
            ui.text(screen, MUSIC_X + 11, H, now.paused and " > " or " ||", theme.ink,
                theme.panelAlt or theme.panel)
            ui.text(screen, MUSIC_X + 14, H, " >|", theme.ink, theme.panelAlt or theme.panel)
        elseif spec.music then
            ui.text(screen, MUSIC_X, H, string.char(14) .. " Music", theme.muted, theme.panel)
        end
        local clock = spec.clock and spec.clock() or ""
        ui.text(screen, W - #clock + 1, H, clock, theme.ink, theme.panel)
    end

    local function menuItems()
        return type(spec.menu) == "function" and spec.menu() or {}
    end

    local function paintMenu()
        local items = menuItems()
        local width = 4
        for _, item in ipairs(items) do width = math.max(width, #item.label + 2) end
        local top = H - #items
        menu = { x = 1, top = top, width = width, items = items }
        for index, item in ipairs(items) do
            ui.fill(screen, 1, top + index - 1, width, 1, theme.panel)
            ui.text(screen, 2, top + index - 1, item.label, theme.ink, theme.panel)
        end
    end

    local function placeCursor()
        local task = front()
        local body = task and task.body
        if not body then return end
        local okBlink, blink = pcall(function() return body.getCursorBlink() end)
        local cx, cy = body.getCursorPos()
        local bw, bh = body.getSize()
        local left, top = bodyAt(task)
        local x0 = task.kind == "app" and not task.kiosk and task.x or 1
        local on = okBlink and blink and cx >= 1 and cy >= 1 and cx <= bw and cy <= bh
        screen.setCursorBlink(on == true)
        if on then
            screen.setCursorPos(x0 + left - 2 + cx, top - 1 + cy)
            screen.setTextColor(body.getTextColor())
        end
    end

    local function compose()
        composing = true
        if kiosk then
            kiosk.frame.setVisible(true)
            kiosk.frame.setVisible(false)
        else
            home.frame.setVisible(true)
            home.frame.setVisible(false)
            for _, task in ipairs(tasks) do
                if task.kind == "app" and not task.minimized and not task.dead then
                    paintTitle(task)
                    task.frame.setVisible(true)
                    task.frame.setVisible(false)
                end
            end
            paintTaskbar()
            if menu then paintMenu() end
        end
        if modal then
            modal.frame.setVisible(true)
            modal.frame.setVisible(false)
        end
        composing, dirty = false, false
        placeCursor()
    end

    -- Taps and keys ---------------------------------------------------------------------------

    local function windowAt(x, y)
        if y > TOP then return nil end
        for index = #tasks, 1, -1 do
            local task = tasks[index]
            if task.kind == "app" and not task.minimized and not task.dead
                and x >= task.x and x < task.x + task.w then
                return task
            end
        end
        return home
    end

    local function background(run)
        desk.spawn(function() run(desk) end)
    end

    local function onTaskbar(x)
        if x <= 7 then
            menu = not menu and {} or nil
            dirty = true
            return
        end
        for _, item in ipairs(taskbarItems()) do
            if x >= item.x and x < item.x + item.w then
                if item.task == focused and not item.label then
                    item.task.minimized = true
                    focus(topWindow())
                else
                    focus(item.task)
                end
                return
            end
        end
        if spec.music and x >= MUSIC_X and x <= MUSIC_X + 16 then
            local part = x >= MUSIC_X + 14 and "next" or x >= MUSIC_X + 11 and "play" or "open"
            background(function(d) spec.music.tap(part, d) end)
        end
    end

    local function onMenu(x, y)
        local shown = menu
        menu = nil
        dirty = true
        if not shown or not shown.items or x > shown.width or y < shown.top or y >= H then return end
        local item = shown.items[y - shown.top + 1]
        if item and spec.choose then background(function(d) spec.choose(item.id, d) end) end
    end

    local function toggleMax(task)
        if task.maximized then
            task.maximized, task.x, task.w = false, task.saved.x, task.saved.w
        else
            task.saved = { x = task.x, w = task.w }
            task.maximized, task.x, task.w = true, 1, W
        end
        geometry(task)
        deliver(task, { "term_resize", n = 1 })
    end

    local function onTitle(task, x)
        for _, button in ipairs(buttonsOf(task)) do
            if x >= button[2] and x <= button[2] + 2 then
                if button[1] == "close" then
                    -- Closed at once, the way a program is when Ctrl+T ends it:
                    -- the Pocket's apps keep what matters as they go.
                    close(task)
                elseif button[1] == "min" then
                    task.minimized = true
                    focus(topWindow())
                else
                    toggleMax(task)
                end
                return
            end
        end
        if not task.maximized then drag = { task = task, dx = x - 1 } end
    end

    local function onMouse(event)
        local name, x, y = event[1], event[3], event[4]
        if name == "mouse_click" or name == "mouse_scroll" then ui.noteActivity() end
        if modal then return deliver(modal, event) end
        if kiosk then return deliver(kiosk, moved(event, kiosk)) end
        if name == "mouse_drag" or name == "mouse_up" then
            if drag then
                if name == "mouse_drag" then
                    local task = drag.task
                    task.x = math.max(4 - task.w, math.min(W - 3, x - drag.dx))
                    task.frame.reposition(task.x, 1)
                    dirty = true
                else
                    drag = nil
                end
            elseif capture then
                deliver(capture, moved(event, capture))
                if name == "mouse_up" then capture = nil end
            end
            return
        end
        if menu and name == "mouse_click" then return onMenu(x, y) end
        if y == H then
            if name == "mouse_click" then onTaskbar(x) end
            return
        end
        local task = windowAt(x, y)
        if task ~= front() then focus(task.kind == "app" and task or nil) end
        if task.kind == "app" and y == 1 then
            if name == "mouse_click" then onTitle(task, x - task.x + 1) end
            return
        end
        capture = name == "mouse_click" and task or nil
        deliver(task, moved(event, task))
    end

    local function onEvent(event)
        local name = event[1]
        if MOUSE[name] then
            onMouse(event)
        elseif INPUT[name] then
            if name ~= "monitor_touch" then ui.noteActivity() end
            -- Ctrl+T closes the window in front. Never the desktop, the lock
            -- screen or Till Mode: a till's customer cannot leave it that way.
            if name == "terminate" then
                if focused and not kiosk and not modal then close(focused) end
                return
            end
            deliver(front(), event)
        else
            -- Timers, rednet, speakers: everybody's.
            for _, task in ipairs(services) do deliver(task, event) end
            deliver(home, event)
            for _, task in ipairs(tasks) do deliver(task, event) end
            if modal then deliver(modal, event) end
        end
    end

    local function flush()
        while #pending > 0 do
            local task = table.remove(pending, 1)
            if task.focus then
                focus(task.focus)
            else
                start(task)
            end
        end
        for index = #services, 1, -1 do
            if services[index].dead then table.remove(services, index) end
        end
    end

    -- Locking, after spec.lock.seconds with nothing touched. Never in Till Mode.
    local function lockDue()
        local lock = spec.lock
        return lock and lock.run and not modal and not kiosk and lock.seconds
            and ui.idleForMs() >= lock.seconds * 1000
    end

    -- Running ---------------------------------------------------------------------------------

    term.redirect(screen)
    screen.setCursorBlink(false)
    home = newTask("home", function() spec.home(desk) end, { title = "Desktop" })
    focus(nil)
    resume(home)
    for _, run in ipairs(spec.services or {}) do desk.spawn(run) end
    flush()
    compose()
    local clockTimer = os.startTimer(1)
    while not leaving and (not spec.running or spec.running()) do
        local event = table.pack(os.pullEventRaw())
        if event[1] == "timer" and event[2] == clockTimer then
            clockTimer = os.startTimer(1)
            if not kiosk and not modal then
                composing = true
                paintTaskbar()
                composing = false
                placeCursor()
            end
        else
            onEvent(event)
        end
        flush()
        if lockDue() then
            desk.modal(function() spec.lock.run() end)
            flush()
        end
        if dirty then compose() end
    end
    -- Whatever is still open goes with the desktop.
    for _, task in ipairs(tasks) do
        task.dead = true
        if ui.setSidebar then ui.setSidebar(task.body, nil) end
    end
    if ui.setForeground then ui.setForeground(nil) end
    spec.setTarget(screen)
    term.redirect(screen)
    return why
end

return desktop
