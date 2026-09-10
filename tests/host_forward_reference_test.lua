-- A local declared further down a file is not a forward declaration: at any
-- use site above it the same name is a global, and a global that was never
-- assigned is nil. Lua compiles that happily, so it only shows up in the
-- world, as "attempt to call global 'x' (a nil value)".
--
-- This has bitten three times now: logActivity used by the load-time depot
-- bootstrap two hundred lines above it, a renderer reading POTS before its
-- declaration, and appstore reached from Urgent Contact. Each one parsed,
-- passed every test, and failed on the server.
--
-- The check is textual rather than a real parse: strip comments and strings,
-- find the top-level `local` declarations, then look for the same name used
-- as a bare identifier on an earlier line. A name that an inner scope also
-- declares is skipped, because there the earlier use is that inner local.

local PROGRAMS = {
    "bank_server.lua", "pumpe.lua", "installer.lua", "startup.lua",
    "service_kiosk.lua", "event_kiosk.lua", "border_controller.lua",
    "admin_terminal.lua", "ccg.lua", "gps_anchor.lua", "tax_controller.lua",
    "launcher.lua", "foxy.lua", "app_server.lua", "bank_app_server.lua",
    "buckapp.lua", "ccg_server.lua",
    "lib/net.lua", "lib/ui.lua", "lib/update.lua", "lib/util.lua",
}

local function readLines(path)
    local handle = assert(io.open(path, "r"), "cannot read " .. path)
    local body = handle:read("*a")
    handle:close()
    local lines = {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

-- Comments and string literals are not code. Blanking them keeps a name in
-- a comment or an error message from counting as a use.
local function stripNoise(line)
    line = line:gsub("%-%-%[=*%[.*$", "")
    line = line:gsub("%-%-.*$", "")
    line = line:gsub('"[^"]*"', '""')
    line = line:gsub("'[^']*'", "''")
    line = line:gsub("%[=*%[.-%]=*%]", "[[]]")
    return line
end

-- Depth 0 is the file's own top level. `function x.y()` opens a block but
-- declares nothing, so only the `local` keyword matters here.
local function scan(path)
    local lines = readLines(path)
    local declared, allLocals, depth = {}, {}, 0
    local inLongString = false
    for number, raw in ipairs(lines) do
        local line = raw
        if inLongString then
            if line:find("%]=*%]") then
                line = line:gsub("^.-%]=*%]", "")
                inLongString = false
            else
                line = ""
            end
        end
        line = stripNoise(line)
        if line:find("%[=*%[") and not line:find("%]=*%]") then
            inLongString = true
            line = line:gsub("%[=*%[.*$", "")
        end

        local names = {}
        for name in line:gmatch("local%s+function%s+([%a_][%w_]*)") do
            names[#names + 1] = name
        end
        for list in line:gmatch("local%s+([%a_][%w_,%s]*)=") do
            for name in list:gmatch("[%a_][%w_]*") do names[#names + 1] = name end
        end
        for list in line:gmatch("local%s+([%a_][%w_,%s]*)$") do
            for name in list:gmatch("[%a_][%w_]*") do names[#names + 1] = name end
        end
        for _, name in ipairs(names) do
            if name ~= "function" then
                allLocals[name] = (allLocals[name] or 0) + 1
                if depth == 0 and not declared[name] then
                    declared[name] = number
                end
            end
        end

        -- Track block depth so a `local` inside a function is not mistaken
        -- for a top-level one.
        for word in line:gmatch("[%a_][%w_]*") do
            if word == "function" or word == "do" or word == "then" then
                depth = depth + 1
            elseif word == "end" then
                depth = depth - 1
            end
        end
        for _ in line:gmatch("elseif") do depth = depth - 1 end
        for _ in line:gmatch("until") do depth = depth - 1 end
        if depth < 0 then depth = 0 end
    end
    return lines, declared, allLocals
end

local problems = {}
for _, name in ipairs(PROGRAMS) do
    local path = "../" .. name
    local lines, declared, allLocals = scan(path)
    for declaredName, declaredLine in pairs(declared) do
        -- A name some inner scope also declares is ambiguous to a textual
        -- check: an earlier use is that inner local, not this one.
        if allLocals[declaredName] == 1 and #declaredName > 2 then
            for number = 1, declaredLine - 1 do
                local line = stripNoise(lines[number])
                for word, suffix in line:gmatch("([%a_][%w_]*)(.?)") do
                    if word == declaredName then
                        local at = line:find(word, 1, true)
                        local before = line:sub(1, at - 1)
                        local after = line:sub(at + #word):match("^%s*(.?.?)")
                            or ""
                        -- `a.name` and `a:name` are fields, not the local.
                        -- `name =` is a table key or an assignment; what
                        -- actually fails in the world is *reading* a name
                        -- that is not bound yet.
                        if not before:match("[%.:]$")
                            and not (after:sub(1, 1) == "="
                                and after:sub(2, 2) ~= "=") then
                            problems[#problems + 1] = string.format(
                                "%s:%d uses %q, which is not declared local "
                                .. "until line %d -- at line %d it is a nil "
                                .. "global", name, number, declaredName,
                                declaredLine, number)
                        end
                        break
                    end
                    if suffix == "" then break end
                end
            end
        end
    end
end

if #problems > 0 then
    for _, problem in ipairs(problems) do print("  " .. problem) end
    error(#problems .. " forward reference(s) to a top-level local")
end
print("host_forward_reference_test: OK (" .. #PROGRAMS
    .. " programs, no local used above its declaration)")
