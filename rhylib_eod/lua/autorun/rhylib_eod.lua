if not Rhylib then
    print("[Rhylib] rhylib_eod needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("eod", { name = "EOD: bombs and defusal", version = "0.1.0" })
