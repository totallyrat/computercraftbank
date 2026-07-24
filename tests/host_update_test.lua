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

print("host_update_test: OK")
