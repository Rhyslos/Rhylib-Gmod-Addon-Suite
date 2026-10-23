--[[
    A280-CFE (rhylib_bounty, rifle). Heavy blaster rifle. Placeholder model: the Westar-M5.
    Built on rhylib_westarm5 for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_westarm5"
SWEP.PrintName = "A280-CFE"
SWEP.InvGroup = "rifle"

SWEP.Primary = { ClipSize = 60, DefaultClip = 60, Automatic = true, Ammo = "rhylib_mag_medium" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_medium", "mag_small" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 32
SWEP.FireRate = 400
SWEP.BoltSpeed = 8000
SWEP.ReloadTime = 2.0
SWEP.Spread = { hip = 1.3, aim = 0.5, kickMain = 0.4, kickSide = 0.11, bloomPerShot = 0.13, bloomMax = 2.0, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 0.8, side = 0.25, bias = 0.08, recover = 0.6, aimMult = 0.6 }
SWEP.StartMags = 4

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "auto", "semi", "stun" } })
end
