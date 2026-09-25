-- PUMPE Bank rescue, 11.2.
--
-- For a Bank Server that will not start because its disk is full. On the
-- Bank's own computer, at the shell:
--
--   wget run https://raw.githubusercontent.com/totallyrat/computercraftbank/main/tools/bank_rescue.lua
--
-- It runs from memory and writes nothing until it has made room. First it
-- deletes what can always be fetched again: the /updates cache and staging
-- left by updates that never finished. Only if that is still not enough for
-- the Bank to save and to install 11.2 does it trim transaction history and
-- notifications -- to the newest thirty and twenty per account, which is
-- all 11.2 keeps anyway. Balances, accounts and everything else that is
-- money are never touched. Then reboot: Easy Deployment installs the new
-- Bank Server on the way up.

local ROOT = "/pumpe"
local KEEP = { transactions = 30, notifications = 20 }
-- Room for one save of the data plus the new Bank Server going in.
local INSTALL_ROOM = 320 * 1024

local function free() return fs.getFreeSpace("/") end
local function kib(bytes) return string.format("%d KiB", math.floor(bytes / 1024)) end
local function say(text, color)
    if term.isColor() and color then term.setTextColor(color) end
    print(text)
    if term.isColor() then term.setTextColor(colors.white) end
end

say("PUMPE Bank rescue", colors.orange)
say("Free space: " .. kib(free()))

-- 1. What can be fetched again.
local removed = 0
local function remove(path)
    if fs.exists(path) then
        local ok = pcall(fs.delete, path)
        if ok then
            removed = removed + 1
            say("  removed " .. path, colors.lightGray)
        end
    end
end
remove("/updates")
for _, name in ipairs({ ".online_update_stage", ".online_update_backup",
    ".self_update", ".wire_update", ".easy_deployment_source.lua" }) do
    remove(fs.combine(ROOT, name))
end
for _, folder in ipairs({ ROOT, fs.combine(ROOT, "lib"), "/" }) do
    if fs.exists(folder) and fs.isDir(folder) then
        for _, name in ipairs(fs.list(folder)) do
            if name:match("%.tmp$") or name:match("%.watchdog_update$")
                or name:match("%.lua%.update$") then
                remove(fs.combine(folder, name))
            end
        end
    end
end
say("Free space now: " .. kib(free()), colors.lime)

-- 2. The Bank's data, only if it still does not fit.
local ok, config = pcall(dofile, fs.combine(ROOT, "config.lua"))
local dataPath = fs.combine(ROOT, ok and type(config) == "table"
    and config.data_file or "bank_data_v5.dat")
if not fs.exists(dataPath) then
    say("No Bank data at " .. dataPath .. " - nothing more to do.")
else
    local size = fs.getSize(dataPath)
    say("Bank data: " .. kib(size))
    if free() >= size + INSTALL_ROOM then
        say("That is enough room. Type: reboot", colors.lime)
        return
    end
    say("Still short. Trimming history (balances are not touched)...",
        colors.orange)
    local handle = fs.open(dataPath, "r")
    local state = textutils.unserialize(handle.readAll())
    handle.close()
    if type(state) ~= "table" or type(state.accounts) ~= "table" then
        say("The Bank data could not be read. Nothing was changed.", colors.red)
        return
    end
    local dropped = 0
    if type(state.transactions) == "table" then
        local kept, counted = {}, {}
        for index = #state.transactions, 1, -1 do
            local tx = state.transactions[index]
            local id = type(tx) == "table" and tx.account_id or "?"
            counted[id] = (counted[id] or 0) + 1
            if counted[id] <= KEEP.transactions then
                table.insert(kept, 1, tx)
            else
                dropped = dropped + 1
            end
        end
        state.transactions = kept
    end
    for _, account in pairs(state.accounts) do
        local notes = account.notifications
        if type(notes) == "table" then
            while #notes > KEEP.notifications do
                table.remove(notes)
                dropped = dropped + 1
            end
        end
    end
    local body = textutils.serialize(state, { compact = true })
    if free() < #body + 1024 then
        say("Even trimmed it needs " .. kib(#body) .. " to save and there is "
            .. kib(free()) .. ". Nothing was changed.", colors.red)
        return
    end
    local temp = dataPath .. ".tmp"
    local writer = fs.open(temp, "w")
    writer.write(body)
    writer.close()
    fs.delete(dataPath)
    fs.move(temp, dataPath)
    say("Trimmed " .. dropped .. " old records. Data is now " .. kib(#body),
        colors.lime)
    say("Free space now: " .. kib(free()), colors.lime)
end
say("Type: reboot", colors.lime)
