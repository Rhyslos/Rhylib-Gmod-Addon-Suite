-- rhylib_eod loader. Loads lua/rhylib/eod/ (sh_ first, then sv_, then
-- cl_, by number). Needs rhylib_core; see docs/addons/rhylib_eod.md.
if not Rhylib then
    print("[Rhylib] rhylib_eod needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("eod", { name = "EOD: bombs and defusal", version = "0.1.0" })
