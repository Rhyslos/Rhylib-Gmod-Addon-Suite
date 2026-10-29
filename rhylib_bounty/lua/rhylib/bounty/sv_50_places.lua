--[[
    Saving Bounty Offices and wanted posters per map (server), through
    rhylib_core's Rhylib.Perma.Placements. Only the ones made permanent
    with the toolgun's Permanent tool are kept; they come back at map
    start and after a cleanup. Data "bounty_places"/<map> = list of
    { class, pos, ang }.

    B.SavePlaces() -> saved, notPermanent. B.LoadPlaces() -> spawned.
]]

local B = Rhylib.Bounty

B.PLACE_CLASSES = { "rhylib_bounty_office", "rhylib_bounty_poster" }

B.places = Rhylib.Perma.Placements("bounty", {
    classes = B.PLACE_CLASSES,
    dataModule = "bounty_places",
})

function B.SavePlaces() return B.places:Save() end
function B.LoadPlaces() return B.places:Load() end
