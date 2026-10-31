--[[
    Weather in the world (client): rain streaks with splashes, snowflakes
    drifting down, sand blowing past, fog, the rain / wind loops, and
    lightning with thunder in storms. Only outdoors: things only fall
    where the sky is open above them (a trace up to the sky, cached per
    96-unit cell), so roofs keep you dry and you see it through windows
    and doorways; indoors the sounds and fog are lower.

    State: W.cur = { kind, amt } (what is shown now; amt fades toward
    the server's W.Intensity() over fadeTime, and to 0 before the kind
    changes). W.exposure = 0-1, how much you are out in it (eased; the
    sky straight above your eyes). W.flash = 0-1 lightning on the screen.

    Client convars (Settings > Interface / Audio): rhylib_weather_fx
    (world effects on), rhylib_weather_amount (0.25-1, how many falling
    things: less for more FPS), rhylib_weather_volume (0-1).
    Hooks: Think "weather.state", PostDrawTranslucentRenderables
    "weather.world", SetupWorldFog / SetupSkyboxFog "weather.fog",
    HUDPaintBackground "weather.flash".
]]

local W = Rhylib.Weather

local cvFx = CreateClientConVar("rhylib_weather_fx", "1", true, false, "Weather: falling rain / snow / sand, fog and sounds")
local cvAmount = CreateClientConVar("rhylib_weather_amount", "1", true, false, "Weather: how much falls around you (0.25-1; lower for more FPS)")
local cvVolume = CreateClientConVar("rhylib_weather_volume", "0.8", true, false, "Weather: volume of rain, wind and thunder (0-1)")

W.cur = W.cur or { kind = "clear", amt = 0 }
W.exposure = W.exposure or 0
W.flash = 0

local function on() return cvFx:GetBool() end

-- Sky above the eyes: outdoors? (one input table, reused)
local tr = {}
local trIn = { mask = MASK_SOLID_BRUSHONLY, output = tr }
local function skyAbove(pos)
    trIn.start, trIn.endpos, trIn.mask = pos, pos + Vector(0, 0, 4000), MASK_SOLID_BRUSHONLY
    util.TraceLine(trIn)
    return tr.HitSky or not tr.Hit
end

-- Cells: is the sky open above this spot? [key] = { sky, x, y, t }
-- (the map doesn't move: kept until you're far away)
local cells = {}
local CELL = 96
local function cellSky(x, y, z)
    local cx, cy, cz = math.floor(x / CELL), math.floor(y / CELL), math.floor(z / 256)
    local key = cx .. ":" .. cy .. ":" .. cz
    local c = cells[key]
    if c then return c.sky end
    local p = Vector((cx + 0.5) * CELL, (cy + 0.5) * CELL, (cz + 0.5) * 256)
    trIn.start, trIn.endpos, trIn.mask = p, p + Vector(0, 0, 4000), MASK_SOLID_BRUSHONLY
    util.TraceLine(trIn)
    local sky = (tr.HitSky or not tr.Hit) and not tr.StartSolid
    cells[key] = { sky = sky, x = p.x, y = p.y }
    return sky
end
timer.Create("Rhylib.Weather.Cells", 5, 0, function()
    local e = EyePos()
    for k, c in pairs(cells) do
        local dx, dy = c.x - e.x, c.y - e.y
        if dx * dx + dy * dy > 3000 * 3000 then cells[k] = nil end
    end
end)
Rhylib.Hook.Add("InitPostEntity", "weather.cells", function() cells = {} end)

-- Wind direction: turns slowly over minutes.
local function windDir()
    local a = CurTime() * 0.01 + math.sin(CurTime() * 0.037) * 0.6
    return math.cos(a), math.sin(a)
end
W.WindDir = windDir

-- Fading between weathers, and how much you're out in it. (Joining
-- during a storm: it's there at once, no fade in.)
local expAt = 0
local rawOut = false
local started = false
Rhylib.Hook.Add("Think", "weather.state", function()
    local cur = W.cur
    local target = W.Kind()
    local want = target == "clear" and 0 or W.Intensity()
    if not started then
        local me = LocalPlayer()
        if IsValid(me) then
            started = true
            cur.kind, cur.amt = target, want
        end
    end
    local rate = FrameTime() / math.max(tonumber(W.Cfg("fadeTime")) or 12, 0.5)
    if cur.kind ~= target then
        cur.amt = math.max(0, cur.amt - rate)
        if cur.amt <= 0 then cur.kind = target end
    elseif cur.amt < want then
        cur.amt = math.min(want, cur.amt + rate)
    else
        cur.amt = math.max(want, cur.amt - rate)
    end
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local now = RealTime()
    if now >= expAt then
        expAt = now + 0.2
        rawOut = skyAbove(me:EyePos())
    end
    W.exposure = math.Approach(W.exposure, rawOut and 1 or 0, FrameTime() * 1.5)
end)

