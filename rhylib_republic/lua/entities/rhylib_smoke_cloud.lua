--[[
    A smoke or bacta cloud, left where a smoke grenade / bacta grenade
    (rhylib_grenade kinds "smoke" / "bacta") went off.

    Smoke (kind 1): a dark grey cloud weapons smokeRadius across that grows
    in over the first seconds and thins out at the end (smokeLife). It can't
    be seen through: dense particles for the edge, a few big camera-facing
    puffs for a solid core (DrawTranslucent), and the screen goes grey for
    anyone inside it (HUDPaintBackground "weapons.smokeinside"). Rhylib
    droids can't see through it: Rhylib.Weapons.SmokeBlocks(a, b) is a
    line-against-sphere check (no traces) that rhylib_droids' sight test
    calls. Players just can't see through the particles.

    Bacta (kind 2): a low blue mist on the ground (weapons bactaRadius,
    bactaLife) that doesn't block the view. Twice a second (one timer for
    all mists, only running while one exists), players standing in any mist
    (within the radius, feet less than bactaHeight above its middle) get
    rhylib_medical's Med.Bacta(ply, dt) once: a little healing, bleeding
    stepping down slowly, and a downed player's bleed-out held. Overlapping
    mists don't add up. Without rhylib_medical: just the healing. Players
    inside see a soft blue edge glow round the screen, like a commander's
    order (worked out on their own client).

    At most weapons smokeMax smoke clouds at once: a new one removes the
    oldest.

    Realm: shared. Network vars: Kind, Born, Life, Radius (nothing changes
    after it's made). Both realms: Rhylib.Weapons.smokes / .bactas =
    { [cloud] = true }. Client: a particle emitter per cloud in view, freed
    with the cloud.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Smoke"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

local Config = Rhylib.Config
Config.Register("weapons", "smokeRadius", 320, "Smoke grenade: radius of the cloud (units, 320 = 6 m)")
Config.Register("weapons", "smokeLife", 30, "Smoke grenade: seconds the cloud lasts")
Config.Register("weapons", "smokeMax", 8, "Smoke grenade: most smoke clouds at once (a new one removes the oldest)")
Config.Register("weapons", "bactaRadius", 400, "Bacta grenade: radius of the mist (units, 400 = 7.5 m)")
Config.Register("weapons", "bactaLife", 20, "Bacta grenade: seconds the mist lasts")
Config.Register("weapons", "bactaHeight", 72, "Bacta grenade: how far above the mist's middle your feet may be and still count as in it (units)")

local W = Rhylib.Weapons
W.smokes = W.smokes or {}
W.bactas = W.bactas or {}

local GROW, FADE = 3, 4   -- seconds to grow in / thin out

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Kind")
    self:NetworkVar("Float", 0, "Born")
    self:NetworkVar("Float", 1, "Life")
    self:NetworkVar("Float", 2, "Radius")
end

-- ENT:Strength(): 0..1, how thick it is now (grows in, thins out).
function ENT:Strength()
    local age, life = CurTime() - self:GetBorn(), self:GetLife()
    return math.Clamp(math.min(age / GROW, (life - age) / FADE), 0, 1)
end

-- ENT:CurRadius(): the radius right now.
function ENT:CurRadius()
    return self:GetRadius() * (0.35 + 0.65 * self:Strength())
end

-- W.SmokeBlocks(a, b): does any smoke cloud lie across the line from a to
-- b? Pure maths (closest point of the segment to each cloud's middle),
-- so it's cheap enough to run with every droid sight check. Shared.
function W.SmokeBlocks(a, b)
    if next(W.smokes) == nil then return false end
    local d = b - a
    local len2 = d:LengthSqr()
    for c in pairs(W.smokes) do
        if IsValid(c) then
            local s = c:Strength()
            if s > 0.3 then
                local m = c:GetPos() + Vector(0, 0, 40)
                local t = len2 > 0 and math.Clamp((m - a):Dot(d) / len2, 0, 1) or 0
                local r = c:CurRadius() * 0.85
                if (a + d * t):DistToSqr(m) < r * r then return true end
            end
        end
    end
    return false
end

-- W.InBacta(ply): standing in a bacta mist? Shared.
function W.InBacta(ply)
    if next(W.bactas) == nil then return false end
    local pos = ply:GetPos()
    for c in pairs(W.bactas) do
        if IsValid(c) and c:Strength() > 0 then
            local m = c:GetPos()
            local r = c:CurRadius()
            local dz = pos.z - m.z
            if dz < Config.Get("weapons", "bactaHeight") and dz > -64
                and (pos.x - m.x) ^ 2 + (pos.y - m.y) ^ 2 < r * r then
                return true
            end
        end
    end
    return false
end

function ENT:Initialize()
    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")   -- (never drawn)
    self:DrawShadow(false)
    if SERVER then
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        local bacta = self.cloudKind == 2
        self:SetKind(bacta and 2 or 1)
        self:SetBorn(CurTime())
        self:SetLife(Config.Get("weapons", bacta and "bactaLife" or "smokeLife"))
        self:SetRadius(Config.Get("weapons", bacta and "bactaRadius" or "smokeRadius"))
        -- (a mist settles on the ground under where it went off)
        local tr = util.TraceLine({ start = self:GetPos() + Vector(0, 0, 8), endpos = self:GetPos() - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
        if tr.Hit then self:SetPos(tr.HitPos + Vector(0, 0, 2)) end
        if not bacta then
            -- (too many clouds: the oldest goes)
            local n, oldest, ob = 0, nil, math.huge
            for c in pairs(W.smokes) do
                if IsValid(c) then
                    n = n + 1
                    if c:GetBorn() < ob then oldest, ob = c, c:GetBorn() end
                end
            end
            if oldest and n >= Config.Get("weapons", "smokeMax") then oldest:Remove() end
        end
    end
    if self:GetKind() == 2 then W.bactas[self] = true else W.smokes[self] = true end
    if SERVER and self:GetKind() == 2 and W.StartBacta then W.StartBacta() end
end

function ENT:OnRemove(fullUpdate)
    if fullUpdate then   -- (client full update: the cloud stays, only the emitter goes)
        if self.emitter then self.emitter:Finish() self.emitter = nil end
        return
    end
    W.smokes[self] = nil
    W.bactas[self] = nil
    if CLIENT and self.emitter then
        self.emitter:Finish()
        self.emitter = nil
    end
end

if SERVER then
    function ENT:Think()
        local now = CurTime()
        if now > self:GetBorn() + self:GetLife() then
            self:Remove()
            return
        end
        self:NextThink(now + 0.5)
        return true
    end

    -- Bacta: one timer for every mist, so a player in two mists at once
    -- still gets one dose. Runs only while a mist exists.
    function W.StartBacta()
        if timer.Exists("Rhylib.Weapons.Bacta") then return end
        timer.Create("Rhylib.Weapons.Bacta", 0.5, 0, function()
            for c in pairs(W.bactas) do if not IsValid(c) then W.bactas[c] = nil end end
            if next(W.bactas) == nil then timer.Remove("Rhylib.Weapons.Bacta") return end
            local Med = Rhylib.Medical
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() and W.InBacta(p) then
                    if Med and Med.Bacta then
                        Med.Bacta(p, 0.5)
                    elseif p:Health() < p:GetMaxHealth() then
                        p:SetHealth(math.min(p:GetMaxHealth(), p:Health() + 1))
                    end
                end
            end
        end)
    end
end

if CLIENT then
    local MAT = "particle/particle_smokegrenade"
    local SMOKE_COL = { 58, 60, 62 }
    local BACTA_COL = { 110, 190, 255 }

    local CORE = Material("particle/particle_smokegrenade")

    function ENT:Draw() end

    -- Smoke: a solid core, a few big camera-facing puffs in the middle, so
    -- the cloud can't be seen through from any side (the particles around
    -- them give the soft edge).
    function ENT:DrawTranslucent()
        if self:GetKind() == 2 then return end
        local s = self:Strength()
        if s <= 0 then return end
        local r = self:CurRadius()
        local base = self:GetPos()
        local a = math.min(255, 300 * s)
        render.SetMaterial(CORE)
        local c = Color(SMOKE_COL[1], SMOKE_COL[2] + 2, SMOKE_COL[3] + 4, a)
        render.DrawSprite(base + Vector(0, 0, 45), r * 1.9, r * 1.9, c)
        render.DrawSprite(base + Vector(0, 0, 80), r * 1.6, r * 1.6, c)
        render.DrawSprite(base + Vector(0, 0, 25), r * 1.7, r * 1.2, c)
        render.DrawSprite(base + Vector(0, 0, 60), r * 1.3, r * 1.3, c)
    end

    -- Particles: a few a second while it lasts, only while it's near enough
    -- to see (the engine stops sending it far away anyway).
    function ENT:Think()
        local now = CurTime()
        if (self.nextPuff or 0) > now then return end
        local bacta = self:GetKind() == 2
        -- (in the right list, also if the kind arrived after Initialize)
        if bacta then W.bactas[self], W.smokes[self] = true, nil else W.smokes[self], W.bactas[self] = true, nil end
        -- (a wider mist puffs more often, so it looks as thick)
        self.nextPuff = now + (bacta and 0.18 * math.Clamp(200 / math.max(self:GetRadius(), 1), 0.25, 1) or 0.1)
        -- (big enough render bounds for the core puffs)
        local R = self:GetRadius()
        if self.boundsR ~= R then
            self.boundsR = R
            self:SetRenderBounds(Vector(-R, -R, -20), Vector(R, R, R + 80))
        end
        local s = self:Strength()
        if s <= 0 then return end
        if not self.emitter then self.emitter = ParticleEmitter(self:GetPos(), false) end
        local em = self.emitter
        if not em then return end
        local r = self:CurRadius()
        local base = self:GetPos()
        if bacta then
            -- A low mist hugging the ground.
            local a = math.random() * math.pi * 2
            local d = math.sqrt(math.random()) * r
            local p = em:Add(MAT, base + Vector(math.cos(a) * d, math.sin(a) * d, 8))
            if p then
                p:SetVelocity(Vector(math.Rand(-6, 6), math.Rand(-6, 6), math.Rand(0, 4)))
                p:SetDieTime(math.Rand(3.5, 5))
                p:SetStartAlpha(70 * s)
                p:SetEndAlpha(0)
                p:SetStartSize(math.Rand(30, 45))
                p:SetEndSize(math.Rand(70, 95))
                p:SetRoll(math.Rand(0, 360))
                p:SetRollDelta(math.Rand(-0.3, 0.3))
                p:SetColor(BACTA_COL[1], BACTA_COL[2], BACTA_COL[3])
                p:SetAirResistance(40)
            end
        else
            -- A thick dark grey cloud.
            local dir = VectorRand()
            dir.z = math.abs(dir.z) * 0.6
            local p = em:Add(MAT, base + dir * math.Rand(0, r * 0.75) + Vector(0, 0, math.Rand(15, 95)))
            if p then
                p:SetVelocity(dir * math.Rand(10, 25))
                p:SetDieTime(math.Rand(7, 9))
                p:SetStartAlpha(255 * math.min(1, s + 0.2))
                p:SetEndAlpha(90 * s)
                p:SetStartSize(math.Rand(130, 170))
                p:SetEndSize(math.Rand(200, 260))
                p:SetRoll(math.Rand(0, 360))
                p:SetRollDelta(math.Rand(-0.2, 0.2))
                local g = SMOKE_COL[1] + math.random(-6, 6)
                p:SetColor(g, g + 2, g + 4)
                p:SetAirResistance(60)
            end
        end
    end

    -- Inside the smoke: the screen goes grey, fully once you're well in.
    Rhylib.Hook.Add("HUDPaintBackground", "weapons.smokeinside", function()
        if next(W.smokes) == nil then return end
        local eye = EyePos()
        local worst = 0
        for c in pairs(W.smokes) do
            if IsValid(c) then
                local s = c:Strength()
                if s > 0 then
                    local r = c:CurRadius() * 0.9
                    local d = eye:Distance(c:GetPos() + Vector(0, 0, 45))
                    if d < r then worst = math.max(worst, s * math.Clamp((r - d) / (r * 0.35), 0, 1)) end
                end
            end
        end
        if worst <= 0 then return end
        surface.SetDrawColor(SMOKE_COL[1], SMOKE_COL[2] + 2, SMOKE_COL[3] + 4, 255 * worst)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    end)

    -- Standing in bacta: the soft blue edge glow (the same look as a
    -- commander's order): a brighter pulse on stepping in, then a gentle
    -- steady glow, fading out after stepping out.
    local GLOW = Color(90, 175, 255)
    local STRIPS = 28
    local function edgeGlow(col, alpha, w, h)
        local e = math.floor(h * 0.11)
        local step = math.max(1, math.ceil(e / STRIPS))
        draw.NoTexture()
        surface.SetTexture(0)
        for i = 0, e - 1, step do
            local t = 1 - i / e
            local a = alpha * t * t * t
            surface.SetDrawColor(col.r, col.g, col.b, a)
            surface.DrawRect(0, i, w, step)
            surface.DrawRect(0, h - i - step, w, step)
            surface.DrawRect(i, 0, step, h)
            surface.DrawRect(w - i - step, 0, step, h)
        end
    end
    local inSince, lastIn = nil, -100
    Rhylib.Hook.Add("HUDPaint", "weapons.bacta", function()
        local me = LocalPlayer()
        local now = RealTime()
        local inside = IsValid(me) and me:Alive() and W.InBacta(me)
        if inside then
            inSince = inSince or now
            lastIn = now
        else
            inSince = nil
        end
        local fade = math.Clamp(1 - (now - lastIn) / 0.6, 0, 1)
        if fade <= 0 then return end
        local pulse = inSince and math.max(0, 1 - (now - inSince) / 0.8) or 0
        edgeGlow(GLOW, (32 + 6 * math.sin(now * 2) + 50 * pulse) * fade, ScrW(), ScrH())
    end)
end
