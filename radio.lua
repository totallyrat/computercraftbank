-- PUMPE APP: Radio
-- PUMPE APP ICON: f1ffff1f/1ff11ff1/1ff88ff1/f1f88f1f/ff8ff8ff/f8ffff8f
-- PUMPE APP ACTION: dial | Dial | Turn the dial, find a station
-- PUMPE APP ACTION: favorites | Favorites | State Radios, Featured, saved
--
-- Radio, by Foxy, FoxyOS 18.2: the radio, out of the Music app and on a dial
-- of its own.
--
--   Dial       87.5 to 108.0, a tenth at a time, a whole one, or anywhere
--              along the slider. Between stations is static; landing on one
--              shows it and the Music Player starts playing it. Radio
--              Broadcasters -- companies' stations -- are only found here.
--   Favorites  the State Radios, today's Featured station, and the Radio+
--              stations you saved. Only a station with Radio+ can be saved;
--              any other has to be found on the dial each time.
--
-- What you hear comes out of the Music Player you choose, as in the Music app.

return function(api)
    local ui, util, target, colors = api.ui, api.util, api.target, api.colors
    local music = api.music
    local LOW, HIGH = 875, 1080
    local COLORS = { red = colors.red, orange = colors.orange, yellow = colors.yellow,
        lime = colors.lime, green = colors.green, cyan = colors.cyan,
        lightBlue = colors.lightBlue, blue = colors.blue, purple = colors.purple,
        magenta = colors.magenta, pink = colors.pink, brown = colors.brown,
        white = colors.white, lightGray = colors.lightGray }
    local kept = type(api.load) == "function" and api.load() or {}
    local state = { frequency = tonumber(kept.frequency) or 984, saved = kept.saved or {},
        player_id = kept.player_id, players = nil, tuned = nil, scroll = 0 }

    local function running() return api.running() end
    local function ask(action, payload) return music.ask(action, payload or {}) end
    local function said(kind, title, body, seconds)
        ui.message(target, kind, title, body or "", seconds or 1.4)
    end
    local function colorOf(name) return COLORS[tostring(name or "")] or colors.orange end
    local function label(frequency)
        return string.format("%d.%d", math.floor(frequency / 10), frequency % 10)
    end
    local function keep()
        if type(api.save) == "function" then
            pcall(api.save, { frequency = state.frequency, saved = state.saved,
                player_id = state.player_id })
        end
    end

    -- Big digits, three by five.
    local DIGITS = {
        ["0"] = { "###", "# #", "# #", "# #", "###" }, ["1"] = { " # ", "## ", " # ", " # ", "###" },
        ["2"] = { "###", "  #", "###", "#  ", "###" }, ["3"] = { "###", "  #", " ##", "  #", "###" },
        ["4"] = { "# #", "# #", "###", "  #", "  #" }, ["5"] = { "###", "#  ", "###", "  #", "###" },
        ["6"] = { "###", "#  ", "###", "# #", "###" }, ["7"] = { "###", "  #", " # ", " # ", " # " },
        ["8"] = { "###", "# #", "###", "# #", "###" }, ["9"] = { "###", "# #", "###", "  #", "###" },
        ["."] = { " ", " ", " ", " ", "#" },
    }
    local function bigWidth(text)
        local total = 0
        for index = 1, #text do total = total + #DIGITS[text:sub(index, index)][1] + 1 end
        return total - 1
    end
    local function big(y, text, color)
        local width = target.getSize()
        local x = math.floor((width - bigWidth(text)) / 2) + 1
        for index = 1, #text do
            local glyph = DIGITS[text:sub(index, index)]
            for row, line in ipairs(glyph) do
                for column = 1, #line do
                    if line:sub(column, column) == "#" then
                        ui.fill(target, x + column - 1, y + row - 1, 1, 1, color)
                    end
                end
            end
            x = x + #glyph[1] + 1
        end
    end

    -- Music Players ----------------------------------------------------------------------------

    local function refreshPlayers()
        local listed = ask("MUSIC_PLAYERS")
        if not listed then return nil end
        state.players = listed.players
        local chosen
        for _, player in ipairs(state.players) do
            if player.player_id == state.player_id then chosen = player end
        end
        if not chosen then
            for _, player in ipairs(state.players) do
                if not chosen or (player.online and not chosen.online) then chosen = player end
            end
        end
        state.player_id = chosen and chosen.player_id or nil
        return chosen
    end

    local function current()
        for _, player in ipairs(state.players or {}) do
            if player.player_id == state.player_id then return player end
        end
        return nil
    end

    local function choosePlayer()
        refreshPlayers()
        local items = {}
        for _, player in ipairs(state.players or {}) do
            items[#items + 1] = player
        end
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Plays on", #items .. " Music Players", util.formatClock())
            local scene = ui.scene(target)
            for index, player in ipairs(items) do
                local y = 1 + index * 3
                if y + 1 > height - 2 then break end
                local on = player.player_id == state.player_id
                scene:button("player:" .. player.player_id, 2, y, width - 2, 2,
                    ui.truncate(player.label, width - 4) .. "\n"
                        .. (player.online and "On" or "Off"),
                    { background = on and colors.orange or ui.theme.panel,
                      foreground = on and colors.black or nil })
            end
            if #items == 0 then
                ui.wrappedText(target, 2, 5, "No Music Player yet. Put a speaker beside a"
                    .. " computer, run Easy Deployment, choose Music Player and sign in.",
                    width - 2, 6, ui.theme.muted)
            end
            scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return end
            local id = action and action:match("^player:(.+)$")
            if id then
                state.player_id = id
                keep()
                return
            end
        end
    end

    local function control(command, extra)
        if not current() then refreshPlayers() end
        if not state.player_id then return nil, "No Music Player" end
        local payload = extra or {}
        payload.command, payload.player_id = command, state.player_id
        return ask("MUSIC_CONTROL", payload)
    end

    -- Tuning: what is there, and the Music Player following.
    local function tune(frequency, quiet)
        state.frequency = math.max(LOW, math.min(HIGH, frequency))
        keep()
        local tuned = ask("MUSIC_TUNE", { frequency = state.frequency })
        state.tuned = tuned and tuned.station or nil
        local played, err = control("tune", { frequency = state.frequency })
        if not played and not quiet and err then said("warning", "Not playing", err, 1.2) end
        return tuned
    end

    local function isSaved(stationId)
        for index, id in ipairs(state.saved) do
            if id == stationId then return index end
        end
        return nil
    end

    local function callIn(number)
        local price = api.config and api.config.phone_call_price or 50
        if not ui.confirm(target, "Call " .. number, "A call is " .. util.money(price,
            api.config and api.config.currency or "$") .. ". Every call is one more entry.",
            "CALL", "BACK") then return end
        local placed, err = api.request("PHONE_CALL", { number = number }, true)
        if placed then said("success", "You're in", "Good luck") else said("error", "No", err) end
    end

    -- The dial ---------------------------------------------------------------------------------------

    local function dialPage(tabs)
        if not state.players then refreshPlayers() end
        local polled = 0
        while running() do
            if util.nowMs() - polled > 2500 then
                local tuned = ask("MUSIC_TUNE", { frequency = state.frequency })
                state.tuned = tuned and tuned.station or nil
                state.reachable = tuned ~= nil
                polled = util.nowMs()
            end
            local width = target.getSize()
            local bottom = ui.contentBottom(target)
            ui.clear(target)
            local player = current()
            ui.header(target, "Radio", "87.5 to 108.0", util.formatClock())
            local scene = ui.scene(target)
            local found = state.tuned
            local tint = found and colorOf(found.color) or ui.theme.muted
            big(4, label(state.frequency), tint)
            local y = 10
            if not state.reachable then
                ui.center(target, y, "The Music Server is not running", ui.theme.warning)
            elseif found then
                ui.fill(target, 2, y, width - 2, 2, tint)
                ui.text(target, 3, y, ui.truncate(found.name .. (found.plus and "  RADIO+" or ""),
                    width - 4), ui.inkOn(tint), tint)
                ui.text(target, 3, y + 1, ui.truncate(not found.on_air and "Off the air"
                    or found.giveaway and ("GIVEAWAY! " .. found.giveaway.number)
                    or found.now and (found.now.title .. (found.now.artist and (" - "
                        .. found.now.artist) or "")) or "Static", width - 4), ui.inkOn(tint), tint)
            else
                ui.center(target, y, "~ static ~", ui.theme.muted)
            end
            -- The slider: tap anywhere along it.
            local barW = width - 2
            local at = math.floor((state.frequency - LOW) / (HIGH - LOW) * (barW - 1) + 0.5)
            for column = 0, barW - 1 do
                local frequency = LOW + math.floor(column * (HIGH - LOW) / (barW - 1) + 0.5)
                scene:button("dial:" .. frequency, 2 + column, 13, 1, 1, column == at and "|"
                    or (column % 5 == 0 and ":" or "."), { background = column == at and tint
                    or ui.theme.panel, foreground = column == at and ui.inkOn(tint) or ui.theme.muted,
                    flash = false })
            end
            local quarter = math.floor((width - 5) / 4)
            local steps = { { "down10", "<<" }, { "down", "<" }, { "up", ">" }, { "up10", ">>" } }
            for index, step in ipairs(steps) do
                scene:button(step[1], 2 + (index - 1) * (quarter + 1), 15, index == 4
                    and (width - 1 - 3 * (quarter + 1)) or quarter, 1, step[2],
                    { background = ui.theme.panel, flash = false })
            end
            if found and found.plus then
                local saved = isSaved(found.station_id)
                scene:button("save", 2, math.min(17, bottom - 1), math.floor(width / 2) - 1, 1,
                    saved and "SAVED" or "SAVE", { background = saved and tint or ui.theme.panel,
                    foreground = saved and ui.inkOn(tint) or nil })
            end
            if found and found.giveaway then
                scene:button("call", math.floor(width / 2) + 1, math.min(17, bottom - 1),
                    width - math.floor(width / 2) - 1, 1, "CALL IN",
                    { background = colors.yellow, foreground = colors.black })
            end
            scene:button("player", 2, 9, width - 2, 1, ui.truncate("Plays on "
                .. (player and player.label or "a Music Player") .. "  >", width - 4),
                { background = ui.theme.background, foreground = ui.theme.muted })
            ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
            local action = scene:wait({ tickRate = 1 })
            if action == "home" or action == "__terminate" or (action or ""):match("^tab:") then
                return action
            end
            local moves = { down10 = -10, down = -1, up = 1, up10 = 10 }
            local dialed = tonumber(action and action:match("^dial:(%d+)$"))
            if moves[action] or dialed then
                local frequency = dialed or state.frequency + moves[action]
                if frequency < LOW then frequency = HIGH end
                if frequency > HIGH then frequency = LOW end
                tune(frequency)
                polled = util.nowMs()
            elseif action == "save" and found then
                local index = isSaved(found.station_id)
                if index then table.remove(state.saved, index)
                elseif #state.saved < 20 then state.saved[#state.saved + 1] = found.station_id end
                keep()
            elseif action == "call" and found and found.giveaway then
                callIn(found.giveaway.number)
            elseif action == "player" then
                choosePlayer()
            end
        end
    end

    -- Favorites --------------------------------------------------------------------------------------
    -- One list, scrolled: the State Radios, Featured, and the stations you saved.

    local function favoritesPage(tabs)
        if not state.players then refreshPlayers() end
        while running() do
            local listed, err = ask("MUSIC_FAVORITES", { saved = state.saved })
            local width = target.getSize()
            local bottom = ui.contentBottom(target)
            ui.clear(target)
            ui.header(target, "Favorites", "State, Featured, saved", util.formatClock())
            local scene = ui.scene(target)
            local rows = {}
            local function heading(text) rows[#rows + 1] = { heading = text } end
            if listed then
                heading("STATE RADIOS")
                for _, radio in ipairs(listed.radios) do
                    rows[#rows + 1] = { id = "radio:" .. radio.radio_id, radio = radio,
                        line = radio.giveaway and ("GIVEAWAY! " .. radio.giveaway.number)
                            or radio.now and radio.now.title or "Off air" }
                end
                if listed.featured then
                    heading("FEATURED TODAY")
                    rows[#rows + 1] = { id = "station:" .. listed.featured.station_id,
                        radio = listed.featured, line = listed.featured.label .. "  "
                            .. (listed.featured.now and listed.featured.now.title or "Static") }
                end
                heading("SAVED")
                for _, saved in ipairs(listed.saved) do
                    rows[#rows + 1] = { id = "station:" .. saved.station_id, radio = saved,
                        line = saved.label .. "  " .. (saved.now and saved.now.title or "Static"),
                        removable = true }
                end
                if #listed.saved == 0 then
                    rows[#rows + 1] = { note = "Find a Radio+ station on the dial and SAVE it." }
                end
            end
            -- Two rows a station, one a heading; as many as fit, from the scroll.
            local y, shown = 4, 0
            state.scroll = math.max(0, math.min(state.scroll, #rows - 1))
            for index = state.scroll + 1, #rows do
                local row = rows[index]
                local tall = row.radio and 2 or 1
                if y + tall - 1 > bottom - 1 then break end
                if row.heading then
                    ui.text(target, 2, y, row.heading, ui.theme.muted)
                elseif row.note then
                    ui.text(target, 2, y, ui.truncate(row.note, width - 2), ui.theme.muted)
                else
                    local band = colorOf(row.radio.color)
                    scene:button(row.id, 2, y, width - (row.removable and 5 or 2), 2, "",
                        { background = band })
                    ui.text(target, 3, y, ui.truncate(row.radio.name, width - 7), ui.inkOn(band), band)
                    ui.text(target, 3, y + 1, ui.truncate(row.line, width - 7), ui.inkOn(band), band)
                    if row.removable then
                        scene:button("forget:" .. row.radio.station_id, width - 2, y, 3, 2, "x",
                            { background = ui.theme.danger })
                    end
                end
                y, shown = y + tall, shown + 1
            end
            if not listed then
                ui.wrappedText(target, 2, 6, tostring(err or "The Music Server is not running"),
                    width - 2, 3, ui.theme.warning)
            end
            if state.scroll > 0 then
                scene:button("scrollup", width - 3, 2, 3, 1, "^", { background = ui.theme.panel })
            end
            if state.scroll + shown < #rows then
                scene:button("scrolldown", width - 3, bottom - 1, 3, 1, "v",
                    { background = ui.theme.panel })
            end
            ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
            local action = scene:wait({ tickRate = 3 })
            if action == "home" or action == "__terminate" or (action or ""):match("^tab:") then
                return action
            end
            if action == "scrollup" then state.scroll = math.max(0, state.scroll - 3)
            elseif action == "scrolldown" then state.scroll = state.scroll + 3 end
            local radioId = action and action:match("^radio:(.+)$")
            local stationId = action and action:match("^station:(.+)$")
            local forget = action and action:match("^forget:(.+)$")
            if forget and isSaved(forget) then
                table.remove(state.saved, isSaved(forget))
                keep()
            elseif radioId or stationId then
                local played, playError = control(radioId and "radio" or "station",
                    radioId and { radio_id = radioId } or { station_id = stationId })
                if played then
                    if played.player.frequency then state.frequency = played.player.frequency end
                    keep()
                    said("success", "Playing", played.player.radio and played.player.radio.name
                        or nil, 0.8)
                else
                    said("error", "Not playing", playError or "Choose a Music Player first", 1.6)
                end
            end
        end
    end

    local wanted = type(api.action) == "function" and api.action() or nil
    ui.runTabs({
        target = target,
        list = { { id = "dial", label = "Dial" }, { id = "favorites", label = "Favorites",
            short = "Favs" } },
        color = colors.orange,
        start = wanted == "favorites" and "favorites" or "dial",
        pages = { dial = dialPage, favorites = favoritesPage },
        running = running,
    })
end
