# rhylib_droids: Droids and clone NPCs

Adds enemy battle droids and friendly clone trooper NPCs. They are NextBots that fire real rhylib_weapons bolts, so hits, hit markers, headshots and kill markers work the same as against players. Droids spot players, react after a short delay, fire short bursts while moving, take cover when shot, throw grenades, and chase where they last saw you. B2s fire from both arms; mortar B2s lob rockets over cover; rocket B2s fire a rocket that dives into the floor in front of you; commanders make droids near them fight better. Clone troopers fight droids on the same brain, never hurt players, heal and revive downed players (medics), stand guard over downed friends, and come as reinforcements when an officer calls them (rhylib_skills).

For game masters: every NPC has a mode (guard, patrol, attack, spread out, retreat) and droids share one live aggression level (1 Retreat to 5 Charge). Both are set with the toolgun, along with order markers (attack here, defend this, fall back here) and ready-made squads. Walking needs a navmesh (`nav_generate`); without one NPCs stand and shoot.

## Requirements

- Required: `rhylib_core`, `rhylib_weapons` (NPCs can't fire without its bolts).
- Works better with: `rhylib_republic` (grenades, droid poppers, the rocket blast effect `rhylib_emp`), `rhylib_toolgun` (placing, orders, markers, presets; it also registers the `rhylib.toolgun` permission that the aggression commands check), `rhylib_skills` (Reinforcements, the command wheel, Heavy Suppression), `rhylib_medical` (clone medics treat injuries and revive downed players), `rhylib_training` (training droids take sim health), `rhylib_eod` (Signal blackout).
- Workshop content: the aussiwozzi CGI B1/B2 droid pack (`models/aussiwozzi/cgi/b1droids/...`), the jajoff TC-13J weapons pack (E-5, DC-15S, DC-15A, Z-6 props), Hazo's clone trooper NPC pack (`models/hazo/npc/...`), the Star Wars shared resources pack (sounds). A missing droid model falls back to the B1 model; a missing clone model to HL2's Combine soldier. Every model can be swapped on the Server settings > Model overrides page.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_droids.lua` | shared | Loads the `droids` module through `Rhylib.LoadModule` (needs rhylib_core). |
| `lua/rhylib/droids/sh_00_config.lua` | shared | `Rhylib.Droids` table, every config key, model paths, `D.KINDS`, `D.CLASSES` (also the spawn menu list), mode/aggression names, `D.Aggro`, `D.Gun`, model overrides, player/clone no-collide. |
| `lua/rhylib/droids/sv_10_droids.lua` | server | Target lists, caps and counts, suppression, commander boost and rattle, EOD blackout check, route budget, cover spot registry, friendly fire rules. |
| `lua/rhylib/droids/sv_20_orders.lua` | server | Modes (`D.SetMode`), markers, toolgun placing and order brush, live aggression (`D.SetAggro`, `!droidaggro`, net `droids.aggro`). |
| `lua/rhylib/droids/sv_30_clones.lua` | server | Clone spawning and reinforcement squads, medics (heal, treat, revive), downed guards, revive shield, roam pairs, calls for help, odds, presets, follow tool, artillery spotting, command wheel squad orders. |
| `lua/entities/rhylib_b1.lua` | shared | The NPC itself (B1 battle droid) and the base of every other kind: the behaviour coroutine, seeing, shooting, grenades, rockets, cover, moving, retreat, medic revive, animation, the gun drawn in the hand. |
| `lua/entities/rhylib_clone.lua` | shared | Clone base class (`rhylib_b1` with `IsRhylibClone`), medic ring. |
| `lua/entities/rhylib_b1_*.lua`, `rhylib_b2*.lua`, `rhylib_ct_*.lua` | shared | One-line subclasses: `ENT.Base` + `ENT.DroidKind`. |
| `lua/entities/rhylib_b2_rocket.lua` | shared | B2 wrist rocket (mortar arc or direct dive), moved by hand each tick. |
| `lua/entities/rhylib_droid_marker.lua` | shared | Order marker (attack / defend / fall back), staff only. |

## For server owners

### NPC kinds

| Kind | Class | Notes |
|---|---|---|
| `b1` | `rhylib_b1` | B1 battle droid: E-5, bursts of 2-3, grenades, takes cover. |
| `b1_aat`, `b1_geonosis`, `b1_marine`, `b1_security`, `b1_snow` | `rhylib_b1_<v>` | A B1 with another model. |
| `b1_heavy` | `rhylib_b1_heavy` | Long fast bursts (6-10), no grenades, own health/speed/rpm/spread. |
| `b1_commander` | `rhylib_b1_commander` | More health; boosts droids within `cmdRadius`; its death rattles them. |
| `b2` | `rhylib_b2` | B2 super battle droid: tough, slow, a blaster in each arm (bursts 5-8), no cover. |
| `b2_cannon` | `rhylib_b2_cannon` | B2 mortar droid: high-arc wrist rocket over cover. |
| `b2_rocket` | `rhylib_b2_rocketdroid` | B2 rocket droid: level rocket that dives into the floor in front of the target; needs sight. |
| `b1t`, `b2t` | `rhylib_b1_training`, `rhylib_b2_training` | Training droids: yellow bolts and blasts that only take sim health, no kill credit. |
| `ct_trooper` | `rhylib_ct_trooper` | Clone trooper: DC-15S, throws droid poppers, takes cover. |
| `ct_rifleman` | `rhylib_ct_rifleman` | DC-15A. |
| `ct_heavy` | `rhylib_ct_heavy` | Z-6, long bursts, crouches instead of taking cover. |
| `ct_medic` | `rhylib_ct_medic` | Heals and treats players/clones in its ring, revives downed players. |
| `ct_commander` | `rhylib_ct_commander` | DC-15A, boosts clones within `cmdRadius`. |

Spawn menu (admins, NPCs tab): "Rhylib: B1 battle droids", "Rhylib: B2 super battle droids", "Rhylib: Training droids", "Rhylib: Clone troopers". The toolgun (rhylib_toolgun) lists them under "Droid NPCs" / "Clone NPCs" and can place 1, 3 or 5 at once.

### Modes, aggression and markers

Every NPC has a mode (shown to staff with the toolgun out as a label over it):

| Mode | What it does |
|---|---|
| `guard` (default for any spawn) | Holds its post (`home`) and fights within `guardRadius`. |
| `patrol` | Walks random points within `patrolRadius` of its centre. |
| `attack` | Goes to its objective (an attack marker), then hunts the nearest target within 6000 units. |
| `roam` ("Spread out") | Wanders the map in pairs (`D.Buddy`), picking a new navmesh spot within `roamRadius` on arrival or every 45 s. |
| `retreat` | Runs legs away from the enemy, turns and fights, runs on; "last stand" when cornered. |
| `follow` | Clones following a player (reinforcements, follow tool, command wheel) or an NPC leader. |

Aggression 1-5 is one live level for every droid (config `aggression` is the start value; clones use `cloneAggro` and their own doctrine):

| Level | Name | Behaviour |
|---|---|---|
| 1 | Retreat | Same as mode `retreat` while fighting. |
| 2 | Fall back | Walks to its fallback point (fallback marker, else home) while firing, then backs off from anyone within 600, takes cover after one hit. |
| 3 | Moderate | Advances when the target is further than 1400, chases where it last saw them within its area. |
| 4 | March | Walks at the target firing (runs instead when fewer than `marchGroup` droids are near or in a corridor). |
| 5 | Charge | Runs at the target, no cover (except the one pull-back). |

Markers (toolgun, only staff see them; not saved): **attack here** (droids within `markerRadius` switch to attack mode toward it), **defend this** (guard with home there), **fall back here** (their fallback point). Droids the toolgun places afterwards follow the latest markers too. Removing an attack marker makes its droids guard where they stand. Clone markers (attack / defend) work the same for clones only.

The toolgun's **order brush** sets a mode on every NPC within `brushRadius` of where you aim (droid orders and clone orders are separate entries).

### Presets (toolgun)

`D.PRESETS`, placed as a grid facing you (front row where you aim, rows 85 units apart, 75 apart sideways):

| Preset | Contents |
|---|---|
| `clone_squad` | 5 front (trooper, rifleman, heavy, rifleman, trooper), rear medic, commander, medic. |
| `clone_company` | 3 rows of 6 troopers/riflemen/heavies, rear 3 medics + commander. |
| `droid_small` | 10 B1. |
| `droid_medium` | 10 B1, rear 5 B2 + commander. |
| `droid_large` | 20 B1, then commander, 7 B2 and 3 rocket B2s. |
| `droid_b2` | 8 B2. |
| `droid_mortar` | 6 B1, rear 2 mortar B2 + commander. The mortars become **artillery** (fire at anything any droid has seen within `artyRange`, their shots walk onto a target), the rest stay with them. |

### Clones

- **Reinforcements** (rhylib_skills): an officer with the skill calls a squad (`D.CallSquad`); they appear behind the officer, walk a few steps toward the nearest droid, then follow the officer. They leave after the skill's life time or when the officer leaves the server.
- **Command wheel** (rhylib_skills): Follow me, Regroup, Hold, Move up there, More/Less aggressive, Dismiss (`D.SquadOrder`).
- **Medics**: every second heal players and clones in `ctMedicRadius` by `ctMedicHeal`, treat injuries (worst bleed first, then a break, then damage and burns), and walk to downed players within `ctMedicReviveRadius`, crouch for `ctMedicReviveTime` and revive them at `ctMedicReviveHealth`. A revived player takes less damage for `reviveShieldTime` (ends when they fire). Medics never revive the dead.
- **Downed guards**: up to `ctDownGuards` free clones within `ctDownRadius` stand over each downed player.
- **Doctrine**: in a fight a clone compares friends to droids nearby: outnumbered = fall back, even = hold, outnumbering = charge. Fresh contact calls up to `ctCallHelpers` idle clones over.
- Players and clones never hurt each other and walk through each other. Bolts fly through friendlies.

### Settings

Config module `"droids"` (Server settings > NPCs > Droids & clones; the sections below match the page). Health, speed and damage are read when an NPC spawns or fires, so a change applies to new NPCs and new shots.

#### General

| Key | Default | What it does |
|---|---|---|
| `maxActive` | `100` | Most droids alive at once (more are removed when spawned) |
| `moveSpread` | `0.003` | Extra aim cone (degrees) per unit/s the target moves |
| `aggression` | `3` | Droid aggression 1-5: 1 retreat (withdraw from the enemy: run, turn and fire, run on; last stand when cornered), 2 fall back (to a fallback marker or their post while firing, then back off from anyone close, no pushing), 3 moderate (default), 4 march forward firing (charge when spread out or in tight spaces), 5 running charge. GMs change it live with !droidaggro or the toolgun |
| `walkMult` | `0.5` | Walking (marching) speed as a share of a droid's run speed |
| `marchGroup` | `2` | Marching (aggression 4) needs this many other droids close by; fewer, or a tight space, means a charge |
| `runSpread` | `1.4` | Aim cone multiplier while running |
| `walkSpread` | `1.1` | Aim cone multiplier while walking |
| `pathPerTick` | `4` | Most route and cover searches all droids start in one tick (spreads the cost) |

#### Orders & areas

| Key | Default | What it does |
|---|---|---|
| `guardRadius` | `700` | Guard mode: how far a droid fights away from its post |
| `patrolRadius` | `900` | Patrol mode: how far a droid walks around its patrol centre |
| `markerRadius` | `2000` | Droids within this range of a new marker follow it (droids placed after it follow it too) |
| `brushRadius` | `400` | Toolgun order brush: droids within this range of where you aim get the order |
| `roamRadius` | `4000` | Spread out (roam): how far a roaming NPC picks its next spot |

#### B1 grenades

| Key | Default | What it does |
|---|---|---|
| `b1NadeChance` | `0.5` | B1: chance to throw a grenade at a target that just went behind cover |
| `b1NadeCooldown` | `20` | B1: seconds between one droid's grenades |
| `b1NadeFightChance` | `0.2` | B1: chance after each burst to throw a grenade at a target it can see (doubled at a group) |
| `b1NadeMin` | `300` | B1: closest target it throws a grenade at |
| `b1NadeMax` | `900` | B1: furthest target it throws a grenade at |
| `b1NadeDamage` | `90` | B1 grenade: damage at the centre |
| `b1NadeRadius` | `260` | B1 grenade: blast radius |

#### B1 battle droids

| Key | Default | What it does |
|---|---|---|
| `b1Health` | `260` | B1 battle droid health |
| `b1Speed` | `170` | B1 run speed |
| `b1Range` | `3000` | How far a B1 sees and shoots |
| `b1Reaction` | `0.7` | Seconds before a B1 starts firing at a new target |
| `e5Damage` | `13` | E-5 damage per bolt |
| `e5RPM` | `300` | E-5 shots per minute within a burst |
| `e5Spread` | `1.2` | E-5 inaccuracy cone (degrees), more against moving targets |

#### B2 rockets & mortars

| Key | Default | What it does |
|---|---|---|
| `b2RocketDamage` | `75` | B2 wrist rocket: damage at the centre |
| `b2RocketRadius` | `230` | B2 wrist rocket: blast radius |
| `b2RocketCooldown` | `9` | B2 wrist rocket: seconds between one droid's rockets |
| `b2RocketMin` | `350` | B2 wrist rocket: closest target it fires at |
| `b2RocketMax` | `2600` | B2 wrist rocket: furthest target it fires at |
| `b2RocketSpread` | `70` | B2 wrist rocket: miss distance per 1000 units of range |
| `b2DirectSpeed` | `1300` | B2 rocket droid: rocket speed (units/s) |
| `b2SlowTime` | `1` | B2 rocket droid: seconds before the dive over which the rocket slows down |
| `b2SlowMult` | `0.65` | B2 rocket droid: speed share it slows to by the dive (kept through the curve) |
| `b2DiveDist` | `220` | B2 rocket droid: how far before its target the rocket starts curving down into the floor |
| `artyRange` | `8000` | Mortar squad artillery: how far its mortars fire (any droid spotting a target is enough) |
| `artyCooldown` | `4.5` | Mortar squad artillery: seconds between one mortar's rockets |
| `artySpread` | `35` | Mortar squad artillery: miss distance per 1000 units (tightens on repeated shots at one target) |
| `artyMaxFlight` | `5.5` | Mortar squad artillery: longest rocket flight time (higher arcs at long range) |
| `artyBlasterRange` | `1500` | Mortar squad artillery: closer than this it also uses its blaster |

#### B2 super battle droids

| Key | Default | What it does |
|---|---|---|
| `b2Health` | `800` | B2 super battle droid health |
| `b2Speed` | `115` | B2 walk speed |
| `b2Range` | `2800` | How far a B2 sees and shoots |
| `b2Reaction` | `0.9` | Seconds before a B2 starts firing at a new target |
| `b2Damage` | `14` | B2 wrist blaster damage per bolt |
| `b2RPM` | `800` | B2 blasters (both arms) shots per minute within a burst |
| `b2cRPM` | `420` | B2 cannon: shots per minute within a burst |
| `b2Spread` | `1.8` | B2 inaccuracy cone (degrees), more against moving targets |

#### Heavy & commander droids

| Key | Default | What it does |
|---|---|---|
| `heavyHealth` | `340` | B1 heavy: health |
| `heavySpeed` | `140` | B1 heavy: run speed |
| `heavyRPM` | `800` | B1 heavy: shots per minute within a burst |
| `heavySpread` | `2.0` | B1 heavy: inaccuracy cone (degrees) |
| `cmdHealth` | `480` | B1 commander: health |
| `cmdRadius` | `800` | B1 commander: droids this close get the boost |
| `cmdSpread` | `0.7` | B1 commander boost: aim cone multiplier |
| `cmdReaction` | `0.6` | B1 commander boost: reaction time multiplier |
| `cmdPause` | `0.6` | B1 commander boost: pause between bursts multiplier |
| `cmdDeathTime` | `6` | B1 commander killed: seconds nearby droids are rattled (0 = off) |
| `cmdDeathMult` | `1.8` | B1 commander killed: aim cone multiplier while rattled |

#### Cover & accuracy

| Key | Default | What it does |
|---|---|---|
| `flashSuppress` | `3` | Flash charge: droid aim cone multiplier while dazzled |
| `flashTime` | `5` | Flash charge: seconds droids stay dazzled |
| `coverHits` | `2` | B1: hits within coverWindow that send it to cover (Z-6 suppression and flash charges too) |
| `coverWindow` | `2.5` | B1: seconds the hits are counted over |
| `coverTime` | `4` | B1: seconds it stays in cover (blind firing) before fighting again |
| `coverCooldown` | `8` | B1: seconds after leaving cover before it takes cover again |
| `coverRadius` | `700` | B1: how far it looks for a cover spot |
| `blindSpread` | `4` | B1: aim cone multiplier when blind firing from cover |
| `retreatFrac` | `0.35` | Health share below which a B1 pulls back once (0 = never) |
| `settleTime` | `0.8` | Seconds after first seeing a target before a droid aims at its best |
| `settleMult` | `1.6` | Aim cone multiplier at first sight (eases to 1 over settleTime) |
| `crowdFree` | `3` | Droids that can fire at one player at full accuracy |
| `crowdMult` | `0.12` | Extra aim cone per droid above crowdFree firing at the same player |
| `crowdMax` | `1.4` | Most the crowd rule widens the aim cone (multiplier) |

#### Retreat

| Key | Default | What it does |
|---|---|---|
| `retreatLeg` | `550` | Retreat: how far each run away from the enemy goes before turning to fight |
| `retreatStand` | `3.5` | Retreat: seconds it turns and fights between runs |
| `retreatClose` | `350` | Retreat: an enemy this close makes it turn and fight instead of turning its back |
| `retreatClear` | `15` | Retreat: seconds with no enemy seen or shooting before it stops and holds where it is |
| `retreatMax` | `1500` | Retreat: with no enemy in sight it stops this far from where the retreat began (stays roughly in the same area) |
| `lastStandPause` | `0.6` | Last stand (retreating with nowhere to go): pause between bursts multiplier |

#### Clone medics

| Key | Default | What it does |
|---|---|---|
| `ctMedicHeal` | `2` | Clone medic: health a second for players and clones near it |
| `ctMedicRadius` | `300` | Clone medic: healing radius |
| `ctDownGuards` | `2` | Clones that go and stand guard over a downed player (0 = off) |
| `ctMedicRepair` | `4` | Clone medic: injury damage and burns healed a second on each body part of players near it (bleeding stops, breaks get splinted first) |
| `ctMedicReviveRadius` | `1500` | Clone medic: goes to downed or just-dead players this close |
| `ctMedicReviveTime` | `5` | Clone medic: seconds crouched on the body to get someone up |
| `ctMedicReviveHealth` | `0.3` | Clone medic: share of max health a revived player gets up with |
| `ctMedicShield` | `0.8` | Clone medic: damage reduction while crouched reviving someone (0.8 = takes 20%) |
| `reviveShield` | `0.6` | Players got up by a clone medic: damage reduction for reviveShieldTime (ends when they fire; an escape tool) |
| `reviveShieldTime` | `5` | Players got up by a clone medic: seconds the damage reduction lasts |
| `ctDownRadius` | `1500` | Clones this close to a downed player can be sent to guard them |

#### Clone tactics

| Key | Default | What it does |
|---|---|---|
| `ctPopperChance` | `0.15` | Clone trooper: chance after each burst to throw a droid popper at a droid in sight (doubled at a group) |
| `ctPopperLobChance` | `0.4` | Clone trooper: chance to throw a droid popper where a droid just went out of sight |
| `ctPopperCooldown` | `30` | Clone trooper: seconds between one clone's droid poppers |
| `ctCallRadius` | `2000` | Clones: how far a clone's call for help reaches |
| `ctCallHelpers` | `4` | Clones: most clones that come when one calls for help |
| `ctCallCooldown` | `12` | Clones: seconds between one clone's calls for help |
| `ctOddsFriends` | `900` | Clones: friends (clones and players) this close count for the odds |
| `ctOddsEnemies` | `1500` | Clones: droids this close count for the odds (B2s count double) |
| `ctFallBackOdds` | `0.8` | Clones fall back when friends are fewer than this share of the enemies |
| `ctChargeOdds` | `1.25` | Clones charge when friends are more than this many times the enemies (in between they hold the line) |
| `ctCrouchTime` | `4` | Clones: seconds they crouch when hit with no cover to reach |
| `ctCrouchSpread` | `0.8` | Clones: aim cone multiplier while crouched |

#### Clone troopers

| Key | Default | What it does |
|---|---|---|
| `cmdFollowRadius` | `900` | Command wheel Follow me: free clones this close join you |
| `cmdMaxFollowers` | `8` | Command wheel: most clones following one commander |
| `cloneMax` | `40` | Most clone NPCs alive at once |
| `cloneAggro` | `3` | Clone NPC aggression 1-5 (same scale as the droids'; 3 = moderate) |
| `cloneFollowRadius` | `600` | Clones following an officer fight at most this far from them |
| `ctHealth` | `300` | Clone trooper / rifleman / medic: health |
| `ctSpeed` | `190` | Clone run speed |
| `ctRange` | `3000` | How far a clone sees and shoots |
| `ctReaction` | `0.35` | Seconds before a clone starts firing at a new target |
| `ctDamage` | `18` | Clone DC-15S damage per bolt |
| `ctRPM` | `360` | Clone DC-15S shots per minute within a burst |
| `ctSpread` | `0.9` | Clone inaccuracy cone (degrees), more against moving targets |
| `ctRifleDamage` | `26` | Clone rifleman / commander DC-15A damage per bolt |
| `ctRifleRPM` | `300` | Clone DC-15A shots per minute within a burst |
| `ctHeavyHealth` | `420` | Clone heavy: health |
| `ctHeavySpeed` | `160` | Clone heavy: run speed |
| `ctHeavyDamage` | `14` | Clone heavy Z-6 damage per bolt |
| `ctHeavyRPM` | `900` | Clone heavy Z-6 shots per minute within a burst |
| `ctHeavySpread` | `1.6` | Clone heavy inaccuracy cone (degrees) |
| `ctCmdHealth` | `500` | Clone commander: health (boosts clones near it like a B1 commander boosts droids) |

#### Models

| Key | Default | What it does |
|---|---|---|
| `ctModel` | `"models/hazo/npc/ct_trp/npc_ct_trp_f.mdl"` | Clone trooper NPC model (troopers, riflemen, heavies; the _h version works too) |
| `ctMedicModel` | `"models/hazo/npc/ct_medic/npc_ct_medic_f.mdl"` | Clone medic NPC model |
| `ctCmdModel` | `"models/hazo/npc/ct_cmd/npc_ct_cmd_f.mdl"` | Clone commander NPC model |

#### Other

| Key | Default | What it does |
|---|---|---|
| `blackoutReaction` | `2` | EOD Signal blackout: droids' reaction time multiplier inside the bubble |

Change them in game on the Server settings page, or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("droids", "maxActive", 60)      -- fewer droids at once
Rhylib.Config.Set("droids", "b1Health", 200)
Rhylib.Config.Set("droids", "aggression", 4)      -- start every map at March
Rhylib.Config.Set("droids", "ctModel", "models/hazo/npc/ct_trp/npc_ct_trp_h.mdl")
```

Droid and gun models that aren't config keys (each kind's `model` and `gun`) are on the Server settings > Model overrides page as `droid.<kind>` and `droid.<kind>.gun`.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `!droidaggro <1-5>` / `!aggression <1-5>` (chat) | permission `rhylib.toolgun` (admin; registered by rhylib_toolgun) | Sets the live aggression for every droid. No number shows the current level. |
| `rhylib_droidaggro <1-5>` (console) | superadmin or the server console | Same (no number sets 3). |
| Toolgun aggression buttons (net `droids.aggro`) | `rhylib.toolgun` | Same. |
| `rhylib_medic_debug 1` (server convar, saved) | server console | Prints each clone medic revive step. |

