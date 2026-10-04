--[[
    Training DP-23: the DP-23 with training magazines only. Its yellow
    bolts take "sim health" instead of real health (rhylib_training) and
    hurt training droids only. Handed out by the training armoury.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dp23"
SWEP.PrintName = "DP-23 (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Training = true
SWEP.TrainingOf = "rhylib_dp23"   -- (skills treat it as the real gun)
SWEP.BoltColor = 7             -- training yellow
SWEP.InvCategory = "training"
SWEP.Mags = { "mag_small_t" }
SWEP.FireModes = { "semi", "auto" }   -- (no stun mode: training bolts take sim health only)
