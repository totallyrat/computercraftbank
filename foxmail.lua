-- PUMPE APP: FoxMail
-- PUMPE APP ACTION: inbox | Inbox | Your mail
-- PUMPE APP ACTION: write | Write an email | To anybody with an address
--
-- Email, new in 11.0, and on every PUMPE.
--
-- Everybody can have one address at foxy.com. A company can have a domain
-- of its own -- revolution.com -- and up to five addresses on it, which its
-- owner reads here beside their own: switching is one tap on the Me tab.
-- The same company mail is on its Service Kiosks, and apps its owner
-- publishes can send from it too.
--
-- The mail itself is kept in the Bank Vault. This app remembers only which
-- address you were last looking at.

return function(api)
    local ui, util, target, colors = api.ui, api.util, api.target, api.colors

    local FOX = colors.orange
    local TABS = { { id = "inbox", label = "Inbox" },
        { id = "sent", label = "Sent" }, { id = "write", label = "Write" },
        { id = "me", label = "Me" } }

    local saved = type(api.load) == "function" and api.load() or {}
    local me, current

    local function running() return api.running() end
    local function ask(action, payload)
        return api.request(action, payload or {}, true)
    end
    local function keep()
        if type(api.save) == "function" then api.save(saved) end
    end

    -- What this person can read and send as, and which one is showing.
    local function refresh()
        local got, err = ask("MAIL_ME")
        if not got then return nil, err end
        me = got
        local still = false
        for _, entry in ipairs(me.addresses or {}) do
            if entry.address == current then still = true end
        end
        if not still then
            current = nil
            for _, entry in ipairs(me.addresses or {}) do
                if entry.address == saved.current then current = entry.address end
            end
            current = current or (me.addresses[1] and me.addresses[1].address)
        end
        return me
    end

    local function unreadHere()
        for _, entry in ipairs(me and me.addresses or {}) do
            if entry.address == current then return entry.unread or 0 end
        end
        return 0
    end

    -- The address showing, and how much is waiting. The count is the part
    -- that must survive a narrow screen, so the address gives way.
    local function subtitle(width)
        local unread = unreadHere()
        local count = unread > 0 and (" (" .. unread .. ")") or ""
        return ui.truncate(current or "No address yet", width - 3 - #count)
            .. count
    end

    -- Getting an address ---------------------------------------------------------

    local function claim()
        local person = api.account() or {}
        local suggestion = string.lower(tostring(person.name or ""))
            :gsub("%s+", "."):gsub("[^a-z0-9%._%-]", ""):sub(1, 16)
        local name = ui.input(target, "Your address", {
            hint = "@" .. tostring(me and me.personal_domain or "foxy.com"),
            mode = "email", maxLength = 16, minLength = 2,
            initial = suggestion })
        if not name then return false end
        local got, err = ask("MAIL_CLAIM", { name = name })
        if not got then
            ui.message(target, "error", "Not yours yet", err, 2)
            return false
        end
        current, saved.current = got.address, got.address
        keep()
        ui.message(target, "success", "You're in", got.address, 1.6)
        return true
    end

    local function companyDomain(company)
        local domain = ui.input(target, "Domain for " .. ui.truncate(
            company.name, 10), { hint = "Like foxgoods.com", mode = "email",
            maxLength = 24, minLength = 4 })
        if not domain then return end
        local first = ui.input(target, "First address", {
            hint = "Before the @, like hello", mode = "email",
            maxLength = 16, minLength = 2, initial = "hello" })
        if not first then return end
        local got, err = ask("MAIL_DOMAIN", { company_id = company.company_id,
            domain = domain, name = first })
        if not got then
            ui.message(target, "error", "Not registered", err, 2)
            return
        end
        current, saved.current = got.address, got.address
        keep()
        ui.message(target, "success", got.domain .. " is yours", got.address, 1.8)
    end

    local function companyAddress(company)
        local name = ui.input(target, "New address", {
            hint = "@" .. company.domain, mode = "email", maxLength = 16,
            minLength = 2 })
        if not name then return end
        local got, err = ask("MAIL_ADDRESS", { domain = company.domain,
            name = name })
        if not got then
            ui.message(target, "error", "Not added", err, 2)
            return
        end
        ui.message(target, "success", "Added", got.address, 1.4)
    end

    -- Writing ------------------------------------------------------------------------

    -- Returns true when something was sent. `draft` fills in a reply.
    local function compose(draft)
        draft = draft or {}
        if not current then
            ui.message(target, "info", "No address yet",
                "Get one on the Me tab", 1.8)
            return false
        end
        local to = ui.input(target, "To", { hint = "Addresses, spaces between",
            mode = "email", maxLength = 120, allowSpace = true,
            scrollToEnd = true, initial = draft.to })
        if not to then return false end
        local subject = ui.input(target, "Subject", { mode = "text",
            maxLength = 40, allowSpace = true, minLength = 0,
            initial = draft.subject })
        if not subject then return false end
        local body = ui.input(target, "Message", { hint = "Up to 300 letters",
            mode = "text", maxLength = 300, allowSpace = true,
            scrollToEnd = true, minLength = 0 })
        if not body then return false end
        if not ui.confirm(target, "Send it?", "From " .. current .. " to "
            .. to .. ".", "Send", "Not yet") then
            return false
        end
        local sent, err = ask("MAIL_SEND", { from = current, to = to,
            subject = subject, body = body, reply_to = draft.reply_to })
        if not sent then
            ui.message(target, "error", "Not sent", err, 2.2)
            return false
        end
        ui.message(target, "success", "Sent", "To " .. table.concat(sent.to,
            ", "), 1.4)
        return true
    end

    -- Reading -------------------------------------------------------------------------

    local function readScreen(id, box)
        local got, err = ask("MAIL_READ", { address = current, id = id })
        if not got then
            ui.message(target, "error", "Cannot open it", err, 1.8)
            return
        end
        local message = got.message
        local offset = 0
        while running() do
            local width, height = target.getSize()
            local lines = ui.wrap(message.body ~= "" and message.body
                or "(nothing written)", width - 2)
            local room = math.max(1, height - 11)
            offset = math.max(0, math.min(offset, #lines - room))
            ui.clear(target)
            ui.header(target, ui.truncate(message.subject, width - 9),
                ui.truncate("From " .. message.from, width - 3),
                util.formatClock())
            ui.text(target, 2, 5, ui.truncate("To " .. table.concat(message.to,
                ", "), width - 2), ui.theme.muted)
            ui.text(target, 2, 6, ui.truncate("Day " .. tostring(message.day)
                .. "  " .. tostring(message.time) .. (message.app_name
                    and ("  via " .. message.app_name) or ""), width - 2),
                ui.theme.muted)
            for index = 1, room do
                local line = lines[offset + index]
                if not line then break end
                ui.text(target, 2, 7 + index, line, ui.theme.ink)
            end
            local scene = ui.scene(target)
            if #lines > room then
                scene:button("up", width - 8, height - 3, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 4, height - 3, 3, 1, "v",
                    { background = ui.theme.panel,
                        disabled = offset + room >= #lines })
            end
            local half = math.floor((width - 3) / 2)
            scene:button("reply", 2, height - 2, half, 1,
                box == "inbox" and "Reply" or "Again",
                { background = FOX, foreground = colors.black })
            scene:button("delete", 3 + half, height - 2, width - 3 - half, 1,
                "Delete", { background = ui.theme.danger })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return end
            if action == "up" then
                offset = offset - room
            elseif action == "down" then
                offset = offset + room
            elseif action == "reply" then
                local subject = message.subject
                if box == "inbox" and not subject:match("^Re: ") then
                    subject = ("Re: " .. subject):sub(1, 40)
                end
                if compose({ to = box == "inbox" and message.from
                    or table.concat(message.to, " "), subject = subject,
                    reply_to = box == "inbox" and message.id or nil }) then
                    return
                end
            elseif action == "delete" and ui.confirm(target, "Delete it?",
                "It is gone from this box for good.", "Delete", "Keep") then
                local deleted, deleteError = ask("MAIL_DELETE",
                    { address = current, id = id })
                if deleted then return end
                ui.message(target, "error", "Not deleted", deleteError, 1.6)
            end
        end
    end

    -- The pages -----------------------------------------------------------------------

    -- Inbox or Sent. Live: it asks again every few seconds.
    local function listPage(box)
        local page = 1
        while running() do
            local width, height = target.getSize()
            local listed = current and ask("MAIL_LIST",
                { address = current, box = box })
            local messages = listed and listed.messages or {}
            local per = math.max(1, math.floor((height - 6) / 3))
            local pages = math.max(1, math.ceil(#messages / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, box == "inbox" and "Inbox" or "Sent",
                subtitle(width), util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local message = messages[index]
                if not message then break end
                local fresh = box == "inbox" and not message.read
                local who = box == "inbox" and message.from
                    or ("To " .. table.concat(message.to, ", "))
                scene:button("open:" .. index, 2, 2 + slot * 3, width - 2, 2,
                    ui.truncate(who, width - 4) .. "\n"
                        .. ui.truncate(message.subject, width - 4),
                    { background = fresh and FOX or ui.theme.panel,
                        foreground = fresh and colors.black or colors.white })
            end
            if #messages == 0 then
                ui.wrappedText(target, 2, 6, not current
                    and "No address yet. Get one on the Me tab."
                    or listed and (box == "inbox" and "Nothing here yet."
                        or "Nothing sent yet.")
                    or "Cannot reach the Bank. Trying again.", width - 2, 3,
                    ui.theme.muted)
            end
            if pages > 1 then
                scene:button("prev", 2, height - 2, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, height - 2, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, TABS, box, FOX)
            local action = scene:wait({ tickRate = 5 })
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            if action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            elseif action == "__tick" then
                refresh()
            else
                local index = tonumber(action and action:match("^open:(%d+)$"))
                if index and messages[index] then
                    readScreen(messages[index].id, box)
                    refresh()
                end
            end
        end
        return "home"
    end

    -- Which address is showing, and getting more of them.
    local function mePage()
        local page = 1
        while running() do
            local width, height = target.getSize()
            refresh()
            local options = {}
            for _, entry in ipairs(me and me.addresses or {}) do
                options[#options + 1] = { kind = "use", address = entry.address,
                    label = entry.address, detail = (entry.address == current
                        and "Showing now" or (entry.company_name or "Personal"))
                        .. ((entry.unread or 0) > 0
                            and ("  " .. entry.unread .. " new") or "") }
            end
            if me and not me.personal then
                options[#options + 1] = { kind = "claim",
                    label = "Get my address", detail = "Yours, at "
                        .. tostring(me.personal_domain) }
            end
            for _, company in ipairs(me and me.companies or {}) do
                options[#options + 1] = company.domain
                    and { kind = "more", company = company,
                        label = "New address", detail = "@" .. company.domain }
                    or { kind = "domain", company = company,
                        label = "Email for " .. company.name,
                        detail = "Register a domain" }
            end
            local per = math.max(1, math.floor((height - 6) / 3))
            local pages = math.max(1, math.ceil(#options / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, "Me", me and "Your addresses" or "Offline",
                util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local option = options[index]
                if not option then break end
                local showing = option.address and option.address == current
                scene:button("pick:" .. index, 2, 2 + slot * 3, width - 2, 2,
                    ui.truncate(option.label, width - 4) .. "\n"
                        .. ui.truncate(option.detail, width - 4),
                    { background = showing and FOX or option.kind == "use"
                        and ui.theme.panel or ui.theme.accentDark,
                      foreground = showing and colors.black or colors.white })
            end
            if pages > 1 then
                scene:button("prev", 2, height - 2, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, height - 2, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, TABS, "me", FOX)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            if action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            else
                local index = tonumber(action and action:match("^pick:(%d+)$"))
                local option = index and options[index]
                if option and option.kind == "use" then
                    current, saved.current = option.address, option.address
                    keep()
                    return "tab:inbox"
                elseif option and option.kind == "claim" then
                    claim()
                elseif option and option.kind == "domain" then
                    companyDomain(option.company)
                elseif option and option.kind == "more" then
                    companyAddress(option.company)
                end
            end
        end
        return "home"
    end

    -- Starting ---------------------------------------------------------------------------

    if not refresh() then
        ui.message(target, "error", "FoxMail is offline",
            "The Bank is not answering", 2)
        return
    end
    if #me.addresses == 0 then
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "FoxMail", "Email for everybody", util.formatClock())
        ui.wrappedText(target, 2, 5, "Get your own address at "
            .. tostring(me.personal_domain) .. ". Anybody with one can"
            .. " write to you, and you to them.", width - 2, 5, ui.theme.ink)
        local scene = ui.scene(target)
        scene:button("claim", 2, 12, width - 2, 3, "Get my address",
            { background = FOX, foreground = colors.black, shadow = true })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action ~= "claim" or not claim() then
            -- A company owner can start from the Me tab instead.
            if #(me.companies or {}) == 0 then return end
        end
        refresh()
    end

    local tab = "inbox"
    local wanted = type(api.action) == "function" and api.action()
    if wanted == "write" then compose() end

    while running() do
        local switched
        if tab == "write" then
            compose()
            refresh()
            switched = "tab:sent"
        elseif tab == "me" then
            switched = mePage()
        else
            switched = listPage(tab)
        end
        local nextTab = type(switched) == "string"
            and switched:match("^tab:(.+)$")
        if not nextTab then return end
        tab = nextTab
    end
end
