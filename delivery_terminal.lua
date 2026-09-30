local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- PUMPE DELIVERY TERMINAL
--
-- The other side of the Shop app, new in 10.2. It shows a company every
-- order it has to deliver, moves each one through its stages -- premade ones
-- or the company's own words -- and marks it done, and the buyer's phone
-- hears about every step.
--
-- It sits in a warehouse on an Advanced Computer and rides in a driver's
-- pocket on a Pocket Computer: every screen is laid out from the size it
-- finds.
--
-- And it can become a pickup point. A pickup point is one computer, one
-- chest the customer can open -- the pickup chest -- and any number of
-- lockers: chests behind a wall, on the same networking cable. A courier
-- types the parcel's delivery code, puts it in the pickup chest, and the
-- terminal files it away in an empty locker. The customer types the code
-- from their phone, confirms on their PUMPE that it is them (Foxy
-- Security, 11.1), and the terminal moves their parcel back out into the
-- pickup chest. ComputerCraft can move items between any two inventories on
-- one wired network, so nobody ever has to know which locker is which.
--
-- Since 11.1 a pickup point can sell on the spot as well: whatever is in
-- the lockers that is not somebody's parcel, from a list set up in the
-- Company app, paid like a Service Kiosk sale.

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "11.9.1"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local deviceFile = fs.combine(ROOT, "delivery_terminal_device.dat")
local lockFile = fs.combine(ROOT, "keyboard.lock")
local device = util.loadTable(deviceFile, {})
local running = true
local company
-- 12.0: this terminal's main colour, orange unless its owner chose one.
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end

local STAFF = { tries = 5, lock_ms = 5 * 60 * 1000 }
local SIDES = { "none", "back", "top", "bottom", "left", "right", "front" }

local function saveDevice() util.saveTable(deviceFile, device) end

-- The keyboard lock --------------------------------------------------------------
-- Holding Ctrl+T stops a program and leaves whoever is at the keyboard in
-- the shell. At a pickup point that is a customer, and the shell can empty
-- every locker. So Pickup mode swaps os.pullEvent for the raw version that
-- hands the terminate over as an ordinary event, and leaves a file behind
-- so that Easy Deployment does the same from the first moment of a reboot.
-- Leaving Pickup mode takes the staff PIN and puts both back.

