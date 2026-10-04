--[[
    Illness (client): symptoms on screen, the analyser window, the dose
    window, test strips (inventory right-click) and the interaction wheel
    options (draw blood, give medicine; staff: infect / cure).
]]

local Med = Rhylib.Medical

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local function Inv() return Rhylib.Inventory end

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

local function progress(text, secs)
    local M = Rhylib.Menus
    if M and M.WheelProgress then M.WheelProgress(text, secs) end
end

-- A timed step was cancelled (uid: an analyser sample, 0 = something else).
net.Receive(Rhylib.Net.Name("ill.stop"), function()
    local uid = net.ReadUInt(Rhylib.Items.UID_BITS)
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
    if not IsValid(ply) or not ply:Alive() then return end
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
    return not string.find(n, "not analysed", 1, true)
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
        Kit.Plate(0, 0, w, h, { title = "Blood analyser", ticks = "all", header = S(34) })
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
                net.WriteUInt(uid, Rhylib.Items.UID_BITS)
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

net.Receive(Rhylib.Net.Name("ill.open"), function()
    local ent = net.ReadEntity()
    if IsValid(ent) then openAnalyser(ent) end
end)

--------------------------------------------------------------------------
-- Test strip: right-click a sample in the inventory
--------------------------------------------------------------------------

Rhylib.Hook.Add("Rhylib.ItemMenu", "medical.strip", function(inst, menu)
    if inst.id ~= Med.SAMPLE then return end
    local note = inst.data and inst.data.note or ""
    if string.find(note, "strip:", 1, true) then return end
    if carried(Med.STRIP) < 1 then
        menu:AddOption("Test on a strip (you have none)", function() end)
        return
    end
    menu:AddOption("Test on a strip", function()
        Rhylib.Net.Start("ill.strip")
        net.WriteUInt(inst.uid, Rhylib.Items.UID_BITS)
        net.SendToServer()
    end)
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
    local lab = Kit.Label(f, "Units (the right dose is the load ÷ 5)", 13, nil, Kit.C.textDim)
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
    if Med.IsMedic(me) and not Med.IsDown(me) then
        if not Med.OnSofa(t) then
            add("Draw blood", nil, { order = 16, disabled = "Lay them on a med sofa" })
        elseif carried(Med.BLOOD_KIT) < 1 then
            add("Draw blood", nil, { order = 16, disabled = "No blood sample kit" })
        else
            add("Draw blood", function(x)
                Rhylib.Net.Start("ill.draw")
                net.WriteEntity(x)
                net.SendToServer()
                progress("Drawing blood", Med.Cfg("drawTime") * (chemist(me) and 0.67 or 1))
            end, { order = 16, sub = "Sample for the analyser" })
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
