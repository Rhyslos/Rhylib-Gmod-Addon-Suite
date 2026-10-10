--[[
    Mine scanner (rhylib_eod). LMB switches it on or off: a beam lights the
    ground ahead and mines inside it show up (outlined) with a beep that
    quickens as you close in. RMB marks the mine nearest your crosshair in
    the beam so everyone sees it (again to unmark). Ammo cabinet, 2x1.
    First person is a placeholder (the HL2 tool gun).

    Shared SWEP; the beam, outlines, beeps and HUD are in cl_50_mines.lua
    (E.ScannerMark, E.ScannerHUD), the server check of a mark in
    sv_30_mines.lua (net eod.minemark). The On NetworkVar is predicted,
    so other players' clients see the beam too. Holstering switches it off.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Mine scanner"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.ViewModelFOV = 54
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 2
SWEP.InvH = 1
SWEP.InvWeight = 1.2
SWEP.InvCategory = "gear"
SWEP.InvHolster = false     -- (no holster slot, though its hold type is "pistol")

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "On")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    self:SetOn(not self:GetOn())
    if IsFirstTimePredicted() then self:EmitSound(self:GetOn() and "buttons/button9.wav" or "buttons/button8.wav", 55) end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if SERVER or not IsFirstTimePredicted() or not self:GetOn() then return end
    local E = Rhylib.EOD
    if E and E.ScannerMark then E.ScannerMark() end
end

function SWEP:Holster()
    if SERVER then self:SetOn(false) end
    return true
end

if CLIENT then
    function SWEP:DrawHUD()
        local E = Rhylib.EOD
        if E and E.ScannerHUD then E.ScannerHUD(self) end
    end
end
