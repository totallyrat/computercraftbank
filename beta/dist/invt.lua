-- PUMPE APP: INVT
-- PUMPE APP ACTION: feed | What's on | Events you can go to
-- PUMPE APP ACTION: new | New event | Invite people to something
-- PUMPE APP ACTION: tickets | My INVT tickets | The tickets you hold











return function(api)
local ui, util, target, colors = api.ui, api.util, api.target, api.colors
local money = api.money
local PINK, DEEP, PAPER = colors.pink, colors.magenta, colors.white

local function running() return api.running() end
local function ask(action, payload)
return api.request(action, payload or {}, true)
end
local function failed(title, err)
ui.message(target, "error", title, err or "The Bank is not answering", 1.8)
end
local function pause(seconds)
if type(sleep) == "function" then sleep(seconds) end
end
local function when(event)
return "Day " .. tostring(event.day) .. "  " .. tostring(event.time)
end
local function price(event)
return (event.price or 0) > 0 and money(event.price) or "Free"
end





local function ticket(x, y, width, height, color)
ui.fill(target, x, y, width, height, color)
local middle = y + math.floor(height / 2)
ui.fill(target, x, middle, 1, 1, ui.theme.background)
ui.fill(target, x + width - 1, middle, 1, 1, ui.theme.background)
for row = y, y + height - 1, 2 do
ui.fill(target, x + width - 5, row, 1, 1, color == PAPER
and colors.lightGray or DEEP)
end
end


local function intro()
local width, height = target.getSize()
local left, envelopeWidth = math.floor(width / 2) - 7, 15
for step = 1, 4 do
ui.clear(target)
local y = height - step * 3 + 1
ui.fill(target, left, y, envelopeWidth, math.min(6, height - y + 1), PINK)
for row = 0, math.min(2, height - y) do
ui.fill(target, left + row, y + row, envelopeWidth - row * 2, 1, DEEP)
end
pause(0.04)
end
local base = height - 12
for step = 1, 3 do
ui.fill(target, left + 2, base - step * 2, envelopeWidth - 4, step * 2, PAPER)
pause(0.05)
end
ui.center(target, base - 4, "INVT", DEEP, PAPER)
pause(0.25)
end



local function rise(top, rows)
local width, height = target.getSize()
for step = 1, 4 do
ui.clear(target)
local y = math.max(top, height - math.floor((height - top) * step / 4))
ticket(2, y, width - 2, math.min(rows, height - y + 1), PAPER)
pause(0.03)
end
end


local function stamp(word, color)
local width, height = target.getSize()
local middle = math.floor(height / 2)
for step = 1, 2 do
local inset = 3 - step
ui.fill(target, 3 + inset, middle - 2 + inset, width - 4 - inset * 2,
5 - inset * 2, color)
pause(0.05)
end
ui.fill(target, 5, middle - 1, width - 8, 3, PAPER)
ui.center(target, middle, word, color, PAPER)
pause(0.5)
end


