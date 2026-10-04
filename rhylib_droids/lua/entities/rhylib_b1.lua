--[[
    B1 battle droid: a NextBot with an E-5. See rhylib/droids/sh_00_config.lua.
    Also the base of the other droids (ENT.DroidKind picks a row of D.KINDS:
    rhylib_b2, rhylib_b2_cannon, rhylib_b1_<variant>, rhylib_b1_training,
    rhylib_b2_training).

    Behaviour (one coroutine): look for a target a few times a second;
    with one, turn to it, wait the reaction time, then fire short bursts
    with pauses, advancing now and then if far. B1s may throw a grenade
    where a target just ducked out of sight; B2 cannons lob a wrist rocket
    high over cover now and then. B2s fire from both arms in turn. Near a
    commander (not itself) a droid aims better, reacts faster and pauses
    less (D.Boosted). When it loses sight it goes to where it last
    saw the target, then wanders near home.
]]

AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "B1 battle droid"
ENT.Category = "Rhylib Droids"
ENT.Spawnable = false   -- spawned from the NPCs tab (list "NPC") or the toolgun
ENT.AdminOnly = true
ENT.IsRhylibDroid = true
ENT.DroidKind = "b1"

-- Animations: the first activity the model has, from player-model sets
-- (ACT_HL2MP_*) to NPC sets. Worked out once per model (anims[model]).
local CHOICES = {
    idle = { ACT_HL2MP_IDLE_AR2, ACT_HL2MP_IDLE_SMG1, ACT_IDLE_ANGRY_SMG1, ACT_IDLE_SMG1, ACT_IDLE_RIFLE, ACT_IDLE_ANGRY, ACT_IDLE },
    walk = { ACT_HL2MP_WALK_AR2, ACT_HL2MP_WALK_SMG1, ACT_WALK_AIM_RIFLE, ACT_WALK_RIFLE, ACT_WALK },
    run = { ACT_HL2MP_RUN_AR2, ACT_HL2MP_RUN_SMG1, ACT_RUN_AIM_RIFLE, ACT_RUN_RIFLE, ACT_RUN },
    shoot = { ACT_HL2MP_GESTURE_RANGE_ATTACK_AR2, ACT_HL2MP_GESTURE_RANGE_ATTACK_SMG1, ACT_GESTURE_RANGE_ATTACK_SMG1, ACT_GESTURE_RANGE_ATTACK_AR2 },
    throw = { ACT_HL2MP_GESTURE_RANGE_ATTACK_GRENADE, ACT_GESTURE_RANGE_ATTACK_THROW },
}
local anims = {}

local function resolveAnims(ent)
    local mdl = ent:GetModel() or ""
    local a = anims[mdl]
    if a then return a end
    a = {}
    for key, list in pairs(CHOICES) do
        for _, act in ipairs(list) do
            if act and ent:SelectWeightedSequence(act) > 0 then a[key] = act break end
        end
    end
    -- Nothing usable for walking/running: reuse what there is.
    a.idle = a.idle or ACT_IDLE
    a.walk = a.walk or a.run or a.idle
    a.run = a.run or a.walk
    anims[mdl] = a
    if SERVER then
        Rhylib.Print("droids", "%s: %d sequences; idle=%s walk=%s run=%s shoot=%s", mdl, ent:GetSequenceCount(),
            tostring(ent:GetSequenceActivityName(ent:SelectWeightedSequence(a.idle))),
            tostring(ent:GetSequenceActivityName(ent:SelectWeightedSequence(a.walk))),
            tostring(ent:GetSequenceActivityName(ent:SelectWeightedSequence(a.run))),
            a.shoot and "yes" or "none")
        if ent:SelectWeightedSequence(a.idle) <= 0 then
            Rhylib.Warn("droids", "%s has no usable animations (is it a ragdoll-only model?)", mdl)
        end
    end
    return a
end

local EYE = Vector(0, 0, 62)
local ADVANCE_DIST = 1400     -- further than this: move closer between bursts

function ENT:Kind()
    return Rhylib.Droids.KINDS[self.DroidKind] or Rhylib.Droids.KINDS.b1
end

