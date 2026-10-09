--[[
    Skill trees (shared).

    A category (Trooper, Support, Officer, Airborne, Medic, Shock Trooper)
    holds nodes; medicOnly categories need Rhylib.Medical.IsMedic, mpOnly
    ones Rhylib.MP.IsMP. A node can belong
    to a specialisation (spec) and, inside it, to an end branch (branch);
    nodes without a spec are shared by the whole category.
        { id, cat, spec, branch, tier, cost, name, desc,
          needs = { ids } (all of them),
          needsGroups = { { ids }, { ids } } (all of one group),
          needsLabel = text for needsGroups, exclusive = group (one per set),
          rankCfg = config key of the lowest rank allowed }
    Rules (K.CanLearn, used by the server and to grey out the menu):
      - one category at a time (config onePath),
      - one specialisation per category, one end branch per specialisation,
      - everything in needs / one of needsGroups learned first,
      - points: free while config freePoints is on (testing), else
        K.Points(ply) minus what's spent,
      - Adaptable (officer adapt_1): with onePath on, an officer may
        learn one skill of tier 4 or lower from another tree or the other
        officer specialisation. Those "borrowed" skills skip needs, spec and branch rules and
        don't count as a path; job rules and points still apply.
    What a player has is one NW2String "rhylib_skills" (",id,id,"), set on
    change only; K.Has parses it once per change, so it's cheap anywhere
    (SetupMove, firing, the crosshair). Effects: sh_10_effects.lua.
]]

Rhylib.Skills = Rhylib.Skills or {}
local K = Rhylib.Skills
local Config = Rhylib.Config

