--[[
    Intel datapads (client): the window net dp.intel opens (sv_95_intel.lua).

      view 0  encrypted, not a field technician: a short note.
      view 1  cracking: three rounds (EASY, MODERATE, HARD), each from
              the seed the server sends (D.IntelSignal). The scope
              shows the target pattern (amber band) and your signal
              (blue). Two knobs, frequency (A / D, or drag / wheel) and
              amplitude (W / S), move your signal; it drifts on its own
              (D.IntelDrift; round 3 also jumps). The match bar shows
              how close it is. Space locks: op 1 to the server (round,
              time into the round, both knobs), which checks it and
              answers with the next round, round 1 again after a miss
              (view 1 again, "why" 1 / 2), or the intel after the third.
      view 2  cracked: the title and text the game master wrote.
      view 3  game master setup: title, text, who reads it once
              cracked, Save, Lock it again.
    UI closer "datapad.intel". Closing sends op 4.
]]

local D = Rhylib.Datapad
local UI = Rhylib.UI

-- (D.intelWin: the open window { frame, pad, view, ... }; kept on refresh)

-- Colours: theme tokens (Rhylib.UI.Col), read when drawing.
local Col, KC = UI.Col, UI.Kit.C
local OPAQUE = Col("datapad.intelWin", 14, 16, 15, 255)
local SCOPE_BG, GRID = Col("datapad.intelScope", 7, 16, 12), Col("datapad.intelGrid", 18, 38, 27)
local BAND, BAND_EDGE = Col("datapad.intelBand", 239, 159, 39, 46), Col("datapad.intelBandEdge", 239, 159, 39, 150)
local LIVE, LIVE_GLOW = Col("datapad.intelSignal", 133, 183, 235), Col("datapad.intelSignalGlow", 133, 183, 235, 60)
local LOCKED_COL, LOCK_BG = Col("datapad.intelLocked", 151, 196, 89), Col("datapad.intelLockBg", 11, 12, 11)
local KNOB_RIM, KNOB_FACE, KNOB_MARK = Col("datapad.intelKnobRim", 58, 61, 57), Col("datapad.intelKnobFace", 38, 43, 40), Col("datapad.intelKnobMark", 133, 183, 235)
local TEXT_DIM, TEXT, AMBER = KC.textDim, KC.text, KC.warn
local OVERLAY = Col("datapad.intelOverlay", 14, 16, 15, 225)
local LOCKED_BAND, PIP_DONE, PIP_NOW = Col("datapad.intelLockedBand", 151, 196, 89, 40), Col("datapad.intelPipDone", 26, 42, 23), Col("datapad.intelPipNow", 48, 64, 90)
local CARET, RX_TEXT = Col("datapad.intelCaret", 70, 100, 140), Col("datapad.intelRxText", 95, 138, 112)

local F_MIN, F_MAX, A_MIN, A_MAX = 1, 4, 0.25, 1
local F_LO, F_HI, A_LO, A_HI = 0, 5, 0, 1.4   -- (how far the knobs turn: past the targets, so drift can always be caught; the server clamps the same)

local function close(tell)
    if not D.intelWin then return end
    local w = D.intelWin
    D.intelWin = nil
    if tell and IsValid(w.pad) and w.view == 1 then
        Rhylib.Net.Start("dp.intelact")
        net.WriteEntity(w.pad)
        net.WriteUInt(4, 3)
        net.SendToServer()
    end
    if IsValid(w.frame) then w.frame:Remove() end
end
if UI and UI.RegisterCloser then
    UI.RegisterCloser("datapad.intel", function()
        if not D.intelWin then return false end
        close(true)
        return true
    end)
end

local function act(op, write)
    if not (D.intelWin and IsValid(D.intelWin.pad)) then return end
    Rhylib.Net.Start("dp.intelact")
    net.WriteEntity(D.intelWin.pad)
    net.WriteUInt(op, 3)
    if write then write() end
    net.SendToServer()
end

