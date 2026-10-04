if not Rhylib then
    print("[Rhylib] rhylib_toolgun needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("toolgun", { name = "Toolgun", version = "0.1.0" })
