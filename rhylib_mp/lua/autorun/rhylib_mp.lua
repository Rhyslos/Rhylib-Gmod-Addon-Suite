--[[
    rhylib_mp autorun (shared). Loads the "mp" module: every file in
    lua/rhylib/mp/ (sh_ first, then sv_, then cl_, in name order).
    Needs rhylib_core; without it the addon prints a line and stops.
]]

if not Rhylib then
    print("[Rhylib] rhylib_mp needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("mp", { name = "Military police", version = "0.1.0" })
