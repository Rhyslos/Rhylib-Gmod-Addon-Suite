--[[
    GM window (client): E on a bomb with the toolgun out, for staff with
    rhylib.eod.gm. Shows the answers (wire kinds, chip code, dose, fake
    board order), and sets the bomb up: re-roll, type, custom build,
    timer, remote signal, spotter, detonate, disarm.

    Opened by net eod.gmopen (the server checks rhylib.eod.gm); every
    button sends net eod.gm (bomb, op 4 bits, argument) and the server
    answers with a fresh eod.gmopen and a note. Ops: 0 re-roll, 1-3 new
    simplified / small / large, 4 custom (JSON of the builder), 5 start
    timer, 6 pause / resume, 7 set seconds (11 bits), 8 signal now,
    9 spotter in N s (11 bits, 0 = call off), 10 detonate, 11 disarm,
    12 refresh, 13 open the defusal window.
    Layout: a plate with Refresh and Close in the header, the server's
    last note as a banner, then two columns: the answers (THIS BOMB: its
    features as rows; WIRES: each wire's colour swatch, name, job and
    ends, CUT ones dim) and the controls (SET UP: re-roll, new bomb types,
    the custom builder in its own amber band; RUN IT: timer, remote
    signal and spotter, open the defusal window, disarm, detonate).
    The custom builder's JSON has the same fields as a feature table
    (see E.Roll), with mods as a list of ids; the server checks it
    (E.CustomFeatures).
]]

local E = Rhylib.EOD
local Net = Rhylib.Net
local UI = Rhylib.UI

local function K() return UI and UI.Kit end
-- Theme token (cl_11_theme.lua): the window's solid background.
local OPAQUE = UI.Col("eod.windowBg", 14, 16, 15, 255)

-- Wire kind -> the name shown in the answers list (add new wire kinds here).
local KIND_NAMES = {
    supply = "battery supply", feed = "capacitor feed", tmrline = "timer line", collapse = "collapse sense",
    antenna = "antenna lead", ajmon = "anti-jam monitor", relay = "relay signal", trig = "relay trigger",
    sense = "charge SENSE line", det = "detonator line", logic = "logic line", tamper = "tamper loop", decoy = "decoy",
}

local gm = { frame = nil, bomb = nil, info = nil, note = "", custom = nil }

local function send(op, write)
    if not IsValid(gm.bomb) then return end
    Net.Start("eod.gm")
    net.WriteEntity(gm.bomb)
    net.WriteUInt(op, 4)
    if write then write() end
    net.SendToServer()
end

local function close()
    if IsValid(gm.frame) then gm.frame:Remove() end
    gm.frame = nil
end

