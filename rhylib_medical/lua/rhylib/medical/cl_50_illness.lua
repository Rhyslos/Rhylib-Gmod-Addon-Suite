--[[
    Illness (client): symptoms on screen, the analyser window, the dose
    window, test strips (inventory right-click) and the interaction wheel
    options (draw blood, give medicine; staff: infect / cure).

    Public: Med.LooksIll, Med.IllSigns, Med.OpenAnalyser.
    Hooks used: Rhylib.WheelOptions / Rhylib.WheelEntityOptions
    (rhylib_menus), Rhylib.ItemMenu (rhylib_inventory right-click).
    The windows need rhylib_menus' Kit; without it they don't open.
]]

local Med = Rhylib.Medical

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local function Inv() return Rhylib.Inventory end
-- (item uid size; rhylib_inventory may be missing: the illness flow then does nothing)
local function uidBits() return Rhylib.Items and Rhylib.Items.UID_BITS or 16 end

local function carried(id)
    local I = Inv()
    if not (I and I.byUid) then return 0 end
    local n = 0
    for _, o in pairs(I.byUid) do
        if o.id == id then n = n + (o.count or 1) end
    end
    return n
end

local function chemist(ply) return Med.Skill(ply, "chem_bench") end

-- Med.LooksIll(ply): true if ply shows signs of an illness (stage 1+).
-- Medics can tell someone is ill (not what it is: that takes a blood test).
function Med.LooksIll(ply)
    local kind, stage = Med.IllState(ply)
    return kind > 0 and stage > 0
end

-- Med.IllSigns(ply): a short text and the stage (1-3), or nil if not ill.
local SIGNS = { "Looks a little off", "Looks sick: coughing, pale", "Looks very ill" }
function Med.IllSigns(ply)
    local kind, stage = Med.IllState(ply)
    if kind == 0 or stage == 0 then return nil end
    return SIGNS[stage], stage
end


local function progress(text, secs)
    local M = Rhylib.Menus
    if M and M.WheelProgress then M.WheelProgress(text, secs) end
end

-- A timed step was cancelled (uid: an analyser sample, 0 = something else).
net.Receive(Rhylib.Net.Name("ill.stop"), function()
    local uid = net.ReadUInt(uidBits())
    if uid > 0 then
        Med.scanning[uid] = nil
        return
    end
    local M = Rhylib.Menus
    if M and M.WheelProgressStop then M.WheelProgressStop() end
end)

--------------------------------------------------------------------------
-- Symptoms: a tinted pulse at the screen edges, blur after an overdose
--------------------------------------------------------------------------

local GRAD_U, GRAD_D = Material("vgui/gradient-u"), Material("vgui/gradient-d")
local GRAD_L, GRAD_R = Material("vgui/gradient-l"), Material("vgui/gradient-r")

Rhylib.Hook.Add("HUDPaint", "medical.illness", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or Med.Muted(ply) then return end
    local kind, stage = Med.IllState(ply)
    local k = Med.ILL[kind]
    if not k or stage < 2 then return end
    -- (a slow wave every few seconds; stronger at stage 3)
    local wave = math.max(0, math.sin(CurTime() * 0.9)) ^ 4
    local a = wave * (stage == 3 and 70 or 40)
    if a < 1 then return end
    local w, h = ScrW(), ScrH()
    local e = math.floor(h * 0.18)
    surface.SetDrawColor(k.col.r, k.col.g, k.col.b, a)
    surface.SetMaterial(GRAD_D) surface.DrawTexturedRect(0, 0, w, e)
    surface.SetMaterial(GRAD_U) surface.DrawTexturedRect(0, h - e, w, e)
    surface.SetMaterial(GRAD_R) surface.DrawTexturedRect(0, 0, e, h)
    surface.SetMaterial(GRAD_L) surface.DrawTexturedRect(w - e, 0, e, h)
end)

Rhylib.Hook.Add("RenderScreenspaceEffects", "medical.overdose", function()
    local ply = LocalPlayer()
    if IsValid(ply) and Med.Overdosed(ply) then DrawMotionBlur(0.12, 0.85, 0.01) end
end)

--------------------------------------------------------------------------
-- Analyser window
--------------------------------------------------------------------------

Med.scanning = Med.scanning or {}   -- [uid] = when it should be done
local anWin

local function samples()
    local out = {}
    local I = Inv()
    for uid, o in pairs(I and I.byUid or {}) do
        if o.id == Med.SAMPLE then out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return a.uid < b.uid end)
    return out
end

