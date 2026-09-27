-- The Internet app, 12.0: Go, Saved and Recent along the bottom, and More,
-- which searches both lists. What you visit and save is kept on the phone;
-- until 12.0 it was forgotten every time the app closed.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16,
    lime = 32, pink = 64, gray = 128, lightGray = 256, cyan = 512,
    purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384,
    black = 32768 }
os.epoch = os.epoch or function() return 0 end
local phone = require("phone_app_harness")

local visited = {}
local function browse(domain) visited[#visited + 1] = domain end
local kept = {}

-- A first visit: type an address, then save another site for later.
local script = phone.script()
phone.push(script.actions, "go")
phone.push(script.inputs, "  FoxDen ")
phone.push(script.actions, "tab:saved", "add")
phone.push(script.inputs, "shopland")
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "shopland"), "it is on the Saved tab")
    return "home"
end)
phone.run({ file = "../internet.lua", script = script, kept = kept, browse = browse })
assert(visited[1] == "foxden", "the address is tidied before it is visited")
assert(kept.value.history[1] == "foxden" and kept.value.bookmarks[1] == "shopland",
    "and both lists are kept on the phone")

-- Next time: both are still there, and More finds them.
script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "foxden"), "Go still shows the last visit")
    return "tab:more"
end)
phone.push(script.more, function(seen)
    local spec = seen.more[#seen.more]
    local ids = {}
    for _, entry in ipairs(spec.more) do ids[entry.id] = true end
    assert(ids["visit:foxden"] and ids["visit:shopland"],
        "More searches every saved and visited site")
    return "visit:shopland"
end)
phone.push(script.actions, "tab:saved", "unmark:1", function(seen)
    assert(phone.has(phone.last(seen), "Nothing saved yet"), "an x takes it off")
    return "tab:recent"
end, "clear", "home")
phone.push(script.confirms, true)
phone.run({ file = "../internet.lua", script = script, kept = kept, browse = browse })
assert(visited[2] == "shopland", "More opened the site")
assert(#kept.value.bookmarks == 0 and #kept.value.history == 0,
    "removed from Saved, and what was visited cleared")

print("host_internet_app_test: OK")
