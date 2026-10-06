--[[
    B1 battle droid: a NextBot with an E-5. See rhylib/droids/sh_00_config.lua.
    Also the base of the other droids (ENT.DroidKind picks a row of D.KINDS:
    rhylib_b2, rhylib_b2_cannon, rhylib_b1_<variant>, rhylib_b1_training,
    rhylib_b2_training).

    Cover (B1 kinds, `cover`): hit coverHits times within coverWindow, or
    suppressed (Z-6 skill, flash charge), it runs to a navmesh hiding spot
    the shooter can't see (D.coverTaken: one droid per spot), blind fires
    toward where it last saw them for coverTime, then fights again (not
    again for coverCooldown). Below retreatFrac health it pulls back once
    to a spot further from the shooter. Route and cover searches share
    D.TakeBudget (pathPerTick per tick).

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
ENT.Category = "Rhylib: B1 battle droids"
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
    crouch = { ACT_HL2MP_IDLE_CROUCH_AR2, ACT_HL2MP_IDLE_CROUCH_SMG1, ACT_COVER_LOW, ACT_CROUCHIDLE, ACT_RANGE_AIM_SMG1_LOW },
    -- weapon on safety (clones roaming with nothing in sight; none = the normal set)
    idleSafe = { ACT_HL2MP_IDLE_PASSIVE, ACT_IDLE_RELAXED },
    walkSafe = { ACT_HL2MP_WALK_PASSIVE, ACT_WALK_RELAXED },
    runSafe = { ACT_HL2MP_RUN_PASSIVE, ACT_RUN_RELAXED },
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
    -- (a model that isn't installed: the B1's; clones never get a droid model)
    local mdl = D.KindModel(k)
    self:SetModel(util.IsValidModel(mdl or "") and mdl or (self.IsRhylibClone and D.CLONE_FALLBACK or D.B1_MODEL))
    self.Training = k.training
    -- Clones: players walk through them (owner: a medic on the body blocked
    -- the way out). Both realms, see sh_00_config ShouldCollide.
    if self.IsRhylibClone then self:SetCustomCollisionCheck(true) end
    if CLIENT then return end

    -- Over the cap: don't add another (clones have their own cap).
    if self.IsRhylibClone and D.CloneCount() >= D.Cfg("cloneMax") or not self.IsRhylibClone and D.Count() >= D.Cfg("maxActive") then
        self.overCap = true
        timer.Simple(0, function() if IsValid(self) then self:Remove() end end)
        return
    end
    if self.IsRhylibClone then
        D.clones[self] = true
        -- (sight ignores players and clones: friendly bolts fly through them)
        self.seeFilter = function(e) return e ~= self and not e:IsPlayer() and not e.IsRhylibClone end
        -- (line of fire: players DO count, so it never fires past one)
        self.fireFilter = function(e) return e ~= self and not e.IsRhylibClone end
    else
        D.active[self] = true
    end
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
    -- (guard where spawned until a GM says otherwise: sv_20_orders)
    self.mode = "guard"
    self:SetNW2String("rhylib_dmode", "guard")
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
        if D.clones then D.clones[self] = nil end
        D.commanders[self] = nil
        self:LeaveCover()
    end

    --------------------------------------------------------------------------
    -- Seeing
    --------------------------------------------------------------------------

    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    -- Targets are players (droids) or NPCs (both sides).
    local function alive(t)
        if t:IsPlayer() then return t:Alive() end
        return t:Health() > 0
    end
    local function seePoint(t)
        if t:IsPlayer() then return t:EyePos() end
        return t:WorldSpaceCenter() + Vector(0, 0, 12)
    end

    local EYE_CROUCH = Vector(0, 0, 40)
    -- Clones crouched in place (no cover to reach): lower and steadier.
    function ENT:Crouched()
        return (self.crouching or (self.crouchUntil or 0) > CurTime()) and self.loco:GetVelocity():Length2DSqr() < 400
    end

    function ENT:Eye()
        if self.IsRhylibClone and self:Crouched() then return self:GetPos() + EYE_CROUCH end
        return self:GetPos() + (self:Kind().big and Vector(0, 0, 74) or EYE)
    end

    function ENT:CanSee(t)
        trData.start = self:Eye()
        trData.endpos = seePoint(t)
        trData.filter = self.seeFilter or self
        util.TraceLine(trData)
        return not tr.Hit or tr.Entity == t
    end

    -- Clones: a friendly player in the line of fire (owner: reinforcements
    -- shot him in the back). A thin box along the shot; the world or the
    -- target first = clear.
    local lofTr = {}
    local lofData = { mask = MASK_SHOT, output = lofTr, mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8) }
    function ENT:FriendInLine(t)
        if not self.IsRhylibClone then return false end
        lofData.start = self:Eye()
        lofData.endpos = t:WorldSpaceCenter()
        lofData.filter = self.fireFilter
        util.TraceHull(lofData)
        local e = lofTr.Entity
        if not IsValid(e) then return false end
        if e:IsPlayer() then return true end
        local L = Rhylib.Lying
        return L and L.Owner and IsValid(L.Owner(e)) or false
    end

    -- Who this NPC fights: clones fight droids; droids fight players and
    -- clones; training droids only players (sim health).
    function ENT:TargetList()
        if self.IsRhylibClone then return D.CloneTargets() end
        if self.Training then return D.Targets() end
        return D.DroidTargets()
    end

    -- Is e on the other side (for being shot at)?
    function ENT:IsFoe(e)
        if not IsValid(e) then return false end
        if self.IsRhylibClone then return e.IsRhylibDroid == true end
        return e:IsPlayer() or e.IsRhylibClone == true
    end

    -- Aggression 1-5: droids follow the GMs' live level, clones their config.
    function ENT:Aggro()
        if self.IsRhylibClone then
            if self.orderAggro then return self.orderAggro end   -- (their commander's aggression, command wheel)
            if self.doctrine then return self.doctrine end   -- (the odds decide: fall back / hold / charge)
            return math.Clamp(math.Round(tonumber(D.Cfg("cloneAggro")) or 3), 1, 5)
        end
        return D.Aggro()
    end

    local MAX_TRACES = 4
    local SWITCH = 0.49     -- (0.7 squared) a new target must be 30% closer
    local REMEMBER = 1      -- seen this recently: no new reaction delay (owner: re-peeking was punished at once)
    local cand, candD = {}, {}   -- scratch lists (Look never yields)

    -- A visible target in range: keeps the current one while it's in sight
    -- unless another is much closer, else the nearest visible (nearest
    -- first, at most 4 traces, plus one rotating farther one). Every 0.3 s,
    -- 0.5 s while engaged.
    function ENT:Look()
        local now = CurTime()
        if now < self.nextLook then return self.target end
        local k = self:Kind()
        local range = self.artillery and D.Cfg("artyRange") or D.Cfg(k.range)
        local pos = self:GetPos()
        local cur = self.target
        -- Targets in range, sorted nearest first (insertion sort, few).
        local n, curD = 0, nil
        for _, p in ipairs(self:TargetList()) do
            local d = IsValid(p) and p:GetPos():DistToSqr(pos) or math.huge   -- (cached lists can hold removed NPCs)
            if d < range * range then
                if p == cur then curD = d end
                local i = n
                while i > 0 and candD[i] > d do
                    cand[i + 1], candD[i + 1] = cand[i], candD[i]
                    i = i - 1
                end
                cand[i + 1], candD[i + 1] = p, d
                n = n + 1
            end
        end
        local best, traces = nil, 0
        local limit = math.huge
        if curD then
            traces = 1
            if self:CanSee(cur) then
                best = cur
                limit = curD * SWITCH
            end
        end
        local i = 1
        while i <= n and traces < MAX_TRACES and candD[i] < limit do
            local p = cand[i]
            if p ~= cur then
                traces = traces + 1
                if self:CanSee(p) then best = p break end
            end
            i = i + 1
        end
        -- Nothing seen and some left untraced: one more trace, rotating
        -- over the farther ones (a player in the open behind hidden ones).
        if not best and i <= n then
            local rot = (self.lookRot or 0) % (n - i + 1)
            self.lookRot = rot + 1
            local p = cand[i + rot]
            if p ~= cur and self:CanSee(p) then best = p end
        end
        for i = 1, n do cand[i] = nil end
        self.nextLook = now + (best and best == cur and 0.5 or 0.3) + math.Rand(0, 0.1)   -- spread droids over ticks
        if best then
            -- Reaction delay only for a target not seen in the last 2 s.
            local seen = self.seenAt
            if not seen then seen = {} self.seenAt = seen end
            -- (sight just started: aim settles in from here, see FireAt)
            if self.target ~= best or now - (seen[best] or -100) > 0.8 then self.sightStart = now end
            if self.target ~= best and now - (seen[best] or -100) > REMEMBER then
                local react = D.Cfg(k.reaction) * math.Rand(0.8, 1.3)
                if D.Boosted(self) then react = react * D.Cfg("cmdReaction") end
                self.reactUntil = now + react
            end
            if not seen[best] then
                for p, at in pairs(seen) do
                    if not IsValid(p) or now - at > REMEMBER then seen[p] = nil end
                end
            end
            seen[best] = now
            -- Clones: fresh contact, call nearby clones over (sv_30_clones).
            if self.IsRhylibClone and not IsValid(cur) and D.CloneCall then D.CloneCall(self, best) end
            self.target = best
            self.lastSeen = best:GetPos()
            self.lastSeenAt = now
        elseif IsValid(self.target) and not alive(self.target) then
            self.target = nil
        end
        return best
    end

    -- Shot at by a player it hadn't seen: turn toward them. Hits are
    -- counted for taking cover, and a bad one may make it pull back.
    function ENT:OnInjured(dmg)
        self.woken = true   -- ends an idle wait early
        local att = dmg:GetAttacker()
        local foe = self:IsFoe(att)
        -- Clones that don't take cover (heavies): crouch where they stand.
        if foe and self.IsRhylibClone and not self:Kind().cover then self.crouchUntil = CurTime() + D.Cfg("ctCrouchTime") end
        if foe then
            self.threatPos, self.threatAt = att:GetPos(), CurTime()
            local hits = self.hits
            if not hits then hits = {} self.hits = hits end
            -- (old hits out first, so a full list never drops new ones)
            local now, win = CurTime(), D.Cfg("coverWindow")
            while hits[1] and now - hits[1] > win do table.remove(hits, 1) end
            if #hits < 8 then hits[#hits + 1] = now end
            local frac = D.Cfg("retreatFrac")
            if frac > 0 and not self.retreated and self:Health() - dmg:GetDamage() < self:GetMaxHealth() * frac then
                self.retreatPending = true
            end
        end
        if foe and not IsValid(self.target) then
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
        if self.IsRhylibClone then
            self:EmitSound("npc/combine_soldier/die" .. math.random(1, 3) .. ".wav", 75, math.random(98, 106))
        else
            local ed = EffectData()
            ed:SetOrigin(self:WorldSpaceCenter())
            ed:SetMagnitude(self:Kind().big and 4 or 2)
            ed:SetScale(1)
            ed:SetRadius(4)
            util.Effect("Sparks", ed)
            self:EmitSound("npc/turret_floor/die.wav", 75, self:Kind().big and math.random(75, 85) or math.random(95, 110))
        end
        self:BecomeRagdoll(dmg)   -- a client-side ragdoll (ai_serverragdolls 0)
    end

    --------------------------------------------------------------------------
    -- Shooting
    --------------------------------------------------------------------------

    -- Hand bone ids per model: { right, left } (false = none).
    local hands = {}

    -- (dual: both arms in turn)
    function ENT:Muzzle()
        local mdl = self:GetModel() or ""
        local h = hands[mdl]
        if not h then
            h = { self:LookupBone("ValveBiped.Bip01_R_Hand") or false, self:LookupBone("ValveBiped.Bip01_L_Hand") or false }
            hands[mdl] = h
        end
        local b = h[1]
        if self:Kind().dual then
            self.leftArm = not self.leftArm
            if self.leftArm then b = h[2] end
        end
        local pos = b and self:GetBonePosition(b)
        if not pos then return self:Eye() end
        return pos + self:GetForward() * (self:Kind().gun and 18 or 10) + Vector(0, 0, 2)
    end

    -- How many droids have shot at each player in the last 1.5 s.
    D.focus = D.focus or setmetatable({}, { __mode = "k" })

    -- Aimed fire at a target. Two softeners (owner: peeking a corner got
    -- you killed before 4 shots): the aim settles in over settleTime after
    -- first sight (cone x settleMult at first), and when more than
    -- crowdFree droids fire at one player each extra one widens the cone.
    function ENT:FireAt(t)
        local now = CurTime()
        local settle = math.Clamp((now - (self.sightStart or 0)) / math.max(D.Cfg("settleTime"), 0.01), 0, 1)
        local extra = Lerp(settle, D.Cfg("settleMult"), 1)
        local f = D.focus[t]
        if not f then f = setmetatable({}, { __mode = "k" }) D.focus[t] = f end
        f[self] = now
        local n = 0
        for d, at in pairs(f) do
            if now - at < 1.5 and IsValid(d) then n = n + 1 else f[d] = nil end
        end
        extra = extra * math.min(1 + D.Cfg("crowdMult") * math.max(0, n - D.Cfg("crowdFree")), D.Cfg("crowdMax"))
        self:FireAtPos(t:WorldSpaceCenter() + Vector(0, 0, 8), t:GetVelocity():Length2D(), extra)   -- chest
    end

    -- A shot at a point; speed = how fast the target moves (worse aim),
    -- extra = cone multiplier (blind fire from cover).
    function ENT:FireAtPos(aim, speed, extra)
        local Bolts = Rhylib.Weapons and Rhylib.Weapons.Bolts
        if not Bolts then return end
        local k = self:Kind()
        local origin = self:Muzzle()
        local dir = aim - origin
        dir:Normalize()
        -- Inaccuracy: base cone, worse against moving targets.
        local mult = D.SuppressMult(self) * (extra or 1)
        if self.IsRhylibClone and self:Crouched() then mult = mult * D.Cfg("ctCrouchSpread") end
        -- (firing on the move is a little less accurate)
        if self.loco:GetVelocity():Length2DSqr() > 400 then mult = mult * D.Cfg(self.running and "runSpread" or "walkSpread") end
        if D.Boosted(self) then mult = mult * D.Cfg("cmdSpread") end
        local cone = math.rad((D.Cfg(k.spread) + (speed or 0) * D.Cfg("moveSpread")) * mult)
        local a = math.Rand(0, math.pi * 2)
        local r = math.tan(cone * math.sqrt(math.Rand(0, 1)))
        local ang = dir:Angle()
        dir = dir + ang:Right() * math.cos(a) * r + ang:Up() * math.sin(a) * r
        dir:Normalize()
        local gun = D.Gun(self.DroidKind)
        Bolts.Fire(self, gun, origin, dir, gun.Damage)
        self:EmitSound(k.sound or D.E5_SOUND, 80, k.big and math.random(90, 98) or (k.sound and math.random(97, 105)) or math.random(108, 118), 0.8, CHAN_WEAPON)
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
        local popper = self:Kind().poppers
        n:SetPos(from)
        n.thrower = self
        if popper then
            -- Clone trooper: a droid popper (EMP), which never stuns players.
            n.kind = "emp"
            n.fuse = 2
            n.noStun = true
            n:SetColor(Color(130, 180, 255))
        else
            n.kind = "fuse"
            n.fuse = 2.4
            n.training = self.Training
            n.Damage = D.Cfg("b1NadeDamage")
            n.Radius = D.Cfg("b1NadeRadius")
            n:SetColor(self.Training and Color(255, 170, 60) or Color(255, 90, 80))
        end
        n:SetOwner(self)
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
        self.nextNade = CurTime() + D.Cfg(popper and "ctPopperCooldown" or "b1NadeCooldown") * math.Rand(0.8, 1.3)
    end

    -- A grenade at a target it can see, by chance (after a burst).
    function ENT:NadeAt(t)
        local k = self:Kind()
        if not (k.nades or k.poppers) or CurTime() < self.nextNade then return false end
        local pos = t:GetPos()
        local d = pos:Distance(self:GetPos())
        if d < D.Cfg("b1NadeMin") or d > D.Cfg("b1NadeMax") then return false end
        local chance = D.Cfg(k.poppers and "ctPopperChance" or "b1NadeFightChance")
        for _, p in ipairs(self:TargetList()) do
            if p ~= t and IsValid(p) and p:GetPos():DistToSqr(pos) < 250 * 250 then
                chance = chance * 2
                break
            end
        end
        if math.random() >= chance then return false end
        -- Clone troopers: a short charge first, then the popper (owner).
        -- Not while standing over a downed player.
        if k.poppers and not self.guarding then
            self.popRush = { t = t, from = self:GetPos(), untilT = CurTime() + 1.6 }
            self.planAt = 0
            return true
        end
        self:Face(pos, 0.25)
        if not IsValid(t) then return false end
        self:ThrowNade(t:GetPos() + t:GetVelocity() * 0.4)
        return true
    end

    -- B2 rocket droid: a level rocket at the target that dives into the
    -- floor just before it (rhylib_b2_rocket with r.direct).
    function ENT:FireDirectRocket(t)
        local from = self:GetPos() + Vector(0, 0, 80) + self:GetForward() * 10
        local speed = D.Cfg("b2DirectSpeed")
        local pos = t:GetPos()
        -- Lead a moving target by the flight time; miss more at range.
        pos = pos + t:GetVelocity() * math.Clamp(from:Distance(pos) / math.max(speed, 1), 0, 2)
        local miss = VectorRand() * D.Cfg("b2RocketSpread") * from:Distance(pos) / 1000
        miss.z = 0
        pos = pos + miss
        local aim = pos + Vector(0, 0, 80)   -- (player head height: it curves down onto this spot)
        local r = ents.Create("rhylib_b2_rocket")
        if not IsValid(r) then return end
        r:SetPos(from)
        r.direct = true
        r.diveAt = aim
        r.vel = (aim - from):GetNormalized() * speed
        r.owner = self
        r.training = self.Training
        r:SetOwner(self)
        r:Spawn()
        self:EmitSound("weapons/stinger_fire1.wav", 80, 105)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
        self.nextRocket = CurTime() + D.Cfg("b2RocketCooldown") * math.Rand(0.8, 1.3)
    end

    -- B2 mortar: a wrist rocket lobbed high, landing near pos.
    function ENT:FireRocket(pos, mover)
        if self:Kind().direct and IsValid(mover) then return self:FireDirectRocket(mover) end
        local from = self:GetPos() + Vector(0, 0, 80) + self:GetForward() * 10
        local dist = from:Distance(pos)
        local g = math.abs(physenv.GetGravity().z)
        -- Lead a moving target a little; miss more at range.
        local arty = self.artillery
        local t = math.Clamp(dist / 650, 1.2, arty and D.Cfg("artyMaxFlight") or 3.0)
        if IsValid(mover) then pos = pos + mover:GetVelocity() * (arty and math.min(t * 0.5, 1.5) or 0.4) end
        local spread = D.Cfg(arty and "artySpread" or "b2RocketSpread")
        -- Artillery walks its rounds in: shots at the same target tighten.
        if arty then
            if IsValid(mover) and mover == self.artyLast and CurTime() - (self.artyLastAt or 0) < 20 then
                self.artyWalk = math.max(0.35, (self.artyWalk or 1) * 0.75)
            else
                self.artyWalk = 1
            end
            self.artyLast, self.artyLastAt = mover, CurTime()
            spread = spread * self.artyWalk
        end
        local miss = VectorRand() * spread * dist / 1000
        miss.z = 0
        pos = pos + miss
        -- High arc (apex = g t^2 / 8), flatter under a low ceiling.
        local apex = g * t * t / 8
        local up = util.TraceLine({ start = from, endpos = from + Vector(0, 0, apex + 40), mask = MASK_SOLID_BRUSHONLY })
        if up.Hit then
            local low = math.Clamp(math.sqrt(math.max(up.HitPos.z - from.z - 40, 0) * 8 / g), 0.4, t)
            -- (artillery under a roof: no near-flat map-crossing shot)
            if arty and low < t * 0.5 then
                self.nextRocket = CurTime() + 2
                return false
            end
            t = low
        end
        local r = ents.Create("rhylib_b2_rocket")
        if not IsValid(r) then return false end
        r:SetPos(from)
        r.vel = lob(from, pos, t, g)
        r.owner = self
        r.training = self.Training
        r:SetOwner(self)
        r:Spawn()
        self:EmitSound("weapons/stinger_fire1.wav", arty and 95 or 80, 115)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
        self.nextRocket = CurTime() + D.Cfg(arty and "artyCooldown" or "b2RocketCooldown") * math.Rand(0.8, 1.3)
    return true
    end

    -- Artillery (mortar squad, 2026-10-06be): a rocket at an enemy any droid
    -- has in sight within artyRange (spotters), when off cooldown. True if fired.
    function ENT:ArtilleryShot()
        if not self.artillery or CurTime() < (self.nextRocket or 0) then return false end
        local t = D.SpottedTarget and D.SpottedTarget(self, D.Cfg("artyRange"))
        if not IsValid(t) then return false end
        self:Face(t:GetPos(), 0.4)
        if not IsValid(t) then return false end
        return self:FireRocket(t:GetPos(), t) == true
    end

    -- Something to throw at a target out of sight (where it was last seen).
    function ENT:LobAtLastSeen()
        local k = self:Kind()
        local pos = self.lastSeen
        if not pos or CurTime() - (self.lastSeenAt or 0) > 4 then return end
        local d = pos:Distance(self:GetPos())
        local now = CurTime()
        if (k.nades or k.poppers) and now >= self.nextNade and d > 250 and d < D.Cfg("b1NadeMax") then
            if math.random() < D.Cfg(k.poppers and "ctPopperLobChance" or "b1NadeChance") then
                self:Face(pos, 0.3)
                self:ThrowNade(pos)
            else
                self.nextNade = now + 5
            end
        elseif k.rockets and not k.direct and now >= self.nextRocket and d > D.Cfg("b2RocketMin") and d < D.Cfg("b2RocketMax") then   -- (rocket droid: needs sight)
            self:Face(pos, 0.3)
            self:FireRocket(pos)
        end
    end

    --------------------------------------------------------------------------
    -- Moving
    --------------------------------------------------------------------------

    -- Doors (2026-10-06bh, owner: clones didn't open doors): clones open an
    -- unlocked door in front of them while walking (droids don't: doors keep
    -- them out). Checked every 0.3 s, one short hull trace.
    local DOORS = { prop_door_rotating = true, func_door = true, func_door_rotating = true }
    local DOOR_MINS, DOOR_MAXS = Vector(-10, -10, -10), Vector(10, 10, 10)
    function ENT:OpenDoors()
        if not self.IsRhylibClone then return end
        local now = CurTime()
        if now < (self.doorAt or 0) then return end
        self.doorAt = now + 0.3
        local dir = self.loco:GetVelocity()
        dir.z = 0
        if dir:LengthSqr() < 100 then dir = self:GetForward() else dir:Normalize() end
        local from = self:GetPos() + Vector(0, 0, 40)
        local tr = util.TraceHull({ start = from, endpos = from + dir * 70, mins = DOOR_MINS, maxs = DOOR_MAXS, filter = self, mask = MASK_SOLID })
        local e = tr.Entity
        if not (IsValid(e) and DOORS[e:GetClass()]) then return end
        if e:GetInternalVariable("m_bLocked") == true then return end
        if e:GetClass() == "prop_door_rotating" then
            e:Fire("OpenAwayFrom", "!activator", 0, self, self)
        else
            e:Fire("Open", "", 0, self, self)
        end
        self.doorAt = now + 1
    end

    -- Walk a path for up to maxTime; stop early when a target shows up (watch).
    function ENT:Go(pos, maxTime, watch)
        local path = self.path   -- one per droid (Go never nests)
        if not path then
            path = Path("Follow")
            path:SetMinLookAheadDistance(300)
            path:SetGoalTolerance(40)
            self.path = path
        end
        -- (route searches are spread over ticks: D.TakeBudget)
        local giveUp = CurTime() + 1
        while not D.TakeBudget() do
            if CurTime() > giveUp then return false end
            coroutine.yield()
        end
        self.redirect = nil   -- (only a redirect during this walk counts)
        if not path:Compute(self, pos) then return false end
        local stop = CurTime() + maxTime
        while path:IsValid() and CurTime() < stop do
            path:Update(self)
            self:OpenDoors()
            if self.loco:IsStuck() then
                self:HandleStuck()
                return false
            end
            if watch and self:Look() then return true end
            if self.redirect then   -- (sent somewhere else: a downed player to guard)
                self.redirect = nil
                return true
            end
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

    --------------------------------------------------------------------------
    -- Cover (B1s): when hit a few times, suppressed or badly hurt
    --------------------------------------------------------------------------

    local IN_COVER = 1        -- NavArea:GetHidingSpots type
    local MAX_AREAS = 16
    local MAX_CHECKS = 6      -- sight traces per search

    function ENT:LeaveCover()
        if self.coverKey and D.coverTaken[self.coverKey] == self then D.coverTaken[self.coverKey] = nil end
        self.coverKey = nil
    end

    function ENT:WantsCover()
        if not self:Kind().cover or not self.threatPos or CurTime() < (self.coverReady or 0) then return false end
        if self.guarding then return false end   -- (stands over a downed player)
        if CurTime() - (self.threatAt or 0) > 10 then return false end   -- (no recent threat to hide from)
        if self.retreatPending then return true end
        local L = self:Aggro()
        if L >= 5 then return false end   -- (a charge doesn't stop for cover)
        if D.SuppressMult(self) > 1 then return true end
        local hits = self.hits
        if not hits then return false end
        local now, win, n = CurTime(), D.Cfg("coverWindow"), 0
        for i = #hits, 1, -1 do
            if now - hits[i] <= win then n = n + 1 else table.remove(hits, i) end
        end
        return n >= (L <= 2 and 1 or D.Cfg("coverHits"))   -- (retreating droids take cover sooner)
    end

    -- A hiding spot near it that the threat can't see (far: one that's
    -- also further from the threat, for pulling back). Nil without a navmesh.
    function ENT:FindCover(threat, far)
        if not (navmesh and navmesh.Find) then return end
        local pos = self:GetPos()
        local areas = navmesh.Find(pos, D.Cfg("coverRadius"), 120, 120)
        if not areas or #areas == 0 then return end
        local myD = pos:DistToSqr(threat)
        local spots, farArea, farD = {}, nil, math.huge
        for i = 1, math.min(#areas, MAX_AREAS) do
            local a = areas[i]
            for _, v in ipairs(a:GetHidingSpots(IN_COVER) or {}) do
                local td = v:DistToSqr(threat)
                local holder = D.coverTaken[D.SpotKey(v)]
                if td > 62500 and (not far or td > myD + 40000) and not (IsValid(holder) and holder ~= self) then
                    spots[#spots + 1] = { v = v, d = v:DistToSqr(pos) }
                end
            end
            -- (no spot: pulling back still moves away from the threat)
            if far then
                local c = a:GetCenter()
                local d = c:DistToSqr(pos)
                if c:DistToSqr(threat) > myD + 90000 and d < farD then farArea, farD = c, d end
            end
        end
        table.sort(spots, function(x, y) return x.d < y.d end)
        local eye = threat + Vector(0, 0, 60)
        local tr = { mask = MASK_SOLID_BRUSHONLY }
        for i = 1, math.min(#spots, MAX_CHECKS) do
            local v = spots[i].v
            tr.start, tr.endpos = eye, v + Vector(0, 0, 56)
            if util.TraceLine(tr).Hit then return v end
        end
        return far and farArea or nil
    end

    -- Run to cover, blind fire from it for a while, then fight again.
    function ENT:TakeCover(threat, far)
        local k = self:Kind()
        while not D.TakeBudget() do coroutine.yield() end
        local spot = self:FindCover(threat, far)
        if not spot then
            self.coverReady = CurTime() + 3   -- (nothing near: try again later)
            return false
        end
        local key = D.SpotKey(spot)
        D.coverTaken[key] = self
        self.coverKey = key
        self.target = nil   -- (no aiming through the cover; Look picks it up after)
        self.loco:SetDesiredSpeed(D.Cfg(k.speed) * 1.15)
        self.running = true
        local ok = self:Go(spot, far and 6 or 4, false)
        self.loco:SetDesiredSpeed(D.Cfg(k.speed))
        -- Didn't get there (no route, stuck): not in cover after all.
        if not ok and self:GetPos():DistToSqr(spot) > 120 * 120 then
            self:LeaveCover()
            self.coverReady = CurTime() + 2
            return false
        end
        local stop = CurTime() + D.Cfg("coverTime") * math.Rand(0.8, 1.3) * (far and 1.5 or 1)
        local wait = 60 / math.max(D.Cfg(k.rpm), 1)
        while CurTime() < stop and self:Health() > 0 do
            local aim = self.lastSeen
            if aim and CurTime() - (self.lastSeenAt or 0) < 8 and math.random() < 0.6 then
                -- Blind fire toward where the enemy was.
                self:Face(aim, 0.2)
                for _ = 1, math.random(2, 3) do
                    self:FireAtPos(aim + Vector(0, 0, 40), 0, D.Cfg("blindSpread"))
                    self:Face(aim, wait)
                end
            end
            self:Face(aim or (self:GetPos() + self:GetForward() * 100), math.Rand(0.8, 1.4))
        end
        self:LeaveCover()
        self.hits = nil
        self.coverReady = CurTime() + D.Cfg("coverCooldown")
        self.nextLook = 0
        return true
    end

    -- Pull back (once) or duck into cover if it should; true if it did.
    function ENT:CoverCheck()
        if not self:WantsCover() then return false end
        local far = self.retreatPending
        local ok = self:TakeCover(self.threatPos, far)
        -- Clones with no cover to reach crouch where they are (owner).
        if not ok and self.IsRhylibClone then self.crouchUntil = CurTime() + D.Cfg("ctCrouchTime") end
        -- (the one pull-back only counts once it happened)
        if far and ok then
            self.retreatPending = nil
            self.retreated = true
        end
        return ok
    end

    local function valid(t)
        return IsValid(t) and alive(t) and not t.rhylibDown and not t:GetNW2Bool("rhylib_simOut", false)
            and t:GetNW2Float("rhylib_knockEnd", 0) == 0
    end

    --------------------------------------------------------------------------
    -- Orders: mode area, aggression, moving while firing
    --------------------------------------------------------------------------

    -- The area a guard / patrol droid stays in (nil = attack: anywhere).
    function ENT:AreaRadius()
        if self.mode == "patrol" then return D.Cfg("patrolRadius") end
        if self.mode == "attack" or self.mode == "roam" then return nil end
        if self.guarding then return 250 end
        if self.mode == "follow" then return D.Cfg("cloneFollowRadius") end
        return D.Cfg("guardRadius")
    end

    -- A point pulled back inside the droid's area.
    function ENT:InArea(pos)
        local r = self:AreaRadius()
        if not (r and self.home) then return pos end
        local off = pos - self.home
        off.z = 0
        if off:Length() <= r then return pos end
        return self.home + off:GetNormalized() * r + Vector(0, 0, pos.z - self.home.z)
    end

    function ENT:SetPace(run)
        local speed = D.Cfg(self:Kind().speed)
        if not run then speed = speed * D.Cfg("walkMult") end
        self.loco:SetDesiredSpeed(speed)
        self.running = run
    end

    -- Several droids close by and room to the sides: march; else charge.
    function ENT:CanMarch()
        local now = CurTime()
        if (self.marchAt or 0) > now then return self.march end
        self.marchAt = now + 1
        local pos, n = self:GetPos(), 0
        for d in pairs(self.IsRhylibClone and D.clones or D.active) do
            if d ~= self and IsValid(d) and d:GetPos():DistToSqr(pos) < 450 * 450 then n = n + 1 end
        end
        local ok = n >= D.Cfg("marchGroup")
        if ok then
            -- (a corridor: walls close on both sides)
            local eye, right = self:Eye(), self:GetRight() * 160
            local l = util.TraceLine({ start = eye, endpos = eye - right, mask = MASK_SOLID_BRUSHONLY })
            local r = util.TraceLine({ start = eye, endpos = eye + right, mask = MASK_SOLID_BRUSHONLY })
            if l.Hit and r.Hit then ok = false end
        end
        self.march = ok
        return ok
    end

    -- Where to fall back to (aggression 1): a fallback marker, else home.
    function ENT:FallbackPoint()
        -- (a player's followers fall back to them)
        if (self.doctrine == 1 or self.orderAggro == 1) and self.leader and not self.leaderNpc and self.home then return self.home end
        if self.doctrine == 1 and self.doctrineFallback then return self.doctrineFallback end
        return self.fallback or self.home
    end

    -- Clones' doctrine (owner): outnumbered → fall back, even → hold the
    -- line, outnumbering → charge. Once a second while fighting.
    function ENT:UpdateDoctrine()
        if not self.IsRhylibClone or not D.CloneOdds then return end
        local now = CurTime()
        if (self.doctrineAt or 0) > now then return end
        self.doctrineAt = now + 1
        if self.guarding or self.reviveTarget or self.orderAggro or not IsValid(self.target) then
            self.doctrine = nil   -- (guards, medics and followers keep to their job)
            return
        end
        local f, e, mid = D.CloneOdds(self)
        if e <= 0 then self.doctrine = nil return end
        local r = f / e
        if r < D.Cfg("ctFallBackOdds") then
            if self.doctrine ~= 1 or not self.doctrineFallback then
                local away = self:GetPos() - (mid or self.target:GetPos())
                away.z = 0
                if away:LengthSqr() < 1 then away = -self:GetForward() end
                away:Normalize()
                local to = self:GetPos() + away * 600
                self.doctrineFallback = D.GroundAt and D.GroundAt(to) or to
            end
            self.doctrine = 1
        elseif r > D.Cfg("ctChargeOdds") then
            self.doctrine = 5
        else
            self.doctrine = 3
        end
    end

    -- Where to move while fighting t, and whether to run (nil = stay).
    function ENT:PlanMove(t)
        self:UpdateHome()
        self:UpdateDoctrine()
        if self.artillery then return nil end   -- (artillery stays where it's set up)
        local pos, tp = self:GetPos(), t:GetPos()
        -- A friend in the line of fire: a step to the side for a clear shot.
        if self.blockedUntil and CurTime() < self.blockedUntil then
            local to = tp - pos
            to.z = 0
            if to:LengthSqr() > 1 then
                to:Normalize()
                local side = Vector(-to.y, to.x, 0) * (self.stepSide or 1) * 140
                return self:InArea(pos + side), false
            end
        end
        -- Popper charge: run a few steps at the droid (Engage throws at the end).
        local rush = self.popRush
        if rush then
            if IsValid(rush.t) then
                local dir = rush.t:GetPos() - rush.from
                dir.z = 0
                if dir:LengthSqr() > 1 then
                    dir:Normalize()
                    return rush.from + dir * 220, true
                end
            end
            self.popRush = nil
        end
        -- Guarding a downed player / keeping up with the officer: back to
        -- the spot while fighting (runs when far).
        if self.home and (self.guarding or self.mode == "follow") then
            local dh = pos:DistToSqr(self.home)
            local near = self.guarding and 90 or D.Cfg("cloneFollowRadius") * 0.5
            if dh > near * near then return self.home, dh > (self.guarding and 300 or 600) ^ 2 end
        end
        -- Reinforcements: the first few steps toward the enemy, firing.
        if self.advanceTo then
            if CurTime() > (self.advanceUntil or 0) or pos:DistToSqr(self.advanceTo) < 80 * 80 then
                self.advanceTo = nil
            else
                return self.advanceTo, false
            end
        end
        local L = self:Aggro()
        -- Crouched clones holding the line stay down.
        if L == 3 and self.IsRhylibClone and (self.crouchUntil or 0) > CurTime() then return nil end
        local d = pos:Distance(tp)
        local goal, run
        if L == 1 then
            local fb = self:FallbackPoint()
            if fb and pos:DistToSqr(fb) > 150 * 150 then goal, run = fb, false end
        elseif L == 2 then
            -- Fights, never pushes, backs off from anyone close.
            if d < 600 then goal, run = pos + (pos - tp):GetNormalized() * 220, false end
        elseif L == 3 then
            if d > ADVANCE_DIST then goal, run = pos + (tp - pos):GetNormalized() * 300, false end
        else
            if d > 260 then
                goal = tp
                run = L >= 5 or not self:CanMarch()
            end
        end
        if goal and L > 1 then goal = self:InArea(goal) end
        if goal and goal:DistToSqr(pos) < 60 * 60 then goal = nil end
        return goal, run
    end

    -- Can it walk straight there (no route needed)? Checked when planning.
    local hullTr = {}
    local hull = { mask = MASK_NPCSOLID, output = hullTr }   -- (props and other droids block it too)
    function ENT:StraightTo(goal)
        local k = self:Kind()
        hull.start = self:GetPos() + Vector(0, 0, 20)
        hull.endpos = goal + Vector(0, 0, 20)
        hull.mins = k.big and Vector(-16, -16, 0) or Vector(-13, -13, 0)
        hull.maxs = k.big and Vector(16, 16, 50) or Vector(13, 13, 46)
        hull.filter = self
        util.TraceHull(hull)
        if hullTr.Hit then return false end
        -- (and ground halfway and under the far end: no backing off ledges)
        for _, p in ipairs({ (self:GetPos() + goal) * 0.5, goal }) do
            local g = util.TraceLine({ start = p + Vector(0, 0, 20), endpos = p - Vector(0, 0, 80), mask = MASK_SOLID_BRUSHONLY })
            if not g.Hit then return false end
        end
        return true
    end

    -- One tick of movement while fighting: straight lines keep facing the
    -- target (walking or backing off while firing); routes face the way
    -- they go (it fires when the target is still in front).
    function ENT:StepMove(t)
        local now = CurTime()
        if now >= (self.planAt or 0) then
            self.planAt = now + math.Rand(0.4, 0.7)
            local goal, run = self:PlanMove(t)
            self.moveGoal = goal
            if goal then
                self:SetPace(run)
                local dist = goal:Distance(self:GetPos())
                self.moveStraight = dist < 700 and self:StraightTo(goal)
                -- (a new route only when the goal moved a fair share of the way)
                local slack = math.max(100, dist * 0.25)
                if not self.moveStraight and (not self.pathGoal or self.pathGoal:DistToSqr(goal) > slack * slack
                    or not (self.path and self.path:IsValid())) then
                    self.needPath = true
                end
            end
        end
        local goal = self.moveGoal
        if not goal then
            self.loco:FaceTowards(t:GetPos())
            return
        end
        if self.moveStraight then
            self.loco:Approach(goal, 1)
            self.loco:FaceTowards(t:GetPos())
            if self.loco:IsStuck() then
                self:HandleStuck()
                self.moveGoal = nil
            end
            return
        end
        -- A route (computed within the per-tick budget).
        local path = self.path
        if not path then
            path = Path("Follow")
            path:SetMinLookAheadDistance(300)
            path:SetGoalTolerance(40)
            self.path = path
        end
        -- (keeps following the old route while waiting for budget)
        if (self.needPath or not self.pathGoal) and D.TakeBudget() then
            self.needPath = false
            if path:Compute(self, goal) then
                self.pathGoal = goal
            else
                self.moveGoal, self.pathGoal = nil, nil
                self.planAt = CurTime() + 2   -- (no route: don't ask again at once)
                return
            end
        end
        if self.pathGoal and path:IsValid() then
            path:Update(self)
            self:OpenDoors()
            -- Falling back / retreating keeps the gun on the enemy.
            if self:Aggro() <= 2 then self.loco:FaceTowards(t:GetPos()) end
            if self.loco:IsStuck() then
                self:HandleStuck()
                self.moveGoal, self.pathGoal = nil, nil
            end
        else
            self.loco:FaceTowards(t:GetPos())
        end
    end

    -- Is the target within the gun's reach of where the body faces?
    function ENT:Facing(t)
        local f = self:GetForward()
        local to = t:GetPos() - self:GetPos()
        to.z = 0
        f.z = 0
        if to:LengthSqr() < 1 then return true end
        to:Normalize()
        f:Normalize()
        return f:Dot(to) > 0.42   -- (within ~65 degrees, inside the aim pose range)
    end

    --------------------------------------------------------------------------
    -- Fighting: one tick at a time, moving and firing together
    --------------------------------------------------------------------------

    function ENT:Engage()
        local k = self:Kind()
        local t = self.target
        local burstLeft, nextShot = 0, 0
        self.planAt = 0
        while valid(t) do
            if self.reviveTarget then break end   -- (a medic going to a downed player)
            if self:CoverCheck() then break end
            self:Look()
            if self.target ~= t then
                t = self.target
                if not IsValid(t) then break end
                burstLeft = 0
            end
            local now = CurTime()
            if now - (self.lastSeenAt or 0) > 1.5 then   -- lost sight
                self:LobAtLastSeen()
                break
            end

            self:StepMove(t)

            -- End of a popper charge: throw it.
            local rush = self.popRush
            if rush then
                if not valid(rush.t) then
                    self.popRush = nil
                elseif self:GetPos():DistToSqr(rush.from) > 150 * 150 or now > rush.untilT
                    or rush.t:GetPos():DistToSqr(self:GetPos()) < 260 * 260 then
                    self.popRush = nil
                    self.loco:FaceTowards(rush.t:GetPos())
                    self:ThrowNade(rush.t:GetPos() + rush.t:GetVelocity() * 0.4)
                    self.planAt = 0
                end
            end

            if now >= (self.reactUntil or 0) and now >= nextShot and self:Facing(t) then
                if burstLeft <= 0 then
                    local d = t:GetPos():Distance(self:GetPos())
                    -- B2 mortar / rocket droid: now and then a rocket instead of a burst.
                    local arty = self.artillery
                    if k.rockets and now >= self.nextRocket and d > D.Cfg("b2RocketMin")
                        and d < (arty and D.Cfg("artyRange") or D.Cfg("b2RocketMax")) and (arty or math.random() < 0.5) then
                        self:FireRocket(t:GetPos(), t)
                        nextShot = now + 0.6 + math.Rand(0.6, 1.3)
                    elseif arty and d > D.Cfg("artyBlasterRange") then
                        nextShot = now + 0.5   -- (artillery: only rockets at range)
                    else
                        burstLeft = math.random(k.burst[1], k.burst[2])
                    end
                end
                if burstLeft > 0 then
                    if self:FriendInLine(t) then
                        -- (hold fire and step aside; the other side next time)
                        burstLeft = 0
                        if CurTime() >= (self.blockedUntil or 0) then self.stepSide = -(self.stepSide or 1) end
                        self.blockedUntil = CurTime() + 1.2
                        self.planAt = 0
                    elseif self:CanSee(t) then
                        self:FireAt(t)
                        burstLeft = burstLeft - 1
                    else
                        burstLeft = 0
                    end
                    if burstLeft > 0 then
                        nextShot = now + 60 / math.max(D.Cfg(k.rpm), 1)
                    else
                        local pause = math.Rand(0.6, 1.3)
                        if D.Boosted(self) then pause = pause * D.Cfg("cmdPause") end
                        nextShot = now + pause
                        if IsValid(t) and self.threatPos then self.threatPos = t:GetPos() end   -- (once shot at: cover from the one it's fighting)
                        -- B1: now and then a grenade at a target in the open
                        -- (more likely at a group); not while on the move.
                        if IsValid(t) and (not self.moveGoal or k.poppers) and not self.popRush then self:NadeAt(t) end
                    end
                end
            end
            coroutine.yield()
        end
        self.target = nil
        self.moveGoal, self.pathGoal = nil, nil
        self.popRush = nil   -- (a charge that didn't end in a throw is dropped)
        self.doctrine = nil
    end

    -- Any target within 1.5x range (distance only, no traces).
    function ENT:AnyoneNear()
        local r = D.Cfg(self:Kind().range) * 1.5
        local pos = self:GetPos()
        for _, p in ipairs(self:TargetList()) do
            if IsValid(p) and p:GetPos():DistToSqr(pos) < r * r then return true end
        end
        return false
    end

    -- The nearest target anywhere (attack mode hunting; distance only).
    function ENT:NearestTarget(maxDist)
        local pos, best, bestD = self:GetPos(), nil, (maxDist or 6000) ^ 2
        for _, p in ipairs(self:TargetList()) do
            local d = IsValid(p) and p:GetPos():DistToSqr(pos) or math.huge
            if d < bestD then best, bestD = p, d end
        end
        return best
    end

    -- Waits up to secs, waking early when hit or someone comes in sight.
    function ENT:Idle(secs)
        local stop = CurTime() + secs
        self.woken = false
        while CurTime() < stop and not self.woken do
            coroutine.wait(0.5)
            if self:Look() then return end
        end
    end

    -- Go, and after a failed route a short wait (no retrying every tick).
    function ENT:GoOrWait(pos, secs, watch)
        if self:Go(pos, secs, watch) == false and not self.target then self:Idle(math.Rand(1, 2)) end
    end

    -- Following an officer (reinforcements): home is a spot beside them.
    -- The officer dead or gone: guard where it stands; downed: stay put.
    function ENT:FollowLeader()
        local l = self.leader
        local npc = self.leaderNpc
        local up = IsValid(l) and (npc and l:Health() > 0 or not npc and l:IsPlayer() and l:Alive())
        if not up then
            local roam = self.buddyRoam
            self.leader, self.leaderNpc, self.buddyRoam = nil, nil, nil
            -- (a roaming pair's second roams on alone; others guard here)
            if D.SetMode then D.SetMode(self, roam and "roam" or "guard", self:GetPos()) end
            return
        end
        if self.holdAt then   -- (command wheel: hold / move up there)
            self.home = self.holdAt
            return
        end
        if l.rhylibDown then return end
        local yaw = Angle(0, npc and l:GetAngles().y or l:EyeAngles().y, 0)
        local s = self.followSlot or Vector(-120, 0, 0)
        self.home = l:GetPos() + yaw:Forward() * s.x + yaw:Right() * s.y
    end

    -- Home for this moment: standing over a downed player (sv_30_clones
    -- picks guards), else beside the officer it follows, else unchanged.
    function ENT:UpdateHome()
        local p = self.guardDowned
        if p then
            if IsValid(p) and p:Alive() and p.rhylibDown then
                local L = Rhylib.Lying
                local pos = L and L.BodyPos and L.BodyPos(p) or p:GetPos()
                -- (between the body and the danger, a little to one side)
                local th = self.threatPos or (IsValid(self.target) and self.target:GetPos()) or self.lastSeen
                local dir = th and (th - pos) or (self:GetPos() - pos)
                dir.z = 0
                if dir:LengthSqr() < 1 then dir = Vector(1, 0, 0) end
                dir:Normalize()
                local right = Vector(-dir.y, dir.x, 0)
                self.home = pos + dir * 70 + right * (self.guardSide or 1) * 55
                self.guarding = true
                return
            end
            -- (back up / gone: back to what it was doing)
            self.guardDowned, self.guarding = nil, nil
            if self.guardOldHome and not self.leader then self.home = self.guardOldHome end
            self.guardOldHome = nil
        end
        if self.leader then self:FollowLeader() end
    end

    -- Medic: go to a downed (or just dead) player, crouch on the body and
    -- get them up (owner). sv_30_clones picks the patient; D.PatientPending,
    -- D.BodyPos and D.NpcRevive live there too.
    function ENT:DoRevive()
        local p = self.reviveTarget
        if not D.PatientPending(p) then
            self.reviveTarget = nil
            return
        end
        local body = D.BodyPos(p)
        if not body then
            self.reviveTarget = nil
            return
        end
        local function far(b)
            local d = self:GetPos() - b
            d.z = d.z * 0.3   -- (a body on a ledge or lifted pelvis still counts)
            return d:LengthSqr() > 80 * 80
        end
        if far(body) then
            self:SetPace(true)
            local ok = self:Go(body, 3, false)
            -- (close but the route ends short: walk the last bit straight)
            if ok ~= false and far(body) and self:GetPos():DistToSqr(body) < 200 * 200 then
                local stop = CurTime() + 1.5
                while CurTime() < stop and far(body) do
                    self.loco:Approach(body, 1)
                    self.loco:FaceTowards(body)
                    coroutine.yield()
                end
            end
            if far(body) then
                self.reviveFails = (self.reviveFails or 0) + 1
                if self.reviveFails >= 4 then   -- (can't get there: give up on them for a while)
                    p.rhylibNoMedicUntil = CurTime() + 20
                    self.reviveTarget, self.reviveFails = nil, nil
                end
                return
            end
        end
        self.reviveFails = nil
        self.loco:SetDesiredSpeed(0)
        self.crouching = true
        local done = CurTime() + D.Cfg("ctMedicReviveTime")
        while CurTime() < done and D.PatientPending(p) do
            local b = D.BodyPos(p)
            if not b or self:GetPos():DistToSqr(b) > 120 * 120 then break end   -- (dragged away)
            self.loco:FaceTowards(b)
            coroutine.yield()
        end
        self.crouching = false
        self:SetPace(false)
        if CurTime() >= done and D.PatientPending(p) then D.NpcRevive(p) end
        self.reviveTarget = nil
    end

    function ENT:RunBehaviour()
        if self.overCap then return end   -- (being removed: over the cap)
        while true do
            local L = self:Aggro()
            self.mode = self.mode or "guard"
            self:UpdateHome()
            local follow = self.mode == "follow"
            local fb = self:FallbackPoint()
            if self.reviveTarget then
                self:DoRevive()
            elseif self:CoverCheck() then
                -- (came out of cover: look again straight away)
            elseif self:Look() then
                self:Engage()
            elseif self.reinforceTo and CurTime() < (self.reinforceUntil or 0) and not self.guarding and not self.leader
                and self:GetPos():DistToSqr(self.reinforceTo) > 250 * 250 then
                -- Called by a clone in a fight: run over.
                self:SetPace(true)
                self:GoOrWait(self.reinforceTo, 6, true)
            elseif self.advanceTo then
                -- Reinforcements: a few steps toward the enemy first.
                local to = self.advanceTo
                self.advanceTo = nil
                self:SetPace(false)
                self:GoOrWait(to, 4, true)
            elseif L == 1 and fb and self:GetPos():DistToSqr(fb) > 200 * 200 then
                self:SetPace(false)
                self:GoOrWait(fb, 8, true)
            elseif L >= 3 and not self.artillery and self.lastSeen and CurTime() - (self.lastSeenAt or 0) < 20 then
                -- Go where the target was last seen (or where the shot came
                -- from); guards and patrols only within their area.
                local pos = self:InArea(self.lastSeen)
                self.lastSeen = nil
                self:SetPace(L >= 5 or self.mode == "attack")
                self:GoOrWait(pos, 8, true)
            elseif self.mode == "attack" and L >= 3 then
                -- Push on: to the objective, then hunt the nearest players.
                self:SetPace(L >= 5)
                if self.objective and self:GetPos():DistToSqr(self.objective) > 300 * 300 then
                    self:GoOrWait(self.objective, 8, true)
                else
                    self.objective = nil   -- (reached: hunt from here on)
                    local p = self:NearestTarget(6000)
                    if p then self:GoOrWait(p:GetPos(), 5, true) else self:Idle(math.Rand(1, 2)) end
                end
            elseif self.mode == "roam" and not self.guarding then
                -- Spread out: wander the map to a new spot, then the next.
                local now = CurTime()
                if not self.roamGoal or now > (self.roamUntil or 0) or self:GetPos():DistToSqr(self.roamGoal) < 200 * 200 then
                    self.roamGoal = D.RoamPoint and D.RoamPoint(self:GetPos()) or nil
                    self.roamUntil = now + 45
                end
                if self.roamGoal then
                    self:SetPace(false)
                    -- (no route there: pick another spot next time)
                    if self:Go(self.roamGoal, 8, true) == false then
                        self.roamGoal = nil
                        if not self.target then self:Idle(math.Rand(1, 2)) end
                    end
                else
                    self:Idle(math.Rand(2, 4))
                end
            elseif self.mode ~= "attack" and self.home
                and self:GetPos():DistToSqr(self.home) > (self.guarding and 60 or self.mode == "patrol" and D.Cfg("patrolRadius") or follow and 150 or 250) ^ 2 then
                -- Back to its post / patrol area / the officer / a downed
                -- player (runs to catch up).
                self:SetPace((follow or self.guarding) and self:GetPos():DistToSqr(self.home) > (self.guarding and 250 or 500) ^ 2)
                self:GoOrWait(self.home, (follow or self.guarding) and 3 or 8, true)
            elseif self.artillery and self:ArtilleryShot() then
                -- (fired at a target the spotters see)
            elseif self.artillery then
                self:Idle(1)   -- (artillery stays put and checks the spotters often)
            elseif self.guarding then
                -- Over the body: watch, check again soon.
                self:Idle(math.Rand(0.5, 1))
            elseif follow then
                -- With the officer: stand ready, check again soon.
                self:Idle(math.Rand(0.5, 1))
            elseif self.mode == "patrol" then
                -- Walk around the patrol area.
                self:SetPace(false)
                -- (a point inside the circle, not the square around it)
                local a, r = math.Rand(0, math.pi * 2), D.Cfg("patrolRadius") * math.sqrt(math.Rand(0, 0.9))
                self:GoOrWait(self.home + Vector(math.cos(a) * r, math.sin(a) * r, 0), 8, true)
                if not self.target then self:Idle(math.Rand(1, 3)) end
            elseif not self:AnyoneNear() then
                -- Nobody anywhere near: stand still a while.
                self:Idle(math.Rand(3, 5))
            elseif math.random() < 0.25 then
                -- Guard: shift a little around the post.
                self:SetPace(false)
                self:GoOrWait((self.home or self:GetPos()) + Vector(math.Rand(-200, 200), math.Rand(-200, 200), 0), 4, true)
                if not self.target then self:Idle(math.Rand(2, 4)) end
            else
                self:Idle(math.Rand(1, 2))
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
        local want = speed > 10 and (speed > 110 and A.run or A.walk) or ((self.crouching or (self.crouchUntil or 0) > CurTime()) and A.crouch) or A.idle
        -- Roaming clones with no enemy about carry the gun on safety (lowered).
        if self.IsRhylibClone and (self.mode == "roam" or self.buddyRoam) and not IsValid(self.target)
            and CurTime() - (self.lastSeenAt or -100) > 8 and not self.crouching then
            local safe = speed > 10 and (speed > 110 and (A.runSafe or A.walkSafe) or A.walkSafe) or (speed <= 10 and A.idleSafe)
            if safe then want = safe end
        end
        if self:GetActivity() ~= want then self:StartActivity(want) end

        -- Aim the gun at the target. Sent only on a 3 degree change, or
        -- a smaller one after 0.1 s (fewer entity updates).
        local t = self.target
        local yaw, pitch = 0, 0
        if IsValid(t) then
            local ang = (t:WorldSpaceCenter() - self:Eye()):Angle()
            yaw = math.Clamp(math.NormalizeAngle(ang.y - self:GetAngles().y), -60, 60)
            pitch = math.Clamp(math.NormalizeAngle(ang.p), -50, 50)
        end
        local dy, dp = math.abs(yaw - (self.aimYaw or 999)), math.abs(pitch - (self.aimPitch or 999))
        if dy > 0.25 or dp > 0.25 then
            local now = CurTime()
            if dy > 3 or dp > 3 or now - (self.aimAt or 0) >= 0.1 then
                self.aimYaw, self.aimPitch, self.aimAt = yaw, pitch, now
                self:SetPoseParameter("aim_yaw", yaw)
                self:SetPoseParameter("aim_pitch", pitch)
            end
        end

        if speed > 10 then self:BodyMoveXY() else self:FrameAdvance() end
    end
end

if CLIENT then
    -- One shared gun model per kind, moved to each droid's hand when drawn.
    local guns = {}
    local handBone = {}
    -- Hand placement (2026-10-06bg, owner: the guns floated): the players'
    -- third-person values (PropWMPos / PropWMAng / PropScale / PropBodygroups)
    -- of the Rhylib weapon using the same model, read from the SWEP, so
    -- tuning a player gun (rhylib_wm_editor) moves the NPC one too. Models no
    -- player weapon uses (the droids' E5) keep the old values (owner: fine).
    local DEFAULT = { pos = Vector(5, 1, -3), ang = Angle(-10, 0, 180), scale = 1 }
    local placeOf = {}

    local function fromSwep(w)
        if not (w and w.PropWMPos and w.PropWMAng) then return nil end
        return { pos = w.PropWMPos, ang = w.PropWMAng, scale = w.PropScale or 1, bg = w.PropBodygroups }
    end

    local function placement(mdl)
        local pl = placeOf[mdl]
        if pl then return pl end
        for _, w in ipairs(weapons.GetList()) do
            if w.PropModel == mdl and w.ClassName and string.StartWith(w.ClassName, "rhylib_") then
                pl = fromSwep(weapons.Get(w.ClassName))
                if pl then break end
            end
        end
        pl = pl or DEFAULT
        placeOf[mdl] = pl
        return pl
    end
    -- (re-read after a Lua refresh)
    Rhylib.Hook.Add("OnReloaded", "droids.gunplace", function() placeOf = {} end)

    local function place(pos, ang, pl)
        local POS, ANG = pl.pos, pl.ang
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
            gun.rhylibPlace = nil
        end
        local pl = placement(mdlName)
        if gun.rhylibPlace ~= pl then
            gun.rhylibPlace = pl
            gun:SetModelScale(pl.scale, 0)
            for i, v in pairs(pl.bg or {}) do gun:SetBodygroup(i, v) end
        end
        local mdl = self:GetModel()
        local b = handBone[mdl]
        if b == nil then
            b = self:LookupBone("ValveBiped.Bip01_R_Hand") or false
            handBone[mdl] = b
        end
        local m = b and self:GetBoneMatrix(b)
        if not m then return end
        local p, a = place(m:GetTranslation(), m:GetAngles(), pl)
        gun:SetPos(p)
        gun:SetAngles(a)
        gun:SetupBones()
        gun:DrawModel()
    end
end
