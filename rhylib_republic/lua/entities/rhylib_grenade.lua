--[[
    A thrown grenade (spawned by rhylib_grenade_base). kind:
      fuse    explodes `fuse` seconds after the throw
      impact  explodes on its first hit (armed after a moment, so it
              can't go off in the thrower's hand)
      emp     fuse; kills Rhylib droids (Rhylib.Droids.active) in range
              and in sight, stuns players there (rhylib_mp MP.Stun), no
              damage to anything else
      breach  a breaching charge stuck to a surface (rhylib_grenade_base
              breach mode): beeps when placed and faster and faster over
              the last 3 s, then a small blast (riot shields facing it
              block it, rhylib_weapons sh_60_shield) that forces doors
              nearby open and holds them open for a while
      flash   fuse; players in range and in sight are stunned (rhylib_mp),
              droids aim worse for a few seconds (Rhylib.Droids.Suppress)
    Blinks (red, blue for EMP) faster as the fuse runs down.
]]

AddCSLuaFile()

local Config = Rhylib.Config

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Grenade"
ENT.Spawnable = false

local KIND = { fuse = 1, impact = 2, emp = 3, emp_impact = 4, breach = 5, flash = 6 }   -- (4: EMP on impact)
ENT.KIND_BREACH = 5

ENT.FlashRadius = 450   -- flash charge: players and droids within this

ENT.Radius = 300        -- frag: blast radius
ENT.Damage = 140        -- frag: damage at the centre
ENT.EmpRadius = 380     -- EMP: droids within this

-- Where the grenade really is: the ball's centre.
function ENT:Centre()
    return self:GetPos()
