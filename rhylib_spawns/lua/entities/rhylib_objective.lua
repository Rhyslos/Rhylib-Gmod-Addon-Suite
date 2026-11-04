--[[
    Objective marker (rhylib_spawns event tools, sh_20_events.lua): placed
    by staff with the toolgun (Spawns > Objective marker), named on
    placing. Players it's for see it on the HUD with the distance to it,
    from anywhere (cl_20_events.lua). E as staff: rename, who sees it,
    shown while jammed. Players walk through it. Not saved over a map
    change. Sent to every client (TRANSMIT_ALWAYS) so the HUD finds it
    anywhere on the map.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Objective marker"
ENT.Category = "Rhy's Spawn points"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

local COL = Color(255, 200, 70)

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "BeaconName")   -- (the toolgun names it through this)
    self:NetworkVar("String", 1, "Battalion")    -- ("" = everyone)
    self:NetworkVar("Bool", 0, "ShowJammed")
end

function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end

function ENT:Initialize()
    local S = Rhylib.Spawns
    if S then
        S.objectives = S.objectives or {}
        S.objectives[self] = true
    end
    if CLIENT then return end
    self:SetModel(Rhylib.Config.Get("spawns", "objectiveModel"))
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetUseType(SIMPLE_USE)
    self:SetColor(COL)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    -- (the toolgun names unnamed things "Beacon")
    if self:GetBeaconName() == "" or self:GetBeaconName() == "Beacon" then self:SetBeaconName("Objective") end
end

function ENT:OnRemove(fullUpdate)
    if fullUpdate then return end   -- (a client full update: it's still there)
    local S = Rhylib.Spawns
    if S and S.objectives then S.objectives[self] = nil end
end

if SERVER then
    function ENT:Use(ply)
        local S = Rhylib.Spawns
        if S and S.OpenObjectiveEdit then S.OpenObjectiveEdit(ply, self) end
    end
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    function ENT:Draw() self:DrawModel() end
    function ENT:DrawTranslucent()
        local pos = self:GetPos() + Vector(0, 0, 8)
        if LocalPlayer():GetPos():DistToSqr(pos) > 800 * 800 then return end
        local pulse = 0.75 + 0.25 * math.sin(CurTime() * 3)
        render.SetMaterial(GLOW)
        render.DrawSprite(pos, 30 * pulse, 30 * pulse, Color(COL.r, COL.g, COL.b, 200))
    end
end
