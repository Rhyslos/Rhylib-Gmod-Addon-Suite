-- Training deposit: your own endless storage, with Store all / Take all (see rhylib/armoury/sh_00_config.lua).
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Training deposit"
ENT.Category = "Rhylib"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "trainingDeposit"
ENT.ModelKey = "locker"
ENT.Hint = "Press E to store or take back your gear"
ENT.Tint = Color(255, 220, 120)
