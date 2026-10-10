-- Impact thermal detonator: explodes on the first hit.
-- Class rhylib_thermal_impact, shared. Base rhylib_grenade_base. Not in the
-- spawn menu any more (the thermal has an impact mode), but kept so saved
-- items and the T-19 grenade launcher (a round) still work.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Impact detonator"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = false   -- (retired: the thermal detonator has an impact mode, E + R)
SWEP.GrenadeKind = "impact"
SWEP.Demolition = true
SWEP.PropColor = Color(255, 190, 150)
