-- FoxyCloud's world, for tests: a disk per computer and rednet between them,
-- around a real Bank Core and Vault (bank_pair_harness), with five real
-- Cloud Servers registered and beating. host_foxycloud_test.lua tests the
-- Bank and the servers through it; the app tests run FoxyCloud on top.
--
-- cloud.start(harness, bank) sets the globals these programs use (fs,
-- rednet, peripheral, term, shell) and returns the world.

local cloud = {}

function cloud.start(harness, bank)
    local config = require("config")
    local rejected = harness.rejected
    -- Disks -----------------------------------------------------------------------------
    -- One per computer, each with its own size. ComputerCraft charges at least 500
    -- bytes for a file however small, and so does this.
    local disks = {}
    local function clean(path)
        return (tostring(path):gsub("^/+", ""):gsub("/+$", ""))
    end
    local function rootOf(path) return clean(path):match("^([^/]+)") or "" end
    local function diskFor(path)
        local root = rootOf(path)
        disks[root] = disks[root] or { files = {}, dirs = {}, capacity = 1000000 }
        return disks[root]
    end
    fs = {
        getDir = function(path)
            local dir = clean(path):match("^(.*)/[^/]*$") or ""
            return "/" .. dir
        end,
        combine = function(left, right)
            return tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", "")
        end,
        exists = function(path)
            local disk = diskFor(path)
            return disk.files[clean(path)] ~= nil or disk.dirs[clean(path)] == true
        end,
        isDir = function(path) return diskFor(path).dirs[clean(path)] == true end,
        makeDir = function(path) diskFor(path).dirs[clean(path)] = true end,
        list = function(path)
            local prefix, names = clean(path) .. "/", {}
            for name in pairs(diskFor(path).files) do
                if name:sub(1, #prefix) == prefix and not name:sub(#prefix + 1):find("/") then
                    names[#names + 1] = name:sub(#prefix + 1)
                end
            end
            table.sort(names)
            return names
        end,
        getName = function(path) return clean(path):match("([^/]*)$") end,
        getSize = function(path) return #(diskFor(path).files[clean(path)] or "") end,
        getFreeSpace = function(path)
            local disk, used = diskFor(path), 0
            for _, data in pairs(disk.files) do used = used + math.max(500, #data) end
            return disk.capacity - used
        end,
        delete = function(path) diskFor(path).files[clean(path)] = nil end,
        move = function(from, to)
            local disk = diskFor(from)
            assert(disk.files[clean(from)] and not disk.files[clean(to)], "fs.move")
            diskFor(to).files[clean(to)], disk.files[clean(from)] = disk.files[clean(from)], nil
        end,
        open = function(path, mode)
            local disk, key = diskFor(path), clean(path)
            if mode:sub(1, 1) == "r" then
                local data = disk.files[key]
                if not data then return nil end
                -- A binary handle reads a count of bytes from where it was
                -- sought to, as CC:Tweaked's does.
                local at = 0
                return { readAll = function() return data end, close = function() end,
                    read = function(count)
                        local part = data:sub(at + 1, at + (count or 1))
                        at = at + #part
                        return part ~= "" and part or nil
                    end,
                    seek = function(whence, offset)
                        local base = whence == "cur" and at or whence == "end" and #data or 0
                        at = math.max(0, base + (offset or 0))
                        return at
                    end }
            end
            local parts = {}
            return { write = function(text) parts[#parts + 1] = text end,
                close = function() disk.files[key] = table.concat(parts) end }
        end,
    }

    -- The network ----------------------------------------------------------------------
    -- rednet, as far as these programs use it. A send reaches its computer at
    -- once, and the answer waits in the sender's mailbox; a receive with nothing
    -- there lets the time it would have waited go by.
    local BANK_ID, POCKET_ID = bank.core_id, 100
    local current = POCKET_ID
    local mail, servers, lose = {}, {}, {}
    -- FoxyOS 17: other servers on the same network, such as a Music Server:
    -- [computer id] = { protocol, hostname, actions }.
    local others = {}

    local function deliver(to, from, message, protocol)
        mail[to] = mail[to] or {}
        table.insert(mail[to], { sender = from, message = message, protocol = protocol })
    end

    local function answer(request, ok, result)
        local reply = { version = 5, kind = "response", request_id = request.request_id }
        if ok then
            reply.ok, reply.data = true, result
        elseif type(result) == "table" and result.pumpe then
            reply.ok, reply.error, reply.code = false, result.message, result.code
        else
            error(result, 0)
        end
        return reply
    end

    local function bankAnswer(from, request)
        local spec = bank.core.routes[request.action]
        if spec then
            return answer(request, pcall(bank.core.route_to_vault, request.action, spec,
                request.payload or {}, from))
        end
        local handler = bank.core.actions[request.action]
        assert(handler, "no bank action " .. tostring(request.action))
        return answer(request, pcall(handler, request.payload or {}, from))
    end

    term = term or { current = function() return {} end }
    peripheral = {
        getNames = function() return { "top" } end,
        getType = function() return "modem" end,
    }
    rednet = {
        isOpen = function() return true end,
        open = function() end, close = function() end,
        host = function() end, unhost = function() end,
        lookup = function(protocol)
            if protocol == config.protocol then return BANK_ID end
            -- FoxyOS 18: every Cloud Server that is up, as rednet.lookup
            -- answers a protocol with no name.
            if protocol == config.cloud_protocol then
                local up = {}
                for _, id in ipairs({ 11, 12, 13, 14, 15 }) do
                    if servers[id] and servers[id].up then up[#up + 1] = id end
                end
                return table.unpack(up)
            end
            for id, other in pairs(others) do
                if other.protocol == protocol and other.up ~= false then return id end
            end
            return nil
        end,
        send = function(to, message, protocol)
            local from = current
            if (lose[to] or 0) > 0 then
                lose[to] = lose[to] - 1
                return true
            end
            if to == BANK_ID and protocol == config.protocol then
                deliver(from, BANK_ID, bankAnswer(from, message), protocol)
            elseif servers[to] and servers[to].up and protocol == config.cloud_protocol then
                current = to
                local handler = servers[to].program.actions[message.action]
                local reply = answer(message, pcall(handler, message.payload or {}, from))
                current = from
                deliver(from, to, reply, protocol)
            elseif others[to] and others[to].up ~= false and protocol == others[to].protocol then
                current = to
                local handler = others[to].actions[message.action]
                local reply = handler and answer(message, pcall(handler, message.payload or {},
                    from)) or { version = 5, kind = "response", request_id = message.request_id,
                    ok = false, error = "Unknown action", code = "UNKNOWN_ACTION" }
                current = from
                deliver(from, to, reply, protocol)
            end
            return true
        end,
        receive = function(protocol, timeout)
            local box = mail[current] or {}
            for index, item in ipairs(box) do
                if protocol == nil or item.protocol == protocol then
                    table.remove(box, index)
                    return item.sender, item.message, item.protocol
                end
            end
            harness.epoch = harness.epoch + math.floor((timeout or 1) * 1000)
            return nil
        end,
    }

    local function as(computerId, fn, ...)
        local before = current
        current = computerId
        local results = table.pack(pcall(fn, ...))
        current = before
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2, results.n)
    end

    -- Five Cloud Servers ----------------------------------------------------------------

    local function loadServer(computerId, capacity)
        shell = { getRunningProgram = function()
            return "/cloud" .. computerId .. "/cloud_server.lua"
        end }
        disks["cloud" .. computerId] = { files = {}, dirs = {}, capacity = capacity }
        PUMPE_TEST_MODE = "cloud_server"
        local program = assert(loadfile("../cloud_server.lua"))()
        PUMPE_TEST_MODE = nil
        fs.makeDir(program.chunk_dir)
        servers[computerId] = { program = program, up = true }
        return program
    end

    rejected(bank.request, "BAD_CODE", "CLOUD_SERVER_REGISTER",
        { code = "0000", computer_id = 11 })
    local ids = { 11, 12, 13, 14, 15 }
    for _, id in ipairs(ids) do
        local program = loadServer(id, 80000)
        local registered = bank.request("CLOUD_SERVER_REGISTER",
            { code = "4040", name = "Cloud " .. id, computer_id = id })
        program.state.server_token = registered.server_token
        program.state.server_id = registered.server_id
    end
    local function beatAll()
        for _, id in ipairs(ids) do
            if servers[id].up then as(id, servers[id].program.beat) end
        end
    end
    local function held(id) return servers[id].program.held end
    local function heldTotal()
        local count = 0
        for _, id in ipairs(ids) do count = count + held(id).count end
        return count
    end
    -- A program of another kind on computer `computerId`, loaded in its test
    -- mode with a disk of its own, answering `protocol`.
    local function attach(computerId, program, protocol, mode)
        shell = { getRunningProgram = function()
            return "/" .. mode .. computerId .. "/" .. program
        end }
        disks[mode .. computerId] = { files = {}, dirs = {}, capacity = 50 * 1000 * 1000 }
        PUMPE_TEST_MODE = mode
        local before = current
        current = computerId
        local loaded = assert(loadfile("../" .. program))()
        current = before
        PUMPE_TEST_MODE = nil
        others[computerId] = { protocol = protocol, actions = loaded.actions, up = true }
        return loaded, others[computerId]
    end
    return {
        disks = disks, servers = servers, lose = lose, ids = ids,
        as = as, beatAll = beatAll, held = held, heldTotal = heldTotal,
        loadServer = loadServer, pocket = POCKET_ID, attach = attach, mail = mail,
    }
end

return cloud
