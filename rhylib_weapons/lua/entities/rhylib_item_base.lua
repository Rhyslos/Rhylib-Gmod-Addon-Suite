--[[
    Base for pick-up items. Press E on it to pick it up.
    Derived items set ENT.Model and ENT.Kind (an ammo kind from
    W.MagTypes, or "cell"), or override ENT:GiveTo(ply), which returns
    true if the player took it. With rhylib_inventory they go into the
    inventory, without it into the ammo pouch.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Rhylib item"
ENT.Category = "Rhylib: Items & ammo"
ENT.Spawnable = false
ENT.Model = "models/items/boxmrounds.mdl"
ENT.PickupSound = "items/ammo_pickup.wav"

function ENT:Initialize()
    if CLIENT then return end
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

if SERVER then
    function ENT:GiveTo(ply)
        if not self.Kind then return false end
        return Rhylib.Weapons.Pouch.Add(ply, self.Kind, 1)
    end

    function ENT:Use(activator)
        if not IsValid(activator) or not activator:IsPlayer() then return end
        if self:GiveTo(activator) then
            activator:EmitSound(self.PickupSound, 60)
            self:Remove()
        else
            activator:PrintMessage(HUD_PRINTCENTER, "No room for this")
        end
    end
end
