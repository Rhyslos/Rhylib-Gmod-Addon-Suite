--[[
    Battalion computer window, Stats tab (client): battalion totals and
    members for a period (today, this week, last week, this month, all
    time); click a column to sort. State in SS; registered with D.TermAddTab.
      dp.stats -> dp.statsr (D.ReadStatRow, sh_00_config.lua)
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)

local SS = { statsPeriod = 2, statsData = nil, statsSort = "mi" }
local PERIOD_NAMES = { "Today", "This week", "Last week", "This month", "All time" }

-- Stats shown: MP battalions count arrests made, the others times arrested.
local function shownKeys() return D.StatKeysShown(D.IsMPBattalion(T.term and T.term.bn or "")) end

local function statsTab(body)
    local k = T.K()
    local s = k.S
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(30))
    bar:DockMargin(0, 0, 0, s(10))
    bar.Paint = nil
    local opts = {}
    for i, n in ipairs(PERIOD_NAMES) do opts[i] = { i, n } end
    local ch = k.Choices(bar, opts, function() return SS.statsPeriod end, function(v)
        SS.statsPeriod = v
        SS.statsData = nil
        T.Build()
    end)
    ch:Dock(LEFT)
    ch:SetWide(s(560))

    if not SS.statsData or SS.statsData.period ~= SS.statsPeriod then
        T.Label(body, "Loading…")
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
    tiles:SetTall(s(64))
    tiles:DockMargin(0, 0, 0, s(12))
    function tiles:Paint(w, h)
        local n = #SHOWN
        local gap = s(6)
        local tw = (w - gap * (n - 1)) / n
        for i, key in ipairs(SHOWN) do
            local x = (i - 1) * (tw + gap)
            k.Plate(x, 0, tw, h, {})
            draw.SimpleText(D.StatText(key, SS.statsData.totals[key]), k.Font(20, 700), x + tw * 0.5, h * 0.42, k.C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            k.Caps(D.STAT_NAMES[key], x + tw * 0.5, h * 0.78, k.C.label, TEXT_ALIGN_CENTER)
        end
    end

    -- Members: click a column to sort by it.
    local head = vgui.Create("DPanel", body)
    head:Dock(TOP)
    head:SetTall(s(26))
    head.Paint = nil
    local nameW = s(200)
    local function colX(i, w) return nameW + (i - 1) * ((w - nameW) / #SHOWN) end
    local nameBtn = vgui.Create("DButton", head)
    nameBtn:SetText("")
    nameBtn:SetPos(0, 0)
    nameBtn:SetSize(nameW, s(26))
    nameBtn.Paint = function(_, w, h)
        k.Caps("Member", s(8), h * 0.5, SS.statsSort == "name" and k.C.accent or k.C.label)
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
                    k.Caps(D.STAT_NAMES[key], bw - s(8), bh * 0.5, SS.statsSort == key and k.C.accent or k.C.label, TEXT_ALIGN_RIGHT)
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
    if #rows == 0 then T.Label(sp, "Nothing recorded for this period yet.") end
    for i, m in ipairs(rows) do
        local r = vgui.Create("DPanel", sp)
        r:Dock(TOP)
        r:SetTall(s(26))
        r:DockMargin(0, 0, s(8), s(2))
        function r:Paint(w, h)
            k.SetCol(i % 2 == 0 and k.C.rowAlt or k.C.row)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(k.Fit(m.name, k.Font(13, 600), nameW - s(12)), k.Font(13, 600), s(8), h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            for c, key in ipairs(SHOWN) do
                draw.SimpleText(D.StatText(key, m[key]), k.Font(13), colX(c + 1, w) - s(8), h * 0.5, SS.statsSort == key and k.C.text or k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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
