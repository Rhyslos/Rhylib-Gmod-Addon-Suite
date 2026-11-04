--[[
    Field structure (rhylib_logistics): placed with the E-tool or the
    repair tool (rhylib/logistics/sv_30_build.lua). First a hologram:
    nothing collides with it, everyone sees it see-through and blue,
    filling up as it's built. Built: a solid, frozen prop with the
    structure's health (L.STRUCTURES), damaged by bolts and explosions,
    broken at 0, repaired with the repair tool. Not saved.

    Networked: DT Int Kind (index in L.STRUCTURES), Float Progress (0-1,
    sent at most every 0.1 s while being built), Bool Built, Int Health,
    Int MaxHealth (the built structure's, for the repair tool's readout),
    String Owner (SteamID64 of whoever placed it).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Structure"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local FALLBACK = "models/props_c17/concrete_barrier001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Kind")
    self:NetworkVar("Int", 1, "SHealth")
    self:NetworkVar("Int", 2, "SMaxHealth")
    self:NetworkVar("Float", 0, "Progress")
    self:NetworkVar("Bool", 0, "Built")
    self:NetworkVar("String", 0, "OwnerSid")
end

function ENT:Def()
    local L = Rhylib.Logistics
    return L and L.StructureAt(self:GetKind())
end

if SERVER then
    function ENT:Initialize()
        local def = self:Def()
        local m = def and def.model or FALLBACK
        if not util.IsValidModel(m) then m = FALLBACK end
        self:SetModel(m)
        -- (a hologram: no collision at all; traces find it by its box, L.AimedStructure)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:SetRenderMode(RENDERMODE_TRANSCOLOR)
        self:DrawShadow(false)
        local L = Rhylib.Logistics
        if L then L.structures[self] = true end
    end

    -- Turns the hologram into the solid prop.
    function ENT:Finish()
        if self:GetBuilt() then return end
        local def = self:Def()
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:SetRenderMode(RENDERMODE_NORMAL)
        self:DrawShadow(true)
        local hp = math.max(1, math.floor(def and def.health or 500))
        self:SetSMaxHealth(hp)
        self:SetSHealth(hp)
        self:SetProgress(1)
        self:SetBuilt(true)
        self:EmitSound("physics/concrete/concrete_impact_hard" .. math.random(1, 3) .. ".wav", 70)
    end

    function ENT:OnTakeDamage(dmg)
        if not self:GetBuilt() or self.broken then return end
        self.hpf = nil   -- (repairing starts again from the health it has now)
        local hp = self:GetSHealth() - math.ceil(dmg:GetDamage())
        if hp <= 0 then
            self.broken = true
            local ed = EffectData()
            ed:SetOrigin(self:WorldSpaceCenter())
            ed:SetScale(2)
            util.Effect("Explosion", ed, true, true)
            self:EmitSound("physics/concrete/concrete_break" .. math.random(2, 3) .. ".wav", 80)
            self:Remove()
            return
        end
        self:SetSHealth(hp)
    end

    function ENT:OnRemove()
        local L = Rhylib.Logistics
        if L then L.structures[self] = nil end
    end
    return
end

function ENT:Initialize()
    local L = Rhylib.Logistics
    if L then L.structures[self] = true end
end

function ENT:OnRemove()
    local L = Rhylib.Logistics
    if L then L.structures[self] = nil end
end

local HOLO = Material("models/wireframe")

function ENT:Draw()
    if self:GetBuilt() then self:DrawModel() end
end

function ENT:DrawTranslucent()
    if self:GetBuilt() then return end
    -- Hologram: see-through blue, brighter as it fills; a wireframe over it.
    local p = self:GetProgress()
    render.SetBlend(0.25 + 0.45 * p)
    render.SetColorModulation(0.35, 0.7, 1)
    self:DrawModel()
    render.SetColorModulation(1, 1, 1)
    render.SetBlend(1)
    render.MaterialOverride(HOLO)
    render.SetColorModulation(0.4, 0.8, 1)
    render.SetBlend(0.35)
    self:DrawModel()
    render.SetBlend(1)
    render.SetColorModulation(1, 1, 1)
    render.MaterialOverride(nil)
end
