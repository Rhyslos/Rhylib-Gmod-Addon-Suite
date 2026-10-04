--[[
    Clone helmet visor, first person only.

    The see-through area is a T shape: wide across the top, narrowing to
    a chin opening at the bottom centre. Around it: a curved brow along
    the top and two cheek pieces in the lower corners.

    Armour (blue, left) and health (red, right) are four long bars each,
    lying along the cheek edges just inside the helmet, from the screen
    side toward the chin (not all the way). Each bar is always 25%; a
    partly used bar fills from the screen side. The ammo counter sits on
    the lower-right cheek (cl_30_ammo.lua), the chat on the lower-left.

    Hidden in third person, in vehicles and while dead.
    Toggle: rhylib_hud_visor 0/1.

    The shape is built once per screen size as cached triangles, so each
    frame is only a few dozen cheap draw calls.
]]

local HUD = Rhylib.HUD
local visorVar = CreateClientConVar("rhylib_hud_visor", "1", true, false, "Clone helmet visor in first person (0/1)")

local COL_SHELL = Color(12, 14, 16, 250)
local COL_EDGE_DARK = Color(0, 0, 0, 230)
local COL_EDGE_LIGHT = Color(170, 176, 180, 120)

local COL_ARMOR_FILL = Color(60, 140, 255, 110)
local COL_ARMOR_LINE = Color(90, 160, 255, 170)
local COL_HEALTH_FILL = Color(230, 60, 50, 110)
local COL_HEALTH_LINE = Color(240, 90, 80, 170)
local COL_SIM_FILL = Color(240, 200, 50, 110)    -- (sim health, training guns)
local COL_SIM_LINE = Color(250, 215, 90, 170)
local COL_EMPTY_ALPHA = 45

-- Shape, as shares of the screen (0..1). Mirrored left/right.
-- Brow (top band): client convars so it can be tuned in Settings; slimmer
-- than the first version (0.022 / 0.07).
local browEdgeVar = CreateClientConVar("rhylib_visor_brow_edge", "0.012", true, false, "Visor brow depth at the screen sides (share of the height)")
local browCentreVar = CreateClientConVar("rhylib_visor_brow_centre", "0.045", true, false, "Visor brow depth in the middle (share of the height)")
local browCurveVar = CreateClientConVar("rhylib_visor_brow_curve", "1", true, false, "Visor brow curve: below 1 flatter and wider, above 1 a sharper dip in the middle")
local CHEEK_TOP = 0.75       -- where the cheek meets the screen side
local CHIN_HALF = 0.1        -- half the chin opening width (0.1 = 20% of the screen)
local CURVE_STEPS = 32

-- Armour / health bars along the cheek edges (shares of the screen).
local BAR_OFFSET = 0.005     -- below the helmet edge
local BAR_THICK = 0.009      -- bar thickness
local BAR_FROM = 0.005       -- starts this far from the screen side (share of the width; was 0.012)
local BAR_TO = 0.3           -- ends here (the chin opening starts at 0.4)
local BAR_GAP = 0.006        -- gap between the four bars (share of the width)
local BAR_STEPS = 10         -- pieces per bar (sets how smoothly a bar fills)

-- The cheek curve, as in build() below: x and y shares at t.
local function cheekPoint(t)
    local u = 1 - t
    local function bz(p0, p1, p2, p3) return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3 end
    return bz(0, 0.3, 0.39, 0.4), bz(0.75, 0.8, 0.86, 1.0)
end

-- Height share of the cheek edge at width share fx (0..0.4).
local function cheekY(fx)
    local lo, hi = 0, 1
    for _ = 1, 30 do
        local mid = (lo + hi) * 0.5
        if cheekPoint(mid) < fx then lo = mid else hi = mid end
    end
    local _, y = cheekPoint((lo + hi) * 0.5)
    return y
end

function HUD.VisorActive()
    if not visorVar:GetBool() then return false end
    if HUD.VisorLayout and HUD.VisorLayout() == "thirdperson" then return false end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or ply:InVehicle() or ply:ShouldDrawLocalPlayer() then return false end
    local wep = ply:GetActiveWeapon()
    return not (IsValid(wep) and wep:GetClass() == "gmod_camera")
end

-- One triangle with the winding surface.DrawPoly needs.
local function tri(ax, ay, bx, by, cx, cy)
    if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0 then
        bx, by, cx, cy = cx, cy, bx, by
    end
    return { { x = ax, y = ay }, { x = bx, y = by }, { x = cx, y = cy } }
end

