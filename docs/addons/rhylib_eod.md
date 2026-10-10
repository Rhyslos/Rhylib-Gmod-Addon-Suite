# rhylib_eod: Bombs, mines and defusal

Game masters place enemy bombs and minefields; players defuse them. Each bomb is a small simulated circuit: batteries, a detonator, a timer or a remote receiver, safeguards and optional modules, joined by wires in random colours. Players learn the rules, not one answer: they inspect the bomb, probe each wire to find out what it does, then cut wires and place jumpers in a safe order. A wrong move sets it off (a large bomb kills everyone within about 40 m). Mines are half buried and hard to see; stepping on one clicks, and the player must hold still while someone digs it out and pins the fuse. The addon also adds the tools for the job: the EOD kit, an interference device that jams remote signals (and your own radio), a mine scanner, training bombs and mines that never hurt anyone, Republic mines that only droids set off, an armour repair kit, and a bomb manual on the datapad. Nothing in the skill tree makes defusing easier: the bomb is the same for everyone.

## Requirements

- Required: rhylib_core, rhylib_inventory (EOD kit, interference device and cells as items), rhylib_menus (every window).
- Recommended: rhylib_radio (the device jams radios), rhylib_republic (droid popper EMP, the HE charge for Render safe, the grenade base of the Republic mine), rhylib_skills (manual, Republic mines, Minefield, Signal blackout, Armour repair), rhylib_datapad (manual tab, "Call the bomb squad"), rhylib_toolgun (placing bombs and mines), rhylib_medical (gas and virus clouds make people ill; without it they do plain damage), rhylib_droids (droids and clones in the blast, droid-only Republic mines, Signal blackout).
- Models (Workshop content the server must list as required items): `models/props/starwars/weapons/seismic_charge.mdl` (small bomb), `models/cire992/props2/gethbomb01.mdl` (large bomb), `models/props/starwars/weapons/ap_mine.mdl` (AP mine, Republic mine), `models/props/starwars/weapons/lasertrap.mdl` (LAP mine). Missing models fall back to HL2 ones (console box, power box, hopper mine).

