-- Personal locker: 36 slots, claimed by one player, lockable. Contents are
-- saved to the owner's SteamID.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Personal locker"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "locker"
ENT.ModelKey = "locker"

if CLIENT then
    function ENT:SubText()
        local name = self:GetOwnerName()
        if self:GetOwnerSid() == "" then return "Free · Press E to claim" end
        return name .. (self:GetLocked() and " · Locked" or " · Open to all")
    end
end
