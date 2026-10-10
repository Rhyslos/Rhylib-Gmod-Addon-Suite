# rhylib_stamina: Stamina

Sprinting and jumping use stamina, which comes back after a short rest. Running completely dry leaves you exhausted: no sprinting until you've recovered a bit. Carried weight (from rhylib_inventory) makes stamina drain faster and come back slower, and very heavy loads slow you down. Everything is predicted on the client, so sprint stops the moment you run dry with no rubber-banding. Server owners tune it all with config settings.

## Requirements

- Required: rhylib_core.
- Recommended: rhylib_inventory (weight and carry cap; without it the load is always 0). rhylib_hud draws the stamina bar.
- Optional links: rhylib_medical (a hurt torso lowers max stamina), rhylib_skills (several skills change drain, regen and the weight penalty).
- No Workshop content.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_stamina.lua` | shared | Loads the module. |
| `lua/rhylib/stamina/sh_00_config.lua` | shared | Settings, `Rhylib.Stamina` maths (Get, Max, Penalty, ...). |
| `lua/rhylib/stamina/sh_10_move.lua` | shared | The predicted SetupMove hook: drain, recovery, jumps, slow-downs; full stamina on spawn. |

## For server owners

### Settings

Config module `stamina`:

| Key | Default | What it does |
|---|---|---|
| `max` | `100` | Full stamina. |
| `sprintDrain` | `12` | Stamina per second while sprinting with no load. |
| `jumpCost` | `8` | Stamina per jump. |
| `regen` | `20` | Stamina per second while resting, with no load. |
| `regenDelay` | `1` | Seconds after sprinting or jumping before stamina comes back. |
| `exhaustedUntil` | `25` | After running dry, no sprinting until stamina is back to this. |
| `maxPenalty` | `0.8` | Penalty at a full load without a backpack. |
| `maxPenaltyPack` | `0.6` | Penalty at a full load with a backpack worn. |
| `penaltyCurve` | `1.2` | Higher = light loads cost less, the last kilos cost more. |
| `heavyFrom` | `0.75` | Above this share of your carry cap you also move slower. |
| `heavySlow` | `0.1` | Speed lost at a full load (0.1 = 10% slower walk and sprint); grows from heavyFrom. |
| `overloadWalkMult` | `0.8` | Walk speed multiplier while over the carry cap. |
| `lowAimBelow` | `20` | Below this stamina, spread starts to grow. |
| `lowAimSpread` | `0.5` | Extra spread at zero stamina, as a fraction of the weapon's resting cone. |

How the load works:

```
load    = weight / carry cap          (rhylib_inventory)
penalty = maxPenalty × min(load, 1) ^ penaltyCurve
drain   = sprintDrain × (1 + penalty)
regen   = regen × (1 − penalty / 2)
```

Over the carry cap you can't sprint and walk at `overloadWalkMult`. "With a backpack" means the carry cap is above the inventory's base cap.

Change them on the in-game Staff > Server settings page, or in a host file:

```lua
-- lua/rhylib_config/settings.lua
Rhylib.Config.Set("stamina", "sprintDrain", 10)
Rhylib.Config.Set("stamina", "regen", 25)
```

### Commands and permissions

None.

## For players (short)

- Sprint (Shift + a movement key, on the ground, not crouching) drains stamina; jumping costs a chunk. Wearing a jetpack makes jumps free.
- Stop sprinting and it comes back after a second.
- Run dry and you're exhausted: walk until the bar is back to 25.
- Low stamina makes your aim wider; heavy kit drains it faster.

## For developers

### Public functions (`Rhylib.Stamina`, shared)

| Function | Returns | Description |
|---|---|---|
| `Get(ply, t)` | number | Stamina at time `t` (default now), 0 to `Max`. |
| `Max(ply)` | number | Config max × rhylib_medical's torso cap. |
| `Frac(ply)` | 0-1 | `Get / config max`. |
| `Exhausted(ply)` | bool | Ran dry and not recovered yet. |
| `Drain(ply, amount)` | — | Server only: take stamina away now (keeps the current slope). |
| `Load(ply)` | load, hasPack | Weight / carry cap, and whether the cap is above the base. |
| `Penalty(ply)` | penalty, over | Penalty 0..maxPenalty, and over the cap. |
| `LoadSpeedMult(ply)` | number | 1, down to 1 − heavySlow at a full load. |
| `SpreadPenalty(ply, baseCone)` | degrees | Extra spread for a low-stamina owner (rhylib_weapons uses it). |

```lua
-- server: a hit that knocks the wind out
Rhylib.Stamina.Drain(victim, 30)

-- client HUD
local frac = Rhylib.Stamina.Frac(LocalPlayer())
```

### How it's stored

Stamina is a straight line in the player's DT vars, rewritten only when the slope changes (sprint starts/stops, a jump, a load change), so a long sprint sends nothing tick by tick:

| Slot | Meaning |
|---|---|
| DTFloat 28 (`S.DT_STAMINA`) | Stamina at the start of the line. |
| DTFloat 29 (`S.DT_FROM`) | When the line starts (in the future while the regen delay runs). |
| DTFloat 26 (`S.DT_RATE`) | Change per second (negative = sprinting). |
| DTBool 28 (`S.DT_EXHAUSTED`) | Exhausted. |

`stamina now = DTFloat28 + DTFloat26 × max(0, now − DTFloat29)`, clamped. Other suite users of player DT slots: jetpack DTBool 29-31, DTFloat 23, 30, 31; grapple DTFloat 27, DTBool 27, DTEntity 31; Sidestep DTFloat 24-25. Don't reuse these in your own player code.

### Hooks

Listens to `SetupMove` ("stamina.move", priority 0) and, on the server, `PlayerSpawn` ("stamina.reset": full stamina). Fires none. It calls into rhylib_skills when present: `K.WeightPenaltyMult`, `K.RegenMult`, `K.FreeSprint`.

### Network messages / saved data

None (DT vars only).

### Examples

Refill a player's stamina from your own addon by setting the line yourself (shared, inside predicted code or on the server):

```lua
-- give a player full stamina now (server)
local S = Rhylib.Stamina
ply:SetDTFloat(S.DT_STAMINA, S.Max(ply))
ply:SetDTFloat(S.DT_FROM, CurTime())
ply:SetDTFloat(S.DT_RATE, 0)
```

The next SetupMove sets the right recovery slope again.

## Notes and gotchas

- The maths runs in SetupMove on both realms; a value read on the server and client should match. Changing the settings mid-game applies straight away (they're read every tick), and clients get the new value through the Server settings sync.
- `Frac` divides by the config max, not `Max(ply)`, so a hurt torso shows as less than full.
- Without rhylib_inventory the load is 0: no weight effects at all.
