-- rhylib_jetpack loader (shared): loads lua/rhylib/jetpack/ through the core.
-- A predicted jetpack worn in the inventory's Back slot.
if not Rhylib then
    print("[Rhy's] Rhy's Jetpack (rhylib_jetpack) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("jetpack", {
    name = "Rhy's Jetpack",
    version = "0.1.0",
    wants = { "inventory" },
})
