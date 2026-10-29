-- rhylib_toolgun loader (shared): loads lua/rhylib/toolgun/ through the core.
-- The staff toolgun: place Rhylib things, NPCs and spawn-menu things.
if not Rhylib then
    print("[Rhy's] Rhy's Toolgun (rhylib_toolgun) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("toolgun", {
    name = "Rhy's Toolgun",
    version = "0.1.0",
    needs = { "weapons" },
})
