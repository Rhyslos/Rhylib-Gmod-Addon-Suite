-- Impact thermal detonator: explodes on the first hit.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Impact detonator"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = false   -- (retired: the thermal detonator has an impact mode, E + R)
SWEP.GrenadeKind = "impact"
SWEP.Demolition = true
SWEP.PropColor = Color(255, 190, 150)
