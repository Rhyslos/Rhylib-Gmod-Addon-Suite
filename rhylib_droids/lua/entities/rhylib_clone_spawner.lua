--[[
    Clone spawner (admins; spawn menu "Rhy's Spawners", or the toolgun's
    Spawners category): the droid spawner (entities/rhylib_droid_spawner.lua)
    sending clone trooper preset squads (D.PRESETS side 1: clone_squad,
    clone_company) instead. Differences:
      - default preset cloneSpawnerPreset; total, cap, interval, mode and
        health are the shared spawner* settings
      - waits while the map is at cloneMax clones (not maxActive)
      - a blue tint and a blue "Clone spawner" label
      - players and clones can't damage it; droids and their blasts can
    Settings window and nets as the droid spawner's (droids.spawner /
    droids.spawnerset; the window shows the clone presets).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_droid_spawner"
ENT.PrintName = "Clone spawner"
ENT.Category = "Rhy's Spawners"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Clones = true
ENT.Model = "models/props_combine/combine_dispenser.mdl"   -- (the spawn window's hover preview; the placed one uses spawnerModel)
