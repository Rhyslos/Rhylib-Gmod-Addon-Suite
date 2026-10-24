--[[
    DR-18 revolver (rhylib_bounty, pistol). Heavy revolver: six big shots, a loud report and a hard kick.
    Model models/jajoff/sps/cgiweapons/tc13j/dr18.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc17
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "DR-18 revolver"
SWEP.InvGroup = "pistol"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/dr18.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dr18.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 6, DefaultClip = 6, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.ClipCap = 6
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 50
SWEP.FireRate = 180
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 2.0
SWEP.Spread = { hip = 1.4, aim = 0.55, kickMain = 1.3, kickSide = 0.3, bloomPerShot = 0.5, bloomMax = 2.6, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 4.2, side = 0.9, bias = 0.25, recover = 0.75, aimMult = 0.75 }   -- (a hard kick)
-- A heavier, louder shot than the other pistols: the clone sniper's report,
-- pitched a little up so it still sounds like a handgun.
SWEP.FireSound = "weapons/shared/shared_clonesniper_fire.ogg"
SWEP.FireSoundPitch = 1.15
SWEP.FireSoundLevel = 148
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "stun" }, pistol = true })
end