--------------------------------------------------------------------------
-- Falling things
--------------------------------------------------------------------------

local GLOW = Material("sprites/light_glow02_add")
local SMOKE = Material("particle/particle_smokegrenade")
local drops = {}     -- { p0, v, born, tEnd, s, ph, puff, land }
local splashes = {}  -- { pos, t }
local RAIN_COL = Color(185, 195, 215, 70)
local SPLASH_COL = Color(200, 210, 230, 60)
local SNOW_COL = Color(240, 244, 255, 200)
local SAND_COL = Color(178, 142, 96, 22)
local GRIT_COL = Color(150, 118, 78, 90)
local P, Q = Vector(), Vector()   -- (scratch: no new Vectors per drop per frame)

-- A new one somewhere around you, only under open sky; it stops where
-- its path first hits something (a roof, a wall, the ground).
local function spawn(k, eye, wx, wy)
    local a, r = math.Rand(0, math.pi * 2), k.radius * math.sqrt(math.Rand(0.02, 1))
    local x, y = eye.x + math.cos(a) * r, eye.y + math.sin(a) * r
    local look = k.look
    local z, v, life
    if look == "rain" then
        z = eye.z + math.Rand(300, 900)
        local side = k.fall * k.wind
        v = Vector(wx * side, wy * side, -k.fall * math.Rand(0.9, 1.1))
        life = (z - eye.z + 1200) / -v.z
        x, y = x - v.x * 0.45, y - v.y * 0.45   -- (start upwind so the slant ends up around you)
    elseif look == "snow" then
        z = eye.z + math.Rand(60, 420)
        v = Vector(wx * k.wind, wy * k.wind, -k.fall * math.Rand(0.7, 1.3))
        life = (z - eye.z + 600) / -v.z
        x, y = x - v.x * 1.5, y - v.y * 1.5
    else
        z = eye.z + math.Rand(-60, 240)
        v = Vector(wx * k.wind * math.Rand(0.8, 1.2), wy * k.wind * math.Rand(0.8, 1.2), math.Rand(-k.fall, k.fall))
        life = math.Rand(0.9, 1.6)
        x, y = x - v.x * 0.6, y - v.y * 0.6
    end
    if not cellSky(x, y, z) then return nil end
    local p0 = Vector(x, y, z)
    trIn.start, trIn.endpos, trIn.mask = p0, p0 + v * life, MASK_SOLID
    util.TraceLine(trIn)
    if tr.StartSolid then return nil end
    local tEnd = life * tr.Fraction
    if tEnd <= 0.02 then return nil end
    return { p0 = p0, v = v, born = CurTime(), tEnd = tEnd, s = math.Rand(0.7, 1.3), ph = math.Rand(0, 6.28),
        puff = math.random(3) == 1, land = tr.Hit and (tr.HitPos + Vector(0, 0, 2)) or nil }
