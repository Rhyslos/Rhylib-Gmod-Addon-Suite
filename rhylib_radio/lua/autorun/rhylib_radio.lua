--[[
    rhylib_radio loader (shared). Needs rhylib_core:
    Rhylib.LoadModule("radio") loads every file in lua/rhylib/radio/
    (sh_ files first, then sv_, then cl_, each group in name order).
    The jammer entities in lua/entities/ load the normal GMod way.
]]

if not Rhylib then
    print("[Rhy's] Rhy's Radio & Squads (rhylib_radio) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("radio", { name = "Rhy's Radio & Squads", version = "0.1.0" })
