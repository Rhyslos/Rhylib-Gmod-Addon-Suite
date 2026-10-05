--[[
    Class mode (shared). Staff switch it on (rhylib_classmode, or the
    button on the Skills page); players may then play a ready-made class
    instead of their own skill tree, with every skill of that class at
    once. Their own tree is never touched (kept in Data) and comes back
    when they leave the class or class mode goes off. Optional: anyone may
    keep their own tree. One pick plus one re-pick each time class mode is
    switched on.

    State: Global2Bool rhylib_classMode, Global2Int rhylib_classEpoch
    (bumped every time it's switched on); player NW2String rhylib_class
    (class id or ""), NW2Int rhylib_classPicks (picks used this epoch).
    Server: sv_40_class.lua. Page: cl_40_class.lua.
]]

local K = Rhylib.Skills

K.CLASS_PICKS = 2   -- (one pick and one re-pick)

-- Presets are worked out from the tree: every skill of the category, of
-- that specialisation and end branch; never Adaptable; the Officer adds
-- the command order the player picks.
K.CLASSES = {
    { id = "vanguard", name = "Vanguard", cat = "trooper", spec = "assault", branch = "vanguard", who = "Anyone",
      desc = "Close-range DC-15S rifleman: faster fire, a free sprint after kills, droid poppers." },
    { id = "spearhead", name = "Spearhead", cat = "trooper", spec = "assault", branch = "shock", who = "Anyone",
      desc = "Runs and guns with the Z-6, even while sprinting." },
    { id = "autorifleman", name = "Autorifleman", cat = "trooper", spec = "autorifleman", who = "Anyone",
      desc = "The DC-15A at its strongest: full auto, Overcharge and the squad's ammo packs." },
    { id = "marksman", name = "Marksman", cat = "support", spec = "marksman", who = "Anyone",
      desc = "Picks off priority targets with the DC-15X or a steady DC-15S, and marks them for the squad." },
    { id = "heavy", name = "Heavy", cat = "support", spec = "heavy", who = "Anyone",
      desc = "Z-6 and DP-24 anchor who soaks hits and suppresses droids." },
    { id = "officer", name = "Officer", cat = "officer", who = "Anyone", orders = true,
      desc = "Dual pistols, quick footwork and marking targets. Leads with one command order of your choice." },
    { id = "airborne", name = "Airborne", cat = "airborne", who = "Anyone",
      desc = "Jetpack trooper: long flights, hard landings, grenades from above and slamming into droids." },
    { id = "combat_medic", name = "Combat medic", cat = "medic", spec = "combat_medic", who = "Medics",
      desc = "Fast frontline revives and dragging the wounded to cover." },
    { id = "chemist", name = "Chemist", cat = "medic", spec = "chemist", who = "Medics",
      desc = "Crafts medical supplies and runs the med bay." },
    { id = "shocktrooper", name = "Shock Trooper", cat = "shocktrooper", who = "Military police",
      desc = "Riot shield, breaching charges and arrests." },
}
K.classById = {}
for i, c in ipairs(K.CLASSES) do
    c.index = i
    K.classById[c.id] = c
end

function K.ClassMode() return GetGlobal2Bool("rhylib_classMode", false) end
function K.ClassEpoch() return GetGlobal2Int("rhylib_classEpoch", 0) end

-- The class a player is playing, or nil.
function K.ClassOf(ply)
    local id = IsValid(ply) and ply:GetNW2String("rhylib_class", "") or ""
    return id ~= "" and K.classById[id] or nil
end

function K.ClassPicksLeft(ply)
    return math.max(0, K.CLASS_PICKS - ply:GetNW2Int("rhylib_classPicks", 0))
end

-- The skill set of a class (orderId: the Officer's command order skill id).
function K.ClassSet(cls, orderId)
    local set = {}
    for _, n in ipairs(K.NODES) do
        if n.cat == cls.cat and (not n.spec or n.spec == cls.spec) and (not n.branch or n.branch == cls.branch)
            and n.id ~= "adapt_1" and n.exclusive ~= "command" then
            set[n.id] = true
        end
    end
    if cls.orders and orderId and K.byId[orderId] and K.byId[orderId].exclusive == "command" then
        set[orderId] = true
    end
    return set
end

-- May this player play this class (job rules)? Returns ok, reason.
function K.ClassAllowed(ply, cls)
    local cat = K.catById[cls.cat]
    if cat and cat.medicOnly then
        local Med = Rhylib.Medical
        if not (Med and Med.IsMedic and Med.IsMedic(ply)) then return false, "Medics only" end
    end
    if cat and cat.mpOnly then
        local MP = Rhylib.MP
        if not (MP and MP.IsMP and MP.IsMP(ply)) then return false, "Military police only" end
    end
    return true
end
