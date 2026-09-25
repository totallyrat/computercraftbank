-- The Delivery Terminal, driven by taps, against a real Bank Core and Vault.
--
-- The chests are fakes that behave like ComputerCraft's: list() shows the
-- stacks by slot, size() is 27, and pushItems moves a stack into the first
-- slot that takes it and says how many items went. A pickup point is only
-- as good as what it actually moves, so the checks here are on the chests
-- as much as on the screens.
--
-- The whole run happens twice, at an Advanced Computer's 51x19 and a Pocket
-- Computer's 26x20 -- a warehouse and a delivery driver -- with every draw
-- bounds checked.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")

local DEVICE = "/pumpe/delivery_terminal_device.dat"
local LOCK = "/pumpe/keyboard.lock"
-- The first locker is not empty: somebody keeps sticks in it. Nothing may
-- be filed on top of them.
local HATCH, JUNK, LOCKER_A, LOCKER_B = "minecraft:chest_0",
    "minecraft:chest_1", "minecraft:chest_2", "minecraft:chest_3"

local function contains(list, wanted)
    for _, item in ipairs(list) do
        if item == wanted then return true end
    end
    return false
end

-- Chests ---------------------------------------------------------------------------

local chests = {}
local function resetChests()
    chests = {}
    for _, name in ipairs({ HATCH, JUNK, LOCKER_A, LOCKER_B }) do
        chests[name] = { size = 27, slots = {} }
    end
    chests[JUNK].slots[1] = { name = "minecraft:stick", count = 5 }
end

local function put(name, item, count)
    local chest = chests[name]
    for slot = 1, chest.size do
        if not chest.slots[slot] then
            chest.slots[slot] = { name = item, count = count }
            return
        end
    end
    error("chest full")
end

local function count(name, item)
    local total = 0
    for _, stack in pairs(chests[name].slots) do
        if stack.name == item then total = total + stack.count end
    end
    return total
end

local function stacks(name)
    local total = 0
    for _ in pairs(chests[name].slots) do total = total + 1 end
    return total
end

