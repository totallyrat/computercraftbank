-- Easy Deployment, 12.0: a downloader.
--
-- The PUMPE has the first screen; the down arrow, or typing, searches every
-- program; each installs straight from the published release, checked
-- against the manifest, and nothing is asked of a Bank Server. A computer
-- boots through its installed copy, which starts the program beside it --
-- /pumpe, or wherever a Bank built by hand keeps its files -- after updating
-- it when the release is newer.
--
-- It was rebuilt because 11.2 Banks handed devices their own program as
-- the installer, and every device, whatever was picked, restarted as a Bank.
-- The last part here is the one that decides whether this can be published
-- at all: an 11.2 Bank in either layout updating itself into this release,
-- and starting again.

package.path = "./?.lua;../?.lua;" .. package.path

local h = require("installer_harness")
local published = h.manifest.version
local key, typed, tap, expect = h.key, h.typed, h.tap, h.expect

local function fresh(options)
    options = options or {}
    options.disk = options.disk or { ["startup.lua"] = h.installer }
    return h.computer(options)
end

local function bootEntry(id)
    return '-- PUMPE ROLE STARTUP\nshell.run("/pumpe/installer.lua", "--boot", "'
        .. id .. '")\n'
end

local function loadConfig(body)
    return assert(load(assert(body, "no config.lua"), "=config", "t", {}))()
end

-- Messages last a moment and are gone by the next question; this is
-- everything the computer ever drew.
local function said(seen, text)
    for _, line in ipairs(seen.drawn) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function snapshot(disk)
    local copy = {}
    for path, body in pairs(disk) do copy[path] = body end
    return copy
end

local function sameDisk(a, b)
    for path, body in pairs(a) do if b[path] ~= body then return false, path end end
    for path in pairs(b) do if a[path] == nil then return false, path end end
    return true
end

local function noLeftovers(disk)
    for path in pairs(disk) do
        assert(not path:find("%.deploy_") and not path:find("%.update$")
            and not path:find("%.previous$"), "left behind: " .. path)
    end
end

-- Everything a program installs, from lib/update.lua: the list a program
-- updates itself by. Easy Deployment keeps its own copy, since it runs
-- before anything else is on the computer; the two have to agree.
local update = select(1, h.environment(h.computer(), {})).require("lib.update")
local function expectedFiles(id)
    local files = {}
    for _, path in ipairs(update.rolePaths(id)) do files[path] = true end
    return files
end

local function assertInstalled(computer, id, program)
    local disk = computer.disk
    assert(disk["startup.lua"] == bootEntry(id), id .. ": boots into it: "
        .. tostring(disk["startup.lua"]))
    for path in pairs(expectedFiles(id)) do
        local installed = path == "startup.lua" and "installer.lua" or path
        if path ~= "config.lua" then
            assert(disk["pumpe/" .. installed] == h.published(path),
                id .. ": " .. installed .. " is the published file")
        end
    end
    assert(disk["pumpe/" .. program], id .. ": its program")
    local config = loadConfig(disk["pumpe/config.lua"])
    assert(config.version == published, id .. ": the release's config")
    noLeftovers(disk)
    return config
end

-- The PUMPE, from the first screen ------------------------------------------------------

local phone = fresh()
local seen = h.run(phone, {
    function(screen)
        assert(h.has(screen, "PERSONAL PUMPE") and h.has(screen, "INSTALL PUMPE")
            and h.has(screen, "SEARCH ALL PROGRAMS"),
            "the first screen is the PUMPE's:\n" .. table.concat(screen, "\n"))
        assert(select(2, h.where(screen, "PERSONAL PUMPE")) == 8,
            "under the big wordmark")
        return key("enter")
    end,
})
assert(seen.rebooted, "installed, it restarts into the PUMPE")
local config = assertInstalled(phone, "pumpe", "pumpe.lua")
assert(config.government_key == "CLIENT-NO-GOVERNMENT-ACCESS",
    "a phone never carries the government key")
