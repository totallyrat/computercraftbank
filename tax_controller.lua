-- PUMPE Tax Controller (retired in v7.1.0).
--
-- Its duties moved to the Bank Admin Terminal, which holds every tax control
-- this program had plus account approval, balance adjustments, bans, tax
-- demands and system-wide announcements.
--
-- This file is still published because the release manifest's required file
-- list is frozen: Bank Servers older than 7.0.1 reject a manifest that is
-- missing an entry they expect, so removing it would strand them.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "8.1.1"
local ok, ui = pcall(require, "lib.ui")
local target = term.current()

if ok and type(ui) == "table" then
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "TAX CONTROLLER RETIRED", "v" .. PROGRAM_VERSION)
    ui.wrappedText(target, 2, 5,
        "Everything this terminal did now lives in the Bank Admin Terminal,"
        .. " along with account approval, balances, bans and announcements.",
        width - 2, 6, ui.theme.ink)
    ui.wrappedText(target, 2, 12,
        "Run Easy Deployment on this computer and install ADMIN TERMINAL."
        .. " It uses the same protected download code.",
        width - 2, 5, ui.theme.muted)
    ui.text(target, 2, height, "Press any key", ui.theme.muted)
    os.pullEvent("key")
    ui.clear(target)
else
    print("The Tax Controller was retired in v7.1.0.")
    print("Install ADMIN TERMINAL through Easy Deployment instead.")
end
