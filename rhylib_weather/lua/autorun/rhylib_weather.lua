-- rhylib_weather loader (shared): loads lua/rhylib/weather/ through the
-- core. Server-wide weather (rain, storm, snow, blizzard, sandstorm) with
-- effects on the clone helmet's visor.
if not Rhylib then
    print("[Rhy's] Rhy's Weather (rhylib_weather) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("weather", { name = "Rhy's Weather", version = "0.1.0", wants = { "gear", "thirdperson", "menus" } })
