-- Thermal detonator: explodes 3 seconds after the throw (frag blast,
-- rhylib_grenade ENT.Radius / ENT.Damage). E + R switches to impact, and
-- with the Breaching charge skill to breaching charge.
-- Class rhylib_thermal, shared. Base rhylib_grenade_base (fields explained
-- there). Also a round for the T-19 grenade launcher.
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
