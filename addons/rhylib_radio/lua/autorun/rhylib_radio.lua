--[[
    rhylib_radio loader (shared). Needs rhylib_core:
    Rhylib.LoadModule("radio") loads every file in lua/rhylib/radio/
    (sh_ files first, then sv_, then cl_, each group in name order).
    The jammer entities in lua/entities/ load the normal GMod way.
]]

if not Rhylib then
    print("[Rhylib] rhylib_radio needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("radio", { name = "Radio and squads", version = "0.1.0" })
