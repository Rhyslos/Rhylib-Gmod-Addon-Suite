--[[
    Droid spawner settings window (client).

    D.Spawner.Window(st, presets, title, sub, onApply(st)): the window:
    squad (preset), orders, droids in all, alive at once, seconds between
    squads and, when st.running is set, running on / off. presets = list
    of preset ids (nil = the droid presets below). Used:
      - by an admin pressing E on a placed spawner (net droids.spawner,
        sv_50_spawner.lua): Apply sends droids.spawnerset;
      - by the toolgun (rhylib_toolgun: right-click the Droid spawner tile,
        "Change spawner settings"): the settings for the next ones placed.
    Esc or Close shuts it (UI closer "droids.spawner").
]]

local D = Rhylib.Droids
D.Spawner = D.Spawner or {}
local SP = D.Spawner

local MODES = { "patrol", "roam", "attack", "guard" }
local MODE_NAMES = { patrol = "Patrol", roam = "Roam", attack = "Attack", guard = "Guard" }
local PRESETS = { "droid_small", "droid_medium", "droid_large", "droid_b2", "droid_mortar" }
local PRESET_NAMES = { droid_small = "Small", droid_medium = "Medium", droid_large = "Large", droid_b2 = "B2s", droid_mortar = "Mortars" }

local function closePanel()
    if IsValid(SP.panel) then SP.panel:Remove() return true end
    return false
end

function SP.Window(st, list, title, sub, onApply)
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then return end
    local s = K.S
    closePanel()
    list = list or PRESETS
    local f = vgui.Create("EditablePanel")
    SP.panel = f
    f:SetSize(s(700), s(430))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(s(14), s(52), s(14), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title or "Droid spawner", sub = sub or "What it sends out · stays until destroyed or empty", ticks = "all", header = s(38) })
    end
    local function row(t, desc)
        local r = K.Row(f, t, desc)
        r:Dock(TOP)
        r:DockMargin(0, 0, 0, s(4))
        return r
    end
    local opts = {}
    for _, name in ipairs(list) do opts[#opts + 1] = { name, PRESET_NAMES[name] or name } end
    local r = row("Squad", "Small 10 · Medium 16 · Large 31 · B2s 8 · Mortars 9")
    r.right:SetWide(s(400))
    K.Choices(r.right, opts, function() return st.preset end, function(v) st.preset = v end):Dock(FILL)
    local mopts = {}
    for _, m in ipairs(MODES) do mopts[#mopts + 1] = { m, MODE_NAMES[m] } end
    r = row("Orders", "Patrol and Roam come out as groups; Attack hunts the nearest players")
    r.right:SetWide(s(300))
    K.Choices(r.right, mopts, function() return st.mode end, function(v) st.mode = v end):Dock(FILL)
    local function slider(t, desc, key, lo, hi)
        local rr = row(t, desc)
        rr.right:SetWide(s(240))
        K.Slider(rr.right, lo, hi, 0, function() return st[key] end, function(v) st[key] = math.Round(v) end):Dock(FILL)
    end
    slider("Droids in all", "A new number starts the count again", "total", 10, 500)
    slider("Alive at once", "It waits until a whole squad fits under this", "cap", 1, 100)
    slider("Seconds between squads", nil, "interval", 5, 300)
    if st.running ~= nil then
        r = row("Running", "Off: it sends nothing until turned back on")
        r.right:SetWide(s(70))
        K.Toggle(r.right, function() return st.running end, function(v) st.running = v end):Dock(RIGHT)
    end
    local bar = vgui.Create("DPanel", f)
    bar.Paint = nil
    bar:Dock(BOTTOM)
    bar:SetTall(s(34))
    local close = K.Button(bar, "Close", function() closePanel() end)
    close:Dock(RIGHT)
    close:SetWide(s(110))
    local apply = K.Button(bar, "Apply", function()
        st.total = math.Clamp(math.floor(st.total or 60), 1, 1000)
        st.cap = math.Clamp(math.floor(st.cap or 20), 1, 100)
        st.interval = math.Clamp(math.floor(st.interval or 30), 5, 600)
        onApply(st)
        closePanel()
    end, { accent = true })
    apply:Dock(RIGHT)
    apply:SetWide(s(110))
    apply:DockMargin(0, 0, s(8), 0)
end

-- E on a placed spawner (admins).
Rhylib.Net.Receive("droids.spawner", function()
    local ent = net.ReadEntity()
    local st = { preset = net.ReadString(), total = net.ReadUInt(10), cap = net.ReadUInt(7), interval = net.ReadUInt(10),
        mode = MODES[net.ReadUInt(3)] or "patrol", running = net.ReadBool() }
    local list = {}
    for i = 1, net.ReadUInt(4) do list[i] = net.ReadString() end
    if not IsValid(ent) then return end
    SP.Window(st, #list > 0 and list or nil, "Droid spawner", nil, function(v)
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

local UI = Rhylib.UI
if UI and UI.RegisterCloser then UI.RegisterCloser("droids.spawner", closePanel) end
