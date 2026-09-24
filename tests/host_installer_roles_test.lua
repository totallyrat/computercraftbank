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
for _, id in ipairs({ "tpbank", "ccgserver", "apps", "anchor", "admin",
    "internet", "delivery" }) do
    assert(declared[id] and programs[id],
        id .. " must be both offered and installable")
end

-- A computer whose boot marker names a role this Easy Deployment does not
-- know must not be stranded. Before 9.2.2 it printed UNKNOWN ROLE and
-- returned, and because the installer only updated itself when booting the
-- Bank, that computer could never learn the role either -- it needed a file
-- copied onto it by hand.
local bootBlock = source:match("\nif bootRoleId then selfUpdateInstaller.-\nif bootRoleId then")
assert(bootBlock,
    "the installer must update itself on every boot, not only the Bank's,"
        .. " or a computer running an older copy can never learn a role"
        .. " added after it was installed")
assert(bootBlock:match("bootRoleId = nil"),
    "an unknown role must fall through to the role picker rather than"
        .. " returning, so the computer always has somewhere to go")

-- A Delivery Terminal in Pickup mode faces the public, and a customer can
-- reboot it with Ctrl+R and then hold Ctrl+T while it starts. Everything
-- Easy Deployment does on the way up -- updating itself, checking the role's
-- files -- waits on the network, and a terminate during any of it would drop
-- them into the shell beside every locker. So the lock is taken before the
-- first thing the installer does at all, which here is asking for the
-- screen.
local function bootAndStop(arguments, lockFileThere)
    local savedFs, savedTerm = fs, term
    local savedPull, savedRaw = os.pullEvent, os.pullEventRaw
    local lockedAtFirstCall
    local plain = function() end
    os.pullEvent, os.pullEventRaw = plain, function() end
    fs = {
        combine = function(left, right)
            return (tostring(left):gsub("^/+", ""):gsub("/+$", "")) .. "/"
                .. tostring(right)
        end,
        exists = function(path)
            return lockFileThere and path == "pumpe/keyboard.lock"
        end,
    }
    term = { current = function()
        lockedAtFirstCall = os.pullEvent == os.pullEventRaw
        error("stopped here", 0)
    end }
    local ok, err = pcall(assert(loadfile("../installer.lua")),
        table.unpack(arguments))
    fs, term, os.pullEvent, os.pullEventRaw = savedFs, savedTerm, savedPull,
        savedRaw
    assert(not ok and err == "stopped here", "the installer did something"
        .. " before asking for the screen: " .. tostring(err))
    return lockedAtFirstCall
end
assert(bootAndStop({ "--boot", "delivery" }, true),
    "a pickup point is locked before Easy Deployment does anything else")
assert(not bootAndStop({ "--boot", "delivery" }, false),
    "and only a pickup point: staff keep Ctrl+T everywhere else")
assert(not bootAndStop({}, true),
    "the role menu is for whoever is setting the computer up")
assert(not bootAndStop({ "--boot", "service" }, true),
    "a lock left on the disk never locks a role that is not a pickup point")
-- A locked program that ends anyway is started again, never left at a
-- shell prompt.
local afterRun = source:match('\n    shell%.run%(program%)\n(.-)\n    return\nend')
assert(afterRun and afterRun:find("fs.exists(KEYBOARD_LOCK)", 1, true)
    and afterRun:find("os.reboot()", 1, true),
    "a locked role that returns must reboot, not fall through to the shell")

-- startup.lua is the same file, so it cannot drift from installer.lua.
assert(readFile("../startup.lua") == source,
    "startup.lua and installer.lua must stay identical")

print("host_installer_roles_test: OK ("
    .. (function()
        local count = 0
        for _ in pairs(programs) do count = count + 1 end
        return count
    end)() .. " roles, each installable and bootable)")
