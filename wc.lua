-- PUMPE APP: Website Crafter
-- Writing a website on a pocket computer. Titles and lines of text, a main
-- page and up to two more, and a name of your own on the network.
--
-- The draft lives on this phone. The name lives at the Bank, because a name
-- has to mean the same thing to everybody. The published pages live on an
-- Internet Server, because that is the machine strangers read them from.
-- Those three are separate on purpose: you can write with the Internet
-- Server switched off, and your name is still yours if somebody rebuilds it.

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

    local function draftFor(domain)
        for _, draft in ipairs(kept.sites) do
            if draft.domain == domain then return draft end
        end
        local draft = {
            domain = domain,
            pages = { { title = domain, blocks = {} } },
        }
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
        draftFor(made.domain)
        remember()
        youAreIn(made.domain)
        return true
    end

    -- Writing ------------------------------------------------------------------

    local function blockLabel(block)
        return (block.kind == "title" and "T  " or "-  ")
            .. tostring(block.text or "")
    end

    local function editBlocks(draft, pageIndex)
        local page = draft.pages[pageIndex]
        local offset = 0
        while running() do
            local width, height = target.getSize()
            local maxBlocks = tonumber(api.config
                and api.config.max_web_blocks) or 14
            ui.clear(target)
            ui.header(target, ui.truncate(page.title, 14),
                "Page " .. pageIndex .. " of " .. #draft.pages,
                util.formatClock())
            local top, rows = 5, math.max(1, height - 11)
            offset = math.max(0, math.min(offset, #page.blocks - rows))
            local scene = ui.scene(target)
            if #page.blocks == 0 then
                ui.wrappedText(target, 2, 6, "Nothing on this page yet. Add a"
                    .. " title or a line of text.", width - 2, 3,
                    ui.theme.muted)
            end
            for slot = 1, rows do
                local block = page.blocks[offset + slot]
                if not block then break end
                ui.text(target, 2, top + slot - 1,
                    ui.truncate(blockLabel(block), width - 6),
                    block.kind == "title" and ui.theme.ink or ui.theme.muted)
                scene:hotspot("block:" .. (offset + slot), 2, top + slot - 1,
                    width - 6, 1)
            end
            if #page.blocks > rows then
                scene:button("up", width - 4, top, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 4, top + rows - 1, 3, 1, "v",
                    { background = ui.theme.panel,
                      disabled = offset + rows >= #page.blocks })
            end
            local half = math.floor((width - 3) / 2)
            scene:button("title", 2, height - 5, half, 2, "+ Title",
                { background = WC, foreground = colors.black,
                  disabled = #page.blocks >= maxBlocks })
            scene:button("text", 3 + half, height - 5, width - 3 - half, 2,
                "+ Text", { background = ui.theme.panel,
                  disabled = #page.blocks >= maxBlocks })
            scene:button("rename", 2, height - 2, width - 2, 2,
                "Rename this page", { background = ui.theme.panel })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "up" then offset = math.max(0, offset - rows)
            elseif action == "down" then offset = offset + rows
            elseif action == "title" or action == "text" then
                local typed = ui.input(target,
                    action == "title" and "A title" or "A line of text", {
                        hint = action == "title" and "Short and bold"
                            or "Say something",
                        maxLength = action == "title" and 40 or 200,
                        allowSpace = true, minLength = 1,
                    })
                if typed then
                    page.blocks[#page.blocks + 1] =
                        { kind = action, text = typed }
                    remember()
                end
            elseif action == "rename" then
                local typed = ui.input(target, "Page title", {
                    initial = page.title, maxLength = 40, allowSpace = true,
                    minLength = 1,
                })
                if typed then page.title = typed remember() end
            else
                local index = tonumber(action
                    and action:match("^block:(%d+)$"))
                local block = index and page.blocks[index]
                if block then
                    if ui.confirm(target, "Remove this?",
                        ui.truncate(block.text, 60), "Remove", "Keep") then
                        table.remove(page.blocks, index)
                        remember()
                    end
                end
            end
        end
    end

    -- Publishing ---------------------------------------------------------------
    -- Two servers, in order. The Internet Server takes the pages, and only
    -- once it has them does the Bank record the edit -- so a publish that
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
        local sent, sendError = api.web("WEB_PUBLISH", {
            domain = draft.domain, token = ticket.token,
            pages = draft.pages,
        })
        if not sent then
            ui.message(target, "error", "No Internet Server",
                sendError or "Nobody is hosting the web", 2.4)
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
            ui.header(target, ui.truncate(site.domain, 14),
                site.live and "Live" or "Preparing", util.formatClock())
            ui.card(target, 2, 5, width - 2, 5,
                site.live and ui.theme.success or ui.theme.warning)
            ui.text(target, 4, 5, site.live and "ON THE WEB" or "GETTING READY",
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 6, ui.truncate(site.domain, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.wrappedText(target, 4, 8, site.live
                and ("Anyone can read this in the Internet app.")
                or ("Opens in about " .. math.max(1,
                    math.ceil(site.hours_left or 0)) .. " hour(s)."),
                width - 6, 2, ui.theme.muted, ui.theme.panel)
            local scene = ui.scene(target)
            local row = 11
            for index, page in ipairs(draft.pages) do
                if row > height - 8 then break end
                scene:button("page:" .. index, 2, row, width - 2, 1,
                    ui.truncate((index == 1 and "Main  " or "Page  ")
                        .. page.title, width - 4),
                    { background = ui.theme.panel })
                row = row + 1
            end
            local maxPages = tonumber(api.config
                and api.config.max_web_pages) or 3
            scene:button("addpage", 2, row, width - 2, 1, "+  Add a page",
                { background = ui.theme.panel,
                  disabled = #draft.pages >= maxPages })
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
            if action == "addpage" then
                local typed = ui.input(target, "New page", {
                    hint = "What is it called?", maxLength = 40,
                    allowSpace = true, minLength = 1,
                })
                if typed then
                    draft.pages[#draft.pages + 1] =
                        { title = typed, blocks = {} }
                    remember()
                end
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
                        forgetDraft(site.domain)
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
                        ui.message(target, "info", "Gone",
                            site.domain .. " is free again", 1.8)
                        return
                    end
                    ui.message(target, "error", "Not deleted", err, 2.2)
                end
            else
                local index = tonumber(action and action:match("^page:(%d+)$"))
                if index and draft.pages[index] then
                    editBlocks(draft, index)
                end
            end
        end
    end

    -- The app ------------------------------------------------------------------

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
            ui.wrappedText(target, 2, 10, "Your websites are written here but"
                .. " your domain is reserved at the Bank.", width - 2, 4,
                ui.theme.muted)
        elseif #mine.sites == 0 then
            ui.card(target, 2, 5, width - 2, 5, WC)
            ui.text(target, 4, 5, "MAKE A WEBSITE", ui.theme.muted,
                ui.theme.panel)
            ui.wrappedText(target, 4, 7, "Pick a name, write a page, and put"
                .. " it on the network.", width - 6, 3, ui.theme.muted,
                ui.theme.panel)
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
