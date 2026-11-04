--[[
    Weather light (client): each weather tints and darkens the screen a
    little (W.KINDS[kind].grade = { brightness, contrast, colour, add
    red, add green, add blue } at full intensity), so a heavy storm feels
    overcast and grey, heavy snow bright and white, a sandstorm brown.
    No networking: it follows the weather each client already has
    (W.Layers, so it cross-fades with it). Indoors it is about half as
    strong; a lightning flash cuts through it; night vision (rhylib_gear)
    turns it off while it's on.

    Settings: weather grade (on/off), gradeStrength. Client convar
    rhylib_weather_grade (Settings > Interface "Weather light").

    Tuning (client console, only changes your own screen until the map
    changes): rhylib_weather_grade_tune <brightness> <contrast> <colour>
    [red] [green] [blue] sets the values for the weather showing now;
    with no numbers it prints the current ones as a line for
    sh_00_config.lua. rhylib_weather_grade_tune reset drops your changes.

    Hook: RenderScreenspaceEffects "weather.grade" (-5, before night vision).
]]

local W = Rhylib.Weather

local cvGrade = CreateClientConVar("rhylib_weather_grade", "1", true, false, "Weather: tint and darken the screen with the weather")

local tune = {}   -- [kind] = { b, c, col, r, g, b } (this session only)
local function gradeOf(kind)
    local k = W.KINDS[kind]
    return tune[kind] or (k and k.grade)
end

local mod = {
    ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1,
    ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

Rhylib.Hook.Add("RenderScreenspaceEffects", "weather.grade", function()
    if not cvGrade:GetBool() or W.Cfg("grade") == false then return end
    local G = Rhylib.Gear
    if G and G.NightVision and G.NightVision() then return end
    if not W.Layers then return end
    local b, c, col, ar, ag, ab = 0, 0, 0, 0, 0, 0
    local any = false
    for _, l in ipairs(W.Layers()) do
        local g = gradeOf(l.kind)
        if g and l.amt > 0.01 then
            any = true
            local a = l.amt
            b, c, col = b + g[1] * a, c + (g[2] - 1) * a, col + (g[3] - 1) * a
            ar, ag, ab = ar + (g[4] or 0) * a, ag + (g[5] or 0) * a, ab + (g[6] or 0) * a
        end
    end
    if not any then return end
    -- (half as strong indoors; a lightning flash cuts through)
    local f = math.Clamp(tonumber(W.Cfg("gradeStrength")) or 1, 0, 3) * (0.5 + 0.5 * (W.exposure or 1)) * (1 - math.Clamp(W.flash or 0, 0, 1) * 0.8)
    if f <= 0.01 then return end
    mod["$pp_colour_brightness"] = b * f
    mod["$pp_colour_contrast"] = math.max(0, 1 + c * f)
    mod["$pp_colour_colour"] = math.max(0, 1 + col * f)
    mod["$pp_colour_addr"], mod["$pp_colour_addg"], mod["$pp_colour_addb"] = ar * f, ag * f, ab * f
    DrawColorModify(mod)
end, -5)

concommand.Add("rhylib_weather_grade_tune", function(_, _, args)
    local kind = W.Kind()
    if args[1] == "reset" then
        tune = {}
        print("[Rhylib:weather] Grade tuning cleared.")
        return
    end
    if #args == 0 then
        local g = gradeOf(kind) or { 0, 1, 1, 0, 0, 0 }
        print(string.format("[Rhylib:weather] %s: grade = { %s, %s, %s, %s, %s, %s }%s", kind,
            g[1], g[2], g[3], g[4] or 0, g[5] or 0, g[6] or 0, tune[kind] and " (tuned)" or ""))
        return
    end
    local g = {}
    local base = gradeOf(kind) or { 0, 1, 1, 0, 0, 0 }
    for i = 1, 6 do g[i] = tonumber(args[i]) or base[i] or 0 end
    tune[kind] = g
    print(string.format("[Rhylib:weather] %s now: grade = { %s, %s, %s, %s, %s, %s }", kind, g[1], g[2], g[3], g[4], g[5], g[6]))
end, nil, "Weather light, current weather: <brightness> <contrast> <colour> [red] [green] [blue]; no numbers prints them; reset clears")

-- Settings row (rhylib_menus).
local function addSettings()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Weather", { id = "weather.grade", order = 84, tab = "Interface", title = "Weather light",
        desc = "The weather tints and darkens the screen a little (darker in storms, white in heavy snow, brown in sandstorms)",
        kind = "toggle", convar = "rhylib_weather_grade" })
end
addSettings()
Rhylib.Hook.Add("InitPostEntity", "weather.gradesettings", addSettings)
