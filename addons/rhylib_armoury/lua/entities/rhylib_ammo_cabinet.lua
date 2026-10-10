-- Ammo cabinet: magazines, power cells, rockets, grapple hooks, grenades,
-- ammo packs and HE charges (Rhylib.Armoury.AMMO_STOCK), endless and issued.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Ammo cabinet"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "ammo"
ENT.ModelKey = "ammo"
ENT.Hint = "Press E to draw ammunition"
