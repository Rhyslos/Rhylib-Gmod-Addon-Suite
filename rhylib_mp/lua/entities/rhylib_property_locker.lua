--[[
    Property locker: processed prisoners press E to collect what was taken
    from them in jail (rhylib_mp sv_40_property). Placed by admins and
    saved with the jail (rhylib_mp_save); processed prisoners appear in
    front of it.

    Shared entity, frozen in place. Model: config mp propertyModel
    (HL2 lockers if missing). The storage itself is made on first use
    (sv_40_property). Clients see a "PROPERTY" label within 300 units.
]]


AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Property locker"
ENT.Category = "Rhylib: Military police"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:Initialize()
    if SERVER then
        local m = Rhylib.Config.Get("mp", "propertyModel")
        if not (isstring(m) and util.IsValidModel(m)) then m = "models/props_c17/lockers001a.mdl" end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos)
        e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        e:Spawn()
        return e
    end

    function ENT:Use(ply)
        if IsValid(ply) and ply:IsPlayer() and Rhylib.MP and Rhylib.MP.OpenProperty then Rhylib.MP.OpenProperty(ply, self) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local pos = self:WorldSpaceCenter() + Vector(0, 0, self:OBBMaxs().z - self:OBBCenter().z + 8)
        if LocalPlayer():GetPos():DistToSqr(pos) > 300 * 300 then return end
        local ang = Angle(0, LocalPlayer():EyeAngles().y - 90, 90)
        cam.Start3D2D(pos, ang, 0.08)
            draw.SimpleTextOutlined("PROPERTY", Rhylib.UI.Font(48, 700), 0, 0, Color(239, 159, 39), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 200))
        cam.End3D2D()
    end
end