Without rhylib_inventory everyone counts as having a kit. Without rhylib_menus no window opens (a chat line says so).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_eod.lua` | shared | Loads the module. |
| `lua/rhylib/eod/sh_00_config.lua` | shared | Config, module / tier / chip / colour / cause tables, items, permission, toolgun entries, shared maths (tilt, needles, scanner direction, cell life), the mine "click" freeze. |
| `lua/rhylib/eod/sv_10_bomb.lua` | server | Rolling a bomb, building its board, the circuit rules, what the window may see, the `eod.act` actions. |
| `lua/rhylib/eod/sv_20_world.lua` | server | 0.2 s world timer (motion sensors, jamming, timers, gas leaks, tilt, torch), detonation, gas clouds, remote signals, EMP, interference devices, GM window, training bomb setup. |
| `lua/rhylib/eod/sv_30_mines.lua` | server | Placing mines, pressing, chains, defusing (dig, pin, lift), scanner marks, training mine setup. |
| `lua/rhylib/eod/sv_35_repmines.lua` | server | Republic mines: planting, limit, droid trigger, droid-only blast, pick-up. |
| `lua/rhylib/eod/cl_10_window.lua` | client | Defusal window (board, tools, modules, log), fail / done overlay, gas smoke, far rumble, aim hint. |
| `lua/rhylib/eod/cl_20_gm.lua` | client | GM window: answers and controls. |
| `lua/rhylib/eod/cl_30_device.lua` | client | Interference device window and the inventory "Place" option. |
| `lua/rhylib/eod/cl_40_manual.lua` | client | Bomb manual datapad tab. |
| `lua/rhylib/eod/cl_50_mines.lua` | client | Mine window, "standing on a mine" warning, outlines and flags, mine scanner beam and HUD. |
| `lua/rhylib/eod/cl_55_repmines.lua` | client | Republic mine outlines and pick-up. |
| `lua/rhylib/eod/cl_60_training.lua` | client | Training bomb setup window. |
| `lua/entities/rhylib_eod_bomb.lua` | shared | Small bomb, and the base of the others (timer readout on top). |
| `lua/entities/rhylib_eod_bomb_simple.lua` / `_large` / `_custom` / `_training` | shared | Bomb types (only `ENT.BombType` differs; training sets `IsTrainingBomb`). |
| `lua/entities/rhylib_eod_mine.lua` | shared | AP mine, and the base of the LAP and training mines. |
| `lua/entities/rhylib_eod_mine_lap.lua` / `_training` | shared | LAP (large) mine, training mine. |
| `lua/entities/rhylib_interference_dev.lua` | shared | Placed interference device. |
| `lua/entities/rhylib_rep_mine_planted.lua` | shared | A planted Republic mine. |
| `lua/weapons/rhylib_mine_scanner.lua` | shared | Mine scanner. |
| `lua/weapons/rhylib_rep_mine.lua` | shared | Republic mine stack (needs rhylib_republic's grenade base). |
| `lua/weapons/rhylib_armor_kit.lua` | shared | Armour repair kit, plus the wheel option "Repair armour". |

## How a bomb works

Read this before changing the rules or adding to them. All of it is server side in `sv_10_bomb.lua` and `sv_20_world.lua`; the client only draws what the server sends.

### 1. Features

A bomb starts as a **feature table** `f`, from `E.Roll(kind)` (random) or a builder (GM custom bomb, training setup, checked by `E.CustomFeatures`):

| Field | Values | Meaning |
|---|---|---|
| `type` | `simple`, `small`, `large`, `custom`, `training` | Row in `E.TIERS` (name, `big`). |
| `det` | `timer`, `remote` | How it is set off. Remote bombs have a receiver and antenna; the GM's spotter sends the signal. |
| `antiJam` | bool | Remote only. Jamming it, or cutting the antenna, sets it off. |
| `motion` | `nil`, `normal`, `sensitive` | Motion sensor. |
| `lid` | bool | Lid switch: release the tab before lifting the lid. |
| `battery` | `single`, `dual`, `capacitor`, `collapse` | Power layout. |
| `sensor` | bool | Self-powered charge: it fires when the bomb loses power, unless its cell is shorted first. |
| `charge` | `he`, `gas`, `virus` | What it does when it goes off. |
| `hop` | bool | Remote only: the frequency jumps every `hopEvery` seconds. |
| `mods` | `{ [id] = true }` | Modules (see `E.MODS`). |
| `timerSecs` | number, optional | Timer length (default 150 simplified, 240 big, else 180). |

Random rolls pick modules within the tier's budget: each module costs its rank in points (small: 3 points, at most 2 modules; large: 6 points, at most 3). Simplified bombs have none. Remote-only modules are skipped on timer bombs.

### 2. Parts and wires

`buildBoard(f)` lays out **parts** on a 760 × 420 board and joins them with **wires**.

Parts (by id): `bat` and `batB` (batteries), `cap` (capacitor), `col` (collapse circuit), `aj` (anti-jam), `rx` (receiver), `tmr` (timer), `det` (detonator), `chip` (logic chip), `relay` + `load` (signal relay and dummy load), `ant` (antenna), `chg` (charge), `cell` (charge cell). Parts with `term = true` (batteries, capacitor, detonator, relay, dummy load, charge cell) have + and − terminals for jumpers.

Each wire is `{ k = kind, a = part, b = part }`, plus `armoured` (the cutters won't go through) or `sealed` (under the sealed plate). The **kind** is the wire's job. Players never see it: they see a colour, and the probe tells them what it carries.

| Kind | Joins | Probe says | Cutting it |
|---|---|---|---|
| `supply` | battery → capacitor / timer / detonator | `LIVE 9V`, `DEAD (drained)` | Boom if the collapse circuit is armed. The last supply gone = power gone (see below). |
| `feed` | capacitor → timer / detonator | `LIVE 9V`, `LIVE · CAP n%`, `DEAD · CAP n%`, `DEAD` | Boom if still powered. |
| `tmrline` | timer → detonator | `LIVE 9V · CLOCK`, `DEAD` | Boom if still powered. |
| `collapse` | collapse → battery | `LOOP 3V` | Disarms the collapse circuit. |
| `antenna` | antenna → receiver | `SIGNAL · f GHz`, `JAMMED · …`, `DEAD` | Boom if anti-jam is armed; else the receiver is dead. Armoured on relay bombs. |
| `ajmon` | anti-jam → receiver | `MON · watching receiver` | Disarms anti-jam. |
| `relay`, `trig` | receiver → relay → detonator | `RELAY …`, `TRIGGER …` | Armoured: can't be cut. |
| `sense` | battery → charge | `LIVE 9V · SENSE` | Boom if the self-powered charge is armed. |
| `det` | detonator → charge | like `feed` | Boom if the liquid charge is full, the chip isn't safe, or it is powered. Otherwise the bomb is **safe**. Sealed with the sealed compartment module. |
| `logic` | chip → detonator | `LOGIC · pulsing`, `DEAD · chip safe` | Boom unless the chip is in safe mode. |
| `tamper` | timer → charge | `LOOP 5V` | Halves the time left on a running timer. |
| `decoy` | any pair not already wired | `DEAD` | Nothing. 1 decoy, 2 on large and custom bombs. |

**Jumpers** (3 per bomb, `jumpers`): a jumper from a part's + to its own − **shorts** it; a jumper between two parts **joins** them.

| Jumper | Result |
|---|---|
| Battery shorted | Boom if the collapse circuit is armed; else that battery is drained (counts as its supply gone). |
| Capacitor shorted | Boom if a battery still feeds it; else it is empty at once. |
| Detonator shorted | Boom if powered; else nothing. |
| Charge cell shorted | The self-powered charge's sensor is dead. |
| Relay shorted | Boom. |
| Relay ↔ dummy load | The remote signal goes into the load: the receiver can't fire the bomb. |
| Relay ↔ detonator | Boom. |
| Detonator ↔ live battery or capacitor at 5%+ | Boom. |
| Anything else | Nothing (the jumper is still used up). |

**Power.** The bomb is *powered* while any supply wire is uncut and its battery not shorted, or a capacitor holds 5% or more. When the last supply goes (`powerGone`): an armed self-powered charge fires; otherwise the capacitor starts draining (`capDrain` seconds from 100% to 0) and a timer stops where it was. A timer only runs on battery power.

**Done.** Cutting the detonator line while it reads DEAD sets `st.safe`. `E.CheckDone` then waits for the gas valve to be sealed (gas / virus charges vent for `leakTime` seconds, then the cloud comes out) and the stabiliser dose (if fitted) before the bomb counts as done (readout shows SAFE).

### 3. Safeguards in the world

Every 0.2 s (`tick` in `sv_20_world.lua`), for each bomb, the first of these that applies sets it off:

1. **Anti-jam:** an active interference device covers it, it has power, anti-jam is armed and the receiver is live.
2. **Motion sensor:** a player in brush sight within `sensorRange` moves faster than walk speed × 1.15 (sensitive: the slower of slow-walk and crouch-walk × 1.15). A wideband device in range blinds it. Cloaked players, noclip and toolgun holders are ignored; there is a 4 s grace after setup.
3. **Timer** at zero. Timers start when a player (not holding the toolgun) comes within `timerWake`, or when the GM starts them.
4. **Gas leak** not sealed in time.
5. **Spotter:** the GM's delayed remote signal (`E.RemoteSignal`, which fails if jammed, dead, unpowered or safe).

Then: frequency hops, the tilt bubble (fires past radius 1; frozen while nobody has the window open), the torch on a sealed plate, and closing windows of players who walked off.

### 4. Modules

| Id | Name | Rank | What the player does | Fires when |
|---|---|---|---|---|
| `fuse` | Thermal fuse | 1 | Pause between steps. Each cut adds `heatCut`, each jumper `heatJumper`, a chip setting 10, a mount cut 20; it cools `heatCool` per second. | Heat reaches 100. |
| `stab` | Charge stabiliser | 1 | After the detonator cut, inject exactly the dose printed on the charge (0.75-5.00 ml). | Wrong dose. |
| `tilt` | Tilt switch | 2 | Keep the drifting bubble in the middle (buttons or arrow keys). Cuts and jumpers jolt it. | The bubble reaches the edge. |
| `sealed` | Sealed compartment | 2 | Hold the torch on the plate over the detonator line (`torchTime` s). The torch heats any board (`heatTorch`/s). | Heat reaches 100. |
| `relay` | Signal relay | 2 (remote only) | Jumper the relay to the dummy load. Antenna, relay and trigger wires are armoured. | Relay shorted or jumpered to the detonator. |
| `chip` | Logic chip | 3 | Read the LED's short / long blinks, set four switches from `E.CHIP_CODES`, press Enter. | Wrong switches; logic or detonator line cut before it is safe. |
| `liquid` | Liquid charge | 3 | With all power gone, open the drain while the needle is in the green band. | Drained while powered or outside the band; detonator line cut while full. |
| `fake` | Fake board | 3 | X-ray (`xrays` shots, `xrayTime` s each) to see the mount order, cut the three mounts in that order. | Wrong mount. |

### 5. Who sees what

`E.View(bomb, ply)` is all a defusal window gets: wire ends, colours and flags (cut, sealed, armoured), never the kinds. Parts and modules appear only once the lid is off. Probe readings come one at a time (`eod.read`) to the player who probed. The GM window (`gmInfo`) gets the answers: wire kinds, chip code, dose and mount order.

### 6. Adding a module

A worked outline, for a hypothetical module `press` ("Pressure plate", rank 2) that must be "set" before the detonator line can be cut:

1. **`sh_00_config.lua`:** add `{ id = "press", name = "Pressure plate", rank = 2 }` to `E.MODS` (add `remote = true` if it only makes sense on remote bombs). Random rolls, the GM custom builder, the training builder, `E.CustomFeatures` and the manual's module cards all read `E.MODS`, so it shows up everywhere at once. Add an `E.CAUSES.press = { title, what happened, manual line }` for each way it can fire.
2. **`sv_10_bomb.lua` `E.Build`:** add its state, guarded by the flag: `press = f.mods.press and { set = false } or nil`.
3. **Board (optional):** if it needs a part, `add(...)` it in `buildBoard` (keep at most 15 parts: the jumper sends part indexes in 4 bits) and any wires with `W(...)`.
4. **Rules:** either hook into an existing rule (for this example, in `cutWire`'s `det` branch: `if st.press and not st.press.set then return fail(bomb, "press") end`), or add a window action. **All 16 action ops (0-15) are in use**: a new op means widening the op field from 4 to 5 bits in both `act()` in `cl_10_window.lua` and the `eod.act` receiver. Time-based behaviour goes in the world `tick`.
5. **`E.View`:** add what the player may see, e.g. `if st.press then v.press = { set = st.press.set } end`.
6. **`E.CheckDone`:** only if it must be finished after the detonator line (like the stabiliser).
7. **Client `cl_10_window.lua`:** a section in `buildLeft` (guard it with `v.open and v.press`), and its flags in `layoutKey` so the column rebuilds when they change. Draw anything on the board in `boardPanel`'s `Paint`.
8. **GM window:** add the answer to `gmInfo` (server) and a `line(...)` in `cl_20_gm.lua`'s `build`.
9. **Manual `cl_40_manual.lua`:** steps in `MODULE_STEPS.press`, and the cause key in the "Why bombs go off" list.

### 7. Adding a wire kind or a wire rule

- New kind: a `W("kind", a, b)` line in `buildBoard`; a branch in `E.Reading` (what the probe says, unique enough for players to learn); a branch in `cutWire` (what cutting it does: `return fail(bomb, "cause")` to set it off, else set `st.cut[i] = true` and send a `msg`); a name in `KIND_NAMES` (`cl_20_gm.lua`); a row in the manual's probe readings; and, if it can be a decoy pair, nothing more (decoys pick from their own list in `buildBoard`).
- Changed rule on an existing kind: edit its branch in `cutWire` (or `shortPart` / `jumpParts` for jumpers). Use `was` (powered before this cut) rather than `powered(st)` when the rule is about the wire carrying power. Update the matching `E.CAUSES` line and the manual text.
- At most 31 wires per bomb (wire index is 5 bits).

## For server owners

### Settings

Change them in game on the Staff > Server settings page (group "Combat", "Bombs & mines (EOD)"), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("eod", "largeKill", 1500)
Rhylib.Config.Set("eod", "sensorRange", 400)
```

