local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "7.0.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local sessionToken
local organizer
local running = true
local deviceFile = fs.combine(ROOT, "event_kiosk_device.dat")
local device = util.loadTable(deviceFile, { last_name = "" })

local function money(value)
    return util.money(value, config.currency)
end

local function request(action, payload, silent)
    payload = payload or {}
    if sessionToken and not payload.session_token then
        payload.session_token = sessionToken
    end
    local result, err, code = client:request(action, payload)
    if not result and not silent then ui.networkError(target, err) end
    if code == "SESSION_EXPIRED" then sessionToken, organizer = nil, nil end
    return result, err, code
end

local function login()
    local name = ui.input(target, "ORGANIZER LOGIN", {
        hint = "Your PUMPE account name",
        initial = device.last_name,
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "ACCOUNT PIN", true)
    if not pin then return false end
    local result, err = client:request("LOGIN", { name = name, pin = pin })
    if not result then
        ui.message(target, "error", "LOGIN FAILED", err, 1.1)
        return false
    end
    sessionToken = result.session_token
    organizer = result.account
    device.last_name = organizer.name
    util.saveTable(deviceFile, device)
    ui.message(target, "success", "WELCOME", organizer.name, 0.8)
    return true
end

local function loginScreen()
    local width, height = target.getSize()
    while running and not sessionToken do
        ui.clear(target)
        ui.header(target, "PUMPE EVENTS", "Organizer terminal", util.formatClock())
        ui.center(target, 6, "CREATE. SELL. ADMIT.", ui.theme.accent)
        ui.center(target, 8, "One terminal for the whole venue", ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("login", 4, 11, width - 7, 3, "ORGANIZER SIGN IN",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "login" then login()
        elseif action == "exit" or action == "__terminate" then running = false end
    end
end

local function addTicketType(event)
    local name = ui.input(target, "TICKET TYPE", {
        hint = "Example: VIP Backstage",
        maxLength = 28,
        allowSpace = true,
    })
    if not name then return false end
    local description = ui.input(target, "TICKET DESCRIPTION", {
        hint = "Perks or access included",
        maxLength = 60,
        allowSpace = true,
    })
    if not description then return false end
    local price = ui.input(target, "TICKET PRICE", {
        hint = name,
        mode = "number", maxLength = 12,
    })
    if not price then return false end
    local quantity = ui.input(target, "TICKET QUANTITY", {
        hint = "Maximum inventory",
        mode = "number", maxLength = 8,
    })
    if not quantity then return false end
    local result, err = request("ADD_TICKET_TYPE", {
        event_id = event.event_id,
        name = name,
        description = description,
        price = tonumber(price),
        quantity = tonumber(quantity),
    }, true)
    if result then
        ui.message(target, "success", "TICKET TYPE ADDED",
            name .. "  " .. money(price), 0.9)
        return true
    end
    ui.message(target, "error", "COULD NOT ADD", err, 1.1)
    return false
end

local function createEvent()
    local title = ui.input(target, "CREATE EVENT", {
        hint = "Public event title",
        maxLength = 40,
        allowSpace = true,
    })
    if not title then return end
    local description = ui.input(target, "DESCRIPTION", {
        hint = "What should guests know?",
        maxLength = 100,
        allowSpace = true,
    })
    if not description then return end
    local location = ui.input(target, "LOCATION", {
        hint = "Venue or coordinates",
        maxLength = 50,
        allowSpace = true,
    })
    if not location then return end
    local dayText = ui.input(target, "EVENT DAY", {
        hint = "Today is in-game day " .. util.ingameDay(),
        mode = "number", maxLength = 8,
    })
    if not dayText then return end
    local timeText = ui.input(target, "EVENT TIME", {
        hint = "Four digits, example 1830",
        mode = "number", maxLength = 5,
    })
    if not timeText then return end
    if not timeText:match("^%d%d?:%d%d$") then
        local raw = timeText:gsub("[^%d]", "")
        if #raw == 4 then timeText = raw:sub(1, 2) .. ":" .. raw:sub(3, 4) end
    end

    local countdown = util.eventCountdown(tonumber(dayText), timeText)
    if not ui.confirm(target, "CREATE EVENT",
        title .. " - in " .. countdown, "CREATE", "BACK") then return end
    local result, err = request("CREATE_EVENT", {
        title = title,
        description = description,
        location = location,
        event_day = tonumber(dayText),
        event_time = timeText,
    }, true)
    if not result then
        ui.message(target, "error", "CREATE FAILED", err, 1.2)
        return
    end
    ui.message(target, "success", "EVENT CREATED", result.event.title, 0.9)
    while ui.confirm(target, "ADD TICKET TYPE",
        "Set up another ticket category?", "ADD", "DONE") do
        addTicketType(result.event)
    end
end

local function analyticsScreen(event)
    local blink = true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        local countdown = util.eventCountdown(event.event_day, event.event_time)
        ui.header(target, ui.truncate(event.title, width - 9),
            "Starts in " .. countdown, util.formatClock(blink))
        local sold, capacity, revenue = 0, 0, 0
        for _, ticketType in ipairs(event.ticket_types or {}) do
            sold = sold + ticketType.sold_quantity
            capacity = capacity + ticketType.total_quantity
            revenue = revenue + ticketType.sold_quantity * ticketType.price
        end
        ui.card(target, 2, 5, width - 2, 3, ui.theme.success)
        ui.text(target, 4, 5, sold .. "/" .. capacity .. " SOLD",
            ui.theme.ink, ui.theme.panel)
        ui.text(target, width - #money(revenue), 5, money(revenue),
            ui.theme.success, ui.theme.panel)
        ui.progress(target, 4, 7, width - 6, sold, math.max(1, capacity),
            ui.theme.success, colors.gray)

        local scene = ui.scene(target)
        local visible = math.max(1, height - 12)
        for index = 1, math.min(#(event.ticket_types or {}), visible) do
            local ticketType = event.ticket_types[index]
            local y = 9 + index - 1
            local percentage = ticketType.total_quantity > 0
                and math.floor(ticketType.sold_quantity / ticketType.total_quantity * 100)
                or 0
            local soldOut = ticketType.sold_quantity >= ticketType.total_quantity
            ui.text(target, 2, y, ui.truncate(ticketType.name, width - 22),
                soldOut and ui.theme.danger or ui.theme.ink)
            local detail = string.format("%d/%d  %d%%",
                ticketType.sold_quantity, ticketType.total_quantity, percentage)
            ui.text(target, width - #detail, y, detail,
                soldOut and ui.theme.danger or ui.theme.muted)
        end
        scene:button("add", 9, height, 14, 1, "+ TICKET TYPE",
            { background = ui.theme.accentDark })
        scene:button("back", 1, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "add" then
            if addTicketType(event) then
                local refreshed = request("MY_EVENTS", {}, true)
                if refreshed then
                    for _, candidate in ipairs(refreshed.events) do
                        if candidate.event_id == event.event_id then
                            event = candidate
                            break
                        end
                    end
                end
            end
        end
    end
end

local function myEvents()
    local result = request("MY_EVENTS")
    if not result then return end
    local events, page, blink = result.events, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "MY EVENTS", #events .. " total", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(events, page, 4)
        page = actualPage
        local scene = ui.scene(target)
        if #events == 0 then ui.center(target, 9, "No events yet", ui.theme.muted) end
        for index, event in ipairs(pageItems) do
            local y = 4 + (index - 1) * 3
            local countdown = util.eventCountdown(event.event_day, event.event_time)
            scene:button("event:" .. event.event_id, 2, y, width - 2, 2,
                ui.truncate(event.title, width - 8) .. "\nIN "
                    .. string.upper(countdown), {
                    background = event.status == "active" and ui.theme.panel or colors.gray,
                })
        end
        scene:button("back", 1, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", width - 11, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            ui.text(target, width - 6, height, page .. "/" .. pages, ui.theme.muted)
            scene:button("next", width - 2, height, 2, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^event:(.+)$")
            if id then
                for _, event in ipairs(events) do
                    if event.event_id == id then
                        ui.wipe(target, "SALES ANALYTICS")
                        analyticsScreen(event)
                        result = request("MY_EVENTS", {}, true) or result
                        events = result.events
                        break
                    end
                end
            end
        end
    end
end

local function ticketResultScreen(result)
    local width, height = target.getSize()
    local ticket, event, ticketType = result.ticket, result.event, result.ticket_type
    ui.clear(target)
    ui.header(target, result.valid and "VALID TICKET" or "TICKET BLOCKED",
        ticket.qr_code, util.formatClock())
    local accent = result.valid and ui.theme.success or ui.theme.danger
    ui.card(target, 3, 5, width - 5, 9, accent)
    ui.text(target, 5, 6, ui.truncate(event.title, width - 10),
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 8, ticketType.name, accent, ui.theme.panel)
    ui.text(target, 5, 10, "Holder: " .. result.holder,
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 12, ticket.used
        and ("USED Day " .. tostring(ticket.used_day) .. " " .. tostring(ticket.used_time))
        or "READY TO ADMIT", accent, ui.theme.panel)
    local scene = ui.scene(target)
    if result.valid then
        scene:button("admit", 3, 16, width - 5, 2, "MARK USED + ADMIT",
            { background = ui.theme.success, foreground = colors.black })
    else
        scene:button("back", 3, 16, width - 5, 2,
            ticket.used and "ALREADY USED - BACK" or "INVALID - BACK",
            { background = ui.theme.danger })
    end
    scene:button("cancel", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "admit" then
        local used, err = request("MARK_TICKET_USED", {
            ticket_id = ticket.ticket_id,
        }, true)
        if used then
            ui.message(target, "success", "GUEST ADMITTED",
                result.holder .. " - " .. ticketType.name, 1.2)
        else ui.message(target, "error", "COULD NOT ADMIT", err, 1.1) end
    end
end

local function verifyTicket()
    local code = ui.input(target, "VERIFY TICKET", {
        hint = "Eight-character entry code",
        mode = "code", maxLength = 8, minLength = 8,
    })
    if not code then return end
    local result, err = request("VERIFY_TICKET", { code = code }, true)
    if result then ticketResultScreen(result)
    else ui.message(target, "error", "TICKET REJECTED", err, 1.2) end
end

local function dashboard()
    local blink, tick = true, 0
    local stats = request("EVENT_DASHBOARD")
    while running and sessionToken and stats do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "EVENT DASHBOARD", organizer.name, util.formatClock(blink))
        local cardWidth = math.floor((width - 5) / 3)
        local cards = {
            { "ACTIVE", stats.active_events, ui.theme.accent },
            { "SOLD", stats.tickets_sold, colors.magenta },
            { "REVENUE", money(stats.revenue), ui.theme.success },
        }
        for index, card in ipairs(cards) do
            local x = 2 + (index - 1) * (cardWidth + 1)
            ui.card(target, x, 5, cardWidth, 4, card[3])
            ui.text(target, x + 2, 6, card[1], ui.theme.muted, ui.theme.panel)
            ui.text(target, x + 2, 7, tostring(card[2]), ui.theme.ink, ui.theme.panel,
                cardWidth - 3)
        end
        local scene = ui.scene(target)
        local buttonWidth = math.floor((width - 5) / 2)
        scene:button("create", 2, 11, buttonWidth, 3, "CREATE EVENT",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("events", 3 + buttonWidth, 11, buttonWidth, 3, "MY EVENTS",
            { background = ui.theme.panel, shadow = true })
        scene:button("verify", 2, 15, buttonWidth, 3, "VERIFY TICKET",
            { background = ui.theme.success, foreground = colors.black, shadow = true })
        scene:button("logout", 3 + buttonWidth, 15, buttonWidth, 3, "LOG OUT",
            { background = ui.theme.panel, shadow = true })
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        tick = tick + 1
        blink = not blink
        -- The clock blinks twice a second; the Bank is only asked for fresh
        -- numbers every five seconds, or right after something changed them.
        local refresh = false
        if action == "__tick" then
            net.autoUpdate(config, "event", ROOT, client)
            refresh = tick % 10 == 0
        elseif action == "create" then createEvent() refresh = true
        elseif action == "events" then ui.wipe(target) myEvents() refresh = true
        elseif action == "verify" then verifyTicket() refresh = true
        elseif action == "logout" then
            if ui.confirm(target, "LOG OUT", "End organizer session?", "LOG OUT", "BACK") then
                sessionToken, organizer = nil, nil
            end
        elseif action == "exit" or action == "__terminate" then running = false end
        if refresh and sessionToken then
            stats = request("EVENT_DASHBOARD", {}, true) or stats
        end
    end
end

ui.boot(target, "PUMPE EVENTS", "VENUE CONTROL v" .. config.version)
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "event", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
if not client:discover() then
    ui.message(target, "error", "BANK OFFLINE", "Check the modem", 1.4)
end

while running do
    if not sessionToken then loginScreen() end
    if sessionToken then dashboard() end
end

ui.clear(target)
print("Event Kiosk closed.")
