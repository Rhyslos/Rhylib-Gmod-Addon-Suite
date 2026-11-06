--[[
    LM-432 crab droid: the spider droid's walker (rhylib_spider: model
    sizing, hull, animation, body turning, body bob) with the "crab" row
    of Rhylib.Droids.KINDS and two rapid-fire blasters instead of a cannon.

    What this file changes from rhylib_spider:
      - config keys crab* (crabModel, models/funky/starwars/crab.mdl, missing: models/headcrabclassic.mdl,
        crabHeight, crabScale, crabSeq*, crabTurnRate), a wider hull
      - firing (its own ENT:StyleFire): crabRPM bolts without stopping,
        left and right gun in turn (several in one tick when a tick is
        longer than the gap), only while its body points within
        crabAimCone of where it shoots; commander boost, last stand,
        suppression and smoke as for any droid. No shells, no backing off.
      - where it aims (ENT:CrabTrack / CrabHitChance / CrabMissPoint, a
        state table per target in self.crabAim, new for each target):
        most bolts are near misses, a spot crabMissMin-crabMissMax units
        off the target's body (beside it, over its shoulder or the
        ground in front of its feet), led by its speed and fired with the
        cone x crabMissSpread; the spot is picked again every
        crabMissRepick s and the stream circles round the target to it at
        crabMissWalk degrees a second (never through the body). Each bolt
        is aimed true (ENT:FireAt, crabSpread) by chance:
          crabBaseHit         in sight and moving (strafing, a short dash)
          up to crabStillHit  in sight and slower than crabStillSpeed for
                              more than crabStillTime s (ramps over
                              crabStillRamp s)
          crabChargeHit       closer than crabCloseRange, or within
                              crabChargeRange after closing in on it by
                              crabChargeDist units in one approach (moving
                              toward it at crabChargeSpeed or more; the
                              approach starts over after crabChargeGrace s
                              not doing so)
          always              an event target
        Out of sight it keeps suppressing the spot it last saw the target
        with near misses for crabSuppressTime s after it lost sight
        (ENT:LobAtLastSeen; it stops for a target back in sight, someone
        else in sight, a retreat, or the target down or gone).
      - muzzles: the crabMuzzleLeft / crabMuzzleRight attachments, else
        crabMuzzleFwd / crabMuzzleSide / crabMuzzleUp from its feet
      - armour by where a hit comes from (EntityTakeDamage below): from
        higher than crabTopAngle above its middle x crabTopMult, from
        its left or right x crabSideMult, from the front or back
        x crabFrontMult. Bolts and bullets count from the shooter's eyes
        and as from above only when they land on its top; blasts count
        from the blast. Droid popper EMP (DMG_SHOCK) is never scaled, and
        a rocket straight into it (rhylib_weapons W.directHit, the RPS-6)
        always kills it.
      - belly weak spot (rhylib_spider's, config crabBellyKill /
        crabBellyRadius / crabBellyHeight): a frag grenade going off right
        under it kills it; that hook (-140) runs after the armour above,
        so the armour never lowers it. No spider head armour.
    Health crabHealth; poppers, no knockdown and no cover as for big droids.
]]

AddCSLuaFile()

local B1 = baseclass.Get("rhylib_b1")

