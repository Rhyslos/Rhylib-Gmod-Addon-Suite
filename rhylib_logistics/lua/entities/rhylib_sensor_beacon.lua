--[[
    Sensor array beacon (rhylib_logistics): set down from a sensor kit
    (weapons/rhylib_sensor_kit.lua), or by staff with the toolgun (Base >
    Sensor array beacon: ENT:StaffPlaced, full power, no owner), not from
    the spawn menu. Senses droids
    within logistics sensorRadius and alerts field technicians and officers
    (rhylib/logistics/sv_10_sensors.lua).

    E (the interaction wheel with rhylib_menus): Put in a power cell (one
    from your inventory: a full cell = sensorPower seconds), or Pick up
    (back into your inventory as a sensor kit; the cell left in it is
    lost; only whoever set it down, field technicians and officers). Without
    the wheel E puts in a cell if you carry one and it's below 90%, else
    picks it up. It breaks after sensorHealth damage, and goes when whoever
    set it down leaves the server.

    Networked (public: nothing about enemies): DT Float PowerEnd (CurTime
    it runs dry, 0 = no cell), Bool Jammed (inside an active comms
    jammer), String Label ("Sensor 3"). The enemy count only goes to field
    technicians and officers (net logi.alert). Client: a small light that
    blinks green while running, red while jammed, nothing when dry; field
    technicians, officers and staff holding the toolgun see its range
    (sensorRadius) as a green ring on the ground (dim with no power).
    Model sensorModel at sensorScale (collision box scaled to match).
    Sent to everyone (TRANSMIT_ALWAYS: a few entities) so every player's
    compass radar shows it as a blue radar mark (cl_10_sensors.lua,
    L.beaconEnts).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Sensor array beacon"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.RhylibWheel = true   -- (E opens its own wheel, rhylib_menus)

local MODEL = "models/props_lab/reciever01b.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "PowerEnd")
    self:NetworkVar("Bool", 0, "Jammed")
    self:NetworkVar("String", 0, "Label")
end

function ENT:Powered()
    return self:GetPowerEnd() > CurTime()
end

if SERVER then
    function ENT:Initialize()
        local L = Rhylib.Logistics
        local m = L and L.Cfg("sensorModel") or MODEL
        if not (isstring(m) and util.IsValidModel(m)) then m = MODEL end
        self:SetModel(m)
        -- (scaled: the physics model doesn't scale with it, so a box of the scaled size)
        local sc = math.Clamp(tonumber(L and L.Cfg("sensorScale")) or 1, 0.05, 4)
        if sc ~= 1 then
            self:SetModelScale(sc, 0)
            local mn, mx = self:GetModelBounds()
            self:PhysicsInitBox(mn * sc, mx * sc)
            self:SetCollisionBounds(mn * sc, mx * sc)
        else
            self:PhysicsInit(SOLID_VPHYSICS)
        end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self.hp = L and math.max(1, tonumber(L.Cfg("sensorHealth")) or 1) or 150
        if L and L.AddBeacon then L.AddBeacon(self) end
    end

    -- Placed with the toolgun (staff): labelled and running on a full
    -- cell, with no owner (not in anyone's limit, stays when they leave).
    function ENT:UpdateTransmitState()
        return TRANSMIT_ALWAYS
    end

    function ENT:StaffPlaced(ply)
        local L = Rhylib.Logistics
        if L and L.StaffBeacon then L.StaffBeacon(ply, self) end
    end

    function ENT:OnRemove()
        local L = Rhylib.Logistics
        if L and L.RemoveBeacon then L.RemoveBeacon(self) end
    end

    function ENT:OnTakeDamage(dmg)
        if self.broken then return end
        self.hp = self.hp - dmg:GetDamage()
        if self.hp <= 0 then
            self.broken = true
            local ed = EffectData()
            ed:SetOrigin(self:WorldSpaceCenter())
            util.Effect("cball_explode", ed, true, true)
            self:EmitSound("physics/metal/metal_box_break1.wav", 70)
            self:Remove()
        end
    end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        local L = Rhylib.Logistics
        if L and L.BeaconUse then L.BeaconUse(ply, self) end
    end
    return
end

-- Client: the blinking light and the range ring.
local GLOW = Material("sprites/light_glow02_add")
local RING = Material("effects/select_ring")
local GREEN, RED = Color(80, 255, 120), Color(255, 70, 50)

-- Does this player see range rings? Field technicians and officers
-- (L.Access), or staff holding the toolgun. Checked once a second.
local seeAt, sees = 0, false
local function seesRings()
    local now = CurTime()
    if now < seeAt then return sees end
    seeAt = now + 1
    local me = LocalPlayer()
    local L = Rhylib.Logistics
    if not IsValid(me) then sees = false return sees end
    local w = me:GetActiveWeapon()
    sees = (me:IsAdmin() and IsValid(w) and w:GetClass() == "rhylib_toolgun")
        or (L and L.Access and L.Access(me, false) >= L.ACCESS_TECH) or false
    return sees
end

function ENT:Initialize()
    -- (the compass radar's list, cl_10_sensors.lua)
    local L = Rhylib.Logistics
    if L then
        L.beaconEnts = L.beaconEnts or {}
        L.beaconEnts[self] = true
    end
    -- (the ring is wider than the model: don't cull it when the model is off screen)
    local r = Rhylib.Logistics and Rhylib.Logistics.Cfg("sensorRadius") or 1800
    self:SetRenderBounds(Vector(-r, -r, -16), Vector(r, r, self:OBBMaxs().z + 32))
end

function ENT:OnRemove()
    local L = Rhylib.Logistics
    if L and L.beaconEnts then L.beaconEnts[self] = nil end
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    if seesRings() then
        local L = Rhylib.Logistics
        local r = math.max(100, L and L.Cfg("sensorRadius") or 1800)
        local on = self:Powered()
        local c = self:GetJammed() and RED or GREEN
        render.SetMaterial(RING)
        render.DrawQuadEasy(self:GetPos() + Vector(0, 0, 4), Vector(0, 0, 1), r * 2, r * 2, Color(c.r, c.g, c.b, on and 60 or 22), 0)
    end
    if not self:Powered() then return end
    local jam = self:GetJammed()
    local t = CurTime() * (jam and 4 or 1.5) + self:EntIndex()
    if t % 1 > 0.25 then return end
    render.SetMaterial(GLOW)
    local pos = self:GetPos() + self:GetUp() * (self:OBBMaxs().z + 2)
    render.DrawSprite(pos, 14, 14, jam and RED or GREEN)
end
