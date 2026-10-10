-- Custom bomb: starts as a random large roll; the GM builds it in the GM
-- window (E with the toolgun). Large blast. Base: rhylib_eod_bomb.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_eod_bomb"
ENT.PrintName = "Bomb (custom, GM)"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.BombType = "custom"
ENT.Model = "models/cire992/props2/gethbomb01.mdl"
