--[[
    Droid / clone brain part (server): keeping formation in a squad
    (sv_40_squads.lua has the squads themselves).

    ENT:InSquadFollow() -> is it a squad member that should follow the
    leader now (not the leader, not guarding a downed player, not
    following an officer, not artillery)?
    ENT:FollowSquad() -> keeps its slot for about a second (yields; stops
    early when a target shows up). Each step (StepFormation): every 0.4-0.5
    s it picks how to reach the slot: straight there when a hull trace says
    the way is clear (only re-checked when the slot moved), else straight
    to a point on the leader's trail behind it (single file through doors
    and corridors), else a navmesh route (within the per-tick budget). It
    walks at the leader's pace, faster to catch up, runs when far behind,
    and keeps squadGap units from its squad mates. In its slot it faces the
    way the squad faces.
    ENT:SquadLateral(dir) -> how far to the side of a charge this member
    goes (its slot's sideways offset), used by PlanMove.
    ENT:LeaderPace() -> the leader's walking speed now: slower while its
    members lag behind (squad.lag > squadWait), used by Go and StepMove.
]]

return function(ENT, env)
    local D = env.D

    function ENT:InSquadFollow()
        local sq = self.squad
        if not sq or sq.leader == self or not IsValid(sq.leader) then return false end
        if self.guarding or self.leader or self.artillery or self.reviveTarget then return false end
        return true
    end

    -- Room between squad mates: a push away from any closer than squadGap.
    local function separation(self, sq, goal)
        local gap = D.Cfg("squadGap")
        local pos = self:GetPos()
        local push = Vector(0, 0, 0)
        for _, m in ipairs(sq.list) do
            if m ~= self and IsValid(m) then
                local d = goal - m:GetPos()
                d.z = 0
                local len = d:Length()
                if len < gap then
                    if len < 1 then d = pos - m:GetPos() d.z = 0 len = math.max(d:Length(), 1) end
                    push = push + d / len * (gap - len)
                end
            end
        end
        return goal + push
    end

    -- One tick of keeping formation; false = give up for now.
    function ENT:StepFormation()
        local sq = self.squad
        local lead = sq.leader
        local now = CurTime()
        local pos = self:GetPos()
        if now >= (self.fmAt or 0) then
            self.fmAt = now + math.Rand(0.4, 0.5)
            local slot = D.SlotPos(self)
            if not slot then return false end
            slot = separation(self, sq, slot)
            local dist = pos:Distance(slot)
            -- Pace: the leader's, faster to catch up, running when far behind.
            local base = D.Cfg(self:Kind().speed)
            local walk = base * D.Cfg("walkMult")
            local lspeed = lead.paceSpeed or walk   -- (the leader's chosen pace, not its live speed: a reviving or waiting leader is slow)
            local run = dist > 400 or lead.running
            local speed = run and base or math.min(base, math.max(lspeed, walk) * (dist > 120 and D.Cfg("squadCatchUp") or 1))
            self.loco:SetDesiredSpeed(math.max(speed, 40))
            self.running = run
            if dist < 36 then
                self.fmGoal, self.fmHow = nil, nil
            else
                -- (re-check the straight way only when the slot moved)
                -- (fmSlot = where the straight way was last checked to)
                local moved = not self.fmSlot or self.fmSlot:DistToSqr(slot) > 70 * 70 or self.fmHow ~= "straight"
                if self.fmHow == "straight" and not moved then
                    self.fmGoal = slot
                elseif dist < 900 and self:StraightTo(slot) then
                    self.fmSlot = slot
                    self.fmGoal, self.fmHow = slot, "straight"
                else
                    local crumb = D.TrailPoint(sq, math.min((self.slotIdx or 1) * 2, 38))
                    if crumb and crumb:DistToSqr(pos) > 40 * 40 and crumb:DistToSqr(pos) < 700 * 700 and self:StraightTo(crumb) then
                        self.fmGoal, self.fmHow = crumb, "trail"
                    else
                        if self.fmHow ~= "path" or not self.pathGoal or self.pathGoal:DistToSqr(slot) > 150 * 150 then self.needPath = true end
                        self.fmGoal, self.fmHow = slot, "path"
                    end
                end
            end
        end
        local goal = self.fmGoal
        if not goal then
            -- In its slot: face the way the squad faces (or the leader's way).
            local yaw = sq.heading or lead:GetAngles().y
            self.loco:FaceTowards(pos + Angle(0, yaw, 0):Forward() * 100)
            return true
        end
        if self.fmHow ~= "path" then
            self.loco:Approach(goal, 1)
            self.loco:FaceTowards(goal)
            if self.loco:IsStuck() then
                self:HandleStuck()
                self.fmHow, self.fmAt = nil, 0
            end
            return true
        end
        local path = self.path
        if not path then
            path = Path("Follow")
            path:SetMinLookAheadDistance(300)
            path:SetGoalTolerance(40)
            self.path = path
        end
        if self.needPath and D.TakeBudget() then
            self.needPath = false
            if path:Compute(self, goal) then
                self.pathGoal = goal
            else
                self.pathGoal = nil
                self.fmAt = now + 1.5   -- (no route: don't ask again at once)
                return true
            end
        end
        if self.pathGoal and path:IsValid() then
            path:Update(self)
            self:OpenDoors()
            if self.loco:IsStuck() then
                self:HandleStuck()
                self.pathGoal, self.fmAt = nil, 0
            end
        end
        return true
    end

    -- Keep formation for about a second. Yields.
    function ENT:FollowSquad()
        local stop = CurTime() + math.Rand(0.8, 1.2)
        while CurTime() < stop and self:InSquadFollow() do
            if self:Look() then return end
            if not self:StepFormation() then break end
            coroutine.yield()
        end
    end

    -- Sideways offset for a squad member charging dir (a normal, flat).
    function ENT:SquadLateral()
        local sq = self.squad
        if not sq or sq.leader == self then return 0 end
        if sq.formation == "column" then
            local _, r = D.SlotOffset("wedge", self.slotIdx or 1, #sq.list)
            return r
        end
        local _, r = D.MemberOffset(self)
        return r
    end

    -- The leader's speed now: slower while members lag behind.
    function ENT:LeaderPace(speed)
        local sq = self.squad
        if sq and sq.leader == self and (sq.lag or 0) > D.Cfg("squadWait") and not self.running then
            return speed * 0.55
        end
        return speed
    end
end
