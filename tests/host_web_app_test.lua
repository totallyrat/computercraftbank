-- Website Crafter and the Internet app, driven through a real PUMPE.
--
-- Behind the phone are the real machines: a Bank Core, its Vault, and an
-- Internet Server. Nothing here is canned, so the run only passes if a
-- website written on a pocket screen actually reaches a stranger's.
--
-- Every draw is bounds checked at 26x20, because that is the screen these
-- two apps have to live on.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local ana = bank.register("Ana Fox", "1234")

local WIDTH, HEIGHT = 26, 20
local drawn, buttonLabels = {}, {}
local actions, actionIndex = {}, 0
local inputs, pins = {}, {}
local savedFiles = {}

-- The Internet Server, loaded for real with its Bank connection wired to the
-- Core the same way the game wires it.
local webServer
do
    local realNet = package.loaded["lib.net"]
    term = { current = function()
        return { getSize = function() return 51, 19 end }
    end }
    package.loaded["lib.ui"] = setmetatable({ theme = {} }, {
        __index = function() return function() end end,
    })
    package.loaded["lib.net"] = {
        openModems = function() return { "modem" } end,
        host = function() end,
        reply = function() end,
        locate = function() return nil end,
        autoUpdate = function() end,
        client = function()
            return {
                discover = function() return 1 end,
                request = function(_, action, payload)
                    local ok, result = pcall(bank.request, action, payload or {})
                    if ok then return result end
                    if type(result) == "table" and result.pumpe then
                        return nil, result.message, result.code
                    end
                    return nil, tostring(result), "SERVER_ERROR"
                end,
            }
        end,
    }
    PUMPE_TEST_MODE = true
    webServer = assert(loadfile("../internet_server.lua"))()
    PUMPE_TEST_MODE = nil
    package.loaded["lib.net"] = realNet
end

-- The phone ------------------------------------------------------------------

