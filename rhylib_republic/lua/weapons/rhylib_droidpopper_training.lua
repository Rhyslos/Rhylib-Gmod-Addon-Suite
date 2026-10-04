--[[
    Training droid popper: works like the real one (stuns players in range
    the same way), but its EMP only takes out training droids. Orange blast.
    From the training ammo cabinet; still needs the Droid popper skill.
]]
AddCSLuaFile()
SWEP.Base = "rhylib_droidpopper"
SWEP.PrintName = "Droid popper (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.Training = true
SWEP.TrainingOf = "rhylib_droidpopper"
SWEP.InvCategory = "training"
SWEP.PropColor = Color(255, 210, 110)
SWEP.ImpactColor = Color(255, 170, 80)
