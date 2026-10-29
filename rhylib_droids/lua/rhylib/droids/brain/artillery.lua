--[[
    Droid / clone brain part (server): B2 rockets: the direct rocket, the mortar arc (artillery spotting and walking fire), lobbing at the last seen spot.
    Mixed into the rhylib_b1 NextBot (and every entity based on it) by
    entities/rhylib_b1.lua: include(...)(ENT, env), where env holds the
    shared helpers of the main file (env.D = Rhylib.Droids, ...).
    Every function here is an ENT method; the order within the brain
    and the coroutine (ENT:RunBehaviour) are in rhylib_b1.lua.
]]

return function(ENT, env)
    local D = env.D
    local lob = env.lob

    -- B2 rocket droid: a level rocket at the target that dives into the
    -- floor just before it (rhylib_b2_rocket with r.direct).
    function ENT:FireDirectRocket(t)
        local from = self:GetPos() + Vector(0, 0, 80) + self:GetForward() * 10
        local speed = D.Cfg("b2DirectSpeed")
        local pos = t:GetPos()
        -- Lead a moving target by the flight time; miss more at range.
        pos = pos + t:GetVelocity() * math.Clamp(from:Distance(pos) / math.max(speed, 1), 0, 2)
        local miss = VectorRand() * D.Cfg("b2RocketSpread") * from:Distance(pos) / 1000
        miss.z = 0
        pos = pos + miss
        local aim = pos + Vector(0, 0, 80)   -- (player head height: it curves down onto this spot)
        local r = ents.Create("rhylib_b2_rocket")
        if not IsValid(r) then return end
        r:SetPos(from)
        r.direct = true
        r.diveAt = aim
        r.vel = (aim - from):GetNormalized() * speed
        r.owner = self
        r.training = self.Training
        r:SetOwner(self)
        r:Spawn()
        self:EmitSound("weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_02.ogg", 105, 100)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
        self.nextRocket = CurTime() + D.Cfg("b2RocketCooldown") * math.Rand(0.8, 1.3)
    end

    -- ENT:FireRocket(pos, mover) -> true if fired. B2 mortar: a wrist
    -- rocket lobbed high, landing near pos (mover = the target, for
    -- leading). Direct kinds hand off to FireDirectRocket. Artillery: longer
    -- flight, tighter each shot at the same target, never into a blackout
    -- or from under a low roof.
    function ENT:FireRocket(pos, mover)
        -- (EOD Signal blackout: artillery can't fire into the bubble)
        if self.artillery and D.Blackout and D.Blackout(pos) then
            self.nextRocket = CurTime() + 2
            return false
        end
        if self:Kind().direct and IsValid(mover) then return self:FireDirectRocket(mover) end
        local from = self:GetPos() + Vector(0, 0, 80) + self:GetForward() * 10
        local dist = from:Distance(pos)
        local g = math.abs(physenv.GetGravity().z)
        -- Lead a moving target a little; miss more at range.
        local arty = self.artillery
        local t = math.Clamp(dist / 650, 1.2, arty and D.Cfg("artyMaxFlight") or 3.0)
        if IsValid(mover) then pos = pos + mover:GetVelocity() * (arty and math.min(t * 0.5, 1.5) or 0.4) end
        local spread = D.Cfg(arty and "artySpread" or "b2RocketSpread")
        -- Artillery walks its rounds in: shots at the same target tighten.
        if arty then
            if IsValid(mover) and mover == self.artyLast and CurTime() - (self.artyLastAt or 0) < 20 then
                self.artyWalk = math.max(0.35, (self.artyWalk or 1) * 0.75)
            else
                self.artyWalk = 1
            end
            self.artyLast, self.artyLastAt = mover, CurTime()
            spread = spread * self.artyWalk
        end
        local miss = VectorRand() * spread * dist / 1000
        miss.z = 0
        pos = pos + miss
        -- High arc (apex = g t^2 / 8), flatter under a low ceiling.
        local apex = g * t * t / 8
        local up = util.TraceLine({ start = from, endpos = from + Vector(0, 0, apex + 40), mask = MASK_SOLID_BRUSHONLY })
        if up.Hit then
            local low = math.Clamp(math.sqrt(math.max(up.HitPos.z - from.z - 40, 0) * 8 / g), 0.4, t)
            -- (artillery under a roof: no near-flat map-crossing shot)
            if arty and low < t * 0.5 then
                self.nextRocket = CurTime() + 2
                return false
            end
            t = low
        end
        local r = ents.Create("rhylib_b2_rocket")
        if not IsValid(r) then return false end
        r:SetPos(from)
        r.vel = lob(from, pos, t, g)
        r.owner = self
        r.training = self.Training
        r:SetOwner(self)
        r:Spawn()
        self:EmitSound("weapons/explosives_cannons_superlazers/wpn_mortar_cannon_r1_shoot_0" .. math.random(1, 3) .. ".ogg", arty and 115 or 105, 100)
        if self.anims.shoot then self:RestartGesture(self.anims.shoot, true, true) end
        self.nextRocket = CurTime() + D.Cfg(arty and "artyCooldown" or "b2RocketCooldown") * math.Rand(0.8, 1.3)
    return true
    end

    -- Artillery (mortar squad): a rocket at an enemy any droid
    -- has in sight within artyRange (spotters), when off cooldown. True if fired.
    function ENT:ArtilleryShot()
        if not self.artillery or CurTime() < (self.nextRocket or 0) then return false end
        local t = D.SpottedTarget and D.SpottedTarget(self, D.Cfg("artyRange"))
        if not IsValid(t) then return false end
        self:Face(t:GetPos(), 0.4)
        if not IsValid(t) then return false end
        return self:FireRocket(t:GetPos(), t) == true
    end

    -- Something to throw at a target out of sight (where it was last seen).
    function ENT:LobAtLastSeen()
        local k = self:Kind()
        local pos = self.lastSeen
        if not pos or CurTime() - (self.lastSeenAt or 0) > 4 then return end
        local d = pos:Distance(self:GetPos())
        local now = CurTime()
        if (k.nades or k.poppers) and now >= self.nextNade and d > 250 and d < D.Cfg("b1NadeMax") then
            if math.random() < D.Cfg(k.poppers and "ctPopperLobChance" or "b1NadeChance") then
                self:Face(pos, 0.3)
                self:ThrowNade(pos)
            else
                self.nextNade = now + 5
            end
        elseif k.rockets and not k.direct and now >= self.nextRocket and d > D.Cfg("b2RocketMin") and d < D.Cfg("b2RocketMax") then   -- (rocket droid: needs sight)
            self:Face(pos, 0.3)
            self:FireRocket(pos)
        end
    end

end
