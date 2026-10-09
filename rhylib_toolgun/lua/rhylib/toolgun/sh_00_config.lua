--[[
    Toolgun (rhylib_toolgun weapon, BTX-42 pistol model): the host's spawn
    tool. LMB places the chosen thing where you aim (on the world or on
    props), facing you; RMB removes a Rhylib thing you aim at; R opens the
    list. Nothing placed is saved by itself: the "Permanent" entry (Staff
    tools) makes a thing stay on the map (Rhylib.Perma); !cleanup wipes the
    rest.

    Permission rhylib.toolgun (admin). Get one with rhylib_toolgun in the
    console, !toolgun in chat, or the spawn menu (Weapons > Rhylib).

    Rhylib.Tool.ENTRIES: { id, name, cat, class, count (several at once),
    named (asks for a name: training beacons), save (console command) }.
    Entries whose class isn't installed are left out. Other addons can add
    rows with hook Rhylib.ToolEntries(list).
]]

Rhylib.Tool = Rhylib.Tool or {}
local Tool = Rhylib.Tool

Tool.MODEL = "models/jajoff/sps/cgiweapons/tc13j/btx42_pistol.mdl"
Tool.RANGE = 6000

local ARMOURY = "rhylib_armoury_save"
local MED = "rhylib_medical_save"
local MP = "rhylib_mp_save"
local PAD = "rhylib_datapad_save"
local TRAIN = "rhylib_training_save"
local SPAWNS = "rhylib_spawns_save"
local RADIO = "rhylib_radio_save"

