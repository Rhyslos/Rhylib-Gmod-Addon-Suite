-- Droid popper: EMP grenade. Kills Rhylib droids in range after a short
-- fuse; harmless to everything else.
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Droid popper"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.GrenadeKind = "emp"
SWEP.FuseTime = 2
SWEP.PropColor = Color(130, 180, 255)
SWEP.RequiresSkill = "droid_popper"   -- (rhylib_skills: needed to throw it)
SWEP.CarrySkill = "droid_popper"      -- and to carry it at all
SWEP.ImpactMode = true                -- E + R switches between timed and impact
SWEP.ImpactColor = Color(170, 140, 255)
SWEP.SkillName = "Droid popper"
