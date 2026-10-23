if not Rhylib then
    print("[Rhy's] Rhy's Skill Trees (rhylib_skills) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

-- Loader for rhylib_skills (shared autorun). Skill trees: categories
-- (Trooper, Support, Officer, Specialist, Medic, Shock Trooper),
-- specialisations and the skills that change weapons, movement and
-- carrying; also command orders, marks and class mode. Module files are in
-- lua/rhylib/skills/ (shared, then server, then client).
Rhylib.LoadModule("skills", { name = "Rhy's Skill Trees", version = "0.1.0" })