end

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Kind")
    self:NetworkVar("Float", 0, "Boom")   -- when the fuse ends (0 = impact)
    self:NetworkVar("Bool", 0, "Ball")    -- physics is a plain ball (the model has no collision mesh)
    self:NetworkVar("Float", 1, "Radius") -- the ball's radius
    self:NetworkVar("Vector", 0, "Offset") -- where the grenade sits in the model (its collision mesh centre)
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl")
        if self.kind == "breach" then
            -- Stuck where it was placed: no physics, moves with a door.
            -- (the physics mesh is only measured, so the model is drawn
            -- centred on the spot like a thrown one)
            local c = Vector(0, 0, 0)
            self:PhysicsInit(SOLID_VPHYSICS)
            local mesh = self:GetPhysicsObject()
            if IsValid(mesh) then
                local mn, mx = mesh:GetAABB()
                c = (mn + mx) * 0.5
            end
            self:PhysicsDestroy()
            self:SetOffset(c)
            self:SetBall(true)
            self:SetMoveType(MOVETYPE_NONE)
            self:SetSolid(SOLID_NONE)
            self:SetKind(5)
            self:SetBoom(CurTime() + (self.fuse or 6))
            if IsValid(self.stuckTo) then self:SetParent(self.stuckTo) end
            self.dieAt = CurTime() + 60
            self.nextBeep = 0
            return
        end
        -- The model's bounds are far bigger than the grenade, and its own
        -- collision mesh bounces like a cylinder. So: measure that mesh,
        -- then use a ball of its size at its centre (the model is drawn
        -- around the ball, client side).
        local c, r = Vector(0, 0, 0), 3
        self:PhysicsInit(SOLID_VPHYSICS)
        local mesh = self:GetPhysicsObject()
        if IsValid(mesh) then
            local mn, mx = mesh:GetAABB()
            c = (mn + mx) * 0.5
            local size = mx - mn
            r = math.Clamp(math.max(size.x, size.y, size.z) * 0.5, 1.5, 6)
        end
        self:SetOffset(c)
        self:PhysicsInitSphere(r, "metal")
        self:SetBall(true)
        self:SetRadius(r)
        self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetMass(2)
            phys:SetDamping(0.2, 2)
            phys:Wake()
        end
        local k = KIND[self.kind or "fuse"] or 1
        self:SetKind(k)
        self:SetBoom((k == 2 or k == 4) and 0 or CurTime() + (self.fuse or 3))
        self.armed = CurTime() + 0.15
        self.dieAt = CurTime() + 20   -- an impact one that never hits anything
    end

    function ENT:PhysicsCollide(data)
        if data.Speed > 120 and (self.nextBounce or 0) < CurTime() then
            self.nextBounce = CurTime() + 0.1
            self:EmitSound("physics/metal/metal_grenade_impact_hard" .. math.random(1, 3) .. ".wav", 70)
        end
        -- Can't remove inside the physics callback: blow up on the next think.
        local k = self:GetKind()
        if (k == 2 or k == 4) and CurTime() >= self.armed and data.HitEntity ~= self.thrower then
            self.boomNow = true
            self:NextThink(CurTime())
        end
    end

    function ENT:Think()
        local boom = self:GetBoom()
        if self.boomNow or (boom > 0 and CurTime() >= boom) then
            self:Explode()
            return
        end
        if CurTime() > self.dieAt then self:Remove() return end
        -- Breaching charge: a beep when placed, then faster and faster
        -- over the last 3 s.
        if self:GetKind() == 5 and CurTime() >= self.nextBeep then
            local left = boom - CurTime()
            if self.nextBeep == 0 or left <= 3 then
                self:EmitSound("buttons/blip1.wav", 75, left <= 1 and 135 or 120)
            end
            self.nextBeep = left > 3 and (boom - 3) or (CurTime() + math.max(0.07, 0.5 * left / 3))
        end
        self:NextThink(CurTime() + 0.03)
        return true
    end

    function ENT:Explode()
        if self.done then return end
        self.done = true
        local pos = self:Centre()
        local attacker = IsValid(self.thrower) and self.thrower or self
        local k = self:GetKind()
        if k == 3 or k == 4 then
            self:Emp(pos, attacker)
        elseif k == 5 then
            self:Breach(pos, attacker)
        elseif k == 6 then
            self:Flash(pos, attacker)
        else
            local ed = EffectData()
            ed:SetOrigin(pos)
            util.Effect("Explosion", ed, true, true)
            -- (training grenades, e.g. from training droids: sim health only)
            local W = Rhylib.Weapons
            if self.training and W and W.TrainingBlast then
                W.TrainingBlast(pos, self.Radius, self.Damage, attacker, self)
            else
                util.BlastDamage(self, attacker, pos, self.Radius, self.Damage)
            end
            util.ScreenShake(pos, 6, 120, 0.8, self.Radius * 2)
            util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), self)
        end
        self:Remove()
    end

    -- Doors held open by breaching charges: [door] = { restore data }.
    local held = {}
    local DOOR = { func_door = true, func_door_rotating = true, prop_door_rotating = true }

    local function restoreDoor(door)
        local h = held[door]
        held[door] = nil
        if not (IsValid(door) and h) then return end
        if h.prop then
            door:SetKeyValue("returndelay", h.wait)
        else
            door:SetKeyValue("wait", h.wait)
        end
        door:Fire("Unlock")
        door:Fire("Close", "", 0.05)
        if h.locked then door:Fire("Lock", "", 0.1) end
    end

    local function forceDoor(door, attacker, hold)
        local prop = door:GetClass() == "prop_door_rotating"
        if not held[door] then
            local kv = door:GetKeyValues()
            held[door] = {
                prop = prop,
                wait = tostring((prop and kv.returndelay or kv.wait) or (prop and -1 or 4)),
                locked = door:GetInternalVariable("m_bLocked") == true,
            }
        end
        door:Fire("Unlock")
        if prop then
            door:SetKeyValue("returndelay", "-1")
            door:Fire("OpenAwayFrom", "!activator", 0, attacker, attacker)
        else
            door:SetKeyValue("wait", "-1")
            door:Fire("Open")
        end
        door:Fire("Lock", "", 0.1)   -- (nobody closes it early)
        timer.Create("Rhylib.Breach." .. door:EntIndex(), hold, 1, function() restoreDoor(door) end)
    end

    function ENT:Breach(pos, attacker)
        local ed = EffectData()
        ed:SetOrigin(pos)
        ed:SetMagnitude(1)
        ed:SetScale(1)
        util.Effect("Explosion", ed, true, true)
        local r = Config.Get("weapons", "breachRadius")
        local W = Rhylib.Weapons
        if self.training and W and W.TrainingBlast then
            W.TrainingBlast(pos, r, Config.Get("weapons", "breachDamage"), attacker, self)
        else
            util.BlastDamage(self, attacker, pos, r, Config.Get("weapons", "breachDamage"))
        end
        util.ScreenShake(pos, 8, 120, 0.6, r * 3)
        local hold = Config.Get("weapons", "breachHold")
        local doors = {}
        local stuck = self:GetParent()
        if IsValid(stuck) and DOOR[stuck:GetClass()] then doors[stuck] = true end
        for _, e in ipairs(ents.FindInSphere(pos, Config.Get("weapons", "breachDoors"))) do
            if IsValid(e) and DOOR[e:GetClass()] then doors[e] = true end
        end
        for door in pairs(doors) do forceDoor(door, attacker, hold) end
    end

    function ENT:Flash(pos, attacker)
        sound.Play("ambient/explosions/explode_9.wav", pos, 90, 160)
        sound.Play("ambient/energy/whiteflash.wav", pos, 85, 120)
        local light = EffectData()
        light:SetOrigin(pos)
        util.Effect("cball_explode", light, true, true)
        local r2 = self.FlashRadius * self.FlashRadius
        local MP = Rhylib.MP
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() then
                local eye = p:EyePos()
                if eye:DistToSqr(pos) <= r2 and not util.TraceLine({ start = pos, endpos = eye, mask = MASK_SOLID_BRUSHONLY }).Hit then
                    p:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 240), 1.5, 0.5)
                    if MP and MP.Stun then MP.Stun(p, attacker) end
                end
            end
        end
        local D = Rhylib.Droids
        if D and D.Suppress and D.active then
            for droid in pairs(D.active) do
                if IsValid(droid) and droid:Health() > 0 then
                    local c = droid:WorldSpaceCenter()
                    if c:DistToSqr(pos) <= r2 and not util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY }).Hit then
                        D.Suppress(droid, D.Cfg("flashTime"), D.Cfg("flashSuppress"))
                    end
                end
            end
        end
    end

    function ENT:Emp(pos, attacker)
        local ed = EffectData()
        ed:SetOrigin(pos)
        ed:SetRadius(self.EmpRadius)
        ed:SetFlags(0)
        ed:SetColor(self.training and 2 or 0)   -- (training: orange)
        util.Effect("rhylib_emp", ed, true, true)
        sound.Play("ambient/energy/whiteflash.wav", pos, 85, 110)
        sound.Play("ambient/energy/zap" .. math.random(1, 9) .. ".wav", pos, 80, 100)

        local r2 = self.EmpRadius * self.EmpRadius
        -- Players in range and in sight are stunned (rhylib_mp's stun,
        -- thrower included), with a zap on them. Not from clone NPCs'
        -- poppers (noStun: they're on your side).
        local MP = Rhylib.MP
        if MP and MP.Stun and not self.noStun then
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() then
                    local c = p:WorldSpaceCenter()
                    if c:DistToSqr(pos) <= r2 and not util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY }).Hit then
                        local zap = EffectData()
                        zap:SetOrigin(c)
                        zap:SetFlags(1)
                        zap:SetColor(self.training and 2 or 0)
                        util.Effect("rhylib_emp", zap, true, true)
                        MP.Stun(p, attacker)
                    end
                end
            end
        end

        local D = Rhylib.Droids
        for droid in pairs(D and D.active or {}) do
            -- (a training EMP only takes out training droids)
            if IsValid(droid) and droid:Health() > 0 and (droid.Training or not self.training) and not (self.noStun and droid.Training) then
                local c = droid:WorldSpaceCenter()
                if c:DistToSqr(pos) <= r2 then
                    local tr = util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY })
                    if not tr.Hit then
                        local zap = EffectData()
                        zap:SetOrigin(c)
                        zap:SetEntity(droid)
                        zap:SetFlags(1)
                        zap:SetColor(self.training and 2 or 0)
                        util.Effect("rhylib_emp", zap, true, true)
                        local dmg = DamageInfo()
                        dmg:SetDamage(droid:Health() + 100)
                        dmg:SetDamageType(DMG_SHOCK)
                        dmg:SetAttacker(attacker)
                        dmg:SetInflictor(self)
                        dmg:SetDamagePosition(c)
                        droid:TakeDamageInfo(dmg)
                    end
                end
            end
        end
    end
