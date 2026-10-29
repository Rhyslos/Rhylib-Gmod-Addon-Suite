--[[
    Long rifle (rhylib_bounty, sniper). One heavy, very fast shot, then a reload. Green bolts.
    Model models/jajoff/sps/cgiweapons/tc13j/generic_gun4.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc15x
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor (Rhy's Dev Tools) / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15x"
SWEP.PrintName = "Long rifle"
SWEP.InvGroup = "sniper"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/generic_gun4.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/generic_gun4.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 1, DefaultClip = 1, Automatic = true, Ammo = "rhylib_mag_large" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_large" }
SWEP.ClipCap = 1
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 160
SWEP.FireRate = 60
SWEP.BoltSpeed = 30000
SWEP.ReloadTime = 1.6
SWEP.Spread = { hip = 4.0, aim = 0.06, kickMain = 0.8, kickSide = 0.1, bloomPerShot = 1.2, bloomMax = 4.0, aimKickMult = 0.6, aimOffsetMult = 0.5 }
SWEP.Recoil = { up = 4.0, side = 0.6, bias = 0.1, recover = 0.85, aimMult = 0.7 }
SWEP.Scope = true
SWEP.AimFov = 0.18
SWEP.StartMags = 2

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi" }, sniper = true, color = 3 })
end
