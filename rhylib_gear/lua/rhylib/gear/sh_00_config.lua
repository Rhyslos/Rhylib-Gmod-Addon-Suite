--[[
    Wearable gear (bodygroups):

      Parts are items from the gear cabinet, worn in the inventory's gear
      slots (rhylib_inventory Items.WORN): kama, pauldron, the helmet slot
      (macrobinoculars, rangefinder, helmet lights or sun visor: one at a
      time), holster, forearm, shoulder antenna, belt pouches, plus
      back-slot items (ARC / comms backpack, gun belts, strap). Every
      bodygroup in the scan is an item. The
      cabinet only offers what your model shows and you may take.
      Wearing one turns its bodygroup
      on, matched by group NAME and option (.smd) NAME, because models
      number them differently (327th kama = "co_kama | empty", 104th =
      "empty | co_kama | ..."). You can't wear a part your model doesn't
      have ("you have to see it to wear it"); on a model without it, it
      stays worn but does nothing. Parts can be taken off and dropped.

      Battalion kit (config gear kit, empty by default) is given at spawn
      as job gear; the cabinet hands out the rest (kept: the inventory is
      saved), some only from a rank or qualification
      (config gear unlocks). Helmet variants stay with the job model.

      Effects: kama = less blast damage to the legs and a lower chance of
      a limp (hardcore medical: of breaking a leg); pauldron = armour lasts longer; binoculars and
      rangefinder = optics (zoom, range, night vision, flip down while
      used; sh_30_optics.lua); helmet lights = two forward beams on the
      flashlight key (cl_40_lights.lua); holster = a pistol slot
      (Items.HOLSTER, two pistols); belt pouches = 5 slots (Items.POUCH);
      ARC backpack = 4x4 backpack + a cell pouch for two power cells
      (Items.CELLPACK); comms backpack = a backpack; gun belts = a 6x1
      grid (Items.GUNBELT) and the DC-15A and RPS-6 weigh half
      (def.weightMults); shoulder antenna = jammer resistance (read by
      rhylib_radio through G.Active(ply, "comms")) and a longer command
      comlink reach (rhylib_skills K.OrderRadius, antennaReachMult). The rest are cosmetic
      for now.

    Helmet slot: the four helmet parts share one worn slot ("helmet").
    Each keeps its own part name (it.part: binos, rangefinder, light,
    visor), and G.Worn / G.Active still answer for those names, so
    G.Active(ply, "visor") is true only while the sun visor is the part
    worn. Old saves with several parts worn keep one (G.ORDER: macro-
    binoculars, rangefinder, sun visor, helmet lights; def.wornRank) and
    the rest move into the inventory or onto the ground (rhylib_inventory).

    rhylib_gear_scan (sv_10_scan.lua) lists every job model's bodygroups,
    then runs each item's keyword rules (it.match, G.MATCH below) over
    them and learns the group / option names of models whose names differ
    from the built-in ones. Learned names are merged into the items'
    groups / on / down lists on both realms (G.SetLearned; the built-in
    names stay, G.BUILTIN). Server -> client net rhylib.gear.learned
    (UInt32 length + compressed JSON), sent on join (client asks with
    rhylib.gear.learnreq) and after each scan or reset.

    Also: the helmet on / off toggle (inventory button; hair shows only
    with the helmet off, and a head hit then downs you) and the sun visor
    (a red tactical view, sh_30_optics / cl_30_optics).

    Shared file: Rhylib.Gear (G) with the item list (G.ITEMS, G.SHOWS,
    G.ORDER), the config module "gear", and the lookups both realms use:
    G.ModelInfo, G.InfoShows, G.ItemShown, G.ModelHas, G.Worn, G.Active,
    G.KitFor, G.Unlocked, G.IsOffName, G.SetLearned. Answers
    rhylib_inventory's hook Rhylib.CanWear.
]]

Rhylib.Gear = Rhylib.Gear or {}
local G = Rhylib.Gear
local Config = Rhylib.Config

-- Permission for rhylib_gear_scan (default: admin).
Rhylib.Perms.Register("rhylib.gear.admin", "admin", "Run the bodygroup scan")

