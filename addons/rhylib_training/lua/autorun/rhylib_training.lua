-- rhylib_training loader (shared): loads lua/rhylib/training/ through the
-- core. Sim health, eliminations and respawn beacons for training fights.
if not Rhylib then
    print("[Rhylib] rhylib_training needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("training", { name = "Training", version = "0.1.0" })
