--[[
    RPS-6 top-attack rocket (lock-on mode, EOD Top attack skill).
    Climbs first (up to topClimb units, less under a ceiling), then turns
    over and dives onto its goal:
      locked   the target (it follows it if it moves; a target that's
               gone: its last spot)
      no lock  laser guided: the spot the shooter aims at (ENT:LaserSpot),
               while they live and hold the same gun; after that, the last
               spot
    Moved by hand each tick with one trace, like rhylib_b2_rocket. It flies
    like a heavy rocket: it eases into and out of turns (weapons
    topTurnAccel) and turns at most topTurn; laser guided, the point it
    heads for follows the dot at topLaserFollow, so flicking your aim
    doesn't swing it round. Blast
    (rhylib_weapons W.Explode) =
    the RPS-6's (Explosive radius / damage), hook Rhylib.Explosion strength
    2 for comms jammers (kind "rocket"); Rhylib.Weapons.topAttackHit is
    this rocket while that blast's damage is dealt, if it was fired with a
    lock (laser-guided: nil). Gives up after 12 s (explodes
    where it is).
    Cluster (rhylib_rps6 cluster mode, EOD Cluster rockets skill): spawned
    with aimAt, it isn't guided; it climbs the same way and heads for
    clusterBurstHeight above aimAt (lower under a ceiling). There it
    bursts (a flash and a bang, no damage) into clusterCount bomblets,
    dropped to land spread over clusterSpread round the spot under the
    burst. Each goes off where it hits, or after clusterFuse:
    W.Explode with clusterDamage / clusterRadius, kind "cluster",
    strength 1 (hook Rhylib.Explosion: small comms jammers, mines).
    A rocket that hits something on the way explodes there like a normal
    rocket. Bomblets are not entities: the server moves them in a Tick
    hook (one trace each a tick, only while some fall) and sends each
    burst once (net wep.cluster: position, gravity, fuse, the bomblets'
    velocities, to the players in its PVS); clients fly the same paths
    and draw a glow and a short streak. At most clusterMax bomblets fall
    at once (clusterMaxPlayer for one player); past that a burst drops
    fewer.
    Spawned by rhylib_rps6 with: dir, target, owner, weapon, explosive,
    aimAt (cluster only).
    Shared (AddCSLuaFile): server flies it; client draws it, the flame,
    every guided rocket's red laser dot (everyone sees the dot) and the
    bomblets.
]]

AddCSLuaFile()

-- Settings (module "weapons"; registered here, so only with rhylib_republic).
local Config = Rhylib.Config
Config.Register("weapons", "topClimb", 900, "RPS-6 top attack: highest climb before the dive (units)")
Config.Register("weapons", "topSpeed", 2000, "RPS-6 top attack: rocket speed (units/s)")
Config.Register("weapons", "topTurn", 100, "RPS-6 top attack: fastest turn in the dive (degrees/s; the climb turns at 70% of it)")
Config.Register("weapons", "topTurnAccel", 220, "RPS-6 top attack: how quickly the rocket gets into and out of a turn (degrees/s each second)")
Config.Register("weapons", "topLaserFollow", 1200, "RPS-6 top attack, laser guided: how fast the point the rocket heads for follows the laser dot (units/s)")
Config.Register("weapons", "clusterBurstHeight", 525, "RPS-6 cluster: how high above the spot you aimed at the rocket bursts (units; 525 = 10 m; lower under a ceiling)")
Config.Register("weapons", "clusterCount", 10, "RPS-6 cluster: bomblets in one burst (up to 32)")
Config.Register("weapons", "clusterSpread", 315, "RPS-6 cluster: radius the bomblets land in, round the spot under the burst (units; 315 = 6 m)")
Config.Register("weapons", "clusterDamage", 50, "RPS-6 cluster: blast damage of one bomblet at its centre")
Config.Register("weapons", "clusterRadius", 140, "RPS-6 cluster: blast radius of one bomblet (units)")
Config.Register("weapons", "clusterFuse", 4, "RPS-6 cluster: seconds after the burst a bomblet that hit nothing goes off anyway")
Config.Register("weapons", "clusterMax", 64, "RPS-6 cluster: most bomblets falling at once on the server (a burst past it drops fewer)")
Config.Register("weapons", "clusterMaxPlayer", 20, "RPS-6 cluster: most bomblets falling at once from one player")

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Top-attack rocket"
ENT.Category = "Rhy's Heavy"
ENT.Model = "models/weapons/w_missile_closed.mdl"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

