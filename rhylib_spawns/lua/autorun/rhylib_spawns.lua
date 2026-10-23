-- rhylib_spawns loader (shared): loads lua/rhylib/spawns/ through the core.
-- Named, per-battalion respawn points and staff-run event spawns.
if not Rhylib then
    print("[Rhy's] Rhy's Spawn Points (rhylib_spawns) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("spawns", { name = "Rhy's Spawn Points", version = "0.1.0" })
