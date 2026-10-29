--[[
    Battalion computer / medical holotable window (client): the window,
    shared helpers and the tab registry. Opens on dp.term (E on the
    computer); closes when you walk out of useRange. Needs the UI kit
    (Rhylib.UI.Kit). Every request starts with the computer entity
    (T.Send); the server checks range and rights again.

    Top: upload your notes; admins set the battalion. Each tab is its own
    file and keeps its own state:
      cl_21_term_logs.lua      Logs / Records: search, reader, moderation
      cl_22_term_board.lua     Board: battalion info, sessions, AARs
      cl_23_term_stats.lua     Stats: totals and members for a period
      cl_24_term_unit.lua      Orders, LOA, Applications, Apply; the
                               "you got accepted" popup (dp.uprompt)
      cl_25_term_people.lua    Personnel files
      cl_26_term_missions.lua  Missions: current one and the archive
      Bans                     (here) moderators: who can't upload
    The medical holotable has Records (and Bans) only.

    D.Term (T) is the shared table:
      T.term (last dp.term), T.panel, T.tab (shown tab id), T.unit and
      T.people (unit data and member list, shared by several tabs),
      T.Build(), T.Send(name, fn), T.K(), T.when(t), T.ListRow, T.Label,
      T.Columns, T.FootRow, T.FootButton, T.ParseDate, T.Countdown, T.OPAQUE.
    D.TermAddTab(id, { name = string or fn(term), order, has = fn(term),
      build = fn(body), accent = fn(term), reset = fn(), onTerm = fn(term) })
      adds a tab: has decides whether it shows; reset runs when a
      different computer is opened; onTerm after every dp.term.
    Each tab asks for its data the first time it is shown; replies for
    another computer are ignored.
]]

local D = Rhylib.Datapad

D.Term = D.Term or {}
local T = D.Term
T.tabs = T.tabs or {}
T.tab = T.tab or "logs"

function T.K() return Rhylib.UI and Rhylib.UI.Kit end
local K = T.K
T.OPAQUE = Color(14, 16, 15, 255)
local OPAQUE = T.OPAQUE
function T.when(t) return t and t > 0 and os.date("%d %b %Y %H:%M", t) or "" end
local when = T.when

-- D.TermAddTab(id, def): register (or replace) a computer window tab.
function D.TermAddTab(id, def)
    def.id = id
    T.tabs[id] = def
end

-- T.Send(name, fn): a computer message: the computer entity first, then fn() writes the rest.
function T.Send(name, fn)
    Rhylib.Net.Start(name)
    net.WriteEntity(T.term.ent)
    if fn then fn() end
    net.SendToServer()
end
local send = T.Send

