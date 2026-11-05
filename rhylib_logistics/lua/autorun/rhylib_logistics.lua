-- rhylib_logistics loader (shared): loads lua/rhylib/logistics/ through the
-- core. The FOB: the command post (sensors, supplies, the armoury stock,
-- garrison tickets and call-ins) and sensor array beacons.
if not Rhylib then
    print("[Rhy's] Rhy's Logistics (rhylib_logistics) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("logistics", { name = "Rhy's Logistics", version = "0.2.0",
    needs = { "inventory" }, wants = { "weapons", "droids", "radio", "skills", "roster", "armoury", "menus" } })
