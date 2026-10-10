--[[
    Training droid popper: works like the real one (stuns players in range
    the same way), but its EMP only takes out training droids. Orange blast.
    From the training ammo cabinet; still needs the Droid popper skill.

    Class rhylib_droidpopper_training, shared (AddCSLuaFile). Everything not set here comes from
    SWEP.Base (the real one). Training = true is what makes its bolts,
    rockets and blasts training ones (rhylib_weapons, rhylib_training);
    TrainingOf tells rhylib_skills which real weapon it stands for;
    InvCategory "training" gives the yellow stripe in the inventory.
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
