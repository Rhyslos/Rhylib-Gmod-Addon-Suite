-- LAP mine (large AP): two safety pins, lapRadius / lapDamage / lapTrigger.
-- Everything else is rhylib_eod_mine.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_eod_mine"
ENT.PrintName = "Mine (LAP, large AP)"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.MineType = "lap"
