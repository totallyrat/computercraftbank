-- Host-side tests for online release validation and version ordering.

package.path = "../?.lua;../?/init.lua;" .. package.path

os.day = function() return 1 end
os.time = function() return 12 end
os.epoch = function() return 1 end
os.getComputerID = function() return 1 end

local update = require("lib.update")

assert(update.isNewer("5.1.0", "5.0.2"))
assert(update.isNewer("6.0.0", "5.99.99"))
assert(not update.isNewer("5.1.0", "5.1.0"))
assert(not update.isNewer("5.0.9", "5.1.0"))
assert(not update.isNewer("latest", "5.1.0"))
assert(update.checksum("hello") == "0f923099")

local expected = { "bank_server.lua", "lib/update.lua" }
local manifest = {
    schema = 1,
    channel = "stable",
    version = "5.1.0",
    files = {
        {
            path = "bank_server.lua",
            source = "bank_server.lua",
            size = 100,
            checksum = "1234abcd",
        },
        {
            path = "lib/update.lua",
            source = "lib/update.lua",
            size = 200,
            checksum = "abcdef12",
        },
    },
}

local validated = assert(update.validateManifest(manifest, expected, "stable"))
assert(validated.version == "5.1.0")
assert(#validated.files == 2)

local missing = {
    schema = 1,
    channel = "stable",
    version = "5.1.0",
    files = { manifest.files[1] },
}
assert(update.validateManifest(missing, expected, "stable") == nil)

local unsafe = {
    schema = 1,
    channel = "stable",
    version = "5.1.0",
    files = {
        manifest.files[1],
        {
            path = "lib/update.lua",
            source = "../update.lua",
            size = 200,
            checksum = "abcdef12",
        },
    },
}
assert(update.validateManifest(unsafe, expected, "stable") == nil)

-- A checksum must be exactly eight hex digits.
for _, bad in ipairs({ "1234abcg", "1234abc", "1234abcde", 12345678 }) do
    assert(update.validateManifest({
        schema = 1,
        channel = "stable",
        version = "5.1.0",
        files = {
            manifest.files[1],
            {
                path = "lib/update.lua",
                source = "lib/update.lua",
                size = 200,
                checksum = bad,
            },
        },
    }, expected, "stable") == nil, "accepted checksum " .. tostring(bad))
end

-- Optional roles are published in `extra_files`. Older Bank Servers ignore
-- that array, while current ones install it in the same verified commit.
local optional = { "ccg.lua" }
local withExtra = {
    schema = 1,
    channel = "stable",
    version = "5.1.0",
    files = manifest.files,
    extra_files = {
        {
            path = "ccg.lua",
            source = "ccg.lua",
            size = 300,
            checksum = "00ff11ee",
        },
    },
}
local extended = assert(update.validateManifest(withExtra, expected, "stable",
    optional))
assert(#extended.files == 3, "extra_files must join the download set")
assert(extended.files[3].path == "ccg.lua")

-- A manifest with no extra_files is still complete.
assert(update.validateManifest(manifest, expected, "stable", optional))

-- An unlisted optional path is rejected instead of silently downloaded.
local strayExtra = {
    schema = 1,
    channel = "stable",
    version = "5.1.0",
    files = manifest.files,
    extra_files = {
        {
            path = "evil.lua",
            source = "evil.lua",
            size = 10,
            checksum = "00ff11ee",
        },
    },
}
assert(update.validateManifest(strayExtra, expected, "stable", optional) == nil)

-- Optional files must never appear in `files`; that is exactly the shape a
-- v5.2.1 updater rejects, which would strand older Bank Servers.
local misplaced = {
    schema = 1,
    channel = "stable",
    version = "5.1.0",
    files = {
        manifest.files[1], manifest.files[2],
        {
            path = "ccg.lua",
            source = "ccg.lua",
            size = 300,
            checksum = "00ff11ee",
        },
    },
}
assert(update.validateManifest(misplaced, expected, "stable", optional) == nil)

-- Exercise HTTPS fetching, staged file verification, atomic commit, and
-- rollback with an in-memory ComputerCraft filesystem.
local files = {}
local directories = { ["/"] = true }
local failMoveDestination

fs = {}
fs.combine = function(left, right)
    return tostring(left):gsub("/+$", "") .. "/"
        .. tostring(right):gsub("^/+", "")
end
fs.getDir = function(path)
    return tostring(path):match("^(.*)/[^/]+$") or ""
end
fs.exists = function(path)
    return files[path] ~= nil or directories[path] == true
end
fs.isDir = function(path)
    return directories[path] == true
end
fs.makeDir = function(path)
    directories[path] = true
end
fs.delete = function(path)
    files[path] = nil
    directories[path] = nil
    local prefix = tostring(path):gsub("/+$", "") .. "/"
    for existing in pairs(files) do
        if existing:sub(1, #prefix) == prefix then files[existing] = nil end
    end
    for existing in pairs(directories) do
        if existing:sub(1, #prefix) == prefix then directories[existing] = nil end
    end
end
fs.move = function(source, destination)
    if destination == failMoveDestination then
        failMoveDestination = nil
        error("simulated move failure")
    end
    assert(files[source] ~= nil, "missing move source " .. source)
    files[destination] = files[source]
    files[source] = nil
end
fs.open = function(path, mode)
    assert(mode == "w")
    local chunks = {}
    return {
        write = function(value) chunks[#chunks + 1] = tostring(value) end,
        close = function() files[path] = table.concat(chunks) end,
    }
end

local remoteBodies = {
    ["bank_server.lua"] = "new bank server",
    ["lib/update.lua"] = "new updater",
}
local remoteManifest = {
    schema = 1,
    channel = "stable",
    version = "5.2.0",
    files = {
        {
            path = "bank_server.lua",
            source = "bank_server.lua",
            size = #remoteBodies["bank_server.lua"],
            checksum = update.checksum(remoteBodies["bank_server.lua"]),
        },
        {
            path = "lib/update.lua",
            source = "lib/update.lua",
            size = #remoteBodies["lib/update.lua"],
            checksum = update.checksum(remoteBodies["lib/update.lua"]),
        },
    },
}

textutils = {
    unserializeJSON = function() return remoteManifest end,
}
http = {
    get = function(request)
        assert(request.redirect == false)
        assert(request.url:match("^https://updates%.example/"))
        local source = request.url:match(
            "^https://updates%.example/(.-)%?pumpe=")
        local body = source == "release_manifest.json"
            and "{}" or remoteBodies[source]
        assert(body, "unexpected HTTP path " .. tostring(source))
        local offset = 1
        return {
            read = function(count)
                if offset > #body then return nil end
                local chunk = body:sub(offset, offset + count - 1)
                offset = offset + #chunk
                return chunk
            end,
            close = function() end,
        }
    end,
}

local fetched = assert(update.fetchManifest(
    "https://updates.example/release_manifest.json",
    expected, "stable"))
assert(fetched.version == "5.2.0")
assert(update.downloadRelease(
    fetched,
    "https://updates.example/release_manifest.json",
    "/stage"))
assert(files["/stage/bank_server.lua"] == "new bank server")
assert(files["/stage/lib/update.lua"] == "new updater")

directories["/pumpe"] = true
directories["/pumpe/lib"] = true
files["/pumpe/bank_server.lua"] = "old bank server"
files["/pumpe/lib/update.lua"] = "old updater"
assert(update.commitRelease(fetched, "/stage", "/pumpe", "/backup"))
assert(files["/pumpe/bank_server.lua"] == "new bank server")
assert(files["/pumpe/lib/update.lua"] == "new updater")

assert(update.downloadRelease(
    fetched,
    "https://updates.example/release_manifest.json",
    "/stage"))
files["/pumpe/bank_server.lua"] = "old bank server"
files["/pumpe/lib/update.lua"] = "old updater"
failMoveDestination = "/pumpe/lib/update.lua"
assert(update.commitRelease(fetched, "/stage", "/pumpe", "/backup") == nil)
assert(files["/pumpe/bank_server.lua"] == "old bank server")
assert(files["/pumpe/lib/update.lua"] == "old updater")

local net = require("lib.net")
local updateRuns = {}
shell = {
    run = function(...)
        updateRuns[#updateRuns + 1] = { ... }
        return true
    end,
}
files["/pumpe/installer.lua"] = "installer"
assert(net.autoUpdate({
    auto_update = true,
    update_check_seconds = 10,
}, "service", "/pumpe"))
assert(#updateRuns == 1)
assert(updateRuns[1][1] == "/pumpe/installer.lua")
assert(updateRuns[1][2] == "--auto")
assert(updateRuns[1][3] == "service")
assert(not net.autoUpdate({
    auto_update = true,
    update_check_seconds = 10,
}, "service", "/pumpe"))
assert(#updateRuns == 1)

assert(net.isNewerVersion("6.1.0", "6.0.3"))
assert(not net.isNewerVersion("6.0.3", "6.1.0"))
assert(not net.isNewerVersion("6.1.0", "6.1.0"))

-- With a Bank connection, a client asks for the Bank's version first and only
-- launches Easy Deployment when a newer release actually exists. That keeps a
-- live dashboard from shelling out a 45 KiB installer on every tick.
local clock = 1
os.epoch = function() return clock end
local function advance() clock = clock + 5000 end

local pings = 0
local function bankAt(version)
    return {
        request = function(_, action)
            assert(action == "PING", "clients must use the cheap version probe")
            pings = pings + 1
            return { version = version }
        end,
    }
end

local clientConfig = {
    auto_update = true,
    client_update_check_seconds = 1,
    version = "6.1.0",
}
advance()
assert(not net.autoUpdate(clientConfig, "event", "/pumpe", bankAt("6.1.0")))
assert(pings == 1 and #updateRuns == 1,
    "a current client must not run the installer at all")

advance()
assert(net.autoUpdate(clientConfig, "event", "/pumpe", bankAt("6.2.0")))
assert(pings == 2 and #updateRuns == 2,
    "a newer Bank release must still trigger the installer")

-- An offline Bank is not a reason to shell out either.
advance()
assert(not net.autoUpdate(clientConfig, "event", "/pumpe", {
    request = function() return nil, "Bank server is offline" end,
}))
assert(#updateRuns == 2)

-- A program from one release beside a config from another is a partial
-- install. It must repair at once, even inside the check interval that would
-- otherwise silence it - which is what leaves a device reporting a version it
-- is not running.
files["/pumpe/installer.lua"] = "installer"
local matched = { auto_update = true, version = "6.9.0" }

-- Prime the interval gate for this role.
net.autoUpdate(matched, "border", "/pumpe", nil, { programVersion = "6.9.0" })
local gated = #updateRuns
assert(not net.autoUpdate(matched, "border", "/pumpe", nil,
    { programVersion = "6.9.0" }))
assert(#updateRuns == gated, "a matching install respects the interval")

-- Same role, same instant, still gated - but now mismatched.
assert(net.autoUpdate(matched, "border", "/pumpe", nil,
    { programVersion = "6.3.0" }),
    "a mismatched install must repair even inside the check interval")
assert(#updateRuns == gated + 1
    and updateRuns[#updateRuns][3] == "border")

-- Self-updating roles --------------------------------------------------------

assert(update.roleProgram("pumpe") == "pumpe.lua")
assert(update.installPath("startup.lua") == "installer.lua",
    "startup.lua is published under that name but installed as installer.lua")

local rolePaths = update.rolePaths("pumpe")
assert(#rolePaths == 7, "a role installs its program, Easy Deployment and libs")
local wanted = {}
for _, path in ipairs(rolePaths) do wanted[path] = true end
assert(wanted["pumpe.lua"] and wanted["lib/ui.lua"] and wanted["startup.lua"])
assert(not wanted["bank_server.lua"], "a PUMPE never downloads the Bank")
assert(not wanted["ccg.lua"], "a PUMPE never downloads another role's program")

local fullManifest = { version = "9.9.9", files = {} }
local bodies = {
    ["bank_server.lua"] = "bank", ["pumpe.lua"] = "phone",
    ["ccg.lua"] = "arcade", ["service_kiosk.lua"] = "pos",
    ["startup.lua"] = "installer", ["lib/net.lua"] = "net",
    ["lib/ui.lua"] = "ui", ["lib/update.lua"] = "updater",
    ["lib/util.lua"] = "util",
    ["config.lua"] = 'return { version = "9.9.9", currency = "$" }',
}
for path, body in pairs(bodies) do
    fullManifest.files[#fullManifest.files + 1] = {
        path = path, source = path, size = #body,
        checksum = update.checksum(body),
    }
end
local chosen = update.filesForRole(fullManifest, "pumpe")
assert(#chosen == 7, "only this role's files are downloaded")
for _, file in ipairs(chosen) do
    assert(file.path ~= "bank_server.lua" and file.path ~= "ccg.lua")
end

-- A full self-update against the in-memory filesystem.
textutils = textutils or {}
textutils.serialize = function(value)
    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = ("  %s = %q,"):format(key, tostring(item))
    end
    table.sort(parts)
    return "{\n" .. table.concat(parts, "\n") .. "\n}"
end
local realLoadfile = loadfile
loadfile = function(path)
    local body = files[path]
    if not body then return realLoadfile(path) end
    return load(body, path)
end

update.fetchManifest = function() return fullManifest end
update.fetchFile = function(_, file) return bodies[file.path] end

local localConfig = {
    version = "1.0.0",
    currency = "G",                       -- an operator customisation
    government_key = "MY-SECRET-KEY",
    update_manifest_url = "https://example.test/release_manifest.json",
    auto_update = true,
}
local rebooted = false
os.reboot = function() rebooted = true end

local updated, detail = update.selfUpdate({
    config = localConfig, role = "pumpe", root = "/pumpe",
})
assert(updated, "a newer release installs: " .. tostring(detail))
assert(files["/pumpe/pumpe.lua"] == "phone")
assert(files["/pumpe/installer.lua"] == "installer",
    "startup.lua lands as installer.lua")
assert(files["/pumpe/bank_server.lua"] ~= "bank",
    "a PUMPE never installs the Bank program")

-- Local settings survive; the version follows the release.
local merged = files["/pumpe/config.lua"]
assert(merged:find('currency = "G"', 1, true),
    "an operator's customisation is preserved across updates")
assert(merged:find('government_key = "MY%-SECRET%-KEY"'),
    "the government key is never reset to the published placeholder")
assert(merged:find('version = "9.9.9"', 1, true), "the version follows the release")

-- Already current.
localConfig.version = "9.9.9"
local again, reason = update.selfUpdate({
    config = localConfig, role = "pumpe", root = "/pumpe",
})
assert(again == false and reason == "current")

-- Out of space: the caller is given a chance to free some, then it proceeds.
localConfig.version = "1.0.0"
local tight, freed = true, false
fs.getFreeSpace = function() return tight and 10 or 900000 end
local blocked, why = update.selfUpdate({
    config = localConfig, role = "pumpe", root = "/pumpe",
})
assert(blocked == nil and tostring(why):find("free space", 1, true),
    "a release that cannot fit reports the shortfall")
local recovered = update.selfUpdate({
    config = localConfig, role = "pumpe", root = "/pumpe",
    onSpaceNeeded = function() tight, freed = false, true end,
})
assert(freed and recovered, "freeing room lets the update proceed")
fs.getFreeSpace = nil
loadfile = realLoadfile

print("host_update_test: OK")
