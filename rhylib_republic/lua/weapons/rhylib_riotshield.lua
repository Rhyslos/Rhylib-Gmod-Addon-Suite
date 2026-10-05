--[[
    Riot shield + DC-15S (military police, rhylib_skills Shock Trooper >
    Riot shield). A DC-15S fired from the hip in the right hand, a shield
    on the left arm: bolts from the front stop on it (rhylib_weapons
    sh_60_shield.lua), and so does a breaching charge's blast. No aiming;
    right click is a shield bash with the Shield bash skill.

    First person: GMod's own HL2 stun stick viewmodel used as arms only
    (CarrierInvisible: the stick isn't drawn, the hands are), the left
    upper arm moved into view (CarrierBoneMods), the shield drawn on the
    left hand and the DC-15S on the right hand. Third person: the shield
    on the left forearm, the left arm turned off the gun (WorldBoneMods).

    The shield model is config weapons riotShield (a key of SHIELDS below);
    the first one whose model is installed is used. Models come from
    Workshop dependencies: models/bshields/* and the TF2 baton shield from
    2710278536 / 1819166858 / 2876044103, models/hevy/w_shield.mdl from
    1687809853. Numbers to start from: the ballistic shield addon's tuning
    on the same arms (numbers only). Tune in game: rhylib_extra_editor
    (shield and arms), rhylib_vm_editor / rhylib_wm_editor (the gun).
]]

AddCSLuaFile()

DEFINE_BASECLASS("rhylib_dc15s")

Rhylib.Config.Register("weapons", "riotShield", "tf2", "Riot shield model: tf2, riot, heavy or hevy (first installed one wins)")

SWEP.Base = "rhylib_dc15s"
SWEP.PrintName = "Riot shield (DC-15S)"
SWEP.Category = "Rhylib: Equipment"
SWEP.Spawnable = true

SWEP.RiotShield = true
SWEP.NoAim = true
SWEP.CarrySkill = "riot_shield"
SWEP.HoldType = "pistol"
SWEP.LoweredHold = "passive"   -- (keeps its old sprint pose; pistol grips otherwise lower to "normal")

-- Arms: the HL2 stun stick viewmodel (ships with GMod), drawn invisible.
SWEP.CarrierVM = "models/weapons/c_stunstick.mdl"
SWEP.CarrierBone = "ValveBiped.Bip01_R_Hand"
SWEP.CarrierInvisible = true
SWEP.CarrierBoneMove = nil
SWEP.CarrierFOV = 70
SWEP.PropBonePos = Vector(4, 1.6, -1.5)   -- the DC-15S in the right hand (guess; rhylib_vm_editor)
SWEP.PropBoneAng = false                  -- (worked out on the first idle frame: pointing ahead)
SWEP.VMOffset = Vector(0, 0, 0)
SWEP.SafePose = nil
SWEP.CarrierHideBones = nil
SWEP.FireAct = false                      -- (the stun stick has no firing or reload animation)
SWEP.ReloadAct = ACT_VM_IDLE
SWEP.CarrierBoneMods = {
    ["ValveBiped.Bip01_L_UpperArm"] = { pos = Vector(1.171, 5.705, -11.485), ang = Angle(4, -62, -1) },
    ["ValveBiped.Bip01_R_UpperArm"] = { pos = Vector(0, 3.914, 0), ang = Angle(0, 0, 0) },
}
-- Third person: the left arm off the pistol grip (start: none; rhylib_extra_editor).
SWEP.WorldBoneMods = {
    ["ValveBiped.Bip01_L_UpperArm"] = Angle(0, 0, 0),
    ["ValveBiped.Bip01_L_Forearm"] = Angle(0, 0, 0),
}

-- Shield models and where they sit (first person on the left hand, third
-- person on the left forearm).
local SHIELDS = {
    tf2 = { model = "models/workshop/weapons/c_models/c_batonshield/c_batonshield_shield.mdl",
        vmPos = Vector(30.851, 42.902, -5.067), vmAng = Angle(0.535, 54.853, 5.843), vmScale = 1,
        wmPos = Vector(-43.257, 6.151, -1.39), wmAng = Angle(0, 79.309, 178.636), wmScale = 0.899 },
    riot = { model = "models/bshields/rshield.mdl",
        vmPos = Vector(-3, 4.21, 2.9), vmAng = Angle(0, 90.364, 1.33), vmScale = 0.699,
        wmPos = Vector(5.6, 2.9, 0.7), wmAng = Angle(0, 100, 0), wmScale = 0.92 },
    heavy = { model = "models/bshields/hshield.mdl",
        vmPos = Vector(-3, 4.21, 2.9), vmAng = Angle(0, 90.364, 1.33), vmScale = 0.699,
        wmPos = Vector(5.6, 2.9, 0.7), wmAng = Angle(0, 100, 0), wmScale = 0.92 },
    hevy = { model = "models/hevy/w_shield.mdl",
        vmPos = Vector(-3, 4.21, 2.9), vmAng = Angle(0, 90, 0), vmScale = 0.7,
        wmPos = Vector(4, 2, 0), wmAng = Angle(0, 90, 90), wmScale = 0.92 },
}
local ORDER = { "tf2", "riot", "heavy", "hevy" }

local function shieldProp()
    local want = Rhylib.Config.Get("weapons", "riotShield")
    local list = { want }
    for _, k in ipairs(ORDER) do if k ~= want then list[#list + 1] = k end end
    for _, k in ipairs(list) do
        local sh = SHIELDS[k]
        if sh and util.IsValidModel(sh.model) then
            return { key = "shield", model = sh.model,
                vmBone = "ValveBiped.Bip01_L_Hand", vmPos = sh.vmPos, vmAng = sh.vmAng, vmScale = sh.vmScale,
                wmBone = "ValveBiped.Bip01_L_Forearm", wmPos = sh.wmPos, wmAng = sh.wmAng, wmScale = sh.wmScale }
        end
    end
end

SWEP.ExtraProps = nil   -- (picked per weapon in Initialize, from the installed models)

function SWEP:Initialize()
    BaseClass.Initialize(self)
    if CLIENT then
        local p = shieldProp()
        self.ExtraProps = p and { p } or nil
    end
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return BaseClass.Deploy(self)
end

SWEP.InvW = 3
SWEP.InvH = 2
SWEP.InvLarge = true
SWEP.InvWeight = 9.0         -- kg (gun and shield)

SWEP.MoveMult = 0.85         -- walking with a shield up
SWEP.BashRange = 75
SWEP.BashDelay = 1.5

function SWEP:GetMoveMult()
    local m = BaseClass.GetMoveMult(self)
    return math.min(m, self.MoveMult)
end

-- Right click: shield bash (Shield bash skill).
function SWEP:Think()
    BaseClass.Think(self)
    local o = self:GetOwner()
    if not (IsValid(o) and o:IsPlayer()) or not o:KeyPressed(IN_ATTACK2) then return end
    if CurTime() < (self.rhylibNextBash or 0) or self:IsLowered() then return end
    local K = Rhylib.Skills
    if not (K and K.Has and K.Has(o, "shield_bash")) then return end
    self.rhylibNextBash = CurTime() + self.BashDelay
    self:SendWeaponAnim(ACT_VM_HITCENTER)
    if IsFirstTimePredicted() then
        o:ViewPunch(Angle(-4, 2, 0))
        self:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 5) .. ".wav", 70, 95)
    end
    if CLIENT then return end
    o:SetAnimation(PLAYER_ATTACK1)
    o:LagCompensation(true)
    local tr = util.TraceHull({
        start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * self.BashRange,
        filter = o, mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10), mask = MASK_SHOT_HULL,
    })
    o:LagCompensation(false)
    local e = tr.Entity
    local L = Rhylib.Lying
    if L and L.Owner and L.Owner(e) then return end   -- (not on someone already down)
    if not IsValid(e) then return end
    local push = o:GetAimVector()
    push.z = 0
    push:Normalize()
    if e:IsPlayer() then
        local MP = Rhylib.MP
        if MP and MP.Stun and MP.IsMP(o) then MP.Stun(e, o) end
    elseif e:IsNPC() or e:IsNextBot() then
        local d = DamageInfo()
        d:SetDamage(Rhylib.Config.Get("skills", "bashDamage") or 30)
        d:SetDamageType(DMG_CLUB)
        d:SetAttacker(o)
        d:SetInflictor(self)
        d:SetDamagePosition(tr.HitPos)
        d:SetDamageForce(push * 16000)
        e:TakeDamageInfo(d)
        if e:IsNextBot() and e.loco then e.loco:SetVelocity(push * 320 + Vector(0, 0, 120)) end
        if e.rhylibStagger then e:rhylibStagger(1) end
    end
end

if CLIENT then
    function SWEP:DrawHUD()
        BaseClass.DrawHUD(self)
        local K = Rhylib.Skills
        local o = self:GetOwner()
        if K and K.Has and IsValid(o) and K.Has(o, "shield_bash") then
            local s = ScrH() / 1080
            draw.SimpleText("RMB  shield bash", Rhylib.UI.Font(13, 600), ScrW() * 0.5, ScrH() * 0.55 + 40 * s,
                Rhylib.UI.Colors.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end
