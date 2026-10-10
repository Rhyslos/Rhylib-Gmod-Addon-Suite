-- Old pick-up class (a medium magazine), not in the spawn menu. See the note at the end.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_item_base"
ENT.PrintName = "Medium magazine"
ENT.Category = "Rhylib: Items & ammo"
ENT.Spawnable = false
ENT.Model = "models/items/boxmrounds.mdl"  -- placeholder
ENT.Kind = "mag_medium"

-- Old name, kept so saved maps and dupes still work. Use rhylib_item_mag_medium.
