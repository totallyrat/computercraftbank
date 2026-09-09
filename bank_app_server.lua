local ROOT = fs.getDir(shell.getRunningProgram())
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")

-- PUMPE 3RD PARTY BANK SERVER
--
-- A bank that is not Foxy. It hosts one Bank App -- BuckApp, or anything
-- else somebody writes -- and keeps that bank's accounts, which have their
-- own logins and nothing to do with a Foxy Account.
--
-- The one thing it shares with Foxy is the Account ID: sixteen digits, the
-- first four naming the bank. That is what makes money movable between
-- banks that otherwise know nothing about each other, and it is why the
-- settlement rules live in lib/util rather than being written twice.
--
-- Unlike a Foxy Bank Server this needs no operator code. The bank it hosts
-- is public, its accounts are opened by whoever wants one, and there is
-- nothing here that could compromise the Foxy ledger.

local PROGRAM_VERSION = "9.0.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local TEST_MODE = rawget(_G, "PUMPE_TEST_MODE") == true

local target = term.current()
local running = true
local dataFile = fs.combine(ROOT, "third_party_bank_v1.dat")
local activity = {}
local ledger = setmetatable({}, { __index = util.ledger })

local function logActivity(text, color)
    table.insert(activity, 1, {
        time = util.formatClock(), text = tostring(text),
        color = color or colors.white,
    })
    while #activity > 40 do table.remove(activity) end
end

local state = util.loadTable(dataFile, {
    app_id = nil, bank_name = nil, bank_code = nil,
    accounts = {}, names = {}, ids = {},
    applied_transfers = {}, sequence = 0, transactions = {},
})

local function save() pcall(util.saveTable, dataFile, state) end

local function reject(code, message)
    error({ pumpe = true, code = code, message = message }, 0)
end
local function need(condition, code, message)
    if not condition then reject(code, message) end
    return condition
end

-- Accounts ------------------------------------------------------------------
-- Its own logins, deliberately separate from Foxy. Somebody who banks here
-- has an account here; the Foxy Account is not involved and never sees it.

local sessions = {}

local function publicAccount(account)
    return {
        account_id = account.account_id,
        bank_account_id = account.bank_account_id,
        formatted = ledger.format(account.bank_account_id),
        name = account.name,
        balance = account.balance,
        bank_name = state.bank_name,
        opened_day = account.opened_day,
    }
end

local function requireSession(payload)
    local accountId = sessions[payload and payload.session_token or ""]
    local account = accountId and state.accounts[accountId]
    need(account, "SESSION_EXPIRED", "Sign in again")
    return account
end

local function transaction(account, kind, amount, counterparty, description)
    table.insert(state.transactions, {
        account_id = account.account_id, type = kind,
        amount = util.roundMoney(amount) or 0,
        counterparty = util.safeText(counterparty, 30),
        description = util.safeText(description, 60),
        day = util.ingameDay(), time = util.formatClock(),
    })
    while #state.transactions > 600 do table.remove(state.transactions, 1) end
end

local actions = {}

function actions.TPB_INFO()
    return {
        bank_name = state.bank_name,
        bank_code = state.bank_code,
        app_id = state.app_id,
        version = config.version,
        accounts = (function()
            local count = 0
            for _ in pairs(state.accounts) do count = count + 1 end
            return count
        end)(),
    }
end

function actions.TPB_REGISTER(payload)
    local name = util.safeText(util.trim(payload.name or ""), 20)
    need(name:match("^[%w_ %-]+$") and #name >= 2, "INVALID_NAME",
        "Use 2-20 letters, numbers, spaces, _ or -")
    need(not state.names[util.normalName(name)], "NAME_TAKEN",
        "Somebody banks here under that name")
    need(util.validPin(payload.pin), "INVALID_PIN", "PIN must be four digits")

    state.sequence = state.sequence + 1
    local accountId = string.format("TPB%06d", state.sequence)
    local bankAccountId = ledger.newId(state.bank_code, state.ids)
    local account = {
        account_id = accountId,
        bank_account_id = bankAccountId,
        name = name,
        pin_hash = util.hashPin(payload.pin),
        -- A third-party bank mints no money. Every penny here arrived from
        -- somewhere, which is what keeps the economy one economy.
        balance = 0,
        opened_day = util.ingameDay(),
        pending_transfers = {},
    }
    state.accounts[accountId] = account
    state.names[util.normalName(name)] = accountId
    state.ids[bankAccountId] = accountId
    save()
    logActivity(name .. " opened an account", colors.lime)
    local token = util.token("TPBS")
    sessions[token] = accountId
    return { account = publicAccount(account), session_token = token }
