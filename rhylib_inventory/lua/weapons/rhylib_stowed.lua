--[[
    "Stowed": what you hold when no weapon is out. Picking an empty hotbar
    slot (or the slot you're already holding) switches to it, so your guns
    stay stowed in the inventory. Nothing to draw, nothing to fire.
    Every player gets it on spawn (sv_10_inventory.lua, Inv.Stow). Shared.
    Not an inventory item and never stripped by rhylib_cleanhotbar.
]]

AddCSLuaFile()

SWEP.PrintName = "Stowed"
SWEP.Author = "Rhylib"
SWEP.Category = "Rhylib"
SWEP.Spawnable = false
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.ViewModel = ""
SWEP.WorldModel = ""
SWEP.UseHands = false
SWEP.HoldType = "normal"
SWEP.IsRhylibStowed = true

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end

function SWEP:Deploy()
    return true
end

function SWEP:DrawWorldModel() end
function SWEP:DrawWorldModelTranslucent() end

if CLIENT then
    function SWEP:PreDrawViewModel() return true end
    function SWEP:DrawHUD() end
end
