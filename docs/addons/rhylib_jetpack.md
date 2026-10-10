# rhylib_jetpack: Jetpack

A jetpack worn in the inventory's Back slot (instead of a backpack). In the air, hold Jump to climb or Sprint to hover; steer with the movement keys. Fuel drains while thrusting and refills on the ground; running dry locks the jetpack until the tank is partly refilled. Flight is predicted on the client, so it feels as instant as walking. Other players see the jetpack on your back, the flames and hear the jet sound.

## Requirements

- Required: rhylib_core.
- Recommended: rhylib_inventory (the jetpack is an inventory item; it's the only normal way to get one). Without it, staff can still switch one on with `rhylib_jetpack_give`.
- Optional: rhylib_skills (Airborne skills change fuel, recharge and speeds per player), rhylib_armoury (gear cabinet stocks it), rhylib_gear (shows the model's backpack bodygroup).
- Model: the placeholder `models/thrusters/jetpack.mdl` ships with GMod. Swap it on the Models page (`item.jetpack`).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_jetpack.lua` | shared | Loads the module. |
| `lua/entities/rhylib_item_jetpack.lua` | shared | Spawn menu entry (a world item holding a jetpack). |
| `lua/rhylib/jetpack/sh_00_config.lua` | shared | Settings, DT slots, `J.Fuel`, `J.SetLine`, the `jetpack` item. |
| `lua/rhylib/jetpack/sh_10_move.lua` | shared | Predicted flight in SetupMove. |
| `lua/rhylib/jetpack/sv_10_equip.lua` | server | Turns the jetpack on/off from the Back slot; `rhylib_jetpack_give`. |
| `lua/rhylib/jetpack/cl_10_effects.lua` | client | Model on the back, flames, sound, fuel bar. |

## For server owners

### Settings

Config module `jetpack`:

| Key | Default | What it does |
|---|---|---|
| `fuelTime` | `10` | Seconds of thrust from a full tank (rhylib_skills Airborne: skills airborneFuel). |
| `rechargeTime` | `6` | Seconds to refill an empty tank while on the ground. |
| `rechargeDelay` | `0.5` | Seconds on the ground before refilling starts. |
| `unlockAt` | `0.35` | After running dry, fuel needed before the jetpack works again. |
| `climbSpeed` | `230` | Vertical speed the jetpack steers toward while thrusting (units/s). |
| `climbTau` | `0.35` | How quickly it reaches climb speed when already rising (seconds). |
| `brakeTau` | `0.12` | How quickly it cancels a fall (seconds); lower = harder braking. |
| `maxAccel` | `1500` | Cap on the upward force while rising (units/s²). |
| `brakeAccel` | `640` | Cap on the braking force while falling (units/s²). Lower = long falls take longer to stop, so you must start braking early. |
| `airAccel` | `420` | Sideways steering while thrusting (units/s²). |
| `maxAirSpeed` | `235` | Top sideways speed from steering (units/s). |
| `airStopTau` | `0.3` | How quickly sideways movement stops with no keys held (seconds); lower = stops faster. |
| `loadFuelMult` | `0.3` | At a full load the jetpack burns this much more fuel (0.3 = 30% faster). |
| `hoverFuel` | `1` | Fuel burn multiplier while hovering (rhylib_skills Hover: skills hoverFuelMult). |

rhylib_skills can change `fuelTime`, `rechargeTime`, `climbSpeed`, `airAccel`, `maxAirSpeed` and `hoverFuel` per player; these values are everyone's base.

```lua
-- lua/rhylib_config/settings.lua
Rhylib.Config.Set("jetpack", "fuelTime", 14)
Rhylib.Config.Set("models", "item.jetpack", "models/mypack/jetpack.mdl")
```

Item: `jetpack`, 2×2, Back slot, 8 kg, category gear.

### Commands and permissions

| Command | Permission (default) | What it does |
|---|---|---|
| `rhylib_jetpack_give` | `rhylib.jetpack.give` (admin) | With rhylib_inventory: gives you a jetpack item (worn if the Back slot is free, else in the inventory or on the ground). Without it: toggles a jetpack on you. |

### Placing things

The spawn menu entity "Jetpack" (Rhylib: Items & ammo) is a world item; only spawnable with rhylib_inventory.

## For players (short)

- Wear it in the Back slot.
- In the air: hold Jump to climb, hold Sprint to hover (Sprint wins if both are held), movement keys steer; with no keys you slow to a stop.
- A fuel bar shows under the crosshair while it isn't full; red "Jetpack recharging" when it ran dry (land and wait).
- Heavier loads burn fuel faster. No thrust under water or on a grapple rope.

## For developers

### Public functions (`Rhylib.Jetpack`)

| Function | Realm | Returns | Description |
|---|---|---|---|
| `Has(ply)` | shared | bool | Wearing a jetpack (DTBool 31). |
| `Flying(ply)` | shared | bool | Wearing one and not on the ground. |
| `Fuel(ply, t)` | shared | 0-1 | Fuel at time `t` (default now). |
| `SetLine(ply, fuel, from, rate)` | shared | — | Start a new fuel line. |
| `Set(ply, has)` | server | — | Switch the jetpack on/off (on = full tank). |
| `Refresh(ply)` | server | — | On if the Back slot holds a `jetpack` item (needs rhylib_inventory). |

Client tunables (cl_10_effects.lua): `J.BackOffset`, `J.CrouchDrop`, `J.BackAngle`, `J.Nozzles`: where the back model and flames sit.

```lua
-- a big gun that can't fire while flying
if Rhylib.Jetpack and Rhylib.Jetpack.Flying(owner) then return false end

-- refill a player's tank (server)
Rhylib.Jetpack.SetLine(ply, 1, 0, 0)
```

### State (player DT vars, predicted)

| Slot | Meaning |
|---|---|
| DTBool 31 (`DT_HAS`) | Wearing a jetpack. |
| DTBool 30 (`DT_LOCKED`) | Ran dry; locked until `unlockAt`. |
| DTBool 29 (`DT_THRUST`) | Thrusting now (effects, sound). |
| DTFloat 30 (`DT_FUEL`) | Fuel at the start of the line (0-1). |
| DTFloat 31 (`DT_FROM`) | When the line starts (future while the refill delay runs). |
| DTFloat 23 (`DT_RATE`) | Fuel per second (negative = burning). |

`fuel now = DTFloat30 + DTFloat23 × max(0, now − DTFloat31)`, clamped to 0..1, rewritten only when the slope changes. Also read: DTEntity 31 (grapple rope from rhylib_weapons: no thrust while set).

### Hooks

Listens to: `SetupMove` ("jetpack.move"), `Rhylib.InventoryChanged` (server, re-checks the Back slot), `PlayerSpawn` (server, next tick: re-check, full tank), client `PostPlayerDraw` and `HUDPaint`. Fires none. Calls `Rhylib.Skills.JetCfg(ply, key, value)` when present.

### Network messages / saved data

None (DT vars only; the item is saved with the inventory).

### Examples

Give jetpacks to a job without rhylib_inventory:

```lua
Rhylib.Hook.Add("PlayerSpawn", "myaddon.jet", function(ply)
    timer.Simple(0.1, function()
        if IsValid(ply) and ply:Team() == TEAM_JUMPTROOPER then Rhylib.Jetpack.Set(ply, true) end
    end)
end)
```

(With rhylib_inventory installed, `J.Refresh` turns it off again on the next inventory change unless the item is worn: give the item instead.)

## Notes and gotchas

- The item registers only if rhylib_inventory loaded first (its autorun sorts before ours).
- Changing the item model on the Models page also changes the model drawn on players' backs; the back offsets were set for the placeholder.
- Explosion knockdowns and rhylib_core's soft knock switch thrust off.
- Jumping costs no stamina while wearing a jetpack (rhylib_stamina).
