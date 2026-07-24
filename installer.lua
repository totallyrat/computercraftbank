-- Manual launcher for the standalone Easy Deployment startup installer.

local root = fs.getDir(shell.getRunningProgram())
if root == "" then root = "." end
local installer = fs.combine(root, "startup.lua")

if not fs.exists(installer) then
    error("Missing standalone installer: " .. installer)
end

shell.run(installer, ...)
