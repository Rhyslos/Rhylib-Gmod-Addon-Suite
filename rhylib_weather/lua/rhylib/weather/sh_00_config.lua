--[[
    Weather (shared): one weather for the whole server, set by staff in
    Server settings (module "weather": kind, intensity) or with the
    command below. Everything you see and hear is drawn on each client
    (cl_10_world.lua: falling rain / snow / sand, fog, sounds, lightning;
    cl_20_visor.lua: drops, frost and dust on the helmet visor), so the
    server only stores two settings and sends nothing per tick.

    Kinds (W.KINDS): clear, mist (light haze), fog (thick fog), rain,
    storm (heavy rain, wind, lightning strikes and thunder), heavystorm
    (twice the storm: rain, wind, darker fog, more lightning), snow,
    heavysnow (a blizzard: heavy snow, wind, thick white fog), sandstorm
    (sand blowing sideways, brown fog), heavysandstorm (near impossible to
    see through). The normal snow and sandstorm put half the frost / dust
    on the visor their heavy versions do. Heavy storms, heavy snow and
    heavy sandstorms cut comms and the compass radar now and then
    (sv_10_weather.lua; rhylib_radio asks W.JamFor), and lightning strikes
    cut them briefly near them. A change cross-fades straight from the old
    weather to the new one over fadeTime seconds (snow to heavy snow
    without clear sky in between). A saved "blizzard" reads as heavysnow.

    Command (Rhylib.Command): rhylib_weather [kind] [intensity 0.1-1],
    chat !weather; permission rhylib.weather (admin). "noef" anywhere in
    it (!weather heavy snow noef) sets the weather without its visor effect
    (setting visorFx off; any !weather with a kind and no noef turns it
    back on). "heavy storm" (or "heavy" alone), "heavy snow" and "heavy
    sandstorm" are the heavystorm, heavysnow and heavysandstorm kinds;
    "heavy <other kind>" sets that kind at full intensity, "light <kind>"
    at 30%. No kind = says the
    current weather. It sets the same settings as the Server settings
    page (saved, sent to everyone).

    Light (cl_30_grade.lua): each weather tints and darkens the screen a
    little (W.KINDS[kind].grade), cross-fading with it, weaker indoors.

    Earthquake (sv_20_quake.lua, cl_40_quake.lua): a game master event
    that runs alongside the weather (it doesn't change it): !weather
    earthquake [level 1-3 | light | strong | violent] [seconds] (also
    "quake"). The whole map shakes: screen shake that builds, peaks and
    eases, a rumble, dust and bits falling from ceilings indoors, loose
    props rattling. Nobody is hurt or knocked over.

    The weather doesn't carry over a map change: each new map starts
    clear, with the visor effect on (sv_10_weather.lua resets kind and
    visorFx once per map; a host file's kind still counts).

    Adds Rhylib.Weather (W): W.KINDS, W.ORDER, W.Cfg(key), W.Kind() ->
    kind id (unknown values read as "clear"), W.Intensity() -> 0.1-1,
    W.Quake(level, secs) (server) -> ok, why.
]]

Rhylib.Weather = Rhylib.Weather or {}
local W = Rhylib.Weather
local Config = Rhylib.Config

Config.Describe("weather", { name = "Weather", category = "Server & interface" })
Config.Register("weather", "kind", "clear", "Weather for everyone: clear, mist, fog, rain, storm, heavystorm, snow, heavysnow, sandstorm or heavysandstorm")
Config.Register("weather", "intensity", 0.7, "How strong the weather is, 0.1 (light) to 1 (heavy)")
Config.Meta("weather", "intensity", { min = 0.1, max = 1, step = 0.05 })
Config.Register("weather", "fadeTime", 12, "Seconds a change takes: the old weather fades out while the new one fades in")
Config.Register("weather", "visorFx", true, "Weather shows on the helmet visor (drops, frost, dust); !weather <kind> noef turns it off for that weather, the next !weather without noef back on")
Config.Register("weather", "fog", true, "Weather fog (thicker in storms, heavy snow and sandstorms); off keeps the map's own fog")
Config.Register("weather", "lightning", true, "Storms have lightning strikes: a bolt and a flash lighting up the area, thunder after it (sooner and louder the closer it is)")
Config.Register("weather", "disrupt", true, "Heavy storms, heavy snow and heavy sandstorms (from disruptFrom) now and then cut comms and the compass radar for a few seconds for everyone outdoors; a lightning strike does it briefly near it")
Config.Register("weather", "disruptFrom", 0.6, "Intensity from which heavy storms, heavy snow and heavy sandstorms disrupt comms")
Config.Register("weather", "disruptEvery", 60, "Seconds between comms disruptions at full intensity (more apart when weaker)")
Config.Register("weather", "strikeJamRadius", 900, "Units around a lightning strike where outdoor comms drop for a moment")
Config.Register("weather", "grade", true, "Weather light: each weather tints and darkens the screen a little (darker in storms, white in heavy snow, brown in sandstorms); weaker indoors")
Config.Register("weather", "gradeStrength", 1, "Weather light: how strong the tint and darkening are (0.5 = half, 1.5 = half again)")
Config.Register("weather", "quakeTimeLight", { 3, 6 }, "Earthquake, light (level 1): with no time given it lasts a random time between these seconds (3-16; never longer than 16)")
Config.Register("weather", "quakeTimeStrong", { 5, 10 }, "Earthquake, strong (level 2): with no time given it lasts a random time between these seconds (3-16; never longer than 16)")
Config.Register("weather", "quakeTimeViolent", { 8, 16 }, "Earthquake, violent (level 3): with no time given it lasts a random time between these seconds (3-16; never longer than 16)")
Config.Register("weather", "quakeShake", 1, "Earthquake: screen shake multiplier (players can lower it for themselves)")
Config.Register("weather", "quakeProps", true, "Earthquake: loose (unfrozen) props near players rattle and slide")
Config.Register("weather", "quakeDust", true, "Earthquake: dust and small bits fall from ceilings around players indoors")
Config.Register("weather", "quakeSounds", { "ambient/atmosphere/city_rumble_loop1.wav", "ambient/atmosphere/underground_hall_loop1.wav", "ambient/atmosphere/terrain_rumble1.wav" },
    "Earthquake rumble loop: the first of these sound files the game has is used")
Config.Register("weather", "rainSounds", { "ambient/weather/rumble_rain_nowind.wav", "ambient/weather/rumble_rain.wav", "ambient/water/water_flow_loop1.wav" },
    "Rain loop: the first of these sound files the game has is used")
Config.Register("weather", "windSounds", { "ambient/wind/wind_rooftop1.wav", "ambient/wind/wind1.wav", "ambient/levels/canals/windmill_wind_loop1.wav", "ambient/wind/windgust.wav" },
    "Wind loop (storm, snow, heavy snow, sandstorms): the first of these sound files the game has is used")
Config.Register("weather", "thunderSounds", { "ambient/atmosphere/thunder1.wav", "ambient/atmosphere/thunder2.wav", "ambient/atmosphere/thunder3.wav", "ambient/atmosphere/thunder4.wav" },
    "Thunder: one of these (the ones the game has) after each lightning flash")

W.Cfg = Config.For and Config.For("weather") or function(k) return Config.Get("weather", k) end

-- count: falling things around you at full intensity; fall: units/s
-- down; wind: sideways speed; fog: start, end (units, at full strength),
-- max density, colour; rain / wind: loop volumes; visor: what lands on it
-- (drops, frost, dust, mist = small beads; sandFx scales the sand streaks,
-- grain hits and gusts; visorRate drops / flakes / beads a second); lightning = { min, max } seconds between
-- strikes at full intensity; disrupt: heavy enough to cut comms now and
-- then (from disruptFrom intensity); grade = the light: { brightness,
-- contrast, colour (saturation), add red, add green, add blue } at full
-- intensity outdoors (rhylib_weather_grade_tune tunes them live).
W.KINDS = {
    clear = { name = "Clear" },
    mist = { name = "Mist", look = "mist", count = 50, fall = 0, wind = 18, radius = 900,
        fog = { 0, 3200, 0.6, Color(172, 180, 188) }, rain = 0, windVol = 0, visor = "mist", visorRate = 1.5,
        grade = { 0.01, 0.92, 0.82, 0, 0, 0.004 } },
    fog = { name = "Fog", look = "mist", count = 90, fall = 0, wind = 12, radius = 800,
        fog = { 0, 850, 0.94, Color(160, 166, 172) }, rain = 0, windVol = 0.08, visor = "mist", visorRate = 3,
        grade = { 0.02, 0.86, 0.7, 0, 0, 0.006 } },
    rain = { name = "Rain", look = "rain", count = 420, fall = 1300, wind = 0.12, radius = 700,
        fog = { 200, 7000, 0.45, Color(105, 112, 122) }, rain = 0.55, windVol = 0, visor = "drops", visorRate = 9, wetRate = 0.03,
        grade = { -0.03, 0.95, 0.85, 0, 0, 0.006 } },
    storm = { name = "Storm", look = "rain", count = 750, fall = 1600, wind = 0.35, radius = 700,
        fog = { 150, 3800, 0.65, Color(80, 86, 96) }, rain = 0.85, windVol = 0.45, visor = "drops", visorRate = 22, wetRate = 0.06,
        lightning = { 9, 24 }, grade = { -0.06, 0.92, 0.7, -0.004, 0, 0.01 } },
    heavystorm = { name = "Heavy storm", look = "rain", count = 1100, fall = 1900, wind = 0.6, radius = 700,
        fog = { 80, 1900, 0.82, Color(62, 67, 77) }, rain = 1, windVol = 0.9, visor = "drops", visorRate = 45, wetRate = 0.12,
        lightning = { 4, 11 }, disrupt = true, grade = { -0.11, 0.88, 0.55, -0.008, -0.004, 0.012 } },
    -- (snow and sandstorm: half the visor frost / dust / sand of their heavy versions)
    snow = { name = "Snow", look = "snow", count = 380, fall = 110, wind = 40, radius = 650,
        fog = { 200, 4500, 0.55, Color(200, 206, 216) }, rain = 0, windVol = 0.15, visor = "frost", frostRate = 0.025, frostMax = 0.21, visorRate = 2.25,
        grade = { 0.02, 0.95, 0.85, -0.004, 0, 0.012 } },
    heavysnow = { name = "Heavy snow", look = "snow", count = 750, fall = 220, wind = 380, radius = 600,
        fog = { 60, 1300, 0.85, Color(215, 222, 232) }, rain = 0, windVol = 0.75, visor = "frost", frostRate = 0.05, frostMax = 0.425, visorRate = 4.5,
        disrupt = true, grade = { 0.05, 0.86, 0.62, -0.008, 0.002, 0.02 } },
    sandstorm = { name = "Sandstorm", look = "sand", count = 180, fall = 30, wind = 520, radius = 650,
        fog = { 150, 3200, 0.7, Color(176, 140, 96) }, rain = 0, windVol = 0.55, visor = "dust", dustRate = 0.0175, dustMax = 0.19, visorRate = 0, sandFx = 0.25,
        grade = { -0.02, 0.95, 0.85, 0.02, 0.008, -0.01 } },
    heavysandstorm = { name = "Heavy sandstorm", look = "sand", count = 360, fall = 50, wind = 900, radius = 650,
        fog = { 0, 420, 0.97, Color(168, 130, 86) }, rain = 0, windVol = 1, visor = "dust", dustRate = 0.035, dustMax = 0.375, visorRate = 0, sandFx = 0.5,
        disrupt = true, grade = { -0.08, 0.9, 0.75, 0.045, 0.018, -0.02 } },
}
W.ORDER = { "clear", "mist", "fog", "rain", "storm", "heavystorm", "snow", "heavysnow", "sandstorm", "heavysandstorm" }
do
    local opts = {}
    for i, k in ipairs(W.ORDER) do opts[i] = { k, W.KINDS[k].name } end
    Rhylib.Config.Meta("weather", "kind", { options = opts })
end

-- Old names that still read (a saved "blizzard" from before heavysnow).
W.ALIASES = { blizzard = "heavysnow" }

-- W.Kind() -> the weather now ("clear" for anything unknown).
function W.Kind()
    local k = string.Trim(string.lower(tostring(W.Cfg("kind") or "clear")))
    k = W.ALIASES[k] or k
    return W.KINDS[k] and k or "clear"
end

-- The heavy version of a kind ("heavy snow" -> heavysnow), or nil.
W.HEAVY = { storm = "heavystorm", snow = "heavysnow", sandstorm = "heavysandstorm", sand = "heavysandstorm" }

-- W.Intensity() -> 0.1-1.
function W.Intensity()
    return math.Clamp(tonumber(W.Cfg("intensity")) or 0.7, 0.1, 1)
end

Rhylib.Command.Add({
    name = "rhylib_weather",
    chat = { "weather" },
    perm = "rhylib.weather",
    minAccess = "admin",
    help = "Set the weather for everyone: clear, mist, fog, rain, storm, snow, sandstorm (and an intensity 0.1-1 or 10-100). heavy storm / heavy snow / heavy sandstorm = their heavy versions (heavy alone = heavy storm), heavy <other kind> = full strength, light <kind> = 30%; add noef to leave out the visor effect. earthquake [1-3] [seconds] = an earthquake alongside the weather (no seconds: a random time, longer the stronger). The weather resets to clear on a map change",
    args = "[kind | earthquake] [intensity | level] [noef | seconds]",
    tag = "Weather",
    fn = function(ply, args)
        -- (noef anywhere: no visor effect)
        local noef = false
        for i = #args, 1, -1 do
            if string.lower(string.Trim(args[i])) == "noef" then
                table.remove(args, i)
                noef = true
            end
        end
        local kind = args[1] and string.Trim(string.lower(args[1]))
        -- An earthquake: alongside the weather, which stays as it is.
        if kind == "earthquake" or kind == "quake" then
            if not W.Quake then return "Earthquakes run on the server", "bad" end
            local a2 = args[2] and string.lower(string.Trim(args[2])) or ""
            local named = { light = 1, strong = 2, violent = 3 }
            local lv, secs = named[a2] or tonumber(a2), tonumber(args[3])
            -- (one number above 3: the seconds, e.g. !weather quake 30)
            if lv and lv > 3 and not secs then lv, secs = nil, lv end
            lv = math.Clamp(math.floor(lv or 2), 1, 3)
            local ok, why = W.Quake(lv, secs)
            if not ok then return why, "bad" end
            return string.format("Earthquake: %s for %d s", W.QUAKE_NAMES[lv], why), "good"
        end
        local nArg, forceAmt = 2, nil
        -- "heavy" / "heavy storm" = heavystorm, "heavy snow" = heavysnow,
        -- "heavy sandstorm" = heavysandstorm; "heavy <other kind>" = that
        -- kind at full strength, "light <kind>" = that kind at 30%
        if kind == "heavy" or kind == "light" then
            local nextw = args[2] and string.Trim(string.lower(args[2]))
            if kind == "heavy" and (not nextw or nextw == "" or tonumber(nextw)) then
                kind = "heavystorm"
                nArg = 2
            elseif kind == "heavy" and W.HEAVY[nextw] then
                kind = W.HEAVY[nextw]
                nArg = 3
            elseif nextw and W.KINDS[nextw] and nextw ~= "clear" then
                forceAmt = (kind == "heavy") and 1 or 0.3
                kind = nextw
                nArg = 3
            end
        end
        if not kind or kind == "" then
            local k = W.Kind()
            return string.format("Weather: %s%s", W.KINDS[k].name, k == "clear" and "" or string.format(" (%d%%)", math.Round(W.Intensity() * 100)))
        end
        if kind == "blizzard" then return "Blizzard is now: !weather heavy snow", "bad" end
        if not W.KINDS[kind] then return "Unknown weather. Use: " .. table.concat(W.ORDER, ", ") .. " (or heavy snow / heavy sandstorm / heavy storm)", "bad" end
        if not (Rhylib.Settings and Rhylib.Settings.Set) then return "Settings aren't available", "bad" end
        local ok, why = Rhylib.Settings.Set("weather", "kind", kind, ply)
        if ok == false then return "Couldn't set it: " .. tostring(why), "bad" end
        Rhylib.Settings.Set("weather", "visorFx", not noef, ply)
        local n = tonumber(args[nArg]) or forceAmt
        if n then
            if n >= 2 then n = n / 100 end   -- (70 = 70%; 0.1-1 as it is)
            Rhylib.Settings.Set("weather", "intensity", math.Clamp(n, 0.1, 1), ply)
        end
        return string.format("Weather: %s%s (fades in over %d s)%s", W.KINDS[kind].name,
            kind == "clear" and "" or string.format(" %d%%", math.Round(W.Intensity() * 100)), W.Cfg("fadeTime"),
            noef and " (no visor effect)" or ""), "good"
    end,
})

-- Earthquake (sv_20_quake.lua runs it): !weather earthquake [1-3] [seconds].
W.QUAKE_NAMES = { "light", "strong", "violent" }

-- W.QuakeEnvelope(q, now) -> how strong a quake { level, start, secs } is
-- now (0-1): builds over the first fifth, eases out over the last third.
function W.QuakeEnvelope(q, now)
    local t = (now - q.start) / q.secs
    if t < 0 or t > 1 then return 0 end
    if t < 0.2 then return math.sin(t / 0.2 * math.pi * 0.5) end
    if t > 0.66 then return math.cos((t - 0.66) / 0.34 * math.pi * 0.5) end
    return 1
end
