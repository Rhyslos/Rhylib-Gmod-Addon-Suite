--[[
    Quartermaster (admins; toolgun Base, or the spawn menu "Rhy's Armoury &
    storage"). A clone standing where he was placed, idling, turning his
    head to whoever is near; "Quartermaster" over him. Walk up and press E:
    the loadout window (Rhylib.Armoury.QM.Use, rhylib/armoury/
    sv_50_quartermaster.lua). Can't be hurt or moved.

    Make him permanent with the toolgun's Permanent tool and he comes back
    every restart on this map (Rhylib.Perma.Placements "armoury_qm", Data
    "armoury_qm_places"). Model: armoury setting qmModel.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Quartermaster"
ENT.Category = "Rhy's Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_BOTH

local FALLBACK = "models/ct_trp/pm_ct_trp.mdl"
local IDLE = { "idle_all_01", "pose_standing_01", "idle_passive", "idle" }

local function idleSequence(e)
    for _, name in ipairs(IDLE) do
        local seq = e:LookupSequence(name)
        if seq and seq >= 0 then return seq end
    end
    return 0
end

if SERVER then
    function ENT:Initialize()
        local m = Rhylib.Config and Rhylib.Config.Get("armoury", "qmModel") or FALLBACK
        if not (isstring(m) and util.IsValidModel(m)) then m = FALLBACK end
        self:SetModel(m)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-14, -14, 0), Vector(14, 14, 72))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetUseType(SIMPLE_USE)
        self:ResetSequence(idleSequence(self))
        self:SetPlaybackRate(1)
    end

    function ENT:Think()
        -- (keeps the idle looping)
        if self:GetCycle() >= 0.99 then self:ResetSequence(idleSequence(self)) end
        self:NextThink(CurTime() + 0.5)
        return true
    end

    function ENT:OnTakeDamage() end

    -- (spawn menu: on the ground where you aim, facing you)
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos)
        e:SetAngles(Angle(0, (ply:GetPos() - tr.HitPos):Angle().y, 0))
        e:Spawn()
        e:Activate()
        return e
    end

    function ENT:Use(ply)
        local Q = Rhylib.Armoury and Rhylib.Armoury.QM
        if Q and Q.Use then Q.Use(ply, self) end
    end
    return
end

-- Client: look at whoever is near, and the name over him.
function ENT:Initialize()
    self.lookYaw = 0
end

function ENT:Think()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local near = me:GetPos():DistToSqr(self:GetPos()) < 300 * 300
    local want = 0
    if near then
        local to = (me:EyePos() - self:EyePos()):Angle()
        want = math.Clamp(math.NormalizeAngle(to.y - self:GetAngles().y), -60, 60)
    end
    local was = self.lookYaw or 0
    if was == want then return end   -- (nothing to turn: idle or far away)
    self.lookYaw = math.Approach(was, want, FrameTime() * 120)
    if self.headBone == nil then self.headBone = self:LookupBone("ValveBiped.Bip01_Head1") or false end
    if self.headBone then self:ManipulateBoneAngles(self.headBone, Angle(0, 0, self.lookYaw * -0.6)) end
end

function ENT:Draw()
    self:DrawModel()
end

local WHITE, PURPLE, SHADOW = Color(235, 238, 240), Color(164, 110, 224), Color(0, 0, 0, 200)

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 500 * 500 then return end
    local pos = self:GetPos() + Vector(0, 0, 82)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local UI = Rhylib.UI
    local f = UI and UI.Font and UI.Font(24, 700) or "DermaLarge"
    local f2 = UI and UI.Font and UI.Font(17, 500) or "DermaDefault"
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("Quartermaster", f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined("Press E for your loadouts", f2, 0, 26, PURPLE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
