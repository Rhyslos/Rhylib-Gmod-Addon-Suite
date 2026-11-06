--[[
    Training (client): the sim health bar (only while it's below full or
    you're eliminated, and not while a training gun is in hand: then the
    HUD's health bar turns yellow and shows it) and the respawn beacon list.
    The list needs the UI kit (Rhylib.UI.Kit); without it the client picks
    the nearest beacon as soon as it may.

    Sim health bar: a small plate under the crosshair, caps SIMULATION and
    the number (ELIMINATED in yellow when out), a yellow bar.
    Beacon list: a plate with a yellow rule (ELIMINATED, by whom), the
    wait as a yellow bar with "Back in the simulation in N s" / "Pick a
    respawn point (nearest in N s)", one card per beacon (number, name,
    NEAREST chip on the first, distance right; hover lights it), then
    Nearest. Clicking a card or Nearest picks and closes it.
]]

local T = Rhylib.Training

-- The training yellow (the HUD's sim health and hit markers use it too).
local COL_SIM = Rhylib.UI.Col("training.sim", 255, 210, 60)

local shownAt = 0
local lastHp

Rhylib.Hook.Add("HUDPaint", "training.bar", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local max = T.Cfg("simHealth")
    local hp = T.Health(ply)
    local out = T.Out(ply)
    if hp ~= lastHp then
        lastHp = hp
        shownAt = CurTime()
    end
    -- Shown while hurt, and a moment after it refills.
    if hp >= max and not out and CurTime() - shownAt > 1.5 then return end
    -- A training gun in hand: the HUD's own health bar shows it (rhylib_hud).
    local HUD = Rhylib.HUD
    if not out and HUD and HUD.SimHealth and HUD.SimHealth(ply) then return end
    local K = Rhylib.UI.Kit
    if not K then return end
    local C = K.C
    local S = K.S
    local w, h = S(260), S(8)
    local pw, ph = w + S(20), S(42)
    local x, y = math.floor(ScrW() * 0.5 - w * 0.5), math.floor(ScrH() * 0.5 + S(120))
    local px, py = x - S(10), y - S(28)
    K.Plate(px, py, pw, ph, { alpha = 235 })
    K.SetCol(COL_SIM)
    surface.DrawRect(px + 1, py + 1, S(3), ph - 2)
    if out then
        K.Caps("Eliminated (simulation)", x, py + S(12), COL_SIM)
    else
        K.Caps("Simulation", x, py + S(12), C.label)
        draw.SimpleText(hp, K.Font(14, 700), x + w, py + S(12), C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    K.SetCol(COL_SIM, 50)
    surface.DrawRect(x, y, w, h)
    K.SetCol(COL_SIM)
    surface.DrawRect(x, y, math.floor(w * math.Clamp(hp / max, 0, 1)), h)
end)

--------------------------------------------------------------------------
-- Respawn list
--------------------------------------------------------------------------

local win

local function close()
    if IsValid(win) then win:Remove() end
    win = nil
end

local function pick(idx)
    Rhylib.Net.Start("train.pick")
    net.WriteUInt(idx or 0, 13)
    net.SendToServer()
end

local function open(by, readyAt, autoAt, list)
    close()
    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then
        -- No menus addon: the nearest beacon after the wait.
        timer.Simple(math.max(0, readyAt - CurTime()), function() pick(nil) end)
        return
    end
    local C, S = K.C, K.S
    local f = vgui.Create("EditablePanel")
    win = f
    local rows = math.min(#list, 8)
    local CARD = S(44)
    local total = math.max(0.01, readyAt - CurTime())
    f:SetSize(S(400), S(118) + math.max(rows, 1) * (CARD + S(4)) + S(44))
    f:SetPos(ScrW() * 0.5 - f:GetWide() * 0.5, ScrH() * 0.62 - f:GetTall() * 0.5)
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(S(12), S(104), S(12), S(12))
    local byText = by ~= "" and ("by " .. by) or nil
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Eliminated", sub = byText, ticks = "all", header = S(38), rule = COL_SIM })
        local left = math.max(0, math.ceil(autoAt - CurTime()))
        local wait = readyAt - CurTime()
        local msg = wait > 0 and string.format("Back in the simulation in %.0f s. Pick where:", math.ceil(wait))
            or ("Pick a respawn point (nearest in " .. left .. " s)")
        draw.SimpleText(msg, K.Font(14, 600), S(12), S(58), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- (the wait as a bar: fills up until you may get back in)
        local bw, by2 = w - S(24), S(74)
        K.SetCol(C.row)
        surface.DrawRect(S(12), by2, bw, S(6))
        K.SetCol(COL_SIM, wait > 0 and 200 or 255)
        surface.DrawRect(S(12), by2, math.floor(bw * math.Clamp(1 - wait / total, 0, 1)), S(6))
        K.Caps(wait > 0 and "Waiting" or "Ready", S(12), S(92), wait > 0 and C.label or COL_SIM)
    end
    function f:Think()
        if not T.Out(LocalPlayer()) and CurTime() > readyAt + 1 then close() end
    end
    local sc = K.Scroll(f)
    sc:Dock(FILL)
    if #list == 0 then
        local b = K.Button(sc, "Get up here (no beacons on this map)", function() pick(nil) close() end, { accent = true })
        b:Dock(TOP)
    end
    for i, row in ipairs(list) do
        local b = vgui.Create("DButton", sc)
        b:SetText("")
        b:SetTall(CARD)
        b:Dock(TOP)
        b:DockMargin(0, 0, S(8), S(4))
        local key, dist, nearest = tostring(i), row.dist .. " m", i == 1
        function b:Paint(w, h)
            local hov = self:IsHovered()
            K.SetCol(hov and C.rowHover or (i % 2 == 0 and C.rowAlt or C.row))
            surface.DrawRect(0, 0, w, h)
            K.SetCol(hov and C.accent or C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            K.SetCol(nearest and COL_SIM or C.tick, nearest and 255 or 120)
            surface.DrawRect(0, 0, S(3), h)
            local cy = h * 0.5
            local kb = S(22)
            K.SetCol(C.header)
            surface.DrawRect(S(12), cy - kb * 0.5, kb, kb)
            K.SetCol(C.edgeLight)
            surface.DrawOutlinedRect(S(12), cy - kb * 0.5, kb, kb)
            draw.SimpleText(key, K.Font(13, 700), S(12) + kb * 0.5, cy, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(dist, K.Font(14, 700), w - S(12), cy, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            local nf = K.Font(15, 700)
            local name = K.Fit(row.name, nf, w - S(46) - S(70) - (nearest and S(76) or 0))
            draw.SimpleText(name, nf, S(46), cy, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if nearest then
                surface.SetFont(nf)
                local cx, cw, ch = S(46) + surface.GetTextSize(name) + S(8), S(64), S(16)
                K.SetCol(COL_SIM, 35)
                surface.DrawRect(cx, cy - ch * 0.5, cw, ch)
                K.SetCol(COL_SIM, 150)
                surface.DrawOutlinedRect(cx, cy - ch * 0.5, cw, ch)
                draw.SimpleText("NEAREST", K.Font(10, 700), cx + cw * 0.5, cy, COL_SIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            return true
        end
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            pick(row.idx)
            close()
        end
    end
    local n = K.Button(f, "Nearest", function() pick(nil) close() end)
    n:Dock(BOTTOM)
    n:DockMargin(0, S(8), 0, 0)
end

Rhylib.Net.Receive("train.out", function()
    if not net.ReadBool() then return close() end
    local by = net.ReadString()
    local readyAt, autoAt = net.ReadFloat(), net.ReadFloat()
    local list = {}
    for i = 1, net.ReadUInt(6) do
        list[i] = { idx = net.ReadUInt(13), name = net.ReadString(), dist = net.ReadUInt(16) }
    end
    surface.PlaySound("buttons/button19.wav")
    open(by, readyAt, autoAt, list)
end)
