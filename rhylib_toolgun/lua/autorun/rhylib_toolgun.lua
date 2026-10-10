-- rhylib_toolgun loader (shared): loads lua/rhylib/toolgun/ through the core.
-- The staff toolgun: place Rhylib things, NPCs and spawn-menu things.
if not Rhylib then
    print("[Rhylib] rhylib_toolgun needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("toolgun", { name = "Toolgun", version = "0.1.0" })