end

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weather.world", function(depth, sky)
    if depth or sky then return end
    local cur = W.cur
    local k = W.KINDS[cur.kind]
    if not (on() and k and k.count and cur.amt > 0.01) then
        if #drops > 0 then drops = {} end
        return
    end
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local eye = EyePos()
    local now = CurTime()
    local wx, wy = windDir()
    local amt = cur.amt
    local want = math.floor(k.count * amt * math.Clamp(cvAmount:GetFloat(), 0.25, 1))
    -- Old ones out (landed, or far from you after a teleport).
    for i = #drops, 1, -1 do
        local d = drops[i]
        if now - d.born >= d.tEnd or d.p0:DistToSqr(eye) > 2500 * 2500 then
            if d.land and k.look == "rain" and #splashes < 80 and d.land:DistToSqr(eye) < 500 * 500 then
                splashes[#splashes + 1] = { pos = d.land, t = now }
            end
            drops[i] = drops[#drops]
            drops[#drops] = nil
        end
    end
    -- New ones (a fair number a frame; sky cells are cached).
    for _ = 1, math.min(want - #drops, 60) do
        local d = spawn(k, eye, wx, wy)
        if d then drops[#drops + 1] = d end
    end
    local look = k.look
    if look == "rain" then
        render.SetColorMaterial()
        for _, d in ipairs(drops) do
            P:Set(d.v) P:Mul(now - d.born) P:Add(d.p0)
            Q:Set(d.v) Q:Mul(-0.035 * d.s) Q:Add(P)
            render.DrawBeam(P, Q, 1.1, 0, 1, RAIN_COL)
        end
        render.SetMaterial(GLOW)
        for i = #splashes, 1, -1 do
            local sp = splashes[i]
            local f = (now - sp.t) / 0.18
            if f >= 1 then
                table.remove(splashes, i)
            else
                SPLASH_COL.a = 70 * (1 - f)
                local size = 4 + 10 * f
                render.DrawSprite(sp.pos, size, size * 0.5, SPLASH_COL)
            end
        end
    elseif look == "snow" then
        render.SetMaterial(GLOW)
        for _, d in ipairs(drops) do
            P:Set(d.v) P:Mul(now - d.born) P:Add(d.p0)
            -- (a little sway, each flake its own)
            P.x = P.x + math.sin(now * 1.7 + d.ph) * 12
            P.y = P.y + math.cos(now * 1.3 + d.ph * 0.7) * 12
            local size = 4.5 * d.s
            render.DrawSprite(P, size, size, SNOW_COL)
        end
    else
        render.SetMaterial(SMOKE)
        local base = 26 * amt
        for _, d in ipairs(drops) do
            if d.puff then
                local age = now - d.born
                P:Set(d.v) P:Mul(age) P:Add(d.p0)
                SAND_COL.a = base * math.sin(math.min(age / d.tEnd, 1) * math.pi)
                local size = 90 * d.s
                render.DrawSprite(P, size, size, SAND_COL)
            end
        end
        render.SetColorMaterial()
        GRIT_COL.a = 90 * amt
        for _, d in ipairs(drops) do
            if not d.puff then
                P:Set(d.v) P:Mul(now - d.born) P:Add(d.p0)
                Q:Set(d.v) Q:Mul(-0.02) Q:Add(P)
                render.DrawBeam(P, Q, 0.8, 0, 1, GRIT_COL)
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Fog: from the map's own fog toward the weather's
--------------------------------------------------------------------------

local function fogStrength()
    if not on() or not W.Cfg("fog") then return 0 end
    local k = W.KINDS[W.cur.kind]
    if not (k and k.fog) then return 0 end
    return W.cur.amt * (0.4 + 0.6 * W.exposure), k.fog
end

-- The map's fog, read while the weather isn't changing it.
local mapFog = { on = false, s = 0, e = 30000, d = 0, r = 128, g = 128, b = 128 }
local function readMapFog()
    local on_ = render.GetFogMode and render.GetFogMode() ~= MATERIAL_FOG_NONE
    local s, e = render.GetFogDistances()
    local r, g, b = render.GetFogColor()
    if on_ and e and e > 0 then
        mapFog.on, mapFog.s, mapFog.e, mapFog.d = true, s or 0, e, 0.6
        mapFog.r, mapFog.g, mapFog.b = r or 128, g or 128, b or 128
    else
        mapFog.on, mapFog.s, mapFog.e, mapFog.d = false, 0, 30000, 0
    end
end

local function setupFog(scale, skybox)
    local f, fog = fogStrength()
    if f < 0.02 then
        if not skybox then readMapFog() end
        return
    end
    scale = scale or 1
    local c = fog[4]
    local m = mapFog
    local d = math.min(1, f * 1.2)
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(Lerp(d, m.s, fog[1]) * scale)
    render.FogEnd(Lerp(d, m.e, math.min(fog[2], m.e)) * scale)
    render.FogMaxDensity(Lerp(d, m.d, math.max(fog[3], m.d)))
    if m.on then
        render.FogColor(Lerp(d, m.r, c.r), Lerp(d, m.g, c.g), Lerp(d, m.b, c.b))
    else
        render.FogColor(c.r, c.g, c.b)
    end
    return true
end
-- (after night vision's own fog: that one wins while it's on)
Rhylib.Hook.Add("SetupWorldFog", "weather.fog", function() return setupFog(1) end, 5)
Rhylib.Hook.Add("SetupSkyboxFog", "weather.fog", function(scale) return setupFog(scale, true) end, 5)

--------------------------------------------------------------------------
-- Sounds and lightning
--------------------------------------------------------------------------

local found = {}
local function pick(key)
    if found[key] ~= nil then return found[key] or nil end
    local list = W.Cfg(key)
    found[key] = false
    for _, p in ipairs(istable(list) and list or {}) do
        if isstring(p) and file.Exists("sound/" .. p, "GAME") then found[key] = p break end
    end
    return found[key] or nil
end
Rhylib.Hook.Add("Rhylib.ConfigChanged", "weather.sounds", function(m)
    if m == "weather" then found = {} end
end)

local loops = {}   -- [name] = { snd, path, again }
local function loop(name, key, vol)
    local l = loops[name]
    if vol < 0.01 then
        if l and l.snd then
            local snd = l.snd
            snd:FadeOut(1.5)
            timer.Simple(1.6, function() snd:Stop() end)   -- (holds it until faded)
            loops[name] = nil
        end
        return
    end
    local path = pick(key)
    if not path then return end
    local me = LocalPlayer()
    local now = RealTime()
    if not l or l.path ~= path or not l.snd then
        if l and l.snd then l.snd:Stop() end
        local snd = CreateSound(me, path)
        if not snd then return end
        snd:PlayEx(0.01, 100)
        local dur = SoundDuration(path) or 0
        l = { snd = snd, path = path, dur = dur, again = dur > 1 and now + dur - 0.05 or nil }
        loops[name] = l
    elseif (l.again and now >= l.again) or not l.snd:IsPlaying() then
        -- (a file without loop points ends: start it again)
        l.snd:Stop()
        l.snd:PlayEx(vol, 100)
        l.again = l.dur > 1 and now + l.dur - 0.05 or nil
    end
    l.snd:ChangeVolume(vol, 0.4)
end

local thunderAt, nextBolt = nil, 0
local flashStart, flashOn = 0, false
timer.Create("Rhylib.Weather.Sound", 0.1, 0, function()
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local k = W.KINDS[W.cur.kind]
    local amt = (on() and k and k.count) and W.cur.amt or 0
    local master = math.Clamp(cvVolume:GetFloat(), 0, 1)
    local out = 0.3 + 0.7 * W.exposure
    loop("rain", "rainSounds", (k and k.rain or 0) * amt * out * master)
    loop("wind", "windSounds", (k and k.windVol or 0) * amt * out * master)
    -- Lightning: a flash, the thunder a moment later.
    local now = CurTime()
    if k and k.lightning and amt > 0.2 and W.Cfg("lightning") then
        if now >= nextBolt then
            if nextBolt > 0 then
                flashStart, flashOn = RealTime(), true
                thunderAt = now + math.Rand(0.3, 2.5)
            end
            nextBolt = now + math.Rand(8, 22) / amt
        end
    else
        nextBolt = 0
    end
    if thunderAt and now >= thunderAt then
        thunderAt = nil
        local list = {}
        for _, p in ipairs(istable(W.Cfg("thunderSounds")) and W.Cfg("thunderSounds") or {}) do
            if isstring(p) and file.Exists("sound/" .. p, "GAME") then list[#list + 1] = p end
        end
        if #list > 0 then
            me:EmitSound(list[math.random(#list)], 75, math.random(90, 105), math.min(1, 0.6 * out * master + 0.1), CHAN_STATIC)
        end
    end
end)

-- The flash: two quick flickers, brighter outdoors.
Rhylib.Hook.Add("HUDPaintBackground", "weather.flash", function()
    if not flashOn then W.flash = 0 return end
    local t = RealTime() - flashStart
    if t > 0.45 then flashOn = false W.flash = 0 return end
    local f = t < 0.08 and 1 or (t < 0.14 and 0.25 or (t < 0.2 and 0.8 or math.max(0, 1 - (t - 0.2) / 0.25) * 0.6))
    W.flash = f
    surface.SetDrawColor(235, 240, 255, 110 * f * (0.35 + 0.65 * W.exposure))
    surface.DrawRect(0, 0, ScrW(), ScrH())
end, -10)

-- Settings rows (rhylib_menus).
local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Weather", { id = "weather.fx", order = 80, tab = "Interface", title = "Weather effects",
        desc = "Rain, snow and sand falling around you, weather fog and sounds (the weather itself is set by staff)",
        kind = "toggle", convar = "rhylib_weather_fx" })
    M.AddSetting("Weather", { id = "weather.amount", order = 81, tab = "Interface", title = "Weather amount",
        desc = "How much falls around you: lower it for more FPS", kind = "slider", convar = "rhylib_weather_amount", min = 0.25, max = 1, decimals = 2 })
    M.AddSetting("Weather", { id = "weather.volume", order = 82, tab = "Audio", title = "Weather volume",
        desc = "Rain, wind and thunder", kind = "slider", convar = "rhylib_weather_volume", min = 0, max = 1, decimals = 2 })
end
addSettings()
Rhylib.Hook.Add("InitPostEntity", "weather.settings", addSettings)
