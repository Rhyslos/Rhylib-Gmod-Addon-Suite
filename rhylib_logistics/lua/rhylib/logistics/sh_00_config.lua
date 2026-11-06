--[[
    Rhy's Logistics (shared): settings, who sees what, the sensor kit item.

    Stage 1 of the FOB:
      Command post (entities/rhylib_command_post.lua; sv_20_post.lua,
        cl_20_post.lua): a computer game masters place (and make
        permanent). E opens its window: Logistics (supply crates, medical
        crates and armoury cabinets within postRadius, how much is left),
        Respawn tickets and Garrison tickets, the armoury stock running
        low, Sensor arrays (field technicians and officers), Orders
        (officers: call-ins).
      Sensor array beacons (entities/rhylib_sensor_beacon.lua,
        weapons/rhylib_sensor_kit.lua; sv_10_sensors.lua, cl_10_sensors.lua):
        anyone carrying a sensor kit (4x1, stacks to 2) sets one down
        (LMB on the ground close by). It runs on a power cell (one full
        cell = sensorPower seconds, a part-used cell less): one is used
        from your inventory when you place it, and E on it puts in a new
        one. While powered and not inside an active comms jammer, it counts
        droids within sensorRadius, through walls (the agreed exception to
        "no wallhacks"), and tells every field technician and officer on the
        map: a SENSOR alert on screen and an arrow on the compass (rhylib_radio)
        toward it, with how many. Sent only when the count changes.

    Stage 2 (sh_40_stock.lua, sv_50_stock.lua, sv_60_calls.lua,
    entities/rhylib_resupply_crate.lua): one shared armoury stock per
    item, resupply crates, garrison tickets and officer call-ins.

    Who (L.Access(ply) -> 1 everyone, 2 field technician, 3 officer):
      field technician = any Field technician skill (rhylib_skills, spec
      "eod"); officer = rank officerRank or higher (rhylib_roster), or
      permission rhylib.logistics.admin (admin).

    Settings: module logistics (Server settings > Logistics).
    Adds Rhylib.Logistics (L).
]]

Rhylib.Logistics = Rhylib.Logistics or {}
local L = Rhylib.Logistics
local Config = Rhylib.Config

Config.Describe("logistics", { name = "Logistics", category = "Soldiers", sections = {
    { "Command post", { "^post" } },
    { "Sensor arrays", { "^sensor" } },
    { "Who sees what", { "^officerRank$" } },
    { "Building", { "^build", "^etool", "^repair", "^skill", "^crate", "^carry", "^staffCrate" } },
    { "Armoury stock", { "^stock", "^resupply" } },
    { "Garrison & call-ins", { "^garrison", "^call" } },
    { "Supply depots", { "^depot", "^supplyCrate", "^fuel" } },
} })
Config.Register("logistics", "postRadius", 3000, "Command post: supplies within this range are listed (units)")
Config.Register("logistics", "postModel", "models/ace/sw/rh/cgi_holotable_bottom.mdl", "Command post: model (the battalion computer's for now)")
Config.Register("logistics", "postFieldModel", "models/fisher/command/command.mdl", "Field command post (the big outdoor one): model")
Config.Register("logistics", "sensorRadius", 1800, "Sensor array: how far a beacon senses droids (units, through walls; 1800 = the small comms jammer's range). Field technicians, officers and staff holding the toolgun see it as a ring on the ground")
Config.Register("logistics", "sensorPower", 720, "Sensor array: seconds one full power cell keeps a beacon running (12 min)")
Config.Register("logistics", "sensorHealth", 150, "Sensor array: damage a beacon takes before it breaks")
Config.Register("logistics", "sensorMax", 4, "Sensor array: most beacons one player can have out at once")
Config.Register("logistics", "sensorMaxTotal", 40, "Sensor array: most beacons out on the whole server at once (staff placing with the toolgun aren't held to it)")
Config.Register("logistics", "sensorModel", "models/theinvisibleman/swbf/scarifprops/generatorpillar_01.mdl", "Sensor array: beacon model (falls back to an HL2 radio when it isn't installed)")
Config.Register("logistics", "sensorScale", 0.5, "Sensor array: size of the beacon model (1 = the model's own size)")
Config.Register("logistics", "officerRank", "LT", "Lowest rank (rhylib_roster rank prefix) that counts as an officer: sees everything on the command post and gets sensor alerts")
Config.Meta("logistics", "officerRank", { kind = "rank" })

