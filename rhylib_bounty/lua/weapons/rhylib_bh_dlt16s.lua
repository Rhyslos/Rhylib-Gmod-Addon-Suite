--[[
    DLT-16S (rhylib_bounty, carbine). Heavy carbine: harder hits, more kick, heavier.
    Model models/jajoff/sps/cgiweapons/tc13j/dlt16s.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc15s
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "DLT-16S"
SWEP.InvGroup = "carbine"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dlt16s.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dlt16s.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 60, DefaultClip = 60, Automatic = true, Ammo = "rhylib_mag_medium" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_medium", "mag_small" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 30
SWEP.FireRate = 360
SWEP.BoltSpeed = 7500
SWEP.ReloadTime = 2.1
SWEP.Spread = { hip = 1.5, aim = 0.6, kickMain = 0.55, kickSide = 0.14, bloomPerShot = 0.16, bloomMax = 2.3, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 0.9, side = 0.35, bias = 0.05, recover = 0.6, aimMult = 0.65 }
SWEP.StartMags = 4
SWEP.InvWeight = 4.5

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "auto", "semi", "stun" } })
end
