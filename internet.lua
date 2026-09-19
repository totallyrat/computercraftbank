-- PUMPE APP: Internet
-- PUMPE APP ACTION: go | Go to a domain | Type an address
--
-- Reading the web. Type a domain and the phone fetches it, runs it and
-- throws it away again.
--
-- This app does almost nothing on purpose. It is an address bar and a short
-- history; everything that matters happens in api.browse, on the phone,
-- because running code somebody else wrote is not a thing an app should be
-- able to do on its own.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local colors = api.colors

    local NET = colors.lightBlue
    local history = {}

    local function running() return api.running() end

    local function visit(domain)
        domain = string.lower(util.trim(tostring(domain or "")))
        if domain == "" then return end
        if type(api.browse) ~= "function" then
            ui.message(target, "info", "Not on this PUMPE",
                "This phone is on an older release", 2)
            return
        end
        for index = #history, 1, -1 do
            if history[index] == domain then table.remove(history, index) end
        end
        table.insert(history, 1, domain)
        while #history > 4 do table.remove(history) end
        api.browse(domain)
    end

    local function ask(initial)
        return ui.input(target, "Go to", {
            hint = "A domain, like foxden", initial = initial,
            maxLength = 20,
        })
    end

    -- Opened by name from search: straight to the address bar.
    if type(api.action) == "function" and api.action() == "go" then
        local typed = ask()
        if typed then visit(typed) end
        return
    end

    while running() do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Internet", "Type a domain", util.formatClock())
        local scene = ui.scene(target)
        scene:button("go", 2, 5, width - 2, 3, "Go to a domain",
            { background = NET, foreground = colors.black, shadow = true })
        if #history == 0 then
            -- No list of every site on the server. It was a phone book
            -- nobody asked for, and a front page belonging to whoever
            -- happened to publish first.
            ui.wrappedText(target, 2, 10, "Websites are made in Website"
                .. " Crafter. Ask somebody for theirs, or make one.",
                width - 2, 5, ui.theme.muted)
        else
            ui.text(target, 2, 10, "RECENTLY", ui.theme.muted)
            for index, domain in ipairs(history) do
                local y = 11 + index
                if y <= height - 2 then
                    scene:button("again:" .. index, 2, y, width - 2, 1,
                        ui.truncate(domain, width - 4),
                        { background = ui.theme.panel })
                end
            end
        end
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "go" then
            local typed = ask()
            if typed then visit(typed) end
        else
            local index = tonumber(action and action:match("^again:(%d+)$"))
            if index and history[index] then visit(history[index]) end
        end
    end
end
