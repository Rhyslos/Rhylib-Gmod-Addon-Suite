-- Medical holotable: medics upload medical records here and read them all.
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
