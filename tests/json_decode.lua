-- A small JSON reader for tests: enough for release_manifest.json, and
-- strict enough that a malformed manifest fails here rather than passing.

local json = {}

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f",
    n = "\n", r = "\r", t = "\t" }

function json.decode(text)
    local at = 1
    local function fail(what) error("JSON: " .. what .. " at " .. at, 0) end
    local function space() at = text:find("[^ \t\r\n]", at) or #text + 1 end
    local value
    local function str()
        at = at + 1
        local out = {}
        while true do
            local c = text:sub(at, at)
            if c == "" then fail("unterminated string") end
            if c == '"' then at = at + 1 return table.concat(out) end
            if c == "\\" then
                local e = text:sub(at + 1, at + 1)
                if e == "u" then
                    out[#out + 1] = utf8.char(tonumber(text:sub(at + 2, at + 5), 16))
                    at = at + 6
                else
                    out[#out + 1] = escapes[e] or fail("bad escape")
                    at = at + 2
                end
            else
                out[#out + 1] = c
                at = at + 1
            end
        end
    end
    function value()
        space()
        local c = text:sub(at, at)
        if c == "{" then
            at = at + 1
            local out = {}
            space()
            if text:sub(at, at) == "}" then at = at + 1 return out end
            while true do
                space()
                if text:sub(at, at) ~= '"' then fail("expected a key") end
                local key = str()
                space()
                if text:sub(at, at) ~= ":" then fail("expected :") end
                at = at + 1
                out[key] = value()
                space()
                local d = text:sub(at, at)
                at = at + 1
                if d == "}" then return out end
                if d ~= "," then fail("expected , or }") end
            end
        elseif c == "[" then
            at = at + 1
            local out = {}
            space()
            if text:sub(at, at) == "]" then at = at + 1 return out end
            while true do
                out[#out + 1] = value()
                space()
                local d = text:sub(at, at)
                at = at + 1
                if d == "]" then return out end
                if d ~= "," then fail("expected , or ]") end
            end
        elseif c == '"' then
            return str()
        elseif text:sub(at, at + 3) == "true" then
            at = at + 4 return true
        elseif text:sub(at, at + 4) == "false" then
            at = at + 5 return false
        elseif text:sub(at, at + 3) == "null" then
            at = at + 4 return nil
        else
            local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", at)
            if not number or number == "" then fail("unexpected " .. c) end
            at = at + #number
            return tonumber(number)
        end
    end
    local result = value()
    space()
    if at <= #text then fail("trailing text") end
    return result
end

return json
