-- Interactive Notifications, FoxyOS 16, drawn and tapped by the real lib/ui.
--
-- A banner sits at the top of the screen over whatever is open -- here the
-- box an app asks for its VerCode in -- and stays drawn over it as that
-- screen redraws. Its own buttons answer taps on them; the screen under it
-- answers everything else. Paste puts the code in the box that is open. A
-- paste is for a minute: an old one does not fill the next box that opens.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")
local clock = 1000000
os.epoch = function() return clock end

local width, height = 26, 20
local display = screen.terminal(width, height)
local steps = {}
local ui, state = screen.install({ display = display, steps = steps, event = "mouse_click" })

local tapped = {}
local layout
local function raise()
    local function draw(where, drop)
        return ui.topBanner(where, {
            title = "Foxy  482019", body = "Yap! code", color = ui.theme.accent,
            buttons = { { id = "paste", label = "Paste", color = ui.theme.success },
                { id = "close", label = "Close", color = ui.theme.panel } },
        }, drop)
    end
    layout = draw(display, 1)
    ui.setOverlay({ target = display, top = layout.top, bottom = layout.bottom,
        buttons = layout.buttons, draw = function(where) draw(where, 1) end,
        tap = function(id)
            tapped[#tapped + 1] = id
            if id == "paste" then ui.paste("482019") end
            ui.setOverlay(nil)
        end })
end
local function buttonAt(id)
    for _, button in ipairs(layout.buttons) do
        if button.id == id then return button.x1, button.y1 end
    end
end

-- The banner, over the code box ----------------------------------------------------------

raise()
local pasteX, pasteY = buttonAt("paste")
assert(layout.top == 1 and layout.bottom == 5, "five rows at the top")
assert(pasteY == 4 and pasteX >= 3, "its buttons on its fourth row")
screen.push(steps, function()
    -- The box is drawn, and the banner over it.
    -- The box under it (the keypad), and what is typed, below the banner.
    assert(display.has("DONE"), "the box the app opened")
    assert(display.has("Foxy  482019") and display.has("Paste"),
        "and the banner, drawn over it:\n" .. display.dump())
    -- A tap on the banner, but not on a button: nothing happens.
    return { raw = { "mouse_click", 1, width - 2, 2 } }
end, function()
    assert(#tapped == 0, "the banner's words are not a button")
    assert(display.has("Foxy  482019"), "and it is still there")
    return { raw = { "mouse_click", 1, pasteX, pasteY } }
end, function()
    assert(tapped[1] == "paste", "Paste is the banner's to answer")
    assert(not ui.overlay(), "and the banner goes")
    assert(display.has("482019"), "the code is in the box now:\n" .. display.dump())
    return { key = keys.enter }
end)
local typed = ui.input(display, "Your code", { mode = "integer", maxLength = 6,
    hint = "From Foxy in Messages" })
assert(typed == "482019", "Paste, then OK: " .. tostring(typed))

-- The screen under the banner still works ---------------------------------------------------

raise()
screen.push(steps, screen.typed("7"))
typed = ui.input(display, "Something else", { mode = "integer", maxLength = 6,
    hint = "From Foxy in Messages" })
assert(typed == "7", "typing below the banner reaches the box under it")
assert(ui.overlay(), "and the banner stays until it is answered")
ui.setOverlay(nil)

-- A paste is for a minute -------------------------------------------------------------------

ui.paste("111111")
clock = clock + 61000
screen.push(steps, screen.typed("5"))
typed = ui.input(display, "Your code", { mode = "integer", maxLength = 6,
    hint = "From Foxy in Messages" })
assert(typed == "5", "a paste from over a minute ago fills nothing: " .. tostring(typed))
-- And a paste is used once.
ui.paste("222222")
screen.push(steps, { key = keys.enter })
assert(ui.input(display, "Your code", { mode = "integer", maxLength = 6,
    hint = "From Foxy in Messages" }) == "222222")
screen.push(steps, screen.typed("9"))
assert(ui.input(display, "Your code", { mode = "integer", maxLength = 6,
    hint = "From Foxy in Messages" }) == "9",
    "the second box does not get the same paste")
assert(#state.steps == 0)

print("host_overlay_test: OK")
