--[[
    Interference device (rhylib_eod): placed from the inventory item
    (right-click "Place interference device"), runs on a power cell.
    E opens its window: on/off, radius (1-15 m; bigger = the cell lasts
    much shorter), wideband or tuned to one frequency, a scanner showing
    nearby receivers, swap the cell, pick it up.

    Wideband blocks every remote signal and blinds motion sensors in the
    circle, and also jams your own side's radio and compass there
    (rhylib_radio, via ENT:JamRange). Tuned blocks one frequency only,
    lasts 4× longer and leaves the radio alone; a hopping receiver gets
    away from it.

    Cell: a line (Cell at CellAt, draining at Rate per second while on),
    so nothing is networked while it runs.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Interference device"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Model = "models/props_lab/reciever01a.mdl"
ENT.ModelFromConfig = true   -- (eod modelDevice)

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Tuned")
    self:NetworkVar("Int", 0, "Radius")
    self:NetworkVar("Float", 0, "Dial")
    self:NetworkVar("Float", 1, "Cell")
    self:NetworkVar("Float", 2, "CellAt")
    self:NetworkVar("Float", 3, "Rate")
end

function ENT:Fill()
    local f = self:GetCell()
    if self:GetActive() then f = f - (CurTime() - self:GetCellAt()) * self:GetRate() end
    return math.Clamp(f, 0, 1)
end

-- Radio jamming range (rhylib_radio R.JammerRange): wideband only.
function ENT:JamRange()
    if self:GetActive() and not self:GetTuned() and self:Fill() > 0 then
        return self:GetRadius() * (Rhylib.EOD and Rhylib.EOD.UNITS_PER_M or 52.5)
    end
    return 0
end

if SERVER then
    function ENT:Initialize()
        local E = Rhylib.EOD
        local mdl = E and E.Cfg("modelDevice")
        if not (isstring(mdl) and util.IsValidModel(mdl)) then mdl = self.Model end
        self:SetModel(mdl)
        self:PhysicsInit(SOLID_VPHYSICS)
        if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local ph = self:GetPhysicsObject()
        if IsValid(ph) then ph:EnableMotion(false) end
        self:SetRadius(5)
        self:SetDial(2440)
        self:SetCell(1)
        self:SetCellAt(CurTime())
        self:SetActive(false)
        self.viewers = {}
        if E then E.devices[self] = true end
        local R = Rhylib.Radio
        if R and R.jammers then R.jammers[self] = true end
    end

    function ENT:Use(ply)
        if IsValid(ply) and ply:IsPlayer() and Rhylib.EOD then Rhylib.EOD.OpenDevice(ply, self) end
    end

    function ENT:OnRemove()
        local E = Rhylib.EOD
        if E then E.devices[self] = nil end
        local R = Rhylib.Radio
        if R and R.jammers then R.jammers[self] = nil end
    end
end

if CLIENT then
    local RING = Material("sprites/light_glow02_add")

    function ENT:Draw()
        self:DrawModel()
    end

    -- Ground ring (orange wideband, cyan tuned) and a status light.
    function ENT:DrawTranslucent()
        local pos = self:GetPos()
        local eye = EyePos()
        if eye:DistToSqr(pos) > 4000 * 4000 then return end
        local on = self:GetActive() and self:Fill() > 0
        local col = not on and Color(120, 40, 40) or self:GetTuned() and Color(80, 200, 255) or Color(255, 150, 40)
        render.SetMaterial(RING)
        local top = self:LocalToWorld(Vector(0, 0, self:OBBMaxs().z + 2))
        render.DrawSprite(top, 10, 10, (on and CurTime() % 1 < 0.5) and col or Color(col.r * 0.4, col.g * 0.4, col.b * 0.4))
        if not on then return end
        local r = self:GetRadius() * (Rhylib.EOD and Rhylib.EOD.UNITS_PER_M or 52.5)
        local seg, prev = 48, nil
        local z = pos.z + 3
        for i = 0, seg do
            local a = i / seg * math.pi * 2
            local p = Vector(pos.x + math.cos(a) * r, pos.y + math.sin(a) * r, z)
            if prev then render.DrawLine(prev, p, col, true) end
            prev = p
        end
    end
end
