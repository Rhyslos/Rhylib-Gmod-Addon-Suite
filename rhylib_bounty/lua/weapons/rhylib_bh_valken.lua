--[[
    Valken-38x (rhylib_bounty, sniper). Scoped blaster sniper rifle. Placeholder model: the DC-15X.
    Built on rhylib_dc15x for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15x"
SWEP.PrintName = "Valken-38x"
SWEP.InvGroup = "sniper"

SWEP.Primary = { ClipSize = 12, DefaultClip = 12, Automatic = true, Ammo = "rhylib_mag_large" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_large" }
SWEP.ClipCap = 12
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 110
SWEP.FireRate = 55
SWEP.BoltSpeed = 17000
SWEP.ReloadTime = 2.6
SWEP.Spread = { hip = 3.5, aim = 0.1, kickMain = 0.6, kickSide = 0.1, bloomPerShot = 0.9, bloomMax = 3.5, aimKickMult = 0.6, aimOffsetMult = 0.5 }
SWEP.Recoil = { up = 3.0, side = 0.5, bias = 0.1, recover = 0.8, aimMult = 0.7 }
SWEP.Scope = true
SWEP.AimFov = 0.2
SWEP.StartMags = 2

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi" }, sniper = true })
end
