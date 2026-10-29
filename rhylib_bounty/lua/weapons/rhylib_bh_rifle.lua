--[[
    Hunter's rifle (rhylib_bounty, rifle). Blaster rifle with yellow bolts.
    Model models/jajoff/sps/cgiweapons/tc13j/generic_gun3.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_westarm5
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor (Rhy's Dev Tools) / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_westarm5"
SWEP.PrintName = "Hunter's rifle"
SWEP.InvGroup = "rifle"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/generic_gun3.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/generic_gun3.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 60, DefaultClip = 60, Automatic = true, Ammo = "rhylib_mag_medium" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_medium", "mag_small" }
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 33
SWEP.FireRate = 400
SWEP.BoltSpeed = 8000
SWEP.ReloadTime = 2.0
SWEP.Spread = { hip = 1.3, aim = 0.5, kickMain = 0.4, kickSide = 0.11, bloomPerShot = 0.13, bloomMax = 2.0, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 0.8, side = 0.25, bias = 0.08, recover = 0.6, aimMult = 0.6 }
SWEP.StartMags = 4

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "auto", "semi", "stun" }, color = 7 })
end
