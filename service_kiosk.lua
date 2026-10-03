local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- The Service Kiosk, FoxyOS 13: merged into the Company app in the Pocket.
--
-- Everything a kiosk did is in the Pocket now. The till is the Company app's
-- Sell tab, a standing computer running the Pocket keeps its customer
-- monitors, Dev Mode is in the Pocket's Settings and the MyID Verifier is
-- at the till. A kiosk that updates to 13 says so and offers to turn itself
-- into a Pocket. One that was never linked to a company, and still holds
-- money of its own, offers to pay it out first: nobody will open this
-- machine to collect it later.

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "12.1.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local kiosk = util.loadTable(fs.combine(ROOT, "service_kiosk_device.dat"), {})
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end

local MERGED = "The Service Kiosk has merged with the Company app in the Pocket"

local function money(value)
    return util.money(value, config.currency)
end

local function asKiosk(payload)
    payload = payload or {}
    payload.terminal_id = kiosk.terminal_id
    payload.terminal_token = kiosk.terminal_token
    return payload
end

-- The customer monitor, if there is one, tells the customers too.
local function tellMonitor()
    if type(peripheral) ~= "table" or not peripheral.find then return end
    local monitor = peripheral.find("monitor")
    if not monitor then return end
    pcall(function()
        monitor.setTextScale(0.5)
        local width, height = monitor.getSize()
        ui.clear(monitor, colors.black)
        ui.fill(monitor, 1, 1, width, math.min(2, height), colors.cyan)
        ui.center(monitor, 1, "MOVED", colors.black, colors.cyan)
        for index, line in ipairs(ui.wrap("This till runs in the Pocket now",
            math.max(1, width - 2))) do
            if 3 + index <= height then
                ui.center(monitor, 3 + index, line, colors.white, colors.black)
            end
        end
    end)
end

-- What this kiosk holds of its own: only one never linked to a company has
-- any. A linked kiosk always paid straight into its owner's account.
local function strandedBalance()
    if not kiosk.terminal_id then return 0 end
    local state = client:request("KIOSK_STATE", asKiosk())
    if not state or state.company then return 0 end
    return tonumber(state.terminal and state.terminal.balance) or 0
end

-- Paying it out: a withdrawal code, typed into Foxy on somebody's Pocket.
local function withdraw(balance)
    local created, err = client:request("CREATE_WITHDRAWAL_CODE", asKiosk({
        amount = balance, description = "Service Kiosk closing" }))
    if not created then
        ui.message(target, "error", "NO CODE", err, 1.6)
        return false
    end
    local deadline = util.nowMs() + (tonumber(config.payment_code_ttl_ms) or 300000)
    while true do
        local width, height = target.getSize()
        local seconds = math.max(0, math.floor((deadline - util.nowMs()) / 1000))
        ui.clear(target)
        ui.header(target, "WITHDRAW " .. money(created.amount), "Type it into Foxy",
            util.formatClock())
        ui.fill(target, 3, 6, width - 4, 5, colors.white)
        ui.center(target, 7, "FOXY > CODE", colors.gray, colors.white)
        ui.center(target, 9, created.code:sub(1, 3) .. " " .. created.code:sub(4, 6),
            colors.black, colors.white)
        ui.center(target, 12, string.format("%d:%02d left", math.floor(seconds / 60),
            seconds % 60), ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 1, width - 2, 1, "CANCEL",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 0.8 })
        if action == "cancel" or action == "__terminate" then
            client:request("CANCEL_CODE", asKiosk({ code = created.code }))
            return false
        end
        local status = client:request("CODE_STATUS", asKiosk({ code = created.code }))
        if status and status.status == "paid" then
            ui.message(target, "success", "PAID OUT", money(created.amount)
                .. " to " .. tostring(status.payer or "your account"), 1.6)
            return true
        end
        if seconds <= 0 or (status and (status.status == "expired"
            or status.status == "cancelled")) then
            ui.message(target, "warning", "CODE EXPIRED", "Nothing was paid out", 1.4)
            return false
        end
    end
end

-- Turning this computer into a Pocket. Apps written in Dev Mode lived in
-- the apps folder beside this program, which a Pocket keeps the apps it
-- installs in; they move to /apps, where the Pocket's Dev Mode looks.
local function becomePocket()
    if not ui.confirm(target, "DOWNLOAD POCKET", "This computer becomes a"
        .. " Pocket. Sign in as the owner, open Company, then Sell.",
        "DOWNLOAD", "BACK") then return false end
    local devDir = fs.combine(ROOT, "apps")
    if fs.exists(devDir) and fs.isDir(devDir) then
        if not fs.exists("/apps") then fs.makeDir("/apps") end
        for _, name in ipairs(fs.list(devDir)) do
            local from = fs.combine(devDir, name)
            local to = fs.combine("/apps", name)
            if not fs.isDir(from) and name:sub(-4) == ".lua" and not fs.exists(to) then
                pcall(fs.move, from, to)
            end
        end
    end
    local installer = fs.combine(ROOT, "installer.lua")
    if not fs.exists(installer) then
        ui.message(target, "error", "NO INSTALLER", "Run Easy Deployment and"
            .. " pick Pocket", 2.4)
        return false
    end
    ui.clear(target)
    shell.run(installer, "--install", "pumpe")
    return true
end

if rawget(_G, "PUMPE_SERVICE_TEST_MODE") == true then
    return { merged = MERGED, become_pocket = becomePocket, withdraw = withdraw,
        stranded_balance = strandedBalance }
end

ui.boot(target, "SERVICE KIOSK", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
-- Keeps updating, so whatever comes next still reaches a kiosk that has
-- not been turned into a Pocket yet.
net.autoUpdate(config, "service", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
tellMonitor()
client:discover()
local held = strandedBalance()

while true do
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "SERVICE KIOSK", ui.osLabel and ui.osLabel(config) or "FoxyOS",
        util.formatClock())
    ui.wrappedText(target, 3, 5, MERGED, width - 4, 3, ui.theme.ink)
    ui.wrappedText(target, 3, 8, "Sell from Company, then Sell, on any Pocket. A"
        .. " computer like this one runs the Pocket too, and keeps its customer"
        .. " screen.", width - 4, 4, ui.theme.muted)
    local scene = ui.scene(target)
    local buttonY = height - 4
    if held > 0 then
        scene:button("withdraw", 2, buttonY - 2, width - 2, 1, "WITHDRAW "
            .. money(held) .. " FIRST", { background = ui.theme.warning,
                foreground = colors.black })
    end
    scene:button("pocket", 2, buttonY, width - 2, 3, "DOWNLOAD POCKET",
        { background = ui.theme.success, foreground = colors.black, shadow = true })
    scene:button("exit", 1, height, 9, 1, "CLOSE", { background = ui.theme.panel })
    local action = scene:wait({ tickRate = 30 })
    if action == "exit" or action == "__terminate" then break end
    if action == "__tick" then
        net.autoUpdate(config, "service", ROOT, client)
    elseif action == "withdraw" then
        if withdraw(held) then held = strandedBalance() end
    elseif action == "pocket" then
        if becomePocket() then return end
    end
end

ui.clear(target)
print("Service Kiosk closed.")
