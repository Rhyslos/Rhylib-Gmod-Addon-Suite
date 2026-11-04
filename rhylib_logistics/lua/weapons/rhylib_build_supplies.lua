--[[
    Building supplies (rhylib_logistics): anyone can take them from the
    gear cabinet. 2x2, stacks to 4. Hold them and click the ground close
    by: one goes down as a crate holding logistics buildSupplyUnit (or into
    a crate within 120 units). Structures placed near crates take their
    cost out of them (sv_30_build.lua).
]]

AddCSLuaFile()

SWEP.PrintName = "Building supplies"
SWEP.Category = "Rhy's Logistics"
SWEP.Author = "Rhy"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 4
SWEP.SlotPos = 6
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/props_junk/wood_crate001a.mdl"
SWEP.HoldType = "slam"

SWEP.InvGroup = "gear"
SWEP.InvW = 2
SWEP.InvH = 2
SWEP.InvStack = 4
SWEP.InvWeight = 2.5

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

local REACH = 110

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Place()
    self:SetNextPrimaryFire(CurTime() + 0.6)
    self:SetNextSecondaryFire(CurTime() + 0.6)
    if CLIENT then return end
    local o = self:GetOwner()
    if not (IsValid(o) and o:IsPlayer() and o:Alive()) then return end
    if Rhylib.State and Rhylib.State.CanAct and not Rhylib.State.CanAct(o) then return end
    local tr = util.TraceLine({ start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * REACH, filter = o, mask = MASK_SOLID })
    if not tr.Hit or tr.HitSky or tr.HitNormal.z < 0.7 then
        Rhylib.Notify(o, "Look at the ground close by to set the supplies down", "bad", "Logistics")
        return
    end
    local L = Rhylib.Logistics
    if not (L and L.AddCrateSupplies) then return end
    local Inv = Rhylib.Inventory
    local inst
    if Inv and Inv.Get then
        for _, x in pairs(Inv.Get(o).byUid) do
            if x.id == self:GetClass() then inst = x break end
        end
    end
    if Inv and not inst then return end
    if not L.AddCrateSupplies(o, tr, math.max(1, math.floor(L.Cfg("buildSupplyUnit")))) then return end
    if inst then
        Inv.Remove(o, inst.uid, 1)   -- (the inventory takes the weapon away with the last one)
    else
        o:StripWeapon(self:GetClass())
    end
end

function SWEP:PrimaryAttack() self:Place() end
function SWEP:SecondaryAttack() self:Place() end

if CLIENT then
    local COL = Color(255, 210, 140, 230)
    local SHADOW = Color(0, 0, 0, 160)
    function SWEP:DrawHUD()
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        draw.SimpleTextOutlined("BUILDING SUPPLIES  ·  CLICK THE GROUND TO SET A CRATE DOWN (OR ADD TO ONE)",
            font, ScrW() * 0.5, ScrH() * 0.55, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, SHADOW)
    end
end
