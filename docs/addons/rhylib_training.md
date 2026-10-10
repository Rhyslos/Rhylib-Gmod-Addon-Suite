# rhylib_training: Training simulations

Safe training fights. Training guns and training droids fire yellow bolts that never hurt anyone; instead every player has "sim health". Training hits take it off (head and limb multipliers count, armour doesn't). At 0 you're eliminated: you drop, can't act, and pick a training respawn beacon from a list (or the nearest is picked for you). Sim health refills after a few seconds without a training hit. No credits, stats, kill feed or injuries come from training; real damage still works as normal during a simulation.

## Requirements

- Required: rhylib_core, rhylib_weapons (it sends the training hits).
- Recommended: rhylib_republic (training guns and grenades) or rhylib_droids (training droids), rhylib_armoury (training armoury, ammo cabinet and deposit), rhylib_menus (the beacon list), rhylib_hud (sim health on the HUD, yellow hit markers), rhylib_toolgun (placing and naming beacons).
- Model: config `beaconModel`, default `models/props_combine/combine_mine01.mdl` (ships with GMod).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_training.lua` | shared | Loads the module. |
| `lua/entities/rhylib_training_beacon.lua` | shared | Respawn beacon (yellow ring and name). |
| `lua/rhylib/training/sh_00_config.lua` | shared | Settings, `T.Out`, `T.Health`. |
| `lua/rhylib/training/sv_10_sim.lua` | server | Sim health, elimination, respawn, beacon saving. |
| `lua/rhylib/training/cl_10_sim.lua` | client | Sim health bar, beacon list. |

## For server owners

### Settings

Config module `training`:

| Key | Default | What it does |
|---|---|---|
| `simHealth` | `100` | Sim health: what training hits take off before you're eliminated. |
| `simRegen` | `10` | Seconds without a training hit before sim health refills. |
| `outMin` | `3` | Seconds an eliminated player lies there at least. |
| `chooseTime` | `20` | Seconds to pick a respawn beacon before the nearest one is picked. |
| `immune` | `2` | Seconds of no training hits after respawning at a beacon. |
| `beaconModel` | `"models/props_combine/combine_mine01.mdl"` | Respawn beacon model. |

```lua
Rhylib.Config.Set("training", "simHealth", 150)
Rhylib.Config.Set("training", "chooseTime", 10)
```

### Commands and permissions

| Permission | Default | Used for |
|---|---|---|
| `rhylib.training.admin` | admin | `rhylib_training_save`. |

| Command | What it does |
|---|---|
| `rhylib_training_save` | Saves this map's permanent beacons now. |

### Placing things / saving

- Place beacons with the toolgun (Training > "Training respawn beacon"; the "Beacon name" box names it, e.g. "Range", "Killhouse A") or the spawn menu (Rhylib: Training, admin only).
- Make them permanent with the toolgun's Permanent tool; only permanent beacons are saved (Data `training`/`<map>`) and come back at map load and after a cleanup.
- The training armoury, ammo cabinet and deposit belong to rhylib_armoury.

## For players (short)

- Use training guns (yellow bolts) from the training armoury.
- Your sim health shows in yellow: with a training gun in hand on the HUD's health bar (rhylib_hud), otherwise as a bar under the crosshair while it isn't full.
- Eliminated: you lie down; after 3 s pick a beacon in the list (or "Nearest"), or wait 20 s for the nearest. No beacons on the map = you get up where you are.
- Going down, dying or respawning for real ends your elimination.

## For developers

### Public functions (`Rhylib.Training`)

| Function | Realm | Returns | Description |
|---|---|---|---|
| `Cfg(key)` | shared | value | `Config.Get("training", key)`. |
| `Out(ply)` | shared | bool | Eliminated now (NW2Bool `rhylib_simOut`). |
| `Health(ply)` | shared | number | Sim health (NW2Int `rhylib_sim`). |
| `Eliminate(ply, by)` | server | bool | Knock down and open the beacon list; true if they're out now. |
| `Respawn(ply, beacon)` | server | — | Back in at that beacon (or the nearest, or in place). |
| `SaveBeacons()` / `SpawnBeacons()` | server | count / — | Save permanent beacons / spawn the saved ones. |

State: `T.hp[ply]` (only while below full), `T.lastHit[ply]`, `T.out[ply] = { at }`; NW2Float `rhylib_simOutAt`; `ply.rhylibSimImmune` (time). Elimination uses `Rhylib.Lying.Knock(ply, 0)` (a server ragdoll, no end time).

Beacon entity: NetworkVar `BeaconName`; `ENT:SpawnPos()`.

### Hooks

Handled here:

`Rhylib.TrainingHit(ply, attacker, amount, inflictor, group)`: fired by rhylib_weapons for training bolts and training blasts. This addon's handler returns `true` when the hit eliminated the player, `false` when it was ignored (out, downed, lying, immune, dead), nil for a normal hit. rhylib_weapons uses that for the hit marker.

Listens to: `Rhylib.PlayerDowned`, `PlayerDeath`, `PlayerSpawn` (reset), `Rhylib.PlayerUnknocked` (got up another way), `PlayerDisconnected`, `InitPostEntity` (beacons +1 s), `PostCleanupMap`.

Sends hit feedback with `Rhylib.HUD.SendHit` (rhylib_hud) when present.

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `train.out` | server → player | Bool open; String attacker; Float ready time; Float auto time; UInt6 count (max 32); per beacon UInt13 entindex, String name, UInt16 metres | Open (or close, false) the beacon list. |
| `train.pick` | client → server | UInt13 entindex (0 = nearest) | Pick a beacon (rate 2/s; waits until `outMin`). |

### Saved data

`Data "training"/<map>` = `{ { name, pos = {x,y,z}, yaw } }` (permanent beacons). In `Rhylib.PLACEMENT_CLASSES`.

### Examples

Treat your own weapon's hits as training hits (server):

```lua
local out = hook.Run("Rhylib.TrainingHit", victim, attacker, 25, myWeapon, HITGROUP_CHEST)
if out == true then attacker:ChatPrint("Eliminated " .. victim:Nick()) end
```

Remember who last hit each player in training, e.g. for your own scoreboard (server):

```lua
Rhylib.Hook.Add("Rhylib.TrainingHit", "myaddon.count", function(ply, attacker)
    -- runs before training.hit (priority -10) and returns nothing, so the hit still counts
    MyAddon.lastAttacker[ply] = attacker
end, -10)
```

## Notes and gotchas

- Without rhylib_menus the beacon list doesn't show; the client picks the nearest beacon as soon as `outMin` is up.
- Sim health uses the training hit amount as is: rhylib_weapons has already applied head/limb multipliers.
- Soft-knocked players (explosion knockdown) are stood up first, then eliminated properly.
- Beacons placed but never made permanent are gone after a map change.
