-- PUMPE APP: FoxyCloud
-- PUMPE APP ICON: 33333333/33330033/30000003/00000000/30000003/33333333
-- PUMPE APP ACTION: files | FoxyCloud files | Your files, on every device
-- PUMPE APP ACTION: plus | FoxyCloud+ | More room and more perks
-- PUMPE APP ACTION: account | Foxy Account | Your name, PIN and plan















return function(api)
local ui, util, target, colors = api.ui, api.util, api.target, api.colors
local request = api.request
local cloud = api.cloud

local SKY, GOLD = colors.lightBlue, colors.yellow
local KINDS = {
text = { mark = "T", color = colors.lightBlue, word = "Text" },
midi = { mark = string.char(14), color = colors.magenta, word = "MIDI" },
lua = { mark = "<", color = colors.orange, word = "Program" },
image = { mark = "#", color = colors.lime, word = "Picture" },
file = { mark = "?", color = colors.lightGray, word = "File" },
}
local LINE_LENGTH = 60

local function running() return api.running() end
local function pause(seconds)
if type(sleep) == "function" then sleep(seconds) end
end
local function ask(action, payload)
return request(action, payload or {}, true)
end
local function said(kind, title, body, seconds)
ui.message(target, kind, title, body, seconds or 1.4)
end
local function kindOf(file) return KINDS[file and file.kind or ""] or KINDS.file end



