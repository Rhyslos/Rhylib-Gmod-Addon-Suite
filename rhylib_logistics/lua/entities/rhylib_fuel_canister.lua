--[[
    Fuel canister (rhylib_logistics; staff place them with the toolgun,
    Base > Fuel canister). RP stock for a supply depot
    (entities/rhylib_supply_depot.lua): set down inside a depot's ring it
    counts there. One trooper carries it (E, sv_40_carry.lua).

    Explosive: fuelHits hits from anyone's gun set it off, any explosion
    (blast or fire damage) at once. It blows up with fuelRadius /
    fuelDamage, hurting everyone near (the world is the attacker), and
    canisters caught in the blast go off a moment later, one after
    another.

    Droids (rhylib_droids D.objTargets) only shoot at it while a player or
    clone is within fuelNear of it (ENT:DroidTargetable), as eagerly as
    at a trooper (DroidPriority 1).

    Networked: DT Int Holders, Bool Carried (the carry system), Int Hits.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Fuel canister"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.rhylibDepotItem = "fuel"
ENT.rhylibObjTarget = true
ENT.DroidPriority = 1

local FALLBACK = "models/props_junk/gascan001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Holders")
    self:NetworkVar("Bool", 0, "Carried")
    self:NetworkVar("Int", 1, "Hits")
end

function ENT:IsHeavy() return false end

if SERVER then
    function ENT:Initialize()
        local L = Rhylib.Logistics
        local m = L and L.Cfg("fuelModel") or FALLBACK
        if not (isstring(m) and (util.IsValidModel(m) or file.Exists(m, "GAME"))) then m = FALLBACK end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetMaxHealth(100)
        self:SetHealth(100)   -- (droids skip things at 0 health; the hits count is what sets it off)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if L and L.carriables then L.carriables[self] = true end
        self.rhylibHome = self:GetPos()
        timer.Simple(0, function() if IsValid(self) and not self:GetCarried() then self.rhylibHome = self:GetPos() end end)
        local D = Rhylib.Droids
        if D and D.AddObjectTarget then D.AddObjectTarget(self) end
    end

    -- Droids only aim at it with a player or clone close by (checked twice a second).
    function ENT:DroidTargetable()
        if self:GetCarried() or self.boom then return false end
        local now = CurTime()
        if now < (self.nearAt or 0) then return self.nearOk end
        self.nearAt = now + 0.5
        local L, D = Rhylib.Logistics, Rhylib.Droids
        local r2 = (L and L.Cfg("fuelNear") or 420) ^ 2
        local pos = self:GetPos()
        local ok = false
        for _, p in ipairs(D and D.Targets and D.Targets() or {}) do
            if IsValid(p) and p:GetPos():DistToSqr(pos) < r2 then ok = true break end
        end
        if not ok and D and D.clones then
            for c in pairs(D.clones) do
                if IsValid(c) and c:Health() > 0 and c:GetPos():DistToSqr(pos) < r2 then ok = true break end
            end
        end
        self.nearOk = ok
        return ok
    end

    function ENT:OnTakeDamage(dmg)
        if self.boom or dmg:GetDamage() <= 0 then return end
        local L = Rhylib.Logistics
        local att = dmg:GetAttacker()
        if dmg:IsDamageType(DMG_BLAST) or dmg:IsDamageType(DMG_BURN) or dmg:IsExplosionDamage() then
            -- (caught in a blast: goes off a moment later, so chains ripple)
            self:GoOff(att, math.Rand(0.12, 0.35))
            return
        end
        -- (only shots count: bolts, bullets, a melee hit; not knocks or falls)
        if not (dmg:IsBulletDamage() or dmg:IsDamageType(DMG_ENERGYBEAM) or dmg:IsDamageType(DMG_CLUB) or dmg:IsDamageType(DMG_SLASH)) then return end
        local hits = self:GetHits() + 1
        self:SetHits(hits)
        self:EmitSound("physics/metal/metal_canister_impact_hard" .. math.random(1, 3) .. ".wav", 70, 110)
        if hits >= math.max(1, (L and L.Cfg("fuelHits") or 3)) then self:GoOff(att, 0) end
    end

    -- ENT:GoOff(attacker, delay): the blast (once).
    function ENT:GoOff(att, delay)
        if self.boom then return end
        self.boom = true
        local function blow()
            if not IsValid(self) then return end
            local L = Rhylib.Logistics
            local pos = self:WorldSpaceCenter()
            -- (the world as the attacker: the blast hurts everyone near, whoever lit it)
            local who = game.GetWorld()
            -- (carried: whoever holds it lets go first)
            if L and L.carry and L.carry[self] and L.DropCrate then L.DropCrate(self) end
            local fx = EffectData()
            fx:SetOrigin(pos)
            fx:SetScale(1)
            util.Effect("Explosion", fx, true, true)
            self:SetHealth(0)
            util.BlastDamage(self, who, pos, L and L.Cfg("fuelRadius") or 240, L and L.Cfg("fuelDamage") or 110)
            self:Remove()
        end
        if delay and delay > 0 then timer.Simple(delay, blow) else blow() end
    end

    -- (set down: where it is saved when permanent, sv_70_depots.lua)
    function ENT:OnSetDown() self.rhylibHome = self:GetPos() end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer()) or self.boom then return end
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

local WHITE, AMBER, SHADOW = Color(235, 238, 240), Color(255, 180, 90), Color(0, 0, 0, 200)

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    local L = Rhylib.Logistics
    local range = L and L.Cfg and L.Cfg("depotLabelRange") or 790
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > (range * 0.45) ^ 2 then return end
    local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 8)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local f = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(20, 700) or "DermaDefaultBold"
    local f2 = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(16, 600) or "DermaDefault"
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("FUEL CANISTER", f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined(self:GetCarried() and "Set it down in a supply depot" or "Explosive · E to carry", f2, 0, 22, AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
