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
    blizzard (heavy snow, wind, thick white fog), sandstorm (sand blowing
    sideways, brown fog). Heavy storms, blizzards and sandstorms cut comms
    and the compass radar now and then (sv_10_weather.lua; rhylib_radio
    asks W.JamFor), and lightning strikes cut them briefly near them. A change fades the old
    weather out and the new one in over fadeTime seconds.

    Command (Rhylib.Command): rhylib_weather [kind] [intensity 0.1-1],
    chat !weather; permission rhylib.weather (admin). "heavy <kind>" sets
    that kind at full intensity, "light <kind>" at 30%; "heavy" or "heavy
    storm" alone is the heavystorm kind. No kind = says the
    current weather. It sets the same settings as the Server settings
    page (saved, sent to everyone).

    Adds Rhylib.Weather (W): W.KINDS, W.ORDER, W.Cfg(key), W.Kind() ->
    kind id (unknown values read as "clear"), W.Intensity() -> 0.1-1.
]]

Rhylib.Weather = Rhylib.Weather or {}
local W = Rhylib.Weather
local Config = Rhylib.Config

Config.Describe("weather", { name = "Weather", category = "Server & interface" })
Config.Register("weather", "kind", "clear", "Weather for everyone: clear, mist, fog, rain, storm, heavystorm, snow, blizzard or sandstorm")
Config.Register("weather", "intensity", 0.7, "How strong the weather is, 0.1 (light) to 1 (heavy)")
Config.Register("weather", "fadeTime", 12, "Seconds the old weather takes to fade out and the new one to fade in")
Config.Register("weather", "fog", true, "Weather fog (thicker in storms, blizzards and sandstorms); off keeps the map's own fog")
Config.Register("weather", "lightning", true, "Storms have lightning strikes: a bolt and a flash lighting up the area, thunder after it (sooner and louder the closer it is)")
Config.Register("weather", "disrupt", true, "Heavy storms, blizzards and sandstorms (from disruptFrom) now and then cut comms and the compass radar for a few seconds for everyone outdoors; a lightning strike does it briefly near it")
Config.Register("weather", "disruptFrom", 0.6, "Intensity from which heavy storms, blizzards and sandstorms disrupt comms")
Config.Register("weather", "disruptEvery", 60, "Seconds between comms disruptions at full intensity (more apart when weaker)")
Config.Register("weather", "strikeJamRadius", 900, "Units around a lightning strike where outdoor comms drop for a moment")
Config.Register("weather", "rainSounds", { "ambient/weather/rumble_rain_nowind.wav", "ambient/weather/rumble_rain.wav", "ambient/water/water_flow_loop1.wav" },
    "Rain loop: the first of these sound files the game has is used")
Config.Register("weather", "windSounds", { "ambient/wind/wind_rooftop1.wav", "ambient/wind/wind1.wav", "ambient/levels/canals/windmill_wind_loop1.wav", "ambient/wind/windgust.wav" },
    "Wind loop (storm, snow, blizzard, sandstorm): the first of these sound files the game has is used")
Config.Register("weather", "thunderSounds", { "ambient/atmosphere/thunder1.wav", "ambient/atmosphere/thunder2.wav", "ambient/atmosphere/thunder3.wav", "ambient/atmosphere/thunder4.wav" },
    "Thunder: one of these (the ones the game has) after each lightning flash")

W.Cfg = Config.For and Config.For("weather") or function(k) return Config.Get("weather", k) end

