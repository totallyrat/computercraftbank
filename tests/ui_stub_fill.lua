-- What 12.0 added to lib/ui, for a test's hand-made ui.
--
-- Most phone tests replace lib/ui with a table of their own that records
-- what is drawn. The functions that only work things out -- which colour
-- reads on which, where the tab bar sits, the tab host -- are taken from the
-- real library; the ones that draw or touch the disk are given versions
-- that do neither. Whatever the test already defined is left alone.
local realUi = dofile("real_ui.lua")

return function(stub)
    for _, name in ipairs({ "inkOn", "contentBottom", "tabRow", "searchEntries",
        "runTabs", "resolveTab", "tabBar" }) do
        if stub[name] == nil then stub[name] = realUi[name] end
    end
    stub.MAIN_COLORS = stub.MAIN_COLORS or realUi.MAIN_COLORS
    stub.mainColor = stub.mainColor or "orange"
    stub.TAB_COUNT = stub.TAB_COUNT or realUi.TAB_COUNT
    stub.useMainColor = stub.useMainColor or function() return "orange" end
    stub.hasMainColor = stub.hasMainColor or function() return true end
    stub.saveMainColor = stub.saveMainColor or function() return true end
    stub.setMainColor = stub.setMainColor or function() return true end
    stub.pickMainColor = stub.pickMainColor or function() return nil end
    stub.wordmark = stub.wordmark or function() return false end
    -- FoxyOS 12's update screens: drawn by the real library in its own test.
    stub.updateFrame = stub.updateFrame or function() end
    stub.updating = stub.updating or function(_, work) return work(function() end) end
    stub.updateReady = stub.updateReady or function() return false end
    stub.myIdVerifier = stub.myIdVerifier or function(_, ask)
        stub.verified = stub.verified or {}
        stub.verified[#stub.verified + 1] = ask(stub.myIdCode or "MY7K2M9QPA")
    end
    stub.moreMenu = stub.moreMenu or function(_, spec)
        return "tab:" .. tostring(spec and spec.active or "more")
    end
    if stub.theme then
        stub.theme.accentInk = stub.theme.accentInk or 32768
    end
    -- The real tab host opens More through its own library; this copy of
    -- it is the test's alone, so it is pointed at the test's More.
    realUi.moreMenu = function(target, spec) return stub.moreMenu(target, spec) end
    stub.runTabs = realUi.runTabs
    return stub
end
