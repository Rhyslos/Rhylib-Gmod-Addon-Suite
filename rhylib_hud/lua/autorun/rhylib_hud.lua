--[[
    rhylib_hud loader (shared). Runs on both realms when the addon loads.
    Needs rhylib_core: Rhylib.LoadModule("hud") loads every file in
    lua/rhylib/hud/ (sh_ files first, then sv_, then cl_, each group in
    name order) and sends the cl_ and sh_ files to clients.
]]

if not Rhylib then
    print("[Rhy's] Rhy's HUD (rhylib_hud) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("hud", { name = "Rhy's HUD", version = "0.1.0" })
