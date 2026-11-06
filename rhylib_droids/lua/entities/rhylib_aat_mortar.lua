-- AAT mortar tank: the AAT droid tank (rhylib_aat) with the "aat_mortar"
-- row of Rhylib.Droids.KINDS (aatRole "mortar"): it hangs back
-- (aatMortarStandoff), lobs mortar shells at its target, where it was last
-- seen and at targets other droids spot (aatMortarRange), and defends
-- itself with its side lasers; no direct cannon shots, no rocket barrage.
AddCSLuaFile()
ENT.Base = "rhylib_aat"
ENT.Type = "nextbot"
ENT.PrintName = "AAT mortar tank"
ENT.Category = "Rhy's Droid tanks"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "aat_mortar"
