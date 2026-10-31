-- Bacta grenade (medics): a short fuse, then a low blue bacta mist on the
-- ground (rhylib_smoke_cloud, weapons bactaRadius / bactaLife) that doesn't
-- block the view. Players standing in it heal slowly, bleeding eases off
-- and a downed player's bleed-out is held (rhylib_medical Med.Bacta).
-- Only medic jobs may throw it; in the medical armoury (rhylib_armoury
-- roles.medic).
-- Class rhylib_bactagrenade, shared. Base rhylib_grenade_base.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Bacta grenade"
SWEP.Category = "Rhy's Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.GrenadeKind = "bacta"
SWEP.FuseTime = 1.5
SWEP.PropColor = Color(90, 190, 255)
SWEP.MedicOnly = true
SWEP.NeedText = "Only medics can use bacta grenades"