local ALL = {
    -- Staff tool (2026-10-09u, owner): placing no longer saves anything; this
    -- makes the aimed thing permanent (rhylib_core Rhylib.Perma). Works on
    -- anything not part of the map: fixtures, props, other addons' entities.
    { id = "perma", name = "Permanent (LMB: keep it on the map / save its new spot, RMB: stop keeping it)", cat = "Staff tools", perma = true },
    { id = "b1", name = "B1 battle droid", cat = "Droid NPCs", class = "rhylib_b1", count = true },
    { id = "b2", name = "B2 super battle droid", cat = "Droid NPCs", class = "rhylib_b2", count = true },
    { id = "b2c", name = "B2 mortar droid", cat = "Droid NPCs", class = "rhylib_b2_cannon", count = true },
    { id = "b2r", name = "B2 rocket droid", cat = "Droid NPCs", class = "rhylib_b2_rocketdroid", count = true },
    { id = "b1_commander", name = "B1 commander droid", cat = "Droid NPCs", class = "rhylib_b1_commander", count = true },
    { id = "b1_heavy", name = "B1 heavy droid", cat = "Droid NPCs", class = "rhylib_b1_heavy", count = true },
    { id = "b1_aat", name = "B1 AAT crew droid", cat = "Droid NPCs", class = "rhylib_b1_aat", count = true },
    { id = "b1_geonosis", name = "B1 Geonosis droid", cat = "Droid NPCs", class = "rhylib_b1_geonosis", count = true },
    { id = "b1_marine", name = "B1 marine droid", cat = "Droid NPCs", class = "rhylib_b1_marine", count = true },
    { id = "b1_security", name = "B1 security droid", cat = "Droid NPCs", class = "rhylib_b1_security", count = true },
    { id = "b1_snow", name = "B1 snow droid", cat = "Droid NPCs", class = "rhylib_b1_snow", count = true },
    { id = "b1t", name = "B1 training droid", cat = "Droid NPCs", class = "rhylib_b1_training", count = true },
    { id = "b2t", name = "B2 training droid", cat = "Droid NPCs", class = "rhylib_b2_training", count = true },
    -- Clone troopers (friendly NPCs, 2026-10-06az)
    { id = "ct_trooper", name = "Clone trooper", cat = "Clone NPCs", class = "rhylib_ct_trooper", count = true },
    { id = "ct_rifleman", name = "Clone rifleman", cat = "Clone NPCs", class = "rhylib_ct_rifleman", count = true },
    { id = "ct_heavy", name = "Clone heavy", cat = "Clone NPCs", class = "rhylib_ct_heavy", count = true },
    { id = "ct_medic", name = "Clone medic", cat = "Clone NPCs", class = "rhylib_ct_medic", count = true },
    { id = "ct_commander", name = "Clone commander", cat = "Clone NPCs", class = "rhylib_ct_commander", count = true },
    -- Preset squads (2026-10-06bd): placed in a grid facing you.
    { id = "ps_clone_squad", name = "Clone squad (8)", cat = "Clone NPCs", preset = "clone_squad" },
    { id = "ps_clone_company", name = "Clone company (22)", cat = "Clone NPCs", preset = "clone_company" },
    { id = "ps_droid_small", name = "Droid squad, small (10)", cat = "Droid NPCs", preset = "droid_small" },
    { id = "ps_droid_medium", name = "Droid squad, medium (16)", cat = "Droid NPCs", preset = "droid_medium" },
    { id = "ps_droid_large", name = "Droid squad, large (31)", cat = "Droid NPCs", preset = "droid_large" },
    { id = "ps_droid_b2", name = "B2 squad (8)", cat = "Droid NPCs", preset = "droid_b2" },
    { id = "ps_droid_mortar", name = "Mortar squad (9)", cat = "Droid NPCs", preset = "droid_mortar" },
    -- Droid orders (rhylib_droids sv_20_orders): a brush that sets the mode
    -- of droids near where you aim, and admin-only markers.
    { id = "ord_guard", name = "Order: guard here", cat = "Droid orders", order = "guard" },
    { id = "ord_patrol", name = "Order: patrol here", cat = "Droid orders", order = "patrol" },
    { id = "ord_attack", name = "Order: attack", cat = "Droid orders", order = "attack" },
    { id = "ord_roam", name = "Order: spread out (roam the map, in twos)", cat = "Droid orders", order = "roam" },
    { id = "ord_retreat", name = "Order: retreat (get away from the enemy, last stand if cornered)", cat = "Droid orders", order = "retreat" },
    { id = "mk_attack", name = "Marker: attack here", cat = "Droid orders", class = "rhylib_droid_marker", marker = 1 },
    { id = "mk_defend", name = "Marker: defend this", cat = "Droid orders", class = "rhylib_droid_marker", marker = 2 },
    { id = "mk_fallback", name = "Marker: fall back here", cat = "Droid orders", class = "rhylib_droid_marker", marker = 3 },
    -- Clone orders (2026-10-06bb): same brush and markers for clone NPCs.
    { id = "cord_guard", name = "Clones: guard here", cat = "Clone orders", order = "guard", side = 1 },
    { id = "cord_patrol", name = "Clones: patrol here", cat = "Clone orders", order = "patrol", side = 1 },
    { id = "cord_attack", name = "Clones: attack", cat = "Clone orders", order = "attack", side = 1 },
    { id = "cord_roam", name = "Clones: spread out (roam the map, in twos)", cat = "Clone orders", order = "roam", side = 1 },
    { id = "cord_retreat", name = "Clones: retreat (get away from the enemy, last stand if cornered)", cat = "Clone orders", order = "retreat", side = 1 },
    { id = "cord_follow", name = "Clones: follow (LMB pick clones, RMB: follow you / the player you aim at)", cat = "Clone orders", follow = true },
    { id = "cmk_attack", name = "Clone marker: attack here", cat = "Clone orders", class = "rhylib_droid_marker", marker = 1, side = 1 },
    { id = "cmk_defend", name = "Clone marker: defend this", cat = "Clone orders", class = "rhylib_droid_marker", marker = 2, side = 1 },
    { id = "spawn", name = "Spawn point (set battalion with E)", cat = "Spawns", class = "rhylib_spawn_point", named = true, save = SPAWNS },
    { id = "eventspawn", name = "Event spawn (open it with E)", cat = "Spawns", class = "rhylib_event_spawn", named = true, save = SPAWNS },
    { id = "beacon", name = "Training respawn beacon", cat = "Training", class = "rhylib_training_beacon", named = true, save = TRAIN },
    { id = "tarmoury", name = "Training armoury", cat = "Training", class = "rhylib_training_armoury", save = ARMOURY },
    { id = "tammo", name = "Training ammo cabinet", cat = "Training", class = "rhylib_training_ammo", save = ARMOURY },
    { id = "tdeposit", name = "Training deposit", cat = "Training", class = "rhylib_training_deposit", save = ARMOURY },
    { id = "armoury", name = "Weapons armoury", cat = "Armoury", class = "rhylib_armoury", save = ARMOURY },
    { id = "ammo", name = "Ammo cabinet", cat = "Armoury", class = "rhylib_ammo_cabinet", save = ARMOURY },
    { id = "gear", name = "Gear cabinet", cat = "Armoury", class = "rhylib_gear_cabinet", save = ARMOURY },
    { id = "specw", name = "Specialist weapons", cat = "Armoury", class = "rhylib_spec_weapons", save = ARMOURY },
    { id = "specg", name = "Specialist gear", cat = "Armoury", class = "rhylib_spec_gear", save = ARMOURY },
    { id = "locker", name = "Personal locker", cat = "Armoury", class = "rhylib_locker", save = ARMOURY },
    { id = "crs", name = "Supply crate (small)", cat = "Armoury", class = "rhylib_crate_small", save = ARMOURY },
    { id = "crm", name = "Supply crate (medium)", cat = "Armoury", class = "rhylib_crate_medium", save = ARMOURY },
    { id = "crl", name = "Supply crate (large)", cat = "Armoury", class = "rhylib_crate_large", save = ARMOURY },
    { id = "medcrate", name = "Medical crate", cat = "Medical", class = "rhylib_med_crate", save = ARMOURY },
    { id = "tank", name = "Bacta tank", cat = "Medical", class = "rhylib_bacta_tank", save = MED },
    { id = "bench", name = "Chemistry bench", cat = "Medical", class = "rhylib_chem_bench", save = MED },
    { id = "sofa", name = "Med sofa", cat = "Medical", class = "rhylib_med_sofa", save = MED },
    { id = "holo", name = "Medical holotable", cat = "Medical", class = "rhylib_med_holotable", save = PAD },
    { id = "computer", name = "Battalion computer", cat = "Base", class = "rhylib_bn_computer", save = PAD },
    { id = "cell", name = "Jail cell", cat = "Base", class = "rhylib_jail_cell", save = MP },
    { id = "terminal", name = "Jail terminal", cat = "Base", class = "rhylib_jail_terminal", save = MP },
    { id = "property", name = "Property locker", cat = "Base", class = "rhylib_property_locker", save = MP },
    { id = "jammer", name = "Comms jammer (small)", cat = "Base", class = "rhylib_comms_jammer", save = RADIO },
    { id = "jammer_m", name = "Comms jammer (medium)", cat = "Base", class = "rhylib_comms_jammer_medium", save = RADIO },
    { id = "jammer_l", name = "Comms jammer (large)", cat = "Base", class = "rhylib_comms_jammer_large", save = RADIO },
    { id = "jammer_map", name = "Comms jammer (whole map)", cat = "Base", class = "rhylib_comms_jammer_map", save = RADIO },
    { id = "dummy", name = "Test dummy", cat = "Testing", class = "rhylib_test_dummy" },
    { id = "dummyt", name = "Test dummy (tough)", cat = "Testing", class = "rhylib_test_dummy_tough" },
}

