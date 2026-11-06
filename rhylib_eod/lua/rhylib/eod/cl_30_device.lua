--[[
    Interference device window (client) and the inventory option to
    place one. The device's settings are its network vars; the scanner
    (receivers nearby: frequency, strength, hopping) comes twice a second.

    Nets: eod.dev opens it; eod.devscan fills the scanner; eod.devset
    (device, op 3 bits, argument) changes it: 0 power, 1 radius (4 bits),
    2 tuned (bool), 3 dial - 2400 (7 bits), 4 swap cell, 5 pick up,
    6 closed. eod.place (item uid) places one from the inventory.

    Layout: a plate with Close in the header; a status card (ON · TUNED
    blue / ON · WIDEBAND orange / OFF grey with the time left, the cell %
    and its bar, what the mode does); SETTINGS rows (power, radius, mode,
    dial); the scanner as a green screen (peaks with their frequency, HOP
    in amber, the tuned dial's band in blue, a signal count); Swap the
    power cell and Pick it up at the bottom. Colours are theme tokens
    "eod.*" (cl_11_theme.lua).
]]

local E = Rhylib.EOD
local Net = Rhylib.Net
local UI = Rhylib.UI

local function K() return UI and UI.Kit end
-- Theme tokens (cl_11_theme.lua): the window and the scanner's screen.
local OPAQUE = UI.Col("eod.windowBg", 14, 16, 15, 255)
local COL_SCAN_BG = UI.Col("eod.scanBg", 6, 14, 10)
local COL_SCAN_GRID = UI.Col("eod.scanGrid", 40, 70, 52)
local COL_SCAN_AXIS = UI.Col("eod.scanAxis", 90, 130, 105)
local COL_SCAN_TRACE = UI.Col("eod.scanTrace", 70, 140, 95)
local COL_SCAN_PEAK = UI.Col("eod.scanPeak", 150, 255, 180)
local COL_SCAN_HOP = UI.Col("eod.scanHop", 255, 209, 102)
local COL_TUNED = UI.Col("eod.tuned", 80, 200, 255)
local COL_WIDE = UI.Col("eod.wideband", 255, 150, 40)

-- (scanner axis labels, made once)
local FREQ_LABEL = {}
for f = E.F0, E.F1, 10 do FREQ_LABEL[f] = tostring(f) end

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

-- A small caps chip (text already upper case); y is its centre. Returns its width.
local function chip(k, text, x, y, col, right)
    local f = k.Font(11, 700)
    surface.SetFont(f)
    local tw = surface.GetTextSize(text)
    local w, h = tw + k.S(14), k.S(20)
    if right then x = x - w end
    k.SetCol(col, 40)
    surface.DrawRect(x, y - h * 0.5, w, h)
    k.SetCol(col, 170)
    surface.DrawOutlinedRect(x, y - h * 0.5, w, h)
    draw.SimpleText(text, f, x + w * 0.5, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

local GRAD = Material("vgui/gradient-l")
local DIA = { {}, {}, {}, {} }
local function diamond(k, cx, cy, r, col)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    k.SetCol(col)
    surface.DrawPoly(DIA)
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
    fr:SetSize(math.min(ScrW() - s(60), s(680)), math.min(ScrH() - s(60), s(660)))
    fr:Center()
    fr:MakePopup()
    fr:DockPadding(s(14), s(52), s(14), s(14))
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
    x:SetPos(fr:GetWide() - s(90) - s(8), s(6))

    -- Status card: state, time left, the cell, what the mode does
    local st = vgui.Create("DPanel", fr)
    st:Dock(TOP)
    st:SetTall(s(92))
    st:DockMargin(0, 0, 0, s(10))
    function st:Paint(w, h)
        local e = dev.ent
        if not IsValid(e) then return end
        local on = e:GetActive() and e:Fill() > 0
        local tuned = e:GetTuned()
        local col = on and (tuned and COL_TUNED or COL_WIDE) or C.textDim
        k.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(col, 26)
        surface.SetMaterial(GRAD)
        surface.DrawTexturedRect(0, 0, w * 0.6, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        k.SetCol(col)
        surface.DrawRect(0, 0, s(4), h)
        k.Ticks(0, 0, w, h)
        k.Caps("Status", s(18), s(18))
        draw.SimpleText(on and (tuned and "ON · TUNED" or "ON · WIDEBAND") or "OFF", k.Font(22, 800), s(18), s(44),
            col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local fill = e:Fill()
        local life = E.CellLife(e:GetRadius(), tuned, e:GetNW2Bool("rhylib_eodLong", false))
        local txt = on and ("about " .. fmtTime(fill / math.max(1e-6, e:GetRate())) .. " left") or ("a full cell lasts " .. fmtTime(life) .. " like this")
        draw.SimpleText(txt, k.Font(13), s(18), s(70), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- the cell (right)
        local cw = math.min(s(240), w * 0.42)
        local cx = w - cw - s(16)
        k.Caps("Power cell", cx, s(18))
        local low = fill < 0.15
        draw.SimpleText(string.format("Cell %d%%", math.floor(fill * 100)), k.Font(15, 700), w - s(16), s(18), low and C.bad or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        k.SetCol(C.row)
        surface.DrawRect(cx, s(32), cw, s(8))
        k.SetCol(low and C.bad or (fill < 0.35 and C.warn or C.good))
        surface.DrawRect(cx, s(32), math.floor(cw * math.Clamp(fill, 0, 1)), s(8))
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(cx, s(32), cw, s(8))
        local note = tuned and "Tuned: blocks one frequency, radio unaffected" or "Wideband: blocks every signal and motion sensors, jams your radio too"
        local nf = k.Font(12)
        draw.SimpleText(k.Fit(note, nf, w - s(36) - math.min(s(240), w * 0.5)), nf, w - s(16), s(70), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local band = vgui.Create("DPanel", fr)
    band:Dock(TOP)
    band:SetTall(s(30))
    band:DockMargin(0, 0, 0, s(4))
    function band:Paint(w, h)
        k.SetCol(C.accent, 30)
        surface.SetMaterial(GRAD)
        surface.DrawTexturedRect(0, 0, w * 0.7, h)
        k.SetCol(C.accent)
        surface.DrawRect(0, 0, s(3), h)
        diamond(k, s(16), h * 0.5, s(5), C.accent)
        draw.SimpleText("SETTINGS", k.Font(13, 700), s(28), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local n = 0
    local function row(title, desc)
        n = n + 1
        local alt = n % 2 == 0
        local r = vgui.Create("DPanel", fr)
        r:Dock(TOP)
        r:SetTall(desc and s(48) or s(38))
        r:DockMargin(0, 0, 0, s(2))
        r:DockPadding(s(12), s(7), s(10), s(7))
        function r:Paint(w, h)
            k.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(title, k.Font(14, 500), s(12), desc and h * 0.36 or h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if desc then draw.SimpleText(desc, k.Font(12), s(12), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end
        r.right = vgui.Create("DPanel", r)
        r.right:Dock(RIGHT)
        r.right:SetWide(s(320))
        r.right.Paint = nil
        return r
    end

    local r1 = row("Power")
    local t = k.Toggle(r1.right, function() return IsValid(dev.ent) and dev.ent:GetActive() end, function() send(0) end)
    t:Dock(RIGHT)

    local r2 = row("Radius (m)", "Bigger lasts much shorter (radius²)")
    local sl = k.Slider(r2.right, 1, math.min(15, E.Cfg("deviceMaxRadius")), 0,
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

    -- Scanner: a green screen in a plate, the band 2400-2480 MHz
    local sc = vgui.Create("DPanel", fr)
    sc:Dock(FILL)
    sc:DockMargin(0, s(10), 0, s(10))
    function sc:Paint(w, h)
        local e = dev.ent
        local hh = s(28)
        k.SetCol(C.header)
        surface.DrawRect(0, 0, w, hh)
        k.SetCol(COL_SCAN_PEAK, 150)
        surface.DrawRect(0, hh - 1, w, 1)
        k.Caps("Scanner", s(12), hh * 0.5, C.text)
        draw.SimpleText("receivers within ~60 m", k.Font(12), s(80), hh * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local nsig = #dev.scan
        chip(k, nsig == 1 and "1 SIGNAL" or (nsig .. " SIGNALS"), w - s(8), hh * 0.5, nsig > 0 and COL_SCAN_PEAK or C.textDim, true)
        k.SetCol(COL_SCAN_BG)
        surface.DrawRect(0, hh, w, h - hh)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.Ticks(0, 0, w, h, false, 120)
        local top, bot = hh + s(14), h - s(22)
        local function fx(f) return s(10) + (w - s(20)) * (f - E.F0) / (E.F1 - E.F0) end
        -- grid
        local axisFont = k.Font(10)
        for f = E.F0, E.F1, 10 do
            local gx = fx(f)
            k.SetCol(COL_SCAN_GRID)
            surface.DrawRect(gx, top, 1, bot - top)
            draw.SimpleText(FREQ_LABEL[f] or "", axisFont, gx, bot + s(10), COL_SCAN_AXIS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        k.SetCol(COL_SCAN_GRID)
        surface.DrawRect(fx(E.F0), bot, fx(E.F1) - fx(E.F0) + 1, 1)
        -- noise floor
        k.SetCol(COL_SCAN_TRACE)
        local now = CurTime()
        local lastX, lastY
        for i = 0, 80 do
            local f = E.F0 + i
            local y = bot - s(4) - math.abs(math.sin(i * 1.7 + now * 3)) * s(5)
            for _, p in ipairs(dev.scan) do
                local d = math.abs(f - (E.F0 + p[1]))
                if d < 4 then y = math.min(y, bot - (bot - top - s(10)) * p[2] / 100 * (1 - d / 4) - s(4)) end
            end
            local gx = fx(f)
            if lastX then surface.DrawLine(lastX, lastY, gx, y) end
            lastX, lastY = gx, y
        end
        local pf = k.Font(11, 700)
        for _, p in ipairs(dev.scan) do
            local gx = fx(E.F0 + p[1])
            local y = bot - (bot - top - s(10)) * p[2] / 100 - s(18)
            draw.SimpleText(string.format("%.3f%s", (E.F0 + p[1]) / 1000, p[3] and " HOP" or ""), pf, gx, y, p[3] and COL_SCAN_HOP or COL_SCAN_PEAK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        -- the dial (tuned): marker and the band it blocks
        if IsValid(e) and e:GetTuned() then
            local d = dev.pending.dial or e:GetDial()
            k.SetCol(COL_TUNED, 40)
            surface.DrawRect(fx(d - 2.5), top, fx(d + 2.5) - fx(d - 2.5), bot - top)
            k.SetCol(COL_TUNED)
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

local function addCloser()
    if Rhylib.UI and Rhylib.UI.RegisterCloser then
        Rhylib.UI.RegisterCloser("eoddev", function() if IsValid(dev.frame) then close(true) return true end end)
    end
end
addCloser()
Rhylib.Hook.Add("InitPostEntity", "eod.devcloser", addCloser)