Admins see a chat line whenever the aggression changes. The live level is not saved: a map change goes back to the config value. Changing `aggression` in Server settings also replaces the live level.

### Placing things / saving

NPCs and markers are never saved; place them for each session (spawn menu, toolgun, or the rhylib_core load test). The toolgun's "New droids" setting picks the mode new placements get (Guard, Patrol, Attack, Roam).

## For players (short)

Nothing to press. Things to know: droids react a moment after first seeing you and aim better after a second; a crowd of droids on one player aims worse per extra shooter; flash charges and Z-6 suppression make them miss and duck into cover; killing a commander rattles the droids around it. Clone NPCs walk through you, never shoot you, hold fire when you are in their line of fire, and a medic NPC will come to you when you are downed.

## For developers

### How the brain works

`entities/rhylib_b1.lua`, `ENT:RunBehaviour` (one coroutine per NPC). Each pass picks one job, in this order: revive a patient (medics) > take cover > fight (`ENT:Look` finds a target → `ENT:Engage`) > keep retreating > answer a call for help > reinforcement steps > walk to the fallback point (aggression 2) > go where the target was last seen > attack mode > roam > back to home > artillery > idle / patrol / shuffle. `ENT:Engage` runs one tick at a time: cover check, `Look`, `StepMove` (walks toward `PlanMove`'s goal, straight or by a navmesh Path), then fires when the reaction delay is over, the next shot is due and the body faces the target. Path searches share `D.TakeBudget()` (`pathPerTick` per tick for all NPCs).

Targets come from cached lists (0.25 s): droids `D.DroidTargets()` (players + clones), clones `D.CloneTargets()` (non-training droids), training droids `D.Targets()` (players).

### Public functions

On `Rhylib.Droids` (`D`), server unless marked.

| Function | What it does |
|---|---|
| `D.Cfg(key)` → value (shared) | `Rhylib.Config.Get("droids", key)`. |
| `D.KindModel(kindRow)` → path (shared) | The kind's model (config for clones). |
| `D.Aggro()` → 1-5 (shared) | Droid aggression (client: Global2Int `rhylib_droidAggro`). |
| `D.Gun(kindName)` → table (shared) | The bolt "weapon" passed to `Bolts.Fire`. |
| `D.Targets()`, `D.DroidTargets()`, `D.CloneTargets()` → list | Cached target lists. |
| `D.Count()`, `D.CloneCount()` → number | Living droids / clones. |
| `D.Suppress(npc, secs, mult)` | Worse aim (cone × mult) for secs. `D.SuppressMult(npc)` reads it. |
| `D.Boosted(npc)` → bool | Near a commander of its side. |
| `D.Rattle(cmd)` | Commander killed: nearby NPCs of its side aim worse. |
| `D.Blackout(pos)`, `D.BlackedOut(npc)` → bool | EOD Signal blackout (asks `Rhylib.EOD.InBlackout`). |
| `D.TakeBudget()` → bool | One route/cover search allowed this tick. |
| `D.SetMode(npc, mode, center)` | Set a mode (and home). |
| `D.ApplyMarker(npc, marker)`, `D.MarkerPlaced(marker, kind, side)`, `D.MarkerRemoved(marker)` | Marker orders. |
| `D.ToolPlaced(npc, mode)` | A placed NPC: mode + latest markers. |
| `D.PaintMode(pos, mode, side)` → count | Order brush. side 1 = clones. |
| `D.SetAggro(n, by)` | Live aggression for every droid. |
| `D.SpawnClone(kind, pos, yaw)` → clone or nil | One clone (respects `cloneMax`). |
| `D.CallSquad(leader, kinds, life)` → count | Reinforcement squad following leader. |
| `D.SpawnPreset(name, origin, yaw, mode)` → list, wanted | Place a preset grid. |
| `D.Buddy(b, lead)` | b walks beside lead (roam pair). |
| `D.RoamPoint(from)` → Vector or nil | A random navmesh spot to roam to. |
| `D.CloneCall(caller, enemy)` | Call idle clones over. |
| `D.CloneOdds(clone)` → friends, enemies, middle | The odds around a clone. |
| `D.ToggleFollowPick(ply, trace)` → count, `D.AssignFollow(ply, target)` → count | Follow tool. |
| `D.Followers(ply)` → list, `D.SquadOrder(ply, op)` → message | Command wheel. |
| `D.SpottedTarget(mortar, range)` → target | Artillery spotting. |
| `D.PatientPending(p)`, `D.BodyPos(p)`, `D.NpcRevive(p)`, `D.ReviveShield(p)` | Medic helpers. |
| `D.GroundAt(pos)` → Vector or nil | Navmesh / floor point under pos. |

NPC methods you may call or override in a subclass (server): `ENT:Kind()` (shared), `ENT:Look()`, `ENT:TargetList()`, `ENT:IsFoe(e)`, `ENT:Aggro()`, `ENT:FireAt(t)`, `ENT:FireAtPos(aim, speed, extra)`, `ENT:ThrowNade(pos)`, `ENT:FireRocket(pos, mover)`, `ENT:PlanMove(t)`, `ENT:Retreating()`, `ENT:SetPace(run)`. The waiting ones (`Go`, `Face`, `Idle`, `TakeCover`, `Engage`) yield and only work inside the coroutine.

Useful fields: `ENT.IsRhylibDroid` / `ENT.IsRhylibClone`, `ENT.DroidKind`, `npc.mode`, `npc.home`, `npc.target`, `npc.Training`, `npc.artillery`, `npc.leader`.

### Adding a new droid kind

A kind is a row in `D.KINDS` plus a class name in `D.CLASSES` plus a one-line entity file. The brain reads everything from the row, so no other code changes.

**Inside rhylib_droids** (simplest). In `lua/rhylib/droids/sh_00_config.lua`, register any new config keys, add the row (after the other B1 variants, so `variant` and `B1V` exist) and the class:

```lua
-- config keys (with the others near the top)
Config.Register("droids", "sniperHealth", 200, "B1 sniper droid: health")
Config.Register("droids", "sniperDamage", 45, "B1 sniper droid: damage per bolt")
Config.Register("droids", "sniperRPM", 40, "B1 sniper droid: shots per minute within a burst")
Config.Register("droids", "sniperSpread", 0.4, "B1 sniper droid: aim cone (degrees)")
Config.Register("droids", "sniperRange", 5000, "How far a B1 sniper sees and shoots")

-- the kind: a B1 with another model and these fields changed
D.KINDS.b1_sniper = variant("b1", "B1 sniper droid", B1V .. "marine.mdl", {
    health = "sniperHealth", damage = "sniperDamage", rpm = "sniperRPM",
    spread = "sniperSpread", range = "sniperRange",
    burst = { 1, 2 },     -- one or two aimed shots, then a pause
    nades = false,        -- no grenades
})

-- the class (right after the D.CLASSES table, before the spawn menu loop at the bottom)
D.CLASSES.b1_sniper = "rhylib_b1_sniper"
```

Then add `lua/entities/rhylib_b1_sniper.lua`:

```lua
-- B1 sniper droid: the B1 code (rhylib_b1) with the "b1_sniper" row of Rhylib.Droids.KINDS.
AddCSLuaFile()
ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "B1 sniper droid"
ENT.Category = "Rhylib: B1 battle droids"
ENT.Spawnable = false   -- listed in the NPCs tab through D.CLASSES instead
ENT.AdminOnly = true
ENT.DroidKind = "b1_sniper"
```

That's all: it appears in the spawn menu's NPCs tab, counts toward `maxActive`, its health/damage show in Server settings, and its model shows on the Model overrides page as `droid.b1_sniper`. For a clone kind use `side = "republic"` (copy a `ct_*` row with `variant("ct_trooper", ...)`), `ENT.Base = "rhylib_clone"`, and the clone counts toward `cloneMax`.

Row fields: `name`, `model` (or `modelCfg` = a config key holding the model), `health`, `speed`, `range`, `reaction`, `damage`, `rpm`, `spread` (all config KEY names), `burst = { min, max }`, `color` (bolt colour: 1 blue, 2 red, 8 training), `gun` (prop model in the right hand; none = no prop), `sound`, `pitch`, and the flags `nades`, `poppers`, `cover`, `big`, `dual`, `rockets`, `direct`, `commander`, `medic`, `training`, `side`. The comment above `D.KINDS` in `sh_00_config.lua` explains each.

**From your own addon** (so Workshop updates don't overwrite it), do the same at gamemode `Initialize`, when every addon has loaded. Config keys and the row must exist on both realms, and the spawn menu list must be set by hand because `sh_00_config.lua` has already built it:

```lua
-- lua/autorun/my_droids.lua (shared, in your own addon)
hook.Add("Initialize", "my_droids.kinds", function()
    local D = Rhylib and Rhylib.Droids
    if not D then return end   -- rhylib_droids not installed
    local Config = Rhylib.Config
    Config.Register("droids", "sniperHealth", 200, "B1 sniper droid: health")
    Config.Register("droids", "sniperDamage", 45, "B1 sniper droid: damage per bolt")

    local k = table.Copy(D.KINDS.b1)
    k.name = "B1 sniper droid"
    k.model = "models/aussiwozzi/cgi/b1droids/b1_battledroid_marine.mdl"
    k.health, k.damage = "sniperHealth", "sniperDamage"
    k.burst, k.nades = { 1, 2 }, false
    D.KINDS.b1_sniper = k
    D.CLASSES.b1_sniper = "my_b1_sniper"

    list.Set("NPC", "my_b1_sniper", { Name = k.name, Class = "my_b1_sniper",
        Category = "Rhylib: B1 battle droids", AdminOnly = true })
    if CLIENT then language.Add("my_b1_sniper", k.name) end
end)

-- Toolgun entry (shared, rhylib_toolgun): "Droid NPCs" list, 1/3/5 at once
hook.Add("Rhylib.ToolEntries", "my_droids.tool", function(list)
    list[#list + 1] = { id = "my_b1_sniper", name = "B1 sniper droid", cat = "Droid NPCs", class = "my_b1_sniper", count = true }
end)
```

with `lua/entities/my_b1_sniper.lua` being the same one-line file as above (`ENT.DroidKind = "b1_sniper"`). To put the new kind in a preset, add a row to `D.PRESETS` (a toolgun entry with `preset = "<name>"` places it).

### Hooks

Fired: GMod's `OnNPCKilled(npc, attacker, inflictor)` when a droid or clone dies (not for training droids), so kill feeds and skills see it.

Listened to: `Rhylib.ModelCatalogue` (adds each kind's model and gun to Model overrides), `Rhylib.ConfigChanged` (a Server settings change of `aggression` replaces the live level), `EntityTakeDamage` (`droids.friendly` -200: droids never hurt droids, players and clones never hurt each other; `droids.shields` 60: medic and revive shields), `ShouldCollide` (players and clones don't collide), `KeyPress` and `PlayerSpawn` (end the revive shield), `PlayerDisconnected` (an officer's reinforcements leave with them), `PlayerSay` (`!droidaggro`), `InitPostEntity`, `OnReloaded` (client gun placement cache).

Other addons' functions it calls when present: `Rhylib.Weapons.Bolts.Fire`, `Rhylib.Medical.Revive` / `inj` / `MarkInjuries`, `Rhylib.Skills.Has` / `HasReinforcements`, `Rhylib.Lying.BodyPos` / `Owner`, `Rhylib.EOD.InBlackout`, `Rhylib.Weapons.TrainingBlast`, the `rhylib_grenade` entity and the `rhylib_emp` effect.

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `droids.aggro` | client → server | level UInt 3 (1-5) | Toolgun aggression buttons (needs `rhylib.toolgun`). |

Networked state: Global2Int `rhylib_droidAggro` (live aggression); on NPCs NW2String `rhylib_dmode` (mode label: guard, patrol, attack, roam, retreat, follow, laststand), NW2Entity `rhylib_lead` (a clone's player leader), NW2Entity `rhylib_pickBy` (picked by the follow tool), aim pose parameters; on players NW2Int `rhylib_squadAggro` (command wheel level); marker DT `Kind` / `Side`; rocket DT `Training`.

### Saved data

None. NPCs, markers and the live aggression last until the map changes. Settings are saved by rhylib_core's Server settings.

### Examples

Spawn a B1 that patrols around a spot, from your own code:

```lua
-- server
local d = ents.Create("rhylib_b1")
d:SetPos(pos)
d:Spawn()
Rhylib.Droids.SetMode(d, "patrol", pos)   -- or "guard" / "attack" / "roam" / "retreat"
```

Send every droid near a spot to attack, and turn the aggression up:

```lua
-- server
Rhylib.Droids.PaintMode(pos, "attack")
Rhylib.Droids.SetAggro(5)
```

Suppress droids hit by your own weapon:

```lua
-- server
hook.Add("EntityTakeDamage", "myaddon.suppress", function(ent, dmg)
    if ent.IsRhylibDroid and IsValid(dmg:GetInflictor()) and dmg:GetInflictor():GetClass() == "my_minigun" then
        Rhylib.Droids.Suppress(ent, 3, 1.8)
    end
end)
```

Call a clone squad for a player (event script):

```lua
-- server
Rhylib.Droids.CallSquad(ply, { "ct_trooper", "ct_rifleman", "ct_medic" }, 300)
```

## Notes and gotchas

- Walking needs a navmesh. Without one NPCs still see and shoot, retreat in straight lines, but never take cover or patrol.
- `maxActive` and `cloneMax` are checked when an NPC is created: one over the cap removes itself the next tick (`npc.overCap`).
- Droid aggression is one live level for all droids; it is not saved and resets to the config on a map change. Clones use `cloneAggro`, their doctrine, or their commander's command wheel level.
- `!droidaggro` and the toolgun buttons check the `rhylib.toolgun` permission, which rhylib_toolgun registers. Without rhylib_toolgun installed that check always fails; use the console command instead.
- Config description of `ctMedicReviveRadius` still says "downed or just-dead players": medics revive only downed players since 2026-10-07.
- Kind rows store config KEY names, not numbers, so a Server settings change applies without a map change (health for new spawns, damage and spread at once). Model changes need new NPCs (or a map change).
- Training droids give no kill credit (no `OnNPCKilled`), take normal damage, and are never targeted by clones.
- Artillery is only set by the Mortar squad preset (`npc.artillery = true`); a mortar spawned alone behaves as a normal mortar B2.
- Markers are seen only by admins (`IsAdmin`) and never saved.
- Grenades need rhylib_republic (`rhylib_grenade`); without it the throw does nothing.
- Performance: target lists are shared and cached for 0.25 s, sight checks are capped at 4-5 traces per look, idle NPCs with nobody near wait 3-5 s between checks, and route/cover searches are limited per tick (`pathPerTick`).
