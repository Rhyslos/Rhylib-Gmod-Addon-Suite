--[[
    Q2 holdout (rhylib_bounty, pistol). A tiny holdout pistol: six big shots. Placeholder model: the DC-17 (smaller).
    Built on rhylib_dc17 for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "Q2 holdout"
SWEP.InvGroup = "pistol"

SWEP.Primary = { ClipSize = 6, DefaultClip = 6, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.ClipCap = 6
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 50
SWEP.FireRate = 140
SWEP.BoltSpeed = 6500
SWEP.ReloadTime = 1.3
SWEP.Spread = { hip = 1.6, aim = 0.8, kickMain = 0.8, kickSide = 0.25, bloomPerShot = 0.4, bloomMax = 2.6, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 2.0, side = 0.5, bias = 0.2, recover = 0.8, aimMult = 0.7 }
SWEP.InvW = 1
SWEP.InvWeight = 0.6
SWEP.PropScale = 0.75
SWEP.StartMags = 2

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "stun" }, pistol = true })
end
