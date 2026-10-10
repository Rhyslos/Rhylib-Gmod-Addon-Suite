--[[
    Bacta tank (med bay). Press E to climb in: you're held inside and
    healed over time (health, bleeding, damage and burns; bones after a
    few seconds). Jump or E climbs out; fully healed lets you out by
    itself. A Chemist with Bacta specialist nearby doubles the rate.
    The tank also makes a med bay around it (Med.InMedBay).
    Logic: rhylib_medical sv_40_medbay.lua. Saved per map with
    rhylib_medical_save.
    Shared entity (admins spawn it: Rhylib: Medical). Model: config medical
    tankModel (a fridge if that model is missing). NetworkVar Occupant =
    who is inside (for the label and the blue light).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Bacta tank"
ENT.Category = "Rhylib: Medical"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.IsRhylibMedBay = true   -- (marks med bay fixtures)

local FALLBACK = "models/props_c17/FurnitureFridge001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Occupant")
end

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))   -- facing you
    ent:Spawn()
    ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z))
    return ent
end

function ENT:Initialize()
    if CLIENT then return end
    local Med = Rhylib.Medical
    local m = Med and Med.Cfg("tankModel") or FALLBACK
    if not isstring(m) or not util.IsValidModel(m) then m = FALLBACK end
    self:SetModel(m)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

if SERVER then
    function ENT:Use(ply)
        local Med = Rhylib.Medical
        if Med and Med.TankUse and IsValid(ply) and ply:IsPlayer() then Med.TankUse(self, ply) end
    end

    function ENT:OnRemove()
        local Med = Rhylib.Medical
        local o = self:GetOccupant()
        if Med and Med.TankExit and IsValid(o) then Med.TankExit(o) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local Med = Rhylib.Medical
        if not (Med and Med.DrawEntLabel) then return end
        local o = self:GetOccupant()
        Med.DrawEntLabel(self, "Bacta tank", IsValid(o) and ("In use · " .. o:Nick()) or "Press E to climb in")
    end

    function ENT:Think()
        if not IsValid(self:GetOccupant()) then return end
        local d = DynamicLight(self:EntIndex())
        if d then
            d.pos = self:WorldSpaceCenter()
            d.r, d.g, d.b = 80, 170, 255
            d.brightness = 2
            d.decay = 1000
            d.size = 160
            d.dietime = CurTime() + 0.2
        end
    end
end
