--[[
    Intel datapad (entity, shared): a game master places it (toolgun Base,
    or the spawn menu) and writes its intel with E while holding the
    toolgun (rhylib.datapad.intel). Field technicians press E to crack it
    (three signal locks); then whoever may read it sees the intel.
    E runs Rhylib.Datapad.IntelUse (sv_95_intel.lua). Make it permanent
    with the toolgun's Permanent tool to keep it (and its intel) after a
    map change. Model: Rhylib.Datapad.MODELS.intel (Server settings >
    Models). NW2 rhylib_intelCracked (bool) for the label.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Intel datapad"
ENT.Category = "Rhy's Terminals"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

local FALLBACK = "models/props_lab/reciever01b.mdl"

function ENT:Initialize()
    if CLIENT then return end
    local D = Rhylib.Datapad
    local m = D and D.MODELS and D.MODELS.intel or FALLBACK
    if not (isstring(m) and util.IsValidModel(m)) then m = FALLBACK end
    self:SetModel(m)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    -- (what the game master writes; sv_95_intel.lua)
    self.intel = self.intel or { title = "", text = "", onlyCracker = false, cracked = false }
end

if SERVER then
    function ENT:Use(ply)
        local D = Rhylib.Datapad
        if IsValid(ply) and ply:IsPlayer() and D and D.IntelUse then D.IntelUse(ply, self) end
    end
    return
end

local WHITE, AMBER, GREEN, SHADOW = Color(235, 238, 240), Color(239, 159, 39), Color(151, 196, 89), Color(0, 0, 0, 200)

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not IsValid(me) or me:GetPos():DistToSqr(self:GetPos()) > 300 * 300 then return end
    local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 8)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local UI = Rhylib.UI
    local f = UI and UI.Font and UI.Font(22, 700) or "DermaLarge"
    local f2 = UI and UI.Font and UI.Font(16, 600) or "DermaDefaultBold"
    local cracked = self:GetNW2Bool("rhylib_intelCracked", false)
    cam.Start3D2D(pos, ang, 0.1)
        draw.SimpleTextOutlined("INTEL DATAPAD", f, 0, 0, WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
        draw.SimpleTextOutlined(cracked and "Cracked · Press E" or "Encrypted · Press E", f2, 0, 22, cracked and GREEN or AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, SHADOW)
    cam.End3D2D()
end
