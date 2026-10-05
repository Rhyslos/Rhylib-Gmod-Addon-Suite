-- Medical crate: an assortment of medical kits (config "medCrate"). Runs
-- out; stays empty until an admin runs rhylib_crate_refill.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Medical crate"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "crate"
ENT.ModelKey = "medcrate"
ENT.CrateStock = "medCrate"
ENT.Hint = "Medical supplies · Press E"
