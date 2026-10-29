--[[
    Droid / clone brain part (server): Retreat (aggression 1 / mode retreat): legs away from the threat, standing to fight between them, the last stand, clearing the alarm.
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D

    --------------------------------------------------------------------------
    -- Retreat: mode "retreat" or aggression 1. Leave
    -- the front, nowhere in particular: run a leg away from the enemy, turn
    -- and fight a few seconds, run on. An enemy close by or hits while
    -- running = turn and fight first (so they don't just get shot in the
    -- back). Nowhere left to run = last stand: hold, no cover, fire faster.
    -- Once nobody has been seen or shot at them for retreatClear they hold
    -- where they ended up.
    --------------------------------------------------------------------------

    -- ENT:Retreating() -> retreat mode or aggression 1 (never while guarding
    -- a downed player, reviving, or artillery).
    function ENT:Retreating()
        if self.guarding or self.reviveTarget or self.artillery then return false end
        return self.mode == "retreat" or self:Aggro() == 1
    end

    -- Last time there was an enemy to get away from.
    function ENT:RetreatAlarm()
        return math.max(self.threatAt or 0, self.lastSeenAt or 0)
    end

    function ENT:RetreatThreat(t)
        if IsValid(t) then return t:GetPos() end
        local now = CurTime()
        if self.threatPos and now - (self.threatAt or 0) < 10 then return self.threatPos end
        if self.lastSeen and now - (self.lastSeenAt or 0) < 10 then return self.lastSeen end
        return self.rt and self.rt.from
    end

    function ENT:SetLastStand(on)
        on = on and true or nil
        if self.lastStand == on then return end
        self.lastStand = on
        self:SetNW2String("rhylib_dmode", on and "laststand" or (self.buddyRoam and "roam") or self.mode or "guard")
    end

    -- Hits within secs (from OnInjured's list).
    function ENT:HitsWithin(secs)
        local n, now = 0, CurTime()
        for _, h in ipairs(self.hits or {}) do
            if now - h <= secs then n = n + 1 end
        end
        return n
    end

    -- The next spot to run to: away from the threat (blended with the
    -- group's shared way out), turning up to 70 degrees to find ground
    -- that is further from the threat. Nil = nowhere to go.
    local LEG_TURNS = { 0, 35, -35, 70, -70 }
    local WIDE_TURNS = { 0, 50, -50, 105, -105 }
    function ENT:PickRetreatLeg(threat)
        local pos = self:GetPos()
        local away = threat and (pos - threat) or -self:GetForward()
        away.z = 0
        if away:LengthSqr() < 1 then away = -self:GetForward() away.z = 0 end
        away:Normalize()
        local dir = away
        -- (the group's way out, unless it now leads toward the enemy)
        if self.retreatDir and self.retreatDir:Dot(away) > 0 then
            dir = self.retreatDir * 0.6 + away * 0.4
            dir.z = 0
            if dir:LengthSqr() < 0.01 then dir = away end
            dir:Normalize()
        end
        local leg = D.Cfg("retreatLeg") * math.Rand(0.8, 1.2)
        local myD = threat and pos:Distance(threat) or 0
        local mesh = navmesh and navmesh.IsLoaded and navmesh.IsLoaded() and navmesh.GetNearestNavArea
        local function try(d, turns)
            for _, turn in ipairs(turns) do
                local a = d:Angle()
                a.y = a.y + turn
                local to = pos + a:Forward() * leg
                if mesh then
                    local area = navmesh.GetNearestNavArea(to, false, 250, false, true)
                    to = IsValid(area) and area:GetClosestPointOnArea(to) or nil
                elseif not self:OpenGround(to) then
                    to = nil
                end
                if to and to:DistToSqr(pos) > 200 * 200 and (not threat or to:Distance(threat) > myD + 150) then return to end
            end
        end
        return try(dir, LEG_TURNS) or try(away, WIDE_TURNS)
    end

    -- No navmesh: walls and ground only (other NPCs don't block a retreat).
    local openTr = {}
    local openHull = { mask = MASK_SOLID_BRUSHONLY, output = openTr, mins = Vector(-13, -13, 0), maxs = Vector(13, 13, 46) }
    function ENT:OpenGround(goal)
        openHull.start = self:GetPos() + Vector(0, 0, 20)
        openHull.endpos = goal + Vector(0, 0, 20)
        util.TraceHull(openHull)
        if openTr.Hit then return false end
        local g = util.TraceLine({ start = goal + Vector(0, 0, 20), endpos = goal - Vector(0, 0, 80), mask = MASK_SOLID_BRUSHONLY })
        return g.Hit
    end

    -- No navmesh: walk a straight leg (yields; stops when a target shows up).
    function ENT:WalkStraight(goal, secs)
        local stop = CurTime() + secs
        while CurTime() < stop and self:GetPos():DistToSqr(goal) > 60 * 60 do
            self.loco:Approach(goal, 1)
            self.loco:FaceTowards(goal)
            if self.loco:IsStuck() then
                self:HandleStuck()
                return false
            end
            if self:Look() then return true end
            coroutine.yield()
        end
        return true
    end

    -- Turn and fight for a few seconds where it stands.
    function ENT:RetreatStand(rt)
        local now = CurTime()
        rt.phase, rt.untilT = "stand", now + D.Cfg("retreatStand") * math.Rand(0.8, 1.25)
        if self.IsRhylibClone then self.crouchUntil = rt.untilT end
        self.home = self:GetPos()   -- (never walks back to the old post)
    end

    -- Where to go now: goal, run, face the goal (nil = stay and fight).
    function ENT:RetreatPlan(t)
        if self.lastStand then
            if self.IsRhylibClone then self.crouchUntil = CurTime() + 1 end
            return nil
        end
        local now = CurTime()
        local rt = self.rt
        if not rt then
            rt = { phase = "stand", untilT = 0, stuck = 0, origin = self:GetPos() }
            self.rt = rt
        end
        local threat = self:RetreatThreat(t)
        if threat then rt.from = threat end
        local pos = self:GetPos()
        local close = D.Cfg("retreatClose")
        if rt.phase == "run" then
            -- An enemy close or hits while running: turn and fight back first.
            if IsValid(t) and (pos:DistToSqr(t:GetPos()) < close * close or self:HitsWithin(1.2) >= 2) then
                self:RetreatStand(rt)
                return nil
            end
            if pos:DistToSqr(rt.leg) < 80 * 80 or now > rt.untilT then
                if IsValid(t) then
                    self:RetreatStand(rt)
                    return nil
                end
                rt.phase, rt.untilT = "stand", 0   -- (nobody in sight: straight on)
            elseif now > rt.checkAt then
                -- Not getting anywhere: another way; three in a row = cornered.
                local moved = pos:DistToSqr(rt.checkPos) > 40 * 40
                -- (waiting for a route search isn't being stuck)
                local waiting = IsValid(t) and (self.needPath or not (self.moveStraight or self.pathGoal))
                rt.checkAt, rt.checkPos = now + 1.5, pos
                if moved or waiting then
                    rt.stuck = 0
                else
                    rt.stuck = rt.stuck + 1
                    if rt.stuck >= 3 then
                        self:SetLastStand(true)
                        return nil
                    end
                    rt.phase, rt.untilT = "stand", 0
                end
            end
            if rt.phase == "run" then return rt.leg, true, true end
        end
        -- Standing: fight out the stand (longer while someone is right on it).
        if IsValid(t) and now < rt.untilT then return nil end
        if IsValid(t) and pos:DistToSqr(t:GetPos()) < (close * 0.6) ^ 2 then
            rt.untilT = now + 1
            return nil
        end
        local leg = self:PickRetreatLeg(threat)
        if not leg then
            -- (twice in a row = cornered; the first time it fights a moment more)
            rt.noLeg = (rt.noLeg or 0) + 1
            if rt.noLeg >= 2 then self:SetLastStand(true) end
            rt.untilT = now + 1.5
            return nil
        end
        rt.noLeg = 0
        rt.phase, rt.leg, rt.untilT = "run", leg, now + 6
        rt.checkAt, rt.checkPos = now + 1.5, pos
        return leg, true, true
    end

    -- Retreat over (nobody about for retreatClear): hold where it is.
    -- Also ends when it isn't retreating any more (aggression raised,
    -- another order, guarding a downed player).
    function ENT:RetreatCheckClear()
        if not (self.rt or self.lastStand) then return end
        local still = self:Retreating()
        if still and CurTime() - self:RetreatAlarm() < D.Cfg("retreatClear") then return end
        self.rt = nil
        self:SetLastStand(false)
        if still then
            self.retreatDir = nil
            self.lastSeen = nil   -- (no walking back to where the enemy was)
            if not self.leader then self.home = self:GetPos() end
        end
    end

    -- Out of sight and far enough from where this retreat began: stop
    -- there (they stay roughly in the same area).
    function ENT:RetreatFarEnough()
        local rt = self.rt
        return rt and rt.origin and self:GetPos():DistToSqr(rt.origin) > D.Cfg("retreatMax") ^ 2
    end

end
