--[[
    Westar-M35 sniper (rhylib_bounty, sniper). Scoped blaster sniper rifle, 5 shots a magazine.
    Model models/jajoff/sps/cgiweapons/tc13j/westarm35_sniper.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc15x
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor (Rhy's Dev Tools) / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15x"
SWEP.PrintName = "Westar-M35 sniper"
SWEP.InvGroup = "sniper"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/westarm35_sniper.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/westarm35_sniper.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 5, DefaultClip = 5, Automatic = true, Ammo = "rhylib_mag_large" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_large" }
SWEP.ClipCap = 5
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 105
SWEP.FireRate = 60
SWEP.BoltSpeed = 17000
SWEP.ReloadTime = 2.4
SWEP.Spread = { hip = 3.5, aim = 0.1, kickMain = 0.6, kickSide = 0.1, bloomPerShot = 0.9, bloomMax = 3.5, aimKickMult = 0.6, aimOffsetMult = 0.5 }
SWEP.Recoil = { up = 3.0, side = 0.5, bias = 0.1, recover = 0.8, aimMult = 0.7 }
SWEP.Scope = true
SWEP.AimFov = 0.2
SWEP.StartMags = 2

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi" }, sniper = true })
end
