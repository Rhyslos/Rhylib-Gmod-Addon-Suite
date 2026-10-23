--[[
    Westar-34 (rhylib_bounty, pistol). Light blaster pistol; two with Twin Westars. Placeholder model: the DC-17.
    Built on rhylib_dc17 for its first- and third-person placement; swap
    the model in Server settings > Model overrides and retune it with
    rhylib_vm_editor / rhylib_wm_editor. Bounty hunter gun: sold at the
    Bounty Office (not in the Republic armouries), stun mode with the
    Stun rounds skill (B.Gun in sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "Westar-34"
SWEP.InvGroup = "pistol"

SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 30
SWEP.FireRate = 380
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 1.5
SWEP.Spread = { hip = 1.3, aim = 0.6, kickMain = 0.5, kickSide = 0.15, bloomPerShot = 0.2, bloomMax = 2.2, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 1.2, side = 0.35, bias = 0.2, recover = 0.8, aimMult = 0.7 }
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "dual", "stun" }, pistol = true, dual = "bh_twin" })
end
