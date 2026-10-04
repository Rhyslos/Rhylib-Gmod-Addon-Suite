--[[
    Blood analyser (med bay): medics press E and analyse the blood samples
    they carry (up to 4 at once); the result is written on the sample.
    Logic: rhylib_medical sv_50_illness.lua. Saved per map with
    rhylib_medical_save.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Blood analyser"
ENT.Category = "Rhylib Medical"
ENT.Spawnable = true
ENT.AdminOnly = true

local FALLBACK = "models/props_lab/reciever_cart.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Busy")   -- (samples running)
end

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    ent:Spawn()
    ent:SetPos(tr.HitPos - Vector(0, 0, ent:OBBMins().z))
    return ent
end

function ENT:Initialize()
    if CLIENT then return end
    local Med = Rhylib.Medical
    local m = Med and Med.Cfg("analyserModel") or FALLBACK
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
        if Med and Med.AnalyserUse and IsValid(ply) and ply:IsPlayer() then Med.AnalyserUse(self, ply) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local Med = Rhylib.Medical
        local busy = self:GetBusy()
        if Med and Med.DrawEntLabel then Med.DrawEntLabel(self, "Blood analyser", busy > 0 and ("Analysing " .. busy .. " · Press E") or "Medics · Press E") end
    end
end
