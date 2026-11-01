--[[
    Weather on the visor (client): what the clone helmet's visor collects
    while you're out in it, drawn under the HUD (HUDPaintBackground).
    Only in first person with the helmet on (rhylib_gear's helmet toggle;
    without rhylib_gear the helmet always counts as on).

    The glass effects use a copy of the screen: frost, mist, breath and
    dust blur what is behind them (pp/blurscreen inside a stencil mask),
    and rain drops are small lenses that show the view behind them
    flipped and squeezed (a screen copy drawn on each drop).

      Rain / storm / heavy storm: drops land (more looking up or running)
        with a little ring, show the world flipped inside them with a dark
        rim and a small glint, and the bigger ones run down leaving a
        wavy wet trail and a few tiny beads, swallowing small drops on the
        way; a fine wet film builds up. A lightning flash glints in every
        drop. Indoors no new ones land and it dries off over a few seconds.
      Snow / blizzard: frosted glass grows in from the edges and corners
        with a ragged edge (blurred and pale, whiter further in, fine
        grain), ice crystals branch in from its edge; flakes stick as
        little stars and melt into drops; your breath fogs the bottom of
        the visor every few seconds. Indoors it thaws.
      Sandstorm: sand streaks whip across with the wind, gusts of dust
        sweep over, grains tick against the visor, a dusty blurred film
        builds up (heaviest at the bottom) with stuck grains and fine
        scratches; indoors it slowly settles off.
      Mist / fog: the visor fogs over from the edges, blurred and pale,
        with fine condensation.
    While the weather cuts comms (rhylib_radio NW2Bool rhylib_jamWx), thin
    interference bands flicker across the visor.

    Client convar rhylib_weather_visor (Settings > Interface "Weather on
    the visor"). W.visor = { frost, dust, wet, mist } (0-1) for other code.
]]

local W = Rhylib.Weather

local cvVisor = CreateClientConVar("rhylib_weather_visor", "1", true, false, "Weather: drops, frost and dust on the helmet visor (first person)")

W.visor = W.visor or { frost = 0, dust = 0, wet = 0, mist = 0 }
local V = W.visor
V.wet, V.mist = V.wet or 0, V.mist or 0

local drops = {}    -- { x, y, r, born, life, snow, runAt, vy, trail = { {x, y, t} }, nextTrail, wob, dead, drying }
local streaks = {}  -- sand: { x, y, vx, vy, len, t, thick }
local ticks = {}    -- sand hits: { x, y, t }
local gusts = {}    -- dust gusts sweeping across: { t, dir }
local breath = nil  -- { t }
local nextBreath = 0

local blurMat = Material("pp/blurscreen")
local scrMat = CreateMaterial("rhylib_wx_screen", "UnlitGeneric", {
    ["$basetexture"] = "_rt_FullFrameFB", ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$ignorez"] = 1,
})
if render.GetScreenEffectTexture then scrMat:SetTexture("$basetexture", render.GetScreenEffectTexture()) end

-- Circle tables (cos / sin per side count).
local rings = {}
local function ring(n)
    local t = rings[n]
    if not t then
        t = { cs = {}, sn = {}, p = {}, tp = {} }
        for i = 1, n do
            local a = (i - 1) / n * math.pi * 2
            t.cs[i], t.sn[i] = math.cos(a), math.sin(a)
            t.p[i] = { x = 0, y = 0 }
            t.tp[i] = { x = 0, y = 0, u = 0, v = 0 }
        end
        rings[n] = t
    end
    return t
end

-- Filled circle (untextured).
local function circle(x, y, r, cr, cg, cb, ca)
    if ca <= 0.5 or r <= 0 then return end
    local t = ring(r > 30 and 28 or (r > 8 and 16 or 10))
    local cs, sn, poly = t.cs, t.sn, t.p
    for i = 1, #poly do poly[i].x, poly[i].y = x + cs[i] * r, y + sn[i] * r end
    surface.SetDrawColor(cr, cg, cb, ca)
    surface.DrawPoly(poly)
end

-- A circle of the screen copy: mag < 0 shows the view behind it flipped
-- and squeezed (a drop), 0-1 magnified a little (a wet smear).
local function lens(x, y, r, mag, cr, cg, cb, ca, w, h)
    if ca <= 0.5 or r <= 0 then return end
    local t = ring(r > 10 and 20 or 12)
    local cs, sn, poly = t.cs, t.sn, t.tp
    local iw, ih = 1 / w, 1 / h
    local rm = r * mag
    for i = 1, #poly do
        local p = poly[i]
        p.x, p.y = x + cs[i] * r, y + sn[i] * r
        p.u, p.v = (x + cs[i] * rm) * iw, (y + sn[i] * rm) * ih
    end
    surface.SetDrawColor(cr, cg, cb, ca)
    surface.DrawPoly(poly)
end

-- A four-point shape in whichever winding DrawPoly wants.
local quadP = { { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 }, { x = 0, y = 0 } }
local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
    local area = (x1 * y2 - x2 * y1) + (x2 * y3 - x3 * y2) + (x3 * y4 - x4 * y3) + (x4 * y1 - x1 * y4)
    if area < 0 then x2, y2, x4, y4 = x4, y4, x2, y2 end
    quadP[1].x, quadP[1].y = x1, y1
    quadP[2].x, quadP[2].y = x2, y2
    quadP[3].x, quadP[3].y = x3, y3
    quadP[4].x, quadP[4].y = x4, y4
    surface.DrawPoly(quadP)
end

-- Blur the screen behind (inside the current stencil mask).
local function blur(amount, passes)
    if amount <= 0.05 then return end
    surface.SetMaterial(blurMat)
    surface.SetDrawColor(255, 255, 255, 255)
    for i = 1, passes do
        blurMat:SetFloat("$blur", amount * i / passes)
        blurMat:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
    end
    draw.NoTexture()
end

-- Draw inside(): only where mask() drew.
local function masked(mask, inside)
    draw.NoTexture()
    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(1)
    render.SetStencilTestMask(1)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.OverrideColorWriteEnable(true, false)
    surface.SetDrawColor(255, 255, 255, 255)
    local ok, err = pcall(mask)
    render.OverrideColorWriteEnable(false)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    if ok then ok, err = pcall(inside) end
    render.SetStencilEnable(false)
    draw.NoTexture()
    if not ok then ErrorNoHalt("[Rhylib] weather visor: " .. tostring(err) .. "\n") end
end

-- Ragged fronts growing in from the edges. A noise set holds 0-1 per
-- point along each edge (1 top, 2 bottom, 3 left, 4 right).
local function noiseSet(n, smooth)
    local set = {}
    for e = 1, 4 do
        local a = {}
        for i = 1, n + 1 do a[i] = math.random() end
        for _ = 1, smooth do
            local b = {}
            for i = 1, n + 1 do b[i] = (a[math.max(1, i - 1)] + a[i] * 2 + a[math.min(n + 1, i + 1)]) / 4 end
            a = b
        end
        local lo, hi = 1, 0
        for i = 1, #a do lo, hi = math.min(lo, a[i]), math.max(hi, a[i]) end
        for i = 1, #a do a[i] = (a[i] - lo) / math.max(hi - lo, 0.01) end
        set[e] = a
    end
    return set
end

local function edgePoint(e, t, d, w, h)
    if e == 1 then return t * w, d
    elseif e == 2 then return t * w, h - d
    elseif e == 3 then return d, t * h
    else return w - d, t * h end
end

local INWARD = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }

