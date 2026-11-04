-- rhylib_weather loader (shared): loads lua/rhylib/weather/ through the
-- core. Server-wide weather (rain, storm, snow, heavy snow, sandstorms) with
-- effects on the clone helmet's visor and the screen's light, and the
-- earthquake event (!weather earthquake).
if not Rhylib then
    print("[Rhy's] Rhy's Weather (rhylib_weather) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("weather", { name = "Rhy's Weather", version = "0.1.0", wants = { "gear", "thirdperson", "menus" } })
