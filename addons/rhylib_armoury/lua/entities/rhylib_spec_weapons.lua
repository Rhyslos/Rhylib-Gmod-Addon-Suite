-- Specialist weapons rack: role weapons (stun guns for MPs, ...). Endless,
-- issued; each player sees only what their role allows (config "roles").
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Specialist armoury"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "spec"
ENT.SpecKind = "weapons"
ENT.ModelKey = "specWeapons"
ENT.Hint = "Role weapons · Press E"
