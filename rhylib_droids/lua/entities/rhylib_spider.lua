--[[
    DSD1 dwarf spider droid: the droid brain (rhylib_b1) with the "spider"
    row of Rhylib.Droids.KINDS, on a four-legged model. Walks the navmesh
    like the others (no wall climbing).

    What this file changes from rhylib_b1:
      - model: config spiderModel (placeholder models/antlion.mdl), sized
        to spiderHeight (or spiderScale), hull spiderHeight tall, eyes near
        the top of the body
      - animation: spiderSeqIdle / spiderSeqWalk / spiderSeqRun sequence
        names, else the model's ACT_IDLE / ACT_WALK / ACT_RUN; a model with
        no walk or run sequence gets a small body bob while it moves
        (client, NW2Bool rhylib_bob) instead of sliding
      - turning: its body turns at spiderTurnRate degrees a second
      - main gun (style "shell", ENT:StyleFire): one slow explosive shell
        (entities/rhylib_spider_shell.lua) every spiderShellInterval s at
        a target in sight, led by its speed, only once its body points
        within spiderAimCone of it and the way from the gun is clear (a
        wall in the way for 2 s: it steps aside). At most spiderShellMax
        shells fly at once. No bolts at all (FireAtPos and firing into
        smoke do nothing).
      - closer than spiderShellMin: it backs off, walking and facing the
        target, and holds fire; with nowhere to back off, or while an
        order keeps it in place (defending, guarding, following,
        reinforcement steps, aggression 2), it fires anyway. A charge
        (aggression 4-5) stops short of that range, inside its area.
      - muzzle: the spiderMuzzleAttach attachment, else spiderMuzzleFwd /
        spiderMuzzleUp from its feet
    Health, damage rules, poppers, no knockdown and no cover are the B2's
    (kind.big, b2Health). Reaction time, aggression, squads, orders and
    stealth are the shared brain's.
]]

AddCSLuaFile()

