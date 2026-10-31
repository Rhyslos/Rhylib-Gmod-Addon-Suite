-- Smoke grenade: a short fuse, then a dark grey cloud (rhylib_smoke_cloud,
-- weapons smokeRadius / smokeLife) that blocks sight, Rhylib droids' too.
-- Anyone may carry and throw it; from the ammo cabinet.
-- Class rhylib_smokegrenade, shared. Base rhylib_grenade_base.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Smoke grenade"
SWEP.Category = "Rhy's Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.GrenadeKind = "smoke"
SWEP.FuseTime = 1.5
SWEP.PropColor = Color(120, 122, 125)
