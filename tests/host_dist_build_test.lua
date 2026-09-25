-- The stripped build, 11.2.
--
-- The Core, the Vault and the shared libraries are published from dist/:
-- the same files with their comments and indentation taken out, because the
-- Bank Core ran out of disk. A stripper that got a string or a long comment
-- wrong would ship a different program -- so this compiles both and compares
-- the bytecode, debug information stripped. Identical bytecode is the same
-- program. And every line has to stay where it was, so an error a computer
-- reports still names the right line of the source.

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "missing " .. path)
    local body = handle:read("a")
    handle:close()
    return body
end

local function lines(body)
    local count = 1
    for _ in body:gmatch("\n") do count = count + 1 end
    return count
end

local STRIPPED = { "bank_server.lua", "bank_vault.lua", "lib/net.lua",
    "lib/ui.lua", "lib/update.lua", "lib/util.lua" }

local saved, total = 0, 0
for _, path in ipairs(STRIPPED) do
    local source = readFile("../" .. path)
    local built = readFile("../dist/" .. path)
    local original = assert(load(source, "=" .. path))
    local stripped = assert(load(built, "=" .. path),
        "dist/" .. path .. " does not compile")
    assert(string.dump(original, true) == string.dump(stripped, true),
        "dist/" .. path .. " is not the same program as " .. path
            .. "; rerun the release builder")
    assert(lines(built) == lines(source),
        "dist/" .. path .. " moved lines, so errors would name the wrong one")
    assert(not built:find("\n%s*%-%-"), "dist/" .. path .. " still has comments")
    assert(#built < #source)
    saved, total = saved + (#source - #built), total + #source
end

-- The stripper itself, on the cases that would break a naive one.
local tricky = table.concat({
    'local a = "-- not a comment" -- a comment',
    "local b = [[ -- inside a long string",
    "   keeps its indentation ]] --[[ a long",
    "comment ]] local c = 'it\\'s' .. [==[ ]] still string ]==]",
    "local d = a--[[inline]]..b",
    "local e = 1 - -1 --[=[ level one ]=]",
    -- Two words held apart only by a comment must stay apart: "dor e".
    "local f = e--[[x]]or 0",
    "return \"line\\",
    "    continues\", d, e, f",
}, "\n")
-- Run through the real stripper when node is here to run it (it is on the
-- machine that builds releases; the check is skipped anywhere else).
local probe = io.popen("node --version 2>/dev/null")
local hasNode = probe and probe:read("a"):match("^v%d") ~= nil
if probe then probe:close() end
if hasNode then
    local input, output = os.tmpname(), os.tmpname()
    local writer = assert(io.open(input, "wb"))
    writer:write(tricky)
    writer:close()
    assert(os.execute("node ../tools/strip_lua.js " .. input .. " " .. output))
    local built = readFile(output)
    os.remove(input)
    os.remove(output)
    local a = assert(load(tricky, "=tricky"))
    local b = assert(load(built, "=tricky"), "stripped sample does not compile")
    assert(string.dump(a, true) == string.dump(b, true),
        "the stripper changed the sample program")
    local x = { a() }
    local y = { b() }
    assert(x[1] == y[1] and x[1] == "line\n    continues" and x[2] == y[2]
        and x[3] == y[3] and x[4] == y[4] and x[4] == 2,
        "and it returns the same values")
    assert(lines(built) == lines(tricky))
    assert(built:find("   keeps its indentation", 1, true),
        "indentation inside a long string is the string's")
    assert(not built:find("level one", 1, true)
        and not built:find("inline", 1, true)
        and built:find("-- not a comment", 1, true), "comments are gone,"
        .. " and a string that looks like one is not")
else
    print("host_dist_build_test: node not found, stripper sample skipped")
end
print(string.format("host_dist_build_test: OK (%d KiB of comments and"
    .. " indentation left out of %d KiB)", math.floor(saved / 1024),
    math.floor(total / 1024)))
