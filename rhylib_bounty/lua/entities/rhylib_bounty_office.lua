--[[
    Bounty Office (rhylib_bounty): a standing agent. E opens the office
    window (Board, Post, Turn in, Gear; cl_10_office.lua). Staff place it
    with the toolgun (Bounty) and keep it with the Permanent tool; saved
    per map by the bounty addon (Data "bounty_places"/map).
    Model: config bounty officeModel (Server settings > Model overrides).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Bounty Office"
ENT.Category = "Rhy's Bounty hunters"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ModelFromConfig = true
ENT.AutomaticFrameAdvance = true

function ENT:WantedModel()
    local m = Rhylib.Config.Get("bounty", "officeModel")
    if isstring(m) and (util.IsValidModel(m) or (CLIENT and file.Exists(m, "GAME"))) then return m end
    return "models/Humans/Group02/male_02.mdl"
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self:WantedModel())
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 72))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetUseType(SIMPLE_USE)
        local seq = self:LookupSequence("idle_subtle")
        if not seq or seq < 0 then seq = self:LookupSequence("idle_all_01") end
        if not seq or seq < 0 then seq = self:LookupSequence("idle01") end
        if seq and seq >= 0 then self:ResetSequence(seq) end
    end

    function ENT:Use(ply)
        if IsValid(ply) and ply:IsPlayer() and Rhylib.Bounty and Rhylib.Bounty.Open then Rhylib.Bounty.Open(ply, self) end
    end

    function ENT:Think()
        self:NextThink(CurTime())
        return true
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local me = LocalPlayer()
        if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 600 * 600 then return end
        local pos = self:GetPos() + Vector(0, 0, 84)
        local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
        cam.Start3D2D(pos, ang, 0.1)
            draw.SimpleTextOutlined("BOUNTY OFFICE", Rhylib.UI.Font(48, 800), 0, 0, Color(230, 190, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
            draw.SimpleTextOutlined("Press E", Rhylib.UI.Font(30, 500), 0, 44, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
        cam.End3D2D()
    end
end
