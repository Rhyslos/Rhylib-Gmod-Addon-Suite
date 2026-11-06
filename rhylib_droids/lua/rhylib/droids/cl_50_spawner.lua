--[[
    Droid and clone spawner settings window (client).

    D.Spawner.Window(st, presets, title, sub, onApply(st)): the window:
    squad (preset), orders, droids in all, alive at once, seconds between
    squads and, when st.running is set, running on / off. presets = list
    of preset ids (nil = the droid presets below, or the clone ones when
    st.clones is set; st.clones also makes the words say clones). Used:
      - by an admin pressing E on a placed spawner (net droids.spawner,
        sv_50_spawner.lua): Apply sends droids.spawnerset;
      - by the toolgun (rhylib_toolgun: right-click the Droid spawner tile,
        "Change spawner settings"): the settings for the next ones placed.
    Layout: a plate with the title and a line about it; left the settings
    in two bands (WHAT IT SENDS: squad and orders as buttons; NUMBERS: the
    sliders and Running), rows alternating; right a summary card (squad
    size, how many squads that makes, how long it runs, RUNNING / OFF).
    Close and Apply at the bottom.
    Esc or Close shuts it (UI closer "droids.spawner").
]]

local D = Rhylib.Droids
D.Spawner = D.Spawner or {}
local SP = D.Spawner
local UI = Rhylib.UI

