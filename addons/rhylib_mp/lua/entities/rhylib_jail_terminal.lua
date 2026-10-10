--[[
    Jail terminal: MPs press E to jail cuffed prisoners standing near it
    (or escorted by them), release prisoners, and go through evidence.

    Shared entity, frozen in place. Model: config mp terminalModel (falls
    back to the HL2 combine_interface001 when that model isn't installed).
    E calls MP.OpenTerminal (sv_30_jail), which checks the player is an MP.
    Saved with rhylib_mp_save or the toolgun's Permanent tool.
]]


AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Jail terminal"
ENT.Category = "Rhylib: Military police"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:Initialize()
    if SERVER then
        local m = Rhylib.Config.Get("mp", "terminalModel")
        if not (isstring(m) and util.IsValidModel(m)) then m = "models/props_combine/combine_interface001.mdl" end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos)
        e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        e:Spawn()
        return e
    end

    function ENT:Use(ply)
        if IsValid(ply) and ply:IsPlayer() and Rhylib.MP then Rhylib.MP.OpenTerminal(ply, self) end
    end
end
