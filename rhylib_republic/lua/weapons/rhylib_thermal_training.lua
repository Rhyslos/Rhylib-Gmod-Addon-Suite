--[[
    Training thermal detonator: works like the real one (timed, impact,
    breaching charge with the skill), but the blast only takes sim health
    (rhylib_training) and hurts training droids. Yellow. From the training
    ammo cabinet.
]]
AddCSLuaFile()
SWEP.Base = "rhylib_thermal"
SWEP.PrintName = "Thermal detonator (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.Training = true
SWEP.TrainingOf = "rhylib_thermal"
SWEP.InvCategory = "training"
SWEP.PropColor = Color(255, 225, 90)
SWEP.ImpactColor = Color(255, 185, 70)
