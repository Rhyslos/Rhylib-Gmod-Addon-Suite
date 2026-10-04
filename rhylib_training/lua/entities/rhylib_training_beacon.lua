--[[
    Training respawn beacon (rhylib_training): eliminated players pick one
    of these to come back at. Its name shows in the list. Place with the
    toolgun; rhylib_training_save keeps them on the map.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Training respawn beacon"
ENT.Category = "Rhylib"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "BeaconName")
end

function ENT:Initialize()
    if CLIENT then return end
    local T = Rhylib.Training
    self:SetModel(T and T.Cfg("beaconModel") or "models/props_combine/combine_mine01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)   -- (players stand on the spot)
    self:SetColor(Color(255, 210, 80))
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    if self:GetBeaconName() == "" then self:SetBeaconName("Beacon") end
end

-- Where a player comes back: on top of it.
function ENT:SpawnPos()
    return self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 2)
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local RING = Material("effects/select_ring")
    local COL = Color(255, 210, 70)
    local COL_TEXT = Color(255, 236, 180)

    function ENT:DrawTranslucent()
        local pos = self:GetPos() + Vector(0, 0, 4)
        local pulse = 0.75 + 0.25 * math.sin(CurTime() * 3)
        render.SetMaterial(RING)
        render.DrawQuadEasy(pos, Vector(0, 0, 1), 60 * pulse, 60 * pulse, Color(COL.r, COL.g, COL.b, 160), 0)
        render.SetMaterial(GLOW)
        render.DrawSprite(pos + Vector(0, 0, 6), 24, 24, Color(COL.r, COL.g, COL.b, 200 * pulse))
        local ply = LocalPlayer()
        if ply:GetPos():DistToSqr(pos) < 400 * 400 then
            local ang = Angle(0, ply:EyeAngles().y - 90, 90)
            cam.Start3D2D(pos + Vector(0, 0, 40), ang, 0.1)
                draw.SimpleTextOutlined(self:GetBeaconName(), Rhylib.UI.Font(30, 700), 0, 0, COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
                draw.SimpleText("TRAINING RESPAWN", Rhylib.UI.Font(18, 700), 0, 26, COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cam.End3D2D()
        end
    end

    function ENT:Draw()
        self:DrawModel()
    end
end
