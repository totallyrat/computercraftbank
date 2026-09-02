local util = require("lib.util")

local update = {}

local MAX_MANIFEST_BYTES = 256 * 1024
local MAX_FILE_BYTES = 1024 * 1024

local function safeRelativePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:sub(1, 1) ~= "/"
        and not path:find("\\", 1, true)
        and not path:find("..", 1, true)
        and path:match("^[%w_%-/%.]+$") ~= nil
end

local function versionParts(value)
    local major, minor, patch = tostring(value or ""):match(
        "^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

function update.isNewer(candidate, current)
    local candidateMajor, candidateMinor, candidatePatch =
        versionParts(candidate)
    local currentMajor, currentMinor, currentPatch = versionParts(current)
    if not candidateMajor or not currentMajor then return false end
    if candidateMajor ~= currentMajor then return candidateMajor > currentMajor end
    if candidateMinor ~= currentMinor then return candidateMinor > currentMinor end
    return candidatePatch > currentPatch
end

function update.checksum(body)
    return util.checksum(body)
end

local function closeResponse(response)
    if response and type(response.close) == "function" then
        pcall(response.close)
    end
end

local function readResponse(response, maximumBytes)
    local chunks, length = {}, 0
    while true do
        local chunk = response.read(8192)
        if not chunk then break end
        length = length + #chunk
        if length > maximumBytes then
            closeResponse(response)
            return nil, "Online update exceeded its allowed size"
        end
        chunks[#chunks + 1] = chunk
    end
    closeResponse(response)
    return table.concat(chunks)
end

local function fetchBody(url, maximumBytes)
    if type(http) ~= "table" or type(http.get) ~= "function" then
        return nil, "ComputerCraft HTTP is disabled"
    end
    if type(url) ~= "string" or not url:match("^https://") then
        return nil, "Online updates require an HTTPS URL"
    end

    local ok, response, err, errorResponse = pcall(http.get, {
        url = url,
        headers = {
            ["Accept"] = "application/json, text/plain",
            ["Cache-Control"] = "no-cache",
        },
        binary = false,
        redirect = false,
        timeout = 10,
    })
    if not ok then return nil, tostring(response) end
    if not response then
        closeResponse(errorResponse)
        return nil, tostring(err or "HTTP request failed")
    end
    return readResponse(response, maximumBytes)
end

local function cacheBusted(url, version)
    local separator = url:find("?", 1, true) and "&" or "?"
    return url .. separator .. "pumpe=" .. tostring(version or util.nowMs())
end

local function releaseBaseUrl(manifestUrl)
    local clean = tostring(manifestUrl or ""):gsub("[?#].*$", "")
    return clean:match("^(https://.*/)[^/]+$")
end

local function releaseFileUrl(manifestUrl, source, version)
    local base = releaseBaseUrl(manifestUrl)
    if not base then return nil end
    return cacheBusted(base .. source, version)
end

-- Required files live in `files`; optional roles live in `extra_files` so
-- older Bank updaters, which reject unknown entries in `files`, keep working.
local function readEntry(rawFile, allowed, seen)
    local path = type(rawFile) == "table" and rawFile.path or nil
    local source = type(rawFile) == "table"
        and (rawFile.source or rawFile.path) or nil
    local size = type(rawFile) == "table" and rawFile.size or nil
    local checksum = type(rawFile) == "table" and rawFile.checksum or nil
    if not safeRelativePath(path) or not allowed[path] or seen[path] then
        return nil, "Update manifest contains an unexpected file"
    end
    if not safeRelativePath(source) then
        return nil, "Update manifest contains an unsafe source"
    end
    if type(size) ~= "number" or size < 0 or size % 1 ~= 0
        or size > MAX_FILE_BYTES then
        return nil, "Update manifest contains an invalid file size"
    end
    if type(checksum) ~= "string" or not checksum:match("^%x%x%x%x%x%x%x%x$") then
        return nil, "Update manifest contains an invalid checksum"
    end
    seen[path] = true
    return {
        path = path,
        source = source,
        size = size,
        checksum = string.lower(checksum),
    }
end

function update.validateManifest(manifest, expectedPaths, expectedChannel,
    optionalPaths)
    if type(manifest) ~= "table" or manifest.schema ~= 1 then
        return nil, "Unsupported online update manifest"
    end
    if type(manifest.version) ~= "string"
        or not versionParts(manifest.version) then
        return nil, "Update manifest has an invalid version"
    end
    if expectedChannel and manifest.channel ~= expectedChannel then
        return nil, "Update manifest is for another channel"
    end
    if type(manifest.files) ~= "table" then
        return nil, "Update manifest has no files"
    end

    local required, optional = {}, {}
    for _, path in ipairs(expectedPaths or {}) do required[path] = true end
    for _, path in ipairs(optionalPaths or {}) do optional[path] = true end
    local seen, files = {}, {}
    for _, rawFile in ipairs(manifest.files) do
        local file, err = readEntry(rawFile, required, seen)
        if not file then return nil, err end
        files[#files + 1] = file
    end
    for path in pairs(required) do
        if not seen[path] then
            return nil, "Update manifest is missing " .. path
        end
    end
    if type(manifest.extra_files) == "table" then
        for _, rawFile in ipairs(manifest.extra_files) do
            local file, err = readEntry(rawFile, optional, seen)
            if not file then return nil, err end
            files[#files + 1] = file
        end
    end

    return {
        schema = 1,
        channel = manifest.channel,
        version = manifest.version,
        notes = tostring(manifest.notes or ""),
        files = files,
    }
end

function update.fetchManifest(manifestUrl, expectedPaths, expectedChannel,
    optionalPaths)
    local body, err = fetchBody(cacheBusted(manifestUrl), MAX_MANIFEST_BYTES)
    if not body then return nil, err end
    local ok, manifest = pcall(textutils.unserializeJSON, body)
    if not ok or type(manifest) ~= "table" then
        return nil, "Online update manifest is not valid JSON"
    end
    return update.validateManifest(manifest, expectedPaths, expectedChannel,
        optionalPaths)
end

-- Downloads and verifies exactly one validated manifest entry.
function update.fetchFile(manifestUrl, file, version)
    local url = releaseFileUrl(manifestUrl, file.source, version)
    if not url then return nil, "Update manifest URL has no release folder" end
    local body, err = fetchBody(url, math.min(MAX_FILE_BYTES, file.size + 1))
    if not body then return nil, err end
    if #body ~= file.size or update.checksum(body) ~= file.checksum then
        return nil, "Online checksum failed for " .. file.path
    end
    return body
end

function update.downloadRelease(manifest, manifestUrl, stagingRoot, onProgress)
    if fs.exists(stagingRoot) then fs.delete(stagingRoot) end
    fs.makeDir(stagingRoot)

    for index, file in ipairs(manifest.files) do
        if onProgress then onProgress(file, index, #manifest.files) end
        local body, err = update.fetchFile(manifestUrl, file, manifest.version)
        if not body then return nil, err end
        local destination = fs.combine(stagingRoot, file.path)
        local ok, writeError = pcall(util.writeFile, destination, body)
        if not ok then return nil, tostring(writeError) end
    end
    return true
end

local function moveWithParent(source, destination)
    local directory = fs.getDir(destination)
    if directory ~= "" and not fs.exists(directory) then
        fs.makeDir(directory)
    end
    fs.move(source, destination)
end

function update.commitRelease(manifest, stagingRoot, installRoot, backupRoot)
    if fs.exists(backupRoot) then fs.delete(backupRoot) end
    fs.makeDir(backupRoot)
    local committed = {}
    local ok, err = pcall(function()
        for _, file in ipairs(manifest.files) do
            local source = fs.combine(stagingRoot, file.path)
            local destination = fs.combine(installRoot, file.path)
            if fs.exists(destination) then
                moveWithParent(destination, fs.combine(backupRoot, file.path))
            end
            moveWithParent(source, destination)
            committed[#committed + 1] = file.path
        end
    end)
    if not ok then
        for _, path in ipairs(committed) do
            local destination = fs.combine(installRoot, path)
            if fs.exists(destination) then fs.delete(destination) end
        end
        for _, file in ipairs(manifest.files) do
            local backup = fs.combine(backupRoot, file.path)
            if fs.exists(backup) then
                moveWithParent(backup, fs.combine(installRoot, file.path))
            end
        end
        if fs.exists(stagingRoot) then fs.delete(stagingRoot) end
        if fs.exists(backupRoot) then fs.delete(backupRoot) end
        return nil, tostring(err)
    end
    fs.delete(stagingRoot)
    fs.delete(backupRoot)
    return true
end

return update
