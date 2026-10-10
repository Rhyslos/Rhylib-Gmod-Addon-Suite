-- Supply crate full of small magazines. Runs out; stays empty until an
-- admin runs rhylib_crate_refill.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Supply crate (small mags)"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "crate"
ENT.ModelKey = "crate"
ENT.CrateMag = "mag_small"
ENT.Hint = "Small magazines · Press E"
