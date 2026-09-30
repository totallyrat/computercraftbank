-- The MyID Verifier, FoxyOS 12, drawn by the real lib/ui on a kiosk's
-- screen: a code typed as it is said, and a plain answer -- VALID and whose,
-- or NOT VALID and why.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")

local display = screen.terminal(51, 19)
local steps = {}
local ui, state = screen.install({ display = display, steps = steps, event = "mouse_click" })

local asked = {}
local answers = {
    { valid = true, status = "active", code = "MY-7K2M-9QPA", name = "Kit Wolf",
      confirmed_day = 12 },
    { valid = false, status = "pending", code = "MY-AAAA-BBBB" },
}
screen.push(steps, screen.typed("my-7k2m-9qpa"), function()
    assert(display.has("VALID") and display.has("Kit Wolf")
        and display.has("Confirmed on day 12"), "a confirmed ID, and whose\n" .. display.dump())
    assert(not display.has("NOT VALID"))
    return "again"
end, screen.typed("MYAAAABBBB"), function()
    assert(display.has("NOT VALID") and display.has("not confirmed it yet"),
        "not confirmed yet, said plainly\n" .. display.dump())
    assert(not display.has("Kit Wolf"), "and nobody's name")
    return "done"
end)
ui.myIdVerifier(display, function(code)
    asked[#asked + 1] = code
    return table.remove(answers, 1)
end)
assert(asked[1] == "MY7K2M9QPA", "typed as it is said, dashes and all: " .. tostring(asked[1]))
assert(asked[2] == "MYAAAABBBB")
assert(#state.steps == 0)

-- The Bank not answering is said, and the verifier asks for another code;
-- CANCEL on it leaves.
steps = {}
ui, state = screen.install({ display = display, steps = steps, event = "mouse_click" })
local said
ui.message = function(_, kind, title, body) said = { kind, title, body } end
screen.push(steps, screen.typed("MY7K2M9QPA"), function()
    assert(said and said[2] == "NOT CHECKED" and said[3] == "Bank server timed out",
        "the Bank not answering is said")
    return "cancel"
end)
ui.myIdVerifier(display, function() return nil, "Bank server timed out" end)
assert(#state.steps == 0)

print("host_myid_screens_test: OK")
