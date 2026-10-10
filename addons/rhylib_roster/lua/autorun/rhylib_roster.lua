if not Rhylib then
    print("[Rhylib] rhylib_roster needs rhylib_core. Install it and restart the map.")
    return
end

-- Loader for rhylib_roster (shared autorun). Characters, ranks and
-- battalion membership; the module files are in lua/rhylib/roster/ and
-- load shared, then server, then client. The UI uses rhylib_menus.
Rhylib.LoadModule("roster", { name = "Roster", version = "0.1.0" })