assert(not phone.disk["pumpe/bank_server.lua"], "and never the Bank's program")
assert(phone.disk["pumpe/installer.lua"] == h.installer,
    "its installer is Easy Deployment itself")
do
    local allowed = { ["release_manifest.json"] = true }
    for path in pairs(expectedFiles("pumpe")) do allowed[h.sources[path]] = true end
    for _, source in ipairs(phone.fetched) do
        assert(allowed[source], "it downloaded " .. source .. " too")
    end
end

-- A tap does the same.
phone = fresh()
seen = h.run(phone, { tap("INSTALL PUMPE") })
assert(seen.rebooted)
assertInstalled(phone, "pumpe", "pumpe.lua")

-- Then it boots: the program beside the installer starts, and nothing on
-- the disk changes when the release is the one installed.
local before = snapshot(phone.disk)
phone.fetched = {}
seen = h.run(phone, {}, { "--boot", "pumpe" }, "pumpe/installer.lua")
assert(#seen.launched == 1 and seen.launched[1] == "pumpe/pumpe.lua",
    "it starts the PUMPE: " .. table.concat(seen.launched, ", "))
assert(sameDisk(before, phone.disk), "and changes nothing")
assert(#phone.fetched == 1 and phone.fetched[1] == "release_manifest.json",
    "one look at the release, no downloads")

-- Search ---------------------------------------------------------------------------------

-- The down arrow opens it; the results follow every key.
local kiosk = fresh()
seen = h.run(kiosk, h.concat(
    key("down"),
    expect("Type to search", { "char", "s" }),
    typed("hop"),
    function(screen)
        local _, y = h.where(screen, "Service Kiosk")
        assert(y == 6, "the first result is the kiosk:\n" .. table.concat(screen, "\n"))
        assert(h.has(screen, "> shop_"), "the box shows what was typed")
        return key("enter")
    end,
    expect("SERVICE KIOSK", key("enter"))
))
assert(seen.rebooted)
assertInstalled(kiosk, "service", "service_kiosk.lua")

-- Typing on the first screen starts a search with what was typed.
local function firstResult(query)
    local found
    local computer = fresh()
    h.run(computer, h.concat(
        { "char", query:sub(1, 1) },
        typed(query:sub(2)),
        function(screen)
            local line = screen[6] or ""
            found = line:match("^%s*(.-)%s*$")
            return { "terminate" }
        end
    ))
    assert(computer.disk["startup.lua"] == h.installer, "searching installs nothing")
    return found
end
assert(firstResult("ccg") == "CCG Bet Console")
assert(firstResult("casino") == "CCG Bet Console", "keywords count")
assert(firstResult("web") == "Internet Server")
assert(firstResult("gps") == "GPS Anchor")
assert(firstResult("bank") == "Bank Server")
assert(firstResult("vault") == "Bank Vault")
assert(firstResult("pickup") == "Delivery Terminal")
assert(firstResult("third") == "3rd Party Bank Server")
assert(firstResult("SERVER BANK") == "Bank Server", "any order, any case")

local nothing = fresh()
h.run(nothing, h.concat(key("down"), typed("zebra"),
    expect("Nothing matches", { "terminate" })))

-- Back to the PUMPE: up from the first result, backspace on an empty box,
-- or the button.
for _, back in ipairs({
    { key("down"), key("up") },
    { key("down"), { "char", "x" }, key("backspace"), key("backspace") },
    { key("down"), tap("^ PUMPE") },
}) do
    local computer = fresh()
    local script = h.concat(back, expect("INSTALL PUMPE", { "terminate" }))
    seen = h.run(computer, script)
    assert(seen.ok, "back on the first screen, then out")
end

-- Down moves through the results; a tap opens one.
local web = fresh()
h.run(web, h.concat(key("down"), typed("server"), key("down"),
    function(screen)
        return tap("Internet Server")(screen)
    end,
    expect("INTERNET SERVER", tap("< BACK")),
    expect("> server_", { "terminate" })))

