-- PUMPE APP: Internet
-- PUMPE APP ACTION: go | Go to a domain | Type an address
-- Reading the web. Type a domain, or pick one off the list of what is out
-- there, and the pages arrive from whichever Internet Server the network is
-- running.
--
-- A domain that has been reserved but has not opened yet is not an error and
-- does not read like one. Somebody is building it; come back.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local colors = api.colors

    local NET = colors.lightBlue
    local history = {}

    local function running() return api.running() end

    local function ask(action, payload)
        if type(api.web) ~= "function" then
            return nil, "This PUMPE is on an older release"
        end
        return api.web(action, payload or {})
    end

    -- One page ------------------------------------------------------------------

    local function lines(site, width)
        local out = {}
        for _, block in ipairs(site.blocks or {}) do
            if block.kind == "title" then
                if #out > 0 then out[#out + 1] = { text = "" } end
                out[#out + 1] = { text = tostring(block.text), title = true }
            else
                for _, line in ipairs(ui.wrap(tostring(block.text), width)) do
                    out[#out + 1] = { text = line }
                end
            end
            out[#out + 1] = { text = "" }
        end
        if #out == 0 then out[1] = { text = "This page is empty." } end
        return out
    end

    local function readScreen(domain)
        local page, offset, site = 1, 0, nil
        while running() do
            local width, height = target.getSize()
            if not site or site.page ~= page then
                local found, err, code = ask("WEB_SITE",
                    { domain = domain, page = page })
                if not found then
                    ui.message(target, "error",
                        code == "NO_SUCH_DOMAIN" and "No such site"
                            or "Cannot reach it",
                        err or "No Internet Server is running", 2.4)
                    return
                end
                site, offset = found, 0
            end
            ui.clear(target)
            ui.header(target, ui.truncate(domain, 14),
                site.preparing and "Preparing"
                    or ui.truncate("by " .. tostring(site.owner_name), 11),
                util.formatClock())
            local scene = ui.scene(target)
            if site.preparing then
                -- Reserved, not yet open. Said as a person would say it.
                ui.card(target, 2, 6, width - 2, 6, ui.theme.warning)
                ui.wrappedText(target, 4, 7, "We're still preparing. Come"
                    .. " back soon.", width - 6, 3, ui.theme.ink,
                    ui.theme.panel)
                ui.text(target, 4, 10, ui.truncate(tostring(site.owner_name
                    or "Somebody") .. " is building it", width - 6),
                    ui.theme.muted, ui.theme.panel)
            else
                ui.text(target, 2, 5, ui.truncate(site.title, width - 3),
                    ui.theme.ink)
                local top = 7
                local rows = math.max(1, height - top - 4)
                local body = lines(site, width - 4)
                offset = math.max(0, math.min(offset, #body - rows))
                for slot = 1, rows do
                    local line = body[offset + slot]
                    if not line then break end
                    ui.text(target, 2, top + slot - 1,
                        ui.truncate(line.text, width - 5),
                        line.title and ui.theme.ink or ui.theme.muted)
                end
                if #body > rows then
                    scene:button("up", width - 3, top, 3, 1, "^",
                        { background = ui.theme.panel, disabled = offset <= 0 })
                    scene:button("down", width - 3, top + rows - 1, 3, 1, "v",
                        { background = ui.theme.panel,
                          disabled = offset + rows >= #body })
                end
                local names = site.pages or {}
                if #names > 1 then
                    local span = math.floor((width - 2) / #names)
                    for index, name in ipairs(names) do
                        scene:button("page:" .. index,
                            2 + (index - 1) * span, height - 2, span - 1, 1,
                            ui.truncate(name, span - 3),
                            { background = index == page and NET
                                or ui.theme.panel,
                              foreground = index == page and colors.black
                                or colors.white })
                    end
                end
            end
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "up" then offset = math.max(0, offset - 3)
            elseif action == "down" then offset = offset + 3
            else
                local wanted = tonumber(action and action:match("^page:(%d+)$"))
                if wanted and wanted ~= page then page, site = wanted, nil end
            end
        end
    end

    local function visit(domain)
        domain = string.lower(util.trim(tostring(domain or "")))
        if domain == "" then return end
        for index = #history, 1, -1 do
            if history[index] == domain then table.remove(history, index) end
        end
        table.insert(history, 1, domain)
        while #history > 5 do table.remove(history) end
        readScreen(domain)
    end

    -- The app ---------------------------------------------------------------------

    if type(api.action) == "function" and api.action() == "go" then
        local typed = ui.input(target, "Go to", {
            hint = "A domain, like foxnews", maxLength = 20,
        })
        if typed then visit(typed) end
        return
    end

    local offset = 0
    while running() do
        local width, height = target.getSize()
        local listed = ask("WEB_DIRECTORY", { offset = offset })
        ui.clear(target)
        ui.header(target, "Internet",
            listed and (listed.total .. " site"
                .. (listed.total == 1 and "" or "s")) or "Offline",
            util.formatClock())
        local scene = ui.scene(target)
        scene:button("go", 2, 5, width - 2, 2, "Type a domain",
            { background = NET, foreground = colors.black })
        if not listed then
            ui.center(target, 10, "No Internet Server", ui.theme.ink)
            ui.wrappedText(target, 2, 12, "Nobody is hosting the web. Set one"
                .. " up from Easy Deployment: SERVERS, then INTERNET SERVER.",
                width - 2, 5, ui.theme.muted)
        elseif #listed.sites == 0 then
            ui.center(target, 10, "Nothing published yet", ui.theme.ink)
            ui.wrappedText(target, 2, 12, "Websites are written in Website"
                .. " Crafter. Yours could be the first.", width - 2, 4,
                ui.theme.muted)
        else
            ui.text(target, 2, 8, "ON THE WEB", ui.theme.muted)
            local row = 9
            for index, site in ipairs(listed.sites) do
                if row > height - 4 then break end
                ui.text(target, 2, row, ui.truncate(site.domain, width - 4),
                    ui.theme.ink)
                ui.text(target, 2, row + 1,
                    ui.truncate(tostring(site.title), width - 4),
                    ui.theme.muted)
                scene:hotspot("site:" .. index, 2, row, width - 2, 2)
                row = row + 3
            end
        end
        if #history > 0 then
            scene:button("again", 2, height - 2, width - 2, 2,
                ui.truncate("Back to " .. history[1], width - 4),
                { background = ui.theme.panel })
        end
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        if listed and listed.total > #listed.sites then
            scene:button("more", width - 8, height, 8, 1, "MORE",
                { background = ui.theme.panel })
        end
        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "go" then
            local typed = ui.input(target, "Go to", {
                hint = "A domain, like foxnews", maxLength = 20,
            })
            if typed then visit(typed) end
        elseif action == "again" then
            visit(history[1])
        elseif action == "more" then
            offset = (listed and listed.next_offset or 0)
            if not listed or offset >= listed.total then offset = 0 end
        else
            local index = tonumber(action and action:match("^site:(%d+)$"))
            local site = index and listed and listed.sites[index]
            if site then visit(site.domain) end
        end
    end
end
