-- Lua allows 200 local variables per function, and each program's top level
-- is one function. bank_server.lua crossed that line in 8.0.0 with two new
-- constants and would not load in ComputerCraft at all -- "function at line
-- 5257 has more than 200 local variables" -- while luac on the host still
-- accepted the same file. ComputerCraft's Lua counts a little differently, so
-- the host needs real margin rather than none: v7.1.0 ran with 187 and v8.0.0
-- failed with 189.

local CEILING = 175

local function readFile(path)
    local handle = assert(io.open(path, "r"), "cannot read " .. path)
    local body = handle:read("a")
    handle:close()
    return body
end

-- Counts by asking the parser how many more locals the top level can take.
-- Padding goes in front of the body so a module ending in `return x` still
-- parses.
local function topLevelLocals(path)
    local body = readFile(path)
    assert(load(body, path), path .. " does not parse at all")
    local low, high = 0, 200
    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        local padding = {}
        for index = 1, middle do
            padding[index] = "local __probe" .. index .. " = " .. index
        end
        if load(table.concat(padding, "\n") .. "\n" .. body, path) then
            low = middle
        else
            high = middle - 1
        end
    end
    return 200 - low
end

local PROGRAMS = {
    "bank_server.lua", "pumpe.lua", "installer.lua", "startup.lua",
    "service_kiosk.lua", "event_kiosk.lua", "border_controller.lua",
    "admin_terminal.lua", "ccg.lua", "gps_anchor.lua", "tax_controller.lua",
    "launcher.lua", "lib/net.lua", "lib/ui.lua", "lib/update.lua",
    "lib/util.lua",
}

local worst, worstFile = 0, nil
for _, name in ipairs(PROGRAMS) do
    local used = topLevelLocals("../" .. name)
    if used > worst then worst, worstFile = used, name end
    assert(used <= CEILING, string.format(
        "%s declares %d top-level locals; keep it under %d or ComputerCraft "
        .. "will refuse to load it (group constants into one table)",
        name, used, CEILING))
end

-- A guard nobody can see the value of is a guard nobody maintains.
print(string.format("host_local_limit_test: OK (worst is %s at %d/%d)",
    worstFile, worst, CEILING))
