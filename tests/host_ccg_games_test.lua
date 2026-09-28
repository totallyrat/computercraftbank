-- The CCG's Game Browser, 12.0 Final: games fetched from the App Server and
-- played in Home Mode, each in a box of its own.
--
-- The Game Browser lists the App Server's games, and only games; a fetched
-- game is checked, tried and kept, and then it is on the console's menu
-- beside the four built in. A game is somebody else's code running on
-- somebody's console, so it is handed maths, strings, tables, colours and a
-- board, and nothing else: it cannot reach the disk or the network, it
-- cannot paint off its board, and a game that fails ends its round rather
-- than the console.

package.path = "../?.lua;../?/init.lua;" .. package.path

local WIDTH, HEIGHT = 29, 19
colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
local monitor = { getSize = function() return WIDTH, HEIGHT end,
    setTextScale = function() end, isColor = function() return true end }
term = { current = function() return monitor end }
peripheral = { getNames = function() return { "top" } end,
    getType = function() return "monitor" end, wrap = function() return monitor end }

local files = {}
local function canonical(path)
    path = tostring(path or ""):gsub("/+", "/"):gsub("/$", "")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end
fs = {
    getDir = function(path) return (canonical(path):match("^(.*)/[^/]*$") or "") end,
    combine = function(left, right)
        return canonical(tostring(left) .. "/" .. tostring(right))
    end,
    exists = function(path)
        path = canonical(path)
        if files[path] then return true end
        for name in pairs(files) do
            if name:sub(1, #path + 1) == path .. "/" then return true end
        end
        return false
    end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function(path) files[canonical(path)] = nil end,
    open = function(path, mode)
        path = canonical(path)
        if mode:find("r") then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end, close = function() end }
        end
        local parts = {}
        return { write = function(value) parts[#parts + 1] = tostring(value) end,
            close = function() files[path] = table.concat(parts) end }
    end,
}
shell = { getRunningProgram = function() return "/pumpe/ccg.lua" end }
sleep = function() end
os.day = function() return 3 end
os.time = function() return 12 end
os.epoch = function() return 1000 end
os.queueEvent = function() end
os.getComputerID = function() return 5 end
rednet = { host = function() end, unhost = function() end }

local util = dofile("../lib/util.lua")
local shelf
util.loadTable = function(path, fallback)
    if tostring(path):find("ccg_games", 1, true) and shelf then return shelf end
    return util.copy(fallback)
end
util.saveTable = function(path, value)
    if tostring(path):find("ccg_games", 1, true) then shelf = util.copy(value) end
end
package.loaded["lib.util"] = util
package.loaded.config = { version = "12.0.0", currency = "$", app_chunk_size = 700 }

-- An App Server with a few games in it, and one app.
local function readFile(path)
    local handle = assert(io.open(path, "r"))
    local body = handle:read("a")
    handle:close()
    return body
end
local catalogue = {}
local function offer(id, name, kind, body)
    catalogue[#catalogue + 1] = { app_id = id, name = name, kind = kind, body = body,
        description = name .. " for testing", author = "Tester", version = 1,
        size = #body, checksum = util.checksum(body) }
end
offer("BRICKS", "Brick Breaker", "game", readFile("../brickbreaker.lua"))
offer("NOTES", "Notes", "app", "return function(api) end\n")
offer("SNOOP", "Snoop", "game", "fs.delete('/pumpe/ccg.lua')\n"
    .. "return { new = function() return {} end, draw = function() end }\n")
offer("RADIO", "Radio", "game", "return { new = function() rednet.broadcast('hi')"
    .. " return {} end, draw = function() end }\n")
offer("CRASH", "Crash", "game", "return { new = function() return { score = 3 } end,"
    .. " tick = function(state) error('the floor gave way') end,"
    .. " draw = function(state, screen) screen.fill(1, 1, 2, 2, colors.red) end }\n")
offer("WILD", "Wild", "game", "return { new = function() return { score = 0 } end,"
    .. " draw = function(state, screen)"
    .. " screen.fill(-50, -50, 999, 999, colors.blue)"
    .. " screen.text(screen.width - 2, screen.height, 'LONG TEXT OFF THE EDGE')"
    .. " screen.fill(1, 1, 1, 1, 'not a colour') end }\n")
-- One the App Server says one thing about and sends another.
offer("BENT", "Bent", "game", "return { new = function() return {} end, draw = function() end }\n")
catalogue[#catalogue].checksum = "not what arrives"
-- A game whose state and errors are traps: reading them runs its code.
offer("TRAP", "Trap", "game", "local trap = { __index = function() error('gotcha') end,"
    .. " __tostring = function() error('gotcha') end }\n"
    .. "return { new = function() return setmetatable({ score = {}, status = {} }, trap) end,"
    .. " tick = function(state) error(setmetatable({}, trap)) end,"
    .. " draw = function() end }\n")
offer("MEDDLE", "Meddle", "game", "string.rep = nil math.random = nil\n"
    .. "return { new = function() return { score = 0 } end, draw = function() end }\n")
local oldServer, storeCalls = false, {}
local store = {}
function store:request(action, payload)
    storeCalls[#storeCalls + 1] = action
    local function public(app)
        return { app_id = app.app_id, name = app.name, kind = not oldServer and app.kind or nil,
            description = app.description, author = app.author, version = app.version,
            size = app.size, checksum = app.checksum }
    end
    if action == "APP_LIST" then
        local list = {}
        for _, app in ipairs(catalogue) do
            if oldServer or app.kind == (payload.kind or "app") then
                list[#list + 1] = public(app)
            end
        end
        return { apps = list }
    end
    for _, app in ipairs(catalogue) do
        if app.app_id == payload.app_id then
            if action == "APP_INFO" then return { app = public(app) } end
            if action == "APP_CHUNK" then
                local data = app.body:sub(payload.offset + 1, payload.offset + payload.limit)
                return { data = data, next_offset = payload.offset + #data }
            end
        end
    end
    return nil, "That app is not here", "NOT_FOUND"
end
package.loaded["lib.net"] = {
    client = function(spec)
        if spec.protocol == "PUMPE_APPS_V1" then return store end
        return { discover = function() return nil end }
    end,
    autoUpdate = function() end, openModems = function() end,
}

-- Every paint bounds checked against the monitor.
local drawn = {}
local function inside(label, x, y, width, height)
    assert(x >= 1 and y >= 1 and x + width - 1 <= WIDTH and y + height - 1 <= HEIGHT,
        label .. " leaves the monitor at " .. x .. "," .. y .. " size "
            .. width .. "x" .. height)
end
local ui = { theme = { accent = colors.orange } }
function ui.usePhoneStyle() end
function ui.useMainColor() return "orange" end
function ui.clear() drawn = {} end
function ui.fill(_, x, y, width, height, color)
    inside("fill", x, y, width, height)
    assert(type(color) == "number", "a fill with no colour")
end
function ui.text(_, x, y, value)
    value = tostring(value)
    inside("text " .. value, x, y, math.max(1, #value), 1)
    drawn[#drawn + 1] = value
end
function ui.center(_, y, value)
    assert(#tostring(value) <= WIDTH, "centred text too wide: " .. tostring(value))
    drawn[#drawn + 1] = tostring(value)
end
function ui.truncate(value, maximum) return tostring(value or ""):sub(1, math.max(0, maximum)) end
function ui.inkOn() return colors.black end
function ui.wordmark() return false end
function ui.message() end
package.loaded["lib.ui"] = ui

PUMPE_TEST_MODE = "ccg_home"
local console = assert(loadfile("../ccg.lua"))()
PUMPE_TEST_MODE = nil
files["/pumpe/ccg.lua"] = "the console's own program"

local home = { screen = "pair", active = true }
console.new_code(home)
local token = console.handle(home, "HOME_PAIR", { code = home.code, name = "Kit" }, 4).token
local function ask(action, payload)
    payload = payload or {}
    payload.token = token
    return console.handle(home, action, payload, 4)
end
local function refused(code, action, payload)
    local ok, err = pcall(ask, action, payload)
    assert(not ok and type(err) == "table" and err.code == code,
        action .. ": expected " .. code .. ", got " .. tostring(ok and "success"
            or (type(err) == "table" and err.code or err)))
    return err
end
local function onMenu(id)
    for _, game in ipairs(ask("HOME_STATE").games) do
        if game.id == id then return game end
    end
end

-- The Game Browser lists games, and only games ------------------------------------------

local listed = ask("HOME_BROWSE")
local names = {}
for _, game in ipairs(listed.games) do names[game.app_id] = game end
assert(names.BRICKS and names.CRASH and not names.NOTES,
    "the Game Browser lists the App Server's games and none of its apps")
assert(not names.BRICKS.here, "nothing is on the console yet")
-- An App Server from before 12.0 Final says nothing of kinds: none of what it
-- lists is a game.
oldServer = true
assert(#ask("HOME_BROWSE").games == 0, "an old App Server's apps are not games")
oldServer = false

-- Fetching one -------------------------------------------------------------------------

refused("NOT_A_GAME", "HOME_GET", { app_id = "NOTES" })
ask("HOME_GET", { app_id = "BRICKS" })
assert(files["/pumpe/games/BRICKS.lua"] == readFile("../brickbreaker.lua"),
    "the game is kept on the console, whole")
assert(shelf and shelf.list[1].app_id == "BRICKS" and shelf.list[1].version == 1,
    "and listed as fetched")
local bricks = onMenu("BRICKS")
assert(bricks and bricks.label == "BRICK BREAKER" and bricks.fetched,
    "it is on the menu beside the four")
assert(names.BRICKS and ask("HOME_BROWSE").games[1].here, "the browser says it is here")

-- And played, with the phone as the controller.
local state = ask("HOME_PLAY", { game = "BRICKS" })
assert(state.screen == "game" and state.label == "BRICK BREAKER")
ask("HOME_INPUT", { key = "left" })
ask("HOME_INPUT", { key = "a" })
for _ = 1, 400 do
    console.tick(home)
    if home.screen ~= "game" then break end
end
console.draw(home)
assert(home.play.score >= 0 and type(home.play.status) ~= "table")
-- Played until the balls run out, and the score kept like any other.
for _ = 1, 5000 do
    if home.screen ~= "game" then break end
    -- Each new ball waits on the paddle for A.
    if home.play.inner.held then ask("HOME_INPUT", { key = "a" }) end
    console.tick(home)
end
assert(home.screen == "over", "a round of Brick Breaker ends")
console.draw(home)

-- A game in a box ---------------------------------------------------------------------

local snoop = refused("BROKEN", "HOME_GET", { app_id = "SNOOP" })
assert(tostring(snoop.message):find("fs", 1, true), "reaching for the disk is refused: "
    .. tostring(snoop.message))
assert(files["/pumpe/ccg.lua"], "and the console's own file is untouched")
assert(not files["/pumpe/games/SNOOP.lua"] and not onMenu("SNOOP"), "and nothing is kept")
-- What arrives is checked against what the App Server said it was.
refused("DAMAGED", "HOME_GET", { app_id = "BENT" })
assert(not files["/pumpe/games/BENT.lua"] and not onMenu("BENT"), "a damaged download is not kept")
-- The network is not in the box either: that one gets as far as starting.
ask("HOME_GET", { app_id = "RADIO" })
state = ask("HOME_PLAY", { game = "RADIO" })
assert(state.screen == "over" and tostring(state.status):find("did not start", 1, true),
    "a game that reaches for rednet does not start: " .. tostring(state.status))
-- A game that fails mid-round ends its round, with why.
ask("HOME_MENU")
ask("HOME_GET", { app_id = "CRASH" })
ask("HOME_PLAY", { game = "CRASH" })
console.draw(home)
console.tick(home)
state = ask("HOME_STATE")
assert(state.screen == "over" and tostring(state.status):find("the floor gave way", 1, true),
    "the round ends and says why: " .. tostring(state.status))
assert(state.best == 3, "what it scored still counts")
-- A game that paints wildly paints its board, and nothing else.
ask("HOME_MENU")
ask("HOME_GET", { app_id = "WILD" })
ask("HOME_PLAY", { game = "WILD" })
console.draw(home)
assert(home.screen == "game", "painting off the board is clipped, not fatal")
-- A game whose state is a trap: the console reads plain copies, so none of
-- it runs outside the box, and it cannot take the console down.
ask("HOME_MENU")
ask("HOME_GET", { app_id = "TRAP" })
state = ask("HOME_PLAY", { game = "TRAP" })
assert(state.screen == "game" and state.score == 0 and state.status == nil,
    "a score or a status that is not one is not read")
console.draw(home)
console.tick(home)
console.draw(home)
state = ask("HOME_STATE")
assert(state.screen == "over" and state.status == "The game stopped: ?",
    "an error that is a trap ends the round without being read: " .. tostring(state.status))
-- A game that tampers with what it was handed changes its own copies.
ask("HOME_MENU")
ask("HOME_GET", { app_id = "MEDDLE" })
assert(type(string.rep) == "function" and type(math.random) == "function",
    "a game changes its own copies of the libraries, never the console's")

-- Removing, and room --------------------------------------------------------------------

ask("HOME_REMOVE", { app_id = "WILD" })
assert(not files["/pumpe/games/WILD.lua"] and not onMenu("WILD"), "removed, file and all")
refused("NOT_HERE", "HOME_REMOVE", { app_id = "WILD" })
-- Bet Play is not here at all: the browser is Home Mode's.
local bet = io.open("../ccg.lua"):read("a")
assert(not bet:match("local function gameMenu%(%)(.-)\nend\n"):find("HOME_BROWSE", 1, true),
    "the Game Browser is only in Home Mode")

print("host_ccg_games_test: OK")
