-- Tough test dummy: like the test dummy, but takes no damage at all (no
-- bleeding, burns, fractures; never goes down). Hits still show their
-- damage numbers. See rhylib_test_dummy.lua.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "rhylib_test_dummy"
ENT.PrintName = "Test dummy (tough)"
ENT.Category = "Rhylib: Medical"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.BotName = "Tough dummy"
ENT.Tough = true