end

if CLIENT then
    -- rhylib_grenade_debug 1: draws the physics ball (green), the model's
    -- bounds (yellow), its origin (axes) and Centre() (white); prints the
    -- numbers once per grenade.
    local debugVar = CreateClientConVar("rhylib_grenade_debug", "0", false, false, "Show grenade physics and model bounds")

    function ENT:DrawDebug(prop)
        if not debugVar:GetBool() then return end
        render.SetColorMaterial()
        local r = self:GetRadius()
        if r > 0 then render.DrawWireframeSphere(self:GetPos(), r, 12, 12, Color(0, 255, 0), true) end
        local e = IsValid(prop) and prop or self
        local mins, maxs = e:GetModelBounds()
        render.DrawWireframeBox(e:GetPos(), e:GetAngles(), mins, maxs, Color(255, 220, 0), true)
        local o, a = e:GetPos(), e:GetAngles()
        render.DrawLine(o, o + a:Forward() * 6, Color(255, 0, 0), true)
        render.DrawLine(o, o + a:Right() * 6, Color(0, 255, 0), true)
        render.DrawLine(o, o + a:Up() * 6, Color(0, 120, 255), true)
        render.DrawSphere(self:Centre(), 0.6, 8, 8, Color(255, 255, 255))
        if not self.debugPrinted then
            self.debugPrinted = true
            local size = maxs - mins
            local off = self:GetOffset()
            print(string.format("[Rhylib] grenade model %s\n  bounds mins (%.2f %.2f %.2f) maxs (%.2f %.2f %.2f)\n  size (%.2f %.2f %.2f), collision mesh centre (%.2f %.2f %.2f), ball radius %.2f",
                self:GetModel(), mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z, size.x, size.y, size.z,
                off.x, off.y, off.z, r))
        end
    end

    function ENT:OnRemove()
        if IsValid(self.prop) then self.prop:Remove() end
    end

    local GLOW = Material("sprites/light_glow02_add")

    -- With a ball, the model (origin off to one side) is drawn centred on
    -- it with its own client model.
    function ENT:Draw()
        if not self:GetBall() then
            self:DrawModel()
        else
            local e = self.prop
            if not IsValid(e) then
                e = ClientsideModel(self:GetModel(), RENDERGROUP_OPAQUE)
                if not IsValid(e) then return end
                e:SetNoDraw(true)
                self.prop = e
            end
            e:SetColor(self:GetColor())
            e:SetPos(self:LocalToWorld(-self:GetOffset()))
            e:SetAngles(self:GetAngles())
            e:SetupBones()
            e:DrawModel()
        end
        self:DrawDebug(self.prop)
        local boom = self:GetBoom()
        local left = boom > 0 and math.max(boom - CurTime(), 0) or 1
        local rate = boom > 0 and Lerp(math.Clamp(left / 3, 0, 1), 12, 3) or 4
        if math.sin(CurTime() * rate * math.pi) > 0 then
            local k = self:GetKind()
            local col = (k == 3 or k == 4) and Color(90, 170, 255) or k == 6 and Color(255, 255, 220) or Color(255, 60, 40)
            render.SetMaterial(GLOW)
            render.DrawSprite(self:Centre(), 14, 14, col)
        end
    end
end
