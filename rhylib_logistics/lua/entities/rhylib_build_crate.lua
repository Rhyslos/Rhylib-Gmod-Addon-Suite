--[[
    Building supply crate (rhylib_logistics): set down from building
    supplies (weapons/rhylib_build_supplies.lua) or by staff with the
    toolgun (full of logistics staffCrate). Structures placed within
    buildSupplyRange take their cost out of it (sv_30_build.lua); empty,
    it goes. E carries it (sv_40_carry.lua): light up to crateLightMax,
    heavy above (two troopers, or one with Heavy lifter).

    Networked: DT Int Supplies, Bool Carried (being carried: not counted
    for building), Int Holders (how many carry it: 0-2, for the label).
    L.crates lists every crate (both realms). Not saved.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Building supplies"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local FALLBACK = "models/props_junk/wood_crate001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Supplies")
    self:NetworkVar("Int", 1, "Holders")
    self:NetworkVar("Bool", 0, "Carried")
end

-- Heavy: more than crateLightMax in it.
function ENT:IsHeavy()
    local L = Rhylib.Logistics
    if not L then return false end
    return self:GetSupplies() > L.Cfg("crateLightMax")
end

if SERVER then
    function ENT:Initialize()
        local L = Rhylib.Logistics
        local m = L and L.Cfg("crateModel") or FALLBACK
        if not (isstring(m) and util.IsValidModel(m)) then m = FALLBACK end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if L then L.crates[self] = true end
    end

    -- Staff with the toolgun: a full crate.
    function ENT:StaffPlaced(ply)
        local L = Rhylib.Logistics
        if L then self:SetSupplies(math.max(1, math.floor(L.Cfg("staffCrate")))) end
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
            L.crates[self] = nil
            if L.CrateRemoved then L.CrateRemoved(self) end
        end
    end
    return
end

function ENT:Initialize()
    local L = Rhylib.Logistics
    if L then L.crates[self] = true end
end

function ENT:OnRemove()
    local L = Rhylib.Logistics
    if L then L.crates[self] = nil end
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
    local heavy = self:IsHeavy()
    local sub
    if self:GetCarried() then
        sub = "Being carried"
    elseif self:GetHolders() == 1 and heavy then
        sub = "Heavy: a second trooper press E"
    else
        sub = heavy and "Heavy · E with a second trooper (or Heavy lifter)" or "E to carry"
    end
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("BUILDING SUPPLIES · " .. self:GetSupplies(), f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined(sub, f2, 0, 26, heavy and AMBER or DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