Config module `eod`:

| Key | Default | What it does |
|---|---|---|
| `smallRadius` | `600` | Small bomb blast radius (units). |
| `smallDamage` | `300` | Small bomb blast damage at the centre. |
| `largeRadius` | `7000` | Large bomb radius (units; ~a quarter of a big map). |
| `largeKill` | `2200` | Large bomb: inside this radius everything dies, walls or not. |
| `largeDamage` | `450` | Large bomb: damage just outside the kill radius (falls off to 0 at largeRadius; halved behind cover). |
| `gasRadius` | `550` | Gas and virus charges: cloud radius (units). ×3 on large and custom bombs. |
| `gasTime` | `25` | Gas and virus charges: seconds the cloud lasts. |
| `gasLoad` | `35` | Gas and virus charges: illness load given (rhylib_medical; simplified medical: damage instead). |
| `sensorRange` | `315` | Motion sensors: range (units, ~6 m). |
| `timerWake` | `900` | Timer bombs start counting once a player comes this close (units), unless the GM starts them. |
| `capDrain` | `15` | Capacitor: seconds to drain after the supply is cut. |
| `jumpers` | `3` | Jumper wires per bomb. |
| `xrays` | `2` | Fake board: X-ray shots per bomb. |
| `xrayTime` | `5` | Fake board: seconds the X-ray shows the mount order. |
| `inspectTime` | `2.5` | Seconds to hold for the first inspection. |
| `reach` | `130` | How close you must be to work on a bomb (units). |
| `heatCut` | `24` | Thermal fuse: heat per cut. |
| `heatJumper` | `30` | Thermal fuse: heat per jumper. |
| `heatTorch` | `26` | Torch heat per second (sealed compartment). |
| `heatCool` | `9` | Heat lost per second. |
| `torchTime` | `5` | Seconds of torching to cut the sealed plate open. |
| `leakTime` | `20` | Gas charges: seconds to seal the valve after cutting the detonator line. |
| `hopEvery` | `25` | Frequency hopping receivers: seconds between hops. |
| `popperChance` | `0.1` | Chance a droid popper's EMP fries a bomb. |
| `deviceMaxRadius` | `15` | Interference device: largest radius (metres). Values above 15 have no effect. |
| `deviceDrain` | `3840` | Interference device: one cell lasts this / radius² seconds in wideband (×4 tuned), at most 900 s (×4). |
| `modelSmall` | `models/props/starwars/weapons/seismic_charge.mdl` | Small, simplified and training bomb model (HL2 console box if missing). |
| `modelLarge` | `models/cire992/props2/gethbomb01.mdl` | Large and custom bomb model (HL2 power box if missing). |
| `modelDevice` | `models/props_lab/reciever01a.mdl` | Interference device model. |
| `apRadius` | `260` | AP mine: blast radius (units). |
| `apDamage` | `170` | AP mine: blast damage at the centre. |
| `lapRadius` | `420` | LAP mine (large AP): blast radius (units). |
| `lapDamage` | `320` | LAP mine: blast damage at the centre. |
| `apTrigger` | `26` | AP mine: how close a foot must come to press it (units). |
| `lapTrigger` | `38` | LAP mine: how close a foot must come to press it (units). |
| `mineShift` | `16` | Standing on a mine: moving further than this (units) sets it off. |
| `mineVisible` | `240` | Mines: how close you see one without a scanner (units). |
| `mineDigTime` | `3` | Mines: seconds to dig one out. |
| `mineLiftTime` | `2` | Mines: seconds to lift a pinned mine away. |
| `mineScanRange` | `700` | Mine scanner: reach of its beam (units). |
| `mineScanCone` | `22` | Mine scanner: half-angle of its beam (degrees). |
| `mineModel` | `models/props/starwars/weapons/ap_mine.mdl` | AP mine model (HL2 hopper mine if missing). Also the Republic mine. |
| `mineModelLarge` | `models/props/starwars/weapons/lasertrap.mdl` | LAP (large AP) mine model (HL2 hopper mine if missing). |
| `mineSize` | `20` | AP mine: width it is drawn at (units; the model is scaled to fit, LAP ×1.4). |
| `mineChain` | `140` | Mines: another mine within this (units) of an explosion goes off too. |
| `repDamage` | `260` | Republic mine: blast damage to droids at the centre. |
| `repRadius` | `280` | Republic mine: blast radius (units; Minefield ×repFieldRadius). |
| `repTrigger` | `45` | Republic mine: how close a droid must come to set it off (units). |
| `repLimit` | `3` | Republic mines: how many one player may have out. |
| `repLimitField` | `6` | Republic mines: how many with the Minefield skill. |
| `repFieldRadius` | `1.3` | Republic mines: blast radius multiplier with Minefield. |
| `armorKitPool` | `300` | Armour repair kit: armour points in a full kit. |
| `armorKitStep` | `50` | Armour repair kit: most armour one use gives (0 = all the way up). |

