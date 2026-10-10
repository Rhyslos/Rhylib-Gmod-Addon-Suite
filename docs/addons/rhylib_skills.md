# rhylib_skills: Skill trees, command orders and class mode

Players spend skill points on a tree of skills that change how they fight: faster reloads, steadier aim, fire modes, carrying more, jetpack upgrades, medic and military police abilities. There are six categories (tabs): Trooper, Support, Officer, Specialist (Airborne or Field technician), Medic (medic jobs only) and Shock Trooper (military police only). Each category splits into specialisations, some of those into end branches, and by default a player follows one category at a time. Officers also get command orders (a short buff for everyone near them, given with the command comlink), target marking, and with the capstone a squad of clone NPCs to call and command. Server owners can switch on class mode, where players pick a ready-made class instead of building their own tree.

The skills themselves live in other addons' code: the weapon base, stamina, inventory, jetpack, medical and others ask this addon "does this player have X?" or "what multiplier applies now?". Without rhylib_skills installed, nothing is gated: every fire mode, scope and item works for everyone.

## The trees

| Tab (category) | Specialisations (end branches) | Notes |
|---|---|---|
| Trooper | Assault (Vanguard, Spearhead), Autorifleman | |
| Support | Marksman, Heavy | |
| Officer | Pistol, Commander | Mark target is shared; command orders (pick one) in both; Commander skills need `commandRank`. Adaptable borrows one skill of tier 4 or lower from elsewhere. |
| Specialist | Airborne, Field technician (Demolitions, Sapper) | Field technician only shares the page. |
| Medic | Combat medic, Chemist | Medic jobs only. |
| Shock Trooper | — | Military police only. |

Rules (`K.CanLearn`): one category at a time (`onePath`), one specialisation per category, one end branch per specialisation, a skill's `needs` first, one command order, enough points.

## Requirements

- Required: `rhylib_core`, `rhylib_menus` (learning skills happens only on the Skills page).
- Recommended (each adds or enables part of it):
  - `rhylib_weapons` / `rhylib_republic`: the guns and grenades most skills act on.
  - `rhylib_inventory`: the command comlink, the cell rack and ammo belt, carry limits, items that need a skill (droid popper, ammo pack).
  - `rhylib_stamina`, `rhylib_jetpack`: Momentum, Second wind, Steady the line, Airborne jetpack upgrades.
  - `rhylib_roster`: rank checks (command orders need LT). Without it rank checks pass.
  - `rhylib_radio`: squads (marks are shared with your squad; squad auras; Chain of command).
  - `rhylib_droids`: Reinforcements, squad orders, Suppression.
  - `rhylib_medical`, `rhylib_mp`: the Medic and Shock Trooper trees, Field triage, Under fire.
  - `rhylib_gear`: marking through macrobinoculars, the sun visor auto spot.
  - `rhylib_eod`: the Field technician path.
- No Workshop content of its own (the comlink uses HL2 models).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_skills.lua` | shared | Loads the module through `Rhylib.LoadModule` (needs rhylib_core). |
| `lua/rhylib/skills/sh_00_config.lua` | shared | The tree: `K.CATEGORIES`, `K.NODES`, the learning rules (`K.CanLearn`, `K.CanUnlearn`, `K.Excluded`), `K.Has` / `K.Set`, Adaptable, points. |
| `lua/rhylib/skills/sh_10_effects.lua` | shared | Effect numbers (config) and the effect functions other addons call; Light kit and Sidestep movement. |
| `lua/rhylib/skills/sh_20_command.lua` | shared | Command orders (`K.ORDERS`), order state and timing, Hold fast / Press forward movement, squad wheel options, hand-signal words. |
| `lua/rhylib/skills/sh_30_class.lua` | shared | Class mode: `K.CLASSES`, presets, who may play which class. |
| `lua/rhylib/skills/sv_10_skills.lua` | server | Saving, learning, undo, reset, `K.SetSkills`, damage dealt (`K.DamageMult`) and taken, Momentum, Combat drop, Death from above, Suppression, extra inventory grids. |
| `lua/rhylib/skills/sv_20_command.lua` | server | Giving orders (`K.IssueOrder`), Field triage healing, Reinforcements, squad orders, handing out the comlink. |
| `lua/rhylib/skills/sv_30_mark.lua` | server | Mark target, Tactical visor locks and spots, Called shot, Priority target, the Commander's squad auras. |
| `lua/rhylib/skills/sv_40_class.lua` | server | Class mode on/off, picks, applying and leaving classes. |
| `lua/rhylib/skills/cl_10_menu.lua` | client | The Skills page (tree drawing, layout, side panel); chat notes. |
| `lua/rhylib/skills/cl_20_command.lua` | client | Order HUD (tint, edge glow, timer bar), squad wheel, hiding hand-signal chat lines. |
| `lua/rhylib/skills/cl_30_mark.lua` | client | Q to mark, drawing marks (diamonds) and rings. |
| `lua/rhylib/skills/cl_40_class.lua` | client | The Class page. |
| `lua/weapons/rhylib_commlink.lua` | shared | The command comlink SWEP (LMB order, RMB reinforcements, reach ring, HUD). |

## For server owners

### Settings

Config module `"skills"`. Change them in game on the Staff > Server settings page, or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("skills", "freePoints", false)   -- live server: points count
Rhylib.Config.Set("skills", "startPoints", 24)
Rhylib.Config.Set("skills", "commandRank", "SGT")  -- orders from Sergeant up
```

