-- Minimal host-side tests for deterministic utility behavior.
-- Run from this directory with any Lua 5.2+ interpreter.

package.path = "../?.lua;../?/init.lua;" .. package.path

os.day = function() return 100 end
os.time = function() return 18.5 end
os.epoch = function() return 123456789 end
os.getComputerID = function() return 42 end

local util = require("lib.util")

assert(util.ingameDay() == 100)
assert(util.formatClock() == "18:30")
assert(util.formatClock(false) == "18 30")
assert(util.parseEventTime("00:00") == 0)
assert(util.parseEventTime("23:59") == 1439)
assert(util.parseEventTime("24:00") == nil)
assert(util.eventCountdown(101, "18:30") == "1d 00h 00m")
assert(util.money(12, "$") == "$12")
assert(util.money(12.5, "$") == "$12.50")
assert(util.roundMoney(1.005) == 1)
assert(util.validPin("1234"))
assert(not util.validPin("12345"))
assert(util.hashPin("1234") == util.hashPin("1234"))
assert(util.normalName("  Alice Smith ") == "alice smith")

local items, page, pages = util.page({ 1, 2, 3, 4, 5 }, 2, 2)
assert(page == 2 and pages == 3)
assert(items[1] == 3 and items[2] == 4)

print("host_util_test: OK")
