-- Aqua droid: the B1 code (rhylib_b1) with the "aqua" row of Rhylib.Droids.KINDS:
-- a B2 that fires one heavy bolt a second (aquaRPM, aquaDamage) with aquaHealth;
-- model aquaModel (a missing one falls back to the B2's).
AddCSLuaFile()
ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "Aqua droid"
ENT.Category = "Rhy's B2 super battle droids"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "aqua"
