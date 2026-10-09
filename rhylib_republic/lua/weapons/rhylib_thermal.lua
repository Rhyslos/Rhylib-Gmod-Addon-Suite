-- Thermal detonator: explodes 3 seconds after the throw.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Thermal detonator"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.GrenadeKind = "fuse"
SWEP.FuseTime = 3
SWEP.ImpactMode = true   -- E + R switches between timed and impact
SWEP.BreachMode = true   -- and breaching charge (rhylib_skills Breaching charge)
SWEP.Demolition = true   -- (EOD Demolitions: harder, wider)
