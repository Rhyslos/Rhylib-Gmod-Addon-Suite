--[[
    Rhy's Logistics stage 2 (shared): armoury stock, the garrison and
    call-ins.

    Armoury stock: the weapons armoury, ammo cabinet, gear cabinet and
    specialist racks (rhylib_armoury) hand out from one stock per item,
    shared by every cabinet on the map (two weapons armouries draw from
    the same DC-15As). Taking one lowers it; handing issued gear back in,
    or issued gear dropped on the ground running out of time
    (rhylib_inventory's world item), puts it back. Training armouries
    never count. A resupply crate (entities/rhylib_resupply_crate.lua),
    carried to any armoury and set down there, puts back resupplyAmount
    of each item's max. The maxima: stockMax per item id, else
    stockDefault by shelf group (rifle, pistol, ammo, medical ...; 0 =
    endless). The stock is saved (Data "logistics" "stock") so it carries
    over map changes and restarts, unless stockSave is off.

    Garrison tickets: a shared pool staff set for an event (!garrison on
    <n>); officers spend one per clone to call a clone squad from a
    command post, and the Reinforcements skill's comlink call (rhylib_skills)
    costs them too while the garrison is on.

    Call-ins (officers, at a command post): a clone squad (garrison
    tickets), an armoury resupply crate, ammo crates, a medical crate.
    They arrive near the post after callDelay seconds; each has its own
    cooldown (per server). Needs rhylib_droids for the squad and
    rhylib_armoury for the crates.

    Global2: rhylib_garrison_on (bool), rhylib_garrison (int),
    rhylib_call_<kind> (float: CurTime when the kind is ready again).
    Adds to Rhylib.Logistics: L.StockMax(id), L.CALLS, L.CallReady(kind),
    L.GarrisonOn(), L.Garrison().
]]

local L = Rhylib.Logistics
local Config = Rhylib.Config

local S = { section = "Armoury stock" }
Config.Register("logistics", "stockOn", true, "Armoury stock: armouries, ammo, gear cabinets and specialist racks hand out from one limited stock per item, shared by every one on the map (off: endless as before). Training armouries never count", S)
Config.Register("logistics", "stockMax", {
    mag_large = 60, rocket = 20, cell = 100, rhylib_he_charge = 16, rhylib_ammo_pack = 10,
    rhylib_grapple_personal = 12, grapple = 30, rhylib_rps6 = 6, rhylib_dc15x = 6, rhylib_z6 = 8, rhylib_dp24 = 10,
    jetpack = 8, rhylib_firstaid = 16, rhylib_revivekit = 20,
}, "Armoury stock: the most kept of each item (item id = count; a fresh stock starts full). Items not listed use stockDefault", S)
Config.Register("logistics", "stockDefault", {
    rifle = 30, carbine = 30, pistol = 30, heavy = 8, shotgun = 12, sniper = 6, weapon = 10, grenade = 40,
    ammo = 200, medical = 40, back = 12, helmet = 15, gear = 15, body = 0, misc = 0,
}, "Armoury stock for items not in stockMax, by shelf group (rifle, carbine, pistol, heavy, shotgun, sniper, weapon, grenade, ammo, medical, back, body, helmet, gear, misc); 0 = endless", S)
Config.Register("logistics", "stockSave", true, "Armoury stock carries over map changes and restarts (off: full again on every map)", S)
Config.Register("logistics", "resupplyAmount", 0.35, "Armoury resupply crate: share of each item's max it puts back", S)
Config.Meta("logistics", "resupplyAmount", { min = 0.05, max = 1, step = 0.05 })
Config.Register("logistics", "resupplyModel", "models/props_junk/wood_crate002a.mdl", "Armoury resupply crate: model (a placeholder)", S)
Config.Register("logistics", "resupplyRange", 260, "Armoury resupply crate: set it down this close to an armoury, ammo or gear cabinet to restock (units)", S)

local G = { section = "Garrison & call-ins" }
Config.Register("logistics", "garrisonStart", 30, "Garrison tickets: the pool when staff switch it on without a number (!garrison on)", G)
Config.Register("logistics", "callSquad", { "ct_trooper", "ct_rifleman", "ct_heavy", "ct_rifleman", "ct_medic" },
    "Call-in clone squad: its clones (rhylib_droids kinds); one garrison ticket each", G)
Config.Register("logistics", "callSquadLife", 900, "Call-in clone squad: seconds before they're pulled out again (0 = they stay)", G)
Config.Register("logistics", "callDelay", 20, "Call-ins: seconds before what was called arrives at the post", G)
Config.Register("logistics", "callCooldownSquad", 180, "Call-ins: seconds before another clone squad can be called (whole server)", G)
Config.Register("logistics", "callCooldownSupply", 300, "Call-ins: seconds before another resupply crate", G)
Config.Register("logistics", "callCooldownAmmo", 240, "Call-ins: seconds before more ammo crates", G)
Config.Register("logistics", "callCooldownMedical", 240, "Call-ins: seconds before another medical crate", G)
Config.Register("logistics", "callAmmoCrates", { "rhylib_crate_small", "rhylib_crate_medium", "rhylib_crate_large" }, "Call-in ammo crates: the crates that arrive (rhylib_armoury classes)", G)
Config.Register("logistics", "callCrateLife", 1200, "Call-ins: seconds a called crate stays before it's taken away (0 = it stays; made permanent ones always stay)", G)

-- L.CALLS: what officers can call in, in window order. id, title, cost
-- text, cooldown key.
L.CALLS = {
    { id = "squad", title = "Clone squad", cd = "callCooldownSquad" },
    { id = "supply", title = "Armoury resupply crate", cd = "callCooldownSupply" },
    { id = "ammo", title = "Ammo crates", cd = "callCooldownAmmo" },
    { id = "medical", title = "Medical crate", cd = "callCooldownMedical" },
}
L.CALL_BY = {}
for i, c in ipairs(L.CALLS) do c.index = i L.CALL_BY[c.id] = c end

function L.GarrisonOn() return GetGlobal2Bool("rhylib_garrison_on", false) end
function L.Garrison() return GetGlobal2Int("rhylib_garrison", 0) end

-- L.CallReady(id) -> seconds until that call-in can be made again (0 = now).
function L.CallReady(id)
    return math.max(0, GetGlobal2Float("rhylib_call_" .. id, 0) - CurTime())
end

-- L.StockMax(id) -> the most kept of an item, or nil when it's endless
-- (stock off, not in any rule, a training item, or 0).
function L.StockMax(id)
    if not L.Cfg("stockOn") then return nil end
    local Items = Rhylib.Items
    local def = Items and Items.defs and Items.defs[id]
    if not def then return nil end
    local g = Items.GroupOf and Items.GroupOf(def) or def.category
    if g == "training" or def.category == "training" or def.training or string.find(id, "_training") then return nil end
    local per = L.Cfg("stockMax")
    local n = istable(per) and tonumber(per[id])
    if n == nil then
        local byGroup = L.Cfg("stockDefault")
        n = istable(byGroup) and tonumber(byGroup[g]) or 0
    end
    if not n or n <= 0 then return nil end
    return math.floor(n)
end
