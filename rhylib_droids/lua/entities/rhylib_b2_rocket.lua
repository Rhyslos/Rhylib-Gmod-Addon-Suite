--[[
    B2 wrist rocket: a small rocket lobbed high that drops onto its target.
    Moved by hand each tick (gravity, one trace per tick), so it never
    tunnels. Blast: config b2RocketDamage / b2RocketRadius, purple EMP-style
    effect (rhylib_republic's rhylib_emp, colour 1). Training droids' rockets
    (r.training) only take sim health (orange-yellow).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "B2 rocket"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Training")
end

if SERVER then
    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    function ENT:Initialize()
        self:SetModel("models/weapons/w_missile_closed.mdl")
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
        self.vel.z = self.vel.z - math.abs(physenv.GetGravity().z) * dt
        local to = from + self.vel * dt
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
