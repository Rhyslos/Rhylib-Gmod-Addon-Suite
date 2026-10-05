--[[
    Droid order marker (rhylib_droids sv_20_orders): attack here, defend
    this, fall back here. Placed with the toolgun; only admins see it.
    Not solid (bolts fly through it); the toolgun's RMB removes it when
    aimed near it. Not saved: markers last until removed or a map change.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Droid order marker"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.IsDroidMarker = true

local KINDS = { "attack", "defend", "fallback" }
local LABELS = { "ATTACK HERE", "DEFEND THIS", "FALL BACK HERE" }
local COLS = { Color(235, 70, 60), Color(70, 150, 255), Color(255, 200, 60) }

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Kind")
end

function ENT:KindName() return KINDS[self:GetKind()] or "attack" end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:DrawShadow(false)
        local k = self.MarkerKind or self:GetKind()
        if not KINDS[k] then k = 1 end
        self:SetKind(k)
        -- (after the toolgun has set the position)
        timer.Simple(0, function()
            if IsValid(self) and Rhylib.Droids and Rhylib.Droids.MarkerPlaced then Rhylib.Droids.MarkerPlaced(self, KINDS[k]) end
        end)
    end

    function ENT:OnRemove()
        if Rhylib.Droids and Rhylib.Droids.MarkerRemoved then Rhylib.Droids.MarkerRemoved(self) end
    end
end

if CLIENT then
    local RING = Material("effects/select_ring")
    local GLOW = Material("sprites/light_glow02_add")

    -- (admins only: players never see where droids are sent)
    local function canSee()
        local me = LocalPlayer()
        return IsValid(me) and me:IsAdmin()
    end

    function ENT:Draw() end

    function ENT:DrawTranslucent()
        if not canSee() then return end
        local k = self:GetKind()
        local col = COLS[k] or COLS[1]
        local pos = self:GetPos()
        local pulse = 0.75 + 0.25 * math.sin(CurTime() * 4)
        render.SetMaterial(RING)
        render.DrawQuadEasy(pos + Vector(0, 0, 2), Vector(0, 0, 1), 90 * pulse + 30, 90 * pulse + 30, col, 0)
        render.SetMaterial(GLOW)
        render.DrawSprite(pos + Vector(0, 0, 40), 40, 40, col)
        -- With the toolgun out: the range droids follow it from.
        local w = LocalPlayer():GetActiveWeapon()
        if IsValid(w) and w:GetClass() == "rhylib_toolgun" then
            local r = Rhylib.Droids.Cfg("markerRadius") or 2000
            render.SetMaterial(RING)
            render.DrawQuadEasy(pos + Vector(0, 0, 3), Vector(0, 0, 1), r * 2, r * 2, ColorAlpha(col, 60), 0)
        end
        local ang = (pos - EyePos()):Angle()
        ang = Angle(0, ang.y - 90, 90)
        cam.Start3D2D(pos + Vector(0, 0, 70), ang, 0.25)
            draw.SimpleTextOutlined(LABELS[k] or "", Rhylib.UI.Font(40, 800), 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
            draw.SimpleTextOutlined("staff only", Rhylib.UI.Font(22), 0, 34, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        cam.End3D2D()
    end
end
