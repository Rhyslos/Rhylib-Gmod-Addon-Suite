--[[
    Interference device window (client) and the inventory option to
    place one. The device's settings are its network vars; the scanner
    (receivers nearby: frequency, strength, hopping) comes twice a second.

    Nets: eod.dev opens it; eod.devscan fills the scanner; eod.devset
    (device, op 3 bits, argument) changes it: 0 power, 1 radius (4 bits),
    2 tuned (bool), 3 dial - 2400 (7 bits), 4 swap cell, 5 pick up,
    6 closed. eod.place (item uid) places one from the inventory.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local OPAQUE = Color(14, 16, 15, 255)

-- pending = slider values not sent yet (sent at most every 0.15 s).
local dev = { frame = nil, ent = nil, scan = {}, pending = {}, sentAt = 0 }

local function send(op, write)
    if not IsValid(dev.ent) then return end
    Net.Start("eod.devset")
    net.WriteEntity(dev.ent)
    net.WriteUInt(op, 3)
    if write then write() end
    net.SendToServer()
end

local function close(tell)
    if tell and IsValid(dev.ent) then send(6) end
    if IsValid(dev.frame) then dev.frame:Remove() end
    dev.frame = nil
end

local function fmtTime(t)
    if t >= 3600 then return string.format("%dh %02dm", t / 3600, (t % 3600) / 60) end
    return string.FormattedTime(t, "%02i:%02i")
end

local function open(ent)
    local k = K()
    if not k then return end
    close(false)
    local s = k.S
    local C = k.C
    dev.ent = ent
    dev.scan = {}
    dev.local_ = { r = ent:GetRadius(), dial = ent:GetDial() }
    local fr = vgui.Create("EditablePanel")
    fr:SetSize(math.min(ScrW() - s(60), s(620)), math.min(ScrH() - s(60), s(600)))
    fr:Center()
    fr:MakePopup()
    fr:DockPadding(s(12), s(48), s(12), s(12))
    dev.frame = fr
    function fr:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "Interference device", ticks = "all", header = s(38), bg = OPAQUE })
    end
    function fr:Think()
        local e = dev.ent
        if not IsValid(e) or not LocalPlayer():Alive() or LocalPlayer():GetPos():DistToSqr(e:GetPos()) > 240 * 240 then close(true) return end
        -- (sliders send at most every 0.15 s)
        if CurTime() - dev.sentAt >= 0.15 then
            if dev.pending.r then
                local r = dev.pending.r
                dev.pending.r = nil
                send(1, function() net.WriteUInt(r, 4) end)
                dev.sentAt = CurTime()
            elseif dev.pending.dial then
                local d = dev.pending.dial
                dev.pending.dial = nil
                send(3, function() net.WriteUInt(math.Clamp(math.floor(d - E.F0 + 0.5), 0, 127), 7) end)
                dev.sentAt = CurTime()
            end
        end
    end
    local x = k.Button(fr, "Close", function() close(true) end, { small = true })
    x:SetSize(s(90), s(26))
    x:SetPos(fr:GetWide() - s(90) - s(12), s(6))

    -- status
    local st = vgui.Create("DPanel", fr)
    st:Dock(TOP)
    st:SetTall(s(64))
    st:DockMargin(0, 0, 0, s(8))
    function st:Paint(w, h)
        local e = dev.ent
        if not IsValid(e) then return end
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        local on = e:GetActive() and e:Fill() > 0
        draw.SimpleText(on and (e:GetTuned() and "ON · TUNED" or "ON · WIDEBAND") or "OFF", k.Font(18, 800), s(12), s(18),
            on and (e:GetTuned() and Color(80, 200, 255) or Color(255, 150, 40)) or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local fill = e:Fill()
        draw.SimpleText(string.format("Cell %d%%", math.floor(fill * 100)), k.Font(14, 700), w - s(12), s(18), fill < 0.15 and C.bad or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local life = E.CellLife(e:GetRadius(), e:GetTuned(), e:GetNW2Bool("rhylib_eodLong", false))
        local txt = on and ("about " .. fmtTime(fill / math.max(1e-6, e:GetRate())) .. " left") or ("a full cell lasts " .. fmtTime(life) .. " like this")
        draw.SimpleText(txt, k.Font(13), s(12), s(44), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(e:GetTuned() and "Tuned: blocks one frequency, radio unaffected" or "Wideband: blocks every signal and motion sensors, jams your radio too",
            k.Font(12), w - s(12), s(44), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local function row(title, desc)
        local r = k.Row(fr, title, desc)
        r:Dock(TOP)
        r:DockMargin(0, 0, 0, s(4))
        return r
    end

    local r1 = row("Power")
    local t = k.Toggle(r1.right, function() return IsValid(dev.ent) and dev.ent:GetActive() end, function() send(0) end)
    t:Dock(RIGHT)

    local r2 = row("Radius (m)", "Bigger lasts much shorter (radius²)")
    local sl = k.Slider(r2.right, 1, math.min(15, E.Cfg("deviceMaxRadius") or 15), 0,
        function() return dev.pending.r or (IsValid(dev.ent) and dev.ent:GetRadius() or 5) end,
        function(v) dev.pending.r = math.floor(v) end)
    sl:Dock(FILL)

    local r3 = row("Mode")
    local ch = k.Choices(r3.right, { { false, "Wideband" }, { true, "Tuned" } },
        function() return IsValid(dev.ent) and dev.ent:GetTuned() end,
        function(v) send(2, function() net.WriteBool(v) end) end)
    ch:Dock(FILL)

    local r4 = row("Dial (MHz)", "Tuned mode: match a receiver's peak")
    local dl = k.Slider(r4.right, E.F0, E.F1, 0,
        function() return dev.pending.dial or (IsValid(dev.ent) and dev.ent:GetDial() or 2440) end,
        function(v) dev.pending.dial = v end)
    dl:Dock(FILL)

    -- scanner
    local sc = vgui.Create("DPanel", fr)
    sc:Dock(FILL)
    sc:DockMargin(0, s(6), 0, s(8))
    function sc:Paint(w, h)
        local e = dev.ent
        k.SetCol(Color(6, 14, 10, 255))
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("SCANNER · receivers within ~60 m", k.Font(12, 700), s(8), s(12), C.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local top, bot = s(26), h - s(22)
        local function fx(f) return s(8) + (w - s(16)) * (f - E.F0) / (E.F1 - E.F0) end
        -- grid
        k.SetCol(Color(40, 70, 52, 255))
        for f = E.F0, E.F1, 10 do
            local x = fx(f)
            surface.DrawRect(x, top, 1, bot - top)
            draw.SimpleText(tostring(f), k.Font(10), x, bot + s(10), Color(90, 130, 105), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        -- noise floor
        k.SetCol(Color(70, 140, 95, 255))
        local now = CurTime()
        local lastX, lastY
        for i = 0, 80 do
            local f = E.F0 + i
            local y = bot - s(4) - math.abs(math.sin(i * 1.7 + now * 3)) * s(5)
            for _, p in ipairs(dev.scan) do
                local d = math.abs(f - (E.F0 + p[1]))
                if d < 4 then y = math.min(y, bot - (bot - top - s(10)) * p[2] / 100 * (1 - d / 4) - s(4)) end
            end
            local x = fx(f)
            if lastX then surface.DrawLine(lastX, lastY, x, y) end
            lastX, lastY = x, y
        end
        for _, p in ipairs(dev.scan) do
            local x = fx(E.F0 + p[1])
            local y = bot - (bot - top - s(10)) * p[2] / 100 - s(18)
            draw.SimpleText(string.format("%.3f%s", (E.F0 + p[1]) / 1000, p[3] and " HOP" or ""), k.Font(11, 700), x, y, p[3] and Color(255, 209, 102) or Color(150, 255, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        -- the dial (tuned): marker and the band it blocks
        if IsValid(e) and e:GetTuned() then
            local d = dev.pending.dial or e:GetDial()
            k.SetCol(Color(80, 200, 255, 40))
            surface.DrawRect(fx(d - 2.5), top, fx(d + 2.5) - fx(d - 2.5), bot - top)
            k.SetCol(Color(80, 200, 255, 255))
            surface.DrawRect(fx(d), top, 2, bot - top)
        end
    end

    local bottom = vgui.Create("DPanel", fr)
    bottom:Dock(BOTTOM)
    bottom:SetTall(s(34))
    bottom.Paint = nil
    local swap = k.Button(bottom, "Swap the power cell", function() send(4) end)
    swap:Dock(LEFT)
    swap:SetWide(s(220))
    local pick = k.Button(bottom, "Pick it up", function() send(5) close(false) end, { danger = true })
    pick:Dock(RIGHT)
    pick:SetWide(s(160))
end

Net.Receive("eod.dev", function()
    local e = net.ReadEntity()
    if IsValid(e) then open(e) end
end)

Net.Receive("eod.devscan", function()
    local e = net.ReadEntity()
    local n = net.ReadUInt(4)
    local list = {}
    for i = 1, n do list[i] = { net.ReadUInt(7), net.ReadUInt(7), net.ReadBool() } end
    if e == dev.ent then dev.scan = list end
end)

-- Inventory right-click: place it.
Rhylib.Hook.Add("Rhylib.ItemMenu", "eod.place", function(inst, menu)
    if inst.id ~= E.DEVICE then return end
    menu:AddOption("Place interference device", function()
        Net.Start("eod.place")
        net.WriteUInt(inst.uid, Rhylib.Items and Rhylib.Items.UID_BITS or 16)
        net.SendToServer()
    end)
end)

Rhylib.Hook.Add("InitPostEntity", "eod.devcloser", function()
    if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("eoddev", function() if IsValid(dev.frame) then close(true) return true end end)
    end
end)
