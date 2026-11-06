--[[
    Supply crate (rhylib_logistics; staff place them with the toolgun,
    Base > Supply crate). RP stock for a supply depot
    (entities/rhylib_supply_depot.lua): set down inside a depot's ring
    its supplies (supplyCrateAmount) count there. Carried with E
    (sv_40_carry.lua); heavy (two troopers, or Heavy lifter) with
    supplyCrateHeavy.

    Droids shoot at it (rhylib_droids D.objTargets, a little less eagerly
    than at troopers: supplyCratePriority). Only droids and explosions
    hurt it (supplyCrateHealth); it doesn't explode: it breaks apart and
    its supplies are gone.

    Networked: DT Int Holders, Bool Carried (the carry system), Int
    Supplies, Bool Damaged.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Supply crate"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.rhylibDepotItem = "crate"
ENT.rhylibObjTarget = true

local FALLBACK = "models/props_junk/wood_crate001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Holders")
    self:NetworkVar("Bool", 0, "Carried")
    self:NetworkVar("Int", 1, "Supplies")
    self:NetworkVar("Bool", 1, "Damaged")
end

function ENT:IsHeavy()
    local L = Rhylib.Logistics
    return L and L.Cfg and L.Cfg("supplyCrateHeavy") and true or false
end

if SERVER then
    function ENT:Initialize()
        local L = Rhylib.Logistics
        local m = L and L.Cfg("supplyCrateModel") or FALLBACK
        if not (isstring(m) and (util.IsValidModel(m) or file.Exists(m, "GAME"))) then m = FALLBACK end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local hp = math.max(1, math.floor(L and L.Cfg("supplyCrateHealth") or 250))
        self:SetMaxHealth(hp)
        self:SetHealth(hp)
        if self:GetSupplies() <= 0 then self:SetSupplies(math.max(1, math.floor(L and L.Cfg("supplyCrateAmount") or 100))) end
        self.DroidPriority = math.max(0.25, tonumber(L and L.Cfg("supplyCratePriority")) or 1.5)
        self:PrecacheGibs()
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if L and L.carriables then L.carriables[self] = true end
        self.rhylibHome = self:GetPos()
        timer.Simple(0, function() if IsValid(self) and not self:GetCarried() then self.rhylibHome = self:GetPos() end end)
        local D = Rhylib.Droids
        if D and D.AddObjectTarget then D.AddObjectTarget(self) end
    end

    function ENT:DroidTargetable() return not self:GetCarried() end

    local function hurts(dmg)
        if dmg:IsDamageType(DMG_BLAST) or dmg:IsExplosionDamage() then return true end
        local att, inf = dmg:GetAttacker(), dmg:GetInflictor()
        return (IsValid(att) and (att.IsRhylibDroid or att.rhylibDroidShot)) or (IsValid(inf) and (inf.IsRhylibDroid or inf.rhylibDroidShot)) or false
    end

    function ENT:OnTakeDamage(dmg)
        if self.broken or not hurts(dmg) then return end
        local d = math.floor(dmg:GetDamage() + 0.5)
        if d <= 0 then return end
        local hp = self:Health() - d
        self:SetDamaged(true)
        if hp > 0 then self:SetHealth(hp) return end
        self:SetHealth(0)
        self.broken = true
        local L = Rhylib.Logistics
        if L and L.carry and L.carry[self] and L.DropCrate then L.DropCrate(self) end
        local fx = EffectData()
        fx:SetOrigin(self:WorldSpaceCenter())
        fx:SetMagnitude(2)
        fx:SetScale(1)
        fx:SetRadius(8)
        util.Effect("Sparks", fx, true, true)
        self:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 5) .. ".wav", 80)
        self:GibBreakClient(dmg:GetDamageForce() * 0.01 + Vector(0, 0, 40))
        if L and L.DepotItemLost then L.DepotItemLost(self) end
        self:Remove()
    end

    -- (set down: where it is saved when permanent, sv_70_depots.lua)
    function ENT:OnSetDown() self.rhylibHome = self:GetPos() end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer()) or self.broken then return end
        local L = Rhylib.Logistics
        if L and L.CrateUse then L.CrateUse(ply, self) end
    end

    function ENT:OnRemove()
        local L = Rhylib.Logistics
        if L then
            if L.carriables then L.carriables[self] = nil end
            if L.CrateRemoved then L.CrateRemoved(self) end
        end
        local D = Rhylib.Droids
        if D and D.RemoveObjectTarget then D.RemoveObjectTarget(self) end
    end
    return
end

function ENT:Draw()
    self:DrawModel()
end

local WHITE, DIM, RED, AMBER, SHADOW = Color(235, 238, 240), Color(170, 180, 186), Color(255, 140, 120), Color(255, 190, 90), Color(0, 0, 0, 200)

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    local L = Rhylib.Logistics
    local range = L and L.Cfg and L.Cfg("depotLabelRange") or 790
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > (range * 0.45) ^ 2 then return end
    local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 8)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local f = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(20, 700) or "DermaDefaultBold"
    local f2 = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(16, 600) or "DermaDefault"
    local sub, col
    if self:GetCarried() then
        sub, col = "Set it down in a supply depot", DIM
    elseif self:GetHolders() == 1 then
        sub, col = "Heavy: a second trooper press E", AMBER
    elseif self:GetDamaged() then
        sub, col = "Damaged", RED
    else
        sub, col = self:IsHeavy() and "Heavy · E with a second trooper" or "E to carry", DIM
    end
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("SUPPLIES · " .. self:GetSupplies(), f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined(sub, f2, 0, 22, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
