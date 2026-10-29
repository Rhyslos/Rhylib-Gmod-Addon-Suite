--[[
    Weapon base, client: the scope (rhylib_base includes this; it returns
    function(SWEP, env)). SWEP:Scoped() (aimFrac >= 0.8 and not Rhy's
    third person), SWEP:EffectiveAimFov(), SWEP:DrawScope() (the overlay:
    cached rings, reticle, range in metres, zoom).
]]

return function(SWEP, env)
    local function thirdPerson()
        local tp = Rhylib.ThirdPerson
        return tp and tp.Active and tp.Active() or false
    end

    function SWEP:Scoped()
        return (self.aimFrac or 0) >= 0.8 and self:HasScope() and not thirdPerson()
    end

    -- Aim zoom; a scope only zooms in first person.
    function SWEP:EffectiveAimFov()
        if self.Scope and (thirdPerson() or not self:HasScope()) then return 0.85 end
        return self.AimFov
    end

    -- Scope overlay: black outside a circle, a soft dark edge, a light
    -- lens tint, the reticle and a range readout.
    local SEG = 96
    local ringCache = {}
    local function ring(cx, cy, r1, r2, col)
        surface.SetDrawColor(col)
        draw.NoTexture()
        local key = cx .. ":" .. cy .. ":" .. r1 .. ":" .. r2
        local polys = ringCache[key]
        if not polys then
            polys = {}
            for i = 0, SEG - 1 do
                local a0, a1 = i / SEG * math.pi * 2, (i + 1) / SEG * math.pi * 2
                local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
                polys[#polys + 1] = {
                    { x = cx + c0 * r1, y = cy + s0 * r1 },
                    { x = cx + c0 * r2, y = cy + s0 * r2 },
                    { x = cx + c1 * r2, y = cy + s1 * r2 },
                    { x = cx + c1 * r1, y = cy + s1 * r1 },
                }
            end
            if table.Count(ringCache) > 32 then ringCache = {} end
            ringCache[key] = polys
        end
        for i = 1, #polys do surface.DrawPoly(polys[i]) end
    end

    local BLACK = Color(0, 0, 0, 255)
    function SWEP:DrawScope()
        local w, h = ScrW(), ScrH()
        local cx, cy = math.floor(w * 0.5), math.floor(h * 0.5)
        local r = math.floor(h * 0.45)
        local accent = (Rhylib.UI and Rhylib.UI.Colors and Rhylib.UI.Colors.accent) or Color(90, 200, 255)

        -- Lens tint, then everything outside the lens black.
        surface.SetDrawColor(40, 90, 130, 22)
        surface.DrawRect(cx - r, cy - r, r * 2, r * 2)
        surface.SetDrawColor(BLACK)
        surface.DrawRect(0, 0, cx - r + 1, h)
        surface.DrawRect(cx + r - 1, 0, w - cx - r + 1, h)
        surface.DrawRect(cx - r, 0, r * 2, cy - r + 1)
        surface.DrawRect(cx - r, cy + r - 1, r * 2, h - cy - r + 1)
        ring(cx, cy, r, r * 1.5, BLACK)
        -- Soft dark edge inside the lens.
        for i = 1, 6 do
            ring(cx, cy, r - i * r * 0.018, r - (i - 1) * r * 0.018, Color(0, 0, 0, 150 - i * 22))
        end

        -- Reticle: thick posts from the edge, thin lines to a gap, a dot.
        local thin, thick, gap = math.max(1, math.floor(h / 900)), math.max(3, math.floor(h / 260)), r * 0.06
        surface.SetDrawColor(0, 0, 0, 230)
        surface.DrawRect(cx - r, cy - thick / 2, r * 0.55, thick)
        surface.DrawRect(cx + r * 0.45, cy - thick / 2, r * 0.55, thick)
        surface.DrawRect(cx - thick / 2, cy + r * 0.45, thick, r * 0.55)
        surface.DrawRect(cx - r * 0.45, cy - thin / 2, r * 0.45 - gap, thin)
        surface.DrawRect(cx + gap, cy - thin / 2, r * 0.45 - gap, thin)
        surface.DrawRect(cx - thin / 2, cy + gap, thin, r * 0.45 - gap)
        surface.DrawRect(cx - thin / 2, cy - r, thin, r - gap)
        -- Mil ticks on the lower and side lines (drop and lead marks).
        for i = 1, 4 do
            local d = gap + i * r * 0.08
            local len = (i % 2 == 0) and r * 0.035 or r * 0.02
            surface.DrawRect(cx - len / 2, cy + d, len, thin)
            surface.DrawRect(cx + d, cy - len / 2, thin, len)
            surface.DrawRect(cx - d, cy - len / 2, thin, len)
        end
        surface.SetDrawColor(accent.r, accent.g, accent.b, 255)
        surface.DrawRect(cx - thick / 2, cy - thick / 2, thick, thick)

        -- Range to whatever is under the reticle, in metres.
        local o = self:GetOwner()
        if IsValid(o) then
            local tr = util.TraceLine({ start = o:EyePos(), endpos = o:EyePos() + o:EyeAngles():Forward() * 32768, filter = o, mask = MASK_SHOT })
            local m = tr.Hit and math.floor(tr.HitPos:Distance(tr.StartPos) * 0.01905 + 0.5) or nil
            local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(18 * h / 1080)) or "DermaDefault"
            draw.SimpleText(m and (m .. " m") or "---", font, cx + r * 0.62, cy + r * 0.62, Color(accent.r, accent.g, accent.b, 220), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("x%.1f", 1 / (self.AimFov or 1)), font, cx - r * 0.62, cy + r * 0.62, Color(accent.r, accent.g, accent.b, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end
