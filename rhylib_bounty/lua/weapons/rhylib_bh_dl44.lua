--[[
    DL-44 (rhylib_bounty, pistol). Heavy blaster pistol: hard hits, slow. Placeholder model: the DC-17.
    Built on rhylib_dc17 for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "DL-44"
SWEP.InvGroup = "pistol"

SWEP.Primary = { ClipSize = 20, DefaultClip = 20, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.ClipCap = 20
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 44
SWEP.FireRate = 220
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 1.7
SWEP.Spread = { hip = 1.4, aim = 0.6, kickMain = 0.7, kickSide = 0.2, bloomPerShot = 0.3, bloomMax = 2.5, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 1.8, side = 0.4, bias = 0.2, recover = 0.8, aimMult = 0.7 }
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "stun" }, pistol = true })
end
