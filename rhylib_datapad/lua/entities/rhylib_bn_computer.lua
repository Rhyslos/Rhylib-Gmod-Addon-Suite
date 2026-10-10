--[[
    Battalion computer (entity, shared): troopers upload their datapad logs
    here and use the battalion's computer window (logs, board, orders,
    missions, LOA, personnel, stats, applications; cl_20_terminal.lua).
    An admin sets the battalion (a DarkRP job category) from its window,
    or later with rhylib_datapad_setbattalion. Make it permanent with the
    toolgun's Permanent tool (or rhylib_datapad_save) to keep it after a
    map change; the battalion is saved with it.

    E runs Rhylib.Datapad.UseTerminal (sv_20_terminals.lua). The model is
    Rhylib.Datapad.MODELS[ENT.ModelKey] (Server settings > Models).
    The medical holotable is built on this class.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Battalion computer"
ENT.Category = "Rhylib: Terminals"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ModelKey = "battalion"   -- key in Rhylib.Datapad.MODELS

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Battalion")   -- "" = not set yet (the holotable never uses it)
end

function ENT:Initialize()
    if CLIENT then return end
    self:SetModel(Rhylib.Datapad.MODELS[self.ModelKey])
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

if SERVER then
    function ENT:Use(ply)
        Rhylib.Datapad.UseTerminal(self, ply)
    end
end

if CLIENT then
    -- ENT:LabelText(): title and sub line of the floating label. Override it
    -- in a class built on this one (the holotable does).
    function ENT:LabelText()
        local bn = self:GetBattalion()
        return bn ~= "" and (bn .. " computer") or self.PrintName, "Press E to upload and read logs"
    end

    function ENT:Draw()
        self:DrawModel()
        local title, sub = self:LabelText()
        Rhylib.Datapad.DrawLabel(self, title, sub)
    end
end
