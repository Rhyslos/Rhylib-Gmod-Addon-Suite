--[[
    Skill trees (shared).

    A category (Trooper, Support, Officer, Airborne, Medic, Shock Trooper)
    holds nodes; medicOnly categories need Rhylib.Medical.IsMedic, mpOnly
    ones Rhylib.MP.IsMP. A node can belong
    to a specialisation (spec) and, inside it, to an end branch (branch);
    nodes without a spec are shared by the whole category.
        { id, cat, spec, branch, tier, cost, name, desc,
          needs = { ids } (all of them),
          needsGroups = { { ids }, { ids } } (all of one group) }
    Rules (K.CanLearn, used by the server and to grey out the menu):
      - one category at a time (config onePath),
      - one specialisation per category, one end branch per specialisation,
      - everything in needs / one of needsGroups learned first,
      - points: free while config freePoints is on (testing), else
        K.Points(ply) minus what's spent.
    What a player has is one NW2String "rhylib_skills" (",id,id,"), set on
    change only; K.Has parses it once per change, so it's cheap anywhere
    (SetupMove, firing, the crosshair). Effects: sh_10_effects.lua.
]]

Rhylib.Skills = Rhylib.Skills or {}
local K = Rhylib.Skills
local Config = Rhylib.Config

Config.Register("skills", "freePoints", true, "Every skill is free and can be reset any time (testing)")
Config.Register("skills", "startPoints", 20, "Skill points everyone has while freePoints is off")
Config.Register("skills", "onePath", true, "Only one category (Trooper, Support, Officer, Airborne, Medic, Shock Trooper) at a time")

function K.Cfg(key) return Config.Get("skills", key) end

K.CATEGORIES = {
    { id = "trooper", name = "Trooper", desc = "Frontline riflemen",
      specs = {
          { id = "assault", name = "Assault", desc = "Close-range assault",
            branches = {
                { id = "vanguard", name = "Vanguard", desc = "DC-15S fire rate and momentum" },
                { id = "shock", name = "Spearhead", desc = "The Z-6 on the move" },
            } },
          { id = "autorifleman", name = "Autorifleman", desc = "Sustained fire and the squad's ammo" },
      } },
    { id = "support", name = "Support", desc = "Long-range picks or holding the line",
      specs = {
          { id = "marksman", name = "Marksman", desc = "Long-range engagements" },
          { id = "heavy", name = "Heavy", desc = "The Z-6, the shotgun and soaking hits" },
      } },
    { id = "officer", name = "Officer", desc = "Sidearms, footwork and leading (more coming later)", specs = {} },
    { id = "airborne", name = "Airborne", desc = "Jetpacks, hard landings and getting in close (indoors too)", specs = {} },
    { id = "medic", name = "Medic", desc = "Medic jobs only: revives, treatment and the med bay", medicOnly = true,
      specs = {
          { id = "combat_medic", name = "Combat medic", desc = "Frontline revives" },
          { id = "chemist", name = "Chemist", desc = "Crafting, the med bay and full recoveries" },
      } },
    { id = "shocktrooper", name = "Shock Trooper", desc = "Military police only: the riot shield, breaching and searches", mpOnly = true,
      specs = {} },
}

