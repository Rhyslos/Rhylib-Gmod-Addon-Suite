--[[
    A planted Republic mine (EOD Republic mines skill; the item is the
    rhylib_rep_mine weapon). Half buried like the droids' mines, but every
    player sees it outlined in blue, and only droids set it off. The blast
    only hurts droids. Rules: rhylib_eod sv_35_repmines.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Republic mine"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = false
ENT.Model = "models/props/starwars/weapons/ap_mine.mdl"
ENT.FallbackModel = "models/props_combine/combine_mine01.mdl"
ENT.ModelFromConfig = true   -- (eod mineModel)
ENT.IsRepMine = true

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Planter")
    self:NetworkVar("Bool", 0, "Wide")   -- (Minefield: wider blast)
end

-- Model: config mineModel (HL2 hopper mine if missing). Drawn scaled to
-- mineSize like the droids' AP mines; tinted blue.
function ENT:WantedModel()
    local E = Rhylib.EOD
    local mdl = E and E.Cfg("mineModel")
    if isstring(mdl) and (util.IsValidModel(mdl) or (CLIENT and file.Exists(mdl, "GAME"))) then return mdl end
    return self.FallbackModel
end

function ENT:MineScale()
    local E = Rhylib.EOD
    local want = E and E.Cfg("mineSize") or 20
    local mn, mx = self:GetModelBounds()
    if not mn then return 1 end
    local wide = math.max(mx.x - mn.x, mx.y - mn.y)
    if wide < 1 then return 1 end
    return math.Clamp(want / wide, 0.05, 4)
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self:WantedModel())
        self:SetSolid(SOLID_BBOX)
        local sc = self:MineScale()
        local mn, mx = self:GetModelBounds()
        local half = math.max(8, math.max(-mn.x, mx.x, -mn.y, mx.y) * sc)
        self:SetCollisionBounds(Vector(-half, -half, mn.z * sc), Vector(half, half, mx.z * sc + 3))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        self.armAt = CurTime() + 2
        local E = Rhylib.EOD
        if E and E.repMines then E.repMines[self] = true end
    end

    function ENT:OnRemove()
        local E = Rhylib.EOD
        if E and E.repMines then E.repMines[self] = nil end
    end
end

if CLIENT then
    function ENT:Draw()
        local key = self:GetModel() .. ((Rhylib.EOD and Rhylib.EOD.Cfg("mineSize")) or 20)
        if self.rhylibScaled ~= key then
            self.rhylibScaled = key
            local m = Matrix()
            m:Scale(Vector(1, 1, 1) * self:MineScale())
            self:EnableMatrix("RenderMultiply", m)
            self:SetRenderBounds(self:OBBMins() - Vector(8, 8, 8), self:OBBMaxs() + Vector(8, 8, 8))
        end
        render.SetColorModulation(0.7, 0.85, 1)
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
    end
end
