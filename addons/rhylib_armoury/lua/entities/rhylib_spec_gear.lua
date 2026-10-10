-- Specialist gear rack: role equipment (medical kits for medics, cuffs and
-- batons for MPs, ...). Endless, issued; filtered by role like the weapons rack.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Specialist gear"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "spec"
ENT.SpecKind = "gear"
ENT.ModelKey = "specGear"
ENT.Hint = "Role equipment · Press E"
