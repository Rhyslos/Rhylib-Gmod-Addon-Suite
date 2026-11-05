--[[
    Intel datapads (client): the window net dp.intel opens (sv_95_intel.lua).

      view 0  encrypted, not a field technician: a short note.
      view 1  cracking: three rounds (EASY, MODERATE, HARD). The scope
              shows the target pattern (amber band) and your signal
              (blue). Two knobs, frequency (A / D, or drag / wheel) and
              amplitude (W / S), move your signal; it drifts on its own
              (D.IntelRound: drift, band, hold; round 3 also jumps).
              Inside the band the lock bar fills, outside it drains.
              Full: the round is locked (op 1 to the server), "Next
              signal" starts the next one; after the third the server
              sends the intel.
      view 2  cracked: the title and text the game master wrote.
      view 3  game master setup: title, text, who reads it once
              cracked, Save, Lock it again.
    UI closer "datapad.intel". Closing sends op 4.
]]

local D = Rhylib.Datapad
local UI = Rhylib.UI

-- (D.intelWin: the open window { frame, pad, view, ... }; kept on refresh)

local OPAQUE = Color(14, 16, 15, 255)
local SCOPE_BG, GRID = Color(7, 16, 12), Color(18, 38, 27)
local BAND, BAND_EDGE = Color(239, 159, 39, 46), Color(239, 159, 39, 150)
local LIVE, LIVE_GLOW = Color(133, 183, 235), Color(133, 183, 235, 60)
local LOCKED_COL, LOCK_BG = Color(151, 196, 89), Color(11, 12, 11)
local KNOB_RIM, KNOB_FACE, KNOB_MARK = Color(58, 61, 57), Color(38, 43, 40), Color(133, 183, 235)
local TEXT_DIM, TEXT, AMBER = Color(169, 168, 160), Color(228, 227, 220), Color(239, 159, 39)
local OVERLAY = Color(14, 16, 15, 225)
local LOCKED_BAND, PIP_DONE, PIP_NOW, CARET, RX_TEXT = Color(151, 196, 89, 40), Color(26, 42, 23), Color(48, 64, 90), Color(70, 100, 140), Color(95, 138, 112)

local F_MIN, F_MAX, A_MIN, A_MAX = 1, 4, 0.25, 1
local F_LO, F_HI, A_LO, A_HI = 0, 5, 0, 1.4   -- (how far the knobs turn: past the targets, so drift can always be caught)
local SAMPLES = 96

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

-- A new round: a target pattern, the knobs somewhere else, fresh drift.
local function newRound(g, r)
    g.round = r
    g.cfg = D.IntelRound(r)
    g.tf = math.Rand(F_MIN + 0.4, F_MAX - 0.4)
    g.ta = math.Rand(0.5, 0.8)
    g.kf = math.Clamp(g.tf + (math.random(2) == 1 and -1 or 1) * math.Rand(0.8, 1.4), F_MIN, F_MAX)
    g.ka = math.Clamp(g.ta + (math.random(2) == 1 and -1 or 1) * math.Rand(0.2, 0.35), A_MIN, A_MAX)
    g.p = { math.Rand(0, 6.28), math.Rand(0, 6.28), math.Rand(0, 6.28), math.Rand(0, 6.28) }
    g.walkF, g.walkA = 0, 0
    g.jumpF, g.jumpA, g.nextJump = 0, 0, CurTime() + math.Rand(3, 6)
    g.lock = 0
    g.locked = false
    g.inBand = false
    g.err = 1
    g.t0 = CurTime()
end