K.NODES = {
    -- Trooper
    { id = "quick_hands", cat = "trooper", tier = 1, cost = 1, name = "Quick hands",
      desc = "Magazine reloads are 10% faster on every gun." },

    { id = "run_gun", cat = "trooper", spec = "assault", tier = 2, cost = 2, name = "Run and gun",
      desc = "Fire while sprinting. Spread is wider while you do.", needs = { "quick_hands" } },
    { id = "point_blank", cat = "trooper", spec = "assault", tier = 2, cost = 2, name = "Point blank",
      desc = "+25% damage within 8 m, fading to normal by 15 m.", needs = { "quick_hands" } },

    { id = "full_auto", cat = "trooper", spec = "autorifleman", tier = 2, cost = 2, name = "Full auto",
      desc = "DC-15A full-auto fire mode (E + R).", needs = { "quick_hands" } },
    { id = "ext_mags", cat = "trooper", spec = "autorifleman", tier = 2, cost = 2, name = "Extended mags",
      desc = "Medium magazines hold 70 rounds instead of 60 when you load them.", needs = { "quick_hands" } },

    { id = "droid_popper", cat = "trooper", tier = 3, cost = 2, name = "Droid popper",
      desc = "You can carry and throw droid poppers (EMP grenades; E + R switches impact / timed). Nobody else can even pick them up.",
      needsGroups = { { "run_gun", "point_blank" }, { "full_auto", "ext_mags" } } },

    { id = "light_kit", cat = "trooper", spec = "assault", tier = 4, cost = 3, name = "Light kit",
      desc = "+5% movement speed while you carry under 60% of your limit.", needs = { "droid_popper" } },

    { id = "rapid_fire", cat = "trooper", spec = "assault", branch = "vanguard", tier = 5, cost = 3, name = "Rapid fire",
      desc = "The DC-15S fires 600 rounds a minute instead of 540.", needs = { "light_kit" } },
    { id = "momentum", cat = "trooper", spec = "assault", branch = "vanguard", tier = 6, cost = 5, name = "Momentum",
      desc = "A kill gives 4 s of sprinting with no stamina cost, and your next reload is 25% faster.", needs = { "rapid_fire" } },

    { id = "gun_runner", cat = "trooper", spec = "assault", branch = "shock", tier = 5, cost = 3, name = "Gun runner",
      desc = "The Z-6 weighs half and barely slows you while its barrels spin.", needs = { "light_kit" } },
    { id = "steady_barrels", cat = "trooper", spec = "assault", branch = "shock", tier = 6, cost = 5, name = "Steady barrels",
      desc = "While sprinting with the Z-6: spread and kick cut by more than half.", needs = { "gun_runner" } },

    { id = "eff_cells", cat = "trooper", spec = "autorifleman", tier = 4, cost = 3, name = "Efficient cells",
      desc = "Power cells last 25% longer in your guns.", needs = { "droid_popper" } },
    { id = "load_bearer", cat = "trooper", spec = "autorifleman", tier = 4, cost = 3, name = "Load bearer",
      desc = "+6 kg carry limit, 25% less stamina penalty from weight, and a cell rack (5 power cells).",
      needs = { "droid_popper" } },
    { id = "ammo_pack", cat = "trooper", spec = "autorifleman", tier = 5, cost = 5, name = "Ammo pack",
      desc = "Carry and use ammo packs: they top up a teammate's magazines and hand out full ones for any blaster.",
      needs = { "eff_cells", "load_bearer" } },

    -- Support
    { id = "steady_stance", cat = "support", tier = 1, cost = 1, name = "Steady stance", icon = "crouch",
      desc = "20% less spread while crouched." },

    { id = "long_gun", cat = "support", spec = "marksman", tier = 2, cost = 2, name = "Long gun", icon = "scope",
      desc = "You can look through the DC-15X scope.", needs = { "steady_stance" } },
    { id = "steady_aim", cat = "support", spec = "marksman", tier = 2, cost = 2, name = "Steady aim", icon = "aim",
      desc = "25% less spread while aiming, with any gun.", needs = { "steady_stance" } },
    { id = "headhunter", cat = "support", spec = "marksman", tier = 3, cost = 3, name = "Headhunter", icon = "target",
      desc = "+25% damage on headshots, droids included.", needs = { "long_gun", "steady_aim" } },
    { id = "bolt_drills", cat = "support", spec = "marksman", tier = 4, cost = 3, name = "Bolt drills", icon = "bolt",
      desc = "The DC-15X fires 20% faster.", needs = { "headhunter" } },
    { id = "light_frame", cat = "support", spec = "marksman", tier = 4, cost = 3, name = "Light frame", icon = "feather",
      desc = "The DC-15X weighs half.", needs = { "headhunter" } },
    { id = "first_shot", cat = "support", spec = "marksman", tier = 5, cost = 5, name = "First shot", icon = "crosshair",
      desc = "Aimed, after 3 s without firing: your next shot does +50% damage and goes exactly where you aim.",
      needs = { "bolt_drills", "light_frame" } },

    { id = "heavy_feed", cat = "support", spec = "heavy", tier = 2, cost = 2, name = "Heavy feed", icon = "stack",
      desc = "Load large 250-round magazines into the Z-6 (nobody else can).", needs = { "steady_stance" } },
    { id = "reinforced", cat = "support", spec = "heavy", tier = 2, cost = 2, name = "Reinforced", icon = "heart",
      desc = "+25 max health.", needs = { "steady_stance" } },
    { id = "planted", cat = "support", spec = "heavy", tier = 3, cost = 3, name = "Planted", icon = "anchor",
      desc = "Crouched with the Z-6: half the spread and half the kick.", needs = { "heavy_feed", "reinforced" } },
    { id = "ammo_belt", cat = "support", spec = "heavy", tier = 4, cost = 3, name = "Ammo belt", icon = "belt",
      desc = "A 5x1 belt in your inventory: an extra large magazine, or a shotgun and a small item.", needs = { "planted" } },
    { id = "shotgun_drills", cat = "support", spec = "heavy", tier = 4, cost = 3, name = "Shotgun drills", icon = "flame",
      desc = "DP-24: +30% pellet damage, 20% tighter cone. Guns 4 cells long or shorter weigh half.", needs = { "planted" } },
    { id = "juggernaut", cat = "support", spec = "heavy", tier = 5, cost = 5, name = "Juggernaut", icon = "shield",
      desc = "15% less damage from everything.", needs = { "ammo_belt", "shotgun_drills" } },
    { id = "suppression", cat = "support", spec = "heavy", tier = 6, cost = 3, name = "Suppression", icon = "barrels",
      desc = "Droids near one you hit with the Z-6 aim much worse for 3 s.", needs = { "juggernaut" } },

    -- Officer
    { id = "pistol_prof", cat = "officer", tier = 1, cost = 2, name = "Pistol proficiency",
      desc = "DC-17: 20% less spread." },
    { id = "light_mags", cat = "officer", tier = 2, cost = 2, name = "Light mags", icon = "mag",
      desc = "Small magazines hold 50 rounds instead of 30 when you load them.", needs = { "pistol_prof" } },
    { id = "sidestep", cat = "officer", tier = 2, cost = 2, name = "Sidestep", icon = "dodge",
      desc = "Sprint + left, right or back + Jump (or Alt + any direction): a quick step aside from the ground. Costs stamina, 2.5 s cooldown.", needs = { "pistol_prof" } },
    { id = "dual_dc17", cat = "officer", tier = 3, cost = 3, name = "Dual DC-17",
      desc = "Draw a second DC-17 (E + R): two magazines loaded, shots alternate between hands.", needs = { "light_mags" } },
    { id = "crits", cat = "officer", tier = 3, cost = 3, name = "Critical hits",
      desc = "10% of your hits do 50% more damage.", needs = { "sidestep" } },

    -- Airborne (jetpack: 15 s of flight with any Airborne skill, 10 s without)
    { id = "hard_landings", cat = "airborne", tier = 1, cost = 1, name = "Hard landings",
      desc = "Half fall damage, and your legs never break. Jetpacks fly 15 s instead of 10." },
    { id = "extended_tanks", cat = "airborne", tier = 2, cost = 2, name = "Extended tanks",
      desc = "Jetpack fuel lasts 40% longer and refills 40% faster.", needs = { "hard_landings" } },
    { id = "spring_legs", cat = "airborne", tier = 2, cost = 2, name = "Spring legs",
      desc = "Jump 20% higher.", needs = { "hard_landings" } },
    { id = "afterburner", cat = "airborne", tier = 3, cost = 2, name = "Afterburner",
      desc = "Jetpack climbs, steers and flies 25% faster.", needs = { "extended_tanks" } },
    { id = "combat_drop", cat = "airborne", tier = 3, cost = 3, name = "Combat drop",
      desc = "Land after 7 s or more of jetpack flight: 50% less damage for 5 s.",
      needs = { "spring_legs" } },
    { id = "blast_hardened", cat = "airborne", tier = 4, cost = 3, name = "Blast hardened",
      desc = "30% less damage from explosions.", needs = { "afterburner", "combat_drop" } },
    { id = "aerial_stability", cat = "airborne", tier = 4, cost = 3, name = "Aerial stability",
      desc = "20% less damage while you're off the ground.", needs = { "afterburner", "combat_drop" } },
    { id = "death_from_above", cat = "airborne", tier = 5, cost = 5, name = "Death from above",
      desc = "Landing hard (a long drop or a jetpack dive) slams droids around you.",
      needs = { "blast_hardened", "aerial_stability" } },

    -- Medic (medic jobs only)
    { id = "field_drag", cat = "medic", tier = 1, cost = 1, name = "Field drag",
      desc = "Drag bodies at a jog instead of a crawl." },
    { id = "hands_on", cat = "medic", tier = 2, cost = 2, name = "Hands-on revive",
      desc = "Revive with no kit at all (E menu). Very slow, and they get up with 15 health.", needs = { "field_drag" } },
    { id = "steady_hands", cat = "medic", tier = 2, cost = 2, name = "Steady hands",
      desc = "Treatments (not revives) are 15% faster.", needs = { "field_drag" } },

    { id = "quick_revive", cat = "medic", spec = "combat_medic", tier = 3, cost = 2, name = "Quick revive",
      desc = "Revives take 20% less time.", needs = { "hands_on", "steady_hands" } },
    { id = "under_fire", cat = "medic", spec = "combat_medic", tier = 4, cost = 3, name = "Under fire",
      desc = "20% less damage while you revive or treat someone.", needs = { "quick_revive" } },
    { id = "deep_pockets", cat = "medic", spec = "combat_medic", tier = 4, cost = 3, name = "Deep pockets",
      desc = "Medkit stacks hold 2 more.", needs = { "quick_revive" } },
    { id = "triage", cat = "medic", spec = "combat_medic", tier = 4, cost = 3, name = "Triage",
      desc = "Downed markers reach twice as far, show who is helping and flash when time runs short.",
      needs = { "quick_revive" } },
    { id = "medevac", cat = "medic", spec = "combat_medic", tier = 5, cost = 5, name = "Medevac", icon = "drag",
      desc = "A downed player's bleed-out pauses while you drag them to cover.",
      needs = { "under_fire" } },

    { id = "chem_bench", cat = "medic", spec = "chemist", tier = 3, cost = 2, name = "Chemistry",
      desc = "Use a chemistry bench to turn medical supplies into gels, painkillers, splints, blood packs and medkits.",
      needs = { "hands_on", "steady_hands" } },
    { id = "field_surgeon", cat = "medic", spec = "chemist", tier = 4, cost = 3, name = "Field surgeon",
      desc = "Your first aid kit fully sets bones and heals burns anywhere, not just in the med bay.",
      needs = { "chem_bench" } },
    { id = "batch_brewing", cat = "medic", spec = "chemist", tier = 4, cost = 3, name = "Batch brewing",
      desc = "The bench makes two of everything.", needs = { "chem_bench" } },
    { id = "bacta_specialist", cat = "medic", spec = "chemist", tier = 4, cost = 3, name = "Bacta specialist",
      desc = "Bacta tanks near you heal twice as fast.", needs = { "chem_bench" } },
    { id = "efficient_care", cat = "medic", spec = "chemist", tier = 5, cost = 5, name = "Efficient care", icon = "flask",
      desc = "Your first aid kits use a third less charge.",
      needs = { "field_surgeon" } },

    -- Shock Trooper (military police jobs only)
    { id = "riot_shield", cat = "shocktrooper", tier = 1, cost = 1, name = "Riot shield",
      desc = "Carry the riot shield: a DC-15S fired from the hip behind a shield that stops bolts from the front." },
    { id = "shield_bash", cat = "shocktrooper", tier = 2, cost = 2, name = "Shield bash",
      desc = "Right click with the riot shield: stun a player in front of you, or knock a droid back.", needs = { "riot_shield" } },
    { id = "escort_drills", cat = "shocktrooper", tier = 2, cost = 2, name = "Escort drills",
      desc = "No slowdown while you escort a prisoner.", needs = { "riot_shield" } },
    { id = "breaching", cat = "shocktrooper", tier = 3, cost = 3, name = "Breaching charge",
      desc = "Thermal detonators get a third mode (E + R): stick it on a door or wall. 6 s fuse, small blast, and doors nearby are forced open for 5 minutes.",
      needs = { "shield_bash" } },
    { id = "thorough_search", cat = "shocktrooper", tier = 3, cost = 2, name = "Thorough search",
      desc = "Your search rolls are 20% higher, so hidden contraband turns up more often.", needs = { "escort_drills" } },
    { id = "shock_assault", cat = "shocktrooper", tier = 4, cost = 3, name = "Shock Assault",
      desc = "Hits don't push you around or knock the wind out of you: you take the damage and keep moving.",
      needs = { "breaching", "thorough_search" } },
    { id = "hold_line", cat = "shocktrooper", tier = 5, cost = 3, name = "Hold the line",
      desc = "20% less damage while your riot shield is up and another MP is near you.", needs = { "shock_assault" } },
    { id = "flash_charge", cat = "shocktrooper", tier = 5, cost = 3, name = "Flash charge",
      desc = "Carry flash charges: players in sight of the flash are stunned, droids aim much worse for a few seconds.",
      needs = { "shock_assault" } },
    { id = "phalanx", cat = "shocktrooper", tier = 6, cost = 5, name = "Phalanx",
      desc = "Your raised shield also stops bolts aimed at teammates right behind you.",
      needs = { "hold_line", "flash_charge" } },
}