local function terminating(filter)
    local event = table.pack(os.pullEventRaw(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
end

local function lockKeyboard(locked)
    if locked then
        os.pullEvent = os.pullEventRaw
        if not fs.exists(lockFile) then util.writeFile(lockFile, "pickup\n") end
    else
        os.pullEvent = terminating
        if fs.exists(lockFile) then fs.delete(lockFile) end
    end
end

-- The lock exists exactly while this terminal is a pickup point. One left
-- behind by a pickup point it no longer is would take Ctrl+T away from staff
-- at an ordinary board.
if device.mode == "pickup" and device.pickup then
    lockKeyboard(true)
elseif fs.exists(lockFile) then
    lockKeyboard(false)
end

local function request(action, payload, silent)
    payload = payload or {}
    payload.terminal_id = device.terminal_id
    payload.terminal_token = device.terminal_token
    local result, err, code = client:request(action, payload)
    if not result and not silent then
        ui.message(target, "error", "NOT DONE", err or "No answer", 1.6)
    end
    return result, err, code
end

local function money(value) return util.money(value, config.currency) end

-- One list screen for every choice made here -- a company, a chest, an
-- order, a stage, a side -- paged, so a warehouse wired to forty chests
-- still fits a pocket computer.
local function pick(title, subtitle, items, labelOf)
    local page = 1
    while true do
        local width, height = target.getSize()
        local per = math.max(1, math.floor((height - 5) / 2))
        local pages = math.max(1, math.ceil(#items / per))
        page = math.max(1, math.min(page, pages))
        ui.clear(target)
        ui.header(target, title, subtitle
            and ui.truncate(subtitle, width - 3))
        local scene = ui.scene(target)
        for slot = 1, per do
            local index = (page - 1) * per + slot
            if not items[index] then break end
            scene:button("pick:" .. index, 2, 2 + slot * 2, width - 2, 1,
                ui.truncate(labelOf(items[index]), width - 4),
                { background = ui.theme.panel })
        end
        if pages > 1 then
            scene:button("prev", width - 8, height, 3, 1, "^",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 4, height, 3, 1, "v",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return nil end
        if action == "prev" then
            page = page - 1
        elseif action == "next" then
            page = page + 1
        else
            local index = tonumber(action and action:match("^pick:(%d+)$"))
            if index and items[index] then return items[index], index end
        end
    end
end

-- Joining a company --------------------------------------------------------------
-- The same steps a Service Kiosk takes: register as a terminal, have the
-- owner sign in, pick the company. The Bank then shows this terminal that
-- company's orders and nobody else's.

local function register()
    if not device.terminal_id then
        device.name = ui.input(target, "DELIVERY TERMINAL", {
            hint = "Name this terminal", initial = "Warehouse",
            maxLength = 20, allowSpace = true })
        if not device.name then return false end
    end
    -- The Bank hands back the same identity, or a new one if it has
    -- forgotten this terminal.
    local made, err = client:request("KIOSK_REGISTER", {
        terminal_id = device.terminal_id,
        terminal_token = device.terminal_token, name = device.name })
    if not made then
        -- An identity already held is still this terminal's while the Bank
        -- is away.
        if device.terminal_id then return true end
        ui.message(target, "error", "SETUP FAILED", err, 1.6)
        return false
    end
    device.terminal_id = made.terminal_id
    device.terminal_token = made.terminal_token
    device.name = made.name
    saveDevice()
    return true
end

-- The owner's Foxy name and PIN. Used to link the terminal, and as the way
-- back into a pickup point whose staff PIN has been forgotten.
local function ownerSignIn(title)
    local ownerName = ui.input(target, title, {
        hint = "Foxy Account that owns the store", maxLength = 20,
        allowSpace = true })
    if not ownerName then return nil end
    local pin = ui.pin(target, "OWNER PIN", true)
    if not pin then return nil end
    local login, err = request("KIOSK_OWNER_LOGIN",
        { name = ownerName, pin = pin }, true)
    if not login then
        ui.message(target, "error", "SIGN IN FAILED", err, 1.6)
        return nil
    end
    local owned = request("OWNER_COMPANIES",
        { owner_session = login.owner_session }, true)
    return login, owned and owned.companies or {}
end

local function linkCompany()
    local login, companies = ownerSignIn("OWNER SIGN IN")
    if not login then return false end
    local chosen = companies[1]
    if #companies > 1 then
        chosen = pick("WHICH COMPANY?", "This terminal works for",
            companies, function(item) return item.name end)
    end
    if not chosen then
        ui.message(target, "error", "NO COMPANY",
            "Make one on a Service Kiosk first", 2)
        return false
    end
    local linked, linkError = request("LINK_TERMINAL", {
        owner_session = login.owner_session,
        company_id = chosen.company_id }, true)
    if not linked then
        ui.message(target, "error", "LINK FAILED", linkError, 1.6)
        return false
    end
    company = linked.company
    -- Setting up a new terminal: its colour, once.
    if type(ui.hasMainColor) == "function" and not ui.hasMainColor(ROOT) then
        ui.pickMainColor(target, ROOT, "Terminal colour")
    end
    return true
end

-- Chests -----------------------------------------------------------------------

local function inventories()
    local found = {}
    for _, name in ipairs(peripheral.getNames()) do
        local ok, methods = pcall(peripheral.getMethods, name)
        if ok and type(methods) == "table" then
            local has = {}
            for _, method in ipairs(methods) do has[method] = true end
            if has.list and has.pushItems and has.size then
                found[#found + 1] = name
            end
        end
    end
    table.sort(found)
    return found
end

local function hatchName() return device.pickup and device.pickup.hatch end

local function lockers()
    local list = {}
    for _, name in ipairs(inventories()) do
        if name ~= hatchName() then list[#list + 1] = name end
    end
    return list
end

-- How many slots hold something, or nil when the chest cannot be reached.
local function used(name)
    local ok, items = pcall(peripheral.call, name, "list")
    if not ok or type(items) ~= "table" then return nil end
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    return count
end

-- Every stack from one chest into another. Returns how many items moved;
-- the caller checks what is left, because a full chest moves nothing and
-- says so only by leaving the items where they were.
local function moveAll(from, to)
    local ok, items = pcall(peripheral.call, from, "list")
    if not ok or type(items) ~= "table" then return 0 end
    local moved = 0
    for slot in pairs(items) do
        local pushedOk, pushed = pcall(peripheral.call, from, "pushItems",
            to, slot)
        if pushedOk then moved = moved + (tonumber(pushed) or 0) end
    end
    return moved
end

-- The lockers a parcel is already waiting in, as the Bank remembers them.
local function takenLockers()
    local waiting = request("PICKUP_ORDERS", {}, true)
    if not waiting then return nil end
    local taken = {}
    for _, order in ipairs(waiting.orders or {}) do
        if order.locker then taken[order.locker] = order.order_id end
    end
    return taken, waiting.orders or {}
end

-- An empty locker with room for this many stacks, that no parcel is booked
-- into.
local function freeLocker(stacks, taken)
    for _, name in ipairs(lockers()) do
        if not taken[name] and used(name) == 0 then
            local ok, size = pcall(peripheral.call, name, "size")
            if ok and (tonumber(size) or 0) >= stacks then return name end
        end
    end
    return nil
end

local function pulse()
    local side = device.pickup and device.pickup.side
    if not side or side == "none" or type(redstone) ~= "table" then return end
    pcall(redstone.setOutput, side, true)
    sleep(1.5)
    pcall(redstone.setOutput, side, false)
end

-- Orders -----------------------------------------------------------------------

local function addressOf(order)
    local delivery = order.delivery or {}
    if delivery.kind == "pickup" then
        return "Pickup: " .. tostring(delivery.point_name)
    end
    return tostring(delivery.label or "Home") .. " " .. tostring(delivery.x)
        .. " " .. tostring(delivery.y) .. " " .. tostring(delivery.z)
end

local function linesText(order)
    local parts = {}
    for _, line in ipairs(order.lines or {}) do
        parts[#parts + 1] = tostring(line.quantity) .. " x " .. line.name
    end
    return table.concat(parts, ", ")
end

local function nextStage(order, stages)
    local choices = {}
    for index, label in ipairs(stages) do
        choices[#choices + 1] = { stage = index, label = label }
    end
    choices[#choices + 1] = { label = "MY OWN WORDS", custom = true }
    local chosen = pick("NEXT STAGE", "Now: " .. tostring(order.stage),
        choices, function(item) return item.label end)
    if not chosen then return nil end
    if chosen.custom then
        local typed = ui.input(target, "WHAT IS HAPPENING?", {
            hint = "Handed to the courier", maxLength = 28,
            allowSpace = true, minLength = 2 })
        return typed and { label = typed } or nil
    end
    return { stage = chosen.stage }
end

-- In-game hours as "1h 40m".
local function span(hours)
    local minutes = math.max(0, math.floor((tonumber(hours) or 0) * 60))
    if minutes >= 60 then
        return math.floor(minutes / 60) .. "h " .. (minutes % 60) .. "m"
    end
    return minutes .. "m"
end

-- Where an order stands on money, in one line: a buyer who can still
-- cancel (so do not ship it yet), a return waiting on this store, or how
-- it ended.
local function standing(order)
    local asked = order.return_request
    if asked and asked.status == "requested" then
        return "RETURN: " .. tostring(asked.reason), ui.theme.warning
    elseif asked then
        return "Return " .. asked.status, ui.theme.muted
    elseif order.status == "cancelled" then
        return "CANCELLED, refunded", ui.theme.danger
    elseif order.cancellable then
        return "Buyer can cancel for " .. span(order.confirms_in),
            ui.theme.warning
    end
    return nil
end

local function orderScreen(order, stages)
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, order.order_id, ui.truncate(order.stage or "",
            width - 3))
        ui.text(target, 2, 4, ui.truncate(tostring(order.buyer_name) .. "  "
            .. money(order.total), width - 2), ui.theme.ink)
        ui.text(target, 2, 5, ui.truncate(addressOf(order), width - 2),
            ui.theme.accent)
        local said, color = standing(order)
        local row = 6
        if said then
            ui.text(target, 2, row, ui.truncate(said, width - 2), color)
            row = row + 1
        end
        -- 11.1: what the courier types at the pickup point to put it in.
        if order.delivery_code then
            ui.text(target, 2, row, "Delivery code " .. order.delivery_code,
                colors.purple)
            row = row + 1
        end
        row = math.max(row, 7)
        for _, line in ipairs(order.lines or {}) do
            if row > height - 8 then break end
            ui.text(target, 2, row, ui.truncate(line.quantity .. " x "
                .. line.name, width - 2), ui.theme.ink)
            row = row + 1
        end
        local history = order.history or {}
        local last = history[#history]
        if last and row + 1 <= height - 6 then
            ui.text(target, 2, row + 1, ui.truncate(tostring(last.time) .. "  "
                .. tostring(last.label), width - 2), ui.theme.muted)
        end
        local scene = ui.scene(target)
        local open = order.status == "open"
        local returning = order.return_request
            and order.return_request.status == "requested"
        local half = math.floor((width - 3) / 2)
        if returning then
            scene:button("take_back", 2, height - 4, half, 2, "REFUND RETURN",
                { background = ui.theme.success, foreground = colors.black })
            scene:button("decline", 3 + half, height - 4, width - 3 - half, 2,
                "DECLINE", { background = ui.theme.danger })
        else
            scene:button("stage", 2, height - 4, half, 2, "NEXT STAGE",
                { background = ui.theme.accentDark, disabled = not open })
            scene:button("done", 3 + half, height - 4, width - 3 - half, 2,
                "DONE", { background = ui.theme.success,
                    foreground = colors.black, disabled = not open })
        end
        if open then
            scene:button("refund", 2, height - 2, width - 2, 1,
                "CANCEL + REFUND", { background = ui.theme.danger })
        end
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
        -- An order this store cannot fill: every coin goes back to whoever
        -- paid, from wherever it is -- still held, or the owner's account.
        if action == "refund" and open then
            if ui.confirm(target, "CANCEL AND REFUND?", tostring(
                order.buyer_name) .. " gets " .. money(order.total)
                    .. " back and is told.", "REFUND", "KEEP") then
                local note = ui.input(target, "WHY?", { hint = "Optional."
                    .. " Sold out", maxLength = 40, allowSpace = true,
                    minLength = 0 })
                if request("DELIVERY_REFUND",
                    { order_id = order.order_id, note = note }) then
                    ui.message(target, "success", "REFUNDED",
                        tostring(order.buyer_name) .. " has been told", 1.4)
                    return
                end
            end
        elseif action == "take_back" and returning then
            if ui.confirm(target, "REFUND THE RETURN?", "Only once it is back"
                .. " with you. " .. money(order.total) .. " goes back to "
                .. tostring(order.buyer_name) .. ".", "REFUND", "NOT YET") then
                if request("DELIVERY_REFUND",
                    { order_id = order.order_id, why = "return" }) then
                    ui.message(target, "success", "REFUNDED",
                        tostring(order.buyer_name) .. " has been told", 1.4)
                    return
                end
            end
        elseif action == "decline" and returning then
            local reason = ui.input(target, "WHY NOT?", {
                hint = "The buyer is told this", maxLength = 40,
                allowSpace = true, minLength = 2 })
            if reason and request("DELIVERY_RETURN_DECLINE",
                { order_id = order.order_id, reason = reason }) then
                ui.message(target, "info", "DECLINED",
                    tostring(order.buyer_name) .. " has been told", 1.4)
                return
            end
        end
        if action == "stage" and open then
            local chosen = nextStage(order, stages)
            if chosen then
                chosen.order_id = order.order_id
                local moved = request("DELIVERY_STAGE", chosen)
                if moved then order = moved.order end
            end
        elseif action == "done" and open then
            if ui.confirm(target, "DELIVERED?", tostring(order.buyer_name)
                .. " is told it has arrived.", "DONE", "NOT YET") then
                local note = ui.input(target, "A NOTE FOR THEM?", {
                    hint = "Optional. Left by the door", maxLength = 40,
                    allowSpace = true, minLength = 0 })
                local finished = request("DELIVERY_DONE",
                    { order_id = order.order_id, note = note })
                if finished then
                    ui.message(target, "success", "DELIVERED",
                        tostring(order.buyer_name) .. " has been told", 1.4)
                    return
                end
            end
        end
    end
end

-- Pickup mode ---------------------------------------------------------------------

-- Staff get in with the PIN. Five wrong ones lock the door for five
-- minutes, and the count is kept on disk, because rebooting is free.
local function staffPin()
    local pickup = device.pickup
    if util.nowMs() < (pickup.locked_until or 0) then
        ui.message(target, "error", "STAFF LOCKED",
            "Too many wrong PINs. Try again later", 2)
        return false
    end
    local pin = ui.pin(target, "STAFF PIN", true)
    if not pin then return false end
    if util.hashPin(pin) == pickup.pin_hash then
        pickup.misses = 0
        saveDevice()
        return true
    end
    pickup.misses = (pickup.misses or 0) + 1
    if pickup.misses >= STAFF.tries then
        pickup.misses, pickup.locked_until = 0, util.nowMs() + STAFF.lock_ms
    end
    saveDevice()
    ui.message(target, "error", "WRONG PIN", "Staff only", 1.2)
    return false
end

local function staffAccess()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "STAFF ONLY", ui.truncate(device.pickup.name,
        width - 3))
    local scene = ui.scene(target)
    scene:button("pin", 2, 5, width - 2, 2, "STAFF PIN",
        { background = ui.theme.accentDark })
    scene:button("owner", 2, 8, width - 2, 2, "OWNER SIGN IN",
        { background = ui.theme.panel })
    scene:button("back", 1, height, 8, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "pin" then return staffPin() end
    if action == "owner" then
        local login, companies = ownerSignIn("OWNER SIGN IN")
        if not login then return false end
        if not company then
            local known = request("KIOSK_STATE", {}, true)
            company = known and known.company or nil
        end
        for _, owned in ipairs(companies) do
            if company and owned.company_id == company.company_id then
                return true
            end
        end
        ui.message(target, "error", "NOT THE OWNER",
            "That account does not own this point", 1.8)
    end
    return false
end

-- Whatever an earlier visit left in the pickup chest goes into a spare
-- locker, so nobody walks off with a stranger's things. False when the
-- chest cannot be emptied, and a message has been shown.
local function clearHatch()
    local hatch = hatchName()
    local left = used(hatch)
    if not left then
        ui.message(target, "error", "PICKUP IS CLOSED",
            "Ask a member of staff", 2.4)
        return false
    end
    if left > 0 then
        local taken = takenLockers()
        local spare = taken and freeLocker(left, taken)
        if spare then moveAll(hatch, spare) end
        if (used(hatch) or 0) > 0 then
            ui.message(target, "warning", "ASK A MEMBER OF STAFF",
                "The pickup chest is not empty", 2.4)
            return false
        end
    end
    return true
end

-- A courier with a parcel, 11.1. They typed its delivery code rather than
-- a staff PIN: whoever has the parcel has the code, and it opens nothing
-- else. It goes in the pickup chest and the terminal files it in an empty
-- locker; the buyer gets their code.
local function deliverParcel(found, code)
    local hatch = hatchName()
    if not ui.confirm(target, "INTO THE PICKUP CHEST", found.order_id .. ": "
        .. linesText(found) .. ". Put it in, then press STOCKED.", "STOCKED",
        "CANCEL") then
        if (used(hatch) or 0) > 0 then
            ui.message(target, "warning", "TAKE IT BACK OUT",
                "The pickup chest is not empty", 2)
        end
        return
    end
    local stacks = used(hatch)
    if not stacks then
        ui.message(target, "error", "NO PICKUP CHEST",
            "Check its modem and cable", 2)
        return
    elseif stacks == 0 then
        ui.message(target, "warning", "THE CHEST IS EMPTY",
            "Put the parcel in first", 1.6)
        return
    end
    local taken = takenLockers()
    if not taken then
        ui.message(target, "error", "NOT DONE", "The Bank is not answering", 1.6)
        return
    end
    local locker = freeLocker(stacks, taken)
    if not locker then
        ui.message(target, "error", "NO FREE LOCKER",
            "Take it back. Staff need to make room", 2.4)
        return
    end
    moveAll(hatch, locker)
    if (used(hatch) or 0) > 0 then
        moveAll(locker, hatch)
        ui.message(target, "error", "DID NOT FIT",
            "It is back in the pickup chest", 2)
        return
    end
    local stocked, err = request("PICKUP_STOCK",
        { order_id = found.order_id, locker = locker, code = code }, true)
    if not stocked then
        moveAll(locker, hatch)
        ui.message(target, "error", "NOT STOCKED", tostring(err)
            .. ". It is back in the pickup chest", 2.4)
        return
    end
    ui.message(target, "success", "DELIVERED",
        tostring(found.buyer_name) .. " has their code", 1.6)
end

-- For a parcel that could not come out on its own, or a locker that has
-- ended up with something in it that nobody ordered.
local function openLocker()
    local taken = takenLockers() or {}
    local full = {}
    for _, name in ipairs(lockers()) do
        if (used(name) or 0) > 0 then full[#full + 1] = name end
    end
    if #full == 0 then
        ui.message(target, "info", "ALL LOCKERS EMPTY", "Nothing to take out",
            1.4)
        return
    end
    local chosen = pick("EMPTY A LOCKER", "Into the pickup chest", full,
        function(name)
            return (taken[name] and (taken[name] .. "  ") or "(no order)  ")
                .. name
        end)
    if not chosen then return end
    if taken[chosen] and not ui.confirm(target, "A PARCEL IS WAITING",
        "Order " .. taken[chosen] .. " is in there. Its buyer will find"
            .. " nothing when they come.", "EMPTY IT", "KEEP IT") then
        return
    end
    local moved = moveAll(chosen, hatchName())
    ui.message(target, moved > 0 and "success" or "warning",
        moved > 0 and "IN THE PICKUP CHEST" or "NOTHING MOVED",
        moved > 0 and (moved .. " items") or "Is the pickup chest full?", 1.6)
end

-- Lockers that are not holding a parcel, fullest first: stock goes in
-- where there is stock already, so the empty ones stay free for parcels.
local function stockLockers(taken)
    local order = {}
    for _, name in ipairs(lockers()) do
        if not taken[name] then order[#order + 1] = name end
    end
    table.sort(order, function(a, b)
        local left, right = used(a) or 0, used(b) or 0
        if left ~= right then return left > right end
        return a < b
    end)
    return order
end

-- Staff put stock in through the pickup chest too: RESTOCK files it into
-- lockers that are not holding a parcel.
local function restock()
    local hatch = hatchName()
    if (used(hatch) or 0) == 0 then
        return ui.message(target, "info", "NOTHING TO FILE",
            "Put the stock in the pickup chest first", 1.8)
    end
    local taken = takenLockers()
    if not taken then
        return ui.message(target, "error", "NOT DONE",
            "The Bank is not answering", 1.6)
    end
    local moved = 0
    for _, name in ipairs(stockLockers(taken)) do
        if (used(hatch) or 0) == 0 then break end
        moved = moved + moveAll(hatch, name)
    end
    if (used(hatch) or 0) > 0 then
        return ui.message(target, "warning", "NO ROOM FOR ALL OF IT",
            moved .. " filed. The rest is still in the chest", 2.2)
    end
    ui.message(target, "success", "RESTOCKED", moved .. " items filed", 1.4)
end

local function newStaffPin()
    local pin = ui.pin(target, "NEW STAFF PIN", true)
    if not pin then return end
    if ui.pin(target, "REPEAT IT", true) ~= pin then
        ui.message(target, "error", "PINS DO NOT MATCH", "Nothing changed", 1.6)
        return
    end
    device.pickup.pin_hash = util.hashPin(pin)
    device.pickup.misses, device.pickup.locked_until = 0, nil
    saveDevice()
    ui.message(target, "success", "PIN CHANGED", "Tell your staff", 1.2)
end

-- Returns "leave" when Pickup mode is over.
local function staffMenu()
    if not staffAccess() then return "stay" end
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "STAFF", ui.truncate(device.pickup.name, width - 3))
        local scene = ui.scene(target)
        -- Parcels go in with their delivery code at the counter since
        -- 11.1; this is for the pickup point's own stock.
        scene:button("stock", 2, 4, width - 2, 2, "RESTOCK STORE",
            { background = colors.purple })
        scene:button("open", 2, 7, width - 2, 1, "EMPTY A LOCKER",
            { background = ui.theme.panel })
        scene:button("pin", 2, 9, width - 2, 1, "NEW STAFF PIN",
            { background = ui.theme.panel })
        scene:button("leave", 2, 11, width - 2, 2, "LEAVE PICKUP MODE",
            { background = ui.theme.warning, foreground = colors.black })
        scene:button("retire", 2, 14, width - 2, 1, "RETIRE THIS POINT",
            { background = ui.theme.danger })
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return "stay" end
        if action == "stock" then
            restock()
        elseif action == "open" then
            openLocker()
        elseif action == "pin" then
            newStaffPin()
        elseif action == "leave" then
            device.mode = "board"
            saveDevice()
            lockKeyboard(false)
            return "leave"
        elseif action == "retire" then
            local _, waiting = takenLockers()
            if not waiting then
                ui.message(target, "error", "NOT DONE",
                    "The Bank is not answering", 1.6)
            elseif #waiting > 0 then
                ui.message(target, "warning", "PARCELS ARE COMING",
                    #waiting .. " orders are headed here", 2)
            elseif ui.confirm(target, "RETIRE THIS POINT",
                "Buyers stop being offered it.", "RETIRE", "KEEP") then
                if request("PICKUP_REMOVE", {}) then
                    device.pickup, device.mode = nil, "board"
                    saveDevice()
                    lockKeyboard(false)
                    return "leave"
                end
            end
        end
    end
    return "stay"
end

-- Foxy Security, 11.1. The buyer's PUMPE asks them whether this is them
-- at the counter; they answer with their PIN. Nothing comes out until they
-- do, and a "not me" changes their code.
local function waitForBuyer(found)
    local deadline = util.nowMs() + (tonumber(found.expires_in_ms) or 120000)
    while running do
        local width, height = target.getSize()
        local middle = math.max(4, math.floor(height / 2) - 3)
        local seconds = math.max(0, math.floor((deadline - util.nowMs()) / 1000))
        ui.clear(target)
        ui.center(target, 2, ui.truncate(device.pickup.name, width - 2),
            ui.theme.accent)
        ui.center(target, middle, "CHECK YOUR PUMPE", ui.theme.ink)
        ui.center(target, middle + 1, "Confirm with your PIN",
            ui.theme.muted)
        ui.center(target, middle + 3, string.format("%d:%02d",
            math.floor(seconds / 60), seconds % 60), ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("cancel", 3, height - 3, width - 4, 2, "CANCEL",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 2 })
        if action == "cancel" then return "cancelled" end
        local polled = request("PICKUP_WAIT", { order_id = found.order_id },
            true)
        local status = polled and polled.status
        if status == "confirmed" then return "confirmed" end
        if status == "denied" then
            ui.message(target, "error", "NOT CONFIRMED",
                "The buyer says it is not them", 2.4)
            return "denied"
        end
        if status == "expired" or util.nowMs() > deadline + 10000 then
            ui.message(target, "warning", "NOT CONFIRMED",
                "Nobody answered in time", 2.4)
            return "expired"
        end
    end
    return "cancelled"
end

-- A parcel the Bank has let go of: out of its locker, into the pickup
-- chest.
local function giveOut(handed)
    local hatch = hatchName()
    ui.clear(target)
    local _, height = target.getSize()
    ui.center(target, math.floor(height / 2), "ONE MOMENT", ui.theme.ink)
    local moved = moveAll(handed.locker, hatch)
    if moved > 0 then
        pulse()
        return ui.message(target, "success", "TAKE YOUR PARCEL",
            "It is in the pickup chest. Thank you", 3)
    end
    return ui.message(target, "warning", "ASK A MEMBER OF STAFF",
        "Your parcel is in " .. ui.truncate(tostring(handed.locker), 24), 4)
end

local function collectParcel(found)
    if not found.confirmed and waitForBuyer(found) ~= "confirmed" then
        return
    end
    if not clearHatch() then return end
    local handed, err = request("PICKUP_RELEASE",
        { order_id = found.order_id }, true)
    if not handed then
        return ui.message(target, "error", "NOT HERE", err, 2)
    end
    return giveOut(handed)
end

-- One box for everybody with a code: a buyer's collects, a courier's
-- delivers.
local function enterCode()
    local code = ui.input(target, "YOUR CODE", {
        hint = "Six digits, Shop app or courier", mode = "integer",
        maxLength = 6, minLength = 6 })
    if not code then return end
    if not used(hatchName()) then
        return ui.message(target, "error", "PICKUP IS CLOSED",
            "Ask a member of staff", 2.4)
    end
    local found, err = request("PICKUP_CODE", { code = code }, true)
    if not found then
        return ui.message(target, "error", "NOT HERE", err, 2)
    end
    if found.kind == "deliver" then return deliverParcel(found, code) end
    return collectParcel(found)
end

-- The Store, 11.1 ------------------------------------------------------------------
-- A pickup point that sells things on the spot. The list comes from the
-- Company app; what is in stock is whatever is in the lockers that is not
-- somebody's parcel. Paid the way a Service Kiosk is paid -- Foxy Pay to
-- the nearest PUMPE, or a code for another bank -- and then it comes out
-- into the pickup chest.

-- How many of an item the store lockers hold.
local function inStock(item, taken)
    local total = 0
    for _, name in ipairs(lockers()) do
        if not taken[name] then
            local ok, items = pcall(peripheral.call, name, "list")
            for _, stack in pairs(ok and type(items) == "table" and items or {}) do
                if stack.name == item then total = total + (stack.count or 0) end
            end
        end
    end
    return total
end

-- Moves up to `count` of an item out of the store lockers.
local function dispense(item, count, taken)
    local moved = 0
    for _, name in ipairs(lockers()) do
        if moved >= count then break end
        if not taken[name] then
            local ok, items = pcall(peripheral.call, name, "list")
            for slot, stack in pairs(ok and type(items) == "table" and items or {}) do
                if moved < count and stack.name == item then
                    local pushedOk, pushed = pcall(peripheral.call, name,
                        "pushItems", hatchName(), slot, count - moved)
                    if pushedOk then moved = moved + (tonumber(pushed) or 0) end
                end
            end
        end
    end
    return moved
end

local function payWithFoxy(offer)
    local position = net.locate(2)
    if not position then
        ui.message(target, "error", "NO GPS FIX",
            "Foxy Pay needs GPS anchors here", 2.2)
        return false
    end
    local created, err = request("PROXIMITY_OFFER", { amount = offer.price,
        items = { { name = offer.name, price = offer.price, quantity = 1 } },
        description = offer.name, position = position }, true)
    if not created then
        ui.message(target, "error", "NOT DONE", err, 1.8)
        return false
    end
    local sale = created.offer
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "FOXY PAY", money(offer.price), util.formatClock())
        ui.center(target, 7, sale.status == "nobody_nearby" and "NOBODY NEARBY"
            or ui.truncate(tostring(sale.target_name or "Finding you"),
                width - 2), ui.theme.ink)
        ui.center(target, 9, "Confirm on your PUMPE", ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 3, width - 2, 2, "CANCEL",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 1 })
        if action == "cancel" then
            request("PROXIMITY_CANCEL", { offer_id = sale.offer_id }, true)
            return false
        end
        local polled = request("PROXIMITY_STATUS",
            { offer_id = sale.offer_id }, true)
        if polled then sale = polled.offer end
        if sale.status == "paid" then return true, sale.target_name end
        if sale.status == "expired" or sale.status == "cancelled" then
            ui.message(target, "warning", "NOT PAID", "Nothing was taken", 1.6)
            return false
        end
    end
    return false
end

local function payWithCode(offer)
    local created, err = request("CREATE_PAY_CODE", { amount = offer.price,
        items = { { name = offer.name, price = offer.price, quantity = 1 } },
        purchase_type = "one_time", description = offer.name }, true)
    if not created then
        ui.message(target, "error", "NOT DONE", err, 1.8)
        return false
    end
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PAY WITH A CODE", money(offer.price),
            util.formatClock())
        ui.center(target, 7, "Type it in your bank app", ui.theme.muted)
        ui.center(target, 9, created.code:sub(1, 3) .. " "
            .. created.code:sub(4, 6), ui.theme.ink)
        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 3, width - 2, 2, "CANCEL",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 1 })
        if action == "cancel" then
            request("CANCEL_CODE", { code = created.code }, true)
            return false
        end
        local status = request("CODE_STATUS", { code = created.code }, true)
        if status and status.status == "paid" then
            return true, status.payer
        end
        if status and (status.status == "expired"
            or status.status == "cancelled") then
            ui.message(target, "warning", "NOT PAID", "Nothing was taken", 1.6)
            return false
        end
    end
    return false
end

-- 12.0 Final: the price the Bank works out -- the store's sale, and a
-- discount code if there is one -- the same way the Shop app's is.
local function priceOf(offer, code)
    return request("STORE_PRICE", { price = offer.price, code = code }, true)
end

-- What the list shows before anybody types a code.
local function salePrice(price, sale)
    if (sale or 0) <= 0 then return price end
    return util.roundMoney(price - util.roundMoney(price * sale / 100))
end

local function buyOffer(offer)
    if not clearHatch() then return end
    local taken = takenLockers()
    if not taken then
        return ui.message(target, "error", "NOT DONE",
            "The Bank is not answering", 1.6)
    end
    if inStock(offer.item, taken) < offer.count then
        return ui.message(target, "warning", "SOLD OUT", offer.name, 1.6)
    end
    local priced = priceOf(offer) or { total = offer.price, discount = 0 }
    local promo, method
    while not method do
        local was = (priced.discount or 0) > 0 and ("  was " .. money(offer.price)) or ""
        local how = pick(ui.truncate(string.upper(offer.name), 20),
            offer.count .. " for " .. money(priced.total) .. was, {
                { id = "foxy", label = "PAY WITH FOXY PAY" },
                { id = "code", label = "ANOTHER BANK: CODE" },
                { id = "promo", label = promo and ("DISCOUNT: " .. promo)
                    or "I HAVE A DISCOUNT CODE" } },
            function(item) return item.label end)
        if not how then return end
        if how.id == "promo" then
            local typed = ui.input(target, "DISCOUNT CODE", {
                hint = "The store's code", mode = "text", maxLength = 16 })
            if typed then
                local withCode, err = priceOf(offer, typed)
                if withCode then
                    priced, promo = withCode, withCode.promo
                    ui.message(target, "success", "CODE TAKEN",
                        "Now " .. money(withCode.total), 1.4)
                else
                    ui.message(target, "error", "CODE NOT TAKEN", err, 1.8)
                end
            end
        else
            method = how.id
        end
    end
    local charged = { name = offer.name, price = priced.total }
    local paid, payer
    if priced.total <= 0 then
        -- A code that makes it free: nothing to pay, and nothing moves.
        paid, payer = true, "A customer"
    elseif method == "foxy" then
        paid, payer = payWithFoxy(charged)
    else
        paid, payer = payWithCode(charged)
    end
    if not paid then return end
    if promo then request("STORE_PROMO_USED", { code = promo }, true) end
    ui.clear(target)
    local _, height = target.getSize()
    ui.center(target, math.floor(height / 2), "ONE MOMENT", ui.theme.ink)
    local moved = dispense(offer.item, offer.count, takenLockers() or taken)
    if moved > 0 then pulse() end
    if moved >= offer.count then
        return ui.message(target, "success", "TAKE YOUR ITEMS",
            "In the pickup chest. Thank you", 3)
    end
    -- Paid, and the lockers came up short: somebody emptied one by hand
    -- between the check and now. The owner is told who is owed what.
    local owed = util.roundMoney(priced.total * (offer.count - moved)
        / offer.count)
    request("STORE_SHORT", { name = offer.name, count = offer.count,
        got = moved, owed = owed, payer = payer }, true)
    return ui.message(target, "warning", "ASK A MEMBER OF STAFF",
        "Only " .. moved .. " came out. The owner knows you are owed "
            .. money(owed), 4)
end

-- Me, 12.0 Final --------------------------------------------------------------------
-- Somebody types their name; their PUMPE asks whether it is them, and they
-- say yes with their PIN. Then this counter shows everything of theirs that
-- is coming here or waiting here. What has arrived comes out with a tap;
-- what is on its way can be made ready, so their code opens it without
-- asking again when it comes. Walk away and it signs itself out.

local function waitForLookup(asked)
    local deadline = util.nowMs() + (tonumber(asked.expires_in_ms) or 120000)
    while running do
        local width, height = target.getSize()
        local middle = math.max(5, math.floor(height / 2) - 3)
        local seconds = math.max(0, math.floor((deadline - util.nowMs()) / 1000))
        ui.clear(target)
        ui.header(target, ui.truncate(device.pickup.name, width - 3),
            ui.truncate(tostring(asked.name), width - 3))
        ui.center(target, middle, "CHECK YOUR PUMPE", ui.theme.ink)
        ui.center(target, middle + 1, "Say yes with your PIN", ui.theme.muted)
        ui.center(target, middle + 3, string.format("%d:%02d",
            math.floor(seconds / 60), seconds % 60), ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("cancel", 3, height - 3, width - 4, 2, "CANCEL",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 2 })
        if action == "cancel" then
            request("PICKUP_ME_END", {}, true)
            return nil
        end
        local polled = request("PICKUP_ME_WAIT", { request_id = asked.request_id }, true)
        local status = polled and polled.status
        if status == "confirmed" then
            return { token = polled.me_token, name = polled.name,
                orders = polled.orders or {} }
        elseif status == "denied" then
            ui.message(target, "error", "NOT CONFIRMED",
                "They said it is not them", 2.4)
            return nil
        elseif status == "expired" or util.nowMs() > deadline + 10000 then
            ui.message(target, "warning", "NOT CONFIRMED",
                "Nobody answered in time", 2.4)
            return nil
        end
    end
    return nil
end

local function signIn()
    local name = ui.input(target, "YOUR NAME", {
        hint = "As on your PUMPE", mode = "text", allowSpace = true,
        maxLength = 20, minLength = 2 })
    if not name then return nil end
    local asked, err = request("PICKUP_ME_ASK", { name = name }, true)
    if not asked then
        ui.message(target, "error", "NOT ASKED", err, 2)
        return nil
    end
    return waitForLookup(asked)
end

local function refreshMe(me)
    local listed = request("PICKUP_ME_ORDERS", { me_token = me.token }, true)
    if not listed then return nil end
    me.orders = listed.orders or {}
    return me
end

-- One of theirs, tapped: out it comes, or ready for when it does.
local function openMine(me, entry)
    local what = ui.truncate(tostring(entry.company_name) .. ": "
        .. linesText(entry), 60)
    if entry.arrived then
        if not ui.confirm(target, "PICK IT UP", what, "PICK UP", "BACK") then
            return me
        end
        if not clearHatch() then return me end
        local handed, err = request("PICKUP_ME_RELEASE",
            { order_id = entry.order_id, me_token = me.token }, true)
        if not handed then
            ui.message(target, "error", "NOT HERE", err, 2)
            return refreshMe(me)
        end
        giveOut(handed)
        return refreshMe(me)
    end
    if entry.ready then
        ui.message(target, "info", "READY FOR IT",
            "When it comes, your code opens it without asking", 2.4)
        return me
    end
    if not ui.confirm(target, "GET READY FOR IT", what .. ". When it comes, your"
        .. " code opens it without asking you again.", "READY", "BACK") then
        return me
    end
    local done, err = request("PICKUP_ME_READY",
        { order_id = entry.order_id, me_token = me.token }, true)
    ui.message(target, done and "success" or "error",
        done and "READY" or "NOT DONE", done and "We will have it waiting" or err, 1.6)
    return refreshMe(me)
end

-- The counter, 12.0 Final: Collect, Store and Me along the bottom, and
-- STAFF under them.
local PICKUP_TABS = { { id = "code", label = "Collect" },
    { id = "store", label = "Store" }, { id = "me", label = "Me" } }

-- Pickup points update themselves since 11.1, when nobody has touched them
-- for a minute -- from the counter screen, so nobody can be halfway through
-- anything when it restarts.
local lastTouch = util.nowMs()

local function pickupScreen()
    local store = request("PICKUP_STORE", {}, true)
    local deals = request("STORE_DEALS", {}, true) or {}
    local tab, page, me = "code", 1, nil
    local function signOut()
        if me then request("PICKUP_ME_END", {}, true) end
        me = nil
    end
    while running and device.mode == "pickup" do
        local width, height = target.getSize()
        local bottom = ui.contentBottom(target)
        local open = store and store.open and #(store.offers or {}) > 0
        ui.clear(target)
        local subtitle = tab == "store" and ((deals.sale or 0) > 0
            and (deals.sale .. "% off everything") or "Buy it here, take it now")
            or tab == "me" and (me and ("Hi, " .. me.name) or "Your orders here")
            or "Pickup point"
        ui.header(target, ui.truncate(device.pickup.name, width - 9),
            ui.truncate(subtitle, width - 3), util.formatClock())
        local scene = ui.scene(target)
        local taken, offers
        if tab == "code" then
            ui.text(target, 2, 5, "COLLECT OR DELIVER", ui.theme.muted)
            ui.wrappedText(target, 2, 6, "Your pickup code from the Shop app,"
                .. " or a courier's delivery code.", width - 2, 2, ui.theme.ink)
            scene:button("code", 2, 9, width - 2, 3, "ENTER CODE",
                { background = ui.theme.accent, foreground = ui.theme.accentInk,
                  shadow = true })
            if bottom >= 14 then
                ui.wrappedText(target, 2, 13, "No code? Me shows your orders"
                    .. " here by your name.", width - 2, 2, ui.theme.muted)
            end
        elseif tab == "store" then
            offers = open and store.offers or {}
            taken = open and takenLockers() or nil
            if not open or not taken then
                ui.wrappedText(target, 2, 5, not open and "The store here is"
                    .. " closed. Parcels still come and go on Collect."
                    or "The Bank is not answering.", width - 2, 3, ui.theme.muted)
                offers = {}
            end
            local per = math.max(1, math.floor((bottom - 3) / 3))
            local pages = math.max(1, math.ceil(#offers / per))
            page = math.max(1, math.min(page, pages))
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local offer = offers[index]
                if not offer then break end
                local left = math.floor(inStock(offer.item, taken) / offer.count)
                local now = salePrice(offer.price, deals.sale)
                local price = money(now) .. (now < offer.price
                    and ("  was " .. money(offer.price)) or "")
                scene:button("offer:" .. index, 2, 1 + slot * 3, width - 2, 2,
                    ui.truncate(offer.name .. "  " .. price, width - 4) .. "\n"
                        .. ui.truncate(left > 0 and (offer.count .. " each, "
                            .. left .. " left") or "Sold out", width - 4),
                    { background = left > 0 and ui.theme.accentDark
                        or ui.theme.panel, disabled = left <= 0 })
            end
            if pages > 1 then
                scene:button("prev", 1, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", 5, height, 3, 1, "v",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
        elseif not me then
            ui.text(target, 2, 5, "YOUR ORDERS HERE", ui.theme.muted)
            ui.wrappedText(target, 2, 6, "Type your name and say yes on your"
                .. " PUMPE. You will see what is coming here and what is"
                .. " waiting, and take it.", width - 2, 3, ui.theme.ink)
            scene:button("signin", 2, 10, width - 2, 3, "TYPE YOUR NAME",
                { background = ui.theme.accent, foreground = ui.theme.accentInk,
                  shadow = true })
        else
            local per = math.max(1, math.floor((bottom - 3) / 3))
            if #me.orders == 0 then
                ui.wrappedText(target, 2, 5, "Nothing of yours is coming here"
                    .. " or waiting here.", width - 2, 2, ui.theme.muted)
            end
            for slot = 1, math.min(per, #me.orders) do
                local entry = me.orders[slot]
                local status = entry.arrived and "HERE: TAP TO TAKE"
                    or entry.ready and "ON ITS WAY, READY"
                    or ("ON ITS WAY: " .. tostring(entry.stage or "Packing"))
                scene:button("mine:" .. slot, 2, 1 + slot * 3, width - 2, 2,
                    ui.truncate(tostring(entry.company_name) .. "  "
                        .. linesText(entry), width - 4) .. "\n"
                        .. ui.truncate(status, width - 4),
                    { background = entry.arrived and ui.theme.success
                        or ui.theme.panel,
                      foreground = entry.arrived and colors.black or colors.white })
            end
            scene:button("signout", 1, height, 8, 1, "< DONE",
                { background = ui.theme.panel })
        end
        scene:button("staff", width - 6, height, 7, 1, "STAFF",
            { background = ui.theme.panel })
        ui.tabBar(scene, target, PICKUP_TABS, tab, nil, { home = false })
        -- "__terminate" lands here now, and like every other stray event
        -- it just redraws the screen.
        local action = scene:wait({ tickRate = 20 })
        if action == "__tick" then
            store = request("PICKUP_STORE", {}, true) or store
            deals = request("STORE_DEALS", {}, true) or deals
            if util.nowMs() - lastTouch >= 60000 then
                -- Walked away: Me signs itself out, and back to the start.
                if me then signOut() end
                tab = "code"
                net.autoUpdate(config, "delivery", ROOT, client, {
                    programVersion = PROGRAM_VERSION,
                    onProgress = function()
                        ui.clear(target)
                        ui.center(target, math.floor(height / 2),
                            "UPDATING, ONE MOMENT", ui.theme.ink)
                    end })
            end
        end
        local picked = (action or ""):match("^tab:(.+)$")
        if picked then
            tab, page = picked, 1
        elseif action == "staff" then
            signOut()
            if staffMenu() == "leave" then return end
        elseif action == "code" then
            enterCode()
        elseif action == "prev" then
            page = page - 1
        elseif action == "next" then
            page = page + 1
        elseif action == "signin" then
            me = signIn()
        elseif action == "signout" then
            signOut()
        else
            local index = tonumber(action and action:match("^offer:(%d+)$"))
            local mine = tonumber(action and action:match("^mine:(%d+)$"))
            if index and offers and offers[index] then
                buyOffer(offers[index])
            elseif mine and me and me.orders[mine] then
                me = openMine(me, me.orders[mine])
                if not me then
                    ui.message(target, "info", "SIGNED OUT",
                        "Type your name again", 1.4)
                end
            end
        end
        if action ~= "__tick" and action ~= "__terminate" then
            lastTouch = util.nowMs()
            store = request("PICKUP_STORE", {}, true) or store
        end
    end
end

-- An error inside Pickup mode must not end the program: the shell is what
-- the lock is there to keep customers out of. It pauses, and staff can
-- still leave with the PIN.
local function pickupMode()
    lockKeyboard(true)
    while running and device.mode == "pickup" and device.pickup do
        local ok, err = pcall(pickupScreen)
        if ok then return end
        pcall(ui.message, target, "error", "PICKUP PAUSED",
            ui.truncate(tostring(err), 60), 3)
        local pin = ui.pin(target, "STAFF PIN TO LEAVE", true)
        if pin and util.hashPin(pin) == device.pickup.pin_hash then
            device.mode = "board"
            saveDevice()
            lockKeyboard(false)
        end
    end
end

-- Becoming a pickup point: a name buyers choose at checkout, a staff PIN,
-- which chest customers open, and whether to pulse redstone -- a door, a
-- lamp, a bell -- when a parcel comes out.
local function setupPickup()
    local found = inventories()
    if #found < 2 then
        ui.message(target, "error", "ATTACH CHESTS FIRST",
            "One for customers, and lockers behind a wall", 2.4)
        return
    end
    local name = ui.input(target, "PICKUP POINT NAME", {
        hint = "What buyers choose", maxLength = 20, allowSpace = true,
        minLength = 2, initial = device.pickup and device.pickup.name })
    if not name then return end
    local pin = ui.pin(target, "NEW STAFF PIN", true)
    if not pin then return end
    if ui.pin(target, "REPEAT IT", true) ~= pin then
        ui.message(target, "error", "PINS DO NOT MATCH", "Nothing changed", 1.6)
        return
    end
    local hatch = pick("PICKUP CHEST", "Customers open this one", found,
        function(item) return item end)
    if not hatch then return end
    local side = pick("REDSTONE", "When a parcel comes out",
        SIDES, function(item)
            return item == "none" and "NO REDSTONE" or string.upper(item)
        end)
    if not side then return end
    local position = net.locate(2) or {}
    local registered = request("PICKUP_REGISTER", { name = name,
        x = position.x, y = position.y, z = position.z })
    if not registered then return end
    device.pickup = { name = name, pin_hash = util.hashPin(pin),
        hatch = hatch, side = side, misses = 0 }
    device.mode = "pickup"
    saveDevice()
    ui.message(target, "success", "PICKUP POINT READY",
        (#found - 1) .. " lockers. Leaving takes the PIN", 2)
end

-- The board ------------------------------------------------------------------------
-- 12.0: three tabs -- Open, Done and (12.0 Final) Setup, which has the
-- pickup point and the terminal itself. Pickup mode faces the public, so it
-- has its own tabs, for customers.

local function bar(scene, spec)
    ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
end

-- A tap a page does not handle itself: a tab, or closing.
local function passOn(action)
    if action == "__terminate" then running = false return "stop" end
    if action and action:match("^tab:") then return action end
    return nil
end

-- One list of orders, for Open or Done. `open` picks which.
local function ordersPage(open)
    return function(spec)
        local offset = 0
        while running and device.mode ~= "pickup" do
            local width = target.getSize()
            local listed = request("DELIVERY_ORDERS", {}, true)
            local orders = {}
            for _, order in ipairs(listed and listed.orders or {}) do
                local returning = order.return_request
                    and order.return_request.status == "requested"
                if (order.status == "open") == open or (not open and returning) then
                    orders[#orders + 1] = order
                end
            end
            ui.clear(target)
            ui.header(target, open and "DELIVERIES" or "DONE",
                ui.truncate(#orders .. (open and " open  " or "  ")
                    .. tostring(company and company.name or device.name or ""),
                    width - 3), util.formatClock())
            local scene = ui.scene(target)
            local rows = math.max(1, math.floor((ui.contentBottom(target) - 3) / 2))
            offset = math.max(0, math.min(offset, #orders - rows))
            for slot = 1, rows do
                local order = orders[offset + slot]
                if not order then break end
                local y = 2 + slot * 2
                local done = order.status ~= "open"
                local pickup = (order.delivery or {}).kind == "pickup"
                local returning = order.return_request
                    and order.return_request.status == "requested"
                scene:button("order:" .. (offset + slot), 2, y, width - 2, 1,
                    ui.truncate(order.order_id .. "  "
                        .. tostring(order.buyer_name), width - 4),
                    { background = returning and ui.theme.warning
                        or done and ui.theme.panel
                        or (pickup and colors.purple or ui.theme.accentDark),
                      foreground = returning and colors.black or nil })
                ui.text(target, 3, y + 1, ui.truncate((returning and "Return asked. "
                    or done and "Done. " or "") .. tostring(order.stage) .. "  "
                    .. addressOf(order), width - 4), ui.theme.muted)
            end
            if #orders == 0 then
                ui.wrappedText(target, 2, 5, not listed and "The Bank is not answering."
                    or open and ("Nothing to deliver. Orders land here the moment"
                        .. " somebody checks out in the Shop app.")
                    or "Nothing delivered yet.", width - 2, 4, ui.theme.muted)
            end
            if #orders > rows then
                scene:button("up", width - 8, 2, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 4, 2, 3, 1, "v",
                    { background = ui.theme.panel,
                        disabled = offset + rows >= #orders })
            end
            bar(scene, spec)
            -- Every few seconds the board asks again, so an order placed a
            -- moment ago is on screen without anybody touching anything.
            local action = scene:wait({ tickRate = 5 })
            local passed = passOn(action)
            if passed == "stop" then return nil end
            if passed then return passed end
            if action == "up" then
                offset = math.max(0, offset - rows)
            elseif action == "down" then
                offset = offset + rows
            else
                local index = tonumber(action and action:match("^order:(%d+)$"))
                if index and orders[index] then
                    orderScreen(orders[index], listed.stages or {})
                end
            end
        end
    end
end

local function setupPage(spec)
    while running and device.mode ~= "pickup" do
        local width = target.getSize()
        ui.clear(target)
        ui.header(target, "SETUP", ui.truncate(device.pickup
            and ("Pickup point: " .. device.pickup.name) or "No pickup point",
            width - 3), util.formatClock())
        local scene = ui.scene(target)
        if device.pickup then
            scene:button("start", 2, 5, width - 2, 3, "START PICKUP MODE",
                { background = ui.theme.accent, foreground = ui.theme.accentInk,
                  shadow = true })
            scene:button("setup", 2, 10, width - 2, 1, "SET IT UP AGAIN",
                { background = ui.theme.panel })
        else
            ui.wrappedText(target, 2, 5, "This terminal can be a pickup point:"
                .. " one chest for customers and lockers behind a wall, on one"
                .. " cable.", width - 2, 4, ui.theme.muted)
            scene:button("setup", 2, 10, width - 2, 3, "SET UP A PICKUP POINT",
                { background = ui.theme.accent, foreground = ui.theme.accentInk })
        end
        -- The terminal itself: three across on a computer, one under the
        -- other on anything narrower.
        local controls = { { "link", "LINK COMPANY", ui.theme.panel },
            { "color", "MAIN COLOUR", ui.theme.panel },
            { "close", "CLOSE", ui.theme.danger } }
        local wide = width >= 40
        local third = math.floor((width - 4) / 3)
        for index, entry in ipairs(controls) do
            local x = wide and 2 + (index - 1) * (third + 1) or 2
            local w = wide and (index == 3 and width - x or third) or width - 2
            local y = wide and 14 or 12 + index * 2
            if y + (wide and 1 or 0) <= ui.contentBottom(target) then
                scene:button(entry[1], x, y, w, wide and 2 or 1, entry[2],
                    { background = entry[3], foreground = ui.inkOn(entry[3]) })
            end
        end
        bar(scene, spec)
        local action = scene:wait()
        local passed = passOn(action)
        if passed == "stop" then return nil end
        if passed then return passed end
        if action == "start" then
            device.mode = "pickup"
            saveDevice()
        elseif action == "setup" then
            setupPickup()
        elseif action == "link" then
            linkCompany()
        elseif action == "color" then
            ui.pickMainColor(target, ROOT, "Terminal colour")
        elseif action == "close" and ui.confirm(target, "CLOSE",
            "Stop the Delivery Terminal?", "CLOSE", "BACK") then
            running = false
            return nil
        end
    end
end

local function board()
    while running do
        if device.mode == "pickup" and device.pickup then
            pickupMode()
        else
            ui.runTabs({
                target = target, title = "Deliveries", subtitle = "Everything here",
                list = { { id = "open", label = "Open" }, { id = "done", label = "Done" },
                    { id = "setup", label = "Setup" } },
                pages = { open = ordersPage(true), done = ordersPage(false),
                    setup = setupPage },
                running = function() return running and device.mode ~= "pickup" end,
            })
        end
    end
end

if rawget(_G, "PUMPE_TEST_MODE") == true then
    return {
        inventories = inventories, moveAll = moveAll, used = used,
        freeLocker = freeLocker, lockKeyboard = lockKeyboard,
        inStock = inStock, dispense = dispense, stockLockers = stockLockers,
        device = device,
    }
end

local function updateLoop()
    while running do
        -- Never with a customer at the counter: the board updates, a pickup
        -- point waits for staff to take it out of Pickup mode.
        if device.mode ~= "pickup" then
            net.autoUpdate(config, "delivery", ROOT, client,
                { programVersion = PROGRAM_VERSION })
        end
        sleep(30)
    end
end

ui.boot(target, "PUMPE DELIVERY", "DELIVERY TERMINAL v" .. config.version)
net.autoUpdate(config, "delivery", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
if not register() then
    ui.clear(target)
    print("Delivery Terminal not set up.")
    return
end
local known = client:request("KIOSK_STATE", {
    terminal_id = device.terminal_id, terminal_token = device.terminal_token })
company = known and known.company or nil
-- A pickup point goes straight back to the counter, Bank or no Bank.
-- Stopping here would hand the shell to whoever is standing at it.
if not (device.mode == "pickup" and device.pickup) then
    if not known then
        ui.message(target, "error", "BANK OFFLINE", "Try again soon", 2)
        ui.clear(target)
        print("Delivery Terminal could not reach the Bank.")
        return
    end
    if not company and not linkCompany() then
        ui.clear(target)
        print("Delivery Terminal needs a company.")
        return
    end
end
parallel.waitForAny(board, updateLoop)
ui.clear(target)
print("PUMPE Delivery Terminal stopped.")
