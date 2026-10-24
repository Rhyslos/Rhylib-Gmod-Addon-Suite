--[[
    Westar-M35 scatter pistol (rhylib_bounty, pistol). Double-barrel blaster pistol: both barrels fire at once (2 bolts, one round each), as accurate as a normal pistol, then reload.
    Model models/jajoff/sps/cgiweapons/tc13j/westarm35_shotgun.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc17
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "Westar-M35 scatter pistol"
SWEP.InvGroup = "pistol"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/westarm35_shotgun.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/westarm35_shotgun.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 2, DefaultClip = 2, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.ClipCap = 2
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 32
SWEP.FireRate = 120
SWEP.BoltSpeed = 6000
SWEP.ReloadTime = 1.6
SWEP.Spread = { hip = 1.3, aim = 0.6, kickMain = 0.9, kickSide = 0.25, bloomPerShot = 0.4, bloomMax = 2.4, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 2.4, side = 0.6, bias = 0.2, recover = 0.8, aimMult = 0.7 }
SWEP.Pellets = 2         -- (both barrels)
SWEP.PelletCone = 0.6    -- (the two bolts land close together)
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "stun" }, pistol = true })
end
