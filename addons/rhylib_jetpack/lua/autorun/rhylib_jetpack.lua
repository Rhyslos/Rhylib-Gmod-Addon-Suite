-- rhylib_jetpack loader (shared): loads lua/rhylib/jetpack/ through the core.
-- A predicted jetpack worn in the inventory's Back slot.
if not Rhylib then
    print("[Rhylib] rhylib_jetpack needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("jetpack", { name = "Jetpack", version = "0.1.0" })
