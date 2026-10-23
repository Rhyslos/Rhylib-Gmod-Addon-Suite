--[[
    Jobs made in game (client): the job list from the server, and the
    Staff > Jobs page (permission rhylib.roster.jobs; needs rhylib_menus).
    How it works and the def fields: sh_40_jobs.lua; checks and messages:
    sv_40_jobs.lua.

    Staff > Jobs:
      - the jobs by category, each with its command, players, limit,
        battalion and rank, flags, and where it comes from (jobs.lua or
        made in game), with Edit, Off / On, Delete (made in game) or Reset
        (an edited jobs.lua job)
      - New job: every field (name, command, category or a new one,
        colour, player models (typed, or picked from the installed player
        models), description, limit, salary, order, who may take it,
        battalion + lowest rank, basic training, name prefix, medic / MP /
        commander / bomb squad, qualification, armoury roles, spawn armour,
        hands model, spawn weapons)
      - New battalion: name, command prefix, colour, MP or not, and a model
        per role; makes its category and five jobs (Clone Trooper, Medic,
        Sergeant, Officer, Commander) like battalion() in jobs.lua
    The server checks everything again and answers with roster.jobmsg
    (shown on the page and in chat).

    Adds R.Jobs.state (the last list from the server), R.Jobs.PickModel(cb)
    (a window of the installed player models; cb(path)).
]]

local R = Rhylib.Roster
local J = R.Jobs
local Net = Rhylib.Net

local PAGE = "jobeditor"
local OP_SAVE, OP_OFF, OP_DELETE, OP_RESET, OP_BATTALION = 0, 1, 2, 3, 4   -- (as J.OP_* on the server)

local view = { kind = "list" }   -- list | edit { cmd, isNew, form } | battalion { form }
local busyUntil = 0   -- waiting for roster.jobmsg (gives up after 5 s)
local function isBusy() return RealTime() < busyUntil end

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end

local function redraw()
    local M = Rhylib.Menus
    if M and IsValid(M.pause) and M.pause.pageId == PAGE and J.Build then
        M.pause.page:Clear()
        J.Build(M.pause.page)
    end
end

--------------------------------------------------------------------------
-- The job list from the server
--------------------------------------------------------------------------

Net.Receive("roster.jobs", function()
    local len = net.ReadUInt(32)
    local st = J.Unpack(net.ReadData(len))
    if not istable(st) then return end
    J.state = st
    J.Apply(st)
    file.CreateDir("rhylib")
    file.Write(J.CacheFile(), util.TableToJSON(st) or "{}")
    if view.kind == "list" then redraw() end
end)

Rhylib.Hook.Add("InitPostEntity", "roster.jobsreq", function()
    Net.Start("roster.jobsreq")
    net.SendToServer()
end)

Net.Receive("roster.jobmsg", function()
    local ok, text = net.ReadBool(), net.ReadString()
    busyUntil = 0
    J.msg = { ok = ok, text = text }
    chat.AddText(ok and Color(120, 210, 140) or Color(230, 110, 90), "[Jobs] ", Color(230, 230, 230), text)
    if ok then view = { kind = "list" } end
    redraw()
end)

