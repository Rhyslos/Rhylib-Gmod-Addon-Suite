--[[
    Training RPS-6: the RPS-6 with training magazines only. Its yellow
    bolts take "sim health" instead of real health (rhylib_training) and
    hurt training droids only. Handed out by the training armoury.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_rps6"
SWEP.PrintName = "RPS-6 (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Training = true
SWEP.TrainingOf = "rhylib_rps6"   -- (skills treat it as the real gun)
SWEP.BoltColor = 9             -- training yellow
SWEP.InvCategory = "training"
SWEP.Mags = { "rocket_t" }
SWEP.FireModes = { "semi" }   -- (no lock-on with training rockets)
-- (the rocket's blast only takes sim health, rhylib_training)
