-- Every program is stamped with its release, and every role updates itself.
--
-- Both halves of this went wrong quietly. The builder stamped PROGRAM_VERSION
-- from a list kept by hand, and nobody added the programs written after 9.0 --
-- so bank_app_server.lua shipped for three releases still calling itself
-- 9.0.0. Worse, neither it nor ccg_server.lua ever called net.autoUpdate, so
-- a 3rd Party Bank Server installed in 9.0 was still running the 9.0 file
-- three releases later and had no way of knowing.
--
-- Nothing here is a list of its own: it reads the manifest and the installer,
-- so a program added in future is covered without anybody remembering to.

local function readFile(path)
    local handle = assert(io.open(path, "r"), "cannot read " .. path)
    local body = handle:read("*a")
    handle:close()
    return body
end

local manifest = readFile("../release_manifest.json")
local release = manifest:match('"version"%s*:%s*"([%d%.]+)"')
assert(release, "the manifest has no version")

-- Everything published that is a program rather than a library.
local published = {}
for path in manifest:gmatch('"path"%s*:%s*"([^"]+)"') do
    if path:match("%.lua$") and not path:match("^lib/") then
        published[path] = true
    end
end
assert(published["bank_server.lua"] and published["pumpe.lua"],
    "the manifest was not read as expected")

local stamped, unstamped = 0, {}
for path in pairs(published) do
    local body = readFile("../" .. path)
    local version = body:match('local PROGRAM_VERSION = "([%d%.]+)"')
    if version then
        stamped = stamped + 1
        assert(version == release, path .. " is stamped " .. version
            .. " but this release is " .. release
            .. " -- it will report the wrong version for as long as it runs")
    else
        unstamped[#unstamped + 1] = path
    end
end
assert(stamped >= 10, "only " .. stamped .. " programs carry a version")

-- Every role Easy Deployment can install has to keep itself current. A role
-- that never calls net.autoUpdate is frozen on whatever release installed
-- it, and nothing on the network can move it.
local installer = readFile("../installer.lua")
local programBlock = installer:match("local rolePrograms = {(.-)\n}")
assert(programBlock, "rolePrograms was not found")

local frozen = {}
for id, file in programBlock:gmatch('([%w_]+)%s*=%s*"([%w_%.]+)"') do
    -- The Bank is the one exception: it is updated by Easy Deployment
    -- itself from the public manifest, not by net.autoUpdate.
    if id ~= "bank" and id ~= "tax" then
        local body = readFile("../" .. file)
        if not body:find("net.autoUpdate", 1, true) then
            frozen[#frozen + 1] = id .. " (" .. file .. ")"
        end
    end
end
assert(#frozen == 0,
    "these roles never update themselves, so they stay on whatever release"
        .. " installed them: " .. table.concat(frozen, ", "))

-- A role the installer knows and the Bank does not is a computer that boots,
-- asks its Bank for its program, is told there is no such role, and stops.
-- That is what 9.3.0 did to every Vault: the role was added to the installer
-- and not to RELEASE.programs, so becoming a Vault ended in "ROLE FILE
-- MISSING -- Run Easy Deployment again" and a computer that turned itself
-- off. Both lists are read here rather than restated, so a role added to one
-- and forgotten in the other fails before it ships.
local bank = readFile("../bank_server.lua")
local servedBlock = bank:match("RELEASE%.programs = {(.-)\n}")
assert(servedBlock, "RELEASE.programs was not found in bank_server.lua")
local served = {}
for id, file in servedBlock:gmatch('([%w_]+)%s*=%s*"([%w_%.]+)"') do
    served[id] = file
end

local unservable, mismatched = {}, {}
for id, file in programBlock:gmatch('([%w_]+)%s*=%s*"([%w_%.]+)"') do
    if not served[id] then
        unservable[#unservable + 1] = id .. " (" .. file .. ")"
    elseif served[id] ~= file then
        mismatched[#mismatched + 1] = id .. ": installer wants " .. file
            .. ", the Bank serves " .. served[id]
    end
end
assert(#unservable == 0,
    "Easy Deployment cannot serve these roles, so a computer installed as"
        .. " one boots and stops: " .. table.concat(unservable, ", "))
assert(#mismatched == 0,
    "the installer and the Bank disagree about which program a role runs: "
        .. table.concat(mismatched, "; "))

print("host_program_version_test: OK (" .. stamped .. " programs stamped v"
    .. release .. ", every role self-updating and servable)")
