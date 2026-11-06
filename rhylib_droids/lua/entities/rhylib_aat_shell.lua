--[[
    AAT droid tank shell: the turret cannon's round (entities/rhylib_aat.lua).
    Looks like the spider droid's shell (the droids' red bolt: beam, white
    core, glow) aatShellSize times as big as a B1 bolt. Fired directly it
    flies straight (no gravity); as a mortar round (s.grav) it falls under
    gravity on a high arc. Moved by hand each tick with one trace, so it
    never tunnels; flies through droids. On impact: Rhylib.Weapons.Explode
    with kind "aatshell", tier 2 (hook Rhylib.Explosion; stealth hearing),
    aatCannonRadius / aatCannonDamage, plus aatCannonDirect to what it hit;
    knocks players down where the blast does weapons knockMin or more.

    Shared entity. Fields set before Spawn: s.vel (velocity), s.grav (true:
    falls), s.owner (the tank, credited), s.size (look size multiplier).
    Size (Float) is a DT var for the look; clients draw the tail along the
    way it moves. Gone after 12 s, in the sky, or without rhylib_weapons.
    A shell whose tank is gone is credited to itself (rhylibDroidShot: no
    droid damage, no mines).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "AAT tank shell"
ENT.Category = "Rhy's Droids"
ENT.Model = "models/hunter/blocks/cube025x025x025.mdl"   -- (never drawn: only its bolt look)
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
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
        self.rhylibDroidShot = true
        self:SetSize(math.Clamp(tonumber(self.size) or 1, 0.25, 10))
        self.vel = self.vel or Vector(0, 0, 0)
        self.dieAt = CurTime() + 20
        local me = self
        self.filterFn = function(e) return e ~= me and not e.IsRhylibDroid end
        self:SetAngles(self.vel:Angle())
    end

    function ENT:Explode(pos, normal, hit)
        if self.done then return end
        self.done = true
        local D, W = Rhylib.Droids, Rhylib.Weapons
        if W and W.Explode then
            local owner = IsValid(self.owner) and self.owner or self
            local radius = D.Cfg("aatCannonRadius")
            local direct = D.Cfg("aatCannonDirect")
            W.Explode({
                pos = pos + normal * 4, radius = radius, damage = D.Cfg("aatCannonDamage"),
                attacker = owner, inflictor = self,
                tier = 2, kind = "aatshell",
                effectData = { normal = normal, magnitude = 2, scale = 2 },
                direct = IsValid(hit) and not hit:IsWorld() and direct > 0 and { ent = hit, damage = direct } or nil,
                sound = { "ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", 100, 90 },
                shake = { 8, 120, 0.8, radius * 3 },
                decal = true, decalFilter = self,
            })
        end
        self:Remove()
    end

    function ENT:Think()
        local now = CurTime()
        if now > self.dieAt then self:Remove() return end
        local dt = engine.TickInterval()
        if self.grav then self.vel.z = self.vel.z - math.abs(physenv.GetGravity().z) * dt end
        local from = self:GetPos()
        local to = from + self.vel * dt
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
end

if CLIENT then
    local BEAM = Material("trails/laser")
    local GLOW = Material("sprites/light_glow02_add")
    local CORE = Color(255, 255, 255, 220)
    local COLOR = Color(255, 30, 25)
    local LENGTH, WIDTH, GLOWS = 100, 10, 26

    function ENT:Initialize()
        self.firstPos = self:GetPos()
        self.lastPos = self:GetPos()
        self.dir = self:GetForward()
    end

    local function size(self)
        local m = self:GetSize()
        return m > 0 and m or 1
    end

    function ENT:Think()
        local m = size(self)
        if self.boundsSize ~= m then
            self.boundsSize = m
            local r = LENGTH * m + 30 * m
            self:SetRenderBounds(Vector(-r, -r, -r), Vector(r, r, r))
        end
    end

    function ENT:Draw() end

    local tail = Vector()
    function ENT:DrawTranslucent()
        local m = size(self)
        local pos = self:GetPos()
        -- (the way it moves: a lobbed shell turns along its arc)
        local mv = pos - (self.lastPos or pos)
        if mv:LengthSqr() > 1 then
            mv:Normalize()
            self.dir = mv
            self.lastPos = pos
        end
        local d = self.dir or self:GetForward()
        self.firstPos = self.firstPos or pos
        local len = math.min(LENGTH * m, pos:Distance(self.firstPos) + 1)
        tail:SetUnpacked(pos.x - d.x * len, pos.y - d.y * len, pos.z - d.z * len)
        render.SetMaterial(BEAM)
        render.DrawBeam(tail, pos, WIDTH * m, 0, 1, COLOR)
        render.DrawBeam(tail, pos, WIDTH * m * 0.3, 0, 1, CORE)
        render.SetMaterial(GLOW)
        render.DrawSprite(pos, GLOWS * m, GLOWS * m, COLOR)
    end
end
