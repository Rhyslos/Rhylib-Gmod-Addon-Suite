-- Revive kit (shared SWEP, base rhylib_med_base). Medics: LMB on a downed
-- player revives (reviveKitTime s, to reviveKitHealth of max health). One
-- kit per revive.
AddCSLuaFile()

SWEP.Base = "rhylib_med_base"
SWEP.PrintName = "Revive kit"
SWEP.Spawnable = true
SWEP.Category = "Rhylib: Medical"  -- the spawn menu reads it from this file, not the base
SWEP.Hint = "LMB  revive a downed player (medics)"

SWEP.InvW, SWEP.InvH = 1, 1
SWEP.InvStack = 2
SWEP.InvWeight = 0.4
