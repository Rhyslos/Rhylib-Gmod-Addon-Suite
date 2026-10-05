-- Event spawn (rhylib_spawns): a spawn point staff switch on for an event; can teleport everyone to it.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_spawn_point"
ENT.PrintName = "Event spawn"
ENT.Category = "Rhylib: Spawn points"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Event = true
