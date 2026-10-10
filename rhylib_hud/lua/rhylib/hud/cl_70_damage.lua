--[[
    Damage feedback (client), from the hud.dmg batch (sv_30_damage.lua):

      - direction markers: an arc on a ring around the crosshair pointing
        at where the hit came from (it keeps pointing there as you turn),
        red for health, blue for hits the armour soaked, yellow for sim
        hits; thicker for bigger hits
      - a flash from the screen edges, strongest on the side it came from
      - a short camera shake (view only, never the aim)
      - a hit sound: flesh, armour clang, or a sim beep; blasts ring the ears
      - low health: a slow red pulse at the edges and a heartbeat
      - head hits crack the visor (first person, fades after a few seconds)

    Near misses (bolts passing close) are in rhylib_weapons cl_10_bolts.lua.
    Client convars (Settings > HUD): rhylib_dmg_markers, rhylib_dmg_flash,
    rhylib_dmg_shake, rhylib_dmg_lowhp, rhylib_dmg_volume (0-1, scales
    every sound here), rhylib_dmg_ring (ear ringing on/off),
    rhylib_dmg_cracks (visor cracks). All default on (volume 1).
]]

local HUD = Rhylib.HUD
local DMG_SIM, DMG_BLAST, DMG_NODIR, DMG_HEAD = 1, 2, 4, 8   -- same bits as HUD.DMG_* (sv_30_damage.lua)

local cvMarkers = CreateClientConVar("rhylib_dmg_markers", "1", true, false, "Damage direction markers around the crosshair")
local cvFlash = CreateClientConVar("rhylib_dmg_flash", "1", true, false, "Screen edge flash when hit")
local cvShake = CreateClientConVar("rhylib_dmg_shake", "1", true, false, "Short camera shake when hit (view only)")
local cvLow = CreateClientConVar("rhylib_dmg_lowhp", "1", true, false, "Red pulse and heartbeat at low health")
local cvVol = CreateClientConVar("rhylib_dmg_volume", "1", true, false, "Volume of hit sounds, beeps and the heartbeat (0-1)")
local cvRing = CreateClientConVar("rhylib_dmg_ring", "1", true, false, "Ear ringing after big explosions")
local cvCracks = CreateClientConVar("rhylib_dmg_cracks", "1", true, false, "Visor cracks from head hits (first person)")

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

