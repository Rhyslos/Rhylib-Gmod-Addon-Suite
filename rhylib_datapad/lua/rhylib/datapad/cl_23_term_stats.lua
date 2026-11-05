--[[
    Battalion computer window, Stats tab (client): STATS title with period
    chips (today, this week, last week, this month, all time), a row of
    total tiles, then the members table; click a column to sort. State in SS; registered with D.TermAddTab.
      dp.stats -> dp.statsr (D.ReadStatRow, sh_00_config.lua)
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)
local C = T.C

local SS = { statsPeriod = 2, statsData = nil, statsSort = "mi" }
local PERIOD_NAMES = { "Today", "This week", "Last week", "This month", "All time" }

-- Stats shown: MP battalions count arrests made, the others times arrested.
local function shownKeys() return D.StatKeysShown(D.IsMPBattalion(T.term and T.term.bn or "")) end

local function statsTab(body)
    local k = T.K()
    local s = k.S
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(40))
    bar:DockMargin(0, 0, 0, s(14))
    bar.Paint = nil
    T.Title(bar, "Stats"):Dock(LEFT)
    local opts = {}
    for i, n in ipairs(PERIOD_NAMES) do opts[i] = { i, n } end
    local ch = T.Chips(bar, opts, function() return SS.statsPeriod end, function(v)
        SS.statsPeriod = v
        SS.statsData = nil
        T.Build()
    end)
    ch:Dock(LEFT)
    ch:DockMargin(s(4), s(4), 0, s(4))

    if not SS.statsData or SS.statsData.period ~= SS.statsPeriod then
        T.Empty(body, "Loading…")
        if not (SS.statsData and SS.statsData.pending == SS.statsPeriod) then
            SS.statsData = { pending = SS.statsPeriod }
            T.Send("dp.stats", function() net.WriteUInt(SS.statsPeriod, 3) end)
        end
        return
    end

    local SHOWN = shownKeys()   -- (the stat ids this battalion shows)

    -- Totals: one tile per stat.
    local tiles = vgui.Create("DPanel", body)
    tiles:Dock(TOP)
    tiles:SetTall(s(72))
    tiles:DockMargin(0, 0, 0, s(16))
    local vals, names = {}, {}
    for i, key in ipairs(SHOWN) do
        vals[i] = D.StatText(key, SS.statsData.totals[key])
        names[i] = string.upper(D.STAT_NAMES[key] or key)
    end
    local fV, fK = k.Font(22, 700), k.Font(11, 600)
    function tiles:Paint(w, h)
        local n = #SHOWN
        local gap = s(8)
        local tw = (w - gap * (n - 1)) / n
        for i = 1, n do
            local x = math.floor((i - 1) * (tw + gap))
            T.SetCol(C.card)
            surface.DrawRect(x, 0, math.floor(tw), h)
            T.SetCol(C.edge)
            surface.DrawOutlinedRect(x, 0, math.floor(tw), h)
            draw.SimpleText(vals[i], fV, x + s(14), s(10), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(names[i], fK, x + s(14), h - s(10), C.caps, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end
    end

    -- Members: click a column to sort by it.
    local head = vgui.Create("DPanel", body)
    head:Dock(TOP)
    head:SetTall(s(30))
    head:DockMargin(0, 0, s(8), 0)
    function head:Paint(w, h)
        T.SetCol(C.accentOn)
        surface.DrawRect(0, 0, w, h)
        T.SetCol(C.edge)
        surface.DrawRect(0, h - 1, w, 1)
    end
    local nameW = s(200)
    local function colX(i, w) return nameW + (i - 1) * ((w - nameW) / #SHOWN) end
    local nameBtn = vgui.Create("DButton", head)
    nameBtn:SetText("")
    nameBtn:SetPos(0, 0)
    nameBtn:SetSize(nameW, s(30))
    nameBtn.Paint = function(_, w, h)
        k.Caps("Member", s(12), h * 0.5, SS.statsSort == "name" and C.accent or C.caps)
        return true
    end
    nameBtn.DoClick = function()
        SS.statsSort = "name"
        T.Build()
    end
    function head:PerformLayout(w, h)
        for i, key in ipairs(SHOWN) do
            local b = self["c" .. i]
            if not IsValid(b) then
                b = vgui.Create("DButton", self)
                b:SetText("")
                b.Paint = function(_, bw, bh)
                    k.Caps(D.STAT_NAMES[key], bw - s(12), bh * 0.5, SS.statsSort == key and C.accent or C.caps, TEXT_ALIGN_RIGHT)
                    return true
                end
                b.DoClick = function()
                    SS.statsSort = key
                    T.Build()
                end
                self["c" .. i] = b
            end
            local x0, x1 = colX(i, w), colX(i + 1, w)
            b:SetPos(x0, 0)
            b:SetSize(x1 - x0, h)
        end
    end

    local rows = {}
    for _, m in ipairs(SS.statsData.members) do rows[#rows + 1] = m end
    table.sort(rows, function(a, b)
        if SS.statsSort == "name" then return string.lower(a.name) < string.lower(b.name) end
        return (a[SS.statsSort] or 0) > (b[SS.statsSort] or 0)
    end)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #rows == 0 then T.Empty(sp, "Nothing recorded for this period yet.") end
    for i, m in ipairs(rows) do
        local r = vgui.Create("DPanel", sp)
        r:Dock(TOP)
        r:SetTall(s(32))
        r:DockMargin(0, 0, s(8), 0)
        local cells = {}
        for c, key in ipairs(SHOWN) do cells[c] = D.StatText(key, m[key]) end
        local fN, fC = k.Font(13, 700), k.Font(13)
        local nm = k.Fit(m.name, fN, nameW - s(20))
        function r:Paint(w, h)
            T.SetCol(i % 2 == 0 and C.bar or C.card)
            surface.DrawRect(0, 0, w, h)
            T.SetCol(C.edge)
            surface.DrawRect(0, h - 1, w, 1)
            draw.SimpleText(nm, fN, s(12), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            for c, key in ipairs(SHOWN) do
                draw.SimpleText(cells[c], fC, colX(c + 1, w) - s(12), h * 0.5, SS.statsSort == key and C.text or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end
end

Rhylib.Net.Receive("dp.statsr", function()
    local d = { period = net.ReadUInt(3), members = {} }
    d.totals = D.ReadStatRow()
    for i = 1, net.ReadUInt(7) do
        local name = net.ReadString()
        local m = D.ReadStatRow()
        m.name = name
        d.members[i] = m
    end
    SS.statsData = d
    if IsValid(T.panel) and T.tab == "stats" then T.Build() end
end)

D.TermAddTab("stats", {
    order = 70, name = "Stats",
    has = function(tm) return not tm.med end,
    build = statsTab,
    reset = function() SS.statsData = nil end,
})
