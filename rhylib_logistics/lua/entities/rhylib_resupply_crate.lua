--[[
    Armoury resupply crate (rhylib_logistics): called in by an officer at
    a command post (sv_60_calls.lua) or placed by staff with the toolgun.
    Always heavy: two troopers carry it (E each), or one with Heavy
    lifter (sv_40_carry.lua). Set down within logistics resupplyRange of
    a weapons armoury, ammo cabinet, gear cabinet or specialist rack, it
    unloads: each counted item gets resupplyAmount of its max back
    (sv_50_stock.lua L.ResupplyAt) and the crate goes.

    Networked: DT Int Holders, Bool Carried. In L.carriables (server).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Armoury resupply crate"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local FALLBACK = "models/props_junk/wood_crate002a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Holders")
    self:NetworkVar("Bool", 0, "Carried")
end

function ENT:IsHeavy() return true end

if SERVER then
    function ENT:Initialize()
        local L = Rhylib.Logistics
        local m = L and L.Cfg("resupplyModel") or FALLBACK
        if not (isstring(m) and util.IsValidModel(m)) then m = FALLBACK end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if L and L.carriables then L.carriables[self] = true end
    end

    -- Staff with the toolgun: unloads at once when placed by a cabinet.
    function ENT:StaffPlaced(ply)
        local L = Rhylib.Logistics
        timer.Simple(0, function()
            if IsValid(self) and L and L.ResupplyAt then L.ResupplyAt(self) end
        end)
    end

    function ENT:OnSetDown(a, b)
        local L = Rhylib.Logistics
        if L and L.ResupplyAt then L.ResupplyAt(self, a) end
    end

    function ENT:OnTakeDamage() end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        local L = Rhylib.Logistics
        if L and L.CrateUse then L.CrateUse(ply, self) end
    end

    function ENT:OnRemove()
        local L = Rhylib.Logistics
        if L then
            if L.carriables then L.carriables[self] = nil end
            if L.CrateRemoved then L.CrateRemoved(self) end
        end
    end
    return
end

function ENT:Draw()
    self:DrawModel()
end

local WHITE, DIM, AMBER, SHADOW = Color(235, 238, 240), Color(170, 180, 186), Color(255, 190, 90), Color(0, 0, 0, 200)

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 350 * 350 then return end
    local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 10)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local f = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(24, 700) or "DermaLarge"
    local f2 = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(18, 600) or "DermaDefaultBold"
    local sub
    if self:GetCarried() then
        sub = "Set it down by an armoury to restock"
    elseif self:GetHolders() == 1 then
        sub = "Heavy: a second trooper press E"
    else
        sub = "Heavy · E with a second trooper (or Heavy lifter)"
    end
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("ARMOURY RESUPPLY", f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined(sub, f2, 0, 26, self:GetCarried() and DIM or AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