local function analysed(o)
    local n = o.data and o.data.note or ""
    return string.find(n, "dose ~", 1, true) ~= nil or string.find(n, "no infection", 1, true) ~= nil
end

local function openAnalyser(ent)
    local Kit = K()
    if not Kit then return end
    if IsValid(anWin) then anWin:Remove() end
    local S = Kit.S
    local f = vgui.Create("EditablePanel")
    anWin = f
    Rhylib.Menus.prompts[f] = true   -- (Esc closes it)
    f.OnRemove = function(self) Rhylib.Menus.prompts[self] = nil end
    f:SetSize(S(460), S(360))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(S(12), S(48), S(12), S(12))
    function f:Paint(w, h)
        Kit.Plate(0, 0, w, h, { title = "Blood analyser", sub = "Chemistry bench", ticks = "all", header = S(34) })
    end
    local sc = Kit.Scroll(f)
    sc:Dock(FILL)
    local shown
    local function fill()
        sc:Clear()
        local list = samples()
        shown = #list
        if #list == 0 then
            local l = Kit.Label(sc, "You carry no blood samples. Draw blood from a patient on a med sofa (interaction wheel).", 14, nil, Kit.C.textDim)
            l:Dock(TOP)
        end
        for _, o in ipairs(list) do
            local row = Kit.Row(sc, (o.data and o.data.note) or "Blood sample")
            row:Dock(TOP)
            row:DockMargin(0, 0, S(6), S(4))
            row.right:SetWide(S(110))
            local uid = o.uid
            local done = analysed(o)
            local function running()
                local t = Med.scanning[uid]
                return t and RealTime() < t + 1 and t or nil
            end
            local b = Kit.Button(row.right, function()
                if done then return "Done" end
                local t = running()
                return t and (math.max(0, math.ceil(t - RealTime())) .. " s") or "Analyse"
            end, function()
                if not IsValid(ent) then return end
                Rhylib.Net.Start("ill.scan")
                net.WriteEntity(ent)
                net.WriteUInt(uid, uidBits())
                net.SendToServer()
                Med.scanning[uid] = RealTime() + Med.Cfg("scanTime") * (chemist(LocalPlayer()) and 0.5 or 1)
            end, { small = true, accent = true, enabled = function() return not done and not running() end })
            b:Dock(FILL)
        end
    end
    fill()
    local last = ""
    function f:Think()
        if not IsValid(ent) or LocalPlayer():GetPos():DistToSqr(ent:GetPos()) > 220 * 220 then self:Remove() return end
        -- (rebuilt when a sample comes, goes or gets its result)
        local key = ""
        for _, o in ipairs(samples()) do key = key .. o.uid .. ":" .. tostring(o.data and o.data.note) .. ";" end
        if key ~= last then
            last = key
            fill()
        end
    end
end

-- Med.OpenAnalyser(bench): opens the blood analyser window for that bench
-- (lists your samples; "Analyse" sends ill.scan). Client only.
Med.OpenAnalyser = openAnalyser

net.Receive(Rhylib.Net.Name("ill.open"), function()
    local ent = net.ReadEntity()
    if IsValid(ent) then openAnalyser(ent) end
end)

-- The bench on the interaction wheel: analyser or crafting.
Rhylib.Hook.Add("Rhylib.WheelEntityOptions", "medical.bench", function(ent, me, add)
    if ent:GetClass() ~= "rhylib_chem_bench" then return end
    if Med.Simple() then
        add("Chemistry bench", nil, { disabled = "Not used in the simplified medical system" })
        return
    end
    if not Med.IsMedic(me) then
        add("Chemistry bench", nil, { disabled = "Medics only" })
        return
    end
    add("Blood analyser", function(e) openAnalyser(e) end, { order = 10, sub = "Analyse your blood samples" })
    if Med.Skill(me, "chem_bench") then
        add("Crafting", function(e)
            Rhylib.Net.Start("chem.use")
            net.WriteEntity(e)
            net.SendToServer()
        end, { order = 11, sub = "Supplies into kits and medicine" })
    else
        add("Crafting", nil, { order = 11, disabled = "Needs the Chemistry skill" })
    end
end)

--------------------------------------------------------------------------
-- Test strip: right-click a sample to put it on a strip; the used strip
-- shows an assay readout that develops (control channel: the test works; a
-- lit test channel: infected, and its colour says what with; it lights at
-- once when developed, with a beep). Right-click
-- samples and used strips to throw them away.
--------------------------------------------------------------------------

