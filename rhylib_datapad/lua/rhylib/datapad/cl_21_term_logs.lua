--[[
    Battalion computer window, Logs / Records tab (client): search (title,
    text, author, patient) with a time filter, the reader, and for
    moderators delete entry / ban author. State in LG; registered with
    D.TermAddTab (cl_20_terminal.lua).
      dp.tread / dp.tbody   an entry's text      dp.tfind / dp.tfound  search
      dp.tdel, dp.tban      moderation
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)

local LG = { selected = nil, bodies = {}, filter = { q = "", days = 0, mp = false, ids = nil } }   -- (selected: log id; bodies[id] = text; filter.ids: last search)

local function entryById(id)
    for _, e in ipairs(T.term.entries) do
        if e.id == id then return e end
    end
end

local function logReader(parent)
    local k = T.K()
    local s = k.S
    local e = LG.selected and entryById(LG.selected)
    if not e then
        T.Label(parent, "Pick an entry to read it.")
        return
    end
    local h = k.Heading(parent, e.title)
    h:Dock(TOP)
    local by = T.Label(parent, "By " .. e.author .. (e.pn ~= "" and (" · patient " .. e.pn) or "") .. " · " .. T.when(e.t))
    by:DockMargin(0, s(4), 0, s(8))
    if T.term.mod then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local del = k.Button(row, "Delete entry", function()
            T.Send("dp.tdel", function() net.WriteUInt(e.id, 20) end)
            LG.selected = nil
        end, { small = true, danger = true })
        del:Dock(LEFT)
        del:SetWide(s(140))
        local ban = k.Button(row, "Ban author", function()
            T.Send("dp.tban", function() net.WriteUInt(e.id, 20) end)
        end, { small = true, danger = true })
        ban:Dock(LEFT)
        ban:SetWide(s(140))
        ban:DockMargin(s(6), 0, 0, 0)
    end
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, LG.bodies[e.id] or "Loading…", 14, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
    if not LG.bodies[e.id] then T.Send("dp.tread", function() net.WriteUInt(e.id, 20) end) end
end

local function runSearch()
    if LG.filter.q == "" and LG.filter.days == 0 then
        LG.filter.ids = nil
        T.Build()
        return
    end
    T.Send("dp.tfind", function()
        net.WriteString(string.sub(LG.filter.q, 1, 64))
        net.WriteUInt(LG.filter.days, 10)
    end)
end

local function logsTab(body)
    local k = T.K()
    local s = k.S
    -- Search bar.
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(30))
    bar:DockMargin(0, 0, 0, s(8))
    bar.Paint = nil
    local q = k.TextEntry(bar, "Search title, text or author")
    q:Dock(LEFT)
    q:SetWide(s(300))
    q:SetText(LG.filter.q)
    q.OnEnter = function(self)
        LG.filter.q = string.Trim(self:GetText() or "")
        runSearch()
    end
    local go = k.Button(bar, "Search", function() q:OnEnter() end, { small = true, accent = true })
    go:Dock(LEFT)
    go:SetWide(s(80))
    go:DockMargin(s(6), 0, s(12), 0)
    local days = k.Choices(bar, { { 0, "Any time" }, { 1, "Today" }, { 7, "Week" }, { 30, "Month" } },
        function() return LG.filter.days end,
        function(v)
            LG.filter.days = v
            LG.filter.q = string.Trim(q:GetText() or "")
            runSearch()
        end)
    days:Dock(FILL)

    local left, right = T.Columns(body)
    local shown = {}
    for _, e in ipairs(T.term.entries) do
        if not LG.filter.ids or LG.filter.ids[e.id] then shown[#shown + 1] = e end
    end
    local h = k.Heading(left, (T.term.med and "Medical records" or "Logs") .. " (" .. #shown .. (#shown ~= #T.term.entries and (" of " .. #T.term.entries) or "") .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #shown == 0 then T.Label(sp, #T.term.entries == 0 and "Nothing uploaded yet." or "Nothing matches.") end
    for _, e in ipairs(shown) do
        local sub = e.author .. (e.pn ~= "" and (" → " .. e.pn) or "") .. "  ·  " .. T.when(e.t)
        T.ListRow(sp, e.title, sub, function() return LG.selected == e.id end, function()
            LG.selected = e.id
            T.Build()
        end, e.mp and "MP" or nil)
    end
    logReader(right)
end

Rhylib.Net.Receive("dp.tbody", function()
    local id = net.ReadUInt(20)
    LG.bodies[id] = net.ReadString()
    if IsValid(T.panel) and LG.selected == id and T.tab == "logs" then T.Build() end
end)

Rhylib.Net.Receive("dp.tfound", function()
    local ids = {}
    for _ = 1, net.ReadUInt(8) do ids[net.ReadUInt(20)] = true end
    LG.filter.ids = ids
    if IsValid(T.panel) and T.tab == "logs" then T.Build() end
end)

D.TermAddTab("logs", {
    order = 10,
    name = function(tm) return tm.med and "Records" or "Logs" end,
    build = logsTab,
    reset = function() LG.selected, LG.bodies, LG.filter = nil, {}, { q = "", days = 0, mp = false, ids = nil } end,
    onTerm = function() if LG.selected and not entryById(LG.selected) then LG.selected = nil end end,
})
