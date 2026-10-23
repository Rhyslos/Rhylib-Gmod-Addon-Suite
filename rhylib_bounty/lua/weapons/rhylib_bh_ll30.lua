--[[
    LL-30 (rhylib_bounty, pistol). Quick, light blaster pistol. Placeholder model: the DC-17.
    Built on rhylib_dc17 for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "LL-30"
SWEP.InvGroup = "pistol"

SWEP.Primary = { ClipSize = 25, DefaultClip = 25, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.ClipCap = 25
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 27
SWEP.FireRate = 430
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 1.4
SWEP.Spread = { hip = 1.2, aim = 0.55, kickMain = 0.45, kickSide = 0.14, bloomPerShot = 0.18, bloomMax = 2.0, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 1.0, side = 0.3, bias = 0.15, recover = 0.8, aimMult = 0.7 }
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "stun" }, pistol = true })
end
