AddCSLuaFile()

SWEP.Base = "rhylib_med_base"
SWEP.PrintName = "Medkit"
SWEP.Spawnable = true
SWEP.Category = "Rhylib: Medical"  -- the spawn menu reads it from this file, not the base
SWEP.CanSelf = true
SWEP.OpensMenu = true
SWEP.Hint = "LMB  treat someone   ·   RMB  treat yourself   (drag onto a body part)"

-- One use each. Stacks 3 for troopers, 5 for medics (config medkitStack /
-- medkitStackMedic, at most InvStack).
SWEP.InvW, SWEP.InvH = 1, 1
SWEP.InvStack = 10
SWEP.InvWeight = 0.3