function ENT:Initialize()
    local D = Rhylib.Droids
    local k = self:Kind()
    -- (a model that isn't installed: the B1's)
    self:SetModel(util.IsValidModel(k.model) and k.model or D.B1_MODEL)
    self.Training = k.training
    if CLIENT then return end

    -- Over the cap: don't add another.
    if D.Count() >= D.Cfg("maxActive") then
        timer.Simple(0, function() if IsValid(self) then self:Remove() end end)
        return
    end
    D.active[self] = true
    if k.commander then D.commanders[self] = true end

    self:SetHealth(D.Cfg(k.health))
    self:SetMaxHealth(D.Cfg(k.health))
    self:SetCollisionBounds(k.big and Vector(-16, -16, 0) or Vector(-13, -13, 0), k.big and Vector(16, 16, 84) or Vector(13, 13, 72))
    self.loco:SetDesiredSpeed(D.Cfg(k.speed))
    self.loco:SetAcceleration(500)
    self.loco:SetDeceleration(800)
    self.loco:SetStepHeight(18)
    self.loco:SetJumpHeight(40)
    self.home = self:GetPos()
    self.nextLook = 0
    self.nextNade = CurTime() + math.Rand(3, 8)
    self.nextRocket = CurTime() + math.Rand(2, 5)
    self.anims = resolveAnims(self)
    self:StartActivity(self.anims.idle)
end