Model settings apply to bombs set up after the change (and mines when they are placed or reset).

Items: `eod_kit` (EOD kit, 2×1, 1.5 kg), `eod_interference` (interference device, 2×2, 3 kg); weapons as items: `rhylib_mine_scanner` (2×1), `rhylib_armor_kit` (2×2, charge), `rhylib_rep_mine` (1×1, stack 3). All five are stocked in the armoury's ammo cabinet. The interference device runs on the inventory's `cell` item.

### Commands and permissions

There are no console commands.

| Permission | Default rank | What it allows |
|---|---|---|
| `rhylib.eod.gm` | admin (rhylib_admin's gamemaster rank also has it) | The GM window (E on a bomb with the toolgun out), and the EOD / Training toolgun entries without full toolgun access. |

A host config that redefines rhylib_admin's ranks must add `rhylib.eod.gm` to the gamemaster rank itself.

Training bombs and mines can be set up by anyone standing near them.

### Placing things / saving

Use the toolgun (rhylib_toolgun):

| Entry | Category | Places |
|---|---|---|
| `eod_simple` | EOD | Simplified bomb (timer, lid switch, wires). |
| `eod_small` | EOD | Small bomb (random, up to 2 modules). |
| `eod_large` | EOD | Large bomb (random, up to 3 modules; quarter-map blast). |
| `eod_custom` | EOD | Custom bomb: then E on it with the toolgun to build it. |
| `mine_ap`, `mine_lap` | EOD | Mines; the count box scatters that many around the spot. |
| `minefield` | EOD | 14 mines over ~10 m, about a quarter LAP. |
| `minefield_big` | EOD | 30 mines over ~20 m. |
| `eod_training` | Training | Training bomb. |
| `mine_training` | Training | Training mines (count = scattered). |

Bombs and mines are also in the spawn menu (category "Rhylib: EOD", admin only).

**GM window** (E on a bomb with the toolgun out): shows the bomb's features, every wire's job and the module answers; re-roll it (custom and training bombs keep their features and get a fresh board), make it a new simplified / small / large bomb, build a custom one (every feature and module), start / pause / set the timer, send the remote signal now or after N seconds (spotter), open the defusal window, disarm, or detonate.

**Saving:** nothing is saved on its own. Make bombs and mines permanent with the toolgun's Permanent tool (rhylib_core). Only the entity and its spot are kept: a permanent bomb gets a new random roll each map (a custom bomb's choices are not kept). A permanent mine or bomb that went off or was lifted in play stays in the save and is back next map.