-- Lookups (rebuilt on refresh).
K.byId, K.catById, K.specById = {}, {}, {}
for i, n in ipairs(K.NODES) do
    K.byId[n.id] = n
    n.index = i
end
for _, c in ipairs(K.CATEGORIES) do
    K.catById[c.id] = c
    for _, s in ipairs(c.specs or {}) do K.specById[s.id] = s end
end

--------------------------------------------------------------------------
-- What a player has
--------------------------------------------------------------------------

local EMPTY = {}

-- Set of learned ids, parsed once per change of the NW2 string.
function K.Set(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return EMPTY end
    local str = ply:GetNW2String("rhylib_skills", "")
    local c = ply.rhylibSkillCache
    if c and c.str == str then return c.set end
    local set = {}
    for id in string.gmatch(str, "[^,]+") do set[id] = true end
    ply.rhylibSkillCache = { str = str, set = set }
    return set
end

function K.Has(ply, id)
    return K.Set(ply)[id] == true
end

-- The category, spec and branch a set of skills is committed to.
function K.Commitments(set)
    local cat, spec, branch = {}, {}, {}
    for id in pairs(set) do
        local n = K.byId[id]
        if n then
            cat[n.cat] = true
            if n.spec then spec[n.cat] = n.spec end
            if n.branch then branch[n.spec] = n.branch end
        end
    end
    return cat, spec, branch
end

function K.Spent(set)
    local total = 0
    for id in pairs(set) do
        local n = K.byId[id]
        if n then total = total + n.cost end
    end
    return total
end

-- Points to spend (freePoints: unlimited). Hook Rhylib.SkillPoints(ply) can answer.
function K.Points(ply)
    if K.Cfg("freePoints") then return math.huge end
    local r = hook.Run("Rhylib.SkillPoints", ply)
    if isnumber(r) then return r end
    return K.Cfg("startPoints")
end

-- Can a player with this set learn node id? Returns ok, reason.
function K.CanLearn(ply, set, id)
    local n = K.byId[id]
    if not n then return false, "No such skill" end
    if set[id] then return false, "Already learned" end
    local cat = K.catById[n.cat]
    if cat and cat.medicOnly then
        local Med = Rhylib.Medical
        if not (Med and Med.IsMedic and Med.IsMedic(ply)) then return false, "Medics only" end
    end
    if cat and cat.mpOnly then
        local MP = Rhylib.MP
        if not (MP and MP.IsMP and MP.IsMP(ply)) then return false, "Military police only" end
    end
    local cats, specs, branches = K.Commitments(set)
    if K.Cfg("onePath") then
        for c in pairs(cats) do
            if c ~= n.cat then return false, "You're on the " .. (K.catById[c] and K.catById[c].name or c) .. " path (reset to change)" end
        end
    end
    if n.spec and specs[n.cat] and specs[n.cat] ~= n.spec then
        return false, "You chose " .. (K.specById[specs[n.cat]] and K.specById[specs[n.cat]].name or specs[n.cat])
    end
    if n.branch and branches[n.spec] and branches[n.spec] ~= n.branch then
        return false, "You chose the other branch"
    end
    for _, req in ipairs(n.needs or EMPTY) do
        if not set[req] then return false, "Needs " .. (K.byId[req] and K.byId[req].name or req) end
    end
    if n.needsGroups then
        local okAny = false
        for _, g in ipairs(n.needsGroups) do
            local all = true
            for _, req in ipairs(g) do
                if not set[req] then all = false break end
            end
            if all then okAny = true break end
        end
        if not okAny then return false, "Needs both earlier skills of one specialisation" end
    end
    if K.Spent(set) + n.cost > K.Points(ply) then return false, "Not enough skill points" end
    return true
end
