-- PUMPE APP: Internet
-- PUMPE APP ACTION: go | Go to a domain | Type an address














return function(api)
local ui, util, target = api.ui, api.util, api.target
local colors = api.colors

local NET = colors.lightBlue
local HISTORY_SIZE = 12
local saved = type(api.load) == "function" and api.load() or {}
saved.history = type(saved.history) == "table" and saved.history or {}
saved.bookmarks = type(saved.bookmarks) == "table" and saved.bookmarks or {}
local history, bookmarks = saved.history, saved.bookmarks

local TABS = { { id = "go", label = "Go" },
{ id = "saved", label = "Saved" }, { id = "recent", label = "Recent" } }

local function running() return api.running() end
local function keep()
if type(api.save) == "function" then api.save(saved) end
end

local function clean(domain)
return string.lower(util.trim(tostring(domain or "")))
end

local function visit(domain)
domain = clean(domain)
if domain == "" then return end
if type(api.browse) ~= "function" then
ui.message(target, "info", "Not on this Pocket",
"This phone is on an older release", 2)
return
end
for index = #history, 1, -1 do
if history[index] == domain then table.remove(history, index) end
end
table.insert(history, 1, domain)
while #history > HISTORY_SIZE do table.remove(history) end
keep()
api.browse(domain)
end

local function ask(initial)


local typed, picked = ui.input(target, "Go to", {
hint = "foxden, or a store.shop", initial = initial,
maxLength = 25, mode = "domain",

suggest = function(value)
local found, seen = {}, {}
value = string.lower(value)
for _, list in ipairs({ bookmarks, history }) do
for _, domain in ipairs(list) do
if #found < 4 and not seen[domain]
and string.lower(domain):find(value, 1, true) then
seen[domain] = true
found[#found + 1] = { label = domain,
detail = list == bookmarks and "Saved" or "Visited" }
end
end
end
return found
end,
})
return picked and picked.label or typed
end

local function isSaved(domain)
for index, item in ipairs(bookmarks) do
if item == domain then return index end
end
return nil
end


if type(api.action) == "function" and api.action() == "go" then
local typed = ask()
if typed then visit(typed) end
return
end



local function drawList(scene, list, top, prefix, empty, removable)
local width = target.getSize()
local bottom = type(ui.contentBottom) == "function"
and ui.contentBottom(target) or select(2, target.getSize()) - 2
if #list == 0 then
ui.wrappedText(target, 2, top, empty, width - 2, 4, ui.theme.muted)
return
end
for index, domain in ipairs(list) do
local y = top + (index - 1)
if y > bottom then break end
scene:button(prefix .. index, 2, y, removable and width - 6 or width - 2, 1,
ui.truncate((isSaved(domain) and "* " or "") .. domain, width - 8),
{ background = ui.theme.panel })
if removable then
scene:button("unmark:" .. index, width - 3, y, 3, 1, "x",
{ background = ui.theme.danger })
end
end
end

local tab = "go"
while running() do
local width = target.getSize()
ui.clear(target)
local scene = ui.scene(target)
if tab == "go" then
ui.header(target, "Internet", "Type a domain", util.formatClock())
scene:button("go", 2, 5, width - 2, 3, "Go to a domain",
{ background = NET, foreground = colors.black, shadow = true })
if #history == 0 then



ui.wrappedText(target, 2, 10, "Websites are made in Website"
.. " Crafter. Stores are at name.shop: try one.",
width - 2, 5, ui.theme.muted)
else
ui.text(target, 2, 10, "RECENTLY", ui.theme.muted)
local recent = {}
for index = 1, math.min(4, #history) do recent[index] = history[index] end
drawList(scene, recent, 11, "again:", "")
end
elseif tab == "saved" then
ui.header(target, "Saved", #bookmarks .. " sites", util.formatClock())
scene:button("add", 2, 4, width - 2, 1, "+ Save a domain",
{ background = ui.theme.accentDark })
drawList(scene, bookmarks, 6, "mark:",
"Nothing saved yet. Save a site to find it here.", true)
else
ui.header(target, "Recent", #history .. " sites", util.formatClock())
if #history > 0 then
scene:button("clear", 2, 4, width - 2, 1, "Clear what you visited",
{ background = ui.theme.panel })
end
drawList(scene, history, 6, "again:", "Nothing visited yet.")
end
if type(ui.tabBar) == "function" then
ui.tabBar(scene, target, TABS, tab, NET)
else
local _, height = target.getSize()
scene:button("home", 1, height, 8, 1, "< Home",
{ background = ui.theme.panel })
end
local action = scene:wait({ tickRate = 5 })
if action == "home" or action == "back" or action == "__terminate" then
return
end
local picked = (action or ""):match("^tab:(.+)$")
local again = tonumber(action and action:match("^again:(%d+)$"))
local mark = tonumber(action and action:match("^mark:(%d+)$"))
local unmark = tonumber(action and action:match("^unmark:(%d+)$"))
if picked then
tab = picked
elseif action == "go" then
local typed = ask()
if typed then visit(typed) end
elseif action == "add" then
local typed = ask()
local domain = typed and clean(typed)
if domain and domain ~= "" and not isSaved(domain) then
table.insert(bookmarks, 1, domain)
keep()
end
elseif action == "clear" then
if ui.confirm(target, "Clear it?", "The sites you visited are"
.. " forgotten. Saved ones stay.", "Clear", "Keep") then
for index = #history, 1, -1 do history[index] = nil end
keep()
end
elseif again and history[again] then
visit(history[again])
elseif mark and bookmarks[mark] then
visit(bookmarks[mark])
elseif unmark and bookmarks[unmark] then
table.remove(bookmarks, unmark)
keep()
end
end
end
