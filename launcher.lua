-- Usage:
--   launcher bank
--   launcher pumpe
--   launcher service
--   launcher event
--   launcher tax

local args = { ... }
local role = string.lower(args[1] or "")
local programs = {
    bank = "bank_server.lua",
    pumpe = "pumpe.lua",
    service = "service_kiosk.lua",
    event = "event_kiosk.lua",
    tax = "tax_controller.lua",
}

if not programs[role] then
    print("PUMPE Ecosystem launcher")
    print("")
    print("Usage: launcher <role>")
    print("Roles: bank, pumpe, service, event, tax")
    return
end

local root = fs.getDir(shell.getRunningProgram())
if root == "" then root = "." end
local installer = fs.combine(root, "installer.lua")
if role ~= "bank" and fs.exists(installer) then
    pcall(shell.run, installer, "--auto", role)
end
local program = fs.combine(root, programs[role])
if not fs.exists(program) then
    error("Missing PUMPE program: " .. program)
end

shell.run(program)
