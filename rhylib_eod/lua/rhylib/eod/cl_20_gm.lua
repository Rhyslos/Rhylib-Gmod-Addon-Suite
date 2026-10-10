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
    The custom builder's JSON has the same fields as a feature table
    (see E.Roll), with mods as a list of ids; the server checks it
    (E.CustomFeatures).
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local OPAQUE = Color(14, 16, 15, 255)

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

-- (Re)builds the window's contents from gm.info.
local function build()
    local k = K()
    if not k or not IsValid(gm.frame) then return end
    local s = k.S
    local C = k.C
    local sp = gm.scroll
    local scroll = sp:GetVBar():GetScroll()
    sp:Clear()
    local info = gm.info
    local f = info.f

    local function heading(t)
        local h = k.Heading(sp, t)
        h:Dock(TOP)
        h:DockMargin(0, s(8), s(6), s(4))
    end
    local function line(a, b, col)
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:SetTall(s(24))
        p:DockMargin(0, 0, s(8), s(2))
        function p:Paint(w, h)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(a, k.Font(13), s(8), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(k.Fit(b, k.Font(13, 700), w * 0.6), k.Font(13, 700), w - s(8), h / 2, col or C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        return p
    end
    local function buttons(list)
        local row = vgui.Create("DPanel", sp)
        row:Dock(TOP)
        row:SetTall(s(32))
        row:DockMargin(0, 0, s(8), s(4))
        row.Paint = nil
        local n = #list
        function row:PerformLayout(w)
            local bw = (w - s(4) * (n - 1)) / n
            for i, b in ipairs(self:GetChildren()) do
                b:SetPos((i - 1) * (bw + s(4)), 0)
                b:SetSize(bw, s(32))
            end
        end
        for _, b in ipairs(list) do k.Button(row, b[1], b[2], b[3]) end
    end

    if gm.note ~= "" then
        local l = k.Label(sp, gm.note, 14, 700, C.accent)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(8), s(6))
    end

    heading("This bomb")
    line("Type", info.kind)
    line("Detonator", f.det == "remote" and ("remote · " .. string.format("%.3f GHz", info.freq / 1000) .. (f.hop and " · hops" or "")) or "timer")
    line("Anti-jam", f.antiJam and "YES" or "no", f.antiJam and C.warn or nil)
    line("Motion sensor", f.motion or "none", f.motion and C.warn or nil)
    line("Lid switch", f.lid and "YES" or "no")
    line("Battery", f.battery)
    line("Charge", (f.charge == "gas" and "poison gas" or f.charge == "virus" and "virus" or "explosive") .. (f.sensor and " · self-powered" or ""))
    local mods = {}
    for _, m in ipairs(E.MODS) do if f.mods and f.mods[m.id] then mods[#mods + 1] = m.name end end
    line("Modules", #mods > 0 and table.concat(mods, ", ") or "none")
    line("State", (info.done and "SAFE (done)" or info.safe and "detonator cut" or info.open and "open" or info.inspected and "inspected" or "untouched")
        .. (info.covered and " · jammed" or "") .. (info.powered and "" or " · no power") .. " · " .. info.viewers .. " working on it")
    if info.chip then line("Chip code", E.ChipText(info.chip[1]) .. " → " .. info.chip[2]) end
    if info.stab then line("Stabiliser dose", string.format("%.2f ml", info.stab)) end
    if info.fake then
        local cols = {}
        line("Fake board order", "mounts " .. table.concat(info.fake, ", "))
        local _ = cols
    end

    heading("Wires (answers)")
    for _, w in ipairs(info.wires) do
        line((E.COLOURS[w.c] or E.COLOURS[1])[1] .. (w.cut and " (cut)" or ""), (KIND_NAMES[w.k] or w.k) .. " · " .. w.a .. " → " .. w.b, w.cut and C.textDim or nil)
    end

    heading("Set up")
    buttons({ { "Re-roll", function() send(0) end, { accent = true } }, { "Simplified", function() send(1) end }, { "Small", function() send(2) end }, { "Large", function() send(3) end } })
    buttons({ { gm.custom and "Hide custom" or "Custom bomb…", function()
        gm.custom = (not gm.custom) and customFrom(f) or nil
        build()
    end } })

    if gm.custom then
        local c = gm.custom
        local function choiceRow(title, opts, key)
            local r = k.Row(sp, title)
            r:Dock(TOP)
            r:DockMargin(0, 0, s(8), s(2))
            local ch = k.Choices(r.right, opts, function() return c[key] end, function(v) c[key] = v end)
            ch:Dock(FILL)
        end
        local function toggleRow(title, key)
            local r = k.Row(sp, title)
            r:Dock(TOP)
            r:DockMargin(0, 0, s(8), s(2))
            local t = k.Toggle(r.right, function() return c[key] end, function(v) c[key] = v end)
            t:Dock(RIGHT)
        end
        choiceRow("Detonator", { { "timer", "Timer" }, { "remote", "Remote" } }, "det")
        toggleRow("Anti-jam (remote)", "antiJam")
        toggleRow("Frequency hopping (remote)", "hop")
        choiceRow("Motion sensor", { { "none", "None" }, { "normal", "Normal" }, { "sensitive", "Sensitive" } }, "motion")
        toggleRow("Lid switch", "lid")
        choiceRow("Battery", { { "single", "Single" }, { "dual", "Dual" }, { "capacitor", "Capacitor" }, { "collapse", "Collapse" } }, "battery")
        toggleRow("Self-powered charge (cell + sensor)", "sensor")
        choiceRow("Charge", { { "he", "Explosive" }, { "gas", "Gas" }, { "virus", "Virus" } }, "charge")
        for _, m in ipairs(E.MODS) do
            local r = k.Row(sp, m.name .. " (" .. m.rank .. ")" .. (m.remote and " · remote only" or ""))
            r:Dock(TOP)
            r:DockMargin(0, 0, s(8), s(2))
            local t = k.Toggle(r.right, function() return hasMod(c, m.id) end, function() toggleMod(c, m.id) end)
            t:Dock(RIGHT)
        end
        local r = k.Row(sp, "Timer (seconds)")
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(2))
        local sl = k.Slider(r.right, 30, 900, 0, function() return c.timerSecs end, function(v) c.timerSecs = v end)
        sl:Dock(FILL)
        buttons({ { "Build custom bomb", function()
            local t = table.Copy(c)
            if t.motion == "none" then t.motion = nil end
            send(4, function() net.WriteString(util.TableToJSON(t)) end)
        end, { accent = true } } })
    end

    heading("Run it")
    local t = info.timer
    if t then
        local p = line("Timer", "")
        function p:Paint(w, h)
            k.SetCol(C.row)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText("Timer", k.Font(13), s(8), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local txt
            if t.ends and t.ends > 0 then txt = string.FormattedTime(math.max(0, t.ends - CurTime()), "%02i:%02i") .. " running"
            else txt = string.FormattedTime(t.left or t.secs, "%02i:%02i") .. (t.stopped and " stopped (no power)" or t.held and " paused" or " waiting for someone within " .. math.floor((E.Cfg("timerWake") or 900) / E.UNITS_PER_M) .. " m") end
            draw.SimpleText(txt, k.Font(13, 700), w - s(8), h / 2, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        buttons({
            { "Start", function() send(5) end },
            { "Pause / resume", function() send(6) end },
            { "Set time…", function()
                k.Prompt("Timer", "Seconds (10-1800)", tostring(t.secs), function(x)
                    local n = tonumber(x)
                    if n then send(7, function() net.WriteUInt(math.Clamp(math.floor(n), 10, 1800), 11) end) end
                end)
            end },
        })
    end
    if f.det == "remote" then
        if info.spotAt and info.spotAt > 0 then
            local p = line("Spotter", "")
            function p:Paint(w, h)
                k.SetCol(C.row)
                surface.DrawRect(0, 0, w, h)
                draw.SimpleText("Spotter", k.Font(13), s(8), h / 2, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local left = info.spotAt - info.now - (CurTime() - gm.recv)
                draw.SimpleText(string.format("signal in %.0f s", math.max(0, left)), k.Font(13, 700), w - s(8), h / 2, C.warn, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        buttons({
            { "Send signal now", function() send(8) end, { danger = true } },
            { "Spotter in…", function()
                k.Prompt("Spotter", "Seconds until the signal (0 = call it off)", "60", function(x)
                    local n = tonumber(x)
                    if n then send(9, function() net.WriteUInt(math.Clamp(math.floor(n), 0, 2000), 11) end) end
                end)
            end },
        })
    end
    buttons({
        { "Open the defusal window", function() send(13) close() end },
        { "Disarm", function() send(11) end },
        { "Detonate", function()
            local m = k.Menu()
            m:AddOption("Yes, detonate it now", function() send(10) close() end)
            m:AddOption("Cancel", function() end)
            m:Open()
        end, { danger = true } },
    })
    buttons({ { "Refresh", function() send(12) end } })

    timer.Simple(0, function() if IsValid(sp) then sp:GetVBar():SetScroll(scroll) end end)
end

local function open(bomb)
    local k = K()
    if not k then return end
    local s = k.S
    if not IsValid(gm.frame) or gm.bomb ~= bomb then
        close()
        gm.custom = nil
        local fr = vgui.Create("EditablePanel")
        fr:SetSize(math.min(ScrW() - s(60), s(640)), math.min(ScrH() - s(60), s(820)))
        fr:Center()
        fr:MakePopup()
        fr:DockPadding(s(12), s(48), s(12), s(12))
        function fr:Paint(w, h)
            k.Plate(0, 0, w, h, { title = "Bomb · game master", ticks = "all", header = s(38), bg = OPAQUE })
        end
        function fr:Think()
            if not IsValid(gm.bomb) then close() end
        end
        local x = k.Button(fr, "Close", close, { small = true })
        x:SetSize(s(90), s(26))
        x:SetPos(fr:GetWide() - s(90) - s(12), s(6))
        gm.scroll = k.Scroll(fr)
        gm.scroll:Dock(FILL)
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

Rhylib.Hook.Add("InitPostEntity", "eod.gmcloser", function()
    if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("eodgm", function() if IsValid(gm.frame) then close() return true end end)
    end
end)
