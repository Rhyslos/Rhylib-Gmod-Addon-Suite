-- rhylib_stamina loader (shared): loads lua/rhylib/stamina/ through the core.
-- Sprint and jump stamina, slowed by carried weight (rhylib_inventory).
if not Rhylib then
    print("[Rhy's] Rhy's Stamina (rhylib_stamina) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("stamina", { name = "Rhy's Stamina", version = "0.1.0" })