function T.Countdown(at)
    local d = at - os.time()
    if d <= 0 then return "now" end
    if d < 3600 then return "in " .. math.ceil(d / 60) .. " min" end
    if d < 86400 then return string.format("in %d h %d min", math.floor(d / 3600), math.floor(d % 3600 / 60)) end
    return string.format("in %d d %d h", math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

-- A two-line list row: title, dim line under it.
function T.ListRow(parent, title, sub, isSel, onClick, tag)
    local k = K()
    local s = k.S
    local b = k.Button(parent, "", onClick, { small = true, align = "left", selected = isSel })
    b:SetTall(s(44))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(3))
    local paint = b.Paint
    function b:Paint(w, hh)
        paint(self, w, hh)
        local x = s(14)
        if tag then
            k.Caps(tag, x, s(14), k.C.accent)
            surface.SetFont(k.Font(12, 700))
            x = x + surface.GetTextSize(string.upper(tag)) + s(8)
        end
        draw.SimpleText(k.Fit(title, k.Font(14, 600), w - x - s(12)), k.Font(14, 600), x, s(6), k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(k.Fit(sub, k.Font(11), w - s(26)), k.Font(11), s(14), hh - s(6), k.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        return true
    end
    return b
end

function T.Label(parent, text, col, size)
    local k = K()
    local l = k.Label(parent, text, size or 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    return l
end

function T.Columns(body)
    local k = K()
    local s = k.S
    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(s(430))
    left.Paint = nil
    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)
    right:DockMargin(s(16), 0, 0, 0)
    right.Paint = nil
    return left, right
end
local listRow, label, columns = T.ListRow, T.Label, T.Columns

function T.FootRow(parent)
    local s = K().S
    local row = vgui.Create("DPanel", parent)
    row:Dock(BOTTOM)
    row:SetTall(s(32))
    row:DockMargin(0, s(8), 0, 0)
    row.Paint = nil
    return row
end

function T.FootButton(row, text, fn, opts)
    local s = K().S
    local b = K().Button(row, text, fn, opts)
    b:Dock(RIGHT)
    b:SetWide(s(150))
    b:DockMargin(s(6), 0, 0, 0)
    return b
end

-- "YYYY-MM-DD" -> os.time (start or end of that day), or nil.
function T.ParseDate(txt, endOfDay)
    local y, mo, d = string.match(txt or "", "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = 0 })
end

--------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------

local function bansTab(body)
    local k = K()
    local s = k.S
    local h = k.Heading(body, "Banned from uploading")
    h:Dock(TOP)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #T.term.bans == 0 then label(sp, "Nobody is banned.") end
    for _, b in ipairs(T.term.bans) do
        local r = k.Row(sp, b.name, b.sid)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        r.right:SetWide(s(110))
        local u = k.Button(r.right, "Unban", function()
            send("dp.tunban", function() net.WriteString(b.sid) end)
        end, { small = true })
        u:Dock(FILL)
    end
end

D.TermAddTab("bans", {
    order = 100,
    name = function(tm) return "Bans (" .. #tm.bans .. ")" end,
    has = function(tm) return tm.mod end,
    build = bansTab,
})

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

-- The tabs this player gets, in order: { id, label, build(body), highlight }.
local function tabs()
    local list = {}
    for _, def in pairs(T.tabs) do
        if not def.has or def.has(T.term) then list[#list + 1] = def end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    local out = {}
    for i, def in ipairs(list) do
        local name = isfunction(def.name) and def.name(T.term) or def.name or def.id
        out[i] = { def.id, name, def.build, def.accent and def.accent(T.term) or nil }
    end
    return out
end

function T.Build()
    local k = K()
    if not IsValid(T.panel) or not T.term then return end
    local s = k.S
    T.panel.body:Clear()
    local body = T.panel.body

    -- Top bar: upload, set battalion; tabs on the right.
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(32))
    top:DockMargin(0, 0, 0, s(10))
    top.Paint = nil
    local function topButton(text, fn, opts, side)
        local b = k.Button(top, text, fn, opts)
        b:Dock(side or LEFT)
        surface.SetFont(k.Font(13, 700))
        b:SetWide(surface.GetTextSize(string.upper(text)) + s(34))
        if side == RIGHT then b:DockMargin(s(6), 0, 0, 0) else b:DockMargin(0, 0, s(6), 0) end
        return b
    end
    local n = T.term.upload
    topButton(n > 0 and ("Upload " .. n .. " note" .. (n == 1 and "" or "s")) or "Nothing to upload", function()
        send("dp.tup")
    end, { accent = true, enabled = n > 0 and not T.term.banned })
    if T.term.admin and not T.term.med and T.term.bn == "" then
        topButton("Set battalion", function()
            local m = k.Menu()
            local cats = DarkRP and DarkRP.getCategories and DarkRP.getCategories().jobs or {}
            for _, c in ipairs(cats) do
                if c.name then
                    m:AddOption(c.name, function() send("dp.tset", function() net.WriteString(c.name) end) end)
                end
            end
            m:AddOption("Type a name…", function()
                k.Prompt("Battalion", "The DarkRP job category this computer belongs to", T.term.bn, function(t)
                    send("dp.tset", function() net.WriteString(t) end)
                end)
            end)
            m:Open()
        end)
    end
    if T.term.banned then
        local l = k.Label(top, "You're banned from uploading here", 13, 700, k.C.bad)
        l:Dock(LEFT)
        l:DockMargin(s(8), s(8), 0, 0)
        l:SetWide(s(260))
    end

    if not T.term.med and T.term.bn == "" then
        label(body, "This computer has no battalion yet. An admin sets it with Set battalion.", k.C.warn, 14)
        return
    end
    if not T.term.view then
        label(body, T.term.med and "Medical records are for medics only." or
            ("This is the " .. T.term.bn .. " battalion's computer. Only its members can read it."), nil, 14)
        if not T.term.med and T.ApplyPanel then T.ApplyPanel(body) end
        return
    end
    if not T.term.med and T.AskUnit then T.AskUnit() end

    local list = tabs()
    local valid = false
    for _, t in ipairs(list) do
        if t[1] == T.tab then valid = true end
    end
    if not valid then T.tab = "logs" end
    for i = #list, 1, -1 do
        local t = list[i]
        topButton(t[2], function()
            T.tab = t[1]
            T.Build()
        end, { selected = function() return T.tab == t[1] end, accent = t[4] }, RIGHT)
    end

    for _, t in ipairs(list) do
        if t[1] == T.tab then t[3](body) end
    end
end

local function open()
    local k = K()
    if not k then return end
    local s = k.S
    if not IsValid(T.panel) then
        T.panel = vgui.Create("EditablePanel")
        T.panel:SetSize(s(1180), s(680))
        T.panel:Center()
        T.panel:MakePopup()
        T.panel:DockPadding(s(14), s(52), s(14), s(14))
        function T.panel:Paint(w, h)
            if not T.term then return end
            local title = T.term.med and "Medical holotable" or (T.term.bn ~= "" and (T.term.bn .. " computer") or "Battalion computer")
            -- Fully opaque: the text must stay readable whatever is behind the screen.
            k.Plate(0, 0, w, h, { title = title, sub = T.term.foreign and "Admin inspection" or (T.term.med and "Medical records" or "Battalion"),
                ticks = "all", header = s(38), bg = OPAQUE })
        end
        -- The battalion's colour as the accent.
        k.Tint(T.panel, function() return T.term and not T.term.med and D.BnColor(T.term.bn) or nil end)
        function T.panel:Think()
            local r = D.Cfg("useRange") + 20
            if not T.term or not IsValid(T.term.ent) or LocalPlayer():GetPos():DistToSqr(T.term.ent:GetPos()) > r * r then self:Remove() end
        end
        local close = k.Button(T.panel, "Close", function() T.panel:Remove() end, { small = true })
        close:Dock(BOTTOM)
        close:DockMargin(0, s(10), 0, 0)
        T.panel.body = vgui.Create("DPanel", T.panel)
        T.panel.body:Dock(FILL)
        T.panel.body.Paint = nil
        if Rhylib.Menus.RegisterCloser then
            Rhylib.Menus.RegisterCloser("datapad.term", function()
                if IsValid(T.panel) then T.panel:Remove() return true end
                return false
            end)
        end
    end
    T.Build()
end

Rhylib.Net.Receive("dp.term", function()
    local t = { entries = {}, bans = {} }
    t.ent = net.ReadEntity()
    t.bn = net.ReadString()
    t.view = net.ReadBool()
    t.mod = net.ReadBool()
    t.admin = net.ReadBool()
    t.foreign = net.ReadBool()
    t.banned = net.ReadBool()
    t.upload = net.ReadUInt(8)
    for i = 1, net.ReadUInt(8) do
        t.entries[i] = { id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), pn = net.ReadString(), t = net.ReadUInt(32), mp = net.ReadBool() }
    end
    for i = 1, net.ReadUInt(8) do
        t.bans[i] = { sid = net.ReadString(), name = net.ReadString() }
    end
    if not IsValid(t.ent) then return end
    t.med = t.ent:GetClass() == "rhylib_med_holotable"
    -- A different computer (or newly opened): every tab starts fresh.
    if not T.term or T.term.ent ~= t.ent or not IsValid(T.panel) then
        T.tab = "logs"
        for _, def in pairs(T.tabs) do
            if def.reset then def.reset() end
        end
    end
    T.term = t
    for _, def in pairs(T.tabs) do
        if def.onTerm then def.onTerm(t) end
    end
    open()
end)
