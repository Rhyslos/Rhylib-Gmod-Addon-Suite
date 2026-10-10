-- Pick-up: a grapple hook item (shared). Press E to take it. See rhylib_item_base
-- and sh_30_grapple.lua.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_item_base"
ENT.PrintName = "Grapple hook"
ENT.Category = "Rhylib: Items & ammo"
ENT.Spawnable = true
ENT.Model = "models/props_junk/meathook001a.mdl"  -- placeholder
ENT.Kind = "grapple"
ENT.PickupSound = "physics/metal/metal_solid_impact_soft1.wav"
