if not Rhylib then
    print("[Rhylib] rhylib_gear needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("gear", { name = "Wearable gear", version = "0.1.0" })
