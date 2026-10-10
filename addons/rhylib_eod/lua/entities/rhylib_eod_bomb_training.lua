--[[
    Training bomb (rhylib_eod): set up like a custom bomb by anyone near it
    ("Training setup" in the defusal window), or rolled at random. A wrong
    move only fails (a spark and the reason), then it re-arms with the
    same setup a few seconds later. No blast, gas or kill radius.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_eod_bomb"
ENT.PrintName = "Training bomb"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.BombType = "training"
ENT.IsTrainingBomb = true
