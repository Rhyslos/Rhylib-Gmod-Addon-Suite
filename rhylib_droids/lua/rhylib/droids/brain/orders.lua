--[[
    Droid / clone brain part (server): Orders: the mode area (guard / patrol / attack), walk or run (marching), the fallback point, clone doctrine (the odds), and moving while firing (PlanMove, StraightTo, StepMove, Facing).
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D
    local ADVANCE_DIST = env.ADVANCE_DIST

    --------------------------------------------------------------------------
    -- Orders: mode area, aggression, moving while firing
    --------------------------------------------------------------------------

    -- The area a guard / patrol droid stays in (nil = attack: anywhere).
    function ENT:AreaRadius()
        if self.mode == "patrol" then return D.Cfg("patrolRadius") end
        if self.mode == "attack" or self.mode == "roam" or self.mode == "retreat" then return nil end
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

    -- ENT:SetPace(run): run speed, or walk (x walkMult).
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

    -- Where to fall back to (aggression 2, "Fall back"): a fallback
    -- marker, else home.
    function ENT:FallbackPoint()
        -- (a player's followers fall back to them)
        if (self.doctrine == 2 or self.orderAggro == 2) and self.leader and not self.leaderNpc and self.home then return self.home end
        if self.doctrine == 2 and self.doctrineFallback then return self.doctrineFallback end
        return self.fallback or self.home
    end

    -- Clones' doctrine: outnumbered → fall back, even → hold the
    -- line, outnumbering → charge. Once a second while fighting.
    function ENT:UpdateDoctrine()
        if not self.IsRhylibClone or not D.CloneOdds then return end
        local now = CurTime()
        if (self.doctrineAt or 0) > now then return end
        self.doctrineAt = now + 1
        if self.guarding or self.reviveTarget or self.orderAggro or self.mode == "retreat" or not IsValid(self.target)
            or math.Round(tonumber(D.Cfg("cloneAggro")) or 3) == 1 then
            self.doctrine = nil   -- (guards, medics and followers keep to their job)
            return
        end
        local f, e, mid = D.CloneOdds(self)
        if e <= 0 then self.doctrine = nil return end
        local r = f / e
        if r < D.Cfg("ctFallBackOdds") then
            if self.doctrine ~= 2 or not self.doctrineFallback then
                local away = self:GetPos() - (mid or self.target:GetPos())
                away.z = 0
                if away:LengthSqr() < 1 then away = -self:GetForward() end
                away:Normalize()
                local to = self:GetPos() + away * 600
                self.doctrineFallback = D.GroundAt and D.GroundAt(to) or to
            end
            self.doctrine = 2   -- (fall back: relocate, not a full retreat)
        elseif r > D.Cfg("ctChargeOdds") then
            self.doctrine = 5
        else
            self.doctrine = 3
        end
    end

    -- ENT:PlanMove(t) -> goal (or nil = stay), run, faceGoal. Where to move
    -- while fighting t. Checked in order: artillery (never), a friend in
    -- the line of fire (step aside), retreat, popper charge, back to a
    -- downed player / the officer, reinforcement steps, then by aggression:
    -- 1-2 fall back / back off, 3 close in beyond ADVANCE_DIST, 4-5 go at
    -- the target (4 walks if it CanMarch, else runs). Guards and patrols
    -- keep goals inside their area (InArea).
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
        -- Retreating: its own plan (away from the enemy).
        self:RetreatCheckClear()
        if self:Retreating() then return self:RetreatPlan(t) end
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
        if L <= 2 then
            -- Fall back: to the fallback point while firing; there, fights,
            -- never pushes, backs off from anyone close.
            local fb = self:FallbackPoint()
            if fb and pos:DistToSqr(fb) > 150 * 150 then
                goal, run = fb, false
            elseif d < 600 then
                goal, run = pos + (pos - tp):GetNormalized() * 220, false
            end
        elseif L == 3 then
            if d > ADVANCE_DIST then goal, run = pos + (tp - pos):GetNormalized() * 300, false end
        else
            if d > 260 then
                goal = tp
                run = L >= 5 or not self:CanMarch()
            end
        end
        if goal and not (L == 2 and goal == self:FallbackPoint()) then goal = self:InArea(goal) end
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
            local goal, run, face = self:PlanMove(t)
            self.moveGoal = goal
            self.moveFace = face   -- (retreating: turns its back and runs)
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
            self.loco:FaceTowards(self.moveFace and goal or t:GetPos())
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
            -- Falling back keeps the gun on the enemy (retreat runs facing the way).
            if not self.moveFace and self:Aggro() == 2 then self.loco:FaceTowards(t:GetPos()) end
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

end
