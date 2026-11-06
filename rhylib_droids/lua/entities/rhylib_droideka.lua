--[[
    Droideka (destroyer droid): the droid brain (rhylib_b1) with the
    "droideka" row of Rhylib.Droids.KINDS. Two looks and two ways to fight:

      rolled (NW2Int rhylib_dk 0)   fast (droidekaSpeed), no shield, holds
                                    fire, takes damage like any droid
                                    (droidekaHealth)
      deploying (1)                 stopped for 0.3 s: unfolds for
                                    droidekaDeployTime s (no shield yet,
                                    no firing)
      deployed (2)                  stands (or crawls at droidekaWalkSpeed
                                    for a side step), shield up, fires its
                                    two arm blasters in turn (left, right)
                                    in bursts of kind.burst shots at
                                    droidekaRPM, droidekaPause s between
                                    bursts
    The state follows its speed (BodyUpdate, every tick): faster than
    droidekaWalkSpeed + 20 = rolled at once; stopped 0.3 s = deploying.
    So anything that moves it (chasing, patrols, squads, orders) rolls it.

    Moving in a fight (ENT:PlanMove): retreating, falling back
    (aggression 1-2), defending, guarding, following and reinforcement
    steps use the shared plan. Otherwise: a target further than
    droidekaDeployRange: it rolls in to 0.75 x that range (aggression 4-5:
    0.45 x) and deploys there; in range it stays deployed. Now and then
    (every droidekaRepositionMin-Max s deployed, 0 = never) it rolls a few
    metres to the side (closer when far, back when close) and deploys again.
    A friend in the line of fire: it crawls aside deployed (ENT:SetPace).

    Shield (shared ENT:ShieldSphere: centre and radius; the model bounds'
    half-diagonal x droidekaShieldScale, or droidekaShieldRadius): up while
    deployed, except droidekaShieldDownTime s after a droid popper's EMP
    (NW2Float rhylib_dkOff = until when). With it up:
      - bolts: rhylib_weapons asks ENT:BoltShield(bolt, tr) when one hits
        it. A bolt whose shooter stands inside the bubble (its body from
        feet to top reaches into it; no shooter: where the bolt started)
        hits normally; any other stops at the bubble: spark, a flash on
        the bubble (effect rhylib_deka_hit), no damage. Its own bolts
        start inside and fly out.
      - EntityTakeDamage "droids.droideka.shield" (-150), checked in order:
          rocket straight into it (W.directHit): always kills it
          rocket blast (a gun / rocket / missile entity as the inflictor,
          as the spider's; cluster bomblets too): centre inside the bubble
          or within 60 units of it: kills it, rolled or not; further out:
          none while the shield is up, else normal blast damage
          droid popper EMP (DMG_SHOCK): shield up: no damage, the shield
          drops; no shield: as for any droid
          frag grenade (rhylib_grenade fuse / impact, npc_grenade_frag,
          grenade_ar2) going off inside the bubble: kills it; outside: none
          another blast: centre inside: normal damage; outside: none
          anything else (bolts, bullets, melee): from someone inside
          x droidekaInsideMult; from outside: none (the brain still hears
          it, ENT:OnInjured with 0 damage)
    No shield (rolled, deploying, EMP'd): normal damage; a direct rocket
    hit or a rocket blast at or in the bubble still kills.

    Look: droidekaModel; sequences droidekaSeqRoll / SeqDeploy / SeqIdle /
    SeqWalk, else found by name ("roll", "ball", "deploy", "idle", ...),
    idle else ACT_IDLE. With no roll sequence the rolled droideka is drawn
    as a ball (droidekaBallModel, droidekaBallRadius) spinning with its
    speed and the model is hidden. The console prints the model's sequence
    names once per model.
    Muzzles: attachments droidekaMuzzleLeft / Right, else the model's
    ValveBiped hands, else droidekaMuzzleFwd / Side / Up from its feet.
    Hull droidekaHeight tall, HullHalf wide; big (clones count it double,
    no cover, no grenades).
]]

AddCSLuaFile()

local Base = baseclass.Get("rhylib_b1")

ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "Droideka"
ENT.Category = "Rhy's Droidekas"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "droideka"
ENT.QuietAnims = true   -- (its own animation line below)
ENT.IsDroideka = true
ENT.HullHalf = 16
ENT.RenderGroup = RENDERGROUP_BOTH

local ROLLED, DEPLOYING, DEPLOYED = 0, 1, 2

-- Sequences per model: { roll, deploy, idle, walk } (sequence ids or nil;
-- idle always set). Shared: the client needs roll to pick the ball look.
local NAMES = {
    roll = { "roll", "rolling", "roll_loop", "ball", "curl" },
    deploy = { "deploy", "unroll", "uncurl", "unfold", "transform" },
    idle = { "idle", "deployed_idle", "idle_deployed", "idle_all_01" },
    walk = { "walk", "walk_all", "deployed_walk" },
}
local SEQ_KEY = { roll = "droidekaSeqRoll", deploy = "droidekaSeqDeploy", idle = "droidekaSeqIdle", walk = "droidekaSeqWalk" }
local animsOf = {}

local function seqOf(ent, name)
    if not (isstring(name) and name ~= "") then return nil end
    local s = ent:LookupSequence(name)
    return s and s >= 0 and s or nil
end

local function resolve(ent)
    local D = Rhylib.Droids
    local mdl = ent:GetModel() or ""
    local key = mdl
    for _, k in pairs(SEQ_KEY) do key = key .. "|" .. tostring(D.Cfg(k)) end
    local a = animsOf[key]
    if a then return a end
    a = {}
    for part, cfgKey in pairs(SEQ_KEY) do
        a[part] = seqOf(ent, D.Cfg(cfgKey))
        if not a[part] then
            for _, n in ipairs(NAMES[part]) do
                a[part] = seqOf(ent, n)
                if a[part] then break end
            end
        end
    end
    if not a.idle then
        for _, act in ipairs({ ACT_IDLE, ACT_HL2MP_IDLE }) do
            local s = act and ent:SelectWeightedSequence(act) or -1
            if s and s >= 0 then a.idle = s break end
        end
    end
    a.idle = a.idle or 0
    animsOf[key] = a
    if SERVER then
        local names = {}
        for i = 0, math.min(ent:GetSequenceCount() - 1, 59) do names[#names + 1] = ent:GetSequenceName(i) end
        local function nm(s) return s and ent:GetSequenceName(s) or "none" end
        Rhylib.Print("droids", "droideka %s: %d sequences (%s); roll %s, deploy %s, idle %s, walk %s", mdl, ent:GetSequenceCount(),
            table.concat(names, " "), a.roll and nm(a.roll) or "none (ball look)", nm(a.deploy), nm(a.idle), nm(a.walk))
    end
    return a
end

-- ENT:ShieldSphere() -> centre (world), radius of the bubble. Shared;
-- the size is worked out again at most once a second.
function ENT:ShieldSphere()
    local now = CurTime()
    if not self.dkSph or now >= self.dkSphAt then
        local D = Rhylib.Droids
        local ms = self:GetModelScale() or 1
        local mn, mx = self:GetModelBounds()
        local r, z
        if mn and mx then
            r = ((mx - mn) * 0.5 * ms):Length() * math.max(tonumber(D.Cfg("droidekaShieldScale")) or 1, 0.1)
            z = (mn.z + mx.z) * 0.5 * ms
        end
        local fixed = tonumber(D.Cfg("droidekaShieldRadius")) or 0
        if fixed > 0 then r = fixed end
        r = math.Clamp(r or 56, 24, 200)
        self.dkSph = { r = r, z = math.Clamp(z or r * 0.6, 8, r) }
        self.dkSphAt = now + 1
    end
    local s = self.dkSph
    local c = self:GetPos()
    c.z = c.z + s.z
    return c, s.r
end

-- ENT:InBubble(p) -> is point p inside the bubble?
function ENT:InBubble(p)
    local c, r = self:ShieldSphere()
    return p:DistToSqr(c) <= r * r
end

-- ENT:BodyInBubble(e) -> does e's body (a line from its feet to its top)
-- reach into the bubble?
function ENT:BodyInBubble(e)
    local c, r = self:ShieldSphere()
    local p = e:GetPos()
    local top = p.z + math.max(e:OBBMaxs().z, 8)
    p.z = math.Clamp(c.z, p.z, top)
    return p:DistToSqr(c) <= r * r
end

-- ENT:DekaBounds(): render bounds that hold the bubble (client; again
-- when its size changes).
function ENT:DekaBounds()
    local c, r = self:ShieldSphere()
    if self.dkRB == r then return end
    self.dkRB = r
    local z = c.z - self:GetPos().z
    self:SetRenderBounds(Vector(-r, -r, math.min(z - r, 0)), Vector(r, r, z + r))
end

function ENT:Initialize()
    Base.Initialize(self)
    if CLIENT then
        -- (the client's IsValidModel can miss an installed model: Base set the fallback)
        local mdl = Rhylib.Droids.KindModel(self:Kind())
        if isstring(mdl) and mdl ~= "" and self:GetModel() ~= mdl and file.Exists(mdl, "GAME") then
            util.PrecacheModel(mdl)
            self:SetModel(mdl)
        end
        self.dkSph = nil
        self:DekaBounds()
        return
    end
    if self.overCap then return end
    local D = Rhylib.Droids
    local h = math.max(D.Cfg("droidekaHeight"), 16)
    local scale = tonumber(D.Cfg("droidekaScale")) or 1
    if scale > 0 and math.abs(scale - 1) > 0.01 then self:SetModelScale(scale, 0) else scale = 1 end
    -- (the spider's hull rule: if the engine scaled the bounds, set them again divided by it)
    local w = self.HullHalf
    local mins, maxs = Vector(-w, -w, 0), Vector(w, w, h)
    local function hull()
        if not IsValid(self) then return end
        self:SetCollisionBounds(mins, maxs)
        if scale ~= 1 and math.abs(self:OBBMaxs().z - h) > h * 0.1 then self:SetCollisionBounds(mins / scale, maxs / scale) end
    end
    hull()
    timer.Simple(0.1, hull)
    self.eyeOff = Vector(0, 0, math.max(h * 0.85, 12))
    -- (the shared brain reads self.anims.shoot / throw: none here)
    self.anims = { idle = ACT_IDLE, walk = ACT_WALK, run = ACT_RUN }
    self.dkAnims = resolve(self)
    self.dkSeq = nil
    -- (placed standing: deployed, shield up)
    self:SetDk(DEPLOYED)
end

if SERVER then
    local D = Rhylib.Droids

    function ENT:Eye()
        return self:GetPos() + (self.eyeOff or Vector(0, 0, 54))
    end

    -- ENT:SetDk(state): rolled / deploying / deployed, for clients too.
    function ENT:SetDk(s)
        local old = self.dkState
        if old == s then return end
        self.dkState = s
        self:SetNW2Int("rhylib_dk", s)
        local now = CurTime()
        if s == DEPLOYED then
            self.dkDeployedAt = now
        else
            self.dkRepoAt = nil
        end
        if s == DEPLOYING then
            self.dkDeployEnd = now + math.max(D.Cfg("droidekaDeployTime"), 0)
            self:EmitSound("npc/roller/mine/rmine_blades_out" .. math.random(1, 3) .. ".wav", 70, 90)
        elseif s == ROLLED and old ~= nil then
            self:EmitSound("npc/roller/mine/rmine_blades_in" .. math.random(1, 3) .. ".wav", 70, 90)
        elseif s == DEPLOYED and old ~= nil and self:ShieldUp() then
            self:EmitSound("items/suitchargeok1.wav", 70, 70)
        end
    end

    -- ENT:ShieldUp() -> deployed and not knocked out by an EMP.
    function ENT:ShieldUp()
        return self.dkState == DEPLOYED and CurTime() >= (self.dkOffUntil or 0)
    end

    -- ENT:ShieldDrop(): an EMP: the shield is down droidekaShieldDownTime s.
    function ENT:ShieldDrop()
        local untilT = CurTime() + math.max(D.Cfg("droidekaShieldDownTime"), 0)
        self.dkOffUntil = untilT
        self:SetNW2Float("rhylib_dkOff", untilT)
        self:EmitSound("ambient/energy/zap7.wav", 80, 90)
    end

    -- Bolt hook (rhylib_weapons sv_10_bolts applyHit): true = stopped at
    -- the bubble (spark, flash), false = hits normally. Bolts from inside
    -- are marked for the damage hook (self.dkInTick).
    local nextFx = setmetatable({}, { __mode = "k" })
    function ENT:BoltShield(bolt, tr)
        if not self:ShieldUp() then return false end
        local owner = bolt.owner
        local inside
        if IsValid(owner) and (owner:IsPlayer() or owner:IsNPC() or owner:IsNextBot()) then
            inside = self:BodyInBubble(owner)
        else
            inside = self:InBubble(bolt.start or tr.HitPos)
        end
        if inside then
            self.dkInTick = engine.TickCount()
            return false
        end
        local now = CurTime()
        if now >= (nextFx[self] or 0) then
            nextFx[self] = now + 0.05
            -- (where the bolt's line enters the bubble, back from where it hit)
            local c, r = self:ShieldSphere()
            local dir = bolt.dir
            local hit = tr.HitPos
            local v = hit - c
            local b = v:Dot(dir)
            local disc = b * b - v:LengthSqr() + r * r
            local at = disc >= 0 and hit - dir * (b + math.sqrt(disc)) or hit
            local ed = EffectData()
            ed:SetOrigin(at)
            ed:SetNormal((at - c):GetNormalized())
            ed:SetEntity(self)
            util.Effect("rhylib_deka_hit", ed, true, true)
            if now >= (self.dkSndAt or 0) then
                self.dkSndAt = now + 0.12
                sound.Play("weapons/physcannon/energy_bounce" .. math.random(1, 2) .. ".wav", at, 70, math.random(120, 140), 0.6)
            end
        end
        return true
    end

    -- Arms in turn: left, right (self.dkLeft).
    local attOf, hands = {}, {}
    local function att(self, name)
        if not (isstring(name) and name ~= "") then return nil end
        local key = (self:GetModel() or "") .. "|" .. name
        local id = attOf[key]
        if id == nil then
            id = self:LookupAttachment(name) or 0
            attOf[key] = id
        end
        local a = id > 0 and self:GetAttachment(id)
        return a and a.Pos or nil
    end
    function ENT:Muzzle()
        local left = not self.dkLeft
        self.dkLeft = left
        local p = att(self, D.Cfg(left and "droidekaMuzzleLeft" or "droidekaMuzzleRight"))
        if p then return p end
        local mdl = self:GetModel() or ""
        local h = hands[mdl]
        if not h then
            h = { self:LookupBone("ValveBiped.Bip01_L_Hand") or false, self:LookupBone("ValveBiped.Bip01_R_Hand") or false }
            hands[mdl] = h
        end
        local b = h[left and 1 or 2]
        local bp = b and self:GetBonePosition(b)
        if bp then return bp + self:GetForward() * 8 end
        return self:GetPos() + self:GetForward() * D.Cfg("droidekaMuzzleFwd")
            + self:GetRight() * (left and -1 or 1) * D.Cfg("droidekaMuzzleSide") + Vector(0, 0, D.Cfg("droidekaMuzzleUp"))
    end

    function ENT:FireAtPos(aim, speed, extra)
        Base.FireAtPos(self, aim, speed, extra)
        self.dkFired = (self.dkFired or 0) + 1
    end

    -- Firing smoke near a commander: only deployed.
    function ENT:SuppressSmoke(t)
        if self.dkState ~= DEPLOYED then return false end
        return Base.SuppressSmoke(self, t)
    end

    -- Fires only deployed, in bursts (kind.burst) of the shared
    -- "suppress" style, droidekaPause s between them.
    function ENT:StyleFire(t, now, st)
        if self.dkState ~= DEPLOYED then
            st.dkLeft, st.suppT = 0, nil
            return now + 0.15
        end
        local k = self:Kind()
        if (st.dkLeft or 0) <= 0 then
            if now < (st.dkPauseUntil or 0) then return st.dkPauseUntil end
            st.dkLeft = math.random(k.burst[1], k.burst[2])
        end
        local before = self.dkFired or 0
        local nextT = Base.StyleFire(self, t, now, st)
        if (self.dkFired or 0) > before then
            st.dkLeft = st.dkLeft - 1
            if st.dkLeft <= 0 then
                local m = 1
                if D.Boosted(self) then m = m * D.Cfg("cmdPause") end
                if self.lastStand then m = m * D.Cfg("lastStandPause") end
                st.dkPauseUntil = now + math.max(D.Cfg("droidekaPause"), 0) * math.Rand(0.8, 1.25) * m
                return math.max(nextT, st.dkPauseUntil)
            end
        end
        return nextT
    end

    -- Crawling aside deployed (self.dkCreepTick: PlanMove asked for it
    -- this tick, StepMove sets the pace right after), else the shared pace.
    function ENT:SetPace(run)
        if self.dkCreepTick == engine.TickCount() then
            local s = math.max(D.Cfg("droidekaWalkSpeed"), 1)
            self.paceSpeed, self.running = s, false
            self.loco:SetDesiredSpeed(s)
            return
        end
        Base.SetPace(self, run)
    end

    -- A spot a few metres to the side (closer when far, back when close).
    function ENT:DekaRepoPoint(pos, tp, d, far)
        local to = tp - pos
        to.z = 0
        if to:LengthSqr() < 1 then return nil end
        to:Normalize()
        local off = Vector(-to.y, to.x, 0) * (math.random(2) == 1 and 1 or -1) * math.Rand(220, 420)
        if d > far * 0.8 then off = off + to * 150 elseif d < 450 then off = off - to * 150 end
        local goal = self:InArea(pos + off)
        if navmesh.IsLoaded() then
            local a = navmesh.GetNearestNavArea(goal, false, 250, false, true)
            if not a then return nil end
            goal = a:GetClosestPointOnArea(goal)
        elseif not self:StraightTo(goal) then
            return nil
        end
        if not goal or goal:DistToSqr(pos) < 100 * 100 then return nil end
        return goal
    end

    -- Moving in a fight: see the header.
    function ENT:PlanMove(t)
        self.dkCreepTick = nil
        if self:Retreating() or self.artillery then return Base.PlanMove(self, t) end
        local now = CurTime()
        if self.blockedUntil and now < self.blockedUntil then
            if self.dkState ~= ROLLED then self.dkCreepTick = engine.TickCount() end
            return Base.PlanMove(self, t)
        end
        local L = self:Aggro()
        if L <= 2 or self.defending or self.guarding or self.mode == "follow" or self.advanceTo then
            self.dkRepo, self.dkClosing = nil, nil
            return Base.PlanMove(self, t)
        end
        local pos, tp = self:GetPos(), t:GetPos()
        local d = pos:Distance(tp)
        if self.dkRepo then
            if now > (self.dkRepoUntil or 0) or pos:DistToSqr(self.dkRepo) < 80 * 80 then
                self.dkRepo = nil
            else
                return self.dkRepo, true
            end
        end
        local far = D.Cfg("droidekaDeployRange")
        local stopAt = far * (L >= 4 and 0.45 or 0.75)
        if d > far or (self.dkClosing and d > stopAt + 60) then
            self.dkClosing = true
            local to = tp - pos
            to.z = 0
            if to:LengthSqr() >= 1 then
                to:Normalize()
                local goal = self:InArea(tp - to * stopAt)
                if goal:DistToSqr(pos) >= 60 * 60 then return goal, true end
            end
        end
        self.dkClosing = nil
        if self.dkState == DEPLOYED then
            local lo, hi = D.Cfg("droidekaRepositionMin"), D.Cfg("droidekaRepositionMax")
            if hi > 0 then
                self.dkRepoAt = self.dkRepoAt or now + math.Rand(math.Clamp(lo, 0, hi), hi)
                if now >= self.dkRepoAt then
                    self.dkRepoAt = nil
                    local goal = self:DekaRepoPoint(pos, tp, d, far)
                    if goal then
                        self.dkRepo, self.dkRepoUntil = goal, now + 5
                        return goal, true
                    end
                end
            end
        end
        return nil
    end

    -- State (see the header) and animation. Every tick (NextBot callback).
    function ENT:BodyUpdate()
        local A = self.dkAnims
        if not A then return end
        local now = CurTime()
        local speed = self.loco:GetVelocity():Length2D()
        local s = self.dkState
        if speed > D.Cfg("droidekaWalkSpeed") + 20 then
            if s ~= ROLLED then self:SetDk(ROLLED) end
            self.dkStillAt = nil
        elseif s == ROLLED then
            if speed < 15 then
                self.dkStillAt = self.dkStillAt or now
                if now - self.dkStillAt >= 0.3 then self:SetDk(DEPLOYING) end
            else
                self.dkStillAt = nil
            end
        elseif s == DEPLOYING and now >= (self.dkDeployEnd or 0) then
            self:SetDk(DEPLOYED)
        end
        -- (an EMP wears off: the shield comes back)
        if self.dkOffUntil and now >= self.dkOffUntil then
            self.dkOffUntil = nil
            if self.dkState == DEPLOYED then self:EmitSound("items/suitchargeok1.wav", 70, 70) end
        end
        s = self.dkState
        local want, rate
        if s == ROLLED then
            want = A.roll or A.idle
            rate = A.roll and math.Clamp(speed / 150, 0.3, 3) or 1
        elseif s == DEPLOYING then
            want = A.deploy or A.idle
        else
            want = (speed > 5 and A.walk) or A.idle
        end
        if want ~= self.dkSeq then
            self.dkSeq = want
            self:ResetSequence(want)
            self:SetCycle(0)
            if s == DEPLOYING and A.deploy then
                local dur = self:SequenceDuration(want)
                rate = dur > 0 and dur / math.max(D.Cfg("droidekaDeployTime"), 0.1) or 1
            end
            rate = rate or 1
            self.dkRate = rate
            self:SetPlaybackRate(rate)
        elseif rate and math.abs(rate - (self.dkRate or 1)) > 0.15 then
            self.dkRate = rate
            self:SetPlaybackRate(rate)
        end
        self:FrameAdvance()
    end

    -- A rocket's blast (not a direct hit)? (the spider's rule: a gun as
    -- the inflictor, the RPS-6 and other launchers' rocket bolts, or a
    -- rocket / missile entity such as rhylib_topattack's bomblets)
    local ROCKET_CLASS = { rhylib_b2_rocket = true, rhylib_topattack = true, rpg_missile = true }
    local ROCKET_REACH = 60   -- (a rocket blast this far outside the bubble still counts as inside)
    local function isRocketBlast(dmg)
        if not dmg:IsDamageType(DMG_BLAST) then return false end
        local inf = dmg:GetInflictor()
        if not IsValid(inf) then return false end
        if inf:IsWeapon() then return true end   -- (rhylib_weapons rocket bolts: the launcher)
        local c = inf:GetClass()
        return ROCKET_CLASS[c] or string.find(c, "rocket", 1, true) ~= nil or string.find(c, "missile", 1, true) ~= nil
    end

    -- A frag grenade's blast -> where it went off (the spider's rule).
    local OTHER_NADE = { npc_grenade_frag = true, grenade_ar2 = true }
    local function grenadeAt(dmg)
        if not dmg:IsDamageType(DMG_BLAST) then return nil end
        local inf = dmg:GetInflictor()
        if not IsValid(inf) then return nil end
        local c = inf:GetClass()
        if c == "rhylib_grenade" then
            local k = inf.GetKind and inf:GetKind()
            if k ~= 1 and k ~= 2 then return nil end   -- (fuse, impact)
            return inf.Centre and inf:Centre() or inf:GetPos()
        end
        if OTHER_NADE[c] then return inf:GetPos() end
        return nil
    end

    -- Where a blast went off: its damage position, else a non-weapon inflictor's.
    local function blastAt(dmg)
        local p = dmg:GetDamagePosition()
        if p and not p:IsZero() then return p end
        local inf = dmg:GetInflictor()
        if IsValid(inf) and not inf:IsWeapon() then return inf:GetPos() end
        return nil
    end

    local function kill(ent, dmg)
        dmg:SetDamage(math.max(dmg:GetDamage(), ent:Health() + 100))
    end

    -- Blocked by the shield: no damage; the brain still hears it.
    local function block(ent, dmg)
        dmg:SetDamage(0)
        ent:OnInjured(dmg)
        return true
    end

    -- After the friendly-fire check (-200). See the header.
    Rhylib.Hook.Add("EntityTakeDamage", "droids.droideka.shield", function(ent, dmg)
        if not ent.IsDroideka or not ent.ShieldUp then return end
        local W = Rhylib.Weapons
        if W and W.directHit == ent then
            kill(ent, dmg)
            return
        end
        local up = ent:ShieldUp()
        if isRocketBlast(dmg) then
            local p = blastAt(dmg)
            if p then
                local c, r = ent:ShieldSphere()
                r = r + ROCKET_REACH
                if p:DistToSqr(c) <= r * r then
                    kill(ent, dmg)
                    return
                end
            end
            if up then return block(ent, dmg) end
            return
        end
        if dmg:IsDamageType(DMG_SHOCK) then
            if not up then return end
            ent:ShieldDrop()
            dmg:SetDamage(0)
            return true
        end
        if not up then return end
        local g = grenadeAt(dmg)
        if g then
            if ent:InBubble(g) then
                kill(ent, dmg)
                return
            end
            return block(ent, dmg)
        end
        if dmg:IsDamageType(DMG_BLAST) then
            local p = blastAt(dmg)
            if p and ent:InBubble(p) then return end
            return block(ent, dmg)
        end
        local inside = ent.dkInTick == engine.TickCount()
        ent.dkInTick = nil
        if not inside then
            local att = dmg:GetAttacker()
            inside = IsValid(att) and att ~= ent and not att:IsWorld() and ent:BodyInBubble(att)
        end
        if not inside then return block(ent, dmg) end
        dmg:ScaleDamage(math.max(D.Cfg("droidekaInsideMult"), 0))
    end, -150)
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local SHIELD = Color(90, 150, 255, 30)
    local WIRE = Color(140, 200, 255, 30)
    local FLASH = Color(170, 215, 255, 255)

    -- ENT:ShieldHit(pos): a bolt stopped here (effect rhylib_deka_hit).
    function ENT:ShieldHit(pos)
        local h = self.dkHits
        if not h then h = {} self.dkHits = h end
        if #h >= 6 then table.remove(h, 1) end
        h[#h + 1] = { pos = pos, t = CurTime() }
    end

    local function shieldUp(self)
        return self:GetNW2Int("rhylib_dk", DEPLOYED) == DEPLOYED and CurTime() >= self:GetNW2Float("rhylib_dkOff", 0)
    end

    -- Rolled with no roll sequence: a spinning ball instead of the model.
    function ENT:DrawBall()
        local D = Rhylib.Droids
        local ball = self.dkBall
        local mdl = D.Cfg("droidekaBallModel")
        if not IsValid(ball) or ball.dkMdl ~= mdl then
            if IsValid(ball) then ball:Remove() end
            if not (isstring(mdl) and (util.IsValidModel(mdl) or file.Exists(mdl, "GAME"))) then return false end
            util.PrecacheModel(mdl)
            ball = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
            if not IsValid(ball) then return false end
            ball:SetNoDraw(true)
            ball.dkMdl = mdl
            local mn, mx = ball:GetModelBounds()
            ball.dkR = math.max((mx.x - mn.x) * 0.5, 1)
            self.dkBall = ball
        end
        local R = math.max(D.Cfg("droidekaBallRadius"), 4)
        local pos = self:GetPos()
        local frame = FrameNumber()
        if self.dkBallFrame ~= frame then
            self.dkBallFrame = frame
            local ang = self.dkBallAng or Angle()
            local last = self.dkLast
            if last then
                local dx, dy = pos.x - last.x, pos.y - last.y
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0.01 and len < 200 then
                    ang:RotateAroundAxis(Vector(-dy / len, dx / len, 0), math.deg(len / R))
                end
            end
            self.dkLast = pos
            self.dkBallAng = ang
        end
        local sc = R / ball.dkR
        if ball.dkSc ~= sc then
            ball.dkSc = sc
            ball:SetModelScale(sc, 0)
        end
        ball:SetPos(pos + Vector(0, 0, R))
        ball:SetAngles(self.dkBallAng)
        render.SetColorModulation(0.6, 0.5, 0.38)
        ball:DrawModel()
        render.SetColorModulation(1, 1, 1)
        return true
    end

    function ENT:Draw()
        local now = CurTime()
        if not self.dkRollAt or now >= self.dkRollAt then
            self.dkRollAt = now + 1
            self.dkNoRoll = not resolve(self).roll
        end
        self:DekaBounds()
        if self.dkNoRoll and self:GetNW2Int("rhylib_dk", DEPLOYED) == ROLLED and self:DrawBall() then return end
        self.dkLast = nil
        self:DrawModel()
    end

    -- The bubble: a translucent sphere (both sides, so it shows from
    -- inside), a faint wire shimmer, and a flash where bolts stopped.
    function ENT:DrawTranslucent()
        if not shieldUp(self) then return end
        local c, r = self:ShieldSphere()
        self:DekaBounds()
        local now = CurTime()
        local pulse = 0.5 + 0.5 * math.sin(now * 3 + self:EntIndex())
        local flash = 0
        local hits = self.dkHits
        if hits then
            for i = #hits, 1, -1 do
                local age = now - hits[i].t
                if age > 0.4 or age < 0 then table.remove(hits, i) else flash = math.max(flash, 1 - age / 0.4) end
            end
        end
        render.SetColorMaterial()
        SHIELD.a = 16 + 10 * pulse + 45 * flash
        render.CullMode(MATERIAL_CULLMODE_CW)
        render.DrawSphere(c, r, 24, 16, SHIELD)
        render.CullMode(MATERIAL_CULLMODE_CCW)
        render.DrawSphere(c, r, 24, 16, SHIELD)
        WIRE.a = 14 + 18 * pulse
        render.DrawWireframeSphere(c, r * (0.995 + 0.006 * pulse), 18, 12, WIRE, false)
        if hits and #hits > 0 then
            render.SetMaterial(GLOW)
            for i = 1, #hits do
                local a = 1 - (now - hits[i].t) / 0.4
                FLASH.a = 255 * a
                local s = 18 + 22 * a
                render.DrawSprite(hits[i].pos, s, s, FLASH)
            end
        end
    end

    function ENT:OnRemove()
        if IsValid(self.dkBall) then self.dkBall:Remove() end
    end
end
