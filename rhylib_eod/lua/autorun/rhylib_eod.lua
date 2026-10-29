-- rhylib_eod loader. Loads lua/rhylib/eod/ (sh_ first, then sv_, then
-- cl_, by number). Needs rhylib_core; see docs/addons/rhylib_eod.md.
if not Rhylib then
    print("[Rhy's] Rhy's EOD: Bombs & Mines (rhylib_eod) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("eod", {
    name = "Rhy's EOD: Bombs & Mines",
    version = "0.1.0",
    needs = { "inventory" },
    wants = { "skills", "datapad", "radio" },
})
