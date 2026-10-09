--[[
    Mine (rhylib_eod): AP by default, rhylib_eod_mine_lap is the large one.
    Placed by the GM with the toolgun (EOD: single mines, scattered mines,
    minefields). Half buried and hard to see: you spot one within a few
    metres (Trained eye further), or with the mine scanner.

    Stepping on one clicks: whoever stands on it must not move; stepping
    off or moving sets it off. Someone with an EOD kit digs it out (hold),
    pushes the safety pin(s) in at the right moment (LAP: two) and lifts
    it away. Clone NPCs set mines off at once; droids know where theirs are.
    Explosions nearby, and shooting it, set it off too.
    Rules: sv_30_mines.lua.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Mine (AP)"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.Model = "models/props_combine/combine_mine01.mdl"
ENT.MineType = "ap"
ENT.IsRhylibMine = true

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Safe")
    self:NetworkVar("Bool", 1, "Dug")
    self:NetworkVar("Bool", 2, "Marked")
    self:NetworkVar("Int", 0, "Pins")
    self:NetworkVar("Entity", 0, "Presser")
end

function ENT:PinsNeeded() return self.MineType == "lap" and 2 or 1 end
function ENT:MineScale() return self.MineType == "lap" and 0.7 or 0.5 end

if SERVER then
    function ENT:Initialize()
        local E = Rhylib.EOD
        local mdl = E and E.Cfg("mineModel")
        if not (isstring(mdl) and util.IsValidModel(mdl)) then mdl = self.Model end
        self:SetModel(mdl)
        -- (the model is drawn smaller on the client; the box here is set by
        -- hand from the model's own bounds, so nothing is scaled twice)
        local sc = self:MineScale()
        local mn, mx = self:GetModelBounds()
        local half = self.MineType == "lap" and 13 or 10
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-half, -half, mn.z * sc), Vector(half, half, mx.z * sc + 3))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)   -- (players walk over it; traces still find it)
        if E and E.SetupMine then E.SetupMine(self) end
    end

    function ENT:OnTakeDamage(dmg)
        local E = Rhylib.EOD
        if E and E.MineShot then E.MineShot(self, dmg) end
    end

    function ENT:OnRemove()
        local E = Rhylib.EOD
        if E and E.mines then E.mines[self] = nil end
        local p = self:GetPresser()
        if IsValid(p) and p:GetNW2Entity("rhylib_onMine") == self then p:SetNW2Entity("rhylib_onMine", NULL) end
    end
end

if CLIENT then
    -- How much of it you see: dug out, pinned, pressed, marked or found by a
    -- scanner = all of it; otherwise only up close (Trained eye further).
    function ENT:VisibleAmount()
        if self:GetDug() or self:GetSafe() or IsValid(self:GetPresser()) or self:GetMarked() then return 1 end
        local E = Rhylib.EOD
        if E and E.mineSeen and (E.mineSeen[self] or 0) > CurTime() then return 1 end
        local ply = LocalPlayer()
        local w = ply:GetActiveWeapon()
        if IsValid(w) and w:GetClass() == "rhylib_toolgun" then return 0.8 end   -- (the GM placing them)
        local vis = (E and E.Cfg("mineVisible") or 240) * (E and E.Skill(ply, "eod_eye") and 1.6 or 1)
        local d = EyePos():Distance(self:GetPos())
        if d >= vis then return 0 end
        return 0.6 * math.sqrt(1 - d / vis)
    end

    function ENT:Draw() end

    function ENT:DrawTranslucent()
        local a = self:VisibleAmount()
        if a <= 0.02 then return end
        if self.rhylibScaled ~= self:GetModel() then
            self.rhylibScaled = self:GetModel()
            local m = Matrix()
            m:Scale(Vector(1, 1, 1) * self:MineScale())
            self:EnableMatrix("RenderMultiply", m)
            self:SetRenderBounds(self:OBBMins() - Vector(8, 8, 8), self:OBBMaxs() + Vector(8, 8, 8))
        end
        render.SetBlend(a)
        if self:GetSafe() then render.SetColorModulation(0.6, 1, 0.6) end
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
        render.SetBlend(1)
    end
end
