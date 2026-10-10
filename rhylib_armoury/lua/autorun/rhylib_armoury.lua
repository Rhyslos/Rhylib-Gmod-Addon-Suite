-- rhylib_armoury loader (shared, runs on server and client). Loads the
-- module files in lua/rhylib/armoury/ through rhylib_core: sh_ first, then
-- sv_, then cl_. The entities in lua/entities/ load the normal GMod way.
if not Rhylib then
    print("[Rhylib] rhylib_armoury needs rhylib_core. Install it and restart the map.")
    return
end

-- Needs rhylib_inventory too. That loads after this file (alphabetical),
-- so the armoury code only looks it up when it's used.
Rhylib.LoadModule("armoury", { name = "Armoury", version = "0.1.0" })
