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
local transfer = assert(util.transferBreakdown(100, 0.10))
assert(transfer.amount == 100 and transfer.fee == 10 and transfer.total == 110)
local tinyTransfer = assert(util.transferBreakdown(0.01, 0.10))
assert(tinyTransfer.fee == 0.01 and tinyTransfer.total == 0.02)
assert(util.transferBreakdown(0, 0.10) == nil)
local allowed, remaining = util.dailyLimitRemaining(1500, 500, 2000)
assert(allowed and remaining == 0)
allowed, remaining = util.dailyLimitRemaining(1500, 500.01, 2000)
assert(not allowed and remaining == 0)
assert(util.validPin("1234"))
assert(not util.validPin("12345"))
assert(util.hashPin("1234") == util.hashPin("1234"))
assert(util.normalName("  Alice Smith ") == "alice smith")

-- Large release files must give ComputerCraft's watchdog regular scheduler
-- hand-offs while preserving the exact checksum used by release manifests.
local largeBody = string.rep("PUMPE-BANK-YIELD-SLICE\n", 10000)
local expectedLargeChecksum = util.checksum(largeBody)
local oldQueueEvent, oldPullEvent = os.queueEvent, os.pullEvent
local queuedEvent, yieldCount
yieldCount = 0
os.queueEvent = function(event)
    queuedEvent = event
end
os.pullEvent = function(filter)
    assert(filter == queuedEvent)
    yieldCount = yieldCount + 1
    return filter
end
assert(util.checksum(largeBody) == expectedLargeChecksum)
assert(yieldCount >= 100, "large checksum did not yield often enough")
os.queueEvent, os.pullEvent = oldQueueEvent, oldPullEvent

local items, page, pages = util.page({ 1, 2, 3, 4, 5 }, 2, 2)
assert(page == 2 and pages == 3)
assert(items[1] == 3 and items[2] == 4)

print("host_util_test: OK")
