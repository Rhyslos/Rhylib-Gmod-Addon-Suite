--[[
    Westar-M35 Super Commando (rhylib_bounty, carbine). Three-round burst carbine.
    Model models/jajoff/sps/cgiweapons/tc13j/westarm35_supercommando.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc15s
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "Westar-M35 Super Commando"
SWEP.InvGroup = "carbine"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/westarm35_supercommando.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/westarm35_supercommando.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

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
