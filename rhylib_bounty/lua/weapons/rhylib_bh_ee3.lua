--[[
    EE-3 (rhylib_bounty, carbine). Three-round burst carbine. Placeholder model: the DC-15S.
    Built on rhylib_dc15s for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "EE-3"
SWEP.InvGroup = "carbine"

SWEP.Primary = { ClipSize = 60, DefaultClip = 60, Automatic = true, Ammo = "rhylib_mag_medium" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_medium", "mag_small" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 26
SWEP.FireRate = 300
SWEP.BoltSpeed = 7500
SWEP.ReloadTime = 1.8
SWEP.Spread = { hip = 1.3, aim = 0.55, kickMain = 0.45, kickSide = 0.12, bloomPerShot = 0.14, bloomMax = 2.0, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 0.7, side = 0.3, bias = 0, recover = 0.6, aimMult = 0.65 }
SWEP.BurstCount = 3
SWEP.BurstFireRate = 900
SWEP.BurstDelay = 0.3
SWEP.StartMags = 4

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "burst", "semi", "stun" }, autoModes = {} })
end