if SERVER then
    local D = Rhylib.Droids

    function ENT:OnRemove()
        D.active[self] = nil
        D.commanders[self] = nil
    end

    --------------------------------------------------------------------------
    -- Seeing
    --------------------------------------------------------------------------

    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    function ENT:Eye()
        return self:GetPos() + (self:Kind().big and Vector(0, 0, 74) or EYE)
    end

    function ENT:CanSee(t)
        trData.start = self:Eye()
        trData.endpos = t:EyePos()
        trData.filter = self
        util.TraceLine(trData)
        return not tr.Hit or tr.Entity == t
    end

    -- Closest visible target in range, checked at most every 0.3 s.
    function ENT:Look()
        local now = CurTime()
        if now < self.nextLook then return self.target end
        self.nextLook = now + 0.3 + math.Rand(0, 0.1)   -- spread droids over ticks
        local k = self:Kind()
        local range = D.Cfg(k.range)
        local pos = self:GetPos()
        local best, bestD
        for _, p in ipairs(D.Targets()) do
            local d = p:GetPos():DistToSqr(pos)
            if d < range * range and (not bestD or d < bestD) and self:CanSee(p) then
                best, bestD = p, d
            end
        end
        if best then
            if self.target ~= best then
                local react = D.Cfg(k.reaction) * math.Rand(0.8, 1.3)
                if D.Boosted(self) then react = react * D.Cfg("cmdReaction") end
                self.reactUntil = now + react
            end
            self.target = best
            self.lastSeen = best:GetPos()
            self.lastSeenAt = now
        elseif IsValid(self.target) and not self.target:Alive() then
            self.target = nil
        end
        return best
    end

    -- Shot at by a player it hadn't seen: turn toward them.
    function ENT:OnInjured(dmg)
        local att = dmg:GetAttacker()
        if IsValid(att) and att:IsPlayer() and not IsValid(self.target) then
            self.lastSeen = att:GetPos()
            self.lastSeenAt = CurTime()
            self.nextLook = 0
        end
    end

    function ENT:OnKilled(dmg)
        -- Training droids give nothing (kill feed, skills, credits).
        if not self.Training then hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor()) end
        -- A commander down: the droids it led are rattled for a while.
        if self:Kind().commander then
            D.commanders[self] = nil
            D.Rattle(self)
        end
        local ed = EffectData()
        ed:SetOrigin(self:WorldSpaceCenter())
        ed:SetMagnitude(self:Kind().big and 4 or 2)
        ed:SetScale(1)
        ed:SetRadius(4)
        util.Effect("Sparks", ed)
        self:EmitSound("npc/turret_floor/die.wav", 75, self:Kind().big and math.random(75, 85) or math.random(95, 110))
        self:BecomeRagdoll(dmg)   -- a client-side ragdoll (ai_serverragdolls 0)
    end

    --------------------------------------------------------------------------
    -- Shooting
    --------------------------------------------------------------------------

    -- (dual: both arms in turn)
    function ENT:Muzzle()
        local hand = "ValveBiped.Bip01_R_Hand"
        if self:Kind().dual then
            self.leftArm = not self.leftArm
            if self.leftArm then hand = "ValveBiped.Bip01_L_Hand" end
        end
        local b = self:LookupBone(hand)
        local pos = b and self:GetBonePosition(b)
        if not pos then return self:Eye() end
        return pos + self:GetForward() * (self:Kind().gun and 18 or 10) + Vector(0, 0, 2)
    end

    function ENT:FireAt(t)
        local Bolts = Rhylib.Weapons and Rhylib.Weapons.Bolts
        if not Bolts then return end
        local k = self:Kind()
        local origin = self:Muzzle()
        local aim = t:WorldSpaceCenter() + Vector(0, 0, 8)   -- chest
        local dir = aim - origin
        dir:Normalize()
        -- Inaccuracy: base cone, worse against moving targets.
        local mult = D.SuppressMult(self)
        if D.Boosted(self) then mult = mult * D.Cfg("cmdSpread") end
        local cone = math.rad((D.Cfg(k.spread) + t:GetVelocity():Length2D() * D.Cfg("moveSpread")) * mult)
        local a = math.Rand(0, math.pi * 2)
        local r = math.tan(cone * math.sqrt(math.Rand(0, 1)))
        local ang = dir:Angle()
        dir = dir + ang:Right() * math.cos(a) * r + ang:Up() * math.sin(a) * r
        dir:Normalize()
        local gun = D.Gun(self.DroidKind)
        Bolts.Fire(self, gun, origin, dir, gun.Damage)
        self:EmitSound(D.E5_SOUND, 80, k.big and math.random(90, 98) or math.random(108, 118), 0.8, CHAN_WEAPON)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
    end

    -- Launch velocity to land at `to` after `t` seconds (gravity g).
    local function lob(from, to, t, g)
        local v = (to - from) / t
        v.z = v.z + 0.5 * g * t
        return v
    end

    -- B1: a grenade at where the target was (they just went into cover).
    function ENT:ThrowNade(pos)
        local from = self:GetPos() + Vector(0, 0, 60) + self:GetForward() * 12
        local dist = from:Distance(pos)
        local g = math.abs(physenv.GetGravity().z)
        local t = math.Clamp(dist / 450, 0.7, 1.6)
        local n = ents.Create("rhylib_grenade")
        if not IsValid(n) then return end
        n:SetPos(from)
        n.kind = "fuse"
        n.fuse = 2.4
        n.thrower = self
        n.training = self.Training
        n.Damage = D.Cfg("b1NadeDamage")
        n.Radius = D.Cfg("b1NadeRadius")
        n:SetOwner(self)
        n:SetColor(self.Training and Color(255, 170, 60) or Color(255, 90, 80))
        n:Spawn()
        local phys = n:GetPhysicsObject()
        if IsValid(phys) then
            local miss = VectorRand() * dist * 0.06
            miss.z = 0
            phys:SetVelocity(lob(from, pos + miss, t, g) * 1.05)   -- (a little extra for air drag)
            phys:AddAngleVelocity(VectorRand() * 400)
        end
        self:EmitSound("weapons/slam/throw.wav", 70, 90)
        if self.anims.throw then self:RestartGesture(self.anims.throw, true, true) end
        self.nextNade = CurTime() + D.Cfg("b1NadeCooldown") * math.Rand(0.8, 1.3)
    end

    -- A grenade at a target it can see, by chance (after a burst).
    function ENT:NadeAt(t)
        local k = self:Kind()
        if not k.nades or CurTime() < self.nextNade then return false end
        local pos = t:GetPos()
        local d = pos:Distance(self:GetPos())
        if d < D.Cfg("b1NadeMin") or d > D.Cfg("b1NadeMax") then return false end
        local chance = D.Cfg("b1NadeFightChance")
        for _, p in ipairs(D.Targets()) do
            if p ~= t and p:GetPos():DistToSqr(pos) < 250 * 250 then
                chance = chance * 2
                break
            end
        end
        if math.random() >= chance then return false end
        self:Face(pos, 0.25)
        if not IsValid(t) then return false end
        self:ThrowNade(t:GetPos() + t:GetVelocity() * 0.4)
        return true
    end

    -- B2 cannon: a wrist rocket lobbed high, landing near pos.
    function ENT:FireRocket(pos, mover)
        local from = self:GetPos() + Vector(0, 0, 80) + self:GetForward() * 10
        local dist = from:Distance(pos)
        local g = math.abs(physenv.GetGravity().z)
        -- Lead a moving target a little; miss more at range.
        if IsValid(mover) then pos = pos + mover:GetVelocity() * 0.4 end
        local miss = VectorRand() * D.Cfg("b2RocketSpread") * dist / 1000
        miss.z = 0
        pos = pos + miss
        -- High arc (apex = g t^2 / 8), flatter under a low ceiling.
        local t = math.Clamp(dist / 650, 1.2, 3.0)
        local apex = g * t * t / 8
        local up = util.TraceLine({ start = from, endpos = from + Vector(0, 0, apex + 40), mask = MASK_SOLID_BRUSHONLY })
        if up.Hit then t = math.Clamp(math.sqrt(math.max(up.HitPos.z - from.z - 40, 0) * 8 / g), 0.4, t) end
        local r = ents.Create("rhylib_b2_rocket")
        if not IsValid(r) then return end
        r:SetPos(from)
        r.vel = lob(from, pos, t, g)
        r.owner = self
        r.training = self.Training
        r:SetOwner(self)
        r:Spawn()
        self:EmitSound("weapons/stinger_fire1.wav", 80, 115)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
        self.nextRocket = CurTime() + D.Cfg("b2RocketCooldown") * math.Rand(0.8, 1.3)
    end

    -- Something to throw at a target out of sight (where it was last seen).
    function ENT:LobAtLastSeen()
        local k = self:Kind()
        local pos = self.lastSeen
        if not pos or CurTime() - (self.lastSeenAt or 0) > 4 then return end
        local d = pos:Distance(self:GetPos())
        local now = CurTime()
        if k.nades and now >= self.nextNade and d > 250 and d < D.Cfg("b1NadeMax") then
            if math.random() < D.Cfg("b1NadeChance") then
                self:Face(pos, 0.3)
                self:ThrowNade(pos)
            else
                self.nextNade = now + 5
            end
        elseif k.rockets and now >= self.nextRocket and d > D.Cfg("b2RocketMin") and d < D.Cfg("b2RocketMax") then
            self:Face(pos, 0.3)
            self:FireRocket(pos)
        end
    end

    --------------------------------------------------------------------------
    -- Moving
    --------------------------------------------------------------------------

    -- Walk a path for up to maxTime; stop early when a target shows up (watch).
    function ENT:Go(pos, maxTime, watch)
        local path = Path("Follow")
        path:SetMinLookAheadDistance(300)
        path:SetGoalTolerance(40)
        if not path:Compute(self, pos) then return false end
        local stop = CurTime() + maxTime
        while path:IsValid() and CurTime() < stop do
            path:Update(self)
            if self.loco:IsStuck() then
                self:HandleStuck()
                return false
            end
            if watch and self:Look() then return true end
            coroutine.yield()
        end
        return true
    end

    -- Turn to face a point for up to t seconds.
    function ENT:Face(pos, t)
        local stop = CurTime() + t
        while CurTime() < stop do
            self.loco:FaceTowards(pos)
            coroutine.yield()
        end
    end

    local function valid(t)
        return IsValid(t) and t:Alive() and not t.rhylibDown and not t:GetNW2Bool("rhylib_simOut", false)
            and t:GetNW2Float("rhylib_knockEnd", 0) == 0
    end

    function ENT:Engage()
        local k = self:Kind()
        local t = self.target
        local bursts = 0
        while valid(t) do
            self:Look()
            if self.target ~= t then
                t = self.target
                if not IsValid(t) then break end
            end
            if CurTime() - (self.lastSeenAt or 0) > 1.5 then   -- lost sight
                self:LobAtLastSeen()
                break
            end

            self:Face(t:GetPos(), 0.15)
            if CurTime() >= (self.reactUntil or 0) then
                local d = t:GetPos():Distance(self:GetPos())
                -- B2 cannon: now and then a rocket instead of a burst.
                if k.rockets and CurTime() >= self.nextRocket and d > D.Cfg("b2RocketMin") and d < D.Cfg("b2RocketMax") and math.random() < 0.5 then
                    self:FireRocket(t:GetPos(), t)
                    self:Face(t:GetPos(), 0.6)
                else
                    -- A burst.
                    local wait = 60 / math.max(D.Cfg(k.rpm), 1)
                    for _ = 1, math.random(k.burst[1], k.burst[2]) do
                        if not valid(t) or not self:CanSee(t) then break end
                        self.loco:FaceTowards(t:GetPos())
                        self:FireAt(t)
                        self:Face(t:GetPos(), wait)
                    end
                end
                bursts = bursts + 1
                -- B1: now and then a grenade at a target in the open
                -- (more likely at a group).
                if IsValid(t) then self:NadeAt(t) end
                local pause = math.Rand(0.6, 1.3)
                if D.Boosted(self) then pause = pause * D.Cfg("cmdPause") end
                self:Face(IsValid(t) and t:GetPos() or self:GetPos(), pause)
                -- Far away: walk a bit closer every few bursts.
                if IsValid(t) and bursts % 3 == 0 and t:GetPos():DistToSqr(self:GetPos()) > ADVANCE_DIST * ADVANCE_DIST then
                    local toward = self:GetPos() + (t:GetPos() - self:GetPos()):GetNormalized() * 400
                    self:Go(toward, 1.5, false)
                end
            end
        end
        self.target = nil
    end

    function ENT:RunBehaviour()
        while true do
            if self:Look() then
                self:Engage()
            elseif self.lastSeen and CurTime() - (self.lastSeenAt or 0) < 20 then
                -- Go where the target was last seen (or where the shot came from).
                local pos = self.lastSeen
                self.lastSeen = nil
                self:Go(pos, 8, true)
            elseif math.random() < 0.35 then
                -- Wander near home.
                local pos = self.home + Vector(math.Rand(-350, 350), math.Rand(-350, 350), 0)
                self:Go(pos, 5, true)
                if not self.target then coroutine.wait(math.Rand(2, 4)) end
            else
                coroutine.wait(math.Rand(1, 2))
            end
            coroutine.yield()
        end
    end

    --------------------------------------------------------------------------
    -- Animation
    --------------------------------------------------------------------------

    function ENT:BodyUpdate()
        local speed = self.loco:GetVelocity():Length2D()
        local A = self.anims
        if not A then return end   -- removed at once (over the cap)
        local want = speed > 10 and (speed > 110 and A.run or A.walk) or A.idle
        if self:GetActivity() ~= want then self:StartActivity(want) end

        -- Aim the gun at the target.
        local t = self.target
        if IsValid(t) then
            local ang = (t:WorldSpaceCenter() - self:Eye()):Angle()
            self:SetPoseParameter("aim_yaw", math.Clamp(math.NormalizeAngle(ang.y - self:GetAngles().y), -60, 60))
            self:SetPoseParameter("aim_pitch", math.Clamp(math.NormalizeAngle(ang.p), -50, 50))
        else
            self:SetPoseParameter("aim_yaw", 0)
            self:SetPoseParameter("aim_pitch", 0)
        end

        if speed > 10 then self:BodyMoveXY() else self:FrameAdvance() end
    end
