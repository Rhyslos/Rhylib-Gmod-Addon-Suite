-- Spawn menu entry for a backpack. Picking it up wears it if the Back slot is free.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_world_item"
ENT.PrintName = "Backpack"
ENT.Category = "Rhylib: Items & ammo"
ENT.Spawnable = true

if SERVER then
    function ENT:Initialize()
        if not self.itemId then self:SetItem("backpack", 1, {}) end
        baseclass.Get("rhylib_world_item").Initialize(self)
    end
end
