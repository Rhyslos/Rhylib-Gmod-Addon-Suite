-- Medical holotable (entity, shared): medics upload medical records here and
-- read them all (window: Records and Bans only). Built on rhylib_bn_computer;
-- the server tells them apart by class (Data key "__medical", D.MED_KEY).
-- rhylib_medical also counts it as a med bay fixture.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_bn_computer"
ENT.PrintName = "Medical holotable"
ENT.Category = "Rhylib: Terminals"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ModelKey = "medical"

if CLIENT then
    function ENT:LabelText()
        return self.PrintName, "Medical records · Press E"
    end
end
