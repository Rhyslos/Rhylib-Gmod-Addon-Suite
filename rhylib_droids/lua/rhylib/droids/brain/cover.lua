--[[
    Droid / clone brain part (server): Cover: when to take it, finding a
    spot (navmesh hiding spots and spots behind nearby walls and props, out
    of the threat's sight, scored), fighting from it (aimed bursts over
    low cover, peeking out from full cover, blind fire), moving on when
    flanked, leaving it.
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
        self.coverKey, self.coverSpot = nil, nil
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
        -- (falling back: cover sooner; clones take it sooner than droids)
        return n >= (L == 2 and 1 or (self.IsRhylibClone and D.Cfg("ctCoverHits") or D.Cfg("coverHits")))
    end

    -- Is anyone in the squad (or another NPC's cover spot) already right
    -- there? Two NPCs don't crowd one bit of wall.
    local function crowded(self, v)
        local sq = self.squad
        if sq then
            for _, m in ipairs(sq.list) do
                if m ~= self and IsValid(m) and m.coverSpot and m.coverSpot:DistToSqr(v) < 70 * 70 then return true end
            end
        end
        local holder = D.coverTaken[D.SpotKey(v)]
        return IsValid(holder) and holder ~= self
    end

    -- (walls and props block; players and NPCs don't)
    local trOut = {}
    local function solidOnly(e) return not (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) end
    local sightTr = { mask = MASK_SOLID, output = trOut, filter = solidOnly }
    local function blocked(a, b)
        sightTr.start, sightTr.endpos = a, b
        util.TraceLine(sightTr)
        return trOut.Hit
    end

    -- ENT:FindCover(threat, far) -> spot, low (or nil). A spot near it the
    -- threat can't see at crouch height. Candidates: the navmesh's hiding
    -- spots plus a few found by tracing from nearby areas toward the threat
    -- (behind a wall or prop on our side of it; coverWallTries traces).
    -- Scored by distance, with a cost for spots closer to the threat than
    -- it is now (less for a charging droid) and none next to a squad mate.
    -- low = the threat would see it standing (it can fire over it).
    -- far: pulling back, only spots further from the threat (or, with no
    -- spot, the nearest area centre further away). Nil without a navmesh.
    function ENT:FindCover(threat, far)
        if not (navmesh and navmesh.Find) then return end
        local pos = self:GetPos()
        local areas = navmesh.Find(pos, D.Cfg("coverRadius"), 120, 120)
        if not areas or #areas == 0 then return end
        local myD = pos:DistToSqr(threat)
        local myLen = math.sqrt(myD)
        local push = self:Aggro() >= 4 and 0.3 or 1.5
        local spots, farArea, farD = {}, nil, math.huge
        local function consider(v)
            local td = v:DistToSqr(threat)
            if td > 62500 and (not far or td > myD + 40000) and not crowded(self, v) then
                local closer = math.max(0, myLen - math.sqrt(td))
                spots[#spots + 1] = { v = v, s = v:Distance(pos) + closer * push }
            end
        end
        local nAreas = math.min(#areas, MAX_AREAS)
        for i = 1, nAreas do
            local a = areas[i]
            for _, v in ipairs(a:GetHidingSpots(IN_COVER) or {}) do consider(v) end
            -- (no spot: pulling back still moves away from the threat)
            if far then
                local c = a:GetCenter()
                local d = c:DistToSqr(pos)
                if c:DistToSqr(threat) > myD + 90000 and d < farD then farArea, farD = c, d end
            end
        end
        -- Behind walls and props: from area centres, toward the threat.
        local tries = math.min(D.Cfg("coverWallTries"), nAreas)
        for i = 1, tries do
            local c = areas[math.random(nAreas)]:GetCenter()
            local dir = threat - c
            dir.z = 0
            local len = dir:Length()
            if len > 200 then
                dir = dir / len
                local from = c + Vector(0, 0, 30)
                sightTr.start, sightTr.endpos = from, from + dir * 180
                util.TraceLine(sightTr)
                if trOut.Hit and not trOut.HitSky and trOut.Fraction > 0.1 then
                    local v = Vector(trOut.HitPos.x - dir.x * 26, trOut.HitPos.y - dir.y * 26, c.z)
                    consider(D.SnapNav and D.SnapNav(v) or v)   -- (on the navmesh: reachable)
                end
            end
        end
        table.sort(spots, function(x, y) return x.s < y.s end)
        local eye = threat + Vector(0, 0, 60)
        for i = 1, math.min(#spots, MAX_CHECKS) do
            local v = spots[i].v
            if blocked(eye, v + Vector(0, 0, 36)) then
                return v, not blocked(eye, v + Vector(0, 0, 64))
            end
        end
        return far and farArea or nil, false
    end

    -- ENT:CoverFire(t): one aimed burst at t (from low cover or a peek).
    -- Yields. false if it couldn't see t.
    function ENT:CoverFire(t)
        if not (IsValid(t) and self:CanSee(t)) then return false end
        local k = self:Kind()
        local wait = 60 / math.max(D.Cfg(k.rpm), 1)
        -- (the same reaction delay as in the open: a fresh peek gets a moment)
        local react = (self.reactUntil or 0) - CurTime()
        self:Face(t:GetPos(), math.max(0.25, math.min(react, 2)))
        if not (IsValid(t) and self:CanSee(t)) then return true end
        if self:FriendInLine(t) then return true end
        for _ = 1, math.random(k.burst[1], k.burst[2]) do
            if not (IsValid(t) and self:CanSee(t)) then break end
            self:FireAt(t)
            self:Face(t:GetPos(), wait)
        end
        return true
    end

    -- ENT:TakeCover(threat, far) -> true if it got there. Run to cover, then
    -- for coverTime: low cover = fire aimed bursts over it at whoever it
    -- sees (crouched between them); full cover = crouched, blind fire
    -- toward where the enemy was, and now and then (coverPeek) a step out
    -- to the side for an aimed burst and back. Every coverFlankCheck s: if
    -- the enemy can see it in its spot it leaves for another one. Yields.
    function ENT:TakeCover(threat, far)
        local k = self:Kind()
        while not D.TakeBudget() do coroutine.yield() end
        local spot, low = self:FindCover(threat, far)
        if not spot then
            self.coverReady = CurTime() + 3   -- (nothing near: try again later)
            return false
        end
        local key = D.SpotKey(spot)
        D.coverTaken[key] = self
        self.coverKey, self.coverSpot = key, spot
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
        local peek = D.Cfg("coverPeek")
        -- (stepping out of full cover: clones; droids only blind fire unless droidPeekOut)
        local stepOut = peek and (self.IsRhylibClone or D.Cfg("droidPeekOut"))
        local outChance = self.IsRhylibClone and 0.65 or 0.45
        local flankAt = CurTime() + D.Cfg("coverFlankCheck")
        local flanked = false
        local peekSide = math.random() < 0.5 and 1 or -1
        while CurTime() < stop and self:Health() > 0 do
            local aim = self.lastSeen
            -- Flanked: the enemy can see it here at crouch height.
            if CurTime() >= flankAt then
                flankAt = CurTime() + D.Cfg("coverFlankCheck")
                local t = self.target
                local from = IsValid(t) and (t:IsPlayer() and t:EyePos() or t:WorldSpaceCenter()) or (aim and CurTime() - (self.lastSeenAt or 0) < 3 and aim + Vector(0, 0, 60))
                if from and not blocked(from, self:GetPos() + Vector(0, 0, 36)) then flanked = true break end
            end
            if low and peek then
                -- Low cover: fire over it at whoever it can see.
                local t = self:Look()
                if not (t and self:CoverFire(t)) then
                    -- (ducks between looks; up again before the next one)
                    self.crouchUntil = CurTime() + 0.35
                    self:Face(aim or (self:GetPos() + self:GetForward() * 100), math.Rand(0.5, 0.8))
                else
                    self.crouchUntil = CurTime() + 0.4
                    self:Face(aim or (self:GetPos() + self:GetForward() * 100), math.Rand(0.6, 1.0))
                end
            elseif stepOut and aim and CurTime() - (self.lastSeenAt or 0) < 8 and math.random() < outChance then
                -- Full cover: step out to the side, an aimed burst, back in.
                local to = aim - spot
                to.z = 0
                if to:LengthSqr() > 1 then
                    to:Normalize()
                    local out = spot + Vector(to.y, -to.x, 0) * peekSide * 46
                    if self:StraightTo(out) then
                        self:WalkStraight(out, 0.8)
                        local t = self:Look()
                        if t then self:CoverFire(t) end
                        self.target = nil
                        -- (back in: no stopping halfway for whoever it sees)
                        local back = CurTime() + 0.9
                        while CurTime() < back and self:GetPos():DistToSqr(spot) > 20 * 20 do
                            self.loco:Approach(spot, 1)
                            self.loco:FaceTowards(aim)
                            if self.loco:IsStuck() then self:HandleStuck() break end
                            coroutine.yield()
                        end
                    else
                        peekSide = -peekSide   -- (no room that side: the other next time)
                    end
                end
                self.crouchUntil = CurTime() + 1.2
                self:Face(aim, math.Rand(0.8, 1.3))
            else
                if aim and CurTime() - (self.lastSeenAt or 0) < 8 and math.random() < 0.6 then
                    -- Blind fire toward where the enemy was.
                    self:Face(aim, 0.2)
                    for _ = 1, math.random(2, 3) do
                        self:FireAtPos(aim + Vector(0, 0, 40), 0, D.Cfg("blindSpread"))
                        self:Face(aim, wait)
                    end
                end
                self.crouchUntil = CurTime() + 1.5
                self:Face(aim or (self:GetPos() + self:GetForward() * 100), math.Rand(0.8, 1.4))
            end
        end
        self:LeaveCover()
        self.hits = nil
        self.crouchUntil = nil
        -- (flanked: another spot soon; else the usual wait)
        self.coverReady = CurTime() + (flanked and 0.5 or D.Cfg("coverCooldown"))
        if flanked then
            -- (counts as hit enough to want cover again at once)
            local h = {}
            for i = 1, math.max(2, D.Cfg("coverHits")) do h[i] = CurTime() end
            self.hits = h
        end
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
