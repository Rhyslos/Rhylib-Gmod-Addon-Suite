--[[
    DC-15X sniper rifle. Large magazines, but only 15 shots load from one
    (the rest stays in the magazine). Semi-auto, slow and hard hitting.
    Aiming looks through the scope: the gun is hidden, the view zooms
    (AimFov) and a scope overlay is drawn.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/dc15x.mdl), held
    in first person by the trooper hands (CarrierVM, DC-15A hold). The
    model's addon must be installed. Tune with rhylib_vm_editor /
    rhylib_wm_editor, then paste the lines below. First guesses.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "DC-15X"
SWEP.Category = "Rhylib: Snipers"
SWEP.InvGroup = "sniper"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_irifle.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dc15x.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on a Battlefront viewmodel
-- (Reworked Assets, a Workshop dependency); its gun bone is hidden.
SWEP.CarrierVM = "models/weapons/synbf3/c_dlt19.mdl"
SWEP.CarrierBone = "v_dlt19_reference001"
SWEP.PropBonePos = Vector(0.7, -10, 1.2)
SWEP.PropBoneAng = Angle(1.2, -89, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(1.3, 0, -0.6)
SWEP.CarrierFOV = 54
SWEP.ReloadTime = 2.6
SWEP.HoldType = "ar2"
SWEP.Slot = 2

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc15x.mdl"
SWEP.PropBodygroups = { [1] = 2, [2] = 0 }   -- (the scoped version of the model)
SWEP.PropScale = 0.9
SWEP.PropVMPos = Vector(18, 7, -8)     -- floating fallback: forward, right, up
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-6.2, 2, 0)    -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-13, 0, 180)
SWEP.PropMuzzle = Vector(40, 0, 2)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 15,
    DefaultClip = 15,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_mag_large",
}
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }

SWEP.FireRate = 50          -- 1.2 s between shots
SWEP.Recoil = { up = 3.2, side = 0.5, bias = 0.1, recover = 0.8, aimMult = 0.7 }
SWEP.Damage = 120
SWEP.BoltSpeed = 16000
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy2.wav"

SWEP.Mags = { "mag_large" }
SWEP.ClipCap = 15

SWEP.Grapple = true
SWEP.FireModes = { "semi" }

SWEP.UsesCell = false
SWEP.StartMags = 2
SWEP.StartCells = 0

SWEP.InvW = 5
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 6.5         -- kg

-- Wild from the hip, exact through the scope.
SWEP.Spread = {
    hip = 4.0,
    aim = 0.05,
    kickMain = 0.6,
    kickSide = 0.15,
    bloomPerShot = 1.0,
    bloomMax = 3.0,
    aimKickMult = 0.3,
    aimOffsetMult = 0.4,
}

SWEP.Scope = true
SWEP.ScopeSkill = "long_gun"                 -- (rhylib_skills: Marksman; others aim it like a rifle)
SWEP.AimPos = Vector(-2.5, 0, 1)
SWEP.AimFov = 0.18           -- about x5.5
