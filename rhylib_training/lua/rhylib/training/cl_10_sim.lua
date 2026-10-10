--[[
    Training (client): the sim health bar (only while it's below full or
    you're eliminated, and not while a training gun is in hand: then the
    HUD's health bar turns yellow and shows it) and the respawn beacon list.
    The list needs rhylib_menus (Menus.Kit); without it the client picks
    the nearest beacon as soon as it may.
]]

local T = Rhylib.Training

local COL_SIM = Color(255, 210, 60)
local COL_BACK = Color(0, 0, 0, 170)
local COL_DIM = Color(255, 210, 60, 60)
local COL_TEXT = Color(255, 236, 180)

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
    local S = function(n) return math.floor(n * ScrH() / 1080 + 0.5) end
    local w, h = S(240), S(8)
    local x, y = ScrW() * 0.5 - w * 0.5, ScrH() * 0.5 + S(120)
    surface.SetDrawColor(COL_BACK)
    surface.DrawRect(x - 1, y - 1, w + 2, h + 2)
    surface.SetDrawColor(COL_DIM)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(COL_SIM)
    surface.DrawRect(x, y, w * math.Clamp(hp / max, 0, 1), h)
    local label = out and "ELIMINATED (SIMULATION)" or ("SIMULATION  " .. hp)
    draw.SimpleTextOutlined(label, Rhylib.UI.Font(14, 700), ScrW() * 0.5, y - S(4), COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
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
    local M = Rhylib.Menus
    local K = M and M.Kit
    if not K then
        -- No menus addon: the nearest beacon after the wait.
        timer.Simple(math.max(0, readyAt - CurTime()), function() pick(nil) end)
        return
    end
    local S = K.S
    local f = vgui.Create("EditablePanel")
    win = f
    local rows = math.min(#list, 8)
    f:SetSize(S(380), S(96) + math.max(rows, 1) * S(38) + S(44))
    f:SetPos(ScrW() * 0.5 - f:GetWide() * 0.5, ScrH() * 0.62 - f:GetTall() * 0.5)
    f:MakePopup()
    f:SetKeyboardInputEnabled(false)
    f:DockPadding(S(12), S(80), S(12), S(12))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Eliminated", sub = by ~= "" and ("by " .. by) or nil, ticks = "all", header = S(34), rule = COL_SIM })
        local left = math.max(0, math.ceil(autoAt - CurTime()))
        local wait = readyAt - CurTime()
        local msg = wait > 0 and string.format("Back in the simulation in %.0f s. Pick where:", math.ceil(wait))
            or ("Pick a respawn point (nearest in " .. left .. " s)")
        draw.SimpleText(msg, K.Font(14), S(12), S(56), K.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
        local b = K.Button(sc, row.name .. "  ·  " .. row.dist .. " m", function() pick(row.idx) close() end, { accent = i == 1, align = "left" })
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, S(4))
    end
    local n = K.Button(f, "Nearest", function() pick(nil) close() end)
    n:Dock(BOTTOM)
end

net.Receive(Rhylib.Net.Name("train.out"), function()
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
