--[[
    The bomb manual: a datapad tab (rhylib_datapad) for players with the
    Field technician skill "Bomb manual". A jump bar, then: the approach
    and safe order as numbered steps, the tool kit, probe readings as
    coloured chips, safeguards (what fires it / how to beat it), module
    cards, the logic chip table drawn as blinks and switches, the
    interference device, mines, training and why bombs go off.
    Built from the shared tables and config, so it never disagrees with
    the game.
]]

local E = Rhylib.EOD

local function hasManual()
    return E.Skill(LocalPlayer(), "eod_manual")
end

-- Section colours.
local COL = {
    start = Color(90, 170, 255),
    order = Color(70, 190, 120),
    tools = Color(200, 200, 205),
    probe = Color(245, 200, 60),
    guard = Color(235, 90, 80),
    mods = Color(170, 120, 235),
    chip = Color(60, 210, 220),
    device = Color(110, 150, 255),
    mines = Color(240, 140, 50),
    train = Color(245, 217, 10),
    boom = Color(220, 60, 60),
}

local RED, AMBER, GREEN = Color(229, 72, 77), Color(245, 170, 40), Color(70, 190, 100)
local BLUE, PURPLE, CYAN, GREY = Color(62, 142, 247), Color(164, 110, 224), Color(60, 210, 220), Color(140, 146, 152)

local function metres(units) return math.floor((units or 0) / E.UNITS_PER_M + 0.5) end

-- Module steps (short lines, in order).
local MODULE_STEPS = {
    fuse = { "Watch the heat bar: past 100° it fires.", "Every cut and jumper heats the board; so does the torch.", "Pause between steps: it cools down by itself." },
    stab = { "Read the dose printed on the charge.", "Cut the detonator line as normal.", "Set the slider to exactly that dose, then Inject." },
    tilt = { "Once the lid is off, a level bubble drifts.", "Nudge it back to the middle (buttons or arrow keys).", "Cuts and jumpers jolt it: re-centre before the next step." },
    sealed = { "The detonator line runs under a welded plate.", "Torch it open in short bursts (it heats the board).", "Then probe and cut that line as normal." },
    relay = { "Remote bombs only: antenna, relay and trigger wires are armoured.", "Put a jumper from the relay to the dummy load: the remote can't reach the detonator.", "Never short the relay or jumper it to the detonator." },
    chip = { "An LED blinks a code of short and long flashes.", "Find the code in the Logic chip table and set the four switches.", "Press Enter before cutting the logic or detonator line." },
    liquid = { "Kill every supply first.", "Open the drain valve while the needle is in the green band.", "Drain it before the detonator line." },
    fake = { "A cover hides the real board.", "X-ray it (2 shots) to see the mount order.", "Cut the three mount wires in that order." },
}
local RANK_NAME = { "Basic", "Advanced", "Expert" }

