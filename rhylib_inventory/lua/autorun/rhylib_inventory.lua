-- Loads the inventory module (lua/rhylib/inventory/*). Needs rhylib_core.
if not Rhylib then
    print("[Rhy's] Rhy's Inventory (rhylib_inventory) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("inventory", { name = "Rhy's Inventory", version = "0.1.0" })
