--[[
    RPS-6 top-attack rocket (lock-on mode, EOD Top attack skill).
    Climbs first (up to topClimb units, less under a ceiling), then turns
    over and dives onto the locked target (it follows it if it moves; a
    target that's gone: its last spot). Moved by hand each tick with one
    trace, like rhylib_b2_rocket. Blast = the RPS-6's (Explosive radius /
    damage), strength 2 for comms jammers (kind "rocket").
    Spawned by rhylib_rps6 with: dir, target, owner, weapon, explosive.
]]

AddCSLuaFile()

local Config = Rhylib.Config
Config.Register("weapons", "topClimb", 900, "RPS-6 top attack: highest climb before the dive (units)")
Config.Register("weapons", "topSpeed", 1500, "RPS-6 top attack: rocket speed (units/s)")

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Top-attack rocket"
ENT.Category = "Rhylib: Heavy"
ENT.Model = "models/weapons/w_missile_closed.mdl"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

-- Guide: the player steering it by laser (unlocked shots), else NULL.
function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Guide")
end

-- Where the guide's laser lands (nil if it isn't steering any more).
local GUIDE_RANGE = 12000
function ENT:LaserSpot()
    local g = self:GetGuide()
    if not (IsValid(g) and g:IsPlayer() and g:Alive()) then return nil end
    local w = g:GetActiveWeapon()
    if not (IsValid(w) and w.LockOn and w:GetClass() == self:GetNW2String("rhylib_guideGun", "rhylib_rps6")) then return nil end
    local tr = util.TraceLine({ start = g:EyePos(), endpos = g:EyePos() + g:GetAimVector() * GUIDE_RANGE,
        filter = { g, self }, mask = MASK_SHOT })
    if not tr.Hit or tr.HitSky then return nil end
    return tr.HitPos
end