-- The Rhylib tab's categories, top to bottom (owner: NPCs on their own,
-- not alphabetical); others follow alphabetically.
Tool.CAT_ORDER = { "Staff tools", "Clone NPCs", "Clone orders", "Droid NPCs", "Droid orders", "EOD", "Spawns", "Armoury", "Medical", "Base", "Training", "Testing" }

-- The installed entries (built once, after entities are registered).
function Tool.Entries()
    if Tool.list then return Tool.list end
    local list = {}
    for _, e in ipairs(ALL) do
        -- (orders need rhylib_droids, the rest their entity)
        if ((e.order or e.preset or e.follow) and Rhylib.Droids) or (e.class and scripted_ents.GetStored(e.class))
            or (e.perma and Rhylib.Perma) then list[#list + 1] = e end
    end
    hook.Run("Rhylib.ToolEntries", list)
    for i, e in ipairs(list) do e.index = i end
    Tool.list = list
    return list
end

-- The model a toolgun entry places, for the spawn window's tile picture
-- and hover preview (owner 2026-10-08). Mirrors how each entity picks its
-- model in Initialize (module config, then that entity's fallback).
-- Orders have none; presets show their main unit.
local PRESET_CLASS = { clone_squad = "rhylib_ct_trooper", clone_company = "rhylib_ct_trooper", droid_small = "rhylib_b1",
    droid_medium = "rhylib_b1", droid_large = "rhylib_b1", droid_b2 = "rhylib_b2", droid_mortar = "rhylib_b2_cannon" }
-- (on a client, util.IsValidModel is false for a model nobody has loaded
-- yet even when it's installed: check the file instead)
local function modelExists(m)
    return isstring(m) and m ~= "" and (util.IsValidModel(m) or file.Exists(m, "GAME"))
end
local function ok(m) return modelExists(m) and m or nil end
local function cfg(module, key, fallback) return ok(Rhylib.Config.Get(module, key)) or fallback end

function Tool.ClassModel(class)
    local t = class and scripted_ents.Get(class)
    if not t then return nil end
    -- droids and clones (rhylib_droids kinds)
    local D = Rhylib.Droids
    if t.DroidKind and D and D.KINDS then
        local k = D.KINDS[t.DroidKind] or D.KINDS.b1
        return ok(D.KindModel and D.KindModel(k)) or (t.IsRhylibClone and D.CLONE_FALLBACK or D.B1_MODEL)
    end
    -- armouries, cabinets, crates, lockers
    if t.ModelKey and Rhylib.Armoury and Rhylib.Armoury.MODELS and Rhylib.Armoury.MODELS[t.ModelKey] and (t.Base == "rhylib_armoury_base" or class == "rhylib_armoury_base") then
        return ok(Rhylib.Armoury.MODELS[t.ModelKey])
    end
    -- battalion computer, medical holotable
    if t.ModelKey and Rhylib.Datapad and Rhylib.Datapad.MODELS and Rhylib.Datapad.MODELS[t.ModelKey] then
        return ok(Rhylib.Datapad.MODELS[t.ModelKey])
    end
    -- comms jammers
    local R = Rhylib.Radio
    if R and R.JAMMER_SIZES and R.JAMMER_SIZES[class] then
        local key = R.JAMMER_SIZES[class].key or ""
        return ok(R.Cfg("jammerModel" .. key)) or ok(R.Cfg("jammerFallbackModel")) or "models/props_lab/reciever01a.mdl"
    end
    local byClass = {
        rhylib_bacta_tank = function() return cfg("medical", "tankModel", "models/props_c17/FurnitureFridge001a.mdl") end,
        rhylib_chem_bench = function() return cfg("medical", "benchModel", "models/props_c17/FurnitureTable001a.mdl") end,
        rhylib_med_sofa = function() return cfg("medical", "sofaModel", "models/props_c17/FurnitureCouch001a.mdl") end,
        rhylib_jail_terminal = function() return cfg("mp", "terminalModel", "models/props_combine/combine_interface001.mdl") end,
        rhylib_property_locker = function() return cfg("mp", "propertyModel", "models/props_c17/lockers001a.mdl") end,
        rhylib_jail_cell = function() return "models/hunter/plates/plate1x1.mdl" end,
        rhylib_spawn_point = function() return cfg("spawns", "model", "models/props_combine/combine_mine01.mdl") end,
        rhylib_event_spawn = function() return cfg("spawns", "model", "models/props_combine/combine_mine01.mdl") end,
        rhylib_training_beacon = function() return cfg("training", "beaconModel", "models/props_combine/combine_mine01.mdl") end,
        rhylib_test_dummy = function() return ok("models/ct_trp/pm_ct_trp.mdl") or "models/aussiwozzi/cgi/base/unassigned_cpt.mdl" end,
        rhylib_test_dummy_tough = function() return ok("models/ct_trp/pm_ct_trp.mdl") or "models/aussiwozzi/cgi/base/unassigned_cpt.mdl" end,
        rhylib_droid_marker = function() return "models/hunter/blocks/cube025x025x025.mdl" end,
    }
    local f = byClass[class]
    if f then return ok(f()) end
    return ok(t.Model) or ok(t.WorldModel)
end

function Tool.EntryModel(e)
    if e.preset then return Tool.ClassModel(PRESET_CLASS[e.preset]) end
    if e.order or e.follow or e.perma then return nil end
    return Tool.ClassModel(e.class)
end

-- What the Permanent tool works on: the entity aimed at, or (for things
-- that aren't solid, like jail cells and spawn points) the nearest one
-- within 48 units of where you aim. Shared, so the outline matches: the
-- fallback only picks scripted entities (both realms agree on that).
local PICK_R = 48
function Tool.PermaTarget(ply)
    local start = ply:EyePos()
    local tr = util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * Tool.RANGE, filter = ply, mask = MASK_SOLID })
    local e = tr.Entity
    if IsValid(e) and e:IsPlayer() then return nil end
    if IsValid(e) and not e:IsWorld() then return e end
    if not tr.Hit then return nil end
    local best, bestD = nil, PICK_R * PICK_R
    for _, c in ipairs(ents.FindInSphere(tr.HitPos, PICK_R)) do
        if IsValid(c) and c:IsScripted() and not c:IsPlayer() and not c:IsWeapon()
            and not IsValid(c:GetParent()) and not (IsValid(c:GetOwner()) and c:GetOwner():IsPlayer())
            and not (SERVER and c:CreatedByMap())
            and isstring(c:GetModel()) and c:GetModel() ~= "" then
            local d = c:GetPos():DistToSqr(tr.HitPos)
            if d < bestD then best, bestD = c, d end
        end
    end
    return best
end

function Tool.ById(id)
    for _, e in ipairs(Tool.Entries()) do
        if e.id == id then return e end
    end
end

function Tool.ByClass(class)
    for _, e in ipairs(Tool.Entries()) do
        if e.class == class then return e end
    end
end

Rhylib.Perms.Register("rhylib.toolgun", "admin", "Use the Rhylib toolgun (place droids, armouries, beacons and other fixtures)")

-- Limited toolgun access (2026-10-09y, owner: gamemasters place bombs).
-- An entry may set perm = "<permission>": staff without rhylib.toolgun but
-- with that permission may hold the toolgun and use only those entries
-- (rhylib_eod: rhylib.eod.gm for bombs and mines). These checks are
-- for the client's list; the server checks with Rhylib.Perms.
local function has(ply, perm)
    local A = Rhylib.Admin
    if A and A.Has then return A.Has(ply, perm, "admin") end
    return IsValid(ply) and ply:IsAdmin()
end

function Tool.FullAccess(ply) return has(ply, "rhylib.toolgun") end

function Tool.CanEntry(ply, e)
    if Tool.FullAccess(ply) then return true end
    return e and e.perm and has(ply, e.perm) or false
end

-- The permissions that give limited access (one list per map).
function Tool.EntryPerms()
    local seen, out = {}, {}
    for _, e in ipairs(Tool.Entries()) do
        if e.perm and not seen[e.perm] then seen[e.perm] = true out[#out + 1] = e.perm end
    end
    return out
end
