--[[
    Illness (client): symptoms on screen, the analyser window, the dose
    window, test strips (inventory right-click) and the interaction wheel
    options (draw blood, give medicine; staff: infect / cure), and the
    datapad's "Illness guide" tab for medics (rhylib_datapad D.AddTab).

    Public: Med.LooksIll, Med.IllSigns, Med.OpenAnalyser.
    Hooks used: Rhylib.WheelOptions / Rhylib.WheelEntityOptions
    (rhylib_menus; test dummies get draw blood and give medicine standing
    up, through WheelEntityOptions), Rhylib.ItemMenu (rhylib_inventory
    right-click).
    The windows use the UI kit (rhylib_core) and close on Esc (UI.prompts).
    Look: plates with a red top edge (token "med.illness"). Analyser: your
    samples as rows (state strip: grey not analysed, blue analysing with a
    progress line, green analysed; Analyse right), a dashed box when you
    carry none. Test strip: the assay readout (control and test channels,
    flow and time bars, DEVELOPING / DEVELOPED chip), the colour key, next
    steps. Dose: medicine buttons, a box with your sample's dose, units
    (bar + typed box), Cancel / Give. Illness guide: numbered step cards
    and the strip colour key, drawn with the kit colours read while
    painting (so the datapad's screen colours and teal accent show).
]]

local Med = Rhylib.Medical

local function K() return Rhylib.UI and Rhylib.UI.Kit end
local function Inv() return Rhylib.Inventory end
-- (item uid size; rhylib_inventory may be missing: the illness flow then does nothing)
local function uidBits() return Rhylib.Items and Rhylib.Items.UID_BITS or 16 end

local UI = Rhylib.UI
-- Theme tokens (cl_11_theme.lua): the windows' red top edge and the test
-- strip's empty channel track and unlit segments.
local COL_MED = UI.Col("med.illness", 226, 75, 74)
local COL_TRACK = UI.Col("med.stripTrack", 8, 9, 9, 255)
local COL_OFF = UI.Col("med.stripOff", 30, 33, 31, 255)

-- A dashed outline (empty slots), drawn in a Paint.
local function dashed(Kit, x, y, w, h, col)
    Kit.SetCol(col)
    local dash, gap = Kit.S(6), Kit.S(4)
    for i = x, x + w - 1, dash + gap do
        local l = math.min(dash, x + w - i)
        surface.DrawRect(i, y, l, 1)
        surface.DrawRect(i, y + h - 1, l, 1)
    end
    for j = y, y + h - 1, dash + gap do
        local l = math.min(dash, y + h - j)
        surface.DrawRect(x, j, 1, l)
        surface.DrawRect(x + w - 1, j, 1, l)
    end
end

-- A small caps chip (text already upper case), left edge at x, centred on y.
local function chip(Kit, text, x, y, col, right)
    local f = Kit.Font(11, 700)
    surface.SetFont(f)
    local tw = surface.GetTextSize(text)
    local w, h = tw + Kit.S(14), Kit.S(20)
    if right then x = x - w end
    Kit.SetCol(col, 40)
    surface.DrawRect(x, y - h * 0.5, w, h)
    Kit.SetCol(col, 170)
    surface.DrawOutlinedRect(x, y - h * 0.5, w, h)
    draw.SimpleText(text, f, x + w * 0.5, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

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
Rhylib.Net.Receive("ill.stop", function()
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
    local C = Kit.C
    local f = vgui.Create("EditablePanel")
    anWin = f
    UI.prompts[f] = true   -- (Esc closes it)
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(math.min(ScrW() - S(40), S(580)), math.min(ScrH() - S(40), S(440)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(S(14), S(52), S(14), S(14))
    f.count, f.done = 0, 0
    function f:Paint(w, h)
        Kit.Plate(0, 0, w, h, { title = "Blood analyser", ticks = "all", header = S(38), rule = COL_MED })
        draw.SimpleText("Chemistry bench", Kit.Font(13), w - S(110), S(19), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local x = Kit.Button(f, "Close", function() f:Remove() end, { small = true })
    x:SetSize(S(90), S(26))
    x:SetPos(f:GetWide() - S(98), S(6))

    local head = vgui.Create("DPanel", f)
    head:Dock(TOP)
    head:SetTall(S(30))
    head:DockMargin(0, 0, 0, S(6))
    function head:Paint(w, hh)
        Kit.Caps("Your blood samples", 0, hh * 0.5)
        draw.SimpleText(f.count .. " carried · " .. f.done .. " analysed", Kit.Font(13), w, hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        Kit.SetCol(C.edgeLight)
        surface.DrawRect(0, hh - 1, w, 1)
    end
    local sc = Kit.Scroll(f)
    sc:Dock(FILL)
    local function fill()
        sc:Clear()
        local list = samples()
        f.count, f.done = #list, 0
        if #list == 0 then
            local e = vgui.Create("DPanel", sc)
            e:Dock(TOP)
            e:SetTall(S(96))
            e:DockMargin(0, S(4), S(10), 0)
            function e:Paint(w, h)
                dashed(Kit, 0, 0, w, h, C.tick)
                draw.SimpleText("You carry no blood samples", Kit.Font(15, 700), w * 0.5, h * 0.4, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText("Draw blood from a patient on a med sofa (interaction wheel).", Kit.Font(13), w * 0.5, h * 0.64, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        for i, o in ipairs(list) do
            local uid = o.uid
            local done = analysed(o)
            if done then f.done = f.done + 1 end
            local note = (o.data and o.data.note) or "Blood sample"
            local alt = i % 2 == 0
            local function running()
                local t = Med.scanning[uid]
                return t and RealTime() < t + 1 and t or nil
            end
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP)
            row:SetTall(S(54))
            row:DockMargin(0, 0, S(10), S(2))
            row:DockPadding(0, S(12), S(10), S(12))
            function row:Paint(w, h)
                local t = running()
                Kit.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
                surface.DrawRect(0, 0, w, h)
                Kit.SetCol(C.edgeDark)
                surface.DrawOutlinedRect(0, 0, w, h)
                local col = done and C.good or (t and C.accent or C.label)
                Kit.SetCol(col)
                surface.DrawRect(0, 0, S(3), h)
                local tf = Kit.Font(14, 700)
                draw.SimpleText(Kit.Fit(note, tf, w - S(160)), tf, S(14), h * 0.36, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local state = done and "ANALYSED" or (t and "ANALYSING" or "NOT ANALYSED YET")
                draw.SimpleText(state, Kit.Font(11, 700), S(14), h * 0.72, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if t and not done then
                    local dur = math.max(0.1, Med.Cfg("scanTime") * (chemist(LocalPlayer()) and 0.5 or 1))
                    local frac = math.Clamp(1 - (t - RealTime()) / dur, 0, 1)
                    Kit.SetCol(C.button)
                    surface.DrawRect(S(3), h - S(4), w - S(4), S(3))
                    Kit.SetCol(C.accent)
                    surface.DrawRect(S(3), h - S(4), math.floor((w - S(4)) * frac), S(3))
                end
            end
            local right = vgui.Create("DPanel", row)
            right:Dock(RIGHT)
            right:SetWide(S(120))
            right.Paint = nil
            local b = Kit.Button(right, function()
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

Rhylib.Net.Receive("ill.open", function()
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
    UI.prompts[f] = true
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(math.min(ScrW() - S(40), S(580)), S(330))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    local got = RealTime()
    local k = Med.ILL[info.kind]
    local x = Kit.Button(f, "Close", function() f:Remove() end, { small = true })
    x:SetSize(S(90), S(26))
    x:SetPos(f:GetWide() - S(98), S(6))
    function f:Paint(w, h)
        local top = Kit.Plate(0, 0, w, h, { title = "Test strip", ticks = "all", header = S(38), rule = COL_MED })
        draw.SimpleText(Kit.Fit(info.who or "", Kit.Font(13), w * 0.4), Kit.Font(13), w - S(110), S(19), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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
        Kit.SetCol(done and C.text or C.accent)
        surface.DrawRect(px, py, S(3), ph)
        Kit.Ticks(px, py, pw, ph)
        Kit.Caps("Assay", px + S(14), py + S(16), C.label)
        chip(Kit, done and "DEVELOPED" or "DEVELOPING", px + pw - S(10), py + S(16), done and C.text or C.accent, true)

        local lx, tx, tw, th = px + S(14), px + S(92), pw - S(104), S(18)
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
        Kit.Caps("Next", px, ny + S(20), C.label)
        draw.SimpleText("While it develops: write the patient's record on your datapad.", Kit.Font(13), px + S(52), ny + S(12), C.textDim)
        draw.SimpleText("Then bring this strip and the sample to the analyser for the dose.", Kit.Font(13), px + S(52), ny + S(32), C.textDim)
    end
end

-- Beep at the start and when the result is in (window open or not).
Rhylib.Net.Receive("ill.beep", function()
    local done, who = net.ReadBool(), net.ReadString()
    local me = LocalPlayer()
    if IsValid(me) then me:EmitSound("buttons/blip1.wav", 75, done and 125 or 100, 0.7, CHAN_STATIC) end
    if done and Med.ShowNote then Med.ShowNote("Test strip ready" .. (who ~= "" and (": " .. who) or "")) end
end)

Rhylib.Net.Receive("ill.cass", function()
    local info = { uid = net.ReadUInt(uidBits()), who = net.ReadString(), elapsed = net.ReadUInt(16),
        dev = net.ReadUInt(10), kind = net.ReadUInt(2), load = net.ReadUInt(7) }
    info.max = Med.Cfg("stripMax")
    openCassette(info)
end)

--------------------------------------------------------------------------
-- Dose window
--------------------------------------------------------------------------

local function openDose(t)
    local Kit = K()
    if not Kit then return end
    local S = Kit.S
    local C = Kit.C
    local f = vgui.Create("EditablePanel")
    UI.prompts[f] = true
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(math.min(ScrW() - S(40), S(500)), S(340))
    f:Center()
    f:MakePopup()
    f:DockPadding(S(14), S(52), S(14), S(14))
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
        Kit.Plate(0, 0, w, h, { title = "Give medicine", sub = who ~= "" and who or nil, ticks = "all", header = S(38), rule = COL_MED })
    end
    function f:Think()
        if not IsValid(t) or t:GetPos():DistToSqr(LocalPlayer():GetPos()) > 200 * 200 then self:Remove() end
    end
    local function caps(text)
        local p = vgui.Create("DPanel", f)
        p:Dock(TOP)
        p:SetTall(S(24))
        function p:Paint(w, h) Kit.Caps(text, 0, h * 0.5) end
        return p
    end
    caps("Medicine")
    local row = vgui.Create("DPanel", f)
    row:Dock(TOP)
    row:SetTall(S(34))
    row.Paint = nil
    local nMed = 0
    for i, m in ipairs(Med.MEDICINES) do
        local have = carried(m[1])
        if have > 0 then
            pick = pick or i
            nMed = nMed + 1
            Kit.Button(row, m[2] .. " (" .. have .. ")", function() pick = i end, { small = true, selected = function() return pick == i end, tooltip = m[3] })
        end
    end
    function row:PerformLayout(w, h)
        local kids = self:GetChildren()
        local gap = S(6)
        local bw = (w - gap * (#kids - 1)) / math.max(1, #kids)
        for i, b in ipairs(kids) do
            b:SetPos(math.floor((i - 1) * (bw + gap)), 0)
            b:SetSize(math.floor(bw), h)
        end
    end
    if nMed == 0 then
        function row:Paint(w, h)
            dashed(Kit, 0, 0, w, h, C.tick)
            draw.SimpleText("You carry no medicine", Kit.Font(13), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    -- What your sample says (or that there's none)
    local box = vgui.Create("DPanel", f)
    box:Dock(TOP)
    box:SetTall(S(54))
    box:DockMargin(0, S(12), 0, S(10))
    local boxText = info or "Units: analyse a blood sample first to know the dose"
    function box:Paint(w, h)
        Kit.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        Kit.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        Kit.SetCol(info and C.good or C.warn)
        surface.DrawRect(0, 0, S(3), h)
        Kit.Caps(info and "From your sample" or "No analysed sample", S(14), h * 0.32, info and C.good or C.warn)
        local bf = Kit.Font(13)
        draw.SimpleText(Kit.Fit(boxText, bf, w - S(28)), bf, S(14), h * 0.68, info and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    caps("Units")
    local ur = vgui.Create("DPanel", f)
    ur:Dock(TOP)
    ur:SetTall(S(38))
    ur.Paint = nil
    local num = Kit.Number(ur, { min = 1, max = 40, unit = "units" }, function() return units end,
        function(v) units = math.Clamp(math.floor(tonumber(v) or 1), 1, 40) end)
    num:Dock(FILL)

    local bar = vgui.Create("DPanel", f)
    bar:Dock(BOTTOM)
    bar:SetTall(S(34))
    bar.Paint = nil
    local give = Kit.Button(bar, function() return pick and ("Give " .. units .. " units") or "Give" end, function()
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
    end, { accent = true, enabled = function() return pick ~= nil end })
    give:Dock(RIGHT)
    give:SetWide(S(200))
    local cancel = Kit.Button(bar, "Cancel", function() f:Remove() end)
    cancel:Dock(RIGHT)
    cancel:SetWide(S(110))
    cancel:DockMargin(0, 0, S(8), 0)
end

--------------------------------------------------------------------------
-- Interaction wheel
--------------------------------------------------------------------------

local function wheelOptions(t, me, add)
    if Med.Simple() then return end   -- (simplified medical system: no illness)
    local dummy = Med.IsDummy(t)
    if Med.IsMedic(me) and not Med.IsDown(me) then
        -- (test dummies can't lie down: standing is fine for them)
        if not (Med.OnSofa(t) or dummy) then
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
        local MP = Rhylib.MP
        local still = Med.OnSofa(t) or Med.IsDown(t) or dummy or (MP and MP.IsCuffed and MP.IsCuffed(t))
        if any and not still then
            add("Give medicine", nil, { order = 17, disabled = "Lay them on a med sofa" })
        elseif any then
            add("Give medicine", function(x) openDose(x) end, { order = 17, sub = "Pick the medicine and dose" })
        end
    end
    -- Staff: start or end an illness (rhylib_admin; players only, test
    -- dummies have rhylib_dummy_infect).
    local A = Rhylib.Admin
    local M = Rhylib.Menus
    if not dummy and A and A.Run and A.TargetWord and M and M.IsStaff and M.IsStaff() then
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
end
Rhylib.Hook.Add("Rhylib.WheelOptions", "medical.illness", wheelOptions)
Rhylib.Hook.Add("Rhylib.WheelEntityOptions", "medical.illness", function(ent, me, add)
    if Med.IsDummy(ent) and ent:Alive() then wheelOptions(ent, me, add) end
end)

--------------------------------------------------------------------------
-- Datapad tab "Illness guide" (medics, full medical system only): the
-- steps from a sick patient to the right dose, for medics who've never
-- seen it (rhylib_datapad D.AddTab).
--------------------------------------------------------------------------

local GUIDE = {
    { "1. Spot it", "Someone who is ill shows an affliction tag on the head in the health (H) menu: UNWELL, ILL or SEVERELY ILL. You can't tell the cause by looking." },
    { "2. Draw blood", "Lay them on a med sofa, then hold E on them and pick Draw blood (needs a blood sample kit). You get a blood sample item." },
    { "3. Test strip", "Right-click the sample and pick Apply to a test strip. The strip develops in 30 seconds to 2 minutes; you hear a blip when it's ready. Right-click the used strip to read it: the colour of the Test channel tells you the kind of illness (the key is on the right)." },
    { "4. Analyse", "Take the sample and its developed strip to a chemistry bench and open the Blood analyser. It gives the dose in units (± a small band)." },
    { "5. Dose", "Hold E on the patient (on the sofa, downed or cuffed) and pick Give medicine. Pick the medicine that matches the strip's colour and the units from the analyser." },
    { "Careful", "Too little and the illness keeps growing; too much is an overdose (blurred vision, lost health, twice over and they go down); the wrong medicine makes them sick. Samples and strips spoil after a while." },
}

-- Text cut into lines that fit w pixels (by words).
local function wrapLines(text, font, w)
    surface.SetFont(font)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if cur ~= "" and surface.GetTextSize(try) > w then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- One step card: a number badge ("!" for the warning), the title and the
-- wrapped text. Colours are read from k.C while painting, so the datapad's
-- teal screen colours (and its K.Tint accent) show on it.
local function guideCard(k, parent, title, body, warn)
    local s = k.S
    local num, name = string.match(title, "^(%d+)%.%s*(.+)$")
    local badge = num or "!"
    name = string.upper(name or title)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(0, 0, s(10), s(6))
    p.lines = {}
    function p:PerformLayout(w)
        local font = k.Font(14)
        self.font = font
        self.lines = wrapLines(body, font, math.max(s(60), w - s(78)))
        local _, lh = surface.GetTextSize("Ag")
        self.lh = lh + s(2)
        local want = s(40) + #self.lines * self.lh + s(10)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    function p:Paint(w, h)
        local C = k.C
        if self.font ~= k.Font(14) then self:InvalidateLayout() end
        local col = warn and C.warn or C.accent
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        k.SetCol(col)
        surface.DrawRect(0, 0, s(3), h)
        -- badge
        local bs = s(32)
        local bx, by = s(16), s(10)
        k.SetCol(col, 34)
        surface.DrawRect(bx, by, bs, bs)
        k.SetCol(col, 200)
        surface.DrawOutlinedRect(bx, by, bs, bs)
        draw.SimpleText(badge, k.Font(16, 800), bx + bs * 0.5, by + bs * 0.5, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local tx = s(64)
        draw.SimpleText(name, k.Font(14, 700), tx, s(22), warn and C.warn or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local y = s(38)
        for i = 1, #self.lines do
            draw.SimpleText(self.lines[i], self.font, tx, y, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            y = y + self.lh
        end
    end
    return p
end

local function addGuideTab()
    local D = Rhylib.Datapad
    if not (D and D.AddTab) then return end
    D.AddTab({
        id = "illness", name = "Illness guide", order = 70,
        has = function() return Med.IsMedic(LocalPlayer()) and not Med.Simple() end,
        build = function(content, k)
            if not k then return end
            local s = k.S
            local sp = k.Scroll(content)
            sp:Dock(FILL)
            local h = k.Heading(sp, "Treating an illness")
            h:Dock(TOP)
            h:DockMargin(0, 0, s(10), s(4))
            local intro = vgui.Create("DPanel", sp)
            intro:Dock(TOP)
            intro:SetTall(s(26))
            intro:DockMargin(0, 0, s(10), s(6))
            function intro:Paint(w, hh)
                draw.SimpleText(k.Fit("From a sick patient to the right dose, in five steps.", k.Font(13), w), k.Font(13), 0, hh * 0.5, k.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            for _, g in ipairs(GUIDE) do
                guideCard(k, sp, g[1], g[2], not string.match(g[1], "^%d"))
            end
            -- The strip colour key (the same as on the test strip window)
            local key = vgui.Create("DPanel", sp)
            key:Dock(TOP)
            key:SetTall(s(40) + #Med.ILL * s(22))
            key:DockMargin(0, s(4), s(10), s(6))
            function key:Paint(w, hh)
                local C = k.C
                k.SetCol(C.header)
                surface.DrawRect(0, 0, w, hh)
                k.SetCol(C.edgeDark)
                surface.DrawOutlinedRect(0, 0, w, hh)
                k.Ticks(0, 0, w, hh)
                k.Caps("Test channel colour", s(16), s(18))
                for i = 1, #Med.ILL do
                    local kk = Med.ILL[i]
                    local y = s(34) + (i - 1) * s(22)
                    k.SetCol(kk.col)
                    surface.DrawRect(s(16), y + s(3), s(12), s(12))
                    k.SetCol(C.edgeDark)
                    surface.DrawOutlinedRect(s(16), y + s(3), s(12), s(12))
                    draw.SimpleText(kk.colour .. " · " .. kk.name, k.Font(13), s(36), y, C.textDim)
                end
            end
        end,
    })
end
Rhylib.After("datapad", addGuideTab)
