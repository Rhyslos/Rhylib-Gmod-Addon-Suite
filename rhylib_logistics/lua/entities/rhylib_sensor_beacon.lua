--[[
    Sensor array beacon (rhylib_logistics): set down from a sensor kit
    (weapons/rhylib_sensor_kit.lua), not from the spawn menu. Senses droids
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
    blinks green while running, red while jammed, nothing when dry.
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
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self.hp = L and math.max(1, tonumber(L.Cfg("sensorHealth")) or 1) or 150
        if L and L.AddBeacon then L.AddBeacon(self) end
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

-- Client: the blinking light.
local GLOW = Material("sprites/light_glow02_add")
local GREEN, RED = Color(80, 255, 120), Color(255, 70, 50)

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    if not self:Powered() then return end
    local jam = self:GetJammed()
    local t = CurTime() * (jam and 4 or 1.5) + self:EntIndex()
    if t % 1 > 0.25 then return end
    render.SetMaterial(GLOW)
    local pos = self:GetPos() + self:GetUp() * (self:OBBMaxs().z + 2)
    render.DrawSprite(pos, 14, 14, jam and RED or GREEN)
end
