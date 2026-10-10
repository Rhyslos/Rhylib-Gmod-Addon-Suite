-- Loader for rhylib_admin (runs on server and client).
-- Needs rhylib_core: without it this file prints a note and stops.
-- Rhylib.LoadModule("admin") then loads lua/rhylib/admin/*.lua
-- (sh_ files first, then sv_, then cl_, in number order).
if not Rhylib then
    print("[Rhylib] rhylib_admin needs rhylib_core. Install it and restart the map.")
    return
end

-- Staff ranks, permissions (CAMI provider), commands, bans and logs.
-- Replaces ULX / SAM / FAdmin.
Rhylib.LoadModule("admin", { name = "Admin", version = "0.1.0" })