-- The operator's code --------------------------------------------------------------------

local bank = fresh()
seen = h.run(bank, h.concat(
    key("down"), typed("bank"), key("enter"),
    expect("BANK SERVER", key("enter")),
    expect("OPERATOR CODE", { "char", "1" }), typed("234"),
    -- Wrong: nothing is installed, and the Bank's screen is back.
    expect("BANK SERVER", key("enter")),
    typed("4040")
))
assert(seen.rebooted)
assert(said(seen, "OPERATOR CODE") and said(seen, "WRONG CODE"),
    "the code is asked for, and a wrong one refused")
config = assertInstalled(bank, "bank", "bank_server.lua")
assert(bank.disk["pumpe/config.lua"] == h.published("config.lua"),
    "a new Bank gets the release's config exactly, comments and all")
assert(config.government_key ~= "CLIENT-NO-GOVERNMENT-ACCESS")
assert(bank.disk["pumpe/bank_server.lua"] == h.readRepo("dist/bank_server.lua"),
    "the Bank's published build")

-- Every program --------------------------------------------------------------------------
-- Found by its name, installed, booted into. A program Easy Deployment can
-- install and not start is a computer that stops on its next boot.

local installer = h.installer
local programs = {}
for id, name, file in installer:gmatch('{ id = "([%w_]+)", name = "([^"]+)", file = "([%w_%.]+)"') do
    programs[#programs + 1] = { id = id, name = name, file = file }
end
assert(#programs >= 15, "the program list was not found")
for _, program in ipairs(programs) do
    local hidden = program.id == "tax"
    local roleFiles = update.rolePaths(program.id)
    if program.id ~= "tax" then
        assert(roleFiles and roleFiles[1] == program.file,
            program.id .. ": lib/update.lua must agree on its program")
    end
    if not hidden then
        local computer = fresh()
        local script = h.concat(key("down"), typed(program.name), key("enter"),
            expect(string.upper(program.name), key("enter")))
        if program.id == "bank" or program.id == "admin" then
            script = h.concat(script, typed("4040"))
        end
        seen = h.run(computer, script)
        assert(seen.rebooted, program.id .. " did not install")
        assertInstalled(computer, program.id, program.file)
        local expected, count = expectedFiles(program.id), 0
        for path in pairs(computer.disk) do
            if path:sub(1, 6) == "pumpe/" then count = count + 1 end
        end
        local want = 0
        for _ in pairs(expected) do want = want + 1 end
        assert(count == want, program.id .. ": exactly its own files, " .. count
            .. " of " .. want)
        seen = h.run(computer, {}, { "--boot", program.id }, "pumpe/installer.lua")
        assert(seen.launched[1] == "pumpe/" .. program.file,
            program.id .. " does not start: " .. table.concat(seen.launched, ", "))
    end
end

-- Reinstalling keeps settings ------------------------------------------------------------

local kept = fresh({ disk = {
    ["startup.lua"] = bootEntry("pumpe"),
    ["pumpe/installer.lua"] = h.installer,
    ["pumpe/pumpe.lua"] = "-- an older PUMPE",
    ["pumpe/pumpe_data.dat"] = "mine",
    ["pumpe/config.lua"] = 'return { version = "11.2.0", release_name = "11.2",'
        .. ' currency = "E", government_key = "Government1234" }\n',
} })
seen = h.run(kept, {
    expect("OPEN PUMPE", tap("REINSTALL")),
}, nil, "pumpe/installer.lua")
assert(seen.rebooted)
config = assertInstalled(kept, "pumpe", "pumpe.lua")
assert(config.currency == "E", "its own settings stay")
assert(config.release_name == h.manifest.label, "the release's name does not")
assert(config.government_key == "CLIENT-NO-GOVERNMENT-ACCESS",
    "and a phone that somehow had the key loses it")
assert(kept.disk["pumpe/pumpe_data.dat"] == "mine", "its data is not touched")

-- A /startup.lua that is somebody's own program is kept, and what was
-- installed is started straight away instead of on a restart that would
-- not reach it.
local own = fresh({ disk = {
    ["startup.lua"] = "print('my own startup')",
    ["installer.lua"] = h.installer,
} })
seen = h.run(own, { key("enter") }, nil, "installer.lua")
assert(not seen.rebooted and seen.launched[1] == "pumpe/pumpe.lua",
    "started now, not on a restart")
assert(own.disk["startup.lua"] == "print('my own startup')", "their startup is kept")
assert(said(seen, "was kept"))

-- What cannot be installed ---------------------------------------------------------------

-- HTTP switched off.
local offline = fresh({ http = false })
seen = h.run(offline, { expect("HTTP is off", key("enter")), { "terminate" } })
assert(said(seen, "HTTP IS OFF"), "it says why")
assert(offline.disk["startup.lua"] == h.installer and not offline.disk["pumpe/pumpe.lua"],
    "and nothing was installed")

-- A file that is not the one the release describes -- the right size, one
-- byte changed: nothing goes in.
local realUi = h.readRepo("dist/lib/ui.lua")
local tampered = fresh({ disk = {
    ["startup.lua"] = h.installer,
    ["pumpe/pumpe.lua"] = "-- what was there",
}, served = { ["dist/lib/ui.lua"] = "X" .. realUi:sub(2) } })
before = snapshot(tampered.disk)
seen = h.run(tampered, { key("enter"), { "terminate" } })
assert(said(seen, "INSTALL FAILED") and said(seen, "match the release"))
assert(sameDisk(before, tampered.disk), "a failed download changes nothing")

-- A disk too full to take it.
local full = fresh({ free = 200 * 1024 })
seen = h.run(full, { key("enter"), { "terminate" } })
assert(said(seen, "INSTALL FAILED") and said(seen, "free space"),
    "it says it needs room")
assert(not full.disk["pumpe/pumpe.lua"])

-- Booting --------------------------------------------------------------------------------

-- A newer release is installed on the way up, then the computer restarts.
local stale = fresh({ disk = {
    ["startup.lua"] = bootEntry("pumpe"),
    ["pumpe/installer.lua"] = h.installer,
    ["pumpe/pumpe.lua"] = "-- 11.2",
    ["pumpe/config.lua"] = 'return { version = "11.2.0", currency = "E" }\n',
} })
seen = h.run(stale, {}, { "--boot", "pumpe" }, "pumpe/installer.lua")
assert(seen.rebooted and #seen.launched == 0, "updated first, then restarted")
config = assertInstalled(stale, "pumpe", "pumpe.lua")
assert(config.currency == "E")

-- Except a Vault: its Core updates it over the cable to the Core's own
-- release, and a Vault that went ahead on its own would be answering another
-- release's questions.
local vaultComputer = fresh({ disk = {
    ["startup.lua"] = bootEntry("vault"),
    ["pumpe/installer.lua"] = h.installer,
    ["pumpe/bank_vault.lua"] = "-- 11.2 vault",
    ["pumpe/config.lua"] = 'return { version = "11.2.0" }\n',
} })
before = snapshot(vaultComputer.disk)
seen = h.run(vaultComputer, {}, { "--boot", "vault" }, "pumpe/installer.lua")
assert(not seen.rebooted and seen.launched[1] == "pumpe/bank_vault.lua",
    "a Vault starts on the release its Core gave it")
assert(sameDisk(before, vaultComputer.disk))

-- With no internet it starts what it has.
stale.http = false
stale.disk["pumpe/config.lua"] = 'return { version = "11.2.0" }\n'
seen = h.run(stale, {}, { "--boot", "pumpe" }, "pumpe/installer.lua")
assert(seen.launched[1] == "pumpe/pumpe.lua")

-- A program it does not know opens the menu rather than stopping.
seen = h.run(fresh(), { expect("INSTALL PUMPE", { "terminate" }) },
    { "--boot", "nonsense" })
assert(said(seen, "UNKNOWN PROGRAM"))

-- A counter in Pickup mode ignores Ctrl+T from the start, and a program that
-- ends is started again rather than leaving the shell at a public counter.
local counter = fresh({ disk = {
    ["startup.lua"] = bootEntry("delivery"),
    ["pumpe/installer.lua"] = h.installer,
    ["pumpe/delivery_terminal.lua"] = "-- counter",
    ["pumpe/keyboard.lock"] = "locked",
    ["pumpe/config.lua"] = 'return { version = "' .. published .. '" }\n',
} })
seen = h.run(counter, {}, { "--boot", "delivery" }, "pumpe/installer.lua")
assert(seen.env.os.pullEvent == seen.env.os.pullEventRaw, "Ctrl+T is ignored")
assert(seen.launched[1] == "pumpe/delivery_terminal.lua" and seen.rebooted)
-- Only a Delivery Terminal.
counter.disk["startup.lua"] = bootEntry("pumpe")
counter.disk["pumpe/pumpe.lua"] = "-- phone"
seen = h.run(counter, {}, { "--boot", "pumpe" }, "pumpe/installer.lua")
assert(seen.env.os.pullEvent ~= seen.env.os.pullEventRaw)

-- lib/net's fallback: only a newer release, then a restart.
local auto = fresh({ disk = {
    ["pumpe/installer.lua"] = h.installer,
    ["pumpe/pumpe.lua"] = "-- 11.2",
    ["pumpe/config.lua"] = 'return { version = "11.2.0" }\n',
} })
seen = h.run(auto, {}, { "--auto", "pumpe" }, "pumpe/installer.lua")
assert(seen.rebooted and auto.disk["pumpe/pumpe.lua"] == h.published("pumpe.lua"))
auto.fetched = {}
seen = h.run(auto, {}, { "--auto", "pumpe" }, "pumpe/installer.lua")
assert(seen.ok and seen.result == false and #auto.fetched == 1,
    "current: nothing is downloaded")

-- Keeping itself current ------------------------------------------------------------------

-- An older Easy Deployment replaces its own file with the published one and
-- restarts, on the menu and on every boot.
local older = h.installer:gsub('INSTALLER_VERSION = "[%d%.]+"',
    'INSTALLER_VERSION = "11.2.0"', 1)
for _, run in ipairs({
    { path = "startup.lua", args = nil },
    { path = "pumpe/installer.lua", args = { "--boot", "pumpe" } },
}) do
    local computer = fresh({ disk = {
        [run.path] = older,
        ["pumpe/pumpe.lua"] = h.published("pumpe.lua"),
        ["pumpe/config.lua"] = 'return { version = "' .. published .. '" }\n',
    } })
    seen = h.run(computer, {}, run.args, run.path)
    assert(seen.rebooted and computer.disk[run.path] == h.installer,
        run.path .. " did not update itself")
    noLeftovers(computer.disk)
end

-- It trusts the downloaded file's own version: a release published with a
-- stale stamp would otherwise install the same file and restart for ever.
do
    local function djb2(body)
        local hash = 5381
        for index = 1, #body do hash = (hash * 33 + body:byte(index)) % 4294967296 end
        return string.format("%08x", hash)
    end
    local manifest = h.readRepo("release_manifest.json")
    local startupEntry = '"path": "startup.lua",%s*"source": "startup.lua",%s*"size": %d+,%s*"checksum": "%x+"'
    assert(manifest:find(startupEntry), "the manifest's installer entry")
    local restamped = manifest:gsub(startupEntry, '"path": "startup.lua", "source": '
        .. '"startup.lua", "size": ' .. #older .. ', "checksum": "' .. djb2(older) .. '"')
    local computer = fresh({ disk = {
        ["pumpe/installer.lua"] = older,
        ["pumpe/pumpe.lua"] = h.published("pumpe.lua"),
        ["pumpe/config.lua"] = 'return { version = "' .. published .. '" }\n',
    }, served = { ["release_manifest.json"] = restamped, ["startup.lua"] = older } })
    seen = h.run(computer, {}, { "--boot", "pumpe" }, "pumpe/installer.lua")
    assert(not seen.rebooted and seen.launched[1] == "pumpe/pumpe.lua",
        "no endless restarts")
end

-- An 11.2 Bank updating itself into this release ---------------------------------------
-- The Bank updates with lib/update.lua, unchanged since 11.2, into the folder
-- its program runs from. Then it restarts through /startup.lua, which names
-- the installer copy in that same folder -- now this Easy Deployment. On the
-- Banks that caused all this, that copy was the Bank's own program, and the
-- folder may not be /pumpe. Either way the Bank has to come back up, on its
-- own data, with its own government key.

local function bankOn(root)
    local at = function(path) return root == "" and path or (root .. "/" .. path) end
    local disk = {
        ["startup.lua"] = '-- PUMPE ROLE STARTUP\nshell.run("/' .. at("installer.lua")
            .. '", "--boot", "bank")\n',
        [at("installer.lua")] = h.readRepo("dist/bank_server.lua"),
        [at("config.lua")] = 'return { version = "11.2.0", release_name = "11.2",'
            .. ' government_key = "Secret", data_file = "bank_data_v5.dat",'
            .. ' update_manifest_url = "https://raw.githubusercontent.com/totallyrat/'
            .. 'computercraftbank/main/release_manifest.json" }\n',
        [at("bank_data_v5.dat")] = "{ accounts = {} }",
        [at("bank_pair_v1.dat")] = "{ role = \"core\" }",
    }
    for _, name in ipairs({ "net", "ui", "update", "util" }) do
        disk[at("lib/" .. name .. ".lua")] = "-- 11.2 " .. name
    end
    return h.computer({ disk = disk }), at
end

for _, root in ipairs({ "pumpe", "" }) do
    local computer, at = bankOn(root)
    local startup = computer.disk["startup.lua"]
    -- The running Bank's own update.
    local env = h.environment(computer, {}, at("installer.lua"))
    local bankUpdate = env.require("lib.update")
    local bankConfig = loadConfig(computer.disk[at("config.lua")])
    local updated, detail = bankUpdate.selfUpdate({ config = bankConfig, role = "bank",
        root = root, requiredPaths = bankUpdate.PUBLISHED_FILES,
        optionalPaths = bankUpdate.PUBLISHED_OPTIONAL, repair = true })
    assert(updated and detail == published, "the Bank updated: " .. tostring(detail))
    assert(computer.disk[at("installer.lua")] == h.installer,
        "its installer copy is Easy Deployment now")

    -- And restarts.
    seen = h.run(computer, {}, { "--boot", "bank" }, at("installer.lua"))
    assert(#seen.launched == 1 and seen.launched[1] == at("bank_server.lua"),
        "the Bank in '" .. root .. "' starts again: " .. table.concat(seen.launched, ", "))
    assert(computer.disk["startup.lua"] == startup, "/startup.lua is left as it was")
    assert(computer.disk[at("bank_data_v5.dat")] == "{ accounts = {} }",
        "on its own data")
    assert(loadConfig(computer.disk[at("config.lua")]).government_key == "Secret",
        "with its own government key")
    if root == "" then
        for path in pairs(computer.disk) do
            assert(path:sub(1, 6) ~= "pumpe/", "nothing was put in /pumpe: " .. path)
        end
    end
    noLeftovers(computer.disk)
end

-- Every screen size it runs on ----------------------------------------------------------

for _, size in ipairs({ { 26, 20 }, { 51, 19 }, { 39, 13 }, { 57, 24 } }) do
    local computer = fresh({ width = size[1], height = size[2] })
    h.run(computer, h.concat(
        expect("INSTALL", key("down")),
        typed("kiosk"),
        expect("Service Kiosk", key("enter")),
        expect("SERVICE KIOSK", tap("< BACK")),
        { "terminate" }
    ))
end

print("host_installer_test: OK")
