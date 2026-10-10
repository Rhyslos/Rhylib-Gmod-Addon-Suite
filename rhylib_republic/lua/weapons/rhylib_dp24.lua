--[[
    DP-24 blaster shotgun. Medium magazines; each shot fires 6 bolts and
    uses 6 rounds (fewer when the magazine is nearly empty).

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dp24.mdl), held in
    first person by the trooper hands (CarrierVM, DC-15S hold). The model's
    addon must be installed. Tune with rhylib_vm_editor / rhylib_wm_editor,
    then paste the lines below. First guesses.

    Class rhylib_dp24. Shared: one file for server and client (AddCSLuaFile).
    Base rhylib_base (rhylib_weapons), where every SWEP field is explained;
    only the fields that differ are set here.
    Training copy: rhylib_dp24_training.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DP-24"
SWEP.Category = "Rhylib: Shotguns"
SWEP.InvGroup = "shotgun"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_shotgun.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dp24.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on a Battlefront viewmodel
-- (Reworked Assets, a Workshop dependency); its gun bone is hidden.
SWEP.CarrierVM = "models/bf2017/c_e11.mdl"
SWEP.CarrierBone = "v_e11_reference001"
SWEP.CarrierBoneMove = Vector(-3, 0, 0)
SWEP.PropBonePos = Vector(0, -8, -0.2)
SWEP.PropBoneAng = Angle(1, -88, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(0.7, 0, 0)
SWEP.CarrierFOV = 54
SWEP.ReloadTime = 2.0
SWEP.HoldType = "ar2"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dp24.mdl"
SWEP.PropScale = 0.9
SWEP.PropVMPos = Vector(18, 7, -8)     -- floating fallback: forward, right, up
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-6, 2.2, 0)    -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-13, 0, 180)
SWEP.PropMuzzle = Vector(24, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 60,
    DefaultClip = 60,
    Automatic = true,
    Ammo = "rhylib_mag_medium",
}
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "rhylib_cell" }   -- (shows spare cells on the HUD)

SWEP.FireRate = 75           -- 0.8 s between shots
-- Recoil: view kick per shot (rhylib_weapons cl_50_recoil): up = degrees up,
-- side = random sideways, bias = lean -1 (left) .. 1 (right), recover = share
-- of the climb that settles back, aimMult = multiplier while aiming.
SWEP.Recoil = { up = 2.4, side = 0.6, bias = 0.1, recover = 0.75, aimMult = 0.75 }
SWEP.Damage = 14             -- per bolt
SWEP.Pellets = 6
SWEP.PelletCone = 4.5        -- degrees, on top of the normal spread
SWEP.BoltSpeed = 6500
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/dc17_shotgun/dc17mat_fire.mp3"
SWEP.FireSoundLevel = 145

SWEP.Mags = { "mag_medium" }

SWEP.Grapple = true
SWEP.FireModes = { "semi" }

-- Power cell too (2026-10-09t, owner: snipers and shotguns take cells; about 12 magazines (10 shots each) per cell).
SWEP.UsesCell = true
SWEP.CellShots = 120
SWEP.CellReloadMult = 1.6
-- Spare magazines / cells put in your pouch when you pick it up (rhylib_base).
SWEP.StartMags = 4
SWEP.StartCells = 1

SWEP.InvW = 4
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 4.5         -- kg

-- Spread: cone angles in degrees (rhylib_weapons sh_10_spread): hip / aim =
-- resting cone, kickMain / kickSide = how far the crosshair arcs move per shot,
-- bloomPerShot (up to bloomMax) = growth of the whole cone, aimKickMult /
-- aimOffsetMult = share of that while aiming. Each value is also a setting
-- in Server settings > guns (rhylib_weapons sh_70_gunstats).
SWEP.Spread = {
    hip = 1.6,
    aim = 1.0,
    kickMain = 0.5,
    kickSide = 0.2,
    bloomPerShot = 0.4,
    bloomMax = 2.5,
    aimKickMult = 0.6,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-2, 0, 1.2)
SWEP.AimFov = 0.9
