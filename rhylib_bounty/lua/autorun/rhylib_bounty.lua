-- rhylib_bounty loader. Loads lua/rhylib/bounty/ (sh_ first, then sv_, then
-- cl_, by number). Needs rhylib_core; see docs/addons/rhylib_bounty.md.
-- A separate addon for DarkRP play: it works with the rest of the suite but
-- isn't part of the military experience.
if not Rhylib then
    print("[Rhy's] Rhy's Bounty Hunters (rhylib_bounty) needs Rhy's Core (rhylib_core). Install it and restart the map.")
    return
end

Rhylib.LoadModule("bounty", { name = "Rhy's Bounty Hunters", version = "0.1.0" })
