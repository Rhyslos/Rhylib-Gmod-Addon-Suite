--[[
    B-10 revolver (rhylib_bounty, pistol). Revolver: six shots; two at once with the Twin revolvers skill.
    Model models/jajoff/sps/cgiweapons/tc13j/b10.mdl (Workshop: the TC-13J weapon pack). Built on rhylib_dc17
    for its first- and third-person holding; the model sits differently,
    so tune it with rhylib_vm_editor (Rhy's Dev Tools) / rhylib_wm_editor and paste the lines
    in here. Bounty hunter gun: sold at the Bounty Office (not in the
    Republic armouries), stun mode with the Stun rounds skill (B.Gun in
    sh_00_config.lua).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_dc17"
SWEP.PrintName = "B-10 revolver"
SWEP.InvGroup = "pistol"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/b10.mdl"
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/b10.mdl"
SWEP.PropBodygroups = { [1] = 0, [2] = 0 }   -- (clears the base gun's bodygroups)

SWEP.Primary = { ClipSize = 6, DefaultClip = 6, Automatic = true, Ammo = "rhylib_mag_small" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = { "mag_small" }
SWEP.ClipCap = 6
SWEP.UsesCell = false
SWEP.StartCells = 0
SWEP.Damage = 36
SWEP.FireRate = 260
SWEP.BoltSpeed = 7000
SWEP.ReloadTime = 1.8
SWEP.Spread = { hip = 1.3, aim = 0.55, kickMain = 0.6, kickSide = 0.18, bloomPerShot = 0.25, bloomMax = 2.3, aimKickMult = 0.5, aimOffsetMult = 0.6 }
SWEP.Recoil = { up = 1.5, side = 0.4, bias = 0.2, recover = 0.8, aimMult = 0.7 }
SWEP.StartMags = 3

if Rhylib and Rhylib.Bounty and Rhylib.Bounty.Gun then
    Rhylib.Bounty.Gun(SWEP, { modes = { "semi", "dual", "stun" }, pistol = true, dual = "bh_twin" })
end
