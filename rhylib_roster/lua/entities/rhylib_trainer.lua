--[[
    Training instructor (admins; spawn menu "Rhy's Roster", or the
    toolgun's spawn window). A clone standing where it was placed, idling,
    turning his head to whoever is near; "Basic training instructor" over
    him. A cadet walks up and presses E to take the basic training quiz
    (R.QuizStart, rhylib/roster/sv_60_quiz.lua); anyone else is told
    they've passed already. Can't be hurt or moved.

    Make him permanent with the toolgun's Permanent tool and he comes back
    every restart on this map (Rhylib.Perma.Placements "roster", Data
    "roster_places"). Model: roster setting trainerModel.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Training instructor"
ENT.Category = "Rhy's Roster"
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
        local R = Rhylib.Roster
        local m = R and R.Cfg and R.Cfg("trainerModel") or FALLBACK
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
        if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end
        if ply:GetPos():DistToSqr(self:GetPos()) > 160 * 160 then return end
        if (ply.rhylibTrainerUse or 0) > CurTime() then return end   -- (one press at a time)
        ply.rhylibTrainerUse = CurTime() + 1
        local R = Rhylib.Roster
        if not R then return end
        local me = R.Get(ply)
        if not me.has then return end
        if me.trained then
            return Rhylib.Notify(ply, "You've passed basic training already, trooper.", "info", "Training")
        end
        if R.QuizStart then R.QuizStart(ply) end
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

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 500 * 500 then return end
    local pos = self:GetPos() + Vector(0, 0, 82)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local f = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(24, 700) or "DermaLarge"
    local f2 = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(17, 500) or "DermaDefault"
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("Basic training instructor", f, 0, 0, Color(235, 238, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
        local R = Rhylib.Roster
        local c = R and R.Get and R.Get(me)
        if c and c.has and not c.trained then
            draw.SimpleTextOutlined("Press E for the basic training quiz", f2, 0, 26, Color(120, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
        end
    cam.End3D2D()
end
