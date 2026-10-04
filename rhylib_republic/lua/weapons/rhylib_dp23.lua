--[[
    DP-23 blaster carbine. Small (light) magazines plus a power cell;
    semi or auto, close-range hitter.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dp23.mdl), held in
    first person by the trooper hands with the DC-15A's values (CarrierVM,
    safety pose included). The model's addon must be installed. Tune with
    rhylib_vm_editor / rhylib_wm_editor, then paste the lines below.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DP-23"
SWEP.Category = "Rhylib: Republic"
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_irifle.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dp23.mdl"
SWEP.UseHands = false
-- First person: same hold as the DC-15A.
SWEP.CarrierVM = "models/weapons/synbf3/c_dlt19.mdl"
SWEP.CarrierBone = "v_dlt19_reference001"
SWEP.PropBonePos = Vector(0.7, -10, 0)
SWEP.PropBoneAng = Angle(1.2, -89, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(1.3, 0, -0.6)
SWEP.CarrierFOV = 54
SWEP.SafePose = {
    PropBonePos = Vector(-17.9021, 1.67832, 10.0699),
    PropBoneAng = Angle(0, -45.3147, -17.6224),
    PropBoneScale = 1.27622,
    VMOffset = Vector(1, -6, -4),
    CarrierFOV = 75,
}
SWEP.SafeBlendTime = 0.35
SWEP.ReloadTime = 1.8
SWEP.HoldType = "ar2"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dp23.mdl"
SWEP.PropScale = 0.9
SWEP.PropVMPos = Vector(18, 7, -8)     -- floating fallback: forward, right, up
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-6.7, 2.2, 0)    -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-12, 0, 180)
SWEP.PropMuzzle = Vector(24, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 30,
    DefaultClip = 30,
    Automatic = true,
    Ammo = "rhylib_mag_small",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "rhylib_cell",   -- shows spare cells on the HUD
}

SWEP.FireRate = 580
SWEP.Recoil = { up = 0.85, side = 0.3, bias = 0, recover = 0.6, aimMult = 0.65 }
SWEP.Damage = 20
SWEP.BoltSpeed = 7000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy1.wav"

SWEP.Mags = { "mag_small" }

SWEP.Grapple = true
SWEP.FireModes = { "semi", "auto", "stun" }   -- (stun: military police only)

SWEP.UsesCell = true
SWEP.CellShots = 500
SWEP.CellReloadMult = 1.6
SWEP.StartMags = 8
SWEP.StartCells = 1

SWEP.InvW = 4
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 3.5         -- kg

SWEP.Spread = {
    hip = 1.5,
    aim = 0.75,
    kickMain = 0.38,
    kickSide = 0.13,
    bloomPerShot = 0.12,
    bloomMax = 2.2,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2.5, 0, 1)
SWEP.AimFov = 0.85