-- Drift of frequency and amplitude at time t (added to the knobs).
local function drift(g, t, dt)
    local d = g.cfg.drift
    -- (a random walk scaled by the square root of the frame time: the same at any frame rate)
    local sq = math.sqrt(dt)
    g.walkF = math.Clamp(g.walkF + (math.random() - 0.5) * d * sq * 0.4, -d, d)
    g.walkA = math.Clamp(g.walkA + (math.random() - 0.5) * d * sq * 0.12, -d * 0.3, d * 0.3)
    if g.cfg.jumps and t >= g.nextJump then
        g.jumpF = g.jumpF + (math.random(2) == 1 and -1 or 1) * math.Rand(0.25, 0.45)
        g.jumpA = g.jumpA + (math.random(2) == 1 and -1 or 1) * math.Rand(0.05, 0.12)
        g.nextJump = t + math.Rand(3, 6)
    end
    -- (jumps fade out slowly, so the player has to catch them)
    g.jumpF = math.Clamp(g.jumpF * math.max(0, 1 - dt * 0.5), -0.45, 0.45)
    g.jumpA = math.Clamp(g.jumpA * math.max(0, 1 - dt * 0.5), -0.12, 0.12)
    local df = d * (0.6 * math.sin(t * 0.7 + g.p[1]) + 0.4 * math.sin(t * 1.9 + g.p[2])) + g.walkF + g.jumpF
    local da = d * 0.3 * (0.6 * math.sin(t * 0.9 + g.p[3]) + 0.4 * math.sin(t * 2.3 + g.p[4])) + g.walkA + g.jumpA
    return math.Clamp(df, -1, 1), math.Clamp(da, -0.25, 0.25)
end

local function liveOf(g)
    return math.Clamp(g.kf + (g.df or 0), 0.5, 5), math.Clamp(g.ka + (g.da or 0), 0.05, 1.3)
end

-- Mean gap between the two waves (0 = on top of each other).
local function errorOf(g)
    local lf, la = liveOf(g)
    local sum = 0
    for i = 0, SAMPLES - 1 do
        local x = i / (SAMPLES - 1)
        sum = sum + math.abs(la * math.sin(6.2832 * lf * x) - g.ta * math.sin(6.2832 * g.tf * x))
    end
    return sum / SAMPLES
end

