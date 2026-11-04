--[[
    Weapon base, client: the scope (rhylib_base includes this; it returns
    function(SWEP, env)). SWEP:Scoped() (aimFrac >= 0.8 and not Rhy's
    third person), SWEP:EffectiveAimFov(), SWEP:DrawScope() (the overlay:
    cached rings, reticle, range in metres, zoom). SWEP.ScopeStyle
    "launcher": SWEP:DrawLauncherScope() instead (a wide cut-corner window,
    black outside, compass bar, reticle, the weapon's lock-on hexagon from
    SWEP:LockHexScreen(owner) if it has one, elevation / bearing / range /
    zoom / night vision boxes, the binocular viewer's night vision).
    SWEP.ScopeNightVision: the flashlight key switches night vision while
    scoped (PlayerBindPress "weapons.scopenv", -65, before rhylib_gear's
    optics keys); Rhylib.Weapons.ScopeNV() -> on now (rhylib_gear's night
    vision draws it).
]]

-- Scope night vision (once, not per weapon class).
local W = Rhylib.Weapons
function W.ScopeNV()
    local me = LocalPlayer()
    local w = IsValid(me) and me:GetActiveWeapon()
    return IsValid(w) and w.ScopeNightVision and w.rhylibScopeNV and w.Scoped and w:Scoped() or false
end
Rhylib.Hook.Add("PlayerBindPress", "weapons.scopenv", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "impulse 100", 1, true) then return end
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w.ScopeNightVision and w.Scoped and w:Scoped()) then return end
    w.rhylibScopeNV = not w.rhylibScopeNV
    surface.PlaySound("items/flashlight1.wav")
    return true