end

if CLIENT then
    -- One shared gun model per kind, moved to each droid's hand when drawn.
    local guns = {}
    local handBone = {}
    local POS, ANG = Vector(5, 1, -3), Angle(-10, 0, 180)   -- like the clone guns

    local function place(pos, ang)
        local p = pos + ang:Forward() * POS.x + ang:Right() * POS.y + ang:Up() * POS.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), ANG.y)
        a:RotateAroundAxis(a:Right(), ANG.p)
        a:RotateAroundAxis(a:Forward(), ANG.r)
        return p, a
    end

    function ENT:Draw()
        self:DrawModel()
        local mdlName = self:Kind().gun
        if not mdlName then return end   -- (B2: wrist blasters are part of the model)
        local gun = guns[mdlName]
        if not IsValid(gun) then
            gun = ClientsideModel(mdlName, RENDERGROUP_OPAQUE)
            if not IsValid(gun) then return end
            gun:SetNoDraw(true)
            guns[mdlName] = gun
        end
        local mdl = self:GetModel()
        local b = handBone[mdl]
        if b == nil then
            b = self:LookupBone("ValveBiped.Bip01_R_Hand") or false
            handBone[mdl] = b
        end
        local m = b and self:GetBoneMatrix(b)
        if not m then return end
        local p, a = place(m:GetTranslation(), m:GetAngles())
        gun:SetPos(p)
        gun:SetAngles(a)
        gun:SetupBones()
        gun:DrawModel()
    end
end
