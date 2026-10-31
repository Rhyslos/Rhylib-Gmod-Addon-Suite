--[[
    Weather on the visor (client): what the clone helmet's visor collects
    while you're out in it, drawn under the HUD (HUDPaintBackground).
    Only in first person with the helmet on (rhylib_gear's helmet toggle;
    without rhylib_gear the helmet always counts as on).

      Rain / storm: drops land on the visor (more looking up or running),
        sit there and slowly dry up; the bigger ones start to run down,
        leaving a fading wet trail, and swallow small drops on the way.
        Indoors no new ones land and they dry off over a few seconds.
      Snow / blizzard: frost creeps in from the edges (frost crystals and
        a cold white rim), up to about half the visor in snow and most of
        it in a blizzard; flakes stick for a moment and melt. Indoors it
        thaws.
      Sandstorm: dust settles: grains spread in from the edges and a
        brown film builds up; indoors it slowly settles off.

    Client convar rhylib_weather_visor (Settings > Interface "Weather on
    the visor"). W.visor = { frost, dust } (0-1) for other code.
]]

local W = Rhylib.Weather

local cvVisor = CreateClientConVar("rhylib_weather_visor", "1", true, false, "Weather: drops, frost and dust on the helmet visor (first person)")

W.visor = W.visor or { frost = 0, dust = 0 }
local drops = {}   -- { x, y, r, born, life, run = false, vy, trail = { {x, y, t} }, nextTrail, snow }

-- A filled circle (one poly table, reused).
local CIRCLE_N = 12
local poly = {}
for i = 1, CIRCLE_N do poly[i] = { x = 0, y = 0 } end
local function circle(x, y, r, cr, cg, cb, ca)
    for i = 1, CIRCLE_N do
        local a = (i - 1) / CIRCLE_N * math.pi * 2
        poly[i].x, poly[i].y = x + math.cos(a) * r, y + math.sin(a) * r
    end
    surface.SetDrawColor(cr, cg, cb, ca)
    surface.DrawPoly(poly)
end

-- Frost crystals and dust grains: made once (fractions of the screen).
local crystals, grains = nil, nil
local function build()
    crystals, grains = {}, {}
    for i = 1, 110 do
        -- (an edge, a spot along it, how far in, a few branches)
        local side = math.random(4)
        local along = math.Rand(0, 1)
        local depth = math.Rand(0, 1) ^ 1.6
        local segs = {}
        local x, y
        if side == 1 then x, y = along, depth * 0.3
        elseif side == 2 then x, y = along, 1 - depth * 0.3
        elseif side == 3 then x, y = depth * 0.22, along
        else x, y = 1 - depth * 0.22, along end
        for _ = 1, math.random(3, 6) do
            local a = math.Rand(0, math.pi * 2)
            local len = math.Rand(0.006, 0.022)
            segs[#segs + 1] = { x, y, x + math.cos(a) * len, y + math.sin(a) * len * 1.7 }
        end
        crystals[i] = { depth = depth, segs = segs }
    end
    for i = 1, 520 do
        local x, y = math.Rand(0, 1), math.Rand(0, 1)
        -- (grains near the edges come first)
        local edge = math.min(x, 1 - x, y, 1 - y) * 2
        grains[i] = { x = x, y = y, s = math.random(1, 3), th = math.Clamp(edge * 1.6 + math.Rand(-0.15, 0.15), 0, 1),
            c = math.random(70, 130) }
    end
end

-- Soft edge strips (the commander-order glow style): color, alpha at the
-- edge, how far in (pixels).
local function edges(r, g, b, a, width)
    local w, h = ScrW(), ScrH()
    local steps = 14
    local step = math.max(1, width / steps)
    for i = 0, steps - 1 do
        local f = 1 - i / steps
        surface.SetDrawColor(r, g, b, math.min(255, a * f * f))
        local o = math.floor(i * step)
        local s = math.ceil(step)
        surface.DrawRect(o, o, w - o * 2, s)
        surface.DrawRect(o, h - o - s, w - o * 2, s)
        surface.DrawRect(o, o + s, s, h - (o + s) * 2)
        surface.DrawRect(w - o - s, o + s, s, h - (o + s) * 2)
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

local spawnAcc = 0
Rhylib.Hook.Add("HUDPaintBackground", "weather.visor", function()
    local dt = math.min(FrameTime(), 0.1)
    local cur = W.cur
    if not cur then return end
    local k = W.KINDS[cur.kind] or W.KINDS.clear
    local amt = cur.amt
    local out = W.exposure or 0
    local V = W.visor
    local show = cvVisor:GetBool() and visorView()
    if not show then
        -- (helmet off / third person: the visor isn't in front of you)
        if #drops > 0 then drops = {} end
        V.frost = math.max(0, V.frost - dt * 0.05)
        V.dust = math.max(0, V.dust - dt * 0.02)
        return
    end
    if not crystals then build() end
    local w, h = ScrW(), ScrH()
    local s = h / 1080
    local now = RealTime()
    local me = LocalPlayer()

    -- Build up / wear off.
    if k.visor == "frost" and out > 0.5 then
        V.frost = math.min(k.frostMax * amt, V.frost + dt * k.frostRate * amt)
    else
        V.frost = math.max(0, V.frost - dt * 0.04)
    end
    if k.visor == "dust" and out > 0.5 then
        V.dust = math.min(k.dustMax * amt, V.dust + dt * k.dustRate * amt)
    else
        V.dust = math.max(0, V.dust - dt * 0.012)
    end

    -- New drops / flakes: more looking up and moving.
    if (k.visorRate or 0) > 0 and out > 0.5 then
        local up = math.Clamp(-me:EyeAngles().p / 60, 0, 1)
        local speed = math.Clamp(me:GetVelocity():Length2D() / 300, 0, 1)
        spawnAcc = spawnAcc + dt * k.visorRate * amt * (0.6 + up * 1.2 + speed * 0.6)
        while spawnAcc >= 1 do
            spawnAcc = spawnAcc - 1
            if #drops < 70 then
                local snow = k.visor == "frost"
                drops[#drops + 1] = {
                    x = math.Rand(0.03, 0.97) * w, y = math.Rand(0.02, 0.9) * h,
                    r = (snow and math.Rand(1.5, 3.5) or (math.random() < 0.18 and math.Rand(5, 8) or math.Rand(1.5, 4.5))) * s,
                    born = now, life = snow and math.Rand(1.5, 4) or math.Rand(4, 9), snow = snow,
                    runAt = now + math.Rand(0.4, 2.5), trail = {}, nextTrail = 0, vy = 0, wob = math.Rand(0, 6),
                }
            end
        end
    else
        spawnAcc = 0
    end

    -- Dust: a brown film and grains from the edges in.
    if V.dust > 0.01 then
        surface.SetDrawColor(150, 118, 78, 55 * V.dust)
        surface.DrawRect(0, 0, w, h)
        edges(125, 95, 60, 200 * V.dust, h * 0.18 * V.dust + 4)
        for _, g in ipairs(grains) do
            if g.th < V.dust then
                surface.SetDrawColor(g.c, g.c * 0.8, g.c * 0.55, 150)
                surface.DrawRect(g.x * w, g.y * h, g.s, g.s)
            end
        end
    end

    -- Frost: a cold rim and crystals reaching in.
    if V.frost > 0.01 then
        edges(215, 232, 255, 230 * V.frost, h * 0.32 * V.frost + 4)
        for _, c in ipairs(crystals) do
            if c.depth < V.frost * 1.1 then
                local a = 160 * math.Clamp((V.frost * 1.1 - c.depth) * 4, 0, 1)
                surface.SetDrawColor(235, 245, 255, a)
                for _, sg in ipairs(c.segs) do
                    surface.DrawLine(sg[1] * w, sg[2] * h, sg[3] * w, sg[4] * h)
                    surface.DrawLine(sg[1] * w + 1, sg[2] * h, sg[3] * w + 1, sg[4] * h)
                end
            end
        end
    end

    -- Drops and flakes.
    if #drops == 0 then return end
    draw.NoTexture()
    local dryFast = out < 0.5
    for i = #drops, 1, -1 do
        local d = drops[i]
        local age = now - d.born
        -- (indoors: everything dries within 3 s from now, fading out)
        if dryFast and not d.drying then
            d.drying = true
            d.life = math.min(d.life, age + 3)
        end
        local life = d.life
        if d.dead or age >= life or d.y - d.r > h then
            table.remove(drops, i)
        else
            local fade = math.min(1, (life - age) / 1.2)
            if d.snow then
                circle(d.x, d.y, d.r, 245, 250, 255, 210 * fade)
            else
                -- Big drops run down, leaving a trail and taking small ones with them.
                if d.r > 4.5 * s and now >= d.runAt and not dryFast then
                    d.vy = math.min(d.vy + dt * 260 * s, 280 * s)
                    d.y = d.y + d.vy * dt
                    d.x = d.x + math.sin(now * 3 + d.wob) * 6 * s * dt
                    d.r = math.max(3 * s, d.r - dt * 0.6 * s)
                    if now >= d.nextTrail then
                        d.nextTrail = now + 0.03
                        d.trail[#d.trail + 1] = { d.x, d.y, now }
                        if #d.trail > 55 then table.remove(d.trail, 1) end
                    end
                    for _, o in ipairs(drops) do
                        if o ~= d and not o.dead and not o.snow and o.r < d.r and math.abs(o.x - d.x) < d.r and math.abs(o.y - d.y) < d.r then
                            d.r = math.min(9 * s, d.r + o.r * 0.25)
                            o.dead = true   -- (removed when the loop gets to it)
                        end
                    end
                end
                for _, p in ipairs(d.trail) do
                    local ta = 1 - (now - p[3]) / 1.6
                    if ta > 0 then
                        surface.SetDrawColor(210, 220, 235, 40 * ta * fade)
                        surface.DrawRect(p[1] - d.r * 0.35, p[2] - 4 * s, d.r * 0.7, 8 * s)
                    end
                end
                -- (a dark rim, a lighter body, a bright highlight)
                circle(d.x, d.y + d.r * 0.15, d.r + 1, 20, 30, 45, 55 * fade)
                circle(d.x, d.y, d.r, 190, 205, 225, 70 * fade)
                circle(d.x - d.r * 0.35, d.y - d.r * 0.4, math.max(1, d.r * 0.3), 255, 255, 255, 170 * fade)
            end
        end
    end
end, -5)

local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Weather", { id = "weather.visor", order = 83, tab = "Interface", title = "Weather on the visor",
        desc = "Rain drops running down, frost creeping in and dust settling on your helmet visor (first person, helmet on)",
        kind = "toggle", convar = "rhylib_weather_visor" })
end
addSettings()
Rhylib.Hook.Add("InitPostEntity", "weather.visorsettings", addSettings)
