--[[
    Comms jammer (rhylib_radio, 2026-10-07, owner): while it's on, players
    within its range can't use the radio: keying it only gives
    static, others hear them only as local voice, they hear no radio, and
    the radio text channels (squad, battalion, command, comms) are closed.
    Their incoming radio meter goes haywire.

    Staff (rhylib.radio.admin) press E on it to switch it on or off.
    It can be shot to pieces (radio jammerHealth; 0 = can't be destroyed):
    it goes dark and stops jamming until the next map change or cleanup,
    and the map save keeps it as it was.
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
        local hp = R and R.Cfg("jammerHealth" .. key) or 400
        self.hp = hp > 0 and hp or nil
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

    function ENT:OnTakeDamage(dmg)
        if not self.hp or self.destroyed then return end
        self.hp = self.hp - dmg:GetDamage()
        local e = EffectData()
        e:SetOrigin(dmg:GetDamagePosition())
        e:SetMagnitude(1)
        e:SetScale(1)
        util.Effect("Sparks", e)
        if self.hp <= 0 then
            -- Wrecked, not removed: a later save must still keep it on the map.
            self.wasOn = self:GetActive()
            self.destroyed = true
            local b = EffectData()
            b:SetOrigin(self:WorldSpaceCenter())
            util.Effect("Explosion", b)
            if self.hum then self.hum:Stop() end
            self:SetActive(false)
            self:SetNoDraw(true)
            self:SetNotSolid(true)
            self:DrawShadow(false)
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