-- count: falling things around you at full intensity; fall: units/s
-- down; wind: sideways speed; fog: start, end (units, at full strength),
-- max density, colour; rain / wind: loop volumes; visor: what lands on it
-- (drops, frost, dust, mist); lightning = { min, max } seconds between
-- strikes at full intensity; disrupt: heavy enough to cut comms now and
-- then (from disruptFrom intensity).
W.KINDS = {
    clear = { name = "Clear" },
    mist = { name = "Mist", look = "mist", count = 50, fall = 0, wind = 18, radius = 900,
        fog = { 0, 3200, 0.6, Color(172, 180, 188) }, rain = 0, windVol = 0, visor = "mist", mistRate = 0.02, mistMax = 0.35 },
    fog = { name = "Fog", look = "mist", count = 90, fall = 0, wind = 12, radius = 800,
        fog = { 0, 850, 0.94, Color(160, 166, 172) }, rain = 0, windVol = 0.08, visor = "mist", mistRate = 0.04, mistMax = 0.6 },
    rain = { name = "Rain", look = "rain", count = 420, fall = 1300, wind = 0.12, radius = 700,
        fog = { 200, 7000, 0.45, Color(105, 112, 122) }, rain = 0.55, windVol = 0, visor = "drops", visorRate = 9, wetRate = 0.03 },
    storm = { name = "Storm", look = "rain", count = 750, fall = 1600, wind = 0.35, radius = 700,
        fog = { 150, 3800, 0.65, Color(80, 86, 96) }, rain = 0.85, windVol = 0.45, visor = "drops", visorRate = 22, wetRate = 0.06,
        lightning = { 9, 24 } },
    heavystorm = { name = "Heavy storm", look = "rain", count = 1100, fall = 1900, wind = 0.6, radius = 700,
        fog = { 80, 1900, 0.82, Color(62, 67, 77) }, rain = 1, windVol = 0.9, visor = "drops", visorRate = 45, wetRate = 0.12,
        lightning = { 4, 11 }, disrupt = true },
    snow = { name = "Snow", look = "snow", count = 380, fall = 110, wind = 40, radius = 650,
        fog = { 200, 4500, 0.55, Color(200, 206, 216) }, rain = 0, windVol = 0.15, visor = "frost", frostRate = 0.018, frostMax = 0.5, visorRate = 3 },
    blizzard = { name = "Blizzard", look = "snow", count = 750, fall = 220, wind = 380, radius = 600,
        fog = { 60, 1300, 0.85, Color(215, 222, 232) }, rain = 0, windVol = 0.75, visor = "frost", frostRate = 0.05, frostMax = 0.85, visorRate = 9,
        disrupt = true },
    sandstorm = { name = "Sandstorm", look = "sand", count = 260, fall = 40, wind = 750, radius = 650,
        fog = { 60, 1400, 0.85, Color(176, 140, 96) }, rain = 0, windVol = 0.8, visor = "dust", dustRate = 0.035, dustMax = 0.75, visorRate = 0,
        disrupt = true },
}
W.ORDER = { "clear", "mist", "fog", "rain", "storm", "heavystorm", "snow", "blizzard", "sandstorm" }

-- W.Kind() -> the weather now ("clear" for anything unknown).
function W.Kind()
    local k = string.Trim(string.lower(tostring(W.Cfg("kind") or "clear")))
    return W.KINDS[k] and k or "clear"
end

-- W.Intensity() -> 0.1-1.
function W.Intensity()
    return math.Clamp(tonumber(W.Cfg("intensity")) or 0.7, 0.1, 1)
end

Rhylib.Command.Add({
    name = "rhylib_weather",
    chat = { "weather" },
    perm = "rhylib.weather",
    minAccess = "admin",
    help = "Set the weather for everyone: clear, mist, fog, rain, storm, heavystorm, snow, blizzard, sandstorm (and an intensity 0.1-1 or 10-100). heavy <kind> = full strength, light <kind> = 30%, heavy / heavy storm = heavystorm",
    args = "[kind] [intensity]",
    tag = "Weather",
    fn = function(ply, args)
        local kind = args[1] and string.Trim(string.lower(args[1]))
        local nArg, forceAmt = 2, nil
        -- "heavy" / "heavy storm" = heavystorm; "heavy <kind>" = that kind
        -- at full strength, "light <kind>" = that kind at 30%
        if kind == "heavy" or kind == "light" then
            local nextw = args[2] and string.Trim(string.lower(args[2]))
            if kind == "heavy" and (not nextw or nextw == "" or nextw == "storm" or tonumber(nextw)) then
                kind = "heavystorm"
                nArg = (nextw == "storm") and 3 or 2
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
        if not W.KINDS[kind] then return "Unknown weather. Use: " .. table.concat(W.ORDER, ", "), "bad" end
        if not (Rhylib.Settings and Rhylib.Settings.Set) then return "Settings aren't available", "bad" end
        local ok, why = Rhylib.Settings.Set("weather", "kind", kind, ply)
        if ok == false then return "Couldn't set it: " .. tostring(why), "bad" end
        local n = tonumber(args[nArg]) or forceAmt
        if n then
            if n >= 2 then n = n / 100 end   -- (70 = 70%; 0.1-1 as it is)
            Rhylib.Settings.Set("weather", "intensity", math.Clamp(n, 0.1, 1), ply)
        end
        return string.format("Weather: %s%s (fades in over %d s)", W.KINDS[kind].name,
            kind == "clear" and "" or string.format(" %d%%", math.Round(W.Intensity() * 100)), W.Cfg("fadeTime")), "good"
    end,
})
