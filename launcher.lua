-- PUMPE v5.3 -> v5.4 migration bridge.
-- New installations boot through installer.lua and do not use this file.

local args = { ... }
local role = string.lower(tostring(args[1] or ""))
local valid = {
    bank = true, pumpe = true, service = true,
    event = true, tax = true, border = true,
}

if not valid[role] then
    print("PUMPE migration launcher")
    print("Usage: launcher <bank|pumpe|service|event|tax|border>")
    return
end

local root = fs.getDir(shell.getRunningProgram())
if root == "" then root = "." end

-- Bank Servers upgraded from v5.3 have the new standalone installer at
-- startup.lua. Running it once rewrites /startup.lua to the permanent
-- installer boot entry. Other roles normally already have installer.lua.
local installer = fs.combine(root,
    role == "bank" and "startup.lua" or "installer.lua")
if not fs.exists(installer) then
    error("Missing PUMPE Easy Deployment: " .. installer)
end

shell.run(installer, "--boot", role)
