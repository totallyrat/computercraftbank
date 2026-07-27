-- End-to-end Bank Server state test for territories, travel documents,
-- Free Roam, temporary stays, and Border Controller authentication.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay = 100
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return 123456789 end
os.getComputerID = function() return 1 end

fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return false end,
    isDir = function() return false end,
}
shell = {
    getRunningProgram = function() return "/pumpe/bank_server.lua" end,
}

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = bank.actions

local function register(name)
    return actions.REGISTER({
        name = name,
        pin = "1234",
        gender = "Not set",
    })
end

local alphaOwner = register("Alpha Owner")
local betaOwner = register("Beta Owner")
local traveler = register("Traveler")
local applicant = register("Applicant")

local alpha = actions.CUSTOMS_CREATE_TERRITORY({
    session_token = alphaOwner.session_token,
    name = "Alpha Territory",
    pin = "1234",
})
local beta = actions.CUSTOMS_CREATE_TERRITORY({
    session_token = betaOwner.session_token,
    name = "Beta Territory",
    pin = "1234",
})
assert(alpha.citizenship.permanent)
assert(beta.citizenship.permanent)
assert(#alpha.citizenship.code == 8)

local betaCitizenship = actions.CUSTOMS_ISSUE_CITIZENSHIP({
    session_token = betaOwner.session_token,
    territory_id = beta.territory.territory_id,
    username = "Traveler",
    pin = "1234",
})
assert(betaCitizenship.document.kind == "citizenship")

local roam = actions.CUSTOMS_SET_FREE_ROAM({
    session_token = alphaOwner.session_token,
    territory_id = alpha.territory.territory_id,
    source_territory_id = beta.territory.territory_id,
    enabled = true,
    pin = "1234",
})
assert(roam.enabled)

local travelerOverview = actions.VISA_OVERVIEW({
    session_token = traveler.session_token,
})
local foundRoam = false
for _, document in ipairs(travelerOverview.documents) do
    if document.visa_id == betaCitizenship.document.visa_id then
        assert(document.permanent)
        assert(document.free_roam[1].territory_name == "Alpha Territory")
        foundRoam = true
    end
end
assert(foundRoam)

local border = actions.BORDER_REGISTER({
    session_token = alphaOwner.session_token,
    territory_id = alpha.territory.territory_id,
    label = "North Gate",
})
local freeEntry = actions.BORDER_CHECK({
    controller_id = border.controller_id,
    controller_token = border.controller_token,
    code = betaCitizenship.document.code,
})
assert(freeEntry.approved)
assert(freeEntry.authorization == "free_roam")
assert(freeEntry.permanent)
assert(freeEntry.due_day == nil)
assert(freeEntry.visiting)

local application = actions.VISA_APPLY({
    session_token = applicant.session_token,
    territory_id = alpha.territory.territory_id,
    requested_days = 5,
})
assert(application.application.status == "pending")

local reviewed = actions.CUSTOMS_REVIEW_APPLICATION({
    session_token = alphaOwner.session_token,
    application_id = application.application.application_id,
    approved = true,
    pin = "1234",
})
assert(reviewed.application.status == "approved")
assert(reviewed.document.kind == "visa")
assert(reviewed.document.duration_days == 5)

local temporaryEntry = actions.BORDER_CHECK({
    controller_id = border.controller_id,
    controller_token = border.controller_token,
    code = reviewed.document.code,
})
assert(temporaryEntry.approved)
assert(temporaryEntry.authorization == "visa")
assert(not temporaryEntry.permanent)
assert(temporaryEntry.stay_days == 5)
assert(temporaryEntry.due_day == 104)

local repeatedEntry = actions.BORDER_CHECK({
    controller_id = border.controller_id,
    controller_token = border.controller_token,
    code = reviewed.document.code,
})
assert(repeatedEntry.due_day == 104)
assert(repeatedEntry.stay_days == 5)

currentDay = 105
bank.cleanup()
local ok, rejection = pcall(actions.BORDER_CHECK, {
    controller_id = border.controller_id,
    controller_token = border.controller_token,
    code = reviewed.document.code,
})
assert(not ok)
assert(type(rejection) == "table")
assert(rejection.code == "VISA_EXPIRED")

print("host_travel_server_test: OK")