Config.Register("skills", "freePoints", true, "Every skill is free and can be reset any time (testing)")
Config.Register("skills", "startPoints", 24, "Skill points everyone has while freePoints is off (every path costs 24, so any one can be finished)")
Config.Register("skills", "commandRank", "LT", "Lowest rank (roster prefix) that can learn and issue command orders")
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
    { id = "officer", name = "Officer", desc = "Leads from the front with pistols, or runs the squad with target locks and stronger orders",
      specs = {
          { id = "pistol", name = "Pistol", desc = "Two DC-17s, fast hands and footwork for close fights" },
          { id = "commander", name = "Commander", desc = "Locks targets for the squad, buffs them nearby and gives stronger orders" },
      } },
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

    { id = "run_gun", cat = "trooper", spec = "assault", tier = 2, cost = 3, name = "Run and gun",
      desc = "Fire while sprinting. Spread is wider while you do.", needs = { "quick_hands" } },
    { id = "point_blank", cat = "trooper", spec = "assault", tier = 2, cost = 3, name = "Point blank",
      desc = "+25% damage within 8 m, fading to normal by 15 m.", needs = { "quick_hands" } },

    { id = "full_auto", cat = "trooper", spec = "autorifleman", tier = 2, cost = 2, name = "Full auto",
      desc = "DC-15A full-auto fire mode (E + R).", needs = { "quick_hands" },
      redundantWith = "combat_veteran", redundantWhy = "Combat veteran already gives you DC-15A full auto" },
    { id = "ext_mags", cat = "trooper", spec = "autorifleman", tier = 2, cost = 2, name = "Extended mags",
      desc = "Medium magazines hold 70 rounds instead of 60 when you load them.", needs = { "quick_hands" } },

    { id = "droid_popper", cat = "trooper", tier = 3, cost = 2, name = "Droid popper",
      desc = "You can carry and throw droid poppers (EMP grenades; E + R switches impact / timed). Nobody else can even pick them up.",
      needsGroups = { { "run_gun", "point_blank" }, { "full_auto", "ext_mags" } } },

    { id = "light_kit", cat = "trooper", spec = "assault", tier = 4, cost = 4, name = "Light kit",
      desc = "+5% movement speed while you carry under 60% of your limit.", needs = { "droid_popper" } },

    { id = "rapid_fire", cat = "trooper", spec = "assault", branch = "vanguard", tier = 5, cost = 4, name = "Rapid fire",
      desc = "The DC-15S fires 600 rounds a minute instead of 540.", needs = { "light_kit" } },
    { id = "momentum", cat = "trooper", spec = "assault", branch = "vanguard", tier = 6, cost = 7, name = "Momentum",
      desc = "A kill gives 4 s of sprinting with no stamina cost, and your next reload is 25% faster.", needs = { "rapid_fire" } },

    { id = "gun_runner", cat = "trooper", spec = "assault", branch = "shock", tier = 5, cost = 4, name = "Gun runner",
      desc = "The Z-6 weighs half and barely slows you while its barrels spin.", needs = { "light_kit" } },
    { id = "steady_barrels", cat = "trooper", spec = "assault", branch = "shock", tier = 6, cost = 7, name = "Steady barrels",
      desc = "While sprinting with the Z-6: spread and kick cut by more than half.", needs = { "gun_runner" } },

    { id = "eff_cells", cat = "trooper", spec = "autorifleman", tier = 4, cost = 3, name = "Efficient cells",
      desc = "Power cells last 25% longer in your guns.", needs = { "droid_popper" } },
    { id = "load_bearer", cat = "trooper", spec = "autorifleman", tier = 4, cost = 3, name = "Load bearer",
      desc = "+6 kg carry limit, 25% less stamina penalty from weight, and a cell rack (5 power cells).",
      needs = { "droid_popper" } },
    { id = "ammo_pack", cat = "trooper", spec = "autorifleman", tier = 5, cost = 5, name = "Ammo pack",
      desc = "Carry and use ammo packs: they top up a teammate's magazines and hand out full ones for any blaster.",
      needs = { "eff_cells", "load_bearer" } },
    { id = "overcharge", cat = "trooper", spec = "autorifleman", tier = 5, cost = 3, name = "Overcharge", icon = "bolt",
      desc = "DC-15A Overcharge fire mode (E + R): full auto, 30% more damage and bigger bolts, a bit more kick, and the power cell drains 4x faster.",
      needs = { "eff_cells" } },
    { id = "sustained_fire", cat = "trooper", spec = "autorifleman", tier = 6, cost = 3, name = "Sustained fire", icon = "burst",
      desc = "DC-15A full auto: the kick eases off the longer you hold the trigger (40% less after 1.5 s), and hits on the same target add 2% damage each, up to +10%.",
      needsGroups = { { "overcharge" }, { "ammo_pack" } }, needsLabel = "Needs Overcharge or Ammo pack" },

    -- Support
    { id = "steady_stance", cat = "support", tier = 1, cost = 1, name = "Steady stance", icon = "crouch",
      desc = "20% less spread while crouched." },

    -- Marksman: 1-3-2-3-1. A sniper side (Long gun, Bolt drills) and a
    -- carbine side (Carbine discipline, Precision rhythm) that cross in the
    -- middle; Priority target and First shot work with either.
    { id = "long_gun", cat = "support", spec = "marksman", tier = 2, cost = 2, name = "Long gun", icon = "scope",
      desc = "You can look through the DC-15X scope, and it weighs 25% less.", needs = { "steady_stance" } },
    { id = "steady_aim", cat = "support", spec = "marksman", tier = 2, cost = 2, name = "Steady aim", icon = "aim",
      desc = "25% less spread while aiming, with any gun.", needs = { "steady_stance" } },
    { id = "carbine_disc", cat = "support", spec = "marksman", tier = 2, cost = 2, name = "Carbine discipline",
      desc = "DC-15S: 30% less spread while aiming, 15% less kick, and it comes out 30% faster.",
      needs = { "steady_stance" } },
    { id = "headhunter", cat = "support", spec = "marksman", tier = 3, cost = 3, name = "Headhunter", icon = "target",
      desc = "+25% damage on headshots, droids included.",
      needsGroups = { { "long_gun" }, { "steady_aim" } }, needsLabel = "Needs Long gun or Steady aim" },
    { id = "called_shot", cat = "support", spec = "marksman", tier = 3, cost = 3, name = "Called shot",
      desc = "Your headshots mark the target for you and your squad for 6 s.",
      needsGroups = { { "steady_aim" }, { "carbine_disc" } }, needsLabel = "Needs Steady aim or Carbine discipline" },
    { id = "bolt_drills", cat = "support", spec = "marksman", tier = 4, cost = 2, name = "Bolt drills", icon = "bolt",
      desc = "The DC-15X fires 20% faster.", needs = { "headhunter", "long_gun" } },
    { id = "priority_target", cat = "support", spec = "marksman", tier = 4, cost = 3, name = "Priority target",
      desc = "+20% damage against heavy droids (B2s, heavy and commander B1s) and anything marked.",
      needsGroups = { { "headhunter" }, { "called_shot" } }, needsLabel = "Needs Headhunter or Called shot" },
    { id = "precision_rhythm", cat = "support", spec = "marksman", tier = 4, cost = 2, name = "Precision rhythm",
      desc = "Aimed DC-15S hits on the same target within 1.5 s add 5% damage each, up to +10%.",
      needs = { "called_shot", "carbine_disc" } },
    { id = "first_shot", cat = "support", spec = "marksman", tier = 5, cost = 4, name = "First shot", icon = "crosshair",
      desc = "Aimed, after 3 s without firing: your next shot goes exactly where you aim, with +50% damage from the DC-15X or +30% from other guns.",
      needsGroups = { { "bolt_drills", "priority_target" }, { "bolt_drills", "precision_rhythm" }, { "priority_target", "precision_rhythm" } },
      needsLabel = "Needs two of Bolt drills, Priority target and Precision rhythm" },

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
    { id = "juggernaut", cat = "support", spec = "heavy", tier = 5, cost = 6, name = "Juggernaut", icon = "shield",
      desc = "15% less damage from everything.", needs = { "ammo_belt", "shotgun_drills" } },
    { id = "suppression", cat = "support", spec = "heavy", tier = 6, cost = 4, name = "Suppression", icon = "barrels",
      desc = "Droids near one you hit with the Z-6 aim much worse for 3 s.", needs = { "juggernaut" } },

    -- Officer: Mark target, then one of two specialisations (owner
    -- 2026-10-05): Pistol (Rex, the old tree) or Commander (Cody, Gree,
    -- Fox). Both full paths cost 24. The command orders sit in both specs
    -- (same orders: `order` names the base skill, K.ORDERS): Pistol at
    -- tier 6, Commander at tier 3 so its order upgrades come after them.
    { id = "mark_target", cat = "officer", tier = 1, cost = 1, name = "Mark target",
      desc = "Q: mark what you aim at for 15 s, seen by you and your squad. Through macrobinoculars or a rangefinder, Q marks up to 5 enemies nearest the middle of the view." },

    -- Pistol: 1-3-4-2 then the orders.
    { id = "dual_dc17", cat = "officer", spec = "pistol", tier = 2, cost = 2, name = "Dual DC-17",
      desc = "Draw a second DC-17 (E + R): two magazines loaded, shots alternate between hands.", needs = { "mark_target" } },
    { id = "pistol_prof", cat = "officer", spec = "pistol", tier = 3, cost = 3, name = "Pistol proficiency",
      desc = "DC-17: 20% less spread.", needs = { "dual_dc17" } },
    { id = "quick_draw", cat = "officer", spec = "pistol", tier = 3, cost = 1, name = "Quick draw",
      desc = "Guns come out 40% faster when you switch to them.", needs = { "dual_dc17" } },
    { id = "sidestep", cat = "officer", spec = "pistol", tier = 3, cost = 2, name = "Sidestep", icon = "dodge",
      desc = "Sprint + left, right or back + Jump (or Alt + any direction): a quick step aside from the ground. Costs stamina, 2.5 s cooldown.", needs = { "dual_dc17" } },
    { id = "light_mags", cat = "officer", spec = "pistol", tier = 4, cost = 2, name = "Light mags", icon = "mag",
      desc = "Small magazines hold 50 rounds instead of 30 when you load them.", needs = { "pistol_prof" } },
    { id = "steady_grip", cat = "officer", spec = "pistol", tier = 4, cost = 2, name = "Steady grip",
      desc = "Pistols kick half as much when you fire (the DC-17, and the DC-15S as a sidearm).",
      needsGroups = { { "pistol_prof" }, { "quick_draw" } }, needsLabel = "Needs Pistol proficiency or Quick draw" },
    { id = "speed_loader", cat = "officer", spec = "pistol", tier = 4, cost = 2, name = "Speed loader",
      desc = "Pistol (DC-17) reloads are 30% faster.", needs = { "quick_draw" } },
    { id = "carbine_sidearm", cat = "officer", spec = "pistol", tier = 4, cost = 1, name = "Carbine sidearm",
      desc = "DC-15S: semi-auto becomes Sidearm: held like a pistol in both hands, in first and third person, and 6% more damage.",
      needsGroups = { { "quick_draw" }, { "sidestep" } }, needsLabel = "Needs Quick draw or Sidestep" },
    { id = "light_rounds", cat = "officer", spec = "pistol", tier = 5, cost = 3, name = "Light rounds",
      desc = "Hits from a gun loaded with a small magazine: 15% chance to do 50% more damage. Doesn't stack with Critical hits (the better chance counts).",
      needs = { "light_mags" } },
    { id = "crits", cat = "officer", spec = "pistol", tier = 5, cost = 3, name = "Critical hits",
      desc = "10% of your hits with any gun do 50% more damage (with a small magazine, Light rounds' 15% counts instead).",
      needsGroups = { { "steady_grip" }, { "speed_loader" } }, needsLabel = "Needs Steady grip or Speed loader" },
    { id = "cmd_wind", cat = "officer", spec = "pistol", tier = 6, cost = 2, name = "Second wind", exclusive = "command", rankCfg = "commandRank", order = "cmd_wind",
      desc = "No stamina drain while sprinting, and stamina refills fast. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "light_rounds" }, { "crits" } }, needsLabel = "Needs Light rounds or Critical hits" },
    { id = "cmd_triage", cat = "officer", spec = "pistol", tier = 6, cost = 2, name = "Field triage", exclusive = "command", rankCfg = "commandRank", order = "cmd_triage",
      desc = "Downed players nearby get up (at 25% health), everyone heals 8 health a second, and all afflictions are muted (bleeding, fractures, hurt limbs, illness). You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "light_rounds" }, { "crits" } }, needsLabel = "Needs Light rounds or Critical hits" },
    { id = "cmd_hold", cat = "officer", spec = "pistol", tier = 6, cost = 2, name = "Hold fast", exclusive = "command", rankCfg = "commandRank", order = "cmd_hold",
      desc = "Armour refilled (it stays) and no damage at all while it lasts, but nobody can sprint, dash or fly: hold the position. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "light_rounds" }, { "crits" } }, needsLabel = "Needs Light rounds or Critical hits" },
    { id = "cmd_focus", cat = "officer", spec = "pistol", tier = 6, cost = 2, name = "Focus fire", exclusive = "command", rankCfg = "commandRank", order = "cmd_focus",
      desc = "+20% damage and half the kick on every gun. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "light_rounds" }, { "crits" } }, needsLabel = "Needs Light rounds or Critical hits" },
    { id = "cmd_open", cat = "officer", spec = "pistol", tier = 6, cost = 2, name = "Open up", exclusive = "command", rankCfg = "commandRank", order = "cmd_open",
      desc = "Guns use no ammo or power cells. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "light_rounds" }, { "crits" } }, needsLabel = "Needs Light rounds or Critical hits" },
    { id = "cmd_press", cat = "officer", spec = "pistol", tier = 6, cost = 2, name = "Press forward", exclusive = "command", rankCfg = "commandRank", order = "cmd_press",
      desc = "No knockback from hits, no explosion knockdowns, and 20% faster sprinting. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "light_rounds" }, { "crits" } }, needsLabel = "Needs Light rounds or Critical hits" },

    -- Commander (owner: LT and up from the first skill, rankCfg on all):
    -- 1-6-3-4-2. The orders alone at tier 3 (two sides next to them looked
    -- messy), then Rifle drill / Command presence / Field logistics.
    { id = "tactical_visor", cat = "officer", spec = "commander", tier = 2, cost = 2, name = "Tactical visor", icon = "scope", rankCfg = "commandRank",
      desc = "Your Q marks become locks: 25 s instead of 15, a red ring only you see, a red diamond for your squad, and your squad mates (not Marksmen) do 15% more damage to them. With the sun visor down, enemies in view are spotted every 5 s and the one you look at is ringed white: Q locks it.",
      needs = { "mark_target" } },
    { id = "cmd_wind_c", cat = "officer", spec = "commander", tier = 3, cost = 2, name = "Second wind", exclusive = "command", rankCfg = "commandRank", order = "cmd_wind",
      desc = "No stamina drain while sprinting, and stamina refills fast. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "tactical_visor" } }, needsLabel = "Needs Tactical visor" },
    { id = "cmd_triage_c", cat = "officer", spec = "commander", tier = 3, cost = 2, name = "Field triage", exclusive = "command", rankCfg = "commandRank", order = "cmd_triage",
      desc = "Downed players nearby get up (at 25% health), everyone heals 8 health a second, and all afflictions are muted (bleeding, fractures, hurt limbs, illness). You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "tactical_visor" } }, needsLabel = "Needs Tactical visor" },
    { id = "cmd_hold_c", cat = "officer", spec = "commander", tier = 3, cost = 2, name = "Hold fast", exclusive = "command", rankCfg = "commandRank", order = "cmd_hold",
      desc = "Armour refilled (it stays) and no damage at all while it lasts, but nobody can sprint, dash or fly: hold the position. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "tactical_visor" } }, needsLabel = "Needs Tactical visor" },
    { id = "cmd_focus_c", cat = "officer", spec = "commander", tier = 3, cost = 2, name = "Focus fire", exclusive = "command", rankCfg = "commandRank", order = "cmd_focus",
      desc = "+20% damage and half the kick on every gun. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "tactical_visor" } }, needsLabel = "Needs Tactical visor" },
    { id = "cmd_open_c", cat = "officer", spec = "commander", tier = 3, cost = 2, name = "Open up", exclusive = "command", rankCfg = "commandRank", order = "cmd_open",
      desc = "Guns use no ammo or power cells. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "tactical_visor" } }, needsLabel = "Needs Tactical visor" },
    { id = "cmd_press_c", cat = "officer", spec = "commander", tier = 3, cost = 2, name = "Press forward", exclusive = "command", rankCfg = "commandRank", order = "cmd_press",
      desc = "No knockback from hits, no explosion knockdowns, and 20% faster sprinting. You and everyone near you, 6 s; 6 min cooldown.",
      needsGroups = { { "tactical_visor" } }, needsLabel = "Needs Tactical visor" },
    { id = "rifle_drill", cat = "officer", spec = "commander", tier = 4, cost = 2, name = "Rifle drill", rankCfg = "commandRank",
      desc = "Rifles and carbines (DC-15A, Westar-M5, DC-15S, DP-23): 20% less spread while aiming.",
      needsGroups = { { "cmd_wind_c" }, { "cmd_triage_c" }, { "cmd_hold_c" }, { "cmd_focus_c" }, { "cmd_open_c" }, { "cmd_press_c" } },
      needsLabel = "Needs a command order" },
    { id = "cmd_presence", cat = "officer", spec = "commander", tier = 4, cost = 2, name = "Command presence", rankCfg = "commandRank",
      desc = "Your orders reach 50% further.",
      needsGroups = { { "cmd_wind_c" }, { "cmd_triage_c" }, { "cmd_hold_c" }, { "cmd_focus_c" }, { "cmd_open_c" }, { "cmd_press_c" } },
      needsLabel = "Needs a command order" },
    { id = "field_logistics", cat = "officer", spec = "commander", tier = 4, cost = 2, name = "Field logistics", icon = "box", rankCfg = "commandRank",
      desc = "You and your radio squad mates within 15 m of you reload 15% faster.",
      needsGroups = { { "cmd_wind_c" }, { "cmd_triage_c" }, { "cmd_hold_c" }, { "cmd_focus_c" }, { "cmd_open_c" }, { "cmd_press_c" } },
      needsLabel = "Needs a command order" },
    { id = "steady_line", cat = "officer", spec = "commander", tier = 5, cost = 2, name = "Steady the line", icon = "shield", rankCfg = "commandRank",
      desc = "You and your radio squad mates within 15 m of you: 15% less kick and stamina refills 25% faster.", needs = { "rifle_drill" } },
    { id = "seasoned_cmd", cat = "officer", spec = "commander", tier = 5, cost = 1, name = "Seasoned command", rankCfg = "commandRank",
      desc = "Your order cooldown is 4 minutes instead of 6.", needs = { "cmd_presence" } },
    { id = "standing_orders", cat = "officer", spec = "commander", tier = 5, cost = 2, name = "Standing orders", rankCfg = "commandRank",
      desc = "Your orders last 10 s instead of 6.", needs = { "cmd_presence" } },
    { id = "combat_veteran", cat = "officer", spec = "commander", tier = 5, cost = 2, name = "Combat veteran", icon = "star", rankCfg = "commandRank",
      desc = "Rifles (DC-15A, Westar-M5): 10% less spread and kick, 10% faster reloads, and the DC-15A full-auto mode. Carbines (DC-15S, DP-23): 8% more damage. With the Z-6 in your hands: 10% less damage taken.",
      needs = { "field_logistics" } },
    { id = "adapt_1", cat = "officer", spec = "commander", tier = 6, cost = 2, name = "Adaptable", rankCfg = "commandRank",
      desc = "Learn one skill of tier 4 or lower from any other tree, or from the Pistol officer side of this one. It skips that skill's requirements, but you still need the job (medic, MP) and pay its points.",
      needs = { "combat_veteran" } },
    { id = "chain_command", cat = "officer", spec = "commander", tier = 6, cost = 2, name = "Chain of command", rankCfg = "commandRank",
      desc = "Your orders also reach every radio squad mate, however far away (alive and not downed).",
      needsGroups = { { "seasoned_cmd" }, { "standing_orders" } }, needsLabel = "Needs Seasoned command or Standing orders" },
    -- Capstone (2026-10-06az, owner). Path still 24: Adaptable and
    -- Seasoned command each cost one point less to make room.
    { id = "reinforcements", cat = "officer", spec = "commander", tier = 7, cost = 2, name = "Reinforcements", icon = "stack", rankCfg = "commandRank",
      desc = "Right-click with the command comlink: a clone squad (a trooper, a medic, a rifleman and a heavy) arrives around you, steps toward the enemy and follows you, for 10 minutes. You lead them: clones near you aim better, react faster and pause less. 15 min cooldown.",
      needsGroups = { { "adapt_1" }, { "chain_command" } }, needsLabel = "Needs Adaptable or Chain of command" },

    -- Airborne (jetpack: 15 s of flight with any Airborne skill, 10 s without).
    -- Shape 1-2-3-1-3-1: it widens, narrows to Grenadier, then widens again.
    { id = "hard_landings", cat = "airborne", tier = 1, cost = 1, name = "Hard landings",
      desc = "Half fall damage, your legs never break, and you jump 20% higher. Jetpacks fly 15 s instead of 10." },
    { id = "extended_tanks", cat = "airborne", tier = 2, cost = 2, name = "Extended tanks",
      desc = "Jetpack fuel lasts 40% longer and refills 40% faster.", needs = { "hard_landings" } },
    { id = "hover", cat = "airborne", tier = 2, cost = 2, name = "Hover",
      desc = "Hovering with the jetpack (Sprint) burns half the fuel, and you aim 25% steadier and kick 25% less while you hover.",
      needs = { "hard_landings" } },
    { id = "afterburner", cat = "airborne", tier = 3, cost = 2, name = "Afterburner",
      desc = "Jetpack climbs, steers and flies 25% faster.", needs = { "extended_tanks" } },
    { id = "aerial_stability", cat = "airborne", tier = 3, cost = 2, name = "Aerial stability",
      desc = "20% less damage while you're off the ground.",
      needsGroups = { { "extended_tanks" }, { "hover" } }, needsLabel = "Needs Extended tanks or Hover" },
    { id = "combat_drop", cat = "airborne", tier = 3, cost = 2, name = "Combat drop",
      desc = "Land after 7 s or more of jetpack flight: 50% less damage for 5 s.",
      needs = { "hover" } },
    { id = "grenadier", cat = "airborne", tier = 4, cost = 3, name = "Grenadier",
      desc = "Thermal detonators you throw fly 20% further, hit 30% harder and blast 10% wider.",
      needsGroups = { { "afterburner" }, { "aerial_stability" }, { "combat_drop" } },
      needsLabel = "Needs Afterburner, Aerial stability or Combat drop" },
    { id = "dp23_prof", cat = "airborne", tier = 5, cost = 2, name = "DP-23 proficiency",
      desc = "Fire the DP-23 while flying the jetpack (other large guns still can't).",
      needs = { "grenadier" } },
    { id = "blast_hardened", cat = "airborne", tier = 5, cost = 2, name = "Blast hardened",
      desc = "30% less damage from explosions.", needs = { "grenadier" } },
    { id = "battle_rush", cat = "airborne", tier = 5, cost = 2, name = "Battle rush",
      desc = "The first hit you take gives you 25% more damage for 5 s. Once a minute.",
      needs = { "grenadier" } },
    { id = "death_from_above", cat = "airborne", tier = 6, cost = 4, name = "Death from above",
      desc = "Landing hard (a long drop or a jetpack dive) slams droids around you.",
      needsGroups = { { "dp23_prof", "blast_hardened" }, { "dp23_prof", "battle_rush" }, { "blast_hardened", "battle_rush" } },
      needsLabel = "Needs two of DP-23 proficiency, Blast hardened and Battle rush" },

    -- Medic (medic jobs only)
    { id = "field_drag", cat = "medic", tier = 1, cost = 1, name = "Field drag",
      desc = "Drag bodies at a jog instead of a crawl." },
    { id = "hands_on", cat = "medic", tier = 2, cost = 1, name = "Hands-on revive",
      desc = "Revive with no kit at all (E menu). Very slow, and they get up with 15 health.", needs = { "field_drag" } },
    { id = "steady_hands", cat = "medic", tier = 2, cost = 1, name = "Steady hands",
      desc = "Treatments (not revives) are 15% faster.", needs = { "field_drag" } },
    -- (2026-10-09s, owner: both medic paths; Hands-on and Steady hands went 2 -> 1 so paths stay 24)
    { id = "recovery", cat = "medic", tier = 2, cost = 2, name = "Recovery",
      desc = "You heal 4 health every 6 seconds, and your own injuries heal at the same pace: bleeding eases a step each time (heavy, then light, then stopped), damage and burns drop by 4, and a broken bone knits once its damage is gone.",
      needs = { "field_drag" } },

    { id = "quick_revive", cat = "medic", spec = "combat_medic", tier = 3, cost = 3, name = "Quick revive",
      desc = "Revives take 20% less time.", needs = { "hands_on", "steady_hands" } },
    { id = "under_fire", cat = "medic", spec = "combat_medic", tier = 4, cost = 4, name = "Under fire",
      desc = "20% less damage while you revive or treat someone.", needs = { "quick_revive" } },
    { id = "deep_pockets", cat = "medic", spec = "combat_medic", tier = 4, cost = 3, name = "Deep pockets",
      desc = "Medkit stacks hold 2 more.", needs = { "quick_revive" } },
    { id = "triage", cat = "medic", spec = "combat_medic", tier = 4, cost = 3, name = "Triage",
      desc = "Downed markers reach twice as far, show who is helping and flash when time runs short.",
      needs = { "quick_revive" } },
    { id = "medevac", cat = "medic", spec = "combat_medic", tier = 5, cost = 6, name = "Medevac", icon = "drag",
      desc = "A downed player's bleed-out pauses while you drag them to cover.",
      needs = { "under_fire" } },

    { id = "chem_bench", cat = "medic", spec = "chemist", tier = 3, cost = 3, name = "Chemistry",
      desc = "Use a chemistry bench to turn medical supplies into gels, painkillers, splints, blood packs and medkits.",
      needs = { "hands_on", "steady_hands" } },
    { id = "field_surgeon", cat = "medic", spec = "chemist", tier = 4, cost = 4, name = "Field surgeon",
      desc = "Your first aid kit fully sets bones and heals burns anywhere, not just in the med bay.",
      needs = { "chem_bench" } },
    { id = "batch_brewing", cat = "medic", spec = "chemist", tier = 4, cost = 3, name = "Batch brewing",
      desc = "The bench makes two of everything.", needs = { "chem_bench" } },
    { id = "bacta_specialist", cat = "medic", spec = "chemist", tier = 4, cost = 3, name = "Bacta specialist",
      desc = "Bacta tanks near you heal twice as fast.", needs = { "chem_bench" } },
    { id = "efficient_care", cat = "medic", spec = "chemist", tier = 5, cost = 6, name = "Efficient care", icon = "flask",
      desc = "Your first aid kits use a third less charge.",
      needs = { "field_surgeon" } },

    -- Shock Trooper (military police jobs only)
    { id = "riot_shield", cat = "shocktrooper", tier = 1, cost = 1, name = "Riot shield",
      desc = "Unlocks the Coruscant Guard riot shield in the MP armoury, and lets you fire through a shield's viewport. Better than the Republic shield anyone carries: lighter, faster on foot, wider cover, halves explosions you hold it up against. Your Shock Trooper skills only work with it." },
    { id = "shield_bash", cat = "shocktrooper", tier = 2, cost = 2, name = "Shield bash",
      desc = "Shield bash key (default X) with the CG riot shield: stun a player in front of you, or knock a droid back.", needs = { "riot_shield" } },
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
    -- (client: when your own skills were learned, for the menu's undo hint)
    if CLIENT and c and ply == LocalPlayer() then
        K.learnedAt = K.learnedAt or {}
        for id in pairs(set) do
            if not c.set[id] then K.learnedAt[id] = CurTime() end
        end
    end
    ply.rhylibSkillCache = { str = str, set = set }
    return set
end

function K.Has(ply, id)
    return K.Set(ply)[id] == true
end

-- Adaptable: the officer skills that let you borrow from other trees,
-- and the highest tier each one takes.
K.ADAPT_CAT = "officer"
K.ADAPT = { { id = "adapt_1", tier = 4 } }   -- (owner 2026-10-05: one borrowed skill, tier 4 or lower)

-- Is id a borrowed skill in this set (another tree's, or the other officer
-- specialisation's, through Adaptable)?
function K.Borrowed(set, id)
    local n = K.byId[id]
    if not (n and set.adapt_1 and K.Cfg("onePath")) then return false end
    if n.cat ~= K.ADAPT_CAT then return true end
    local own = K.byId.adapt_1 and K.byId.adapt_1.spec
    return n.spec ~= nil and own ~= nil and n.spec ~= own
end

-- A Commander officer (any skill of the commander specialisation that
-- isn't borrowed)? Only they give clone squad orders (comlink R wheel).
function K.IsCommanderSpec(ply)
    local set = K.Set(ply)
    for id in pairs(set) do
        local n = K.byId[id]
        if n and n.spec == "commander" and not K.Borrowed(set, id) then return true end
    end
    return false
end

-- A skill made pointless by another one you have (redundantWith)? Reason or nil.
function K.Redundant(set, n)
    if n and n.redundantWith and set[n.redundantWith] then
        return n.redundantWhy or ("You have " .. (K.byId[n.redundantWith] and K.byId[n.redundantWith].name or n.redundantWith))
    end
end

-- Tier caps of the set's Adaptable slots, highest first.
function K.AdaptSlots(set)
    local out = {}
    for i = #K.ADAPT, 1, -1 do
        if set[K.ADAPT[i].id] then out[#out + 1] = K.ADAPT[i].tier end
    end
    return out
end

-- Do these borrowed tiers fit the slots? (highest tier into the highest cap)
function K.FitsSlots(tiers, slots)
    if #tiers > #slots then return false end
    table.sort(tiers, function(a, b) return a > b end)
    for i, t in ipairs(tiers) do
        if t > slots[i] then return false end
    end
    return true
end

-- The category, spec and branch a set of skills is committed to
-- (borrowed skills don't count).
function K.Commitments(set)
    local cat, spec, branch = {}, {}, {}
    for id in pairs(set) do
        local n = K.byId[id]
        if n and not K.Borrowed(set, id) then
            cat[n.cat] = true
            if n.spec then spec[n.cat] = n.spec end
            if n.branch then branch[n.spec] = n.branch end
        end
    end
    return cat, spec, branch
end

-- Rank check for rankCfg nodes and command orders. Returns ok, reason.
function K.RankOk(ply, key)
    local prefix = K.Cfg(key or "commandRank")
    local R = Rhylib.Roster
    if not (prefix and prefix ~= "" and R and R.RankIndex) then return true end
    local need = R.RankIndex(prefix)
    if need and ply:GetNW2Int("rhylib_rank", 0) < need then
        return false, "Needs the rank " .. (R.RankName and R.RankName(need) or prefix)
    end
    return true
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
    if K.ClassOf and K.ClassOf(ply) then return false, "You're playing a class (leave it on the Class page first)" end
    local cat = K.catById[n.cat]
    if cat and cat.medicOnly then
        local Med = Rhylib.Medical
        if not (Med and Med.IsMedic and Med.IsMedic(ply)) then return false, "Medics only" end
    end
    if cat and cat.mpOnly then
        local MP = Rhylib.MP
        if not (MP and MP.IsMP and MP.IsMP(ply)) then return false, "Military police only" end
    end
    local redundant = K.Redundant(set, n)
    if redundant then return false, redundant end
    local cats, specs, branches = K.Commitments(set)

    -- Borrowed through Adaptable: only the slots and points matter
    -- (and one command order).
    if K.Borrowed(set, id) and next(cats) ~= nil then
        if n.exclusive then
            for sid in pairs(set) do
                local o = K.byId[sid]
                if o and o.exclusive == n.exclusive then return false, "You chose " .. o.name .. " (one of these only)" end
            end
        end
        local tiers = { n.tier }
        for sid in pairs(set) do
            if K.Borrowed(set, sid) then tiers[#tiers + 1] = K.byId[sid].tier end
        end
        local slots = K.AdaptSlots(set)
        if not K.FitsSlots(tiers, slots) then
            if #tiers > #slots then return false, "All your Adaptable slots are used" end
            return false, "No free Adaptable slot for a tier " .. n.tier .. " skill"
        end
        if K.Spent(set) + n.cost > K.Points(ply) then return false, "Not enough skill points" end
        return true
    end

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
    if n.exclusive then
        for sid in pairs(set) do
            local o = K.byId[sid]
            if o and o.exclusive == n.exclusive then return false, "You chose " .. o.name .. " (one of these only)" end
        end
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
        if not okAny then return false, n.needsLabel or "Needs both earlier skills of one specialisation" end
    end
    if n.rankCfg then
        local ok, why = K.RankOk(ply, n.rankCfg)
        if not ok then return false, why end
    end
    if K.Spent(set) + n.cost > K.Points(ply) then return false, "Not enough skill points" end
    return true
end

-- Is node id ruled out by a choice already made (another path, the other
-- specialisation or branch, another skill of an exclusive group)? Returns
-- the reason, or nil. The menu greys these out.
function K.Excluded(ply, set, id)
    local n = K.byId[id]
    if not n or set[id] then return nil end
    local redundant = K.Redundant(set, n)
    if redundant then return redundant end
    local cats, specs, branches = K.Commitments(set)
    if K.Borrowed(set, id) and next(cats) ~= nil then return nil end   -- (Adaptable can still take it)
    if K.Cfg("onePath") then
        for c in pairs(cats) do
            if c ~= n.cat then return "You're on the " .. (K.catById[c] and K.catById[c].name or c) .. " path" end
        end
    end
    if n.spec and specs[n.cat] and specs[n.cat] ~= n.spec then
        return "You chose " .. (K.specById[specs[n.cat]] and K.specById[specs[n.cat]].name or specs[n.cat])
    end
    if n.branch and branches[n.spec] and branches[n.spec] ~= n.branch then return "You chose the other branch" end
    if n.exclusive then
        for sid in pairs(set) do
            local o = K.byId[sid]
            if o and o.exclusive == n.exclusive then return "You chose " .. o.name .. " (one of these only)" end
        end
    end
    return nil
end

-- Undo (right-click): would taking id out of the set leave every other
-- learned skill valid? Returns ok, reason. (When it may be undone at all
-- is the server's call: K.UndoAllowed.)
function K.CanUnlearn(ply, set, id)
    local n = K.byId[id]
    if not (n and set[id]) then return false, "Not learned" end
    if K.ClassOf and K.ClassOf(ply) then return false, "You're playing a class" end
    local rest = {}
    for sid in pairs(set) do
        if sid ~= id then rest[sid] = true end
    end
    for sid in pairs(rest) do
        local o = K.byId[sid]
        if o then
            local ok = true
            -- (borrowed skills skip their own needs, as in K.CanLearn)
            if not K.Borrowed(rest, sid) then
            for _, r in ipairs(o.needs or EMPTY) do
                if not rest[r] then ok = false end
            end
            if ok and o.needsGroups then
                ok = false
                for _, g in ipairs(o.needsGroups) do
                    local all = true
                    for _, r in ipairs(g) do
                        if not rest[r] then all = false break end
                    end
                    if all then ok = true break end
                end
            end
            end
            -- (Adaptable going: the skills borrowed through it would be stranded)
            if ok and K.Borrowed(set, sid) and not K.Borrowed(rest, sid) then ok = false end
            if not ok then return false, o.name .. " needs it (undo that first)" end
        end
    end
    return true
end

-- May this player undo id now? Any time while reset is allowed (freePoints),
-- else within undoWindow seconds of learning it. learnedAt: id -> CurTime.
function K.UndoAllowed(learnedAt, id)
    if K.Cfg("freePoints") then return true end
    local t = learnedAt and learnedAt[id]
    return t ~= nil and CurTime() - t <= K.Cfg("undoWindow")
end
