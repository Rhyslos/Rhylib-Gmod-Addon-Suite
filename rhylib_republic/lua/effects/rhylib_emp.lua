--[[
    EMP effect (droid popper). Flags 0: the blast at the origin (flash,
    expanding ring, blue light, lightning arcs out to the radius).
    Flags 1: lightning crawling over a hit droid (around the origin; the
    droid itself is gone by the time this runs).
]]

local BOLT = Material("trails/electric")
local GLOW = Material("sprites/light_glow02_add")
local RING = Material("effects/select_ring")
-- Colour by EffectData:SetColor: 0 blue (droid popper), 1 purple (B2
-- rocket), 2 orange-yellow (training).
local PALETTE = {
    [0] = { Color(110, 180, 255), Color(220, 240, 255) },
    [1] = { Color(190, 90, 255), Color(240, 210, 255) },
    [2] = { Color(255, 175, 50), Color(255, 240, 200) },
}
local BLUE, WHITE = PALETTE[0][1], PALETTE[0][2]
local lightN = 0   -- (effects have no entity index: own light slots)

local function arc(a, b, width, col)
    -- A jagged line: a few kinked segments between a and b.
    local n = 6
    local prev = a
    local len = a:Distance(b)
    render.SetMaterial(BOLT)
    for i = 1, n do
        local p = LerpVector(i / n, a, b)
        if i < n then p = p + VectorRand() * len * 0.06 end
        render.DrawBeam(prev, p, width, 0, 1, col)
        prev = p
    end
end

function EFFECT:Init(data)
    self.pos = data:GetOrigin()
    self.kind = data:GetFlags()
    self.radius = math.max(data:GetRadius(), 60)
    self.start = CurTime()
    local pal = PALETTE[data:GetColor()] or PALETTE[0]
    self.col, self.white = pal[1], pal[2]
    self.life = self.kind == 0 and 0.7 or 1.0
    self.arcs = {}
    self.nextArcs = 0
    self:SetPos(self.pos)
    self:SetRenderBounds(Vector(-1, -1, -1) * self.radius, Vector(1, 1, 1) * self.radius)
    if self.kind == 0 then
        lightN = (lightN + 1) % 32
        local d = DynamicLight(0x7000 + lightN)
        if d then
            d.pos = self.pos
            d.r, d.g, d.b = self.col.r, self.col.g, self.col.b
            d.brightness = 5
            d.size = self.radius * 1.4
            d.decay = self.radius * 2
            d.dieTime = CurTime() + 0.6
        end
    end
end

function EFFECT:Think()
    if CurTime() > self.start + self.life then return false end
    -- New arc shapes every few frames.
    if CurTime() >= self.nextArcs then
        self.nextArcs = CurTime() + 0.05
        self.arcs = {}
        if self.kind == 0 then
            for i = 1, 7 do
                local dir = VectorRand()
                dir.z = math.abs(dir.z) * 0.5
                dir:Normalize()
                local tr = util.TraceLine({ start = self.pos, endpos = self.pos + dir * self.radius * math.Rand(0.4, 1), mask = MASK_SOLID_BRUSHONLY })
                self.arcs[i] = tr.HitPos
            end
        else
            -- A body-sized box around the hit droid's centre.
            local function pt() return self.pos + Vector(math.Rand(-16, 16), math.Rand(-16, 16), math.Rand(-36, 30)) end
            for i = 1, 4 do self.arcs[i] = { pt(), pt() } end
        end
    end
    return true
end

function EFFECT:Render()
    local BLUE, WHITE = self.col or BLUE, self.white or WHITE
    local f = (CurTime() - self.start) / self.life
    local fade = math.Clamp(1 - f, 0, 1)
    if self.kind == 0 then
        render.SetMaterial(GLOW)
        local s = self.radius * 0.6 * (1 - f * 0.5)
        render.DrawSprite(self.pos, s, s, Color(BLUE.r, BLUE.g, BLUE.b, 255 * fade))
        render.DrawSprite(self.pos, s * 0.4, s * 0.4, Color(255, 255, 255, 255 * fade))
        render.SetMaterial(RING)
        local r = self.radius * 2 * math.min(f * 2, 1)
        render.DrawQuadEasy(self.pos + Vector(0, 0, 4), Vector(0, 0, 1), r, r, Color(BLUE.r, BLUE.g, BLUE.b, 200 * fade), 0)
        for _, p in ipairs(self.arcs) do
            arc(self.pos, p, 10 * fade + 2, Color(WHITE.r, WHITE.g, WHITE.b, 255 * fade))
        end
    else
        for _, ab in ipairs(self.arcs) do
            arc(ab[1], ab[2], 6, Color(BLUE.r, BLUE.g, BLUE.b, 255 * fade))
        end
        render.SetMaterial(GLOW)
        render.DrawSprite(self.pos, 40, 40, Color(BLUE.r, BLUE.g, BLUE.b, 160 * fade))
    end
end
