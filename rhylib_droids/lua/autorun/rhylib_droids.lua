--[[
    rhylib_droids autorun (shared). Loads the "droids" module: every file in
    lua/rhylib/droids/ (sh_ first, then sv_, then cl_, in name order).
    The NPC classes themselves live in lua/entities/ and load on their own.
    Needs rhylib_core; without it the addon prints a line and stops.
]]

if not Rhylib then
    print("[Rhy's] Rhy's Droids & Clones (rhylib_droids) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

-- Droids shoot rhylib_weapons bolts; it's looked up when they fire.
Rhylib.LoadModule("droids", {
    name = "Rhy's Droids & Clones",
    version = "0.1.0",
    needs = { "weapons" },
})
