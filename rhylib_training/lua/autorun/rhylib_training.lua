-- rhylib_training loader (shared): loads lua/rhylib/training/ through the
-- core. Sim health, eliminations and respawn beacons for training fights.
if not Rhylib then
    print("[Rhy's] Rhy's Training (rhylib_training) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("training", {
    name = "Rhy's Training",
    version = "0.1.0",
    needs = { "weapons" },
})
