-- CCG, FoxyOS 17: one console became two.
--
-- Until FoxyOS 17 a CCG was Home Mode and Bet Play on the same computer. Now
-- each is its own download: CCG Home (ccg_home.lua), Home Mode as it was,
-- and CCG Casino (ccg_casino.lua), the casino, run from the CCG app. A CCG
-- that updates arrives here once and is asked which it is to be. The answer
-- fetches that program from the release this computer is on, points
-- /startup.lua at it, and restarts into it.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "16.5.0"
local config = require("config")
local util = require("lib.util")
local ui = require("lib.ui")

local CHOICES = {
    home = { role = "ccghome", file = "ccg_home.lua", title = "CCG HOME",
        about = "Home Mode, as it was: free games, a Pocket as the controller." },
    casino = { role = "ccgcasino", file = "ccg_casino.lua", title = "CCG CASINO",
        about = "Roulette, Blackjack, Heads or Tails and Poker, run by a company"
            .. " from the CCG app." },
}
-- What /startup.lua looks like when Easy Deployment wrote it.
local ROLE_MARKER = "-- PUMPE ROLE STARTUP"
local HEADER = "-- PUMPE EASY DEPLOYMENT"

local function screen()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local monitor = peripheral.wrap(name)
            if monitor and type(monitor.isColor) == "function" and monitor.isColor() then
                pcall(monitor.setTextScale, 0.5)
                return monitor
            end
        end
    end
    return term.current()
end
local target = screen()
ui.usePhoneStyle(false)

-- Fetching the chosen program from the release this computer runs: the
-- beta's manifest on a beta, the release's otherwise.
local function fetchProgram(choice)
    local okLib, update = pcall(require, "lib.update")
    if not okLib or type(update) ~= "table" then return nil, "No updater here" end
    local onBeta = util.isBetaVersion and util.isBetaVersion(config.version)
    local url = onBeta and config.beta_manifest_url or config.update_manifest_url
    local manifest, err = update.fetchManifest(tostring(url or ""), update.PUBLISHED_FILES,
        onBeta and "beta" or "stable", update.PUBLISHED_OPTIONAL)
    if not manifest then return nil, err or "No release found" end
    for _, file in ipairs(manifest.files) do
        if file.path == choice.file then
            local body, fetchError = update.fetchFile(url, file, manifest.version)
            if not body then return nil, fetchError or "Download failed" end
            return body
        end
    end
    return nil, "This release has no " .. choice.title
end

local function become(choice)
    local body, err = fetchProgram(choice)
    if not body then
        ui.message(target, "error", "NOT DOWNLOADED", err, 2.4)
        return false
    end
    local file = fs.open(fs.combine(ROOT, choice.file), "w")
    if not file then
        ui.message(target, "error", "NO ROOM", "Free some space and try again", 2.4)
        return false
    end
    file.write(body)
    file.close()
    -- Point the computer's start at it, unless somebody wrote their own.
    local current = fs.exists("/startup.lua") and fs.open("/startup.lua", "r")
    local existing = current and current.readAll() or nil
    if current then current.close() end
    if not existing or existing:sub(1, #ROLE_MARKER) == ROLE_MARKER
        or existing:sub(1, #HEADER) == HEADER then
        local out = fs.open("/startup.lua", "w")
        out.write(ROLE_MARKER .. "\nshell.run(\"/" .. fs.combine(ROOT, "installer.lua")
            .. "\", \"--boot\", \"" .. choice.role .. "\")\n")
        out.close()
    end
    ui.message(target, "success", choice.title, "Starting it now", 1.2)
    os.reboot()
    return true
end

local function chooser()
    while true do
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        ui.fill(target, 1, 1, width, 1, colors.magenta)
        ui.center(target, 1, "CCG IS TWO NOW", colors.white, colors.magenta)
        ui.wrappedText(target, 2, 3, "Choose what this CCG is. You can only"
            .. " change it again by installing.", width - 2, 2, colors.lightGray,
            colors.black)
        local scene = ui.scene(target)
        local tall = math.max(3, math.floor((height - 7) / 2))
        local y = 6
        for _, id in ipairs({ "casino", "home" }) do
            local choice = CHOICES[id]
            local color = id == "casino" and colors.red or colors.cyan
            scene:button(id, 2, y, width - 2, tall, choice.title .. "\n"
                .. ui.truncate(choice.about, (width - 4) * math.max(1, tall - 1)),
                { background = color, foreground = id == "casino" and colors.white
                    or colors.black })
            y = y + tall + 1
        end
        local action = scene:wait({ keys = { [keys.h] = "home", [keys.c] = "casino" } })
        if action == "__terminate" then return end
        local choice = CHOICES[action]
        if choice and ui.confirm(target, choice.title .. "?", choice.about,
            "YES", "BACK") then
            if become(choice) then return end
        end
    end
end

if rawget(_G, "PUMPE_TEST_MODE") == "ccg_split" then
    return { choices = CHOICES, become = become, fetch = fetchProgram }
end

-- On the computer's own screen too, when the choice is on a monitor.
if target ~= term.current() then
    term.clear()
    term.setCursorPos(1, 1)
    print("CCG is two now. Choose on the monitor:")
    print("CCG Casino or CCG Home.")
end
chooser()
