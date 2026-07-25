local util = {}

local seeded = false

local function seedRandom()
    if seeded then return end
    seeded = true
    local seed = os.getComputerID() * 7919
    if os.epoch then
        seed = seed + (os.epoch("utc") % 2147483647)
    else
        seed = seed + math.floor(os.clock() * 100000)
    end
    math.randomseed(seed)
    math.random()
    math.random()
    math.random()
end

function util.nowMs()
    if os.epoch then
        return os.epoch("utc")
    end
    return math.floor(os.clock() * 1000)
end

function util.ingameDay()
    local ok, value = pcall(os.day, "ingame")
    if ok and type(value) == "number" then return value end
    return os.day()
end

function util.ingameTime()
    local ok, value = pcall(os.time, "ingame")
    if ok and type(value) == "number" then return value end
    return os.time()
end

function util.clockParts()
    local raw = util.ingameTime()
    local hour = math.floor(raw) % 24
    local minute = math.floor((raw - math.floor(raw)) * 60 + 0.5)
    if minute >= 60 then
        minute = 0
        hour = (hour + 1) % 24
    end
    return hour, minute
end

function util.formatClock(blink)
    local hour, minute = util.clockParts()
    return string.format("%02d%s%02d", hour, blink == false and " " or ":", minute)
end

function util.parseEventTime(value)
    if type(value) == "number" then
        return math.max(0, math.min(1439, math.floor(value)))
    end
    local hour, minute = tostring(value or ""):match("^(%d%d?):(%d%d)$")
    hour, minute = tonumber(hour), tonumber(minute)
    if not hour or not minute or hour > 23 or minute > 59 then return nil end
    return hour * 60 + minute
end

function util.eventCountdown(eventDay, eventTime)
    local targetMinute = util.parseEventTime(eventTime)
    if not targetMinute then return "Time TBA", nil end
    local nowHour, nowMinute = util.clockParts()
    local remaining = (tonumber(eventDay) - util.ingameDay()) * 1440
        + targetMinute - (nowHour * 60 + nowMinute)
    if remaining < 0 then return "Started", remaining end
    if remaining == 0 then return "Starting now", remaining end
    local days = math.floor(remaining / 1440)
    local hours = math.floor((remaining % 1440) / 60)
    local minutes = remaining % 60
    if days > 0 then
        return string.format("%dd %02dh %02dm", days, hours, minutes), remaining
    elseif hours > 0 then
        return string.format("%dh %02dm", hours, minutes), remaining
    end
    return string.format("%dm", minutes), remaining
end

function util.roundMoney(value)
    value = tonumber(value)
    if not value then return nil end
    return math.floor(value * 100 + 0.5) / 100
end

function util.transferBreakdown(value, feeRate)
    local amount = util.roundMoney(value)
    if not amount or amount <= 0 then return nil end
    feeRate = math.max(0, tonumber(feeRate) or 0)
    -- Round fees up to the nearest cent so splitting one transfer into many
    -- tiny transfers cannot avoid the configured percentage fee.
    local fee = math.ceil(amount * feeRate * 100 - 0.000000001) / 100
    return {
        amount = amount,
        fee = fee,
        total = util.roundMoney(amount + fee),
    }
end

function util.dailyLimitRemaining(alreadyUsed, amount, limit)
    alreadyUsed = util.roundMoney(alreadyUsed) or 0
    amount = util.roundMoney(amount)
    limit = util.roundMoney(limit)
    if not amount or amount <= 0 or not limit or limit < 0 then return false, 0 end
    local remaining = util.roundMoney(limit - alreadyUsed - amount)
    return remaining >= 0, math.max(0, remaining)
end

function util.money(value, symbol)
    value = tonumber(value) or 0
    symbol = symbol or "$"
    if math.floor(value) == value then
        return symbol .. tostring(math.floor(value))
    end
    return string.format("%s%.2f", symbol, value)
end

function util.clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function util.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function util.normalName(value)
    return string.lower(util.trim(value))
end

function util.hex32(value)
    value = math.floor(tonumber(value) or 0) % 4294967296
    local alphabet, output = "0123456789abcdef", {}
    for index = 8, 1, -1 do
        local digit = value % 16
        output[index] = alphabet:sub(digit + 1, digit + 1)
        value = math.floor(value / 16)
    end
    return table.concat(output)
end

function util.checksum(body)
    local hash = 5381
    body = tostring(body or "")
    for index = 1, #body do
        hash = (hash * 33 + string.byte(body, index)) % 4294967296
    end
    return util.hex32(hash)
end

function util.hashPin(pin)
    return util.checksum(pin)
end

function util.validPin(pin)
    return type(pin) == "string" and pin:match("^%d%d%d%d$") ~= nil
end

function util.randomString(length, alphabet)
    seedRandom()
    alphabet = alphabet or "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    local out = {}
    for i = 1, length do
        local index = math.random(1, #alphabet)
        out[i] = alphabet:sub(index, index)
    end
    return table.concat(out)
end

function util.token(prefix)
    return (prefix or "TOK") .. "_" .. util.randomString(24)
end

function util.copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[util.copy(key, seen)] = util.copy(item, seen)
    end
    return result
end

function util.sortedValues(map, predicate, sorter)
    local values = {}
    for _, value in pairs(map or {}) do
        if not predicate or predicate(value) then
            values[#values + 1] = value
        end
    end
    table.sort(values, sorter)
    return values
end

function util.safeText(value, maxLength)
    local text = tostring(value or ""):gsub("[%c]", " ")
    if maxLength and #text > maxLength then
        text = text:sub(1, maxLength)
    end
    return text
end

function util.readFile(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local body = handle.readAll()
    handle.close()
    return body
end

function util.writeFile(path, body)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then
        fs.makeDir(directory)
    end
    local handle = assert(fs.open(path, "w"))
    handle.write(body)
    handle.close()
end

function util.loadTable(path, fallback)
    local body = util.readFile(path)
    if not body then return util.copy(fallback) end
    local ok, value = pcall(textutils.unserialize, body)
    if ok and type(value) == "table" then return value end
    return util.copy(fallback)
end

function util.saveTable(path, value)
    local temp = path .. ".tmp"
    util.writeFile(temp, textutils.serialize(value, { compact = true }))
    if fs.exists(path) then fs.delete(path) end
    fs.move(temp, path)
end

function util.page(items, page, pageSize)
    pageSize = math.max(1, pageSize or 5)
    local pages = math.max(1, math.ceil(#items / pageSize))
    page = util.clamp(page or 1, 1, pages)
    local output = {}
    local first = (page - 1) * pageSize + 1
    local last = math.min(#items, first + pageSize - 1)
    for i = first, last do output[#output + 1] = items[i] end
    return output, page, pages
end

return util
