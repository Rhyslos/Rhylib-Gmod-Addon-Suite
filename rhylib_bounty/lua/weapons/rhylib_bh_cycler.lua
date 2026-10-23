--[[
    Cycler rifle (rhylib_bounty, sniper). Slugthrower: a very fast round that hits hard, slow to fire. Placeholder model: the DC-15A.
    Built on rhylib_dc15a for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15a"
SWEP.PrintName = "Cycler rifle"
SWEP.InvGroup = "sniper"

SWEP.Primary = { ClipSize = 5, DefaultClip = 5, Automatic = true, Ammo = "rhylib_mag_large" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_large" }
SWEP.ClipCap = 5
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 150
SWEP.FireRate = 35
SWEP.BoltSpeed = 30000
SWEP.ReloadTime = 2.8
SWEP.Spread = { hip = 4.0, aim = 0.08, kickMain = 0.8, kickSide = 0.1, bloomPerShot = 1.2, bloomMax = 4.0, aimKickMult = 0.6, aimOffsetMult = 0.5 }
SWEP.Recoil = { up = 4.0, side = 0.6, bias = 0.1, recover = 0.85, aimMult = 0.7 }
SWEP.Scope = true
SWEP.AimFov = 0.25
SWEP.StartMags = 2

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi" }, sniper = true })
end
