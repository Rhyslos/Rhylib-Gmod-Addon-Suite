--[[
    Droids: lightweight NextBot enemies that fire real bolts (rhylib_weapons),
    so hits, hit markers and kill markers work like against players.

      B1 battle droid (rhylib_b1): 200 health, E-5 blaster with red bolts,
      now and then a grenade at someone who just ducked behind cover.
      B1 variants (rhylib_b1_<variant>): aat, geonosis, marine, security,
      snow fight like a B1 (other model); heavy fires long fast bursts;
      commander has more health and makes droids near it aim better,
      react faster and pause less between bursts. Killing a commander
      rattles the droids near it for a few seconds.
      B2 super battle droid (rhylib_b2): tough and slow, a blaster in each
      arm firing long fast bursts (no rocket).
      B2 mortar (rhylib_b2_cannon, was "B2 cannon"): slower bursts, and a
      wrist rocket lobbed high over cover (purple blast).
      B2 rocket droid (rhylib_b2_rocketdroid): same arm, but its rocket
      flies straight at you and dives into the floor just before you, so
      it works down hallways and indoors (needs sight of you).
      Training B1 / B2 (rhylib_b1_training, rhylib_b2_training): like the
      B1 and B2 with orange-yellow bolts that only take sim health
      (rhylib_training).
      Fewer but tougher (owner): B1s take cover when hit a few times
      (or suppressed), blind fire from it, and pull back once when badly
      hurt; B2s don't. Route and cover searches are spread over ticks
      (pathPerTick).
      Spots players in sight within range (checked a few times a second,
      not every tick), turns, fires short inaccurate bursts, advances when
      far away, chases to where it last saw you, wanders near where it was
      spawned when idle. Walking needs a navmesh (nav_generate); without
      one droids stand and shoot.

    Spawn menu: NPCs tab, "Rhylib: B1 battle droids", "Rhylib: B2 super
    battle droids" and "Rhylib: Training droids"
    (admins). Droids don't hurt each other. At most maxActive droids exist at once.
]]

Rhylib.Droids = Rhylib.Droids or {}
local D = Rhylib.Droids
local Config = Rhylib.Config

Config.Register("droids", "maxActive", 100, "Most droids alive at once (more are removed when spawned)")
Config.Register("droids", "b1Health", 260, "B1 battle droid health")
Config.Register("droids", "b1Speed", 170, "B1 run speed")
Config.Register("droids", "b1Range", 3000, "How far a B1 sees and shoots")
Config.Register("droids", "b1Reaction", 0.7, "Seconds before a B1 starts firing at a new target")
Config.Register("droids", "e5Damage", 13, "E-5 damage per bolt")
Config.Register("droids", "e5RPM", 300, "E-5 shots per minute within a burst")
Config.Register("droids", "e5Spread", 1.2, "E-5 inaccuracy cone (degrees), more against moving targets")

Config.Register("droids", "b1NadeChance", 0.5, "B1: chance to throw a grenade at a target that just went behind cover")
Config.Register("droids", "b1NadeCooldown", 20, "B1: seconds between one droid's grenades")
Config.Register("droids", "b1NadeFightChance", 0.2, "B1: chance after each burst to throw a grenade at a target it can see (doubled at a group)")
Config.Register("droids", "b1NadeMin", 300, "B1: closest target it throws a grenade at")
Config.Register("droids", "b1NadeMax", 900, "B1: furthest target it throws a grenade at")
Config.Register("droids", "b1NadeDamage", 90, "B1 grenade: damage at the centre")
Config.Register("droids", "b1NadeRadius", 260, "B1 grenade: blast radius")