-- Fill a region as a fan of triangles from one anchor point.
local function fan(list, ax, ay, points)
    for i = 1, #points - 1 do
        local p, q = points[i], points[i + 1]
        list[#list + 1] = tri(ax, ay, p[1], p[2], q[1], q[2])
    end
end

local function bezier(t, p0, p1, p2, p3)
    local u = 1 - t
    return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
end

local cache = { w = 0, h = 0 }
local BLEED = 16   -- px at 1080p the shell reaches past the screen edges

local function build(W, H)
    cache = { w = W, h = H, tris = {}, edges = {}, bars = {} }

    -- Brow: a smooth sag, deepest in the middle.
    local browEdge = math.Clamp(browEdgeVar:GetFloat(), 0, 0.1)
    local browCentre = math.Clamp(browCentreVar:GetFloat(), 0, 0.15)
    local curve = math.Clamp(browCurveVar:GetFloat(), 0.3, 4)
    local brow = {}
    for i = 0, CURVE_STEPS do
        local f = i / CURVE_STEPS
        local sag = math.sin(f * math.pi) ^ curve
        brow[#brow + 1] = { f * W, (browEdge + (browCentre - browEdge) * sag) * H }
    end
    local browShape = { { 0, 0 } }
    for _, p in ipairs(brow) do browShape[#browShape + 1] = p end
    browShape[#browShape + 1] = { W, 0 }
    fan(cache.tris, W * 0.5, 0, browShape)
    cache.edges[#cache.edges + 1] = brow

    -- Cheeks: from the screen side, sweeping down into the chin opening.
    for _, side in ipairs({ -1, 1 }) do
        local function sx(f) return side < 0 and f * W or (1 - f) * W end
        local x0, x1, x2, x3 = 0, 0.3, 0.5 - CHIN_HALF - 0.01, 0.5 - CHIN_HALF
        local y0, y1, y2, y3 = CHEEK_TOP, CHEEK_TOP + 0.05, 0.86, 1.0
        local curve = {}
        for i = 0, CURVE_STEPS do
            local t = i / CURVE_STEPS
            curve[#curve + 1] = { sx(bezier(t, x0, x1, x2, x3)), bezier(t, y0, y1, y2, y3) * H }
        end
        local shape = { { sx(0), H } }
        for _, p in ipairs(curve) do shape[#shape + 1] = p end
        -- Fan from the bottom corner, which sees every point on the curve.
        local corner = { sx(0), H }
        local pts = {}
        for i = 2, #shape do pts[#pts + 1] = shape[i] end
        fan(cache.tris, corner[1], corner[2], pts)
        cache.edges[#cache.edges + 1] = curve
    end

    -- Bars: for each side, four bars of small quads along the curve.
    -- bars[side][k] = { quads = { {x1,y1, x2,y2, x3,y3, x4,y4}, ... }, outline = { points } }
    cache.bars = {}
    local span = (BAR_TO - BAR_FROM - BAR_GAP * 3) / 4
    for _, side in ipairs({ -1, 1 }) do
        local function sx(f) return side < 0 and f * W or (1 - f) * W end
        local list = {}
        for k = 1, 4 do
            local f0 = BAR_FROM + (k - 1) * (span + BAR_GAP)
            local top, bottom = {}, {}
            for i = 0, BAR_STEPS do
                local fx = f0 + span * i / BAR_STEPS
                local y = cheekY(fx)
                top[#top + 1] = { sx(fx), (y + BAR_OFFSET) * H }
                bottom[#bottom + 1] = { sx(fx), (y + BAR_OFFSET + BAR_THICK) * H }
            end
            local quads = {}
            for i = 1, BAR_STEPS do
                local a1, b1, a2, b2 = top[i], top[i + 1], bottom[i + 1], bottom[i]
                quads[i] = { { x = a1[1], y = a1[2] }, { x = b1[1], y = b1[2] }, { x = a2[1], y = a2[2] }, { x = b2[1], y = b2[2] } }
                if side > 0 then  -- mirrored: keep the winding clockwise
                    local q = quads[i]
                    quads[i] = { q[2], q[1], q[4], q[3] }
                end
            end
            local outline = {}
            for _, p in ipairs(top) do outline[#outline + 1] = p end
            for i = #bottom, 1, -1 do outline[#outline + 1] = bottom[i] end
            list[k] = { quads = quads, outline = outline }
        end
        cache.bars[side] = list
    end

    -- Edge bleed: whatever touches a screen edge is pushed BLEED px past
    -- it (the shapes inside the screen don't change), so a moving HUD
    -- (rhylib_core cl_66_motion.lua) never opens a gap at the edges.
    local bleed = math.ceil(BLEED * H / 1080)
    local function push(x, y)
        if x <= 0.5 then x = -bleed elseif x >= W - 0.5 then x = W + bleed end
        if y <= 0.5 then y = -bleed elseif y >= H - 0.5 then y = H + bleed end
        return x, y
    end
    for _, t in ipairs(cache.tris) do
        for _, v in ipairs(t) do v.x, v.y = push(v.x, v.y) end
    end
    for _, edge in ipairs(cache.edges) do
        for _, p in ipairs(edge) do p[1], p[2] = push(p[1], p[2]) end
    end
end

-- Four bars for a 0..1 value, each bar 25%, filling from the screen side.
local function drawBars(list, frac, fill, line)
    draw.NoTexture()
    for k, bar in ipairs(list) do
        local part = math.Clamp(frac * 4 - (k - 1), 0, 1)
        local n = math.floor(part * BAR_STEPS + 0.5)
        if n > 0 then
            surface.SetDrawColor(fill)
            for i = 1, n do surface.DrawPoly(bar.quads[i]) end
        end
        if part > 0 then
            surface.SetDrawColor(line)
        else
            surface.SetDrawColor(line.r, line.g, line.b, COL_EMPTY_ALPHA)
        end
        local o = bar.outline
        for i = 1, #o do
            local p, q = o[i], o[i % #o + 1]
            surface.DrawLine(p[1], p[2], q[1], q[2])
        end
    end
end

-- Drawn before the other HUD parts (priority -10), so they sit on top.
Rhylib.Hook.Add("HUDPaint", "hud.visor", function()
    if not HUD.VisorActive() then return end
    local W, H = ScrW(), ScrH()
    -- (rebuilt when the screen size or the brow settings change)
    local be, bc, bv = browEdgeVar:GetFloat(), browCentreVar:GetFloat(), browCurveVar:GetFloat()
    if cache.w ~= W or cache.h ~= H or cache.be ~= be or cache.bc ~= bc or cache.bv ~= bv then
        build(W, H)
        cache.be, cache.bc, cache.bv = be, bc, bv
    end

    draw.NoTexture()
    surface.SetDrawColor(COL_SHELL)
    for _, t in ipairs(cache.tris) do surface.DrawPoly(t) end

    -- Edges: a dark line with a faint light line on the see-through side.
    for _, edge in ipairs(cache.edges) do
        for i = 1, #edge - 1 do
            local p, q = edge[i], edge[i + 1]
            surface.SetDrawColor(COL_EDGE_DARK)
            surface.DrawLine(p[1], p[2], q[1], q[2])
            surface.DrawLine(p[1], p[2] - 1, q[1], q[2] - 1)
            surface.SetDrawColor(COL_EDGE_LIGHT)
            surface.DrawLine(p[1], p[2] - 2, q[1], q[2] - 2)
        end
    end

    local ply = LocalPlayer()
    local maxAr = ply.GetMaxArmor and ply:GetMaxArmor() or 100
    if maxAr <= 0 then maxAr = 100 end
    drawBars(cache.bars[-1], ply:Armor() / maxAr, COL_ARMOR_FILL, COL_ARMOR_LINE)
    local simHp, simMax = HUD.SimHealth(ply)
    if simHp then
        drawBars(cache.bars[1], simHp / simMax, COL_SIM_FILL, COL_SIM_LINE)
    else
        drawBars(cache.bars[1], math.max(ply:Health(), 0) / math.max(ply:GetMaxHealth(), 1), COL_HEALTH_FILL, COL_HEALTH_LINE)
    end
end, -10)

--------------------------------------------------------------------------
-- Helpers for other HUD parts that sit on the cheeks (stamina, hotbar).
--------------------------------------------------------------------------

-- Screen x of the cheek edge at screen y. side -1 = left cheek, 1 = right.
-- (Above the cheek: the screen side; below the chin: the chin edge.)
function HUD.VisorCheekX(y, side)
    local W, H = ScrW(), ScrH()
    local fy = y / H
    local lo, hi = 0, 1
    for _ = 1, 30 do
        local mid = (lo + hi) * 0.5
        local _, py = cheekPoint(mid)
        if py < fy then lo = mid else hi = mid end
    end
    local fx = cheekPoint((lo + hi) * 0.5)
    return side < 0 and fx * W or (1 - fx) * W
end

-- Screen y of the cheek edge at screen x. side -1 = left cheek, 1 = right.
-- Past the chin end of the curve: the bottom of the screen.
function HUD.VisorCheekY(x, side)
    local W, H = ScrW(), ScrH()
    local fx = side < 0 and x / W or (W - x) / W
    if fx <= 0 then return CHEEK_TOP * H end
    if fx >= 0.5 - CHIN_HALF then return H end
    return cheekY(fx) * H
end

--[[
    A strip along a cheek edge, as quads, from width share fx0 to fx1,
    offset into the cheek along the edge's normal (so it keeps its
    thickness where the edge gets steep near the chin). Shares of the
    screen height for offset and thickness. Quads are ordered from fx0
    to fx1 and wound for surface.DrawPoly. Cached per screen size.
]]
local stripCache = {}
function HUD.VisorStrip(side, fx0, fx1, offset, thick, steps)
    local W, H = ScrW(), ScrH()
    local key = table.concat({ W, H, side, fx0, fx1, offset, thick, steps }, ",")
    if stripCache[key] then return stripCache[key] end

    -- t at a width share.
    local function tAt(fx)
        local lo, hi = 0, 1
        for _ = 1, 30 do
            local mid = (lo + hi) * 0.5
            if cheekPoint(mid) < fx then lo = mid else hi = mid end
        end
        return (lo + hi) * 0.5
    end
    local t0, t1 = tAt(fx0), tAt(fx1)
    local outer, inner = {}, {}
    for i = 0, steps do
        local t = t0 + (t1 - t0) * i / steps
        local px, py = cheekPoint(t)
        -- Direction of the curve here (looking back at the very end).
        local ta, tb = t, t + 0.001
        if tb > 1 then ta, tb = t - 0.001, t end
        local ax0, ay0 = cheekPoint(ta)
        local bx0, by0 = cheekPoint(tb)
        local tx, ty = (bx0 - ax0) * W, (by0 - ay0) * H
        local len = math.sqrt(tx * tx + ty * ty)
        local nx, ny = -ty / len, tx / len  -- into the left cheek (down and out)
        local x, y = px * W, py * H
        local o1, o2 = offset * H, (offset + thick) * H
        local ax, ay = x + nx * o1, y + ny * o1
        local bx, by = x + nx * o2, y + ny * o2
        if side > 0 then ax, bx = W - ax, W - bx end
        outer[#outer + 1] = { ax, ay }
        inner[#inner + 1] = { bx, by }
    end
    local quads = {}
    for i = 1, steps do
        local a, b, c, d = outer[i], outer[i + 1], inner[i + 1], inner[i]
        local q = { { x = a[1], y = a[2] }, { x = b[1], y = b[2] }, { x = c[1], y = c[2] }, { x = d[1], y = d[2] } }
        -- Keep the winding clockwise on screen.
        local area = 0
        for k = 1, 4 do
            local p, n = q[k], q[k % 4 + 1]
            area = area + (p.x * n.y - n.x * p.y)
        end
        if area < 0 then q = { q[1], q[4], q[3], q[2] } end
        quads[i] = q
    end
    local strip = { quads = quads, outer = outer, inner = inner }
    stripCache[key] = strip
    return strip
end

-- Where the armour/health bars end, so others can carry on from there.
HUD.VISOR_BAR_FROM = BAR_FROM
HUD.VISOR_BAR_TO = BAR_TO
HUD.VISOR_BAR_OFFSET = BAR_OFFSET
HUD.VISOR_BAR_THICK = BAR_THICK

-- Brow sliders (Settings > Interface), for finding the right shape.
Rhylib.Hook.Add("InitPostEntity", "hud.visor.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    Menus.AddSetting("HUD", { id = "hud.browedge", order = 40, title = "Visor brow: depth at the sides",
        desc = "Share of the screen height (default 0.012)", kind = "slider", convar = "rhylib_visor_brow_edge", min = 0, max = 0.06, decimals = 3 })
    Menus.AddSetting("HUD", { id = "hud.browcentre", order = 41, title = "Visor brow: depth in the middle",
        desc = "Share of the screen height (default 0.045)", kind = "slider", convar = "rhylib_visor_brow_centre", min = 0, max = 0.1, decimals = 3 })
    Menus.AddSetting("HUD", { id = "hud.browcurve", order = 42, title = "Visor brow: curve",
        desc = "Below 1 flatter and wider, above 1 a sharper dip (default 1)", kind = "slider", convar = "rhylib_visor_brow_curve", min = 0.3, max = 4, decimals = 2 })
end)
