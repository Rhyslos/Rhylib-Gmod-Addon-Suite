--[[
    B2 wrist rocket: a small rocket lobbed high that drops onto its target
    (B2 mortar), or with r.direct (B2 rocket droid) one that flies level,
    without gravity, at r.diveAt and turns straight down into the floor
    b2DiveDist before it (or once it has passed it), so it works indoors.
    Moved by hand each tick (gravity, one trace per tick), so it never
    tunnels. Blast: config b2RocketDamage / b2RocketRadius, purple EMP-style
    effect (rhylib_republic's rhylib_emp, colour 1). Training droids' rockets
    (r.training) only take sim health (orange-yellow).

    Shared entity, made by ENT:FireRocket / ENT:FireDirectRocket in
    rhylib_b1.lua. Fields set before Spawn: r.vel (start velocity),
    r.owner (the droid, credited for the blast), r.training, and for the
    rocket droid r.direct + r.diveAt (aim point). Training is also a DT
    Bool so clients pick the glow colour. Gone after 8 s or in the sky.
    The blast effect needs rhylib_republic (rhylib_emp).
]]


AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "B2 rocket"
ENT.Category = "Rhylib: Droids"
ENT.Model = "models/weapons/w_missile_closed.mdl"   -- (Server settings > Models can swap it)
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Training")
end

if SERVER then
    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:SetModelScale(0.5, 0)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:SetTraining(self.training and true or false)
        self.vel = self.vel or Vector(0, 0, 0)
        self.dieAt = CurTime() + 8
        -- (droids don't set their friends' rockets off)
        local me = self
        self.filterFn = function(e) return e ~= me and not e.IsRhylibDroid end
        self:SetAngles(self.vel:Angle())
        local col = self.training and Color(255, 170, 50) or Color(190, 90, 255)
        util.SpriteTrail(self, 0, col, true, 10, 0, 0.5, 1 / 10 * 0.5, "trails/smoke.vmt")
        self:EmitSound("weapons/rpg/rocket1.wav", 70, 140)
    end

    function ENT:Explode(pos)
        if self.done then return end
        self.done = true
        local D = Rhylib.Droids
        local owner = IsValid(self.owner) and self.owner or self
        local radius, damage = D.Cfg("b2RocketRadius"), D.Cfg("b2RocketDamage")
        local W = Rhylib.Weapons
        if self.training then
            if W and W.TrainingBlast then W.TrainingBlast(pos, radius, damage, owner, self) end
        else
            util.BlastDamage(self, owner, pos, radius, damage)
            util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), self)
        end
        local ed = EffectData()
        ed:SetOrigin(pos)
        ed:SetRadius(radius)
        ed:SetFlags(0)
        ed:SetColor(self.training and 2 or 1)
        util.Effect("rhylib_emp", ed, true, true)
        util.ScreenShake(pos, 5, 100, 0.6, radius * 2)
        sound.Play("ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", pos, 85, 115)
        self:StopSound("weapons/rpg/rocket1.wav")
        self:Remove()
    end

    function ENT:Think()
        local now = CurTime()
        if now > self.dieAt then self:Remove() return end
        local dt = engine.TickInterval()
        local from = self:GetPos()
        local to
        if self.direct then
            -- Level flight, then a curved dive (a quarter ellipse) that ends
            -- pointing straight down onto the floor at the aim point.
            if not self.arc and self.diveAt then
                local to2 = Vector(self.diveAt.x - from.x, self.diveAt.y - from.y, 0)
                local v2 = Vector(self.vel.x, self.vel.y, 0)
                -- Eases off a little over the last b2SlowTime before the dive
                -- (owner: it came in too fast at the end).
                local D = Rhylib.Droids
                self.speed0 = self.speed0 or self.vel:Length()
                local window = self.speed0 * D.Cfg("b2SlowTime")
                local rem = to2:Length() - D.Cfg("b2DiveDist")
                if window > 0 and rem < window then
                    local p = math.Clamp(1 - rem / window, 0, 1)
                    p = p * p * (3 - 2 * p)   -- (smoothstep)
                    self.vel = self.vel:GetNormalized() * self.speed0 * Lerp(p, 1, D.Cfg("b2SlowMult"))
                end
                if to2:Length() <= Rhylib.Droids.Cfg("b2DiveDist") or to2:Dot(v2) <= 0 then
                    -- The floor under the aim point.
                    local g = util.TraceLine({ start = self.diveAt, endpos = self.diveAt - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
                    local floor = g.Hit and g.HitPos or (self.diveAt - Vector(0, 0, 70))
                    local a = math.max(to2:Length(), 1)
                    if to2:Dot(v2) <= 0 then a = 1 end
                    local b = math.max(from.z - floor.z, 1)
                    local dir = (to2:Dot(v2) > 0 and to2 or v2):GetNormalized()
                    -- (θ per second from the speed over about a quarter ellipse's length)
                    self.arc = { p0 = from, dir = dir, a = a, b = b, t = 0,
                        rate = self.vel:Length() / (math.pi * 0.25 * (a + b) + 1) * (math.pi * 0.5) }
                end
            end
            local arc = self.arc
            if arc then
                arc.t = math.min(arc.t + arc.rate * dt, math.pi * 0.5)
                local s, c = math.sin(arc.t), math.cos(arc.t)
                to = arc.p0 + arc.dir * (arc.a * s) - Vector(0, 0, arc.b * (1 - c))
                -- (heading along the curve: level at the start, straight down at the end)
                self.vel = (arc.dir * (arc.a * c) + Vector(0, 0, -arc.b * s)):GetNormalized() * self.vel:Length()
                -- At the end: keep going down until it hits the floor.
                if arc.t >= math.pi * 0.5 then to = to - Vector(0, 0, 40) end
            end
        else
            self.vel.z = self.vel.z - math.abs(physenv.GetGravity().z) * dt
        end
        to = to or (from + self.vel * dt)
        trData.start, trData.endpos = from, to
        trData.filter = self.filterFn
        util.TraceLine(trData)
        if tr.HitSky then self:Remove() return end
        if tr.Hit then
            self:Explode(tr.HitPos + tr.HitNormal * 4)
            return
        end
        self:SetPos(to)
        self:SetAngles(self.vel:Angle())
        self:NextThink(now)
        return true
    end

    function ENT:OnRemove()
        self:StopSound("weapons/rpg/rocket1.wav")
    end
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local PURPLE = Color(200, 110, 255)
    local ORANGE = Color(255, 175, 50)

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        local col = self:GetTraining() and ORANGE or PURPLE
        render.SetMaterial(GLOW)
        local s = 34 + 6 * math.sin(CurTime() * 40)
        render.DrawSprite(self:GetPos() - self:GetForward() * 8, s, s, col)
    end
end
