local util = require("lib.util")

local ui = {}

local phoneStyle = false
local idleTimeoutMs
local idleHandler
local lastActivityMs = util.nowMs()
local idleHandling = false
local backgroundIntervalMs
local backgroundHandler
local backgroundRunning = false
local lastBackgroundMs = util.nowMs()

ui.theme = {
background = colors.black,
panel = colors.gray,
panelAlt = colors.lightGray,
ink = colors.white,
muted = colors.lightGray,
accent = colors.orange,
accentDark = colors.brown,
accentInk = colors.black,
success = colors.lime,
danger = colors.red,


warning = colors.yellow,
shadow = colors.gray,
}


function ui.inkOn(color)
if color == colors.purple or color == colors.blue or color == colors.red
or color == colors.green or color == colors.brown
or color == colors.gray or color == colors.black then
return colors.white
end
return colors.black
end






ui.MAIN_COLORS = {
{ id = "orange", label = "Orange", color = colors.orange, dark = colors.brown },
{ id = "red", label = "Red", color = colors.red, dark = colors.brown },
{ id = "pink", label = "Pink", color = colors.pink, dark = colors.magenta },
{ id = "magenta", label = "Magenta", color = colors.magenta, dark = colors.purple },
{ id = "purple", label = "Purple", color = colors.purple, dark = colors.purple },
{ id = "blue", label = "Blue", color = colors.blue, dark = colors.blue },
{ id = "lightBlue", label = "Sky", color = colors.lightBlue, dark = colors.blue },
{ id = "cyan", label = "Cyan", color = colors.cyan, dark = colors.blue },
{ id = "green", label = "Green", color = colors.green, dark = colors.green },
{ id = "lime", label = "Lime", color = colors.lime, dark = colors.green },
{ id = "yellow", label = "Yellow", color = colors.yellow, dark = colors.brown },
}
ui.mainColor = "orange"

local function mainColorEntry(id)
for _, entry in ipairs(ui.MAIN_COLORS) do
if entry.id == id then return entry end
end
return nil
end


function ui.setMainColor(id)
local entry = mainColorEntry(id)
if not entry then return false end
ui.mainColor = entry.id
ui.theme.accent = entry.color
ui.theme.accentDark = entry.dark
ui.theme.accentInk = ui.inkOn(entry.color)
return true
end

local function mainColorFile(root)
return fs.combine(root or "/pumpe", "main_color.dat")
end


function ui.hasMainColor(root)
return fs.exists(mainColorFile(root))
end


function ui.useMainColor(root)
local saved = util.loadTable(mainColorFile(root), {})
if not ui.setMainColor(saved.color) then ui.setMainColor("orange") end
return ui.mainColor
end

function ui.saveMainColor(root, id)
if not ui.setMainColor(id) then return false end
pcall(util.saveTable, mainColorFile(root), { color = ui.mainColor })
return true
end

function ui.usePhoneStyle(enabled)
phoneStyle = enabled == true
end

function ui.noteActivity()
lastActivityMs = util.nowMs()
end

function ui.idleForMs()
return math.max(0, util.nowMs() - lastActivityMs)
end

function ui.setIdleLock(seconds, handler)
seconds = tonumber(seconds)
if not seconds or seconds <= 0 or type(handler) ~= "function" then
idleTimeoutMs, idleHandler = nil, nil
return
end
idleTimeoutMs = seconds * 1000
idleHandler = handler
ui.noteActivity()
end





function ui.setBackgroundTask(seconds, handler)
seconds = tonumber(seconds)
if not seconds or seconds <= 0 or type(handler) ~= "function" then
backgroundIntervalMs, backgroundHandler = nil, nil
return
end
backgroundIntervalMs = seconds * 1000
backgroundHandler = handler
lastBackgroundMs = util.nowMs()
end

local function keyBindings(entries)
local bindings = {}
if type(keys) ~= "table" then return bindings end
for keyName, action in pairs(entries or {}) do
local keyCode = keys[keyName]
if type(keyCode) == "number" then bindings[keyCode] = action end
end
return bindings
end

local function surface(target)
return target or term.current()
end









local overlay
function ui.setOverlay(spec)
overlay = type(spec) == "table" and spec or nil
if overlay then overlay.target = surface(overlay.target) end
end

function ui.overlay() return overlay end


function ui.size(target)
return surface(target).getSize()
end

function ui.isColor(target)
return surface(target).isColor()
end

function ui.clear(target, background)
target = surface(target)
target.setBackgroundColor(background or ui.theme.background)
target.setTextColor(ui.theme.ink)
target.clear()
target.setCursorPos(1, 1)
end

function ui.fill(target, x, y, width, height, background, character)
target = surface(target)
local sw, sh = target.getSize()
x, y = math.floor(x), math.floor(y)
width = math.max(0, math.min(math.floor(width), sw - x + 1))
height = math.max(0, math.min(math.floor(height), sh - y + 1))
if width <= 0 or height <= 0 then return end
target.setBackgroundColor(background)
local line = string.rep(character or " ", width)
for row = y, y + height - 1 do
if row >= 1 and row <= sh then
target.setCursorPos(math.max(1, x), row)
target.write(line)
end
end
end

function ui.text(target, x, y, value, foreground, background, maxWidth)
target = surface(target)
local sw, sh = target.getSize()
if y < 1 or y > sh or x > sw then return end
value = tostring(value or "")
if maxWidth then value = value:sub(1, math.max(0, maxWidth)) end
if x < 1 then
value = value:sub(2 - x)
x = 1
end
if #value > sw - x + 1 then value = value:sub(1, sw - x + 1) end
if background then target.setBackgroundColor(background) end
target.setTextColor(foreground or ui.theme.ink)
target.setCursorPos(x, y)
target.write(value)
end

