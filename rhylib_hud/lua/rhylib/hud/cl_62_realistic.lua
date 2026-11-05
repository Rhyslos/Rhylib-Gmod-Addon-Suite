--[[
    "Realistic" first-person HUD (client): the clone helmet as seen from
    inside in the show. Picked like the other layouts (layout "real",
    Settings > HUD > First-person HUD, or rhylib_hud_layout real).

    The helmet: a visor window with an arched top, the cheek pads coming
    in from the screen sides in a straight slope to the chin opening, and
    the chin opening narrowing a little toward the bottom.

    On the visor:
      top        a broken white rim along the arch, a thin line under it
                 and the heading ticks (N, NE, ...), turning as you turn
      sides      the show's side details: a notched block at the screen
                 edge, a two-part curved blade bracket and a curved ladder
                 of bars: armour (blue) on the left, health (red; yellow
                 sim health with a training gun) on the right, filled from
                 the bottom, the number above. Client convar
                 rhylib_hud_real_tall 1 stretches them over the whole side
                 of the visor (more bars), 0 keeps them compact
      cheek edges  stamina, from the chin outward, on both cheeks
      chin       two pillars: the left stack counts spare magazines, the
                 right stack the rounds left in the magazine (red when low)
      right cheek  mirrors the left: four fire-mode squares by the chin
                 edge (the mode in use amber, a charged shot / flare
                 toggle that's on blue, SAFE), an ammo dial where the
                 radar is (30 segments for the magazine, the cell inside,
                 the count in the middle), and in the room where the chat
                 is (to the screen edge, no background) weapon · mode,
                 spare magazine pips and the cell / spare line over the
                 hotbar: one row of tall tiles with their counts when they
                 fit (wide screens, or 4 slots), else four columns (4, 6
                 with a backpack, 7 with the staff tool slot). Client convar
                 rhylib_hud_real_strip 1 swaps it for a simpler look: the
                 big count with the weapon lines, a row of round ticks,
                 the cell bar, a slanted bar by the chin and one row of
                 slanted tiles under a line naming their groups
      left cheek   the chat, the radio compass and the radio squares
                 (rhylib_chat and rhylib_radio place themselves with
                 HUD.RealGeo / HUD.RealCheekY / HUD.RealChinX)

    Sizes come from a 1600 x 900 design scaled by the screen height
    (s = ScrH / 900); everything along the sides keeps to the screen
    edges, the chin parts to the middle.

    Public: HUD.RealisticActive(), HUD.RealGeo(), HUD.RealCheekY(x, side),
    HUD.RealCheekX(y, side), HUD.RealChinX(y, side), HUD.RealShellTris(),
    HUD.DrawRealHotbar(entries, active, alpha) (called by
    HUD.DrawVisorLayout in cl_42_layouts.lua).
]]

local HUD = Rhylib.HUD
local UI = Rhylib.UI

local tallVar = CreateClientConVar("rhylib_hud_real_tall", "0", true, false,
    "Realistic HUD: stretch the side ladders over the whole side of the visor (0/1)")
local stripVar = CreateClientConVar("rhylib_hud_real_strip", "0", true, false,
    "Realistic HUD: the simple right cheek (round ticks, one row of hotbar tiles) (0/1)")

local INK = Color(232, 241, 247)
local COL_SHELL = Color(12, 14, 16, 250)
local COL_EDGE_DARK = Color(0, 0, 0, 230)
local COL_EDGE_LIGHT = Color(170, 176, 180, 120)
local COL_EMPTY = Color(255, 255, 255, 34)
local COL_LOW = Color(239, 159, 39)
local COL_EXHAUSTED = Color(226, 75, 74)

-- HUD.RealisticActive(): true while the visor shows with the "real" layout.
function HUD.RealisticActive()
    if not (HUD.VisorActive and HUD.VisorActive()) then return false end
    return HUD.VisorLayout and HUD.VisorLayout() == "real" or false
end

--------------------------------------------------------------------------
-- Shapes
--------------------------------------------------------------------------

-- One triangle with the winding surface.DrawPoly needs.
local function tri(ax, ay, bx, by, cx, cy)
    if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0 then
        bx, by, cx, cy = cx, cy, bx, by
    end
    return { { x = ax, y = ay }, { x = bx, y = by }, { x = cx, y = cy } }
end

-- A convex polygon ({ {x, y}, ... }) as DrawPoly vertices, wound right.
local function poly(pts)
    local area = 0
    for i = 1, #pts do
        local p, q = pts[i], pts[i % #pts + 1]
        area = area + (p[1] * q[2] - q[1] * p[2])
    end
    local out = {}
    if area >= 0 then
        for i = 1, #pts do out[i] = { x = pts[i][1], y = pts[i][2] } end
    else
        for i = #pts, 1, -1 do out[#out + 1] = { x = pts[i][1], y = pts[i][2] } end
    end
    return out
end

-- A straight band from (x1, y1) to (x2, y2), w thick, as a quad.
local function band(x1, y1, x2, y2, w)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    local nx, ny = -dy / len * w * 0.5, dx / len * w * 0.5
    return poly({ { x1 + nx, y1 + ny }, { x2 + nx, y2 + ny }, { x2 - nx, y2 - ny }, { x1 - nx, y1 - ny } })
end

-- A simple polygon (concave allowed) cut into triangles (ear clipping).
local function triangulate(pts)
    local n = #pts
    local idx = {}
    for i = 1, n do idx[i] = i end
    local area = 0
    for i = 1, n do
        local p, q = pts[i], pts[i % n + 1]
        area = area + (p[1] * q[2] - q[1] * p[2])
    end
    local sign = area >= 0 and 1 or -1
    local function cross(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) end
    local function inside(p, a, b, c)
        local d1, d2, d3 = cross(a, b, p) * sign, cross(b, c, p) * sign, cross(c, a, p) * sign
        return d1 >= 0 and d2 >= 0 and d3 >= 0
    end
    local out = {}
    local guard = 0
    while #idx > 3 and guard < 1000 do
        guard = guard + 1
        local cut = false
        for k = 1, #idx do
            local ia, ib, ic = idx[(k - 2) % #idx + 1], idx[k], idx[k % #idx + 1]
            local a, b, c = pts[ia], pts[ib], pts[ic]
            if cross(a, b, c) * sign > 0 then
                local ear = true
                for _, j in ipairs(idx) do
                    if j ~= ia and j ~= ib and j ~= ic and inside(pts[j], a, b, c) then ear = false break end
                end
                if ear then
                    out[#out + 1] = tri(a[1], a[2], b[1], b[2], c[1], c[2])
                    table.remove(idx, k)
                    cut = true
                    break
                end
            end
        end
        if not cut then break end
    end
    if #idx == 3 then
        local a, b, c = pts[idx[1]], pts[idx[2]], pts[idx[3]]
        out[#out + 1] = tri(a[1], a[2], b[1], b[2], c[1], c[2])
    end
    return out
end

local function qb(p0, p1, p2, t)
    local u = 1 - t
    return u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1], u * u * p0[2] + 2 * u * t * p1[2] + t * t * p2[2]
end

-- Appends a quadratic curve's points (t > 0) to list.
local function curveTo(list, p0, p1, p2, steps)
    for i = 1, steps do
        local x, y = qb(p0, p1, p2, i / steps)
        list[#list + 1] = { x, y }
    end
end

--------------------------------------------------------------------------
-- Geometry (cached per screen size and the tall setting)
--------------------------------------------------------------------------

-- The side details in design units (left side; the right side mirrors).
local function sideShapes()
    local shapes = {}
    shapes[#shapes + 1] = { { 15, 295 }, { 36, 293 }, { 34, 303 }, { 13, 304 } }
    local block = { { 10, 310 }, { 45, 311 } }
    curveTo(block, { 45, 311 }, { 42, 345 }, { 44, 378 }, 6)
    block[#block + 1] = { 8, 374 }
    curveTo(block, { 8, 374 }, { 1, 342 }, { 10, 310 }, 6)
    table.remove(block)   -- (the last point is the first one again)
    shapes[#shapes + 1] = block
    shapes[#shapes + 1] = { { 13, 381 }, { 35, 388 }, { 34, 396 }, { 11, 389 } }
    local top = { { 127, 261 }, { 183, 254 } }
    curveTo(top, { 183, 254 }, { 160, 294 }, { 154, 350 }, 10)
    curveTo(top, { 154, 350 }, { 143, 329 }, { 139, 308 }, 6)
    top[#top + 1] = { 123, 305 }
    shapes[#shapes + 1] = top
    local bot = { { 150, 423 } }
    curveTo(bot, { 150, 423 }, { 161, 446 }, { 162, 474 }, 8)
    bot[#bot + 1] = { 139, 478 }
    curveTo(bot, { 139, 478 }, { 141, 447 }, { 150, 423 }, 8)
    table.remove(bot)
    shapes[#shapes + 1] = bot
    return shapes
end

-- The thin lines by the side details: { x1, y1, x2, y2, alpha share }.
local SIDE_LINES = {
    { 0, 226, 250, 222, 0.45 }, { 0, 240, 230, 236, 0.45 },
    { 0, 262, 133, 260, 0.8 }, { 0, 277, 117, 276, 0.8 },
    { 0, 414, 123, 446, 0.8 }, { 0, 428, 150, 463, 0.8 },
}

-- The rim's dash pattern along the design's 1600 width (on, off, ...).
local RIM_DASH = { 220, 14, 60, 14, 380, 14, 40, 30 }

local geo = { key = "" }

-- The left chin edge's x at height y, and the left helmet edge's y at x
-- (left-side screen x; mirror with W - x for the right side).
local function chinAt(g, y)
    if y <= g.cornerY then return g.cornerX end
    return g.cornerX + (g.bottomX - g.cornerX) * math.min(1, (y - g.cornerY) / math.max(g.H - g.cornerY, 1))
end

local function cheekAt(g, x)
    if x <= 0 then return g.edgeY end
    if x <= g.cornerX then return g.edgeY + (g.cornerY - g.edgeY) * x / g.cornerX end
    if x >= g.bottomX then return g.H end
    return g.cornerY + (g.H - g.cornerY) * (x - g.cornerX) / (g.bottomX - g.cornerX)
end

-- A ring segment from angle a0 to a1 (degrees, screen: 0 = right, 90 =
-- down) between radius r0 and r1, as a quad.
local function arcQuad(cx, cy, r0, r1, a0, a1)
    local c0, s0 = math.cos(math.rad(a0)), math.sin(math.rad(a0))
    local c1, s1 = math.cos(math.rad(a1)), math.sin(math.rad(a1))
    return poly({ { cx + c0 * r1, cy + s0 * r1 }, { cx + c1 * r1, cy + s1 * r1 },
        { cx + c1 * r0, cy + s1 * r0 }, { cx + c0 * r0, cy + s0 * r0 } })
end

-- The right cheek (screen px): R.modes (four squares by the chin edge,
-- each { poly, tx, ty }), the ammo dial (x, y, r, bg, rim, ring, cell) and
-- the panel (x0, x1, yb: the room for the weapon lines and
-- hotbar); for the simple look R.frame / R.ticks.
local function buildRight(g)
    local W, H, s = g.W, g.H, g.s
    local R = {}
    local function xl(y) return W - chinAt(g, y) + 8 * s end
    local function xr(y) return xl(y) + 38 * s end
    R.modes = {}
    local rows = { { 724, 763 }, { 768, 798 }, { 803, 833 }, { 838, 868 } }
    for i, r in ipairs(rows) do
        local y0, y1 = r[1] * s, r[2] * s
        local t0, t1 = y0, y0
        if i == 1 then   -- (cut to the cheek pad's slope)
            t0 = cheekAt(g, W - xl(y0)) + 5 * s
            t1 = cheekAt(g, W - xr(y0)) + 5 * s
        end
        local my = (math.max(t0, t1) + y1) * 0.5
        R.modes[i] = { poly = poly({ { xl(t0), t0 }, { xr(t1), t1 }, { xr(y1), y1 }, { xl(y1), y1 } }),
            tx = (xl(my) + xr(my)) * 0.5, ty = my }
    end
    -- Ammo dial where the radar is on the left.
    -- (on narrow screens it shrinks / moves so the panel keeps 150 px)
    local d = { x = W - (g.cornerX - 120 * s), y = 795 * s, r = 75 * s }
    local lo = xr(d.y) + 6 * s
    local hi = W - 32 * s - 150 * s - 11 * s
    if hi - lo < 2 * d.r then d.r = math.max((hi - lo) * 0.5, 30 * s) end
    d.x = math.max(math.min(d.x, hi - d.r), lo + d.r)
    d.k = d.r / (75 * s)
    local k = d.k
    local bg = {}
    for i = 0, 39 do
        local a = math.rad(i * 9)
        bg[#bg + 1] = { d.x + math.cos(a) * d.r, d.y + math.sin(a) * d.r }
    end
    d.bg = poly(bg)
    d.rim, d.ring, d.cell = {}, {}, {}
    for i = 0, 47 do d.rim[#d.rim + 1] = arcQuad(d.x, d.y, d.r - 2 * s, d.r, i * 7.5, i * 7.5 + 7.5) end
    for i = 0, 29 do
        local a0 = 120 + i * 10 + 1.2
        d.ring[#d.ring + 1] = arcQuad(d.x, d.y, 62 * s * k, 71 * s * k, a0, a0 + 7.6)
    end
    for i = 0, 59 do d.cell[#d.cell + 1] = arcQuad(d.x, d.y, 53 * s * k, 57 * s * k, 120 + i * 5, 125 + i * 5) end
    R.dial = d
    -- Panel where the chat is on the left (nothing drawn: just its room).
    local p = { x1 = W - 32 * s, yb = 870 * s }
    p.x0 = d.x + d.r + 11 * s     -- (as the chat on the left: all the room to the edge)
    R.panel = p
    -- Simple look: a slanted bar by the chin with five ticks.
    local cx = W * 0.5
    local function X(x) return cx + (x - 800) * s end
    R.frame = poly({ { X(1058), 742 * s }, { X(1070), 742 * s }, { X(1050), 880 * s }, { X(1038), 880 * s } })
    R.ticks = {}
    for i = 0, 4 do
        local y = 748 + i * 9
        local x = 1070 - 20 * (y - 742) / 138
        R.ticks[#R.ticks + 1] = poly({ { X(x), y * s }, { X(x + 26), y * s }, { X(x + 25), (y + 4) * s }, { X(x - 1), (y + 4) * s } })
    end
    R.tickRight = X(1096)
    R.frameX = function(y) return X(1070 - 20 * (y / s - 742) / 138) end
    return R
end

local function build(W, H, tall)
    local s = H / 900
    local g = { key = W .. "x" .. H .. (tall and "t" or "c"), W = W, H = H, s = s, tall = tall }
    g.edgeY = 612 * s
    g.cornerY = 732 * s
    g.cornerX = W * 0.5 - 240 * s        -- left chin corner (screen x)
    g.bottomX = W * 0.5 - 192 * s        -- left chin edge at the screen bottom

    local function rimY(x, a, c)
        local t = x / W
        return ((1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * a) * s
    end
    g.rimY = function(x) return rimY(x, 110, 40) end
    g.baseY = function(x) return rimY(x, 126, 56) end

    -- Shell: the brow above the arch, the two cheek pads.
    local tris, edges = {}, {}
    local arch = {}
    for i = 0, 48 do
        local x = W * i / 48
        arch[#arch + 1] = { x, g.rimY(x) }
    end
    local browPts = { { 0, 0 } }
    for _, p in ipairs(arch) do browPts[#browPts + 1] = p end
    browPts[#browPts + 1] = { W, 0 }
    for i = 1, #browPts - 1 do
        local p, q = browPts[i], browPts[i + 1]
        tris[#tris + 1] = tri(W * 0.5, 0, p[1], p[2], q[1], q[2])
    end
    edges[#edges + 1] = arch
    for _, side in ipairs({ -1, 1 }) do
        local function sx(x) return side < 0 and x or W - x end
        local e = { sx(0), g.edgeY }
        local c = { sx(g.cornerX), g.cornerY }
        local b = { sx(g.bottomX), H }
        local o = { sx(0), H }
        tris[#tris + 1] = tri(e[1], e[2], c[1], c[2], o[1], o[2])
        tris[#tris + 1] = tri(c[1], c[2], b[1], b[2], o[1], o[2])
        edges[#edges + 1] = { e, c, b }
    end
    -- Edge bleed (as cl_60_visor.lua): edges pushed past the screen so a
    -- moving HUD (rhylib_core cl_66_motion.lua) opens no gap.
    local bleed = math.ceil(16 * H / 1080)
    local function push(x, y)
        if x <= 0.5 then x = -bleed elseif x >= W - 0.5 then x = W + bleed end
        if y <= 0.5 then y = -bleed elseif y >= H - 0.5 then y = H + bleed end
        return x, y
    end
    for _, t in ipairs(tris) do
        for _, v in ipairs(t) do v.x, v.y = push(v.x, v.y) end
    end
    g.tris, g.edges = tris, edges

    -- Rim dashes (thick) and the thin line under them.
    local rim = {}
    local N = 120
    local pat, pi, left = RIM_DASH, 1, RIM_DASH[1] * W / 1600
    local on = true
    local px, py = 0, g.rimY(0)
    for i = 1, N do
        local x = W * i / N
        local y = g.rimY(x)
        local seg = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        if on then
            local q = band(px, py, x, y, 3 * s)
            if q then rim[#rim + 1] = q end
        end
        left = left - seg
        while left <= 0 do
            pi = pi % #pat + 1
            left = left + pat[pi] * W / 1600
            on = not on
        end
        px, py = x, y
    end
    g.rim = rim
    local base = {}
    for i = 0, 64 do
        local x = W * i / 64
        base[#base + 1] = { x, g.baseY(x) }
    end
    g.base = base

    -- Side details and ladders.
    local function ty(y) return tall and (y * 1.7 - 227.4) or y end
    g.side = {}
    g.ladder = { [-1] = {}, [1] = {} }
    local n = tall and 18 or 11
    local y0 = tall and 204 or 254
    g.ladderN = n
    g.numberY = (tall and 196 or 246) * s
    for _, side in ipairs({ -1, 1 }) do
        local function X(x) return side < 0 and x * s or W - x * s end
        for _, shape in ipairs(sideShapes()) do
            local pts = {}
            for _, p in ipairs(shape) do pts[#pts + 1] = { X(p[1]), ty(p[2]) * s } end
            for _, t in ipairs(triangulate(pts)) do g.side[#g.side + 1] = { t = t } end
        end
        for _, l in ipairs(SIDE_LINES) do
            local q = band(X(l[1]), ty(l[2]) * s, X(l[3]), ty(l[4]) * s, 3 * s)
            if q then g.side[#g.side + 1] = { t = q, a = l[5] } end
        end
        for i = 0, n - 1 do
            local t = i / (n - 1)
            local r = 245 - 33 * (1 - (1 - t) * (1 - t))
            local len = (i == 0 or i == n - 1) and 42 or (i % 2 == 0 and 31 or 20)
            local ya, yb = (y0 + i * 20.4) * s, (y0 + i * 20.4 + 9.5) * s
            g.ladder[side][i + 1] = poly({ { X(r - len + 3), ya }, { X(r + 3), ya }, { X(r), yb }, { X(r - len), yb } })
        end
    end

    -- Chin pillars: six stacked bars on top of a long bar, each side.
    g.stack = { [-1] = {}, [1] = {} }
    g.pillar = {}
    local cx = W * 0.5
    for _, side in ipairs({ -1, 1 }) do
        local function X(x) return cx + (side < 0 and (x - 800) or (800 - x)) * s end
        for i = 0, 5 do
            local top = 752 + i * 12
            local bot = top + 7
            local function px(y) return 612 + 20 * (y - 752) / 74 end
            g.stack[side][i + 1] = poly({ { X(px(top) - 30), top * s }, { X(px(top) + 14), top * s },
                { X(px(bot) + 14), bot * s }, { X(px(bot) - 30), bot * s } })
        end
        g.pillar[#g.pillar + 1] = poly({ { X(618), 826 * s }, { X(630), 826 * s }, { X(650), H }, { X(636), H } })
    end
    -- Stamina tracks along the cheek edges (the fill is drawn per frame).
    g.stamOff = 4 * s
    g.stamTrack = {}
    for _, side in ipairs({ -1, 1 }) do
        local function X(x) return side < 0 and x or W - x end
        local q = band(X(0), g.edgeY - g.stamOff, X(g.cornerX), g.cornerY - g.stamOff, 3 * s)
        if q then g.stamTrack[#g.stamTrack + 1] = q end
    end
    g.right = buildRight(g)
    geo = g   -- (only once it's complete)
    return g
end

-- HUD.RealGeo(): the cached layout numbers (screen px): s (design scale),
-- edgeY / cornerY (cheek at the screen side / chin corner height), cornerX
-- / bottomX (left chin edge at the corner / at the bottom). Read only.
function HUD.RealGeo()
    local W, H = ScrW(), ScrH()
    local tall = tallVar:GetBool()
    if geo.W ~= W or geo.H ~= H or geo.tall ~= tall then build(W, H, tall) end
    return geo
end

-- HUD.RealChinX(y, side): screen x of the chin opening's edge at height y
-- (above the corner: the corner's x). side -1 left, 1 right.
function HUD.RealChinX(y, side)
    local g = HUD.RealGeo()
    local x = chinAt(g, y)
    return side < 0 and x or g.W - x
end

-- HUD.RealCheekY(x, side): screen y of the helmet's edge (cheek pad, then
-- chin edge) at screen x; past the chin edge the bottom of the screen.
function HUD.RealCheekY(x, side)
    local g = HUD.RealGeo()
    if side > 0 then x = g.W - x end
    return cheekAt(g, x)
end

-- HUD.RealCheekX(y, side): screen x of the helmet's edge at height y
-- (above the cheek: the screen side).
function HUD.RealCheekX(y, side)
    local g = HUD.RealGeo()
    local x
    if y <= g.edgeY then
        x = 0
    elseif y <= g.cornerY then
        x = g.cornerX * (y - g.edgeY) / (g.cornerY - g.edgeY)
    else
        return HUD.RealChinX(y, side)
    end
    return side < 0 and x or g.W - x
end

-- HUD.RealShellTris(): the helmet's triangles (brow and cheek pads), for
-- masks (HUD.VisorShellTris returns these while the realistic HUD shows).
function HUD.RealShellTris()
    return HUD.RealGeo().tris
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function setCol(c, a)
    surface.SetDrawColor(c.r, c.g, c.b, a or c.a or 255)
end

-- Font size for a design pixel size (UI.Font sizes are 1080p pixels).
local function F(px) return math.floor(px * 1.2 + 0.5) end

local tcol = Color(0, 0, 0)
local function text(str, px, weight, x, y, col, a, ax, ay)
    tcol.r, tcol.g, tcol.b, tcol.a = col.r, col.g, col.b, a or col.a or 255
    return draw.SimpleText(str, UI.Font(F(px), weight), x, y, tcol, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end

local fitCache, fitCount = {}, 0
local function fit(str, px, weight, maxW)
    local key = str .. "|" .. px .. "|" .. weight .. "|" .. math.floor(maxW)
    local hit = fitCache[key]
    if hit then return hit end
    if fitCount > 256 then fitCache, fitCount = {}, 0 end
    local out = str
    surface.SetFont(UI.Font(F(px), weight))
    if surface.GetTextSize(out) > maxW then
        -- (whole characters: names can hold æøå or ·)
        local chars = {}
        for _, c in utf8.codes(out) do chars[#chars + 1] = utf8.char(c) end
        while #chars > 1 and surface.GetTextSize(table.concat(chars) .. "…") > maxW do chars[#chars] = nil end
        out = table.concat(chars) .. "…"
    end
    fitCache[key] = out
    fitCount = fitCount + 1
    return out
end

local COMPASS = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }

local function drawCompass(g)
    local s, W = g.s, g.W
    local yaw = EyeAngles().y   -- (the view's: freelook turns it too)
    local heading = (90 - yaw) % 360          -- (north is +y, as on the radio compass)
    local font = UI.Font(F(15), 500)
    for a = 0, 345, 15 do
        local rel = ((a - heading + 540) % 360) - 180
        if math.abs(rel) <= 60 then
            local x = W * 0.5 + rel * 5 * s
            local y = g.baseY(x)
            local alpha = 255 * (1 - math.abs(rel) / 75)
            local major = a % 45 == 0
            setCol(INK, alpha)
            surface.DrawRect(math.floor(x - s), math.floor(y), math.max(2, math.floor(2 * s)), math.floor((major and 14 or 7) * s))
            if major then
                tcol.r, tcol.g, tcol.b, tcol.a = INK.r, INK.g, INK.b, alpha
                draw.SimpleText(COMPASS[a], font, x, y + 32 * s, tcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            end
        end
    end
end

local function drawLadder(g, side, frac, col)
    local n = g.ladderN
    local lit = math.Round(math.Clamp(frac, 0, 1) * n)
    for i, q in ipairs(g.ladder[side]) do
        if n - i < lit then setCol(col, 240) else setCol(COL_EMPTY) end
        surface.DrawPoly(q)
    end
end

local stamQuad = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function drawStamina(g)
    local S = Rhylib.Stamina
    if not (S and S.Frac) then return end   -- (no rhylib_stamina: no line)
    local ply = LocalPlayer()
    local frac = math.Clamp(S.Frac(ply), 0, 1)
    local col = INK
    local a = 230
    if S and S.Exhausted and S.Exhausted(ply) then
        col = COL_EXHAUSTED
    elseif frac <= 0.2 then
        col = COL_LOW
        a = a * (0.65 + 0.35 * math.cos(RealTime() * 7))
    end
    local s = g.s
    local off = g.stamOff     -- (just inside the visor, above the pad's edge)
    setCol(INK, 46)
    for _, q in ipairs(g.stamTrack) do surface.DrawPoly(q) end
    if frac <= 0.005 then return end
    -- The fill: from the chin corner out along the edge, 3 * s thick
    -- (straight up/down offsets: the slope is gentle).
    local h = 1.5 * s
    local x0, y0 = g.cornerX, g.cornerY - off
    local x1, y1 = g.cornerX * (1 - frac), g.cornerY - off - (g.cornerY - g.edgeY) * frac
    setCol(col, a)
    for _, side in ipairs({ -1, 1 }) do
        local ax, bx = x1, x0
        if side > 0 then ax, bx = g.W - x0, g.W - x1 end
        local ay, by = side < 0 and y1 or y0, side < 0 and y0 or y1
        local q = stamQuad
        q[1].x, q[1].y = ax, ay - h
        q[2].x, q[2].y = bx, by - h
        q[3].x, q[3].y = bx, by + h
        q[4].x, q[4].y = ax, ay + h
        surface.DrawPoly(q)
    end
end

--------------------------------------------------------------------------
-- Right cheek: weapon, fire modes, rounds (two looks, rhylib_hud_real_strip)
--------------------------------------------------------------------------

local COL_MODE = Color(240, 166, 74)
local COL_DARK = Color(6, 7, 10)

-- Short labels for the fire-mode squares.
local MODE_SHORT = {
    semi = "SEMI", auto = "AUTO", burst = "BRST", dual = "DUAL", sidearm = "SIDE", stun = "STUN",
    grapple = "GRPL", zipline = "ZIP", hook = "HOOK", lockon = "LOCK", charge = "CHRG", flare = "FLR",
}

local function short(name)
    if not name or name == "" then return "" end
    return MODE_SHORT[name] or string.upper(string.sub(name, 1, 4))
end

-- The three rows above SAFE: the weapon's modes (a window round the
-- current one when there are more) and its toggles (charged shot, flare)
-- last. { label, on, toggle }; asked again every quarter second.
local modeCache = { at = 0, list = {} }
local function fireModes(wep)
    local now = RealTime()
    if modeCache.wep == wep and now < modeCache.at then return modeCache.list end
    local list = {}
    if IsValid(wep) and wep.ModeWheel then
        local modes, toggles, cur = {}, {}, 1
        for _, e in ipairs(wep:ModeWheel() or {}) do
            if e.toggle then
                toggles[#toggles + 1] = { label = short(e.toggle), on = e.on, toggle = true }
            else
                local name = e.slot and wep.ModeNameAt and wep:ModeNameAt(e.slot) or nil
                modes[#modes + 1] = { label = name and short(name) or string.upper(string.sub(e.label or "", 1, 4)), on = e.current }
                if e.current then cur = #modes end
            end
        end
        local room = math.max(1, 3 - #toggles)
        local first = math.Clamp(cur - 1, 1, math.max(1, #modes - room + 1))
        for i = first, math.min(#modes, first + room - 1) do list[#list + 1] = modes[i] end
        for i = 1, math.min(#toggles, 3 - #list) do list[#list + 1] = toggles[i] end
    end
    modeCache.wep, modeCache.at, modeCache.list = wep, now + 0.25, list
    return list
end

-- The round count's colour: amber at a quarter, red when empty.
local function ammoColour(ai)
    local C = HUD.Colors
    if not (ai and ai.clip and ai.maxClip and ai.maxClip > 0) then return INK end
    if ai.clip == 0 then return C.bad end
    if ai.clip / ai.maxClip <= 0.25 then return C.fuel end
    return INK
end

-- Spare magazines (whole magazines for guns that count rounds), up to 6.
local function spareMags(ai)
    local spare = ai and ai.spare or 0
    if ai and not ai.magShort and ai.maxClip and ai.maxClip > 0 then spare = spare / ai.maxClip end
    return math.Clamp(math.floor(spare), 0, 6)
end

-- "CELL 73% · 2 SPARE", "4 MED MAGS", plus the other ammo types carried.
local function ammoLine(ai)
    local info
    if ai.cell then
        info = "CELL " .. math.floor(ai.cell * 100 + 0.5) .. "%  ·  " .. (ai.cells or 0) .. " SPARE"
    elseif ai.spare then
        local unit = ai.magShort and string.upper(ai.magShort) or "SPARE"
        if ai.magShort then
            if (ai.magRounds or 2) > 1 then unit = unit .. (ai.spare == 1 and " MAG" or " MAGS") elseif ai.spare ~= 1 then unit = unit .. "S" end
        end
        info = ai.spare .. "  " .. unit
    end
    if ai.others then info = (info and info .. "  ·  " or "") .. string.upper(ai.others) end
    return info
end

local function weaponLine(ai)
    local name = string.upper(ai.name or "")
    if ai.mode then name = name .. "  ·  " .. ai.mode end
    return name
end

-- Pips (one per spare magazine) right-aligned at x ending, centred on y.
local function drawPips(n, x, y, w, h, gap)
    for i = 1, 6 do
        local px = x - (7 - i) * (w + gap) + gap
        if i <= n then setCol(INK, 235) else surface.SetDrawColor(255, 255, 255, 38) end
        surface.DrawRect(math.floor(px), math.floor(y - h * 0.5), math.max(1, math.floor(w)), math.floor(h))
    end
    return 6 * (w + gap)
end

-- The hotbar's rows in the panel (set by HUD.DrawRealHotbar), so the
-- weapon lines sit just above it.
local panelRows, panelRowsAt, panelTh = 0, 0, 42

-- Default look: fire-mode squares by the chin, the ammo dial, the panel
-- with the weapon lines (the hotbar grid is drawn into it by
-- HUD.DrawRealHotbar).
local function drawMirror(g, ai)
    local s = g.s
    local C = HUD.Colors
    local R = g.right
    local wep = LocalPlayer():GetActiveWeapon()
    local p = R.panel
    draw.NoTexture()

    -- Fire modes: the one in use amber, a toggle that's on blue, SAFE
    -- amber while the safety is on.
    local list = fireModes(wep)
    local armed = ai and not ai.unarmed
    local safe = armed and ai.safe
    for i, q in ipairs(R.modes) do
        local label, lit, col, dim = nil, false, COL_MODE, 56
        if i == 4 then
            if armed then label, lit = "SAFE", safe end
        else
            local m = armed and list[i]
            if m then
                label = m.label
                col = m.toggle and C.armor or COL_MODE
                lit = m.on and (m.toggle or not safe) or false
                if m.on and not lit then dim = 120 end
            end
        end
        if lit then setCol(col, 242) else setCol(INK, dim) end
        surface.DrawPoly(q.poly)
        if label then
            text(label, 10, 600, q.tx, q.ty, lit and COL_DARK or INK, lit and 255 or 200, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.NoTexture()
    end

    -- Ammo dial: a ring of 30 segments for the magazine, the cell inside.
    local d = R.dial
    surface.SetDrawColor(0, 0, 0, 115)
    surface.DrawPoly(d.bg)
    setCol(INK, 178)
    for _, q in ipairs(d.rim) do surface.DrawPoly(q) end
    local hasClip = ai and ai.clip and not ai.noAmmo and not ai.unarmed
    local ccol = ammoColour(ai)
    local lit = 0
    if hasClip and ai.maxClip and ai.maxClip > 0 then lit = math.ceil(math.Clamp(ai.clip / ai.maxClip, 0, 1) * #d.ring) end
    for i, q in ipairs(d.ring) do
        if i <= lit then setCol(ccol, 240) else setCol(COL_EMPTY) end
        surface.DrawPoly(q)
    end
    if hasClip and ai.cell then
        setCol(C.armor, 230)
        for i = 1, math.ceil(math.Clamp(ai.cell, 0, 1) * #d.cell) do surface.DrawPoly(d.cell[i]) end
    end
    if hasClip then
        text("RND", 11 * d.k, 500, d.x, d.y - 27 * s * d.k, INK, 150, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        text(tostring(ai.clip), 38 * d.k, 500, d.x, d.y, ccol, 255, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if ai.maxClip and ai.maxClip > 0 then
            text("/ " .. ai.maxClip, 13 * d.k, 500, d.x, d.y + 29 * s * d.k, INK, 150, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    elseif ai and ai.unarmed then
        text("—", 38 * d.k, 500, d.x, d.y, INK, 140, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    draw.NoTexture()

    -- Weapon lines in the panel, right-aligned, just above the hotbar.
    if not ai then return end
    local rows = RealTime() - panelRowsAt < 0.5 and panelRows or 0
    local bottom = p.yb - 10 * s
    if rows > 0 then bottom = bottom - rows * panelTh * s - (rows - 1) * 6 * s - 8 * s end
    local right = p.x1
    local info = hasClip and ammoLine(ai) or nil
    local nameBottom = bottom
    if info then
        local py = bottom - 6 * s
        local room = p.x1 - p.x0 - 22 * s
        local pips = ai.spare ~= nil and room >= 200 * s
        info = fit(info, 12, 500, room - (pips and 68 * s or 0))
        local tw = text(info, 12, 500, right, py, INK, 205, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if pips then drawPips(spareMags(ai), right - tw - 8 * s, py, 7 * s, 12 * s, 3 * s) end
        nameBottom = bottom - 15 * s
    end
    text(fit(weaponLine(ai), 16, 700, p.x1 - p.x0 - 22 * s), 16, 700, right, nameBottom, INK, 255, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
end

-- Simple look: weapon lines and the big count on top, a row of round
-- ticks and the cell bar, the slanted bar by the chin (the tiles and
-- their group line come from HUD.DrawRealHotbar).
local function drawStrip(g, ai)
    local s, W = g.s, g.W
    local C = HUD.Colors
    local R = g.right
    draw.NoTexture()
    setCol(INK, 230)
    surface.DrawPoly(R.frame)
    for _, q in ipairs(R.ticks) do surface.DrawPoly(q) end
    if not ai then return end

    local right = W - 40 * s
    local base = 716 * s
    local hasClip = ai.clip and not ai.noAmmo and not ai.unarmed
    local ccol = ammoColour(ai)
    local countLeft = right
    if hasClip then
        local mw = 0
        if ai.maxClip and ai.maxClip > 0 then mw = text("/" .. ai.maxClip, 16, 500, right, base, INK, 150, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM) + 6 * s end
        countLeft = right - mw - text(tostring(ai.clip), 50, 500, right - mw, base + 7 * s, ccol, 255, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    elseif ai.unarmed then
        countLeft = right - text("—", 50, 500, right, base + 7 * s, INK, 140, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
    local tx = countLeft - 14 * s
    -- (the left end of a row whose top is at y: just inside the cheek pad)
    local function leftAt(y)
        local xp = math.Clamp((y - 4 * s - g.edgeY) * g.cornerX / (g.cornerY - g.edgeY), 0, g.cornerX)
        return W - xp
    end
    local info = hasClip and ammoLine(ai) or nil
    if info then
        local py = base - 8 * s
        local room = tx - leftAt(py - 7 * s)
        local pips = ai.spare ~= nil and room >= 160 * s
        info = fit(info, 12, 500, math.max(room - (pips and 66 * s or 0), 20 * s))
        local tw = text(info, 12, 500, tx, py, INK, 205, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if pips then drawPips(spareMags(ai), tx - tw - 6 * s, py, 6 * s, 11 * s, 3 * s) end
        local nb = py - 10 * s
        text(fit(weaponLine(ai), 16, 700, math.max(tx - leftAt(nb - 20 * s), 20 * s)), 16, 700, tx, nb, INK, 255, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    else
        text(fit(weaponLine(ai), 16, 700, math.max(tx - leftAt(base - 20 * s), 20 * s)), 16, 700, tx, base, INK, 255, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
    draw.NoTexture()

    -- Round ticks (one per round, up to 60) and the cell bar.
    if not hasClip then return end
    local x0, x1 = math.max(W - 400 * s, R.tickRight + 20 * s), W - 40 * s
    local n = ai.maxClip and ai.maxClip > 0 and math.min(ai.maxClip, 60) or 0
    if n > 0 and x1 > x0 then
        local step = (x1 - x0) / n
        local w = math.Clamp(step * 0.5, 1, 6 * s)
        local lit = math.ceil(math.Clamp(ai.clip / ai.maxClip, 0, 1) * n)
        local y, h = math.floor(752 * s), math.floor(14 * s)
        for i = 1, n do
            if i <= lit then setCol(ccol, 240) else surface.SetDrawColor(255, 255, 255, 33) end
            surface.DrawRect(math.floor(x0 + (i - 1) * step), y, math.max(1, math.floor(w)), h)
        end
    end
    if ai.cell then
        local y, h = math.floor(772 * s), math.max(2, math.floor(3 * s))
        surface.SetDrawColor(255, 255, 255, 31)
        surface.DrawRect(math.floor(x0), y, math.floor(x1 - x0), h)
        setCol(C.armor, 235)
        surface.DrawRect(math.floor(x0), y, math.floor((x1 - x0) * math.Clamp(ai.cell, 0, 1)), h)
    end
end

local function drawRight(g, ai)
    if stripVar:GetBool() then drawStrip(g, ai) else drawMirror(g, ai) end
end

local function drawPillars(g, ai)
    local C = HUD.Colors
    setCol(INK, 215)
    for _, q in ipairs(g.pillar) do surface.DrawPoly(q) end
    -- Left: spare magazines (one bar each, up to six; only for guns
    -- that count magazines, else spare rounds as whole magazines).
    local spare = ai.spare or 0
    if not ai.magShort and ai.maxClip and ai.maxClip > 0 then spare = spare / ai.maxClip end
    local mags = math.Clamp(math.floor(spare), 0, 6)
    for i, q in ipairs(g.stack[-1]) do
        if 7 - i <= mags then setCol(INK, 235) else setCol(COL_EMPTY) end
        surface.DrawPoly(q)
    end
    -- Right: what's left in the magazine, in sixths.
    local lit, col = 0, INK
    if ai.clip and ai.maxClip and ai.maxClip > 0 then
        lit = math.ceil(ai.clip / ai.maxClip * 6)
        if ai.clip / ai.maxClip <= 0.25 then col = ai.clip == 0 and C.bad or C.fuel end
    end
    for i, q in ipairs(g.stack[1]) do
        if 7 - i <= lit then setCol(col, 235) else setCol(COL_EMPTY) end
        surface.DrawPoly(q)
    end
end

-- Drawn before the other HUD parts (priority -10, as the normal visor).
Rhylib.Hook.Add("HUDPaint", "hud.realistic", function()
    if not HUD.RealisticActive() then return end
    local g = HUD.RealGeo()
    local s = g.s
    draw.NoTexture()
    surface.SetTexture(0)
    setCol(COL_SHELL)
    for _, t in ipairs(g.tris) do surface.DrawPoly(t) end
    for _, edge in ipairs(g.edges) do
        for i = 1, #edge - 1 do
            local p, q = edge[i], edge[i + 1]
            setCol(COL_EDGE_DARK)
            surface.DrawLine(p[1], p[2], q[1], q[2])
            surface.DrawLine(p[1], p[2] - 1, q[1], q[2] - 1)
            setCol(COL_EDGE_LIGHT)
            surface.DrawLine(p[1], p[2] - 2, q[1], q[2] - 2)
        end
    end

    -- Top: rim dashes, the thin line, the heading.
    setCol(INK, 215)
    for _, q in ipairs(g.rim) do surface.DrawPoly(q) end
    setCol(INK, 90)
    for i = 1, #g.base - 1 do
        local p, q = g.base[i], g.base[i + 1]
        surface.DrawLine(p[1], p[2], q[1], q[2])
    end
    drawCompass(g)
    draw.NoTexture()

    -- Sides.
    for _, d in ipairs(g.side) do
        setCol(INK, 235 * (d.a or 1))
        surface.DrawPoly(d.t)
    end
    local ply = LocalPlayer()
    local C = HUD.Colors
    local maxAr = ply.GetMaxArmor and ply:GetMaxArmor() or 100
    if maxAr <= 0 then maxAr = 100 end
    local armour = math.max(ply:Armor(), 0)
    drawLadder(g, -1, armour / maxAr, C.armor)
    local hp, maxHp, hcol = math.max(ply:Health(), 0), math.max(ply:GetMaxHealth(), 1), C.health
    local simHp, simMax = HUD.SimHealth(ply)
    if simHp then
        hp, maxHp, hcol = simHp, simMax, C.sim
        if hp / maxHp <= 0.3 then hcol = C.simLow end
    elseif hp / maxHp <= 0.3 then
        hcol = C.healthLow
    end
    drawLadder(g, 1, hp / maxHp, hcol)
    text(tostring(math.floor(armour)), 18, 600, 258 * s, g.numberY, C.armor, 255)
    text(tostring(math.floor(hp)), 18, 600, g.W - 258 * s, g.numberY, hcol, 255, TEXT_ALIGN_RIGHT)

    draw.NoTexture()
    drawStamina(g)
    draw.NoTexture()
    local ai = HUD.AmmoInfo and HUD.AmmoInfo(ply, ply:GetActiveWeapon())
    drawPillars(g, ai or {})
    drawRight(g, ai)
end, -10)

--------------------------------------------------------------------------
-- Hotbar (from cl_40_hotbar.lua through HUD.DrawVisorLayout)
--------------------------------------------------------------------------

-- HUD.DrawRealHotbar(entries, active, alpha): the hotbar on the right
-- cheek, one tile per entry (4, 6 with a backpack, the extra slot last).
-- Default: one row of tall tiles (with their count) at the bottom of
-- the panel when they fit, else four columns. Simple
-- look (rhylib_hud_real_strip): one row of slanted tiles under a line
-- naming the groups (loadout, backpack, staff).
local function heldIn(e, active)
    if e.wep ~= nil and e.wep == active then return true end
    if e.overflow then
        for _, w in ipairs(e.overflow) do
            if w == active then return true end
        end
    end
    return false
end

-- Which group an entry is in: 1 loadout, 2 backpack, 3 the extra slot.
local function groupOf(i, e)
    if e.overflow then return 3 end
    return (i <= 4 or not Rhylib.Inventory) and 1 or 2
end

local function tagOf(i, e)
    if e.overflow then return #e.overflow > 1 and ("+" .. (#e.overflow - 1)) or nil end
    return groupOf(i, e) == 2 and "BP" or nil
end

-- A tile's small line: the item's own (x2, 38/60, 80%), else the gun's
-- magazine.
local function subOf(e)
    if e.sub then return e.sub end
    local w = e.wep
    if IsValid(w) and w.Clip1 then
        local c, m = w:Clip1(), w.GetMagSize and w:GetMagSize() or w:GetMaxClip1()
        if c >= 0 and m > 0 then return c .. "/" .. m end
    end
end

local function gridHotbar(g, entries, active, alpha)
    local s = g.s
    local p = g.right.panel
    local n = #entries
    local gap = math.floor(6 * s)
    local ix0, ix1 = p.x0, p.x1
    -- One row when every tile gets 72 px or more (wide screens), else
    -- four columns; a single row gets taller tiles with their count.
    local cols = n * 72 * s + (n - 1) * gap <= ix1 - ix0 and n or math.max(4, math.ceil(n / 2))
    local rows = math.ceil(n / cols)
    local tall = rows == 1
    local th = math.floor((tall and 56 or 42) * s)
    panelRows, panelRowsAt, panelTh = rows, RealTime(), tall and 56 or 42
    local tw = math.floor((ix1 - ix0 - (cols - 1) * gap) / cols)
    tw = math.min(tw, math.floor(120 * s))
    ix0 = ix1 - cols * tw - (cols - 1) * gap        -- (right-aligned)
    local bottom = math.floor(p.yb - 10 * s)
    local top = bottom - rows * th - (rows - 1) * gap
    local r = HUD.HotbarRect
    if r then r.x, r.y, r.w, r.h, r.frame = math.floor(ix0), top, math.floor(ix1 - ix0), bottom - top, FrameNumber() end
    draw.NoTexture()
    local pad = math.floor(6 * s)
    for i, e in ipairs(entries) do
        local c, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local x = math.floor(ix0 + c * (tw + gap))
        local y = top + row * (th + gap)
        local on = heldIn(e, active)
        local a = on and 255 or alpha * 0.7
        if e.empty then a = a * 0.5 end
        local fg = INK
        if on then
            setCol(INK, a)
            surface.DrawRect(x, y, tw, th)
            fg = COL_DARK
        else
            surface.SetDrawColor(255, 255, 255, 64 * a / 255)
            surface.DrawOutlinedRect(x, y, tw, th)
        end
        text(tostring(e.key), 11, 700, x + pad, y + 3 * s, fg, a)
        local tag = tagOf(i, e)
        if tag then text(tag, 11, 500, x + tw - pad, y + 3 * s, fg, a * 0.7, TEXT_ALIGN_RIGHT) end
        local sub = tall and not e.empty and subOf(e) or nil
        if sub then text(fit(sub, 11, 500, tw - pad * 2), 11, 500, x + pad, y + th - 22 * s, fg, a * 0.7, nil, TEXT_ALIGN_BOTTOM) end
        if e.empty then
            text(fit("Empty", 13, 500, tw - pad * 2), 13, 500, x + pad, y + th - 4 * s, fg, a * 0.6, nil, TEXT_ALIGN_BOTTOM)
        else
            text(fit(e.name or "", 13, 600, tw - pad * 2), 13, 600, x + pad, y + th - 4 * s, fg, a, nil, TEXT_ALIGN_BOTTOM)
        end
        draw.NoTexture()
    end
end

local GROUP_NAMES = { "LOADOUT", "BACKPACK", "STAFF" }
local tileQuad = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }

local function stripHotbar(g, entries, active, alpha)
    local s, W = g.s, g.W
    local C = HUD.Colors
    local R = g.right
    local n = #entries
    local th, gap = math.floor(52 * s), math.floor(6 * s)
    local y0 = math.floor(812 * s)
    local lean = 6.5 * s       -- (each tile leans right: top edge this far right of the middle)
    local right = W - 44 * s
    -- (narrower tiles where the cheek is short: 4:3 / 5:4 screens)
    local avail = right - (R.frameX(y0 + th) + 14 * s)
    local tw = math.max(math.floor(14 * s), math.min(math.floor(62 * s), math.floor((avail - (n - 1) * gap) / n)))
    local total = n * tw + (n - 1) * gap
    local x0 = math.floor(right - total)
    local r = HUD.HotbarRect
    if r then r.x, r.y, r.w, r.h, r.frame = x0, y0, total, th, FrameNumber() end
    draw.NoTexture()

    -- The line over the tiles, a stretch of it per group with its name.
    local ly = math.floor(800 * s)
    local lx0 = math.min(math.max(W - 500 * s, R.tickRight + 10 * s), x0 - lean)
    surface.SetDrawColor(INK.r, INK.g, INK.b, 89 * alpha / 255)
    surface.DrawRect(math.floor(lx0), ly, math.floor(W - 40 * s - lx0), 1)
    local gx0, gx1, gk = nil, nil, nil
    local function flushGroup()
        if not gk then return end
        local col = gk == 2 and C.armor or (gk == 3 and COL_MODE or INK)
        setCol(col, alpha)
        surface.DrawRect(gx0, ly - 1, gx1 - gx0, math.max(2, math.floor(2 * s)))
        text(GROUP_NAMES[gk], 10, 500, gx0, ly - 3 * s, INK, alpha * 0.7, nil, TEXT_ALIGN_BOTTOM)
        draw.NoTexture()
    end
    for i, e in ipairs(entries) do
        local k = groupOf(i, e)
        local x = x0 + (i - 1) * (tw + gap)
        if k ~= gk then
            flushGroup()
            gk, gx0 = k, x
        end
        gx1 = x + tw
    end
    flushGroup()

    local pad = math.floor(7 * s)
    for i, e in ipairs(entries) do
        local x = x0 + (i - 1) * (tw + gap)
        local on = heldIn(e, active)
        local a = on and 255 or alpha * 0.75
        if e.empty then a = a * 0.5 end
        local q = tileQuad
        q[1].x, q[1].y = x + lean, y0
        q[2].x, q[2].y = x + tw + lean, y0
        q[3].x, q[3].y = x + tw - lean, y0 + th
        q[4].x, q[4].y = x - lean, y0 + th
        local fg = INK
        if on then
            setCol(INK, a)
            surface.DrawPoly(q)
            fg = COL_DARK
        else
            surface.SetDrawColor(0, 0, 0, 77 * a / 255)
            surface.DrawPoly(q)
            surface.SetDrawColor(255, 255, 255, 77 * a / 255)
            for j = 1, 4 do
                local p1, p2 = q[j], q[j % 4 + 1]
                surface.DrawLine(p1.x, p1.y, p2.x, p2.y)
            end
        end
        text(tostring(e.key), 15, 700, x + pad, y0 + 3 * s, fg, a)
        local sub = not e.empty and tw >= 50 * s and subOf(e) or nil
        if sub then text(sub, 10, 500, x + tw + lean * 0.4 - pad * 0.6, y0 + 5 * s, fg, a * 0.75, TEXT_ALIGN_RIGHT) end
        if tw < 30 * s then
            -- (too narrow for names)
        elseif e.empty then
            text(fit("Empty", 13, 500, tw - pad), 13, 500, x + pad * 0.3, y0 + th - 4 * s, fg, a * 0.6, nil, TEXT_ALIGN_BOTTOM)
        else
            text(fit(e.name or "", 13, 600, tw - pad), 13, 600, x + pad * 0.3, y0 + th - 4 * s, fg, a, nil, TEXT_ALIGN_BOTTOM)
        end
        draw.NoTexture()
    end
end

function HUD.DrawRealHotbar(entries, active, alpha)
    if #entries == 0 then return end
    local g = HUD.RealGeo()
    if stripVar:GetBool() then stripHotbar(g, entries, active, alpha) else gridHotbar(g, entries, active, alpha) end
end

-- Settings > HUD (only with this layout): tall side ladders, and the
-- simple right cheek.
Rhylib.Hook.Add("InitPostEntity", "hud.realistic.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    local function shown() return HUD.VisorLayout and HUD.VisorLayout() == "real" end
    Menus.AddSetting("HUD", { id = "hud.realtall", order = 11, title = "Realistic HUD: tall side ladders",
        desc = "Stretch the armour and health ladders over the whole side of the visor", kind = "toggle",
        convar = "rhylib_hud_real_tall", showIf = shown })
    Menus.AddSetting("HUD", { id = "hud.realstrip", order = 12, title = "Realistic HUD: simple right cheek",
        desc = "A plainer right cheek: the round count with a row of round ticks and the hotbar in one row, instead of the fire-mode squares, the ammo dial and the hotbar panel",
        kind = "toggle", convar = "rhylib_hud_real_strip", showIf = shown })
end)
