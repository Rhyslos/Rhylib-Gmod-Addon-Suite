--[[
    Toolgun (rhylib_toolgun addon): LMB place, RMB remove, R the list.
    See rhylib/toolgun/sh_00_config.lua. Looks: the BTX-42 pistol on the
    HL2 pistol's hands (its own pistol hidden). Offsets are first guesses.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Toolgun"
SWEP.Category = "Rhylib"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/btx42_pistol.mdl"
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

-- The pistol prop on the right hand (forward, right, up; pitch, yaw, roll).
SWEP.PropVMPos = Vector(4, 1.4, -2.4)
SWEP.PropVMAng = Angle(-6, 0, 180)
SWEP.PropWMPos = Vector(4, 1, -2)
SWEP.PropWMAng = Angle(-10, 0, 180)

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

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
    local function place(pos, ang, off, rot)
        local p = pos + ang:Forward() * off.x + ang:Right() * off.y + ang:Up() * off.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), rot.y)
        a:RotateAroundAxis(a:Right(), rot.p)
        a:RotateAroundAxis(a:Forward(), rot.r)
        return p, a
    end

    function SWEP:Prop()
        if not IsValid(self.prop) then
            self.prop = ClientsideModel(self.WorldModel, RENDERGROUP_OPAQUE)
            if IsValid(self.prop) then self.prop:SetNoDraw(true) end
        end
        return IsValid(self.prop) and self.prop or nil
    end

    function SWEP:DrawPropOn(ent, bone, off, rot)
        local b = ent:LookupBone(bone)
        local m = b and ent:GetBoneMatrix(b)
        local e = m and self:Prop()
        if not e then return end
        local p, a = place(m:GetTranslation(), m:GetAngles(), off, rot)
        e:SetPos(p)
        e:SetAngles(a)
        e:SetupBones()
        e:DrawModel()
    end

    -- The HL2 pistol is hidden (render blend 0, put back by the hook below
    -- before the hands draw); the prop goes on the hand.
    function SWEP:PreDrawViewModel(vm)
        render.SetBlend(0)
        vm.rhylibBlendOff = true
    end

    -- (same id as rhylib_weapons' copy, so only one runs)
    Rhylib.Hook.Add("PostDrawViewModel", "weapons.blendreset", function(vm)
        if IsValid(vm) and vm.rhylibBlendOff then
            render.SetBlend(1)
            vm.rhylibBlendOff = nil
        end
    end, -1000)

    function SWEP:PostDrawViewModel(vm)
        self:DrawPropOn(vm, "ValveBiped.Bip01_R_Hand", self.PropVMPos, self.PropVMAng)
    end

    function SWEP:DrawWorldModel()
        local o = self:GetOwner()
        if not IsValid(o) then self:DrawModel() return end
        self:DrawPropOn(o, "ValveBiped.Bip01_R_Hand", self.PropWMPos, self.PropWMAng)
    end

    function SWEP:OnRemove()
        if IsValid(self.prop) then self.prop:Remove() end
    end

    function SWEP:DrawHUD()
        local Tool = Rhylib.Tool
        if Tool and Tool.DrawHUD then Tool.DrawHUD(self) end
    end
end