function ui.center(target, y, value, foreground, background, maxWidth)
target = surface(target)
local width = target.getSize()
value = tostring(value or "")
if maxWidth and #value > maxWidth then value = value:sub(1, maxWidth) end
ui.text(target, math.max(1, math.floor((width - #value) / 2) + 1), y,
value, foreground, background)
end

function ui.truncate(value, length)
value = tostring(value or "")
if #value <= length then return value end
if length <= 2 then return value:sub(1, length) end
return value:sub(1, length - 2) .. ".."
end

function ui.wrap(value, width)
width = math.max(1, math.floor(tonumber(width) or 1))
value = tostring(value or "")
local lines = {}
for paragraph in (value .. "\n"):gmatch("(.-)\n") do
paragraph = util.trim(paragraph)
if paragraph == "" then
lines[#lines + 1] = ""
else
while #paragraph > width do
local breakAt
for index = width, 1, -1 do
if paragraph:sub(index, index) == " " then
breakAt = index
break
end
end
if not breakAt or breakAt < math.floor(width / 2) then
breakAt = width
end
lines[#lines + 1] = util.trim(paragraph:sub(1, breakAt))
paragraph = util.trim(paragraph:sub(breakAt + 1))
end
if paragraph ~= "" then lines[#lines + 1] = paragraph end
end
end
if #lines == 0 then lines[1] = "" end
return lines
end

function ui.wrappedText(target, x, y, value, width, maxLines,
foreground, background)
width = math.max(1, math.floor(tonumber(width) or 1))
maxLines = math.max(1, math.floor(tonumber(maxLines) or 1))
local lines = ui.wrap(value, width)
if #lines > maxLines then
while #lines > maxLines do table.remove(lines) end
lines[maxLines] = ui.truncate(lines[maxLines] .. "..", width)
end
for index, line in ipairs(lines) do
ui.text(target, x, y + index - 1, line,
foreground, background, width)
end
return #lines
end

function ui.header(target, title, subtitle, clockText)
target = surface(target)
local width = target.getSize()
if phoneStyle then
ui.fill(target, 1, 1, width, 3, ui.theme.background)
ui.text(target, 2, 1, "Pocket", ui.theme.muted, ui.theme.background)
local clock = clockText or util.formatClock()
ui.center(target, 1, clock, ui.theme.ink, ui.theme.background)
ui.text(target, math.max(1, width - 2), 1, "[]",
ui.theme.success, ui.theme.background)
ui.text(target, 2, 2, ui.truncate(title, width - 3),
ui.theme.ink, ui.theme.background)
if subtitle then
ui.text(target, 2, 3, ui.truncate(subtitle, width - 3),
ui.theme.muted, ui.theme.background)
end
return
end
ui.fill(target, 1, 1, width, subtitle and 3 or 2, ui.theme.panel)
local titleWidth = clockText and (width - #clockText - 3) or (width - 3)
ui.text(target, 2, 1, ui.truncate(title, math.max(1, titleWidth)),
ui.theme.ink, ui.theme.panel)
if clockText then
ui.text(target, math.max(1, width - #clockText + 1), 1, clockText,
ui.theme.accent, ui.theme.panel)
end
if subtitle then
ui.text(target, 2, 2, ui.truncate(subtitle, width - 3),
ui.theme.muted, ui.theme.panel)
end
ui.fill(target, 1, subtitle and 3 or 2, width, 1, ui.theme.accent)
end

local Scene = {}
Scene.__index = Scene

function ui.scene(target)
target = surface(target)
local width, height = target.getSize()
return setmetatable({
target = target,
width = width,
height = height,
buttons = {},
}, Scene)
end

function Scene:button(id, x, y, width, height, label, options)
options = options or {}
width, height = math.max(1, width), math.max(1, height)
local background = options.background or ui.theme.panel
local foreground = options.foreground or ui.theme.ink
if options.disabled then
background, foreground = colors.gray, colors.lightGray
end

if options.shadow and x + width <= self.width and y + height <= self.height then
ui.fill(self.target, x + 1, y + 1, width, height, ui.theme.shadow)
end
ui.fill(self.target, x, y, width, height, background)
if phoneStyle and height >= 2 and width >= 4 then


local corner = options.corner or ui.theme.background
ui.fill(self.target, x, y, 1, 1, corner)
ui.fill(self.target, x + width - 1, y, 1, 1, corner)
ui.fill(self.target, x, y + height - 1, 1, 1, corner)
ui.fill(self.target, x + width - 1, y + height - 1, 1, 1, corner)
end

local labelWidth = math.max(1, width - 2)
local lines = ui.wrap(label or "", labelWidth)
if #lines > height then
while #lines > height do table.remove(lines) end
lines[height] = ui.truncate(lines[height] .. "..", labelWidth)
end
local firstY = y + math.floor((height - #lines) / 2)
for index, line in ipairs(lines) do
local textX = x + math.max(0, math.floor((width - #line) / 2))
ui.text(self.target, textX, firstY + index - 1, line, foreground, background)
end

if not options.disabled then
self.buttons[#self.buttons + 1] = {
id = id, x1 = x, y1 = y,
x2 = x + width - 1, y2 = y + height - 1,
background = background,
}
end
end



function Scene:hotspot(id, x, y, width, height)
self.buttons[#self.buttons + 1] = {
id = id, x1 = x, y1 = y,
x2 = x + math.max(1, width) - 1,
y2 = y + math.max(1, height) - 1,
flash = false,
}
end

function Scene:hit(x, y)
for index = #self.buttons, 1, -1 do
local button = self.buttons[index]
if x >= button.x1 and x <= button.x2
and y >= button.y1 and y <= button.y2 then
return button.id, button
end
end
return nil
end



local customerScreens = {}
function ui.customerScreen(name)
if name then customerScreens[name] = true end
end

function Scene:wait(options)
options = options or {}
local timer
if options.tickRate then
timer = os.startTimer(options.tickRate)
end
local idleTimer

local function cancelTimer(timerId)
if timerId and os.cancelTimer then pcall(os.cancelTimer, timerId) end
end

local backgroundTimer

local function backgroundDue()
if not backgroundIntervalMs or not backgroundHandler
or backgroundRunning then return nil end
return math.max(0, backgroundIntervalMs
- (util.nowMs() - lastBackgroundMs))
end

local function scheduleBackgroundTimer()
local remaining = backgroundDue()
if not remaining then return nil end
return os.startTimer(math.max(0.05, remaining / 1000))
end

local function runBackgroundTask()
local remaining = backgroundDue()
if not remaining or remaining > 0 then return false end
lastBackgroundMs = util.nowMs()
backgroundRunning = true
local ok, tookOver = pcall(backgroundHandler)
backgroundRunning = false
lastBackgroundMs = util.nowMs()
if not ok then error(tookOver, 0) end
return tookOver == true
end

local function scheduleIdleTimer()
if not idleTimeoutMs or not idleHandler or idleHandling then return nil end
local remaining = math.max(50, idleTimeoutMs - ui.idleForMs())
return os.startTimer(remaining / 1000)
end

local function finish(action)
cancelTimer(timer)
cancelTimer(idleTimer)
cancelTimer(backgroundTimer)
return action
end

local function recordActivity()
if idleHandling then return end
ui.noteActivity()
cancelTimer(idleTimer)
idleTimer = scheduleIdleTimer()
end

local function handleIdle()
if idleHandling or not idleTimeoutMs or not idleHandler
or ui.idleForMs() < idleTimeoutMs then return false end
idleHandling = true
local ok, err = pcall(idleHandler, ui.idleForMs())
idleHandling = false
ui.noteActivity()
if not ok then error(err, 0) end
return true
end


local function onTop()
return overlay and overlay.target == self.target and overlay or nil
end
local function drawOverlay()
local shown = onTop()
if shown and shown.draw then pcall(shown.draw, self.target) end
end



if runBackgroundTask() then return finish("__wake") end
drawOverlay()
idleTimer = scheduleIdleTimer()
backgroundTimer = scheduleBackgroundTimer()
while true do
local event = { os.pullEvent() }
local shown = (event[1] == "mouse_click" or event[1] == "monitor_touch")
and not customerScreens[event[2]] and onTop()
local onBanner = shown and event[4] >= (shown.top or 1)
and event[4] <= (shown.bottom or 0)
if event[1] == "monitor_touch" and customerScreens[event[2]] then

elseif onBanner then


recordActivity()
for _, button in ipairs(shown.buttons or {}) do
if event[3] >= button.x1 and event[3] <= button.x2
and event[4] >= button.y1 and event[4] <= button.y2 then
local ok, err = pcall(shown.tap, button.id)
if not ok then error(err, 0) end
return finish("__wake")
end
end
elseif event[1] == "mouse_click" or event[1] == "monitor_touch" then
if handleIdle() then return finish("__idle") end
recordActivity()
local action, button = self:hit(event[3], event[4])
if action then
if options.flash ~= false and button.flash ~= false then
ui.fill(self.target, button.x1, button.y1,
button.x2 - button.x1 + 1,
button.y2 - button.y1 + 1, ui.theme.accentDark)
sleep(0.04)
end
return finish(action)
end
elseif event[1] == "key" then
if handleIdle() then return finish("__idle") end
recordActivity()
local action = options.keys and options.keys[event[2]]
if action then return finish(action) end
elseif event[1] == "char" then
if handleIdle() then return finish("__idle") end
recordActivity()
local action = options.onChar and options.onChar(event[2])
if action then return finish(action) end
elseif backgroundTimer and event[1] == "timer"
and event[2] == backgroundTimer then
if runBackgroundTask() then return finish("__wake") end
drawOverlay()
backgroundTimer = scheduleBackgroundTimer()
elseif idleTimer and event[1] == "timer" and event[2] == idleTimer then
if handleIdle() then return finish("__idle") end
idleTimer = scheduleIdleTimer()
elseif timer and event[1] == "timer" and event[2] == timer then
if handleIdle() then return finish("__idle") end
return finish("__tick")
elseif event[1] == "terminate" then
return finish("__terminate")
end
end
end
















ui.TAB_COUNT = 4
local PILL_CAP = string.char(149)


local function tabsShown(tabs)
if #tabs <= ui.TAB_COUNT then return #tabs, false end
return ui.TAB_COUNT - 1, true
end


function ui.tabRow(target)
local _, height = surface(target).getSize()
return height - 1
end

function ui.contentBottom(target)
return ui.tabRow(target) - 1
end


local function litTab(tabs, active)
for index = 1, (tabsShown(tabs)) do
if tabs[index].id == active then return active end
end
return "more"
end

local function fitLabel(tab, room)
local label = tostring(tab.label or tab.id)
if #label > room and tab.short then label = tostring(tab.short) end
return label:sub(1, math.max(1, room))
end

function ui.tabBar(scene, target, tabs, active, accent, options)
target = surface(target)
local width, height = target.getSize()
local y = height - 1
local shown = {}
local count, more = tabsShown(tabs)
for index = 1, count do shown[index] = tabs[index] end
if more then shown[#shown + 1] = { id = "more", label = "More", short = "..." } end
local lit = litTab(tabs, active)
local shade, ink = ui.theme.accent, ui.theme.accentInk or ui.inkOn(ui.theme.accent)


local paint = type(target.setBackgroundColor) == "function"


if paint then
ui.fill(target, 1, height, width, 1, ui.theme.background)
ui.fill(target, 3, y, math.max(0, width - 4), 1, ui.theme.panel)
ui.text(target, 2, y, PILL_CAP, ui.theme.background, ui.theme.panel)
ui.text(target, width - 1, y, PILL_CAP, ui.theme.panel, ui.theme.background)
end

local inner = math.max(#shown, width - 4)
local each, over = math.floor(inner / math.max(1, #shown)), inner % math.max(1, #shown)
local x = 3
for index, tab in ipairs(shown) do
local slot = each + (index <= over and 1 or 0)
local on = tab.id == lit
if paint then
if on then ui.fill(target, x, y, slot, 1, shade) end
local label = fitLabel(tab, slot >= 4 and slot - 1 or slot)
ui.text(target, x + math.floor((slot - #label) / 2), y, label,
on and ink or ui.theme.ink, on and shade or ui.theme.panel)
end
scene:hotspot("tab:" .. tab.id, x, y, slot, 1)
x = x + slot
end


if not (options and options.home == false) then
scene:button("home", 1, 1, 1, 1, "<", {
background = shade, foreground = ink, flash = false,
})
scene:hotspot("home", 2, 1, 6, 1)
end
end



local function moreEntries(spec)
local entries = {}
local count = tabsShown(spec.list or {})
for index, tab in ipairs(spec.list or {}) do
entries[#entries + 1] = { id = "tab:" .. tab.id, label = tab.label,
hint = tab.hint, main = index <= count }
end
for _, extra in ipairs(spec.more or {}) do
entries[#entries + 1] = { id = extra.id, label = extra.label,
hint = extra.hint, words = extra.words }
end
return entries
end



function ui.searchEntries(entries, query)
local results = {}
for order, entry in ipairs(entries) do
local label = string.lower(tostring(entry.label or ""))
local everything = label .. " " .. string.lower(tostring(entry.hint or "")
.. " " .. tostring(entry.words or ""))
local score = 0
for word in string.lower(query or ""):gmatch("%S+") do
if label:sub(1, #word) == word then
score = score + 3
elseif (" " .. label):find(" " .. word, 1, true) then
score = score + 2
elseif everything:find(word, 1, true) then
score = score + 1
else
score = nil
break
end
end
if score then results[#results + 1] = { entry = entry, score = score,
order = order } end
end
table.sort(results, function(a, b)
if a.score ~= b.score then return a.score > b.score end
return a.order < b.order
end)
local out = {}
for index, result in ipairs(results) do out[index] = result.entry end
return out
end




function ui.moreMenu(target, spec)
target = surface(target)
local query, selected = "", 1
local entries = moreEntries(spec)
while true do
local width, height = target.getSize()
local list
if query:match("%S") then
list = ui.searchEntries(entries, query)
else
list = {}
for _, entry in ipairs(entries) do
if not entry.main then list[#list + 1] = entry end
end
end
selected = math.max(1, math.min(selected, #list))
ui.clear(target)
ui.header(target, spec.title or "More", spec.subtitle or "Everything else")
local scene = ui.scene(target)
ui.fill(target, 2, 5, width - 2, 1, ui.theme.panel)
local shown = #query > width - 7 and query:sub(-(width - 7)) or query
ui.text(target, 3, 5, query == "" and "Search..." or ("> " .. shown .. "_"),
query == "" and ui.theme.muted or ui.theme.ink, ui.theme.panel)
scene:hotspot("search", 2, 5, width - 2, 1)
ui.text(target, 2, 7, query:match("%S")
and (#list == 0 and "NOTHING MATCHES" or "RESULTS") or "SUGGESTED",
ui.theme.muted)
local rows = height >= 16 and 2 or 1
local top, bottom = 8, ui.contentBottom(target)
local room = math.max(1, math.floor((bottom - top + 1) / rows))
local first = math.max(1, math.min(selected - room + 1, #list - room + 1))
for index = first, math.min(#list, first + room - 1) do
local entry = list[index]
local y = top + (index - first) * rows
local on = index == selected
local background = on and ui.theme.accentDark or ui.theme.panel
ui.fill(target, 2, y, width - 2, rows, background)
ui.text(target, 3, y, ui.truncate(tostring(entry.label), width - 4),
ui.theme.ink, background)
if rows == 2 and entry.hint then
ui.text(target, 3, y + 1, ui.truncate(tostring(entry.hint), width - 4),
ui.theme.muted, background)
end
scene:hotspot("pick:" .. index, 2, y, width - 2, rows)
end
ui.tabBar(scene, target, spec.list or {}, "more", nil,
{ home = spec.home })
local action = scene:wait({
keys = keyBindings({ up = "up", down = "down", enter = "open",
numPadEnter = "open", backspace = "erase" }),
onChar = function(character) return "typed:" .. character end,
})
local typed = action and action:match("^typed:(.)$")
local picked = tonumber(action and action:match("^pick:(%d+)$"))
if typed then
query, selected = query .. typed, 1
elseif action == "erase" then
if query == "" then return "tab:" .. (spec.active or "more") end
query, selected = query:sub(1, -2), 1
elseif action == "up" then
selected = math.max(1, selected - 1)
elseif action == "down" then
selected = math.min(#list, selected + 1)
elseif action == "open" and list[selected] then
return list[selected].id
elseif picked and list[picked] then
return list[picked].id
elseif action == "search" then

local _, item = ui.input(target, "Search", {
hint = spec.title or "More", initial = query, allowSpace = true,
suggest = function(value)
local found = {}
for index, entry in ipairs(ui.searchEntries(entries, value)) do
if index > 4 then break end
found[index] = { label = entry.label, detail = entry.hint,
id = entry.id }
end
return found
end,
})
if item and item.id then return item.id end
elseif action == "tab:more" or action == "__tick" or action == "__idle"
or action == "__wake" then

elseif action then
return action
end
end
end




function ui.resolveTab(target, action, spec)
if action ~= "tab:more" then return action end
return ui.moreMenu(target, spec)
end












function ui.runTabs(spec)
local first = spec.list[1].id
local tab, previous = spec.start or first, nil
while not spec.running or spec.running() do
spec.active = tab

if spec.refresh then spec.refresh(spec) end
local switched = spec.pages[tab](spec)
if switched == "tab:more" then
switched = ui.moreMenu(spec.target, spec)
local run = spec.actions and spec.actions[switched]
if run then
run(spec)
switched = "tab:" .. tab
end
end
local once = spec.once and spec.once[tab]
if once then switched = "tab:" .. (previous or first) end
local nextTab = type(switched) == "string"
and switched:match("^tab:(.+)$")
if not nextTab or not spec.pages[nextTab] then return switched end
if not once then previous = tab end
tab = nextTab
end
end







function ui.betaUpdates(target, root, spec)
target = surface(target)
spec = spec or {}
local kind = tostring(spec.kind or "device")
while true do
local width, height = target.getSize()
local joined = util.betaJoined(root)
local onBeta = util.isBetaVersion(spec.version)
ui.clear(target)
ui.header(target, "BETA UPDATES", joined and "Signed up" or "Not signed up",
util.formatClock())
local y = 4
y = y + ui.wrappedText(target, 2, y, joined
and ("This " .. kind .. " installs each beta by itself as it comes out.")
or ("Get the next FoxyOS before everybody else. Betas come before"
.. " testing is done, so things can break."), width - 2, 3, ui.theme.ink) + 1
if spec.version then
ui.text(target, 2, y, ui.truncate("Running v" .. tostring(spec.version)
.. (onBeta and "  (a beta)" or ""), width - 2),
onBeta and ui.theme.warning or ui.theme.muted)
y = y + 2
end
if spec.warning and y + 2 < height - 3 then
ui.wrappedText(target, 2, y, spec.warning, width - 2,
math.max(1, height - 4 - y), ui.theme.warning)
end
local scene = ui.scene(target)
local half = math.floor((width - 3) / 2)
scene:button(joined and "leave" or "join", 2, height - 2, half, 2,
joined and "LEAVE" or "SIGN UP", { background = joined
and ui.theme.danger or ui.theme.success,
foreground = joined and ui.inkOn(ui.theme.danger) or colors.black })
scene:button("back", 3 + half, height - 2, width - 3 - half, 2, "BACK",
{ background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "join" and ui.confirm(target, "SIGN UP?", "This " .. kind
.. " will install betas by itself. Leave any time.", "SIGN UP", "BACK") then
util.setBetaJoined(root, true)
ui.message(target, "success", "SIGNED UP", "Betas install here by themselves", 1.4)
elseif action == "leave" and ui.confirm(target, "LEAVE?", onBeta
and "It keeps this beta until the full release comes out."
or "No more betas here.", "LEAVE", "STAY") then
util.setBetaJoined(root, false)
ui.message(target, "success", "LEFT BETA UPDATES", onBeta
and "The full release replaces this beta" or nil, 1.4)
end
end
end













function ui.serverTabs(spec)
local target = surface(spec.target)
local blink = true
local function actionList()
local list = type(spec.actions) == "function" and spec.actions() or spec.actions or {}
if spec.root then
list[#list + 1] = { id = "__color", label = "MAIN COLOUR",
hint = "How this server looks", color = ui.theme.accent,
run = function() ui.pickMainColor(target, spec.root,
spec.colorTitle or "Server colour") end }
end
local betaRoot = spec.betaRoot or spec.root
if betaRoot and spec.beta ~= false then
local joined = util.betaJoined(betaRoot)
list[#list + 1] = { id = "__beta", label = joined and "BETA: ON"
or "BETA UPDATES", hint = "Get what is next first",
color = joined and ui.theme.success or ui.theme.panel,
run = function() ui.betaUpdates(target, betaRoot, { kind = "server",
version = spec.version, warning = spec.betaWarning }) end }
end
return list
end
local function run(id, terminated)
for _, entry in ipairs(actionList()) do
if entry.id == id then return entry.run(terminated) end
end
end
local function header()
local subtitle = type(spec.subtitle) == "function" and spec.subtitle()
or spec.subtitle or ""
ui.header(target, spec.title, subtitle, util.formatClock(blink))
end

local function finish(scene, tabSpec)
ui.tabBar(scene, target, tabSpec.list, tabSpec.active, nil, { home = false })
local action = scene:wait({ tickRate = spec.tickRate or 0.5, flash = false })
blink = not blink
if action == "__tick" or action == "__idle" then
if spec.tick then spec.tick() end
return nil
end
if action == "__terminate" then
run("stop", true)
return nil
end
if action and action:match("^tab:") then return action end
if action then run(action) end
return nil
end
local function page(draw)
return function(tabSpec)
while not spec.running or spec.running() do
ui.clear(target)
header()
local scene = ui.scene(target)
draw(scene)
local switched = finish(scene, tabSpec)
if switched then return switched end
end
end
end

local status = page(function()
local width = target.getSize()
local bottom = ui.contentBottom(target)
local y = 5
local cards = spec.cards and spec.cards() or {}
if #cards > 0 then
local cardWidth = math.floor((width - 1 - #cards) / #cards)
for index, card in ipairs(cards) do
local x = 2 + (index - 1) * (cardWidth + 1)
local panelWidth = index == #cards and width - x or cardWidth
ui.card(target, x, 5, panelWidth, 4, card[3] or ui.theme.accent)
ui.text(target, x + 2, 6, tostring(card[1]), ui.theme.muted, ui.theme.panel)
ui.text(target, x + 2, 7, tostring(card[2]), ui.theme.ink, ui.theme.panel,
panelWidth - 3)
end
y = 10
end
for _, line in ipairs(spec.lines and spec.lines() or {}) do
if y > bottom then break end
ui.text(target, 2, y, ui.truncate(tostring(line[1]), width - 2),
line[2] or ui.theme.ink)
y = y + 1
end
end)

local activity = page(function()
local width = target.getSize()
local list = spec.activity or {}
ui.text(target, 2, 4, "ACTIVITY  " .. #list, ui.theme.muted)
for index = 1, math.min(#list, ui.contentBottom(target) - 4) do
local item = list[index]
ui.text(target, 2, 4 + index, ui.truncate(tostring(item.time) .. "  "
.. tostring(item.text), width - 2), item.color or ui.theme.ink)
end
if #list == 0 then ui.text(target, 2, 6, "Nothing yet", ui.theme.muted) end
end)

local server = page(function(scene)
local width = target.getSize()
local half = math.floor((width - 3) / 2)
for index, entry in ipairs(actionList()) do
local column = (index - 1) % 2
local row = math.floor((index - 1) / 2)
local y = 5 + row * 3
if y + 1 <= ui.contentBottom(target) then
local background = entry.color or ui.theme.panel
scene:button(entry.id, 2 + column * (half + 1), y,
column == 0 and half or width - 3 - half, 2, entry.label,
{ background = background, foreground = ui.inkOn(background) })
end
end
end)

ui.runTabs({
target = target, title = spec.title, subtitle = "Everything here",
list = { { id = "status", label = "Status" }, { id = "activity", label = "Activity",
short = "Log" }, { id = "server", label = spec.serverLabel or "Server" } },
pages = { status = status, activity = activity, server = server },
running = spec.running,
})
end



function ui.pickMainColor(target, root, title)
target = surface(target)
local before, chosen = ui.mainColor, ui.mainColor
while true do
local width, height = target.getSize()
ui.setMainColor(chosen)
ui.clear(target)
ui.header(target, title or "Main colour", "How this device looks")
local scene = ui.scene(target)
local columns = width >= 40 and 4 or 2
local gap = 1
local cellWidth = math.floor((width - 2 - (columns - 1) * gap) / columns)
local rows = math.ceil(#ui.MAIN_COLORS / columns)
local top = 5
local step = math.max(1, math.min(2, math.floor((height - top - 5) / rows)))
for index, entry in ipairs(ui.MAIN_COLORS) do
local column = (index - 1) % columns
local row = math.floor((index - 1) / columns)
local x = 2 + column * (cellWidth + gap)
local y = top + row * step
local label = (entry.id == chosen and "* " or "") .. entry.label
ui.fill(target, x, y, cellWidth, 1, entry.color)
ui.text(target, x + math.max(0, math.floor((cellWidth - #label) / 2)), y,
label:sub(1, cellWidth), ui.inkOn(entry.color), entry.color)
scene:hotspot("color:" .. entry.id, x, y, cellWidth, 1)
end
local previewY = top + rows * step + 1
if previewY <= height - 3 then
local sample = ui.scene(target)
ui.center(target, previewY, "Looks like this", ui.theme.muted)
ui.tabBar(sample, target, { { id = "a", label = "Home" },
{ id = "b", label = "Pay" }, { id = "c", label = "Me" } }, "a")
ui.fill(target, 1, height, width, 1, ui.theme.background)
end
scene:button("cancel", 2, height - 3, math.floor((width - 3) / 2), 1, "Back",
{ background = ui.theme.panel })
scene:button("done", width - math.floor((width - 3) / 2), height - 3,
math.floor((width - 3) / 2), 1, "Done",
{ background = ui.theme.accentDark, foreground = colors.white })
local action = scene:wait()
local picked = action and action:match("^color:(.+)$")
if picked then
chosen = picked
elseif action == "done" then
ui.saveMainColor(root, chosen)
return chosen
elseif action == "cancel" or action == "__terminate" or action == "home" then
ui.setMainColor(before)
return nil
end
end
end

function ui.progress(target, x, y, width, value, maximum, foreground, background)
maximum = maximum == 0 and 1 or maximum
local fraction = util.clamp((value or 0) / (maximum or 1), 0, 1)
ui.fill(target, x, y, width, 1, background or colors.gray)
ui.fill(target, x, y, math.floor(width * fraction + 0.5), 1,
foreground or ui.theme.accent)
end

function ui.card(target, x, y, width, height, accent)
ui.fill(target, x, y, width, height, ui.theme.panel)
ui.fill(target, x, y, 1, height, accent or ui.theme.accent)
if phoneStyle and width >= 4 and height >= 2 then
ui.fill(target, x, y, 1, 1, ui.theme.background)
ui.fill(target, x + width - 1, y, 1, 1, ui.theme.background)
ui.fill(target, x, y + height - 1, 1, 1, ui.theme.background)
ui.fill(target, x + width - 1, y + height - 1,
1, 1, ui.theme.background)
end
end

function ui.wipe(target, title)
target = surface(target)
local width, height = target.getSize()
target.setCursorBlink(false)
for row = 1, height do
ui.fill(target, 1, row, width, 1,
row % 2 == 0 and ui.theme.panel or ui.theme.background)
if row % 3 == 0 then sleep(0.01) end
end
if title then
ui.center(target, math.max(1, math.floor(height / 2)), title,
ui.theme.accent, ui.theme.background)
sleep(0.15)
end
ui.clear(target)
end



local GLYPHS = {
P = { "###", "# #", "###", "#  ", "#  " },
U = { "# #", "# #", "# #", "# #", "###" },
M = { "# #", "###", "###", "# #", "# #" },
E = { "###", "#  ", "###", "#  ", "###" },

F = { "###", "#  ", "## ", "#  ", "#  " },

C = { "###", "#  ", "#  ", "#  ", "###" },
K = { "# #", "# #", "## ", "# #", "# #" },
T = { "###", " # ", " # ", " # ", " # " },
O = { "###", "# #", "# #", "# #", "###" },
X = { "# #", "# #", " # ", "# #", "# #" },
Y = { "# #", "# #", " # ", " # ", " # " },

["0"] = { "###", "# #", "# #", "# #", "###" },
["1"] = { " # ", "## ", " # ", " # ", "###" },
["2"] = { "###", "  #", "###", "#  ", "###" },
["3"] = { "###", "  #", " ##", "  #", "###" },
["4"] = { "# #", "# #", "###", "  #", "  #" },
["5"] = { "###", "#  ", "###", "  #", "###" },
["6"] = { "###", "#  ", "###", "# #", "###" },
["7"] = { "###", "  #", "  #", "  #", "  #" },
["8"] = { "###", "# #", "###", "# #", "###" },
["9"] = { "###", "# #", "###", "  #", "###" },
[":"] = { "   ", " # ", "   ", " # ", "   " },
[" "] = { "   ", "   ", "   ", "   ", "   " },
}
local GLYPH_WIDTH, GLYPH_HEIGHT = 3, 5

ui.wordmarkHeight = GLYPH_HEIGHT




function ui.wordmark(target, y, word, count, color)
target = surface(target)
local width, height = target.getSize()
word = tostring(word or ""):upper()
if word == "" then return false end
local span = #word * (GLYPH_WIDTH + 1) - 1
if span > width or y < 1 or y + GLYPH_HEIGHT - 1 > height then
return false
end
for index = 1, #word do
if not GLYPHS[word:sub(index, index)] then return false end
end
local left = math.floor((width - span) / 2) + 1
for index = 1, math.min(count or #word, #word) do
local glyph = GLYPHS[word:sub(index, index)]
local x = left + (index - 1) * (GLYPH_WIDTH + 1)
for row = 1, GLYPH_HEIGHT do
for column = 1, GLYPH_WIDTH do
if glyph[row]:sub(column, column) == "#" then
ui.fill(target, x + column - 1, y + row - 1, 1, 1,
color or ui.theme.accent)
end
end
end
end
return true
end




function ui.splash(target, word, tagline, options)
target = surface(target)
options = options or {}
local width, height = target.getSize()
local top = math.max(2, math.floor((height - GLYPH_HEIGHT) / 2))
local color = options.color or ui.theme.accent
local big = ui.wordmark(target, top, word, 0, color)
local middle = math.max(1, math.floor(height / 2))

local function frame(count)
ui.clear(target)
if big then
ui.wordmark(target, top, word, count, color)
else
ui.center(target, middle, word:sub(1, count), ui.theme.ink)
end
end

for count = 1, #tostring(word) do
frame(count)
sleep(options.step or 0.16)
end
for _ = 1, (options.blinks or 3) do
ui.clear(target)
sleep(0.15)
frame(#tostring(word))
sleep(0.15)
end
if tagline then
ui.clear(target)
ui.center(target, middle, tagline, ui.theme.ink)
if options.footnote and middle + 2 <= height then
ui.center(target, middle + 2, options.footnote, ui.theme.muted)
end
sleep(options.hold or 3)
end
end








local function updateWordTop(height)
return math.max(1, math.min(math.floor((height - GLYPH_HEIGHT) / 2), height - 15))
end

function ui.updateFrame(target, fraction, lit, note)
target = surface(target)
local width, height = target.getSize()
ui.fill(target, 1, 1, width, height, ui.theme.background)
local top = updateWordTop(height)
if not ui.wordmark(target, top, "FOXY", nil,
lit and ui.theme.accent or ui.theme.background) then
ui.center(target, math.max(1, math.floor(height / 2)), "FOXY",
lit and ui.theme.accent or ui.theme.panel, ui.theme.background)
elseif note and top + GLYPH_HEIGHT + 1 < height then
ui.center(target, top + GLYPH_HEIGHT + 1, ui.truncate(tostring(note), width - 2),
ui.theme.panel, ui.theme.background)
end
local filled = math.floor(width * util.clamp(tonumber(fraction) or 0, 0, 1) + 0.5)
if filled > 0 then ui.fill(target, 1, height, filled, 1, ui.theme.panel) end
end




function ui.updating(target, work, note)
local fraction, lit = 0, true
local function draw() ui.updateFrame(target, fraction, lit, note) end
local function progress(value, text)
fraction = util.clamp(tonumber(value) or 0, 0, 1)
if text then note = text end
draw()
end
local results = { n = 0 }
local function run() results = table.pack(work(progress)) end
draw()
if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
parallel.waitForAny(run, function()
while true do
sleep(0.5)
lit = not lit
draw()
end
end)
else
run()
end
return table.unpack(results, 1, results.n)
end





function ui.updateReady(target, info)
target = surface(target)
local width, height = target.getSize()
local wordTop = updateWordTop(height)

local drawn = ui.wordmark(target, wordTop, info.word or "FOXY", nil, ui.theme.accent)
local panelTop = drawn and math.max(wordTop + GLYPH_HEIGHT + 1, height - 9)
or math.max(1, height - 9)
local frames = 6
for step = 1, frames do
local y = height - math.floor((height - panelTop + 1) * step / frames) + 1
ui.fill(target, 1, y, width, height - y + 1, ui.theme.panel)
sleep(0.04)
end
local function line(y, text, color)
if y >= panelTop and y <= height then
ui.center(target, y, ui.truncate(tostring(text or ""), width - 2),
color, ui.theme.panel)
end
end
line(height - 8, info.title or "FoxyOS", ui.theme.ink)
line(height - 7, "Version " .. tostring(info.version or "?"), ui.theme.muted)
line(height - 6, info.what, ui.theme.muted)
while true do
local scene = ui.scene(target)
scene:button("install", 2, height - 4, width - 2, 2, "Install",
{ background = ui.theme.accent, foreground = ui.theme.accentInk })
scene:button("cancel", 2, height - 1, width - 2, 2, "Cancel & Delete",
{ background = ui.theme.background, foreground = ui.theme.ink })
local action = scene:wait()
if action == "install" then return true end
if action == "cancel" or action == "__terminate" then return false end
end
end









function ui.circleWipe(target, color, after)
target = surface(target)
local width, height = target.getSize()
local cx, cy = (width + 1) / 2, (height + 1) / 2

local reach = math.sqrt((width / 2) ^ 2 + (height * 0.75) ^ 2) + 1
for frame = 1, ui.CIRCLE_FRAMES do
local radius = reach * frame / ui.CIRCLE_FRAMES
for y = 1, height do
local dy = (y - cy) * 1.5
local span = radius * radius - dy * dy
if span > 0 then
local half = math.sqrt(span)
local left = math.max(1, math.ceil(cx - half))
local right = math.min(width, math.floor(cx + half))
if right >= left then
ui.fill(target, left, y, right - left + 1, 1, color)
end
end
end
if after then after() end
sleep(ui.CIRCLE_STEP)
end
end
ui.CIRCLE_FRAMES, ui.CIRCLE_STEP = 7, 0.05


function ui.circles(target, rounds, after)
for _ = 1, rounds or 3 do
ui.circleWipe(target, ui.theme.accent, after)
ui.circleWipe(target, colors.black, after)
end
end


function ui.pocketStart(target, version)
target = surface(target)
ui.circles(target, 3)
local width, height = target.getSize()
ui.fill(target, 1, 1, width, height, colors.black)
local top = math.max(2, math.floor((height - GLYPH_HEIGHT) / 2))
if not ui.wordmark(target, top, "POCKET", nil, ui.theme.accent) then
ui.center(target, math.floor(height / 2), "POCKET", ui.theme.accent,
colors.black)
end
sleep(1)
ui.fill(target, 1, 1, width, height, colors.black)
ui.center(target, math.floor(height / 2), ui.truncate("Powered by FoxyOS "
.. tostring(version or ""), width - 2), colors.white, colors.black)
sleep(1.5)
end


local function pocketBar(target, fraction)
local width, height = target.getSize()
local filled = math.floor(width * util.clamp(tonumber(fraction) or 0, 0, 1) + 0.5)
if filled > 0 then ui.fill(target, 1, height, filled, 1, ui.theme.panel) end
end


function ui.pocketUpdating(target, work)
target = surface(target)
local fraction = 0
local function progress(value) fraction = util.clamp(tonumber(value) or 0, 0, 1) end
local results = { n = 0 }
local function run() results = table.pack(work(progress)) end
if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
parallel.waitForAny(run, function()
while true do
ui.circles(target, 1, function() pocketBar(target, fraction) end)
end
end)
else
run()
end
ui.fill(target, 1, 1, select(1, target.getSize()), select(2, target.getSize()),
colors.black)
return table.unpack(results, 1, results.n)
end


function ui.pocketInstalling(target, seconds)
target = surface(target)
local round = 2 * ui.CIRCLE_FRAMES * ui.CIRCLE_STEP
local rounds = math.max(1, math.ceil((seconds or 15) / round))
for done = 1, rounds do
ui.circles(target, 1, function() pocketBar(target, (done - 1) / rounds) end)
end
pocketBar(target, 1)
end





local VERIFY_WHY = {
unknown = "No Digital ID has that code",
pending = "The government has not confirmed it yet",
rejected = "The government refused it",
suspended = "Its account is suspended",
}

function ui.myIdVerifier(target, ask)
target = surface(target)
while true do
local code = ui.input(target, "MYID CODE", { hint = "They say it: MY-....-....",
mode = "code", maxLength = 10, minLength = 8 })
if not code then return end
local answer, err = ask(code)
if not answer then
ui.message(target, "error", "NOT CHECKED", err, 2)
else
local width, height = target.getSize()
local color = answer.valid and ui.theme.success or ui.theme.danger
local middle = math.max(5, math.floor(height / 2) - 2)
ui.clear(target)
ui.header(target, "MYID VERIFIER", tostring(answer.code or code),
util.formatClock())
ui.fill(target, 1, middle - 2, width, 5, color)
ui.center(target, middle - 1, answer.valid and "VALID" or "NOT VALID",
ui.inkOn(color), color)
ui.center(target, middle + 1, ui.truncate(answer.valid
and tostring(answer.name) or (VERIFY_WHY[answer.status]
or "Not a Digital ID"), width - 2), ui.inkOn(color), color)
if answer.valid and answer.confirmed_day then
ui.center(target, middle + 4, "Confirmed on day "
.. tostring(answer.confirmed_day), ui.theme.muted)
end
local scene = ui.scene(target)
local half = math.floor((width - 3) / 2)
scene:button("again", 2, height - 2, half, 2, "CHECK ANOTHER",
{ background = ui.theme.accent, foreground = ui.theme.accentInk })
scene:button("done", 3 + half, height - 2, width - 3 - half, 2, "DONE",
{ background = ui.theme.panel })
local action = scene:wait()
if action ~= "again" then return end
end
end
end



function ui.osLabel(config)
local name = type(config) == "table" and config.release_name or nil
if type(name) == "string" and name:find("FoxyOS", 1, true) then return name end
local major = type(config) == "table" and tostring(config.version or ""):match("^(%d+)")
return "FoxyOS" .. (major and (" " .. major) or "")
end

function ui.boot(target, product, subtitle)
target = surface(target)
local width, height = target.getSize()
ui.clear(target)
local centerY = math.max(3, math.floor(height / 2) - 1)
for step = 1, 4 do
ui.clear(target)
ui.center(target, centerY, product, ui.theme.ink)
ui.center(target, centerY + 1, subtitle or "FoxyOS",
ui.theme.muted)
local barWidth = math.max(8, math.min(width - 6, 28))
ui.progress(target, math.floor((width - barWidth) / 2) + 1,
centerY + 3, barWidth, step, 4, ui.theme.accent, ui.theme.panel)
sleep(0.09)
end
end





function ui.message(target, kind, title, body, duration)
target = surface(target)
local width, height = target.getSize()
local color = kind == "success" and ui.theme.success or ui.theme.danger
local inside = ui.theme.background



local left, right = 2, math.max(2, width - 1)
local textWidth = math.max(4, right - left - 3)
local titleLines = ui.wrap(title, textWidth)
local bodyLines = body and body ~= "" and ui.wrap(body, textWidth) or {}
local function bannerHeight() return 4 + #titleLines + #bodyLines end
local function trimTo(lines)
lines[#lines] = ui.truncate(lines[#lines] .. "..", textWidth)
end
while bannerHeight() > height and #bodyLines > 0 do
table.remove(bodyLines)
if #bodyLines > 0 then trimTo(bodyLines) end
end
while bannerHeight() > height and #titleLines > 1 do
table.remove(titleLines)
trimTo(titleLines)
end
local tall = math.min(height, bannerHeight())
local top = math.max(1, math.floor((height - tall) / 2) + 1)
local bottom = top + tall - 1
local middle = math.floor((top + bottom) / 2)
local span = right - left + 1


for step = 1, 3 do
local reach = math.max(1, math.floor(span * step / 3))
ui.fill(target, left + math.floor((span - reach) / 2), middle, reach, 1, color)
sleep(0.03)
end

local opened = 0
while true do
local upper = math.max(top, middle - opened)
local lower = math.min(bottom, middle + opened + 1)
ui.fill(target, left, upper, span, lower - upper + 1, inside)
ui.fill(target, left, upper, span, 1, color)
ui.fill(target, left, lower, span, 1, color)
if lower - upper > 1 then
ui.fill(target, left, upper, 1, lower - upper + 1, color)
ui.fill(target, right, upper, 1, lower - upper + 1, color)
end
if upper == top and lower == bottom then break end
opened = opened + 1
sleep(0.03)
end
local row = top + 2
for _, line in ipairs(titleLines) do
ui.center(target, row, line, color, inside)
row = row + 1
end
for _, line in ipairs(bodyLines) do
ui.center(target, row, line, color, inside)
row = row + 1
end
sleep(duration or 0.8)
end






function ui.topBanner(target, spec, drop)
target = surface(target)
local width = target.getSize()
local color = spec.color or ui.theme.accent
local inside = ui.theme.background
local left, right = 2, math.max(2, width - 1)
local span, tall = right - left + 1, 5
local top = 1 - math.floor((1 - util.clamp(tonumber(drop) or 1, 0, 1)) * tall + 0.5)
local function onScreen(row) return top + row - 1 >= 1 end
local function at(row) return top + row - 1 end
for row = 1, tall do
if onScreen(row) then
local edge = row == 1 or row == tall
ui.fill(target, left, at(row), span, 1, edge and color or inside)
ui.fill(target, left, at(row), 1, 1, color)
ui.fill(target, right, at(row), 1, 1, color)
end
end
if onScreen(2) then
ui.text(target, left + 2, at(2), ui.truncate(tostring(spec.title or ""), span - 4),
color, inside)
end
if onScreen(3) then
ui.text(target, left + 2, at(3), ui.truncate(tostring(spec.body or ""), span - 4),
ui.theme.muted, inside)
end
local buttons = {}
local list = spec.buttons or {}
local inner = span - 4
local each = math.floor((inner - (#list - 1)) / math.max(1, #list))
local x = left + 2
for index, entry in ipairs(list) do
local w = index == #list and (left + 2 + inner - x) or each
local label = ui.truncate(tostring(entry.label), w)
if onScreen(4) then
ui.fill(target, x, at(4), w, 1, entry.color or ui.theme.panel)
ui.text(target, x + math.floor((w - #label) / 2), at(4), label,
ui.inkOn(entry.color or ui.theme.panel), entry.color or ui.theme.panel)
end
buttons[#buttons + 1] = { id = entry.id, x1 = x, y1 = at(4), x2 = x + w - 1,
y2 = at(4) }
x = x + w + 1
end
return { top = 1, bottom = math.max(1, at(tall)), buttons = buttons }
end

local function keyboardRows(mode)
if mode == "integer" then return { "123", "456", "789", "-0<" } end
if mode == "number" then return { "123", "456", "789", ".0<" } end
if mode == "code" then return { "1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM<" } end


if mode == "email" then
return { "1234567890", "QWERTYUIOP", "ASDFGHJKL@", "ZXCVBNM._<" }
end
if mode == "text" then
return { "1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM,.?<" }
end

if mode == "domain" then
return { "1234567890", "QWERTYUIOP", "ASDFGHJKL.", "ZXCVBNM-<" }
end
return { "1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM-_<" }
end




local clipboard = {}
function ui.paste(text)
clipboard.text, clipboard.at = tostring(text or ""), util.nowMs()
end
local function takePaste()
if not clipboard.text or util.nowMs() - (clipboard.at or 0) > 60000 then return nil end
local text = clipboard.text
clipboard.text = nil
return text
end

function ui.input(target, title, options)
target = surface(target)
options = options or {}
local width, height = target.getSize()
local value = tostring(options.initial or "")
local maxLength = options.maxLength or 24
local rows = keyboardRows(options.mode)
local blink = true




local suggestions, suggestedFor = {}, nil

while true do

local pasted = takePaste()
if pasted then value = pasted:sub(1, maxLength) end
ui.clear(target)
ui.header(target, title, options.hint)
local fieldY = options.hint and 5 or 4
ui.fill(target, 2, fieldY, width - 2, 3, ui.theme.panel)
local shown = value
if options.mask then shown = string.rep(options.mask, #value) end
local visibleLength = width - 5
if options.scrollToEnd and #shown > visibleLength then
shown = "<" .. shown:sub(-(visibleLength - 1))
else
shown = ui.truncate(shown, visibleLength)
end
ui.text(target, 3, fieldY + 1, shown .. (blink and "_" or " "),
ui.theme.ink, ui.theme.panel, width - 4)



local actionHeight = height >= 18 and 2 or 1
local actionY = height - actionHeight + 1
local spaceY = options.allowSpace and actionY - 1 or nil
local keyBottom = (spaceY or actionY) - 1
local startY = math.max(fieldY + 3, keyBottom - #rows + 1)
local scene = ui.scene(target)
if options.suggest then
if value ~= suggestedFor then
suggestedFor = value
suggestions = #util.trim(value) > 0
and (options.suggest(value) or {}) or {}
end
for index, item in ipairs(suggestions) do
local y = fieldY + 2 + index
if y > startY - 1 then break end
local detail = item.detail and tostring(item.detail) or ""
local labelRoom = math.max(1, width - 5 - #detail)
ui.fill(target, 2, y, width - 2, 1, index == 1
and ui.theme.accentDark or ui.theme.panel)
ui.text(target, 3, y, ui.truncate(tostring(item.label),
labelRoom), ui.theme.ink, index == 1 and ui.theme.accentDark
or ui.theme.panel)
if #detail > 0 and #detail < width - 8 then
ui.text(target, width - #detail, y, detail, ui.theme.muted,
index == 1 and ui.theme.accentDark or ui.theme.panel)
end
scene:hotspot("suggest:" .. index, 2, y, width - 2, 1)
end
end
for rowIndex, row in ipairs(rows) do
local y = startY + rowIndex - 1
if y <= keyBottom then
local keyWidth = math.max(1, math.floor((width - 2) / #row))
local totalWidth = keyWidth * #row
local startX = math.floor((width - totalWidth) / 2) + 1
for index = 1, #row do
local key = row:sub(index, index)
scene:button("key:" .. key, startX + (index - 1) * keyWidth,
y, keyWidth, 1, key, {
background = key == "<" and ui.theme.danger
or ui.theme.panelAlt,
foreground = key == "<" and colors.white
or colors.black,
})
end
end
end
if spaceY then
scene:button("space", 2, spaceY, width - 2, 1, "SPACE",
{ background = ui.theme.panel })
end
local half = math.floor((width - 2) / 2)
scene:button("cancel", 2, actionY, half, actionHeight, "CANCEL",
{ background = ui.theme.panel })
scene:button("ok", 2 + half, actionY, width - 2 - half, actionHeight,
"DONE", { background = ui.theme.accentDark })

local action = scene:wait({
tickRate = 0.4,
onChar = function(character)
return "typed:" .. character
end,
keys = keyBindings({
backspace = "backspace",
enter = "ok",
numPadEnter = "ok",
escape = "cancel",
}),
flash = false,
})
local picked = tonumber(action and action:match("^suggest:(%d+)$"))
if picked and suggestions[picked] then
return value, suggestions[picked]
elseif action == "__tick" then
blink = not blink
elseif action == "cancel" or action == "__terminate" then
return nil
elseif action == "ok" then
local trimmed = options.keepSpaces and value or util.trim(value)
if #trimmed >= (options.minLength or 1) then return trimmed end
elseif action == "space" and #value < maxLength then
value = value .. " "
elseif action == "backspace" or action == "key:<" then
value = value:sub(1, -2)
else
local key = action and action:match("^key:(.)$")
local typed = action and action:match("^typed:(.)$")
local character = key or typed
if character and character ~= "<" and #value < maxLength then
if options.mode == "integer" then

if character:match("%d") then
value = value .. character
elseif character == "-" and #value == 0 then
value = "-"
end
elseif options.mode == "number" then
if character:match("%d") or (character == "." and not value:find("%.")) then
value = value .. character
end
elseif options.mode == "code" then
if character:match("[%w]") then value = value .. string.upper(character) end
elseif options.mode == "domain" then
if character:match("[%w%.%-]") then
value = value .. string.lower(character)
end
elseif (options.mode == "email" or options.mode == "text") and key then


value = value .. string.lower(character)
else
value = value .. character
end
end
end
end
end

function ui.pin(target, title, allowCancel)
target = surface(target)
local width, height = target.getSize()
local value = ""
local layout = {
{ "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
{ "C", "0", "<" },
}
while true do
ui.clear(target)
ui.header(target, title or "ENTER PIN", "Four digits")
ui.center(target, 5, string.rep("* ", #value) .. string.rep("- ", 4 - #value),
ui.theme.accent)
local scene = ui.scene(target)
local buttonWidth = math.max(5, math.min(10, math.floor((width - 6) / 3)))
local gridWidth = buttonWidth * 3 + 2
local startX = math.floor((width - gridWidth) / 2) + 1
local bottom = allowCancel and height - 1 or height
local startY = math.max(7, math.floor((height - 8) / 2) + 5)
local rowStep = startY + 6 <= bottom and 2 or 1
if startY + rowStep * 3 > bottom then
startY = math.max(4, bottom - rowStep * 3)
end
for row = 1, 4 do
for column = 1, 3 do
local label = layout[row][column]
scene:button("pin:" .. label,
startX + (column - 1) * (buttonWidth + 1),
startY + (row - 1) * rowStep, buttonWidth, 1, label, {
background = label == "C" and ui.theme.danger
or label == "<" and ui.theme.panel
or ui.theme.panelAlt,
foreground = label:match("%d") and colors.black or colors.white,
})
end
end
if allowCancel then
scene:button("cancel", 2, height, math.min(8, width - 2), 1, "BACK",
{ background = ui.theme.panel })
end
local action = scene:wait({
keys = keyBindings({
backspace = "pin:<",
escape = "cancel",
}),
onChar = function(character)
if character:match("%d") then return "pin:" .. character end
end,
flash = false,
})
if action == "cancel" or action == "__terminate" then return nil end
local key = action and action:match("^pin:(.)$")
if key == "C" then
value = ""
elseif key == "<" then
value = value:sub(1, -2)
elseif key and key:match("%d") and #value < 4 then
value = value .. key
if #value == 4 then
sleep(0.08)
return value
end
end
end
end

function ui.confirm(target, title, body, yesLabel, noLabel)
target = surface(target)
local width, height = target.getSize()
ui.clear(target)
ui.header(target, title)


local lines = ui.wrap(body or "", math.max(4, width - 4))
local bodyY = math.max(5, math.floor((height - 3 - #lines) / 2) + 1)
local maxBodyLines = math.max(1, height - 4 - bodyY)
if #lines > maxBodyLines then
while #lines > maxBodyLines do table.remove(lines) end
lines[maxBodyLines] = ui.truncate(lines[maxBodyLines] .. "..", width - 4)
end
for index, line in ipairs(lines) do
ui.center(target, bodyY + index - 1, line, ui.theme.ink)
end
local scene = ui.scene(target)
local buttonWidth = math.max(8, math.floor((width - 6) / 2))
scene:button("no", 2, height - 3, buttonWidth, 2, noLabel or "NO",
{ background = ui.theme.panel })
scene:button("yes", width - buttonWidth, height - 3, buttonWidth, 2,
yesLabel or "YES", { background = ui.theme.accentDark })
return scene:wait({ keys = keyBindings({
y = "yes",
n = "no",
escape = "no",
}) }) == "yes"
end

function ui.networkError(target, err)
ui.message(target, "error", "CONNECTION FAILED", err or "Try again", 1.1)
end

return ui
