--[[
    Armoury: where troopers get their gear.

      Weapons armoury   endless: one of each gun. Drag one out to take it,
                        drag it back to hand it in. (rhylib_armoury)
      Ammo cabinet      endless: magazines, power cells, rockets and
                        grapple hooks. (rhylib_ammo_cabinet)
      Supply crates     one per magazine size, about 20 slots of it. Run
                        out, and stay empty until an admin refills them.
                        (rhylib_crate_small / _medium / _large)
      Medical crate     an assortment of medical kits; runs out like the
                        supply crates. (rhylib_med_crate)
      Specialist        role gear: the weapons rack (rhylib_spec_weapons)
      armouries         and the gear rack (rhylib_spec_gear) show only
                        what your role may take (config "roles").
      Personal locker   36 slots (6 x 6). Press E on a free one to claim it
                        (one per player); the owner can lock it. Contents
                        belong to the owner's SteamID and are saved.
                        (rhylib_locker)
      Training deposit  per player and as good as endless (grows as it
                        fills): "Store all" puts everything you carry in
                        (not job gear or the backpack you wear, but what's
                        in it), "Take all" gives it back. Saved under your
                        SteamID; every deposit on the map shows the same
                        contents. (rhylib_training_deposit)

    Gear from the armoury and ammo cabinet is "issued": dropping it hands
    it back instead of leaving it on the ground.

    Admins place them from the spawn menu (Rhylib tab), then run
    rhylib_armoury_save to keep them on this map. They come back at every
    map start, frozen in place.
]]

Rhylib.Armoury = Rhylib.Armoury or {}
local A = Rhylib.Armoury

A.MODELS = {
    armoury = "models/reizer_props/srsp/sci_fi/armory_01/armory_01.mdl",
    ammo = "models/reizer_props/srsp/sci_fi/armory_02_3/armory_02_3.mdl",
    locker = "models/reizer_props/srsp/sci_fi/console_02_1/console_02_1.mdl",
    crate = "models/reizer_props/srsp/sci_fi/crate_01/crate_01.mdl",
    medcrate = "models/reizer_props/srsp/sci_fi/crate_03/crate_03.mdl",
    specWeapons = "models/reizer_props/srsp/sci_fi/armory_02/armory_02.mdl",
    specGear = "models/reizer_props/srsp/sci_fi/armory_02_2/armory_02_2.mdl",
    gear = "models/reizer_props/srsp/sci_fi/armory_02_1/armory_02_1.mdl",
}

-- Every armoury entity class, for saving and loading placements.
A.CLASSES = {
    rhylib_armoury = true,
    rhylib_ammo_cabinet = true,
    rhylib_locker = true,
    rhylib_crate_small = true,
    rhylib_crate_medium = true,
    rhylib_crate_large = true,
    rhylib_med_crate = true,
    rhylib_spec_weapons = true,
    rhylib_spec_gear = true,
    rhylib_gear_cabinet = true,
    rhylib_training_armoury = true,
    rhylib_training_ammo = true,
    rhylib_training_deposit = true,
}
A.CRATES = { "rhylib_crate_small", "rhylib_crate_medium", "rhylib_crate_large", "rhylib_med_crate" }

A.TRAINING_AMMO_STOCK = { "mag_small_t", "mag_medium_t", "mag_large_t", "cell", "rocket_t" }
A.AMMO_STOCK = { "mag_small", "mag_medium", "mag_large", "cell", "rocket", "grapple", "rhylib_thermal", "rhylib_droidpopper", "rhylib_ammo_pack" }

local Config = Rhylib.Config
Config.Register("armoury", "weapons", {}, "Weapon classes in the armoury, in order. Empty = every Rhylib weapon")
Config.Register("armoury", "trainingWeapons", {}, "Weapon classes in the training armoury, in order. Empty = every training weapon")
Config.Register("armoury", "gearStock", { "backpack", "jetpack" }, "Gear cabinet: equipment it hands out (endless, issued)")
Config.Register("armoury", "lockerW", 6, "Personal locker width in cells")
Config.Register("armoury", "lockerH", 6, "Personal locker height in cells")
Config.Register("armoury", "crateW", 5, "Supply crate width in cells")
Config.Register("armoury", "crateH", 4, "Supply crate height in cells")

Config.Register("armoury", "medCrate", {
    { "rhylib_medkit", 10 }, { "rhylib_firstaid", 2 }, { "rhylib_revivekit", 3 },
    { "rhylib_antiviral", 2 }, { "rhylib_antidote", 2 }, { "rhylib_antibiotics", 2 },
    { "rhylib_splint", 4 }, { "rhylib_burngel", 3 }, { "rhylib_painkiller", 4 },
    { "rhylib_bloodpack", 2 }, { "rhylib_med_supplies", 10 },
}, "What a medical crate is filled with: { item, count }")

-- Everyone has the "trooper" role; mp / medic come from the DarkRP job
-- (mp = true, medic = true), others from a job's role = "name" (or a list).
-- Items listed here are kept out of the normal weapons armoury.
Config.Register("armoury", "roles", {
    trooper = { weapons = {}, gear = { "sw_datapad" } },
    mp = { weapons = { "rhylib_riotshield" }, gear = { "rhylib_stunbaton", "rhylib_handcuffs", "rhylib_flashcharge" } },   -- (stun is a fire mode for MPs)
    medic = { weapons = {}, gear = { "rhylib_medkit", "rhylib_firstaid", "rhylib_revivekit", "rhylib_antiviral", "rhylib_antidote", "rhylib_antibiotics",
        "rhylib_med_supplies" } },
}, "Specialist armoury stock per role: { weapons = {...}, gear = {...} }")

-- Role names a player has, sorted (so the same set always gives the same key).
function A.Roles(ply)
    local out, seen = {}, {}
    local function add(r)
        if isstring(r) and r ~= "" and not seen[r] then seen[r] = true out[#out + 1] = r end
    end
    add("trooper")
    if Rhylib.MP and Rhylib.MP.IsMP and Rhylib.MP.IsMP(ply) then add("mp") end
    if Rhylib.Medical and Rhylib.Medical.IsMedic and Rhylib.Medical.IsMedic(ply) then add("medic") end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    if job then
        if istable(job.role) then for _, r in ipairs(job.role) do add(r) end else add(job.role) end
    end
    local extra = hook.Run("Rhylib.PlayerRoles", ply)
    if istable(extra) then for _, r in ipairs(extra) do add(r) end end
    table.sort(out)
    return out
end
