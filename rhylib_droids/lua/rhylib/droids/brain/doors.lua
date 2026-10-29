--[[
    Droid / clone brain part (server): Moving: opening unlocked doors on the way, ENT:Go along a navmesh path, turning to face.
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D

    --------------------------------------------------------------------------
    -- Moving
    --------------------------------------------------------------------------

    -- Doors: every NPC (clones and droids) opens an unlocked door in front of it while
    -- walking. Checked every 0.3 s, one short hull trace.
    local DOORS = { prop_door_rotating = true, func_door = true, func_door_rotating = true }
    local DOOR_MINS, DOOR_MAXS = Vector(-10, -10, -10), Vector(10, 10, 10)
    function ENT:OpenDoors()
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

    -- ENT:Go(pos, maxTime, watch) -> false if no route (or stuck), else true.
    -- Walk a path for up to maxTime; stop early when a target shows up
    -- (watch) or self.redirect is set. Needs a navmesh. Yields.
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

    -- ENT:Face(pos, t): turn to face a point for t seconds. Yields.
    function ENT:Face(pos, t)
        local stop = CurTime() + t
        while CurTime() < stop do
            self.loco:FaceTowards(pos)
            coroutine.yield()
        end
    end

end
