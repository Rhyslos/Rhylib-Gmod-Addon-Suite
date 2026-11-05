-- Tough test dummy: like the test dummy (a NextBot, no player slot), but
-- takes no damage at all (no armour loss, bleeding or limps; never goes
-- down). Hits still show their damage numbers (after armour).
-- See rhylib_test_dummy.lua and rhylib_medical sv_60_dummy.lua.
AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "rhylib_test_dummy"
ENT.PrintName = "Test dummy (tough)"
ENT.Category = "Rhy's Medical"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.DummyName = "Tough dummy"
ENT.Tough = true
