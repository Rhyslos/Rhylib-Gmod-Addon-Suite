--[[
    LM-432 crab droid: the spider droid's walker (rhylib_spider: model
    sizing, hull, animation, body turning, body bob) with the "crab" row
    of Rhylib.Droids.KINDS and two rapid-fire blasters instead of a cannon.

    What this file changes from rhylib_spider:
      - config keys crab* (crabModel, placeholder models/headcrabclassic.mdl,
        crabHeight, crabScale, crabSeq*, crabTurnRate), a wider hull
      - firing: the B2's "suppress" style (shared brain, rhylib_b1) with
        crabRPM / crabSpread / crabDamage bolts, left and right gun in
        turn, only once its body points within crabAimCone of the target;
        commander boost, suppression, smoke and friends in the line as for
        any droid. No shells, no backing off.
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

    -- Bolts again (the spider fires none), left and right in turn.
    function ENT:FireAtPos(aim, speed, extra)
        B1.FireAtPos(self, aim, speed, extra)
        self.crabLeft = not self.crabLeft
    end
    function ENT:SuppressSmoke(t)
        return B1.SuppressSmoke(self, t)
    end

    -- Style: the shared one, once the body points at the target.
    function ENT:StyleFire(t, now, st)
        local D = Rhylib.Droids
        self.loco:SetMaxYawRate(D.Cfg("crabTurnRate"))
        local pos, tp = self:GetPos(), t:GetPos()
        local f = self:GetForward()
        f.z = 0
        local to = tp - pos
        to.z = 0
        if to:LengthSqr() > 1 and f:LengthSqr() > 0 then
            to:Normalize()
            f:Normalize()
            if f:Dot(to) < math.cos(math.rad(D.Cfg("crabAimCone"))) then return now + 0.1 end
        end
        return B1.StyleFire(self, t, now, st)
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
