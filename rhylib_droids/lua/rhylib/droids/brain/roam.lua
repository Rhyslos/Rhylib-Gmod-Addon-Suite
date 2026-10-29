--[[
    Droid / clone brain part (server): Idling, waiting for a route, following a leader (player or NPC) and the home spot beside a downed player being guarded.
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D
    local State = Rhylib.State

    -- ENT:Idle(secs): waits up to secs, waking early when hit (or
    -- self.woken is set) or someone comes in sight. Yields.
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
        if State.IsDown(l) then return end
        local yaw = Angle(0, npc and l:GetAngles().y or l:EyeAngles().y, 0)
        local s = self.followSlot or Vector(-120, 0, 0)
        self.home = l:GetPos() + yaw:Forward() * s.x + yaw:Right() * s.y
    end

    -- Home for this moment: standing over a downed player (sv_30_clones
    -- picks guards), else beside the officer it follows, else unchanged.
    function ENT:UpdateHome()
        local p = self.guardDowned
        if p then
            if IsValid(p) and p:Alive() and State.IsDown(p) then
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

end
