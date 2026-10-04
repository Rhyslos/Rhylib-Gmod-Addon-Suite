--[[
    Training Z-6: the Z-6 with training magazines only. Its yellow
    bolts take "sim health" instead of real health (rhylib_training) and
    hurt training droids only. Handed out by the training armoury.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_z6"
SWEP.PrintName = "Z-6 (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Training = true
SWEP.TrainingOf = "rhylib_z6"   -- (skills treat it as the real gun)
SWEP.BoltColor = 7             -- training yellow
SWEP.InvCategory = "training"
SWEP.Mags = { "mag_large_t", "mag_medium_t", "mag_small_t" }
SWEP.MagSkills = { mag_large_t = "heavy_feed" }
