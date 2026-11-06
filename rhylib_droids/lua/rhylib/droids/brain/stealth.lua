--[[
    Droid brain part (server): the stealth look of an unaware droid
    (only droids a GM set to Unaware: npc.stealth; see sv_60_stealth.lua
    and sh_50_stealth.lua for the rules and settings).
    Mixed into the rhylib_b1 NextBot by entities/rhylib_b1.lua:
    include(...)(ENT, env).

    ENT:StealthLook(): called by ENT:Look while npc.stealth is set (at
    most 4 times a second). Instead of spotting at once it fills a meter
    per player it notices (at most 3): range and view cone first (no
    trace), then at most 2 of them traced at head, chest and knees
    (lowered when crouched; clear glass doesn't block; within the
    server-wide D.StealthTraces budget, the rest wait for the next look),
    foliage and smoke, then the rate (D.StealthMath.Rate). Sprinting and
    walking close by add to the meter seen or not. Moves the state on
    (D.StealthMath.Advance) and alerts it (D.StealthAlert) at 1, or when
    a startle's reaction time is over. Never yields, returns nothing.
    ENT:StealthStep() -> true if it did something (yields): turning to a
    sound, a suspicious droid stopping, turning and walking slowly to
    the spot, a searching one walking there and looking round.
    ENT:StealthWatch(pos, t): face pos for t seconds, still looking.
]]

