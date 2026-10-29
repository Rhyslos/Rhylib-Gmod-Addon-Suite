-- rhylib_devtools loader. Loads lua/rhylib/devtools/ (sh_ first, then sv_,
-- then cl_, by number). Needs rhylib_core; see docs/addons/rhylib_devtools.md.
-- Tools for building and tuning the suite (the weapon position editors and
-- their console commands). Not needed on a live server: leave it out there.
if not Rhylib then
    print("[Rhy's] Rhy's Dev Tools (rhylib_devtools) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("devtools", {
    name = "Rhy's Dev Tools",
    version = "0.1.0",
    needs = { "weapons" },
})
