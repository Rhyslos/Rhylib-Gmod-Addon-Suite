-- rhylib_thirdperson loader (shared): loads lua/rhylib/thirdperson/ through
-- the core. Over-the-shoulder third person with aim correction.
if not Rhylib then
    print("[Rhy's] Rhy's Third Person (rhylib_thirdperson) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("thirdperson", { name = "Rhy's Third Person", version = "0.1.0" })
