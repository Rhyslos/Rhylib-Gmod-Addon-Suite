-- rhylib_datapad loader (shared). Registers module "datapad": the core then
-- loads lua/rhylib/datapad/ (sh_ files, then sv_, then cl_, by name).
-- Needs rhylib_core; rhylib_menus is needed for every window.
if not Rhylib then
    print("[Rhy's] Rhy's Datapad (rhylib_datapad) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

-- Uses rhylib_menus (UI), rhylib_mp and rhylib_medical when they're there;
-- they load later (alphabetical), so they're only looked up when used.
Rhylib.LoadModule("datapad", { name = "Rhy's Datapad", version = "0.1.0" })
