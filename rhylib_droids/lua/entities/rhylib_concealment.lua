--[[
    Concealment area (rhylib_droids stealth): a round patch that counts as
    foliage for unaware droids (sv_55_foliage.lua), for maps whose bushes
    are brushes or detail sprites the map file doesn't list as props.
    Placed with the toolgun (Base: "Concealment area (foliage)", three
    sizes), made permanent with the Permanent tool (Rhylib.Perma.Placements
    "droids_conceal", Data "droids_conceal"/<map>, row field r = radius).

    Invisible and not solid. Staff holding the toolgun see it as a green
    ring with a faint fill. RMB with the toolgun near its centre removes it.

    Shared entity. Set e.ConcealRadius before Spawn (units, 32-1024;
    default 128); DT Int Radius carries it to clients.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Concealment area"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.IsRhylibConcealment = true
-- (an invisible helper: the toolgun's spawn window shows this as its picture)
ENT.PreviewModel = "models/hunter/blocks/cube025x025x025.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Radius")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self.PreviewModel)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:DrawShadow(false)
        self:SetRadius(math.Clamp(math.floor(tonumber(self.ConcealRadius) or 128), 32, 1024))
        local D = Rhylib.Droids
        if D and D.conceal then
            D.conceal[self] = true
            if D.Foliage then D.Foliage.dirty = true end
        end
    end

    function ENT:OnRemove()
        local D = Rhylib.Droids
        if D and D.conceal then D.conceal[self] = nil end
        if D and D.Foliage then D.Foliage.dirty = true end
    end
end

if CLIENT then
    local GREEN = Color(151, 196, 89)
    local FILL = Color(151, 196, 89, 26)
    local RING = Material("effects/select_ring")
    local mins, maxs = Vector(), Vector()

    function ENT:Draw() end

    function ENT:Think()
        local r = self:GetRadius()
        if r ~= self.boundsR then
            self.boundsR = r
            mins:SetUnpacked(-r, -r, -8)
            maxs:SetUnpacked(r, r, 96)
            self:SetRenderBounds(mins, maxs)
        end
    end

    function ENT:DrawTranslucent()
        local me = LocalPlayer()
        local w = IsValid(me) and me:GetActiveWeapon()
        if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then return end
        local pos = self:GetPos()
        if pos:DistToSqr(EyePos()) > 4000 * 4000 then return end
        local r = self:GetRadius()
        render.SetMaterial(RING)
        render.DrawQuadEasy(pos + Vector(0, 0, 3), Vector(0, 0, 1), r * 2, r * 2, GREEN, 0)
        render.SetColorMaterial()
        render.DrawSphere(pos, r, 24, 12, FILL)
        local ang = (pos - EyePos()):Angle()
        cam.Start3D2D(pos + Vector(0, 0, 40), Angle(0, ang.y - 90, 90), 0.25)
            draw.SimpleTextOutlined("CONCEALMENT", Rhylib.UI.Font(32, 800), 0, 0, GREEN, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
            draw.SimpleTextOutlined(string.format("%d m  ·  staff only", math.Round(r * 0.019)), Rhylib.UI.Font(20), 0, 30, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        cam.End3D2D()
    end
end
