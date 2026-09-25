-- tools/bank_rescue.lua, on a Bank whose disk is full.
--
-- What it must do: free what can be fetched again first, touch the Bank's
-- data only when that is not enough, and then only its history -- never a
-- balance -- keeping the newest of each for every account.

local CAPACITY = 1000 * 1024
local files, dirs = {}, {}

local function used()
    local total = 0
    for _, body in pairs(files) do total = total + #body end
    return total
end

local function norm(path)
    path = tostring(path):gsub("/+", "/")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    if #path > 1 then path = path:gsub("/$", "") end
    return path
end

fs = {
    combine = function(a, b) return norm(a .. "/" .. b) end,
    exists = function(path)
        path = norm(path)
        if files[path] or dirs[path] then return true end
        for name in pairs(files) do
            if name:sub(1, #path + 1) == path .. "/" then return true end
        end
        return false
    end,
    isDir = function(path)
        path = norm(path)
        if dirs[path] or path == "/" then return true end
        for name in pairs(files) do
            if name:sub(1, #path + 1) == path .. "/" then return true end
        end
        return false
    end,
    list = function(path)
        path = norm(path)
        local out, seen = {}, {}
        for name in pairs(files) do
            local rest = name:sub(#path + 2)
            if name:sub(1, #path + 1) == (path == "/" and "/" or path .. "/")
                and rest ~= "" then
                local first = rest:match("^[^/]+")
                if path == "/" then first = name:sub(2):match("^[^/]+") end
                if first and not seen[first] then
                    seen[first] = true
                    out[#out + 1] = first
                end
            end
        end
        return out
    end,
    delete = function(path)
        path = norm(path)
        files[path], dirs[path] = nil, nil
        for name in pairs(files) do
            if name:sub(1, #path + 1) == path .. "/" then files[name] = nil end
        end
    end,
    move = function(from, to) files[norm(to)], files[norm(from)] = files[norm(from)], nil end,
    getSize = function(path) return #(files[norm(path)] or "") end,
    getFreeSpace = function() return CAPACITY - used() end,
    open = function(path, mode)
        path = norm(path)
        if mode == "r" then
            local body = files[path]
            return { readAll = function() return body end, close = function() end }
        end
        local parts = {}
        return { write = function(text) parts[#parts + 1] = text end,
            close = function()
                local body = table.concat(parts)
                assert(used() + #body <= CAPACITY, "Out of space")
                files[path] = body
            end }
    end,
}

local function serialize(value)
    if type(value) == "table" then
        local parts = {}
        for key, item in pairs(value) do
            local name = type(key) == "number" and ("[" .. key .. "]")
                or ("[" .. string.format("%q", key) .. "]")
            parts[#parts + 1] = name .. "=" .. serialize(item)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end
textutils = {
    serialize = function(value) return serialize(value) end,
    unserialize = function(body) return load("return " .. body)() end,
}
colors = { white = 1, orange = 2, lightGray = 256, lime = 32, red = 16384 }
local printed = {}
term = { isColor = function() return false end, setTextColor = function() end }
print = function(text) printed[#printed + 1] = text end
local realDofile = dofile
dofile = function(path)
    if path == "/pumpe/config.lua" then return { data_file = "bank_data_v5.dat" } end
    return realDofile(path)
end

local function seed(historyPerAccount, cacheBytes)
    files, dirs = {}, {}
    files["/pumpe/bank_server.lua"] = string.rep("b", 280 * 1024)
    files["/pumpe/installer.lua"] = string.rep("i", 63 * 1024)
    files["/pumpe/lib/ui.lua"] = string.rep("u", 80 * 1024)
    files["/updates/pumpe.lua"] = string.rep("p", cacheBytes)
    files["/updates/.cache_version"] = "11.1.0"
    files["/pumpe/.online_update_stage/bank_server.lua"] = string.rep("s", 20 * 1024)
    files["/pumpe/bank_data_v5.dat.tmp"] = string.rep("t", 10 * 1024)
    local state = { accounts = {}, transactions = {} }
    for _, id in ipairs({ "ACC1", "ACC2" }) do
        state.accounts[id] = { account_id = id, balance = 123.5,
            notifications = {} }
        for index = 1, 50 do
            state.accounts[id].notifications[index] = { notification_id = id
                .. "N" .. index, title = string.rep("n", 100) }
        end
    end
    for index = 1, historyPerAccount do
        for _, id in ipairs({ "ACC1", "ACC2" }) do
            state.transactions[#state.transactions + 1] = { tx_id = id .. "T"
                .. index, account_id = id, amount = index,
                description = string.rep("d", 150) }
        end
    end
    files["/pumpe/bank_data_v5.dat"] = serialize(state)
    return state
end

local function run()
    printed = {}
    assert(loadfile("../tools/bank_rescue.lua"))()
end

-- 1. The cache was the problem: removing it is enough, and the data is left
-- exactly as it was.
seed(100, 400 * 1024)
local before = files["/pumpe/bank_data_v5.dat"]
run()
assert(not fs.exists("/updates"), "the /updates cache is gone")
assert(not fs.exists("/pumpe/.online_update_stage"), "and unfinished staging")
assert(files["/pumpe/bank_data_v5.dat.tmp"] == nil, "and a half-written save")
assert(files["/pumpe/bank_data_v5.dat"] == before,
    "enough room, so the data is not touched")
assert(printed[#printed]:find("reboot", 1, true))

-- 2. The data itself is too big: history is trimmed, money is not.
seed(1100, 100 * 1024)
run()
local state = textutils.unserialize(files["/pumpe/bank_data_v5.dat"])
local counts = {}
for _, tx in ipairs(state.transactions) do
    counts[tx.account_id] = (counts[tx.account_id] or 0) + 1
end
assert(counts.ACC1 == 30 and counts.ACC2 == 30, "the newest thirty each")
assert(state.transactions[#state.transactions].tx_id == "ACC2T1100",
    "newest kept, in order")
assert(#state.accounts.ACC1.notifications == 20
    and state.accounts.ACC1.notifications[1].notification_id == "ACC1N1",
    "and the newest twenty notifications")
assert(state.accounts.ACC1.balance == 123.5 and state.accounts.ACC2.balance == 123.5,
    "balances untouched")
assert(fs.getFreeSpace() > 320 * 1024, "room for the new Bank to go in")

dofile = realDofile
print = _G.print
io.write("host_bank_rescue_test: OK\n")
