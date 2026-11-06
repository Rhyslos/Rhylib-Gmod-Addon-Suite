--[[
    Signal flare (rhylib_weapons): fired from a FlareGun's fire-mode wheel
    (rhylib/weapons/sv_25_flare.lua). Not in the spawn menu.

    No model and no physics: just its glow. Its path is worked out from a
    few numbers, the same on the server and every client, so nothing is
    sent while it flies or drifts:
      1 flight  from A with velocity V under gravity (sv_gravity), until
                the top of its arc (at least 0.6 s, so a flare fired level
                still flies a little way first); over its last weapons
                flareSlow seconds it slows smoothly to a stop (the same arc,
                travelled slower and slower)
      2 drift   from A, slowly down (weapons flareFall units/s, eased in
                over the first second) with a gentle sway
      3 rest    at A (it came down on something; still burning)
    It lights at the top of its arc or after 1.6 s, whichever is first.
    The server traces along the path every 0.05 s: hitting a wall or
    ceiling in flight starts the drift there, a wall while drifting
    drifts on straight down, the ground (or a second wall) is where it
    rests. Lit, it lights the area in its colour (a dynamic light
    flareLight units across, drawn by each client; only the nearest
    flareLightsMax lit flares in reach light up, the rest still glow) with a soft flicker,
    a big bright glow and a burning hiss, for weapons flareTime seconds.
    A smoke trail follows it from the muzzle (puffs every ~14 units of
    path, at most 10 a frame, each lasting 5-8 s).

    When it lights, idle roaming and patrolling droid groups within
    weapons flareDraw of the ground under it walk over to look (rhylib_droids
    D.Investigate, whole groups until flareDrawMax droids are coming).

    Networked (only when the phase changes, three times at most): DT Int
    ColorIndex (1-4, Rhylib.Weapons.FLARE_COLORS), Int Phase, Float LitAt
    (0 = not yet), Float T0 (the phase's start), Float Sway (drift sway,
    units), Vector A, Vector V. Sent to everyone (TRANSMIT_ALWAYS: you see
    a flare from across the map). ENT:Launch(pos, vel) starts it.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Signal flare"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

local MODEL = "models/hunter/blocks/cube025x025x025.mdl"   -- (never drawn)
local FLIGHT_MIN = 0.6   -- s of flight before it can start drifting
local LIGHT_BY = 1.6     -- s after launch it lights at the latest
local SWAY = 14          -- drift sway (units)

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ColorIndex")
    self:NetworkVar("Int", 1, "Phase")
    self:NetworkVar("Float", 0, "LitAt")
    self:NetworkVar("Float", 1, "T0")
    self:NetworkVar("Float", 2, "Sway")
    self:NetworkVar("Vector", 0, "A")
    self:NetworkVar("Vector", 1, "V")
end

local function colorOf(self)
    local C = Rhylib.Weapons and Rhylib.Weapons.FLARE_COLORS
    local c = C and C[self:GetColorIndex()]
    return c and c.col or Color(255, 80, 60)
end

local gravVar = GetConVar("sv_gravity")
local function gravity()
    return gravVar and gravVar:GetFloat() or 600
end

-- The climb: to the top of its arc (at least FLIGHT_MIN) along the
-- gravity path, its last flareSlow seconds played back slower and slower
-- until it hangs still. -> apex (path time), slow (s), flight (real s).
function ENT:FlightParts()
    local apex = math.max(FLIGHT_MIN, self:GetV().z / math.max(1, gravity()))
    local slow = math.Clamp(tonumber(Rhylib.Config.Get("weapons", "flareSlow")) or 0, 0, apex)
    return apex, slow, apex + slow / 2
end

-- How long the flight lasts (real seconds).
function ENT:FlightTime()
    local _, _, f = self:FlightParts()
    return f
end

-- (real flight time -> path time: speed ramps from full to 0 over the slow part)
function ENT:PathTime(t)
    local apex, slow = self:FlightParts()
    local t1 = apex - slow / 2
    if t <= t1 or slow <= 0 then return math.min(t, apex) end
    local u = math.min(t - t1, slow)
    return t1 + u - u * u / (2 * slow)
end

-- Where it is at time now (both realms).
function ENT:PathPos(now)
    local ph, a = self:GetPhase(), self:GetA()
    local t = math.max(0, now - self:GetT0())
    if ph == 1 then
        local v = self:GetV()
        t = self:PathTime(t)
        return a + v * t - Vector(0, 0, 0.5 * gravity() * t * t)
    elseif ph == 2 then
        local sw = self:GetSway()
        -- (it eases into its fall over the first second, from hanging still)
        local fall = t < 1 and t * t / 2 or t - 0.5
        return a + Vector(math.sin(t * 0.5) * sw, (1 - math.cos(t * 0.37)) * sw * 0.6, -math.max(1, Rhylib.Config.Get("weapons", "flareFall")) * fall)
    end
    return a
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(MODEL)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:DrawShadow(false)
    end

    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end

    -- Start flying from pos with velocity vel.
    function ENT:Launch(pos, vel)
        self.born = CurTime()
        self.last = pos
        self:SetPos(pos)
        self:SetA(pos)
        self:SetV(vel)
        self:SetT0(CurTime())
        self:SetPhase(1)
        self:NextThink(CurTime())
    end

    function ENT:SetPhaseAt(ph, pos, sway)
        self:SetA(pos)
        self:SetT0(CurTime())
        self:SetSway(sway or 0)
        self:SetPhase(ph)
        self:SetPos(pos)
        self.last = pos
    end

    function ENT:Light()
        local now = CurTime()
        self:SetLitAt(now)
        self.removeAt = now + math.max(5, Rhylib.Config.Get("weapons", "flareTime"))
        -- (droid patrols come to look, at the ground under it: that's where they can walk to)
        local D = Rhylib.Droids
        if D and D.Investigate then
            local p = self:PathPos(now)
            local tr = util.TraceLine({ start = p, endpos = p - Vector(0, 0, 20000), mask = MASK_SOLID_BRUSHONLY })
            D.Investigate(tr.Hit and tr.HitPos or p, Rhylib.Config.Get("weapons", "flareDraw"), Rhylib.Config.Get("weapons", "flareDrawMax"))
        end
    end

    function ENT:Think()
        local now = CurTime()
        local ph = self:GetPhase()
        if ph == 0 then return end
        if self:GetLitAt() == 0 and now - self.born >= math.min(self:FlightTime(), LIGHT_BY) then self:Light() end
        if ph ~= 3 then
            local p = self:PathPos(now)
            local tr = util.TraceLine({ start = self.last, endpos = p, filter = IsValid(self:GetOwner()) and { self, self:GetOwner() } or self, mask = MASK_SOLID })
            if tr.Hit then
                local n = tr.HitNormal
                if n.z > 0.5 or (ph == 2 and self:GetSway() == 0) then
                    -- (came down on something, or a second wall: it rests there)
                    self:SetPhaseAt(3, tr.HitPos + n * 3)
                else
                    -- (a wall or ceiling: it drifts straight down from there)
                    if self:GetLitAt() == 0 then self:Light() end
                    self:SetPhaseAt(2, tr.HitPos + n * 4, 0)
                end
            elseif ph == 1 and now - self:GetT0() >= self:FlightTime() then
                self:SetPhaseAt(2, p, SWAY)
            else
                self.last = p
            end
        end
        if self.removeAt and now >= self.removeAt then self:Remove() return end
        if now - (self.born or now) > 120 then self:Remove() return end   -- (never lit somehow)
        self:NextThink(now + 0.05)
        return true
    end
    return
end

-- Client: glow, light, smoke, sound.
local GLOW = Material("sprites/light_glow02_add")
local BURN = { "weapons/flaregun/burn.wav", "ambient/fire/fire_small_loop1.wav", "ambient/fire/fire_small_loop2.wav" }
local burnFile
local function burnSound()
    if burnFile == nil then
        burnFile = false
        for _, p in ipairs(BURN) do if file.Exists("sound/" .. p, "GAME") then burnFile = p break end end
    end
    return burnFile or nil
end

function ENT:Initialize()
    self.nextSmoke = 0
end

-- Only the nearest few lit flares cast a light on each client (weapons
-- flareLightsMax, and only those whose light can reach you): the engine
-- has room for few dynamic lights. Picked every 0.25 s.
local lightOk, lightAt = {}, 0
local function mayLight(e)
    local now = CurTime()
    if now >= lightAt then
        lightAt = now + 0.25
        lightOk = {}
        local me = LocalPlayer()
        if IsValid(me) then
            local eye = me:EyePos()
            local reach = Rhylib.Config.Get("weapons", "flareLight") * 1.25
            local list = {}
            for _, f in ipairs(ents.FindByClass("rhylib_flare")) do
                if IsValid(f) and f:GetLitAt() > 0 then
                    local d = (f.drawPos or f:GetPos()):DistToSqr(eye)
                    if d < reach * reach then list[#list + 1] = { f = f, d = d } end
                end
            end
            table.sort(list, function(a, b) return a.d < b.d end)
            for i = 1, math.min(#list, math.max(0, math.floor(Rhylib.Config.Get("weapons", "flareLightsMax")))) do
                lightOk[list[i].f] = true
            end
        end
    end
    return lightOk[e]
end

function ENT:Think()
    local now = CurTime()
    if self:GetPhase() == 0 then return end
    local pos = self:PathPos(now)
    self.drawPos = pos
    self:SetPos(pos)   -- (so its hiss and light follow it; the server only moves it on a phase change)
    self:SetRenderBoundsWS(pos - Vector(220, 220, 220), pos + Vector(220, 220, 220))
    self:Trail(pos, colorOf(self))
    local lit = self:GetLitAt()
    if lit == 0 then return end
    local c = colorOf(self)
    -- (a soft flicker; it fades in over half a second)
    local up = math.Clamp((now - lit) / 0.5, 0, 1)
    local flick = 0.88 + 0.12 * math.sin(now * 23 + self:EntIndex()) * math.sin(now * 7.3)
    local dl = mayLight(self) and DynamicLight(self:EntIndex())
    if dl then
        dl.pos = pos
        dl.r, dl.g, dl.b = c.r, c.g, c.b
        dl.brightness = 5 * up
        dl.decay = 1000
        dl.size = Rhylib.Config.Get("weapons", "flareLight") * flick * up
        dl.dietime = now + 0.25
    end
    if not self.snd then
        local p = burnSound()
        if p then
            self.snd = CreateSound(self, p)
            if self.snd then self.snd:PlayEx(0.45, 130) end
        end
    end
end

-- Smoke trail along the path (from launch, lit or not).
local TRAIL_STEP = 14
function ENT:Trail(pos, c)
    local last = self.trailPos
    self.trailPos = pos
    if not last then return end
    local d = pos:Distance(last)
    if d < TRAIL_STEP and CurTime() < (self.nextSmoke or 0) then self.trailPos = last return end
    self.nextSmoke = CurTime() + 0.15   -- (resting or slow: a puff now and then)
    local em = self.em or ParticleEmitter(pos)
    self.em = em
    if not em then return end
    em:SetPos(pos)
    local n = math.Clamp(math.floor(d / TRAIL_STEP), 1, 10)
    local tint = c and 0.3 or 0
    for k = 1, n do
        local p = em:Add("particle/particle_smokegrenade", LerpVector(k / n, last, pos))
        if p then
            p:SetVelocity(VectorRand() * 5 + Vector(0, 0, 6))
            p:SetDieTime(math.Rand(5, 8))
            p:SetStartAlpha(110)
            p:SetEndAlpha(0)
            p:SetStartSize(math.Rand(6, 9))
            p:SetEndSize(math.Rand(40, 60))
            p:SetRoll(math.Rand(0, 360))
            p:SetRollDelta(math.Rand(-0.3, 0.3))
            local r, g, b = 200, 200, 200
            if c then r, g, b = 190 + c.r * tint * 0.2, 190 + c.g * tint * 0.2, 190 + c.b * tint * 0.2 end
            p:SetColor(math.min(255, r), math.min(255, g), math.min(255, b))
            p:SetAirResistance(60)
        end
    end
end

function ENT:Draw()
end

-- Only its glow: a small bright one in flight, a big soft one once lit.
function ENT:DrawTranslucent()
    local pos = self.drawPos
    if not pos then return end
    local c = colorOf(self)
    local now = CurTime()
    render.SetMaterial(GLOW)
    local lit = self:GetLitAt()
    if lit == 0 then
        render.DrawSprite(pos, 26, 26, Color(c.r, c.g, c.b, 255))
        render.DrawSprite(pos, 8, 8, Color(255, 255, 255, 240))
        return
    end
    local up = math.Clamp((now - lit) / 0.5, 0, 1)
    local f = 1 + math.sin(now * 19 + self:EntIndex()) * 0.12
    -- (additive: drawn twice for a brighter glow; reds read dim otherwise)
    render.DrawSprite(pos, 420 * up * f, 420 * up * f, Color(c.r, c.g, c.b, 110))
    render.DrawSprite(pos, 130 * f, 130 * f, Color(c.r, c.g, c.b, 255))
    render.DrawSprite(pos, 130 * f, 130 * f, Color(c.r, c.g, c.b, 255))
    render.DrawSprite(pos, 40 * f, 40 * f, Color(255, 255, 255, 255))
end

function ENT:OnRemove()
    if self.snd then self.snd:Stop() self.snd = nil end
    if self.em then self.em:Finish() self.em = nil end
end