-- Items, registered once the inventory has loaded. Each shows as
-- bodygroups: groups = the group names to look for, on / down (optics in
-- use) = option names, lower case without ".smd". Several items can share
-- a slot (kama / ARC kama); G.ORDER decides who gets a shared group.
-- Effects belong to the slot (an ARC kama works like a kama).
-- Fields: slot (worn slot, rhylib_inventory Items.WORN), part (helmet parts:
-- the name effects use, see G.Worn), name, desc, groups,
-- on, down (optics only), optics (1 binoculars, 2 rangefinder), w / h
-- (cells), weight (kg), model (inventory picture), grid / gridName /
-- gridCid / extraGrids (containers it adds), carry, weightMults
-- ({ item id = weight multiplier } while worn).
G.ITEMS = {
    rhylib_kama = { slot = "kama", name = "Kama", desc = "Worn: less blast damage to your legs, and you limp (or break a leg) less often",
        groups = { "kama" }, on = { "co_kama" },
        w = 2, h = 1, weight = 1.2, model = "models/props_c17/briefcase001a.mdl" },
    rhylib_kama_arc = { slot = "kama", name = "ARC kama", desc = "Worn: less blast damage to your legs, and you limp (or break a leg) less often",
        groups = { "kama" }, on = { "arc2_arc_kama_strap_reference" },
        w = 2, h = 1, weight = 1.2, model = "models/props_c17/briefcase001a.mdl" },
    rhylib_pauldron = { slot = "pauldron", name = "Pauldron", desc = "Worn: your armour lasts longer",
        groups = { "pauldron" }, on = { "co_pauldron" },
        w = 1, h = 1, weight = 0.8, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_pauldron_arc = { slot = "pauldron", name = "ARC pauldron", desc = "Worn: your armour lasts longer",
        groups = { "pauldron" }, on = { "arc2_arcpauldron" },
        w = 1, h = 1, weight = 0.9, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_macrobinoculars = { slot = "helmet", part = "binos", name = "Macrobinoculars", desc = "Helmet slot (one helmet part at a time): zoom, range and night vision (optics key)",
        groups = { "binos" }, on = { "trooper_binosup" }, down = { "trooper_binosdown" }, optics = 1,
        w = 1, h = 1, weight = 0.6, model = "models/props_lab/binderblue.mdl" },
    rhylib_rangefinder = { slot = "helmet", part = "rangefinder", name = "Rangefinder", desc = "Helmet slot (one helmet part at a time): zoom, range and night vision (optics key)",
        groups = { "rangefinder", "antenna" }, on = { "co_antennaup" }, down = { "co_antennadown" }, optics = 2,
        w = 1, h = 1, weight = 0.4, model = "models/props_lab/reciever01d.mdl" },
    rhylib_helmet_light = { slot = "helmet", part = "light", name = "Helmet lights", desc = "Helmet slot (one helmet part at a time): two lamps (flashlight key)",
        groups = { "flashlighthelmet" }, on = { "trooper_flashlight" },
        w = 1, h = 1, weight = 0.2, model = "models/props_junk/garbage_metalcan001a.mdl" },
    rhylib_sunvisor = { slot = "helmet", part = "visor", name = "Sun visor", desc = "Helmet slot (one helmet part at a time). Helmet gear key (L): visor down for a red tactical view, 3x zoom while aiming, night vision on the flashlight key; with Mark target it spots enemies every 5 s.",
        groups = { "sunvisor", "binos" }, on = { "sunvisor" },
        w = 1, h = 1, weight = 0.1, model = "models/props_lab/binderblue.mdl" },
    rhylib_holster = { slot = "holster", name = "Holster", desc = "Worn: holsters for two pistols",
        groups = { "holster_left", "holster_right" }, on = { "co_holster_left_reference", "co_holster_right_reference" },
        w = 1, h = 1, weight = 0.4, model = "models/props_junk/garbage_bag001a.mdl", grid = { 2, 2 }, gridName = "holster", gridCid = "HOLSTER" },   -- (two pistols, one per holster)
    rhylib_forearm_arc = { slot = "forearm", name = "ARC forearm guard", desc = "Worn on the right forearm",
        groups = { "forearms" }, on = { "arc2_arc_forearm_right_reference" },
        w = 1, h = 1, weight = 0.5, model = "models/props_junk/garbage_metalcan002a.mdl" },
    rhylib_shoulder_antenna = { slot = "comms", name = "Shoulder antenna", desc = "Worn on the shoulder: resists comms jammers (you're only fully jammed once you're 30% of the way into a small or medium jammer's range, 10% for a large one; a whole-map jammer still jams you), and an officer's command comlink reaches 50% further",
        groups = { "shoulderantenna" }, on = { "s_ant" },
        w = 1, h = 1, weight = 0.4, model = "models/props_lab/reciever01d.mdl" },
    rhylib_belt_pouches = { slot = "belt", name = "Belt pouches", desc = "Worn on the belt: 5 more slots (no rifles or launchers)",
        groups = { "belt" }, on = { "arc2_arc_belt_pouches_reference" },
        w = 2, h = 1, weight = 0.6, model = "models/props_junk/garbage_bag001a.mdl",
        grid = { 5, 1 }, gridName = "belt pouches", gridCid = "POUCH" },
    -- Back slot (instead of a backpack or jetpack).
    rhylib_arc_backpack = { slot = "back", name = "ARC backpack", desc = "Worn on the back: a 4x4 backpack and a side pouch for two power cells",
        groups = { "backpack", "back" }, on = { "arc2_arc_backpack_reference" },
        w = 2, h = 2, weight = 2, carry = 4, grid = { 4, 4 }, gridName = "backpack", model = "models/props_c17/suitcase001a.mdl",
        extraGrids = { { cid = "CELLPACK", w = 2, h = 1, name = "cell pouch" } } },
    rhylib_comms_backpack = { slot = "back", name = "Comms backpack", desc = "Worn on the back: a radio pack with a little room",
        groups = { "backpack", "back" }, on = { "comms_backpackcomms_2" },
        w = 2, h = 2, weight = 3, carry = 3, grid = { 3, 2 }, gridName = "backpack", model = "models/props_lab/reciever01b.mdl" },
    rhylib_gunbelt = { slot = "back", name = "Gun belt", desc = "Worn on the back: 6 slots (no long guns), and the DC-15A and RPS-6 weigh half",
        groups = { "backpack", "back" }, on = { "gunbelt" },
        w = 2, h = 1, weight = 0.5, model = "models/props_junk/garbage_bag001a.mdl", grid = { 6, 1 }, gridName = "gun belt", gridCid = "GUNBELT", weightMults = { rhylib_dc15a = 0.5, rhylib_dc15a_training = 0.5, rhylib_rps6 = 0.5, rhylib_rps6_training = 0.5 } },
    rhylib_gunbelt_rifle = { slot = "back", name = "Rifle gun belt", desc = "Worn on the back: 6 slots (no long guns), and the DC-15A and RPS-6 weigh half",
        groups = { "backpack", "back" }, on = { "gunbelt_rifle" },
        w = 2, h = 1, weight = 0.6, model = "models/props_junk/garbage_bag001a.mdl", grid = { 6, 1 }, gridName = "gun belt", gridCid = "GUNBELT", weightMults = { rhylib_dc15a = 0.5, rhylib_dc15a_training = 0.5, rhylib_rps6 = 0.5, rhylib_rps6_training = 0.5 } },
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

-- Keyword rules for rhylib_gear_scan (sv_10_scan.lua), set as each
-- entry's .match. Lower case, plain substrings; an entry that is a table
-- needs all its words (e.g. { "shoulder", "antenna" }).
--   words:    hit in the option name (best), or in "group option" when no
--             item's words hit the option name itself (not with
--             groupFallback = false: parts that share one back group)
--   need:     one of these must also be in the name that hit
--   notWords: none of these may be in the option name
--   notGroups: none of these may be in the group name
-- Options that mean "nothing" (G.IsOffName) never count. The best score
-- wins an option (an option-name hit, plus a bonus when the group name
-- also has one of the item's words); a tie between items is reported and
-- left unlearned.
G.MATCH = {
    rhylib_kama = { words = { "kama" }, notWords = { "arc" } },
    rhylib_kama_arc = { words = { "kama" }, need = { "arc" } },
    rhylib_pauldron = { words = { "pauldron", "shoulderpad", "shoulder_pad", "spaulder" }, notWords = { "arc", "antenna", "s_ant" } },
    rhylib_pauldron_arc = { words = { "pauldron", "shoulderpad", "shoulder_pad", "spaulder" }, need = { "arc" }, notWords = { "antenna", "s_ant" } },
    rhylib_macrobinoculars = { words = { "bino", "macro" }, notWords = { "visor", "range" } },
    rhylib_rangefinder = { words = { "range", "antenna" }, notWords = { "s_ant", "shoulder", "arm_", "comm", "pack", "orange" }, notGroups = { "shoulder", "arm" } },
    rhylib_helmet_light = { words = { "light", "flash", "lamp", "torch" }, notWords = { "saber", "highlight", "lightweight" } },
    rhylib_sunvisor = { words = { "visor" }, notWords = { "bandit" } },
    rhylib_holster = { words = { "holster" } },
    rhylib_forearm_arc = { words = { "forearm", "gauntlet", "bracer", "vambrace" } },
    rhylib_shoulder_antenna = { words = { "s_ant", "shoulderant", { "shoulder", "antenna" }, "arm_antenna", { "arm", "antenna" } } },
    rhylib_belt_pouches = { words = { "pouch", "belt" }, notWords = { "gun", "bandolier", "holster", "kama", "strap" } },
    rhylib_arc_backpack = { words = { { "arc", "pack" } }, groupFallback = false },
    rhylib_comms_backpack = { words = { "comms", { "comm", "pack" }, { "radio", "pack" } }, notWords = { "antenna", "s_ant", "arc", "commander" }, groupFallback = false },
    rhylib_gunbelt = { words = { "gunbelt", "gun_belt", "bandolier" }, notWords = { "rifle" }, groupFallback = false },
    rhylib_gunbelt_rifle = { words = { { "gunbelt", "rifle" }, { "gun_belt", "rifle" }, { "bandolier", "rifle" } }, groupFallback = false },
    rhylib_strap = { words = { "strap" }, notWords = { "kama", "pauldron", "holster", "pack", "belt", "arc" }, groupFallback = false },
    backpack = { words = { "backpack", "rucksack" }, notWords = { "arc", "comm", "radio", "jet" }, groupFallback = false },
    jetpack = { words = { "jetpack", "jet_pack" }, groupFallback = false },
}
for id, m in pairs(G.MATCH) do
    if G.SHOWS[id] then G.SHOWS[id].match = m end
end

-- The built-in groups / on / down of every entry (copies), so learned
-- names can be merged in and taken out again (G.SetLearned).
G.BUILTIN = {}
for id, s in pairs(G.SHOWS) do
    G.BUILTIN[id] = { groups = table.Copy(s.groups), on = table.Copy(s.on or {}), down = s.down and table.Copy(s.down) or nil }
end

-- Who gets a shared group first (binoculars before the sun visor). The
-- first four are also the helmet slot's order for old saves that had
-- several helmet parts worn: the first one listed stays worn (def.wornRank).
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
-- "helmet" is the worn slot; the rest are the part names inside it.
G.ON_HELMET = { helmet = true, binos = true, rangefinder = true, light = true, visor = true }
-- Part names that live in the one helmet slot (G.Worn / G.Active take them
-- as slot names).
G.HELMET_PARTS = { binos = true, rangefinder = true, light = true, visor = true }

-- G.HelmetOn(ply): false while the helmet is off (NW2Bool rhylib_helmetOff). Shared.
function G.HelmetOn(ply) return not ply:GetNW2Bool("rhylib_helmetOff", false) end

-- G.HelmetGroup(info) -> the model's helmet group (from G.ModelInfo):
-- "helmet", else one whose name ends in "helmet" ("parahelmet") with an
-- option that isn't a helmet (the bare head). Its "helmet" options are
-- helmet on, the others helmet off.
function G.HelmetGroup(info)
    local g = info and info.groups and info.groups.helmet
    if g then return g end
    for gn, gr in pairs(info and info.groups or {}) do
        if string.sub(gn, -6) == "helmet" then
            for name in pairs(gr.opts or {}) do
                if not string.find(name, "helmet", 1, true) then return gr end
            end
        end
    end
end

-- (No kit by default: players keep what they take from the gear cabinet,
-- since the inventory is saved.)
-- Settings (module "gear"). Change in Server settings or a host file, e.g.
-- Rhylib.Config.Set("gear", "kit", { ["327th"] = { "rhylib_kama", "rhylib_pauldron" } })
Config.Describe("gear", { name = "Wearable gear", category = "Soldiers", sections = { "Kit & unlocks", "Armour parts", "Helmet lights", "Sun visor", "Night vision" } })
Config.Register("gear", "kit", {},
    "Battalion kit given at spawn as job gear: battalion (part of its name, * = everyone) -> item ids, e.g. { [\"*\"] = { \"rhylib_macrobinoculars\" } }. Empty by default", { section = "Kit & unlocks" })
Config.Register("gear", "unlocks", {
    rhylib_kama = { rank = "SGT" }, rhylib_pauldron = { rank = "SGT" }, rhylib_rangefinder = { rank = "LT" },
    rhylib_kama_arc = { rank = "SGT" }, rhylib_pauldron_arc = { rank = "SGT" },
}, "Gear cabinet parts that need a rank (rank prefix, rhylib_roster) or a qualification (qual id); your battalion kit is always allowed", { section = "Kit & unlocks" })
Config.Register("gear", "kamaBlastMult", 0.5, "Kama: blast damage to the legs (body part damage) is multiplied by this", { section = "Armour parts" })
Config.Register("gear", "kamaLimpChance", 0.5, "Kama: chance a leg actually limps when it would", { section = "Armour parts" })
Config.Register("gear", "kamaFractureChance", 0.5, "Kama: chance a leg actually breaks when it would (hardcore medical system)", { section = "Armour parts" })
Config.Register("gear", "pauldronDrainMult", 0.8, "Pauldron: armour lost per hit is multiplied by this", { section = "Armour parts" })
Config.Register("gear", "lightNeeded", true, "The flashlight key only works with helmet lights worn", { section = "Helmet lights" })
Config.Register("gear", "lightFov", 26, "Helmet lights: width of each beam (degrees); the two point apart with a small gap between", { section = "Helmet lights" })
Config.Register("gear", "lightGap", -4.7, "Helmet lights: extra degrees each beam turns outwards past touching (positive = a dark gap in the middle, negative = overlap; a dark slit is hard on the eyes)", { section = "Helmet lights" })
Config.Register("gear", "lightOverlapDim", 0.6, "Helmet lights: each beam's brightness where the two overlap (1 = no dimming; the middle is then about twice as bright)", { section = "Helmet lights" })
Config.Register("gear", "lightOverlapFlip", false, "Helmet lights: mirror the dimmed band if it shows on the outer edges instead of the middle", { section = "Helmet lights" })
Config.Register("gear", "lightRange", 2000, "Helmet lights: how far the beams reach", { section = "Helmet lights" })
Config.Register("gear", "lightBrightness", 3.5, "Helmet lights: brightness of each beam", { section = "Helmet lights" })
Config.Register("gear", "lightMaxPlayers", 2, "Helmet lights: other players whose beams light the world for you (nearest first, no shadows; your own always do). Further ones show only the lamp glow", { section = "Helmet lights" })
Config.Register("gear", "bareHeadshotDowns", true, "With the helmet off, any head hit downs you", { section = "Armour parts" })
Config.Register("gear", "visorZoom", 3, "Sun visor: the zoom it gives while aiming a gun (no scope of its own)", { section = "Sun visor" })
Config.Register("gear", "nvMode", 1, "Night vision: 1 = amplified (a wide shadowless light from your eyes that turns itself down where it's already bright; default), 2 = the world drawn fully lit (can glare at light sources), 0 = only the green filter", { section = "Night vision" })
Config.Meta("gear", "nvMode", { options = { { 1, "Amplified light (default)" }, { 2, "World drawn fully lit" }, { 0, "Green filter only" } } })
Config.Register("gear", "nvGain", 2.5, "Night vision (amplified): strength of the light in the dark", { section = "Night vision" })
Config.Register("gear", "nvLift", 0.04, "Night vision: how much the darkest parts are lifted (the green floor)", { section = "Night vision" })
Config.Register("gear", "nvColour", 0.6, "Night vision: how much of the real colours stays (0 = plain green picture, 1 = full colour under the green tint); colours keep their own hue, so unit markings stay readable", { section = "Night vision" })
Config.Register("gear", "nvTint", 0.3, "Night vision: how strong the green tint is (0 = none, 1 = only green)", { section = "Night vision" })
Config.Register("gear", "visorColour", 0.6, "Sun visor: how much of the real colours stays in its red view (0 = plain red picture, 1 = full colour under the red tint); colours keep their own hue", { section = "Night vision" })
Config.Register("gear", "visorTint", 0.5, "Sun visor: how strong the red tint is (0 = none, 1 = only red)", { section = "Night vision" })
Config.Meta("gear", "nvColour", { min = 0, max = 1 })
Config.Meta("gear", "nvTint", { min = 0, max = 1 })
Config.Meta("gear", "visorColour", { min = 0, max = 1 })
Config.Meta("gear", "visorTint", { min = 0, max = 1 })
Config.Register("gear", "nvBoost", 1.5, "Night vision: how much brighter the picture is made in the dark (1 = no boost; eased off in lit places)", { section = "Night vision" })
Config.Register("gear", "nvRange", 0, "Night vision: fade the picture into dark green beyond this distance (units; 0 = off)", { section = "Night vision" })
Config.Register("gear", "nvFadeFrom", 600, "Night vision: where that fade starts (units)", { section = "Night vision" })
Config.Register("gear", "nvLightRange", 4000, "Night vision (amplified): how far its light reaches (units)", { section = "Night vision" })

-- G.Cfg(key): a "gear" setting.
G.Cfg = Config.For("gear")

-- G.KeyDown(convar) (client): is the key named in that convar held? The
-- one helper the gear key handlers share.
if CLIENT then
    function G.KeyDown(var)
        local k = var:GetString()
        if k == "" then return false end   -- (unbound)
        local code = input.GetKeyCode(k)
        return code and code > 0 and input.IsButtonDown(code)
    end
end

local function norm(s)
    s = string.lower(tostring(s or ""))
    return (string.gsub(s, "%.smd$", ""))
end
G.Norm = norm

-- G.IsOffName(option) -> true for an option that means "nothing shown":
-- "empty", "" or a name with a word none / empty / off / blank / nothing /
-- no (split at _ - . space), e.g. "kama_none". Shared.
local OFF_WORDS = { none = true, empty = true, off = true, blank = true, nothing = true, no = true }
function G.IsOffName(name)
    name = norm(name)
    if name == "" then return true end
    for w in string.gmatch(name, "[^_%-%.%s]+") do
        if OFF_WORDS[w] then return true end
    end
    return false
end

-- G.ModelInfo(ent) -> { groups = { [group] = { id, opts = { [option] = index }, off } } }:
-- a model's bodygroups by lower-case name (option names without .smd),
-- off = the "nothing" option's index ("empty", else the first G.IsOffName
-- option, else nil), cached per model (cache cleared past 64 models). Shared.
G.modelCache = G.modelCache or {}
function G.ModelInfo(ent)
    local mdl = ent:GetModel() or ""
    local info = G.modelCache[mdl]
    if info then return info end
    info = { groups = {} }
    for _, g in ipairs(ent:GetBodyGroups() or {}) do
        local opts, off = {}, nil
        for i = 0, (g.num or 1) - 1 do
            local sub = g.submodels and g.submodels[i]
            if sub then
                local n = norm(sub)
                if opts[n] == nil then opts[n] = i end
                if off == nil and G.IsOffName(n) then off = i end
            end
        end
        info.groups[norm(g.name)] = { id = g.id, opts = opts, off = opts.empty or off }
    end
    if table.Count(G.modelCache) > 64 then G.modelCache = {} end
    G.modelCache[mdl] = info
    return info
end

-- G.Option(g, names): option index in group g (from ModelInfo) for the
-- first of names that exists, or nil.
function G.Option(g, names)
    if not (g and names) then return nil end
    for _, n in ipairs(names) do
        if g.opts[n] then return g.opts[n] end
    end
end

-- G.ItemShown(ply, id): does this player's model have a bodygroup option
-- for this item? (true for items rhylib_gear doesn't know). Shared.
-- Example: if Rhylib.Gear.ItemShown(ply, "rhylib_kama") then ... end
function G.ItemShown(ply, id)
    if not G.SHOWS[id] then return true end
    return G.InfoShows(G.ModelInfo(ply), id)
end

-- G.InfoShows(info, id): the same for a G.ModelInfo table (false for
-- unknown ids). Shared.
function G.InfoShows(info, id)
    local s = G.SHOWS[id]
    if not s then return false end
    for _, gn in ipairs(s.groups) do
        if G.Option(info.groups[gn], s.on) then return true end
    end
    return false
end

-- Does it show any item for this slot (or helmet part)? (The inventory
-- hides empty gear slots it can't show.)
function G.ModelHas(ply, slot)
    for id, it in pairs(G.ITEMS) do
        if (it.slot == slot or it.part == slot) and G.ItemShown(ply, id) then return true end
    end
    return false
end

-- G.Worn(ply, slot) -> the item instance worn in a gear slot ({ id, uid,
-- data, ... }), or nil. Server: any player's inventory; client: only your
-- own (others always nil). A helmet part name (binos, rangefinder, light,
-- visor) answers for the helmet slot, but only while that part is the one
-- worn there: G.Worn(ply, "visor") is the sun visor or nil.
function G.Worn(ply, slot)
    local part = G.HELMET_PARTS[slot] and slot
    if part then slot = "helmet" end
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
    if part and inst then
        local it = G.ITEMS[inst.id]
        if not (it and it.part == part) then return nil end
    end
    return inst
end

-- Worn AND shown by the model (and its helmet on, for helmet parts): only
-- then does a part do anything. Parts the current model can't show stay
-- worn but inert (joining as a cadet after a map change used to
-- take everything off).
-- G.Active(ply, slot) -> true / false. Use this before any gear effect.
-- Example: if Rhylib.Gear.Active(ply, "pauldron") then ... end
function G.Active(ply, slot)
    local inst = G.Worn(ply, slot)
    if inst == nil then return false end
    if G.ON_HELMET[slot] and not G.HelmetOn(ply) then return false end
    return G.ItemShown(ply, inst.id)
end

-- G.VisorBlocked(ply): always false now. (The sun visor and the
-- macrobinoculars share the one helmet slot, so the binoculars can no
-- longer take the visor's bodygroup.) Kept for callers.
function G.VisorBlocked(ply)
    return false
end

-- Answers rhylib_inventory's Rhylib.CanWear(ply, def): return false,
-- reason to refuse.
-- You have to see it to wear it (the back slot is free: a backpack works
-- whatever the model shows). The helmet parts share one slot, so only one
-- of them can be worn anyway.
Rhylib.Hook.Add("Rhylib.CanWear", "gear.model", function(ply, def)
    if not (def and def.slot and def.slot ~= "back") then return end
    local gid = def.id
    if gid and G.ITEMS[gid] and not G.ItemShown(ply, gid) then
        return false, "Your model can't show the " .. string.lower(G.ITEMS[gid].name)
    end
end)

-- G.InBattalion(ply, key): does a battalion name match a kit key ("*" =
-- everyone, else part of the name; checks roster battalion NW2 rhylib_bn
-- and the DarkRP job's battalion, category and name, case-insensitive)?
function G.InBattalion(ply, key)
    if key == "*" then return true end
    key = string.lower(key)
    local names = { ply:GetNW2String(Rhylib.NW.BATTALION, "") }
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

-- G.KitFor(ply) -> { [item id] = true }: the config kit for this player.
function G.KitFor(ply)
    local out = {}
    for key, list in pairs(G.Cfg("kit") or {}) do
        if istable(list) and G.InBattalion(ply, key) then
            for _, id in ipairs(list) do out[id] = true end
        end
    end
    return out
end

-- G.Unlocked(ply, id) -> true, or false, reason: may this player take this
-- part from the cabinet (config unlocks: rank via rhylib_roster
-- R.RankIndex, qual via R.HasQual)? Their own kit is always allowed.
-- Without rhylib_roster every part is allowed.
function G.Unlocked(ply, id)
    local rule = (G.Cfg("unlocks") or {})[id]
    if not istable(rule) or G.KitFor(ply)[id] then return true end
    local R = Rhylib.Roster
    if rule.rank and R and R.RankIndex then
        local need = R.RankIndex(rule.rank)
        if need and ply:GetNW2Int(Rhylib.NW.RANK, 0) < need then
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

-- Items go in once the inventory module exists (Rhylib.After: now or
-- right after it loads): Items.Register(id, def) for each G.ITEMS entry,
-- category "gear", shelf group "helmet" / "body" (back items keep their
-- default). wornRank = place in G.ORDER (which of several saved parts
-- keeps a shared worn slot on join). A grid whose container this
-- inventory doesn't have (gridCid unknown) is left out rather than
-- becoming a backpack.
local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) then return false end
    local rank = {}
    for i, id in ipairs(G.ORDER) do rank[id] = i end
    for id, it in pairs(G.ITEMS) do
        local gcid = it.gridCid and Items[it.gridCid] or nil
        local grid = (not it.gridCid or gcid) and it.grid or nil
        Items.Register(id, {
            name = it.name, desc = it.desc, w = it.w, h = it.h, weight = it.weight, model = it.model,
            category = "gear", slot = it.slot, part = it.part, grid = grid, gridCid = grid and gcid or nil, gridName = it.gridName,
            carry = it.carry, weightMults = it.weightMults, extraGrids = extraGrids(it), wornRank = rank[id],
            group = it.slot ~= "back" and (G.ON_HELMET[it.slot] and "helmet" or "body") or nil,
        })
    end
    return true
end
Rhylib.After("inventory", registerItems)

--------------------------------------------------------------------------
-- Learned bodygroup names (rhylib_gear_scan, sv_10_scan.lua)
--------------------------------------------------------------------------

-- G.learned = { [item id] = { groups = { names }, on = { names }, down = { names } } }:
-- names the scan found on models whose names differ from the built-in ones.
G.learned = G.learned or {}

local function addUnique(list, names, seen)
    for _, n in ipairs(names or {}) do
        if isstring(n) and n ~= "" and not seen[n] then
            seen[n] = true
            list[#list + 1] = n
        end
    end
end

-- G.SetLearned(t): puts every entry's groups / on / down back to the
-- built-in names and appends the learned ones from t (bad entries are
-- skipped), then rebuilds G.ALL_GROUPS in place. The tables are changed
-- in place, so G.ITEMS and G.SHOWS keep sharing them. Shared.
function G.SetLearned(t)
    G.learned = istable(t) and t or {}
    for id, s in pairs(G.SHOWS) do
        local b = G.BUILTIN[id]
        if b then
            local l = istable(G.learned[id]) and G.learned[id] or {}
            for _, key in ipairs({ "groups", "on", "down" }) do
                if b[key] or (key == "down" and s.optics and istable(l.down) and #l.down > 0) then
                    local list, seen = {}, {}
                    addUnique(list, b[key], seen)
                    if istable(l[key]) then addUnique(list, l[key], seen) end
                    s[key] = list
                end
            end
        end
    end
    for k in pairs(G.ALL_GROUPS) do G.ALL_GROUPS[k] = nil end
    for _, s in pairs(G.SHOWS) do
        for _, gn in ipairs(s.groups) do G.ALL_GROUPS[gn] = true end
    end
end
-- (a refresh of this file rebuilds G.ITEMS: merge again)
if next(G.learned) then G.SetLearned(G.learned) end

if CLIENT then
    -- Learned names from the server (on join and after each scan / reset):
    -- merged, then the inventory's gear pictures are made again.
    Rhylib.Net.Receive("gear.learned", function()
        local n = net.ReadUInt(32)
        if n <= 0 or n > 65000 then G.SetLearned({}) return end
        local raw = net.ReadData(n)
        local t = raw and util.JSONToTable(util.Decompress(raw) or "") or {}
        G.SetLearned(t)
        local Icons = Rhylib.Inventory and Rhylib.Inventory.Icons
        if Icons and Icons.RedrawGear then Icons.RedrawGear() end
    end)
    Rhylib.Hook.Add("InitPostEntity", "gear.learned", function()
        Rhylib.Net.Start("gear.learnreq")
        net.SendToServer()
    end)
end