local function send(op, payload)
    local raw = J.Pack(payload)
    if #raw > 32000 then
        J.msg = { ok = false, text = "That's too much text" }
        redraw()
        return
    end
    busyUntil = RealTime() + 5
    timer.Create("Rhylib.Roster.JobsBusy", 5.1, 1, redraw)   -- (no answer: drop "Saving…")
    Net.Start("roster.jobedit")
    net.WriteUInt(op, 3)
    net.WriteUInt(#raw, 16)
    net.WriteData(raw, #raw)
    net.SendToServer()
end

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function catNames()
    local out = {}
    for _, c in ipairs(DarkRP.getCategories().jobs or {}) do out[#out + 1] = c.name end
    return out
end

local function battalions()
    local out, seen = {}, {}
    for _, j in pairs(RPExtraTeams or {}) do
        if j.battalion and not seen[j.battalion] and not j.rhylibDead then
            seen[j.battalion] = true
            out[#out + 1] = j.battalion
        end
    end
    table.sort(out)
    return out
end

local function hex(col)
    return string.format("#%02x%02x%02x", col[1] or 0, col[2] or 0, col[3] or 0)
end

local function fromHex(s)
    local r, g, b = string.match(string.lower(s or ""), "^#?(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

local PALETTE = {
    { 230, 130, 40 }, { 85, 150, 70 }, { 125, 140, 160 }, { 200, 50, 50 }, { 60, 110, 200 }, { 150, 155, 160 },
    { 120, 170, 120 }, { 210, 190, 70 }, { 140, 90, 190 }, { 60, 170, 170 }, { 220, 220, 220 }, { 90, 90, 95 },
}

local function teamOf(job)
    for t, j in pairs(RPExtraTeams or {}) do if j == job then return t end end
end

--------------------------------------------------------------------------
-- Player model picker
--------------------------------------------------------------------------

-- J.PickModel(cb): a window with every installed player model; a click
-- calls cb(path). Esc or Close cancels.
function J.PickModel(cb)
    local k = K()
    if not k then return end
    local s = k.S
    local Menus = Rhylib.Menus
    local f = vgui.Create("EditablePanel")
    Menus.prompts[f] = true
    f.OnRemove = function(self) Menus.prompts[self] = nil end
    f:SetSize(math.min(ScrW() - s(80), s(900)), math.min(ScrH() - s(80), s(640)))
    f:Center()
    f:MakePopup()
    f:DoModal()
    f:DockPadding(s(14), s(42), s(14), s(14))
    function f:Paint(w, h) k.Plate(0, 0, w, h, { title = "Pick a player model", ticks = "all" }) end

    local top = vgui.Create("DPanel", f)
    top:Dock(TOP)
    top:SetTall(s(30))
    top:DockMargin(0, 0, 0, s(8))
    top.Paint = nil
    local close = k.Button(top, "Close", function() f:Remove() end, { small = true })
    close:Dock(RIGHT)
    close:SetWide(s(100))
    local search = k.TextEntry(top, "Search names and paths")
    search:Dock(FILL)
    search:DockMargin(0, 0, s(8), 0)
    search:SetUpdateOnType(true)

    local list = {}
    for name, mdl in pairs(player_manager.AllValidModels()) do list[#list + 1] = { name = name, mdl = mdl } end
    table.sort(list, function(a, b) return a.name < b.name end)

    local sp = k.Scroll(f)
    sp:Dock(FILL)
    local grid = vgui.Create("DIconLayout", sp)
    grid:Dock(TOP)
    grid:SetSpaceX(s(6))
    grid:SetSpaceY(s(6))
    local function fill(q)
        grid:Clear()
        q = string.lower(q or "")
        local n = 0
        for _, it in ipairs(list) do
            if q == "" or string.find(string.lower(it.name), q, 1, true) or string.find(string.lower(it.mdl), q, 1, true) then
                n = n + 1
                if n > 300 then break end
                local icon = grid:Add("SpawnIcon")
                icon:SetSize(s(72), s(72))
                icon:SetModel(it.mdl)
                icon:SetTooltip(it.name .. "\n" .. it.mdl)
                icon.DoClick = function()
                    f:Remove()
                    cb(it.mdl)
                end
            end
        end
    end
    function search:OnValueChange(v) fill(v) end
    fill("")
    search:RequestFocus()
end

--------------------------------------------------------------------------
-- The page: list
--------------------------------------------------------------------------

local function statusLine(parent)
    local k = K()
    local m = J.msg
    local busy = isBusy()
    if busy or m then
        local l = k.Label(parent, busy and "Saving…" or m.text, 13, 600, busy and k.C.textDim or (m.ok and k.C.good or k.C.bad))
        l:Dock(TOP)
        l:DockMargin(0, 0, 0, k.S(6))
    end
end

local function jobLine(job, t)
    local bits = { "/" .. tostring(job.command), team.NumPlayers(t) .. " playing" }
    if (job.max or 0) > 0 then bits[#bits + 1] = "max " .. job.max end
    if job.battalion then bits[#bits + 1] = job.battalion .. (job.minRank and (" from " .. job.minRank) or "") end
    if job.needsTraining then bits[#bits + 1] = "trained" end
    for _, f in ipairs({ { "medic", "medic" }, { "mp", "MP" }, { "commander", "commander" }, { "eod", "bomb squad" }, { "bountyHunter", "bounty hunter" } }) do
        if job[f[1]] then bits[#bits + 1] = f[2] end
    end
    if job.qual then bits[#bits + 1] = "needs " .. R.QualName(job.qual) end
    if (job.admin or 0) > 0 then bits[#bits + 1] = job.admin == 2 and "superadmins" or "admins" end
    return table.concat(bits, "  ·  ")
end

local function buildList(page)
    local k = K()
    local s = k.S
    local C = k.C

    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(s(34))
    top:DockMargin(0, 0, 0, s(8))
    top.Paint = nil
    local nb = k.Button(top, "New job", function()
        local cats = catNames()
        view = { kind = "edit", isNew = true, form = {
            cmd = "", name = "", col = { 150, 155, 160 }, models = { "models/ct_trp/pm_ct_trp.mdl" }, desc = "",
            max = 0, salary = 20, order = 100, admin = 0, cat = cats[1] or "Recruits", weapons = {}, trained = true,
        } }
        J.msg = nil
        redraw()
    end, { accent = true })
    nb:Dock(LEFT)
    nb:SetWide(s(150))
    local bb = k.Button(top, "New battalion", function()
        view = { kind = "battalion", form = { name = "", prefix = "", col = { 60, 110, 200 }, mp = false, models = { trooper = "models/ct_trp/pm_ct_trp.mdl" } } }
        J.msg = nil
        redraw()
    end)
    bb:Dock(LEFT)
    bb:SetWide(s(170))
    bb:DockMargin(s(8), 0, 0, 0)

    local note = k.Label(page, "Changes reach everyone straight away. Jobs from jobs.lua can be edited and switched off (Reset goes back to the file). Jobs made here can be deleted: they hide at once and are gone after the next map change. Players on a job that's switched off go to their home job.", 13, 400, C.textDim)
    note:Dock(TOP)
    note:DockMargin(0, 0, 0, s(8))
    statusLine(page)

    if not J.state then
        local l = k.Label(page, "Waiting for the job list from the server…", 14, 400, C.textDim)
        l:Dock(TOP)
        Net.Start("roster.jobsreq")
        net.SendToServer()
        return
    end

    local sp = k.Scroll(page)
    sp:Dock(FILL)

    -- Saved jobs DarkRP refused (e.g. a jobs.lua job took their command).
    local broken = istable(J.state.broken) and J.state.broken or {}
    if #broken > 0 then
        local h = k.Heading(sp, "Saved jobs that couldn't be made", C.bad)
        h:Dock(TOP)
        h:DockMargin(0, s(6), s(8), s(4))
        for _, b in ipairs(broken) do
            local r = k.Row(sp, tostring(b.name), "/" .. tostring(b.cmd) .. "  ·  see the server console for why; delete it and make it again")
            r:Dock(TOP)
            r:DockMargin(0, 0, s(8), s(3))
            r.right:SetWide(s(96))
            local del = k.Button(r.right, "Delete", function() send(OP_DELETE, { cmd = b.cmd }) end, { small = true, danger = true })
            del:Dock(FILL)
            del:DockMargin(0, s(7), 0, s(7))
        end
    end

    for _, cat in ipairs(DarkRP.getCategories().jobs or {}) do
        local members = cat.members or {}
        if #members > 0 then
            local h = k.Heading(sp, cat.name, cat.color)
            h:Dock(TOP)
            h:DockMargin(0, s(6), s(8), s(4))
            for _, job in ipairs(members) do
                local t = teamOf(job)
                if t then
                    local info = J.Info(t)
                    local r = vgui.Create("DPanel", sp)
                    r:Dock(TOP)
                    r:SetTall(s(52))
                    r:DockMargin(0, 0, s(8), s(3))
                    r:DockPadding(s(12), s(10), s(12), s(10))
                    local tags = {}
                    tags[#tags + 1] = info.made and "MADE IN GAME" or "JOBS.LUA"
                    if info.edited then tags[#tags + 1] = "EDITED" end
                    if info.dead then tags[#tags + 1] = "DELETED" elseif info.off then tags[#tags + 1] = "OFF" end
                    local tagText = table.concat(tags, "  ·  ")
                    function r:Paint(w, h)
                        k.SetCol(self:IsHovered() and C.rowAlt or C.row)
                        surface.DrawRect(0, 0, w, h)
                        k.SetCol(C.edgeDark)
                        surface.DrawOutlinedRect(0, 0, w, h)
                        k.SetCol(job.color or C.accent, info.off and 90 or 255)
                        surface.DrawRect(1, 1, s(5), h - 2)
                        local tc = info.off and C.textDim or C.text
                        draw.SimpleText(job.name or "?", k.Font(14, 600), s(16), h * 0.34, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        surface.SetFont(k.Font(14, 600))
                        local nw = surface.GetTextSize(job.name or "?")
                        draw.SimpleText(tagText, k.Font(11, 700), s(16) + nw + s(10), h * 0.34, (info.off or info.dead) and C.warn or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText(k.Fit(jobLine(job, t), k.Font(12), w - s(420)), k.Font(12), s(16), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                    local function btn(text, fn, opts)
                        local b = k.Button(r, text, fn, opts)
                        b:Dock(RIGHT)
                        b:SetWide(s(96))
                        b:DockMargin(s(6), 0, 0, 0)
                        return b
                    end
                    local cmd = job.command
                    if info.made then
                        btn("Delete", function()
                            Derma_Query("Delete " .. job.name .. "? It's hidden at once and gone after the next map change. Players on it go to their home job.",
                                "Delete job", "Delete", function() send(OP_DELETE, { cmd = cmd }) end, "Cancel")
                        end, { small = true, danger = true, enabled = not info.dead })
                    elseif info.edited then
                        btn("Reset", function()
                            Derma_Query("Put " .. job.name .. " back to its jobs.lua version?", "Reset job", "Reset", function() send(OP_RESET, { cmd = cmd }) end, "Cancel")
                        end, { small = true })
                    end
                    btn(info.off and "Switch on" or "Switch off", function() send(OP_OFF, { cmd = cmd, off = not info.off }) end,
                        { small = true, enabled = not info.dead and (info.off or not info.locked),
                          tooltip = info.locked and "New players and clones without a battalion go here: it can't be switched off" or nil })
                    btn("Edit", function()
                        view = { kind = "edit", cmd = cmd, isNew = false, form = J.FromJob(job) }
                        J.msg = nil
                        redraw()
                    end, { small = true, accent = true, enabled = not info.dead })
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- The page: form rows
--------------------------------------------------------------------------

local function formRows(sp, form)
    local k = K()
    local s = k.S
    local rows = {}

    function rows.row(title, desc, w)
        local r = k.Row(sp, title, desc)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        r.right:SetWide(s(w or 340))
        return r
    end

    -- Centre a control of height ch in a row's right side.
    local function centre(pnl, r, ch)
        local m = math.max(0, math.floor((r:GetTall() - s(12) - ch) / 2))
        pnl:DockMargin(0, m, 0, m)
    end

    function rows.heading(text)
        local h = k.Heading(sp, text)
        h:Dock(TOP)
        h:DockMargin(0, s(8), s(8), s(4))
    end

    function rows.text(title, desc, keyName, placeholder, w)
        local r = rows.row(title, desc, w)
        local e = k.TextEntry(r.right, placeholder)
        e:Dock(FILL)
        centre(e, r, s(30))
        e:SetText(tostring(form[keyName] or ""))
        e:SetUpdateOnType(true)
        function e:OnValueChange(v) form[keyName] = v end
        return e
    end

    -- optional: an empty box means "not set" (nil) instead of 0.
    function rows.number(title, desc, keyName, w, optional)
        local e = rows.text(title, desc, keyName, "", w or 120)
        e:SetNumeric(true)
        function e:OnValueChange(v)
            if optional and string.Trim(v) == "" then form[keyName] = nil else form[keyName] = tonumber(v) or 0 end
        end
        return e
    end

    function rows.toggle(title, desc, keyName)
        local r = rows.row(title, desc, 64)
        local t = k.Toggle(r.right, function() return form[keyName] == true end, function(v) form[keyName] = v or nil end)
        t:Dock(RIGHT)
    end

    -- A dropdown: options() -> list of { value, label }; extra = { label, fn }
    -- added at the bottom (e.g. "New category…").
    function rows.pick(title, desc, keyName, options, extra, w)
        local r = rows.row(title, desc, w or 260)
        local function label()
            for _, o in ipairs(options()) do if o[1] == form[keyName] then return o[2] end end
            return form[keyName] ~= nil and tostring(form[keyName]) or "None"
        end
        local b = k.Button(r.right, function() return label() .. "  ▾" end, function()
            local m = k.Menu()
            for _, o in ipairs(options()) do m:AddOption(o[2], function() form[keyName] = o[1] end) end
            if extra then
                m:AddSpacer()
                m:AddOption(extra[1], extra[2])
            end
            m:Open()
        end, { small = true, align = "left" })
        b:Dock(FILL)
        centre(b, r, s(26))
    end

    function rows.colour(title, desc, keyName)
        local r = rows.row(title, desc, 260)
        local sw = vgui.Create("DPanel", r.right)
        sw:Dock(LEFT)
        sw:SetWide(s(30))
        sw:DockMargin(0, s(4), s(8), s(4))
        function sw:Paint(w, h)
            local c = form[keyName] or { 0, 0, 0 }
            surface.SetDrawColor(c[1], c[2], c[3], 255)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(k.C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        local pal = k.Button(r.right, "▾", function()
            local m = k.Menu()
            for _, c in ipairs(PALETTE) do
                local o = m:AddOption(hex(c), function() form[keyName] = table.Copy(c) if IsValid(r.entry) then r.entry:SetText(hex(c)) end end)
                o.PaintOver = function(_, w, h) surface.SetDrawColor(c[1], c[2], c[3], 255) surface.DrawRect(w - h, 2, h - 4, h - 4) end
            end
            m:Open()
        end, { small = true })
        pal:Dock(RIGHT)
        pal:SetWide(s(40))
        pal:DockMargin(s(6), s(4), 0, s(4))
        local e = k.TextEntry(r.right, "#rrggbb")
        e:Dock(FILL)
        e:DockMargin(0, s(1), 0, s(1))
        e:SetText(hex(form[keyName] or { 150, 155, 160 }))
        e:SetUpdateOnType(true)
        function e:OnValueChange(v) local c = fromHex(v) if c then form[keyName] = c end end
        r.entry = e
    end

    -- A model path with a Pick button (player models). Returns the row and
    -- the text box.
    function rows.model(title, desc, get, set)
        local r = rows.row(title, desc, 460)
        local e
        local pick = k.Button(r.right, "Pick…", function()
            J.PickModel(function(m) set(m) if IsValid(e) then e:SetText(m) end end)
        end, { small = true })
        pick:Dock(RIGHT)
        pick:SetWide(s(80))
        centre(pick, r, s(26))
        local pm = select(2, pick:GetDockMargin())
        pick:DockMargin(s(6), pm, 0, pm)
        e = k.TextEntry(r.right, "models/....mdl")
        e:Dock(FILL)
        centre(e, r, s(30))
        e:SetText(get() or "")
        e:SetUpdateOnType(true)
        function e:OnValueChange(v) set(string.Trim(v)) end
        r.centre = centre
        return r, e
    end

    return rows
end

--------------------------------------------------------------------------
-- The page: job editor
--------------------------------------------------------------------------

local function buildEdit(page)
    local k = K()
    local s = k.S
    local C = k.C
    local form = view.form
    local isNew = view.isNew

    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(s(34))
    top:DockMargin(0, 0, 0, s(8))
    top.Paint = nil
    local back = k.Button(top, "Back", function() view = { kind = "list" } J.msg = nil redraw() end)
    back:Dock(LEFT)
    back:SetWide(s(100))
    local save = k.Button(top, isNew and "Make job" or "Save", function()
        local d = table.Copy(form)
        d.weapons = {}
        for w in string.gmatch(form.weaponsText or table.concat(form.weapons or {}, ","), "[^,%s]+") do d.weapons[#d.weapons + 1] = w end
        d.weaponsText = nil
        d.newCat = nil
        send(OP_SAVE, { cmd = isNew and string.lower(string.Trim(form.cmd or "")) or view.cmd, new = isNew, newCat = form.newCat == true, d = d })
        redraw()
    end, { accent = true, enabled = function() return not isBusy() end })
    save:Dock(RIGHT)
    save:SetWide(s(140))
    local title = vgui.Create("DPanel", top)
    title:Dock(FILL)
    function title:Paint(w, h)
        draw.SimpleText(isNew and "New job" or ("Editing " .. tostring(form.name)), k.Font(16, 700), s(12), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    statusLine(page)

    local sp = k.Scroll(page)
    sp:Dock(FILL)
    local rows = formRows(sp, form)

    rows.heading("The job")
    rows.text("Name", "Shown in the job list and the scoreboard", "name", "e.g. ARC Trooper")
    if isNew then
        rows.text("Command", "Players type /command to take it (letters, digits, _)", "cmd", "e.g. arc", 200)
    else
        local r = rows.row("Command", "Can't change after the job is made", 200)
        local l = k.Label(r.right, "/" .. tostring(view.cmd), 14, 600, C.textDim)
        l:Dock(FILL)
    end
    rows.pick("Category", "The heading it sits under (battalions use their own name)", "cat",
        function()
            local out = {}
            for _, n in ipairs(catNames()) do out[#out + 1] = { n, n } end
            if form.newCat then out[#out + 1] = { form.cat, form.cat .. " (new)" } end
            return out
        end,
        { "New category…", function()
            k.Prompt("New category", "Its name (made when you save; it takes the job's colour)", "", function(t)
                t = string.Trim(t)
                if t ~= "" then form.cat = t form.newCat = true end
            end)
        end })
    rows.colour("Colour", "Job and name colour", "col")
    rows.number("Order", "Lower numbers come first in the category", "order")

    -- Description.
    local dr = vgui.Create("DPanel", sp)
    dr:Dock(TOP)
    dr:SetTall(s(104))
    dr:DockMargin(0, 0, s(8), s(3))
    dr:DockPadding(s(12), s(26), s(12), s(8))
    function dr:Paint(w, h)
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("Description", k.Font(14, 500), s(12), s(13), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local de = k.TextEntry(dr, "What the job is for")
    de:Dock(FILL)
    de:SetMultiline(true)
    de:SetText(form.desc or "")
    de:SetUpdateOnType(true)
    function de:OnValueChange(v) form.desc = v end

    rows.heading("Player models")
    form.models = istable(form.models) and form.models or {}
    for i = 1, #form.models do
        local idx = i
        local r = rows.model("Model " .. idx, idx == 1 and "Players get one of these at random" or nil,
            function() return form.models[idx] end, function(v) form.models[idx] = v end)
        if #form.models > 1 then
            local rm = k.Button(r.right, "X", function()
                table.remove(form.models, idx)
                redraw()
            end, { small = true, danger = true, tooltip = "Remove this model" })
            rm:Dock(RIGHT)
            rm:SetWide(s(34))
            r.centre(rm, r, s(26))
            local m = select(2, rm:GetDockMargin())
            rm:DockMargin(s(6), m, 0, m)
        end
    end
    if #form.models < 8 then
        local r = rows.row("Add a model", nil, 160)
        local b = k.Button(r.right, "Add model", function()
            form.models[#form.models + 1] = ""
            redraw()
        end, { small = true })
        b:Dock(FILL)
        b:DockMargin(0, s(7), 0, s(7))
    end

    rows.heading("Who can take it")
    rows.number("Limit", "Most players at once (0 = no limit; 0.25 = a quarter of the players)", "max")
    rows.pick("Staff only", "Leave on Everyone unless only staff should see it", "admin",
        function() return { { 0, "Everyone" }, { 1, "Admins" }, { 2, "Superadmins" } } end)
    rows.toggle("Needs basic training", "Only clones who passed basic training (CT and up)", "trained")
    rows.pick("Battalion", "Only members of this battalion (its roster and datapad computer)", "bn",
        function()
            local out = { { nil, "None" } }
            for _, b in ipairs(battalions()) do out[#out + 1] = { b, b } end
            if form.bn and not table.HasValue(battalions(), form.bn) then out[#out + 1] = { form.bn, form.bn .. " (new)" } end
            return out
        end,
        { "New battalion name…", function()
            k.Prompt("Battalion", "The battalion's name (members are kept by this name)", "", function(t)
                t = string.Trim(t)
                if t ~= "" then form.bn = t end
            end)
        end })
    rows.pick("Lowest rank", "With a battalion: the rank needed", "minRank",
        function()
            local out = {}
            for _, r in ipairs(R.Ranks()) do out[#out + 1] = { r[1], r[1] .. "  ·  " .. r[2] } end
            return out
        end)
    rows.pick("Qualification", "Needs this qualification (given at the battalion computer)", "qual",
        function()
            local out = { { nil, "None" } }
            for _, q in ipairs(R.Quals()) do out[#out + 1] = { q[1], q[2] } end
            return out
        end)

    rows.heading("Role")
    rows.toggle("Medic", "Medical tools and records, medic gear at the specialist armoury", "medic")
    rows.toggle("Military police", "Stun, cuff, search and jail; MP datapad tools", "mp")
    rows.toggle("Commander", "Moderates the battalion's computer", "commander")
    rows.toggle("Bomb squad", "Gets the datapad's bomb squad calls", "eod")
    rows.toggle("Bounty hunter", "Takes bounty contracts and learns the Bounty hunter skills (rhylib_bounty)", "bountyHunter")
    rows.text("Name prefix", "Fixed name prefix (CT, CC...); empty = their rank", "prefix", "", 120)
    rows.text("Armoury roles", "Extra specialist armoury roles, comma separated (e.g. heavy, pilot)", "role", "")

    rows.heading("Spawn and pay")
    rows.number("Spawn armour", "Empty = the server default", "armor", nil, true)
    rows.model("Hands model", "First-person arms (empty = the server default)",
        function() return form.hands end, function(v) form.hands = v ~= "" and v or nil end)
    if not form.weaponsText then form.weaponsText = table.concat(form.weapons or {}, ", ") end
    rows.text("Spawn weapons", "Weapon classes given on spawn, comma separated (gear normally comes from the armouries)", "weaponsText", "")
    rows.number("Salary", "DarkRP pay per payday (only with money switched on)", "salary")
end

--------------------------------------------------------------------------
-- The page: new battalion
--------------------------------------------------------------------------

local function buildBattalion(page)
    local k = K()
    local s = k.S
    local C = k.C
    local form = view.form

    local top = vgui.Create("DPanel", page)
    top:Dock(TOP)
    top:SetTall(s(34))
    top:DockMargin(0, 0, 0, s(8))
    top.Paint = nil
    local back = k.Button(top, "Back", function() view = { kind = "list" } J.msg = nil redraw() end)
    back:Dock(LEFT)
    back:SetWide(s(100))
    local save = k.Button(top, "Make battalion", function()
        send(OP_BATTALION, table.Copy(form))
        redraw()
    end, { accent = true, enabled = function() return not isBusy() end })
    save:Dock(RIGHT)
    save:SetWide(s(170))
    local title = vgui.Create("DPanel", top)
    title:Dock(FILL)
    function title:Paint(w, h)
        draw.SimpleText("New battalion", k.Font(16, 700), s(12), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local note = k.Label(page, "Makes a category and five jobs: Clone Trooper (PVT), Medic (PVT, max 6), Sergeant (SGT, max 6), Officer (LT, max 4) and Commander (CMD, max 1), like battalion() in jobs.lua. Edit each job afterwards to change limits, ranks or pay.", 13, 400, C.textDim)
    note:Dock(TOP)
    note:DockMargin(0, 0, 0, s(8))
    statusLine(page)

    local sp = k.Scroll(page)
    sp:Dock(FILL)
    local rows = formRows(sp, form)
    rows.heading("The battalion")
    rows.text("Name", "Also the category and the battalion its computer belongs to", "name", "e.g. 501st")
    rows.text("Command prefix", "212 makes /212trooper, /212medic, /212sergeant...", "prefix", "e.g. 501", 160)
    rows.colour("Colour", "Category and job colour", "col")
    rows.toggle("Military police", "Every job in it is MP (like the Coruscant Guard)", "mp")
    rows.heading("Models (empty = the trooper model)")
    form.models = form.models or {}
    for _, r in ipairs(J.BATTALION_ROLES) do
        local role = r[1]
        rows.model(r[2], role == "trooper" and "Needed" or nil, function() return form.models[role] end, function(v) form.models[role] = v ~= "" and v or nil end)
    end
end

--------------------------------------------------------------------------
-- Registering the page
--------------------------------------------------------------------------

function J.Build(page)
    if not (K() and DarkRP and DarkRP.getCategories) then return end
    if view.kind == "edit" then buildEdit(page)
    elseif view.kind == "battalion" then buildBattalion(page)
    else buildList(page) end
end

local function addPage()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddPage) then return end
    Menus.AddPage(PAGE, {
        title = "Jobs",
        order = 65,
        group = "staff",
        visible = function()
            local me = LocalPlayer()
            if not (IsValid(me) and DarkRP and RPExtraTeams) then return false end
            local A = Rhylib.Admin
            if A and A.Has then return A.Has(me, "rhylib.roster.jobs", "superadmin") end
            return me:IsSuperAdmin()
        end,
        build = function(page) J.Build(page) end,
    })
end
addPage()
Rhylib.Hook.Add("InitPostEntity", "roster.jobspage", addPage)
