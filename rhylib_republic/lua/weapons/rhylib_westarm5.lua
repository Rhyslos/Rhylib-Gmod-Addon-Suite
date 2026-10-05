--[[
    Westar-M5 blaster rifle: between the DC-15S and DC-15A. Medium or
    small magazines plus a power cell; semi or auto.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/westarm5_h.mdl),
    held in first person by the trooper hands (CarrierVM, DC-15S hold). The
    model's addon must be installed. Tune with rhylib_vm_editor /
    rhylib_wm_editor, then paste the lines below. First guesses.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "Westar-M5"
SWEP.Category = "Rhylib: Rifles"
SWEP.InvGroup = "rifle"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_smg1.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/westarm5_h.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on a Battlefront viewmodel
-- (Reworked Assets, a Workshop dependency); its gun bone is hidden.
SWEP.CarrierVM = "models/bf2017/c_e11.mdl"
SWEP.CarrierBone = "v_e11_reference001"
SWEP.CarrierBoneMove = Vector(-3, 0, 0)
SWEP.PropBonePos = Vector(0, -7, 0.3)
SWEP.PropBoneAng = Angle(2, -88, 0)
SWEP.PropBoneScale = 0.6
SWEP.VMOffset = Vector(0.7, 0, 0)
SWEP.CarrierFOV = 54
SWEP.ReloadTime = 1.9
SWEP.HoldType = "ar2"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/westarm5_h.mdl"
SWEP.PropBodygroups = { [1] = 1 }
SWEP.PropScale = 0.9
SWEP.PropVMPos = Vector(18, 7, -8)     -- floating fallback: forward, right, up
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-6, 2, 0)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(190, 180, 0)
SWEP.PropMuzzle = Vector(28, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 60,
    DefaultClip = 60,
    Automatic = true,
    Ammo = "rhylib_mag_medium",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "rhylib_cell",   -- shows spare cells on the HUD
}

SWEP.FireRate = 440
SWEP.Recoil = { up = 0.7, side = 0.25, bias = 0.05, recover = 0.6, aimMult = 0.6 }
SWEP.Damage = 27
SWEP.BoltSpeed = 7500
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy2.wav"

SWEP.Mags = { "mag_medium", "mag_small" }

SWEP.Grapple = true
SWEP.FireModes = { "semi", "auto", "stun" }   -- (stun: military police only)

SWEP.UsesCell = true
SWEP.CellShots = 500
SWEP.CellReloadMult = 1.6
SWEP.StartMags = 6
SWEP.StartCells = 1

SWEP.InvW = 4
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 4.0         -- kg

SWEP.Spread = {
    hip = 1.3,
    aim = 0.6,
    kickMain = 0.4,
    kickSide = 0.11,
    bloomPerShot = 0.13,
    bloomMax = 2.0,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1.2)
SWEP.AimFov = 0.82
