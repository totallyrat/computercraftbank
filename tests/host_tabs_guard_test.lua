-- 12.0 Final: every program has the tabs it needs, all on the bar. The bar
-- only grows a More past four tabs, and no program has that many -- so a
-- program that still hands More its actions, or waits for a tap on it, has
-- things nobody can reach. Every program here is read for that.

local listing = assert(io.popen("ls ../*.lua"))
local checked = 0
for path in listing:lines() do
    local handle = assert(io.open(path, "r"))
    local source = handle:read("a")
    handle:close()
    checked = checked + 1
    for _, pattern in ipairs({ "resolveTab%(", "moreMenu%(", "tab:more",
        "%f[%w_]more = {", "%f[%w_]more = more" }) do
        assert(not source:find(pattern), path .. " still uses More ("
            .. pattern .. "): put what it holds on a tab")
    end
    -- And no tab list is longer than the bar holds.
    for list in source:gmatch("list = (%b{})") do
        local tabs = 0
        for _ in list:gmatch("{ id = ") do tabs = tabs + 1 end
        assert(tabs <= 4, path .. " has " .. tabs .. " tabs; the bar shows four")
    end
end
listing:close()
assert(checked > 20, "the programs were found")
print("host_tabs_guard_test: OK")
