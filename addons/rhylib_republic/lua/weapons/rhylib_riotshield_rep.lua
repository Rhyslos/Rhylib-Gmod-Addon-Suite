--[[
    Republic shield + DC-15S (owner 2026-10-08): the riot shield anyone may
    carry and use. Same blocking as the CG shield (rhylib_riotshield), but
    no Shock Trooper bonuses (Hold the line, Phalanx) and its bash (own
    key, no skill needed) only shoves. Model: cs574's blast_shield.mdl.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_riotshield"
SWEP.PrintName = "Republic shield (DC-15S)"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true

SWEP.CarrySkill = false   -- (false, not nil: nil would inherit the CG shield's skill)
SWEP.ShieldKind = "rep"
SWEP.ShieldProficiency = false
SWEP.BashStun = false
SWEP.BashSkill = false
SWEP.InvWeight = 9.0      -- (the CG shield is lighter and faster: rhylib_riotshield)
SWEP.MoveMult = 0.85
-- Aiming: the gun drops down and right, below the viewport (owner 2026-10-09c:
-- it sat in front of the shield). (AimPos: right, forward, up.)
SWEP.AimPos = Vector(2, -1, -7)

SWEP.InvIconModels = { "models/cs574/weapons/shields/blast_shield.mdl", "models/bshields/rshield.mdl", "models/bshields/hshield.mdl", "models/hevy/w_shield.mdl" }
