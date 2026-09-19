-- PUMPE APP: Website Crafter
-- PUMPE APP ACTION: new | New website | Reserve a domain
-- PUMPE APP ACTION: sites | My websites | Edit what you have made
--
-- Writing a website on a pocket computer. Since 10.1 a website is a program
-- rather than a page of text, so this is a code editor -- one line at a
-- time, which is the only shape that fits twenty-six columns.
--
-- Nobody writes a site here from an empty screen, and they are not meant to.
-- Start from a template, change the words, publish. The Foxy one is the
-- worked example: signing in, drawing, and a button that does something.
--
-- Three places keep three different things, and that separation is the
-- point: the draft is on this phone, the name is at the Bank, and the
-- published program is on an Internet Server.

local TEMPLATES = {
    {
        id = "hello",
        name = "Hello",
        lines = {
            "-- A website is a program that returns a function.",
            "-- The phone calls it with an api table and nothing else.",
            "return function(api)",
            "    local ui, target = api.ui, api.target",
            "    local width, height = target.getSize()",
            "    ui.clear(target)",
            "    ui.header(target, api.domain, \"A website\", \"\")",
            "    ui.wrappedText(target, 2, 6, \"Hello from the web.\",",
            "        width - 2, 3, ui.theme.ink)",
            "    local scene = ui.scene(target)",
            "    scene:button(\"back\", 1, height, 8, 1, \"< Back\",",
            "        { background = ui.theme.panel })",
            "    scene:wait({ tickRate = 5 })",
            "end",
        },
    },
    {
        id = "foxy",
        name = "Foxy",
        lines = {
            "-- foxy.web -- the worked example for the new web.",
            "--",
            "-- A page is a program. It gets a screen, the ui library and",
            "-- Foxy Signin. It gets no filesystem, no network of its own",
            "-- and no way to ask the Bank what you have -- only who you",
            "-- are, and only once you say so.",
            "return function(api)",
            "    local ui, target = api.ui, api.target",
            "    local colors = api.colors",
            "    local FOX = colors.orange",
            "    local me = nil",
            "",
            "    while api.running() do",
            "        local width, height = target.getSize()",
            "        ui.clear(target)",
            "        ui.header(target, \"Foxy\", me and me.name or \"foxy.web\",",
            "            \"\")",
            "        ui.card(target, 2, 5, width - 2, 5, FOX)",
            "        ui.text(target, 4, 5, \"FOXY\", colors.black,",
            "            ui.theme.panel)",
            "        ui.wrappedText(target, 4, 7, me",
            "            and (\"Signed in as \" .. me.name)",
            "            or \"Small bank, big vault.\",",
            "            width - 6, 3, ui.theme.muted, ui.theme.panel)",
            "        ui.wrappedText(target, 2, 11, me",
            "            and \"It knows your name because you told it.\"",
            "            or \"A bank that fits in a pocket.\",",
            "            width - 2, 4, ui.theme.muted)",
            "        local scene = ui.scene(target)",
            "        scene:button(\"in\", 2, height - 5, width - 2, 2,",
            "            me and \"Thanks for visiting\" or \"Sign in with Foxy\",",
            "            { background = me and ui.theme.panel or FOX,",
            "              foreground = me and colors.white or colors.black })",
            "        scene:button(\"back\", 1, height, 8, 1, \"< Back\",",
            "            { background = ui.theme.panel })",
            "        local action = scene:wait({ tickRate = 5 })",
            "        if action == \"back\" or action == \"__terminate\" then",
            "            return",
            "        end",
            "        if action == \"in\" and not me then",
            "            me = api.login({ name = \"Foxy\" })",
            "        end",
            "    end",
            "end",
        },
    },
}

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local request, colors = api.request, api.colors

    local WC = colors.cyan
    local kept = type(api.load) == "function" and api.load() or {}
    kept.sites = type(kept.sites) == "table" and kept.sites or {}

    local function running() return api.running() end

    local function remember()
        if type(api.save) == "function" then api.save(kept) end
    end

    local function templateLines(id)
        for _, template in ipairs(TEMPLATES) do
            if template.id == id then
                local copy = {}
                for index, line in ipairs(template.lines) do
                    copy[index] = line
                end
                return copy
            end
        end
        return { "return function(api)", "end" }
    end

    local function draftFor(domain)
        for _, draft in ipairs(kept.sites) do
            if draft.domain == domain then
                draft.lines = type(draft.lines) == "table" and draft.lines
                    or templateLines("hello")
                return draft
            end
        end
        local draft = { domain = domain, lines = templateLines("hello") }
        kept.sites[#kept.sites + 1] = draft
        return draft
    end

    local function forgetDraft(domain)
        for index = #kept.sites, 1, -1 do
            if kept.sites[index].domain == domain then
                table.remove(kept.sites, index)
            end
        end
        remember()
    end

    local function sourceOf(draft)
        return table.concat(draft.lines, "\n")
    end

    -- Reserving ----------------------------------------------------------------
    -- The one moment this app earns its name. The letters of the domain land
    -- one at a time, then the card turns over and it is yours.

    local function youAreIn(domain)
        local width, height = target.getSize()
        local name = (api.account() or {}).name or "you"
        ui.clear(target)
        local middle = math.max(4, math.floor(height / 2) - 3)
        for count = 1, #domain do
            ui.center(target, middle, domain:sub(1, count) .. "_", WC,
                ui.theme.background)
            sleep(0.06)
        end
        ui.center(target, middle, domain, WC, ui.theme.background)
        sleep(0.25)
        for step = 1, 3 do
            ui.clear(target)
            ui.center(target, middle, domain, step % 2 == 1 and ui.theme.ink
                or WC, ui.theme.background)
            sleep(0.12)
        end
        ui.clear(target)
        ui.center(target, middle - 2,
            ui.truncate("You're in, " .. name, width - 2), ui.theme.ink,
            ui.theme.background)
        ui.card(target, 2, middle, width - 2, 5, WC)
        ui.text(target, 4, middle, "YOUR DOMAIN", ui.theme.muted,
            ui.theme.panel)
        ui.text(target, 4, middle + 2, ui.truncate(domain, width - 6),
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, middle + 3, "Live in two hours", ui.theme.muted,
            ui.theme.panel)
        sleep(2.2)
    end

    local function pickTemplate()
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Start from", "Change it after", util.formatClock())
        ui.wrappedText(target, 2, 5, "A website is a program. Start from one"
            .. " that works and change the words.", width - 2, 4,
            ui.theme.muted)
        local scene = ui.scene(target)
        for index, template in ipairs(TEMPLATES) do
            scene:button("pick:" .. index, 2, 9 + (index - 1) * 3,
                width - 2, 2, template.name,
                { background = index == 1 and ui.theme.panel or WC,
                  foreground = index == 1 and colors.white or colors.black })
        end
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 5 })
        local index = tonumber(action and action:match("^pick:(%d+)$"))
        if index and TEMPLATES[index] then
            return templateLines(TEMPLATES[index].id)
        end
        return nil
    end

    local function reserveScreen()
        local wanted = ui.input(target, "Your domain", {
            hint = "3-20 letters, numbers or -",
            maxLength = 20, minLength = 3,
        })
        if not wanted then return false end
        local made, err = request("WEB_RESERVE", { domain = wanted }, true)
        if not made then
            ui.message(target, "error", "Not reserved", err, 2.2)
            return false
        end
        local draft = draftFor(made.domain)
        local lines = pickTemplate()
        if lines then draft.lines = lines end
        remember()
        youAreIn(made.domain)
        return true
    end

    -- Writing ------------------------------------------------------------------
    -- One line at a time. A screen this size cannot show a cursor moving
    -- through a paragraph, so it does not pretend to: you pick a line and
    -- you replace it.

    local function editSource(draft)
        local offset = 0
        while running() do
            local width, height = target.getSize()
            local lines = draft.lines
            ui.clear(target)
            ui.header(target, ui.truncate(draft.domain, 12),
                #lines .. " lines", util.formatClock())
            local top = 5
            local rows = math.max(1, height - top - 6)
            offset = math.max(0, math.min(offset, #lines - rows))
            local scene = ui.scene(target)
            for slot = 1, rows do
                local index = offset + slot
                local line = lines[index]
                if not line then break end
                ui.text(target, 2, top + slot - 1,
                    ui.truncate(string.format("%2d ", index) .. line,
                        width - 6),
                    line:match("^%s*%-%-") and ui.theme.muted or ui.theme.ink)
                scene:hotspot("line:" .. index, 2, top + slot - 1,
                    width - 6, 1)
            end
            if #lines > rows then
                scene:button("up", width - 4, top, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 4, top + rows - 1, 3, 1, "v",
                    { background = ui.theme.panel,
                      disabled = offset + rows >= #lines })
            end
            local half = math.floor((width - 3) / 2)
            scene:button("add", 2, height - 4, half, 1, "+ Line",
                { background = ui.theme.panel })
            scene:button("check", 3 + half, height - 4, width - 3 - half, 1,
                "Check", { background = ui.theme.panel })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then
                remember()
                return
            end
            if action == "up" then offset = math.max(0, offset - rows)
            elseif action == "down" then offset = offset + rows
            elseif action == "add" then
                local typed = ui.input(target, "New line", {
                    hint = "Lua, one line", maxLength = 90, allowSpace = true })
                if typed then
                    draft.lines[#draft.lines + 1] = typed
                    remember()
                end
            elseif action == "check" then
                local checked = api.web("WEB_CHECK",
                    { source = sourceOf(draft) })
                if not checked then
                    ui.message(target, "error", "No Internet Server",
                        "Nothing can check it from here", 2.2)
                elseif checked.ok then
                    ui.message(target, "success", "It parses",
                        checked.bytes .. " bytes", 1.6)
                else
                    ui.message(target, "error", "Will not run",
                        ui.truncate(tostring(checked.error), 60), 3)
                end
            else
                local index = tonumber(action
                    and action:match("^line:(%d+)$"))
                if index and draft.lines[index] then
                    local typed = ui.input(target, "Line " .. index, {
                        initial = draft.lines[index], maxLength = 90,
                        allowSpace = true })
                    if typed == nil then
                        -- Cancelled. Offer the other thing somebody wants
                        -- from a line they tapped.
                        if ui.confirm(target, "Remove line " .. index .. "?",
                            ui.truncate(draft.lines[index], 60),
                            "Remove", "Keep") then
                            table.remove(draft.lines, index)
                            remember()
                        end
                    else
                        draft.lines[index] = typed
                        remember()
                    end
                end
            end
        end
    end

    -- Publishing ---------------------------------------------------------------
    -- Two servers, in order. The Internet Server takes the program, and only
    -- once it has it does the Bank record the edit -- so a publish that
    -- never landed does not cost the site its half hour of downtime.

    local function publish(draft, live)
        if type(api.web) ~= "function" then
            ui.message(target, "info", "Not on this PUMPE",
                "This phone is on an older release", 2)
            return false
        end
        local ticket, ticketError = request("WEB_TOKEN",
            { domain = draft.domain }, true)
        if not ticket then
            ui.message(target, "error", "Cannot publish", ticketError, 2.2)
            return false
        end
        local sent, sendError, code = api.web("WEB_PUBLISH", {
            domain = draft.domain, token = ticket.token,
            source = sourceOf(draft),
        })
        if not sent then
            ui.message(target, "error",
                code == "BAD_SOURCE" and "Will not run" or "Not published",
                sendError or "Nobody is hosting the web", 2.6)
            return false
        end
        request("WEB_EDITED", { domain = draft.domain }, true)
        ui.message(target, "success", "Published",
            live and "Back up in half an hour" or "Live when it opens", 2)
        return true
    end

    -- One website -------------------------------------------------------------

    local function siteScreen(site)
        local draft = draftFor(site.domain)
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, ui.truncate(site.domain, 12),
                site.live and "Live" or "Preparing", util.formatClock())
            ui.card(target, 2, 5, width - 2, 5,
                site.live and ui.theme.success or ui.theme.warning)
            ui.text(target, 4, 5, site.live and "ON THE WEB" or "GETTING READY",
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 6, ui.truncate(site.domain, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.wrappedText(target, 4, 8, site.live
                and "Anyone can open this in the Internet app."
                or ("Opens in about " .. math.max(1,
                    math.ceil(site.hours_left or 0)) .. " hour(s)."),
                width - 6, 2, ui.theme.muted, ui.theme.panel)
            ui.text(target, 2, 11, #draft.lines .. " lines of code",
                ui.theme.muted)
            local scene = ui.scene(target)
            scene:button("edit", 2, 13, width - 2, 2, "Edit the code",
                { background = ui.theme.panel })
            scene:button("publish", 2, height - 5, width - 2, 2, "Publish",
                { background = WC, foreground = colors.black })
            local half = math.floor((width - 3) / 2)
            scene:button("domain", 2, height - 2, half, 2, "Domain",
                { background = ui.theme.panel })
            scene:button("delete", 3 + half, height - 2, width - 3 - half, 2,
                "Delete", { background = ui.theme.danger })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "edit" then
                editSource(draft)
            elseif action == "publish" then
                publish(draft, site.live)
                return
            elseif action == "domain" then
                local typed = ui.input(target, "Change the domain", {
                    initial = site.domain, maxLength = 20, minLength = 3,
                })
                if typed and typed ~= site.domain then
                    local moved, err = request("WEB_RENAME",
                        { domain = site.domain, new_domain = typed }, true)
                    if moved then
                        draft.domain = moved.domain
                        remember()
                        ui.message(target, "success", "Renamed",
                            "Back up in half an hour", 2)
                        return
                    end
                    ui.message(target, "error", "Not renamed", err, 2.2)
                end
            elseif action == "delete" then
                if ui.confirm(target, "Delete " .. site.domain,
                    "The website and the name both go.", "Delete", "Keep")
                then
                    local gone, err = request("WEB_RELEASE",
                        { domain = site.domain }, true)
                    if gone then
                        if type(api.web) == "function" then
                            local ticket = request("WEB_TOKEN",
                                { domain = site.domain }, true)
                            if ticket then
                                api.web("WEB_UNPUBLISH", {
                                    domain = site.domain,
                                    token = ticket.token,
                                })
                            end
                        end
                        forgetDraft(site.domain)
                        ui.message(target, "info", "Gone",
                            site.domain .. " is free again", 1.8)
                        return
                    end
                    ui.message(target, "error", "Not deleted", err, 2.2)
                end
            end
        end
    end

    -- The app ------------------------------------------------------------------

    local wanted = type(api.action) == "function" and api.action() or nil
    if wanted == "new" then
        reserveScreen()
        return
    end

    while running() do
        local width, height = target.getSize()
        local mine = request("WEB_MINE", {}, true)
        ui.clear(target)
        ui.header(target, "Website Crafter",
            mine and (#mine.sites .. " of " .. mine.limit) or "Offline",
            util.formatClock())
        local scene = ui.scene(target)
        if not mine then
            ui.center(target, 8, "The Bank is not answering", ui.theme.ink)
            ui.wrappedText(target, 2, 10, "Your code is written here but your"
                .. " domain is reserved at the Bank.", width - 2, 4,
                ui.theme.muted)
        elseif #mine.sites == 0 then
            ui.card(target, 2, 5, width - 2, 5, WC)
            ui.text(target, 4, 5, "MAKE A WEBSITE", ui.theme.muted,
                ui.theme.panel)
            ui.wrappedText(target, 4, 7, "Pick a name, start from a template,"
                .. " and put it on the network.", width - 6, 3,
                ui.theme.muted, ui.theme.panel)
        else
            local row = 5
            for index, site in ipairs(mine.sites) do
                if row > height - 8 then break end
                scene:button("site:" .. index, 2, row, width - 2, 2,
                    ui.truncate(site.domain, width - 4) .. "\n"
                        .. (site.live and "Live" or "Preparing..."),
                    { background = site.live and ui.theme.panel
                        or ui.theme.warning,
                      foreground = site.live and colors.white or colors.black })
                row = row + 3
            end
        end
        scene:button("new", 2, height - 5, width - 2, 2, "New website",
            { background = WC, foreground = colors.black,
              disabled = not mine or #mine.sites >= mine.limit })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "new" then
            reserveScreen()
        else
            local index = tonumber(action and action:match("^site:(%d+)$"))
            local site = index and mine and mine.sites[index]
            if site then siteScreen(site) end
        end
    end
end