-- One hit: health lost (8 bits), armour lost (8 bits), flags (4 bits),
-- then the source position unless NODIR. A hit counts as "armour" (blue,
-- metal clang) when the armour took more than health.
Rhylib.Net.ReceiveBatch("hud.dmg", function()
    local h = { amount = net.ReadUInt(8), armour = net.ReadUInt(8), flags = net.ReadUInt(4) }
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

    -- Head hit (real damage): a crack in the visor.
    if bit.band(h.flags, DMG_HEAD) ~= 0 and not sim then HUD.AddCrack(h.from) end

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

-- The heartbeat file loops by itself: one sound, started and stopped
-- (respawning, healing or turning it off stops it).
local beat
local function heartbeat(on, level)
    local ply = LocalPlayer()
    if on then
        if not beat then beat = CreateSound(ply, "player/heartbeat1.wav") end
        if not beat:IsPlaying() then beat:PlayEx(0, 100) end
        beat:ChangeVolume(vol(level), 0.2)
        beat:ChangePitch(100 + 25 * level, 0.2)
    elseif beat and beat:IsPlaying() then
        beat:Stop()
    end
end

--------------------------------------------------------------------------
-- Visor cracks (head hits, first person): a hole with jagged cracks
-- running out from it, made once per hit, fading after CRACK_LIFE.
--------------------------------------------------------------------------

local CRACK_LIFE, MAX_CRACKS = 9, 6
local cracks = {}
local COL_CRACK = Color(225, 235, 240)
local COL_CRACK_DARK = Color(0, 0, 0)

-- HUD.AddCrack(from): adds one visor crack (up to 6 at once, oldest
-- dropped), placed toward the side `from` (a world position, or nil for
-- anywhere) is on. Fades after 9 s. Called for real head hits; drawn only
-- in first person with rhylib_dmg_cracks on. Client only.
-- Example: Rhylib.HUD.AddCrack(attacker:EyePos())
function HUD.AddCrack(from)
    local W, H = ScrW(), ScrH()
    -- Somewhere on the visor, toward the side the shot came from.
    local x, y = math.Rand(0.25, 0.75), math.Rand(0.2, 0.55)
    if from then
        local ply = LocalPlayer()
        local a = math.NormalizeAngle(ply:EyeAngles().y - (from - ply:EyePos()):Angle().y)
        x = math.Clamp(0.5 + a / 180 * 0.6 + math.Rand(-0.08, 0.08), 0.15, 0.85)
    end
    x, y = x * W, y * H
    local s = H / 1080
    local lines = {}
    for _ = 1, math.random(6, 9) do
        -- One crack: a few kinked pieces outward, sometimes a branch.
        local ang = math.Rand(0, math.pi * 2)
        local len = math.Rand(40, 150) * s
        local px, py = x, y
        local n = math.random(3, 5)
        for i = 1, n do
            ang = ang + math.Rand(-0.45, 0.45)
            local step = len / n
            local nx, ny = px + math.cos(ang) * step, py + math.sin(ang) * step
            lines[#lines + 1] = { px, py, nx, ny, 1 - (i - 1) / n }
            if i == 2 and math.random() < 0.5 then
                local b = ang + (math.random() < 0.5 and 0.7 or -0.7)
                lines[#lines + 1] = { nx, ny, nx + math.cos(b) * step * 0.8, ny + math.sin(b) * step * 0.8, 0.5 }
            end
            px, py = nx, ny
        end
    end
    -- A ring around the hole.
    local ring = {}
    local r = math.Rand(10, 16) * s
    for i = 0, 10 do
        local a = i / 10 * math.pi * 2
        local rr = r * math.Rand(0.8, 1.2)
        ring[#ring + 1] = { x + math.cos(a) * rr, y + math.sin(a) * rr }
    end
    if #cracks >= MAX_CRACKS then table.remove(cracks, 1) end
    cracks[#cracks + 1] = { t = CurTime(), x = x, y = y, r = r, lines = lines, ring = ring }
end

local function drawCracks(now)
    draw.NoTexture()
    for i = #cracks, 1, -1 do
        local c = cracks[i]
        local age = now - c.t
        if age > CRACK_LIFE then
            table.remove(cracks, i)
        else
            local a = age < CRACK_LIFE - 2 and 1 or (CRACK_LIFE - age) / 2
            -- Dark hole with a frosted rim.
            surface.SetDrawColor(COL_CRACK_DARK.r, COL_CRACK_DARK.g, COL_CRACK_DARK.b, 170 * a)
            surface.DrawRect(c.x - c.r * 0.35, c.y - c.r * 0.35, c.r * 0.7, c.r * 0.7)
            for j = 1, #c.ring - 1 do
                local p, q = c.ring[j], c.ring[j + 1]
                surface.SetDrawColor(COL_CRACK.r, COL_CRACK.g, COL_CRACK.b, 200 * a)
                surface.DrawLine(p[1], p[2], q[1], q[2])
            end
            for _, l in ipairs(c.lines) do
                local la = a * (0.35 + 0.65 * l[5])
                surface.SetDrawColor(0, 0, 0, 120 * la)
                surface.DrawLine(l[1] + 1, l[2] + 1, l[3] + 1, l[4] + 1)
                surface.SetDrawColor(COL_CRACK.r, COL_CRACK.g, COL_CRACK.b, 210 * la)
                surface.DrawLine(l[1], l[2], l[3], l[4])
            end
        end
    end
end
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

-- Draw order: cracks, low-health pulse, hit flash, then the markers.
-- While HUD.Hidden() (dead) the heartbeat stops and cracks are cleared.
Rhylib.Hook.Add("HUDPaint", "hud.damage", function()
    if HUD.Hidden() then
        heartbeat(false)
        cracks = {}   -- (dead: a fresh visor on respawn)
        return
    end
    local ply = LocalPlayer()
    local W, H = ScrW(), ScrH()
    local now = CurTime()
    local ft = FrameTime()

    -- Visor cracks (first person only).
    if #cracks > 0 then
        if cvCracks:GetBool() and not ply:ShouldDrawLocalPlayer() then drawCracks(now) end
    end

    -- Low health pulse and heartbeat.
    local lowNow = false
    if cvLow:GetBool() then
        local frac = math.max(ply:Health(), 0) / math.max(ply:GetMaxHealth(), 1)
        if frac < 0.3 and not ply:GetNW2Bool("rhylib_down", false) then   -- (not while downed: that has its own screen)
            lowNow = true
            local period = 0.6 + frac * 2
            local p = 0.5 + 0.5 * math.sin(now * math.pi * 2 / period)
            local a = (0.18 + 0.22 * (1 - frac / 0.3)) * (0.6 + 0.4 * p)
            lowA[1], lowA[2], lowA[3], lowA[4] = a, a, a, a
            edges(lowA, COL_LOW, W, H)
            heartbeat(cvVol:GetFloat() > 0, 0.35 + 0.35 * (1 - frac / 0.3))
        end
    end
    if not lowNow then heartbeat(false) end

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
    Menus.AddSetting("HUD", { id = "hud.dmgcracks", order = 67, title = "Visor cracks",
        desc = "Head hits crack your visor for a few seconds (first person)", kind = "toggle", convar = "rhylib_dmg_cracks" })
    Menus.AddSetting("HUD", { id = "hud.whizz", order = 64, title = "Near-miss sounds",
        desc = "Bolts that fly past you whizz", kind = "toggle", convar = "rhylib_whizz" })
end)
