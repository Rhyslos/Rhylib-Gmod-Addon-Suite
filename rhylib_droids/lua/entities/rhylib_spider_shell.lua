--[[
    Spider droid shell: an explosive round from the DSD1 dwarf spider droid
    (entities/rhylib_spider.lua) that looks like a droid blaster bolt (the
    B1's red bolt, rhylib_weapons BoltColor 11: beam, white core, glow;
    a training spider's: the training droids' orange, BoltColor 8),
    spiderShellSize times as big. Flies straight (no gravity) at the
    speed the spider gives it (the B1's bolt speed), moved by hand each
    tick with one trace, so it never tunnels; flies through droids. On
    impact: Rhylib.Weapons.Explode with kind "spidershell", tier 2 (hook
    Rhylib.Explosion; stealth hearing), spiderShellRadius /
    spiderShellDamage, plus spiderShellDirect to what it hit; it knocks
    players down only where the blast does weapons knockMin or more
    (close to the impact), never with spiderShellKnock off. A training
    spider's shell (r.training) only takes sim health.

    Shared entity. Fields set before Spawn: s.vel (velocity), s.owner (the
    spider, credited), s.training, s.size (look size multiplier).
    Training (Bool) and Size (Float) are DT vars for the look. Listed in
    Rhylib.Droids.spiderShells while it flies (the spiderShellMax cap).
    Gone after 8 s, in the sky, or without rhylib_weapons.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Spider droid shell"
ENT.Category = "Rhy's Droids"
ENT.Model = "models/hunter/blocks/cube025x025x025.mdl"   -- (never drawn: only its bolt look)
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Training")
    self:NetworkVar("Float", 0, "Size")
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
        self:SetSize(math.Clamp(tonumber(self.size) or 1, 0.25, 6))
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
    -- The droids' bolt looks (rhylib_weapons cl_10_bolts STYLES 11 and 8),
    -- times the shell's Size.
    local BEAM = Material("trails/laser")
    local GLOW = Material("sprites/light_glow02_add")
    local CORE = Color(255, 255, 255, 220)
    local LOOK = { color = Color(255, 30, 25), length = 100, width = 10, glow = 26, core = true }
    local LOOK_TRAINING = { color = Color(255, 160, 40), length = 70, width = 5, glow = 14 }

    function ENT:Initialize()
        self.firstPos = self:GetPos()
    end

    local function size(self)
        local m = self:GetSize()
        return m > 0 and m or 1
    end

    function ENT:Think()
        -- (bounds along its flight: the tail trails behind it)
        local m = size(self)
        if self.boundsSize ~= m then
            self.boundsSize = m
            local r = 30 * m
            self:SetRenderBounds(Vector(-LOOK.length * m - r, -r, -r), Vector(r, r, r))
        end
    end

    function ENT:Draw() end

    local tail = Vector()
    function ENT:DrawTranslucent()
        local look = self:GetTraining() and LOOK_TRAINING or LOOK
        local m = size(self)
        local pos = self:GetPos()
        local d = self:GetForward()
        self.firstPos = self.firstPos or pos
        local len = math.min(look.length * m, pos:Distance(self.firstPos) + 1)
        tail:SetUnpacked(pos.x - d.x * len, pos.y - d.y * len, pos.z - d.z * len)
        render.SetMaterial(BEAM)
        render.DrawBeam(tail, pos, look.width * m, 0, 1, look.color)
        if look.core then render.DrawBeam(tail, pos, look.width * m * 0.3, 0, 1, CORE) end
        render.SetMaterial(GLOW)
        render.DrawSprite(pos, look.glow * m, look.glow * m, look.color)
    end
end
