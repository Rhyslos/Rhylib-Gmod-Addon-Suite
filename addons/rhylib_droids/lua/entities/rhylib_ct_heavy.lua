-- Clone heavy (clone NPC on the droid brain; see rhylib_clone.lua and rhylib_droids sh_00_config.lua kind ct_heavy).
AddCSLuaFile()
ENT.Base = "rhylib_clone"
ENT.Type = "nextbot"
ENT.PrintName = "Clone heavy"
ENT.Category = "Rhylib: Clone troopers"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "ct_heavy"
