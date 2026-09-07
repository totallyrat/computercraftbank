-- The App Server: publishing, chunked downloads, ownership, and the one
-- question it asks the Bank. Downloads must never reach the Bank at all --
-- carrying them is the whole reason this machine exists.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

os.day = function() return 400 end
os.time = function() return 12 end
os.epoch = function() return 1000 end
os.getComputerID = function() return 5 end

local files = {}
local function canonical(path)
    path = tostring(path or ""):gsub("/+", "/"):gsub("/$", "")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return canonical(tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", ""))
    end,
    exists = function(path) return files[canonical(path)] ~= nil end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function(path) files[canonical(path)] = nil end,
    open = function(path, mode)
        path = canonical(path)
        if mode and mode:find("r") then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end,
                close = function() end }
        end
        local chunks = {}
        return { write = function(v) chunks[#chunks + 1] = tostring(v) end,
            close = function() files[path] = table.concat(chunks) end }
    end,
}
shell = { getRunningProgram = function() return "/pumpe/app_server.lua" end }
term = { current = function()
    return { getSize = function() return 51, 19 end }
end }
sleep = function() end
peripheral = { getNames = function() return {} end,
    getType = function() return "modem" end }
rednet = { isOpen = function() return true end, open = function() end,
    lookup = function() return 1 end, host = function() end }

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

-- The only thing the App Server ever asks the Bank.
local bankCalls = {}
package.loaded["lib.net"] = {
    client = function()
        return {
            discover = function() return 1 end,
            request = function(_, action, payload)
                bankCalls[#bankCalls + 1] = action
                if action == "DEV_VERIFY" then
                    if payload.developer_token == "GOOD" then
                        return { name = "Shop Owner",
                            account_id = "ACC000004" }
                    end
                    return nil, "That developer is not registered"
                end
                error("the App Server must not ask the Bank for " .. action)
            end,
        }
    end,
    host = function() end,
    autoUpdate = function() end,
    reply = function() end,
}

PUMPE_TEST_MODE = true
local server = assert(loadfile("../app_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = server.actions

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local GOOD = { developer_id = "DEV001", developer_token = "GOOD" }
local BODY = "return function(api) return api end\n"

-- Publishing -----------------------------------------------------------------

assert(#actions.APP_LIST().apps == 0, "a fresh store is empty")

rejected(actions.APP_PUBLISH, "DEV_REQUIRED", { name = "Nope", body = BODY })
rejected(actions.APP_PUBLISH, "DEV_UNKNOWN", {
    developer_id = "DEV001", developer_token = "WRONG",
    name = "Nope", body = BODY,
})
rejected(actions.APP_PUBLISH, "APP_INVALID", {
    developer_id = GOOD.developer_id, developer_token = GOOD.developer_token,
    name = "Broken", body = "this is not lua ===",
})
rejected(actions.APP_PUBLISH, "EMPTY_APP", {
    developer_id = GOOD.developer_id, developer_token = GOOD.developer_token,
    name = "Empty", body = "",
})

local published = actions.APP_PUBLISH({
    developer_id = GOOD.developer_id, developer_token = GOOD.developer_token,
    name = "Notes", description = "Jot things down", body = BODY,
}).app
assert(published.name == "Notes" and published.version == 1)
assert(published.author == "Shop Owner", "the Bank names the author")
assert(published.size == #BODY and published.checksum == util.checksum(BODY))
assert(#actions.APP_LIST().apps == 1)

-- Republishing the same app is an update, not a second copy.
local BODY2 = BODY .. "-- v2\n"
local updated = actions.APP_PUBLISH({
    developer_id = GOOD.developer_id, developer_token = GOOD.developer_token,
    app_id = published.app_id,
    name = "Notes", description = "Jot things down", body = BODY2,
}).app
assert(updated.app_id == published.app_id and updated.version == 2)
assert(#actions.APP_LIST().apps == 1, "still one app in the catalogue")

-- Downloads ------------------------------------------------------------------

local before = #bankCalls
local collected, offset = {}, 0
while offset < updated.size do
    local chunk = actions.APP_CHUNK({
        app_id = updated.app_id, offset = offset, limit = 8,
    })
    assert(#chunk.data > 0, "a chunk must carry something")
    collected[#collected + 1] = chunk.data
    offset = chunk.next_offset
end
assert(table.concat(collected) == BODY2, "the file arrives whole")
assert(#bankCalls == before,
    "downloading must never reach the Bank; that is what this server is for")
assert(actions.APP_INFO({ app_id = updated.app_id }).app.downloads == 1,
    "one download is counted per fetch, not per chunk")

rejected(actions.APP_CHUNK, "NOT_FOUND", { app_id = "NOPE", offset = 0 })

-- Ownership ------------------------------------------------------------------

local OTHER = { developer_id = "DEV002", developer_token = "GOOD" }
-- The Bank vouches for the token, but the app still belongs to whoever
-- published it.
rejected(actions.APP_PUBLISH, "NOT_YOURS", {
    developer_id = OTHER.developer_id, developer_token = OTHER.developer_token,
    app_id = updated.app_id, name = "Stolen", body = BODY,
})
rejected(actions.APP_DELETE, "NOT_YOURS", {
    developer_id = OTHER.developer_id, developer_token = OTHER.developer_token,
    app_id = updated.app_id,
})

assert(actions.APP_DELETE({
    developer_id = GOOD.developer_id, developer_token = GOOD.developer_token,
    app_id = updated.app_id,
}).removed == updated.app_id)
assert(#actions.APP_LIST().apps == 0, "and it leaves the catalogue")
rejected(actions.APP_INFO, "NOT_FOUND", { app_id = updated.app_id })

print("host_app_server_test: OK")
