-- rhylib_menus loader (shared). Runs on server and client at startup.
-- Needs rhylib_core (which defines Rhylib.LoadModule). LoadModule then loads
-- every file in lua/rhylib/menus/ by prefix and number: sh_00_config on
-- both sides, then the cl_ files on clients (cl_00_kit first, since every
-- page uses the Kit). The addon has no server files.

if not Rhylib then
    print("[Rhylib] rhylib_menus needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("menus", { name = "Menus", version = "0.1.0" })
