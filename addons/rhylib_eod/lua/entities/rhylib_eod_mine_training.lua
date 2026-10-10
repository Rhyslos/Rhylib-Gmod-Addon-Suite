--[[
    Training mine (rhylib_eod): set up by anyone near it (AP or LAP, how
    many pins, difficulty, always visible or hidden) from the mine window.
    Stepping off it or a wrong pin only fails (a spark and the reason);
    it then re-buries itself to try again. Lifting it re-buries it too.
    Explosions and clone NPCs leave it alone.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_eod_mine"
ENT.PrintName = "Training mine"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.MineType = "ap"
ENT.IsTrainingMine = true
