--[[
    Training DC-17: the DC-17 with training magazines only. Its yellow
    bolts take "sim health" instead of real health (rhylib_training) and
    hurt training droids only. Handed out by the training armoury.

    Class rhylib_dc17_training, shared (AddCSLuaFile). Everything not set here comes from
    SWEP.Base (the real one). Training = true is what makes its bolts,
    rockets and blasts training ones (rhylib_weapons, rhylib_training);
    TrainingOf tells rhylib_skills which real weapon it stands for;
    InvCategory "training" gives the yellow stripe in the inventory.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "DC-17 (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Training = true
SWEP.TrainingOf = "rhylib_dc17"   -- (skills treat it as the real gun)
SWEP.BoltColor = 7             -- training yellow
SWEP.InvCategory = "training"
SWEP.Mags = { "mag_small_t" }
SWEP.FireModes = { "semi", "dual" }   -- (no stun mode: training bolts take sim health only)