-- base = { top, bottom, left, right } in pixels; corner: how much further
-- in it reaches at the corners.
local function frontDepth(set, e, i, base, corner)
    local a = set[e]
    local t = (i - 1) / (#a - 1)
    local c = math.abs(t - 0.5) * 2
    return base[e] * (0.45 + a[i]) * (1 + corner * c * c * c)
end

local function drawFront(set, base, corner)
    local w, h = ScrW(), ScrH()
    for e = 1, 4 do
        if base[e] > 0.5 then
            local a = set[e]
            local n = #a
            local ex0, ey0, fx0, fy0
            for i = 1, n do
                local t = (i - 1) / (n - 1)
                local d = frontDepth(set, e, i, base, corner)
                local ex, ey = edgePoint(e, t, 0, w, h)
                local fx, fy = edgePoint(e, t, d, w, h)
                if i > 1 then quad(ex0, ey0, ex, ey, fx, fy, fx0, fy0) end
                ex0, ey0, fx0, fy0 = ex, ey, fx, fy
            end
        end
    end
end

local function frontRim(set, base, corner, cr, cg, cb, ca)
    local w, h = ScrW(), ScrH()
    surface.SetDrawColor(cr, cg, cb, ca)
    for e = 1, 4 do
        if base[e] > 0.5 then
            local n = #set[e]
            local px, py
            for i = 1, n do
                local x, y = edgePoint(e, (i - 1) / (n - 1), frontDepth(set, e, i, base, corner), w, h)
                if px then surface.DrawLine(px, py, x, y) end
                px, py = x, y
            end
        end
    end
end

-- Made once: noise for the fronts, ice crystals, grain, dust, scratches.
local frostNz, mistNz, dustNz, crystals, frostGrain, grains, scratches, speckles
local function build()
    frostNz, mistNz, dustNz = noiseSet(44, 1), noiseSet(22, 4), noiseSet(30, 3)
    -- (crystals: a stem and 60° side branches, in units of their size)
    crystals = {}
    local function crystal()
        local lines = {}
        local function grow(u, v, a, len, depth, g0)
            if #lines >= 18 then return end
            local u2, v2 = u + math.cos(a) * len, v + math.sin(a) * len
            lines[#lines + 1] = { u, v, u2, v2, g0, len }
            if depth > 0 then
                for _ = 1, math.random(1, 2) do
                    local tt = math.Rand(0.25, 0.85)
                    local side = math.random() < 0.5 and -1 or 1
                    grow(u + (u2 - u) * tt, v + (v2 - v) * tt, a + side * math.rad(60), len * math.Rand(0.3, 0.5), depth - 1, g0 + len * tt)
                end
                grow(u2, v2, a + math.rad(math.Rand(-12, 12)), len * math.Rand(0.5, 0.7), depth - 1, g0 + len)
            end
        end
        grow(0, 0, math.rad(math.Rand(-35, 35)), 1, 3, 0)
        return lines
    end
    for e = 1, 4 do
        local n = #frostNz[e]
        for _ = 1, 8 do
            crystals[#crystals + 1] = { e = e, i = math.random(2, n - 1), size = math.Rand(0.6, 1.4), lines = crystal() }
        end
    end
    frostGrain = {}
    for i = 1, 420 do
        frostGrain[i] = { x = math.Rand(0, 1), y = math.Rand(0, 1), s = math.random(1, 2), a = math.random(30, 80) }
    end
    grains = {}
    for i = 1, 520 do
        local x, y = math.Rand(0, 1), math.Rand(0, 1)
        -- (dust: edges first, the bottom most of all)
        local edge = math.min(x * 1.3, (1 - x) * 1.3, y * 1.6, (1 - y) * 0.8)
        grains[i] = { x = x, y = y, s = math.Rand(0.8, 2.2), th = math.Clamp(edge * 2 + math.Rand(-0.15, 0.15), 0, 1),
            c = math.random(70, 130), light = math.random() < 0.2 }
    end
    scratches = {}
    for i = 1, 160 do
        local x, y = math.Rand(0, 1), math.Rand(0, 1)
        local edge = math.min(x, 1 - x, y * 1.5, (1 - y) * 0.7)
        scratches[i] = { x = x, y = y, len = math.Rand(4, 14), ang = math.rad(math.Rand(-25, 25)), th = math.Clamp(edge * 1.8 + math.Rand(0, 0.5), 0, 1) }
    end
    speckles = {}
    for i = 1, 460 do
        local x, y = math.Rand(0, 1), math.Rand(0, 1)
        local edge = math.min(x, 1 - x, y, 1 - y) * 2
        speckles[i] = { x = x, y = y, th = math.Clamp(edge * 0.8 + math.Rand(0, 0.5), 0, 1), r = math.Rand(0.8, 1.8) }
    end
end

local function visorView()
    local me = LocalPlayer()
    if not (IsValid(me) and me:Alive()) or me:GetViewEntity() ~= me then return false end
    local TP = Rhylib.ThirdPerson
    if TP and TP.Active and TP.Active() then return false end
    local G = Rhylib.Gear
    if G and G.HelmetOn and not G.HelmetOn(me) then return false end
    return true
end

-- A stuck snowflake: six arms with little barbs.
local function drawFlake(x, y, r, a)
    surface.SetDrawColor(232, 240, 250, a)
    for i = 0, 5 do
        local ang = i * math.pi / 3
        local c, sn = math.cos(ang), math.sin(ang)
        surface.DrawLine(x, y, x + c * r, y + sn * r)
        if r > 3 then
            local bx, by = x + c * r * 0.55, y + sn * r * 0.55
            local l = r * 0.3
            local c1, s1 = math.cos(ang + 0.9), math.sin(ang + 0.9)
            local c2, s2 = math.cos(ang - 0.9), math.sin(ang - 0.9)
            surface.DrawLine(bx, by, bx + c1 * l, by + s1 * l)
            surface.DrawLine(bx, by, bx + c2 * l, by + s2 * l)
        end
    end
end

-- (build up while out in it, wear off otherwise)
local function level(cur_, on_, outside, dt, rate, max, off)
    if on_ and outside then return math.min(max, cur_ + dt * rate) end
    return math.max(0, cur_ - dt * off)
end

local base4 = { 0, 0, 0, 0 }
local function setBase(t, b, l, r)
    base4[1], base4[2], base4[3], base4[4] = t, b, l, r
    return base4
end

local spawnAcc, streakAcc = 0, 0
Rhylib.Hook.Add("HUDPaintBackground", "weather.visor", function()
    local dt = math.min(FrameTime(), 0.1)
    local cur = W.cur
    if not cur then return end
    local k = W.KINDS[cur.kind] or W.KINDS.clear
    local amt = cur.amt
    local out = W.exposure or 0
    local show = cvVisor:GetBool() and visorView()
    if not show then
        -- (helmet off / third person: the visor isn't in front of you)
        if #drops > 0 then drops = {} end
        if #streaks > 0 then streaks = {} end
        if #ticks > 0 then ticks = {} end
        if #gusts > 0 then gusts = {} end
        breath = nil
        V.frost = math.max(0, V.frost - dt * 0.05)
        V.dust = math.max(0, V.dust - dt * 0.02)
        V.wet = math.max(0, V.wet - dt * 0.1)
        V.mist = math.max(0, V.mist - dt * 0.05)
        return
    end
    if not frostNz then build() end
    draw.NoTexture()
    local w, h = ScrW(), ScrH()
    local s = h / 1080
    local now = RealTime()
    local me = LocalPlayer()
    local outside = out > 0.5
    local glint = 1 + (W.flash or 0) * 2.5

    -- Build up / wear off.
    V.frost = level(V.frost, k.visor == "frost", outside, dt, (k.frostRate or 0) * amt, (k.frostMax or 0) * amt, 0.04)
    V.dust = level(V.dust, k.visor == "dust", outside, dt, (k.dustRate or 0) * amt, (k.dustMax or 0) * amt, 0.012)
    V.wet = level(V.wet, k.visor == "drops", outside, dt, (k.wetRate or 0) * amt, 0.8 * amt, 0.08)
    V.mist = level(V.mist, k.visor == "mist", outside, dt, (k.mistRate or 0) * amt, (k.mistMax or 0) * amt, 0.05)

    -- New drops / flakes: more looking up and moving.
    if (k.visorRate or 0) > 0 and outside then
        local up = math.Clamp(-me:EyeAngles().p / 60, 0, 1)
        local speed = math.Clamp(me:GetVelocity():Length2D() / 300, 0, 1)
        spawnAcc = spawnAcc + dt * k.visorRate * amt * (0.6 + up * 1.2 + speed * 0.6)
        while spawnAcc >= 1 do
            spawnAcc = spawnAcc - 1
            if #drops < 90 then
                local snow = k.visor == "frost"
                drops[#drops + 1] = {
                    x = math.Rand(0.03, 0.97) * w, y = math.Rand(0.02, 0.9) * h,
                    r = (snow and math.Rand(2.5, 5) or (math.random() < 0.2 and math.Rand(5.5, 9) or math.Rand(1.5, 4.5))) * s,
                    born = now, life = snow and math.Rand(1.5, 4) or math.Rand(4, 10), snow = snow,
                    runAt = now + math.Rand(0.4, 2.5), trail = {}, nextTrail = 0, vy = 0, wob = math.Rand(0, 6),
                }
            end
        end
    else
        spawnAcc = 0
    end

    -- Mist / fog: the glass fogs from the edges, blurred and pale.
    if V.mist > 0.01 then
        local m = V.mist
        surface.SetDrawColor(205, 212, 218, 14 * m)
        surface.DrawRect(0, 0, w, h)
        local b = setBase(h * 0.34 * m, h * 0.4 * m, w * 0.22 * m, w * 0.22 * m)
        masked(function() drawFront(mistNz, b, 0.8) end, function()
            blur(1.5 + 3 * m, 1)
            surface.SetDrawColor(208, 214, 220, 30 + 40 * m)
            surface.DrawRect(0, 0, w, h)
            for _, p in ipairs(speckles) do
                if p.th < m * 1.6 then
                    surface.SetDrawColor(225, 230, 236, 28)
                    surface.DrawRect(p.x * w, p.y * h, p.r * s + 0.5, p.r * s + 0.5)
                end
            end
        end)
    end

    -- Dust: a blurred brown film from the edges (most at the bottom),
    -- stuck grains and fine sand scratches.
    if V.dust > 0.01 then
        local d = V.dust
        surface.SetDrawColor(140, 108, 70, 26 * d)
        surface.DrawRect(0, 0, w, h)
        local b = setBase(h * 0.07 * d, h * 0.32 * d, w * 0.08 * d, w * 0.08 * d)
        masked(function() drawFront(dustNz, b, 0.9) end, function()
            blur(1 + 2 * d, 1)
            surface.SetDrawColor(146, 112, 72, 40 + 60 * d)
            surface.DrawRect(0, 0, w, h)
        end)
        for _, g in ipairs(grains) do
            if g.th < d then
                local x, y, sz = g.x * w, g.y * h, g.s * s + 0.5
                if g.light then surface.SetDrawColor(196, 172, 130, 130)
                else surface.SetDrawColor(g.c, g.c * 0.78, g.c * 0.52, 150) end
                surface.DrawRect(x, y, sz, sz)
            end
        end
        surface.SetDrawColor(215, 196, 160, 26 + 20 * d)
        for _, sc in ipairs(scratches) do
            if sc.th < d then
                local x, y, l = sc.x * w, sc.y * h, sc.len * s
                surface.DrawLine(x, y, x + math.cos(sc.ang) * l, y + math.sin(sc.ang) * l)
            end
        end
    end

    -- Sand whipping across the visor with the wind, gusts, grains ticking.
    if k.visor == "dust" and outside and amt > 0.05 then
        local wx, wy = 1, 0
        if W.WindDir then wx, wy = W.WindDir() end
        local right = me:EyeAngles():Right()
        local side = wx * right.x + wy * right.y   -- (+1: blowing to the right)
        local dir = side >= 0 and 1 or -1
        streakAcc = streakAcc + dt * 40 * amt
        while streakAcc >= 1 do
            streakAcc = streakAcc - 1
            if #streaks < 30 then
                streaks[#streaks + 1] = { x = dir > 0 and -60 or w + 60, y = math.Rand(0, h), vx = dir * math.Rand(1400, 2600) * s,
                    vy = math.Rand(-60, 120) * s, len = math.Rand(30, 90) * s, t = now, thick = math.random() < 0.25 }
            end
        end
        if math.random() < dt * 12 * amt and #ticks < 20 then ticks[#ticks + 1] = { x = math.Rand(0, w), y = math.Rand(0, h), t = now } end
        if math.random() < dt * 0.3 * amt and #gusts < 2 then gusts[#gusts + 1] = { t = now, dir = dir } end
    end
    for i = #gusts, 1, -1 do
        local g = gusts[i]
        local f = (now - g.t) / 0.9
        if f >= 1 then
            table.remove(gusts, i)
        else
            -- (a soft band of dust sweeping across)
            local cx = g.dir > 0 and (-0.3 + f * 1.6) * w or (1.3 - f * 1.6) * w
            local bw = w * 0.4
            local a = 38 * amt * math.sin(f * math.pi)
            for j = -6, 5 do
                local o = (j + 0.5) / 6
                surface.SetDrawColor(160, 126, 84, a * (1 - math.abs(o)))
                surface.DrawRect(cx + j * bw / 12, 0, bw / 12 + 1, h)
            end
        end
    end
    for i = #streaks, 1, -1 do
        local st = streaks[i]
        st.x, st.y = st.x + st.vx * dt, st.y + st.vy * dt
        if st.x < -120 or st.x > w + 120 then
            table.remove(streaks, i)
        else
            -- (fading toward the tail)
            local nx = st.vx > 0 and -1 or 1
            local sy = -st.vy / math.abs(st.vx)
            local seg = st.len / 4
            for j = 0, 3 do
                local x1, x2 = st.x + nx * seg * j, st.x + nx * seg * (j + 1)
                local y1, y2 = st.y + sy * seg * j, st.y + sy * seg * (j + 1)
                surface.SetDrawColor(196, 164, 118, 85 * (1 - j / 4))
                surface.DrawLine(x1, y1, x2, y2)
                if st.thick then surface.DrawLine(x1, y1 + 1, x2, y2 + 1) end
            end
        end
    end
    for i = #ticks, 1, -1 do
        local tk = ticks[i]
        local f = (now - tk.t) / 0.25
        if f >= 1 then table.remove(ticks, i)
        else
            circle(tk.x, tk.y, (1 + f * 2.5) * s, 220, 200, 160, 70 * (1 - f))
            circle(tk.x, tk.y, 1.1 * s, 70, 54, 34, 170 * (1 - f))
        end
    end

    -- Frost: frosted glass from the edges and corners (two layers: lightly
    -- frosted at the front, thick and white further in), crystals at its edge.
    if V.frost > 0.01 then
        local fr = V.frost
        surface.SetDrawColor(196, 214, 236, 10 * fr)
        surface.DrawRect(0, 0, w, h)
        local D = h * 0.36 * fr
        local outer = setBase(D * 0.75, D * 0.95, D * 0.85, D * 0.85)
        masked(function() drawFront(frostNz, outer, 0.8) end, function()
            blur(1.5 + 2 * fr, 1)
            surface.SetDrawColor(206, 222, 240, 26 + 30 * fr)
            surface.DrawRect(0, 0, w, h)
        end)
        local inner = setBase(D * 0.42, D * 0.52, D * 0.47, D * 0.47)
        masked(function() drawFront(frostNz, inner, 1.0) end, function()
            blur(4 + 3 * fr, 2)
            surface.SetDrawColor(222, 233, 246, 50 + 50 * fr)
            surface.DrawRect(0, 0, w, h)
            for _, g in ipairs(frostGrain) do
                surface.SetDrawColor(245, 250, 255, g.a)
                surface.DrawRect(g.x * w, g.y * h, g.s * s + 0.5, g.s * s + 0.5)
            end
        end)
        outer = setBase(D * 0.75, D * 0.95, D * 0.85, D * 0.85)
        frontRim(frostNz, outer, 0.8, 230, 240, 252, 40 + 40 * fr)
        -- Crystals branching in from the frost's edge.
        local G = math.Clamp((fr - 0.06) * 4, 0, 1) * 2.4
        if G > 0 then
            surface.SetDrawColor(232, 242, 255, 70 + 60 * fr)
            for _, c in ipairs(crystals) do
                local dep = frontDepth(frostNz, c.e, c.i, outer, 0.8)
                local ox, oy = edgePoint(c.e, (c.i - 1) / (#frostNz[c.e] - 1), dep * 0.9, w, h)
                local dx, dy = INWARD[c.e][1], INWARD[c.e][2]
                local px, py = -dy, dx
                local S = h * 0.05 * c.size * (0.5 + fr)
                for _, l in ipairs(c.lines) do
                    if l[5] < G then
                        local f = math.Clamp((G - l[5]) / l[6], 0, 1)
                        local u1, v1 = l[1], l[2]
                        local u2, v2 = u1 + (l[3] - u1) * f, v1 + (l[4] - v1) * f
                        surface.DrawLine(ox + (u1 * dx + v1 * px) * S, oy + (u1 * dy + v1 * py) * S,
                            ox + (u2 * dx + v2 * px) * S, oy + (u2 * dy + v2 * py) * S)
                    end
                end
            end
        end
    end

    -- Breath fogging the bottom of the visor in the cold.
    if k.visor == "frost" and outside and amt > 0.1 then
        if now >= nextBreath then
            nextBreath = now + math.Rand(3.2, 4.4)
            breath = { t = now }
        end
    end
    if breath then
        local f = (now - breath.t) / 1.6
        if f >= 1 then
            breath = nil
        else
            local a = math.sin(math.min(f * 2.2, 1) * math.pi * 0.5) * (1 - f)
            if a > 0.03 then
                local rr = h * 0.26 * (0.75 + f * 0.4)
                masked(function()
                    circle(w * 0.5, h * 1.06, rr, 255, 255, 255, 255)
                    circle(w * 0.38, h * 1.1, rr * 0.8, 255, 255, 255, 255)
                    circle(w * 0.62, h * 1.1, rr * 0.8, 255, 255, 255, 255)
                end, function()
                    blur(3 * a * amt + 0.5, 1)
                    surface.SetDrawColor(226, 232, 238, 45 * a * amt)
                    surface.DrawRect(0, 0, w, h)
                end)
            end
        end
    end

    -- Rain film: fine wet speckles (darker dots with a faint light edge).
    if V.wet > 0.01 then
        for _, p in ipairs(speckles) do
            if p.th < V.wet then
                local x, y, sz = p.x * w, p.y * h, p.r * s + 0.5
                surface.SetDrawColor(8, 12, 18, 34)
                surface.DrawRect(x, y, sz, sz)
                surface.SetDrawColor(220, 228, 238, math.min(255, 20 * glint))
                surface.DrawRect(x, y, sz * 0.5 + 0.5, sz * 0.5 + 0.5)
            end
        end
    end

    -- Drops and flakes: move them, then draw rims, lenses and glints.
    if #drops > 0 then
        local dryFast = not outside
        for i = #drops, 1, -1 do
            local d = drops[i]
            local age = now - d.born
            -- (indoors: everything dries within 3 s from now, fading out)
            if dryFast and not d.drying then
                d.drying = true
                d.life = math.min(d.life, age + 3)
            end
            if d.dead or age >= d.life or d.y - d.r > h then
                table.remove(drops, i)
            else
                d.age = age
                d.fade = math.min(1, (d.life - age) / 1.2)
                -- Big drops run down, leaving a trail and taking small ones with them.
                if not d.snow and d.r > 4.5 * s and now >= d.runAt and not dryFast then
                    d.vy = math.min(d.vy + dt * 260 * s, 280 * s)
                    d.y = d.y + d.vy * dt
                    d.x = d.x + math.sin(now * 3 + d.wob) * 6 * s * dt
                    d.r = math.max(3 * s, d.r - dt * 0.6 * s)
                    local last = d.trail[#d.trail]
                    if not last or math.abs(d.y - last[2]) + math.abs(d.x - last[1]) >= math.max(1.5 * s, d.r * 0.45) then
                        d.trail[#d.trail + 1] = { d.x, d.y, now }
                        if #d.trail > 40 then table.remove(d.trail, 1) end
                        -- (now and then a tiny bead left behind)
                        if math.random() < 0.04 and #drops < 90 then
                            drops[#drops + 1] = { x = d.x + math.Rand(-1, 1) * d.r * 0.4, y = d.y - d.r, r = math.Rand(1.2, 2.2) * s,
                                born = now, life = math.Rand(3, 6), runAt = math.huge, trail = {}, nextTrail = 0, vy = 0, wob = 0,
                                age = 0, fade = 1 }
                        end
                    end
                    for _, o in ipairs(drops) do
                        if o ~= d and not o.dead and not o.snow and o.r < d.r and math.abs(o.x - d.x) < d.r and math.abs(o.y - d.y) < d.r then
                            d.r = math.min(9.5 * s, d.r + o.r * 0.25)
                            o.dead = true   -- (removed next frame)
                        end
                    end
                end
            end
        end

        -- (the screen copy for the lenses, taken before any drop is drawn)
        render.UpdateScreenEffectTexture()

        -- Pass 1 (plain): dark rims, wet trail edges, flakes.
        draw.NoTexture()
        for _, d in ipairs(drops) do
            if not d.dead then
                local fade = d.fade
                if d.snow and d.age < d.life * 0.55 then
                    drawFlake(d.x, d.y, d.r * 1.3, 200 * fade)
                else
                    local r = d.snow and d.r * 0.6 or d.r
                    for _, p in ipairs(d.trail) do
                        local ta = 1 - (now - p[3]) / 1.8
                        if ta > 0 then circle(p[1], p[2], r * 0.45, 6, 10, 16, 20 * ta * fade) end
                    end
                    circle(d.x, d.y + r * 0.08, r * 1.12, 4, 7, 12, (r < 1.8 * s and 45 or 85) * fade)
                end
            end
        end

        -- Pass 2 (screen copy): the view behind, flipped inside each drop,
        -- and a faint smear along the trails.
        surface.SetMaterial(scrMat)
        for _, d in ipairs(drops) do
            if not d.dead and not (d.snow and d.age < d.life * 0.55) then
                local r = d.snow and d.r * 0.6 or d.r
                local n = #d.trail
                for j, p in ipairs(d.trail) do
                    local ta = 1 - (now - p[3]) / 1.8
                    if ta > 0 then
                        lens(p[1], p[2], r * (0.22 + 0.2 * j / math.max(n, 1)), 0.4, 230, 234, 240, 150 * ta * d.fade, w, h)
                    end
                end
                if r >= 1.8 * s then lens(d.x, d.y, r, -2.4, 196, 204, 214, 255 * d.fade, w, h) end
            end
        end

        -- Pass 3 (plain): a small glint up top, a faint light spot below, landing rings.
        draw.NoTexture()
        for _, d in ipairs(drops) do
            if not d.dead and not (d.snow and d.age < d.life * 0.55) then
                local r = d.snow and d.r * 0.6 or d.r
                local fade = d.fade
                circle(d.x, d.y + r * 0.42, r * 0.38, 230, 236, 244, 18 * fade * glint)
                if not d.snow and d.age < 0.18 then
                    -- (landing: a thin ring spreading out)
                    local f = d.age / 0.18
                    surface.DrawCircle(d.x, d.y, r * (1.1 + f * 1.6), 200, 214, 230, 70 * (1 - f))
                end
                circle(d.x - r * 0.32, d.y - r * 0.38, math.max(0.7, r * 0.16), 255, 255, 255, math.min(255, 115 * fade * glint))
            end
        end
    end

    -- Comms cut by the weather: interference bands across the visor.
    if me:GetNW2Bool("rhylib_jamWx", false) and me:GetNW2Bool("rhylib_jammed", false) then
        for _ = 1, 5 do
            if math.random() < 0.5 then
                local y = math.Rand(0, h)
                surface.SetDrawColor(200, 220, 255, math.random(10, 35))
                surface.DrawRect(0, y, w, math.Rand(1, 4) * s)
            end
        end
    end
end, -5)

local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Weather", { id = "weather.visor", order = 83, tab = "Interface", title = "Weather on the visor",
        desc = "Rain drops running down, frost creeping in, dust settling and fog misting your helmet visor (first person, helmet on)",
        kind = "toggle", convar = "rhylib_weather_visor" })
end
addSettings()
Rhylib.Hook.Add("InitPostEntity", "weather.visorsettings", addSettings)
