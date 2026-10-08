--[[
    Z-6 rotary blaster cannon. Large or small magazines plus a power cell.
    Hold fire to spin the barrels up (SpinUp seconds) before it fires;
    you walk slower while it spins. Too heavy to fire while flying.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/z6.mdl), held in first person by
    the trooper hands (CarrierVM). The model's addon must be installed.
    Tune with rhylib_vm_editor, then paste its lines below.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "Z-6"
SWEP.Category = "Rhylib: Heavy"
SWEP.InvGroup = "heavy"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_shotgun.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/z6.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on a Battlefront viewmodel
-- (Reworked Assets, a Workshop dependency); its gun bone is hidden.
SWEP.CarrierVM = "models/weapons/synbf3/c_t21.mdl"
SWEP.CarrierBone = "v_t21_reference001"
SWEP.PropBonePos = Vector(-2, -5, -6.5)
SWEP.PropBoneAng = Angle(0, -90, 0)
SWEP.PropBoneScale = 1.15
SWEP.VMOffset = Vector(5, -20, -7)
SWEP.CarrierFOV = 75
SWEP.HoldType = "shotgun"
SWEP.Slot = 3

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/z6.mdl"
SWEP.PropScale = 0.8
SWEP.PropVMPos = Vector(20, 8, -10)    -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(-3.4, 3.4, 1.2)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-8, 4, 175)
SWEP.PropMuzzle = Vector(36, 0, 0)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 250,
    DefaultClip = 250,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_mag_large",
}
SWEP.Secondary = {
    ClipSize = -1,
    DefaultClip = -1,
    Automatic = true,
    Ammo = "rhylib_cell",
}

SWEP.FireRate = 900
SWEP.Recoil = { up = 0.32, side = 0.4, bias = 0.25, recover = 0.4, aimMult = 0.7 }  -- view kick per shot
SWEP.Damage = 18
SWEP.BoltSpeed = 7500
SWEP.BoltColor = 1
SWEP.FireSound = "weapons/airboat/airboat_gun_energy2.wav"

SWEP.Mags = { "mag_large", "mag_medium", "mag_small" }
SWEP.MagSkills = { mag_large = "heavy_feed" }   -- (rhylib_skills: Support > Heavy)
SWEP.FireModes = { "auto" }
SWEP.ReloadTime = 3.2

-- No firing gesture on the player model: the shotgun one jerks the
-- body around at 900 rpm.
SWEP.PlayerFireAnim = false

SWEP.SpinUp = 0.6
SWEP.SpinMoveMult = 0.6
SWEP.SpinSound = "weapons/physcannon/physcannon_charge.wav"  -- placeholder

SWEP.UsesCell = true
SWEP.CellShots = 1000
SWEP.CellReloadMult = 1.3
SWEP.StartMags = 3
SWEP.StartCells = 1

-- Inventory size in cells
SWEP.InvW = 6   -- (long guns are 6 long, the inventory is 6 wide; owner 2026-10-07)
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 12          -- kg

SWEP.Spread = {
    hip = 2.2,
    aim = 1.4,
    kickMain = 0.25,
    kickSide = 0.1,
    bloomPerShot = 0.06,
    bloomMax = 2.4,
    aimKickMult = 0.6,
    aimOffsetMult = 0.7,
}

SWEP.AimPos = Vector(-1.5, 0, 0.5)
SWEP.AimFov = 0.92
