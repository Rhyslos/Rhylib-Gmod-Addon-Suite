--[[
    Wearable gear (bodygroups), owner's design:

      Parts are items from the gear cabinet, worn in the inventory's gear
      slots (rhylib_inventory Items.WORN): kama, pauldron, binoculars,
      rangefinder, helmet lights, sun visor, holster, forearm, shoulder
      antenna, belt pouches, plus back-slot items (ARC / comms backpack,
      gun belts, strap). Every bodygroup in the scan is an item. The
      cabinet only offers what your model shows and you may take.
      Wearing one turns its bodygroup
      on, matched by group NAME and option (.smd) NAME, because models
      number them differently (327th kama = "co_kama | empty", 104th =
      "empty | co_kama | ..."). You can't wear a part your model doesn't
      have ("you have to see it to wear it"); on a model without it, it
      stays worn but does nothing. Parts can be taken off and dropped.

      Battalion kit (config gear kit) is given at spawn as job gear; the
      cabinet hands out the rest, some only from a rank or qualification
      (config gear unlocks). Helmet variants stay with the job model.

      Effects: kama = less blast damage to the legs and a lower chance of
      breaking a leg; pauldron = armour lasts longer; binoculars and
      rangefinder = optics (zoom, range, night vision, flip down while
      used; sh_30_optics.lua); helmet lights = two forward beams on the
      flashlight key (cl_40_lights.lua); holster = a pistol slot
      (Items.HOLSTER, two pistols); belt pouches = 5 slots (Items.POUCH);
      ARC backpack = 4x4 backpack + a cell pouch for two power cells
      (Items.CELLPACK); comms backpack = a backpack; gun belts = the
      DC-15A and RPS-6 weigh half (def.weightMults). The rest are
      cosmetic for now.

    rhylib_gear_scan (sv_10_scan.lua) lists every job model's bodygroups.
]]

Rhylib.Gear = Rhylib.Gear or {}
local G = Rhylib.Gear
local Config = Rhylib.Config

Rhylib.Perms.Register("rhylib.gear.admin", "admin", "Run the bodygroup scan")