local MODES = { "patrol", "roam", "attack", "guard" }
local MODE_NAMES = { patrol = "Patrol", roam = "Roam", attack = "Attack", guard = "Guard" }
local PRESETS = { "droid_small", "droid_medium", "droid_large", "droid_b2", "droid_mortar", "droid_spider", "droid_crab", "droid_commando", "droid_droideka", "droid_company", "droid_division" }
local CLONE_PRESETS = { "clone_squad", "clone_company" }
local PRESET_NAMES = { clone_squad = "Squad", clone_company = "Company", droid_small = "Small", droid_medium = "Medium", droid_large = "Large", droid_b2 = "B2s", droid_mortar = "Mortars", droid_spider = "Spider", droid_crab = "Crab", droid_commando = "Commandos", droid_droideka = "Droidekas", droid_company = "Company", droid_division = "Division" }
-- (the summary card's name where "<name> squad" reads wrong)
local CARD_NAMES = { clone_squad = "Clone squad", clone_company = "Clone company" }
-- (droids in each preset squad, for the summary)
local PRESET_SIZE = { clone_squad = 8, clone_company = 22, droid_small = 10, droid_medium = 16, droid_large = 31, droid_b2 = 8, droid_mortar = 9, droid_spider = 5, droid_crab = 5, droid_commando = 7, droid_droideka = 2, droid_company = 33, droid_division = 66 }

-- (the summary card's lines; the last: when the last squad comes out if the cap never holds it back)
local STAT_NAMES = { "Droids in all", "Alive at once", "Squads", "Last squad, earliest" }
local STAT_NAMES_CLONES = { "Clones in all", "Alive at once", "Squads", "Last squad, earliest" }

local GRAD = Material("vgui/gradient-l")
local DIA = { {}, {}, {}, {} }
local function diamond(K, cx, cy, r, col)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    K.SetCol(col)
    surface.DrawPoly(DIA)
end

local function closePanel()
    if IsValid(SP.panel) then SP.panel:Remove() return true end
    return false
end

local function mmss(t)
    t = math.max(0, math.floor(t))
    if t >= 3600 then return string.format("%d h %02d min", t / 3600, (t % 3600) / 60) end
    return string.format("%d:%02d", t / 60, t % 60)
end

function SP.Window(st, list, title, sub, onApply)
    local K = UI and UI.Kit
    if not K then return end
    local s = K.S
    local C = K.C
    closePanel()
    local clones = st.clones
    list = list or (clones and CLONE_PRESETS or PRESETS)
    local who = clones and "clones" or "droids"
    local f = vgui.Create("EditablePanel")
    SP.panel = f
    f:SetSize(math.min(ScrW() - s(40), s(980)), math.min(ScrH() - s(40), s(500)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(s(14), s(52), s(14), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title or (clones and "Clone spawner" or "Droid spawner"), sub = sub or "What it sends out · stays until destroyed or empty", ticks = "all", header = s(38) })
    end

    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(34))
    bar:DockMargin(0, s(10), 0, 0)

    -- Summary card (right)
    local card = vgui.Create("DPanel", f)
    card:Dock(RIGHT)
    card:SetWide(s(250))
    card:DockMargin(s(12), 0, 0, 0)
    card.vals = {}
    function card:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        K.SetCol(C.accent)
        surface.DrawRect(0, 0, s(3), h)
        K.Ticks(0, 0, w, h)
        local x, y = s(16), s(20)
        K.Caps("Each time", x, y)
        local size = PRESET_SIZE[st.preset]
        draw.SimpleText(CARD_NAMES[st.preset] or ((PRESET_NAMES[st.preset] or tostring(st.preset)) .. " squad"), K.Font(20, 700), x, y + s(24), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText((size and (size .. " " .. who .. " · ") or "") .. (MODE_NAMES[st.mode] or tostring(st.mode)), K.Font(13), x, y + s(46), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        y = y + s(80)
        K.SetCol(C.edgeLight)
        surface.DrawRect(x, y, w - x * 2, 1)
        y = y + s(20)
        local total, cap, gap = st.total or 0, st.cap or 0, st.interval or 0
        local squads = size and math.max(1, math.ceil(total / size)) or nil
        local vals = self.vals
        vals[1], vals[2] = total, cap
        vals[3] = squads or "—"
        vals[4] = squads and mmss((squads - 1) * gap) or "—"
        for i = 1, 4 do
            K.Caps((clones and STAT_NAMES_CLONES or STAT_NAMES)[i], x, y)
            draw.SimpleText(vals[i], K.Font(15, 700), w - x, y, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            y = y + s(26)
        end
        if st.running ~= nil then
            local on = st.running
            local col = on and C.good or C.textDim
            local t = on and "RUNNING" or "OFF"
            local cf = K.Font(11, 700)
            surface.SetFont(cf)
            local tw = surface.GetTextSize(t)
            local cw, chh = tw + s(14), s(20)
            local cy = h - s(18) - chh
            K.SetCol(col, 40)
            surface.DrawRect(x, cy, cw, chh)
            K.SetCol(col, 170)
            surface.DrawOutlinedRect(x, cy, cw, chh)
            draw.SimpleText(t, cf, x + cw * 0.5, cy + chh * 0.5, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body.Paint = nil

    local function band(text)
        local caps = string.upper(text)
        local p = vgui.Create("DPanel", body)
        p:Dock(TOP)
        p:SetTall(s(30))
        p:DockMargin(0, 0, 0, s(4))
        function p:Paint(w, h)
            K.SetCol(C.accent, 30)
            surface.SetMaterial(GRAD)
            surface.DrawTexturedRect(0, 0, w * 0.7, h)
            K.SetCol(C.accent)
            surface.DrawRect(0, 0, s(3), h)
            diamond(K, s(16), h * 0.5, s(5), C.accent)
            draw.SimpleText(caps, K.Font(13, 700), s(28), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local n = 0
    local function row(t, desc)
        n = n + 1
        local alt = n % 2 == 0
        local r = vgui.Create("DPanel", body)
        r:Dock(TOP)
        r:SetTall(desc and s(48) or s(38))
        r:DockMargin(0, 0, 0, s(2))
        r:DockPadding(s(12), s(7), s(10), s(7))
        function r:Paint(w, h)
            K.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(t, K.Font(14, 500), s(12), desc and h * 0.36 or h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if desc then draw.SimpleText(K.Fit(desc, K.Font(12), w - self.right:GetWide() - s(30)), K.Font(12), s(12), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end
        r.right = vgui.Create("DPanel", r)
        r.right:Dock(RIGHT)
        r.right.Paint = nil
        return r
    end
    -- Buttons that share the width evenly (left to right).
    local function seg(r, opts, get, set, wide)
        r.right:SetWide(wide)
        local p = r.right
        for _, o in ipairs(opts) do
            K.Button(p, o[2], function() set(o[1]) end, { small = true, selected = function() return get() == o[1] end })
        end
        function p:PerformLayout(w, h)
            local kids = self:GetChildren()
            local gap = s(4)
            local bw = (w - gap * (#kids - 1)) / math.max(1, #kids)
            for i, b in ipairs(kids) do
                b:SetPos(math.floor((i - 1) * (bw + gap)), math.floor((h - b:GetTall()) * 0.5))
                b:SetWide(math.floor(bw))
            end
        end
    end

    band("What it sends")
    local opts = {}
    local sizes = {}
    for _, name in ipairs(list) do
        opts[#opts + 1] = { name, PRESET_NAMES[name] or name }
        if PRESET_SIZE[name] then sizes[#sizes + 1] = (PRESET_NAMES[name] or name) .. " " .. PRESET_SIZE[name] end
    end
    local r = row("Squad", #sizes > 0 and table.concat(sizes, " · ") or nil)
    -- (80 per option, at most half the window: seven presets fit at 4:3)
    seg(r, opts, function() return st.preset end, function(v) st.preset = v end, math.min(s(80 * #opts), math.floor(f:GetWide() * 0.5)))
    local mopts = {}
    for _, m in ipairs(MODES) do mopts[#mopts + 1] = { m, MODE_NAMES[m] } end
    r = row("Orders", clones and "Patrol and Roam come out as groups; Attack hunts the nearest droids" or "Patrol and Roam come out as groups; Attack hunts the nearest players")
    seg(r, mopts, function() return st.mode end, function(v) st.mode = v end, s(300))

    local b2 = vgui.Create("DPanel", body)
    b2:Dock(TOP)
    b2:SetTall(s(8))
    b2.Paint = nil
    band("Numbers")
    local function slider(t, desc, key, lo, hi)
        local rr = row(t, desc)
        rr.right:SetWide(s(260))
        K.Slider(rr.right, lo, hi, 0, function() return st[key] end, function(v) st[key] = math.Round(v) end):Dock(FILL)
    end
    slider(clones and "Clones in all" or "Droids in all", "A new number starts the count again", "total", 10, 500)
    slider("Alive at once", "It waits until a whole squad fits under this", "cap", 1, 100)
    slider("Seconds between squads", nil, "interval", 5, 300)
    if st.running ~= nil then
        r = row("Running", "Off: it sends nothing until turned back on")
        r.right:SetWide(s(70))
        K.Toggle(r.right, function() return st.running end, function(v) st.running = v end):Dock(RIGHT)
    end

    local close = K.Button(bar, "Close", function() closePanel() end)
    close:Dock(RIGHT)
    close:SetWide(s(120))
    local apply = K.Button(bar, "Apply", function()
        st.total = math.Clamp(math.floor(st.total or 60), 1, 1000)
        st.cap = math.Clamp(math.floor(st.cap or 20), 1, 100)
        st.interval = math.Clamp(math.floor(st.interval or 30), 5, 600)
        onApply(st)
        closePanel()
    end, { accent = true })
    apply:Dock(RIGHT)
    apply:SetWide(s(140))
    apply:DockMargin(0, 0, s(8), 0)
end

-- E on a placed spawner (admins).
Rhylib.Net.Receive("droids.spawner", function()
    local ent = net.ReadEntity()
    local st = { preset = net.ReadString(), total = net.ReadUInt(10), cap = net.ReadUInt(7), interval = net.ReadUInt(10),
        mode = MODES[net.ReadUInt(3)] or "patrol", running = net.ReadBool(), clones = IsValid(ent) and ent.Clones or nil }
    local list = {}
    for i = 1, net.ReadUInt(4) do list[i] = net.ReadString() end
    if not IsValid(ent) then return end
    SP.Window(st, #list > 0 and list or nil, st.clones and "Clone spawner" or "Droid spawner", nil, function(v)
        if not IsValid(ent) then return end
        Rhylib.Net.Start("droids.spawnerset")
        net.WriteEntity(ent)
        net.WriteString(v.preset)
        net.WriteUInt(v.total, 10)
        net.WriteUInt(v.cap, 7)
        net.WriteUInt(v.interval, 10)
        local mi = 1
        for i, m in ipairs(MODES) do if m == v.mode then mi = i end end
        net.WriteUInt(mi, 3)
        net.WriteBool(v.running)
        net.SendToServer()
    end)
end)

if UI and UI.RegisterCloser then UI.RegisterCloser("droids.spawner", closePanel) end
