--[[
    Earthquake (client): what you feel when the server starts one (net
    weather.quake: UInt 2 level, UInt 7 seconds, Float start). Nothing
    more is sent while it runs; the strength follows W.QuakeEnvelope
    (builds, peaks, eases out).

      Screen shake: a short engine shake every 0.2 s, its strength by
        level and the envelope, times the weather setting quakeShake and
        your own rhylib_quake_shake (0-1, Settings > Interface).
      Rumble: a low loop (setting quakeSounds, the first file the game
        has), louder with the envelope (weather volume).
      Indoors (setting quakeDust): dust puffs and small bits fall from
        the ceiling around you (one trace up per puff, at most about 20 a
        second at level 3), and now and then a bit clatters.
    Nobody is hurt or knocked over.

    Hooks: Think "weather.quake". Client convar rhylib_quake_shake.
]]

local W = Rhylib.Weather

local cvShake = CreateClientConVar("rhylib_quake_shake", "1", true, false, "Earthquake: how much your screen shakes (0-1)")

local AMP = { 2.5, 6, 11 }      -- (shake amplitude by level)
local DUST = { 5, 11, 20 }      -- (dust puffs a second indoors at the peak)
local CLATTER = { "ambient/materials/rock1.wav", "ambient/materials/rock2.wav", "ambient/materials/rock3.wav",
    "ambient/materials/rock4.wav", "ambient/materials/rock5.wav", "physics/concrete/concrete_impact_soft1.wav",
    "physics/concrete/concrete_impact_soft2.wav", "physics/concrete/concrete_impact_soft3.wav" }

local quake = nil       -- { level, start, secs }
-- (kept on W, so a Lua refresh mid-quake can still stop the old ones)
if W.quakeRumble then W.quakeRumble:Stop() W.quakeRumble = nil end
if W.quakeEmitter then W.quakeEmitter:Finish() W.quakeEmitter = nil end
local nextShake, dustAcc = 0, 0
local clatter = nil     -- (the clatter files the game has)
local rumbleFile = nil  -- (false = none of them)
local cvVolume = GetConVar("rhylib_weather_volume")
local function volume() return cvVolume and math.Clamp(cvVolume:GetFloat(), 0, 1) or 0.8 end

local tr = {}
local trIn = { mask = MASK_SOLID_BRUSHONLY, output = tr }

local function stop()
    quake = nil
    if W.quakeRumble then W.quakeRumble:FadeOut(1.5) W.quakeRumble = nil end
    if W.quakeEmitter then W.quakeEmitter:Finish() W.quakeEmitter = nil end
end

local function rumblePath()
    if rumbleFile == nil then
        rumbleFile = false
        for _, p in ipairs(istable(W.Cfg("quakeSounds")) and W.Cfg("quakeSounds") or {}) do
            if isstring(p) and file.Exists("sound/" .. p, "GAME") then rumbleFile = p break end
        end
    end
    return rumbleFile or nil
end

Rhylib.Net.Receive("weather.quake", function()
    local level, secs, start = net.ReadUInt(2), net.ReadUInt(7), net.ReadFloat()
    if level < 1 or secs < 1 then return end
    stop()
    quake = { level = level, secs = secs, start = start }
    nextShake, dustAcc = 0, 0
end)