local function cleanName(name)
name = tostring(name or ""):gsub("[^%w _%.%-]", "_"):gsub("^[^%w]+", "")
if #name > 24 then
local ending = name:match("(%.%w+)$") or ""
if #ending > 6 then ending = "" end
name = name:sub(1, 24 - #ending) .. ending
end
return name ~= "" and name or "file"
end




local function drawCloud(cx, cy, color, step)
local puffs = { { -3, 0, 4 }, { 0, -1, 6 }, { 3, 0, 4 } }
for index = 1, math.min(step, #puffs) do
local puff = puffs[index]
ui.fill(target, cx + puff[1] - math.floor(puff[3] / 2), cy + puff[2],
puff[3], 1, color)
end
if step > #puffs then
ui.fill(target, cx - 6, cy + 1, 13, 1, color)
ui.fill(target, cx - 5, cy + 2, 11, 1, color)
end
end

local function intro(plus)
local width, height = target.getSize()
local cx, cy = math.floor(width / 2) + 1, math.floor(height / 2) - 2
ui.clear(target)
for step = 1, 4 do
drawCloud(cx, cy, SKY, step)
pause(0.07)
end
local word = "FoxyCloud" .. (plus and "+" or "")
local left = math.floor((width - #word) / 2) + 1
for index = 1, #word do
local plusSign = plus and index == #word
ui.text(target, left + index - 1, cy + 4, word:sub(index, index),
plusSign and GOLD or ui.theme.ink, ui.theme.background)
pause(0.04)
end
ui.center(target, cy + 6, "by Foxy", ui.theme.muted, ui.theme.background)
pause(0.3)
end


local function sparkle()
local width, height = target.getSize()
local spots = {}
for index = 1, 14 do
spots[index] = { math.random(2, width - 1), math.random(3, height - 3) }
end
for index, spot in ipairs(spots) do
ui.text(target, spot[1], spot[2], index % 2 == 0 and "*" or "+", GOLD)
pause(0.03)
end
pause(0.2)
end


local function moving(title, name)
local width, height = target.getSize()
local y = math.floor(height / 2)
ui.clear(target)
ui.header(target, title, ui.truncate(name, width - 3), util.formatClock())
drawCloud(math.floor(width / 2) + 1, y - 5, SKY, 4)
ui.center(target, y, ui.truncate(name, width - 2), ui.theme.ink)
ui.progress(target, 3, y + 2, width - 4, 0, 1, SKY, ui.theme.panel)
return function(done, total)
ui.progress(target, 3, y + 2, width - 4, done, math.max(1, total), SKY,
ui.theme.panel)
ui.center(target, y + 3, done .. " of " .. total, ui.theme.muted)
end
end



local state = { files = nil, plan = nil }

local function refreshFiles()
local listed, err = ask("CLOUD_FILES")
if listed then state.files = listed end
return listed, err
end

local function refreshPlan()
local plan = ask("CLOUD_PLAN")
if plan then state.plan = plan end
return state.plan
end

local function plus() return state.plan and state.plan.plan == "plus" end

local function storageBar(y)
local width = target.getSize()
local listed = state.files or {}
local used, quota = listed.used or 0, math.max(1, listed.quota or 1)
local over = used > quota
ui.progress(target, 2, y, width - 2, math.min(used, quota), quota,
over and ui.theme.danger or plus() and GOLD or SKY, ui.theme.panel)
ui.text(target, 2, y + 1, ui.truncate(util.sizeText(used) .. " of "
.. util.sizeText(quota) .. (over and "  Over: nothing new fits" or ""),
width - 2), over and ui.theme.danger or ui.theme.muted)
end




local function saveAs(name, body, fileId)
local fields = fileId and { file_id = fileId } or { name = cleanName(name) }
local saved, err, code = cloud.save(fields, body,
moving("Uploading", fields.name or name))
if not saved and code == "NAME_TAKEN" then
refreshFiles()
for _, file in ipairs(state.files and state.files.files or {}) do
if string.lower(file.name) == string.lower(fields.name) then
if ui.confirm(target, "Replace?", "You already have "
.. file.name .. ". Put this in its place?", "Replace", "Back") then
return saveAs(name, body, file.file_id)
end
return nil
end
end
end
if not saved then
said("error", code == "CLOUD_QUOTA" and "No room" or "Not saved", err, 2.2)
return nil
end
refreshFiles()
said("success", "Saved", saved.file.name .. "  " .. util.sizeText(saved.file.size), 1)
return saved.file
end



local function splitLines(body)
local lines = {}
if tostring(body or "") == "" then return lines end
for line in (tostring(body or "") .. "\n"):gmatch("(.-)\r?\n") do
lines[#lines + 1] = line
end
if #lines > 1 and lines[#lines] == "" then lines[#lines] = nil end
return lines
end



local function textPage(file, body, editable, owner)
local lines = splitLines(body)
local top, changed = 1, false
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, ui.truncate(file.name, width - 9),
owner and ("From " .. owner) or util.sizeText(#table.concat(lines, "\n")),
util.formatClock())

local rows = {}
for index, line in ipairs(lines) do
local wrapped = ui.wrap(line == "" and " " or line, width - 2)
for _, piece in ipairs(wrapped) do rows[#rows + 1] = { text = piece, line = index } end
end
local scene = ui.scene(target)
local first, last = 4, height - 4
local room = last - first + 1
top = math.max(1, math.min(top, math.max(1, #rows - room + 1)))
for slot = 1, room do
local row = rows[top + slot - 1]
if not row then break end
ui.text(target, 2, first + slot - 1, row.text, ui.theme.ink)
if editable then scene:hotspot("line:" .. row.line, 1, first + slot - 1, width, 1) end
end
if #rows == 0 then
ui.center(target, first + 1, editable and "Empty. Add a line." or "Empty",
ui.theme.muted)
end
local bottom = height - 2
local third = math.floor((width - 4) / 3)
scene:button("up", 2, bottom, third, 1, "Up",
{ background = ui.theme.panel, disabled = top <= 1 })
scene:button("down", 3 + third, bottom, third, 1, "Down",
{ background = ui.theme.panel, disabled = top + room > #rows })
if editable then
scene:button("add", 4 + third * 2, bottom, width - 3 - third * 2, 1, "+ Line",
{ background = SKY, foreground = colors.black })
scene:button("save", width - 7, height, 7, 1, "Save",
{ background = changed and ui.theme.success or ui.theme.panel,
foreground = changed and colors.black or nil, disabled = not changed })
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait({ keys = { [keys and keys.up or 200] = "up",
[keys and keys.down or 208] = "down" } })
if action == "back" or action == "__terminate" then
if not changed or ui.confirm(target, "Leave?", "Your changes are not"
.. " saved.", "Leave", "Stay") then
return nil
end
elseif action == "up" then top = top - math.max(1, room - 1)
elseif action == "down" then top = top + math.max(1, room - 1)
elseif action == "add" then
local typed = ui.input(target, "New line", { mode = "text",
maxLength = LINE_LENGTH, allowSpace = true, minLength = 0 })
if typed then
lines[#lines + 1] = typed
changed, top = true, #rows + 1
end
elseif action == "save" then
local saved = saveAs(file.name, table.concat(lines, "\n"), file.file_id)
if saved then return saved end
else
local index = tonumber(action and action:match("^line:(%d+)$"))
if index and lines[index] then
local typed = ui.input(target, "Line " .. index, { mode = "text",
initial = lines[index], maxLength = LINE_LENGTH,
allowSpace = true, minLength = 0, hint = "Empty removes it" })
if typed == "" then
table.remove(lines, index)
changed = true
elseif typed and typed ~= lines[index] then
lines[index] = typed
changed = true
end
end
end
end
end


local function aboutPage(file, owner)
local width, height = target.getSize()
local kind = kindOf(file)
ui.clear(target)
ui.header(target, ui.truncate(file.name, width - 9), owner and ("From " .. owner)
or kind.word, util.formatClock())
ui.fill(target, 2, 4, 3, 3, kind.color)
ui.text(target, 3, 5, kind.mark, colors.black, kind.color)
ui.text(target, 6, 4, ui.truncate(kind.word .. ", " .. util.sizeText(file.size),
width - 6), ui.theme.ink)
ui.wrappedText(target, 2, 8, file.kind == "midi"
and "Play it on a CCG Casino: CCG app, My Casino, a table, Music, FoxyCloud."
or "This Pocket cannot open it here. Save it to the Pocket to use it.",
width - 2, 5, ui.theme.muted)
local scene = ui.scene(target)
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
scene:wait()
end


local function openFile(file)
if file.kind ~= "text" and file.kind ~= "lua" then return aboutPage(file) end
local body, err = cloud.load(file.file_id, moving("Opening", file.name))
if not body then
said("error", "Cannot open it", err, 2)
return
end
return textPage(file, body, file.kind == "text")
end



local function filePage(file)
while running() and file do
local width, height = target.getSize()
local kind = kindOf(file)
ui.clear(target)
ui.header(target, ui.truncate(file.name, width - 9), kind.word, util.formatClock())
ui.fill(target, 2, 4, 3, 3, kind.color)
ui.text(target, 3, 5, kind.mark, colors.black, kind.color)
ui.text(target, 6, 4, ui.truncate(util.sizeText(file.size), width - 6), ui.theme.ink)
ui.text(target, 6, 5, ui.truncate("Changed day " .. tostring(file.updated_day
or file.created_day or "-"), width - 6), ui.theme.muted)
ui.text(target, 6, 6, ui.truncate(file.share and ("Shared, code " .. file.share)
or "Only you", width - 6), file.share and SKY or ui.theme.muted)
local scene = ui.scene(target)
local half = math.floor((width - 3) / 2)
local y = 8
scene:button("open", 2, y, width - 2, 2, file.kind == "text" and "Open and edit"
or "Open", { background = SKY, foreground = colors.black })
scene:button("share", 2, y + 3, half, 2, file.share and "Unshare" or "Share",
{ background = ui.theme.panel })
scene:button("rename", 3 + half, y + 3, width - 3 - half, 2, "Rename",
{ background = ui.theme.panel })
scene:button("keep", 2, y + 6, half, 2, "Save here",
{ background = ui.theme.panel })
scene:button("delete", 3 + half, y + 6, width - 3 - half, 2, "Delete",
{ background = ui.theme.danger })
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "open" then
local saved = openFile(file)
if saved then file = saved end
elseif action == "share" then
if file.share or ui.confirm(target, "Share it?", "Anybody with the code"
.. " can open it, but not change it.", "Share", "Back") then
local changed, err = ask("CLOUD_SHARE", { file_id = file.file_id,
share = file.share == nil })
if changed then
file = changed.file
if file.share then said("success", "Shared", "Code " .. file.share, 2) end
else said("error", "Not changed", err) end
end
elseif action == "rename" then
local name = ui.input(target, "New name", { mode = "text", initial = file.name,
maxLength = 24, allowSpace = true })
if name and name ~= file.name then
local renamed, err = ask("CLOUD_RENAME", { file_id = file.file_id,
name = cleanName(name) })
if renamed then file = renamed.file else said("error", "Not renamed", err) end
end
elseif action == "keep" then
local body, err = cloud.load(file.file_id, moving("Downloading", file.name))
local kept, keepError = body and cloud.keep(file.name, body)
if kept then
said("success", "On this Pocket", kept, 1.6)
else
said("error", "Not saved here", keepError or err, 2)
end
elseif action == "delete" then
if ui.confirm(target, "Delete?", file.name .. " goes from FoxyCloud on"
.. " every device.", "Delete", "Keep") then
local gone, err = ask("CLOUD_DELETE", { file_id = file.file_id })
if gone then
refreshFiles()
said("success", "Deleted", file.name, 1)
return
end
said("error", "Not deleted", err)
end
end
end
end




local function dropPage()
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Upload", "Drop files", util.formatClock())
drawCloud(math.floor(width / 2) + 1, 6, SKY, 4)
ui.wrappedText(target, 2, 10, "Drag files from your computer onto this"
.. " Pocket's screen. Text and MIDI files are what FoxyCloud opens.",
width - 2, 5, ui.theme.ink)
local scene = ui.scene(target)
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait({ files = true })
if action == "back" or action == "__terminate" then return end
if action == "__files" then
local ok, files = pcall(function() return scene.dropped.getFiles() end)
local count = 0
for _, handle in ipairs(ok and files or {}) do
local name = handle.getName and handle.getName() or "file"
local body = handle.readAll and handle.readAll() or ""
pcall(handle.close)
if saveAs(tostring(name):match("([^/\\]+)$") or name, body or "") then
count = count + 1
end
end
if count > 0 then return end
end
end
end


local function pocketPage()
local names, page = cloud.pocketFiles(), 1
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Upload", "From this Pocket", util.formatClock())
local scene = ui.scene(target)
local perPage = math.max(1, math.floor((height - 7) / 2))
local items, actual, pages = util.page(names, page, perPage)
page = actual
for index, name in ipairs(items) do
scene:button("pick:" .. ((page - 1) * perPage + index), 2, 2 + index * 2,
width - 2, 1, ui.truncate(name, width - 4), { background = ui.theme.panel })
end
if #names == 0 then
ui.wrappedText(target, 2, 5, "Nothing in this Pocket's Downloads yet. Files"
.. " you save here from FoxyCloud go there.", width - 2, 4, ui.theme.muted)
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
if pages > 1 then
scene:button("more", width - 6, height, 6, 1, page .. "/" .. pages,
{ background = ui.theme.panel })
end
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "more" then page = page % pages + 1 end
local index = tonumber(action and action:match("^pick:(%d+)$"))
if index and names[index] then
local body, err = cloud.readPocket(names[index])
if body then
if saveAs(names[index], body) then return end
else said("error", "Cannot read it", err) end
end
end
end

local function newNote()
local name = ui.input(target, "Name the note", { mode = "text", maxLength = 20,
allowSpace = true, hint = "Like shopping list" })
if not name then return end
name = cleanName(name)
if not name:find("%.") then name = name .. ".txt" end
return textPage({ name = name }, "", true)
end


local function openCode()
local code = ui.input(target, "Share code", { mode = "code", maxLength = 6,
hint = "Six letters and numbers" })
if not code then return end
local body, file = cloud.shared(code, moving("Opening", code))
if not body then
said("error", "Cannot open it", file, 2)
return
end
if file.kind == "text" or file.kind == "lua" then
textPage(file, body, false, file.owner_name)
else
aboutPage(file, file.owner_name)
end
if ui.confirm(target, "Keep a copy?", "Put " .. file.name .. " in your own"
.. " FoxyCloud?", "Keep", "No") then
saveAs(file.name, body)
end
end

local function addFiles()
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Add", "To FoxyCloud", util.formatClock())
local scene = ui.scene(target)
local choices = {
{ "note", "New note", "Write it here" },
{ "drop", "Drop files", "From the computer you play on" },
{ "pocket", "From this Pocket", "Its Downloads" },
{ "code", "Open a share code", "Somebody's shared file" },
}
for index, choice in ipairs(choices) do
local y = 1 + index * 3
scene:button(choice[1], 2, y, width - 2, 2, choice[2],
{ background = index == 1 and SKY or ui.theme.panel,
foreground = index == 1 and colors.black or nil })
ui.text(target, 3, y + 1, ui.truncate(choice[3], width - 4),
index == 1 and colors.black or ui.theme.muted,
index == 1 and SKY or ui.theme.panel)
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "note" then newNote()
elseif action == "drop" then dropPage()
elseif action == "pocket" then pocketPage()
elseif action == "code" then openCode() end
refreshFiles()
return
end
end



local filesTop = 1
local function filesPage(tabs)
if not state.files then refreshFiles() end
while running() do
local width, height = target.getSize()
local listed = state.files
ui.clear(target)
ui.header(target, "FoxyCloud" .. (plus() and "+" or ""), listed
and (#listed.files .. " file" .. (#listed.files == 1 and "" or "s"))
or "Offline", util.formatClock())
local scene = ui.scene(target)
if not listed then
ui.wrappedText(target, 2, 5, "FoxyCloud is not answering. The Bank or"
.. " its Vault may be down.", width - 2, 4, ui.theme.muted)
scene:button("retry", 2, 10, width - 2, 2, "Try again", { background = SKY,
foreground = colors.black })
else
storageBar(4)
local bottom = ui.contentBottom(target) - 2
local perPage = math.max(1, math.floor((bottom - 7 + 1) / 2))
local files = listed.files
filesTop = math.max(1, math.min(filesTop, math.max(1, #files - perPage + 1)))
for slot = 1, perPage do
local file = files[filesTop + slot - 1]
if not file then break end
local y = 7 + (slot - 1) * 2
local kind = kindOf(file)
ui.text(target, 2, y, kind.mark, colors.black, kind.color)
ui.text(target, 4, y, ui.truncate(file.name, width - 4), ui.theme.ink)
ui.text(target, 4, y + 1, ui.truncate(kind.word .. "  "
.. util.sizeText(file.size) .. (file.share and "  Shared" or ""),
width - 4), ui.theme.muted)
scene:hotspot("file:" .. (filesTop + slot - 1), 1, y, width, 2)
end
if #files == 0 then
ui.wrappedText(target, 2, 7, "Nothing here yet. Add a note, or drop"
.. " a text or MIDI file onto this Pocket.", width - 2, 4, ui.theme.muted)
end
local buttonY = bottom + 1
local more = #files > perPage
local addWidth = more and width - 11 or width - 2
scene:button("add", 2, buttonY, addWidth, 1, "+ Add",
{ background = SKY, foreground = colors.black })
if more then
scene:button("up", width - 8, buttonY, 4, 1, "^", { background = ui.theme.panel,
disabled = filesTop <= 1 })
scene:button("down", width - 3, buttonY, 3, 1, "v",
{ background = ui.theme.panel, disabled = filesTop + perPage > #files })
end
if listed.servers == 0 then
ui.text(target, 2, 6, ui.truncate("No Cloud Server is running", width - 2),
ui.theme.danger)
end
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait({ tickRate = 30 })
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
if action == "retry" or action == "__tick" then refreshFiles()
elseif action == "add" then addFiles()
elseif action == "up" then filesTop = filesTop - 1
elseif action == "down" then filesTop = filesTop + 1
else
local index = tonumber(action and action:match("^file:(%d+)$"))
local file = index and listed and listed.files[index]
if file then
filePage(file)
refreshFiles()
end
end
end
end

local function plusPage(tabs)
refreshPlan()
while running() do
local width, height = target.getSize()
local plan = state.plan
ui.clear(target)
ui.header(target, "FoxyCloud+", plus() and "Yours" or "Get more",
util.formatClock())
local scene = ui.scene(target)
if not plan then
ui.wrappedText(target, 2, 5, "The Bank is not answering.", width - 2, 3,
ui.theme.muted)
else
ui.fill(target, 2, 4, width - 2, 3, GOLD)
ui.text(target, 3, 4, "FoxyCloud+", colors.black, GOLD)
ui.text(target, 3, 5, ui.truncate(util.money(plan.price, api.config
and api.config.currency or "$") .. " " .. util.everyText(plan.every_days),
width - 4), colors.black, GOLD)
local status = plus() and (plan.ends_day and ("Ends day " .. plan.ends_day)
or ("Next charge day " .. tostring(plan.next_charge_day)))
or "Billed every " .. tostring(plan.every_days) .. " days"
ui.text(target, 3, 6, ui.truncate(status, width - 4), colors.black, GOLD)
local y = 8
for _, perk in ipairs(plan.perks or {}) do
ui.text(target, 2, y, "+", GOLD)
y = y + ui.wrappedText(target, 4, y, perk, width - 4, 2, ui.theme.ink)
end
ui.text(target, 4, y, ui.truncate("More coming soon", width - 4), ui.theme.muted)
local bottom = ui.contentBottom(target) - 1
if not plus() then
scene:button("join", 2, bottom, width - 2, 2, "Get FoxyCloud+",
{ background = GOLD, foreground = colors.black })
elseif plan.ends_day then
scene:button("join", 2, bottom, width - 2, 2, "Keep FoxyCloud+",
{ background = GOLD, foreground = colors.black })
else
scene:button("cancel", 2, bottom, width - 2, 2, "Cancel FoxyCloud+",
{ background = ui.theme.panel })
end
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait()
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
if action == "join" then
local resume = plan.ends_day ~= nil
local pin = (resume or ui.confirm(target, "FoxyCloud+", util.money(plan.price,
"$") .. " now, then " .. util.everyText(plan.every_days)
.. " until you cancel.", "Join", "Not now"))
and ui.pin(target, "Confirm with PIN", true)
if pin then
local joined, err = ask("CLOUD_PLUS_JOIN", { pin = pin })
if joined then
state.plan = joined
refreshFiles()
api.refresh()
if not resume then sparkle() end
said("success", resume and "Keeping it" or "Welcome to FoxyCloud+",
util.sizeText(joined.quota) .. " is yours", 1.6)
else
said("error", "Not joined", err, 2)
end
end
elseif action == "cancel" then
if ui.confirm(target, "Cancel?", "FoxyCloud+ stays until day "
.. tostring(plan.next_charge_day) .. ". Your files are kept.",
"Cancel it", "Keep it") then
local cancelled, err = ask("CLOUD_PLUS_CANCEL")
if cancelled then state.plan = cancelled
else said("error", "Not cancelled", err) end
end
end
end
end

local function accountPage(tabs)
refreshPlan()
if not state.files then refreshFiles() end
while running() do
local width = target.getSize()
local account = api.account() or {}
ui.clear(target)
ui.header(target, "Foxy Account", plus() and "FoxyCloud+" or "FoxyCloud",
util.formatClock())
local rows = {
{ "Name", account.name or "-" },
{ "Account", account.account_id or "-" },
{ "Plan", plus() and "FoxyCloud+" or "Free" },
{ "Storage", state.files and (util.sizeText(state.files.used) .. " of "
.. util.sizeText(state.files.quota)) or "-" },
}
for index, row in ipairs(rows) do
local y = 2 + index * 2
ui.text(target, 2, y, row[1], ui.theme.muted)
ui.text(target, 2, y + 1, ui.truncate(tostring(row[2]), width - 2), ui.theme.ink)
end
local scene = ui.scene(target)
local bottom = ui.contentBottom(target) - 1
local half = math.floor((width - 3) / 2)
scene:button("name", 2, bottom, half, 2, "Name", { background = ui.theme.panel })
scene:button("pin", 3 + half, bottom, width - 3 - half, 2, "PIN",
{ background = ui.theme.panel })
ui.wrappedText(target, 2, 12, "Your Foxy Account lives here. Your money is in Foxy.",
width - 2, 2, ui.theme.muted)
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait()
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
if action == "name" then
local name = ui.input(target, "Your name", { mode = "text",
initial = account.name, maxLength = 20, allowSpace = true, minLength = 2 })
local pin = name and ui.pin(target, "Confirm with PIN", true)
if pin then
local ok, err = ask("FOXY_SET_ACCOUNT", { name = name, pin = pin })
if ok then
api.refresh()
said("success", "Name changed", name, 1.2)
else said("error", "Not changed", err) end
end
elseif action == "pin" then
local current = ui.pin(target, "Your current PIN", true)
local fresh = current and ui.pin(target, "Your new PIN", true)
local again = fresh and ui.pin(target, "Repeat new PIN", true)
if again and again ~= fresh then
said("error", "PINs do not match", "Nothing changed")
elseif again then
local ok, err = ask("FOXY_SET_ACCOUNT", { pin = current, new_pin = fresh })
said(ok and "success" or "error", ok and "PIN changed" or "Not changed",
ok and "Use it from now on" or err)
end
end
end
end



if not cloud then
said("error", "FoxyCloud", "This Pocket needs the FoxyOS 17 update", 2)
return
end
refreshPlan()
intro(plus())
local wanted = type(api.action) == "function" and api.action() or nil
ui.runTabs({
target = target,
list = { { id = "files", label = "Files" }, { id = "plus", label = "Plus" },
{ id = "account", label = "Account" } },
color = SKY,
start = (wanted == "plus" or wanted == "account") and wanted or "files",
pages = { files = filesPage, plus = plusPage, account = accountPage },
running = running,
})
end