ENT.Base = "rhylib_spider"
ENT.Type = "nextbot"
ENT.PrintName = "LM-432 crab droid"
ENT.Category = "Rhy's Crab droids"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "crab"
ENT.CfgPrefix = "crab"
ENT.HullHalf = 22   -- (the model may be wider: the hull has to fit doors)
ENT.HeadArmour = false   -- (no spider head armour; its belly weak spot is the spider's, crabBelly*)

if SERVER then
    local attOf = {}
    local function att(self, name)
        if not (isstring(name) and name ~= "") then return nil end
        local key = (self:GetModel() or "") .. "|" .. name
        local id = attOf[key]
        if id == nil then
            id = self:LookupAttachment(name) or 0
            attOf[key] = id
        end
        local a = id > 0 and self:GetAttachment(id)
        return a and a.Pos or nil
    end

    -- ENT:Muzzle(): the gun that fires next (self.crabLeft).
    function ENT:Muzzle()
        local D = Rhylib.Droids
        local left = self.crabLeft
        local p = att(self, D.Cfg(left and "crabMuzzleLeft" or "crabMuzzleRight"))
        if p then return p end
        return self:GetPos() + self:GetForward() * D.Cfg("crabMuzzleFwd")
            + self:GetRight() * (left and -1 or 1) * D.Cfg("crabMuzzleSide") + Vector(0, 0, D.Cfg("crabMuzzleUp"))
    end

    local function velOf(t)
        if t:IsNextBot() and t.loco then return t.loco:GetVelocity() end
        return t:GetVelocity()
    end

    -- Still worth shooting at: there, alive, not downed.
    local function alive(t)
        if not IsValid(t) then return false end
        if t:IsPlayer() then
            if not t:Alive() then return false end
            local S = Rhylib.State
            return not (S and S.IsDown and S.IsDown(t))
        end
        return t:Health() > 0
    end

    -- ENT:FireAtPos(aim, speed, extra): one bolt from the gun whose turn
    -- it is (B1's cone rules with crabSpread), left and right in turn;
    -- the fire sound at most every 0.07 s.
    function ENT:FireAtPos(aim, speed, extra)
        local D = Rhylib.Droids
        local Bolts = Rhylib.Weapons and Rhylib.Weapons.Bolts
        if not Bolts then return end
        local k = self:Kind()
        local origin = self:Muzzle()
        local dir = aim - origin
        dir:Normalize()
        local mult = D.SuppressMult(self) * (extra or 1)
        if self.loco:GetVelocity():Length2DSqr() > 400 then mult = mult * D.Cfg(self.running and "runSpread" or "walkSpread") end
        if D.Boosted(self) then mult = mult * D.Cfg("cmdSpread") end
        local cone = math.rad((D.Cfg(k.spread) + (speed or 0) * D.Cfg("moveSpread")) * mult)
        local a = math.Rand(0, math.pi * 2)
        local r = math.tan(cone * math.sqrt(math.Rand(0, 1)))
        local ang = dir:Angle()
        dir = dir + ang:Right() * math.cos(a) * r + ang:Up() * math.sin(a) * r
        dir:Normalize()
        local gun = D.Gun(self.DroidKind)
        Bolts.Fire(self, gun, origin, dir, gun.Damage)
        local now = CurTime()
        if now >= (self.crabSoundAt or 0) then
            self.crabSoundAt = now + 0.07
            self:EmitSound(k.sound or D.E5_SOUND, 130, math.random(96, 104) * (k.pitch or 100) / 100, 0.8, CHAN_WEAPON)
        end
        self.crabLeft = not self.crabLeft
    end
    function ENT:SuppressSmoke(t)
        return B1.SuppressSmoke(self, t)
    end

    -- ENT:CrabState(t) -> the aim state for t (a new one for a new target).
    function ENT:CrabState(t)
        local s = self.crabAim
        if not s or s.t ~= t then
            local D = Rhylib.Droids
            local r = math.Rand(D.Cfg("crabMissMin"), D.Cfg("crabMissMax"))
            s = { t = t, at = CurTime(), still = 0, approach = 0, closeAt = -100, d = math.huge,
                th = math.Rand(0, 360), r = r, thGoal = 0, rGoal = r, pickAt = 0, walkAt = CurTime(), seeUntil = 0 }
            self.crabAim = s
        end
        return s
    end

    -- ENT:CrabTrack(s, t, now, seen): how long t has stood still in
    -- sight and how far it has closed in during this approach.
    function ENT:CrabTrack(s, t, now, seen)
        local D = Rhylib.Droids
        local dt = math.Clamp(now - s.at, 0, 0.5)
        s.at = now
        local vel = velOf(t)
        local to = self:GetPos() - t:GetPos()
        to.z = 0
        local d = to:Length()
        if d > 1 then to:Div(d) end
        s.d = d
        local closing = vel.x * to.x + vel.y * to.y
        if seen and closing >= D.Cfg("crabChargeSpeed") then
            s.approach = s.approach + closing * dt
            s.closeAt = now
        elseif now - s.closeAt > D.Cfg("crabChargeGrace") then
            s.approach = 0
        end
        if not seen then
            s.still = 0
        elseif vel:Length2DSqr() < D.Cfg("crabStillSpeed") ^ 2 then
            s.still = s.still + dt
        else
            s.still = math.max(0, s.still - dt * 3)   -- (a shuffle doesn't start it over)
        end
    end

    -- ENT:CrabHitChance(t, s, seen) -> share of bolts aimed true now.
    function ENT:CrabHitChance(t, s, seen)
        if not seen then return 0 end
        if t.rhylibObjTarget then return 1 end
        local D = Rhylib.Droids
        local base = D.Cfg("crabBaseHit")
        local p = base
        local still = D.Cfg("crabStillTime")
        if s.still > still then
            local f = math.Clamp((s.still - still) / math.max(D.Cfg("crabStillRamp"), 0.01), 0, 1)
            p = math.max(p, Lerp(f, base, D.Cfg("crabStillHit")))
        end
        if s.d < D.Cfg("crabCloseRange") or (s.d < D.Cfg("crabChargeRange") and s.approach >= D.Cfg("crabChargeDist")) then
            p = math.max(p, D.Cfg("crabChargeHit"))
        end
        return p
    end

    -- ENT:CrabMissPoint(s, feet, h, w, from, now) -> a near-miss point
    -- round a body h tall and w wide (half) standing at feet, seen from
    -- from. The spot is an angle round the body (0 right, 90 over its
    -- head, 180 left, 270 the ground in front of its feet) and a distance
    -- off it; both walk to a new pick every crabMissRepick s.
    function ENT:CrabMissPoint(s, feet, h, w, from, now)
        local D = Rhylib.Droids
        local lo, hi = D.Cfg("crabMissMin"), D.Cfg("crabMissMax")
        if hi < lo then lo, hi = hi, lo end
        if now >= s.pickAt then
            s.thGoal = (s.th + math.Rand(-130, 130)) % 360
            s.rGoal = math.Rand(lo, hi)
            s.pickAt = now + math.max(D.Cfg("crabMissRepick"), 0.05) * math.Rand(0.6, 1.4)
        end
        local dt = math.Clamp(now - s.walkAt, 0, 0.2)
        s.walkAt = now
        local step = D.Cfg("crabMissWalk") * dt
        s.th = (s.th + math.Clamp(math.NormalizeAngle(s.thGoal - s.th), -step, step)) % 360
        s.r = math.Clamp(math.Approach(s.r, s.rGoal, (hi - lo + 10) * 2 * dt), lo, hi)
        local fwd = from - feet
        fwd.z = 0
        if fwd:LengthSqr() < 1 then fwd = Vector(1, 0, 0) else fwd:Normalize() end
        local right = Vector(-fwd.y, fwd.x, 0)
        local rad = math.rad(s.th)
        local c, sn = math.cos(rad), math.sin(rad)
        local r = s.r
        local cz = h * 0.55
        -- (a target above the gun: no ground in front of it to aim at)
        if sn < 0 and feet.z > from.z then sn = -sn end
        local p = feet + right * (c * (w + r))
        if sn >= 0 then
            p.z = p.z + cz + sn * (h - cz + r * 0.6)
        else
            p = p + fwd * (-sn * r)
            p.z = p.z + cz * (1 + sn)
        end
        return p
    end

    -- ENT:CrabShot(t, s, seen, now, p): one bolt, true by chance p, else a
    -- near miss (round t, or out of sight round where it was last seen).
    function ENT:CrabShot(t, s, seen, now, p)
        if seen and math.random() < p then
            self:FireAt(t)
            return
        end
        local D = Rhylib.Droids
        local from = self:Muzzle()
        local feet, h, w, vel
        if seen then
            feet = t:GetPos()
            local mx = t:OBBMaxs()
            h, w = math.max(mx.z, 16), math.Clamp(math.max(mx.x, mx.y), 8, 64)
            vel = velOf(t)
            vel.z = 0
        else
            feet = self.lastSeen or t:GetPos()
            h, w, vel = 72, 16, nil
        end
        if vel then
            local W = Rhylib.Weapons
            local speed = W and W.Bolts and W.Bolts.Speed and W.Bolts.Speed(D.Gun(self.DroidKind)) or D.Cfg("boltSpeed")
            feet = feet + vel * math.min(from:Distance(feet) / math.max(speed, 100), 1)
        end
        self:FireAtPos(self:CrabMissPoint(s, feet, h, w, from, now), 0, D.Cfg("crabMissSpread"))
    end

    -- ENT:CrabBurst(t, s, seen, now, st) -> when the next bolt is due:
    -- every bolt due by now (at most 4 in one tick).
    function ENT:CrabBurst(t, s, seen, now, st)
        local D = Rhylib.Droids
        local gap = 60 / math.max(D.Cfg("crabRPM"), 1)
        if D.Boosted(self) then gap = gap * D.Cfg("cmdPause") end
        if self.lastStand then gap = gap * D.Cfg("lastStandPause") end
        local due = st.crabDue
        if not due or due < now - 0.25 then due = now end
        local p = self:CrabHitChance(t, s, seen)
        local n = 0
        while due <= now and n < 4 do
            self:CrabShot(t, s, seen, now, p)
            due = due + gap * math.Rand(0.9, 1.1)
            n = n + 1
        end
        st.crabDue = due
        return due
    end

    -- Does its body point within crabAimCone of pos?
    function ENT:CrabPointing(pos)
        local D = Rhylib.Droids
        local f = self:GetForward()
        f.z = 0
        local to = pos - self:GetPos()
        to.z = 0
        if to:LengthSqr() <= 1 or f:LengthSqr() == 0 then return true end
        to:Normalize()
        f:Normalize()
        return f:Dot(to) >= math.cos(math.rad(D.Cfg("crabAimCone")))
    end

    -- Style: see the header. Sight is checked at most every 0.1 s.
    function ENT:StyleFire(t, now, st)
        local D = Rhylib.Droids
        self.loco:SetMaxYawRate(D.Cfg("crabTurnRate"))
        local s = self:CrabState(t)
        if now >= s.seeUntil then
            s.seen, s.seeUntil = self:CanSee(t), now + 0.1
        end
        local seen = s.seen
        self:CrabTrack(s, t, now, seen)
        local suppressing = not seen and self.lastSeen and now - (self.lastSeenAt or 0) < D.Cfg("crabSuppressTime")
        if not (seen or suppressing) then
            st.crabDue = nil
            return now + 0.2
        end
        if not self:CrabPointing(seen and t:GetPos() or self.lastSeen) then return now + 0.1 end
        return self:CrabBurst(t, s, seen, now, st)
    end

    -- Lost sight (the fight loop's last step): keep suppressing where it
    -- last saw the target, crabSuppressTime s after it lost sight. Yields.
    function ENT:LobAtLastSeen()
        local D = Rhylib.Droids
        local t, spot = self.target, self.lastSeen
        local stop = (self.lastSeenAt or 0) + D.Cfg("crabSuppressTime")
        if not (IsValid(t) and spot) or CurTime() >= stop then return end
        local st, nextSee = {}, 0
        while CurTime() < stop and self:Health() > 0 do
            local now = CurTime()
            if not alive(t) or self:Retreating() then break end
            local seen = self:Look()
            if seen and seen ~= t then break end               -- (someone else in sight)
            if now >= nextSee then
                nextSee = now + 0.25
                if self:CanSee(t) then                         -- (back in sight: fight it, no new reaction delay)
                    if self.seenAt then self.seenAt[t] = now end
                    break
                end
            end
            self.loco:FaceTowards(spot)
            local s = self:CrabState(t)
            self:CrabTrack(s, t, now, false)
            if self:CrabPointing(spot) then self:CrabBurst(t, s, false, now, st) else st.crabDue = nil end
            coroutine.yield()
        end
        self.nextLook = 0
    end

    -- Moving: the shared plan (no backing off).
    function ENT:PlanMove(t)
        return B1.PlanMove(self, t)
    end

    -- Where a hit came from: blasts from the blast, the rest from the
    -- shooter's eyes (else where it hit).
    local function source(dmg)
        local att = dmg:GetAttacker()
        if not dmg:IsDamageType(DMG_BLAST) and IsValid(att) then
            if att.Eye then return att:Eye() end   -- (Rhylib NPCs: their own eye height)
            if att:IsPlayer() or att:IsNPC() or att:IsNextBot() then return att:EyePos() end
        end
        local p = dmg:GetDamagePosition()
        if p and not p:IsZero() then return p end
        return IsValid(att) and att:WorldSpaceCenter() or nil
    end

    -- ENT:CrabArmour(dmg) -> damage multiplier and "top" / "side" / "front".
    function ENT:CrabArmour(dmg)
        local D = Rhylib.Droids
        local from = source(dmg)
        if not from then return D.Cfg("crabFrontMult"), "front" end
        local mid = self:WorldSpaceCenter()
        local to = from - mid
        local len = to:Length()
        if len < 1 then return D.Cfg("crabTopMult"), "top" end
        -- (from above: steeper than crabTopAngle; a shot must also land
        -- on its top, not its side, so point-blank fire from beside it
        -- doesn't count)
        if to.z / len >= math.sin(math.rad(D.Cfg("crabTopAngle"))) then
            local hit = dmg:GetDamagePosition()
            if dmg:IsDamageType(DMG_BLAST) or not hit or hit:IsZero() or hit.z >= self:GetPos().z + self:OBBMaxs().z * 0.8 then
                return D.Cfg("crabTopMult"), "top"
            end
        end
        to.z = 0
        if to:LengthSqr() < 1 then return D.Cfg("crabFrontMult"), "front" end
        to:Normalize()
        -- (more than 45 degrees off its nose or tail: a side)
        if math.abs(to:Dot(self:GetRight())) > 0.7071 then return D.Cfg("crabSideMult"), "side" end
        return D.Cfg("crabFrontMult"), "front"
    end

    local nextPing = 0
    -- After the friendly-fire check (-200), before armour and the rest.
    Rhylib.Hook.Add("EntityTakeDamage", "droids.crab.armour", function(ent, dmg)
        if not ent.CrabArmour then return end
        -- (a droid popper's EMP kill: as for any big droid)
        if dmg:IsDamageType(DMG_SHOCK) then return end
        -- (a rocket straight into it, rhylib_weapons' direct hit: always a kill)
        local W = Rhylib.Weapons
        if W and W.directHit == ent then
            dmg:SetDamage(math.max(dmg:GetDamage(), ent:Health() + 100))
            return
        end
        local m, part = ent:CrabArmour(dmg)
        dmg:ScaleDamage(math.max(m, 0))
        -- (a glancing hit off the side plates: a ricochet now and then)
        if part == "side" and CurTime() >= nextPing then
            nextPing = CurTime() + 0.25
            ent:EmitSound("weapons/fx/rics/ric" .. math.random(1, 5) .. ".wav", 75, math.random(90, 110), 0.6)
        end
    end, -150)
end