local function pick(title, subtitle, items, labelOf)
local page = 1
while running() do
local width, height = target.getSize()
local per = math.max(1, math.floor((height - 6) / 2))
local pages = math.max(1, math.ceil(#items / per))
page = math.max(1, math.min(page, pages))
ui.clear(target)
ui.header(target, ui.truncate(title, width - 9),
ui.truncate(subtitle or "", width - 3), util.formatClock())
local scene = ui.scene(target)
for slot = 1, per do
local index = (page - 1) * per + slot
if not items[index] then break end
scene:button("pick:" .. index, 2, 2 + slot * 2, width - 2, 1,
ui.truncate(labelOf(items[index]), width - 4),
{ background = ui.theme.panel })
end
if #items == 0 then
ui.center(target, 6, "Nobody here yet", ui.theme.muted)
end
if pages > 1 then
scene:button("prev", width - 8, height, 3, 1, "^",
{ background = ui.theme.panel, disabled = page <= 1 })
scene:button("next", width - 4, height, 3, 1, "v",
{ background = ui.theme.panel, disabled = page >= pages })
end
scene:button("back", 1, height, 8, 1, "< Back",
{ background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return nil end
if action == "prev" then page = page - 1
elseif action == "next" then page = page + 1
else
local index = tonumber(action and action:match("^pick:(%d+)$"))
if index and items[index] then return items[index] end
end
end
end



local function ticketScreen(item)
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Ticket", ui.truncate(item.title, width - 3),
util.formatClock())
ticket(2, 5, width - 2, 10, PAPER)
ui.center(target, 6, ui.truncate(item.title, width - 8), colors.black, PAPER)
ui.center(target, 7, when(item), colors.gray, PAPER)
ui.center(target, 9, "SHOW AT THE DOOR", colors.gray, PAPER)
ui.center(target, 11, item.code:sub(1, 3) .. " " .. item.code:sub(4, 6),
colors.black, PAPER)
ui.center(target, 13, item.used and "CHECKED IN" or ("By "
.. ui.truncate(tostring(item.host_name), width - 10)),
item.used and colors.red or colors.gray, PAPER)
local scene = ui.scene(target)
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
end
end


local function drawer()
local got, err = ask("INVT_TICKETS")
if not got then return failed("No tickets", err) end
local tickets, page = got.tickets or {}, 1
local width, height = target.getSize()
for step = 1, 5 do
ui.fill(target, 1, 4, width, math.floor((height - 3) * step / 5), DEEP)
pause(0.03)
end
while running() do
local per = math.max(1, math.floor((height - 7) / 3))
local pages = math.max(1, math.ceil(#tickets / per))
page = math.max(1, math.min(page, pages))
ui.clear(target, DEEP)
ui.header(target, "Your tickets", #tickets .. " held", util.formatClock())
local scene = ui.scene(target)
for slot = 1, per do
local index = (page - 1) * per + slot
local item = tickets[index]
if not item then break end
local y = 2 + slot * 3
ticket(2, y, width - 2, 2, item.used and colors.lightGray or PAPER)
ui.text(target, 3, y, ui.truncate(item.title, width - 10),
colors.black, PAPER)
ui.text(target, 3, y + 1, ui.truncate(when(item), width - 10),
colors.gray, PAPER)
ui.text(target, width - 3, y, item.code:sub(1, 2), colors.gray, PAPER)
scene:hotspot("ticket:" .. index, 2, y, width - 2, 2)
end
if #tickets == 0 then
ui.wrappedText(target, 2, 6, "No tickets yet. Find something in"
.. " the feed.", width - 2, 3, PAPER, DEEP)
end
if pages > 1 then
scene:button("prev", 2, height - 2, 4, 1, "<",
{ background = PINK, disabled = page <= 1 })
scene:button("next", width - 4, height - 2, 4, 1, ">",
{ background = PINK, disabled = page >= pages })
end
scene:button("close", 2, height, width - 2, 1, "^  Close  ^",
{ background = PINK, foreground = colors.black })
local action = scene:wait()
if action == "close" or action == "__terminate" then break end
if action == "prev" then page = page - 1
elseif action == "next" then page = page + 1
else
local index = tonumber(action and action:match("^ticket:(%d+)$"))
if index and tickets[index] then ticketScreen(tickets[index]) end
end
end
for step = 4, 1, -1 do
ui.clear(target)
ui.fill(target, 1, 4, width, math.floor((height - 3) * step / 5), DEEP)
pause(0.03)
end
end





local function getTickets(event)
local room = math.min((event.limit or 10) - (event.mine or 0), event.left or 0)
if room <= 0 then
return ui.message(target, "warning", event.left == 0 and "Full" or "That's the most",
event.left == 0 and "No spots left" or "Ten tickets an account", 1.4)
end
local count = 1
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Tickets", ui.truncate(event.title, width - 3),
util.formatClock())
ui.center(target, 6, "HOW MANY?", ui.theme.muted)
ui.center(target, 8, tostring(count), ui.theme.ink)
ui.center(target, 10, (event.price or 0) > 0
and (money(event.price * count) .. " to " .. tostring(event.host_name))
or "Free", ui.theme.muted)
ui.center(target, 11, "Up to " .. room .. " more", ui.theme.muted)
local scene = ui.scene(target)
scene:button("less", 4, 7, 5, 3, "-", { background = ui.theme.panel,
disabled = count <= 1 })
scene:button("more", width - 8, 7, 5, 3, "+", { background = PINK,
foreground = colors.black, disabled = count >= room })
scene:button("go", 2, height - 3, width - 2, 2, (event.price or 0) > 0
and ("Pay " .. money(event.price * count)) or "I'm going",
{ background = PINK, foreground = colors.black, shadow = true })
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "less" then count = count - 1
elseif action == "more" then count = count + 1
elseif action == "go" then
local done, err
if (event.price or 0) > 0 then
local pin = ui.pin(target, "Pay " .. money(event.price * count), true)
if not pin then return end
done, err = ask("INVT_BUY", { invt_id = event.invt_id,
quantity = count, pin = pin })
else
done, err = ask("INVT_JOIN", { invt_id = event.invt_id,
quantity = count })
end
if not done then return failed("Not this time", err) end

local slot = math.floor(height / 2) - 4
ui.clear(target)
ui.fill(target, 3, slot, width - 4, 1, colors.gray)
for step = 1, 6 do
ticket(4, slot + 1, width - 6, step, PAPER)
pause(0.04)
end
ui.center(target, slot + 3, "YOU'RE GOING", DEEP, PAPER)
ui.center(target, slot + 4, count .. (count == 1 and " ticket" or " tickets"),
colors.gray, PAPER)
pause(0.6)
ui.message(target, "success", "You're going!", event.title, 1.2)
return true
end
end
end



local function invite(event)
local how = pick("Invite", event.title, {
{ label = "A friend", id = "friend" },
{ label = "By FoxMail address", id = "mail" },
}, function(item) return item.label end)
if not how then return end
local payload = { invt_id = event.invt_id }
if how.id == "friend" then
local listed, err = ask("INVT_FRIENDS")
if not listed then return failed("No friends list", err) end
local already, choices = {}, {}
for _, item in ipairs(event.invites or {}) do already[item.account_id] = true end
for _, friend in ipairs(listed.friends or {}) do
if not already[friend.account_id] then choices[#choices + 1] = friend end
end
local friend = pick("Invite a friend", #choices .. " to choose from",
choices, function(item) return item.name end)
if not friend then return end
payload.account_id = friend.account_id
else
local address = ui.input(target, "Their FoxMail", { hint = "name@foxy.com",
mode = "email", maxLength = 40, minLength = 3 })
if not address then return end
payload.address = address
end
local sent, err = ask("INVT_INVITE", payload)
if not sent then return failed("Not invited", err) end
stamp("INVITED", DEEP)
ui.message(target, "success", "Invited", sent.invited.name
.. (sent.invited.mailed and " (mailed)" or ""), 1.2)
return sent.event
end

local function checkIn(event)
while running() do
local code = ui.input(target, "Ticket code", { hint = "Six letters on their ticket",
mode = "code", maxLength = 6, minLength = 6 })
if not code then return end
local answer, err = ask("INVT_CHECKIN", { invt_id = event.invt_id, code = code })
if not answer then return failed("Not checked", err) end
if answer.valid then
stamp("WELCOME", colors.green)
ui.message(target, "success", "Checked in", answer.name, 1.2)
else
ui.message(target, "error", answer.already and "Already in" or "Not a ticket",
answer.already and answer.name or "No ticket for this event has that code", 1.6)
end
end
end

local function guests(event)
local list = {}
for _, guest in ipairs(event.guests or {}) do
list[#list + 1] = guest.name .. "  x" .. guest.count
end
for _, invited in ipairs(event.invites or {}) do
if not invited.going then list[#list + 1] = invited.name .. "  invited" end
end
pick("Guests", event.taken .. " of " .. event.spots .. " spots", list,
function(item) return item end)
end



local function eventPage(id)
local slide = true
while running() do
local got, err = ask("INVT_EVENT", { invt_id = id })
if not got then return failed("Cannot open it", err) end
local event = got.event
local width, height = target.getSize()
local function draw(top)
ticket(2, top, width - 2, 9, PAPER)
ui.text(target, 4, top, ui.truncate(event.public and "PUBLIC"
or "PRIVATE", width - 10), DEEP, PAPER)
ui.wrappedText(target, 4, top + 1, event.title, width - 10, 2,
colors.black, PAPER)
ui.text(target, 4, top + 3, ui.truncate(when(event)
.. "  in " .. util.eventCountdown(event.day, event.time),
width - 10), colors.gray, PAPER)
ui.wrappedText(target, 4, top + 4, event.description ~= ""
and event.description or "No description", width - 10, 3,
colors.gray, PAPER)
ui.text(target, 4, top + 8, ui.truncate(price(event) .. "  "
.. event.left .. " of " .. event.spots .. " left", width - 10),
DEEP, PAPER)
end
if slide then
rise(4, 9)
slide = false
end
ui.clear(target)
ui.header(target, "INVT", ui.truncate("By " .. tostring(event.host_name),
width - 3), util.formatClock())
draw(4)
local scene = ui.scene(target)
if (event.mine or 0) > 0 then
ui.center(target, 14, "You have " .. event.mine
.. (event.mine == 1 and " ticket" or " tickets"), DEEP)
end
if event.host then
local half = math.floor((width - 3) / 2)
scene:button("invite", 2, 15, half, 1, "Invite", { background = PINK,
foreground = colors.black })
scene:button("guests", 3 + half, 15, width - 3 - half, 1,
"Guests " .. event.taken, { background = ui.theme.panel })
scene:button("checkin", 2, 17, half, 1, "Check in",
{ background = ui.theme.panel })
scene:button("cancel", 3 + half, 17, width - 3 - half, 1, "Cancel it",
{ background = ui.theme.danger })
else
local full = event.left <= 0 or (event.mine or 0) >= (event.limit or 10)
scene:button("get", 2, 16, width - 2, 2, event.left <= 0 and "Full"
or (event.mine or 0) >= (event.limit or 10) and "You have the most"
or (event.price or 0) > 0 and ("Get tickets  " .. price(event))
or "Join, free", { background = PINK, foreground = colors.black,
disabled = full, shadow = not full })
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait({ tickRate = 5 })
if action == "back" or action == "__terminate" then return end
if action == "get" then
getTickets(event)
elseif action == "invite" then
invite(event)
elseif action == "guests" then
guests(event)
elseif action == "checkin" then
checkIn(event)
elseif action == "cancel" then
if ui.confirm(target, "Cancel it?", (event.price or 0) > 0
and "Everybody who paid gets it back from you" or "Everybody is told",
"Cancel it", "Keep it") then
local done, cancelError = ask("INVT_CANCEL", { invt_id = event.invt_id })
if done then
ui.message(target, "success", "Cancelled", done.refunded > 0
and ("Refunded " .. money(done.refunded)) or event.title, 1.4)
return
end
failed("Not cancelled", cancelError)
end
end
end
end



local function create()
local draft = { title = "", day = nil, time = "18:00", description = "",
spots = 10, price = 0, public = true }
local width = target.getSize()
local function draw(top)
ticket(2, top, width - 2, 12, PAPER)
local rows = {
{ "TITLE", draft.title ~= "" and draft.title or "Tap to name it" },
{ "WHEN", draft.day and ("Day " .. draft.day .. " " .. draft.time)
or "Tap to set" },
{ "ABOUT", draft.description ~= "" and draft.description or "Optional" },
{ "SPOTS", tostring(draft.spots) },
{ "PRICE", draft.price > 0 and money(draft.price) or "Free" },
{ "WHO", draft.public and "Public" or "Private" },
}
for index, row in ipairs(rows) do
local y = top + (index - 1) * 2
ui.text(target, 3, y, row[1], DEEP, PAPER)
ui.text(target, 8, y, ui.truncate(row[2], width - 13), colors.black, PAPER)
end
end
rise(4, 12)
while running() do
local _, height = target.getSize()
ui.clear(target)
ui.header(target, "New event", "Fill in the ticket", util.formatClock())
draw(4)
local scene = ui.scene(target)
for index, id in ipairs({ "title", "when", "about", "spots", "price", "who" }) do
scene:hotspot(id, 2, 4 + (index - 1) * 2, width - 7, 1)
end
scene:button("create", 2, height - 3, width - 2, 2, "Send it out",
{ background = PINK, foreground = colors.black,
disabled = draft.title == "" or not draft.day, shadow = true })
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "title" then
draft.title = ui.input(target, "Title", { hint = "What is it?",
maxLength = 30, allowSpace = true, minLength = 2,
initial = draft.title }) or draft.title
elseif action == "when" then
local day = ui.input(target, "Which day", { mode = "number",
hint = "Today is day " .. util.ingameDay(), maxLength = 6 })
local time = day and ui.input(target, "What time", { mode = "number",
hint = "Four digits, like 1830", maxLength = 5 })
if time then
local raw = time:gsub("[^%d]", "")
if #raw == 3 then raw = "0" .. raw end
if #raw == 4 then time = raw:sub(1, 2) .. ":" .. raw:sub(3, 4) end
draft.day, draft.time = tonumber(day), time
end
elseif action == "about" then
draft.description = ui.input(target, "About it", { hint = "Where, what to bring",
maxLength = 120, allowSpace = true, minLength = 0,
initial = draft.description }) or draft.description
elseif action == "spots" then
draft.spots = tonumber(ui.input(target, "Spots", { mode = "number",
hint = "How many tickets in all", maxLength = 3 })) or draft.spots
elseif action == "price" then
draft.price = tonumber(ui.input(target, "Price", { mode = "number",
hint = "0 for free", maxLength = 7 })) or draft.price
elseif action == "who" then
draft.public = not draft.public
elseif action == "create" then
local made, err = ask("INVT_CREATE", draft)
if not made then
failed("Not sent", err)
else
stamp(draft.public and "POSTED" or "CREATED", DEEP)
if not draft.public then
ui.message(target, "info", "Private", "Now invite people", 1.2)
end
return eventPage(made.event.invt_id)
end
end
end
end



local function feed()
local page, fresh = 1, true
while running() do
local got, err = ask("INVT_FEED")
local events = got and got.events or {}
local held = got and got.tickets or 0
local width, height = target.getSize()
local per = math.max(1, math.floor((height - 8) / 4))
local pages = math.max(1, math.ceil(#events / per))
page = math.max(1, math.min(page, pages))
local function drawCards(offset)
for slot = 1, per do
local event = events[(page - 1) * per + slot]
if not event then break end
local y = 3 + slot * 4
local x = 2 + offset
local cardWidth = math.max(1, math.min(width - 2, width - x + 1))
local tags = price(event) .. "  " .. event.left .. " left"
.. (event.host and "  Yours" or (event.mine or 0) > 0
and ("  Going x" .. event.mine)
or not event.public and "  Invited" or "")
ui.card(target, x, y, cardWidth, 3, event.public and PINK or DEEP)
if cardWidth > 4 then
ui.text(target, x + 2, y, ui.truncate(event.title, cardWidth - 3),
ui.theme.ink, ui.theme.panel)
ui.text(target, x + 2, y + 1, ui.truncate(when(event)
.. "  " .. tostring(event.host_name), cardWidth - 3),
ui.theme.muted, ui.theme.panel)
ui.text(target, x + 2, y + 2, ui.truncate(tags, cardWidth - 3),
event.public and PINK or DEEP, ui.theme.panel)
end
end
end
local function frame(offset)
ui.clear(target)
ui.header(target, "INVT", got and (#events .. " to go to")
or tostring(err or "Offline"), util.formatClock())

ticket(2, 4, width - 2, 2, held > 0 and PINK or ui.theme.panel)
ui.text(target, 4, 4, ui.truncate(held > 0 and ("Your tickets: " .. held)
or "No tickets yet", width - 10), colors.black,
held > 0 and PINK or ui.theme.panel)
ui.text(target, 4, 5, "Pull down  v", colors.black,
held > 0 and PINK or ui.theme.panel)
drawCards(offset)
end

if fresh and #events > 0 then
for _, offset in ipairs({ 12, 6, 2 }) do
frame(offset)
pause(0.03)
end
fresh = false
end
frame(0)
local scene = ui.scene(target)
scene:hotspot("drawer", 2, 4, width - 2, 2)
for slot = 1, per do
local index = (page - 1) * per + slot
if not events[index] then break end
scene:hotspot("event:" .. index, 2, 3 + slot * 4, width - 2, 3)
end
if #events == 0 then
ui.wrappedText(target, 2, 8, got and "Nothing on yet. Start"
.. " something: a party, a quiz, a game night." or "Cannot reach"
.. " the Bank.", width - 2, 4, ui.theme.muted)
end
if pages > 1 then
scene:button("prev", width - 9, height - 2, 4, 1, "<",
{ background = ui.theme.panel, disabled = page <= 1 })
scene:button("next", width - 4, height - 2, 4, 1, ">",
{ background = ui.theme.panel, disabled = page >= pages })
end
scene:button("new", 2, height - 1, width - 2, 2, "+ New event",
{ background = PINK, foreground = colors.black })
local action = scene:wait({ tickRate = 10 })
if action == "__terminate" then return end
if action == "drawer" then
drawer()
elseif action == "new" then
create()
fresh = true
elseif action == "prev" then page, fresh = page - 1, true
elseif action == "next" then page, fresh = page + 1, true
else
local index = tonumber(action and action:match("^event:(%d+)$"))
if index and events[index] then
eventPage(events[index].invt_id)
end
end
end
end



intro()
local me = type(api.login) == "function"
and api.login({ name = "INVT", scopes = { "friends" } }) or nil
while running() and not me do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "INVT", "Sign in", util.formatClock())
ui.wrappedText(target, 2, 6, "INVT needs you signed in with Foxy: it shows"
.. " your name to hosts, and your friends when you invite them.",
width - 2, 5, ui.theme.muted)
local scene = ui.scene(target)
scene:button("login", 2, 12, width - 2, 3, "Sign in with Foxy",
{ background = colors.orange, foreground = colors.black, shadow = true })
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
me = api.login({ name = "INVT", scopes = { "friends" } })
end
local wanted = type(api.action) == "function" and api.action() or nil
if wanted == "new" then create()
elseif wanted == "tickets" then drawer() end
feed()
end