-- The builder's starting values: the bomb's current features.
local function customFrom(f)
    local mods = {}
    for id in pairs(f.mods or {}) do mods[#mods + 1] = id end
    return {
        det = f.det or "timer", antiJam = f.antiJam or false, hop = f.hop or false, motion = f.motion or "none",
        lid = f.lid or false, battery = f.battery or "single", sensor = f.sensor or false, charge = f.charge or "he",
        mods = mods, timerSecs = f.timerSecs or 240,
    }
end

local function hasMod(c, id) for _, m in ipairs(c.mods) do if m == id then return true end end return false end
local function toggleMod(c, id)
    for i, m in ipairs(c.mods) do if m == id then table.remove(c.mods, i) return end end
    c.mods[#c.mods + 1] = id
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

-- A small caps chip (text already upper case), right edge at x, centred on y.
local function chipRight(k, text, x, y, col)
    local f = k.Font(11, 700)
    surface.SetFont(f)
    local tw = surface.GetTextSize(text)
    local w, h = tw + k.S(12), k.S(18)
    k.SetCol(col, 40)
    surface.DrawRect(x - w, y - h * 0.5, w, h)
    k.SetCol(col, 170)
    surface.DrawOutlinedRect(x - w, y - h * 0.5, w, h)
    draw.SimpleText(text, f, x - w * 0.5, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

-- (Re)builds the window's contents from gm.info: answers on the left,
-- set up and run it on the right.
local function build()
    local k = K()
    if not k or not IsValid(gm.frame) then return end
    local s = k.S
    local C = k.C
    local L, R = gm.left, gm.right
    local scrollL, scrollR = L:GetVBar():GetScroll(), R:GetVBar():GetScroll()
    L:Clear()
    R:Clear()
    local info = gm.info
    local f = info.f

    -- the note from the server's last answer
    local np = gm.noteP
    np.text = gm.note
    np:SetVisible(gm.note ~= "")
    np:SetTall(gm.note ~= "" and s(34) or 0)

    local n = 0
    local function band(sp, t, col, right)
        local caps = string.upper(t)
        local h = vgui.Create("DPanel", sp)
        h:Dock(TOP)
        h:SetTall(s(30))
        h:DockMargin(0, n > 0 and s(10) or 0, s(8), s(4))
        function h:Paint(w, hh)
            local c = col or C.accent
            k.SetCol(c, 30)
            surface.SetMaterial(GRAD)
            surface.DrawTexturedRect(0, 0, w * 0.7, hh)
            k.SetCol(c)
            surface.DrawRect(0, 0, s(3), hh)
            diamond(k, s(16), hh * 0.5, s(5), c)
            draw.SimpleText(caps, k.Font(13, 700), s(28), hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if right then draw.SimpleText(right, k.Font(12), w - s(10), hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        end
        n = n + 1
        h.rows = 0
        sp.lastBand = h
        return h
    end
    -- A key / value row (rows alternate under each band). b: text or a
    -- function returning text and colour (live rows).
    local function line(sp, a, b, col, swatch, tag)
        local band_ = sp.lastBand
        band_.rows = band_.rows + 1
        local alt = band_.rows % 2 == 0
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:SetTall(s(26))
        p:DockMargin(0, 0, s(8), 0)
        function p:Paint(w, h)
            k.SetCol(alt and C.rowAlt or C.row)
            surface.DrawRect(0, 0, w, h)
            local x = s(10)
            if swatch then
                k.SetCol(swatch)
                surface.DrawRect(x, h * 0.5 - s(5), s(10), s(10))
                k.SetCol(C.edgeDark)
                surface.DrawOutlinedRect(x, h * 0.5 - s(5), s(10), s(10))
                x = x + s(18)
            end
            draw.SimpleText(a, k.Font(13), x, h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local txt, c = b, col
            if isfunction(b) then txt, c = b() end
            local rx = w - s(10)
            if tag then rx = rx - chipRight(k, tag, rx, h * 0.5, C.textDim) - s(8) end
            local vf = k.Font(13, 700)
            draw.SimpleText(k.Fit(txt, vf, w * 0.6), vf, rx, h / 2, c or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        return p
    end
    local function buttons(sp, list)
        local row = vgui.Create("DPanel", sp)
        row:Dock(TOP)
        row:SetTall(s(32))
        row:DockMargin(0, s(4), s(8), 0)
        row.Paint = nil
        local cnt = #list
        function row:PerformLayout(w)
            local bw = (w - s(4) * (cnt - 1)) / cnt
            for i, b in ipairs(self:GetChildren()) do
                b:SetPos(math.floor((i - 1) * (bw + s(4))), 0)
                b:SetSize(math.floor(bw), s(32))
            end
        end
        for _, b in ipairs(list) do k.Button(row, b[1], b[2], b[3]) end
    end
    local function ctlRow(sp, title, rightW)
        local band_ = sp.lastBand
        band_.rows = band_.rows + 1
        local alt = band_.rows % 2 == 0
        local r = vgui.Create("DPanel", sp)
        r:Dock(TOP)
        r:SetTall(s(36))
        r:DockMargin(0, 0, s(8), 0)
        r:DockPadding(s(10), s(5), s(8), s(5))
        function r:Paint(w, h)
            k.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(k.Fit(title, k.Font(13, 500), w - self.right:GetWide() - s(24)), k.Font(13, 500), s(10), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        r.right = vgui.Create("DPanel", r)
        r.right:Dock(RIGHT)
        r.right:SetWide(s(rightW or 260))
        r.right.Paint = nil
        return r
    end

    -- Left: the answers
    band(L, "This bomb", nil, info.kind)
    line(L, "Type", info.kind)
    line(L, "Detonator", f.det == "remote" and ("remote · " .. string.format("%.3f GHz", info.freq / 1000) .. (f.hop and " · hops" or "")) or "timer")
    line(L, "Anti-jam", f.antiJam and "YES" or "no", f.antiJam and C.warn or nil)
    line(L, "Motion sensor", f.motion or "none", f.motion and C.warn or nil)
    line(L, "Lid switch", f.lid and "YES" or "no")
    line(L, "Battery", f.battery)
    line(L, "Charge", (f.charge == "gas" and "poison gas" or f.charge == "virus" and "virus" or "explosive") .. (f.sensor and " · self-powered" or ""))
    local mods = {}
    for _, m in ipairs(E.MODS) do if f.mods and f.mods[m.id] then mods[#mods + 1] = m.name end end
    line(L, "Modules", #mods > 0 and table.concat(mods, ", ") or "none")
    local stateCol = info.done and C.good or info.safe and C.good or nil
    line(L, "State", (info.done and "SAFE (done)" or info.safe and "detonator cut" or info.open and "open" or info.inspected and "inspected" or "untouched")
        .. (info.covered and " · jammed" or "") .. (info.powered and "" or " · no power") .. " · " .. info.viewers .. " working on it", stateCol)
    if info.chip then line(L, "Chip code", E.ChipText(info.chip[1]) .. " → " .. info.chip[2]) end
    if info.stab then line(L, "Stabiliser dose", string.format("%.2f ml", info.stab)) end
    if info.fake then line(L, "Fake board order", "mounts " .. table.concat(info.fake, ", ")) end

    local nw = #info.wires
    band(L, "Wires (answers)", nil, nw == 1 and "1 wire" or (nw .. " wires"))
    for _, w in ipairs(info.wires) do
        local wc = E.COLOURS[w.c] or E.COLOURS[1]
        line(L, wc[1], (KIND_NAMES[w.k] or w.k) .. " · " .. w.a .. " → " .. w.b, w.cut and C.textDim or nil, wc[2], w.cut and "CUT" or nil)
    end

    -- Right: set up and run it
    n = 0
    band(R, "Set up")
    buttons(R, { { "Re-roll", function() send(0) end, { accent = true } }, { "Simplified", function() send(1) end }, { "Small", function() send(2) end }, { "Large", function() send(3) end } })
    buttons(R, { { gm.custom and "Hide custom" or "Custom bomb…", function()
        gm.custom = (not gm.custom) and customFrom(f) or nil
        build()
    end } })

    if gm.custom then
        local c = gm.custom
        band(R, "Custom bomb", C.warn, "every feature and module")
        local function choiceRow(title, opts, key)
            local r = ctlRow(R, title, 300)
            local ch = k.Choices(r.right, opts, function() return c[key] end, function(v) c[key] = v end)
            ch:Dock(FILL)
        end
        local function toggleRow(title, key)
            local r = ctlRow(R, title, 80)
            local t = k.Toggle(r.right, function() return c[key] end, function(v) c[key] = v end)
            t:Dock(RIGHT)
        end
        choiceRow("Detonator", { { "timer", "Timer" }, { "remote", "Remote" } }, "det")
        toggleRow("Anti-jam (remote)", "antiJam")
        toggleRow("Frequency hopping (remote)", "hop")
        choiceRow("Motion sensor", { { "none", "None" }, { "normal", "Normal" }, { "sensitive", "Sensitive" } }, "motion")
        toggleRow("Lid switch", "lid")
        local br = ctlRow(R, "Battery", 340)
        k.Choices(br.right, { { "single", "Single" }, { "dual", "Dual" }, { "capacitor", "Capacitor" }, { "collapse", "Collapse" } },
            function() return c.battery end, function(v) c.battery = v end):Dock(FILL)
        toggleRow("Self-powered charge (cell + sensor)", "sensor")
        choiceRow("Charge", { { "he", "Explosive" }, { "gas", "Gas" }, { "virus", "Virus" } }, "charge")
        for _, m in ipairs(E.MODS) do
            local r = ctlRow(R, m.name .. " (" .. m.rank .. ")" .. (m.remote and " · remote only" or ""), 80)
            local t = k.Toggle(r.right, function() return hasMod(c, m.id) end, function() toggleMod(c, m.id) end)
            t:Dock(RIGHT)
        end
        local r = ctlRow(R, "Timer (seconds)")
        local sl = k.Slider(r.right, 30, 900, 0, function() return c.timerSecs end, function(v) c.timerSecs = v end)
        sl:Dock(FILL)
        buttons(R, { { "Build custom bomb", function()
            local t = table.Copy(c)
            if t.motion == "none" then t.motion = nil end
            send(4, function() net.WriteString(util.TableToJSON(t)) end)
        end, { accent = true } } })
    end

    band(R, "Run it")
    local t = info.timer
    if t then
        line(R, "Timer", function()
            if t.ends and t.ends > 0 then return string.FormattedTime(math.max(0, t.ends - CurTime()), "%02i:%02i") .. " running", C.warn end
            return string.FormattedTime(t.left or t.secs, "%02i:%02i") .. (t.stopped and " stopped (no power)" or t.held and " paused" or " waiting for someone within " .. math.floor((E.Cfg("timerWake")) / E.UNITS_PER_M) .. " m"), C.text
        end)
        buttons(R, {
            { "Start", function() send(5) end },
            { "Pause / resume", function() send(6) end },
            { "Set time…", function()
                k.Prompt("Timer", "Seconds (10-1800)", tostring(t.secs), function(x)
                    local num = tonumber(x)
                    if num then send(7, function() net.WriteUInt(math.Clamp(math.floor(num), 10, 1800), 11) end) end
                end)
            end },
        })
    end
    if f.det == "remote" then
        if info.spotAt and info.spotAt > 0 then
            line(R, "Spotter", function()
                local left = info.spotAt - info.now - (CurTime() - gm.recv)
                return string.format("signal in %.0f s", math.max(0, left)), C.warn
            end)
        end
        buttons(R, {
            { "Send signal now", function() send(8) end, { danger = true } },
            { "Spotter in…", function()
                k.Prompt("Spotter", "Seconds until the signal (0 = call it off)", "60", function(x)
                    local num = tonumber(x)
                    if num then send(9, function() net.WriteUInt(math.Clamp(math.floor(num), 0, 2000), 11) end) end
                end)
            end },
        })
    end
    buttons(R, {
        { "Open the defusal window", function() send(13) close() end },
        { "Disarm", function() send(11) end },
        { "Detonate", function()
            local m = k.Menu()
            m:AddOption("Yes, detonate it now", function() send(10) close() end)
            m:AddOption("Cancel", function() end)
            m:Open()
        end, { danger = true } },
    })

    timer.Simple(0, function()
        if IsValid(L) then L:GetVBar():SetScroll(scrollL) end
        if IsValid(R) then R:GetVBar():SetScroll(scrollR) end
    end)
end

local function open(bomb)
    local k = K()
    if not k then return end
    local s = k.S
    local C = k.C
    if not IsValid(gm.frame) or gm.bomb ~= bomb then
        close()
        gm.custom = nil
        local fr = vgui.Create("EditablePanel")
        fr:SetSize(math.min(ScrW() - s(60), s(1000)), math.min(ScrH() - s(60), s(780)))
        fr:Center()
        fr:MakePopup()
        fr:DockPadding(s(14), s(52), s(14), s(14))
        function fr:Paint(w, h)
            k.Plate(0, 0, w, h, { title = "Bomb · game master", ticks = "all", header = s(38), bg = OPAQUE })
        end
        function fr:Think()
            if not IsValid(gm.bomb) then close() end
        end
        local x = k.Button(fr, "Close", close, { small = true })
        x:SetSize(s(90), s(26))
        x:SetPos(fr:GetWide() - s(90) - s(8), s(6))
        local rf = k.Button(fr, "Refresh", function() send(12) end, { small = true })
        rf:SetSize(s(90), s(26))
        rf:SetPos(fr:GetWide() - s(186), s(6))
        -- the server's note (filled in by build)
        local np = vgui.Create("DPanel", fr)
        np:Dock(TOP)
        np:DockMargin(0, 0, 0, s(10))
        np.text = ""
        function np:Paint(w, h)
            if h < 2 then return end
            k.SetCol(C.accent, 30)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(C.accent)
            surface.DrawRect(0, 0, s(3), h)
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            local nf = k.Font(14, 700)
            draw.SimpleText(k.Fit(self.text, nf, w - s(28)), nf, s(14), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        gm.noteP = np
        gm.left = k.Scroll(fr)
        gm.left:Dock(LEFT)
        gm.left:SetWide(math.floor((fr:GetWide() - s(28)) * 0.47))
        gm.left:DockMargin(0, 0, s(10), 0)
        gm.right = k.Scroll(fr)
        gm.right:Dock(FILL)
        gm.frame = fr
    end
    gm.bomb = bomb
    build()
end

Net.Receive("eod.gmopen", function()
    local bomb = net.ReadEntity()
    local note = net.ReadString()
    local len = net.ReadUInt(16)
    local raw = net.ReadData(len)
    local js = raw and util.Decompress(raw)
    local info = js and util.JSONToTable(js)
    if not (istable(info) and IsValid(bomb)) then return end
    gm.info = info
    gm.note = note
    gm.recv = CurTime()
    open(bomb)
end)

local function addCloser()
    if Rhylib.UI and Rhylib.UI.RegisterCloser then
        Rhylib.UI.RegisterCloser("eodgm", function() if IsValid(gm.frame) then close() return true end end)
    end
end
addCloser()
Rhylib.Hook.Add("InitPostEntity", "eod.gmcloser", addCloser)
