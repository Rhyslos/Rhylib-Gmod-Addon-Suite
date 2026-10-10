--[[
    Command comlink (rhylib_skills: Officer command orders).

    Carried by officers with a command order skill (job gear, given at
    spawn). LMB gives the order to you and everyone within commandRadius
    in sight (K.IssueOrder). RMB calls reinforcements with the Commander
    capstone (K.CallReinforcements). While it's out, a ring on the ground shows
    the reach, in the order's colour (grey while on cooldown).
    First person is a placeholder: the HL2 SLAM detonator in the left hand.
    Hold R: the squad wheel (cl_20_command.lua). Shared SWEP; the server
    does the work, the client draws the ring and the HUD text.
    Inventory fields (InvW/InvH/InvWeight/InvCategory, CarrySkill) are read
    by rhylib_inventory; "command" isn't a skill id, K.CarryOk handles it.
]]

AddCSLuaFile()

SWEP.Base = "weapon_base"
SWEP.PrintName = "Command comlink"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/props_lab/reciever01d.mdl"
SWEP.ViewModelFOV = 54
SWEP.UseHands = true
SWEP.HoldType = "slam"
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvWeight = 0.3
SWEP.InvCategory = "gear"
SWEP.CarrySkill = "command"   -- (any command order skill, K.CarryOk)

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_SLAM_DETONATOR_DRAW)
    self.rhylibIdleAt = CurTime() + self:VMDuration()
    return true
end

function SWEP:Think()
    if self.rhylibIdleAt and CurTime() >= self.rhylibIdleAt then
        self.rhylibIdleAt = nil
        self:SendWeaponAnim(ACT_SLAM_DETONATOR_IDLE)
    end
end

-- SWEP:VMDuration(): length of what the viewmodel is playing (at least 0.2 s).
function SWEP:VMDuration()
    local o = self:GetOwner()
    local vm = IsValid(o) and o.GetViewModel and o:GetViewModel()
    return math.max(0.2, IsValid(vm) and vm:SequenceDuration() or 0.5)
end

function SWEP:Reload() end

-- Reinforcements (Commander capstone): a clone squad around you.
function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
    if CLIENT then return end
    local K, owner = Rhylib.Skills, self:GetOwner()
    if not (K and K.CallReinforcements and IsValid(owner)) then return end
    if not K.HasReinforcements(owner) then return end
    local ok, res = K.CallReinforcements(owner)
    if ok then
        self:SendWeaponAnim(ACT_SLAM_DETONATOR_DETONATE)
        self.rhylibIdleAt = CurTime() + self:VMDuration()
        K.Note(owner, string.format("Reinforcements inbound: %d clone%s", res, res == 1 and "" or "s"))
    elseif res then
        K.Note(owner, res, true)
    end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1)
    if CLIENT then return end
    local K, owner = Rhylib.Skills, self:GetOwner()
    if not (K and K.IssueOrder and IsValid(owner)) then return end
    local ok, why = K.IssueOrder(owner)
    if ok then
        self:SendWeaponAnim(ACT_SLAM_DETONATOR_DETONATE)
        self.rhylibIdleAt = CurTime() + self:VMDuration()
    elseif why then
        K.Note(owner, why, true)
    end
end

-- No third-person prop (it sits on the wrist).
function SWEP:DrawWorldModel() end

if CLIENT then
    local beam = Material("trails/laser")
    local GREY = Color(150, 150, 150)
    local SEG = 48

    -- The reach ring around you while the comlink is out.
    Rhylib.Hook.Add("PostDrawTranslucentRenderables", "skills.commlink", function(_, sky)
        if sky then return end
        local me = LocalPlayer()
        local w = IsValid(me) and me:GetActiveWeapon()
        if not (IsValid(w) and w:GetClass() == "rhylib_commlink") then return end
        local K = Rhylib.Skills
        local o = K and K.OrderOf and K.OrderOf(me)
        if not o then return end
        local col = K.OrderCooldown(me) > 0 and GREY or o.col
        local r = K.OrderRadius and K.OrderRadius(me) or K.Cfg("commandRadius")
        local c = me:GetPos() + Vector(0, 0, 3)
        render.SetMaterial(beam)
        local prev = c + Vector(r, 0, 0)
        for i = 1, SEG do
            local a = i / SEG * math.pi * 2
            local p = c + Vector(math.cos(a) * r, math.sin(a) * r, 0)
            render.DrawBeam(prev, p, 6, 0, 1, col)
            prev = p
        end
    end)

    function SWEP:DrawHUD()
        local K, me = Rhylib.Skills, LocalPlayer()
        if not (K and K.OrderOf) then return end
        -- (hidden under the squad wheel: it overlapped the bottom option)
        local W = Rhylib.Menus and Rhylib.Menus.Wheel
        if W and W.open then return end
        local o = K.OrderOf(me)
        local w, h = ScrW(), ScrH()
        local y = h * 0.7
        local C = Rhylib.UI.Colors
        if not o then
            draw.SimpleText("No command order learned", Rhylib.UI.Font(18, 700), w * 0.5, y, C.textDim, TEXT_ALIGN_CENTER)
            return
        end
        draw.SimpleText(string.upper(o.name), Rhylib.UI.Font(20, 700), w * 0.5, y, o.col, TEXT_ALIGN_CENTER)
        local line
        local ok, why = K.RankOk(me, "commandRank")
        local cd = K.OrderCooldown(me)
        if not ok then
            line = why
        elseif cd > 0 then
            local s = math.ceil(cd)
            line = string.format("Next order in %d:%02d", math.floor(s / 60), s % 60)
        else
            line = "Ready  ·  Left click: give the order (" .. o.text .. ")"
        end
        draw.SimpleText(line, Rhylib.UI.Font(15), w * 0.5, y + h * 0.028, (ok and cd <= 0) and C.text or C.textDim, TEXT_ALIGN_CENTER)
        -- Reinforcements (Commander capstone)
        if K.HasReinforcements(me) and K.ReinfCooldown then
            local rc = K.ReinfCooldown(me)
            local rl
            local jammed = Rhylib.Radio and Rhylib.Radio.Jammed and Rhylib.Radio.Jammed(me)
            if not ok then
                rl = nil
            elseif jammed then
                rl = "Comms jammed: no reinforcements"
            elseif rc > 0 then
                local s = math.ceil(rc)
                rl = string.format("Reinforcements in %d:%02d", math.floor(s / 60), s % 60)
            else
                rl = "Right click: call reinforcements"
            end
            if rl then draw.SimpleText(rl, Rhylib.UI.Font(15), w * 0.5, y + h * 0.052, rc <= 0 and C.text or C.textDim, TEXT_ALIGN_CENTER) end
        end
        -- Squad orders (Commander officers, cl_20_command.lua)
        if ok and K.CanCommandSquad and K.CanCommandSquad(me) then
            draw.SimpleText("Hold R: squad orders", Rhylib.UI.Font(15), w * 0.5, y + h * 0.076, C.textDim, TEXT_ALIGN_CENTER)
        end
    end
end
