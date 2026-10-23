--[[
    rhylib_mp autorun (shared). Loads the "mp" module: every file in
    lua/rhylib/mp/ (sh_ first, then sv_, then cl_, in name order).
    Needs rhylib_core; without it the addon prints a line and stops.
]]

if not Rhylib then
    print("[Rhy's] Rhy's Military Police (rhylib_mp) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("mp", { name = "Rhy's Military Police", version = "0.1.0" })