if SERVER then
    local tr = {}
    local trData = { mask = MASK_SHOT, output = tr }

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self.dir = (self.dir or self:GetForward()):GetNormalized()
        self.speed = Config.Get("weapons", "topSpeed") or 1500
        self.born = CurTime()
        self.dieAt = CurTime() + 12
        local me, owner = self, self.owner
        self.filterFn = function(e) return e ~= me and e ~= owner end
        if not IsValid(self.target) and IsValid(owner) and owner:IsPlayer() then
            -- laser guided (fired without a lock)
            self:SetGuide(owner)
            if IsValid(self.weapon) then self:SetNW2String("rhylib_guideGun", self.weapon:GetClass()) end
        end
        self.lastSpot = IsValid(self.target) and self.target:WorldSpaceCenter() or self:LaserSpot() or (self:GetPos() + self.dir * 2000)

        -- The top of the climb: part way to the target, high up (lower
        -- under a ceiling; no room = straight at it).
        local from = self:GetPos()
        local to = self.lastSpot
        local flat = Vector(to.x - from.x, to.y - from.y, 0)
        local dist = flat:Length()
        local want = math.Clamp(dist * 0.5, 250, Config.Get("weapons", "topClimb") or 900)
        local roof = util.TraceLine({ start = from, endpos = from + Vector(0, 0, want + 80), mask = MASK_SOLID_BRUSHONLY })
        local h = roof.Hit and (roof.HitPos.z - from.z - 80) or want
        if h >= 150 and dist > 300 then
            self.apex = from + flat * 0.35 + Vector(0, 0, math.max(h, to.z - from.z + h * 0.5))
            local ok = util.TraceLine({ start = from, endpos = self.apex, mask = MASK_SOLID_BRUSHONLY })
            if ok.Hit then self.apex = nil end
        end
        self.phase = self.apex and 1 or 2
        -- out of the tube upward
        if self.apex then self.dir = (self.dir + Vector(0, 0, 1.2)):GetNormalized() end
        self:SetAngles(self.dir:Angle())
        util.SpriteTrail(self, 0, Color(220, 220, 220), true, 14, 0, 0.8, 1 / 14 * 0.5, "trails/smoke.vmt")
        self:EmitSound("weapons/rpg/rocket1.wav", 75, 110)
    end

    function ENT:Explode(pos)
        if self.done then return end
        self.done = true
        local owner = IsValid(self.owner) and self.owner or game.GetWorld()
        local inflictor = IsValid(self.weapon) and self.weapon or self
        local ex = self.explosive or { radius = 200, damage = 250 }
        util.BlastDamage(inflictor, owner, pos, ex.radius, ex.damage)
        hook.Run("Rhylib.Explosion", pos, ex.radius, ex.tier or 2, owner, inflictor, "rocket")
        local ed = EffectData()
        ed:SetOrigin(pos)
        ed:SetMagnitude(1)
        ed:SetScale(1)
        util.Effect("Explosion", ed, true, true)
        util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 40), self)
        self:StopSound("weapons/rpg/rocket1.wav")
        self:Remove()
    end

    -- Turn the heading toward want by at most rate radians this tick.
    local function steer(dir, want, rate)
        local dot = math.Clamp(dir:Dot(want), -1, 1)
        local ang = math.acos(dot)
        if ang <= rate or ang < 1e-4 then return want end
        local k = rate / ang
        local d = dir * (1 - k) + want * k
        d:Normalize()
        return d
    end

    function ENT:Think()
        local now = CurTime()
        if now > self.dieAt then self:Explode(self:GetPos()) return end
        local dt = engine.TickInterval()
        local from = self:GetPos()
        if IsValid(self.target) and (not self.target.destroyed) then
            self.lastSpot = self.target:WorldSpaceCenter()
        elseif IsValid(self:GetGuide()) then
            -- laser: follow the dot; the guide put the gun away / died = its last spot
            local spot = self:LaserSpot()
            if spot then self.lastSpot = spot else self:SetGuide(NULL) end
        end
        local goal
        if self.phase == 1 then
            goal = self.apex
            local to = goal - from
            -- over the top: close to it, past it, or climbing too long
            if to:Length() < 140 or to:Dot(self.dir) <= 0 or now - self.born > 2.5 then self.phase = 2 end
        end
        if self.phase == 2 then goal = self.lastSpot end
        local want = (goal - from):GetNormalized()
        -- climbing turns gently, the dive hard (so it comes down steeply)
        local rate = (self.phase == 1 and 2.2 or 4.5) * dt
        self.dir = steer(self.dir, want, rate)
        local to = from + self.dir * self.speed * dt
        trData.start, trData.endpos = from, to
        trData.filter = self.filterFn
        util.TraceLine(trData)
        if tr.HitSky then
            -- (climbing into the skybox: dive now instead of vanishing)
            if self.phase == 1 then
                self.phase = 2
                self.dir = (self.lastSpot - from):GetNormalized()
                self:NextThink(now)
                return true
            end
            self:Remove()
            return
        end
        if tr.Hit then
            self:Explode(tr.HitPos + tr.HitNormal * 4)
            return
        end
        -- close enough to the target: go off (a jammer's centre may sit in its hull)
        if self.phase == 2 and to:DistToSqr(self.lastSpot) < 40 * 40 then
            self:Explode(to)
            return
        end
        self:SetPos(to)
        self:SetAngles(self.dir:Angle())
        self:NextThink(now)
        return true
    end

    function ENT:OnRemove()
        self:StopSound("weapons/rpg/rocket1.wav")
    end
end

if CLIENT then
    local GLOW = Material("sprites/light_glow02_add")
    local FLAME = Color(255, 170, 80)

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        render.SetMaterial(GLOW)
        render.DrawSprite(self:GetPos() - self:GetForward() * 10, 28, 28, FLAME)
    end
end

if CLIENT then
    -- The laser dot of every guided rocket (everyone sees it).
    local DOT = Material("sprites/light_glow02_add")
    local RED = Color(255, 40, 30)
    Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weapons.topattack.laser", function(depth, sky)
        if depth or sky then return end
        for _, m in ipairs(ents.FindByClass("rhylib_topattack")) do
            if IsValid(m) and m.LaserSpot then
                local spot = m:LaserSpot()
                if spot then
                    local pulse = 10 + 3 * math.sin(RealTime() * 12)
                    render.SetMaterial(DOT)
                    render.DrawSprite(spot, pulse, pulse, RED)
                    render.DrawSprite(spot, 4, 4, color_white)
                end
            end
        end
    end)
end
