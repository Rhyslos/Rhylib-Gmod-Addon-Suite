-- Loads the inventory module (lua/rhylib/inventory/*). Needs rhylib_core.
if not Rhylib then
    print("[Rhylib] rhylib_inventory needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("inventory", { name = "Inventory", version = "0.1.0" })
