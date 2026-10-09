--[[
    DC-15S blaster carbine. Magazine only, no power cell.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl), held in first person by
    the trooper hands (CarrierVM). The model's addon must be installed.
    Tune with rhylib_vm_editor, then paste its lines below.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-15S"
SWEP.Category = "Rhylib: Carbines"
SWEP.InvGroup = "carbine"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_smg1.mdl"

SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on a Battlefront viewmodel
-- (Reworked Assets, a Workshop dependency); its gun bone is hidden.
SWEP.CarrierVM = "models/bf2017/c_e11.mdl"
SWEP.CarrierBone = "v_e11_reference001"
SWEP.CarrierBoneMove = Vector(-3, 0, 0)
SWEP.PropBonePos = Vector(-0.1, -5.5, 0.6)
SWEP.PropBoneAng = Angle(2, -88, 0)
SWEP.PropBoneScale = 0.8
SWEP.VMOffset = Vector(0.7, 0, 0)
SWEP.CarrierFOV = 54
SWEP.ReloadTime = 1.8       -- seconds, whatever the viewmodel's animation length
SWEP.HoldType = "smg"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(18, 7, -8)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(-7, 2.5, 0)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-12, 0, 180)
SWEP.PropMuzzle = Vector(20, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 60,
    DefaultClip = 60,
    Automatic = true,
    Ammo = "rhylib_mag_medium",
}

SWEP.FireRate = 540
SWEP.Recoil = { up = 0.55, side = 0.3, bias = -0.1, recover = 0.55, aimMult = 0.65 }  -- view kick per shot
SWEP.Damage = 22
SWEP.BoltSpeed = 7000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/dc15s/dc15s_fire.ogg"
SWEP.FireSoundLevel = 110

-- Semi first (default), switch with E + R.
-- Magazines it takes, preferred first.
SWEP.Mags = { "mag_medium", "mag_small" }

SWEP.Grapple = true     -- grapple fire mode while carrying a grapple hook
SWEP.FireModes = { "semi", "auto", "sidearm", "stun" }   -- (stun: military police only)
-- Sidearm (Officer skill): semi-auto only, and it takes the place of semi
-- (owner: mainly for looks). Third person: two-handed pistol grip. First
-- person: held on the DC-17's pistol hands, a proxy viewmodel drawn by us
-- (the real one isn't swapped: that glitched when firing). Values are first
-- guesses: tune with rhylib_vm_editor in sidearm mode; its Copy gives the block.
SWEP.SkillModes = { sidearm = "carbine_sidearm" }
SWEP.ModeHoldTypes = { sidearm = "revolver" }
SWEP.ModeFireGestures = { sidearm = ACT_HL2MP_GESTURE_RANGE_ATTACK_PISTOL }   -- (owner: the revolver recoil lasted too long)
SWEP.ModeReplaces = { sidearm = "semi" }
SWEP.ModeProxies = {
    sidearm = {
        model = "models/bf2017/c_scoutblaster.mdl",
        bone = "v_scoutblaster_reference001",
        PropBonePos = Vector(-1.5, 9, 0.5),
        PropBoneAng = Angle(-2, 89, 0),
        PropBoneScale = 0.8,
        VMOffset = Vector(-0.7, 0, 0),   -- (undoes the carbine's own offset)
    },
}

SWEP.UsesCell = false
SWEP.StartMags = 8
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 3
SWEP.InvH = 1
SWEP.InvLarge = false
SWEP.InvWeight = 3.0         -- kg

SWEP.Spread = {
    hip = 1.4,
    aim = 0.7,
    kickMain = 0.35,
    kickSide = 0.1,
    bloomPerShot = 0.11,
    bloomMax = 2.0,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1.2)
SWEP.AimFov = 0.85
