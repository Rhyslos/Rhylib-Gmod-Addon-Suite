-- Pick-up: one full power cell (shared). Press E to take it. See rhylib_item_base.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_item_base"
ENT.PrintName = "Power cell"
ENT.Category = "Rhylib: Items & ammo"
ENT.Spawnable = true
ENT.Model = "models/items/battery.mdl"  -- placeholder
ENT.Kind = "cell"
ENT.PickupSound = "items/battery_pickup.wav"
