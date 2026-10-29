--[[
    Training (simulations).

    Training guns (rhylib_republic, "(Training)" copies of every gun, from
    the training armoury) and training droids (rhylib_droids) fire yellow
    bolts that never hurt anyone. Instead every player has "sim health"
    (simHealth): training hits take it off (head and limb multipliers
    count, armour doesn't). At 0 you're eliminated: you drop, can't act,
    and pick a training respawn beacon from a list (or the nearest one is
    picked after chooseTime). Sim health refills after simRegen seconds
    without a training hit, and on respawning at a beacon. No credits,
    stats or kill feed; no injuries.

    Respawn beacons (rhylib_training_beacon) are placed with the toolgun
    (rhylib_toolgun) or the spawn menu and named, e.g. "Range" or
    "Killhouse A". Make them permanent (toolgun Permanent tool) to keep
    them on the map; rhylib_training_save re-saves the permanent ones.

    Real damage still works as normal during a simulation.

    Shared file: Rhylib.Training (T) with Cfg, Out, Health. Server logic in
    sv_10_sim.lua, HUD bar and beacon list in cl_10_sim.lua. Training hits
    come from rhylib_weapons (training bolts, W.TrainingBlast).
]]

Rhylib.Training = Rhylib.Training or {}
local T = Rhylib.Training
local Config = Rhylib.Config

Config.Describe("training", { name = "Training", category = "Units & roles" })
Config.Register("training", "simHealth", 100, "Sim health: what training hits take off before you're eliminated")
Config.Register("training", "simRegen", 10, "Seconds without a training hit before sim health refills")
Config.Register("training", "outMin", 3, "Seconds an eliminated player lies there at least")
Config.Register("training", "chooseTime", 20, "Seconds to pick a respawn beacon before the nearest one is picked")
Config.Register("training", "immune", 2, "Seconds of no training hits after respawning at a beacon")
Config.Register("training", "beaconModel", "models/props_combine/combine_mine01.mdl", "Respawn beacon model")

-- T.Cfg(key): a "training" setting.
T.Cfg = Config.For("training")

-- T.Out(ply): eliminated right now (NW2Bool rhylib_simOut). Both realms.
function T.Out(ply)
    return ply:GetNW2Bool(Rhylib.NW.SIM_OUT, false)
end

-- T.Health(ply): sim health (NW2Int rhylib_sim; full when not set).
-- Example (client HUD): local hp = Rhylib.Training.Health(LocalPlayer())
function T.Health(ply)
    return ply:GetNW2Int(Rhylib.NW.SIM, T.Cfg("simHealth"))
end

-- Answers for rhylib_core's Rhylib.State: out of a simulation (or just
-- back at a beacon, still immune) = droids and auto-aim leave you alone.
Rhylib.State.Provide("targetable", "training", function(ply)
    if T.Out(ply) then return false end
    if SERVER and (ply.rhylibSimImmune or 0) > CurTime() then return false end
end)
