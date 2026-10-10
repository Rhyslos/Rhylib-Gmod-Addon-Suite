-- First aid kit (shared SWEP, base rhylib_med_base). Medics only. LMB on
-- a downed player revives, LMB someone standing / RMB yourself opens the
-- injury menu (simplified system: heals to full at once). Holds a charge.
AddCSLuaFile()

SWEP.Base = "rhylib_med_base"
SWEP.PrintName = "First aid kit"
SWEP.Spawnable = true
SWEP.Category = "Rhylib: Medical"  -- the spawn menu reads it from this file, not the base
SWEP.CanSelf = true
SWEP.OpensMenu = true
SWEP.Hint = "LMB  treat someone / revive the downed   ·   RMB  treat yourself"
SWEP.SimpleHint = "LMB  heal someone to full / revive the downed   ·   RMB  heal yourself"   -- (simplified medical system)

-- Doesn't stack. Holds a charge (config firstAidCharge health), kept by the
-- inventory item as fill and shown as %.
SWEP.InvW, SWEP.InvH = 2, 1
SWEP.InvCharge = true
SWEP.InvWeight = 0.8

-- Charge (0-1) is networked so the HUD hint can show it; the server keeps
-- it in step with the inventory item (Med.SpendCharge).
function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "Charge")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if SERVER then self:SetCharge(1) end
end

-- rhylib_inventory hands the item's data (fill) to the weapon it gives.
function SWEP:SetInventoryData(data)
    self:SetCharge(data and data.fill or 1)
end

if CLIENT then
    function SWEP:ChargeText()
        return math.ceil(self:GetCharge() * 100) .. "% charge"
    end
end
