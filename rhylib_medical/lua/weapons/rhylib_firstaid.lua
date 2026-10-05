AddCSLuaFile()

SWEP.Base = "rhylib_med_base"
SWEP.PrintName = "First aid kit"
SWEP.Spawnable = true
SWEP.Category = "Rhylib: Medical"  -- the spawn menu reads it from this file, not the base
SWEP.CanSelf = true
SWEP.OpensMenu = true
SWEP.Hint = "LMB  treat someone / revive the downed   ·   RMB  treat yourself"

-- Doesn't stack. Holds a charge (config firstAidCharge health), kept by the
-- inventory item as fill and shown as %.
SWEP.InvW, SWEP.InvH = 2, 1
SWEP.InvCharge = true
SWEP.InvWeight = 0.8

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "Charge")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then self:SetCharge(1) end
end

function SWEP:SetInventoryData(data)
    self:SetCharge(data and data.fill or 1)
end

if CLIENT then
    function SWEP:ChargeText()
        return math.ceil(self:GetCharge() * 100) .. "% charge"
    end
end