end

function actions.TPB_LOGIN(payload)
    local accountId = state.names[util.normalName(payload.name or "")]
    local account = accountId and state.accounts[accountId]
    need(account and account.pin_hash == util.hashPin(payload.pin),
        "BAD_LOGIN", "Name or PIN is incorrect")
    local token = util.token("TPBS")
    sessions[token] = accountId
    return { account = publicAccount(account), session_token = token }
end

function actions.TPB_SUMMARY(payload)
    local account = requireSession(payload)
    return { account = publicAccount(account) }
end

function actions.TPB_HISTORY(payload)
    local account = requireSession(payload)
    local out = {}
    for index = #state.transactions, 1, -1 do
        local item = state.transactions[index]
        if item.account_id == account.account_id then
            out[#out + 1] = item
            if #out >= 30 then break end
        end
    end
    return { transactions = out }
end

-- Sending between two accounts at this bank. No fee: undercutting Foxy is
-- rather the point of opening your own bank.
function actions.TPB_SEND(payload)
    local sender = requireSession(payload)
    need(sender.pin_hash == util.hashPin(payload.pin), "BAD_PIN",
        "Incorrect PIN")
    local recipientId = state.names[util.normalName(payload.recipient or "")]
    local recipient = recipientId and state.accounts[recipientId]
    need(recipient, "NO_SUCH_ACCOUNT", "Nobody banks here under that name")
    need(recipient.account_id ~= sender.account_id, "INVALID_RECIPIENT",
        "You cannot send money to yourself")
    local amount = math.floor(tonumber(payload.amount) or 0)
    need(amount > 0, "BAD_AMOUNT", "Enter an amount")
    need(sender.balance >= amount, "INSUFFICIENT_FUNDS", "Not enough money")
    sender.balance = util.roundMoney(sender.balance - amount)
    recipient.balance = util.roundMoney(recipient.balance + amount)
    transaction(sender, "transfer_out", -amount, recipient.name, "Money sent")
    transaction(recipient, "transfer_in", amount, sender.name,
        "Money received")
    save()
    return { balance = sender.balance, sent = amount }
end

-- Settling with other banks -----------------------------------------------------
-- The same three steps Foxy uses, and the same rule about what an
-- unanswered transfer means, because both come from lib/util.

local function reach(bankCode)
    return net.client({
        protocol = config.ledger_protocol or "PUMPE_LEDGER_V1",
        hostname = ledger.hostFor(bankCode),
    })
end

local function ask(bankCode, action, payload, timeout)
    if bankCode == state.bank_code then
        local handler = actions[action]
        if not handler then return nil, "Unknown ledger action" end
        local ok, result = pcall(handler, payload or {})
        if ok then return result end
        if type(result) == "table" and result.pumpe then
            return nil, result.message, result.code
        end
        return nil, "Ledger error"
    end
    return reach(bankCode):request(action, payload, timeout or 6)
end

function actions.LEDGER_LOOKUP(payload)
    local accountId = state.ids[ledger.clean(payload.bank_account_id)]
    local account = accountId and state.accounts[accountId]
    need(account, "NO_SUCH_ACCOUNT", "No account has that Account ID")
    return {
        bank_account_id = account.bank_account_id,
        name = account.name,
        bank_name = state.bank_name,
        bank_code = state.bank_code,
        accepting = true,
    }
end

function actions.LEDGER_CREDIT(payload)
    local accountId = state.ids[ledger.clean(payload.bank_account_id)]
    local account = accountId and state.accounts[accountId]
    need(account, "NO_SUCH_ACCOUNT", "No account has that Account ID")
    local amount = math.floor(tonumber(payload.amount) or 0)
    need(amount > 0, "BAD_AMOUNT", "A transfer has to be worth something")
    local transferId = util.safeText(tostring(payload.transfer_id or ""), 32)
    need(#transferId >= 8, "BAD_TRANSFER", "That transfer has no id")

    state.applied_transfers = state.applied_transfers or {}
    local credited, repeated = util.ledger.applyOnce(state.applied_transfers,
        transferId, amount, function()
            account.balance = util.roundMoney(account.balance + amount)
        end)
    if repeated then
        return { credited = credited, balance = account.balance,
                 repeated = true }
    end
    util.ledger.forget(state.applied_transfers)
    transaction(account, "bank_transfer_in", amount,
        util.safeText(tostring(payload.from_bank_name or "Another bank"), 20),
        "Transferred in")
    save()
    logActivity(account.name .. " received "
        .. util.money(amount, config.currency), colors.lime)
    return { credited = amount, balance = account.balance }
end

function actions.LEDGER_STATUS(payload)
    state.applied_transfers = state.applied_transfers or {}
    local applied = util.ledger.applied(state.applied_transfers,
        util.safeText(tostring(payload.transfer_id or ""), 32))
    return { applied = applied ~= nil, amount = applied and applied.amount }
end

local function pending(account)
    account.pending_transfers = account.pending_transfers or {}
    return account.pending_transfers
end

-- Out of the balance, into a pending record, then across the wire. Only an
-- acknowledged credit clears the record; an unanswered one stays parked.
local function settle(account, targetId, amount, transferId)
    local bankCode = ledger.bankOf(targetId)
    account.balance = util.roundMoney(account.balance - amount)
    pending(account)[transferId] = {
        transfer_id = transferId, amount = amount, to = targetId,
        at = util.nowMs(),
    }
    save()
    local outcome, err, code = util.ledger.outcome(ask(bankCode,
        "LEDGER_CREDIT", {
            bank_account_id = targetId, amount = amount,
            transfer_id = transferId, from_name = account.name,
            from_bank_name = state.bank_name,
            from_bank_account_id = account.bank_account_id,
        }, 8))
    if outcome == "sent" then
        pending(account)[transferId] = nil
        save()
        return "sent"
    end
    if outcome == "refused" then
        account.balance = util.roundMoney(account.balance + amount)
        pending(account)[transferId] = nil
        save()
        return "refused", err, code
    end
    return "unknown", err
end

local function reconcile()
    for _, account in pairs(state.accounts) do
        for transferId, parked in pairs(pending(account)) do
            local answer = ask(ledger.bankOf(parked.to), "LEDGER_STATUS",
                { transfer_id = transferId }, 6)
            if answer then
                if not answer.applied then
                    account.balance = util.roundMoney(
                        account.balance + parked.amount)
                else
                    transaction(account, "bank_transfer_out", parked.amount,
                        "Another bank", "Transfer confirmed")
                end
                pending(account)[transferId] = nil
                save()
            end
        end
    end
end

function actions.TPB_TRANSFER_QUOTE(payload)
    local account = requireSession(payload)
    local wanted = ledger.valid(payload.bank_account_id)
    need(wanted, "BAD_ACCOUNT_ID", "An Account ID is sixteen digits")
    need(wanted ~= account.bank_account_id, "SAME_ACCOUNT",
        "That is this account")
    local found, err, code = ask(ledger.bankOf(wanted), "LEDGER_LOOKUP",
        { bank_account_id = wanted })
    if not found then
        need(false, code or "BANK_UNREACHABLE",
            err or "That bank did not answer")
    end
    need(found.accepting, "BANK_CLOSED",
        "That account has moved its money elsewhere")
    return {
        bank_account_id = wanted, formatted = ledger.format(wanted),
        name = found.name, bank_name = found.bank_name,
        amount = account.balance,
    }
end

-- Moving everything to another bank -- including back to a Foxy Account ID,
-- which is how somebody goes home.
function actions.TPB_TRANSFER_CONFIRM(payload)
    local account = requireSession(payload)
    need(account.pin_hash == util.hashPin(payload.pin), "BAD_PIN",
        "Incorrect PIN")
    local wanted = ledger.valid(payload.bank_account_id)
    need(wanted, "BAD_ACCOUNT_ID", "An Account ID is sixteen digits")
    need(wanted ~= account.bank_account_id, "SAME_ACCOUNT",
        "That is this account")
    local amount = math.floor(account.balance or 0)
    need(amount > 0, "NOTHING_TO_MOVE", "There is nothing here to transfer")

    local found, lookupErr, lookupCode = ask(ledger.bankOf(wanted),
        "LEDGER_LOOKUP", { bank_account_id = wanted })
    if not found then
        need(false, lookupCode or "BANK_UNREACHABLE",
            lookupErr or "That bank did not answer")
    end

    local outcome, err, code = settle(account, wanted, amount,
        util.token("XFER"))
    if outcome == "refused" then
        need(false, code or "TRANSFER_FAILED",
            err or "That bank would not take the transfer")
    elseif outcome == "unknown" then
        need(false, "TRANSFER_PENDING",
            "That bank did not answer. Your money is held and will finish"
                .. " moving, or come back, on its own.")
    end
    transaction(account, "bank_transfer_out", amount, found.bank_name,
        "Transferred to " .. found.bank_name)
    save()
    logActivity(account.name .. " moved to " .. found.bank_name, colors.orange)
    return { moved = amount, bank_name = found.bank_name }
end

-- Choosing which bank to host -----------------------------------------------

local function bankChoices()
    local appServer = net.client({
        protocol = config.app_protocol, hostname = config.app_hostname,
    })
    local listed, err = appServer:request("APP_BANKS", {}, 6)
    if not listed then return nil, err or "No App Server is reachable" end
    return listed.apps or {}
end

local function chooseBank()
    local page = 1
    while running do
        local width, height = target.getSize()
        local banks, err = bankChoices()
        ui.clear(target)
        ui.header(target, "3RD PARTY BANK SERVER", "Choose a bank to host",
            util.formatClock())
        local scene = ui.scene(target)
        if not banks then
            ui.wrappedText(target, 2, 6, err, width - 2, 3, colors.orange)
            ui.wrappedText(target, 2, 10, "A 3rd Party Bank Server hosts a"
                .. " Bank App published to the App Server. Publish one from"
                .. " a Service Kiosk in Dev Mode first.", width - 2, 4,
                colors.lightGray)
        elseif #banks == 0 then
            ui.center(target, 7, "NO BANK APPS PUBLISHED", colors.orange)
            ui.wrappedText(target, 2, 9, "A Bank App is an ordinary app whose"
                .. " file says so in its first lines:", width - 2, 3,
                colors.lightGray)
            ui.text(target, 4, 13, "-- PUMPE BANK APP: BuckApp", colors.cyan)
        else
            local perPage = math.max(1, math.floor((height - 9) / 3))
            local pages = math.max(1, math.ceil(#banks / perPage))
            page = math.max(1, math.min(page, pages))
            for slot = 1, perPage do
                local bank = banks[(page - 1) * perPage + slot]
                if not bank then break end
                scene:button("host:" .. bank.app_id, 2, 5 + (slot - 1) * 3,
                    width - 2, 2, bank.bank_name .. "  (" .. bank.name
                        .. " by " .. bank.author .. ")",
                    { background = colors.blue })
            end
            if pages > 1 then
                scene:button("prev", 2, height - 2, 8, 2, "<",
                    { background = colors.gray, disabled = page <= 1 })
                scene:button("next", 11, height - 2, 8, 2, ">",
                    { background = colors.gray, disabled = page >= pages })
            end
        end
        scene:button("again", width - 20, height - 2, 9, 2, "REFRESH",
            { background = colors.gray })
        scene:button("stop", width - 10, height - 2, 9, 2, "STOP",
            { background = colors.red })
        local action = scene:wait({ tickRate = 5, flash = false })
        if action == "stop" or action == "__terminate" then
            running = false
            return nil
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        elseif action and action:find("^host:") then
            local appId = action:match("^host:(.+)$")
            for _, bank in ipairs(banks or {}) do
                if bank.app_id == appId then return bank end
            end
        end
    end
end

local function adopt(bank)
    state.app_id = bank.app_id
    state.bank_name = bank.bank_name
    -- Derived from the name, so the same bank always answers to the same
    -- four digits without anybody keeping a register of them.
    state.bank_code = ledger.codeFor(bank.bank_name)
    save()
    logActivity("Hosting " .. bank.bank_name .. " as bank "
        .. state.bank_code, colors.lime)
end

-- Serving --------------------------------------------------------------------

local function route(sender, message, protocol)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, protocol, message.request_id, false, nil,
            "Unknown action", "UNKNOWN_ACTION")
        return
    end
    local ok, result = pcall(handler, message.payload or {}, sender)
    if ok then
        net.reply(sender, protocol, message.request_id, true, result)
    elseif type(result) == "table" and result.pumpe then
        net.reply(sender, protocol, message.request_id, false, nil,
            result.message, result.code)
    else
        logActivity("Error: " .. tostring(result), colors.red)
        net.reply(sender, protocol, message.request_id, false, nil,
            "Bank failed", "SERVER_ERROR")
    end
end

local function bankLoop()
    local protocol = config.tpb_protocol or "PUMPE_TPB_V1"
    while running do
        local sender, message = rednet.receive(protocol, 1)
        if sender then route(sender, message, protocol) end
    end
end

local function ledgerLoop()
    local protocol = config.ledger_protocol or "PUMPE_LEDGER_V1"
    while running do
        local sender, message = rednet.receive(protocol, 1)
        if sender then route(sender, message, protocol) end
    end
end

local function schedulerLoop()
    while running do
        pcall(reconcile)
        sleep(10)
    end
end

local function dashboardLoop()
    local blink = true
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, state.bank_name or "3RD PARTY BANK",
            "Bank " .. tostring(state.bank_code), util.formatClock(blink))
        local count, held = 0, 0
        for _, account in pairs(state.accounts) do
            count = count + 1
            held = held + (account.balance or 0)
        end
        local half = math.floor((width - 3) / 2)
        ui.card(target, 2, 5, half, 4, colors.cyan)
        ui.text(target, 4, 6, "ACCOUNTS", colors.lightGray, colors.gray)
        ui.text(target, 4, 7, tostring(count), colors.white, colors.gray)
        ui.card(target, 3 + half, 5, width - 3 - half, 4, colors.lime)
        ui.text(target, 5 + half, 6, "HELD", colors.lightGray, colors.gray)
        ui.text(target, 5 + half, 7, util.money(held, config.currency),
            colors.white, colors.gray, width - 6 - half)
        ui.text(target, 2, 10, "ACTIVITY", colors.lightGray)
        local maxFeed = math.max(1, height - 12)
        for index = 1, math.min(#activity, maxFeed) do
            local item = activity[index]
            ui.text(target, 2, 10 + index,
                item.time .. "  " .. ui.truncate(item.text, width - 10),
                item.color)
        end
        local scene = ui.scene(target)
        scene:button("stop", width - 10, height, 9, 1, "STOP",
            { background = colors.red })
        local action = scene:wait({ tickRate = 0.5, flash = false })
        blink = not blink
        if action == "stop" or action == "__terminate" then
            if action == "__terminate"
                or ui.confirm(target, "STOP BANK", "Save and shut down?",
                    "STOP", "BACK") then
                running = false
                save()
                return
            end
        end
    end
end

if TEST_MODE then
    return {
        actions = actions, state = state, sessions = sessions,
        adopt = adopt, settle = settle, reconcile = reconcile,
        ledger = ledger,
    }
end

ui.usePhoneStyle(false)
ui.boot(target, "3RD PARTY BANK", "INDEPENDENT ECONOMY")
net.openModems()

if not state.app_id then
    local chosen = chooseBank()
    if not chosen then
        ui.clear(target)
        print("No bank chosen.")
        return
    end
    adopt(chosen)
end

net.host(config.tpb_protocol or "PUMPE_TPB_V1",
    "TPBANK_" .. tostring(state.app_id))
rednet.host(config.ledger_protocol or "PUMPE_LEDGER_V1",
    ledger.hostFor(state.bank_code))
logActivity(state.bank_name .. " online on computer #"
    .. os.getComputerID(), colors.lime)

parallel.waitForAny(bankLoop, ledgerLoop, schedulerLoop, dashboardLoop)
pcall(rednet.unhost, config.tpb_protocol or "PUMPE_TPB_V1")
pcall(rednet.unhost, config.ledger_protocol or "PUMPE_LEDGER_V1")
save()
ui.clear(target)
print("3rd Party Bank Server stopped safely.")
