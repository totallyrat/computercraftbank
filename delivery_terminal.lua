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
-- lockers: chests behind a wall, on the same networking cable. Staff put a
-- parcel in the pickup chest and the terminal files it away in an empty
-- locker. The customer types the code from their phone and the terminal
-- moves their parcel back out into the pickup chest. ComputerCraft can move
-- items between any two inventories on one wired network, so nobody ever
-- has to know which locker is which.

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "10.2.0"
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
        local row = 7
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
        local half = math.floor((width - 3) / 2)
        scene:button("stage", 2, height - 4, half, 2, "NEXT STAGE",
            { background = ui.theme.accentDark, disabled = not open })
        scene:button("done", 3 + half, height - 4, width - 3 - half, 2,
            "DONE", { background = ui.theme.success,
                foreground = colors.black, disabled = not open })
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
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

-- Staff put a parcel in the pickup chest; the terminal files it in an
-- empty locker and tells the Bank which, and the buyer gets their code.
local function stockParcel()
    local hatch = hatchName()
    local taken, waiting = takenLockers()
    if not taken then
        ui.message(target, "error", "NOT DONE", "The Bank is not answering", 1.6)
        return
    end
    local unstocked = {}
    for _, order in ipairs(waiting) do
        if not order.locker then unstocked[#unstocked + 1] = order end
    end
    if #unstocked == 0 then
        ui.message(target, "info", "NOTHING TO STOCK",
            "No parcels are on their way here", 1.6)
        return
    end
    local order = pick("STOCK A PARCEL", #unstocked .. " on the way here",
        unstocked, function(item)
            return item.order_id .. "  " .. tostring(item.buyer_name)
        end)
    if not order then return end
    if not ui.confirm(target, "INTO THE PICKUP CHEST", linesText(order)
        .. ". Put it in the pickup chest, then press STOCKED.", "STOCKED",
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
    local locker = freeLocker(stacks, taken)
    if not locker then
        ui.message(target, "error", "NO FREE LOCKER",
            "Add a chest, or empty one", 2)
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
        { order_id = order.order_id, locker = locker }, true)
    if not stocked then
        moveAll(locker, hatch)
        ui.message(target, "error", "NOT STOCKED", tostring(err)
            .. ". It is back in the pickup chest", 2.4)
        return
    end
    ui.message(target, "success", "STOCKED",
        tostring(order.buyer_name) .. " has their code", 1.4)
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
        scene:button("stock", 2, 4, width - 2, 2, "STOCK A PARCEL",
            { background = ui.theme.accentDark })
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
            stockParcel()
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

-- A customer at the counter with a code. Whatever an earlier visit left in
-- the pickup chest goes into a spare locker first, so nobody walks off with
-- a stranger's things; then the Bank checks the code and the parcel comes
-- out.
local function collect(code)
    local hatch = hatchName()
    local left = used(hatch)
    if not left then
        return ui.message(target, "error", "PICKUP IS CLOSED",
            "Ask a member of staff", 2.4)
    end
    if left > 0 then
        local taken = takenLockers()
        local spare = taken and freeLocker(left, taken)
        if spare then moveAll(hatch, spare) end
        if (used(hatch) or 0) > 0 then
            return ui.message(target, "warning", "ASK A MEMBER OF STAFF",
                "The pickup chest is not empty", 2.4)
        end
    end
    local handed, err = request("PICKUP_COLLECT", { code = code }, true)
    if not handed then
        return ui.message(target, "error", "NOT HERE", err, 2)
    end
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

local function pickupScreen()
    while running and device.mode == "pickup" do
        local width, height = target.getSize()
        ui.clear(target)
        local middle = math.max(4, math.floor(height / 2) - 3)
        ui.center(target, 2, ui.truncate(device.pickup.name, width - 2),
            ui.theme.accent)
        ui.center(target, middle, "COLLECT YOUR ORDER", ui.theme.ink)
        ui.center(target, middle + 1, "Type your Shop app code",
            ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("code", 3, middle + 3, width - 4, 3, "ENTER CODE",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("staff", width - 7, height, 7, 1, "STAFF",
            { background = ui.theme.panel })
        -- "__terminate" lands here now, and like every other stray event
        -- it just redraws the screen.
        local action = scene:wait()
        if action == "staff" then
            if staffMenu() == "leave" then return end
        elseif action == "code" then
            local code = ui.input(target, "YOUR CODE", {
                hint = "Six digits, from the Shop app", mode = "integer",
                maxLength = 6, minLength = 6 })
            if code then collect(code) end
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

local function pickupButton()
    if not device.pickup then return setupPickup() end
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "PICKUP POINT", ui.truncate(device.pickup.name,
        width - 3))
    local scene = ui.scene(target)
    scene:button("start", 2, 5, width - 2, 3, "START PICKUP MODE",
        { background = ui.theme.accentDark, shadow = true })
    scene:button("setup", 2, 10, width - 2, 1, "SET IT UP AGAIN",
        { background = ui.theme.panel })
    scene:button("back", 1, height, 8, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "start" then
        device.mode = "pickup"
        saveDevice()
    elseif action == "setup" then
        setupPickup()
    end
end

-- The board ------------------------------------------------------------------------

local function board()
    local offset = 0
    while running do
        if device.mode == "pickup" and device.pickup then
            pickupMode()
        else
            local width, height = target.getSize()
            local listed = request("DELIVERY_ORDERS", {}, true)
            local orders = listed and listed.orders or {}
            local open = 0
            for _, order in ipairs(orders) do
                if order.status == "open" then open = open + 1 end
            end
            ui.clear(target)
            ui.header(target, "DELIVERIES", ui.truncate(open .. " open  "
                .. tostring(company and company.name or device.name or ""),
                width - 3), util.formatClock())
            local scene = ui.scene(target)
            local rows = math.max(1, math.floor((height - 6) / 2))
            offset = math.max(0, math.min(offset, #orders - rows))
            for slot = 1, rows do
                local order = orders[offset + slot]
                if not order then break end
                local y = 2 + slot * 2
                local done = order.status ~= "open"
                local pickup = (order.delivery or {}).kind == "pickup"
                scene:button("order:" .. (offset + slot), 2, y, width - 2, 1,
                    ui.truncate(order.order_id .. "  "
                        .. tostring(order.buyer_name), width - 4),
                    { background = done and ui.theme.panel
                        or (pickup and colors.purple or ui.theme.accentDark) })
                ui.text(target, 3, y + 1, ui.truncate((done and "Done. " or "")
                    .. tostring(order.stage) .. "  " .. addressOf(order),
                    width - 4), ui.theme.muted)
            end
            if #orders == 0 then
                ui.wrappedText(target, 2, 5, listed
                    and "No orders yet. They land here the moment somebody"
                        .. " checks out in the Shop app."
                    or "The Bank is not answering.", width - 2, 4,
                    ui.theme.muted)
            end
            if #orders > rows then
                scene:button("up", width - 8, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 4, height, 3, 1, "v",
                    { background = ui.theme.panel,
                        disabled = offset + rows >= #orders })
            end
            scene:button("pickup", 1, height, 8, 1, "PICKUP",
                { background = ui.theme.accentDark })
            -- Every few seconds the board asks again, so an order placed a
            -- moment ago is on screen without anybody touching anything.
            local action = scene:wait({ tickRate = 5 })
            if action == "__terminate" then
                running = false
                return
            end
            if action == "up" then
                offset = math.max(0, offset - rows)
            elseif action == "down" then
                offset = offset + rows
            elseif action == "pickup" then
                pickupButton()
            else
                local index = tonumber(action
                    and action:match("^order:(%d+)$"))
                if index and orders[index] then
                    orderScreen(orders[index], listed.stages or {})
                end
            end
        end
    end
end

if rawget(_G, "PUMPE_TEST_MODE") == true then
    return {
        inventories = inventories, moveAll = moveAll, used = used,
        freeLocker = freeLocker, lockKeyboard = lockKeyboard,
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
