-- Event spawn (rhylib_spawns): a spawn point staff switch on for an event; can teleport everyone to it.
-- Shared entity built on rhylib_spawn_point (ENT.Event = true: orange, Active = open,
-- the Battalion field isn't used). Admin-only in the spawn menu.
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_spawn_point"
ENT.PrintName = "Event spawn"
ENT.Category = "Rhylib: Spawn points"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Event = true
