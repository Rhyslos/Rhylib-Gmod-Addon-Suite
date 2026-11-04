--[[
    Command post (rhylib_logistics; admins: spawn menu "Rhy's Logistics" or
    the toolgun's Base list). The FOB's computer: E opens its window
    (rhylib/logistics/sv_20_post.lua, cl_20_post.lua). Make it permanent
    with the toolgun's Permanent tool to keep it on the map (Data
    "logistics_places", console rhylib_logistics_save). Model: logistics
    postModel (ENT.ModelKey; the field variant,
    entities/rhylib_command_post_field.lua, uses postFieldModel). Can't be hurt.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Command post"
ENT.Category = "Rhy's Logistics"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.ModelKey = "postModel"
ENT.IsRhylibCommandPost = true

local FALLBACK = "models/props_lab/monitor01b.mdl"

if SERVER then
    function ENT:Initialize()
        local L = Rhylib.Logistics
        local m = L and L.Cfg(self.ModelKey) or FALLBACK
        if not (isstring(m) and util.IsValidModel(m)) then m = FALLBACK end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:OnTakeDamage() end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return end
        local L = Rhylib.Logistics
        if L and L.OpenPost then L.OpenPost(ply, self) end
    end
    return
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end
    local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 12)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local f = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(24, 700) or "DermaLarge"
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("Command post", f, 0, 0, Color(235, 238, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined("Press E", f, 0, 28, Color(120, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
    cam.End3D2D()
end
