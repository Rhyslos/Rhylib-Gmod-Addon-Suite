--[[
    Damage feedback (client), from hud.dmg (sv_30_damage.lua):

      - direction markers: an arc on a ring around the crosshair pointing
        at where the hit came from (it keeps pointing there as you turn),
        red for health, blue for hits the armour soaked, yellow for sim
        hits; thicker for bigger hits
      - a flash from the screen edges, strongest on the side it came from
      - a short camera shake (view only, never the aim)
      - a hit sound: flesh, armour clang, or a sim beep; blasts ring the ears
      - low health: a slow red pulse at the edges and a heartbeat

    Near misses (bolts passing close) are in rhylib_weapons cl_10_bolts.lua.
    Client convars (Settings > HUD): rhylib_dmg_markers, rhylib_dmg_flash,
    rhylib_dmg_shake, rhylib_dmg_lowhp, rhylib_dmg_volume (0-1, scales
    every sound here), rhylib_dmg_ring (ear ringing on/off).
]]

local HUD = Rhylib.HUD
local DMG_SIM, DMG_BLAST, DMG_NODIR = 1, 2, 4

local cvMarkers = CreateClientConVar("rhylib_dmg_markers", "1", true, false, "Damage direction markers around the crosshair")
local cvFlash = CreateClientConVar("rhylib_dmg_flash", "1", true, false, "Screen edge flash when hit")
local cvShake = CreateClientConVar("rhylib_dmg_shake", "1", true, false, "Short camera shake when hit (view only)")
local cvLow = CreateClientConVar("rhylib_dmg_lowhp", "1", true, false, "Red pulse and heartbeat at low health")
local cvVol = CreateClientConVar("rhylib_dmg_volume", "1", true, false, "Volume of hit sounds, beeps and the heartbeat (0-1)")
local cvRing = CreateClientConVar("rhylib_dmg_ring", "1", true, false, "Ear ringing after big explosions")

local function vol(v) return v * math.Clamp(cvVol:GetFloat(), 0, 1) end

local MARK_LIFE = 1.8
local MAX_MARKS = 8
local marks = {}          -- { t, from, col, size }
local flash = { 0, 0, 0, 0 }   -- front, right, back, left (0-1)
local flashCol = Color(200, 30, 20)

local COL_HP = Color(235, 60, 45)
local COL_ARMOUR = Color(110, 170, 255)
local COL_SIM = Color(255, 205, 50)

local FLESH = { "physics/flesh/flesh_impact_bullet1.wav", "physics/flesh/flesh_impact_bullet2.wav",
    "physics/flesh/flesh_impact_bullet3.wav", "physics/flesh/flesh_impact_bullet4.wav", "physics/flesh/flesh_impact_bullet5.wav" }
local METAL = { "physics/metal/metal_solid_impact_bullet1.wav", "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav", "physics/metal/metal_solid_impact_bullet4.wav" }

-- Side of the screen a world point is on: 1 front, 2 right, 3 back, 4 left;
-- and its angle (0 = straight ahead, clockwise).
local function relAngle(from)
    local ply = LocalPlayer()
    local d = from - ply:EyePos()
    local a = math.NormalizeAngle(ply:EyeAngles().y - d:Angle().y)   -- (+ = to the right)
    return a
end

local function sideOf(a)
    if a > -45 and a <= 45 then return 1 end
    if a > 45 and a <= 135 then return 2 end
    if a < -45 and a >= -135 then return 4 end
    return 3
end

local nextSound = 0

