-- Clone commander (clone NPC on the droid brain; see rhylib_clone.lua and rhylib_droids sh_00_config.lua kind ct_commander).
AddCSLuaFile()
ENT.Base = "rhylib_clone"
ENT.Type = "nextbot"
ENT.PrintName = "Clone commander"
ENT.Category = "Rhylib: Clone troopers"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "ct_commander"
