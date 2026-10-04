if not Rhylib then
    print("[Rhylib] rhylib_spawns needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("spawns", { name = "Spawn points", version = "0.1.0" })