local function build(content, k)
    if not (k and IsValid(content)) then return end
    local s = k.S
    local C = k.C
    local sensorM = metres(E.Cfg("sensorRange") or 315)
    local wakeM = metres(E.Cfg("timerWake") or 900)
    local capS = E.Cfg("capDrain") or 15
    local leakS = E.Cfg("leakTime") or 20
    local inspectS = E.Cfg("inspectTime") or 2.5

    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local anchors = {}

    -- Helpers -----------------------------------------------------------

    local function chipW(text, font)
        surface.SetFont(font)
        return (surface.GetTextSize(text)) + s(12)
    end
    local function drawChip(text, col, x, y, h, font)
        font = font or k.Font(12, 800)
        local w = chipW(text, font)
        draw.RoundedBox(s(3), x, y, w, h, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 255))
        surface.SetDrawColor(col.r, col.g, col.b, 200)
        surface.DrawOutlinedRect(x, y, w, h, 1)
        draw.SimpleText(text, font, x + w / 2, y + h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return w
    end

    local function section(id, title, col, intro)
        local h = k.Heading(sp, title, col)
        h:Dock(TOP)
        h:DockMargin(0, s(14), s(10), s(6))
        anchors[#anchors + 1] = { id = id, title = title, col = col, panel = h }
        if intro then
            local l = k.Label(sp, intro, 14, 400, C.textDim)
            l:Dock(TOP)
            l:DockMargin(0, 0, s(12), s(6))
        end
        return h
    end

    -- A dark row: optional coloured strip, something drawn on the left
    -- (leftW wide), wrapped text on the right; optional second text column.
    local function row(opts)
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:DockMargin(0, 0, s(10), s(3))
        local leftW = opts.leftW or s(200)
        local l1 = k.Label(p, opts.text or "", 13, 400, opts.textCol or C.text)
        local l2 = opts.text2 and k.Label(p, opts.text2, 13, 400, C.textDim)
        local function relayout() if IsValid(p) then p:InvalidateLayout() end end
        l1.OnSizeChanged = relayout
        if l2 then l2.OnSizeChanged = relayout end
        function p:PerformLayout(w)
            local x = leftW + s(10)
            local avail = w - x - s(8)
            local w1 = l2 and math.floor(avail * 0.5) or avail
            l1:SetPos(x, s(6))
            l1:SetWide(w1)
            l1:InvalidateLayout(true)
            l1:SizeToContentsY()
            local tall = l1:GetTall()
            if l2 then
                l2:SetPos(x + w1 + s(10), s(6))
                l2:SetWide(avail - w1 - s(10))
                l2:InvalidateLayout(true)
                l2:SizeToContentsY()
                tall = math.max(tall, l2:GetTall())
            end
            self:SetTall(math.max(opts.minH or s(30), tall + s(12)))
        end
        function p:Paint(w, h)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            if opts.strip then
                k.SetCol(opts.strip)
                surface.DrawRect(0, 0, s(3), h)
            end
            if opts.left then opts.left(w, h) end
        end
        return p
    end

    -- A table header line over row()s.
    local function header(a, b, c, leftW)
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:SetTall(s(20))
        p:DockMargin(0, 0, s(10), s(2))
        leftW = leftW or s(200)
        function p:Paint(w, h)
            local f = k.Font(11, 700)
            draw.SimpleText(string.upper(a), f, s(10), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local x = leftW + s(10)
            draw.SimpleText(string.upper(b), f, x, h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if c then
                local avail = w - x - s(8)
                draw.SimpleText(string.upper(c), f, x + math.floor(avail * 0.5) + s(10), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- Numbered step with a round badge.
    local function step(n, text, col, sub)
        return row({
            leftW = s(34), minH = s(34), text = text, strip = col,
            left = function(w, h)
                local r = s(11)
                draw.RoundedBox(r, s(12), s(17) - r, r * 2, r * 2, col)
                draw.SimpleText(tostring(n), k.Font(13, 800), s(12) + r, s(17), Color(14, 16, 15), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end,
        })
    end

    local function note(text, col)
        local l = k.Label(sp, text, 13, 400, col or C.textDim)
        l:Dock(TOP)
        l:DockMargin(s(4), s(4), s(12), s(4))
        return l
    end

    -- Title + jump bar ------------------------------------------------------

    local top = vgui.Create("DPanel", sp)
    top:Dock(TOP)
    top:DockMargin(0, 0, s(10), s(4))
    function top:Paint(w, h)
        k.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(COL.guard)
        surface.DrawRect(0, 0, w, s(3))
        draw.SimpleText("BOMB MANUAL", k.Font(22, 800), s(12), s(10), C.text)
        draw.SimpleText("Field technician · every bomb is a small circuit: the colours change, the rules don't.", k.Font(13, 400), s(12), s(38), C.textDim)
    end
    local jump = vgui.Create("DPanel", top)
    jump.Paint = nil
    local jumpBtns = {}
    function top:PerformLayout(w)
        jump:SetPos(s(10), s(62))
        jump:SetWide(w - s(20))
        local x, y, bh, gap = 0, 0, s(24), s(6)
        for _, b in ipairs(jumpBtns) do
            local bw = chipW(string.upper(b.label), k.Font(12, 700)) + s(18)
            if x > 0 and x + bw > jump:GetWide() then x, y = 0, y + bh + gap end
            b:SetPos(x, y)
            b:SetSize(bw, bh)
            x = x + bw + gap
        end
        jump:SetTall(y + bh)
        self:SetTall(s(62) + y + bh + s(10))
    end

    -- 1. Approach ---------------------------------------------------------------

    section("start", "Start here", COL.start, "The first thirty seconds decide most bombs. Do these before touching a single wire.")
    local approach = {
        "Stop at the edge. Motion sensors watch " .. sensorM .. " m around the bomb: walk in, never run (crouch-walk for a sensitive one).",
        "Hold Inspect (" .. inspectS .. " s). It names the detonator, anti-jam, motion sensor, lid switch and charge. It also says how many modules there are.",
        "Remote bomb? With anti-jam, don't jam it yet. Without, place an interference device: wideband also blinds the motion sensor.",
        "Lid switch? Release the tab first, then lift the lid.",
        "Probe every wire before cutting. Decoys read DEAD and do nothing; note what each one is.",
    }
    for i, t in ipairs(approach) do step(i, t, COL.start) end

    -- 2. Safe order ---------------------------------------------------------------

    section("order", "Make it safe", COL.order, "Carry on in this order. Skip what the bomb doesn't have.")
    local order = {
        "Cut MON (anti-jam monitor) and LOOP 3V (collapse sense) if there are any.",
        "Self-powered charge (LIVE 9V · SENSE)? Short the charge cell: jumper its + to its −.",
        "Cut every battery supply, or short the batteries. A running timer stops.",
        "Capacitor? Wait until it reads under 5% (about " .. capS .. " s) or short it, then cut its feed.",
        "Handle the modules (chip, liquid, sealed plate, relay): see Modules.",
        "The detonator line must read DEAD. Cut it.",
        "Gas or virus charge? Seal the valve within " .. leakS .. " s. Stabiliser? Inject the dose.",
    }
    for i, t in ipairs(order) do step(#approach + i, t, COL.order) end

    -- 3. Tool kit ------------------------------------------------------------------

    section("tools", "Tool kit", COL.tools, "Everything comes in the EOD kit. Without one you can only look and inspect.")
    local tools = {
        { "PROBE", "Reads a wire: power, signal, what it does." },
        { "CUTTERS", "Cut a wire. Can't be undone." },
        { "JUMPER", (E.Cfg("jumpers") or 3) .. " per bomb. Joins two terminals; a part's own + and − shorts it." },
        { "TORCH", "Opens a sealed plate. Heats the board while it burns." },
        { "X-RAY", (E.Cfg("xrays") or 2) .. " shots. Shows a fake board's mount order for a few seconds." },
    }
    for _, t in ipairs(tools) do
        row({ leftW = s(110), text = t[2], strip = COL.tools, left = function(w, h)
            drawChip(t[1], COL.tools, s(10), h / 2 - s(10), s(20))
        end })
    end

    -- 4. Probe readings ---------------------------------------------------------------

    section("probe", "Probe readings", COL.probe, "What the probe says, and what to do about it.")
    local readings = {
        { "LIVE 9V", RED, "Battery power on it. Cutting a live feed, timer or detonator line fires the bomb." },
        { "LIVE · CAP n%", AMBER, "The capacitor still holds charge. It drains about " .. capS .. " s after the supply is cut, or short it." },
        { "DEAD", GREEN, "No power. Safe to cut, unless a safeguard says otherwise." },
        { "SIGNAL · f GHz", BLUE, "Antenna lead to the receiver; the frequency is for a tuned device. JAMMED = your device covers it." },
        { "MON", AMBER, "Anti-jam monitor watching the receiver. Cut it first; then you may jam the bomb or cut the antenna." },
        { "LOOP 3V", PURPLE, "Collapse sense line. Cut it before any battery supply." },
        { "LOOP 5V", PURPLE, "Tamper loop. Cutting it halves the time left on a running timer: leave it." },
        { "LIVE 9V · SENSE", RED, "Self-powered charge: it fires if the bomb loses power. Short the charge cell first (+ to −)." },
        { "LOGIC · pulsing", CYAN, "Logic chip line: set the chip to safe mode first." },
        { "RELAY / TRIGGER", GREY, "Armoured signal relay: redirect it into the dummy load with a jumper." },
    }
    for _, r in ipairs(readings) do
        row({ leftW = s(150), text = r[3], left = function(w, h)
            drawChip(r[1], r[2], s(8), math.min(h / 2, s(15)) - s(10), s(20))
        end })
    end

    -- 5. Safeguards ------------------------------------------------------------------

    section("guard", "Safeguards", COL.guard, "Each one is a way the bomb fights back.")
    header("Safeguard", "Fires when", "How to beat it", s(150))
    local guards = {
        { "Anti-jam", "Its remote signal is lost: jammed, or the antenna is cut.", "Cut MON first. Then jam it or cut the antenna." },
        { "Motion sensor", "Someone moves fast within " .. sensorM .. " m (sensitive: even walking).", "Walk in (crouch-walk if sensitive), or blind it with a wideband device." },
        { "Lid switch", "The lid comes off with the tab still in.", "Release the tab, then lift the lid." },
        { "Collapse circuit", "A battery supply is cut or shorted while armed.", "Cut LOOP 3V first." },
        { "Capacitor", "Its feed is cut while it still holds charge.", "Kill the supply, then wait ~" .. capS .. " s or short it." },
        { "Timer", "It reaches zero. Starts when someone comes within " .. wakeM .. " m.", "Cut the power to stop it. Leave LOOP 5V alone." },
        { "Remote", "A spotter sends the signal, any time.", "Jam it (no anti-jam), cut the antenna, or redirect a relay." },
        { "Self-powered charge", "Power stops while its sensor is armed.", "Short the charge cell before cutting any power." },
    }
    for _, g in ipairs(guards) do
        row({ leftW = s(150), text = g[2], text2 = g[3], strip = COL.guard, left = function(w, h)
            draw.SimpleText(g[1], k.Font(13, 700), s(10), s(15), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end })
    end

    -- 6. Modules ----------------------------------------------------------------------

    section("mods", "Modules", COL.mods, "Extra mechanisms on harder bombs. Inspect tells you how many; lift the lid to see which.")
    for _, m in ipairs(E.MODS) do
        local steps = MODULE_STEPS[m.id] or {}
        local card = vgui.Create("DPanel", sp)
        card:Dock(TOP)
        card:DockMargin(0, 0, s(10), s(4))
        local labels = {}
        for i, t in ipairs(steps) do
            labels[i] = k.Label(card, t, 13, 400, C.text)
            labels[i].OnSizeChanged = function() if IsValid(card) then card:InvalidateLayout() end end
        end
        function card:PerformLayout(w)
            local y = s(32)
            for _, l in ipairs(labels) do
                l:SetPos(s(36), y)
                l:SetWide(w - s(48))
                l:InvalidateLayout(true)
                l:SizeToContentsY()
                y = y + l:GetTall() + s(4)
            end
            self:SetTall(y + s(6))
        end
        function card:Paint(w, h)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(COL.mods)
            surface.DrawRect(0, 0, s(3), h)
            draw.SimpleText(m.name, k.Font(15, 800), s(12), s(15), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            -- Difficulty pips + name, remote tag.
            local x = w - s(12)
            local rk = RANK_NAME[m.rank] or ""
            surface.SetFont(k.Font(12, 700))
            local tw = surface.GetTextSize(rk)
            draw.SimpleText(rk, k.Font(12, 700), x, s(15), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            x = x - tw - s(8)
            for i = 3, 1, -1 do
                local c = i <= m.rank and COL.mods or Color(60, 60, 66)
                draw.RoundedBox(s(2), x - s(8), s(11), s(8), s(8), c)
                x = x - s(11)
            end
            if m.remote then
                local f = k.Font(11, 800)
                drawChip("REMOTE ONLY", BLUE, x - s(8) - chipW("REMOTE ONLY", f), s(6), s(18), f)
            end
            for i, l in ipairs(labels) do
                local _, ly = l:GetPos()
                draw.SimpleText(tostring(i), k.Font(12, 800), s(22), ly + s(1), COL.mods, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end
    end

    -- 7. Logic chip codes ------------------------------------------------------------

    section("chip", "Logic chip codes", COL.chip, "Watch the LED: dots are short flashes, bars long ones. Set the switches left to right (up = 1), then press Enter.")
    local codes = E.CHIP_CODES or {}
    local grid = vgui.Create("DPanel", sp)
    grid:Dock(TOP)
    grid:DockMargin(0, 0, s(10), s(4))
    function grid:PerformLayout(w)
        self:SetTall(math.ceil(#codes / 2) * s(48))
    end
    function grid:Paint(w, h)
        local cw, ch = (w - s(4)) / 2, s(44)
        for i, c in ipairs(codes) do
            local cx = ((i - 1) % 2) * (cw + s(4))
            local cy = math.floor((i - 1) / 2) * s(48)
            k.SetCol(C.row)
            surface.DrawRect(cx, cy, cw, ch)
            k.SetCol(COL.chip)
            surface.DrawRect(cx, cy, s(3), ch)
            -- Blink pattern.
            local x = cx + s(14)
            for ch2 in string.gmatch(c[1], ".") do
                local bw = ch2 == "L" and s(22) or s(8)
                draw.RoundedBox(s(2), x, cy + ch / 2 - s(4), bw, s(8), COL.chip)
                x = x + bw + s(6)
            end
            draw.SimpleText(">", k.Font(16, 700), cx + s(110), cy + ch / 2, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            -- Switches.
            local sx = cx + s(134)
            for j = 1, #c[2] do
                local on = string.sub(c[2], j, j) == "1"
                local swx = sx + (j - 1) * s(26)
                draw.RoundedBox(s(3), swx, cy + s(6), s(18), s(32), Color(30, 34, 32))
                draw.RoundedBox(s(2), swx + s(3), on and cy + s(9) or cy + s(23), s(12), s(12), on and COL.chip or GREY)
            end
            if cw > s(300) then draw.SimpleText(c[2], k.Font(13, 700), cx + cw - s(10), cy + ch / 2, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        end
    end

    -- 8. Interference device -----------------------------------------------------------

    section("device", "Interference device", COL.device, "Place it from your inventory (right-click). Needs a power cell.")
    row({ leftW = s(110), text = "Blocks every remote signal and blinds motion sensors inside its circle. Also jams your own radio and compass there.", strip = COL.device,
        left = function(w, h) drawChip("WIDEBAND", COL.device, s(10), math.min(h / 2, s(15)) - s(10), s(20)) end })
    row({ leftW = s(110), text = "Blocks one frequency (read it with the probe or the scanner), lasts four times longer and leaves your radio alone. A hopping receiver jumps away every ~" .. (E.Cfg("hopEvery") or 25) .. " s.", strip = COL.device,
        left = function(w, h) drawChip("TUNED", COL.device, s(10), math.min(h / 2, s(15)) - s(10), s(20)) end })
    note("Signal blackout (Sapper skill): your wideband device also jams droids inside it. Their commanders' boost stops, they react half as fast, and their artillery can't fire on anyone inside.", C.textDim)
    header("Radius", "Wideband per cell", "Tuned per cell", s(80))
    for _, r in ipairs({ 3, 5, 8, 10, 15 }) do
        local wide = string.FormattedTime(E.CellLife(r, false, false), "%02i:%02i")
        local tuned = string.FormattedTime(E.CellLife(r, true, false), "%02i:%02i")
        row({ leftW = s(80), minH = s(26), text = wide, text2 = tuned, left = function(w, h)
            draw.SimpleText(r .. " m", k.Font(13, 700), s(10), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end })
    end

    -- 9. Mines ----------------------------------------------------------------------------

    section("mines", "Mines", COL.mines, "Half buried and hard to see: only a few metres off, unless someone marked them or a scanner shows them. AP mines need one safety pin, LAP (large) mines two and blast much wider.")
    local mineSteps = {
        "It clicked? Freeze. Moving, jumping or stepping off sets it off. Call EOD.",
        "Someone else with an EOD kit: E on the mine, hold Dig until the fuse shows.",
        "Push the safety pin (Space) while the needle is inside the green zone. A wrong push sets it off.",
        "Pinned = safe: whoever stood on it can step off. Hold Lift to take it away.",
    }
    for i, t in ipairs(mineSteps) do step(i, t, COL.mines) end
    row({ leftW = s(110), text = "LMB switches the beam on: mines in it are outlined and it beeps faster as you close in. RMB marks the mine nearest your crosshair for everyone (red flag).", strip = COL.mines,
        left = function(w, h) drawChip("SCANNER", COL.mines, s(10), math.min(h / 2, s(15)) - s(10), s(20)) end })
    row({ leftW = s(110), text = "Grenades and other blasts set mines off from a distance, and so does shooting one you can see. Mines close together set each other off.", strip = COL.mines,
        left = function(w, h) drawChip("CLEARING", COL.mines, s(10), math.min(h / 2, s(15)) - s(10), s(20)) end })
    row({ leftW = s(110), text = "Blue outline = one of ours (Sapper skill). Only droids set them off and the blast only hurts droids: walk over them. Whoever planted one picks it up with E.", strip = COL.mines,
        left = function(w, h) drawChip("REPUBLIC", Color(80, 160, 255), s(10), math.min(h / 2, s(15)) - s(10), s(20)) end })

    -- 10. Training ---------------------------------------------------------------------

    section("train", "Training", COL.train)
    note("Training bombs and mines (yellow) never hurt anyone. A training bomb beeps twice each time it arms: a mistake shows what went wrong and it re-arms with the same setup. Anyone near one can set it up: the defusal window's Training setup builds any bomb (or rolls a random one); a training mine's window picks AP or LAP, difficulty, pins and whether it hides.", C.text)

    -- 11. Last resort + causes -------------------------------------------------------------

    section("boom", "Why bombs go off", COL.boom, "Last resort: a droid popper's EMP has about a 1 in 10 chance to fry a bomb. Don't count on it.")
    header("Cause", "How to avoid it", nil, s(170))
    local shown = {}
    for _, key in ipairs({ "motion", "antijam", "antenna", "lid", "collapse", "feed", "det", "tmrline", "detshort", "sensor", "capshort", "jumpdet",
        "relayshort", "relaydet", "tilt", "heat", "chip", "chipwrong", "liquid", "liquidpower", "liquidfull", "fake", "stab", "leak", "timer", "remote", "mine", "minepin" }) do
        local c = E.CAUSES[key]
        if c and c[3] and c[3] ~= "" and not shown[c[1] .. c[3]] then
            shown[c[1] .. c[3]] = true
            row({ leftW = s(170), text = c[3], strip = COL.boom, left = function(w, h)
                draw.SimpleText(c[1], k.Font(13, 700), s(10), s(15), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end })
        end
    end

    -- Jump bar buttons (now that the anchors exist).
    for _, a in ipairs(anchors) do
        local b = k.Button(jump, a.title, function()
            if not (IsValid(sp) and IsValid(a.panel)) then return end
            local _, y = sp:GetCanvas():GetChildPosition(a.panel)
            sp:GetVBar():AnimateTo(math.max(0, y - s(4)), 0.3, 0, 0.5)
        end, { small = true, col = a.col })
        b.label = a.title
        jumpBtns[#jumpBtns + 1] = b
    end
    top:InvalidateLayout()
end

-- Datapad hooks (rhylib_datapad's TABS entry "eod" calls these).
local function register()
    local D = Rhylib.Datapad
    if not D then return end
    D.EodManualBuild = build
    D.HasEodManual = hasManual
end
register()
Rhylib.Hook.Add("InitPostEntity", "eod.manual", register)
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "eod.manual", function(id) if id == "datapad" then register() end end)
