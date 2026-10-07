--[[
    Comms jammer (rhylib_radio, 2026-10-07, owner): while it's on, players
    within its range can't use the radio: keying it only gives
    static, others hear them only as local voice, they hear no radio, and
    the radio text channels (squad, battalion, command, comms) are closed.
    Their incoming radio meter goes haywire.

    Staff (rhylib.radio.admin) press E on it to switch it on or off.
    Only explosives destroy it (hook Rhylib.Explosion, sv_10_radio; size
    rules in R.JAMMER_SIZES): it goes dark and stops jamming until the
    next map change or cleanup, and the map save keeps it as it was.
    Gunfire only sparks.
    Place with the toolgun; rhylib_radio_save keeps them on the map.

    This is the small one and the base of the others (R.JAMMER_SIZES):
    rhylib_comms_jammer_medium / _large / _map only change the config keys
    (range, health, model). A model that isn't installed falls back to
    radio jammerFallbackModel.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Comms jammer (small)"
ENT.Category = "Rhylib: Military police"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Active")
end

if SERVER then
    local FALLBACK = "models/props_lab/reciever01a.mdl"

    function ENT:Initialize()
        local R = Rhylib.Radio
        local key = R and R.JammerSize(self).key or ""
        local mdl = R and R.Cfg("jammerModel" .. key)
        if not (isstring(mdl) and util.IsValidModel(mdl)) then
            mdl = R and R.Cfg("jammerFallbackModel") or FALLBACK
            if not util.IsValidModel(mdl) then mdl = FALLBACK end
        end
        self:SetModel(mdl)
        self:PhysicsInit(SOLID_VPHYSICS)
        -- (some prop models have no collision mesh: use their box)
        if not IsValid(self:GetPhysicsObject()) then
            self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs())
        end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:SetActive(not self.startOff)
        if R then R.jammers[self] = true end
        self.hum = CreateSound(self, "ambient/machines/combine_terminal_loop1.wav")
        if self.hum and self:GetActive() then self.hum:PlayEx(0.35, 140) end
    end

    function ENT:SetOn(on)
        self:SetActive(on)
        if self.hum then
            if on then self.hum:PlayEx(0.35, 140) else self.hum:Stop() end
        end
        self:EmitSound(on and "buttons/button1.wav" or "buttons/button18.wav", 65)
    end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer()) or self.destroyed then return end
        Rhylib.Perms.Check(ply, "rhylib.radio.admin", function(ok)
            if not (ok and IsValid(self)) then return end
            self:SetOn(not self:GetActive())
            ply:ChatPrint("[Radio] " .. self.PrintName .. " " .. (self:GetActive() and "on" or "off"))
            local R = Rhylib.Radio
            if R and R.SaveJammers then R.SaveJammers() end
        end)
    end

    local function note(self, ply, text)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        self.noted = self.noted or {}
        if (self.noted[ply] or 0) > CurTime() then return end
        self.noted[ply] = CurTime() + 3
        local R = Rhylib.Radio
        if R and R.Note then R.Note(ply, text) else ply:ChatPrint(text) end
    end

    local function sparks(pos)
        local e = EffectData()
        e:SetOrigin(pos)
        e:SetMagnitude(1)
        e:SetScale(1)
        util.Effect("Sparks", e)
    end

    -- Gunfire and the like: sparks and a hint, no harm. (explosions come
    -- through ExplosiveHit)
    function ENT:OnTakeDamage(dmg)
        if self.destroyed then return end
        sparks(dmg:GetDamagePosition())
        if dmg:IsDamageType(DMG_BLAST) then return end
        local R = Rhylib.Radio
        local size = R and R.JammerSize(self)
        local text = size and (size.need or R.JAMMER_TIERS[size.tier or 1]) or "explosives"
        note(self, dmg:GetAttacker(), "That won't do it: the " .. string.lower(self.PrintName) .. " needs " .. text)
    end

    -- Wrecked, not removed: a later save must still keep it on the map.
    function ENT:Destroy(by)
        if self.destroyed then return end
        self.wasOn = self:GetActive()
        self.destroyed = true
        local b = EffectData()
        b:SetOrigin(self:WorldSpaceCenter())
        util.Effect("Explosion", b)
        util.Effect("HelicopterMegaBomb", b)
        self:EmitSound("ambient/explosions/explode_4.wav", 100)
        if self.hum then self.hum:Stop() end
        self:SetActive(false)
        self:SetNoDraw(true)
        self:SetNotSolid(true)
        self:DrawShadow(false)
        local ph = self:GetPhysicsObject()
        if IsValid(ph) then ph:EnableCollisions(false) end
        if IsValid(by) and by:IsPlayer() then
            local R = Rhylib.Radio
            if R and R.Note then R.Note(by, self.PrintName .. " destroyed") end
        end
    end

    -- An explosion of strength tier (R.JAMMER_TIERS) reached it. kind:
    -- "grenade", "breach", "rocket" or "he".
    local POINTS = { he = "jamPointsHE", rocket = "jamPointsRocket", breach = "jamPointsBreach" }
    function ENT:ExplosiveHit(tier, by, kind)
        if self.destroyed then return end
        local R = Rhylib.Radio
        local size = R and R.JammerSize(self) or { tier = 1 }
        sparks(self:WorldSpaceCenter())
        local needText = size.need or R.JAMMER_TIERS[size.tier]
        if tier < (size.tier or 1) then
            note(self, by, "The " .. string.lower(self.PrintName) .. " held: it needs " .. needText)
            return
        end
        -- Damage points that add up (large: HE 6, rocket 3, breaching charge 2).
        if size.points then
            local need = math.max(1, R.Cfg(size.points) or 6)
            local add = POINTS[kind] and (R.Cfg(POINTS[kind]) or 0) or (tier >= 3 and need or 0)
            if add <= 0 then
                note(self, by, "The " .. string.lower(self.PrintName) .. " held: it needs " .. needText)
                return
            end
            self.jamDamage = (self.jamDamage or 0) + add
            if self.jamDamage >= need then self:Destroy(by) return end
            if not self.notePending then
                self.notePending = true
                timer.Simple(0.2, function()
                    if not IsValid(self) then return end
                    self.notePending = nil
                    if self.destroyed then return end
                    self.noted = nil
                    note(self, by, string.format("The %s is damaged (%d of %d): finish it with %s",
                        string.lower(self.PrintName), self.jamDamage, need, needText))
                end)
            end
            return
        end
        local need = size.charges and math.max(1, math.floor(R.Cfg(size.charges) or 1)) or 1
        if need <= 1 then self:Destroy(by) return end
        -- Several HE charges: only high explosive counts, all within the window.
        if tier < 3 then
            note(self, by, "The " .. string.lower(self.PrintName) .. " held: it needs " .. need .. " high explosive charges")
            return
        end
        local now, win = CurTime(), R.Cfg("jammerChargeWindow") or 3
        local hits = {}
        for _, t in ipairs(self.heHits or {}) do
            if win <= 0 or now - t <= win then hits[#hits + 1] = t end
        end
        hits[#hits + 1] = now
        self.heHits = hits
        if #hits >= need then self:Destroy(by) return end
        -- (one note after the charges going off together have all landed)
        if not self.notePending then
            self.notePending = true
            timer.Simple(0.2, function()
                if not IsValid(self) then return end
                self.notePending = nil
                if self.destroyed then return end
                local n = #(self.heHits or {})
                local text = n .. " of " .. need .. " charges: the " .. string.lower(self.PrintName) .. " is damaged but still running"
                if win > 0 then text = text .. ". Set " .. need .. " off together (sync them)" end
                self.noted = nil
                note(self, by, text)
            end)
        end
    end

    function ENT:OnRemove()
        if self.hum then self.hum:Stop() end
        local R = Rhylib.Radio
        if R and R.jammers then R.jammers[self] = nil end
    end
else
    local GLOW = Material("sprites/light_glow02_add")
    local RING = Material("effects/select_ring")
    local RED = Color(235, 70, 60)

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        if not self:GetActive() then return end
        local top = self:OBBMaxs().z
        local pos = self:LocalToWorld(Vector(0, 0, top + 6))
        local size = math.Clamp(top * 0.25, 18, 64)
        local t = CurTime()
        local blink = (t * 2) % 1 < 0.5 and 1 or 0.35
        render.SetMaterial(GLOW)
        render.DrawSprite(pos, size, size, Color(RED.r, RED.g, RED.b, 220 * blink))
        -- Staff with the toolgun see its range on the ground.
        local me = LocalPlayer()
        local w = IsValid(me) and me:GetActiveWeapon()
        if IsValid(me) and me:IsAdmin() and IsValid(w) and w:GetClass() == "rhylib_toolgun" then
            local R = Rhylib.Radio
            local r = R and R.JammerRange(self) or 1800
            if r == math.huge then return end   -- (whole map: no ring)
            render.SetMaterial(RING)
            render.DrawQuadEasy(self:GetPos() + Vector(0, 0, 4), Vector(0, 0, 1), r * 2, r * 2, Color(RED.r, RED.g, RED.b, 60), 0)
        end
    end
end