Rhylib.Perms.Register("rhylib.logistics.admin", "admin", "Logistics: see everything on the command post and get sensor alerts")

-- Supply depots (entities/rhylib_supply_depot.lua, rhylib_supply_crate.lua,
-- rhylib_fuel_canister.lua; sv_70_depots.lua).
Config.Register("logistics", "depotModel", "models/props_c17/signpole001.mdl", "Supply depot: the marker in its middle (a placeholder until one is picked)")
Config.Register("logistics", "depotRadius", 260, "Supply depot: ring radius when the toolgun gives none (units)")
Config.Register("logistics", "depotLabelRange", 790, "Supply depot, crates, canisters: labels show within this distance (units)")
Config.Register("logistics", "supplyCrateModel", "models/reizer_props/srsp/sci_fi/crate_02/crate_02.mdl", "Supply crate: model (a missing one falls back to the HL2 wooden crate)")
Config.Register("logistics", "supplyCrateAmount", 100, "Supply crate: supplies in one (RP only: what's lost when it's destroyed)")
Config.Register("logistics", "supplyCrateHealth", 250, "Supply crate: damage it takes before it breaks (only droids and explosions hurt it)")
Config.Register("logistics", "supplyCrateHeavy", false, "Supply crate: two troopers carry it (or one with Heavy lifter)")
Config.Register("logistics", "supplyCratePriority", 1.5, "Supply crate: droids pick one as if it were this many times further away than it is (1 = like a trooper)")
Config.Register("logistics", "fuelModel", "models/reizer_props/srsp/sci_fi/barrel_01/barrel_01.mdl", "Fuel canister: model (a missing one falls back to the HL2 gas can)")
Config.Register("logistics", "fuelHits", 3, "Fuel canister: hits from any gun that set it off (explosions set it off at once)")
Config.Register("logistics", "fuelRadius", 240, "Fuel canister: blast radius (units; 52 = 1 m)")
Config.Register("logistics", "fuelDamage", 110, "Fuel canister: blast damage at its middle (less further out)")
Config.Register("logistics", "fuelNear", 420, "Fuel canister: droids only shoot at one while a player or clone is within this distance of it (units)")

L.Cfg = Config.For and Config.For("logistics") or function(k) return Config.Get("logistics", k) end

L.KIT = "rhylib_sensor_kit"     -- the sensor kit SWEP / item id
L.ACCESS_ALL, L.ACCESS_TECH, L.ACCESS_OFFICER = 1, 2, 3

-- L.IsFieldTech(ply) -> has any Field technician skill (rhylib_skills).
function L.IsFieldTech(ply)
    local K = Rhylib.Skills
    if not (K and K.NODES and K.Has and IsValid(ply)) then return false end
    for _, n in ipairs(K.NODES) do
        if n.spec == "eod" and K.Has(ply, n.id) then return true end
    end
    return false
end

-- L.IsOfficer(ply) -> rank officerRank or higher in a battalion (rhylib_roster).
function L.IsOfficer(ply)
    local R = Rhylib.Roster
    if not (R and R.Get and R.RankIndex and IsValid(ply)) then return false end
    local need = R.RankIndex(L.Cfg("officerRank"))
    local c = R.Get(ply)
    return need ~= nil and c.bn ~= "" and c.rank >= need
end

-- L.Access(ply, admin) -> 1 everyone, 2 field technician, 3 officer.
-- admin = the rhylib.logistics.admin check already done (server).
function L.Access(ply, admin)
    if admin or L.IsOfficer(ply) then return L.ACCESS_OFFICER end
    if L.IsFieldTech(ply) then return L.ACCESS_TECH end
    return L.ACCESS_ALL
end
