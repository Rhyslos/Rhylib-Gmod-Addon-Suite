--[[
    The three-arc recoil crosshair.

    Drawn from the weapon's real spread (Rhylib.Weapons.Spread), converted
    from degrees to pixels using the current field of view, so every shot
    lands inside the circle you see. Arcs keep their size and only move
    outward; aiming shrinks the whole crosshair.

    Player options (Settings > Weapons): the centre mark (chevron, dot,
    cross, small ring, T, plus, none) and the outer part (three arcs,
    ticks, brackets, a split ring, none) chosen separately; colour (a
    preset or custom R / G / B), centre size, gap and length of the outer
    part, thickness, outline, opacity, hit markers; "Spread on the
    crosshair" off keeps the outer part still (no spread or kick shown);
    "Centre follows recoil" moves the centre mark toward where the kick
    pushes (off by default: the centre never moves). Classic (chevron + arcs) is the default; an old
    rhylib_crosshair_style setting is moved over once.

    Realm: client. Called from rhylib_base SWEP:DoDrawCrosshair (and by
    rhylib_thirdperson for its own crosshair). Receives net "wep.hit"
    (UInt 2: 0 body, 1 head, 2 down/kill) for the hit marker and sound.
    Client convars: rhylib_hitsound, rhylib_crosshair_smooth / _thickness /
    _opacity / _inner / _outer / _colour / _r / _g / _b / _centre / _gap /
    _length / _dynamic / _follow / _outline / _hitmarker (_style: old,
    read once).
    Reads Rhylib.UI.Tint (a command order's colour, rhylib_skills) and
    Rhylib.Gear.visorFov (sun visor zoom, rhylib_gear).
]]

local W = Rhylib.Weapons
W.Crosshair = W.Crosshair or {}
local X = W.Crosshair

X.hitTime = X.hitTime or 0
X.hitKind = 0   -- 0 body, 1 head, 2 down/kill

local HIT_SHOW = 0.25             -- seconds a hit marker shows (fading)
local KILL_SHOW = 0.6
local hitSound = CreateClientConVar("rhylib_hitsound", "1", true, false, "Play a sound when your bolt hits someone", 0, 1)
local SOUNDS = {
    [0] = { "buttons/lightswitch2.wav", 150, 0.45 },     -- body
    [1] = { "buttons/lightswitch2.wav", 210, 0.6 },      -- head
    [2] = { "buttons/blip1.wav", 120, 0.6 },             -- down / kill
}

local GAP = math.rad(14)          -- slit width
local SIXTY = math.rad(60)
local MIN_RADIUS = 10             -- px at 1080p, so tiny cones stay readable
local LINE, OUTLINE = 2, 4        -- px at 1080p
local CHORD = 3                   -- px per arc piece (smooth curve at any size)
local PAD = 2                     -- px of soft edge added to each stroke

local colLine = Color(244, 244, 240)
local colOutline = Color(0, 0, 0, 128)
local colHead = Color(255, 90, 80)
local colMark = Color(0, 0, 0)

local smoothVar = CreateClientConVar("rhylib_crosshair_smooth", "1", true, false, "Anti-aliased crosshair lines (0 = plain polygons)", 0, 1)
local thickVar = CreateClientConVar("rhylib_crosshair_thickness", "1", true, false, "Crosshair line thickness (multiplier)", 0.5, 3)
local opacityVar = CreateClientConVar("rhylib_crosshair_opacity", "1", true, false, "Crosshair opacity", 0.1, 1)
local styleVar = CreateClientConVar("rhylib_crosshair_style", "classic", true, false, "Old crosshair style (moved to _inner / _outer once)")
local innerVar = CreateClientConVar("rhylib_crosshair_inner", "chevron", true, false, "Crosshair centre mark: chevron, dot, cross, circle, tee, plus, none")
local outerVar = CreateClientConVar("rhylib_crosshair_outer", "arcs", true, false, "Crosshair outer part: arcs, ticks, brackets, ring, none")
local colourVar = CreateClientConVar("rhylib_crosshair_colour", "white", true, false, "Crosshair colour (see X.COLOURS; custom = rhylib_crosshair_r / _g / _b)")
local rVar = CreateClientConVar("rhylib_crosshair_r", "244", true, false, "Custom crosshair colour: red", 0, 255)
local gVar = CreateClientConVar("rhylib_crosshair_g", "244", true, false, "Custom crosshair colour: green", 0, 255)
local bVar = CreateClientConVar("rhylib_crosshair_b", "240", true, false, "Custom crosshair colour: blue", 0, 255)
local gapVar = CreateClientConVar("rhylib_crosshair_gap", "0", true, false, "Extra gap between the centre and the outer part (px at 1080p)", 0, 30)
local lengthVar = CreateClientConVar("rhylib_crosshair_length", "1", true, false, "Length of the outer part's pieces (1 = normal)", 0.3, 1.6)
local dynamicVar = CreateClientConVar("rhylib_crosshair_dynamic", "1", true, false, "The outer part shows spread and kick (0 = stays still)", 0, 1)
local followVar = CreateClientConVar("rhylib_crosshair_follow", "0", true, false, "The centre mark moves toward where the kick pushes", 0, 1)
local centreVar = CreateClientConVar("rhylib_crosshair_centre", "1", true, false, "Size of the crosshair's centre mark (multiplier)", 0.5, 2.5)
local outlineVar = CreateClientConVar("rhylib_crosshair_outline", "1", true, false, "Dark outline around the crosshair", 0, 1)
local markerVar = CreateClientConVar("rhylib_crosshair_hitmarker", "1", true, false, "Show hit markers on the crosshair", 0, 1)

-- The old one-setting styles (centre mark, outer part), moved over once.
local OLD_STYLES = {
    classic = { "chevron", "arcs" }, dot = { "dot", "arcs" }, cross = { "cross", "arcs" },
    arcs = { "none", "arcs" }, dotonly = { "dot", "none" },
}
if cookie.GetString("rhylib_xh_v", "") ~= "2" then
    local o = OLD_STYLES[styleVar:GetString()]
    if o and styleVar:GetString() ~= "classic" then
        RunConsoleCommand("rhylib_crosshair_inner", o[1])
        RunConsoleCommand("rhylib_crosshair_outer", o[2])
    end
    cookie.Set("rhylib_xh_v", "2")
end
X.INNER = { chevron = true, dot = true, cross = true, circle = true, tee = true, plus = true, none = true }
X.OUTER = { arcs = true, ticks = true, brackets = true, ring = true, none = true }
X.INNER_OPTIONS = {
    { "chevron", "Chevron" }, { "dot", "Dot" }, { "cross", "Cross" }, { "circle", "Ring" }, { "tee", "T" }, { "plus", "Plus" }, { "none", "None" },
}
X.OUTER_OPTIONS = {
    { "arcs", "Arcs" }, { "ticks", "Ticks" }, { "brackets", "Brackets" }, { "ring", "Split ring" }, { "none", "None" },
}
X.COLOURS = {
    { "white", "White", Color(244, 244, 240) },
    { "green", "Green", Color(90, 235, 110) },
    { "cyan", "Cyan", Color(80, 220, 240) },
    { "yellow", "Yellow", Color(250, 225, 70) },
    { "orange", "Orange", Color(255, 150, 50) },
    { "red", "Red", Color(255, 75, 70) },
    { "magenta", "Magenta", Color(240, 90, 230) },
    { "custom", "Custom", nil },   -- (rhylib_crosshair_r / _g / _b)
}
local COLOUR_BY_ID = {}
for _, c in ipairs(X.COLOURS) do if c[3] then COLOUR_BY_ID[c[1]] = c[3] end end
local colCustom = Color(244, 244, 240)
local function ownColour()
    local id = colourVar:GetString()
    if id == "custom" then
        colCustom.r, colCustom.g, colCustom.b = math.Clamp(rVar:GetInt(), 0, 255), math.Clamp(gVar:GetInt(), 0, 255), math.Clamp(bVar:GetInt(), 0, 255)
        return colCustom
    end
    return COLOUR_BY_ID[id] or colLine
end
local colLineNow, colOutlineNow = Color(244, 244, 240), Color(0, 0, 0, 128)

--[[
    Smooth strokes: every stroke is a quad textured with a soft profile
    (opaque middle, fading to clear over the outer quarter on each side),
    so edges are anti-aliased instead of stair-stepped. The profile lives in
    a tiny render target made at runtime (no file to download), refreshed
    now and then in case the game lost it (alt-tab, video settings).
]]
local strokeMat, strokeRT, strokeAt = nil, nil, 0
local function buildStroke()
    strokeRT = strokeRT or GetRenderTargetEx("rhylib_xh_stroke", 8, 64, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888)
    render.PushRenderTarget(strokeRT)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(255, 255, 255, 0, true, true)
    -- Write colour and alpha exactly (no blending with what's there).
    render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
    cam.Start2D()
        draw.NoTexture()
        for y = 0, 63 do
            local d = math.min(y + 0.5, 64 - (y + 0.5)) / 16  -- 0 at the edge, 1 a quarter in
            surface.SetDrawColor(255, 255, 255, math.Clamp(d, 0, 1) * 255)
            surface.DrawRect(0, y, 8, 1)
        end
    cam.End2D()
    render.OverrideBlend(false)
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    strokeMat = strokeMat or CreateMaterial("rhylib_xh_stroke_mat", "UnlitGeneric", {
        ["$basetexture"] = strokeRT:GetName(),
        ["$translucent"] = "1",
        ["$vertexcolor"] = "1",
        ["$vertexalpha"] = "1",
    })
    strokeAt = RealTime()
end

local verts = {
    { x = 0, y = 0, u = 0, v = 0 }, { x = 0, y = 0, u = 1, v = 0 },
    { x = 0, y = 0, u = 1, v = 1 }, { x = 0, y = 0, u = 0, v = 1 },
}

-- One convex quad: 1-2 is one long edge (v = 0), 4-3 the other (v = 1).
-- surface.DrawPoly needs clockwise order, so flip if needed.
local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
    local area = (x1 * y2 - x2 * y1) + (x2 * y3 - x3 * y2) + (x3 * y4 - x4 * y3) + (x4 * y1 - x1 * y4)
    local a, b, c, d = verts[1], verts[2], verts[3], verts[4]
    a.x, a.y, a.v = x1, y1, 0
    c.x, c.y, c.v = x3, y3, 1
    if area < 0 then
        b.x, b.y, b.v = x4, y4, 1
        d.x, d.y, d.v = x2, y2, 0
    else
        b.x, b.y, b.v = x2, y2, 0
        d.x, d.y, d.v = x4, y4, 1
    end
    surface.DrawPoly(verts)
end

local padNow = 0  -- extra stroke width while drawing smooth

local function arc(cx, cy, r, a0, a1, w)
    w = w + padNow
    local ri, ro = r - w * 0.5, r + w * 0.5
    local n = math.Clamp(math.ceil(r * (a1 - a0) / CHORD), 6, 64)
    local step = (a1 - a0) / n
    local c0, s0 = math.cos(a0), math.sin(a0)
    for i = 1, n do
        local t1 = a0 + step * i
        local c1, s1 = math.cos(t1), math.sin(t1)
        quad(cx + c0 * ro, cy + s0 * ro, cx + c1 * ro, cy + s1 * ro,
             cx + c1 * ri, cy + s1 * ri, cx + c0 * ri, cy + s0 * ri)
        c0, s0 = c1, s1
    end
end

local function line(x1, y1, x2, y2, w)
    w = w + padNow
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local nx, ny = -dy / len * w * 0.5, dx / len * w * 0.5
    quad(x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
end

-- Set up for a batch of strokes: smooth (textured) or plain.
-- noBuild (the Settings preview, inside a panel): never render the
-- stroke texture there (clipping and the panel offset would spoil it);
-- it is made in PreRender instead, and plain lines show until then.
local wantStroke = false
local function beginStrokes(noBuild)
    if smoothVar:GetBool() and noBuild and not strokeMat then
        wantStroke = true
        draw.NoTexture()
        padNow = 0
    elseif smoothVar:GetBool() then
        if not noBuild and (not strokeMat or RealTime() - strokeAt > 5) then buildStroke() end
        surface.SetMaterial(strokeMat)
        padNow = PAD
    else
        draw.NoTexture()
        padNow = 0
    end
end

-- Cone angle (degrees) to screen pixels. Source FOV is horizontal at 4:3.
local function degToPx(deg, fov)
    return math.tan(math.rad(deg)) / (math.tan(math.rad(fov * 0.5)) * 0.75) * ScrH() * 0.5
end

-- A filled dot of radius rad, drawn as a polygon (float positions, so it
-- sits exactly on the centre); when smooth, a soft stroke ring round its edge
-- anti-aliases it. (A dot texture drawn with DrawTexturedRect snapped to
-- whole pixels and showed a square edge when coloured.)
local dotPts = {}
for i = 1, 24 do dotPts[i] = { x = 0, y = 0 } end
local function dot(x, y, rad)
    local smooth = smoothVar:GetBool() and strokeMat
    local fill = smooth and math.max(rad - 0.75, 0.5) or rad
    local n = #dotPts
    for i = 1, n do
        local a = (i - 1) / n * math.pi * 2   -- (clockwise on screen, y down)
        local pt = dotPts[i]
        pt.x, pt.y = x + math.cos(a) * fill, y + math.sin(a) * fill
    end
    draw.NoTexture()
    surface.DrawPoly(dotPts)
    if smooth then
        surface.SetMaterial(strokeMat)
        arc(x, y, fill, 0, math.pi * 2, 1)   -- (1 px core + the soft pad, straddling the fill's edge)
    end
end

-- inner, outer: the chosen ids; k: centre size; L: the outer pieces'
-- length; grow: extra radius for the outline pass; fx, fy: where the
-- centre mark sits.
local function drawShape(x, y, r, offsets, s, w, inner, outer, k, L, grow, fx, fy)
    local centres = W.Spread.ARC_CENTRES
    if outer == "arcs" or outer == "ring" then
        -- arcs: three 120 degree pieces; ring: the same, closed up (only a hair between)
        local gap = outer == "ring" and math.rad(4) or GAP
        local half = math.min(SIXTY - gap * 0.5, (SIXTY - gap * 0.5) * L)
        for i = 1, 3 do
            local c = centres[i]
            local cx, cy = x + math.cos(c) * offsets[i], y + math.sin(c) * offsets[i]
            arc(cx, cy, r, c - half, c + half, w)
        end
    elseif outer == "ticks" then
        -- a short line pointing out from each arc's middle
        local len = 8 * s * L
        for i = 1, 3 do
            local c = centres[i]
            local cs, sn = math.cos(c), math.sin(c)
            local rr = r + offsets[i]
            line(x + cs * rr, y + sn * rr, x + cs * (rr + len), y + sn * (rr + len), w)
        end
    elseif outer == "brackets" then
        -- a bracket round each arc's middle, its ends pointing outward
        local arm = 7 * s * L
        for i = 1, 3 do
            local c = centres[i]
            local cs, sn = math.cos(c), math.sin(c)
            local rr = r + offsets[i]
            local px, py = x + cs * rr, y + sn * rr
            local tx, ty = -sn, cs   -- (along the ring)
            line(px - tx * arm, py - ty * arm, px + tx * arm, py + ty * arm, w)
            line(px - tx * arm, py - ty * arm, px - tx * arm + cs * arm * 0.6, py - ty * arm + sn * arm * 0.6, w)
            line(px + tx * arm, py + ty * arm, px + tx * arm + cs * arm * 0.6, py + ty * arm + sn * arm * 0.6, w)
        end
    end
    -- Centre mark: never moves with the spread (unless "Centre follows recoil").
    x, y = fx, fy
    if inner == "chevron" then
        line(x - 6 * s * k, y + 3 * s * k, x, y - 4 * s * k, w)
        line(x, y - 4 * s * k, x + 6 * s * k, y + 3 * s * k, w)
    elseif inner == "dot" then
        dot(x, y, 2 * s * k + grow)
    elseif inner == "circle" then
        arc(x, y, 4 * s * k, 0, math.pi * 2, w)
    elseif inner == "cross" or inner == "tee" or inner == "plus" then
        local g, l = (inner == "plus" and 0 or 2 * s * k), 7 * s * k
        line(x - l, y, x - g, y, w)
        line(x + g, y, x + l, y, w)
        if inner ~= "tee" then line(x, y - l, x, y - g, w) end
        line(x, y + g, x, y + l, w)
    end
end

local offsets = { 0, 0, 0 }

-- X.Draw(wep, x, y): draws the crosshair for a Rhylib weapon centred on
-- x, y (pixels). Example (own HUD code): Rhylib.Weapons.Crosshair.Draw(wep, ScrW() / 2, ScrH() / 2)
function X.Draw(wep, x, y)
    -- Grapple mode: the hook's landing marker instead (cl_40_grapple.lua).
    if wep.InGrappleMode and wep:InGrappleMode() and X.DrawGrapple then
        X.DrawGrapple(wep, x, y)
        return
    end
    local ply = LocalPlayer()
    local fov = wep:TranslateFOV(ply:GetFOV())
    -- (rhylib_gear sun visor zoom narrows the view further)
    local Gr = Rhylib.Gear
    if Gr and Gr.visorFov and Gr.visorFov > 1 then fov = fov / Gr.visorFov end
    local s = ScrH() / 1080
    local t = CurTime()

    local dynamic = dynamicVar:GetBool()
    local r = math.max(degToPx(W.Spread.BaseCone(wep), fov), MIN_RADIUS * s) + math.Clamp(gapVar:GetFloat(), 0, 30) * s
    if dynamic then
        local o1, o2, o3 = W.Spread.Offsets(wep, t)
        offsets[1], offsets[2], offsets[3] = degToPx(o1, fov), degToPx(o2, fov), degToPx(o3, fov)
    else
        offsets[1], offsets[2], offsets[3] = 0, 0, 0
    end
    X.Paint(x, y, r, offsets, dynamic, t - X.hitTime, X.hitKind)
end

-- X.Paint(x, y, r, offsets, dynamic, hitAge, hitKind): draws the crosshair
-- with the player's look settings: r = the ring radius in pixels,
-- offsets = { kick px per arc }, hitAge / hitKind = the hit marker (age
-- in seconds). X.Draw calls it; the Settings preview draws a fake burst
-- with it. Works in any Paint (panel or HUD).
function X.Paint(x, y, r, offsets, dynamic, hitAge, hitKind)
    local s = ScrH() / 1080
    -- Centre follows recoil (setting): toward the arc that kicked out most.
    local fx, fy = x, y
    if followVar:GetBool() and dynamic then
        local mean = (offsets[1] + offsets[2] + offsets[3]) / 3
        for i = 1, 3 do
            local c = W.Spread.ARC_CENTRES[i]
            local d = (offsets[i] - mean) * 0.5
            fx, fy = fx + math.cos(c) * d, fy + math.sin(c) * d
        end
    end
    local L = math.Clamp(lengthVar:GetFloat(), 0.3, 1.6)

    -- Thickness and opacity from the player's settings.
    local thick = math.Clamp(thickVar:GetFloat(), 0.5, 3)
    local op = math.Clamp(opacityVar:GetFloat(), 0.1, 1)
    local inner = innerVar:GetString()
    if not X.INNER[inner] then inner = "chevron" end
    local outer = outerVar:GetString()
    if not X.OUTER[outer] then outer = "arcs" end
    local k = math.Clamp(centreVar:GetFloat(), 0.5, 2.5)
    local own = ownColour()
    colLineNow.a = 255 * op
    -- (a tint, e.g. an officer's command order: rhylib_skills)
    local tint = Rhylib.UI.Tint
    if tint then
        colLineNow.r, colLineNow.g, colLineNow.b = tint.r, tint.g, tint.b
    else
        colLineNow.r, colLineNow.g, colLineNow.b = own.r, own.g, own.b
    end
    colOutlineNow.a = colOutline.a * op
    beginStrokes(X.painting == "preview")
    if outlineVar:GetBool() then
        surface.SetDrawColor(colOutlineNow)
        drawShape(x, y, r, offsets, s, (LINE * thick + (OUTLINE - LINE)) * s, inner, outer, k, L, (OUTLINE - LINE) * 0.5 * s, fx, fy)
    end
    surface.SetDrawColor(colLineNow)
    drawShape(x, y, r, offsets, s, LINE * thick * s, inner, outer, k, L, 0, fx, fy)
    if not markerVar:GetBool() then return end

    -- Hit marker: four diagonal ticks around the ring, fading out. Head
    -- hits are red; dropping someone shows a larger, longer red X.
    local kill = hitKind == 2
    local show = kill and KILL_SHOW or HIT_SHOW
    local age = hitAge or 99
    if age < show then
        local f = 1 - age / show
        local base = hitKind == 0 and own or colHead
        colMark.r, colMark.g, colMark.b, colMark.a = base.r, base.g, base.b, 255 * f
        local grow = kill and (1 + 0.4 * (1 - f)) or 1
        local r0 = (r + 5 * s) * grow
        local r1 = r0 + (kill and 16 or 10) * s
        local w = (kill and 3 or LINE) * s
        for k = 0, 3 do
            local a = math.rad(45 + 90 * k)
            local c, sn = math.cos(a), math.sin(a)
            surface.SetDrawColor(0, 0, 0, 128 * f)
            line(x + c * r0, y + sn * r0, x + c * r1, y + sn * r1, w + 2 * s)
            surface.SetDrawColor(colMark)
            line(x + c * r0, y + sn * r0, x + c * r1, y + sn * r1, w)
        end
    end
end

-- X.DrawPreview(x, y, t): a sample crosshair for the Settings page: a
-- short burst every 1.6 s (the outer part kicks out and settles while
-- "Spread on the crosshair" is on; a hit marker on the last shot).
local previewOffsets = { 0, 0, 0 }
local KICK = { { 0.4, 1, 0.2 }, { 0.9, 0.5, 0.3 }, { 0.2, 0.8, 1 } }
function X.DrawPreview(x, y, t)
    local s = ScrH() / 1080
    local dynamic = dynamicVar:GetBool()
    local r = (MIN_RADIUS * 1.6 + math.Clamp(gapVar:GetFloat(), 0, 30)) * s
    local cyc = t % 1.6
    for i = 1, 3 do previewOffsets[i] = 0 end
    if dynamic then
        for n = 0, 2 do
            local at = n * 0.12
            if cyc >= at then
                local f = math.exp(-(cyc - at) * 7)
                for i = 1, 3 do previewOffsets[i] = previewOffsets[i] + KICK[n + 1][i] * 10 * s * f end
            end
        end
    end
    X.painting = "preview"
    X.Paint(x, y, r, previewOffsets, dynamic, cyc >= 0.24 and (cyc - 0.24) or 99, 0)
    X.painting = nil
end
Rhylib.Hook.Add("PreRender", "weapons.crosshair.stroke", function()
    if wantStroke then
        wantStroke = false
        if not strokeMat then buildStroke() end
    end
end)

Rhylib.Net.ReceiveBatch("wep.hit", function()
    return net.ReadUInt(2)
end, function(kind)
    -- A kill marker isn't cut short by the next body hit.
    if X.hitKind == 2 and CurTime() - X.hitTime < KILL_SHOW * 0.5 and kind < 2 then return end
    X.hitTime = CurTime()
    X.hitKind = kind
    local snd = hitSound:GetBool() and SOUNDS[kind]
    local me = LocalPlayer()
    if snd and IsValid(me) then me:EmitSound(snd[1], 0, snd[2], snd[3], CHAN_STATIC) end  -- level 0: not positional
end)

-- In the settings menu (rhylib_menus).
Rhylib.Hook.Add("InitPostEntity", "weapons.hitsound.setting", function()
    local Menus = Rhylib.Menus
    if Menus and Menus.AddSetting then
        -- Settings > Crosshair: a live preview above the rows.
        if Menus.SettingGroupTop then
            Menus.SettingGroupTop("Crosshair", function(sp)
                local K = Menus.Kit
                local box = vgui.Create("DPanel", sp)
                box:Dock(TOP)
                box:SetTall(K.S(170))
                box:DockMargin(0, 0, K.S(10), K.S(8))
                local bg1, bg2 = Color(86, 99, 110), Color(42, 44, 37)
                function box:Paint(w, h)
                    -- (a sky-to-ground backdrop, so light and dark colours both show)
                    for i = 0, 7 do
                        local f = i / 7
                        surface.SetDrawColor(Lerp(f, bg1.r, bg2.r), Lerp(f, bg1.g, bg2.g), Lerp(f, bg1.b, bg2.b), 255)
                        surface.DrawRect(0, math.floor(h * i / 8), w, math.ceil(h / 8) + 1)
                    end
                    K.SetCol(K.C.edgeDark)
                    surface.DrawOutlinedRect(0, 0, w, h)
                    X.DrawPreview(w * 0.5, h * 0.5, RealTime())
                    draw.SimpleText("LIVE PREVIEW", K.Font(11, 700), K.S(10), K.S(14), K.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText("a short burst every second or two", K.Font(11), K.S(10), h - K.S(12), K.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end)
        end
        Menus.AddSetting("Weapons", { id = "wep.hitsound", order = 10, title = "Hit sounds",
            desc = "A click when your bolt hits someone", kind = "toggle", convar = "rhylib_hitsound" })
        Menus.AddSetting("Weapons", { id = "wep.xhinner", order = 12, title = "Crosshair centre", wide = 640,
            desc = "The mark in the middle (it never moves unless Centre follows recoil is on)", kind = "choice", convar = "rhylib_crosshair_inner", options = X.INNER_OPTIONS,
            get = function() local v = innerVar:GetString() return X.INNER[v] and v or "chevron" end })
        Menus.AddSetting("Weapons", { id = "wep.xhouter", order = 13, title = "Crosshair outer part", wide = 560,
            desc = "Shows the spread and the kick of each shot", kind = "choice", convar = "rhylib_crosshair_outer", options = X.OUTER_OPTIONS,
            get = function() local v = outerVar:GetString() return X.OUTER[v] and v or "arcs" end })
        -- Colour: squares for the named colours and a mixer (Custom = the
        -- r / g / b convars); kind "colour" on the Settings page.
        local swatches = {}
        for _, c in ipairs(X.COLOURS) do if c[3] then swatches[#swatches + 1] = c[3] end end
        Menus.AddSetting("Weapons", { id = "wep.xhcolour", order = 14, title = "Crosshair colour",
            desc = "Pick a colour, or the last square for any colour", kind = "colour", convar = "rhylib_crosshair_colour", swatches = swatches,
            get = function()
                local v = colourVar:GetString()
                if COLOUR_BY_ID[v] then return COLOUR_BY_ID[v] end
                return Color(rVar:GetInt(), gVar:GetInt(), bVar:GetInt())
            end,
            set = function(c)
                for id, col in pairs(COLOUR_BY_ID) do
                    if col.r == c.r and col.g == c.g and col.b == c.b then RunConsoleCommand("rhylib_crosshair_colour", id) return end
                end
                RunConsoleCommand("rhylib_crosshair_colour", "custom")
                RunConsoleCommand("rhylib_crosshair_r", tostring(c.r))
                RunConsoleCommand("rhylib_crosshair_g", tostring(c.g))
                RunConsoleCommand("rhylib_crosshair_b", tostring(c.b))
            end })
        Menus.AddSetting("Weapons", { id = "wep.xhgap", order = 16.1, title = "Crosshair gap",
            desc = "Extra room between the centre and the outer part", kind = "slider", convar = "rhylib_crosshair_gap", min = 0, max = 30, decimals = 0 })
        Menus.AddSetting("Weapons", { id = "wep.xhlength", order = 16.2, title = "Crosshair outer length",
            desc = "Length of the ticks or brackets (up to 1.6) or the arcs (up to 1)", kind = "slider", convar = "rhylib_crosshair_length", min = 0.3, max = 1.6, decimals = 1 })
        Menus.AddSetting("Weapons", { id = "wep.xhdynamic", order = 16.3, title = "Spread on the crosshair",
            desc = "The outer part opens up with spread and kicks out on the side each shot went (off: no spread or kick shown; it still shrinks when aiming)", kind = "toggle", convar = "rhylib_crosshair_dynamic" })
        Menus.AddSetting("Weapons", { id = "wep.xhfollow", order = 16.4, title = "Centre follows recoil",
            desc = "The centre mark moves a little toward where the kick pushes (off: it never moves)", kind = "toggle", convar = "rhylib_crosshair_follow" })
        Menus.AddSetting("Weapons", { id = "wep.xhcentre", order = 16, title = "Crosshair centre size",
            desc = "Size of the chevron, dot or cross (1 = normal)", kind = "slider", convar = "rhylib_crosshair_centre", min = 0.5, max = 2.5, decimals = 1 })
        Menus.AddSetting("Weapons", { id = "wep.xhoutline", order = 18, title = "Crosshair outline",
            desc = "Dark edge so it shows on bright backgrounds", kind = "toggle", convar = "rhylib_crosshair_outline" })
        Menus.AddSetting("Weapons", { id = "wep.xhmarker", order = 19, title = "Hit markers",
            desc = "Ticks around the crosshair when your bolt hits", kind = "toggle", convar = "rhylib_crosshair_hitmarker" })
        Menus.AddSetting("Weapons", { id = "wep.xhthick", order = 20, title = "Crosshair thickness",
            desc = "Line thickness (1 = normal)", kind = "slider", convar = "rhylib_crosshair_thickness", min = 0.5, max = 3, decimals = 1 })
        Menus.AddSetting("Weapons", { id = "wep.xhsmooth", order = 25, title = "Smooth crosshair lines",
            desc = "Anti-aliased lines (off: plain polygons, if the crosshair looks wrong)", kind = "toggle", convar = "rhylib_crosshair_smooth" })
        Menus.AddSetting("Weapons", { id = "wep.xhopacity", order = 30, title = "Crosshair opacity",
            desc = "1 = solid", kind = "slider", convar = "rhylib_crosshair_opacity", min = 0.1, max = 1, decimals = 2 })
    end
end)