peripheral = {
    getNames = function()
        local names = { "top" }
        for name in pairs(chests) do names[#names + 1] = name end
        table.sort(names)
        return names
    end,
    getMethods = function(name)
        if chests[name] then
            return { "list", "size", "pushItems", "pullItems", "getItemDetail" }
        end
        if name == "top" then return { "open", "close", "isOpen", "transmit" } end
        return nil
    end,
    call = function(name, method, ...)
        local chest = chests[name]
        if not chest then error("No such peripheral: " .. tostring(name)) end
        if method == "list" then
            local listed = {}
            for slot, stack in pairs(chest.slots) do
                listed[slot] = { name = stack.name, count = stack.count }
            end
            return listed
        elseif method == "size" then
            return chest.size
        elseif method == "pushItems" then
            local toName, fromSlot, limit = ...
            local to = chests[toName]
            if not to then
                error("Target '" .. tostring(toName) .. "' does not exist")
            end
            local stack = chest.slots[fromSlot]
            if not stack then return 0 end
            local moving = math.min(stack.count, limit or stack.count)
            local moved = 0
            for slot = 1, to.size do
                local there = to.slots[slot]
                if moved < moving and there and there.name == stack.name
                    and there.count < 64 then
                    local room = math.min(64 - there.count, moving - moved)
                    there.count, moved = there.count + room, moved + room
                end
            end
            for slot = 1, to.size do
                if moved < moving and not to.slots[slot] then
                    to.slots[slot] = { name = stack.name,
                        count = moving - moved }
                    moved = moving
                end
            end
            stack.count = stack.count - moved
            if stack.count == 0 then chest.slots[fromSlot] = nil end
            return moved
        end
        error("unexpected chest method " .. tostring(method))
    end,
}

local outputs = {}
redstone = {
    setOutput = function(side, on) outputs[#outputs + 1] = side .. "=" .. tostring(on) end,
}
parallel = { waitForAny = function(first) first() end }
sleep = function() end
os.pullEventRaw = function() error("no events in a test") end
local terminatingPullEvent = function() error("no events in a test") end

-- One run of the program ------------------------------------------------------------

local function wrap(value, width)
    value, width = tostring(value or ""), math.max(1, width)
    local lines = {}
    for line in (value .. "\n"):gmatch("(.-)\n") do
        while #line > width do
            lines[#lines + 1] = line:sub(1, width)
            line = line:sub(width + 1)
        end
        lines[#lines + 1] = line
    end
    return lines
end

-- Loads delivery_terminal.lua and plays `script` into it. The script has a
-- queue for each kind of question the terminal can ask; an entry can be a
-- function, which runs at that moment -- a buyer checking out, staff putting
-- a parcel in a chest -- and returns the answer.
local function runTerminal(bank, files, WIDTH, HEIGHT, script, offline)
    local seen = { messages = {}, headers = {}, labels = {}, requests = {},
        idleUpdates = 0 }
    local surface = { getSize = function() return WIDTH, HEIGHT end }
    term = { current = function() return surface end }

    local function take(queue, what)
        local entry = table.remove(queue, 1)
        assert(entry ~= nil, "the terminal asked for an unexpected " .. what)
        if type(entry) == "function" then entry = entry() end
        return entry
    end
    local function box(label, x, y, width, height)
        assert(x >= 1 and y >= 1, label .. " starts outside the screen")
        assert(width >= 1 and height >= 1, label .. " is empty")
        assert(x + width - 1 <= WIDTH, label .. " is wider than the screen")
        assert(y + height - 1 <= HEIGHT, label .. " is below the screen")
    end

    local ui = { theme = {
        background = colors.black, panel = colors.gray,
        panelAlt = colors.lightGray, ink = colors.white,
        muted = colors.lightGray, accent = colors.cyan,
        accentDark = colors.blue, success = colors.lime,
        danger = colors.red, warning = colors.orange, shadow = colors.gray,
    } }
    function ui.boot() end
    function ui.clear() end
    function ui.truncate(value, maximum)
        return tostring(value or ""):sub(1, math.max(0, maximum))
    end
    function ui.header(_, title, subtitle, clock)
        local room = WIDTH - 3 - (clock and #clock + 1 or 0)
        assert(#tostring(title) <= room, "header clipped: " .. tostring(title))
        assert(#tostring(subtitle or "") <= WIDTH - 3,
            "subtitle clipped: " .. tostring(subtitle))
        seen.headers[#seen.headers + 1] = tostring(title)
    end
    function ui.text(_, x, y, value)
        box("text", x, y, math.max(1, #tostring(value or "")), 1)
    end
    function ui.center(_, y, value)
        assert(y >= 1 and y <= HEIGHT, "centred text below the screen")
        assert(#tostring(value or "") <= WIDTH, "centred text clipped: "
            .. tostring(value))
    end
    function ui.wrappedText(_, x, y, _, width, lines)
        box("wrapped text", x, y, width, lines)
    end
    function ui.message(_, kind, title, body)
        seen.messages[#seen.messages + 1] = { kind = kind, title = title,
            body = body }
    end
    function ui.input(_, title)
        seen.headers[#seen.headers + 1] = title
        local answer = take(script.inputs, "text box: " .. title)
        if type(answer) == "table" and answer.crash then
            error(answer.crash, 0)
        end
        return answer
    end
    function ui.pin(_, title)
        seen.headers[#seen.headers + 1] = title
        return take(script.pins, "PIN pad: " .. title)
    end
    function ui.confirm(_, title, _, yes, no)
        seen.headers[#seen.headers + 1] = title
        local buttonWidth = math.max(8, math.floor((WIDTH - 6) / 2))
        assert(#(yes or "YES") <= buttonWidth - 2
            and #(no or "NO") <= buttonWidth - 2, "confirm label clipped")
        return take(script.confirms, "confirmation: " .. title)
    end
    function ui.scene()
        local scene = {}
        function scene:button(_, x, y, width, height, label)
            box("button " .. tostring(label), x, y, width, height)
            assert(#wrap(label, math.max(1, width - 2)) <= height,
                "button label clipped: " .. tostring(label))
            seen.labels[#seen.labels + 1] = tostring(label)
        end
        function scene:wait()
            return take(script.actions, "tap")
        end
        return scene
    end

    local client = {
        request = function(_, action, payload)
            seen.requests[#seen.requests + 1] = action
            if seen.lockedAtFirstRequest == nil then
                seen.lockedAtFirstRequest = os.pullEvent == os.pullEventRaw
            end
            if offline then return nil, "Bank server timed out" end
            local copy = {}
            for key, value in pairs(payload or {}) do copy[key] = value end
            local ok, result = pcall(bank.request, action, copy)
            if ok then return result end
            if type(result) == "table" and result.pumpe then
                return nil, result.message, result.code
            end
            error(result, 0)
        end,
    }
    local savedNet, savedUi = package.loaded["lib.net"], package.loaded["lib.ui"]
    package.loaded["lib.net"] = {
        client = function() return client end,
        -- Only the pickup counter passes onProgress: it draws "updating".
        autoUpdate = function(_, _, _, _, options)
            if options and options.onProgress then
                seen.idleUpdates = seen.idleUpdates + 1
            end
        end,
        locate = function() return { x = 10, y = 64, z = -20 } end,
    }
    package.loaded["lib.ui"] = ui
    local ok, err = pcall(assert(loadfile("../delivery_terminal.lua")))
    package.loaded["lib.net"], package.loaded["lib.ui"] = savedNet, savedUi
    assert(ok, err)
    for name, queue in pairs(script) do
        assert(#queue == 0, #queue .. " scripted " .. name .. " never used")
    end
    return seen
end

local function titles(seen)
    local list = {}
    for _, message in ipairs(seen.messages) do list[#list + 1] = message.title end
    return list
end

-- A store, a buyer, and a terminal that has to set itself up ----------------------

local function fullRun(WIDTH, HEIGHT)
    local bank = harness.pair()
    local util = require("lib.util")
    local files = {}
    util.loadTable = function(path, fallback)
        return util.copy(files[path] or fallback)
    end
    util.saveTable = function(path, value) files[path] = util.copy(value) end
    util.writeFile = function(path, body) files[path] = body end
    fs.exists = function(path) return files[path] ~= nil end
    fs.delete = function(path) files[path] = nil end
    os.pullEvent = terminatingPullEvent
    -- A lock left over from a pickup point this computer no longer is.
    files[LOCK] = "left over\n"
    resetChests()
    outputs = {}

    local ana = bank.register("Ana Fox", "1234")
    local kit = bank.register("Kit Wolf", "5678")
    bank.fund(kit, 1000)
    local till = bank.request("KIOSK_REGISTER", { name = "Fox Goods Till" })
    local function as(extra)
        extra.terminal_id, extra.terminal_token =
            till.terminal_id, till.terminal_token
        return extra
    end
    local owner = bank.request("KIOSK_OWNER_LOGIN",
        as({ name = "Ana Fox", pin = "1234" }))
    local company = bank.request("CREATE_COMPANY", as({
        owner_session = owner.owner_session, company_name = "Fox Goods" })).company
    bank.request("LINK_TERMINAL", as({ owner_session = owner.owner_session,
        company_id = company.company_id }))
    local bread = bank.request("ADD_PRODUCT", as({ name = "Bread", price = 4,
        kind = "one_time" })).item
    bank.request("SHOP_PRODUCT", as({ item_id = bread.item_id, online = true }))
    bank.request("SHOP_SETUP", as({ home = true, pickup = true, fee = 5,
        open = true }))
    -- Kit owns a company too, just not this one.
    local kitOwner = bank.request("KIOSK_OWNER_LOGIN",
        as({ name = "Kit Wolf", pin = "5678" }))
    bank.request("CREATE_COMPANY", as({ owner_session = kitOwner.owner_session,
        company_name = "Wolf Pack" }))
    local homeOrder = bank.request("SHOP_CHECKOUT", bank.as(kit, {
        company_id = company.company_id, pin = "5678",
        items = { { item_id = bread.item_id, quantity = 2 } },
        delivery = { kind = "home", x = 100, y = 64, z = -30,
            label = "Home" } }))

    local function device() return files[DEVICE] or {} end
    local orders = bank.vault_state.orders
    local pickupOrder

    local script = { actions = {}, inputs = {}, pins = {}, confirms = {} }
    local function tap(...)
        for _, entry in ipairs({ ... }) do
            script.actions[#script.actions + 1] = entry
        end
    end
    local function typed(...)
        for _, entry in ipairs({ ... }) do
            script.inputs[#script.inputs + 1] = entry
        end
    end
    local function pin(...)
        for _, entry in ipairs({ ... }) do
            script.pins[#script.pins + 1] = entry
        end
    end
    local function confirm(...)
        for _, entry in ipairs({ ... }) do
            script.confirms[#script.confirms + 1] = entry
        end
    end
    local function theCode() return pickupOrder.code end
    local offersBefore
    local function offerCount()
        local total = 0
        for _ in pairs(bank.state.proximity_offers) do total = total + 1 end
        return total
    end
    local function setApples(amount)
        for _, stack in pairs(chests[JUNK].slots) do
            if stack.name == "minecraft:apple" then stack.count = amount end
        end
    end
    local function openOffer()
        for id, offer in pairs(bank.state.proximity_offers) do
            if offer.status == "offered" then return id end
        end
    end

    -- First boot: name the terminal, and the owner links it.
    typed("Warehouse", "Ana Fox")
    pin("1234")

    -- The board. The home order moves on a premade stage, then one in the
    -- company's own words, then it is done with a note.
    tap(function()
        assert(not files[LOCK], "a leftover lock is cleared at start-up")
        return "order:1"
    end, "stage", "pick:2", "stage", "pick:6", "done")
    typed("Stuck in the rain", "Left by the door")
    confirm(true)

    -- The PICKUP button: a new pickup point, with the first chest as the
    -- one customers open and a redstone pulse out of the back.
    tap("pickup", "pick:1", "pick:2")
    typed("North Point")
    pin("2468", "2468")

    -- Pickup mode. Ctrl+T is only a redraw now. A buyer checks out to this
    -- point, and comes before their parcel has.
    tap(function()
        assert(os.pullEvent == os.pullEventRaw,
            "Pickup mode ignores Ctrl+T")
        assert(files[LOCK], "and leaves the lock behind for a reboot")
        pickupOrder = bank.request("SHOP_CHECKOUT", bank.as(kit, {
            company_id = company.company_id, pin = "5678",
            items = { { item_id = bread.item_id, quantity = 3 } },
            delivery = { kind = "pickup", point_id = device().terminal_id } }))
        return "__terminate"
    end, function()
        -- Nobody has touched the counter for a minute: it updates itself.
        bank.advanceMs(61 * 1000)
        return "__tick"
    end, "code")
    typed(theCode)

    -- 11.1: the courier types the parcel's delivery code at the counter --
    -- no staff PIN -- and puts it in the pickup chest as two stacks; the
    -- terminal files it.
    tap("code")
    typed(function() return orders[pickupOrder.order_id].delivery_code end)
    confirm(function()
        put(HATCH, "minecraft:bread", 2)
        put(HATCH, "minecraft:bread", 1)
        return true
    end)

    -- A stranger's dirt is in the pickup chest when the buyer comes back.
    -- Their code asks their PUMPE first; they confirm with their PIN.
    tap(function()
        assert(stacks(HATCH) == 0, "stocking emptied the pickup chest")
        assert(count(LOCKER_A, "minecraft:bread") == 3,
            "into the first free locker")
        assert(stacks(JUNK) == 1, "not on top of the sticks")
        assert(orders[pickupOrder.order_id].locker == LOCKER_A,
            "and the Bank knows which")
        put(HATCH, "minecraft:dirt", 1)
        return "code"
    end)
    typed(theCode)
    tap(function()
        local asked = bank.state.accounts[kit.id].notifications[1]
        assert(asked.security_order == pickupOrder.order_id,
            "the buyer's PUMPE is asked whether it is them")
        assert(count(HATCH, "minecraft:bread") == 0, "and nothing is out yet")
        return "__tick"
    end, function()
        bank.request("SECURITY_CONFIRM", bank.as(kit, {
            order_id = pickupOrder.order_id, pin = "5678" }))
        return "__tick"
    end)

    -- They take their parcel, and the same code does not work twice.
    tap(function()
        assert(count(HATCH, "minecraft:bread") == 3, "the parcel came out")
        assert(count(HATCH, "minecraft:dirt") == 0,
            "and nobody else's things came with it")
        assert(count(LOCKER_B, "minecraft:dirt") == 1,
            "those were put away in a spare locker first")
        assert(stacks(LOCKER_A) == 0)
        assert(orders[pickupOrder.order_id].status == "collected")
        chests[HATCH].slots = {}
        return "code"
    end)
    typed(theCode)

    -- Staff: one wrong PIN, then the right one. They put the point's own
    -- stock in the pickup chest and RESTOCK files it -- fullest locker
    -- first, so the empty one stays free for parcels.
    tap("staff", "pin", "staff", "pin", function()
        put(HATCH, "minecraft:apple", 20)
        return "stock"
    end, "back")
    pin("1111", "2468")

    -- The owner sets up the Store from the Company app, and a customer buys
    -- apples with Foxy Pay.
    local ownApples
    tap(function()
        assert(stacks(HATCH) == 0, "restocking emptied the pickup chest")
        assert(count(JUNK, "minecraft:apple") == 20
            and stacks(LOCKER_A) == 0, "into a locker already in use")
        local point = device().terminal_id
        bank.request("STORE_OFFER_SET", bank.as(ana, {
            company_id = company.company_id, point_id = point,
            name = "Apples", item = "apple", count = 8, price = 6 }))
        bank.request("STORE_OPEN", bank.as(ana, {
            company_id = company.company_id, point_id = point, open = true }))
        bank.request("REPORT_POSITION", bank.as(kit,
            { position = { x = 11, y = 64, z = -20 } }))
        ownApples = bank.balanceOf(ana)
        return "__tick"
    end, "store", "offer:1", "pick:1", function()
        local id = openOffer()
        assert(bank.state.proximity_offers[id].target_account_id == kit.id,
            "Foxy Pay found the customer standing there")
        bank.request("FOXY_PAY_CONFIRM", bank.as(kit, { offer_id = id,
            pin = "5678" }))
        return "__tick"
    end)

    -- A second sale comes up short: somebody takes apples out by hand
    -- while the customer is paying.
    tap(function()
        assert(count(HATCH, "minecraft:apple") == 8, "eight apples came out")
        assert(count(JUNK, "minecraft:apple") == 12)
        assert(bank.balanceOf(ana) == ownApples + 6, "and the owner was paid")
        chests[HATCH].slots = {}
        -- Somebody takes most of them out by hand while the next customer
        -- is still reading the list.
        setApples(5)
        offersBefore = offerCount()
        return "offer:1"
    end, function()
        assert(bank.balanceOf(ana) == ownApples + 6
            and offerCount() == offersBefore,
            "sold out before anybody was asked to pay")
        setApples(12)
        return "__tick"
    end, "offer:1", "pick:1", function()
        local id = openOffer()
        for slot, stack in pairs(chests[JUNK].slots) do
            if stack.name == "minecraft:apple" then stack.count = 3 end
        end
        bank.request("FOXY_PAY_CONFIRM", bank.as(kit, { offer_id = id,
            pin = "5678" }))
        return "__tick"
    end, function()
        assert(count(HATCH, "minecraft:apple") == 3, "what there was came out")
        local told = bank.state.accounts[ana.id].notifications[1]
        assert(told.title == "Pickup sale came up short"
            and told.body:find("Kit Wolf got 3 of 8", 1, true)
            and told.body:find("3.75", 1, true), "the owner knows who is owed "
                .. "what: " .. tostring(told.body))
        chests[HATCH].slots = {}
        return "back"
    end)

    -- Five wrong staff PINs lock the staff door, even to the right PIN.
    for _ = 1, 5 do tap("staff", "pin") end
    pin("0000", "0000", "0000", "0000", "0000")
    tap("staff", "pin")

    -- The owner can still get in, sets a new PIN, empties the locker with
    -- the dirt in it, and leaves Pickup mode.
    tap("staff", "owner")
    typed("Kit Wolf")
    pin("5678")
    tap("staff", "owner", "pin", "open", "pick:2", "leave")
    typed("Ana Fox")
    pin("1234", "1357", "1357")

    -- Back to Pickup mode from the board. Something goes wrong inside it:
    -- the terminal pauses rather than stopping, and the PIN still leaves.
    tap(function()
        assert(not files[LOCK], "leaving Pickup mode takes the lock off")
        assert(os.pullEvent == terminatingPullEvent
            or os.pullEvent ~= os.pullEventRaw,
            "and Ctrl+T works again for staff")
        return "pickup"
    end, "start", "code")
    typed({ crash = "boom" })
    pin("1357")

    -- Retiring the point, and closing the board.
    tap("pickup", "start", "staff", "pin", "retire", "__terminate")
    pin("1357")
    confirm(true)

    local seen = runTerminal(bank, files, WIDTH, HEIGHT, script)
    local shown = titles(seen)

    -- The home order, all the way through.
    local home = orders[homeOrder.order_id]
    local labels = {}
    for _, step in ipairs(home.history) do labels[#labels + 1] = step.label end
    assert(contains(labels, "Packing"), "a premade stage")
    assert(contains(labels, "Stuck in the rain"), "a stage in the company's words")
    assert(home.status == "done" and home.note == "Left by the door",
        "DONE, with the note for the buyer")
    assert(contains(seen.headers, homeOrder.order_id), "the order had its screen")

    -- The pickup point, as the Bank saw it.
    assert(contains(seen.requests, "PICKUP_REGISTER"))
    assert(contains(shown, "NOT HERE"), "a code before the parcel arrives")
    assert(contains(shown, "WRONG PIN"))
    assert(contains(shown, "DELIVERED"), "the courier stocked it with a code")
    assert(contains(shown, "TAKE YOUR PARCEL"))
    assert(contains(shown, "RESTOCKED"))
    assert(seen.idleUpdates == 1, "an idle counter checks for an update, and"
        .. " one somebody is using does not: " .. seen.idleUpdates)
    assert(contains(shown, "TAKE YOUR ITEMS"), "a Store sale")
    assert(contains(shown, "ASK A MEMBER OF STAFF"), "and a short one")
    assert(contains(shown, "SOLD OUT"), "and one sold out under the customer")
    assert(contains(shown, "STAFF LOCKED"), "five wrong PINs lock staff out")
    assert(contains(shown, "NOT THE OWNER"),
        "a customer's own Foxy account is not the way in")
    assert(contains(shown, "PIN CHANGED"))
    assert(contains(shown, "PICKUP PAUSED"), "an error pauses Pickup mode")
    assert(table.concat(outputs, ",") == "back=true,back=false,"
        .. "back=true,back=false,back=true,back=false",
        "a pulse out of the back each time something came out: the parcel"
            .. " and two sales")
    assert(count(HATCH, "minecraft:dirt") == 1,
        "staff emptied the dirt's locker into the pickup chest")
    assert(count(JUNK, "minecraft:stick") == 5, "and never touched the sticks")
    assert(bank.vault_state.pickup_points[device().terminal_id] == nil,
        "and retired the point")
    assert(device().pickup == nil and device().mode == "board")
    assert(not files[LOCK])
    return bank, files, device(), { kit = kit, company = company,
        bread = bread }
end

fullRun(51, 19)
-- The last run's Bank and in-memory disk carry on into the reboot below.
local bank, files, device, shop = fullRun(26, 20)

-- A pickup point that reboots while the Bank is away ----------------------------------
-- It goes straight back to the counter, still locked. Setting up a new
-- terminal, or stopping because there is no Bank, would both leave the shell
-- to whoever is standing there.

resetChests()
local util = require("lib.util")
device.mode = "pickup"
device.pickup = { name = "North Point", pin_hash = util.hashPin("2468"),
    hatch = HATCH, side = "none" }
files[DEVICE] = util.copy(device)
files[LOCK] = "pickup\n"
os.pullEvent = terminatingPullEvent
local script = {
    actions = {
        function()
            assert(os.pullEvent == os.pullEventRaw,
                "locked from the first line, before the Bank answers")
            return "code"
        end,
        "staff", "pin", "leave", "__terminate",
    },
    inputs = { "222222" },
    pins = { "2468" },
    confirms = {},
}
local seen = runTerminal(bank, files, 26, 20, script, true)
assert(seen.lockedAtFirstRequest,
    "locked before the first network wait, not once the screen is up")
assert(contains(titles(seen), "NOT HERE"), "the customer is told, not dropped")
assert(files[DEVICE].terminal_id == device.terminal_id,
    "and the terminal kept its identity")

-- A locker the Bank has a parcel booked into is never offered again, even
-- if somebody has emptied it by hand: filing a second parcel there would
-- hand the first buyer's code the second buyer's things.
do
    resetChests()
    term = { current = function()
        return { getSize = function() return 26, 20 end }
    end }
    local savedNet, savedUi = package.loaded["lib.net"], package.loaded["lib.ui"]
    package.loaded["lib.net"] = { client = function() return {} end,
        autoUpdate = function() end, locate = function() return nil end }
    package.loaded["lib.ui"] = { theme = {} }
    PUMPE_TEST_MODE = true
    local terminal = assert(loadfile("../delivery_terminal.lua"))()
    PUMPE_TEST_MODE = nil
    package.loaded["lib.net"], package.loaded["lib.ui"] = savedNet, savedUi
    terminal.device.pickup = { hatch = HATCH }
    assert(terminal.freeLocker(1, {}) == LOCKER_A)
    assert(terminal.freeLocker(1, { [LOCKER_A] = "ORD00000001" }) == LOCKER_B,
        "a booked locker is skipped")
    chests[LOCKER_B].size = 1
    assert(terminal.freeLocker(2, { [LOCKER_A] = "ORD00000001" }) == nil,
        "and so is one too small for the parcel")

    -- The Store sells from lockers, never out of somebody's parcel.
    resetChests()
    put(LOCKER_A, "minecraft:apple", 10)
    put(JUNK, "minecraft:apple", 5)
    local booked = { [LOCKER_A] = "ORD00000001" }
    assert(terminal.inStock("minecraft:apple", booked) == 5,
        "a parcel's apples are not stock")
    assert(terminal.dispense("minecraft:apple", 8, booked) == 5)
    assert(count(HATCH, "minecraft:apple") == 5
        and count(LOCKER_A, "minecraft:apple") == 10,
        "and never come out of its locker")

    -- Restocking fills lockers that hold stock already, fullest first, and
    -- leaves empty ones for parcels.
    resetChests()
    chests[JUNK].slots = {}
    put(LOCKER_B, "minecraft:apple", 64)
    put(LOCKER_B, "minecraft:apple", 64)
    put(JUNK, "minecraft:stick", 1)
    local order = terminal.stockLockers({})
    assert(order[1] == LOCKER_B and order[2] == JUNK and order[3] == LOCKER_A,
        "fullest first: " .. table.concat(order, ","))
    assert(#terminal.stockLockers({ [LOCKER_B] = "ORD00000001" }) == 2,
        "and never a parcel's locker")
end

-- Refunds and returns from the board (11.0) -------------------------------------------
-- The store cancels an order it cannot fill, refunds a return it has back,
-- and turns down one it never got.

local orders = bank.vault_state.orders
local function buy()
    return bank.request("SHOP_CHECKOUT", bank.as(shop.kit, {
        company_id = shop.company.company_id, pin = "5678",
        items = { { item_id = shop.bread.item_id, quantity = 1 } },
        delivery = { kind = "home", x = 5, y = 64, z = 5 } })).order_id
end
local function arrivedAndReturned(orderId, reason)
    bank.request("DELIVERY_DONE", { order_id = orderId,
        terminal_id = device.terminal_id, terminal_token = device.terminal_token })
    bank.request("SHOP_RETURN", bank.as(shop.kit, { order_id = orderId,
        reason = reason }))
end

local kitBefore = bank.balanceOf(shop.kit)
local soldOut = buy()
local unwanted, neverSent
script = { actions = {}, inputs = {}, pins = {}, confirms = {} }
-- The only open order, first on the board.
local function push(queue, ...)
    for _, entry in ipairs({ ... }) do queue[#queue + 1] = entry end
end
push(script.actions, "order:1", "refund")
push(script.confirms, true)
push(script.inputs, "Sold out")
-- Two returns, placed while the board is up; each is first on it in turn.
push(script.actions, function()
    assert(orders[soldOut].status == "cancelled"
        and bank.balanceOf(shop.kit) == kitBefore,
        "cancelled from the board, and the buyer has it all back")
    unwanted = buy()
    arrivedAndReturned(unwanted, "Too stale")
    -- The board asks again every few seconds; let it.
    return "__tick"
end, "order:1", "take_back")
push(script.confirms, true)
push(script.actions, function()
    assert(orders[unwanted].return_request.status == "refunded")
    neverSent = buy()
    arrivedAndReturned(neverSent, "Mouldy")
    return "__tick"
end, "order:1", "decline")
push(script.inputs, "Never came back to us")
push(script.actions, "__terminate")
local seen = runTerminal(bank, files, 26, 20, script)
assert(contains(titles(seen), "REFUNDED") and contains(titles(seen), "DECLINED"))
assert(contains(seen.labels, "CANCEL + REFUND") and contains(seen.labels,
    "REFUND RETURN") and contains(seen.labels, "DECLINE"))
assert(orders[soldOut].note == "Sold out", "the store's reason reaches the buyer")
assert(orders[neverSent].return_request.status == "declined"
    and orders[neverSent].return_request.answer == "Never came back to us")

print("host_delivery_terminal_test: OK")
