--[[
    An item in your hand (shared SWEP; magazines, power cells, rockets:
    items with def.hand on the hotbar). Which item is NW2Int
    "rhylib_handUid". Given and selected by net inv.hold (sv_40_give.lua);
    put away again when the item is gone or leaves the hotbar.

      Left click   give one to the player you're looking at
      Right click  drop one in front of you
]]

AddCSLuaFile()

SWEP.PrintName = "Item"
SWEP.Spawnable = false
SWEP.Slot = 5
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.IsRhylibHand = true

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

-- SWEP:HeldItem(): the held item (client: from the inventory mirror;
-- server: the real one), or nil.
function SWEP:HeldItem()
    local owner = self:GetOwner()
    if not IsValid(owner) then return nil end
    local uid = owner:GetNW2Int("rhylib_handUid", 0)
    local Inv = Rhylib.Inventory
    if SERVER then return Inv.Get(owner).byUid[uid] end
    return Inv.byUid and Inv.byUid[uid]
end

-- SWEP:Receiver(): the live player in front of you within giveRange, or nil.
function SWEP:Receiver()
    local owner = self:GetOwner()
    local r = Rhylib.Config.Get("inventory", "giveRange") or 130
    local tr = util.TraceHull({
        start = owner:EyePos(), endpos = owner:EyePos() + owner:GetAimVector() * r,
        filter = owner, mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), mask = MASK_SHOT_HULL,
    })
    local e = tr.Entity
    if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.35)
    if not SERVER then return end
    local owner = self:GetOwner()
    local inst = self:HeldItem()
    local target = self:Receiver()
    if not inst then return end
    if not target then
        owner:PrintMessage(HUD_PRINTCENTER, "Look at someone close to hand it over")
        return
    end
    Rhylib.Inventory.GiveTo(owner, target, inst.uid, true)
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.35)
    if not SERVER then return end
    local inst = self:HeldItem()
    if inst then Rhylib.Inventory.Drop(self:GetOwner(), inst.uid, true) end
end

function SWEP:Reload() end

if SERVER then
    -- Nothing left to hold (all given away, moved off the hotbar): put it away.
    function SWEP:Think()
        local owner = self:GetOwner()
        if not IsValid(owner) then return end
        local inst = self:HeldItem()
        if not inst or not inst.hb then Rhylib.Inventory.Stow(owner) end
    end
end

if CLIENT then
    local function def(inst) return inst and Rhylib.Items.Get(inst.id) end

    -- The item model held low in front of you.
    local vmProp
    function SWEP:PreDrawViewModel(vm)
        local inst = self:HeldItem()
        local d = def(inst)
        if not d or not d.model then return true end
        if not IsValid(vmProp) then
            vmProp = ClientsideModel(d.model, RENDERGROUP_OPAQUE)
            if not IsValid(vmProp) then return true end
            vmProp:SetNoDraw(true)
        end
        if vmProp:GetModel() ~= d.model then vmProp:SetModel(d.model) end
        local ep, ea = EyePos(), EyeAngles()
        vmProp:SetPos(ep + ea:Forward() * 18 + ea:Right() * 7 - ea:Up() * 9)
        vmProp:SetAngles(Angle(ea.p, ea.y + 200, ea.r))
        vmProp:SetupBones()
        vmProp:DrawModel()
        return true   -- hide the bare arms
    end

    function SWEP:DrawWorldModel()
        local owner = self:GetOwner()
        local d = def(self:HeldItem())
        if not IsValid(owner) or not d or not d.model then return end
        local b = owner:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = b and owner:GetBoneMatrix(b)
        if not m then return end
        local prop = self.wmProp   -- one per weapon (players hold different items)
        if not IsValid(prop) then
            prop = ClientsideModel(d.model, RENDERGROUP_OPAQUE)
            if not IsValid(prop) then return end
            prop:SetNoDraw(true)
            self.wmProp = prop
        end
        if prop:GetModel() ~= d.model then prop:SetModel(d.model) end
        local ang = m:GetAngles()
        prop:SetPos(m:GetTranslation() + ang:Forward() * 4 + ang:Right() * 2)
        prop:SetAngles(ang)
        prop:SetupBones()
        prop:DrawModel()
    end

    function SWEP:OnRemove()
        if IsValid(self.wmProp) then self.wmProp:Remove() end
    end

    -- What you hold, how many, and who you'd hand it to.
    function SWEP:DrawHUD()
        local inst = self:HeldItem()
        local d = def(inst)
        if not d then return end
        local UI = Rhylib.UI
        local x, y = ScrW() * 0.5, ScrH() * 0.62
        draw.SimpleTextOutlined(d.name .. (inst.count > 1 and ("  x" .. inst.count) or ""), UI.Font(18, 700), x, y,
            UI.Colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
        local target = self:Receiver()
        local hint = target and ("Left click: give one to " .. target:Nick()) or "Look at someone to give them one"
        draw.SimpleTextOutlined(hint .. "  ·  Right click: drop one", UI.Font(13), x, y + 22,
            target and UI.Colors.text or UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
    end
end
