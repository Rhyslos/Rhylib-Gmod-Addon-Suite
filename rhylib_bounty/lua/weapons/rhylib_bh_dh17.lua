--[[
    DH-17 (rhylib_bounty, carbine). Short blaster carbine. Placeholder model: the DC-15S.
    Built on rhylib_dc15s for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "DH-17"
SWEP.InvGroup = "carbine"

SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small", "mag_medium" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 24
SWEP.FireRate = 450
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 1.6
SWEP.Spread = { hip = 1.3, aim = 0.65, kickMain = 0.4, kickSide = 0.12, bloomPerShot = 0.12, bloomMax = 2.0, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 0.6, side = 0.3, bias = -0.1, recover = 0.55, aimMult = 0.65 }
SWEP.StartMags = 4

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "auto", "stun" } })
end
