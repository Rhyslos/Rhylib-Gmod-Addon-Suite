--[[
    EOD bomb (rhylib_eod): placed by the GM with the toolgun (EOD
    category). E opens the defusal window; with the toolgun out, staff
    (rhylib.eod.gm) get the GM window (re-roll, type, custom, timer,
    remote signal, spotter, detonate, disarm).

    This is the small bomb and the base of the others:
    rhylib_eod_bomb_simple / _large / _custom only change ENT.BombType.
    The rules live in sv_10_bomb.lua / sv_20_world.lua (bomb.eod).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Bomb (small)"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.BombType = "small"
ENT.Model = "models/props/starwars/weapons/seismic_charge.mdl"
ENT.IsRhylibBomb = true
ENT.ModelFromConfig = true   -- (eod modelSmall / modelLarge pick it; ENT.Model is only the toolgun preview)

if SERVER then
    function ENT:Initialize()
        local E = Rhylib.EOD
        local big = self.BombType == "large" or self.BombType == "custom"
        local mdl = E and E.Cfg(big and "modelLarge" or "modelSmall")
        if not (isstring(mdl) and util.IsValidModel(mdl)) then mdl = big and "models/props_lab/powerbox01a.mdl" or "models/props_c17/consolebox01a.mdl" end
        self:SetModel(mdl)
        self:PhysicsInit(SOLID_VPHYSICS)
        if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local ph = self:GetPhysicsObject()
        if IsValid(ph) then ph:EnableMotion(false) end
        if not E then return end
        local f
        if self.BombType == "custom" then
            f = E.Roll("large")
            f.type = "custom"
        elseif self.BombType == "training" then
            f = E.Roll("small")
            f.type = "training"
        else
            f = E.Roll(self.BombType)
        end
        E.SetupBomb(self, f)
    end

    function ENT:Use(ply)
        if IsValid(ply) and ply:IsPlayer() and Rhylib.EOD then Rhylib.EOD.UseBomb(ply, self) end
    end

    function ENT:OnRemove()
        local E = Rhylib.EOD
        if not E then return end
        E.bombs[self] = nil
        local st = self.eod
        if st and not st.over then
            for p in pairs(st.viewers) do if IsValid(p) then E.CloseFor(p, self) end end
        end
    end
end

if CLIENT then
    local DIGITS = "Rhylib.EOD.Digits"
    surface.CreateFont(DIGITS, { font = "Consolas", size = 48, weight = 800, antialias = true })
    local SMALL = "Rhylib.EOD.Small"
    surface.CreateFont(SMALL, { font = "Roboto", size = 22, weight = 600, antialias = true })

    function ENT:Draw()
        self:DrawModel()
    end

    -- Timer readout and status light on top, within 700 units.
    function ENT:DrawTranslucent()
        local pos = self:GetPos()
        if EyePos():DistToSqr(pos) > 700 * 700 then return end
        local top = self:LocalToWorld(Vector((self:OBBMins().x + self:OBBMaxs().x) / 2, (self:OBBMins().y + self:OBBMaxs().y) / 2, self:OBBMaxs().z + 0.3))
        local ang = self:GetAngles()
        ang:RotateAroundAxis(ang:Up(), 90)
        local safe = self:GetNW2Bool("rhylib_eodSafe", false)
        local now = CurTime()
        cam.Start3D2D(top, ang, 0.08)
            local hasTimer = self:GetNW2Bool("rhylib_eodTimer", false)
            local w, h = 220, 70
            draw.RoundedBox(4, -w / 2, -h / 2, w, h, Color(10, 10, 10, 255))
            local txt, col
            if safe then
                txt, col = "SAFE", Color(80, 220, 120)
            elseif hasTimer then
                local endT = self:GetNW2Float("rhylib_eodEnd", 0)
                local left = endT > 0 and math.max(0, endT - now) or self:GetNW2Float("rhylib_eodLeft", 0)
                txt = string.FormattedTime(left, "%02i:%02i")
                if self:GetNW2Bool("rhylib_eodStop", false) then
                    col = Color(90, 40, 40)
                elseif endT > 0 then
                    col = (left < 10 and now % 0.5 < 0.25) and Color(255, 120, 120) or Color(235, 50, 45)
                else
                    col = Color(160, 50, 45)
                end
            else
                txt, col = "RX", (now % 1.2 < 0.15) and Color(255, 60, 50) or Color(110, 30, 30)
            end
            draw.SimpleText(txt, DIGITS, 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if self.IsTrainingBomb then
                draw.RoundedBox(4, -w / 2, h / 2 + 4, w, 26, Color(245, 200, 40, 255))
                draw.SimpleText("TRAINING", SMALL, 0, h / 2 + 17, Color(20, 20, 20), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end
end
