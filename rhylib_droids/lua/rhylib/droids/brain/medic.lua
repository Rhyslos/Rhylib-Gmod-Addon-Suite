--[[
    Droid / clone brain part (server): Clone medics: walk to a downed player's body, crouch over it and revive them.
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D

    -- Medic: go to a downed player, crouch on the body and
    -- get them up (downed players only). sv_30_clones picks the patient; D.PatientPending,
    -- D.BodyPos and D.NpcRevive live there too.
    function ENT:DoRevive()
        local p = self.reviveTarget
        -- (Go and the waits below yield: the patient can leave meanwhile; an
        -- error here would end this NPC's behaviour for good)
        local function nick() return IsValid(p) and p:Nick() or "?" end
        if not D.PatientPending(p) then
            self.reviveTarget = nil
            return
        end
        local body = D.BodyPos(p)
        if not body then
            self.reviveTarget = nil
            return
        end
        local function far(b)
            local d = self:GetPos() - b
            d.z = d.z * 0.3   -- (a body on a ledge or lifted pelvis still counts)
            return d:LengthSqr() > 80 * 80
        end
        if far(body) then
            self:SetPace(true)
            local ok = self:Go(body, 3, false)
            -- (close but the route ends short: walk the last bit straight)
            if ok ~= false and far(body) and self:GetPos():DistToSqr(body) < 200 * 200 then
                local stop = CurTime() + 1.5
                while CurTime() < stop and far(body) do
                    self.loco:Approach(body, 1)
                    self.loco:FaceTowards(body)
                    coroutine.yield()
                end
            end
            if not D.PatientPending(p) then
                self.reviveTarget, self.reviveFails = nil, nil
                return
            end
            if far(body) then
                self.reviveFails = (self.reviveFails or 0) + 1
                D.MedicLog("%s: medic %s couldn't reach the body (try %d)", nick(), tostring(self), self.reviveFails)
                if self.reviveFails >= 4 then   -- (can't get there: give up on them for a while)
                    p.rhylibNoMedicUntil = CurTime() + 20
                    self.reviveTarget, self.reviveFails = nil, nil
                end
                return
            end
        end
        self.reviveFails = nil
        D.MedicLog("%s: medic %s reached the body, reviving", nick(), tostring(self))
        self.loco:SetDesiredSpeed(0)
        self.crouching = true
        local done = CurTime() + D.Cfg("ctMedicReviveTime")
        while CurTime() < done and D.PatientPending(p) do
            local b = D.BodyPos(p)
            if not b or self:GetPos():DistToSqr(b) > 120 * 120 then   -- (dragged away)
                D.MedicLog("%s: body moved away from the medic", nick())
                break
            end
            self.loco:FaceTowards(b)
            coroutine.yield()
        end
        self.crouching = false
        self:SetPace(false)
        if CurTime() >= done and D.PatientPending(p) then D.NpcRevive(p) end
        self.reviveTarget = nil
    end

end
