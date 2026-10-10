--[[
    Training bomb setup (client): opened from the defusal window's
    "Training setup" button. Like the GM's custom bomb: pick every part
    and module, or roll a random simplified / small / large one.
    Net eod.train (bomb, op 3 bits, JSON for op 0); eod.trainopen returns
    the bomb's current setup.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local OPAQUE = Color(14, 16, 15, 255)

local tr = { frame = nil, bomb = nil, c = nil }

-- E.TrainAct(bomb, op, json): send net eod.train. Ops: 0 build (json =
-- builder fields, same as the GM custom builder), 1 same again,
-- 2 / 3 / 4 random simplified / small / large, 5 open the setup window.
function E.TrainAct(bomb, op, js)
    if not IsValid(bomb) then return end
    Net.Start("eod.train")
    net.WriteEntity(bomb)
    net.WriteUInt(op, 3)
    if op == 0 then net.WriteString(js or "{}") end
    net.SendToServer()
end

-- E.TrainingSetup(bomb): ask the server for the setup window (it answers
-- with eod.trainopen and the bomb's current features).
function E.TrainingSetup(bomb)
    E.TrainAct(bomb, 5)
end

local function close()
    if IsValid(tr.frame) then tr.frame:Remove() end
    tr.frame = nil
end

local function hasMod(c, id) for _, m in ipairs(c.mods) do if m == id then return true end end return false end
local function toggleMod(c, id)
    for i, m in ipairs(c.mods) do if m == id then table.remove(c.mods, i) return end end
    c.mods[#c.mods + 1] = id
end

local function open(bomb, f)
    local k = K()
    if not k then return end
    close()
    local s = k.S
    local mods = {}
    for id in pairs(f.mods or {}) do mods[#mods + 1] = id end
    local c = {
        det = f.det or "timer", antiJam = f.antiJam or false, hop = f.hop or false, motion = f.motion or "none",
        lid = f.lid or false, battery = f.battery or "single", sensor = f.sensor or false, charge = f.charge or "he",
        mods = mods, timerSecs = f.timerSecs or 180,
    }
    tr.bomb, tr.c = bomb, c
    local fr = vgui.Create("EditablePanel")
    fr:SetSize(math.min(ScrW() - s(60), s(620)), math.min(ScrH() - s(60), s(820)))
    fr:Center()
    fr:MakePopup()
    fr:DockPadding(s(12), s(48), s(12), s(12))
    tr.frame = fr
    function fr:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "Training bomb · setup", ticks = "all", header = s(38), bg = OPAQUE })
    end
    function fr:Think()
        if not IsValid(tr.bomb) or LocalPlayer():GetPos():DistToSqr(tr.bomb:GetPos()) > 320 * 320 then close() end
    end
    local x = k.Button(fr, "Close", close, { small = true })
    x:SetSize(s(90), s(26))
    x:SetPos(fr:GetWide() - s(102), s(6))

    local sp = k.Scroll(fr)
    sp:Dock(FILL)

    local function heading(t)
        local h = k.Heading(sp, t)
        h:Dock(TOP)
        h:DockMargin(0, s(8), s(6), s(4))
    end
    local function buttons(list)
        local row = vgui.Create("DPanel", sp)
        row:Dock(TOP)
        row:SetTall(s(32))
        row:DockMargin(0, 0, s(8), s(4))
        row.Paint = nil
        local n = #list
        function row:PerformLayout(w)
            local bw = (w - s(4) * (n - 1)) / n
            for i, b in ipairs(self:GetChildren()) do
                b:SetPos((i - 1) * (bw + s(4)), 0)
                b:SetSize(bw, s(32))
            end
        end
        for _, b in ipairs(list) do k.Button(row, b[1], b[2], b[3]) end
    end
    local function choiceRow(title, opts, key)
        local r = k.Row(sp, title)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(2))
        local ch = k.Choices(r.right, opts, function() return c[key] end, function(v) c[key] = v end)
        ch:Dock(FILL)
    end
    local function toggleRow(title, key)
        local r = k.Row(sp, title)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(2))
        local t = k.Toggle(r.right, function() return c[key] end, function(v) c[key] = v end)
        t:Dock(RIGHT)
    end

    local l = k.Label(sp, "Nobody gets hurt: a wrong move only fails, shows why, and the bomb re-arms with the same setup.", 13, 400, k.C.textDim)
    l:Dock(TOP)
    l:DockMargin(0, 0, s(8), s(6))

    heading("Random")
    buttons({
        { "Simplified", function() E.TrainAct(bomb, 2) close() end },
        { "Small", function() E.TrainAct(bomb, 3) close() end },
        { "Large", function() E.TrainAct(bomb, 4) close() end },
        { "Same again", function() E.TrainAct(bomb, 1) close() end },
    })

    heading("Build it yourself")
    choiceRow("Detonator", { { "timer", "Timer" }, { "remote", "Remote" } }, "det")
    toggleRow("Anti-jam (remote)", "antiJam")
    toggleRow("Frequency hopping (remote)", "hop")
    choiceRow("Motion sensor", { { "none", "None" }, { "normal", "Normal" }, { "sensitive", "Sensitive" } }, "motion")
    toggleRow("Lid switch", "lid")
    choiceRow("Battery", { { "single", "Single" }, { "dual", "Dual" }, { "capacitor", "Capacitor" }, { "collapse", "Collapse" } }, "battery")
    toggleRow("Self-powered charge (cell + sensor)", "sensor")
    choiceRow("Charge", { { "he", "Explosive" }, { "gas", "Gas" }, { "virus", "Virus" } }, "charge")
    for _, m in ipairs(E.MODS) do
        local r = k.Row(sp, m.name .. " (difficulty " .. m.rank .. ")" .. (m.remote and " · remote only" or ""))
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(2))
        local t = k.Toggle(r.right, function() return hasMod(c, m.id) end, function() toggleMod(c, m.id) end)
        t:Dock(RIGHT)
    end
    local r = k.Row(sp, "Timer (seconds)")
    r:Dock(TOP)
    r:DockMargin(0, 0, s(8), s(2))
    local sl = k.Slider(r.right, 30, 900, 0, function() return c.timerSecs end, function(v) c.timerSecs = v end)
    sl:Dock(FILL)
    buttons({ { "Set it up", function()
        local t = table.Copy(c)
        if t.motion == "none" then t.motion = nil end
        E.TrainAct(bomb, 0, util.TableToJSON(t))
        close()
    end, { accent = true } } })
end

Net.Receive("eod.trainopen", function()
    local bomb = net.ReadEntity()
    local len = net.ReadUInt(16)
    local raw = net.ReadData(len)
    local js = raw and util.Decompress(raw)
    local f = js and util.JSONToTable(js)
    if istable(f) and IsValid(bomb) then open(bomb, f) end
end)

Rhylib.Hook.Add("InitPostEntity", "eod.traincloser", function()
    if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("eodtrain", function() if IsValid(tr.frame) then close() return true end end)
    end
end)
