-- Every role the installer can install, it must also be able to start.
--
-- Installing a role writes a boot marker naming it, and on the next reboot
-- the installer looks that name up. A role it cannot find is refused with
-- "UNKNOWN ROLE" -- which is exactly what a 3rd Party Bank Server did in
-- 9.0 through 9.2, because its role was built inline at the point of
-- install and never added to the list. The same gap silently stopped it
-- auto-updating, since that path looks the name up too.
--
-- This reads the installer's own tables rather than a copy of them, so a
-- role added in the future is covered without anybody remembering to.

local function readFile(path)
    local handle = assert(io.open(path, "r"), "cannot read " .. path)
    local body = handle:read("*a")
    handle:close()
    return body
end

local source = readFile("../installer.lua")

-- The role list, as the installer declares it. Scanned from inside the
-- `roles` block only: an earlier version of this test scanned the whole
-- file, so a role table built inline at the point of install counted as
-- declared and the test passed against the very bug it was written for.
local roleBlock = source:match("\nlocal roles = {(.-)\n}")
assert(roleBlock, "the roles list was not found")
local declared = {}
for id in roleBlock:gmatch('id%s*=%s*"([%w_]+)"') do
    declared[id] = true
end
assert(declared.pumpe and declared.bank,
    "the role list was not found where this test expects it")

-- Every program the installer knows how to install.
local programs = {}
local programBlock = source:match("local rolePrograms = {(.-)\n}")
assert(programBlock, "rolePrograms was not found")
for id, file in programBlock:gmatch('([%w_]+)%s*=%s*"([%w_%.]+)"') do
    programs[id] = file
end

-- Anything installRole is called with must be a role the installer can find
-- again. That is the whole invariant.
for id in pairs(programs) do
    assert(declared[id], "rolePrograms has '" .. id
        .. "' but the roles list does not, so a computer installed as that"
        .. " role fails on its next reboot with UNKNOWN ROLE, and never"
        .. " auto-updates either")
end

-- And every role that is offered has something to install.
for id in pairs(declared) do
    assert(programs[id], "the roles list offers '" .. id
        .. "' but rolePrograms has no file for it")
end

-- The roles added since 9.0, named so a rename cannot quietly drop one.
for _, id in ipairs({ "tpbank", "ccgserver", "apps", "anchor", "admin" }) do
    assert(declared[id] and programs[id],
        id .. " must be both offered and installable")
end

-- startup.lua is the same file, so it cannot drift from installer.lua.
assert(readFile("../startup.lua") == source,
    "startup.lua and installer.lua must stay identical")

print("host_installer_roles_test: OK ("
    .. (function()
        local count = 0
        for _ in pairs(programs) do count = count + 1 end
        return count
    end)() .. " roles, each installable and bootable)")