-- Items, registered once the inventory has loaded. Each shows as
-- bodygroups: groups = the group names to look for, on / down (optics in
-- use) = option names, lower case without ".smd". Several items can share
-- a slot (kama / ARC kama); G.ORDER decides who gets a shared group.
-- Effects belong to the slot (an ARC kama works like a kama).
G.ITEMS = {
    rhylib_kama = { slot = "kama", name = "Kama", desc = "Worn: less blast damage to your legs, and they break less often",
        groups = { "kama" }, on = { "co_kama" },
        w = 2, h = 1, weight = 1.2, model = "models/props_c17/briefcase001a.mdl" },
    rhylib_kama_arc = { slot = "kama", name = "ARC kama", desc = "Worn: less blast damage to your legs, and they break less often",
        groups = { "kama" }, on = { "arc2_arc_kama_strap_reference" },
        w = 2, h = 1, weight = 1.2, model = "models/props_c17/briefcase001a.mdl" },
    rhylib_pauldron = { slot = "pauldron", name = "Pauldron", desc = "Worn: your armour lasts longer",
        groups = { "pauldron" }, on = { "co_pauldron" },
        w = 1, h = 1, weight = 0.8, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_pauldron_arc = { slot = "pauldron", name = "ARC pauldron", desc = "Worn: your armour lasts longer",
        groups = { "pauldron" }, on = { "arc2_arcpauldron" },
        w = 1, h = 1, weight = 0.9, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_macrobinoculars = { slot = "binos", name = "Macrobinoculars", desc = "Worn on the helmet: zoom, range and night vision (optics key)",
        groups = { "binos" }, on = { "trooper_binosup" }, down = { "trooper_binosdown" }, optics = 1,
        w = 1, h = 1, weight = 0.6, model = "models/props_lab/binderblue.mdl" },
    rhylib_rangefinder = { slot = "rangefinder", name = "Rangefinder", desc = "Worn on the helmet: zoom, range and night vision (optics key)",
        groups = { "rangefinder", "antenna" }, on = { "co_antennaup" }, down = { "co_antennadown" }, optics = 2,
        w = 1, h = 1, weight = 0.4, model = "models/props_lab/reciever01d.mdl" },
    rhylib_helmet_light = { slot = "light", name = "Helmet lights", desc = "Worn on the helmet: two lamps (flashlight key)",
        groups = { "flashlighthelmet" }, on = { "trooper_flashlight" },
        w = 1, h = 1, weight = 0.2, model = "models/props_junk/garbage_metalcan001a.mdl" },
    rhylib_sunvisor = { slot = "visor", name = "Sun visor", desc = "Worn on the helmet (not with macrobinoculars on models where they share a mount)",
        groups = { "sunvisor", "binos" }, on = { "sunvisor" },
        w = 1, h = 1, weight = 0.1, model = "models/props_lab/binderblue.mdl" },
    rhylib_holster = { slot = "holster", name = "Holster", desc = "Worn: holsters for two pistols",
        groups = { "holster_left", "holster_right" }, on = { "co_holster_left_reference", "co_holster_right_reference" },
        w = 1, h = 1, weight = 0.4, model = "models/props_junk/garbage_bag001a.mdl", grid = { 2, 2 }, gridName = "holster", gridCid = "HOLSTER" },   -- (owner: two pistols, one per holster)
    rhylib_forearm_arc = { slot = "forearm", name = "ARC forearm guard", desc = "Worn on the right forearm",
        groups = { "forearms" }, on = { "arc2_arc_forearm_right_reference" },
        w = 1, h = 1, weight = 0.5, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_shoulder_antenna = { slot = "comms", name = "Shoulder antenna", desc = "Worn on the shoulder",
        groups = { "shoulderantenna" }, on = { "s_ant" },
        w = 1, h = 1, weight = 0.4, model = "models/props_lab/reciever01d.mdl" },
    rhylib_belt_pouches = { slot = "belt", name = "Belt pouches", desc = "Worn on the belt: 5 more slots (no rifles or launchers)",
        groups = { "belt" }, on = { "arc2_arc_belt_pouches_reference" },
        w = 2, h = 1, weight = 0.6, model = "models/props_junk/garbage_bag001a.mdl",
        grid = { 5, 1 }, gridName = "belt pouches", gridCid = "POUCH" },
    -- Back slot (instead of a backpack or jetpack).
    rhylib_arc_backpack = { slot = "back", name = "ARC backpack", desc = "Worn on the back: a 4x4 backpack and a side pouch for two power cells",
        groups = { "backpack", "back" }, on = { "arc2_arc_backpack_reference" },
        w = 2, h = 2, weight = 2, carry = 6, grid = { 4, 4 }, gridName = "backpack", model = "models/props_c17/suitcase001a.mdl",
        extraGrids = { { cid = "CELLPACK", w = 2, h = 2, name = "cell pouch" } } },
    rhylib_comms_backpack = { slot = "back", name = "Comms backpack", desc = "Worn on the back: a radio pack with a little room",
        groups = { "backpack", "back" }, on = { "comms_backpackcomms_2" },
        w = 2, h = 2, weight = 3, carry = 4, grid = { 3, 2 }, gridName = "backpack", model = "models/props_lab/reciever01b.mdl" },
    rhylib_gunbelt = { slot = "back", name = "Gun belt", desc = "Worn on the back: the DC-15A and RPS-6 weigh half",
        groups = { "backpack", "back" }, on = { "gunbelt" },
        w = 2, h = 1, weight = 0.5, model = "models/props_junk/garbage_bag001a.mdl", weightMults = { rhylib_dc15a = 0.5, rhylib_dc15a_training = 0.5, rhylib_rps6 = 0.5, rhylib_rps6_training = 0.5 } },
    rhylib_gunbelt_rifle = { slot = "back", name = "Rifle gun belt", desc = "Worn on the back: the DC-15A and RPS-6 weigh half",
        groups = { "backpack", "back" }, on = { "gunbelt_rifle" },
        w = 2, h = 1, weight = 0.6, model = "models/props_junk/garbage_bag001a.mdl", weightMults = { rhylib_dc15a = 0.5, rhylib_dc15a_training = 0.5, rhylib_rps6 = 0.5, rhylib_rps6_training = 0.5 } },
    rhylib_strap = { slot = "back", name = "Chest strap", desc = "Worn on the back",
        groups = { "backpack", "back" }, on = { "strap" },
        w = 1, h = 1, weight = 0.3, model = "models/props_junk/garbage_bag001a.mdl" },
}

-- How every worn item shows: gear items plus the backpack and jetpack
-- (other addons' items, always wearable).
G.SHOWS = {
    backpack = { slot = "back", groups = { "backpack", "back" }, on = { "backpack" } },
    jetpack = { slot = "back", groups = { "backpack", "back" }, on = { "jetpack" } },
}
for id, it in pairs(G.ITEMS) do G.SHOWS[id] = it end

-- Who gets a shared group first (binoculars before the sun visor).
G.ORDER = { "rhylib_macrobinoculars", "rhylib_rangefinder", "rhylib_sunvisor", "rhylib_helmet_light",
    "rhylib_kama", "rhylib_kama_arc", "rhylib_pauldron", "rhylib_pauldron_arc", "rhylib_holster",
    "rhylib_forearm_arc", "rhylib_shoulder_antenna", "rhylib_belt_pouches",
    "backpack", "jetpack", "rhylib_arc_backpack", "rhylib_comms_backpack", "rhylib_gunbelt", "rhylib_gunbelt_rifle", "rhylib_strap" }
do
    local listed = {}
    for _, id in ipairs(G.ORDER) do listed[id] = true end
    for id in pairs(G.SHOWS) do if not listed[id] then G.ORDER[#G.ORDER + 1] = id end end
end

-- Every group any item drives (set to empty when nothing worn claims it).
G.ALL_GROUPS = {}
for _, s in pairs(G.SHOWS) do
    for _, gn in ipairs(s.groups) do G.ALL_GROUPS[gn] = true end
end

-- Parts mounted on the helmet: hidden and unusable with the helmet off.
G.ON_HELMET = { binos = true, rangefinder = true, light = true, visor = true }

function G.HelmetOn(ply) return not ply:GetNW2Bool("rhylib_helmetOff", false) end

Config.Register("gear", "kit", { ["*"] = { "rhylib_macrobinoculars" }, ["327th"] = { "rhylib_kama", "rhylib_pauldron" } },
    "Battalion kit given at spawn as job gear: battalion (part of its name, * = everyone) -> item ids")
Config.Register("gear", "unlocks", {
    rhylib_kama = { rank = "SGT" }, rhylib_pauldron = { rank = "SGT" }, rhylib_rangefinder = { rank = "LT" },
    rhylib_kama_arc = { rank = "SGT" }, rhylib_pauldron_arc = { rank = "SGT" },
}, "Gear cabinet parts that need a rank (rank prefix, rhylib_roster) or a qualification (qual id); your battalion kit is always allowed")
Config.Register("gear", "kamaBlastMult", 0.5, "Kama: blast damage to the legs (body part damage) is multiplied by this")
Config.Register("gear", "kamaFractureChance", 0.5, "Kama: chance a leg actually breaks when it would")
Config.Register("gear", "pauldronDrainMult", 0.8, "Pauldron: armour lost per hit is multiplied by this")
Config.Register("gear", "lightNeeded", true, "The flashlight key only works with helmet lights worn")
Config.Register("gear", "lightFov", 26, "Helmet lights: width of each beam (degrees); the two point apart with a small gap between")
Config.Register("gear", "lightGap", -2, "Helmet lights: extra degrees each beam turns outwards past touching (positive = a dark gap in the middle, negative = closer together)")
Config.Register("gear", "lightRange", 2000, "Helmet lights: how far the beams reach")
Config.Register("gear", "lightBrightness", 3.5, "Helmet lights: brightness of each beam")
Config.Register("gear", "lightMaxPlayers", 4, "Helmet lights: most players whose beams you see at once (nearest first; each beam costs a render pass)")
Config.Register("gear", "bareHeadshotDowns", true, "With the helmet off, any head hit downs you")

function G.Cfg(k) return Config.Get("gear", k) end

local function norm(s)
    s = string.lower(tostring(s or ""))
    return (string.gsub(s, "%.smd$", ""))
end
G.Norm = norm

-- A model's bodygroups by name: { [group] = { id, opts = { [option] = index } } },
-- cached per model.
G.modelCache = G.modelCache or {}
function G.ModelInfo(ent)
    local mdl = ent:GetModel() or ""
    local info = G.modelCache[mdl]
    if info then return info end
    info = { groups = {} }
    for _, g in ipairs(ent:GetBodyGroups() or {}) do
        local opts = {}
        for i = 0, (g.num or 1) - 1 do
            local sub = g.submodels and g.submodels[i]
            if sub then opts[norm(sub)] = i end
        end
        info.groups[norm(g.name)] = { id = g.id, opts = opts }
    end
    if table.Count(G.modelCache) > 64 then G.modelCache = {} end
    G.modelCache[mdl] = info
    return info
end

-- Option index in group g for the first of names, or nil.
function G.Option(g, names)
    if not (g and names) then return nil end
    for _, n in ipairs(names) do
        if g.opts[n] then return g.opts[n] end
    end
end

-- Does this player's model show this item?
function G.ItemShown(ply, id)
    local s = G.SHOWS[id]
    if not s then return true end
    local info = G.ModelInfo(ply)
    for _, gn in ipairs(s.groups) do
        if G.Option(info.groups[gn], s.on) then return true end
    end
    return false
end

-- Does it show any item for this slot? (The inventory hides empty gear
-- slots it can't show.)
function G.ModelHas(ply, slot)
    for id, it in pairs(G.ITEMS) do
        if it.slot == slot and G.ItemShown(ply, id) then return true end
    end
    return false
end

-- The item worn in a gear slot, or nil (server: the inventory; client: your own copy).
function G.Worn(ply, slot)
    local Items, Inv = Rhylib.Items, Rhylib.Inventory
    local cid = Items and Items.WORN_BY_SLOT and Items.WORN_BY_SLOT[slot]
    if not (cid and Inv) then return nil end
    local cont
    if SERVER then
        local st = Inv.states and Inv.states[ply]
        cont = st and st.cont[cid]
    elseif ply == LocalPlayer() then
        cont = Inv.cont and Inv.cont[cid]
    end
    if not cont then return nil end
    local _, inst = next(cont.items)
    return inst
end

-- Worn AND shown by the model (and its helmet on, for helmet parts): only
-- then does a part do anything. Parts the current model can't show stay
-- worn but inert (owner: joining as a cadet after a map change used to
-- take everything off).
function G.Active(ply, slot)
    local inst = G.Worn(ply, slot)
    if inst == nil then return false end
    if G.ON_HELMET[slot] and not G.HelmetOn(ply) then return false end
    return G.ItemShown(ply, inst.id)
end

-- You have to see it to wear it, and helmet lights rule out optics (the back slot is free: a backpack works
-- whatever the model shows).
Rhylib.Hook.Add("Rhylib.CanWear", "gear.model", function(ply, def)
    if not (def and def.slot and def.slot ~= "back") then return end
    -- Helmet lights and optics share the helmet mount (owner: one or the other).
    if def.slot == "light" and (G.Worn(ply, "binos") or G.Worn(ply, "rangefinder")) then
        return false, "Take off the macrobinoculars or rangefinder first: they use the same helmet mount"
    end
    if (def.slot == "binos" or def.slot == "rangefinder") and G.Worn(ply, "light") then
        return false, "Take off the helmet lights first: they use the same helmet mount"
    end
    local gid = def.id
    if gid and G.ITEMS[gid] and not G.ItemShown(ply, gid) then
        return false, "Your model can't show the " .. string.lower(G.ITEMS[gid].name)
    end
end)

-- Does a battalion name match a kit key ("*" = everyone, else part of the name)?
function G.InBattalion(ply, key)
    if key == "*" then return true end
    key = string.lower(key)
    local names = { ply:GetNW2String("rhylib_bn", "") }
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    if job then
        names[#names + 1] = job.battalion or ""
        names[#names + 1] = job.category or ""
        names[#names + 1] = job.name or ""
    end
    for _, n in ipairs(names) do
        if n ~= "" and string.find(string.lower(n), key, 1, true) then return true end
    end
    return false
end

-- The kit item ids for this player (set).
function G.KitFor(ply)
    local out = {}
    for key, list in pairs(G.Cfg("kit") or {}) do
        if istable(list) and G.InBattalion(ply, key) then
            for _, id in ipairs(list) do out[id] = true end
        end
    end
    return out
end

-- May this player take this part from the cabinet? Returns false, reason.
function G.Unlocked(ply, id)
    local rule = (G.Cfg("unlocks") or {})[id]
    if not istable(rule) or G.KitFor(ply)[id] then return true end
    local R = Rhylib.Roster
    if rule.rank and R and R.RankIndex then
        local need = R.RankIndex(rule.rank)
        if need and ply:GetNW2Int("rhylib_rank", 0) < need then
            return false, "Needs the rank " .. (R.RankName and R.RankName(need) or rule.rank)
        end
    end
    if rule.qual and R and R.HasQual and not R.HasQual(ply, rule.qual) then
        return false, "Needs the " .. (R.QualName and R.QualName(rule.qual) or rule.qual) .. " qualification"
    end
    return true
end

-- Extra containers of an item, with container names turned into ids.
local function extraGrids(it)
    if not it.extraGrids then return nil end
    local out = {}
    for _, g in ipairs(it.extraGrids) do
        local cid = Rhylib.Items[g.cid]
        if cid then out[#out + 1] = { cid = cid, w = g.w, h = g.h, name = g.name } end
    end
    return out
end

-- Items go in once the inventory module exists (it loads after this one).
local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) then return false end
    for id, it in pairs(G.ITEMS) do
        Items.Register(id, {
            name = it.name, desc = it.desc, w = it.w, h = it.h, weight = it.weight, model = it.model,
            category = "gear", slot = it.slot, grid = it.grid, gridCid = it.gridCid and Items[it.gridCid] or nil, gridName = it.gridName,
            carry = it.carry, weightMults = it.weightMults, extraGrids = extraGrids(it),
            group = it.slot ~= "back" and (G.ON_HELMET[it.slot] and "helmet" or "body") or nil,
        })
    end
    return true
end
if not registerItems() then
    hook.Add("Rhylib.ModuleLoaded", "gear.items", function(id)
        if id == "inventory" then registerItems() end
    end)
end