## For players (short)

- **Bomb:** walk up (never run near one with a motion sensor) and press E. Hold Inspect first. With an EOD kit: release the lid tab, lift the lid, then pick a tool (Probe, Wirecutters, Jumper wire) and click wires or terminals. Arrow keys nudge a tilt switch. Esc or Close closes the window. The datapad's bomb manual (Bomb manual skill) has the rules.
- **Mine:** if it clicks, don't move or jump. Someone else with an EOD kit presses E on it: hold Dig, press Space (or the button) while the needle is in the green zone, then hold Lift.
- **Mine scanner:** LMB on / off; mines in the beam are outlined and it beeps faster as you get closer. RMB marks the mine nearest your crosshair for everyone.
- **Interference device:** right-click the item in the inventory to place it (needs a power cell), E on it for settings. Wideband blocks every signal and blinds motion sensors but jams your own radio; tuned blocks one frequency and lasts four times longer.
- **Republic mine** (skill): LMB / RMB on the ground in front of you. E on your own mine picks it up.
- **Armour repair kit** (skill): LMB a clone you look at, RMB yourself, or "Repair armour" on the interaction wheel.

## For developers

### Public functions

All on `Rhylib.EOD` (`E`). Server unless noted.

| Function | Returns | What it does |
|---|---|---|
| `E.Cfg(key)` (shared) | value | Current `eod` config value. |
| `E.Roll(kind)` | feature table | Random features for `"simple"`, `"small"` or `"large"`. |
| `E.CustomFeatures(json, kind)` | `f` or nil | Checks a builder's JSON and returns a feature table (`kind` = type, default `"custom"`). |
| `E.Build(f)` | state | A fresh bomb state (board, colours, module state). No entity involved. |
| `E.SetupBomb(bomb, f)` | — | Gives an entity a bomb state and registers it. |
| `E.Rebuild(bomb, f)` | — | Closes open windows, then `SetupBomb`. Use this on a bomb in play. |
| `E.Changed(bomb)` | — | Resend the view to everyone with the window open (once per tick). |
| `E.Reading(st, i)` | string | What the probe says about wire `i`. |
| `E.AnySupply(st)`, `E.CapNow(st)`, `E.Powered(st)`, `E.HeatNow(st)` | bool / number | Circuit state helpers. |
| `E.AddHeat(bomb, ply, n, always)` | true if it fired | Heat the board (only with the thermal fuse unless `always`). |
| `E.CheckDone(bomb)` | — | Marks the bomb done when every last step is finished. |
| `E.View(bomb, ply)` | table | What a defusal window may know. |
| `E.OpenFor(ply, bomb)` / `E.CloseFor(ply, bomb)` | — | Open / close a player's defusal window. |
| `E.UseBomb(ply, bomb)` | — | What E on a bomb does (GM window or defusal window). |
| `E.StartTimer(bomb, secs)` | bool | Start or resume the countdown (needs battery power). |
| `E.PauseTimer(bomb)` | bool | GM pause (stays paused until started again). |
| `E.Detonate(bomb, cause)` | — | Set it off; `cause` is an `E.CAUSES` key. |
| `E.Disarm(bomb, why)` | — | Make it safe outright. |
| `E.RemoteSignal(bomb)` | ok, reason | The enemy's remote signal. |
| `E.Cloud(pos, kind, radius, secs)` | — | A gas (`"gas"`) or virus (`"virus"`) cloud. |
| `E.Covered(bomb)` | bool | A device blocked its signal in the last 0.5 s. |
| `E.InBlackout(pos)` | bool | Inside a Signal blackout device (rhylib_droids asks). |
| `E.HasKit(ply)` | bool | Carries an EOD kit. |
| `E.IsBombSquad(ply)` | bool | Any Field technician skill or an EOD kit. |
| `E.Msg(ply, text, bad)` | — | A line in the player's defusal window log. |
| `E.OpenDevice(ply, dev)`, `E.DevSetActive(dev, on)`, `E.DevFill(dev)` | — / bool / 0-1 | Interference device. |
| `E.CellLife(radiusM, tuned, long)` (shared) | seconds | One cell's life at that radius. |
| `E.PlaceMines(tr, n, spread, lapShare, class)` | list | Scatter and bury mines. |
| `E.SetupMine(mine)`, `E.MineReset(mine)`, `E.BuryMine(mine)` | — | Arm, reset (training), bury. |
| `E.MineBoom(mine, cause)`, `E.MineShot(mine, dmg)` | — | Set a mine off; damage handler. |
| `E.RepCount(ply)`, `E.RepCanPlace(ply, pos)`, `E.RepPlace(ply, tr, issued)`, `E.RepBoom(mine)` | | Republic mines. |
| `E.ArmedBeep(ent)` | — | The training "armed" double beep. |
| `E.KeepForNextMap(ent)` | — | Keep a used-up permanent entity in the map save. |
| `E.Skill(ply, id)` (shared) | bool | rhylib_skills node check. |
| `E.TiltPos(t, now)`, `E.TiltResume(st)`, `E.LiquidNeedle(l, now)`, `E.MineNeedle(period, ph, now)`, `E.ScanDir(ply)`, `E.MineTop(m)`, `E.ChipText(p)` (shared) | | Shared maths used by both sides. |
| Client: `E.Nudge(dx, dy)`, `E.CloseWindow(tell)`, `E.TrainAct(bomb, op, json)`, `E.TrainingSetup(bomb)`, `E.ScannerMark()`, `E.ScannerHUD(wep)`, `E.RepCountClient()` | | Window and HUD helpers. |