local function send(name, uid)
    Rhylib.Net.Start(name)
    net.WriteUInt(uid, uidBits())
    net.SendToServer()
end

Rhylib.Hook.Add("Rhylib.ItemMenu", "medical.strip", function(inst, menu)
    if (inst.id == Med.SAMPLE or inst.id == Med.CASSETTE) and Med.Simple() then
        menu:AddOption("Throw away", function() send("ill.discard", inst.uid) end)   -- (simplified: nothing else)
        return
    end
    if inst.id == Med.SAMPLE then
        local note = inst.data and inst.data.note or ""
        if string.find(note, "no strip yet", 1, true) then
            if carried(Med.STRIP) < 1 then
                menu:AddOption("Apply to a test strip (you have none)", function() end)
            else
                menu:AddOption("Apply to a test strip", function() send("ill.strip", inst.uid) end)
            end
        end
        menu:AddOption("Throw away", function() send("ill.discard", inst.uid) end)
    elseif inst.id == Med.CASSETTE then
        menu:AddOption("Look at the result", function() send("ill.look", inst.uid) end)
        menu:AddOption("Throw away", function() send("ill.discard", inst.uid) end)
    end
end)

-- The test as an assay readout in the house style: a control channel that
-- lights on every test and a test channel that lights in the kind's colour.
local casWin
local SEGS = 16
local COL_TRACK, COL_OFF = Color(8, 9, 9, 255), Color(30, 33, 31, 255)

-- A segmented channel; a = 0-1 how lit, col its colour.
local function channel(Kit, x, y, w, h, col, a)
    local C = Kit.C
    Kit.SetCol(COL_TRACK)
    surface.DrawRect(x, y, w, h)
    Kit.SetCol(C.edgeDark)
    surface.DrawOutlinedRect(x, y, w, h)
    local gap = Kit.S(2)
    local sw = (w - 4 - gap * (SEGS - 1)) / SEGS
    for i = 0, SEGS - 1 do
        local sx = math.floor(x + 2 + i * (sw + gap))
        local nx = math.floor(x + 2 + (i + 1) * (sw + gap)) - gap
        Kit.SetCol(COL_OFF)
        surface.DrawRect(sx, y + 2, nx - sx, h - 4)
        if a > 0 then
            Kit.SetCol(col, 255 * a)
            surface.DrawRect(sx, y + 2, nx - sx, h - 4)
        end
    end
end

local function mmss(t)
    t = math.max(0, math.floor(t))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

