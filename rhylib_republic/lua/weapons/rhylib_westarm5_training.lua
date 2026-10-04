--[[
    Training Westar-M5: the Westar-M5 with training magazines only. Its yellow
    bolts take "sim health" instead of real health (rhylib_training) and
    hurt training droids only. Handed out by the training armoury.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_westarm5"
SWEP.PrintName = "Westar-M5 (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Training = true
SWEP.TrainingOf = "rhylib_westarm5"   -- (skills treat it as the real gun)
SWEP.BoltColor = 7             -- training yellow
SWEP.InvCategory = "training"
SWEP.Mags = { "mag_medium_t", "mag_small_t" }
SWEP.FireModes = { "semi", "auto" }   -- (no stun mode: training bolts take sim health only)
