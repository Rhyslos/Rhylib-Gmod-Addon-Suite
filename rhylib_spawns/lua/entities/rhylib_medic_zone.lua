--[[
    Medic zone (rhylib_spawns event tools, sh_20_events.lua): placed by
    staff with the toolgun (Spawns > Medic zone). A green ring of config
    medicZoneRadius round it: a downed player brought inside gets up at
    full health with no injuries or illness and the respawn ticket pool
    gains one (while tickets are on); anyone standing inside heals
    medicZoneRegen health a second (sv_20_events.lua). Players walk
    through it. Not saved over a map change.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Medic zone"
ENT.Category = "Rhy's Spawn points"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

local COL = Color(90, 230, 120)

function ENT:Initialize()
    local S = Rhylib.Spawns
    if S then
        S.medicZones = S.medicZones or {}
        S.medicZones[self] = true
    end
    if CLIENT then
        -- (the ring is far wider than the model: don't cull it with the model)
        local r = Rhylib.Config.Get("spawns", "medicZoneRadius") + 20
        self:SetRenderBounds(Vector(-r, -r, -10), Vector(r, r, 80))
        return
    end
    self:SetModel(Rhylib.Config.Get("spawns", "medicZoneModel"))
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:SetColor(COL)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
end

function ENT:OnRemove(fullUpdate)
    if fullUpdate then return end
    local S = Rhylib.Spawns
    if S and S.medicZones then S.medicZones[self] = nil end
end

if CLIENT then
    local SEG = 48
    function ENT:Draw() self:DrawModel() end
    -- The ring on the ground (within 2500 units), and a label close by.
    function ENT:DrawTranslucent()
        local me = LocalPlayer()
        local pos = self:GetPos()
        local d2 = me:GetPos():DistToSqr(pos)
        if d2 > 2500 * 2500 then return end
        local r = Rhylib.Config.Get("spawns", "medicZoneRadius")
        render.SetColorMaterial()
        local prev
        for i = 0, SEG do
            local a = i / SEG * math.pi * 2
            local p = pos + Vector(math.cos(a) * r, math.sin(a) * r, 4)
            if prev then render.DrawBeam(prev, p, 3, 0, 1, Color(COL.r, COL.g, COL.b, 170)) end
            prev = p
        end
        if d2 < 500 * 500 then
            local ang = Angle(0, me:EyeAngles().y - 90, 90)
            cam.Start3D2D(pos + Vector(0, 0, 36), ang, 0.1)
                draw.SimpleTextOutlined("MEDIC ZONE", Rhylib.UI.Font(30, 700), 0, 0, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
                draw.SimpleText("Bring the downed here", Rhylib.UI.Font(18, 600), 0, 26, Color(230, 236, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end
end
