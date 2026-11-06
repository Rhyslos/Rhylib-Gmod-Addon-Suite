--[[
    Spider droid shell: a slow glowing explosive round from the DSD1 dwarf
    spider droid (entities/rhylib_spider.lua). Flies straight (no gravity),
    moved by hand each tick with one trace, so it never tunnels; flies
    through droids. On impact: Rhylib.Weapons.Explode with kind
    "spidershell", tier 2 (hook Rhylib.Explosion; stealth hearing),
    spiderShellRadius / spiderShellDamage, plus spiderShellDirect to what
    it hit; it knocks players down only where the blast does weapons
    knockMin or more (close to the impact), never with spiderShellKnock
    off. A training spider's shell (r.training) only takes sim health.

    Shared entity. Fields set before Spawn: s.vel (velocity), s.owner (the
    spider, credited), s.training. Training is a DT Bool for the glow
    colour. Listed in Rhylib.Droids.spiderShells while it flies (the
    spiderShellMax cap). Gone after 8 s, in the sky, or without
    rhylib_weapons.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Spider droid shell"
ENT.Category = "Rhy's Droids"
ENT.Model = "models/hunter/blocks/cube025x025x025.mdl"   -- (never drawn: only its glow)
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Training")
end

if SERVER then
    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:DrawShadow(false)
        self.rhylibDroidShot = true   -- (counts as a droid's when its spider is gone: no droid damage, no mines)
        self:SetTraining(self.training and true or false)
        self.vel = self.vel or Vector(0, 0, 0)
        self.dieAt = CurTime() + 8
        local me = self
        self.filterFn = function(e) return e ~= me and not e.IsRhylibDroid end
        self:SetAngles(self.vel:Angle())
        local D = Rhylib.Droids
        if D then
            D.spiderShells = D.spiderShells or {}
            D.spiderShells[self] = true
        end
        util.SpriteTrail(self, 0, self.training and Color(255, 170, 50) or Color(255, 90, 40), true, 14, 0, 0.35, 1 / 14 * 0.5, "trails/laser.vmt")
    end

    function ENT:Explode(pos, normal, hit)
        if self.done then return end
        self.done = true
        local D, W = Rhylib.Droids, Rhylib.Weapons
        if W and W.Explode then
            local owner = IsValid(self.owner) and self.owner or self
            local radius = D.Cfg("spiderShellRadius")
            local direct = D.Cfg("spiderShellDirect")
            local knock
            if not D.Cfg("spiderShellKnock") then knock = false end
            W.Explode({
                pos = pos + normal * 4, radius = radius, damage = D.Cfg("spiderShellDamage"),
                attacker = owner, inflictor = self, training = self.training,
                tier = 2, kind = "spidershell",
                effectData = { normal = normal, magnitude = 1, scale = 1 },
                direct = IsValid(hit) and not hit:IsWorld() and direct > 0 and not self.training and { ent = hit, damage = direct } or nil,
                knock = knock,
                shake = { 4, 100, 0.5, radius * 3 },
                decal = not self.training, decalFilter = self,
            })
        end
        self:Remove()
    end

    function ENT:Think()
        local now = CurTime()
        if now > self.dieAt then self:Remove() return end
        local from = self:GetPos()
        local to = from + self.vel * engine.TickInterval()
        trData.start, trData.endpos = from, to
        trData.filter = self.filterFn
        util.TraceLine(trData)
        if tr.HitSky then self:Remove() return end
        if tr.Hit then
            self:Explode(tr.HitPos, tr.HitNormal, tr.Entity)
            return
        end
        self:SetPos(to)
        self:NextThink(now)
        return true
    end

    function ENT:OnRemove()
        local D = Rhylib.Droids
        if D and D.spiderShells then D.spiderShells[self] = nil end
    end
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local RED = Color(255, 80, 35)
    local ORANGE = Color(255, 175, 50)
    local CORE = Color(255, 235, 200)

    function ENT:Initialize()
        self:SetRenderBounds(Vector(-40, -40, -40), Vector(40, 40, 40))
    end

    function ENT:Draw() end

    function ENT:DrawTranslucent()
        local pos = self:GetPos()
        render.SetMaterial(GLOW)
        local s = 56 + 8 * math.sin(CurTime() * 30)
        render.DrawSprite(pos, s, s, self:GetTraining() and ORANGE or RED)
        render.DrawSprite(pos, 18, 18, CORE)
    end
end
