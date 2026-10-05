--[[
    Battalion computer: troopers upload their datapad logs here and read the
    battalion's logs. An admin sets the battalion (a DarkRP job category)
    from its window; rhylib_datapad_save keeps it on the map.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Battalion computer"
ENT.Category = "Rhylib: Terminals"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ModelKey = "battalion"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Battalion")
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
