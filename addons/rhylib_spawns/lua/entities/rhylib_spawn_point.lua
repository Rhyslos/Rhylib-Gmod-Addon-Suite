--[[
    Spawn point (rhylib_spawns): a named respawn spot for one battalion
    ("" = everyone). rhylib_event_spawn is the same with ENT.Event.
    Shared entity. Frozen, players walk through it (COLLISION_GROUP_WEAPON).
    Model: config spawns "model". E (Use) opens the staff edit menu
    (S.OpenEdit checks the permission). The ring and name are drawn within
    600 / 400 units.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Spawn point"
ENT.Category = "Rhylib: Spawn points"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Event = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "BeaconName")   -- (the toolgun names it through this)
    self:NetworkVar("String", 1, "Battalion")
    self:NetworkVar("Bool", 0, "Active")         -- (event spawns: switched on)
end

function ENT:Initialize()
    if CLIENT then return end
    self:SetModel(Rhylib.Config.Get("spawns", "model"))
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)   -- (players stand on the spot)
    self:SetUseType(SIMPLE_USE)
    self:SetColor(self.Event and Color(255, 190, 80) or Color(120, 190, 255))
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    if self:GetBeaconName() == "" then self:SetBeaconName(self.Event and "Event" or "Spawn") end
end

-- ENT:SpawnPos(): where a player appears: on top of it.
function ENT:SpawnPos()
    return self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 2)
end

if SERVER then
    function ENT:Use(ply)
        local S = Rhylib.Spawns
        if S and S.OpenEdit then S.OpenEdit(ply, self) end
    end
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local RING = Material("effects/select_ring")
    local COL_POINT, COL_EVENT = Color(120, 190, 255), Color(255, 190, 80)
    local COL_TEXT = Color(230, 236, 245)

    function ENT:DrawTranslucent()
        local ply = LocalPlayer()
        local pos = self:GetPos() + Vector(0, 0, 4)
        if ply:GetPos():DistToSqr(pos) > 600 * 600 then return end
        local col = self.Event and COL_EVENT or COL_POINT
        local on = not self.Event or self:GetActive()
        local pulse = on and (0.75 + 0.25 * math.sin(CurTime() * 3)) or 0.5
        render.SetMaterial(RING)
        render.DrawQuadEasy(pos, Vector(0, 0, 1), 60 * pulse, 60 * pulse, Color(col.r, col.g, col.b, on and 160 or 60), 0)
        render.SetMaterial(GLOW)
        render.DrawSprite(pos + Vector(0, 0, 6), 24, 24, Color(col.r, col.g, col.b, (on and 200 or 70) * pulse))
        if ply:GetPos():DistToSqr(pos) < 400 * 400 then
            local ang = Angle(0, ply:EyeAngles().y - 90, 90)
            local sub
            if self.Event then
                sub = self:GetActive() and "EVENT SPAWN · ON" or "EVENT SPAWN · OFF"
            else
                sub = self:GetBattalion() ~= "" and string.upper(self:GetBattalion()) or "SPAWN · EVERYONE"
            end
            cam.Start3D2D(pos + Vector(0, 0, 40), ang, 0.1)
                draw.SimpleTextOutlined(self:GetBeaconName(), Rhylib.UI.Font(30, 700), 0, 0, COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
                draw.SimpleText(sub, Rhylib.UI.Font(18, 700), 0, 26, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end

    function ENT:Draw()
        self:DrawModel()
    end
end
