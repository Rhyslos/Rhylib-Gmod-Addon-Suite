-- rhylib_thirdperson loader (shared): loads lua/rhylib/thirdperson/ through
-- the core. Over-the-shoulder third person with aim correction.
if not Rhylib then
    print("[Rhylib] rhylib_thirdperson needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("thirdperson", { name = "Third person", version = "0.1.0" })
