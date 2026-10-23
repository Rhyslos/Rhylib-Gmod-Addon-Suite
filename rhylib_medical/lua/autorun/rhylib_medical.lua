-- rhylib_medical loader (shared). Loads the files in lua/rhylib/medical through
-- rhylib_core: sh_ files on both sides, then sv_, then cl_, in name order.
-- Weapons (lua/weapons) and entities (lua/entities) load the normal way.
if not Rhylib then
    print("[Rhy's] Rhy's Medical System (rhylib_medical) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("medical", { name = "Rhy's Medical System", version = "0.1.0" })
