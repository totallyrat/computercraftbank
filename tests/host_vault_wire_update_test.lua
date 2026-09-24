-- Updating a Bank Vault over the pair cable, 11.0.
--
-- The Core sends the Vault the release the Core runs; the Vault takes it only
-- from its own Core, only if it is newer, only the files a Vault installs,
-- each checked against what was announced, and installs it the way an
-- internet update is installed: config.lua merged with its own settings,
-- every file or none. The disk here is in memory, so what the update did to
-- it can be read back.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local core, vault = bank.core, bank.vault
local config = require("config")
local util = require("lib.util")
local update = require("lib.update")

-- A disk in memory ---------------------------------------------------------------------

local disk = {}
local function norm(path)
    path = tostring(path):gsub("/+", "/")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return (path:gsub("/$", ""))
end
local function under(path, prefix) return path:sub(1, #prefix + 1) == prefix .. "/" end
fs = {
    combine = function(left, right)
        return norm(tostring(left) .. "/" .. tostring(right))
    end,
    getDir = function(path)
        return (norm(path):match("^(.*)/[^/]*$") or "")
    end,
    exists = function(path)
        path = norm(path)
        if disk[path] then return true end
        for name in pairs(disk) do if under(name, path) then return true end end
        return false
    end,
    isDir = function(path)
        path = norm(path)
        for name in pairs(disk) do if under(name, path) then return true end end
        return false
    end,
    makeDir = function() end,
    delete = function(path)
        path = norm(path)
        disk[path] = nil
        for name in pairs(disk) do if under(name, path) then disk[name] = nil end end
    end,
    move = function(from, to)
        from, to = norm(from), norm(to)
        assert(not disk[to], "move onto an existing file: " .. to)
        if disk[from] then disk[to], disk[from] = disk[from], nil return end
        for name, body in pairs(disk) do
            if under(name, from) then
                disk[to .. name:sub(#from + 1)], disk[name] = body, nil
            end
        end
    end,
    getFreeSpace = function() return 1000000 end,
    open = function(path, mode)
        path = norm(path)
        if mode == "r" then
            local body = disk[path]
            if not body then return nil end
            return { readAll = function() return body end, close = function() end }
        end
        local parts = {}
        return { write = function(text) parts[#parts + 1] = text end,
            close = function() disk[path] = table.concat(parts) end }
    end,
}
local realLoadfile = loadfile
loadfile = function(path, ...)
    if disk[norm(path)] then return load(disk[norm(path)], path) end
    return realLoadfile(path, ...)
end
-- Enough of textutils for a config table.
local function serialize(value, indent)
    indent = indent or ""
    if type(value) == "table" then
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local lines = { "{" }
        for _, key in ipairs(keys) do
            local name = type(key) == "string" and ("[" .. string.format("%q", key) .. "]")
                or ("[" .. tostring(key) .. "]")
            lines[#lines + 1] = indent .. "  " .. name .. " = "
                .. serialize(value[key], indent .. "  ") .. ","
        end
        lines[#lines + 1] = indent .. "}"
        return table.concat(lines, "\n")
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end
-- The real one takes an options table second; this ignores it.
textutils = { serialize = function(value) return serialize(value) end }
util.readFile = function(path) return disk[norm(path)] end

-- The release ------------------------------------------------------------------------
-- A Core that has moved on to 99.0.0, and a published release of it.

local vaultVersion = core.pair.ask("VAULT_STATUS", {}).version
local RELEASE = {
    ["bank_vault.lua"] = "-- the Vault, 99.0.0\nreturn true\n",
    ["startup.lua"] = "-- Easy Deployment, 99.0.0\n",
    ["config.lua"] = 'return { version = "99.0.0", bank_name = "Foxy",'
        .. ' pair_protocol = "PUMPE_PAIR_V1" }\n',
    ["lib/net.lua"] = "-- net 99\n", ["lib/ui.lua"] = "-- ui 99\n",
    ["lib/update.lua"] = "-- update 99\n", ["lib/util.lua"] = "-- util 99\n",
}
local manifest = { version = "99.0.0", files = {} }
for path, body in pairs(RELEASE) do
    manifest.files[#manifest.files + 1] = { path = path, size = #body,
        checksum = util.checksum(body) }
end
local fetched = {}
update.fetchManifest = function() return manifest end
update.fetchFile = function(_, file)
    fetched[#fetched + 1] = file.path
    return RELEASE[file.path]
end

-- The Core's own disk: the shared files as published, and its own config.
for _, path in ipairs({ "lib/net.lua", "lib/ui.lua", "lib/update.lua", "lib/util.lua" }) do
    disk["/pumpe/" .. path] = RELEASE[path]
end
disk["/pumpe/installer.lua"] = RELEASE["startup.lua"]
disk["/pumpe/config.lua"] = 'return { version = "99.0.0", bank_name = "Core" }\n'
disk["/pumpe/bank_vault.lua"] = "-- the Vault as it is now\n"
config.update_manifest_url = "https://example.invalid/release_manifest.json"
-- This computer's own setting, which an update must keep.
config.bank_name = "Fox Bank Local"

-- Nothing to do while they agree.
config.version = vaultVersion
local pushed, why = core.pair.updateVault(true)
assert(not pushed and why == "current", "no update while both run the same release")

config.version = "99.0.0"

-- Only its own Core may start one, only for something newer, only its files.
local good = {}
for path, body in pairs(RELEASE) do
    local installed = update.installPath(path)
    good[#good + 1] = { path = installed, size = #body, checksum = util.checksum(body) }
end
rejected(vault.vault.VAULT_UPDATE_BEGIN, "NOT_MY_CORE",
    { version = "99.0.0", files = good }, 77)
rejected(vault.vault.VAULT_UPDATE_BEGIN, "NOT_NEWER",
    { version = vaultVersion, files = good }, bank.core_id)
local sneaky = util.copy(good)
sneaky[#sneaky + 1] = { path = "bank_server.lua", size = 1, checksum = "x" }
rejected(vault.vault.VAULT_UPDATE_BEGIN, "BAD_PATH",
    { version = "99.0.0", files = sneaky }, bank.core_id)
local climbing = util.copy(good)
climbing[1].path = "../startup.lua"
rejected(vault.vault.VAULT_UPDATE_BEGIN, "BAD_PATH",
    { version = "99.0.0", files = climbing }, bank.core_id)

-- Pieces in order, and a file that arrives damaged changes nothing.
vault.vault.VAULT_UPDATE_BEGIN({ version = "99.0.0", files = good }, bank.core_id)
local program = RELEASE["bank_vault.lua"]
rejected(vault.vault.VAULT_UPDATE_CHUNK, "OUT_OF_ORDER",
    { path = "bank_vault.lua", offset = 5, data = "x" }, bank.core_id)
for _, file in ipairs(good) do
    local body = file.path == "installer.lua" and RELEASE["startup.lua"]
        or RELEASE[file.path]
    if file.path == "bank_vault.lua" then body = program:gsub("Vault", "VAULT") end
    vault.vault.VAULT_UPDATE_CHUNK({ path = file.path, offset = 1, data = body },
        bank.core_id)
end
rejected(vault.vault.VAULT_UPDATE_COMMIT, "DAMAGED", { version = "99.0.0" },
    bank.core_id)
assert(disk["/pumpe/bank_vault.lua"] == "-- the Vault as it is now\n",
    "a damaged update leaves the Vault as it was")
assert(not vault.wire.restart)

-- The real thing, from the Core's scheduler -----------------------------------------------

local done, err = core.pair.updateVault(true)
assert(done, "the Vault was updated over the cable: " .. tostring(err))
table.sort(fetched)
assert(table.concat(fetched, ",") == "bank_vault.lua,config.lua",
    "only the Vault's program and the published config were downloaded: "
        .. table.concat(fetched, ","))
assert(disk["/pumpe/bank_vault.lua"] == RELEASE["bank_vault.lua"], "the program is in place")
assert(disk["/pumpe/installer.lua"] == RELEASE["startup.lua"])
local merged = assert(loadfile("/pumpe/config.lua"))()
assert(merged.version == "99.0.0", "the config names the new release")
assert(merged.bank_name == "Fox Bank Local", "and keeps this computer's own settings")
assert(merged.pair_protocol == "PUMPE_PAIR_V1", "and takes the release's new ones")
assert(not disk["/pumpe/.wire_update/bank_vault.lua"] and not fs.exists("/pumpe/.wire_backup"),
    "nothing staged is left behind")
assert(vault.wire.restart, "and the Vault restarts into it")

-- A release this Core does not run yet is not sent: the Core updates first.
vault.wire.restart = false
manifest.version = "100.0.0"
local moved, movedWhy = core.pair.updateVault(true)
assert(not moved and tostring(movedWhy):find("updates first", 1, true))

-- Paired, the Vault waits for its Core; alone, it updates itself.
assert(vault.updates_itself() == false)
local id = vault.core.id
vault.core.id = nil
assert(vault.updates_itself() == true)
vault.core.id = id

-- And both are wired to run: the Core's scheduler offers the update, and
-- the Vault's own loop restarts into it once the reply has gone.
local function source(path)
    local handle = assert(io.open(path, "r"))
    local body = handle:read("*a")
    handle:close()
    return body
end
local scheduler = source("../bank_server.lua"):match(
    "local function schedulerLoop%(%)(.-)\nend\n")
assert(scheduler and scheduler:find("pair.updateVault", 1, true),
    "the Core's scheduler offers its Vault each new release")
local sweep = source("../bank_vault.lua"):match("local function sweepLoop%(%)(.-)\nend\n")
assert(sweep and sweep:find("wire.restart", 1, true) and sweep:find("os.reboot", 1, true),
    "the Vault restarts into a release it was sent")

print("host_vault_wire_update_test: OK")