-- One dust puff (and a few bits) from the ceiling somewhere near you.
local function dustPuff(eye, level)
    local a, r = math.Rand(0, math.pi * 2), math.Rand(40, 380)
    local from = Vector(eye.x + math.cos(a) * r, eye.y + math.sin(a) * r, eye.z)
    trIn.start, trIn.endpos = from, from + Vector(0, 0, 700)
    util.TraceLine(trIn)
    if not tr.Hit or tr.HitSky or tr.StartSolid then return end
    local at = tr.HitPos - Vector(0, 0, 4)
    if not W.quakeEmitter then W.quakeEmitter = ParticleEmitter(eye) end
    local emitter = W.quakeEmitter
    if not emitter then return end
    local p = emitter:Add("particle/particle_smokegrenade", at)
    if p then
        p:SetVelocity(Vector(math.Rand(-8, 8), math.Rand(-8, 8), -math.Rand(10, 30)))
        p:SetGravity(Vector(0, 0, -60))
        p:SetDieTime(math.Rand(1.8, 3))
        p:SetStartAlpha(55 + 15 * level)
        p:SetEndAlpha(0)
        p:SetStartSize(math.Rand(3, 6))
        p:SetEndSize(math.Rand(22, 40))
        p:SetRoll(math.Rand(0, 360))
        p:SetColor(150, 140, 126)
        p:SetAirResistance(40)
    end
    for _ = 1, math.random(1, level + 1) do
        local b = emitter:Add("effects/fleck_cement" .. math.random(1, 2), at)
        if b then
            b:SetVelocity(Vector(math.Rand(-30, 30), math.Rand(-30, 30), -math.Rand(20, 80)))
            b:SetGravity(Vector(0, 0, -600))
            b:SetDieTime(math.Rand(1, 1.8))
            b:SetStartAlpha(255)
            b:SetEndAlpha(0)
            local sz = math.Rand(0.6, 1.6)
            b:SetStartSize(sz)
            b:SetEndSize(sz)
            b:SetRoll(math.Rand(0, 360))
            b:SetRollDelta(math.Rand(-4, 4))
            b:SetColor(120, 112, 100)
            b:SetCollide(true)
            b:SetBounce(0.2)
        end
    end
    if math.random() < 0.15 then
        if not clatter then
            clatter = {}
            for _, f in ipairs(CLATTER) do if file.Exists("sound/" .. f, "GAME") then clatter[#clatter + 1] = f end end
        end
        if #clatter > 0 then
            local vol = volume() * 0.6
            sound.Play(clatter[math.random(#clatter)], at, 60, math.random(90, 110), vol)
        end
    end
end

Rhylib.Hook.Add("Think", "weather.quake", function()
    local q = quake
    if not q then return end
    local now = CurTime()
    if now > q.start + q.secs then stop() return end
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local env = W.QuakeEnvelope(q, now)
    local eye = me:EyePos()
    -- Shake and rumble, 5 times a second.
    if now >= nextShake then
        nextShake = now + 0.2
        local amp = AMP[q.level] * env * math.Clamp(tonumber(W.Cfg("quakeShake")) or 1, 0, 3) * math.Clamp(cvShake:GetFloat(), 0, 1)
        if amp > 0.05 then util.ScreenShake(eye, amp, 30 + 10 * q.level, 0.3, 5000) end
        local rumble = W.quakeRumble
        if not rumble then
            local path = rumblePath()
            if path then
                rumble = CreateSound(me, path)
                W.quakeRumble = rumble
                if rumble then rumble:PlayEx(0, 85 + 5 * q.level) end
            end
        elseif not rumble:IsPlaying() then
            rumble:PlayEx(0, 85 + 5 * q.level)   -- (a file that doesn't loop: again)
        end
        if rumble then rumble:ChangeVolume(math.min(1, env * (0.4 + 0.2 * q.level)) * volume(), 0.2) end
    end
    -- Dust from the ceiling, indoors.
    if W.Cfg("quakeDust") and (W.exposure or 1) < 0.5 and env > 0.1 then
        if W.quakeEmitter then W.quakeEmitter:SetPos(eye) end
        dustAcc = dustAcc + FrameTime() * DUST[q.level] * env
        local n = 0
        while dustAcc >= 1 and n < 4 do
            dustAcc = dustAcc - 1
            n = n + 1
            dustPuff(eye, q.level)
        end
        if dustAcc > 1 then dustAcc = 1 end
    end
end)

-- Settings row (rhylib_menus).
local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Weather", { id = "weather.quakeshake", order = 85, tab = "Interface", title = "Earthquake shake",
        desc = "How much your screen shakes in an earthquake (0 = not at all)", kind = "slider", convar = "rhylib_quake_shake", min = 0, max = 1, decimals = 2 })
end
addSettings()
Rhylib.Hook.Add("InitPostEntity", "weather.quakesettings", addSettings)