local Base = baseclass.Get("rhylib_b1")

ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "DSD1 dwarf spider droid"
ENT.Category = "Rhy's Spider droids"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "spider"
ENT.QuietAnims = true   -- (the base's animation line and warning: this file prints its own)
-- (a walker built on this file, e.g. rhylib_crab, sets its own: config
-- keys <CfgPrefix>Model / Height / Scale / Seq* / TurnRate / Muzzle*,
-- hull half-width HullHalf)
ENT.CfgPrefix = "spider"
ENT.HullHalf = 20

-- Animation choices per model: [model] = { idle, walk, run, noWalk },
-- each { seq = n } or { act = ACT_* }.
local animsOf = {}
local ACTS = {
    idle = { ACT_IDLE, ACT_IDLE_ANGRY },
    walk = { ACT_WALK, ACT_WALK_AIM, ACT_RUN },
    run = { ACT_RUN, ACT_RUN_AIM, ACT_WALK },
}
local SEQ_KEY = { idle = "SeqIdle", walk = "SeqWalk", run = "SeqRun" }

local function resolve(ent)
    local D = Rhylib.Droids
    local mdl = ent:GetModel() or ""
    local pre = ent.CfgPrefix
    local key = pre .. "|" .. mdl .. "|" .. tostring(D.Cfg(pre .. "SeqIdle")) .. "|" .. tostring(D.Cfg(pre .. "SeqWalk")) .. "|" .. tostring(D.Cfg(pre .. "SeqRun"))
    local a = animsOf[key]
    if a then return a end
    a = {}
    for k, cfgKey in pairs(SEQ_KEY) do
        local name = D.Cfg(pre .. cfgKey)
        local seq = isstring(name) and name ~= "" and ent:LookupSequence(name) or -1
        if seq and seq >= 0 then
            a[k] = { seq = seq }
        else
            for _, act in ipairs(ACTS[k]) do
                if act and ent:SelectWeightedSequence(act) > 0 then a[k] = { act = act } break end
            end
        end
    end
    a.noWalk = not (a.walk or a.run)
    a.idle = a.idle or { act = ACT_IDLE }
    a.walk = a.walk or a.run or a.idle
    a.run = a.run or a.walk
    animsOf[key] = a
    if SERVER then
        Rhylib.Print("droids", "%s %s: %d sequences; walking animation %s", pre, mdl, ent:GetSequenceCount(), a.noWalk and "none (body bob)" or "found")
    end
    return a
end

-- ENT:SpiderMuzzle() -> where shells leave from (shared).
local attOf = {}
function ENT:SpiderMuzzle()
    local D = Rhylib.Droids
    local pre = self.CfgPrefix
    local name = D.Cfg(pre .. "MuzzleAttach")
    if isstring(name) and name ~= "" then
        local key = (self:GetModel() or "") .. "|" .. name
        local id = attOf[key]
        if id == nil then
            id = self:LookupAttachment(name) or 0
            attOf[key] = id
        end
        if id > 0 then
            local at = self:GetAttachment(id)
            if at then return at.Pos end
        end
    end
    return self:GetPos() + self:GetForward() * D.Cfg(pre .. "MuzzleFwd") + Vector(0, 0, D.Cfg(pre .. "MuzzleUp"))
end

-- ENT:SpiderHull(h, scale): the hull h units tall; if the engine scaled
-- the stored bounds by the model scale (height off by over 10%), set
-- them again divided by it (server).
function ENT:SpiderHull(h, scale)
    local w = self.HullHalf or 20
    local mins, maxs = Vector(-w, -w, 0), Vector(w, w, h)
    self:SetCollisionBounds(mins, maxs)
    if scale > 0 and math.abs(self:OBBMaxs().z - h) > h * 0.1 then
        self:SetCollisionBounds(mins / scale, maxs / scale)
    end
end

function ENT:Initialize()
    if CLIENT then
        self.Training = self:Kind().training
        return
    end
    Base.Initialize(self)
    if self.overCap then return end
    local D = Rhylib.Droids
    local pre = self.CfgPrefix
    local h = math.max(D.Cfg(pre .. "Height"), 16)
    -- Size: spiderScale, or fitted to spiderHeight.
    local scale = D.Cfg(pre .. "Scale")
    if not (scale and scale > 0) then
        local mn, mx = self:GetModelBounds()
        local mh = mn and mx and (mx.z - mn.z) or 0
        scale = mh > 1 and math.Clamp(h / mh, 0.25, 4) or 1
    end
    if math.abs(scale - 1) > 0.01 then self:SetModelScale(scale, 0) end
    self:SpiderHull(h, scale)
    -- (again a moment later, in case the scale lands after this tick)
    timer.Simple(0.1, function() if IsValid(self) then self:SpiderHull(h, scale) end end)
    self.eyeOff = Vector(0, 0, math.max(h * 0.85, 12))
    self.loco:SetMaxYawRate(D.Cfg(pre .. "TurnRate"))
    -- (the shared brain reads self.anims.shoot / throw: none here)
    self.spAnims = resolve(self)
    self.anims = { idle = ACT_IDLE, walk = ACT_WALK, run = ACT_RUN }
    self:SetNW2Bool("rhylib_bob", self.spAnims.noWalk)
    self.spCur = nil
    self.nextShell = CurTime() + math.Rand(1, 2)
end

if SERVER then
    function ENT:Eye()
        return self:GetPos() + (self.eyeOff or Vector(0, 0, 54))
    end

    function ENT:Muzzle()
        return self:SpiderMuzzle()
    end

    -- No bolts: it only fires shells.
    function ENT:FireAtPos() end
    function ENT:SuppressSmoke() return false end

    -- How many shells fly now (all spiders).
    local function shellCount(D)
        local n = 0
        for s in pairs(D.spiderShells or {}) do
            if IsValid(s) then n = n + 1 else D.spiderShells[s] = nil end
        end
        return n
    end

    local function speedOf(t)
        if t:IsNextBot() and t.loco then return t.loco:GetVelocity() end
        return t:GetVelocity()
    end

    local lof = {}
    local lofData = { mask = MASK_SHOT, output = lof }
    local function passDroids(e) return not e.IsRhylibDroid end
    lofData.filter = passDroids
    -- Is the way from the gun to p clear (the shell's own trace: walls,
    -- props and structures count, droids don't)? The target itself counts as clear.
    local function clear(from, p, t)
        lofData.start, lofData.endpos = from, p
        util.TraceLine(lofData)
        return not lof.Hit or lof.Entity == t or lof.Fraction > 0.97
    end

    -- Style "shell": see the header. Returns when to look again.
    function ENT:StyleFire(t, now, st)
        local D = Rhylib.Droids
        self.loco:SetMaxYawRate(D.Cfg("spiderTurnRate"))
        if now < (self.nextShell or 0) then return self.nextShell end
        local pos, tp = self:GetPos(), t:GetPos()
        local d = math.sqrt((pos.x - tp.x) ^ 2 + (pos.y - tp.y) ^ 2)
        -- Too close: backing off (PlanMove) unless cornered.
        if d < D.Cfg("spiderShellMin") and (self.spCornerUntil or 0) < now then return now + 0.2 end
        -- Body pointing at it.
        local f = self:GetForward()
        f.z = 0
        local to = tp - pos
        to.z = 0
        if to:LengthSqr() > 1 and f:LengthSqr() > 0 then
            to:Normalize()
            f:Normalize()
            if f:Dot(to) < math.cos(math.rad(D.Cfg("spiderAimCone"))) then return now + 0.1 end
        end
        if not self:CanSee(t) then return now + 0.2 end
        if shellCount(D) >= D.Cfg("spiderShellMax") then return now + 0.5 end
        -- Aim low (a near miss lands by them), lead by the flight time.
        local from = self:Muzzle()
        local speed = math.max(D.Cfg("spiderShellSpeed"), 50)
        local vel = speedOf(t)
        local low = tp + Vector(0, 0, 20)
        local fly = math.min(from:Distance(low) / speed, 3)
        local aim = low + vel * fly
        fly = math.min(from:Distance(aim) / speed, 3)
        aim = low + vel * fly
        if not clear(from, aim, t) then
            aim = t:WorldSpaceCenter() + vel * fly
            if not clear(from, aim, t) then
                -- (a wall in front of the gun for a while: step aside, as for a friend in the line)
                self.spBlockedAt = self.spBlockedAt or now
                if now - self.spBlockedAt > 2 then
                    if now >= (self.blockedUntil or 0) then self.stepSide = -(self.stepSide or 1) end
                    self.blockedUntil = now + 1.2
                    self.planAt = 0
                    self.spBlockedAt = nil
                end
                return now + 0.3
            end
        end
        self.spBlockedAt = nil
        -- (aim like the others: a commander's boost tightens it, being
        -- suppressed or rattled by a commander's death widens it)
        local spread = D.Cfg("spiderShellSpread") * (D.SuppressMult and D.SuppressMult(self) or 1)
        if D.Boosted(self) then spread = spread * D.Cfg("cmdSpread") end
        local miss = VectorRand() * spread * from:Distance(aim) / 1000
        miss.z = 0
        aim = aim + miss
        local s = ents.Create("rhylib_spider_shell")
        if not IsValid(s) then return now + 1 end
        s:SetPos(from)
        s.vel = (aim - from):GetNormalized() * speed
        s.owner = self
        s.training = self.Training
        s:SetOwner(self)
        s:Spawn()
        self:EmitSound("weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_02.ogg", 110, 75)
        local m = 1
        if D.Boosted(self) then m = m * D.Cfg("cmdPause") end
        if self.lastStand then m = m * D.Cfg("lastStandPause") end
        self.nextShell = now + math.max(D.Cfg("spiderShellInterval"), 0.5) * math.Rand(0.9, 1.15) * m
        return self.nextShell
    end

    -- Moving while fighting: the shared plan, but never closer than
    -- spiderShellMin; closer than that it backs off (cornered: holds).
    local BACK = { 0, 45, -45, 90, -90 }
    local backHullTr = {}
    local backHull = { mask = MASK_NPCSOLID, output = backHullTr, mins = Vector(-20, -20, 0), maxs = Vector(20, 20, 50) }
    -- A straight walk to goal with the spider's own hull (and ground under it).
    local function straightBack(self, goal)
        backHull.start = self:GetPos() + Vector(0, 0, 20)
        backHull.endpos = goal + Vector(0, 0, 20)
        backHull.filter = self
        util.TraceHull(backHull)
        if backHullTr.Hit then return false end
        local g = util.TraceLine({ start = goal + Vector(0, 0, 20), endpos = goal - Vector(0, 0, 80), mask = MASK_SOLID_BRUSHONLY })
        return g.Hit
    end
    function ENT:PlanMove(t)
        if self:Retreating() or self.artillery then return Base.PlanMove(self, t) end
        local D = Rhylib.Droids
        local minR = D.Cfg("spiderShellMin")
        local pos, tp = self:GetPos(), t:GetPos()
        local away = pos - tp
        away.z = 0
        local d = away:Length()
        -- (orders first: defending, guarding, following, reinforcement
        -- steps and falling back keep their own plan; it fires anyway)
        local ordered = self.defending or self.guarding or self.mode == "follow" or self.advanceTo or self:Aggro() == 2
        if d < minR and ordered then
            self.spCornerUntil = CurTime() + 1.5
            return Base.PlanMove(self, t)
        end
        if d < minR and d > 1 then
            away:Normalize()
            local yaw = away:Angle().y
            for _, off in ipairs(BACK) do
                local dir = Angle(0, yaw + off, 0):Forward()
                local goal = self:InArea(pos + dir * 250)
                if goal:DistToSqr(pos) > 60 * 60 and straightBack(self, goal) then
                    self.spCornerUntil = nil
                    return goal, false
                end
            end
            self.spCornerUntil = CurTime() + 1.5   -- (nowhere to go: fire anyway)
            return nil
        end
        local goal, run, face = Base.PlanMove(self, t)
        -- (a side-step around something in the way is never cut short)
        if goal and (self.blockedUntil or 0) <= CurTime() then
            local keep = minR * 1.2
            local g = goal - tp
            g.z = 0
            if g:Length() < keep then
                -- (a charge stops at its shelling range)
                if d <= keep then return nil end
                goal = tp + away:GetNormalized() * keep
                goal.z = pos.z
                goal = self:InArea(goal)
            end
        end
        return goal, run, face
    end

    -- Animation: see the header. Every tick (NextBot callback).
    function ENT:BodyUpdate()
        local A = self.spAnims
        if not A then return end
        local speed = self.loco:GetVelocity():Length2D()
        local want = speed > 10 and (speed > 70 and A.run or A.walk) or A.idle
        local cur = self.spCur
        local same = cur and cur.seq == want.seq and cur.act == want.act
        if not same or (want.act and self:GetActivity() ~= want.act) then
            self.spCur = want
            if want.seq then self:ResetSequence(want.seq) else self:StartActivity(want.act) end
        end
        if speed > 10 and not A.noWalk then self:BodyMoveXY() else self:FrameAdvance() end
    end
end

if CLIENT then
    local bobPos = Vector()
    -- A model with no walk animation bobs a little while it moves.
    function ENT:Draw()
        if not self:GetNW2Bool("rhylib_bob", false) then
            self:DrawModel()
            return
        end
        local pos = self:GetPos()
        local frame = FrameNumber()
        if self.bobFrame ~= frame then
            -- (once per frame, however many times it is drawn)
            self.bobFrame = frame
            local now = CurTime()
            local dt = now - (self.bobT or now)
            local sp = 0
            if self.bobLast and dt > 0 then sp = math.min(pos:Distance(self.bobLast) / dt, 400) end
            self.bobLast, self.bobT = pos, now
            self.bobSp = Lerp(math.Clamp(FrameTime() * 8, 0, 1), self.bobSp or 0, sp)
            self.bobPhase = ((self.bobPhase or 0) + FrameTime() * (4 + self.bobSp * 0.06)) % (math.pi * 2)
        end
        local moving = math.Clamp(self.bobSp / 60, 0, 1)
        if moving < 0.02 then
            self:DrawModel()
            return
        end
        bobPos:Set(pos)
        bobPos.z = bobPos.z + math.abs(math.sin(self.bobPhase)) * 3 * moving
        self:SetRenderOrigin(bobPos)
        self:DrawModel()
        self:SetRenderOrigin()
    end
end
