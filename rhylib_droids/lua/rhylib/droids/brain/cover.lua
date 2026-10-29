--[[
    Droid / clone brain part (server): Cover: when to take it, finding a hiding spot (navmesh hiding spots out of the threat's sight), blind fire there, leaving it.
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D
    local alive = env.alive
    local valid = env.valid

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

    -- ENT:WantsCover() -> should it take cover now (see the header)?
    function ENT:WantsCover()
        if not self:Kind().cover or not self.threatPos or CurTime() < (self.coverReady or 0) then return false end
        if self.guarding then return false end   -- (stands over a downed player)
        if self:Retreating() then return false end   -- (retreat runs its own way: away)
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
        return n >= (L == 2 and 1 or D.Cfg("coverHits"))   -- (falling back: cover sooner)
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

    -- ENT:TakeCover(threat, far) -> true if it got there. Run to cover,
    -- blind fire from it for a while, then fight again. Yields.
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
        -- Clones with no cover to reach crouch where they are.
        if not ok and self.IsRhylibClone then self.crouchUntil = CurTime() + D.Cfg("ctCrouchTime") end
        -- (the one pull-back only counts once it happened)
        if far and ok then
            self.retreatPending = nil
            self.retreated = true
        end
        return ok
    end

end
