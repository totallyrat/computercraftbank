-- PUMPE APP: Yap Chat
-- Private messages between Foxy friends. Two things make it different from
-- the PUMPE's own Messages:
--
--   * the whole app is behind your PIN, so a phone left on a desk is not an
--     open inbox
--   * a message you have read is gone a day later, on both phones
--
-- It is also the app that uses all three of the new APIs:
--
--   api.notifications.ask()   -- asked before anything else
--   api.pin(reason)           -- the lock on the front door
--   api.call{ account_id }    -- the same fullscreen ring Urgent Contact uses
--
-- Messages live in the shared app store with an audience of exactly two, so
-- the Bank will not hand one to anybody else even if they ask for it by id.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local request, colors = api.request, api.colors

    local CHAT = colors.magenta
    local MAX_MESSAGE = 120
    local KEEP_DAYS = 1

    -- Notifications first, before the app asks for anything about you.
    api.notifications.ask()

    local me = api.login({ name = "Yap Chat", scopes = { "friends" } })
    if not me then return end

    if not api.pin("Unlock Yap Chat") then return end

    local friends = me.friends or {}

    local function running()
        return api.running()
    end

    -- One collection per pair, named by a checksum of the two account ids so
    -- it is short, stable and identical from both sides.
    local function threadFor(friendId)
        local a, b = me.account_id, friendId
        if a > b then a, b = b, a end
        return "dm" .. util.checksum(a .. "|" .. b)
    end

    -- Animations ---------------------------------------------------------------

    local function wordmark()
        local width, height = target.getSize()
        local middle = math.floor(height / 2)
        ui.clear(target)
        for step = 1, 3 do
            ui.center(target, middle, ("("):rep(step) .. " YAP CHAT "
                .. (")"):rep(step), CHAT, ui.theme.background)
            sleep(0.08)
        end
        ui.center(target, middle + 2, "locked and fleeting", ui.theme.muted,
            ui.theme.background)
        sleep(0.4)
    end

    -- A sent message slides in from the right edge to where it lands.
    local function slideIn(y, width, text)
        for step = 3, 0, -1 do
            ui.fill(target, 2, y, width - 2, 1, ui.theme.background)
            ui.text(target, 2 + step, y,
                ui.truncate(text, width - 3 - step), CHAT)
            sleep(0.03)
        end
    end

    -- Data ---------------------------------------------------------------------

    local function loadThread(friendId)
        local listed = request("APP_DATA_LIST",
            { collection = threadFor(friendId), limit = 40 }, true)
        local records = listed and listed.records or {}
        -- The Bank hands them back newest first; a conversation reads better
        -- oldest first.
        local ordered = {}
        for index = #records, 1, -1 do
            ordered[#ordered + 1] = records[index]
        end
        return ordered
    end

    -- Reading is what starts the one-day clock, so this is also the thing
    -- that makes messages disappear.
    local function markRead(friendId, messages)
        local unread = {}
        for _, message in ipairs(messages) do
            if not message.mine and not message.read then
                unread[#unread + 1] = message.id
            end
        end
        if #unread == 0 then return false end
        request("APP_DATA_READ",
            { collection = threadFor(friendId), ids = unread }, true)
        return true
    end

    local function messageBody(message)
        return tostring(message.data and message.data.body or "")
    end

    local function sendMessage(friend)
        local body = ui.input(target, "To " .. friend.name, {
            hint = "Gone a day after they read it",
            maxLength = MAX_MESSAGE, allowSpace = true, minLength = 1,
            scrollToEnd = true,
        })
        if not body then return false end
        local sent, err = request("APP_DATA_PUT", {
            collection = threadFor(friend.account_id),
            data = { body = body },
            -- Exactly two people can ever read it, and it goes a day after
            -- it has been read.
            audience = { me.account_id, friend.account_id },
            expire_after_days = KEEP_DAYS,
        }, true)
        if not sent then
            ui.message(target, "error", "Not sent", err, 1.8)
            return false
        end
        -- Their phone only hears about it if they allowed this app to
        -- interrupt them. A refusal is not an error.
        api.notifications.send({
            account_id = friend.account_id,
            title = me.name,
            body = ui.truncate(body, 60),
        })
        return true
    end

    -- One conversation ----------------------------------------------------------

    local function conversation(friend)
        local offset, landed = nil, nil
        while running() do
            local width, height = target.getSize()
            local messages = loadThread(friend.account_id)
            if markRead(friend.account_id, messages) then
                messages = loadThread(friend.account_id)
            end
            local top, bottom = 4, height - 5
            local perView = math.max(1, bottom - top + 1)
            -- New conversations open at the newest message rather than the
            -- oldest, which is where a chat should start.
            offset = offset or math.max(0, #messages - perView)
            offset = math.max(0, math.min(offset,
                math.max(0, #messages - perView)))

            ui.clear(target)
            ui.header(target, friend.name,
                #messages == 0 and "No messages" or (#messages .. " kept"),
                util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, perView do
                local message = messages[offset + slot]
                if not message then break end
                local y = top + slot - 1
                local text = (message.mine and "> " or "< ")
                    .. messageBody(message)
                if landed and offset + slot == #messages then
                    slideIn(y, width, text)
                    landed = nil
                end
                ui.text(target, 2, y, ui.truncate(text, width - 3),
                    message.mine and CHAT or ui.theme.ink)
            end
            if #messages == 0 then
                ui.center(target, 8, "Nothing here", ui.theme.ink)
                ui.wrappedText(target, 2, 10,
                    "Messages you have read disappear a day later, on both"
                        .. " phones.", width - 2, 4, ui.theme.muted)
            end

            local half = math.floor((width - 3) / 2)
            scene:button("send", 2, height - 4, half, 2, "Say",
                { background = CHAT, foreground = colors.black })
            scene:button("call", 3 + half, height - 4, width - 3 - half, 2,
                "Call", { background = ui.theme.danger })
            scene:button("back", 1, height, 10, 1, "< Chats",
                { background = ui.theme.panel })
            if #messages > perView then
                scene:button("up", width - 7, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 3, height, 3, 1, "v",
                    { background = ui.theme.panel,
                      disabled = offset + perView >= #messages })
            end

            local action = scene:wait({ tickRate = 4 })
            if action == "back" or action == "__terminate" then return end
            if action == "send" then
                if sendMessage(friend) then
                    offset, landed = nil, true
                end
            elseif action == "call" then
                -- The Urgent Contact API: the same fullscreen alert the
                -- PUMPE raises, labelled Yap Chat on their screen.
                api.call({ account_id = friend.account_id,
                    name = friend.name })
            elseif action == "up" then offset = offset - perView
            elseif action == "down" then offset = offset + perView
            end
        end
    end

    -- The chat list -------------------------------------------------------------

    local function unreadFor(friendId)
        local listed = request("APP_DATA_LIST",
            { collection = threadFor(friendId), limit = 40 }, true)
        local unread = 0
        for _, message in ipairs(listed and listed.records or {}) do
            if not message.mine and not message.read then
                unread = unread + 1
            end
        end
        return unread
    end

    wordmark()
    local page = 1
    while running() do
        local width, height = target.getSize()
        local perPage = 4
        local pages = math.max(1, math.ceil(#friends / perPage))
        page = math.max(1, math.min(page, pages))

        ui.clear(target)
        ui.header(target, "Yap Chat", #friends .. " friends",
            util.formatClock())
        local scene = ui.scene(target)
        if #friends == 0 then
            ui.center(target, 9, "No friends yet", ui.theme.ink)
            ui.wrappedText(target, 2, 11,
                "Add a friend in the PUMPE and they turn up here.",
                width - 2, 4, ui.theme.muted)
        end
        for slot = 1, perPage do
            local friend = friends[(page - 1) * perPage + slot]
            if not friend then break end
            local unread = unreadFor(friend.account_id)
            scene:button("open:" .. friend.account_id, 2, 4 + (slot - 1) * 3,
                width - 2, 2, friend.name .. "\n"
                    .. (unread > 0 and (unread .. " new") or "Tap to open"),
                { background = unread > 0 and CHAT or ui.theme.panel,
                  foreground = unread > 0 and colors.black or nil })
        end
        if pages > 1 then
            scene:button("prev", 2, height - 2, 8, 2, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            ui.center(target, height - 1, page .. "/" .. pages, ui.theme.muted)
            scene:button("next", width - 7, height - 2, 8, 2, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })

        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
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
