--[[
    Mines (client): finding them (E on one you can see), the mine window
    (dig, safety pin on the needle, lift), the standing-on-a-mine warning,
    and the mine scanner (beam, outlines, beeps, marking).
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local OPAQUE = Color(14, 16, 15, 255)
local RED = Color(255, 70, 60)

E.mineSeen = E.mineSeen or setmetatable({}, { __mode = "k" })

-- Mines near enough to matter (refreshed twice a second).
local list, listAt = {}, 0
local function mines()
    local now = RealTime()
    if now - listAt > 0.5 then
        listAt = now
        list = {}
        for _, m in ipairs(ents.FindByClass("rhylib_eod_mine*")) do
            if IsValid(m) and m.IsRhylibMine then list[#list + 1] = m end
        end
    end
    return list
end

local function holding(cls)
    local w = LocalPlayer():GetActiveWeapon()
    return IsValid(w) and w:GetClass() == cls and w or nil
end

--------------------------------------------------------------------------
-- E on a mine
--------------------------------------------------------------------------

local function mineAtAim()
    local ply = LocalPlayer()
    local tr = ply:GetEyeTrace()
    if IsValid(tr.Entity) and tr.Entity.IsRhylibMine and tr.Entity:VisibleAmount() > 0 and tr.HitPos:DistToSqr(tr.StartPos) < 140 * 140 then return tr.Entity end
    local best, bestD = nil, 50 * 50
    for _, m in ipairs(mines()) do
        if IsValid(m) and m:VisibleAmount() > 0 and m:GetPos():DistToSqr(ply:GetPos()) < 140 * 140 then
            local d = m:GetPos():DistToSqr(tr.HitPos)
            if d < bestD then best, bestD = m, d end
        end
    end
    return best
end

Rhylib.Hook.Add("PlayerBindPress", "eod.mineuse", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+use", 1, true) then return end
    local m = mineAtAim()
    if not m then return end
    Net.Start("eod.mineuse")
    net.WriteEntity(m)
    net.SendToServer()
end)

--------------------------------------------------------------------------
-- The mine window
--------------------------------------------------------------------------


local function act(op)
    if not (E.mineWin and IsValid(E.mineWin.mine)) then return end
    Net.Start("eod.mineact")
    net.WriteEntity(E.mineWin.mine)
    net.WriteUInt(op, 3)
    net.SendToServer()
end

local function closeWin(tell)
    if E.mineWin and IsValid(E.mineWin.frame) then
        if tell then act(5) end
        E.mineWin.frame:Remove()
    end
    E.mineWin = nil
end

local function holdBtn(k, parent, label, secs, startOp, doneOp, enabled)
    local s = k.S
    local b = k.Button(parent, label, nil, { accent = true, enabled = enabled })
    function b:OnMousePressed(code)
        if code ~= MOUSE_LEFT or not self:IsOn() then return end
        self.at = CurTime()
        self:MouseCapture(true)
        act(startOp)
    end
    function b:OnMouseReleased(code)
        if code ~= MOUSE_LEFT then return end
        self:MouseCapture(false)
        self.at = nil
    end
    function b:Think()
        if self.at and CurTime() - self.at >= secs() then
            self.at = nil
            self:MouseCapture(false)
            act(doneOp)
        end
    end
    local paint = b.Paint
    function b:Paint(w, h)
        paint(self, w, h)
        if self.at then
            k.SetCol(k.C.good, 140)
            surface.DrawRect(1, h - s(4), (w - 2) * math.Clamp((CurTime() - self.at) / secs(), 0, 1), s(3))
        end
        return true
    end
    return b
end

local function openWin(m, center, width, period, ph)
    local k = K()
    if not k then return end
    closeWin(false)
    local s = k.S
    local C = k.C
    local f = vgui.Create("EditablePanel")
    f:SetSize(s(520), m.IsTrainingMine and s(560) or s(340))
    f:Center()
    f:MakePopup()
    f:DockPadding(s(14), s(50), s(14), s(14))
    E.mineWin = { frame = f, mine = m, center = center, width = width, period = period, ph = ph }
    local lap = m:IsLarge()
    function f:Paint(w, h)
        k.Plate(0, 0, w, h, { title = lap and "LAP mine (large)" or "AP mine", ticks = "all", header = s(38), bg = OPAQUE })
    end
    local x = k.Button(f, "Close", function() closeWin(true) end, { small = true })
    x:SetSize(s(90), s(26))
    x:SetPos(f:GetWide() - s(104), s(6))

    local status = vgui.Create("DPanel", f)
    status:Dock(TOP)
    status:SetTall(s(30))
    function status:Paint(w, h)
        if not IsValid(m) then return end
        local txt, col
        if m:GetSafe() then txt, col = "SAFE: pinned. Lift it away.", C.good
        elseif m:GetDug() then txt, col = string.format("Dug out · safety pins %d / %d", m:GetPins(), m:PinsNeeded()), C.warn
        else txt, col = "Buried. Dig it out to reach the fuse.", C.text end
        draw.SimpleText(txt, k.Font(15, 700), 0, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local pr = m:GetPresser()
        if IsValid(pr) then
            draw.SimpleText((pr == LocalPlayer() and "You are" or pr:Nick() .. " is") .. " standing on it", k.Font(13, 700), w, h / 2, RED, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    local dig = holdBtn(k, f, "Hold: dig it out", function() return (E.Cfg("mineDigTime") or 3) * (E.Skill(LocalPlayer(), "eod_quick") and 0.6 or 1) end, 0, 1,
        function() return IsValid(m) and not m:GetDug() end)
    dig:Dock(TOP)
    dig:DockMargin(0, s(6), 0, s(8))

    local gauge = vgui.Create("DPanel", f)
    gauge:Dock(TOP)
    gauge:SetTall(s(46))
    function gauge:Paint(w, h)
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        if IsValid(m) and m:GetDug() and not m:GetSafe() then
            k.SetCol(Color(70, 167, 88, 170))
            surface.DrawRect(w * (E.mineWin.center - E.mineWin.width / 2) / 100, 1, w * E.mineWin.width / 100, h - 2)
            local n = E.MineNeedle(E.mineWin.period, E.mineWin.ph, CurTime())
            k.SetCol(color_white)
            surface.DrawRect(w * n / 100 - 1, 0, 3, h)
        else
            draw.SimpleText(IsValid(m) and m:GetSafe() and "Fuse pinned" or "Dig it out first", k.Font(13), w / 2, h / 2, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local pin = k.Button(f, "Push the safety pin (Space)", function() act(2) end,
        { danger = true, enabled = function() return IsValid(m) and m:GetDug() and not m:GetSafe() end })
    pin:Dock(TOP)
    pin:DockMargin(0, s(6), 0, s(8))

    local lift = holdBtn(k, f, "Hold: lift it away", function() return E.Cfg("mineLiftTime") or 2 end, 3, 4,
        function() return IsValid(m) and m:GetSafe() end)
    lift:Dock(TOP)

    local note = k.Label(f, "Push the pin only while the needle is inside the green zone. A wrong push sets it off.", 12, 400, C.textDim)
    note:Dock(BOTTOM)

    -- Training mine: set it up (anyone near it).
    if m.IsTrainingMine then
        local set = { large = m:IsLarge(), shown = m:GetShown(), level = math.max(1, m:GetLevel() == 0 and 2 or m:GetLevel()), pins = m:GetPinsNeed() }
        local h = k.Heading(f, "Training setup")
        h:Dock(TOP)
        h:DockMargin(0, s(10), 0, s(4))
        local function row(title, opts, key)
            local r = k.Row(f, title)
            r:Dock(TOP)
            r:SetTall(s(34))
            r:DockMargin(0, 0, 0, s(2))
            local ch = k.Choices(r.right, opts, function() return set[key] end, function(v) set[key] = v end)
            ch:Dock(FILL)
        end
        row("Type", { { false, "AP" }, { true, "LAP" } }, "large")
        row("Difficulty", { { 1, "Easy" }, { 2, "Normal" }, { 3, "Hard" } }, "level")
        row("Safety pins", { { 0, "By type" }, { 1, "1" }, { 2, "2" }, { 3, "3" } }, "pins")
        row("Hidden", { { false, "Hidden" }, { true, "Always visible" } }, "shown")
        local apply = k.Button(f, "Set it up", function()
            Net.Start("eod.trainmine")
            net.WriteEntity(m)
            net.WriteBool(set.large)
            net.WriteBool(set.shown)
            net.WriteUInt(set.level, 2)
            net.WriteUInt(set.pins, 2)
            net.SendToServer()
        end, { accent = true, enabled = function() return IsValid(m) and not IsValid(m:GetPresser()) end })
        apply:Dock(TOP)
        apply:DockMargin(0, s(4), 0, 0)
    end

    function f:Think()
        if not (IsValid(m) and LocalPlayer():Alive()) or LocalPlayer():GetPos():DistToSqr(m:GetPos()) > 200 * 200 then closeWin(false) return end
        local sp = input.IsKeyDown(KEY_SPACE)
        if sp and not self.space and m:GetDug() and not m:GetSafe() then act(2) end
        self.space = sp
    end
end

Net.Receive("eod.mineopen", function()
    local m = net.ReadEntity()
    local center = net.ReadUInt(7)
    local width = net.ReadFloat()
    local period = net.ReadFloat()
    local ph = net.ReadFloat()
    if IsValid(m) then openWin(m, center, width, period, ph) end
end)

--------------------------------------------------------------------------
-- Standing on a mine
--------------------------------------------------------------------------

Rhylib.Hook.Add("HUDPaint", "eod.onmine", function()
    local ply = LocalPlayer()
    local m = ply:GetNW2Entity("rhylib_onMine")
    local k = K()
    local font = k and k.Font(26, 800) or "DermaLarge"
    if IsValid(m) then
        local a = 180 + 75 * math.abs(math.sin(CurTime() * 4))
        draw.SimpleTextOutlined("YOU'RE STANDING ON A MINE", font, ScrW() / 2, ScrH() * 0.3, Color(255, 70, 60, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 230))
        draw.SimpleTextOutlined("Don't move. Don't jump. Call for EOD.", k and k.Font(16, 700) or "DermaDefaultBold", ScrW() / 2, ScrH() * 0.3 + 32, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 230))
    end
    -- others stuck on mines
    local small = k and k.Font(13, 800) or "DermaDefaultBold"
    for _, p in ipairs(player.GetAll()) do
        if p ~= ply and not p:IsDormant() and IsValid(p:GetNW2Entity("rhylib_onMine")) and p:GetPos():DistToSqr(ply:GetPos()) < 2500 * 2500 then
            local sc = (p:GetPos() + Vector(0, 0, 82)):ToScreen()
            if sc.visible then
                draw.SimpleTextOutlined("ON A MINE", small, sc.x, sc.y, RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 230))
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Outlines and marks
--------------------------------------------------------------------------

Rhylib.Hook.Add("PreDrawHalos", "eod.mines", function()
    local now = CurTime()
    local red, green, orange = {}, {}, {}
    local eye = EyePos()
    for _, m in ipairs(mines()) do
        if IsValid(m) and m:GetPos():DistToSqr(eye) < 2500 * 2500 then
            if m:GetSafe() then green[#green + 1] = m
            elseif IsValid(m:GetPresser()) then orange[#orange + 1] = m
            elseif m:GetMarked() or (E.mineSeen[m] or 0) > now then red[#red + 1] = m end
        end
    end
    if #red > 0 then halo.Add(red, RED, 2, 2, 1, true, true) end
    if #orange > 0 then halo.Add(orange, Color(255, 170, 40), 3, 3, 2, true, true) end
    if #green > 0 then halo.Add(green, Color(90, 230, 120), 2, 2, 1, true, false) end
end)

-- Marked mines: a little red flag on a pole.
Rhylib.Hook.Add("PostDrawTranslucentRenderables", "eod.mineflags", function(depth, sky)
    if depth or sky then return end
    local eye = EyePos()
    for _, m in ipairs(mines()) do
        if IsValid(m) and m:GetMarked() and not m:GetSafe() and m:GetPos():DistToSqr(eye) < 3000 * 3000 then
            local base = m:GetPos() + Vector(18, 0, 0)
            render.DrawLine(base, base + Vector(0, 0, 34), Color(200, 200, 200), true)
            render.SetColorMaterial()
            render.DrawQuad(base + Vector(0, 0, 34), base + Vector(14, 0, 30), base + Vector(14, 0, 30), base + Vector(0, 0, 26), RED)
            render.DrawQuad(base + Vector(0, 0, 26), base + Vector(14, 0, 30), base + Vector(14, 0, 30), base + Vector(0, 0, 34), RED)
        end
    end
end)

--------------------------------------------------------------------------
-- Mine scanner
--------------------------------------------------------------------------

local scanAt, beepAt, nearest = 0, 0, nil

local function killBeam()
    if IsValid(E.mineBeam) then E.mineBeam:Remove() end
    E.mineBeam = nil
end

Rhylib.Hook.Add("Think", "eod.scanner", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local w = holding(E.SCANNER)
    if not (w and w:GetOn() and ply:Alive()) then
        killBeam()
        nearest = nil
        return
    end
    local range = E.Cfg("mineScanRange") or 700
    local cone = E.Cfg("mineScanCone") or 22
    local dir = E.ScanDir(ply)
    if not IsValid(E.mineBeam) then
        E.mineBeam = ProjectedTexture()
        E.mineBeam:SetTexture("effects/flashlight001")
        E.mineBeam:SetEnableShadows(false)
        E.mineBeam:SetColor(Color(120, 255, 200))
        E.mineBeam:SetBrightness(2.5)
        E.mineBeam:SetNearZ(8)
    end
    E.mineBeam:SetFOV(cone * 2)
    E.mineBeam:SetFarZ(range)
    E.mineBeam:SetPos(ply:EyePos() - Vector(0, 0, 12))
    E.mineBeam:SetAngles(dir:Angle())
    E.mineBeam:Update()

    local now = CurTime()
    if now >= scanAt then
        scanAt = now + 0.1
        local eye = ply:EyePos()
        local cosC = math.cos(math.rad(cone))
        nearest = nil
        for _, m in ipairs(mines()) do
            if IsValid(m) then
                local mp = E.MineTop(m) + m:GetUp() * 2
                local d = eye:Distance(mp)
                if d <= range and dir:Dot((mp - eye):GetNormalized()) >= cosC
                    and not util.TraceLine({ start = eye, endpos = mp, mask = MASK_SOLID_BRUSHONLY }).Hit then
                    E.mineSeen[m] = now + 1.2
                    if not m:GetSafe() and (not nearest or d < nearest) then nearest = d end
                end
            end
        end
    end
    -- beeps quicken as you close in
    if nearest and now >= beepAt then
        local f = math.Clamp(nearest / range, 0, 1)
        beepAt = now + 0.12 + f * 1.0
        ply:EmitSound("buttons/blip1.wav", 45, 90 + (1 - f) * 80, 0.6)
    end
end)

-- Other players' scanners: a light where their E.mineBeam lands.
Rhylib.Hook.Add("Think", "eod.scanners.others", function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local now = RealTime()
    if (E.scanOthersAt or 0) > now then return end
    E.scanOthersAt = now + 0.05
    for _, p in ipairs(player.GetAll()) do
        if p ~= me and not p:IsDormant() and p:Alive() then
            local w = p:GetActiveWeapon()
            if IsValid(w) and w:GetClass() == E.SCANNER and w:GetOn() and p:GetPos():DistToSqr(me:GetPos()) < 3000 * 3000 then
                local tr = util.TraceLine({ start = p:EyePos(), endpos = p:EyePos() + E.ScanDir(p) * (E.Cfg("mineScanRange") or 700), filter = p, mask = MASK_SOLID_BRUSHONLY })
                local dl = DynamicLight(0x7400 + p:EntIndex())
                if dl then
                    dl.pos = tr.HitPos + tr.HitNormal * 8
                    dl.r, dl.g, dl.b = 120, 255, 200
                    dl.brightness = 1
                    dl.decay = 1000
                    dl.size = 220
                    dl.dietime = CurTime() + 0.15
                end
            end
        end
    end
end)

-- RMB: mark the mine nearest the crosshair that the beam shows.
function E.ScannerMark()
    local ply = LocalPlayer()
    local eye, aim = ply:EyePos(), ply:GetAimVector()
    local best, bestDot = nil, math.cos(math.rad(12))
    local now = CurTime()
    for _, m in ipairs(mines()) do
        if IsValid(m) and (E.mineSeen[m] or 0) > now and not m:GetSafe() then
            local dot = aim:Dot((m:GetPos() - eye):GetNormalized())
            if dot > bestDot then best, bestDot = m, dot end
        end
    end
    if not best then
        surface.PlaySound("buttons/button10.wav")
        return
    end
    Net.Start("eod.minemark")
    net.WriteEntity(best)
    net.SendToServer()
end

function E.ScannerHUD(wep)
    local k = K()
    local font = k and k.Font(14, 700) or "DermaDefaultBold"
    local on = wep:GetOn()
    local y = ScrH() * 0.72
    draw.SimpleTextOutlined(on and "SCANNER ON  ·  LMB off  ·  RMB mark a mine" or "SCANNER OFF  ·  LMB on", font, ScrW() / 2, y,
        on and Color(130, 255, 200) or Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
    if on and nearest then
        draw.SimpleTextOutlined(string.format("MINE  %.1f m", nearest / E.UNITS_PER_M), k and k.Font(20, 800) or "DermaLarge", ScrW() / 2, y + 26,
            RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
    end
end

Rhylib.Hook.Add("InitPostEntity", "eod.minecloser", function()
    if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("eodmine", function() if E.mineWin and IsValid(E.mineWin.frame) then closeWin(true) return true end end)
    end
end)
