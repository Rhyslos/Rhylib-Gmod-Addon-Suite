--[[
    E-tool (rhylib_logistics): the field technician's folding shovel for
    building field structures. Only field technicians get it from the gear
    cabinet (sv_30_build.lua). Also the base of the repair tool
    (weapons/rhylib_repairtool.lua).

    R (hold): build menu. RMB: place the picked structure as a hologram.
    LMB (hold) on a hologram: build it. E / Q: turn the ghost 45 degrees.
    Z (the undo key): remove the structure you look at (yours only).
    How it all works: rhylib/logistics/sh_30_build.lua; client parts
    (ghost, menu, keys, HUD) in cl_30_build.lua.

    The tool model is drawn in the hand on the crowbar's hands (first
    person: SWEP.VMOffset / VMAngle / VMScale from the right hand bone;
    third person: SWEP.WMOffset / WMAngle / WMScale). Third-person pose:
    HoldType (melee2), or the datapad's with HoldLikeDatapad (repair tool).
]]

AddCSLuaFile()

SWEP.PrintName = "E-tool"
SWEP.Category = "Rhy's Logistics"
SWEP.Author = "Rhy"
SWEP.Spawnable = true
SWEP.AdminOnly = true   -- (players get them from the gear cabinet)
SWEP.Slot = 4
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/niksacokica/misc/misc_tool_shovel_01.mdl"
SWEP.ToolModel = "models/niksacokica/misc/misc_tool_shovel_01.mdl"
SWEP.HoldType = "melee2"
SWEP.HoldLikeDatapad = false   -- (true: Initialize takes the datapad's hold type instead; the repair tool does)
SWEP.CanRepair = false
SWEP.CanPlace = true   -- (the repair tool can't: it only helps build and repairs)

SWEP.InvGroup = "gear"
SWEP.InvW = 1
SWEP.InvH = 3
SWEP.InvWeight = 2

-- Where the tool sits in the hand and how big it is (rhylib_vm_editor /
-- rhylib_wm_editor with Rhy's Dev Tools, or rhylib_tool_tune).
SWEP.VMScale = 1
SWEP.WMScale = 0.6
SWEP.VMOffset = Vector(2.8, -1.2, 0)
SWEP.VMAngle = Angle(90, 90, 180)
SWEP.WMOffset = Vector(3.7, -1.5, -0.5)
SWEP.WMAngle = Angle(70, 0, 90)

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

-- HoldLikeDatapad: held like the datapad in third person (the hold type of
-- the SWEP named in rhylib_datapad's config "class", default sw_datapad),
-- else HoldType.
function SWEP:Initialize()
    if not self.HoldLikeDatapad then self:SetHoldType(self.HoldType) return end
    local C = Rhylib.Config
    local class = C and C.defs and C.defs.datapad and C.Get("datapad", "class") or "sw_datapad"
    local st = isstring(class) and weapons.GetStored(class)
    if st and isstring(st.HoldType) and st.HoldType ~= "" then self.HoldType = st.HoldType end
    self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

-- LMB is handled in Think (held: build / repair).
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.1)
end

-- RMB: place the picked structure.
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.4)
    if self.CanPlace and CLIENT and IsFirstTimePredicted() then
        local L = Rhylib.Logistics
        if L and L.SendPlace then L.SendPlace() end
    end
end

-- R: the build menu (client).
function SWEP:Reload()
    if self.CanPlace and CLIENT and IsFirstTimePredicted() then
        local L = Rhylib.Logistics
        if L and L.OpenBuildMenu then L.OpenBuildMenu() end
    end
end

function SWEP:Think()
    local o = self:GetOwner()
    if not (IsValid(o) and o:IsPlayer()) then return end
    if not o:KeyDown(IN_ATTACK) then return end
    local now = CurTime()
    -- (a swing now and then while working)
    if now >= (self.swingAt or 0) then
        self.swingAt = now + 0.9
        self:SendWeaponAnim(ACT_VM_HITCENTER)
        o:SetAnimation(PLAYER_ATTACK1)
    end
    if SERVER then
        local L = Rhylib.Logistics
        if L and L.BuildTick then L.BuildTick(o, self, engine.TickInterval()) end
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        local L = Rhylib.Logistics
        if L and L.DrawBuildHUD then L.DrawBuildHUD(self) end
    end

    local function toolModel(self, key, scale)
        local m = self[key]
        if not IsValid(m) then
            m = ClientsideModel(self.ToolModel, RENDERGROUP_OPAQUE)
            if not IsValid(m) then return nil end
            m:SetNoDraw(true)
            self[key] = m
        end
        scale = scale or 1
        if m.rhylibScale ~= scale then
            m.rhylibScale = scale
            local mat = Matrix()
            mat:Scale(Vector(scale, scale, scale))
            m:EnableMatrix("RenderMultiply", mat)
        end
        return m
    end

    -- (the crowbar itself is hidden: only the hands and the tool show)
    function SWEP:PreDrawViewModel(vm)
        render.SetBlend(0)
    end

    function SWEP:PostDrawViewModel(vm)
        render.SetBlend(1)   -- (the hands get it back first: PreDrawPlayerHands, cl_30_build.lua)
        local m = toolModel(self, "vmTool", self.VMScale)
        if not m then return end
        local bone = vm:LookupBone("ValveBiped.Bip01_R_Hand")
        local mat = bone and vm:GetBoneMatrix(bone)
        if not mat then return end
        local pos, ang = LocalToWorld(self.VMOffset, self.VMAngle, mat:GetTranslation(), mat:GetAngles())
        m:SetPos(pos)
        m:SetAngles(ang)
        m:SetupBones()
        m:DrawModel()
    end

    function SWEP:DrawWorldModel()
        local o = self:GetOwner()
        if not IsValid(o) then
            self:DrawModel()
            return
        end
        local m = toolModel(self, "wmTool", self.WMScale)
        if not m then return end
        local bone = o:LookupBone("ValveBiped.Bip01_R_Hand")
        local mat = bone and o:GetBoneMatrix(bone)
        if not mat then return end
        local pos, ang = LocalToWorld(self.WMOffset, self.WMAngle, mat:GetTranslation(), mat:GetAngles())
        m:SetPos(pos)
        m:SetAngles(ang)
        m:SetupBones()
        m:DrawModel()
    end

    function SWEP:OnRemove()
        if IsValid(self.vmTool) then self.vmTool:Remove() end
        if IsValid(self.wmTool) then self.wmTool:Remove() end
    end

    function SWEP:Holster()
        if IsValid(self.vmTool) then self.vmTool:Remove() end
        return true
    end
end
