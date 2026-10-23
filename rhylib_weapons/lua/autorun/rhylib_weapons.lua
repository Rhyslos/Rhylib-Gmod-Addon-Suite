-- rhylib_weapons loader (shared). Needs rhylib_core, which loads every file
-- in lua/rhylib/weapons/ (sh_ shared, sv_ server, cl_ client, in number
-- order). The SWEP base is lua/weapons/rhylib_base.lua; the guns themselves
-- live in rhylib_republic. See docs/addons/rhylib_weapons.md.

if not Rhylib then
    print("[Rhy's] Rhy's Weapons (rhylib_weapons) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("weapons", { name = "Rhy's Weapons", version = "0.1.0" })