-- The game tick (from the frame's Think).
local function tick(g)
    local now = CurTime()
    local dt = math.min(0.1, now - (g.last or now))
    g.last = now
    if g.locked then return end
    g.df, g.da = drift(g, now - g.t0, dt)
    -- keys: A / D frequency, W / S amplitude
    local fr, ar = 1.1 * dt, 0.35 * dt
    if input.IsKeyDown(KEY_A) or input.IsKeyDown(KEY_LEFT) then g.kf = g.kf - fr end
    if input.IsKeyDown(KEY_D) or input.IsKeyDown(KEY_RIGHT) then g.kf = g.kf + fr end
    if input.IsKeyDown(KEY_W) or input.IsKeyDown(KEY_UP) then g.ka = g.ka + ar end
    if input.IsKeyDown(KEY_S) or input.IsKeyDown(KEY_DOWN) then g.ka = g.ka - ar end
    g.kf = math.Clamp(g.kf, F_LO, F_HI)
    g.ka = math.Clamp(g.ka, A_LO, A_HI)
    g.err = errorOf(g)
    g.inBand = g.err < g.cfg.band
    if g.inBand then g.lock = g.lock + dt / g.cfg.hold
    else g.lock = g.lock - dt / (g.cfg.hold * 2) end
    g.lock = math.Clamp(g.lock, 0, 1)
    if g.lock >= 1 then
        g.locked = true
        surface.PlaySound("buttons/button14.wav")
        local r = g.round
        if r == 3 then g.waitUntil = CurTime() + 4 end
        act(1, function() net.WriteUInt(r, 2) end)
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
            surface.SetDrawColor(g.locked and LOCKED_BAND or BAND)
            surface.DrawRect(px, ty - band, math.ceil(cw), band * 2)
        end
        if ptx then
            surface.SetDrawColor(g.locked and LOCKED_COL or BAND_EDGE)
            surface.DrawLine(ptx, pty, px, ty)
            local lc = g.locked and LOCKED_COL or LIVE
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
local function openCrack(pad, k)
    local s = k.S
    local g = {}
    newRound(g, 1)
    local f = frame(k, 980, 720, function() return "Intel datapad · cracking" end,
        function() return "SIGNAL " .. g.round .. " OF 3 · " .. D.INTEL_ROUND_NAMES[g.round] end)
    D.intelWin = { frame = f, pad = pad, view = 1, g = g }

    local tip = k.Label(f, "Turn the two knobs so your signal (blue) sits inside the target band (amber). It drifts on its own: keep correcting until the lock bar is full. Three signals: easy, moderate, hard.", 14, 400, TEXT_DIM)
    tip:Dock(TOP)
    tip:DockMargin(0, 0, 0, s(10))

    local scope = vgui.Create("DPanel", f)
    scope:Dock(TOP)
    scope:SetTall(math.floor(f:GetTall() * 0.46))
    scope:DockMargin(0, 0, 0, s(12))

    local nextBtn = k.Button(scope, function() return g.round < 3 and "Next signal" or "Reading the intel…" end, function()
        if g.locked and g.round < 3 then newRound(g, g.round + 1) end
    end, { accent = true })
    nextBtn:SetSize(s(220), s(44))
    -- (the locked box sits above the button, drawn with the scope so the button stays on top)
    function scope:PerformLayout(w, h) nextBtn:SetPos((w - nextBtn:GetWide()) / 2, h / 2 + s(20)) end
    local lockedText = { "SIGNAL 1 OF 3 LOCKED", "SIGNAL 2 OF 3 LOCKED", "SIGNAL 3 OF 3 LOCKED" }
    function scope:Paint(w, h)
        drawScope(g, 0, 0, w, h, s)
        if not g.locked then return end
        local bw, bh = s(420), s(70)
        local bx, by = (w - bw) / 2, h / 2 - bh - s(6)
        draw.RoundedBox(4, bx, by, bw, bh, OVERLAY)
        surface.SetDrawColor(LOCKED_COL)
        surface.DrawOutlinedRect(bx, by, bw, bh, 1)
        draw.SimpleText(lockedText[g.round], k.Font(24, 800), w / 2, by + s(24), LOCKED_COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(g.round < 3 and "The next one is harder" or "Reading the intel…", k.Font(13), w / 2, by + s(50), TEXT_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    function scope:Think() nextBtn:SetVisible(g.locked and g.round < 3) end

    local knobs = vgui.Create("DPanel", f)
    knobs:Dock(TOP)
    knobs:SetTall(s(120))
    knobs:DockMargin(0, 0, 0, s(12))
    knobs.Paint = nil
    local k1 = knob(knobs, k, g, "FREQUENCY", "drag, wheel, or A / D", function() return g.kf end, function(v) if not g.locked then g.kf = math.Clamp(v, F_LO, F_HI) end end, F_MIN, F_MAX)
    local k2 = knob(knobs, k, g, "AMPLITUDE", "drag, wheel, or W / S", function() return g.ka end, function(v) if not g.locked then g.ka = math.Clamp(v, A_LO, A_HI) end end, A_MIN, A_MAX)
    function knobs:PerformLayout(w, h)
        local half = (w - s(12)) / 2
        k1:SetPos(0, 0) k1:SetSize(half, h)
        k2:SetPos(half + s(12), 0) k2:SetSize(half, h)
    end

    local bar = vgui.Create("DPanel", f)
    bar:Dock(TOP)
    bar:SetTall(s(44))
    function bar:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("LOCK", k.Font(12, 700), s(14), h / 2, TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local bx, bw = s(70), w - s(70) - s(80)
        surface.SetDrawColor(LOCK_BG)
        surface.DrawRect(bx, h / 2 - s(7), bw, s(14))
        surface.SetDrawColor(LOCKED_COL)
        surface.DrawRect(bx, h / 2 - s(7), bw * g.lock, s(14))
        draw.SimpleText(math.floor(g.lock * 100) .. "%", k.Font(14, 700), w - s(14), h / 2, LOCKED_COL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local pips = vgui.Create("DPanel", f)
    pips:Dock(TOP)
    pips:SetTall(s(34))
    pips:DockMargin(0, s(10), 0, 0)
    function pips:Paint(w, h)
        local pw = (w - s(16)) / 3
        for r = 1, 3 do
            local done = r < g.round or (r == g.round and g.locked)
            local cur = r == g.round and not g.locked
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
    local lastLen
    function cnt:Think()
        local n = utf8.len(tx:GetValue() or "") or #(tx:GetValue() or "")
        if n == lastLen then return end
        lastLen = n
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
    if view >= 2 then
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
    -- (the crack finished: the cracking window turns into the intel)
    if view == 1 then openCrack(pad, k)
    elseif view == 3 then openSetup(pad, k, title, text, by, only, cracked)
    else openRead(pad, k, view, title, text, by) end
end)