The effects read their numbers when they run, so changes apply straight away.

Multipliers: 1 = no change; below 1 means less (spread, kick, time, damage taken), above 1 more. Distances are in units (about 52 to a metre).

**Rules and points**

| Key | Default | What it does |
|---|---|---|
| `freePoints` | `true` | Every skill is free and can be reset any time (testing) |
| `startPoints` | `24` | Skill points everyone has while freePoints is off (every path costs 24, so any one can be finished) |
| `commandRank` | `"LT"` | Lowest rank (roster prefix) that can learn and issue command orders |
| `onePath` | `true` | Only one category (Trooper, Support, Officer, Airborne, Medic, Shock Trooper) at a time |

**Skill effects**

| Key | Default | What it does |
|---|---|---|
| `quickHandsMult` | `0.9` | Quick hands: magazine reload time multiplier |
| `runGunSpread` | `1.6` | Run and gun: spread multiplier while sprinting and firing |
| `pointBlankMult` | `1.25` | Point blank: damage multiplier up close |
| `pointBlankNear` | `420` | Point blank: full bonus within this many units (420 = 8 m) |
| `pointBlankFar` | `790` | Point blank: no bonus beyond this many units (790 = 15 m) |
| `lightKitSpeed` | `1.05` | Light kit: speed multiplier |
| `lightKitLoad` | `0.6` | Light kit: only under this share of your carry limit |
| `momentumTime` | `4` | Momentum: seconds of free sprinting after a kill |
| `momentumReload` | `0.75` | Momentum: next reload time multiplier |
| `extMagBonus` | `10` | Extended mags: extra rounds in a medium magazine |
| `effCellsMult` | `1.25` | Efficient cells: power cell shots multiplier |
| `loadBearerCarry` | `6` | Load bearer: extra carry limit (kg) |
| `loadBearerPenalty` | `0.75` | Load bearer: weight stamina penalty multiplier |
| `cellRack` | `{ 5, 2 }` | Load bearer: cell rack size in inventory cells (cells are 1x2, so 5x2 = 5 cells) |
| `gunRunnerSpin` | `0.9` | Gun runner: walk speed while the Z-6 spins (normally 0.6) |
| `gunRunnerWeight` | `0.5` | Gun runner: Z-6 weight multiplier |
| `steadySpread` | `0.45` | Steady barrels: Z-6 spread multiplier |
| `steadyRecoil` | `0.45` | Steady barrels: Z-6 view kick multiplier |
| `rapidFireRPM` | `600` | Rapid fire: DC-15S fire rate |
| `pistolSpread` | `0.8` | Pistol proficiency: DC-17 spread multiplier |
| `steadyGripRecoil` | `0.5` | Steady grip: pistol view kick multiplier (DC-17, and the DC-15S in Sidearm mode) |
| `dualRate` | `1` | Dual DC-17: fire rate multiplier (the gain is the second magazine) |
| `critChance` | `0.1` | Critical hits: chance per hit |
| `critMult` | `1.5` | Critical hits: damage multiplier |
| `lightRoundsChance` | `0.15` | Light rounds: crit chance with a small magazine loaded (doesn't stack with Critical hits) |
| `quickDrawMult` | `0.6` | Quick draw: draw time multiplier |
| `speedLoaderMult` | `0.7` | Speed loader: pistol reload time multiplier |
| `markTime` | `15` | Mark target: seconds a mark lasts |
| `markRange` | `8000` | Mark target: reach (units) |
| `markCooldown` | `1` | Mark target: seconds between marks |
| `markMax` | `5` | Mark target: most enemies one Q marks through macrobinoculars / a rangefinder |
| `markOpticsCone` | `10` | Mark target: widest cone (degrees from the middle) searched through optics |
| `visorSpotEvery` | `5` | Mark target + sun visor down: seconds between automatic spots |
| `visorSpotCone` | `30` | Mark target + sun visor down: cone (degrees from the middle) the automatic spot searches |
| `visorSpotTime` | `6` | Mark target + sun visor down: seconds an automatic spot lasts |
| `markAimCone` | `3` | Mark target: without optics, the nearest enemy within this many degrees of the crosshair counts |
| `markLockDamage` | `1.15` | Tactical visor: damage multiplier for the marker's squad mates (not Marksmen) on a locked target |
| `markLockTime` | `25` | Tactical visor: seconds a lock (a Q mark) lasts |
| `squadSkillRange` | `600` | Field logistics / Steady the line: reach around the commander (units, 600 = about 15 m) |
| `logiReload` | `0.85` | Field logistics: reload time multiplier near the commander |
| `lineKick` | `0.85` | Steady the line: view kick multiplier near the commander |
| `lineRegen` | `1.25` | Steady the line: stamina refill multiplier near the commander |
| `rifleDrillSpread` | `0.8` | Rifle drill: aimed spread multiplier (rifles and carbines) |
| `vetRifle` | `0.9` | Combat veteran: rifle spread, kick and reload time multiplier |
| `vetCarbineDamage` | `1.08` | Combat veteran: carbine damage multiplier |
| `vetZ6Resist` | `0.9` | Combat veteran: damage taken multiplier with the Z-6 in hand |
| `markVisorCone` | `10` | Mark target: Q with the sun visor down locks the ringed enemy if it's within this many degrees of the aim |
| `undoWindow` | `120` | Seconds after learning a skill in which right-click can undo it (any time while reset is allowed) |
| `rushDamage` | `1.25` | Battle rush: damage multiplier |
| `rushTime` | `5` | Battle rush: seconds it lasts after the first hit |
| `rushCooldown` | `60` | Battle rush: seconds before it can trigger again |
| `grenadeRange` | `1.2` | Grenadier: throw distance multiplier |
| `grenadeDamage` | `1.3` | Grenadier: frag damage multiplier |
| `grenadeRadius` | `1.1` | Grenadier: blast radius multiplier (frag, EMP, flash) |
| `sidearmDamage` | `1.06` | Carbine sidearm: DC-15S damage multiplier in Sidearm mode |
| `airborneFuel` | `15` | Airborne: jetpack seconds of thrust with any Airborne skill (others: jetpack fuelTime) |
| `fallMult` | `0.5` | Hard landings: fall damage multiplier |
| `tankMult` | `1.4` | Extended tanks: fuel time and refill speed multiplier |
| `springJump` | `1.2` | Hard landings: jump power multiplier |
| `hoverFuelMult` | `0.5` | Hover: jetpack fuel burn multiplier while hovering |
| `hoverSpread` | `0.75` | Hover: spread multiplier while hovering |
| `hoverRecoil` | `0.75` | Hover: view kick multiplier while hovering |
| `afterburnerMult` | `1.25` | Afterburner: jetpack climb, steering and top speed multiplier |
| `combatDropAir` | `7` | Combat drop: seconds of jetpack flight needed before a landing counts |
| `combatDropTime` | `5` | Combat drop: seconds of reduced damage after landing |
| `combatDropMult` | `0.5` | Combat drop: damage multiplier while it lasts |
| `sidestepSpeed` | `340` | Sidestep: dash speed (units/s) |
| `sidestepTime` | `0.18` | Sidestep: seconds at full dash speed, then it slows to sidestepCarry |
| `sidestepCarry` | `60` | Sidestep: sideways speed kept after the burst (units/s) |
| `sidestepCooldown` | `2.5` | Sidestep: seconds between dashes |
| `sidestepStamina` | `25` | Sidestep: stamina per dash |
| `lightMagBonus` | `20` | Light mags: extra rounds in a small magazine |
| `blastMult` | `0.7` | Blast hardened: explosion damage multiplier |
| `airMult` | `0.8` | Aerial stability: damage multiplier while off the ground |
| `slamSpeed` | `500` | Death from above: landing speed needed (units/s) |
| `slamRadius` | `220` | Death from above: radius (units) |
| `slamDamage` | `60` | Death from above: damage at the centre (more for faster landings) |
| `underFireMult` | `0.8` | Under fire: damage multiplier while reviving or treating |
| `stanceSpread` | `0.8` | Steady stance: spread multiplier while crouched |
| `steadyAimSpread` | `0.75` | Steady aim: spread multiplier while aiming |
| `headhunterMult` | `1.25` | Headhunter: headshot damage multiplier |
| `boltDrillsRate` | `1.2` | Bolt drills: DC-15X fire rate multiplier |
| `longGunWeight` | `0.75` | Long gun: DC-15X weight multiplier |
| `carbineSpread` | `0.7` | Carbine discipline: DC-15S spread multiplier while aiming |
| `carbineRecoil` | `0.85` | Carbine discipline: DC-15S view kick multiplier |
| `carbineDraw` | `0.7` | Carbine discipline: DC-15S draw time multiplier |
| `calledShotTime` | `6` | Called shot: seconds a headshot mark lasts |
| `priorityMult` | `1.2` | Priority target: damage multiplier on heavy droids and marked targets |
| `rhythmStep` | `0.05` | Precision rhythm: extra damage per DC-15S hit in a row |
| `rhythmMax` | `2` | Precision rhythm: most steps (2 x 0.05 = +10%); only while aiming |
| `overchargeDamage` | `1.3` | Overcharge: DC-15A damage multiplier |
| `overchargeDrain` | `4` | Overcharge: power cell drain multiplier |
| `overchargeKick` | `1.15` | Overcharge: view kick multiplier |
| `sustainKick` | `0.6` | Sustained fire: view kick multiplier once fully settled |
| `sustainRamp` | `1.5` | Sustained fire: seconds of continuous fire to settle fully (eased) |
| `sustainStep` | `0.02` | Sustained fire: extra damage per DC-15A hit in a row on one target |
| `sustainMax` | `5` | Sustained fire: most steps (5 x 0.02 = +10%) |
| `sustainWindow` | `0.4` | Sustained fire: seconds between hits to keep the streak |
| `rhythmWindow` | `1.5` | Precision rhythm: seconds between hits to keep the streak |
| `firstShotWait` | `3` | First shot: seconds without firing before it's ready |
| `firstShotMult` | `1.5` | First shot: damage multiplier with the DC-15X |
| `firstShotOther` | `1.3` | First shot: damage multiplier with other guns |
| `firstShotSpread` | `0.05` | First shot: spread multiplier |
| `reinforcedHealth` | `25` | Reinforced: extra max health |
| `plantedMult` | `0.5` | Planted: Z-6 spread and kick multiplier while crouched |
| `ammoBelt` | `{ 5, 1 }` | Ammo belt: size in inventory cells |
| `shotgunDamage` | `1.3` | Shotgun drills: DP-24 pellet damage multiplier |
| `shotgunCone` | `0.8` | Shotgun drills: DP-24 pellet cone multiplier |
| `sidearmWeight` | `0.5` | Shotgun drills: weight multiplier for guns 4 cells long or shorter |
| `juggernautMult` | `0.85` | Juggernaut: damage multiplier |
| `suppressRadius` | `300` | Suppression: droids this close to one you hit with the Z-6 aim worse (units) |
| `suppressMult` | `1.8` | Suppression: droid aim cone multiplier |
| `suppressTime` | `3` | Suppression: seconds it lasts |
| `holdLineMult` | `0.8` | Hold the line: damage multiplier with the shield up and another MP near |
| `holdLineRange` | `200` | Hold the line: how close the other MP must be (units) |
| `bashDamage` | `30` | Shield bash: damage to droids |
| `searchMult` | `1.2` | Thorough search: search roll multiplier |
| `eodBlastMult` | `0.7` | EOD Blast hardened: explosion damage multiplier |
| `eodPackWeight` | `0.5` | EOD Explosives pack: weight multiplier of grenades, charges, rockets and mines |
| `eodPackStack` | `1` | EOD Explosives pack: extra per stack of grenades, charges and mines |
| `eodDemoDamage` | `1.25` | EOD Demolitions: thermal detonator and HE charge damage multiplier |
| `eodDemoRadius` | `1.15` | EOD Demolitions: thermal detonator and HE charge blast radius multiplier |
| `eodAntiArmour` | `1.25` | EOD Anti-armour: explosive damage multiplier against B2s, heavy and commander droids |

**Command orders, Reinforcements and the squad wheel**

| Key | Default | What it does |
|---|---|---|
| `commandRadius` | `380` | Command orders: radius (units, like a droid popper) |
| `commandTime` | `6` | Command orders: seconds they last |
| `commandCooldown` | `360` | Command orders: seconds before an officer can give the next one |
| `windRegen` | `4` | Second wind: stamina refill speed multiplier |
| `triageHeal` | `8` | Field triage: health per second |
| `triageRevive` | `0.25` | Field triage: downed players in reach get up with this share of their max health |
| `focusDamage` | `1.2` | Focus fire: damage multiplier |
| `focusRecoil` | `0.5` | Focus fire: view kick multiplier |
| `pressSprint` | `1.2` | Press forward: sprint speed multiplier |
| `presenceMult` | `1.5` | Command presence: order radius multiplier |
| `seasonedCooldown` | `240` | Seasoned command: order cooldown (seconds) |
| `standingTime` | `10` | Standing orders: seconds orders last |
| `reinfCooldown` | `900` | Reinforcements (Commander capstone): seconds between calls |
| `reinfLife` | `600` | Reinforcements: seconds the squad stays before pulling out (0 = until killed) |
| `reinfSquad` | `{ "ct_trooper", "ct_medic", "ct_rifleman", "ct_heavy" }` | Reinforcements: the clone kinds that come (ct_trooper, ct_rifleman, ct_heavy, ct_medic, ct_commander) |
| `squadSignals` | `{ follow = "/group", regroup = "/come", hold = "/stop", move = "/advance", aggroUp = "/advance", aggroDown = "/group", dismiss = "" }` | Squad wheel: hand-signal chat command each order runs (for a hand-signal animation addon; "" = none) |
| `squadSignalMode` | `"hooks"` | Squad wheel: how signals reach the animation addon: hooks (PlayerSay hooks only, nothing in chat), gamemode (also the gamemode's chat, e.g. DarkRP chat commands), say (a real chat line) |

rhylib_weapons also registers two keys in this module for the ammo pack: `ammoPackPool` (300, rounds in a full pack) and `ammoPackLargeCost` (0.72, pool cost of one large-magazine round). rhylib_republic's riot shield reads `bashDamage`; rhylib_mp's search reads `searchMult`.

Before opening a live server, switch `freePoints` off: while it's on every skill is free and anyone can reset at any time.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_skills_reset [name]` | permission `rhylib.skills.admin` (default: admin) | Clears a player's skills (yours with no name; a part of the name matches). Takes them out of a class first. |
| `rhylib_classmode [0\|1]` | `rhylib.skills.admin` | Class mode on (1) or off (0); no argument toggles. Staff also get a "Class mode" button on the Skills page. |

Players reset their own tree with the "Reset skills" button: always while `freePoints` is on, otherwise only if a `Rhylib.CanResetSkills` hook returns true. Undo (right-click a learned skill) works for `undoWindow` seconds after learning it, or any time while `freePoints` is on.

### Class mode

Optional. When staff switch it on, a Class page appears under Character > Skills. Players can play a ready-made class (every skill of one specialisation and branch, plus a command order of their choice for the officer classes) instead of their own tree. Their own tree is kept in the database and comes back when they leave the class or class mode goes off. Each time class mode is switched on, everyone gets one pick plus one change. Medic and Shock Trooper classes still need those jobs; the Commander class needs `commandRank`.

### Placing things / saving

Nothing is placed. The command comlink (`rhylib_commlink`, admin-only in the spawn menu) is handed out as job gear to anyone with a command order skill, at spawn and when they learn one.

Saved per player in the database (see Saved data). Order and Reinforcements cooldowns are kept in memory only (they survive a rejoin, not a map change).

## For players (short)

- Skills page: pause menu > Character > Skills. Click a skill to learn it, right-click a learned one to undo it (shortly after learning). Hover to read what it does and what it needs.
- E + R: switch fire mode (skill modes like Full auto, Overcharge, Sidearm, Dual DC-17 appear once learned).
- Q: Mark target (Officer). Through macrobinoculars or a rangefinder it marks up to 5 enemies.
- Sidestep (Pistol officer): Sprint + left/right/back + Jump, or Alt + a direction.
- Command comlink: left click gives your order, right click calls reinforcements (capstone), hold R opens the squad wheel.
- Hand-signal commands (/advance, /group, ...), typed or from the squad wheel, never show in chat.

## For developers

All functions are on `Rhylib.Skills` (called `K` in the code). Always guard calls so your addon still works without rhylib_skills:

```lua
local K = Rhylib.Skills
if K and K.Has and K.Has(ply, "momentum") then ... end
```

### Public functions

Tree and rules (shared, `sh_00_config.lua`):

| Function | Returns | What it does |
|---|---|---|
| `K.Has(ply, id)` | bool | Has the player learned skill `id`? Cheap (parsed once per change), works on both realms and in predicted code. |
| `K.Set(ply)` | table | `{ [id] = true }` of learned skills. Read only. |
| `K.Cfg(key)` | value | A `skills` config value. |
| `K.CanLearn(ply, set, id)` | ok, reason | All learning rules. `set` is usually `K.Set(ply)`. |
| `K.CanUnlearn(ply, set, id)` | ok, reason | Would removing it leave every other skill valid? |
| `K.Excluded(ply, set, id)` | reason or nil | Ruled out by a choice already made (path, spec, branch, one-of group). |
| `K.UndoAllowed(learnedAt, id)` | bool | Inside the undo window (or `freePoints`). |
| `K.Points(ply)` / `K.Spent(set)` | number | Points available / spent. |
| `K.RankOk(ply, cfgKey)` | ok, reason | Rank check against a config key holding a roster rank prefix. |
| `K.Commitments(set)` | cats, specs, branches | What the set is committed to (borrowed skills excluded). |
| `K.Borrowed(set, id)` | bool | Is this skill borrowed through Adaptable? |
| `K.IsCommanderSpec(ply)`, `K.HasReinforcements(ply)`, `K.CanCommandSquad(ply)` | bool | Officer checks used by the comlink and rhylib_droids. |

Server (`sv_10_skills.lua`, `sv_20_command.lua`, `sv_30_mark.lua`, `sv_40_class.lua`):

| Function | What it does |
|---|---|
| `K.SetSkills(ply, set, noSave)` | Give exactly this set (no rule checks), save it, refresh grids/items/health/jump, fire `Rhylib.SkillsChanged`. |
| `K.Stored(ply)` | The server's copy of the player's set (loaded from Data on first use). |
| `K.Note(ply, text, bad)` | A "[Skills]" chat line for one player. |
| `K.IssueOrder(ply)` → ok, reason | Give the officer's order (what the comlink's left click does). |
| `K.CallReinforcements(ply)` → ok, count or reason | Call the clone squad (right click). |
| `K.GiveCommlink(ply)` | Hand out the comlink if they have an order skill. |
| `K.PlaceMarks(ply, list, secs, replace, quiet, lock)` | Mark entities for a player and their radio squad (at most 7 per call). |
| `K.SquadMembers(ply)` | The player's radio squad, them included. |
| `K.SetClassMode(on)`, `K.LeaveClass(ply, quiet)` | Class mode on/off; back to the own tree. |

Shared helpers: `K.GunClass(wep)` (training copies count as the real gun), `K.ItemGun(itemId)`, `K.IsRifle(wep)`, `K.IsCarbine(wep)`, `K.Order(ply)`, `K.OrderIs(ply, key)`, `K.OrderOf(ply)`, `K.OrderLeft(ply)`, `K.OrderCooldown(ply)`, `K.ReinfCooldown(ply)`, `K.ClassOf(ply)`, `K.ClassMode()`, `K.ClassSet(cls, orderId)`, `K.ClassAllowed(ply, cls)`, `K.IsSignalText(text)`. Client: `K.DrawGlyph(name, x, y, size, col, bg)` draws a skill icon.

### Skill effect functions and who calls them

Every function another addon asks. All are shared unless marked; each caller checks that the function exists first.

| Function | Returns | Skills behind it | Called by |
|---|---|---|---|
| `K.Has(ply, id)` | bool | any | rhylib_medical (`Med.Skill`: the Medic tree; Hard landings in fractures; Shock Assault torso stamina; Recovery timer), rhylib_mp (Escort drills movement, Thorough search with `K.Cfg("searchMult")`), rhylib_weapons (ammo pack `RequiresSkill`, Phalanx in `sh_60_shield`), rhylib_republic (grenade base: Breaching, `RequiresSkill`; riot shield `AimFireSkill` / `BashSkill`), rhylib_inventory (fallback for `CarrySkill`), rhylib_eod (armour kit `RequiresSkill`, `E.Skill`, `E.IsBombSquad` via `K.NODES`), rhylib_droids |
| `K.ModeAllowed(ply, wep, mode)` | bool | `SWEP.SkillModes` (Full auto, Overcharge, Sidearm, Dual DC-17; Combat veteran also opens Full auto) | rhylib_weapons `rhylib_base` (`ModeAllowedBase`) |
| `K.ScopeAllowed(ply, wep)` | bool | `SWEP.ScopeSkill` (Long gun) | rhylib_weapons `rhylib_base` |
| `K.RunAndGun(ply, wep)` | bool | Run and gun | rhylib_weapons `rhylib_base` (`UpdateLowered`) |
| `K.SpreadMult(ply, wep)` | number | Run and gun, Steady barrels, Pistol proficiency, Steady stance, Planted, Steady aim, Carbine discipline, Rifle drill, Combat veteran, Hover, First shot | rhylib_weapons `sh_10_spread` (`Spread.SkillMult`) |
| `K.RecoilMult(ply, wep)` | number | Steady grip, Focus fire, Carbine discipline, Hover, Combat veteran, Steady the line, Overcharge, Sustained fire, Steady barrels, Planted | rhylib_weapons `cl_50_recoil`, `cl_70_stats` |
| `K.FireRateMult(ply, wep, mode)` | number | Bolt drills, Rapid fire, Dual DC-17 | rhylib_weapons `rhylib_base` |
| `K.ReloadMult(ply, wep, cell)` | number | Quick hands, Speed loader, Combat veteran, Field logistics, Momentum | rhylib_weapons `rhylib_base`; rhylib_republic grenade launcher |
| `K.DrawMult(ply, wep)` | number | Quick draw, Carbine discipline | rhylib_weapons `rhylib_base` |
| `K.MagBonus(ply, magId)` | number | Extended mags, Light mags | rhylib_weapons `rhylib_base` |
| `K.MagAllowed(ply, wep, magId)` | bool | `SWEP.MagSkills` (Heavy feed) | rhylib_weapons `rhylib_base`, `cl_70_stats` |
| `K.CellMult(ply)` | number | Efficient cells | rhylib_weapons `rhylib_base`, `cl_70_stats` |
| `K.CellDrainMult(ply, wep)` | number | Overcharge mode | rhylib_weapons `rhylib_base`, `cl_70_stats` |
| `K.ModeDamageMult(ply, wep)` | number | Overcharge mode | rhylib_weapons `cl_70_stats` |
| `K.ShotDamageMult(ply, wep)` | number | First shot, Overcharge | rhylib_weapons `rhylib_base` (`FireShot`) |
| `K.PelletConeMult(ply, wep)` | number | Shotgun drills | rhylib_weapons `rhylib_base` |
| `K.SpinMoveMult(ply, wep, base)` | number | Gun runner | rhylib_weapons `rhylib_base` |
| `K.FlyFire(ply, wep)` | bool | DP-23 proficiency | rhylib_weapons `rhylib_base` (`TooHeavyToFire`) |
| `K.OrderIs(ply, key)` | bool | command orders | rhylib_weapons `rhylib_base` (`NoAmmoUse`: Open up) |
| `K.DamageMult(ply, bolt, ent, tr, group)` (server) | mult, crit | Focus fire, Battle rush, Tactical visor locks, Combat veteran, Carbine sidearm, Point blank, Headhunter, Priority target, Precision rhythm, Sustained fire, Shotgun drills, Critical hits, Light rounds (and places Called shot marks) | rhylib_weapons `sv_10_bolts` |
| `K.WeightPenaltyMult(ply)` | number | Load bearer | rhylib_stamina `sh_00_config` |
| `K.FreeSprint(ply)` | bool | Momentum, Second wind | rhylib_stamina `sh_10_move` |
| `K.RegenMult(ply)` | number | Second wind, Steady the line | rhylib_stamina `sh_10_move` |
| `K.AdjustWeight(ply, state, weight, cap)` | weight, cap | Load bearer, Gun runner, Long gun, Shotgun drills, Explosives pack | rhylib_inventory `sv_10_inventory`, `cl_20_panel` |
| `K.ExtraGrids(ply)` (server) | `{ [cid] = { w, h } }` | Load bearer (cell rack), Ammo belt | rhylib_inventory `sv_10_inventory` |
| `K.CarryOk(ply, skill)` | bool | `CarrySkill` on an item (`"command"` = any order skill) | rhylib_inventory `sv_10_inventory` (`Inv.MayHold`); `K.CARRY_NAMES` for its message |
| `K.JetCfg(ply, key, value)` | value | Airborne skills, Extended tanks, Hover, Afterburner | rhylib_jetpack `sh_10_move` |
| `K.GrenadeMults(ply)` | range, dmg, radius or nil | Grenadier | rhylib_republic `rhylib_grenade_base` |
| `K.DemoMults(ply)` | dmg, radius or nil | EOD Demolitions | rhylib_republic `rhylib_grenade_base`, `rhylib_he_charge`, `rhylib_grenade_launcher` |
| `K.HasReinforcements(ply)` | bool | Reinforcements (either officer path) | rhylib_droids `sv_10_droids` (clones near a holder are boosted) |

Effects that need no call from outside are done here with hooks: damage taken (Hard landings, Blast hardened, Aerial stability, Combat drop, Juggernaut, Under fire, Hold the line, Combat veteran with the Z-6, Shock Assault, Hold fast, Press forward), Anti-armour, Suppression, Momentum, Battle rush, Death from above, Reinforced (max health), Hard landings (jump power), Light kit and Sidestep (movement), the Explosives pack stack size and the Dual DC-17 carry limit.

### Hooks

Fired by this addon:

- `Rhylib.SkillsChanged(ply)` (server): after any change to a player's set (learn, undo, reset, class). Return value ignored.
- `Rhylib.CanResetSkills(ply)` (server): return `true` to allow a reset (and a late undo) while `freePoints` is off.
- `Rhylib.SkillPoints(ply)` (both realms, from `K.Points`): return a number to set the player's total points. Add it on both realms, or the menu and the server disagree.
- `PlayerSay` hooks (server): the squad wheel runs hand-signal commands through them (see `squadSignalMode`).

Listened to: `Rhylib.MarkKey` (client, from rhylib_menus: Q), `Rhylib.PlayerDowned` (Momentum; orders end), `Rhylib.CanKnockDown` (returns false for EOD Blast hardened and Press forward), `Rhylib.ItemStack` (Explosives pack), `Rhylib.CarryLimit` (two DC-17s with Dual DC-17), `EntityTakeDamage` (95 resist, 90 anti-armour, -1200 Hold fast, 0 suppression), `OnNPCKilled` / `PlayerDeath` (Momentum, marks), `OnPlayerHitGround`, `PlayerTick`, `SetupMove` (-200 Light kit, -199 Press forward, -160 Hold fast, -150 Sidestep), `PlayerBindPress` (squad wheel), `OnPlayerChat` (hides hand signals).

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `skills.learn` | client → server | node index (UInt 8) | Learn a skill (checked with `K.CanLearn`). |
| `skills.unlearn` | client → server | node index (UInt 8) | Right-click undo. |
| `skills.reset` | client → server | — | Reset your tree. |
| `skills.note` | server → client | bad (bool), text | A "[Skills]" chat line. |
| `skills.order` | server → clients reached | order index (UInt 3), issuer (entity) | Sound and "who gave it" for the order bar. |
| `skills.squad` | client → server | option index (UInt 3, `K.SQUAD_OPS`) | Squad wheel order to clones. |
| `skills.markreq` | client → server | optics (bool), fov ×10 (UInt 10), visor pick (bool) + entity index (UInt 13) | Q pressed. |
| `skills.mark` | server → marker + squad | marker (UInt 13), replace, quiet, lock (bools), seconds (UInt 6), count (UInt 3), targets (UInt 13 each) | Marks to draw. |
| `skills.classpick` | client → server | class index (UInt 4), order index (UInt 3) | Play a class. |
| `skills.classleave` | client → server | — | Back to your own tree. |
| `skills.classmode` | client → server | on (bool) | Staff switch (permission checked). |

State on entities: NW2String `rhylib_skills` (",id,id,"), NW2Int `rhylib_order`, NW2Float `rhylib_orderEnd` / `rhylib_orderLen` / `rhylib_orderCd` / `rhylib_reinfCd` / `rhylib_afflMute` / `rhylib_momentum` / `rhylib_rush`, NW2Bool `rhylib_steadyLine`, NW2String `rhylib_class`, NW2Int `rhylib_classPicks`, Global2Bool `rhylib_classMode`, Global2Int `rhylib_classEpoch`, player DTFloat 24 and 25 (Sidestep).

### Saved data

Module `"skills"` in `Rhylib.Data`:

- `"s" .. SteamID64` = `{ n = { ids } }`: the player's own tree. Old ids are renamed on load (`burst_fire` → `rapid_fire`, `thruster_dodge` → `combat_drop`); unknown ids are dropped.
- `"c" .. SteamID64` = `{ cls, order, epoch, picks }`: their class this round of class mode (ignored once the epoch changes).
- `"classmode"` = `{ on, epoch }`.

### Examples

**Adding a skill node.** Add an entry to `K.NODES` in `sh_00_config.lua` (shared, so both realms get the same list and indexes). It shows on its category's tab at its tier, in its spec's column:

```lua
-- in K.NODES, under the Trooper section
{ id = "tight_grip", cat = "trooper", spec = "assault", tier = 4, cost = 2, name = "Tight grip",
  icon = "aim",                                   -- a glyph from cl_10_menu.lua GLYPHS
  desc = "10% less kick with every gun.",
  needs = { "droid_popper" } },                   -- or needsGroups = { { "a" }, { "b" } } for "one of"
```

Then make it do something. Inside this addon, add it to the matching effect function, with a config number:

```lua
-- sh_10_effects.lua
reg("tightGripRecoil", 0.9, "Tight grip: view kick multiplier")
-- in K.RecoilMult, before `return m`:
if K.Has(ply, "tight_grip") then m = m * cfg("tightGripRecoil") end
```

Class mode picks the new node up by itself (every node of the class's category/spec/branch). Keep `K.NODES` at 255 entries or fewer (the index is sent in 8 bits).

**Making another addon react to a skill (K.Has).** Guard the call so your addon works without rhylib_skills. For a SWEP, a field is enough: `SWEP.CarrySkill = "my_skill"` makes rhylib_inventory refuse the item to anyone without it. In code:

```lua
-- your addon, server: +10 armour at spawn for players with Load bearer
hook.Add("PlayerSpawn", "myaddon.loadbearer", function(ply)
    timer.Simple(0, function()
        local K = Rhylib.Skills
        if IsValid(ply) and K and K.Has and K.Has(ply, "load_bearer") then
            ply:SetArmor(ply:Armor() + 10)
        end
    end)
end)

-- and react when someone's skills change (learn, undo, reset, class)
Rhylib.Hook.Add("Rhylib.SkillsChanged", "myaddon.skills", function(ply)
    -- re-check whatever you gave them
end)
```

`K.Has` reads a networked string, so it works the same on the client (HUD, prediction).

**Points from rank instead of a flat number** (both realms, in a shared file of your own addon):

```lua
Rhylib.Hook.Add("Rhylib.SkillPoints", "myaddon.points", function(ply)
    return 12 + ply:GetNW2Int("rhylib_rank", 0) * 2
end)
```

**Allow resets with a token item, server side:**

```lua
Rhylib.Hook.Add("Rhylib.CanResetSkills", "myaddon.reset", function(ply)
    if ply.myResetToken then ply.myResetToken = nil return true end
end)
```

## Notes and gotchas

- `freePoints` is on by default (testing): everything is free and resettable. Switch it off on a live server.
- The client never decides anything: learn, undo, reset, orders, marks and class picks are all checked again on the server.
- Effects run in predicted code (spread, kick, fire rate, movement), so they only read shared state (NW2 vars, the skill string). Orders are NW2 too, so a short misprediction at an order's start or end is expected.
- `K.ReloadMult` uses up the Momentum reload bonus when called; call it once per reload.
- A Q mark sends at most 7 targets (`markMax` above 7 is cut to 7).
- Order and Reinforcements cooldowns survive a rejoin but not a map change.
- Class presets aren't saved over the player's own tree: leaving the class or switching class mode off brings it back.
- Medic skills only work in medic jobs (`Med.Skill` checks the job too); Shock Trooper skills only with the CG riot shield.
- Old saves aren't re-checked against changed `needs` (a reset re-learns them under the new rules); `K.Stored` only drops renamed, unknown, redundant and mixed officer-spec skills.
