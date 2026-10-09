--[[
    Base for the medical kits (revive kit, first aid kit, medkit).
    Kits with OpensMenu (medkit, first aid kit): left click on someone opens
    their injury menu (drag the kit onto a body part); on a downed player a
    first aid kit revives. Right click opens your own.
    Others (revive kit): left click uses it on the player you aim at.
    The server does the work (rhylib_medical sv_20_actions.lua); a timer
    plays until it's done. Kits are inventory items (InvW / InvStack).
]]

AddCSLuaFile()

SWEP.PrintName = "Medical kit"
SWEP.Author = "Rhylib"
SWEP.Category = "Rhylib: Medical"
SWEP.Spawnable = false
SWEP.Slot = 4
SWEP.SlotPos = 1
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_medkit.mdl"
SWEP.WorldModel = "models/weapons/w_medkit.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.IsRhylibMedical = true
SWEP.CanSelf = false
SWEP.Hint = ""

SWEP.InvCategory = "medical"

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:UseKit(onSelf)
    local owner = self:GetOwner()
    if not SERVER or not IsValid(owner) or not Rhylib.Medical then return end
    Rhylib.Medical.UseKit(owner, self:GetClass(), onSelf)
end

-- (the server decides; menu kits get the injury menu opened via med.open)
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)
    self:UseKit(false)
end

function SWEP:SecondaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)
    if self.CanSelf or self.OpensMenu then self:UseKit(true) end
end

function SWEP:Reload() end

if CLIENT then
    function SWEP:DrawHUD()
        local s = ScrH() / 1080
        local Med = Rhylib.Medical
        local simple = Med and Med.Simple and Med.Simple()
        local text = simple and self.SimpleHint or self.Hint
        -- (simplified medical system: no charge shown when kits never run out)
        local charge = self.ChargeText and not (simple and Med.Cfg("simpleFirstAidCharge") ~= true)
        if charge then text = text .. "   ·   " .. self:ChargeText() end
        draw.SimpleText(text, Rhylib.UI.Font(14, 500), ScrW() * 0.5, ScrH() * 0.5 + 60 * s, Rhylib.UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end
