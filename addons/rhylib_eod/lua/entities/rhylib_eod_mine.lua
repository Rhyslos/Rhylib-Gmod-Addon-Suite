--[[
    Mine (rhylib_eod): AP by default, rhylib_eod_mine_lap is the large one.
    Placed by the GM with the toolgun (EOD: single mines, scattered mines,
    minefields). Half buried and hard to see: you spot one within a few
    metres (config mineVisible), or with the mine scanner.

    Stepping on one clicks: whoever stands on it must not move; stepping
    off or moving sets it off. Someone with an EOD kit digs it out (hold),
    pushes the safety pin(s) in at the right moment (LAP: two) and lifts
    it away. Clone NPCs set mines off at once; droids know where theirs are.
    Explosions nearby, and shooting it, set it off too.
    Rules: sv_30_mines.lua.

    Shared. NetworkVars below; the server keeps the fuse in self.eodm
    (E.SetupMine) and window viewers in self.viewers. To make your own
    variant, set ENT.Base = "rhylib_eod_mine" and MineType ("ap" / "lap")
    or IsTrainingMine.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Mine (AP)"
ENT.Category = "Rhylib: EOD"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
ENT.Model = "models/props/starwars/weapons/ap_mine.mdl"
ENT.FallbackModel = "models/props_combine/combine_mine01.mdl"
ENT.MineType = "ap"         -- "ap" (1 pin) or "lap" (large: 2 pins, bigger blast and trigger)
ENT.IsRhylibMine = true
ENT.ModelFromConfig = true   -- (eod mineModel / mineModelLarge)

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Safe")     -- (pinned: can't go off)
    self:NetworkVar("Bool", 1, "Dug")      -- (dug out: the fuse shows)
    self:NetworkVar("Bool", 2, "Marked")   -- (marked by a scanner: everyone sees it)
    self:NetworkVar("Bool", 3, "Large")      -- (training mines: set up as LAP)
    self:NetworkVar("Bool", 4, "Shown")      -- (training mines: always visible)
    self:NetworkVar("Int", 0, "Pins")        -- (safety pins pushed in so far)
    self:NetworkVar("Int", 1, "PinsNeed")    -- (training mines: 0 = by type)
    self:NetworkVar("Int", 2, "Level")       -- (training mines: 1 easy, 2 normal, 3 hard; 0 = normal)
    self:NetworkVar("Entity", 0, "Presser")  -- (the player standing on it)
end

-- ENT:IsLarge(): a LAP (by type, or a training mine set up as one).
function ENT:IsLarge() return self.MineType == "lap" or self:GetLarge() end
-- ENT:PinsNeeded(): pins to make it safe (training setup, else AP 1 / LAP 2).
function ENT:PinsNeeded()
    local n = self:GetPinsNeed()
    if n > 0 then return n end
    return self:IsLarge() and 2 or 1
end
-- Model for its type (config mineModel / mineModelLarge, HL2 hopper mine if missing).
function ENT:WantedModel()
    local E = Rhylib.EOD
    local mdl = E and E.Cfg(self:IsLarge() and "mineModelLarge" or "mineModel")
    if isstring(mdl) and (util.IsValidModel(mdl) or (CLIENT and file.Exists(mdl, "GAME"))) then return mdl end
    return self.FallbackModel
end
-- Drawn scaled so its width matches mineSize (LAP ×1.4), whatever the model.
function ENT:MineScale()
    local E = Rhylib.EOD
    local want = (E and E.Cfg("mineSize") or 20) * (self:IsLarge() and 1.4 or 1)
    local mn, mx = self:GetModelBounds()
    if not mn then return 1 end
    local wide = math.max(mx.x - mn.x, mx.y - mn.y)
    if wide < 1 then return 1 end
    return math.Clamp(want / wide, 0.05, 4)
end

if SERVER then
    function ENT:Initialize()
        local E = Rhylib.EOD
        self:SetModel(self:WantedModel())
        self:SetSolid(SOLID_BBOX)
        self:SetupBox()
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)   -- (players walk over it; traces still find it)
        if E and E.SetupMine then E.SetupMine(self) end
    end

    -- The model is drawn smaller on the client; the box is set by hand from
    -- the model's own bounds, so nothing is scaled twice.
    function ENT:SetupBox()
        local mdl = self:WantedModel()
        if self:GetModel() ~= mdl then self:SetModel(mdl) end   -- (training mines switch AP/LAP)
        local sc = self:MineScale()
        local mn, mx = self:GetModelBounds()
        local half = math.max(8, math.max(-mn.x, mx.x, -mn.y, mx.y) * sc)
        self:SetCollisionBounds(Vector(-half, -half, mn.z * sc), Vector(half, half, mx.z * sc + 3))
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
    -- scanner = all of it; otherwise only up close (mineVisible, fading in).
    -- ENT:VisibleAmount() -> 0..1 (client).
    function ENT:VisibleAmount()
        if self:GetDug() or self:GetSafe() or IsValid(self:GetPresser()) or self:GetMarked() or self:GetShown() then return 1 end
        local E = Rhylib.EOD
        if E and E.mineSeen and (E.mineSeen[self] or 0) > CurTime() then return 1 end
        local ply = LocalPlayer()
        local w = ply:GetActiveWeapon()
        if IsValid(w) and w:GetClass() == "rhylib_toolgun" then return 0.8 end   -- (the GM placing them)
        local vis = (E and E.Cfg("mineVisible") or 240)
        local d = EyePos():Distance(self:GetPos())
        if d >= vis then return 0 end
        return 0.6 * math.sqrt(1 - d / vis)
    end

    function ENT:Draw() end

    function ENT:DrawTranslucent()
        local a = self:VisibleAmount()
        if a <= 0.02 then return end
        local key = self:GetModel() .. (self:IsLarge() and "L" or "") .. ((Rhylib.EOD and Rhylib.EOD.Cfg("mineSize")) or 20)
        if self.rhylibScaled ~= key then
            self.rhylibScaled = key
            local m = Matrix()
            m:Scale(Vector(1, 1, 1) * self:MineScale())
            self:EnableMatrix("RenderMultiply", m)
            self:SetRenderBounds(self:OBBMins() - Vector(8, 8, 8), self:OBBMaxs() + Vector(8, 8, 8))
        end
        render.SetBlend(a)
        if self:GetSafe() then render.SetColorModulation(0.6, 1, 0.6)
        elseif self.IsTrainingMine then render.SetColorModulation(1, 0.9, 0.35) end
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
        render.SetBlend(1)
    end
end
