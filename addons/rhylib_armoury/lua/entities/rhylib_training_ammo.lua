-- Training ammo cabinet: training magazines and rockets (plus power cells), endless and issued.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Training ammo"
ENT.Category = "Rhylib: Training"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "trainingAmmo"
ENT.ModelKey = "ammo"
ENT.Hint = "Press E to draw training ammunition"
ENT.Tint = Color(255, 220, 120)
