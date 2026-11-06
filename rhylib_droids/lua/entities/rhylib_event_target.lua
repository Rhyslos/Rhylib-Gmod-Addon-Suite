--[[
    Event target (staff; toolgun Spawns > Event target, or spawn menu
    "Rhy's Spawn points"): any prop model the game master picks, at a
    size, with its own health, that droids go after like a trooper
    (rhylib_droids D.DroidTargets, a little less eagerly: etPriority).
    Only droids can damage it (their bolts, grenades, shells, rockets,
    also those of a droid that died meanwhile: rhylibDroidShot). At 0 it
    breaks apart (smoke, sparks, gibs) or, set to explode, blows up with
    a blast of its radius (etBlastDamage, hurting everyone near), tells
    everyone "Objective lost" (net droids.etlost) and is removed.

    Settings: the toolgun's right-click on its tile for the next ones
    (sent with tool.place), or E on a placed one with the toolgun out
    (sv_70_targets.lua, nets droids.etedit / droids.etset). Permanent
    with the Permanent tool (Placements "droids_targets").

    Networked: Name, Model is the entity's own, Scale, HP, HPMax,
    Explosive, Radius (units), HitAt (CurTime of the last droid hit,
    written at most twice a second). Sent to every client
    (TRANSMIT_ALWAYS): the HUD marker shows it from anywhere
    (cl_70_targets.lua).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Event target"
ENT.Category = "Rhy's Spawn points"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.rhylibEventTarget = true
ENT.rhylibObjTarget = true   -- (droids shoot it: D.objTargets)

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "TargetName")
    self:NetworkVar("Int", 0, "HP")
    self:NetworkVar("Int", 1, "HPMax")
    self:NetworkVar("Bool", 0, "Explosive")
    self:NetworkVar("Float", 0, "Radius")
    self:NetworkVar("Float", 1, "Scale")
    self:NetworkVar("Float", 2, "HitAt")
end

function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end

local function D() return Rhylib.Droids end

function ENT:Initialize()
    local Dr = D()
    if Dr then
        Dr.eventTargets = Dr.eventTargets or {}
        Dr.eventTargets[self] = true
        if Dr.objTargets then Dr.objTargets[self] = true end
    end
    if CLIENT then return end
    local cfg = Dr and Dr.Cfg or function(k) return Rhylib.Config.Get("droids", k) end
    self:SetUseType(SIMPLE_USE)
    if self:GetTargetName() == "" then
        self:ApplyConfig({ name = cfg("etName"), model = cfg("etModel"), scale = cfg("etScale"), health = cfg("etHealth"),
            explode = cfg("etExplode"), radius = cfg("etRadius") })
    end
end

function ENT:OnRemove(fullUpdate)
    if fullUpdate then return end
    local Dr = D()
    if Dr and Dr.eventTargets then Dr.eventTargets[self] = nil end
    if Dr and Dr.objTargets then Dr.objTargets[self] = nil end
end

if SERVER then
    local FALLBACK = "models/props_junk/wood_crate002a.mdl"

    -- A model the server can use: a .mdl that exists, else the fallback.
    local function okModel(m)
        if not isstring(m) or not string.EndsWith(string.lower(m), ".mdl") then return FALLBACK end
        if util.IsValidModel(m) or file.Exists(m, "GAME") then return m end
        return FALLBACK
    end

    -- ENT:ApplyConfig(c): name, model, scale (0.5-3), health (1-100000),
    -- explode, radius (units, 16-2000). Keeps its bottom where it was.
    -- Health starts full (also on a placed one: Apply repairs it).
    -- keepPos: stay exactly where it is (a saved one loading).
    function ENT:ApplyConfig(c, keepPos)
        c = c or {}
        local at = keepPos and self:GetPos() or nil
        local hadModel = self:GetModel() ~= nil and self:GetModel() ~= ""
        local bottom = hadModel and (self:GetPos().z + self:OBBMins().z) or nil
        local name = string.Trim(string.sub(tostring(c.name or ""), 1, 32))
        self:SetTargetName(name ~= "" and name or "Target")
        local scale = math.Clamp(tonumber(c.scale) or 1, 0.5, 3)
        self:SetScale(scale)
        local hp = math.Clamp(math.floor(tonumber(c.health) or 800), 1, 100000)
        self:SetHPMax(hp)
        self:SetHP(hp)
        -- (the engine's health too: droid code reads Health(); the HUD the NetworkVars)
        self:SetMaxHealth(hp)
        self:SetHealth(hp)
        self:SetExplosive(c.explode and true or false)
        self:SetRadius(math.Clamp(tonumber(c.radius) or 300, 16, 2000))
        self:SetModel(okModel(c.model))
        self:SetModelScale(scale, 0)
        -- Physics: the model's own at 1x; a box of its scaled bounds
        -- otherwise (SOLID_BBOX, so bolts and sight traces use that box).
        if scale == 1 then
            self:EnableCustomCollisions(false)
            self:PhysicsInit(SOLID_VPHYSICS)
            self:SetSolid(SOLID_VPHYSICS)
        else
            local mn, mx = self:GetModelBounds()
            self:PhysicsInitBox(mn * scale, mx * scale)
            self:SetCollisionBounds(mn * scale, mx * scale)
            self:SetSolid(SOLID_BBOX)
        end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if at then
            self:SetPos(at)
        elseif bottom then
            local p = self:GetPos()
            self:SetPos(Vector(p.x, p.y, bottom - self:OBBMins().z))
        end
        self:PrecacheGibs()
    end

    -- ENT:Config() -> the table ApplyConfig takes (saving, the edit window).
    function ENT:Config()
        return { name = self:GetTargetName(), model = self:GetModel(), scale = self:GetScale(), health = self:GetHPMax(),
            explode = self:GetExplosive(), radius = self:GetRadius() }
    end

    -- Only droids hurt it.
    local function fromDroid(dmg)
        local att, inf = dmg:GetAttacker(), dmg:GetInflictor()
        if IsValid(att) and (att.IsRhylibDroid or att.rhylibDroidShot) then return true end
        if IsValid(inf) and (inf.IsRhylibDroid or inf.rhylibDroidShot) then return true end
        return false
    end

    function ENT:OnTakeDamage(dmg)
        if self.broken or not fromDroid(dmg) then return end
        local d = math.max(0, math.floor(dmg:GetDamage() + 0.5))
        if d <= 0 then return end
        local hp = self:GetHP() - d
        local now = CurTime()
        if now - self:GetHitAt() > 0.5 then self:SetHitAt(now) end
        if hp > 0 then
            self:SetHP(hp)
            self:SetHealth(hp)
            return
        end
        self:SetHP(0)
        self:SetHealth(0)
        self:Destroyed(dmg)
    end

    -- At 0: blast or break apart, tell everyone, gone.
    function ENT:Destroyed(dmg)
        if self.broken then return end
        self.broken = true
        local pos = self:WorldSpaceCenter()
        local Dr = D()
        if self:GetExplosive() then
            local fx = EffectData()
            fx:SetOrigin(pos)
            fx:SetScale(1)
            util.Effect("Explosion", fx, true, true)
            local dmgAmt = Dr and Dr.Cfg("etBlastDamage") or 120
            -- (the world as attacker: droids hit by it don't take the crate for a foe)
            util.BlastDamage(self, game.GetWorld(), pos, self:GetRadius(), dmgAmt)
        else
            local fx = EffectData()
            fx:SetOrigin(pos)
            fx:SetMagnitude(2)
            fx:SetScale(1)
            fx:SetRadius(8)
            util.Effect("Sparks", fx, true, true)
            util.Effect("cball_explode", fx, true, true)
            self:EmitSound("physics/metal/metal_box_break" .. math.random(1, 2) .. ".wav", 85, 90)
        end
        local force = dmg and dmg:GetDamageForce() or Vector(0, 0, 0)
        self:GibBreakClient(force * 0.01 + Vector(0, 0, 50))
        if Dr and Dr.EventTargetLost then Dr.EventTargetLost(self) end
        self:Remove()
    end

    -- E with the toolgun out (staff): this one's settings.
    function ENT:Use(ply)
        local Dr = D()
        if Dr and Dr.OpenEventTarget then Dr.OpenEventTarget(ply, self) end
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
