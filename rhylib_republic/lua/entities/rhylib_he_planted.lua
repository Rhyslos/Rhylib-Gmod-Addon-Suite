--[[
    A planted high explosive charge (rhylib_he_charge weapon, 2026-10-07).
    Class rhylib_he_planted: not the weapon's name (they would clash).

    fuse > 0: counts down and goes off. Placing one also gives every synced
    charge of the same planter (Rhylib.HE.waiting, keyed by SteamID64) the
    same moment, so they all go off together.
    fuse 0 (sync): waits with a slow amber light until its planter places a
    charge with a timer; removed after weapons heIdleLife seconds if that
    never happens. NW2Int rhylib_heSynced on the planter = how many wait.
    Blast: util.BlastDamage heRadius / heDamage, and hook Rhylib.Explosion
    strength 3 (comms jammers, rhylib_radio) within heJammerReach.
    Beeps once a second, faster over the last 5 s; a small readout above it
    shows the seconds left (or SYNC).
]]

AddCSLuaFile()

local Config = Rhylib.Config
Config.Register("weapons", "heRadius", 350, "High explosive charge: blast radius (units)")
Config.Register("weapons", "heDamage", 400, "High explosive charge: damage at the centre")
Config.Register("weapons", "heJammerReach", 250, "High explosive charge: how close a comms jammer must be to take the hit (units, to the nearest point of the jammer)")
Config.Register("weapons", "heIdleLife", 900, "High explosive charge: seconds a synced charge waits for a timer before it's removed")

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "High explosive charge"
ENT.Category = "Rhylib: Grenades & charges"
ENT.Model = "models/weapons/w_slam.mdl"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "Boom")   -- when it goes off (0 = synced, waiting)
end

if SERVER then
    Rhylib.HE = Rhylib.HE or { waiting = {} }
    local HE = Rhylib.HE

    local function recount(sid)
        local n = 0
        for e in pairs(HE.waiting[sid] or {}) do
            if IsValid(e) then n = n + 1 end
        end
        if n == 0 then HE.waiting[sid] = nil end
        local p = player.GetBySteamID64(sid)
        if IsValid(p) then p:SetNW2Int("rhylib_heSynced", n) end
    end

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:SetColor(Color(255, 205, 140))
        if IsValid(self.stuckTo) then self:SetParent(self.stuckTo) end
        local p = self.planter
        self.sid = IsValid(p) and p:SteamID64() or "0"
        self.rhylibPlayerCharge = IsValid(p) and p:IsPlayer()   -- (counts on jammers even if they left)
        self.nextBeep = 0
        local fuse = self.fuse or 0
        if fuse > 0 then
            local boom = CurTime() + fuse
            self:SetBoom(boom)
            -- every synced charge of this planter takes the same timer
            local list = HE.waiting[self.sid]
            if list then
                for e in pairs(list) do
                    if IsValid(e) then
                        e:SetBoom(boom)
                        e.nextBeep = 0
                    end
                end
                HE.waiting[self.sid] = nil
                recount(self.sid)
            end
        else
            self:SetBoom(0)
            self.dieAt = CurTime() + (Config.Get("weapons", "heIdleLife") or 900)
            HE.waiting[self.sid] = HE.waiting[self.sid] or {}
            HE.waiting[self.sid][self] = true
            recount(self.sid)
        end
    end

    function ENT:Think()
        local now, boom = CurTime(), self:GetBoom()
        if boom > 0 then
            if now >= boom then self:Explode() return end
            if now >= self.nextBeep then
                local left = boom - now
                sound.Play("buttons/blip1.wav", self:GetPos(), 80, left <= 2 and 140 or 115, 1)
                self.nextBeep = now + (left > 5 and 1 or math.max(0.08, 0.5 * left / 5))
            end
        elseif self.dieAt and now > self.dieAt then
            self:Remove()
            return
        end
        self:NextThink(now + 0.05)
        return true
    end

    function ENT:Explode()
        if self.done then return end
        self.done = true
        local pos = self:WorldSpaceCenter()
        local attacker = self.planter
        if not IsValid(attacker) then attacker = player.GetBySteamID64(self.sid) end
        if not IsValid(attacker) then attacker = self end
        local ed = EffectData()
        ed:SetOrigin(pos)
        util.Effect("Explosion", ed, true, true)
        util.Effect("HelicopterMegaBomb", ed, true, true)
        sound.Play("ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", pos, 100, 95)
        local r = (Config.Get("weapons", "heRadius") or 350) * (self.radiusMult or 1)
        util.BlastDamage(self, attacker, pos, r, (Config.Get("weapons", "heDamage") or 400) * (self.damageMult or 1))
        util.ScreenShake(pos, 14, 160, 1.2, r * 3)
        util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), self)
        -- strength 3: the only thing that takes down large and map-wide jammers
        hook.Run("Rhylib.Explosion", pos, Config.Get("weapons", "heJammerReach") or 250, 3, attacker, self, "he")
        self:Remove()
    end

    function ENT:OnRemove()
        local list = HE.waiting[self.sid or ""]
        if list and list[self] then
            list[self] = nil
            recount(self.sid)
        end
    end
else
    local GLOW = Material("sprites/light_glow02_add")
    local RED, AMBER = Color(255, 60, 40), Color(255, 175, 60)

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        local boom = self:GetBoom()
        local now = CurTime()
        local pos = self:WorldSpaceCenter() + self:GetUp() * 3
        local on, col
        if boom > 0 then
            local left = math.max(boom - now, 0)
            local rate = Lerp(math.Clamp(left / 5, 0, 1), 10, 1)
            on, col = math.sin(now * rate * math.pi) > 0, RED
        else
            on, col = true, Color(AMBER.r, AMBER.g, AMBER.b, 120 + 100 * math.abs(math.sin(now * 1.5)))
        end
        if on then
            render.SetMaterial(GLOW)
            render.DrawSprite(pos, 12, 12, col)
        end
        -- readout facing you, close up only
        local eye = EyePos()
        if eye:DistToSqr(pos) > 400 * 400 then return end
        local ang = (eye - pos):Angle()
        ang:RotateAroundAxis(ang:Up(), 90)
        ang:RotateAroundAxis(ang:Forward(), 90)
        local text = boom > 0 and string.format("%d", math.ceil(math.max(boom - now, 0))) or "SYNC"
        cam.Start3D2D(pos + Vector(0, 0, 7), ang, 0.08)
            draw.SimpleTextOutlined(text, "DermaLarge", 0, 0, boom > 0 and RED or AMBER, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 200))
        cam.End3D2D()
    end
end