Rhylib.Net.ReceiveBatch("hud.dmg", function()
    local h = { amount = net.ReadUInt(8), armour = net.ReadUInt(8), flags = net.ReadUInt(3) }
    if bit.band(h.flags, DMG_NODIR) == 0 then h.from = net.ReadVector() end
    return h
end, function(h)
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local sim = bit.band(h.flags, DMG_SIM) ~= 0
    local blast = bit.band(h.flags, DMG_BLAST) ~= 0
    local total = h.amount + h.armour * 0.5
    local col = sim and COL_SIM or (h.armour > h.amount and COL_ARMOUR or COL_HP)

    -- Marker (a new hit from about the same place refreshes it).
    if h.from then
        local m
        for _, o in ipairs(marks) do
            if o.from:DistToSqr(h.from) < 100 * 100 then m = o break end
        end
        if not m then
            if #marks >= MAX_MARKS then table.remove(marks, 1) end
            m = { size = 0 }
            marks[#marks + 1] = m
        end
        m.t, m.from, m.col = CurTime(), h.from, col
        m.size = math.Clamp(math.max(m.size * 0.6, 0) + total / 25, 0.35, 1.6)
    end

    -- Edge flash: the hit side most, a little everywhere.
    if not sim then
        local f = math.Clamp(total / 35, 0.15, 1)
        for i = 1, 4 do flash[i] = math.min(1, flash[i] + f * 0.35) end
        if h.from then
            local s = sideOf(relAngle(h.from))
            flash[s] = math.min(1, flash[s] + f)
        end
        flashCol = h.armour > h.amount and COL_ARMOUR or COL_HP
    end

    -- Shake (the view, not the aim).
    if cvShake:GetBool() and not sim then
        util.ScreenShake(ply:GetPos(), math.Clamp(total / 6, 1, blast and 12 or 5), 18, blast and 0.5 or 0.18, 64)
    end

    -- Sound, at most one every 60 ms (a burst of hits stays readable).
    local now = CurTime()
    if now >= nextSound and cvVol:GetFloat() > 0 then
        nextSound = now + 0.06
        if sim then
            ply:EmitSound("buttons/blip1.wav", 0, 135, vol(0.45), CHAN_STATIC)
        elseif h.armour > h.amount then
            ply:EmitSound(METAL[math.random(#METAL)], 0, math.random(105, 120), vol(0.55), CHAN_STATIC)
        else
            ply:EmitSound(FLESH[math.random(#FLESH)], 0, math.random(90, 105), vol(0.7), CHAN_STATIC)
        end
    end
    -- Big blasts: ringing ears (engine DSP preset 35).
    if blast and total >= 30 and cvRing:GetBool() then ply:SetDSP(35, false) end
end)

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local gradL, gradR = Material("vgui/gradient-l"), Material("vgui/gradient-r")
local gradU, gradD = Material("vgui/gradient-u"), Material("vgui/gradient-d")

-- Screen edges: front = top, back = bottom (as a radar would read).
local function edges(a, col, W, H)
    local d = math.floor(H * 0.22)
    surface.SetDrawColor(col.r, col.g, col.b, 255 * a[1])
    surface.SetMaterial(gradU)
    surface.DrawTexturedRect(0, 0, W, d)
    surface.SetDrawColor(col.r, col.g, col.b, 255 * a[3])
    surface.SetMaterial(gradD)
    surface.DrawTexturedRect(0, H - d, W, d)
    surface.SetDrawColor(col.r, col.g, col.b, 255 * a[4])
    surface.SetMaterial(gradL)
    surface.DrawTexturedRect(0, 0, d, H)
    surface.SetDrawColor(col.r, col.g, col.b, 255 * a[2])
    surface.SetMaterial(gradR)
    surface.DrawTexturedRect(W - d, 0, d, H)
end

local lowA = { 0, 0, 0, 0 }
local COL_LOW = Color(170, 10, 10)
local nextBeat = 0
local poly = {}
for i = 1, 4 do poly[i] = { x = 0, y = 0 } end

-- One arc of a marker: quads along the ring.
local function arc(cx, cy, r, thick, ang, width, col, alpha)
    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, alpha)
    local steps = 6
    local a0 = math.rad(ang - width * 0.5)
    local step = math.rad(width) / steps
    for i = 0, steps - 1 do
        local a1, a2 = a0 + step * i, a0 + step * (i + 1)
        -- (0 = up, clockwise)
        local s1, c1, s2, c2 = math.sin(a1), -math.cos(a1), math.sin(a2), -math.cos(a2)
        local ro, ri = r + thick, r
        -- The middle piece sticks out a bit: a pointer.
        local mid = i == steps * 0.5 - 1 or i == steps * 0.5
        if mid then ro = ro + thick * 0.6 end
        poly[1].x, poly[1].y = cx + s1 * ri, cy + c1 * ri
        poly[2].x, poly[2].y = cx + s1 * ro, cy + c1 * ro
        poly[3].x, poly[3].y = cx + s2 * ro, cy + c2 * ro
        poly[4].x, poly[4].y = cx + s2 * ri, cy + c2 * ri
        surface.DrawPoly(poly)
    end
end

Rhylib.Hook.Add("HUDPaint", "hud.damage", function()
    if HUD.Hidden() then return end
    local ply = LocalPlayer()
    local W, H = ScrW(), ScrH()
    local now = CurTime()
    local ft = FrameTime()

    -- Low health pulse and heartbeat.
    if cvLow:GetBool() then
        local frac = math.max(ply:Health(), 0) / math.max(ply:GetMaxHealth(), 1)
        if frac < 0.3 and not ply:GetNW2Bool("rhylib_down", false) then   -- (not while downed: that has its own screen)
            local beat = 0.6 + frac * 2
            local p = 0.5 + 0.5 * math.sin(now * math.pi * 2 / beat)
            local a = (0.18 + 0.22 * (1 - frac / 0.3)) * (0.6 + 0.4 * p)
            lowA[1], lowA[2], lowA[3], lowA[4] = a, a, a, a
            edges(lowA, COL_LOW, W, H)
            if now >= nextBeat and cvVol:GetFloat() > 0 then
                nextBeat = now + beat
                ply:EmitSound("player/heartbeat1.wav", 0, 100, vol(0.35 + 0.35 * (1 - frac / 0.3)), CHAN_STATIC)
            end
        end
    end

    -- Hit flash, fading fast.
    local any = flash[1] + flash[2] + flash[3] + flash[4] > 0.01
    if any then
        if cvFlash:GetBool() then edges(flash, flashCol, W, H) end
        local k = math.max(0, 1 - ft * 3.5)
        for i = 1, 4 do flash[i] = flash[i] * k end
    end

    -- Direction markers.
    if #marks == 0 then return end
    local s = H / 1080
    local cx, cy, r = W * 0.5, H * 0.5, math.floor(110 * s)
    local show = cvMarkers:GetBool()
    for i = #marks, 1, -1 do
        local m = marks[i]
        local age = now - m.t
        if age > MARK_LIFE then
            table.remove(marks, i)
        elseif show then
            local alpha = age < 0.2 and 255 or 255 * (1 - (age - 0.2) / (MARK_LIFE - 0.2))
            arc(cx, cy, r, math.floor((4 + 6 * m.size) * s), relAngle(m.from), 34 + 10 * m.size, m.col, alpha)
        end
    end
end)

-- In the settings menu (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "hud.damage.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    Menus.AddSetting("HUD", { id = "hud.dmgmarkers", order = 60, title = "Damage direction markers",
        desc = "Arcs around the crosshair pointing at what hit you", kind = "toggle", convar = "rhylib_dmg_markers" })
    Menus.AddSetting("HUD", { id = "hud.dmgflash", order = 61, title = "Damage flash",
        desc = "The screen edges flash when you're hit", kind = "toggle", convar = "rhylib_dmg_flash" })
    Menus.AddSetting("HUD", { id = "hud.dmgshake", order = 62, title = "Hit shake",
        desc = "A short camera shake when you're hit (your aim doesn't move)", kind = "toggle", convar = "rhylib_dmg_shake" })
    Menus.AddSetting("HUD", { id = "hud.dmglow", order = 63, title = "Low health warning",
        desc = "Red pulse and heartbeat under 30% health", kind = "toggle", convar = "rhylib_dmg_lowhp" })
    Menus.AddSetting("HUD", { id = "hud.dmgvolume", order = 65, title = "Hit sound volume",
        desc = "Hit sounds, beeps and the heartbeat (0 = off)", kind = "slider", convar = "rhylib_dmg_volume", min = 0, max = 1, decimals = 2 })
    Menus.AddSetting("HUD", { id = "hud.dmgring", order = 66, title = "Ear ringing after explosions",
        desc = "Turn off if ringing sounds bother you (e.g. tinnitus)", kind = "toggle", convar = "rhylib_dmg_ring" })
    Menus.AddSetting("HUD", { id = "hud.whizz", order = 64, title = "Near-miss sounds",
        desc = "Bolts that fly past you whizz", kind = "toggle", convar = "rhylib_whizz" })
end)
