--[[
    SE-14C (rhylib_bounty, pistol). Burst-fire pistol. Placeholder model: the DC-17 (no model given yet).
    Built on rhylib_dc17 for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "SE-14C"
SWEP.InvGroup = "pistol"

SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 22
SWEP.FireRate = 300
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 1.5
SWEP.Spread = { hip = 1.4, aim = 0.65, kickMain = 0.45, kickSide = 0.15, bloomPerShot = 0.16, bloomMax = 2.2, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 0.9, side = 0.35, bias = 0.15, recover = 0.8, aimMult = 0.7 }
SWEP.BurstCount = 3
SWEP.BurstFireRate = 800
SWEP.BurstDelay = 0.25
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "burst", "semi", "stun" }, pistol = true, autoModes = {} })
end
