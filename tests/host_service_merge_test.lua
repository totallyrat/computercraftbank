-- The Service Kiosk after FoxyOS 13, against a real Bank Core and Vault.
--
-- It has merged with the Company app in the Pocket, and says so. A kiosk
-- never linked to a company still holds money of its own, so it offers to
-- pay that out first -- a withdrawal code typed into Foxy -- and then to
-- turn the computer into a Pocket: Easy Deployment installs it, and the
-- apps written in Dev Mode move to /apps, where the Pocket looks for them.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local kiosk = require("kiosk_harness")

local ana = bank.register("Ana Fox", "1234")
local registered = bank.request("KIOSK_REGISTER", { name = "Corner Shop" })
bank.state.terminals[registered.terminal_id].balance = 25

local function real(action, payload)
    local ok, result = pcall(bank.request, action, payload)
    if ok then return result end
    if type(result) == "table" and result.pumpe then
        return nil, result.message, result.code
    end
    error(result, 0)
end

-- A small disk: one app written in Dev Mode, beside the kiosk.
local disk = { ["/pumpe/apps/notes.lua"] = "return function() end" }
fs = {
    exists = function(path) return disk[path] ~= nil or path == "/pumpe/apps"
        or path == "/pumpe/installer.lua" end,
    isDir = function(path) return path == "/pumpe/apps" or path == "/apps" end,
    list = function() return { "notes.lua" } end,
    makeDir = function(path) disk[path] = "dir" end,
    move = function(from, to) disk[to], disk[from] = disk[from], nil end,
}
local ran

local script = kiosk.script()
kiosk.push(script.actions, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "The Service Kiosk has merged with the Company app in the Pocket"),
        "it says so, in so many words")
    assert(kiosk.has(frame, "WITHDRAW $25 FIRST"), "the money it holds is offered")
    assert(kiosk.has(frame, "DOWNLOAD POCKET"))
    return "withdraw"
end, function(seen)
    local code
    for candidate, payment in pairs(bank.state.active_pay_codes) do
        if payment.kind == "withdrawal" then code = candidate end
    end
    assert(code, "a withdrawal code")
    bank.request("PAY_CODE_CONFIRM", bank.as(ana, { code = code, pin = "1234" }))
    return "__tick"
end, function(seen)
    assert(kiosk.said(seen, "PAID OUT"), "paid out")
    assert(not kiosk.has(seen.frames[#seen.frames], "WITHDRAW"),
        "and nothing left to withdraw")
    return "pocket"
end)
kiosk.push(script.confirms, true)
kiosk.run({ file = "service_kiosk.lua", bank = real, script = script,
    device = { terminal_id = registered.terminal_id,
        terminal_token = registered.terminal_token },
    shell_run = function(...) ran = { ... } end })

assert(bank.balanceOf(ana) == 525, "the kiosk's 25 reached Ana")
assert(bank.state.terminals[registered.terminal_id].balance == 0)
assert(ran and ran[1] == "/pumpe/installer.lua" and ran[2] == "--install"
    and ran[3] == "pumpe", "Easy Deployment installs the Pocket")
assert(disk["/apps/notes.lua"] and not disk["/pumpe/apps/notes.lua"],
    "the Dev Mode app moved to where the Pocket looks")

-- A kiosk linked to a company held nothing of its own: no withdraw.
local linked = bank.request("KIOSK_REGISTER", { name = "Linked" })
local company = bank.request("COMPANY_CREATE", bank.as(ana, {
    company_name = "Fox Goods", app_id = "COMPANY" })).company
bank.state.terminals[linked.terminal_id].company_id = company.company_id
script = kiosk.script()
kiosk.push(script.actions, function(seen)
    assert(not kiosk.has(seen.frames[#seen.frames], "WITHDRAW"))
    return "exit"
end)
kiosk.run({ file = "service_kiosk.lua", bank = real, script = script,
    device = { terminal_id = linked.terminal_id,
        terminal_token = linked.terminal_token } })

print("host_service_merge_test: OK")
