--[[
    Wearable gear (bodygroups), owner's design:

      Parts are items from the gear cabinet, worn in the inventory's gear
      slots (rhylib_inventory Items.WORN): kama, pauldron, binoculars,
      rangefinder, helmet light, holster. Wearing one turns its bodygroup
      on, matched by group NAME and option (.smd) NAME, because models
      number them differently (327th kama = "co_kama | empty", 104th =
      "empty | co_kama | ..."). You can't wear a part your model doesn't
      have ("you have to see it to wear it"); changing to a model without
      it takes it off. Parts can be taken off and dropped.

      Battalion kit (config gear kit) is given at spawn as job gear; the
      cabinet hands out the rest, some only from a rank or qualification
      (config gear unlocks). Helmet variants stay with the job model.

      Effects: kama = less blast damage to the legs and a lower chance of
      breaking a leg; pauldron = armour lasts longer; binoculars and
      rangefinder = optics (zoom, range, night vision, flip down while
      used; sh_30_optics.lua); helmet light = the flashlight works;
      holster = a pistol slot (Items.HOLSTER).

    rhylib_gear_scan (sv_10_scan.lua) lists every job model's bodygroups.
]]

Rhylib.Gear = Rhylib.Gear or {}
local G = Rhylib.Gear
local Config = Rhylib.Config

Rhylib.Perms.Register("rhylib.gear.admin", "admin", "Run the bodygroup scan")

-- Bodygroups each slot drives: the group names to look for, the option
-- names for "on" and (optics) "down". Lower case, without ".smd".
G.PARTS = {
    kama = { groups = { "kama" }, on = { "co_kama" } },
    pauldron = { groups = { "pauldron" }, on = { "co_pauldron" } },
    binos = { groups = { "binos" }, on = { "trooper_binosup" }, down = { "trooper_binosdown" } },
    rangefinder = { groups = { "rangefinder", "antenna" }, on = { "co_antennaup" }, down = { "co_antennadown" } },
    light = { groups = { "flashlighthelmet" }, on = { "trooper_flashlight" } },
    holster = { groups = { "holster_left", "holster_right" }, on = { "co_holster_left_reference", "co_holster_right_reference" } },
}
-- The back slot's item shows in the backpack group (nothing worn = empty).
G.BACK_GROUPS = { "backpack", "back" }
G.BACK_OPTIONS = { backpack = { "backpack" }, jetpack = { "jetpack" } }

-- The items (id -> slot), registered once the inventory has loaded.
G.ITEMS = {
    rhylib_kama = { slot = "kama", name = "Kama", desc = "Worn: less blast damage to your legs, and they break less often",
        w = 2, h = 1, weight = 1.2, model = "models/props_c17/briefcase001a.mdl" },
    rhylib_pauldron = { slot = "pauldron", name = "Pauldron", desc = "Worn: your armour lasts longer",
        w = 1, h = 1, weight = 0.8, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_macrobinoculars = { slot = "binos", name = "Macrobinoculars", desc = "Worn on the helmet: zoom, range and night vision (optics key)",
        w = 1, h = 1, weight = 0.6, model = "models/props_lab/binderblue.mdl" },
    rhylib_rangefinder = { slot = "rangefinder", name = "Rangefinder", desc = "Worn on the helmet: zoom, range and night vision (optics key)",
        w = 1, h = 1, weight = 0.4, model = "models/props_lab/reciever01d.mdl" },
    rhylib_helmet_light = { slot = "light", name = "Helmet light", desc = "Worn: your flashlight works",
        w = 1, h = 1, weight = 0.2, model = "models/props_junk/garbage_metalcan001a.mdl" },
    rhylib_holster = { slot = "holster", name = "Holster", desc = "Worn: a holster for one pistol",
        w = 1, h = 1, weight = 0.4, model = "models/props_junk/garbage_bag001a.mdl", grid = { 2, 1 }, gridName = "holster" },
}
G.BY_SLOT = {}
for id, it in pairs(G.ITEMS) do G.BY_SLOT[it.slot] = id end

Config.Register("gear", "kit", { ["*"] = { "rhylib_macrobinoculars" }, ["327th"] = { "rhylib_kama", "rhylib_pauldron" } },
    "Battalion kit given at spawn as job gear: battalion (part of its name, * = everyone) -> item ids")
Config.Register("gear", "unlocks", {
    rhylib_kama = { rank = "SGT" }, rhylib_pauldron = { rank = "SGT" }, rhylib_rangefinder = { rank = "LT" },
}, "Gear cabinet parts that need a rank (rank prefix, rhylib_roster) or a qualification (qual id); your battalion kit is always allowed")
Config.Register("gear", "kamaBlastMult", 0.5, "Kama: blast damage to the legs (body part damage) is multiplied by this")
Config.Register("gear", "kamaFractureChance", 0.5, "Kama: chance a leg actually breaks when it would")
Config.Register("gear", "pauldronDrainMult", 0.8, "Pauldron: armour lost per hit is multiplied by this")
Config.Register("gear", "lightNeeded", true, "The flashlight only works with a helmet light worn")

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

-- Does this player's model show this slot's part?
function G.ModelHas(ply, slot)
    local part = G.PARTS[slot]
    if not part then return true end
    local info = G.ModelInfo(ply)
    for _, gn in ipairs(part.groups) do
        if G.Option(info.groups[gn], part.on) then return true end
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

-- You have to see it to wear it.
Rhylib.Hook.Add("Rhylib.CanWear", "gear.model", function(ply, def)
    if not (def and G.PARTS[def.slot]) then return end
    if not G.ModelHas(ply, def.slot) then
        local w = Rhylib.Items.WORN[Rhylib.Items.WORN_BY_SLOT[def.slot]]
        return false, "Your model has no " .. string.lower(w and w.title or def.slot)
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

-- Items go in once the inventory module exists (it loads after this one).
local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) then return false end
    for id, it in pairs(G.ITEMS) do
        Items.Register(id, {
            name = it.name, desc = it.desc, w = it.w, h = it.h, weight = it.weight, model = it.model,
            category = "gear", slot = it.slot, grid = it.grid, gridCid = it.grid and Items.HOLSTER or nil, gridName = it.gridName,
        })
    end
    return true
end
if not registerItems() then
    hook.Add("Rhylib.ModuleLoaded", "gear.items", function(id)
        if id == "inventory" then registerItems() end
    end)
end
