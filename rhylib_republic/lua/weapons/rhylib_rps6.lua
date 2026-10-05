--[[
    RPS-6 rocket launcher. One rocket at a time, unguided.
    The rocket is a slow explosive bolt: blast damage where it hits.
    Reload with R after each shot.
    Too heavy to fire while flying.

    Uses a prop model (models/jajoff/sps/cgiweapons/tc13j/rps.mdl), held in
    first person by the trooper hands on the HL2 launcher (CarrierVM). The model's addon must be
    installed. Tune with rhylib_vm_editor, then paste its lines below.
    All numbers are first guesses for tuning.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "RPS-6"
SWEP.Category = "Rhylib: Heavy"
SWEP.InvGroup = "heavy"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = true
SWEP.AdminOnly = false

-- Placeholder viewmodel (the carrier model is HL2's, so it's always there); ReloadTime sets the reload length.
SWEP.ViewModel = "models/weapons/c_rpg.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/rps.mdl"
SWEP.UseHands = false
-- First person: the trooper hands hold the prop on GMod's own HL2 rocket
-- launcher viewmodel (shoulder hold); its launcher bone "base" is hidden.
SWEP.CarrierVM = "models/weapons/c_rpg.mdl"
SWEP.CarrierBone = "base"
SWEP.PropBonePos = Vector(1.3, 6.8, 0)
SWEP.PropBoneAng = Angle(90, -90, 0)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(-5, -5.4, 3)
SWEP.CarrierFOV = 54
SWEP.HoldType = "rpg"
SWEP.Slot = 4

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/rps.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(16, 8, -6)     -- forward, right, up (first person)
SWEP.PropVMAng = Angle(0, 0, 0)        -- pitch, yaw, roll
SWEP.PropWMPos = Vector(-7, 3.4, 0)      -- forward, right, up from the right hand
SWEP.PropWMAng = Angle(-10, 1, 180)
SWEP.PropMuzzle = Vector(30, 0, 4)     -- muzzle in the prop's own coordinates

SWEP.Primary = {
    ClipSize = 1,
    DefaultClip = 1,
    Automatic = true,       -- must stay true; FireModes decides
    Ammo = "rhylib_rocket",
}

SWEP.FireRate = 60
SWEP.Recoil = { up = 4.5, side = 0.8, bias = 0, recover = 0.85, aimMult = 0.8 }  -- view kick per shot
SWEP.Damage = 0               -- all damage comes from the blast
SWEP.BoltSpeed = 2200
SWEP.BoltColor = 4            -- rocket look
SWEP.BoltLife = 5
SWEP.FireSound = "weapons/rpg/rocketfire1.wav"

SWEP.Explosive = { radius = 200, damage = 250 }

SWEP.Mags = { "rocket" }
SWEP.FireModes = { "semi" }
SWEP.ReloadTime = 3
SWEP.AutoReload = false     -- reload with R like every other gun

SWEP.UsesCell = false
SWEP.StartMags = 3
SWEP.StartCells = 0

-- Inventory size in cells
SWEP.InvW = 5
SWEP.InvH = 1
SWEP.InvLarge = true
SWEP.InvWeight = 8           -- kg

SWEP.Spread = {
    hip = 0.8,
    aim = 0.25,
    kickMain = 1.2,
    kickSide = 0.5,
    bloomPerShot = 0.5,
    bloomMax = 1.5,
    aimKickMult = 0.5,
    aimOffsetMult = 0.6,
}

SWEP.AimPos = Vector(-3.5, 0, 0.5)
SWEP.AimFov = 0.75