local function openCassette(info)
    local Kit = K()
    if not Kit then return end
    if IsValid(casWin) then casWin:Remove() end
    local S = Kit.S
    local C = Kit.C
    local f = vgui.Create("EditablePanel")
    casWin = f
    Rhylib.Menus.prompts[f] = true
    f.OnRemove = function(self) Rhylib.Menus.prompts[self] = nil end
    f:SetSize(S(560), S(312))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    local got = RealTime()
    local k = Med.ILL[info.kind]
    function f:Paint(w, h)
        local top = Kit.Plate(0, 0, w, h, { title = "Test strip", sub = info.who, ticks = "all", header = S(34) })
        local elapsed = info.elapsed + (RealTime() - got)
        local done = elapsed >= info.dev

        -- Readout panel (left)
        local px, py, pw, ph = S(14), top + S(14), S(320), S(188)
        Kit.SetCol(C.row)
        surface.DrawRect(px, py, pw, ph)
        Kit.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(px, py, pw, ph)
        Kit.SetCol(C.edgeLight)
        surface.DrawLine(px + 1, py + 1, px + pw - 1, py + 1)
        Kit.Caps("Assay", px + S(12), py + S(16), C.label)
        draw.SimpleText(done and "DEVELOPED" or "DEVELOPING", Kit.Font(12, 700), px + pw - S(12), py + S(16),
            done and C.text or C.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        local lx, tx, tw, th = px + S(12), px + S(92), pw - S(104), S(18)
        -- Control: lights after a few seconds on every test.
        local cA = math.Clamp((elapsed - 5) / 5, 0, 1)
        Kit.Caps("Control", lx, py + S(52), C.textDim)
        channel(Kit, tx, py + S(43), tw, th, C.text, cA * 0.85)
        -- Test: lights all at once when it has developed (brighter for a heavier infection).
        local tA = 0
        if k and done then tA = 0.45 + 0.55 * info.load / 100 end
        Kit.Caps("Test", lx, py + S(88), C.textDim)
        channel(Kit, tx, py + S(79), tw, th, k and k.col or C.text, tA)

        -- Sample flow and time
        local fy = py + S(124)
        Kit.Caps("Flow", lx, fy + S(4), C.textDim)
        local soak = math.Clamp(elapsed / 6, 0, 1)
        Kit.SetCol(COL_TRACK)
        surface.DrawRect(tx, fy, tw, S(8))
        Kit.SetCol(C.accent, 200)
        surface.DrawRect(tx, fy, tw * soak, S(8))
        Kit.Caps("Time", lx, fy + S(32), C.textDim)
        local tf = math.Clamp(elapsed / info.max, 0, 1)
        Kit.SetCol(COL_TRACK)
        surface.DrawRect(tx, fy + S(28), tw, S(8))
        Kit.SetCol(done and C.text or C.accent, 200)
        surface.DrawRect(tx, fy + S(28), done and tw or tw * tf, S(8))
        draw.SimpleText(mmss(elapsed) .. " / up to " .. mmss(info.max), Kit.Font(12), tx + tw, fy + S(44),
            C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

        -- Key (right)
        local kx, ky = px + pw + S(18), py
        Kit.Caps("Reading the strip", kx, ky + S(16), C.label)
        draw.SimpleText("Control lit: the test works", Kit.Font(13), kx, ky + S(36), C.textDim)
        draw.SimpleText("Test lit: infected", Kit.Font(13), kx, ky + S(55), C.textDim)
        draw.SimpleText("Test dark: clean", Kit.Font(13), kx, ky + S(74), C.textDim)
        Kit.Caps("Test colour", kx, ky + S(108), C.label)
        for i = 1, 3 do
            local kk = Med.ILL[i]
            local ry = ky + S(122) + (i - 1) * S(20)
            Kit.SetCol(kk.col)
            surface.DrawRect(kx, ry + S(3), S(12), S(12))
            Kit.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(kx, ry + S(3), S(12), S(12))
            draw.SimpleText(kk.colour .. " · " .. kk.id, Kit.Font(13), kx + S(20), ry, C.textDim)
        end

        -- Next steps
        local ny = py + ph + S(16)
        Kit.SetCol(C.edgeLight)
        surface.DrawRect(px, ny, w - px * 2, 1)
        draw.SimpleText("While it develops: write the patient's record on your datapad.", Kit.Font(13), px, ny + S(12), C.textDim)
        draw.SimpleText("Then bring this strip and the sample to the analyser for the dose.", Kit.Font(13), px, ny + S(32), C.textDim)
    end
end

-- Beep at the start and when the result is in (window open or not).
net.Receive(Rhylib.Net.Name("ill.beep"), function()
    local done, who = net.ReadBool(), net.ReadString()
    local me = LocalPlayer()
    if IsValid(me) then me:EmitSound("buttons/blip1.wav", 75, done and 125 or 100, 0.7, CHAN_STATIC) end
    if done and Med.ShowNote then Med.ShowNote("Test strip ready" .. (who ~= "" and (": " .. who) or "")) end
end)

net.Receive(Rhylib.Net.Name("ill.cass"), function()
    local info = { uid = net.ReadUInt(uidBits()), who = net.ReadString(), elapsed = net.ReadUInt(16),
        dev = net.ReadUInt(10), kind = net.ReadUInt(2), load = net.ReadUInt(7) }
    info.max = Med.Cfg("stripMax") or 120
    openCassette(info)
end)

--------------------------------------------------------------------------
-- Dose window
--------------------------------------------------------------------------

local function openDose(t)
    local Kit = K()
    if not Kit then return end
    local S = Kit.S
    local f = vgui.Create("EditablePanel")
    Rhylib.Menus.prompts[f] = true
    f.OnRemove = function(self) Rhylib.Menus.prompts[self] = nil end
    f:SetSize(S(420), S(250))
    f:Center()
    f:MakePopup()
    f:DockPadding(S(12), S(48), S(12), S(12))
    local pick, units = nil, 1
    -- Your newest analysed sample from this patient fills in the dose; the
    -- medicine is your call (the strip's colour).
    -- The sample note starts with the patient's name (cut to 22 letters on
    -- the server), so the first 20 bytes are compared.
    local info
    local who = IsValid(t) and t:Nick() or ""
    for _, o in ipairs(samples()) do
        local note = o.data and o.data.note or ""
        if string.sub(note, 1, math.min(#who, 20)) == string.sub(who, 1, math.min(#who, 20)) then
            local n = tonumber(string.match(note, "dose ~(%d+)"))
            if n then units = math.Clamp(n, 1, 40) info = note end
        end
    end
    function f:Paint(w, h)
        Kit.Plate(0, 0, w, h, { title = "Give medicine", sub = IsValid(t) and t:Nick() or nil, ticks = "all", header = S(34) })
    end
    function f:Think()
        if not IsValid(t) or t:GetPos():DistToSqr(LocalPlayer():GetPos()) > 200 * 200 then self:Remove() end
    end
    local row = vgui.Create("DPanel", f)
    row:Dock(TOP)
    row:SetTall(S(34))
    row.Paint = nil
    for i, m in ipairs(Med.MEDICINES) do
        local have = carried(m[1])
        if have > 0 then
            pick = pick or i
            local b = Kit.Button(row, m[2] .. " (" .. have .. ")", function() pick = i end, { small = true, selected = function() return pick == i end })
            b:Dock(LEFT)
            b:SetWide(S(128))
            b:DockMargin(0, 0, S(6), 0)
        end
    end
    local lab = Kit.Label(f, info and ("From your sample: " .. info) or "Units: analyse a blood sample first to know the dose", 13, nil, Kit.C.textDim)
    lab:Dock(TOP)
    lab:DockMargin(0, S(12), 0, S(4))
    local sl = Kit.Slider(f, 1, 40, 0, function() return units end, function(v) units = math.Clamp(math.floor(tonumber(v) or 1), 1, 40) end)
    sl:Dock(TOP)
    sl:SetTall(S(34))
    local give = Kit.Button(f, "Give", function()
        if not (pick and IsValid(t)) then return end
        local m = Med.MEDICINES[pick]
        if carried(m[1]) < units then
            Inv().note, Inv().noteTime = "You don't carry that much", RealTime()
            return
        end
        Rhylib.Net.Start("ill.dose")
        net.WriteEntity(t)
        net.WriteUInt(pick - 1, 2)
        net.WriteUInt(units, 6)
        net.SendToServer()
        progress("Giving " .. units .. " units of " .. m[2], Med.Cfg("doseTime"))
        f:Remove()
    end, { accent = true })
    give:Dock(BOTTOM)
    give:SetTall(S(34))
end

--------------------------------------------------------------------------
-- Interaction wheel
--------------------------------------------------------------------------

Rhylib.Hook.Add("Rhylib.WheelOptions", "medical.illness", function(t, me, add)
    if Med.Simple() then return end   -- (simplified medical system: no illness)
    if Med.IsMedic(me) and not Med.IsDown(me) then
        -- (test dummies are bots that can't lie down: standing is fine for them)
        if not (Med.OnSofa(t) or t:IsBot()) then
            add("Draw blood", nil, { order = 16, disabled = "Lay them on a med sofa" })
        elseif carried(Med.BLOOD_KIT) < 1 then
            add("Draw blood", nil, { order = 16, disabled = "No blood sample kit" })
        else
            add("Draw blood", function(x)
                Rhylib.Net.Start("ill.draw")
                net.WriteEntity(x)
                net.SendToServer()
                progress("Drawing blood", Med.Cfg("drawTime") * (chemist(me) and 0.67 or 1))
            end, { order = 16, sub = Med.LooksIll(t) and "They look unwell" or "Sample for the analyser" })
        end
        local any = false
        for _, m in ipairs(Med.MEDICINES) do
            if carried(m[1]) > 0 then any = true break end
        end
        if any then
            add("Give medicine", function(x) openDose(x) end, { order = 17, sub = "Pick the medicine and dose" })
        end
    end
    -- Staff: start or end an illness (rhylib_admin).
    local A = Rhylib.Admin
    local M = Rhylib.Menus
    if A and A.Run and A.TargetWord and M and M.IsStaff and M.IsStaff() then
        add("Illness", function(x)
            local Kit = K()
            local m = Kit and Kit.Menu() or DermaMenu()
            for _, kind in ipairs({ "viral", "bacterial", "poison" }) do
                local sub = m:AddSubMenu("Infect: " .. kind)
                for _, l in ipairs({ { 20, "Light" }, { 45, "Moderate" }, { 75, "Severe" } }) do
                    sub:AddOption(l[2] .. " (" .. l[1] .. ")", function() if IsValid(x) then A.Run("infect", { A.TargetWord(x), kind, l[1] }) end end)
                end
            end
            m:AddOption("Cure", function() if IsValid(x) then A.Run("cure", { A.TargetWord(x) }) end end)
            m:Open()
        end, { order = 91, sub = "Staff: infect or cure" })
    end
end)