Config.Register("droids", "b2Health", 800, "B2 super battle droid health")
Config.Register("droids", "b2Speed", 115, "B2 walk speed")
Config.Register("droids", "b2Range", 2800, "How far a B2 sees and shoots")
Config.Register("droids", "b2Reaction", 0.9, "Seconds before a B2 starts firing at a new target")
Config.Register("droids", "b2Damage", 14, "B2 wrist blaster damage per bolt")
Config.Register("droids", "b2RPM", 800, "B2 blasters (both arms) shots per minute within a burst")
Config.Register("droids", "b2cRPM", 420, "B2 cannon: shots per minute within a burst")
Config.Register("droids", "b2Spread", 1.8, "B2 inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "b2RocketDamage", 75, "B2 wrist rocket: damage at the centre")
Config.Register("droids", "b2RocketRadius", 230, "B2 wrist rocket: blast radius")
Config.Register("droids", "b2RocketCooldown", 9, "B2 wrist rocket: seconds between one droid's rockets")
Config.Register("droids", "b2RocketMin", 350, "B2 wrist rocket: closest target it fires at")
Config.Register("droids", "b2RocketMax", 2600, "B2 wrist rocket: furthest target it fires at")
Config.Register("droids", "b2RocketSpread", 70, "B2 wrist rocket: miss distance per 1000 units of range")
Config.Register("droids", "b2DirectSpeed", 1300, "B2 rocket droid: rocket speed (units/s)")
Config.Register("droids", "b2SlowTime", 1, "B2 rocket droid: seconds before the dive over which the rocket slows down")
Config.Register("droids", "b2SlowMult", 0.65, "B2 rocket droid: speed share it slows to by the dive (kept through the curve)")
Config.Register("droids", "b2DiveDist", 220, "B2 rocket droid: how far before its target the rocket starts curving down into the floor")

Config.Register("droids", "heavyHealth", 340, "B1 heavy: health")
Config.Register("droids", "heavySpeed", 140, "B1 heavy: run speed")
Config.Register("droids", "heavyRPM", 800, "B1 heavy: shots per minute within a burst")
Config.Register("droids", "heavySpread", 2.0, "B1 heavy: inaccuracy cone (degrees)")

Config.Register("droids", "cmdHealth", 480, "B1 commander: health")
Config.Register("droids", "cmdRadius", 800, "B1 commander: droids this close get the boost")
Config.Register("droids", "cmdSpread", 0.7, "B1 commander boost: aim cone multiplier")
Config.Register("droids", "cmdReaction", 0.6, "B1 commander boost: reaction time multiplier")
Config.Register("droids", "cmdPause", 0.6, "B1 commander boost: pause between bursts multiplier")
Config.Register("droids", "cmdDeathTime", 6, "B1 commander killed: seconds nearby droids are rattled (0 = off)")
Config.Register("droids", "cmdDeathMult", 1.8, "B1 commander killed: aim cone multiplier while rattled")

Config.Register("droids", "moveSpread", 0.003, "Extra aim cone (degrees) per unit/s the target moves")
Config.Register("droids", "flashSuppress", 3, "Flash charge: droid aim cone multiplier while dazzled")
Config.Register("droids", "flashTime", 5, "Flash charge: seconds droids stay dazzled")

-- Smarter B1s (2026-10-05as, owner: fewer but stronger droids): cover when
-- under fire, blind fire from it, pull back once when badly hurt. B2s
-- don't (they walk into fire). Needs a navmesh; without one they fight
-- in the open like before.
Config.Register("droids", "coverHits", 2, "B1: hits within coverWindow that send it to cover (Z-6 suppression and flash charges too)")
Config.Register("droids", "coverWindow", 2.5, "B1: seconds the hits are counted over")
Config.Register("droids", "coverTime", 4, "B1: seconds it stays in cover (blind firing) before fighting again")
Config.Register("droids", "coverCooldown", 8, "B1: seconds after leaving cover before it takes cover again")
Config.Register("droids", "coverRadius", 700, "B1: how far it looks for a cover spot")
Config.Register("droids", "blindSpread", 4, "B1: aim cone multiplier when blind firing from cover")
Config.Register("droids", "retreatFrac", 0.35, "Health share below which a B1 pulls back once (0 = never)")
-- Peeking (2026-10-05at, owner: 5 B1s and a commander killed you before
-- you got 4 shots off): aim settles in after first sight, and big groups
-- focusing one player aim worse per extra shooter.
Config.Register("droids", "settleTime", 0.8, "Seconds after first seeing a target before a droid aims at its best")
Config.Register("droids", "settleMult", 1.6, "Aim cone multiplier at first sight (eases to 1 over settleTime)")
Config.Register("droids", "crowdFree", 3, "Droids that can fire at one player at full accuracy")
Config.Register("droids", "crowdMult", 0.12, "Extra aim cone per droid above crowdFree firing at the same player")
Config.Register("droids", "crowdMax", 1.4, "Most the crowd rule widens the aim cone (multiplier)")
-- Orders (2026-10-06ay, owner): modes per droid (guard / patrol /
-- attack), admin-only markers (attack here, defend this, fall back here)
-- and one aggression level for every droid that GMs turn up or down live.
Config.Register("droids", "aggression", 3, "Droid aggression 1-5: 1 fall back to a fallback point while firing, 2 slow retreat (no pushing, more cover), 3 moderate (default), 4 march forward firing (charge when spread out or in tight spaces), 5 running charge. GMs change it live with !droidaggro or the toolgun")
Config.Register("droids", "walkMult", 0.5, "Walking (marching) speed as a share of a droid's run speed")
Config.Register("droids", "guardRadius", 700, "Guard mode: how far a droid fights away from its post")
Config.Register("droids", "patrolRadius", 900, "Patrol mode: how far a droid walks around its patrol centre")
Config.Register("droids", "markerRadius", 2000, "Droids within this range of a new marker follow it (droids placed after it follow it too)")
Config.Register("droids", "brushRadius", 400, "Toolgun order brush: droids within this range of where you aim get the order")
Config.Register("droids", "marchGroup", 2, "Marching (aggression 4) needs this many other droids close by; fewer, or a tight space, means a charge")
Config.Register("droids", "runSpread", 1.4, "Aim cone multiplier while running")
Config.Register("droids", "walkSpread", 1.1, "Aim cone multiplier while walking")
Config.Register("droids", "pathPerTick", 4, "Most route and cover searches all droids start in one tick (spreads the cost)")

-- Clone troopers (2026-10-06az, owner): friendly NPCs on the droid brain.
-- They fight droids, never hurt players (or get hurt by them), and the
-- Commander's Reinforcements skill calls a squad of them.
Config.Register("droids", "cloneMax", 40, "Most clone NPCs alive at once")
Config.Register("droids", "cloneAggro", 3, "Clone NPC aggression 1-5 (same scale as the droids'; 3 = moderate)")
Config.Register("droids", "cloneFollowRadius", 600, "Clones following an officer fight at most this far from them")
Config.Register("droids", "ctModel", "models/hazo/npc/ct_trp/npc_ct_trp_f.mdl", "Clone trooper NPC model (troopers, riflemen, heavies; the _h version works too)")
Config.Register("droids", "ctMedicModel", "models/hazo/npc/ct_medic/npc_ct_medic_f.mdl", "Clone medic NPC model")
Config.Register("droids", "ctCmdModel", "models/hazo/npc/ct_cmd/npc_ct_cmd_f.mdl", "Clone commander NPC model")
Config.Register("droids", "ctHealth", 300, "Clone trooper / rifleman / medic: health")
Config.Register("droids", "ctSpeed", 190, "Clone run speed")
Config.Register("droids", "ctRange", 3000, "How far a clone sees and shoots")
Config.Register("droids", "ctReaction", 0.35, "Seconds before a clone starts firing at a new target")
Config.Register("droids", "ctDamage", 18, "Clone DC-15S damage per bolt")
Config.Register("droids", "ctRPM", 360, "Clone DC-15S shots per minute within a burst")
Config.Register("droids", "ctSpread", 0.9, "Clone inaccuracy cone (degrees), more against moving targets")
Config.Register("droids", "ctRifleDamage", 26, "Clone rifleman / commander DC-15A damage per bolt")
Config.Register("droids", "ctRifleRPM", 300, "Clone DC-15A shots per minute within a burst")
Config.Register("droids", "ctHeavyHealth", 420, "Clone heavy: health")
Config.Register("droids", "ctHeavySpeed", 160, "Clone heavy: run speed")
Config.Register("droids", "ctHeavyDamage", 14, "Clone heavy Z-6 damage per bolt")
Config.Register("droids", "ctHeavyRPM", 900, "Clone heavy Z-6 shots per minute within a burst")
Config.Register("droids", "ctHeavySpread", 1.6, "Clone heavy inaccuracy cone (degrees)")
Config.Register("droids", "ctCmdHealth", 500, "Clone commander: health (boosts clones near it like a B1 commander boosts droids)")
Config.Register("droids", "ctMedicHeal", 2, "Clone medic: health a second for players and clones near it")
Config.Register("droids", "ctMedicRadius", 300, "Clone medic: healing radius")
Config.Register("droids", "ctPopperChance", 0.15, "Clone trooper: chance after each burst to throw a droid popper at a droid in sight (doubled at a group)")
Config.Register("droids", "ctPopperLobChance", 0.4, "Clone trooper: chance to throw a droid popper where a droid just went out of sight")
Config.Register("droids", "ctPopperCooldown", 30, "Clone trooper: seconds between one clone's droid poppers")
Config.Register("droids", "ctDownGuards", 2, "Clones that go and stand guard over a downed player (0 = off)")
Config.Register("droids", "ctMedicRepair", 4, "Clone medic: injury damage and burns healed a second on each body part of players near it (bleeding stops, breaks get splinted first)")
Config.Register("droids", "ctMedicReviveRadius", 1500, "Clone medic: goes to downed or just-dead players this close")
Config.Register("droids", "ctMedicReviveTime", 5, "Clone medic: seconds crouched on the body to get someone up")
Config.Register("droids", "ctMedicReviveHealth", 0.3, "Clone medic: share of max health a revived player gets up with")
-- Spread out / doctrine (2026-10-06bd, owner): roaming in twos; clones
-- call for help, fall back when outnumbered, hold when even, charge when
-- they outnumber the droids, and crouch when there's no cover.
Config.Register("droids", "roamRadius", 4000, "Spread out (roam): how far a roaming NPC picks its next spot")
Config.Register("droids", "ctCallRadius", 2000, "Clones: how far a clone's call for help reaches")
Config.Register("droids", "ctCallHelpers", 4, "Clones: most clones that come when one calls for help")
Config.Register("droids", "ctCallCooldown", 12, "Clones: seconds between one clone's calls for help")
Config.Register("droids", "ctOddsFriends", 900, "Clones: friends (clones and players) this close count for the odds")
Config.Register("droids", "ctOddsEnemies", 1500, "Clones: droids this close count for the odds (B2s count double)")
Config.Register("droids", "ctFallBackOdds", 0.8, "Clones fall back when friends are fewer than this share of the enemies")
Config.Register("droids", "ctChargeOdds", 1.25, "Clones charge when friends are more than this many times the enemies (in between they hold the line)")
Config.Register("droids", "ctCrouchTime", 4, "Clones: seconds they crouch when hit with no cover to reach")
Config.Register("droids", "ctCrouchSpread", 0.8, "Clones: aim cone multiplier while crouched")
Config.Register("droids", "ctMedicShield", 0.8, "Clone medic: damage reduction while crouched reviving someone (0.8 = takes 20%)")
Config.Register("droids", "reviveShield", 0.6, "Players got up by a clone medic: damage reduction for reviveShieldTime (ends when they fire; an escape tool)")
Config.Register("droids", "reviveShieldTime", 5, "Players got up by a clone medic: seconds the damage reduction lasts")
Config.Register("droids", "ctMedicDeadWindow", 60, "Clone medic: dead players can be brought back this many seconds after dying (0 = downed players only)")
Config.Register("droids", "ctDownRadius", 1500, "Clones this close to a downed player can be sent to guard them")

function D.Cfg(k) return Config.Get("droids", k) end

D.B1_MODEL = "models/aussiwozzi/cgi/b1droids/b1_battledroid.mdl"   -- (same pack as the variants, B2s and training droids)
D.E5_MODEL = "models/jajoff/sps/cgiweapons/tc13j/e5.mdl"
D.E5_SOUND = "weapons/airboat/airboat_gun_energy2.wav"

D.B2_MODEL = "models/aussiwozzi/cgi/b1droids/b2_battledroid.mdl"
D.B1T_MODEL = "models/aussiwozzi/cgi/b1droids/b1_battledroid_training.mdl"
D.B2T_MODEL = "models/aussiwozzi/cgi/b1droids/b2_battledroid_training.mdl"

--[[
    Droid kinds (ENT.DroidKind). Numbers are config keys. training: yellow
    bolts and blasts that only take sim health (rhylib_training), no kill
    credit. Training droids take normal damage (and training bolts).
]]
D.KINDS = {
    b1 = { name = "B1 battle droid", model = D.B1_MODEL, health = "b1Health", speed = "b1Speed", range = "b1Range", reaction = "b1Reaction",
        damage = "e5Damage", rpm = "e5RPM", spread = "e5Spread", burst = { 2, 3 }, color = 2, gun = D.E5_MODEL, nades = true, cover = true },
    b2 = { name = "B2 super battle droid", model = D.B2_MODEL, health = "b2Health", speed = "b2Speed", range = "b2Range", reaction = "b2Reaction",
        damage = "b2Damage", rpm = "b2RPM", spread = "b2Spread", burst = { 5, 8 }, color = 2, big = true, dual = true },
}

-- B1 variants: a B1 with another model, and a few changes.
local B1V = "models/aussiwozzi/cgi/b1droids/b1_battledroid_"
local function variant(base, name, model, changes)
    local k = table.Copy(D.KINDS[base])
    k.name, k.model = name, model
    for key, v in pairs(changes or {}) do k[key] = v end
    return k
end
D.KINDS.b1_aat = variant("b1", "B1 AAT crew droid", B1V .. "aat.mdl")
D.KINDS.b1_geonosis = variant("b1", "B1 Geonosis droid", B1V .. "geonosis.mdl")
D.KINDS.b1_marine = variant("b1", "B1 marine droid", B1V .. "marine.mdl")
D.KINDS.b1_security = variant("b1", "B1 security droid", B1V .. "security.mdl")
D.KINDS.b1_snow = variant("b1", "B1 snow droid", B1V .. "snow.mdl")
D.KINDS.b1_heavy = variant("b1", "B1 heavy droid", B1V .. "heavy.mdl",
    { health = "heavyHealth", speed = "heavySpeed", rpm = "heavyRPM", spread = "heavySpread", burst = { 6, 10 }, nades = false })
D.KINDS.b1_commander = variant("b1", "B1 commander droid", B1V .. "commander.mdl", { health = "cmdHealth", commander = true })
D.KINDS.b2_cannon = variant("b2", "B2 mortar droid", "models/aussiwozzi/cgi/b1droids/b2_battledroid_cannon.mdl",
    { rpm = "b2cRPM", burst = { 2, 4 }, dual = false, rockets = true })
-- (owner's original idea: a level rocket that dives down just before you)
D.KINDS.b2_rocket = variant("b2", "B2 rocket droid", "models/aussiwozzi/cgi/b1droids/b2_battledroid_cannon.mdl",
    { rpm = "b2cRPM", burst = { 2, 4 }, dual = false, rockets = true, direct = true })

-- Training droids: yellow bolts (color 8), no kill credit.
D.KINDS.b1t = variant("b1", "B1 training droid", D.B1T_MODEL, { training = true, color = 8 })
D.KINDS.b2t = variant("b2", "B2 training droid", D.B2T_MODEL, { training = true, color = 8 })

-- Clone troopers (side "republic"): rhylib_clone and its one-line
-- subclasses. Models come from config (modelCfg); fallback = HL2's
-- Combine soldier (it has rifle animations), never a droid model.
local DC15S, DC15A, Z6 = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl", "models/jajoff/sps/cgiweapons/tc13j/dc15a.mdl", "models/jajoff/sps/cgiweapons/tc13j/z6.mdl"
D.CLONE_FALLBACK = "models/combine_soldier.mdl"
D.KINDS.ct_trooper = { name = "Clone trooper", side = "republic", modelCfg = "ctModel", health = "ctHealth", speed = "ctSpeed", range = "ctRange", reaction = "ctReaction",
    damage = "ctDamage", rpm = "ctRPM", spread = "ctSpread", burst = { 2, 4 }, color = 1, gun = DC15S, poppers = true, cover = true,
    sound = "weapons/airboat/airboat_gun_energy1.wav" }
D.KINDS.ct_rifleman = variant("ct_trooper", "Clone rifleman", nil, { damage = "ctRifleDamage", rpm = "ctRifleRPM", burst = { 2, 3 }, gun = DC15A, poppers = false,
    sound = "weapons/airboat/airboat_gun_energy2.wav" })
D.KINDS.ct_heavy = variant("ct_trooper", "Clone heavy", nil, { health = "ctHeavyHealth", speed = "ctHeavySpeed", damage = "ctHeavyDamage", rpm = "ctHeavyRPM",
    spread = "ctHeavySpread", burst = { 6, 10 }, gun = Z6, poppers = false, cover = false, sound = "weapons/airboat/airboat_gun_energy2.wav" })
D.KINDS.ct_medic = variant("ct_trooper", "Clone medic", nil, { modelCfg = "ctMedicModel", poppers = false, medic = true })
D.KINDS.ct_commander = variant("ct_trooper", "Clone commander", nil, { modelCfg = "ctCmdModel", health = "ctCmdHealth", damage = "ctRifleDamage", rpm = "ctRifleRPM",
    burst = { 2, 3 }, gun = DC15A, poppers = false, commander = true, sound = "weapons/airboat/airboat_gun_energy2.wav" })

-- The model a kind uses (config for clones).
function D.KindModel(k)
    if k.modelCfg then
        local m = D.Cfg(k.modelCfg)
        if isstring(m) and m ~= "" then return m end
    end
    return k.model
end

D.CLASSES = { b1 = "rhylib_b1", b2 = "rhylib_b2", b1t = "rhylib_b1_training", b2t = "rhylib_b2_training", b2_cannon = "rhylib_b2_cannon", b2_rocket = "rhylib_b2_rocketdroid",
    ct_trooper = "rhylib_ct_trooper", ct_rifleman = "rhylib_ct_rifleman", ct_heavy = "rhylib_ct_heavy", ct_medic = "rhylib_ct_medic", ct_commander = "rhylib_ct_commander" }
for _, v in ipairs({ "aat", "commander", "geonosis", "heavy", "marine", "security", "snow" }) do
    D.CLASSES["b1_" .. v] = "rhylib_b1_" .. v
end

D.MODES = { "guard", "patrol", "attack" }   -- (index 1-3 on the wire)
D.MODE_NAMES = { guard = "Guard", patrol = "Patrol", attack = "Attack", follow = "Follow", roam = "Spread out" }
D.AGGRO_NAMES = { "Fall back", "Slow retreat", "Moderate", "March", "Charge" }

-- Aggression 1-5 (server: config, live; clients: Global2Int).
function D.Aggro()
    local v
    if SERVER then v = D.aggroLive or D.Cfg("aggression") else v = GetGlobal2Int("rhylib_droidAggro", 3) end
    return math.Clamp(math.Round(tonumber(v) or 3), 1, 5)
end

-- A droid's blaster as rhylib_weapons sees it (BoltColor 2 = red, 8 = training).
D.guns = D.guns or {}
function D.Gun(kind)
    local k = D.KINDS[kind] or D.KINDS.b1
    local g = D.guns[kind]
    if not g then
        g = { BoltSpeed = 6500, BoltColor = k.color, Training = k.training }
        D.guns[kind] = g
    end
    g.Damage = D.Cfg(k.damage)
    return g
end
function D.E5() return D.Gun("b1") end   -- (older callers)

for kind, class in pairs(D.CLASSES) do
    list.Set("NPC", class, {
        Name = D.KINDS[kind].name,
        Class = class,
        -- (owner: split up so they're easier to find)
        Category = D.KINDS[kind].side == "republic" and "Rhylib: Clone troopers" or D.KINDS[kind].training and "Rhylib: Training droids"
            or (string.sub(kind, 1, 2) == "b2" and "Rhylib: B2 super battle droids" or "Rhylib: B1 battle droids"),
        AdminOnly = true,
    })
    if CLIENT then language.Add(class, D.KINDS[kind].name) end
end

-- Players and clone NPCs don't collide (2026-10-06bc): friendlies never
-- block a doorway or a way out. Bolts still pass by their own rule.
Rhylib.Hook.Add("ShouldCollide", "droids.clones", function(a, b)
    if (a.IsRhylibClone and b:IsPlayer()) or (b.IsRhylibClone and a:IsPlayer()) then return false end
end)
