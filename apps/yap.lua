-- PUMPE APP: Yap
-- A text social network. Posts, likes and comments, everybody signed in with
-- their Foxy Account. Friends float to the top of the feed; everyone else
-- follows, newest first.
--
-- Signing in is one call. Every app gets the same one:
--
--     local me = api.login({ name = "Yap", scopes = { "friends" } })
--     if not me then return end
--
-- The phone shows what the app will see and waits for a tap. The app is
-- handed a profile with exactly those fields, never the session token.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local request, colors = api.request, api.colors

    local YAP = colors.cyan
    local FRIEND = colors.lime
    local MAX_POST = 140
    local MAX_COMMENT = 100

    local me = api.login({ name = "Yap", scopes = { "friends" } })
    if not me then return end

    local friends = {}
    for _, friend in ipairs(me.friends or {}) do
        friends[friend.account_id] = true
    end

    local function running()
        return api.running()
    end

    -- Animations --------------------------------------------------------------

    local function wordmark()
        local width, height = target.getSize()
        local middle = math.floor(height / 2)
        ui.clear(target)
        for step = 1, 3 do
            ui.center(target, middle, ("."):rep(step) .. " YAP "
                .. ("."):rep(step), YAP, ui.theme.background)
            sleep(0.09)
        end
        ui.center(target, middle + 2, "say something", ui.theme.muted,
            ui.theme.background)
        sleep(0.4)
    end

    -- A post lands by drawing itself top down.
    local function landPost(y, height, width)
        for row = 0, height - 1 do
            ui.fill(target, 2, y + row, width - 2, 1, ui.theme.panel)
            sleep(0.02)
        end
    end

    local function heartbeat(x, y)
        for _, mark in ipairs({ "<3", "<3", "  ", "<3" }) do
            ui.text(target, x, y, mark, colors.red, ui.theme.background)
            sleep(0.06)
        end
    end

    -- Data --------------------------------------------------------------------

    local function loadFeed()
        local listed = request("APP_DATA_LIST",
            { collection = "posts", limit = 40 }, true)
        local posts = listed and listed.records or {}
        -- Friends first, then everybody else, each group newest first. The
        -- Bank already hands them back newest first, so a stable split is
        -- all this needs.
        local mates, others = {}, {}
        for _, post in ipairs(posts) do
            if friends[post.author_id] or post.author_id == me.account_id then
                mates[#mates + 1] = post
            else
                others[#others + 1] = post
            end
        end
        local feed = {}
        for _, post in ipairs(mates) do feed[#feed + 1] = post end
        for _, post in ipairs(others) do feed[#feed + 1] = post end
        return feed
    end

    local function postBody(post)
        return tostring(post.data and post.data.body or "")
    end

    -- Composing ---------------------------------------------------------------

    local function compose()
        local body = ui.input(target, "New post", {
            hint = "Up to " .. MAX_POST .. " characters",
            maxLength = MAX_POST, allowSpace = true, minLength = 1,
            scrollToEnd = true,
        })
        if not body then return false end
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Yap", "Posting", util.formatClock())
        ui.wrappedText(target, 2, 5, body, width - 2, 6, ui.theme.ink)
        local barWidth = width - 6
        for step = 1, barWidth do
            ui.fill(target, 4, height - 5, barWidth, 1, ui.theme.panel)
            ui.fill(target, 4, height - 5, step, 1, YAP)
            sleep(0.01)
        end
        local posted, err = request("APP_DATA_PUT", {
            collection = "posts", data = { body = body },
        }, true)
        if not posted then
            ui.message(target, "error", "Not posted", err, 1.8)
            return false
        end
        ui.message(target, "success", "Posted", "Your yap is live", 1)
        return true
    end

    local function addComment(post)
        local body = ui.input(target, "Reply", {
            hint = "To " .. post.author_name,
            maxLength = MAX_COMMENT, allowSpace = true, minLength = 1,
            scrollToEnd = true,
        })
        if not body then return false end
        local added, err = request("APP_DATA_PUT", {
            collection = "comments", parent = post.id,
            data = { body = body },
        }, true)
        if not added then
            ui.message(target, "error", "Not sent", err, 1.6)
            return false
        end
        return true
    end

    -- One post, in full ---------------------------------------------------------

    local function postScreen(post)
        local offset = 0
        while running() do
            local width, height = target.getSize()
            local listed = request("APP_DATA_LIST",
                { collection = "comments", parent = post.id, limit = 40 }, true)
            local comments = listed and listed.records or {}
            ui.clear(target)
            ui.header(target, post.author_name,
                "Day " .. tostring(post.created_day) .. "  "
                    .. tostring(post.created_time), util.formatClock())
            local bodyLines = ui.wrappedText(target, 2, 5, postBody(post),
                width - 2, 4, ui.theme.ink)
            local row = 5 + bodyLines + 1
            local function plural(count, one, many)
                return count .. " " .. (count == 1 and one or many)
            end
            ui.text(target, 2, row,
                plural(post.reactions, "like", "likes") .. "   "
                    .. plural(#comments, "reply", "replies"), ui.theme.muted)
            row = row + 2

            local scene = ui.scene(target)
            local perView = math.max(1, math.floor((height - 4 - row) / 2))
            offset = math.max(0, math.min(offset,
                math.max(0, #comments - perView)))
            for slot = 1, perView do
                local comment = comments[offset + slot]
                if not comment then break end
                local y = row + (slot - 1) * 2
                ui.text(target, 2, y,
                    ui.truncate(comment.author_name, width - 3),
                    friends[comment.author_id] and FRIEND or ui.theme.accent)
                ui.text(target, 2, y + 1,
                    ui.truncate(tostring(comment.data.body or ""), width - 3),
                    ui.theme.muted)
            end
            if #comments == 0 then
                ui.text(target, 2, row, "No replies yet", ui.theme.muted)
            end
            local half = math.floor((width - 3) / 2)
            scene:button("like", 2, height - 2, half, 2,
                post.reacted and "Liked" or "Like",
                { background = post.reacted and colors.red or ui.theme.panel })
            scene:button("reply", 3 + half, height - 2, width - 3 - half, 2,
                "Reply", { background = YAP, foreground = colors.black })
            scene:button("back", 1, height, 8, 1, "< Feed",
                { background = ui.theme.panel })
            if #comments > perView then
                scene:button("up", width - 7, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 3, height, 3, 1, "v",
                    { background = ui.theme.panel,
                      disabled = offset + perView >= #comments })
            end
            if post.mine then
                scene:button("delete", math.floor(width / 2) - 3, height, 8, 1,
                    "Delete", { background = ui.theme.danger })
            end
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return true end
            if action == "like" then
                local toggled = request("APP_DATA_REACT", {
                    collection = "posts", id = post.id,
                    on = not post.reacted,
                }, true)
                if toggled then
                    if not post.reacted then heartbeat(2, height - 4) end
                    post = toggled.record
                end
            elseif action == "reply" then
                addComment(post)
            elseif action == "up" then offset = offset - 1
            elseif action == "down" then offset = offset + 1
            elseif action == "delete" then
                if ui.confirm(target, "Delete post",
                    "It goes for everybody.", "Delete", "Keep") then
                    request("APP_DATA_DELETE",
                        { collection = "posts", id = post.id }, true)
                    return true
                end
            end
        end
        return true
    end

    -- The feed ------------------------------------------------------------------

    local POST_HEIGHT = 4

    local function drawPost(post, y, width)
        local mate = friends[post.author_id]
        ui.text(target, 2, y, mate and "*" or " ",
            mate and FRIEND or ui.theme.muted)
        ui.text(target, 4, y, ui.truncate(post.author_name, width - 12),
            mate and FRIEND or ui.theme.ink)
        ui.text(target, width - 6, y,
            ui.truncate(tostring(post.created_time or ""), 5), ui.theme.muted)
        local lines = ui.wrap(postBody(post), width - 5)
        for index = 1, 2 do
            local line = lines[index]
            if line then
                -- Anything past the second line becomes a trailing ".." on
                -- it, rather than an ellipsis drawn over the top of it.
                if index == 2 and lines[3] then
                    line = ui.truncate(line .. " ..", width - 5)
                end
                ui.text(target, 4, y + index, line, ui.theme.ink)
            end
        end
        ui.text(target, 4, y + 3, post.reactions
            .. (post.reactions == 1 and " like" or " likes"),
            post.reacted and colors.red or ui.theme.muted)
    end

    wordmark()
    local feed, offset, landed = loadFeed(), 0, false
    while running() do
        local width, height = target.getSize()
        -- The scroll buttons own the right-hand edge, so the posts stop short
        -- of it rather than running underneath.
        local column = width - 5
        local top, bottom = 4, height - 3
        local perView = math.max(1, math.floor((bottom - top + 1) / POST_HEIGHT))
        offset = math.max(0, math.min(offset, math.max(0, #feed - perView)))

        ui.clear(target)
        ui.header(target, "Yap", #feed .. " posts", util.formatClock())
        local scene = ui.scene(target)
        for slot = 1, perView do
            local post = feed[offset + slot]
            if not post then break end
            local y = top + (slot - 1) * POST_HEIGHT
            if not landed then landPost(y, POST_HEIGHT - 1, column) end
            drawPost(post, y, column)
            scene:hotspot("post:" .. post.id, 2, y, column - 2,
                POST_HEIGHT - 1)
        end
        landed = true
        if #feed == 0 then
            ui.center(target, 9, "Nothing here yet", ui.theme.ink)
            ui.wrappedText(target, 2, 11,
                "Tap + to say the first thing.", column - 2, 3, ui.theme.muted)
        end

        -- Scrolling lives on the right, one tall button each way.
        local half = math.floor((bottom - top + 1) / 2)
        scene:button("up", width - 4, top, 4, half, "^",
            { background = ui.theme.panel, disabled = offset <= 0 })
        scene:button("down", width - 4, top + half, 4, bottom - top + 1 - half,
            "v", { background = ui.theme.panel,
                disabled = offset + perView >= #feed })
        scene:button("new", 2, height - 2, 5, 2, "+",
            { background = YAP, foreground = colors.black })
        scene:button("refresh", 8, height - 2, width - 9, 2, "Refresh",
            { background = ui.theme.panel })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        if #feed > 0 then
            ui.text(target, width - 8, height,
                (offset + 1) .. "-" .. math.min(#feed, offset + perView),
                ui.theme.muted)
        end

        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "up" then offset = offset - perView
        elseif action == "down" then offset = offset + perView
        elseif action == "refresh" then feed = loadFeed()
        elseif action == "new" then
            if compose() then
                feed, offset = loadFeed(), 0
            end
        else
            local id = action and action:match("^post:(.+)$")
            for _, post in ipairs(feed) do
                if post.id == id then
                    postScreen(post)
                    feed = loadFeed()
                    break
                end
            end
        end
    end
end
