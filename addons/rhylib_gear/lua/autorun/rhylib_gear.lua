-- rhylib_gear loader (shared). Loads lua/rhylib/gear/ through rhylib_core:
-- sh_ files first, then sv_, then cl_. Needs rhylib_inventory too (the
-- gear items live there); that loads after this addon, so the items are
-- registered once it's ready (sh_00_config.lua).
if not Rhylib then
    print("[Rhylib] rhylib_gear needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("gear", { name = "Wearable gear", version = "0.1.0" })