return function(ENT, env)
    local D = env.D
    local State = Rhylib.State

    local tr = {}
    local trF = {}
    local trData = { mask = MASK_VISIBLE_AND_NPCS, output = tr, filter = trF }
    local pt = Vector(0, 0, 0)
    local mid = Vector(0, 0, 0)
    -- (body points above the feet: head, chest, knees; crouched lower)
    local STAND = { 62, 40, 18 }
    local CROUCH = { 34, 22, 10 }
    local cand, candD = {}, {}
    local o = {}

    local function entryFor(st, e)
        local E = st.e
        for i = 1, 3 do if E[i].ent == e then return E[i] end end
        for i = 1, 3 do
            local x = E[i]
            if not IsValid(x.ent) or x.v <= 0 then
                x.ent, x.v, x.seenAt, x.stepAt, x.sightAt = e, 0, 0, 0, -100
                return x
            end
        end
        return nil
    end

    -- Move state: 0 still, 1 walking, 2 sprinting.
    local function moveOf(p, speed)
        if speed < 15 then return 0 end
        if p:IsPlayer() then
            return (p:KeyDown(IN_SPEED) and speed > p:GetWalkSpeed() * 1.05) and 2 or 1
        end
        return speed > 150 and 2 or 1
    end

    local function crouchOf(p)
        if not p:IsPlayer() then return false end
        if p:Crouching() then return true end
        return State and State.Ask and State.Ask("lying", p) == true or false
    end

    -- Visible body points (0-3).
    local function visCount(self, eye, p, crouch)
        local base = p:GetPos()
        local zs = crouch and CROUCH or STAND
        trF[1], trF[2] = self, p
        local n = 0
        for i = 1, 3 do
            if i == 1 and p:IsPlayer() then pt:Set(p:EyePos()) else pt:SetUnpacked(base.x, base.y, base.z + zs[i]) end
            trData.start, trData.endpos = eye, pt
            util.TraceLine(trData)
            if not tr.Hit then n = n + 1 end
        end
        trF[1], trF[2] = nil, nil
        return n
    end

    function ENT:StealthLook()
        local st = self.stealth
        local now = CurTime()
        if now < st.nextAt then return end
        -- (already fighting, e.g. stealth switched on mid-fight: alert)
        if IsValid(self.target) then
            D.StealthAlert(self, self.target, nil, true)
            return
        end
        local dt = now - st.lastAt
        if dt > 0.75 then dt = 0.75 elseif dt < 0 then dt = 0 end
        st.lastAt = now
        -- Startled by a sound: alerted once its reaction time is over.
        if st.startleAt and now >= st.startleAt then
            local src = st.startleSrc
            D.StealthAlert(self, (IsValid(src) and self:IsFoe(src)) and src or nil, st.startlePos)
            return
        end
        local c = D.Cfg
        local M = D.StealthMath   -- (sh_50_stealth.lua)
        local k = self:Kind()
        local range = self.SightRange and self:SightRange() or D.Cfg(k.range)
        local litRange = range * c("stealthLightsRange")
        local far = math.max(range, litRange)
        local stepR = math.max(c("stealthStepSprint"), c("stealthStepWalk"))
        local pos = self:GetPos()
        st.px, st.py, st.pz = pos.x, pos.y, pos.z   -- (for hearing, sv_60_stealth)
        local eye = self:Eye()
        local fwd = self:GetForward()
        local cosFull = math.cos(math.rad(c("stealthFov") * 0.5))
        local cosWide = math.cos(math.rad(c("stealthFovWide") * 0.5))
        local searching = st.state == "searching"

        -- 1. Who is near enough to see or hear (distance only).
        local n = 0
        for _, p in ipairs(self:TargetList()) do
            -- (things to shoot, event targets, depot crates: only once alerted, by the normal look)
            if IsValid(p) and p:Health() > 0 and not p.rhylibObjTarget then
                local d2 = p:GetPos():DistToSqr(pos)
                if d2 < far * far or d2 < stepR * stepR then
                    n = n + 1
                    cand[n], candD[n] = p, d2
                end
            end
        end

        -- 2. Footsteps close by; the view cone; pick the two to trace
        -- (ones already noticed first, then the nearest).
        local pick1, pick2, s1, s2 = nil, nil, -math.huge, -math.huge
        local sprintR2, walkR2 = c("stealthStepSprint") ^ 2, c("stealthStepWalk") ^ 2
        local heard = nil
        for i = 1, n do
            local p, d2 = cand[i], candD[i]
            local pp = p:GetPos()
            local speed = p:GetVelocity():Length2D()
            local mv = moveOf(p, speed)
            if d2 < sprintR2 or d2 < walkR2 then
                local add = (mv == 2 and d2 < sprintR2) and c("stealthStepSprintAdd")
                    or (mv == 1 and d2 < walkR2 and not crouchOf(p)) and c("stealthStepWalkAdd") or 0
                if add > 0 then
                    local x = entryFor(st, p)
                    if x and now >= x.stepAt then
                        x.stepAt = now + 1
                        x.v = math.min(x.v + add, 1)
                        x.seenAt = now
                        x.pos:Set(pp)
                        heard = x
                    end
                end
            end
            local lit = p:IsPlayer() and p:GetNW2Bool("rhylib_lights", false)
            local r = lit and litRange or range
            if d2 < r * r and p:WaterLevel() < 3 then
                local dx, dy = pp.x - pos.x, pp.y - pos.y
                local len = math.sqrt(dx * dx + dy * dy)
                local dot = len > 1 and (dx * fwd.x + dy * fwd.y) / len or 1
                if dot >= cosWide then
                    local x = entryFor(st, p)   -- (no free slot: not this one)
                    if x then
                        local score = (x.v > 0 and 1e12 + x.v * 1e9 or 0) - d2
                        if score > s1 then
                            pick2, s2 = pick1, s1
                            pick1, s1 = i, score
                        elseif score > s2 then
                            pick2, s2 = i, score
                        end
                    end
                end
            end
        end

        -- 3. Trace the picked ones and fill their meters.
        local seenNow = heard
        for pass = 1, 2 do
            local i = pass == 1 and pick1 or pick2
            if i and D.StealthTraces(3) then
                local p, d2 = cand[i], candD[i]
                local x = entryFor(st, p)
                if x then
                    local crouch = crouchOf(p)
                    local pp = p:GetPos()
                    local W = Rhylib.Weapons
                    mid:SetUnpacked(pp.x, pp.y, pp.z + (crouch and CROUCH[2] or STAND[2]))
                    local vis = 0
                    if not (W and W.SmokeBlocks and W.SmokeBlocks(eye, mid)) then vis = visCount(self, eye, p, crouch) end
                    if vis > 0 then
                        local dx, dy = pp.x - pos.x, pp.y - pos.y
                        local len = math.sqrt(dx * dx + dy * dy)
                        local dot = len > 1 and (dx * fwd.x + dy * fwd.y) / len or 1
                        local Fo = D.Foliage
                        local inside = Fo and Fo.Inside(pp) ~= nil or false
                        o.vis, o.periph, o.crouch = vis, dot < cosFull, crouch
                        o.move = moveOf(p, p:GetVelocity():Length2D())
                        o.inside = inside
                        o.between = (not inside) and Fo ~= nil and Fo.Between(eye, mid) or false
                        o.weather = D.StealthWeather()
                        o.lights = p:IsPlayer() and p:GetNW2Bool("rhylib_lights", false)
                        o.searching = searching
                        local r = o.lights and litRange or range
                        local rate = M.Rate(c, math.sqrt(d2), r, o)
                        if rate > 0 then
                            x.v = M.Step(x.v, rate, dt, 0, true)
                            x.seenAt = now
                            x.sightAt = now   -- (seen by a sight trace: arcs may point at it)
                            x.pos:Set(pp)
                            if not seenNow or x.v > seenNow.v then seenNow = x end
                        end
                    end
                end
            elseif i then
                -- (over the budget: this one keeps its meter until next look)
                local x = entryFor(st, cand[i])
                if x then x.skipAt = now end
            end
        end

        -- 4. Not seen this look: the meter drains.
        local drain = c("stealthDrain")
        local top, focus = 0, nil
        for j = 1, 3 do
            local x = st.e[j]
            if IsValid(x.ent) and x.v > 0 then
                if x.seenAt ~= now and x.skipAt ~= now then x.v = M.Step(x.v, 0, dt, drain, false) end
                if x.v > top then top, focus = x.v, x end
            elseif x.ent ~= nil and not IsValid(x.ent) then
                x.ent, x.v = nil, 0
            end
        end
        for j = 1, n do cand[j] = nil end

        -- 5. The state.
        local seen = focus ~= nil and focus.seenAt == now
        local ev = M.Advance(st, top, seen, now, math.max(c("stealthSuspect"), 0.01), c("stealthLoseTime"), c("stealthSearchTime"))
        if ev == "alert" and focus then
            D.StealthAlert(self, focus.ent, focus.pos, false, true)
            return
        elseif ev == "suspicious" and focus then
            st.spot:Set(focus.pos)
            st.stopUntil = now + 1
            self.redirect, self.woken = true, true
            D.StealthSetState(self, D.SSTATE.suspicious)
        elseif ev == "searching" then
            st.reached = false
            self.redirect, self.woken = true, true
            D.StealthSetState(self, D.SSTATE.searching)
        elseif ev == "unaware" then
            for j = 1, 3 do st.e[j].v = 0 end
            self.redirect = true
            D.StealthSetState(self, D.SSTATE.unaware)
        elseif seen and st.state ~= "unaware" then
            if st.spot:DistToSqr(focus.pos) > 100 * 100 then st.reached = false end
            st.spot:Set(focus.pos)
        end
        st.nextAt = now + (n > 0 and 0.25 or 0.5) + math.Rand(0, 0.05)
    end

    -- ENT:StealthWatch(pos, t): face pos for t seconds, still looking
    -- (true = something came up: alerted or stealth over). Yields.
    function ENT:StealthWatch(pos, t)
        local stop = CurTime() + t
        while CurTime() < stop do
            if not self.stealth then return true end
            self.loco:FaceTowards(pos)
            if self:Look() then return true end
            coroutine.yield()
        end
        return false
    end

    function ENT:StealthStep()
        local st = self.stealth
        if not st or not D.StealthOn() then return false end
        local now = CurTime()
        -- (heard something: turn to it until the reaction time is over)
        if st.startleAt then
            self:StealthWatch(st.startlePos, 0.3)
            return true
        end
        if st.state == "suspicious" then
            if now < st.stopUntil then
                self:StealthWatch(st.spot, 0.3)
            elseif self:GetPos():DistToSqr(st.spot) > 90 * 90 then
                self:SetPace(false)
                self.loco:SetDesiredSpeed(self.loco:GetDesiredSpeed() * math.Clamp(D.Cfg("stealthSlow"), 0.1, 1))
                local spot = Vector(st.spot)
                if self:Go(spot, 1.5, true) == false then self:StealthWatch(spot, 0.5) end
            else
                self:StealthWatch(st.spot, 0.5)
            end
            return true
        elseif st.state == "searching" then
            if self:GetPos():DistToSqr(st.spot) > 90 * 90 and not st.reached then
                self:SetPace(false)
                local spot = Vector(st.spot)
                if self:Go(spot, 3, true) == false then st.reached = true end
                if self:GetPos():DistToSqr(spot) < 120 * 120 then st.reached = true end
            else
                -- (there: look round, a new way every second or two)
                st.reached = true
                local a = math.Rand(0, math.pi * 2)
                self:StealthWatch(self:GetPos() + Vector(math.cos(a), math.sin(a), 0) * 200, math.Rand(1.2, 2.2))
            end
            return true
        end
        return false
    end
end
