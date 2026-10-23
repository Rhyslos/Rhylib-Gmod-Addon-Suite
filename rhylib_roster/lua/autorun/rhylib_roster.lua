if not Rhylib then
    print("[Rhy's] Rhy's Roster (rhylib_roster) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

-- Loader for rhylib_roster (shared autorun). Characters, ranks and
-- battalion membership; the module files are in lua/rhylib/roster/ and
-- load shared, then server, then client. The UI uses rhylib_menus.
Rhylib.LoadModule("roster", { name = "Rhy's Roster", version = "0.1.0" })
