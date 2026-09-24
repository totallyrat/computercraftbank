-- A PUMPE app, run the way the phone runs it, against a real Bank.
--
-- The app gets the same api table the phone hands every installed app, with
-- its Bank calls going to the real Core as whoever is holding the phone.
-- The screen is a stub that bounds checks every draw, runs the real tab bar,
-- and only lets a scripted tap land on something that is actually there.
--
-- A script is four queues -- actions (taps), inputs (text boxes), pins and
-- confirms. An entry can be a function, which runs at that moment (another
-- player doing something, say) and returns the answer.

local phone = {}

local realUi = dofile("../lib/ui.lua")

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

function phone.script()
    return { actions = {}, inputs = {}, pins = {}, confirms = {} }
end

function phone.push(queue, ...)
    for _, entry in ipairs({ ... }) do queue[#queue + 1] = entry end
end

-- options: bank, who (a harness account), file, script, wanted (an app
-- action), width, height, kept (the app's saved table), position, app_id.
function phone.run(options)
    local bank, who, script = options.bank, options.who, options.script
    local WIDTH, HEIGHT = options.width or 26, options.height or 20
    local util = require("lib.util")
    local seen = { frames = {}, messages = {}, inputs = {}, requests = {} }
    local frame = {}
    local surface = { getSize = function() return WIDTH, HEIGHT end }
    local function take(queue, what)
        local entry = table.remove(queue, 1)
        assert(entry ~= nil, "the app asked for an unexpected " .. what)
        if type(entry) == "function" then entry = entry(seen) end
        return entry
    end
    local function box(label, x, y, width, height)
        assert(x >= 1 and y >= 1, label .. " starts outside the screen")
        assert(x + width - 1 <= WIDTH, label .. " is wider than the screen")
        assert(y + height - 1 <= HEIGHT, label .. " is below the screen")
    end
    local function draw(value) frame[#frame + 1] = tostring(value) end

    local ui = { theme = realUi.theme, wrap = realUi.wrap }
    ui.tabBar = realUi.tabBar
    function ui.clear()
        frame = {}
        seen.frames[#seen.frames + 1] = frame
    end
    function ui.fill(_, x, y, width, height) box("fill", x, y, width, height) end
    function ui.card(_, x, y, width, height) box("card", x, y, width, height) end
    function ui.truncate(value, maximum)
        return tostring(value or ""):sub(1, math.max(0, maximum))
    end
    function ui.header(_, title, subtitle)
        assert(#tostring(title) <= WIDTH - 3, "title clipped: " .. tostring(title))
        assert(#tostring(subtitle or "") <= WIDTH - 3,
            "subtitle clipped: " .. tostring(subtitle))
        draw(title)
        draw(subtitle or "")
    end
    function ui.text(_, x, y, value)
        box("text " .. tostring(value), x, y, math.max(1, #tostring(value)), 1)
        draw(value)
    end
    function ui.center(_, y, value)
        assert(y >= 1 and y <= HEIGHT and #tostring(value) <= WIDTH,
            "centred text off the screen: " .. tostring(value))
        draw(value)
    end
    function ui.wrappedText(_, x, y, value, width, lines)
        box("wrapped text", x, y, width, lines)
        draw(value)
    end
    function ui.message(_, kind, title, body)
        seen.messages[#seen.messages + 1] = { kind = kind, title = title,
            body = body }
    end
    function ui.input(_, title, spec)
        draw("input:" .. title)
        seen.inputs[#seen.inputs + 1] = { title = title,
            mode = spec and spec.mode, initial = spec and spec.initial }
        return take(script.inputs, "text box: " .. title)
    end
    function ui.pin(_, title)
        draw("pin:" .. title)
        return take(script.pins, "PIN pad: " .. title)
    end
    function ui.confirm(_, title, body, yes, no)
        draw("confirm:" .. title .. " " .. tostring(body))
        local buttonWidth = math.max(8, math.floor((WIDTH - 6) / 2))
        assert(#(yes or "YES") <= buttonWidth - 2
            and #(no or "NO") <= buttonWidth - 2, "confirm label clipped")
        return take(script.confirms, "confirmation: " .. title)
    end
    function ui.scene()
        local scene, tappable = {}, {}
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
            assert(action ~= "__tick" or (spec and spec.tickRate),
                "a tick reached a screen that never asked to refresh")
            assert(action:sub(1, 2) == "__" or tappable[action],
                "tapped " .. action .. ", which is not on the screen")
            return action
        end
        return scene
    end

    local appId = options.app_id or "TESTAPP"
    options.kept = options.kept or {}
    local api = {
        ui = ui, util = util, target = surface, colors = colors,
        money = function(value) return util.money(value, "$") end,
        request = function(action, payload)
            seen.requests[#seen.requests + 1] = action
            local scoped = {}
            for key, value in pairs(payload or {}) do scoped[key] = value end
            scoped.app_id, scoped.session_token = appId, who.token
            local ok, result = pcall(bank.request, action, scoped)
            if ok then return result end
            if type(result) == "table" and result.pumpe then
                return nil, result.message, result.code
            end
            error(result, 0)
        end,
        account = function() return bank.state.accounts[who.id] end,
        refresh = function() end,
        running = function() return true end,
        position = function() return options.position end,
        save = function(value) options.kept.value = util.copy(value) return true end,
        load = function() return util.copy(options.kept.value or {}) end,
        action = function() return options.wanted end,
        -- A bank app's own 3rd Party Bank Server, when the test has one.
        bank = options.bank_app,
        banks = function() return {} end,
        app_id = appId,
    }
    assert(loadfile(options.file))()(api)
    for name, queue in pairs(script) do
        assert(#queue == 0, #queue .. " scripted " .. name .. " never used")
    end
    return seen
end

-- Helpers for reading what was drawn and said.
function phone.has(frame, wanted)
    for _, value in ipairs(frame or {}) do
        if tostring(value):find(wanted, 1, true) then return true end
    end
    return false
end

function phone.last(seen) return seen.frames[#seen.frames] end

function phone.said(seen, title)
    for _, message in ipairs(seen.messages) do
        if message.title == title then return message end
    end
    return nil
end

return phone
