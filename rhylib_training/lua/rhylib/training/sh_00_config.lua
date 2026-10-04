--[[
    Training (simulations).

    Training guns (rhylib_republic, "(Training)" copies of every gun, from
    the training armoury) and training droids (rhylib_droids) fire yellow
    bolts that never hurt anyone. Instead every player has "sim health"
    (simHealth): training hits take it off (head and limb multipliers
    count, armour doesn't). At 0 you're eliminated: you drop, can't act,
    and pick a training respawn beacon from a list (or the nearest one is
    picked after simChooseTime). Sim health refills after simRegen seconds
    without a training hit, and on respawning at a beacon. No credits,
    stats or kill feed; no injuries.

    Respawn beacons (rhylib_training_beacon) are placed with the toolgun
    (rhylib_toolgun) or the spawn menu and named, e.g. "Range" or
    "Killhouse A". rhylib_training_save keeps them on the map.

    Real damage still works as normal during a simulation.
]]

Rhylib.Training = Rhylib.Training or {}
local T = Rhylib.Training
local Config = Rhylib.Config

Config.Register("training", "simHealth", 100, "Sim health: what training hits take off before you're eliminated")
Config.Register("training", "simRegen", 10, "Seconds without a training hit before sim health refills")
Config.Register("training", "outMin", 3, "Seconds an eliminated player lies there at least")
Config.Register("training", "chooseTime", 20, "Seconds to pick a respawn beacon before the nearest one is picked")
Config.Register("training", "immune", 2, "Seconds of no training hits after respawning at a beacon")
Config.Register("training", "beaconModel", "models/props_combine/combine_mine01.mdl", "Respawn beacon model")

function T.Cfg(k) return Config.Get("training", k) end

function T.Out(ply)
    return ply:GetNW2Bool("rhylib_simOut", false)
end

function T.Health(ply)
    return ply:GetNW2Int("rhylib_sim", T.Cfg("simHealth"))
end