-- Guide: the player steering it by laser (unlocked shots), else NULL.
function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Guide")
end

-- ENT:LaserSpot() -> where the guide's laser lands, or nil if it isn't
-- steering any more (dead, other gun out, aiming at the sky). Shared: the
-- server steers by it, clients draw the dot. The gun class is in NW2String
-- rhylib_guideGun.
-- Where the guide's laser lands (nil if it isn't steering any more).
local GUIDE_RANGE = 12000
function ENT:LaserSpot()
    local g = self:GetGuide()
    if not (IsValid(g) and g:IsPlayer() and g:Alive()) then return nil end
    local w = g:GetActiveWeapon()
    if not (IsValid(w) and w.LockOn and w:GetClass() == self:GetNW2String("rhylib_guideGun", "rhylib_rps6")) then return nil end
    local tr = util.TraceLine({ start = g:EyePos(), endpos = g:EyePos() + g:GetAimVector() * GUIDE_RANGE,
        filter = { g, self }, mask = MASK_SHOT })
    if not tr.Hit or tr.HitSky then return nil end
    return tr.HitPos
end

if SERVER then
    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    -- Bomblets in the air: list of { pos, vel, owner, inflictor, fuseAt };
    -- falling[owner] = how many are that player's.
    Rhylib.Net.Register("wep.cluster")
    local bomblets, falling = {}, {}
    local btr = {}
    local btrData = { mask = MASK_SHOT, output = btr }
    local MAX_BURST = 32

    local function gravity()
        local g = GetConVar("sv_gravity")
        return math.Clamp(math.floor(g and g:GetFloat() or 600), 50, 4095)   -- (whole units: sent in 12 bits)
    end

    local function boom(b, pos)
        local r = Config.Get("weapons", "clusterRadius")
        Rhylib.Weapons.Explode({
            pos = pos, radius = r, damage = Config.Get("weapons", "clusterDamage"),
            attacker = b.owner, inflictor = b.inflictor,
            tier = 1, reach = r * 0.5, kind = "cluster",
            effectData = { magnitude = 1, scale = 0.5 },
            shake = { 3, 120, 0.4, r * 2.5 },
        })
    end

    local function tick()
        local now = CurTime()
        local dt = engine.TickInterval()
        local g = gravity()
        local i = 1
        while i <= #bomblets do
            local b = bomblets[i]
            local from = b.pos
            local to = from + b.vel * dt
            b.vel.z = b.vel.z - g * dt
            btrData.start, btrData.endpos = from, to
            util.TraceLine(btrData)
            local gone = false
            if btr.Hit then
                if not btr.HitSky then boom(b, btr.HitPos + btr.HitNormal * 4) end
                gone = true
            elseif now >= b.fuseAt or not util.IsInWorld(to) then
                if util.IsInWorld(to) then boom(b, to) end
                gone = true
            else
                b.pos = to
            end
            if gone then
                local o = b.ownerKey
                falling[o] = (falling[o] or 1) - 1
                if falling[o] <= 0 then falling[o] = nil end
                bomblets[i] = bomblets[#bomblets]
                bomblets[#bomblets] = nil
            else
                i = i + 1
            end
        end
        if #bomblets == 0 then Rhylib.Hook.Remove("Tick", "weapons.cluster") end
    end

    -- burst(pos, owner, weapon): the flash and bang, then the bomblets,
    -- each aimed to land at a random spot within clusterSpread of the
    -- ground under pos.
    local function burst(pos, owner, weapon)
        local ed = EffectData()
        ed:SetOrigin(pos)
        util.Effect("HelicopterMegaBomb", ed, true, true)
        sound.Play("ambient/explosions/explode_4.wav", pos, 120, 125)
        util.ScreenShake(pos, 4, 100, 0.6, 1500)
        local Dr = Rhylib.Droids
        if Dr and Dr.HearNoise then Dr.HearNoise(pos, "blast", IsValid(owner) and owner or game.GetWorld()) end

        local ownerKey = IsValid(owner) and owner or game.GetWorld()
        local n = math.Clamp(math.floor(Config.Get("weapons", "clusterCount")), 0, MAX_BURST)
        n = math.floor(math.min(n, math.max(0, math.floor(Config.Get("weapons", "clusterMax")) - #bomblets),
            math.max(0, math.floor(Config.Get("weapons", "clusterMaxPlayer")) - (falling[ownerKey] or 0))))
        if n <= 0 then return end
        local g = gravity()
        local ground = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, 4000), mask = MASK_SOLID_BRUSHONLY })
        local h = math.max(40, pos.z - ground.HitPos.z)
        local down = 80   -- (thrown down out of the casing, units/s)
        local t = (-down + math.sqrt(down * down + 2 * g * h)) / g
        local spread = math.max(0, Config.Get("weapons", "clusterSpread"))
        local fuse = math.Clamp(Config.Get("weapons", "clusterFuse"), 0.5, 25)
        local now = CurTime()
        local inflictor = IsValid(weapon) and weapon or nil
        local vels = {}
        for k = 1, n do
            local r = spread * math.sqrt(math.random())
            local a = math.random() * math.pi * 2
            local v = Vector(math.cos(a) * r / t, math.sin(a) * r / t, -down)
            vels[k] = v
            bomblets[#bomblets + 1] = { pos = Vector(pos), vel = Vector(v), owner = owner, inflictor = inflictor,
                ownerKey = ownerKey, fuseAt = now + fuse }
        end
        falling[ownerKey] = (falling[ownerKey] or 0) + n
        Rhylib.Hook.Add("Tick", "weapons.cluster", tick)
        Rhylib.Net.Start("wep.cluster")
        net.WriteVector(pos)
        net.WriteUInt(g, 12)
        net.WriteUInt(math.floor(fuse * 10), 8)
        net.WriteUInt(n, 6)
        for k = 1, n do net.WriteVector(vels[k]) end
        net.SendPVS(pos)
    end

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self.dir = (self.dir or self:GetForward()):GetNormalized()
        self.locked = IsValid(self.target)   -- (fired with a lock: W.topAttackHit)
        self.speed = Config.Get("weapons", "topSpeed")
        self.born = CurTime()
        self.dieAt = CurTime() + 12
        local me, owner = self, self.owner
        self.filterFn = function(e) return e ~= me and e ~= owner end
        if self.aimAt then
            -- cluster: the burst point, clusterBurstHeight over the aim
            -- (under a ceiling: just below it)
            local up = math.max(0, Config.Get("weapons", "clusterBurstHeight"))
            local roof = util.TraceLine({ start = self.aimAt, endpos = self.aimAt + Vector(0, 0, up), mask = MASK_SOLID_BRUSHONLY })
            self.burstAt = roof.Hit and roof.HitPos - Vector(0, 0, math.min(40, roof.Fraction * up)) or roof.HitPos
        elseif not IsValid(self.target) and IsValid(owner) and owner:IsPlayer() then
            -- laser guided (fired without a lock)
            self:SetGuide(owner)
            if IsValid(self.weapon) then self:SetNW2String("rhylib_guideGun", self.weapon:GetClass()) end
        end
        self.lastSpot = self.burstAt or (IsValid(self.target) and self.target:WorldSpaceCenter()) or self:LaserSpot() or (self:GetPos() + self.dir * 2000)

        -- The top of the climb: part way to the target, high up (lower
        -- under a ceiling; no room = straight at it).
        local from = self:GetPos()
        local to = self.lastSpot
        local flat = Vector(to.x - from.x, to.y - from.y, 0)
        local dist = flat:Length()
        local want = math.Clamp(dist * 0.5, 250, Config.Get("weapons", "topClimb"))
        local roof = util.TraceLine({ start = from, endpos = from + Vector(0, 0, want + 80), mask = MASK_SOLID_BRUSHONLY })
        local h = roof.Hit and (roof.HitPos.z - from.z - 80) or want
        if h >= 150 and dist > 300 then
            self.apex = from + flat * 0.35 + Vector(0, 0, math.max(h, to.z - from.z + h * 0.5))
            local ok = util.TraceLine({ start = from, endpos = self.apex, mask = MASK_SOLID_BRUSHONLY })
            if ok.Hit then self.apex = nil end
        end
        self.phase = self.apex and 1 or 2
        -- out of the tube upward
        if self.apex then self.dir = (self.dir + Vector(0, 0, 1.2)):GetNormalized() end
        self:SetAngles(self.dir:Angle())
        util.SpriteTrail(self, 0, Color(220, 220, 220), true, 14, 0, 0.8, 1 / 14 * 0.5, "trails/smoke.vmt")
        self:EmitSound("weapons/rpg/rocket1.wav", 75, 110)
    end

    function ENT:Explode(pos, hit)
        if self.done then return end
        self.done = true
        local owner = IsValid(self.owner) and self.owner or game.GetWorld()
        local inflictor = IsValid(self.weapon) and self.weapon or self
        local ex = self.explosive or { radius = 200, damage = 250 }
        -- (W.topAttackHit while its damage is dealt, only for a rocket fired
        -- with a lock: damage hooks can tell a locked rocket from a fired or
        -- laser-guided one, e.g. rhylib_droids' AAT tank)
        local W = Rhylib.Weapons
        W.topAttackHit = self.locked and self or nil
        ProtectedCall(function()
            W.Explode({
                pos = pos, radius = ex.radius, damage = ex.damage,
                attacker = owner, inflictor = inflictor,
                tier = ex.tier or 2, kind = "rocket",
                effectData = { magnitude = 1, scale = 1 },
                decal = true, decalFilter = self,
                direct = ex.direct and { ent = hit, damage = ex.direct } or nil,
            })
        end)
        W.topAttackHit = nil
        self:StopSound("weapons/rpg/rocket1.wav")
        self:Remove()
    end

    -- ENT:Burst(pos): a cluster rocket opens at pos (the bomblets: below).
    function ENT:Burst(pos)
        if self.done then return end
        self.done = true
        burst(pos, self.owner, self.weapon)
        self:StopSound("weapons/rpg/rocket1.wav")
        self:Remove()
    end

    -- Turn the heading toward want by at most rate radians this tick.
    local function steer(dir, want, rate)
        local dot = math.Clamp(dir:Dot(want), -1, 1)
        local ang = math.acos(dot)
        if ang <= rate or ang < 1e-4 then return want end
        local k = rate / ang
        local d = dir * (1 - k) + want * k
        d:Normalize()
        return d
    end

    function ENT:Think()
        local now = CurTime()
        if now > self.dieAt then self:Explode(self:GetPos()) return end
        local dt = engine.TickInterval()
        local from = self:GetPos()
        if IsValid(self.target) and (not self.target.destroyed) then
            self.lastSpot = self.target:WorldSpaceCenter()
        elseif IsValid(self:GetGuide()) then
            -- laser: head for a point that follows the dot at topLaserFollow
            -- (a flick of the aim doesn't swing the rocket round); the guide
            -- put the gun away / died = it keeps heading for that point
            local spot = self:LaserSpot()
            if spot then
                local d = spot - self.lastSpot
                local len = d:Length()
                local step = Config.Get("weapons", "topLaserFollow") * dt
                if len > step then self.lastSpot = self.lastSpot + d * (step / len) else self.lastSpot = spot end
            else
                self:SetGuide(NULL)
            end
        end
        local goal
        if self.phase == 1 then
            goal = self.apex
            local to = goal - from
            -- over the top: close to it, past it, or climbing too long
            if to:Length() < 140 or to:Dot(self.dir) <= 0 or now - self.born > 2.5 then self.phase = 2 end
        end
        if self.phase == 2 then goal = self.lastSpot end
        local want = (goal - from):GetNormalized()
        -- A heavy rocket: it eases into a turn and out of it (turnV, the
        -- turn rate now, rad/s, changes by topTurnAccel a second) and never
        -- turns faster than topTurn (the climb at 70% of it).
        local maxRate = math.rad(Config.Get("weapons", "topTurn")) * (self.phase == 1 and 0.7 or 1)
        local need = math.acos(math.Clamp(self.dir:Dot(want), -1, 1)) / dt
        self.turnV = math.Approach(self.turnV or 0, math.min(need, maxRate), math.rad(Config.Get("weapons", "topTurnAccel")) * dt)
        self.dir = steer(self.dir, want, self.turnV * dt)
        local to = from + self.dir * self.speed * dt
        trData.start, trData.endpos = from, to
        trData.filter = self.filterFn
        util.TraceLine(trData)
        if tr.HitSky then
            -- (climbing into the skybox: dive now instead of vanishing)
            if self.phase == 1 then
                self.phase = 2
                self.dir = (self.lastSpot - from):GetNormalized()
                self:NextThink(now)
                return true
            end
            self:Remove()
            return
        end
        if tr.Hit then
            self:Explode(tr.HitPos + tr.HitNormal * 4, tr.Entity)
            return
        end
        -- cluster: burst at the point, or once it's close and going past it
        if self.burstAt and self.phase == 2 then
            local d2 = to:DistToSqr(self.burstAt)
            if d2 < 60 * 60 or (d2 < 400 * 400 and (self.burstAt - to):Dot(self.dir) <= 0) then
                self:Burst(to)
                return
            end
        end
        -- close enough to the target: go off (a jammer's centre may sit in its hull)
        if self.phase == 2 and not self.burstAt and to:DistToSqr(self.lastSpot) < 40 * 40 then
            self:Explode(to, IsValid(self.target) and self.target or nil)
            return
        end
        self:SetPos(to)
        self:SetAngles(self.dir:Angle())
        self:NextThink(now)
        return true
    end

    function ENT:OnRemove()
        self:StopSound("weapons/rpg/rocket1.wav")
    end
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local FLAME = Color(255, 170, 80)

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        render.SetMaterial(GLOW)
        render.DrawSprite(self:GetPos() - self:GetForward() * 10, 28, 28, FLAME)
    end
end

if CLIENT then
    -- Cluster bomblets (net wep.cluster): flown on the same paths as on the
    -- server, drawn as a glow with a short streak until they hit something.
    local list = {}
    local GLOW = Material("sprites/light_glow02_add")
    local STREAK = Material("trails/smoke")
    local HOT = Color(255, 180, 90)
    local SMOKE = Color(200, 200, 200, 120)
    local ctr = {}
    local ctrData = { mask = MASK_SHOT, output = ctr }

    -- (moved once a frame in Think; the draw hook can run several times a frame)
    local function moveBomblets()
        local now = CurTime()
        local dt = FrameTime()
        local i = 1
        while i <= #list do
            local b = list[i]
            local from = b.pos
            local to = from + b.vel * dt
            b.vel.z = b.vel.z - b.g * dt
            ctrData.start, ctrData.endpos = from, to
            util.TraceLine(ctrData)
            if ctr.Hit or now >= b.fuseAt then
                list[i] = list[#list]
                list[#list] = nil
            else
                b.pos = to
                i = i + 1
            end
        end
        if #list == 0 then
            Rhylib.Hook.Remove("Think", "weapons.cluster")
            Rhylib.Hook.Remove("PostDrawTranslucentRenderables", "weapons.cluster")
        end
    end
    local function drawBomblets(depth, sky)
        if depth or sky then return end
        for _, b in ipairs(list) do
            render.SetMaterial(STREAK)
            render.DrawBeam(b.pos, b.pos - b.vel * 0.05, 4, 0, 1, SMOKE)
            render.SetMaterial(GLOW)
            render.DrawSprite(b.pos, 12, 12, HOT)
        end
    end

    Rhylib.Net.Receive("wep.cluster", function()
        local pos = net.ReadVector()
        local g = net.ReadUInt(12)
        local fuse = net.ReadUInt(8) / 10
        local n = net.ReadUInt(6)
        local now = CurTime()
        for _ = 1, n do
            if #list >= 128 then break end
            list[#list + 1] = { pos = Vector(pos), vel = net.ReadVector(), g = g, fuseAt = now + fuse }
        end
        if #list > 0 then
            Rhylib.Hook.Add("Think", "weapons.cluster", moveBomblets)
            Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weapons.cluster", drawBomblets)
        end
    end)
end

if CLIENT then
    -- The laser dot of every guided rocket (everyone sees it).
    local DOT = Material("sprites/light_glow02_add")
    local RED = Color(255, 40, 30)
    Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weapons.topattack.laser", function(depth, sky)
        if depth or sky then return end
        for _, m in ipairs(ents.FindByClass("rhylib_topattack")) do
            if IsValid(m) and m.LaserSpot then
                local spot = m:LaserSpot()
                if spot then
                    local pulse = 10 + 3 * math.sin(RealTime() * 12)
                    render.SetMaterial(DOT)
                    render.DrawSprite(spot, pulse, pulse, RED)
                    render.DrawSprite(spot, 4, 4, color_white)
                end
            end
        end
    end)
end
