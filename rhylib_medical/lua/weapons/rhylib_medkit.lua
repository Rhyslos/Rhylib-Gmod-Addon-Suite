-- Medkit (shared SWEP, base rhylib_med_base). Anyone can use one (unless
-- config medkitMedicOnly). LMB someone / RMB yourself treats them, worst
-- problem first (sv_20_actions.lua); in the simplified system it heals.
-- Single use; the stack size comes from config (hook Rhylib.ItemStack).
AddCSLuaFile()

SWEP.Base = "rhylib_med_base"
SWEP.PrintName = "Medkit"
SWEP.Spawnable = true
SWEP.Category = "Rhy's Medical"  -- the spawn menu reads it from this file, not the base
SWEP.CanSelf = true
SWEP.OpensMenu = true
SWEP.Hint = "LMB  treat someone   ·   RMB  treat yourself   (worst wound first)"
SWEP.SimpleHint = "LMB  heal someone   ·   RMB  heal yourself"   -- (simplified medical system)

-- One use each. Stacks 3 for troopers, 5 for medics (config medkitStack /
-- medkitStackMedic, at most InvStack).
SWEP.InvW, SWEP.InvH = 1, 1
SWEP.InvStack = 10   -- the largest stack allowed; the real size is per player
SWEP.InvWeight = 0.3