-- A round from the server: the signal from its seed, the knobs where it
-- says; it starts in wait seconds (why: 0 start, 1 the last round locked,
-- 2 missed: back to round 1).
local function newRound(g, r, seed, wait, why)
    local sg = D.IntelSignal(seed, r)
    g.round = r
    g.sg = sg
    g.cfg = sg
    g.tf, g.ta = sg.tf, sg.ta
    g.kf, g.ka = sg.kf, sg.ka
    g.lf, g.la = nil, nil
    g.t0 = CurTime() + wait
    g.why = why
    g.pending = false
    g.waitUntil = nil
    g.spaceDown = input.IsKeyDown(KEY_SPACE)   -- (a Space already held doesn't count as a press)
    g.inBand = false
    g.ready = false
    g.err = 1
end

local function liveOf(g)
    return g.lf or g.kf, g.la or g.ka
end

-- The game tick (from the frame's Think).
local function tick(g)
    local now = CurTime()
    local dt = math.min(0.1, now - (g.last or now))
    g.last = now
    local space = input.IsKeyDown(KEY_SPACE)
    local pressed = space and not g.spaceDown
    g.spaceDown = space
    if g.pending or now < g.t0 then return end
    local t = now - g.t0
    -- keys: A / D frequency, W / S amplitude
    local fr, ar = 1.1 * dt, 0.35 * dt
    if input.IsKeyDown(KEY_A) or input.IsKeyDown(KEY_LEFT) then g.kf = g.kf - fr end
    if input.IsKeyDown(KEY_D) or input.IsKeyDown(KEY_RIGHT) then g.kf = g.kf + fr end
    if input.IsKeyDown(KEY_W) or input.IsKeyDown(KEY_UP) then g.ka = g.ka + ar end
    if input.IsKeyDown(KEY_S) or input.IsKeyDown(KEY_DOWN) then g.ka = g.ka - ar end
    g.kf = math.Clamp(g.kf, F_LO, F_HI)
    g.ka = math.Clamp(g.ka, A_LO, A_HI)
    g.lf, g.la = D.IntelLive(g.sg, t, g.kf, g.ka)
    g.err = D.IntelError(g.sg, g.lf, g.la)
    g.inBand = g.err < g.sg.band
    local ready = t >= D.IntelMinLock()
    g.ready = ready
    if pressed and ready then
        -- (Space: lock here; the server works it out and answers)
        g.pending = true
        g.waitUntil = now + 4
        surface.PlaySound(g.inBand and "buttons/button14.wav" or "buttons/button10.wav")
        local r, kf, ka = g.round, g.kf, g.ka
        act(1, function()
            net.WriteUInt(r, 2)
            net.WriteFloat(t)
            net.WriteFloat(kf)
            net.WriteFloat(ka)
        end)
    end
end

-- The scope: grid, the target band, the live wave.
local function drawScope(g, x, y, w, h, s)
    surface.SetDrawColor(SCOPE_BG)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(GRID)
    for i = 1, 15 do surface.DrawRect(x + math.floor(w * i / 16), y, 1, h) end
    for i = 1, 7 do surface.DrawRect(x, y + math.floor(h * i / 8), w, 1) end
    local mid, amp = y + h / 2, h * 0.4
    local band = g.cfg.band * amp * 1.6
    local lf, la = liveOf(g)
    local cols = 120
    local cw = w / cols
    local ptx, pty, plx, ply
    for i = 0, cols do
        local fx = i / cols
        local ty = mid - g.ta * math.sin(6.2832 * g.tf * fx) * amp
        local ly = mid - la * math.sin(6.2832 * lf * fx) * amp
        local px = x + fx * w
        if i < cols then
            surface.SetDrawColor(BAND)
            surface.DrawRect(px, ty - band, math.ceil(cw), band * 2)
        end
        if ptx then
            surface.SetDrawColor(BAND_EDGE)
            surface.DrawLine(ptx, pty, px, ty)
            local lc = LIVE
            surface.SetDrawColor(LIVE_GLOW)
            surface.DrawLine(plx, ply - 2, px, ly - 2)
            surface.DrawLine(plx, ply + 2, px, ly + 2)
            surface.SetDrawColor(lc)
            for o = -1, 1 do surface.DrawLine(plx, ply + o, px, ly + o) end
        end
        ptx, pty, plx, ply = px, ty, px, ly
    end
    draw.SimpleText(string.format("RX %.3f GHz · DRIFT %d%%", 2.4 + lf * 0.01, math.Round(g.cfg.drift * 100)), UI.Font(12), x + s(10), y + s(8), RX_TEXT)
    draw.SimpleText(g.inBand and "IN BAND" or "OUT OF BAND", UI.Font(12, 700), x + w - s(10), y + s(8), g.inBand and AMBER or TEXT_DIM, TEXT_ALIGN_RIGHT)
end

-- A knob panel: drag left / right or the mouse wheel.
local function knob(parent, k, g, label, keys, get, set, lo, hi)
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    function p:OnMousePressed(code) if code == MOUSE_LEFT then self.drag = gui.MouseX() self:MouseCapture(true) end end
    function p:OnMouseReleased() self.drag = nil self:MouseCapture(false) end
    function p:OnCursorMoved()
        if not self.drag then return end
        local mx = gui.MouseX()
        set(get() + (mx - self.drag) * (hi - lo) / s(400))
        self.drag = mx
    end
    function p:OnMouseWheeled(d) set(get() + d * (hi - lo) / 200) return true end
    function p:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        local r = math.min(h * 0.38, s(46))
        local cx, cy = s(18) + r, h / 2
        draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, KNOB_RIM)
        draw.RoundedBox(r - s(6), cx - r + s(6), cy - r + s(6), (r - s(6)) * 2, (r - s(6)) * 2, KNOB_FACE)
        local f = math.Clamp((get() - lo) / (hi - lo), 0, 1)
        local a = math.rad(-225 + f * 270)
        surface.SetDrawColor(KNOB_MARK)
        for o = -1, 1 do
            surface.DrawLine(cx + o, cy, cx + math.cos(a) * (r - s(8)) + o, cy + math.sin(a) * (r - s(8)))
        end
        local tx = cx + r + s(18)
        draw.SimpleText(label, k.Font(17, 700), tx, cy - s(24), TEXT)
        draw.SimpleText(string.format("%.2f", get()), k.Font(20, 700), tx, cy - s(2), KNOB_MARK)
        draw.SimpleText(keys, k.Font(12), tx, cy + s(22), TEXT_DIM)
    end
    return p
end

local function frame(k, w, h, title, sub)
    close(true)
    local s = k.S
    local f = vgui.Create("EditablePanel")
    f:SetSize(math.min(ScrW() - s(40), s(w)), math.min(ScrH() - s(40), s(h)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f:DockPadding(s(16), s(52), s(16), s(16))
    function f:Paint(fw, fh)
        k.Plate(0, 0, fw, fh, { title = title(), ticks = "all", header = s(40), bg = OPAQUE, sub = sub and sub() or "" })
    end
    function f:OnKeyCodePressed(code) if code == KEY_ESCAPE then close(true) end end
    local x = k.Button(f, "Close", function() close(true) end, { small = true })
    x:SetSize(s(90), s(26))
    x:SetPos(f:GetWide() - s(100), s(7))
    return f
end

-- view 1: cracking
local function openCrack(pad, k, r, seed, wait, why)
    local s = k.S
    local g = {}
    newRound(g, r, seed, wait, why)
    local f = frame(k, 980, 720, function() return "Intel datapad · cracking" end,
        function() return "SIGNAL " .. g.round .. " OF 3 · " .. D.INTEL_ROUND_NAMES[g.round] end)
    D.intelWin = { frame = f, pad = pad, view = 1, g = g }

    local tip = k.Label(f, "Match the signal, then Space to lock. Turn the two knobs so your signal (blue) sits inside the target band (amber); it drifts on its own. Lock inside the band and the next signal comes; lock outside it and you start again at signal 1. Three signals: easy, moderate, hard.", 14, 400, TEXT_DIM)
    tip:Dock(TOP)
    tip:DockMargin(0, 0, 0, s(10))

    local scope = vgui.Create("DPanel", f)
    scope:Dock(TOP)
    scope:SetTall(math.floor(f:GetTall() * 0.46))
    scope:DockMargin(0, 0, 0, s(12))
    function scope:Paint(w, h)
        drawScope(g, 0, 0, w, h, s)
        local now = CurTime()
        local head, sub, col
        if g.pending then
            head, sub, col = "LOCKING…", "Checking the signal", TEXT
        elseif now < g.t0 and g.why == 1 then
            head, sub, col = "SIGNAL " .. (g.round - 1) .. " OF 3 LOCKED", "The next one is harder", LOCKED_COL
        elseif now < g.t0 and g.why == 2 then
            head, sub, col = "SIGNAL LOST", "Locked outside the band: back to signal 1", AMBER
        end
        if not head then return end
        local bw, bh = s(460), s(70)
        local bx, by = (w - bw) / 2, (h - bh) / 2
        draw.RoundedBox(4, bx, by, bw, bh, OVERLAY)
        surface.SetDrawColor(col)
        surface.DrawOutlinedRect(bx, by, bw, bh, 1)
        draw.SimpleText(head, k.Font(24, 800), w / 2, by + s(24), col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(sub, k.Font(13), w / 2, by + s(50), TEXT_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local function busy() return g.pending or CurTime() < g.t0 end
    local knobs = vgui.Create("DPanel", f)
    knobs:Dock(TOP)
    knobs:SetTall(s(120))
    knobs:DockMargin(0, 0, 0, s(12))
    knobs.Paint = nil
    local k1 = knob(knobs, k, g, "FREQUENCY", "drag, wheel, or A / D", function() return g.kf end, function(v) if not busy() then g.kf = math.Clamp(v, F_LO, F_HI) end end, F_MIN, F_MAX)
    local k2 = knob(knobs, k, g, "AMPLITUDE", "drag, wheel, or W / S", function() return g.ka end, function(v) if not busy() then g.ka = math.Clamp(v, A_LO, A_HI) end end, A_MIN, A_MAX)
    function knobs:PerformLayout(w, h)
        local half = (w - s(12)) / 2
        k1:SetPos(0, 0) k1:SetSize(half, h)
        k2:SetPos(half + s(12), 0) k2:SetSize(half, h)
    end

    -- Match bar: full at a perfect match; the mark is the band's edge.
    local bar = vgui.Create("DPanel", f)
    bar:Dock(TOP)
    bar:SetTall(s(44))
    function bar:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("MATCH", k.Font(12, 700), s(14), h / 2, TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local bx, bw = s(70), w - s(70) - s(190)
        local fill = math.Clamp(1 - g.err / (g.sg.band * 3), 0, 1)
        surface.SetDrawColor(LOCK_BG)
        surface.DrawRect(bx, h / 2 - s(7), bw, s(14))
        surface.SetDrawColor(g.inBand and LOCKED_COL or LIVE)
        surface.DrawRect(bx, h / 2 - s(7), bw * fill, s(14))
        surface.SetDrawColor(AMBER)
        surface.DrawRect(bx + math.floor(bw * 2 / 3), h / 2 - s(11), s(2), s(22))
        local hint = not g.ready and "TUNING…" or (g.inBand and "IN BAND · SPACE TO LOCK" or "SPACE TO LOCK")
        draw.SimpleText(hint, k.Font(13, 700), w - s(14), h / 2,
            g.inBand and LOCKED_COL or TEXT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local pips = vgui.Create("DPanel", f)
    pips:Dock(TOP)
    pips:SetTall(s(34))
    pips:DockMargin(0, s(10), 0, 0)
    function pips:Paint(w, h)
        local pw = (w - s(16)) / 3
        for r = 1, 3 do
            local done = r < g.round
            local cur = r == g.round
            local px = (r - 1) * (pw + s(8))
            surface.SetDrawColor(done and PIP_DONE or (cur and PIP_NOW or k.C.row))
            surface.DrawRect(px, 0, pw, h)
            surface.SetDrawColor(done and LOCKED_COL or (cur and LIVE or k.C.edgeLight))
            surface.DrawOutlinedRect(px, 0, pw, h, 1)
            draw.SimpleText(r .. " · " .. D.INTEL_ROUND_NAMES[r] .. (done and " · LOCKED" or ""), k.Font(13, 700), px + pw / 2, h / 2,
                done and LOCKED_COL or (cur and TEXT or TEXT_DIM), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    function f:Think()
        local me = LocalPlayer()
        if not IsValid(pad) or not me:Alive() or me:GetPos():DistToSqr(pad:GetPos()) > D.Cfg("intelRange") ^ 2 then
            Rhylib.Notify(nil, "The signal was lost: stay close to the datapad", "bad", "Datapad")
            close(true)
            return
        end
        if g.waitUntil and CurTime() > g.waitUntil then
            Rhylib.Notify(nil, "No answer from the datapad: try again", "bad", "Datapad")
            close(true)
            return
        end
        tick(g)
    end
end

-- view 0 / 2: a note, or the intel
local function openRead(pad, k, view, title, text, by)
    local s = k.S
    local f = frame(k, 640, view == 0 and 300 or 600, function() return "Intel datapad" end,
        function() return view == 0 and "Encrypted" or "Cracked" end)
    D.intelWin = { frame = f, pad = pad, view = view }
    if view == 0 then
        local l = k.Label(f, "Encrypted. Only field technicians can crack it: bring one here, or call the bomb squad on your datapad.", 15, 400, TEXT)
        l:Dock(TOP)
        l:DockMargin(0, s(20), 0, 0)
        return
    end
    local h = k.Heading(f, title ~= "" and title or "Intel", LIVE)
    h:Dock(TOP)
    local b = k.Label(f, "Cracked by " .. by, 12, 400, TEXT_DIM)
    b:Dock(TOP)
    b:DockMargin(0, s(4), 0, s(10))
    local sp = k.Scroll(f)
    sp:Dock(FILL)
    local t = k.Label(sp, text ~= "" and text or "(The game master hasn't written anything here yet.)", 15, 400, TEXT)
    t:Dock(TOP)
    t:DockMargin(0, 0, s(10), 0)
end

-- view 3: the game master's setup
local function openSetup(pad, k, title, text, by, only, cracked)
    local s = k.S
    local st = { pad = pad, view = 3, cracked = cracked, by = by }
    local f = frame(k, 720, 640, function() return "Intel setup" end,
        function() return st.cracked and ("Cracked by " .. st.by) or "Encrypted" end)
    st.frame = f
    D.intelWin = st
    local lt = k.Label(f, "Title (shown once it's cracked)", 12, 400, TEXT_DIM)
    lt:Dock(TOP)
    local te = k.TextEntry(f, "Title")
    te:Dock(TOP)
    te:SetTall(s(34))
    te:SetValue(title)
    te:DockMargin(0, s(4), 0, s(10))
    local lx = k.Label(f, "Intel (what the troopers read)", 12, 400, TEXT_DIM)
    lx:Dock(TOP)
    local tx = vgui.Create("DTextEntry", f)
    tx:Dock(TOP)
    tx:SetTall(s(220))
    tx:SetMultiline(true)
    tx:SetFont(k.Font(14))
    tx:SetValue(text)
    tx:DockMargin(0, s(4), 0, s(2))
    local cnt = k.Label(f, "", 12, 400, TEXT_DIM)
    cnt:Dock(TOP)
    cnt:DockMargin(0, 0, 0, s(8))
    local lastLen, lastStamp
    function cnt:Think()
        local n = utf8.len(tx:GetValue() or "") or #(tx:GetValue() or "")
        local stamp = UI.themeStamp or 0
        if n == lastLen and stamp == lastStamp then return end
        -- (after a theme switch: the colour and fonts again)
        if lastStamp and stamp ~= lastStamp then
            self:SetFont(k.Font(12, 400))
            if IsValid(tx) then tx:SetFont(k.Font(14)) end
        end
        lastLen, lastStamp = n, stamp
        local max = D.Cfg("intelTextMax")
        self:SetText(n .. " / " .. max .. (n > max and " · the end will be cut" or ""))
        self:SetTextColor(n > max and AMBER or TEXT_DIM)
    end
    tx:SetPaintBackground(false)
    function tx:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        self:DrawTextEntryText(TEXT, CARET, TEXT)
    end
    local lo = k.Label(f, "Once cracked, who can read it", 12, 400, TEXT_DIM)
    lo:Dock(TOP)
    local row = vgui.Create("DPanel", f)
    row:Dock(TOP)
    row:SetTall(s(34))
    row:DockMargin(0, s(4), 0, s(10))
    row.Paint = nil
    local onlyNow = only
    local b1 = k.Button(row, "Anyone who opens it", function() onlyNow = false end, { selected = function() return not onlyNow end })
    local b2 = k.Button(row, "Only who cracked it", function() onlyNow = true end, { selected = function() return onlyNow end })
    function row:PerformLayout(w, h)
        local half = (w - s(8)) / 2
        b1:SetPos(0, 0) b1:SetSize(half, h)
        b2:SetPos(half + s(8), 0) b2:SetSize(half, h)
    end
    local bottom = vgui.Create("DPanel", f)
    bottom:Dock(BOTTOM)
    bottom:SetTall(s(38))
    bottom.Paint = nil
    local save = k.Button(bottom, "Save", function()
        local tt, xx, oo = te:GetValue() or "", tx:GetValue() or "", onlyNow
        act(2, function()
            net.WriteString(D.Clip(tt, D.Cfg("intelTitleMax")))
            net.WriteString(D.Clip(xx, D.Cfg("intelTextMax"), true))
            net.WriteBool(oo)
        end)
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(140))
    local relock = k.Button(bottom, "Lock it again", function() act(3) end, { enabled = function() return st.cracked end })
    relock:Dock(RIGHT)
    relock:SetWide(s(160))
    relock:DockMargin(0, 0, s(8), 0)
end

Rhylib.Net.Receive("dp.intel", function()
    local pad = net.ReadEntity()
    local view = net.ReadUInt(2)
    local title, text, by, only, cracked = "", "", "", false, false
    local round, seed, why, wait = 1, 1, 0, 0
    if view == 1 then
        round, seed, why, wait = net.ReadUInt(2), net.ReadUInt(32), net.ReadUInt(2), net.ReadUInt(7) / 10
    elseif view >= 2 then
        title, text, by, only = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadBool()
        if view == 3 then cracked = net.ReadBool() end
    end
    if not IsValid(pad) then return end
    local k = UI and UI.Kit
    if not k then return end
    local cur = D.intelWin
    -- (the server stopped a crack: it already said why)
    if view == 0 and cur and cur.view == 1 and cur.pad == pad then close(false) return end
    -- (the setup window already open: only its cracked state changes, typing is kept)
    if view == 3 and cur and cur.view == 3 and cur.pad == pad and IsValid(cur.frame) then
        cur.cracked = cracked
        cur.by = by
        return
    end
    -- (the next round, or round 1 again after a miss: same window)
    if view == 1 and cur and cur.view == 1 and cur.pad == pad and cur.g and IsValid(cur.frame) then
        newRound(cur.g, math.Clamp(round, 1, 3), seed, wait, why)
        return
    end
    -- (the crack finished: the cracking window turns into the intel)
    if view == 1 then openCrack(pad, k, math.Clamp(round, 1, 3), seed, wait, why)
    elseif view == 3 then openSetup(pad, k, title, text, by, only, cracked)
    else openRead(pad, k, view, title, text, by) end
end)
