--[[
    Med sofa (med bay furniture). Press E to lie down on it, E or Jump to
    get up. Looks only: no healing. Logic: rhylib_medical sv_40_medbay.lua
    (Med.SofaUse). Saved per map with rhylib_medical_save.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Med sofa"
ENT.Category = "Rhylib: Medical"
ENT.Spawnable = true
ENT.AdminOnly = true

local FALLBACK = "models/props_c17/FurnitureCouch001a.mdl"

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    ent:Spawn()
    ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z))
    return ent
end

function ENT:Initialize()
    if CLIENT then return end
    local Med = Rhylib.Medical
    local m = Med and Med.Cfg("sofaModel") or FALLBACK
    if not isstring(m) or not util.IsValidModel(m) then m = FALLBACK end
    self:SetModel(m)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

if SERVER then
    function ENT:Use(ply)
        local Med = Rhylib.Medical
        if Med and Med.SofaUse and IsValid(ply) and ply:IsPlayer() then Med.SofaUse(self, ply) end
    end

    function ENT:OnRemove()
        local Med = Rhylib.Medical
        local u = self.rhylibUser
        if Med and Med.SofaUp and IsValid(u) then Med.SofaUp(u) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local Med = Rhylib.Medical
        if Med and Med.DrawEntLabel then Med.DrawEntLabel(self, "Med sofa", "Press E to lie down") end
    end
end