term = { current = function()
    return { getSize = function() return WIDTH, HEIGHT end }
end }
-- A filesystem real enough to watch a website arrive on the phone and leave
-- again, which is the behaviour 10.1 is about.
local directories = {}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function(path)
        return savedFiles[path] ~= nil or directories[path] == true
    end,
    isDir = function(path) return directories[path] == true end,
    makeDir = function(path) directories[path] = true end,
    delete = function(path)
        savedFiles[path], directories[path] = nil, nil
        local prefix = tostring(path):gsub("/+$", "") .. "/"
        for existing in pairs(savedFiles) do
            if existing:sub(1, #prefix) == prefix then
                savedFiles[existing] = nil
            end
        end
    end,
    getFreeSpace = function() return 500000 end,
    getSize = function() return 100 end,
}
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }
sleep = function() end
textutils = textutils or {}
textutils.serialize = function(value)
    local function encode(item)
        if type(item) == "table" then
            local parts = {}
            for key, inner in pairs(item) do
                parts[#parts + 1] = "[" .. encode(key) .. "]="
                    .. encode(inner)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        if type(item) == "string" then return string.format("%q", item) end
        return tostring(item)
    end
    return encode(value)
end
textutils.unserialize = function(body)
    local loader = load("return " .. tostring(body))
    local ok, value = pcall(loader)
    return ok and value or nil
end

local util = require("lib.util")
local realWrite, realRead = util.writeFile, util.readFile
util.writeFile = function(path, body) savedFiles[path] = body end
util.readFile = function(path) return savedFiles[path] end
util.loadTable = function(path, fallback)
    if savedFiles[path] then
        local value = textutils.unserialize(savedFiles[path])
        if type(value) == "table" then return value end
    end
    if tostring(path):find("pumpe_apps", 1, true) then
        return { list = {
            { app_id = "WC", name = "Website Crafter", version = 1,
              author = "PUMPE", description = "Write a website" },
            { app_id = "NET", name = "Internet", version = 1,
              author = "PUMPE", description = "Read the web" },
        } }
    end
    if tostring(path):find("device", 1, true) then
        return { last_name = "Ana Fox", onboarding_complete = true,
            modem_on = true, update_mode = "ask" }
    end
    return util.copy(fallback)
end
util.saveTable = function(path, value)
    savedFiles[path] = textutils.serialize(value)
end
package.loaded["lib.util"] = util

local realLoadfile = loadfile
loadfile = function(path)
    path = tostring(path)
    if path:find("/WC.lua", 1, true) then return realLoadfile("../wc.lua") end
    if path:find("/NET.lua", 1, true) then
        return realLoadfile("../internet.lua")
    end
    return realLoadfile(path)
end

package.loaded["lib.net"] = {
    openModems = function() return { "modem" } end,
    closeModems = function() return {} end,
    modemsOpen = function() return true end,
    host = function() end,
    reply = function() end,
    locate = function() return nil end,
    autoUpdate = function() end,
    isNewerVersion = function() return false end,
    client = function(spec)
        local web = (spec.protocol or ""):find("WEB", 1, true) ~= nil
        return {
            discover = function() return 1 end,
            isOnline = function() return true end,
            request = function(_, action, payload)
                local ok, result
                if web then
                    local handler = webServer.actions[action]
                    if not handler then
                        return nil, "Unknown web action", "UNKNOWN_ACTION"
                    end
                    ok, result = pcall(handler, payload or {})
                else
                    ok, result = pcall(bank.request, action, payload or {})
                end
                if ok then return result end
                if type(result) == "table" and result.pumpe then
                    return nil, result.message, result.code
                end
                return nil, tostring(result), "SERVER_ERROR"
            end,
        }
    end,
}

-- A ui that answers from a script and measures every draw.
local function assertBox(label, x, y, width, height)
    assert(x >= 1 and y >= 1, label .. " starts outside the screen")
    assert(width >= 1 and height >= 1, label .. " has an empty size")
    assert(x + width - 1 <= WIDTH, label .. " exceeds screen width")
    assert(y + height - 1 <= HEIGHT, label .. " exceeds screen height")
end

local ui = { theme = setmetatable({}, { __index = function() return 1 end }) }
function ui.clear() end
function ui.fill(_, x, y, width, height) assertBox("fill", x, y, width, height) end
function ui.card(_, x, y, width, height) assertBox("card", x, y, width, height) end
function ui.text(_, x, y, value)
    assert(y >= 1 and y <= HEIGHT, "text outside the screen: " .. tostring(value))
    assert(#tostring(value or "") <= WIDTH - x + 1,
        "text overflows: " .. tostring(value))
    drawn[#drawn + 1] = tostring(value or "")
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text outside the screen")
    assert(#tostring(value or "") <= WIDTH, "centered text is clipped")
    drawn[#drawn + 1] = tostring(value or "")
end
function ui.wrap(value, width)
    local out, line = {}, ""
    for word in tostring(value or ""):gmatch("%S+") do
        if #line + #word + 1 > width and line ~= "" then
            out[#out + 1] = line
            line = word
        else
            line = line == "" and word or (line .. " " .. word)
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end
function ui.wrappedText(_, x, y, value, width, maxLines)
    local out = ui.wrap(value, width)
    assert(#out <= maxLines, "wrapped text loses lines: " .. tostring(value))
    for index, line in ipairs(out) do ui.text(nil, x, y + index - 1, line) end
end
function ui.header(_, title, subtitle)
    assert(#tostring(title or "") <= WIDTH - 3, "header title is clipped")
    assert(not subtitle or #tostring(subtitle) <= WIDTH - 3,
        "header subtitle is clipped: " .. tostring(subtitle))
    drawn[#drawn + 1] = tostring(title or "")
    drawn[#drawn + 1] = tostring(subtitle or "")
end
function ui.truncate(value, width)
    value = tostring(value or "")
    if #value <= width then return value end
    return value:sub(1, math.max(0, width - 1)) .. "."
end
function ui.message(_, _, title, body)
    drawn[#drawn + 1] = tostring(title)
    drawn[#drawn + 1] = tostring(body or "")
    if tostring(title):find("stopped") then
        error("app crashed: " .. tostring(title) .. " -- " .. tostring(body), 0)
    end
end
function ui.confirm() return true end
function ui.input() return table.remove(inputs, 1) end
function ui.pin() return table.remove(pins, 1) end
function ui.wordmark() return true end
function ui.splash() end
function ui.boot() end
function ui.idleForMs() return 0 end
function ui.noteActivity() end
function ui.setIdleLock() end
function ui.setBackgroundTask() end
function ui.usePhoneStyle() end
function ui.progress() end
function ui.badge() end
function ui.pill() end
function ui.spinner() end
function ui.networkError(_, err) error("network error: " .. tostring(err)) end
function ui.scene()
    local scene = { width = WIDTH, height = HEIGHT }
    local live = {}
    function scene:button(id, x, y, width, height, label, options)
        assertBox("button '" .. tostring(label) .. "'", x, y, width, height)
        local lines = ui.wrap(label, math.max(1, width - 2))
        assert(#lines <= height, "button label is clipped: " .. tostring(label))
        buttonLabels[#buttonLabels + 1] = tostring(label or "")
        if not (options and options.disabled) then live[id] = true end
    end
    function scene:hotspot(id, x, y, width, height)
        assertBox("hotspot", x, y, width, height)
        live[id] = true
    end
    function scene:wait()
        while true do
            actionIndex = actionIndex + 1
            local action = actions[actionIndex]
            assert(action, "the phone asked for more actions than the test has")
            -- A day passing, scripted, so the two hours before a site opens
            -- can be waited out inside one run.
            if action == "__day" then
                harness.day = harness.day + 1
            else
                if action ~= "__terminate" then
                    assert(live[action],
                        "tapped '" .. action .. "' but no such button is on"
                            .. " screen")
                end
                return action
            end
        end
    end
    return scene
end
package.loaded["lib.ui"] = ui

-- The website under test. It draws one line, and it reaches for every door
-- a page is not allowed through: the filesystem, the network, and `load`.
-- What it finds is recorded so the test can check the sandbox rather than
-- take its word for it.
PAGE_SOURCE = table.concat({
    "return function(api)",
    "    local ui, target = api.ui, api.target",
    "    ui.text(target, 2, 5, \"A page ran here\")",
    "    ui.text(target, 2, 6, \"fs \" .. type(fs))",
    "    ui.text(target, 2, 7, \"http \" .. type(http))",
    "    ui.text(target, 2, 8, \"rednet \" .. type(rednet))",
    "    ui.text(target, 2, 9, \"shell \" .. type(shell))",
    "    ui.text(target, 2, 10, \"peri \" .. type(peripheral))",
    "    ui.text(target, 2, 11, \"load \" .. type(load))",
    "    ui.text(target, 2, 12, \"pin \" .. type(ui.pin))",
    "    ui.text(target, 2, 13, \"bank \" .. type(api.bank))",
    "    ui.text(target, 2, 14, \"req \" .. type(api.request))",
    "    ui.text(target, 2, 15, \"login \" .. type(api.login))",
    -- 10.2: a page that asks for more than your name gets your name. It
    -- asks here for the balance, which is exactly what 10.1 let through.
    "    local me = api.login({ scopes = { \"balance\", \"friends\" } })",
    "    ui.text(target, 2, 16, \"who \" .. tostring(me and me.name))",
    "    ui.text(target, 2, 17, \"bal \" .. type(me and me.balance))",
    -- And storage, at the Bank, under the domain's own name.
    "    api.data(\"PUT\", { collection = \"guest\",",
    "        data = { note = \"hello\" } })",
    -- Naming somebody else's app is ignored: a page writes as its domain
    -- or not at all. Otherwise a page could read the records of any app
    -- the visitor happens to be signed into.
    "    api.data(\"PUT\", { app_id = \"YAPCHAT\", collection = \"guest\",",
    "        data = { note = \"spoof\" } })",
    "    local listed = api.data(\"LIST\", { collection = \"guest\" })",
    "    ui.text(target, 2, 18, \"kept \" .. tostring(listed",
    "        and listed.total))",
    "end",
}, "\n")

-- Ana already has a site on the web before the phone starts: the probe
-- above, published the way anything is published. The scripted run makes a
-- second one by hand, so the editor and the sandbox are each tested against
-- the thing they are for.
do
    bank.request("WEB_RESERVE", bank.as(ana, { domain = "probe" }))
    local ticket = bank.request("WEB_TOKEN", bank.as(ana, { domain = "probe" }))
    webServer.actions.WEB_PUBLISH({ domain = "probe", token = ticket.token,
        source = PAGE_SOURCE })
    harness.day = harness.day + 1
end

actions = {
    "login",
    "open:ext:WC",                     -- Website Crafter
    "new",                             -- reserve a domain
    "pick:1",                          -- start from a template
    "site:1",                          -- open it
    "edit",                            -- the code
    "add",                             -- one more line
    "back",
    "publish",                         -- and put it on the web
    "back",                            -- out of Website Crafter
    "open:ext:NET",                    -- the Internet app
    "go",                              -- open the one already up
    "yes",                             -- the page asks who you are
    "back",
    "__terminate",
}
inputs = { "Ana Fox", "foxden", "-- one more line", "probe" }
pins = { "1234" }

local ok, err = pcall(assert(realLoadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))
util.writeFile, util.readFile = realWrite, realRead

local function drew(text)
    for _, item in ipairs(drawn) do
        if item:find(text, 1, true) then return true end
    end
    return false
end

-- A sentence on a 26 column screen arrives as several lines, so anything
-- longer than a few words is looked for in what the whole screen said.
local page = table.concat(drawn, " ")
local function read(text)
    return page:find(text, 1, true) ~= nil
end

-- Reserving --------------------------------------------------------------------

assert(read("You're in, Ana Fox"),
    "reserving a domain says so, by name -- it is the moment the app is for")
assert(drew("YOUR DOMAIN") and drew("foxden"),
    "and shows the name on a card")

local mine = bank.request("WEB_MINE", bank.as(ana))
local reserved = {}
for _, site in ipairs(mine.sites) do reserved[site.domain] = true end
assert(reserved.foxden,
    "the domain is reserved at the Bank, not just on the phone")

-- The draft is on the device ------------------------------------------------------
-- The whole point of Website Crafter working without an Internet Server.

local keptOnDevice = false
for path, body in pairs(savedFiles) do
    if path:find("WC.dat", 1, true) and body:find("foxden", 1, true) then
        keptOnDevice = true
    end
end
assert(keptOnDevice,
    "the website is saved on the phone, so it can be written with no"
        .. " Internet Server anywhere on the network")

-- Publishing ----------------------------------------------------------------------

assert(drew("Published"), "publishing says so")
local stored
for _, site in pairs(webServer.state.sites) do
    if site.domain == "foxden" then stored = site end
end
assert(stored, "and the program actually reached the Internet Server")
assert(type(stored.source) == "string"
    and stored.source:find("return function", 1, true),
    "as source, because a website is a program now")
assert(stored.source:find("-- one more line", 1, true),
    "including the line that was typed into the editor")

-- Running a page ---------------------------------------------------------------------

assert(drew("A page ran here"),
    "opening a website runs it: the page drew its own screen")

-- ...and the box it ran in --------------------------------------------------------------
-- The part that matters. A website is code a stranger wrote and you never
-- chose to install, so what it cannot reach is the feature. The page reports
-- by drawing, because it has no other way to reach this test -- which is
-- itself the point.

for _, door in ipairs({ "fs", "http", "rednet", "shell", "peri", "load" }) do
    assert(drew(door .. " nil"),
        "a website could see `" .. door .. "`, which is a website that can"
            .. " reach past the phone it is being read on")
end
assert(drew("pin nil"),
    "ui.pin returns the owner's PIN in the clear, so a page off the internet"
        .. " is not handed the ui library whole")
assert(drew("bank nil") and drew("req nil"),
    "and none of the Bank: a page can be told who you are, never what you"
        .. " have")
assert(drew("login function"),
    "but Foxy Signin is there, which is the one account a page gets")
assert(drew("who Ana Fox"), "and it tells the page who you are")
assert(drew("bal nil"),
    "and not what you have. 10.1 passed a page's own list of scopes through,"
        .. " so a page asking for your balance got it the moment somebody"
        .. " tapped Allow -- while the release notes said it never could")

-- Storage, since 10.2 ---------------------------------------------------------------
-- At the Bank, under the domain's own name, so the phone stays clean.

assert(drew("kept 2"),
    "a signed-in page keeps what it saves, and reads it back")
local stored = bank.request("APP_DATA_LIST", bank.as(ana,
    { app_id = "WEB-probe", collection = "guest" }))
assert(stored.total == 2, "and it is at the Bank, filed under WEB-probe")
local elsewhere = pcall(bank.request, "APP_DATA_LIST", bank.as(ana,
    { app_id = "YAPCHAT", collection = "guest" }))
assert(not elsewhere or bank.request("APP_DATA_LIST", bank.as(ana,
    { app_id = "YAPCHAT", collection = "guest" })).total == 0,
    "and a page that names another app's id still writes as its own domain")

-- ...and that it is gone again ----------------------------------------------------------

for path in pairs(savedFiles) do
    assert(not path:find("/web/", 1, true),
        "the website is still on the phone at " .. path
            .. "; an app lives here, a page is a visit")
end

-- The templates it ships with ------------------------------------------------------------
-- Website Crafter hands people a program to start from. One that does not
-- parse is a broken website handed to somebody who did not write it.

local crafter = assert(io.open("../wc.lua")):read("a")
local block = crafter:match("local TEMPLATES = (%b{})")
assert(block, "Website Crafter must ship templates")
local templates = assert(load("return " .. block))()
assert(#templates >= 2, "including a worked example, not just a blank")
local named = {}
for _, template in ipairs(templates) do
    named[template.id] = true
    local built, err = load(table.concat(template.lines, "\n"), template.id)
    assert(built, "the " .. template.id .. " template does not parse: "
        .. tostring(err))
end
assert(named.foxy, "and one of them is the Foxy page")

print("host_web_app_test: OK")
