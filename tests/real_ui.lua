-- The real ui library, for tests whose ui is otherwise a stub.
--
-- Every app draws its tabs with ui.tabBar and many run them with
-- ui.runTabs, so a test that fakes the screen still runs those two for real
-- and bounds checks what they draw. lib/ui asks lib.util for the time as it
-- loads, and a test's own util stub may not have it, so the real module is
-- loaded against a throwaway one.
local saved = package.loaded["lib.util"]
package.loaded["lib.util"] = { nowMs = function() return 0 end }
local realUi = dofile("../lib/ui.lua")
package.loaded["lib.util"] = saved
return realUi