Shared tables: `E.MODS` (+ `E.MOD_BY[id]`), `E.TIERS`, `E.CHIP_CODES`, `E.COLOURS`, `E.CAUSES`. Server lists: `E.bombs`, `E.mines`, `E.devices`, `E.repMines`, `E.clouds`, `E.blackouts` (all keyed by entity except clouds / blackouts).

Entity fields to make your own variant: bombs `ENT.Base = "rhylib_eod_bomb"`, `ENT.BombType` (`simple` / `small` / `large` / `custom` / `training`), `ENT.IsTrainingBomb`; mines `ENT.Base = "rhylib_eod_mine"`, `ENT.MineType` (`ap` / `lap`), `ENT.IsTrainingMine`.

### Hooks

Fired:

- `Rhylib.Explosion(pos, reach, tier, attacker, inflictor, kind)` when a bomb (`"bomb"`; tier 3 large, 2 small, 1 gas), a mine (`"mine"`, tier 1, reach `mineChain`) or a Republic mine (`"repmine"`, attacker = planter) goes off. Return values are ignored.

Answered / listened to:

- `Rhylib.IsBombSquad(ply)`: returns true for anyone with a Field technician skill or an EOD kit (rhylib_datapad's "Call the bomb squad").
- `Rhylib.EMP(pos, radius, attacker, inflictor)` (rhylib_republic droid popper): `popperChance` to disarm each bomb in sight; switches off devices.
- `Rhylib.Explosion`: sets off mines within `reach` (at least 60), unless the attacker is a droid.
- `Rhylib.ToolEntries` (toolgun entries), `Rhylib.ModuleLoaded` (items once rhylib_inventory loads; the manual once rhylib_datapad loads), `Rhylib.ItemMenu` (Place interference device), `Rhylib.WheelOptions` (Repair armour).
- `StartCommand` / `SetupMove` "eod.mineclick": freezes a player for `E.MINE_GRACE` (0.6 s) after stepping on a mine.
- `PlayerDisconnected`: leaving while on a mine sets it off; leaving removes your Republic mines.

Other addons read: `Rhylib.Datapad.EodManualBuild` / `HasEodManual` (manual tab), rhylib_radio's `R.jammers` and `ENT:JamRange()` (wideband devices jam radios), rhylib_droids' `D.Blackout` (calls `E.InBlackout`).

### Network messages

All names get the `rhylib.` prefix.

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `eod.act` | client → server | bomb, op (4 bits), op args (wire 5 bits; jumper 4 + bool + 4 + bool; nudge 2 × signed 3 bits; torch bool; chip string; mount 2 bits; dose 5 bits) | Every defusal action (ops 0-15). 20/s. |
| `eod.close` | both | bomb | Window closed. |
| `eod.state` | server → viewer | bomb, len 16 bits, compressed JSON | The window's view. |
| `eod.read` | server → player | wire 5 bits, string | Probe reading. |
| `eod.msg` | server → player | string, bool | Log line. |
| `eod.done` | server → viewers | bomb | Made safe. |
| `eod.xray` | server → player | bomb, 3 × 2 bits, float | Fake board order. |
| `eod.boom` | server → viewers + within 2500 | entity index 13 bits, cause string, vector | Fail overlay / chat line. |
| `eod.far` | server → all | vector, float | Large blast rumble. |
| `eod.gas` | server → nearby | vector, float, float, bool | Cloud smoke. |
| `eod.gmopen` | server → GM | bomb, note, len 16 bits, compressed JSON | GM window. |
| `eod.gm` | GM → server | bomb, op 4 bits, JSON / 11-bit seconds | GM controls. 8/s. |
| `eod.train` / `eod.trainopen` | both | bomb, op 3 bits, JSON | Training bomb setup. |
| `eod.place` | client → server | item uid | Place an interference device. 3/s. |
| `eod.devset` | client → server | device, op 3 bits, arg | Device settings. 12/s. |
| `eod.dev` / `eod.devscan` | server → player | device; count 4 bits + (7, 7 bits, bool) each | Open device window; receiver scanner. |
| `eod.mineuse` / `eod.mineopen` | both | mine; centre 7 bits, width, period, phase | Open the mine window. |
| `eod.mineact` | client → server | mine, op 3 bits | Dig / pin / lift / close. 10/s. |
| `eod.minemark` | client → server | mine | Scanner mark. 8/s. |
| `eod.trainmine` | client → server | mine, bool, bool, 2 bits, 2 bits | Training mine setup. 4/s. |
| `eod.reppick` | client → server | mine | Pick up your Republic mine. 6/s. |
| `wheel.armor` | client → server | player | Repair armour from the wheel. 2/s. |

### Saved data

None in `Rhylib.Data`. Permanent bombs and mines go through rhylib_core's Permanent tool (generic save: class and position only).

### Examples

React to bombs going off from your own addon:

```lua
Rhylib.Hook.Add("Rhylib.Explosion", "myaddon.bombs", function(pos, reach, tier, attacker, inflictor, kind)
    if kind == "bomb" and tier == 3 then
        PrintMessage(HUD_PRINTTALK, "A large bomb went off!")
    end
end)
```

Spawn a scripted bomb for an event (server):

```lua
local E = Rhylib.EOD
local bomb = ents.Create("rhylib_eod_bomb_custom")
bomb:SetPos(pos)
bomb:Spawn()
local f = E.CustomFeatures(util.TableToJSON({
    det = "timer", battery = "capacitor", lid = true, charge = "gas",
    mods = { "chip", "tilt" }, timerSecs = 300,
}))
E.Rebuild(bomb, f)
E.StartTimer(bomb)   -- start now instead of waiting for someone to come close
```

Send the remote signal from your own script (e.g. a scripted event trigger):

```lua
local went, why = Rhylib.EOD.RemoteSignal(bomb)
if not went then print("The bomb didn't go off: " .. why) end
```

A bomb type of your own (in your addon's `lua/entities/`):

```lua
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_eod_bomb"
ENT.PrintName = "Bomb (event)"
ENT.Category = "My server"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.BombType = "large"
```

## Notes and gotchas

- **Toolgun holders are invisible to the bomb.** Motion sensors, mines (pressing and shooting) and the timer wake-up ignore anyone holding the toolgun, so a GM can set things up. Put it away to test as a player.
- **Large bombs kill through walls** inside `largeKill` (2200 units, ~42 m), players included (only god mode is spared).
- **Timers need a battery.** A capacitor alone keeps the bomb powered but not the clock: cutting every supply stops the timer.
- **The tilt bubble freezes** while nobody has the window open, and starts when the lid comes off.
- **Wideband devices jam your own radio and compass** inside their circle (rhylib_radio). Tuned devices don't, but a hopping receiver slips away from them.
- **Limits in the network format:** at most 15 parts (jumper part index, 4 bits) and 31 wires (5 bits) per bomb; all 16 `eod.act` ops are used (see "Adding a module"); device radius is at most 15 m whatever `deviceMaxRadius` says.
- **Training bombs set up "random simplified"** are rolled as type `training`, so they can get a tamper loop and a 180 s timer, unlike a real simplified bomb (no tamper loop, 150 s).
- **Permanent bombs re-roll** every map; a custom bomb's choices are not saved.
- **Rhylib.Explosion from droids** never sets off mines (droids know their mines); clone NPCs walking onto a mine set it off at once; droids never do.
- **Republic mines** only hurt droids and only droids set them off; they don't chain from other explosions, but their blast can set off enemy mines nearby.
- No skill makes defusing easier. Skills only add the manual, recovering the charge (Render safe), Republic mines, Minefield and Signal blackout.
