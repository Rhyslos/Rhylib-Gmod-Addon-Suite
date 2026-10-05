--[[
    DC-17 blaster pistol. Small magazines only, no power cell.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dc17.mdl), held in first person by
    the trooper hands (CarrierVM). The model's addon must be installed.
    Tune with rhylib_vm_editor, then paste its lines below.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-17"
SWEP.Category = "Rhylib: Pistols"
SWEP.InvGroup = "pistol"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_pistol.mdl"

SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dc17.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on a Battlefront viewmodel
-- (Reworked Assets, a Workshop dependency); its gun bone is hidden.
SWEP.CarrierVM = "models/bf2017/c_scoutblaster.mdl"
SWEP.CarrierBone = "v_scoutblaster_reference001"
SWEP.CarrierBoneMove = Vector(0, -0.3, 0)
SWEP.PropBonePos = Vector(-1.5, 13.2, 0.5)   -- (owner-tuned 2026-10-05, in dual)
SWEP.PropBoneAng = Angle(-2, 89, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(0, 0, 0)
SWEP.CarrierFOV = 54
SWEP.ReloadTime = 1.6       -- seconds, whatever the viewmodel's animation length
SWEP.HoldType = "pistol"
SWEP.Slot = 1

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc17.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(16, 6, -6)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(-9.3, 3, 0.8)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, -2, 180)
SWEP.PropMuzzle = Vector(10, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 30,
    DefaultClip = 30,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_mag_small",
}

SWEP.FireRate = 400
SWEP.Recoil = { up = 1.2, side = 0.35, bias = 0.2, recover = 0.8, aimMult = 0.7 }  -- view kick per shot
SWEP.Damage = 28
SWEP.BoltSpeed = 7000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

SWEP.Mags = { "mag_small" }
SWEP.Grapple = true     -- grapple fire mode while carrying a grapple hook
SWEP.FireModes = { "semi", "dual", "stun" }   -- (stun: military police only)
SWEP.SkillModes = { dual = "dual_dc17" }     -- (rhylib_skills: Officer)
SWEP.DualHoldType = "duel"
-- Dual: the second pistol (first guesses, tune in game).
SWEP.DualPropVMPos = Vector(14, -9, -6)      -- floating at the left of the view
SWEP.DualPropVMAng = Angle(0, 0, 0)
SWEP.DualPropWMPos = Vector(3, 1.5, -1)      -- left hand
SWEP.DualPropWMAng = Angle(0, 0, 0)       -- (owner: was upside down at roll 180)
-- Dual in first person: the pistol viewmodel and hands drawn a second
-- time, mirrored, as the left hand (owner: the Counter-Strike dual pistols
-- model never showed a left hand). The CS:S model stays as the fallback.
SWEP.DualMirror = true
SWEP.DualSpread = 3                          -- (owner-tuned)
SWEP.DualMirrorPos = Vector(-0.2, -2.6, -0.3)
SWEP.DualMirrorAng = Angle(0, 1, 0)
SWEP.DualCarrierVM = "models/weapons/cstrike/c_pist_elite.mdl"
SWEP.DualBonePos = Vector(0, 0, 0)
SWEP.DualBoneAng = Angle(0, 0, 0)
SWEP.DualMags = 2

SWEP.UsesCell = false
SWEP.StartMags = 4
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 2
SWEP.InvH = 1
SWEP.InvLarge = false
SWEP.InvWeight = 1.2         -- kg

SWEP.Spread = {
    hip = 1.2,
    aim = 0.6,
    kickMain = 0.4,
    kickSide = 0.1,
    bloomPerShot = 0.14,
    bloomMax = 1.8,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1)
SWEP.AimFov = 0.9
