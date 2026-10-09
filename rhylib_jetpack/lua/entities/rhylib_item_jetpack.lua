-- Spawn menu entry for a jetpack. Picking it up wears it if the Back slot is free.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_world_item"
ENT.PrintName = "Jetpack"
ENT.Category = "Rhylib: Items & ammo"
-- (its base is rhylib_inventory's world item: only spawnable with it installed)
ENT.Spawnable = Rhylib ~= nil and Rhylib.Inventory ~= nil

if SERVER then
    function ENT:Initialize()
        if not self.SetItem then self:Remove() return end   -- (no rhylib_inventory)
        if not self.itemId then self:SetItem("jetpack", 1, {}) end
        baseclass.Get("rhylib_world_item").Initialize(self)
    end
end
