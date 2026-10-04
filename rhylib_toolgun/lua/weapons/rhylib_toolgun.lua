--[[
    Toolgun (rhylib_toolgun addon): LMB place, RMB remove, R the list.
    See rhylib/toolgun/sh_00_config.lua.

    Built on the Rhylib weapon base (rhylib_weapons), so it's held like the
    DC-17 (same Battlefront carrier viewmodel and hands) and can be tuned
    with rhylib_vm_editor / rhylib_wm_editor like any Rhylib gun; paste the
    copied lines below. It fires nothing, has no ammo, no aiming and isn't
    an inventory item or in the armoury. Needs rhylib_weapons.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "Toolgun"
SWEP.Category = "Rhylib"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.NoArmoury = true
SWEP.ToolGun = true          -- (R opens the list instead of the reload wheel)
SWEP.Slot = 5
SWEP.DrawAmmo = false

-- Placeholder viewmodel, used only if the carrier model is missing.
SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/btx42_pistol.mdl"
SWEP.UseHands = false
-- First person: the DC-17's carrier (Reworked Assets) holding the BTX-42.
-- Owner-tuned (rhylib_vm_editor / rhylib_wm_editor).
SWEP.CarrierVM = "models/bf2017/c_scoutblaster.mdl"
SWEP.CarrierBone = "v_scoutblaster_reference001"
SWEP.CarrierBoneMove = Vector(0, -0.3, 0)
SWEP.PropBonePos = Vector(-1.6, 14.5, 0.3)
SWEP.PropBoneAng = Angle(0, 90, -2)
SWEP.PropBoneScale = 1
SWEP.VMOffset = Vector(0, 0, 0)
SWEP.CarrierFOV = 54
SWEP.HoldType = "pistol"

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/btx42_pistol.mdl"
SWEP.PropScale = 1
SWEP.PropVMPos = Vector(16, 6, -6)     -- forward, right, up (without the carrier)
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-10, 3, 1)      -- third person, from the right hand
SWEP.PropWMAng = Angle(-10, -2, 180)
SWEP.PropMuzzle = Vector(10, 0, 2)

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Mags = {}
SWEP.FireModes = { "semi" }
SWEP.Grapple = false
SWEP.NoAim = true
SWEP.UsesCell = false
SWEP.StartMags = 0
SWEP.StartCells = 0
SWEP.InvW = false            -- (not an inventory item)
SWEP.AutoReload = false
SWEP.Recoil = { up = 0, side = 0, bias = 0, recover = 1, aimMult = 1 }
SWEP.Spread = {
    hip = 0.5, aim = 0.5, kickMain = 0, kickSide = 0,
    bloomPerShot = 0, bloomMax = 0, aimKickMult = 0, aimOffsetMult = 0,
}
SWEP.AimPos = Vector(0, 0, 0)
SWEP.AimFov = 1

-- No magazine (the HUD then shows no ammo).
function SWEP:GetMag() return nil end

-- Clicks are worked out on the client (what's chosen lives there) and
-- sent to the server, which checks everything again.
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.25)
    if SERVER and game.SinglePlayer() then self:CallOnClient("ToolClick", "1") end
    if CLIENT and IsFirstTimePredicted() then self:ToolClick("1") end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.25)
    if SERVER and game.SinglePlayer() then self:CallOnClient("ToolClick", "2") end
    if CLIENT and IsFirstTimePredicted() then self:ToolClick("2") end
end

function SWEP:Reload()
    if (self.nextMenu or 0) > CurTime() then return end
    self.nextMenu = CurTime() + 0.5
    if SERVER and game.SinglePlayer() then self:CallOnClient("ToolClick", "3") end
    if CLIENT and IsFirstTimePredicted() then self:ToolClick("3") end
end

function SWEP:ToolClick(which)
    if not CLIENT then return end
    local Tool = Rhylib.Tool
    if not (Tool and Tool.Click) then return end
    Tool.Click(self, which)
end

if CLIENT then
    function SWEP:DrawHUD()
        local Tool = Rhylib.Tool
        if Tool and Tool.DrawHUD then Tool.DrawHUD(self) end
    end
end
