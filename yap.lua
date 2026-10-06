-- PUMPE APP: Yap!
-- PUMPE APP ACTION: feed | Yap! feed | What everybody is saying
-- PUMPE APP ACTION: chat | Yap! chats | Private messages, behind your PIN
-- PUMPE APP ACTION: map | Yap Map | Where your friends are
--
-- Yap!, by Foxy, FoxyOS 16. Yap and Yap Chat were two apps somebody had to
-- publish; this is one, and every Pocket has it.
--
--   Feed  posts, likes and replies, friends before everybody else
--   Chat  private messages between friends. The tab is behind your PIN,
--         and a message you have read is gone a day later, on both Pockets
--   Map   not a map: your friends' coordinates, when they are in a
--         Coordinate Zone -- somewhere the GPS Anchors can place their
--         Pocket. Only friends who use Yap!, and Hide me takes you off
--
-- Signing up takes your Foxy ID and a VerCode: Foxy sends one to Messages,
-- and the notification it comes with has Paste.

return function(api)
    local ui, util, target, colors = api.ui, api.util, api.target, api.colors
    local request = api.request

    local FEED, CHAT, MAP = colors.cyan, colors.magenta, colors.lime
    local FRIEND = colors.lime
    local MAX_POST, MAX_REPLY, MAX_MESSAGE = 140, 100, 120
    local KEEP_DAYS = 1

    local function running() return api.running() end
    local function pause(seconds)
        if type(sleep) == "function" then sleep(seconds) end
    end
    local function ask(action, payload)
        return request(action, payload or {}, true)
    end
    local function plural(count, one, many)
        return count .. " " .. (count == 1 and one or many)
    end

    -- Animations -------------------------------------------------------------------------

    -- A speech bubble, with its tail at the bottom left.
    local function bubble(x, y, width, height, color)
        ui.fill(target, x, y, width, height, color)
        ui.fill(target, x, y, 1, 1, ui.theme.background)
        ui.fill(target, x + width - 1, y, 1, 1, ui.theme.background)
        ui.fill(target, x + width - 1, y + height - 1, 1, 1, ui.theme.background)
        ui.fill(target, x + 1, y + height, 2, 1, color)
        ui.fill(target, x + 1, y + height + 1, 1, 1, color)
    end

    -- Three typing dots, the bubble they become, and Yap! written in it.
    local function intro()
        local width, height = target.getSize()
        local middle = math.floor(height / 2) - 1
        ui.clear(target)
        for dot = 1, 3 do
            ui.text(target, math.floor(width / 2) - 4 + dot * 2, middle, "o",
                FEED, ui.theme.background)
            pause(0.08)
        end
        for step = 1, 3 do
            local bubbleWidth = 6 + step * 4
            bubble(math.floor((width - bubbleWidth) / 2) + 1, middle - step + 1,
                bubbleWidth, step * 2 - 1 + 1, FEED)
            pause(0.05)
        end
        local word = "Yap!"
        local left = math.floor((width - #word) / 2) + 1
        for index = 1, #word do
            ui.text(target, left + index - 1, middle, word:sub(index, index),
                colors.black, FEED)
            pause(0.06)
        end
        ui.center(target, middle + 7, "by Foxy", ui.theme.muted, ui.theme.background)
        pause(0.35)
    end

    -- Switching tabs: the tab's colour sweeps across under the header.
    local function sweep(color)
        local width = target.getSize()
        for column = 1, width, 4 do
            ui.fill(target, column, 4, math.min(4, width - column + 1), 1, color)
            pause(0.012)
        end
    end

    -- A like: a heart that pops, then settles.
    local function heart(x, y)
        for _, mark in ipairs({ ".", "o", "<3", "<3!", "<3" }) do
            ui.fill(target, x, y, 3, 1, ui.theme.background)
            ui.text(target, x, y, mark, colors.red, ui.theme.background)
            pause(0.05)
        end
    end

    -- Posting: the yap rises up the screen as a bubble and is gone.
    local function liftOff(body)
        local width, height = target.getSize()
        local line = ui.truncate(body, width - 6)
        for y = height - 4, 4, -3 do
            ui.clear(target)
            bubble(2, y, width - 2, 2, FEED)
            ui.text(target, 4, y, line, colors.black, FEED)
            pause(0.04)
        end
        ui.clear(target)
        ui.center(target, math.floor(height / 2), "Yapped!", FEED)
        pause(0.3)
    end

    -- The Chat tab's lock: a shackle that lifts.
    local function unlock()
        local width, height = target.getSize()
        local x, y = math.floor(width / 2) - 2, math.floor(height / 2) - 2
        for lift = 0, 2 do
            ui.clear(target)
            ui.fill(target, x, y + 2, 6, 3, CHAT)
            ui.text(target, x + 1, y - lift, "/  \\", CHAT, ui.theme.background)
            ui.text(target, x + 1, y + 1 - lift, "|", CHAT, ui.theme.background)
            if lift == 0 then
                ui.text(target, x + 4, y + 1, "|", CHAT, ui.theme.background)
            end
            ui.text(target, x + 2, y + 3, "**", colors.black, CHAT)
            pause(0.07)
        end
    end

    -- A sent message slides in from the right edge.
    local function slideIn(y, width, text)
        for step = 4, 0, -1 do
            ui.fill(target, 2, y, width - 2, 1, ui.theme.background)
            ui.text(target, 2 + step, y, ui.truncate(text, width - 3 - step), CHAT)
            pause(0.03)
        end
    end

    -- Yap Map: rings spreading out from the middle, like a ping going out.
    local function ping()
        local width, height = target.getSize()
        local cx, cy = width / 2, height / 2
        for radius = 1, 4 do
            for y = 4, height - 3 do
                for x = 1, width do
                    local dx, dy = x - cx, (y - cy) * 1.5
                    local d = math.sqrt(dx * dx + dy * dy)
                    if math.abs(d - radius * 3) < 0.7 then
                        ui.fill(target, x, y, 1, 1, MAP)
                    end
                end
            end
            pause(0.05)
        end
    end

    -- A stamp landing in the middle of the screen.
    local function stamp(word, color)
        local width, height = target.getSize()
        local middle = math.floor(height / 2)
        for inset = 2, 0, -1 do
            ui.fill(target, 3 + inset, middle - 2 + inset, width - 4 - inset * 2,
                5 - inset * 2, color)
            pause(0.05)
        end
        ui.center(target, middle, word, colors.black, color)
        pause(0.45)
    end

    -- Signing in, and signing up ------------------------------------------------------------

    intro()
    local me = type(api.login) == "function"
        and api.login({ name = "Yap!", scopes = { "friends" } }) or nil
    while running() and not me do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Yap!", "Sign in", util.formatClock())
        ui.wrappedText(target, 2, 6, "Yap! uses your Foxy ID: your name on what you"
            .. " post, and your friends for Chat and Yap Map.", width - 2, 5,
            ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("login", 2, 12, width - 2, 3, "Sign in with Foxy",
            { background = colors.orange, foreground = colors.black, shadow = true })
        scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
        me = api.login({ name = "Yap!", scopes = { "friends" } })
    end
    if not me then return end

    -- Signing up the first time on this Pocket: a VerCode, from Foxy.
    local saved = type(api.load) == "function" and api.load() or {}
    saved.verified = type(saved.verified) == "table" and saved.verified or {}
    local needsCode = type(api.vercode) == "table" and not saved.verified[me.account_id]
    while running() and needsCode do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Yap!", "Sign up", util.formatClock())
        bubble(2, 5, width - 2, 3, FEED)
        ui.text(target, 4, 6, ui.truncate("Hi " .. tostring(me.name), width - 6),
            colors.black, FEED)
        ui.wrappedText(target, 2, 10, "To sign up, Foxy sends a 6 digit code to"
            .. " Messages. Tap Paste on it, or type it.", width - 2, 4, ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("send", 2, height - 4, width - 2, 2, "Send my code",
            { background = FEED, foreground = colors.black })
        scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
        local ok, err = api.vercode.ask("Yap! code")
        if ok then
            saved.verified[me.account_id] = true
            api.save(saved)
            needsCode = false
            stamp("Welcome to Yap!", FEED)
        elseif err then
            ui.message(target, "error", "Not signed up", err, 1.6)
        end
    end

    local friendSet = {}
    for _, friend in ipairs(me.friends or {}) do friendSet[friend.account_id] = true end

    -- Feed ------------------------------------------------------------------------------------

    local function loadFeed()
        local listed = ask("APP_DATA_LIST", { collection = "posts", limit = 40 })
        local mates, others = {}, {}
        -- The Bank hands them back newest first; friends (and you) go on top.
        for _, post in ipairs(listed and listed.records or {}) do
            if friendSet[post.author_id] or post.author_id == me.account_id then
                mates[#mates + 1] = post
            else
                others[#others + 1] = post
            end
        end
        for _, post in ipairs(others) do mates[#mates + 1] = post end
        return mates, listed ~= nil
    end

    local function bodyOf(record)
        return tostring(record.data and record.data.body or "")
    end

    local function compose()
        local body = ui.input(target, "New yap", {
            hint = "Up to " .. MAX_POST .. " characters", maxLength = MAX_POST,
            allowSpace = true, minLength = 1, scrollToEnd = true,
        })
        if not body or util.trim(body) == "" then return false end
        local posted, err = ask("APP_DATA_PUT", { collection = "posts", data = { body = body } })
        if not posted then
            ui.message(target, "error", "Not posted", err, 1.6)
            return false
        end
        liftOff(body)
        return true
    end

    local function postScreen(post)
        local offset = 0
        while running() do
            local width, height = target.getSize()
            local listed = ask("APP_DATA_LIST",
                { collection = "comments", parent = post.id, limit = 40 })
            local replies = listed and listed.records or {}
            ui.clear(target)
            ui.header(target, ui.truncate(tostring(post.author_name), width - 9),
                "Day " .. tostring(post.created_day) .. "  " .. tostring(post.created_time),
                util.formatClock())
            local lines = ui.wrappedText(target, 2, 5, bodyOf(post), width - 2, 4, ui.theme.ink)
            local row = 5 + lines + 1
            ui.text(target, 2, row, plural(post.reactions or 0, "like", "likes") .. "   "
                .. plural(#replies, "reply", "replies"), ui.theme.muted)
            row = row + 2
            local scene = ui.scene(target)
            local per = math.max(1, math.floor((height - 4 - row) / 2))
            offset = math.max(0, math.min(offset, math.max(0, #replies - per)))
            for slot = 1, per do
                local reply = replies[offset + slot]
                if not reply then break end
                local y = row + (slot - 1) * 2
                ui.text(target, 2, y, ui.truncate(tostring(reply.author_name), width - 3),
                    friendSet[reply.author_id] and FRIEND or FEED)
                ui.text(target, 2, y + 1, ui.truncate(bodyOf(reply), width - 3), ui.theme.muted)
            end
            if #replies == 0 then ui.text(target, 2, row, "No replies yet", ui.theme.muted) end
            local half = math.floor((width - 3) / 2)
            scene:button("like", 2, height - 2, half, 2, post.reacted and "Liked" or "Like",
                { background = post.reacted and colors.red or ui.theme.panel })
            scene:button("reply", 3 + half, height - 2, width - 3 - half, 2, "Reply",
                { background = FEED, foreground = colors.black })
            scene:button("back", 1, height, 8, 1, "< Feed", { background = ui.theme.panel })
            if #replies > per then
                scene:button("up", width - 7, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 3, height, 3, 1, "v",
                    { background = ui.theme.panel, disabled = offset + per >= #replies })
            end
            if post.mine then
                scene:button("delete", math.floor(width / 2) - 3, height, 8, 1, "Delete",
                    { background = ui.theme.danger })
            end
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "like" then
                local toggled = ask("APP_DATA_REACT",
                    { collection = "posts", id = post.id, on = not post.reacted })
                if toggled then
                    if not post.reacted then heart(2, height - 3) end
                    post = toggled.record
                end
            elseif action == "reply" then
                local body = ui.input(target, "Reply", {
                    hint = "To " .. tostring(post.author_name), maxLength = MAX_REPLY,
                    allowSpace = true, minLength = 1, scrollToEnd = true,
                })
                if body and util.trim(body) ~= "" then
                    local added, err = ask("APP_DATA_PUT", { collection = "comments",
                        parent = post.id, data = { body = body } })
                    if not added then ui.message(target, "error", "Not sent", err, 1.6) end
                end
            elseif action == "up" then offset = offset - 1
            elseif action == "down" then offset = offset + 1
            elseif action == "delete" and ui.confirm(target, "Delete yap",
                "It goes for everybody.", "Delete", "Keep") then
                ask("APP_DATA_DELETE", { collection = "posts", id = post.id })
                return
            end
        end
    end

    local function drawPost(post, x, y, width)
        local mate = friendSet[post.author_id]
        ui.card(target, x, y, width, 3, mate and FRIEND or FEED)
        if width < 6 then return end
        ui.text(target, x + 2, y, ui.truncate(tostring(post.author_name), width - 9),
            mate and FRIEND or ui.theme.ink, ui.theme.panel)
        ui.text(target, x + width - 6, y, ui.truncate(tostring(post.created_time or ""), 5),
            ui.theme.muted, ui.theme.panel)
        ui.text(target, x + 2, y + 1, ui.truncate(bodyOf(post), width - 3),
            ui.theme.ink, ui.theme.panel)
        ui.text(target, x + 2, y + 2, ui.truncate((post.reacted and "<3 " or "") ..
            plural(post.reactions or 0, "like", "likes"), width - 3),
            post.reacted and colors.red or ui.theme.muted, ui.theme.panel)
    end

    local function feedPage(tabs)
        local feed, reached = loadFeed()
        local page, fresh = 1, true
        sweep(FEED)
        while running() do
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 6) / 4))
            local pages = math.max(1, math.ceil(#feed / per))
            page = math.max(1, math.min(page, pages))
            local function frame(offset)
                ui.clear(target)
                ui.header(target, "Yap!", reached and plural(#feed, "yap", "yaps")
                    or "Offline", util.formatClock())
                for slot = 1, per do
                    local post = feed[(page - 1) * per + slot]
                    if not post then break end
                    local x = 2 + offset
                    drawPost(post, x, 4 + (slot - 1) * 4,
                        math.max(1, math.min(width - 2, width - x + 1)))
                end
            end
            -- Fresh yaps slide in from the right, one page at a time.
            if fresh and #feed > 0 then
                for _, offset in ipairs({ 14, 7, 2 }) do
                    frame(offset)
                    pause(0.03)
                end
            end
            fresh = false
            frame(0)
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                if not feed[index] then break end
                scene:hotspot("post:" .. index, 2, 4 + (slot - 1) * 4, width - 2, 3)
            end
            if #feed == 0 then
                ui.center(target, 8, reached and "Nothing here yet" or "Cannot reach the Bank",
                    ui.theme.ink)
                ui.wrappedText(target, 2, 10, "Tap + Yap to say the first thing.",
                    width - 2, 3, ui.theme.muted)
            end
            local buttonWidth = pages > 1 and width - 11 or width - 2
            scene:button("new", 2, height - 2, buttonWidth, 1, "+ Yap",
                { background = FEED, foreground = colors.black })
            if pages > 1 then
                scene:button("prev", width - 8, height - 2, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 3, height - 2, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
            local action = scene:wait({ tickRate = 15 })
            if action == "home" or action == "__terminate"
                or (action or ""):match("^tab:") then
                return action
            end
            if action == "new" then
                if compose() then
                    feed, reached = loadFeed()
                    page, fresh = 1, true
                end
            elseif action == "prev" then page, fresh = page - 1, true
            elseif action == "next" then page, fresh = page + 1, true
            elseif action == "__tick" then
                feed, reached = loadFeed()
            else
                local index = tonumber((action or ""):match("^post:(%d+)$"))
                if index and feed[index] then
                    postScreen(feed[index])
                    feed, reached = loadFeed()
                end
            end
        end
    end

    -- Chat ------------------------------------------------------------------------------------

    -- One collection per pair, named from the two account ids: short, and
    -- the same from both sides.
    local function threadFor(friendId)
        local a, b = me.account_id, friendId
        if a > b then a, b = b, a end
        return "dm" .. util.checksum(a .. "|" .. b)
    end

    local function loadThread(friendId)
        local listed = ask("APP_DATA_LIST", { collection = threadFor(friendId), limit = 40 })
        local records, ordered = listed and listed.records or {}, {}
        for index = #records, 1, -1 do ordered[#ordered + 1] = records[index] end
        return ordered
    end

    -- Reading is what starts the one-day clock.
    local function markRead(friendId, messages)
        local unread = {}
        for _, message in ipairs(messages) do
            if not message.mine and not message.read then unread[#unread + 1] = message.id end
        end
        if #unread == 0 then return false end
        ask("APP_DATA_READ", { collection = threadFor(friendId), ids = unread })
        return true
    end

    local function conversation(friend)
        local offset, landed = nil, nil
        while running() do
            local width, height = target.getSize()
            local messages = loadThread(friend.account_id)
            if markRead(friend.account_id, messages) then messages = loadThread(friend.account_id) end
            local top, bottom = 4, height - 5
            local per = math.max(1, bottom - top + 1)
            offset = offset or math.max(0, #messages - per)
            offset = math.max(0, math.min(offset, math.max(0, #messages - per)))
            ui.clear(target)
            ui.header(target, ui.truncate(tostring(friend.name), width - 9),
                #messages == 0 and "No messages" or (#messages .. " kept"), util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local message = messages[offset + slot]
                if not message then break end
                local y = top + slot - 1
                local text = (message.mine and "> " or "< ") .. bodyOf(message)
                if landed and offset + slot == #messages then
                    slideIn(y, width, text)
                    landed = nil
                end
                ui.text(target, 2, y, ui.truncate(text, width - 3),
                    message.mine and CHAT or ui.theme.ink)
            end
            if #messages == 0 then
                ui.center(target, 8, "Nothing here", ui.theme.ink)
                ui.wrappedText(target, 2, 10, "Messages you have read disappear a day"
                    .. " later, on both Pockets.", width - 2, 4, ui.theme.muted)
            end
            local half = math.floor((width - 3) / 2)
            scene:button("send", 2, height - 4, half, 2, "Say",
                { background = CHAT, foreground = colors.black })
            scene:button("call", 3 + half, height - 4, width - 3 - half, 2, "Call",
                { background = ui.theme.danger })
            scene:button("back", 1, height, 10, 1, "< Chats", { background = ui.theme.panel })
            if #messages > per then
                scene:button("up", width - 7, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 3, height, 3, 1, "v",
                    { background = ui.theme.panel, disabled = offset + per >= #messages })
            end
            local action = scene:wait({ tickRate = 4 })
            if action == "back" or action == "__terminate" then return end
            if action == "send" then
                local body = ui.input(target, "To " .. tostring(friend.name), {
                    hint = "Gone a day after they read it", maxLength = MAX_MESSAGE,
                    allowSpace = true, minLength = 1, scrollToEnd = true,
                })
                if body and util.trim(body) ~= "" then
                    local sent, err = ask("APP_DATA_PUT", {
                        collection = threadFor(friend.account_id), data = { body = body },
                        -- Two people can ever read it, and it goes a day
                        -- after it has been read.
                        audience = { me.account_id, friend.account_id },
                        expire_after_days = KEEP_DAYS,
                    })
                    if sent then
                        offset, landed = nil, true
                        -- Their Pocket shows it only if they let Yap! notify them.
                        api.notifications.send({ account_id = friend.account_id,
                            title = tostring(me.name), body = ui.truncate(body, 60) })
                    else
                        ui.message(target, "error", "Not sent", err, 1.6)
                    end
                end
            elseif action == "call" then
                api.call({ account_id = friend.account_id, name = friend.name })
            elseif action == "up" then offset = offset - per
            elseif action == "down" then offset = offset + per
            end
        end
    end

    local function unreadFrom(friendId)
        local unread = 0
        for _, message in ipairs(loadThread(friendId)) do
            if not message.mine and not message.read then unread = unread + 1 end
        end
        return unread
    end

    local unlocked = false
    local function chatPage(tabs)
        if not unlocked then
            -- The whole tab is behind your PIN, once each time Yap! opens.
            if not api.pin("Unlock Yap! Chat") then return "tab:feed" end
            unlocked = true
            unlock()
            api.notifications.ask()
        end
        sweep(CHAT)
        local friends, page = me.friends or {}, 1
        while running() do
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 6) / 3))
            local pages = math.max(1, math.ceil(#friends / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, "Yap! Chat", plural(#friends, "friend", "friends"),
                util.formatClock())
            local scene = ui.scene(target)
            if #friends == 0 then
                ui.center(target, 8, "No friends yet", ui.theme.ink)
                ui.wrappedText(target, 2, 10, "Add friends in the Friends app and they"
                    .. " turn up here.", width - 2, 4, ui.theme.muted)
            end
            for slot = 1, per do
                local friend = friends[(page - 1) * per + slot]
                if not friend then break end
                local unread = unreadFrom(friend.account_id)
                scene:button("open:" .. friend.account_id, 2, 4 + (slot - 1) * 3, width - 2, 2,
                    tostring(friend.name) .. "\n"
                        .. (unread > 0 and (unread .. " new") or "Tap to open"),
                    { background = unread > 0 and CHAT or ui.theme.panel,
                      foreground = unread > 0 and colors.black or nil })
            end
            if pages > 1 then
                scene:button("prev", width - 8, height - 2, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 3, height - 2, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
            local action = scene:wait({ tickRate = 8 })
            if action == "home" or action == "__terminate"
                or (action or ""):match("^tab:") then
                return action
            end
            if action == "prev" then page = page - 1
            elseif action == "next" then page = page + 1
            else
                local id = action and action:match("^open:(.+)$")
                for _, friend in ipairs(friends) do
                    if friend.account_id == id then conversation(friend) end
                end
            end
        end
    end

    -- Yap Map ---------------------------------------------------------------------------------

    local function coords(spot)
        return spot.x .. " " .. spot.y .. " " .. spot.z
    end

    local function mapPage(tabs)
        sweep(MAP)
        local pinged, dropped, page = false, false, 1
        while running() do
            local map, err = ask("YAP_MAP")
            local width, height = target.getSize()
            local friends = map and map.friends or {}
            local inZone = 0
            for _, friend in ipairs(friends) do
                if friend.in_zone then inZone = inZone + 1 end
            end
            ui.clear(target)
            ui.header(target, "Yap Map", map and (inZone .. " in a zone") or "Offline",
                util.formatClock())
            if not pinged then
                ping()
                pinged = true
                ui.clear(target)
                ui.header(target, "Yap Map", map and (inZone .. " in a zone") or "Offline",
                    util.formatClock())
            end
            -- Where you are, first.
            local here = map and map.me
            ui.fill(target, 2, 4, width - 2, 2, here and MAP or ui.theme.panel)
            ui.text(target, 3, 4, map and map.hidden and "You (hidden)" or "You",
                here and colors.black or ui.theme.ink, here and MAP or ui.theme.panel)
            ui.text(target, 3, 5, ui.truncate(here and coords(here)
                or "Not in a zone", width - 4),
                here and colors.black or ui.theme.muted, here and MAP or ui.theme.panel)
            local scene = ui.scene(target)
            local per = math.max(1, math.floor((height - 10) / 2))
            local pages = math.max(1, math.ceil(#friends / per))
            page = math.max(1, math.min(page, pages))
            if not map then
                ui.wrappedText(target, 2, 8, tostring(err or "Cannot reach the Bank"),
                    width - 2, 3, ui.theme.muted)
            elseif #friends == 0 then
                ui.wrappedText(target, 2, 8, "None of your friends use Yap! yet, or"
                    .. " they chose Hide me.", width - 2, 4, ui.theme.muted)
            end
            for slot = 1, per do
                local friend = friends[(page - 1) * per + slot]
                if not friend then break end
                local y = 7 + (slot - 1) * 2
                ui.text(target, 2, y, friend.in_zone and "o" or ".",
                    friend.in_zone and MAP or ui.theme.muted)
                ui.text(target, 4, y, ui.truncate(tostring(friend.name), width - 5),
                    friend.in_zone and ui.theme.ink or ui.theme.muted)
                local where = friend.in_zone and coords(friend) or "Not in a zone"
                if friend.in_zone and here then
                    local dx, dz = friend.x - here.x, friend.z - here.z
                    where = where .. "  " .. math.floor(math.sqrt(dx * dx + dz * dz)) .. "m"
                end
                ui.text(target, 4, y + 1, ui.truncate(where, width - 5),
                    friend.in_zone and MAP or ui.theme.muted)
                -- The first time, friends drop in one by one.
                if not dropped then pause(0.04) end
            end
            dropped = true
            local hidden = map and map.hidden
            local buttonWidth = pages > 1 and width - 11 or width - 2
            scene:button("hide", 2, height - 2, buttonWidth, 1, hidden and "Show me" or "Hide me",
                { background = hidden and MAP or ui.theme.panel,
                  foreground = hidden and colors.black or nil, disabled = not map })
            if pages > 1 then
                scene:button("prev", width - 8, height - 2, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 3, height - 2, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
            local action = scene:wait({ tickRate = 10 })
            if action == "home" or action == "__terminate"
                or (action or ""):match("^tab:") then
                return action
            end
            if action == "prev" then page = page - 1
            elseif action == "next" then page = page + 1
            elseif action == "hide" and map then
                if hidden or ui.confirm(target, "Hide me", "Friends stop seeing your"
                    .. " coordinates on Yap Map.", "Hide", "Back") then
                    local changed, failed = ask("YAP_MAP_HIDE", { hidden = not hidden })
                    if changed then
                        ui.message(target, "success", changed.hidden and "Hidden"
                            or "On Yap Map again", nil, 1)
                    else
                        ui.message(target, "error", "Not changed", failed, 1.6)
                    end
                end
            end
        end
    end

    -- The app ------------------------------------------------------------------------------------

    local wanted = type(api.action) == "function" and api.action() or nil
    ui.runTabs({
        target = target,
        list = { { id = "feed", label = "Feed" }, { id = "chat", label = "Chat" },
            { id = "map", label = "Map" } },
        color = FEED,
        start = (wanted == "chat" or wanted == "map") and wanted or "feed",
        pages = { feed = feedPage, chat = chatPage, map = mapPage },
        running = running,
    })
end
