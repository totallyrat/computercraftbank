-- Every name a program reads that is not a local is a global, and a global
-- nobody sets is nil. Lua says nothing until the line runs. 12.0 found two:
-- the Vault read `owner` for `ownerId` and told no territory owner about a
-- visa request, and Revolution called a function declared further down, so
-- opening an account stopped the app.
--
-- So every global read in every program is checked against what Lua and
-- ComputerCraft actually provide. Uses luac from the host; skipped without.

local KNOWN = {}
for name in ([[
    assert error ipairs pairs next select tonumber tostring type rawget rawset
    rawequal setmetatable getmetatable pcall xpcall require load loadfile
    loadstring dofile print unpack table string math os io coroutine package
    utf8 _G _ENV
    colors colours fs term shell sleep rednet peripheral keys redstone
    textutils parallel http gps window vector paintutils settings multishell
    PUMPE_TEST_MODE PUMPE_SERVICE_TEST_MODE
]]):gmatch("%S+") do KNOWN[name] = true end

local probe = io.popen("luac5.3 -v 2>&1")
local version = probe and probe:read("*a") or ""
if probe then probe:close() end
if not version:find("Lua 5.3", 1, true) then
    print("host_globals_test: SKIPPED (no luac5.3 on this host)")
    return
end

local listing = io.popen("ls ../*.lua ../lib/*.lua")
local problems = {}
for path in listing:lines() do
    if not path:find("scratch_manifest", 1, true) then
        local dump = io.popen("luac5.3 -p -l '" .. path .. "' 2>&1")
        for line in dump:lines() do
            local name = line:match('GETTABUP.-; _ENV "([%w_]+)"')
                or line:match('SETTABUP.-; _ENV "([%w_]+)"')
            if name and not KNOWN[name] then
                local at = line:match("%[(%d+)%]") or "?"
                problems[#problems + 1] = path:gsub("^%.%./", "") .. ":" .. at
                    .. " uses a global " .. name .. " that nothing sets"
            end
        end
        dump:close()
    end
end
listing:close()
assert(#problems == 0, "\n" .. table.concat(problems, "\n"))
print("host_globals_test: OK")