end, -65)

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
        if self.ScopeStyle == "launcher" then return self:DrawLauncherScope() end
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

        local thin, thick, gap = math.max(1, math.floor(h / 900)), math.max(3, math.floor(h / 260)), r * 0.06
        -- Reticle: thick posts from the edge, thin lines to a gap, a dot.
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

    -- Launcher sight (ScopeStyle "launcher"): a wide window with cut
    -- corners, black outside; inside: the compass bar at the top, the
    -- reticle, the lock-on hexagon (SWEP:LockHexScreen, when the weapon has
    -- one), and the readout boxes in a black tab at the bottom (elevation,
    -- bearing, range, zoom, night vision), the binocular viewer's glass and
    -- night vision picture (rhylib_gear G.NVLayer).
    local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
    local RED = Color(225, 45, 40)
    local PANEL = Color(205, 214, 212, 235)
    local PANEL_NV = Color(170, 235, 170, 235)
    local PANEL_TEXT = Color(18, 26, 22)
    -- The window, as shares of its box (x, y), clockwise from the top left.
    local FRAME = { { 0.14, 0 }, { 0.86, 0 }, { 1, 0.21 }, { 1, 0.79 }, { 0.83, 1 }, { 0.17, 1 }, { 0, 0.79 }, { 0, 0.21 } }

    local function tri(ax, ay, bx, by, cx, cy)
        draw.NoTexture()
        surface.DrawPoly({ { x = ax, y = ay }, { x = bx, y = by }, { x = cx, y = cy } })
    end

    function SWEP:LauncherFrame()
        local w, h = ScrW(), ScrH()
        local fh = math.floor(h * 0.70)
        local fw = math.min(math.floor(fh * 1.54), w - 20)
        local x0, y0 = math.floor((w - fw) * 0.5), math.floor((h - fh) * 0.5)
        local pts = {}
        for i, p in ipairs(FRAME) do pts[i] = { x = x0 + p[1] * fw, y = y0 + p[2] * fh } end
        return pts, x0, y0, fw, fh
    end

    function SWEP:DrawLauncherScope()
        local w, h = ScrW(), ScrH()
        local s = h / 1080
        local cx, cy = math.floor(w * 0.5), math.floor(h * 0.5)
        local pts, x0, y0, fw, fh = self:LauncherFrame()
        local x1, y1 = x0 + fw, y0 + fh
        local accent = (Rhylib.UI and Rhylib.UI.Colors and Rhylib.UI.Colors.accent) or Color(90, 200, 255)
        local nv = self.rhylibScopeNV and self.ScopeNightVision and Rhylib.Gear ~= nil

        -- The glass first (black goes over it): faint tint and crawling
        -- scanlines like the binocular viewer, or its night vision picture.
        draw.NoTexture()
        local G = Rhylib.Gear
        if nv and G and G.NVLayer then
            G.NVLayer(w, h, x0, y0, x1, y1)
        else
            surface.SetDrawColor(18, 24, 30, 22)
            surface.DrawRect(x0, y0, fw, fh)
            local step = math.max(3, math.floor(4 * s))
            local off = math.floor(RealTime() * 30) % step
            surface.SetDrawColor(0, 0, 0, 34)
            for y = y0 + off, y1, step do surface.DrawRect(x0, y, fw, math.max(1, math.floor(step / 2))) end
        end
        -- Black outside the window: round the box, then the cut corners,
        -- then (as on the binocular viewer) a band at the top middle for the
        -- compass and a tab at the bottom for the readouts.
        draw.NoTexture()
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, w, y0 + 1)
        surface.DrawRect(0, y1 - 1, w, h - y1 + 1)
        surface.DrawRect(0, y0, x0 + 1, fh)
        surface.DrawRect(x1 - 1, y0, w - x1 + 1, fh)
        tri(x0 - 1, y0 - 1, pts[1].x, pts[1].y - 1, pts[8].x - 1, pts[8].y)
        tri(pts[2].x, pts[2].y - 1, x1 + 1, y0 - 1, pts[3].x + 1, pts[3].y)
        tri(pts[4].x + 1, pts[4].y, x1 + 1, y1 + 1, pts[5].x, pts[5].y + 1)
        tri(pts[7].x - 1, pts[7].y, pts[6].x, pts[6].y + 1, x0 - 1, y1 + 1)
        local cxf = x0 + fw * 0.5
        local tm1, tm2, dh, dd = cxf - fw * 0.3, cxf + fw * 0.3, math.floor(48 * s), math.floor(24 * s)
        surface.DrawPoly({ { x = tm1 - dd, y = y0 - 1 }, { x = tm2 + dd, y = y0 - 1 }, { x = tm2, y = y0 + dh }, { x = tm1, y = y0 + dh } })
        local bh = math.floor(58 * s)
        local tab = bh + math.floor(40 * s)
        local tb1, tb2 = fw * 0.26, fw * 0.22
        surface.DrawPoly({ { x = cxf - tb2, y = y1 - tab }, { x = cxf + tb2, y = y1 - tab }, { x = cxf + tb1, y = y1 + 1 }, { x = cxf - tb1, y = y1 + 1 } })
        -- The edge, round the window (with the band and the tab).
        local edge = {
            pts[1], { x = tm1 - dd, y = y0 }, { x = tm1, y = y0 + dh }, { x = tm2, y = y0 + dh }, { x = tm2 + dd, y = y0 },
            pts[2], pts[3], pts[4], pts[5], { x = cxf + tb1, y = y1 }, { x = cxf + tb2, y = y1 - tab },
            { x = cxf - tb2, y = y1 - tab }, { x = cxf - tb1, y = y1 }, pts[6], pts[7], pts[8],
        }
        surface.SetDrawColor(nv and 120 or 170, nv and 200 or 176, nv and 120 or 180, 60)
        for i = 1, #edge do
            local a, b = edge[i], edge[i % #edge + 1]
            surface.DrawLine(a.x, a.y, b.x, b.y)
        end

        local o = self:GetOwner()
        if not IsValid(o) then return end
        local ang = o:EyeAngles()
        local heading = (90 - ang.y) % 360

        -- Compass bar on the black band at the top (letters just inside the window).
        local bx0, bx1 = tm1 + dd, tm2 - dd
        local yBase = y0 + dh - 6 * s
        local span = 40
        local pxPerDeg = (bx1 - bx0) / span
        surface.SetDrawColor(RED)
        local first = math.ceil((heading - span / 2) / 2.5) * 2.5
        for deg = first, heading + span / 2, 2.5 do
            local x = cx + (deg - heading) * pxPerDeg
            local major = math.abs(deg % 10) < 0.01
            local len = (major and 22 or 13) * s
            surface.DrawRect(math.floor(x - 1), yBase - len, math.max(2, math.floor(3 * s)), len)
        end
        local cf = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(15 * s), 800) or "DermaDefaultBold"
        for deg = math.ceil((heading - span / 2) / 45) * 45, heading + span / 2, 45 do
            local x = cx + (deg - heading) * pxPerDeg
            draw.SimpleText(COMPASS[(math.floor(deg / 45 + 0.5) % 8) + 1], cf, x, yBase + 22 * s, RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        surface.DrawRect(bx0 - 2 * s, yBase - 30 * s, 4 * s, 30 * s)
        surface.DrawRect(bx1 - 2 * s, yBase - 30 * s, 4 * s, 30 * s)
        local m = 12 * s
        tri(cx, yBase - 30 * s - m * 1.8, cx + m, yBase - 30 * s, cx - m, yBase - 30 * s)

        -- Lock-on hexagon (screen points of the weapon's lock area).
        local hex = self.LockHexScreen and self:LockHexScreen(o)
        local hx0, hx1, hyTop = cx - fw * 0.2, cx + fw * 0.2, cy - fh * 0.3
        if hex then
            local lockOn = self.LockOn and self:LockOn()
            local t = lockOn and self.GetLockTarget and self:GetLockTarget()
            local locked = IsValid(t) and self.LockedTarget and self:LockedTarget()
            local col = locked and Color(255, 70, 60, 230) or (IsValid(t) and Color(255, 190, 60, 230))
                or Color(accent.r, accent.g, accent.b, lockOn and 210 or 70)
            surface.SetDrawColor(col)
            for i = 1, #hex do
                local a, b = hex[i], hex[i % #hex + 1]
                surface.DrawLine(a.x, a.y, b.x, b.y)
                surface.DrawLine(a.x, a.y + 1, b.x, b.y + 1)
            end
            hx0, hx1, hyTop = hex[6].x, hex[2].x, hex[1].y
        end

        -- Reticle: thin lines from the edges to the hexagon, thicker posts at the edges.
        local thin, thick = math.max(1, math.floor(h / 900)), math.max(3, math.floor(h / 300))
        surface.SetDrawColor(0, 0, 0, 230)
        surface.DrawRect(x0, cy - thin / 2, hx0 - x0 - 6 * s, thin)
        surface.DrawRect(hx1 + 6 * s, cy - thin / 2, x1 - hx1 - 6 * s, thin)
        surface.DrawRect(cx - thin / 2, yBase + 34 * s, thin, hyTop - yBase - 40 * s)
        surface.DrawRect(x0, cy - thick / 2, fw * 0.12, thick)
        surface.DrawRect(x1 - fw * 0.12, cy - thick / 2, fw * 0.12, thick)
        surface.SetDrawColor(accent.r, accent.g, accent.b, 255)
        surface.DrawRect(cx - thick / 2, cy - thick / 2, thick, thick)

        local tr = util.TraceLine({ start = o:EyePos(), endpos = o:EyePos() + ang:Forward() * 32768, filter = o, mask = MASK_SHOT })
        local metres = tr.Hit and not tr.HitSky and math.floor(tr.HitPos:Distance(tr.StartPos) * 0.01905 + 0.5) or nil

        -- Readout boxes in the bottom tab.
        local panel = nv and PANEL_NV or PANEL
        local yTop = y1 - bh - 18 * s
        local left, right = cxf - tb2 + 14 * s, cxf + tb2 - 14 * s
        local total = right - left
        local lw = total * 0.62
        local cells = {
            { string.format("%+03d", math.floor(-ang.p + 0.5)), "ELV" },
            { string.format("%03d", math.floor(heading + 0.5) % 360), "BRG" },
            { metres and string.format("%04d", math.min(metres, 9999)) or "----", "RNG M" },
        }
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(30 * s), 800) or "DermaLarge"
        local small = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(13 * s), 700) or "DermaDefault"
        local cw = lw / #cells
        for i, c in ipairs(cells) do
            local x = left + (i - 1) * cw
            surface.SetDrawColor(panel.r, panel.g, panel.b, panel.a - (i % 2 == 0 and 25 or 0))
            surface.DrawRect(x, yTop, cw - 2 * s, bh)
            draw.SimpleText(c[1], font, x + cw * 0.5, yTop + bh * 0.42, PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(c[2], small, x + cw * 0.5, yTop + bh - 8 * s, PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        local rx = left + lw + 12 * s
        local rw = right - rx
        local rh = math.floor((bh - 3 * s) / 2)
        surface.SetDrawColor(panel)
        surface.DrawRect(rx, yTop, rw, rh)
        surface.DrawRect(rx, yTop + rh + 3 * s, rw, rh)
        local mid = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(math.floor(15 * s), 800) or "DermaDefaultBold"
        draw.SimpleText(string.format("ZOOM x%.1f", 1 / (self.AimFov or 1)), mid, rx + rw * 0.5, yTop + rh * 0.5, PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local nvText
        if not (self.ScopeNightVision and Rhylib.Gear) then nvText = "NV ---"
        else
            local key = input.LookupBinding("impulse 100")
            nvText = (nv and "NV ON" or "NV OFF") .. " · " .. string.upper(key or "F")
        end
        draw.SimpleText(nvText, mid, rx + rw * 0.5, yTop + rh * 1.5 + 3 * s, PANEL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
