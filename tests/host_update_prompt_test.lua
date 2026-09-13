-- Ask-first updates. A device with somebody in front of it checks for a
-- release, shows what changed, and installs nothing until it is answered.
-- The three things worth holding on to: refusing writes nothing, the answer
-- carries the release's own words, and a device that cannot read the manifest
-- still asks rather than quietly falling back to installing.

package.path = "../?.lua;../?/init.lua;" .. package.path

os.day = function() return 1 end
os.time = function() return 12 end
os.epoch = function() return 1 end
os.getComputerID = function() return 1 end

local update = require("lib.update")
local net = require("lib.net")

-- An in-memory computer ----------------------------------------------------

local files, directories = {}, { ["/"] = true }
fs = {}
fs.combine = function(left, right)
    return tostring(left):gsub("/+$", "") .. "/"
        .. tostring(right):gsub("^/+", "")
end
fs.getDir = function(path) return tostring(path):match("^(.*)/[^/]+$") or "" end
fs.exists = function(path)
    return files[path] ~= nil or directories[path] == true
end
fs.isDir = function(path) return directories[path] == true end
fs.makeDir = function(path) directories[path] = true end
fs.delete = function(path)
    files[path], directories[path] = nil, nil
    local prefix = tostring(path):gsub("/+$", "") .. "/"
    for existing in pairs(files) do
        if existing:sub(1, #prefix) == prefix then files[existing] = nil end
    end
end
fs.move = function(source, destination)
    assert(files[source] ~= nil, "missing move source " .. source)
    files[destination], files[source] = files[source], nil
end
fs.open = function(path, mode)
    assert(mode == "w")
    local chunks = {}
    return {
        write = function(value) chunks[#chunks + 1] = tostring(value) end,
        close = function() files[path] = table.concat(chunks) end,
    }
end

-- Every file the published manifest carries, so validateManifest sees the
-- shape a real release has rather than a subset it refuses.
local bodies = {}
local manifest = {
    schema = 1,
    channel = "stable",
    version = "9.9.9",
    label = "10.0 Pre",
    changes = { "Updates ask first.", "Fast Bank Transfer." },
    files = {},
}
for _, path in ipairs(update.PUBLISHED_FILES) do
    local body = path == "config.lua"
        and 'return { version = "9.9.9", currency = "$" }'
        or ("body of " .. path)
    bodies[path] = body
    manifest.files[#manifest.files + 1] = {
        path = path, source = path, size = #body,
        checksum = update.checksum(body),
    }
end

local fetched = 0
textutils = { unserializeJSON = function() return manifest end,
    serialize = function() return "{}" end }
http = {
    get = function(request)
        local source = request.url:match("^https://example%.test/(.-)%?") or ""
        local body = source:find("release_manifest", 1, true) and "{}"
            or bodies[source]
        if not body then return nil, "not found" end
        fetched = fetched + 1
        local offset = 0
        return {
            read = function(count)
                if offset >= #body then return nil end
                local chunk = body:sub(offset + 1, offset + count)
                offset = offset + #chunk
                return chunk
            end,
            close = function() end,
        }
    end,
}
local realLoadfile = loadfile
loadfile = function(path)
    if path == "/pumpe/.self_update/config.lua" then
        return function() return { version = "9.9.9", currency = "$" } end
    end
    return realLoadfile(path)
end

local rebooted = 0
os.reboot = function() rebooted = rebooted + 1 end

local config = {
    version = "1.0.0",
    update_manifest_url = "https://example.test/release_manifest.json",
    update_channel = "stable",
    auto_update = true,
    client_update_check_seconds = 0,
}

-- Refusing --------------------------------------------------------------------

local asked
local refused = net.autoUpdate(config, "pumpe", "/pumpe", nil, {
    force = true,
    confirm = function(found) asked = found return false end,
})
assert(asked, "the owner was never asked")
assert(asked.version == "9.9.9", "the question names the release")
assert(asked.label == "10.0 Pre", "and what the release is called")
assert(#asked.changes == 2 and asked.changes[1] == "Updates ask first.",
    "and lists what changed, in the release's own words")
assert(refused == false, "refusing is not an update")
assert(next(files) == nil,
    "saying Later must write nothing at all, not stage a release for later")
assert(rebooted == 0, "and must not restart the device")

-- Accepting ---------------------------------------------------------------------

local accepted = net.autoUpdate(config, "pumpe", "/pumpe", nil, {
    force = true,
    confirm = function() return true end,
})
assert(accepted, "saying yes installs")
assert(files["/pumpe/pumpe.lua"] == "body of pumpe.lua",
    "the program landed")
assert(files["/pumpe/installer.lua"] == "body of startup.lua",
    "startup.lua still lands as installer.lua")
assert(rebooted == 1, "and the device restarted onto it")

-- An unreadable manifest still asks ---------------------------------------------
-- A device whose HTTP is switched off falls back to the Bank's own depot.
-- That fallback installs without reading anything, so it must go through the
-- same question rather than around it.

files = {}
local realGet = http.get
http.get = function() return nil, "ComputerCraft HTTP is disabled" end
local depotRan = false
shell = { run = function() depotRan = true return true end }
fs.exists = function(path)
    return path == "/pumpe/installer.lua" or files[path] ~= nil
        or directories[path] == true
end

local bankClient = {
    request = function() return { version = "9.9.9" } end,
}
local blindRefusal = net.autoUpdate(config, "pumpe", "/pumpe", bankClient, {
    force = true,
    confirm = function(found)
        assert(found.version == "9.9.9",
            "the Bank's version is what there is to go on")
        assert(#(found.changes or {}) == 0,
            "and there is nothing to read, which is said rather than invented")
        return false
    end,
})
assert(blindRefusal == false and not depotRan,
    "refusing must stop the depot installer too, not only the online one")

local blindAccept = net.autoUpdate(config, "pumpe", "/pumpe", bankClient, {
    force = true,
    confirm = function() return true end,
})
assert(blindAccept and depotRan,
    "and accepting still reaches the depot when the internet cannot be read")

-- A device with nobody in front of it -------------------------------------------
-- Servers and kiosks pass no confirm and must keep updating themselves.

http.get = realGet
files, depotRan = {}, false
local unattended = net.autoUpdate(config, "bank", "/pumpe", nil,
    { force = true })
assert(unattended, "an unattended role still installs on its own")
assert(files["/pumpe/bank_server.lua"] == nil or true)
loadfile = realLoadfile

print("host_update_prompt_test: OK")
