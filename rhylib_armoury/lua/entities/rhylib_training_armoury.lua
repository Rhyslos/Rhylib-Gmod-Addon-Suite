-- Training armoury: a training copy of every gun (yellow bolts, sim health only), endless and issued.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Training armoury"
ENT.Category = "Rhylib"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "trainingArmoury"
ENT.ModelKey = "armoury"
ENT.Hint = "Press E to draw training weapons"
ENT.Tint = Color(255, 220, 120)
