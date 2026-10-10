# rhylib_gear: Wearable gear (bodygroups), optics and helmet lights

Clone armour parts as inventory items. A kama, pauldron, macrobinoculars, rangefinder, helmet lights, sun visor, holster, forearm guard, shoulder antenna, belt pouches and back items (ARC backpack, comms backpack, gun belts, chest strap) are worn in the inventory's gear slots. Wearing one turns its bodygroup on, matched by bodygroup and option NAME, since each model numbers them differently. You can only wear what your model can show. Some parts do something: the kama protects the legs from blasts, the pauldron makes armour last, the optics zoom and give range and night vision, the sun visor gives a red tactical view, the helmet lights are two beams on the flashlight key, and the holster, pouches and backpacks add inventory space. Players also get a helmet on / off button (hair shows with it off). Server owners set a battalion kit given at spawn and which parts need a rank. Players take parts from the gear cabinet (`rhylib_armoury`).

## Requirements

- Required: `rhylib_core`, `rhylib_inventory` (the items and gear slots).
- Works better with: `rhylib_armoury` (the gear cabinet, the normal way to get parts), `rhylib_roster` (rank / qualification unlocks, hair and skin looks), `rhylib_medical` (kama effect, downs), `rhylib_weapons` (pauldron armour effect), `rhylib_hud` (visor HUD mask), `rhylib_skills` (Mark target with the visor), `rhylib_menus` (key settings, controls list).
- Workshop content: the player models the parts are on. Made for the OKFellows V-RP Phase 1 clone armour pack. Other models work if their bodygroup and option names match (see `rhylib_gear_scan`). No content of its own (inventory pictures are HL2 props).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_gear.lua` | shared | Loads the module through `Rhylib.LoadModule`. |
| `lua/rhylib/gear/sh_00_config.lua` | shared | `Rhylib.Gear`, the item list, config keys, model lookups (`ModelInfo`, `ItemShown`, `Worn`, `Active`), kit and unlock rules, item registration, `Rhylib.CanWear` answer. |
| `lua/rhylib/gear/sh_30_optics.lua` | shared | Optics state (`OpticsAllowed`, `Looking`, `VisorDown`), zoom ranges, blocks firing / sprinting while looking. |
| `lua/rhylib/gear/sv_10_scan.lua` | server | `rhylib_gear_scan`: every job model's bodygroups. |
| `lua/rhylib/gear/sv_20_gear.lua` | server | Bodygroups from what's worn (`G.Apply`), kit at spawn, helmet toggle, bare-head headshots, effects, helmet lights switch, gear cabinet stock and unlocks. |
| `lua/rhylib/gear/sv_30_optics.lua` | server | Optics and visor up / down requests (`G.SetOptics`, `G.SetVisor`). |
| `lua/rhylib/gear/cl_30_optics.lua` | client | Helmet gear key, the binocular viewer, zoom, night vision, the sun visor's view and zoom. |
| `lua/rhylib/gear/cl_40_lights.lua` | client | The helmet light beams and lamp glows. |

## The items

| Item id | Slot | What it does |
|---|---|---|
| `rhylib_kama`, `rhylib_kama_arc` | kama | Less blast damage to the legs (`kamaBlastMult`), legs break less (`kamaFractureChance`). |
| `rhylib_pauldron`, `rhylib_pauldron_arc` | pauldron | Armour lost per hit × `pauldronDrainMult`. |
| `rhylib_macrobinoculars` | binos | Optics kind 1: zoom x2 to x12, range, night vision. On the helmet. |
| `rhylib_rangefinder` | rangefinder | Optics kind 2: zoom x1 to x6, range, night vision. On the helmet. |
| `rhylib_helmet_light` | light | Two helmet beams (flashlight key). Can't be worn with macrobinoculars or a rangefinder. On the helmet. |
| `rhylib_sunvisor` | visor | Red tactical view, always-on night vision, fixed zoom on the mode key. On the helmet. Not usable with macrobinoculars on models where both are options of one bodygroup. |
| `rhylib_holster` | holster | A 2x2 holster container (two pistols). |
| `rhylib_forearm_arc` | forearm | Looks only. |
| `rhylib_shoulder_antenna` | comms | Looks only. |
| `rhylib_belt_pouches` | belt | A 5x1 pouch container (no rifles or launchers). |
| `rhylib_arc_backpack` | back | 4x4 backpack + a 2x2 power cell pouch. |
| `rhylib_comms_backpack` | back | 3x2 backpack. |
| `rhylib_gunbelt`, `rhylib_gunbelt_rifle` | back | The DC-15A and RPS-6 (and their training copies) weigh half. |
| `rhylib_strap` | back | Looks only. |

Back items replace a backpack or jetpack and can be worn whatever the model shows; the cabinet still only offers what it shows. All parts add their weight. A part your model can't show (e.g. after a job change) stays worn but does nothing.

## For server owners

### Settings

Config module `"gear"`:

| Key | Default | What it does |
|---|---|---|
| `kit` | `{}` | Battalion kit given at spawn as job gear: battalion (part of its name, `*` = everyone) → item ids, e.g. `{ ["*"] = { "rhylib_macrobinoculars" } }`. Empty by default. |
| `unlocks` | `{ rhylib_kama = { rank = "SGT" }, rhylib_pauldron = { rank = "SGT" }, rhylib_rangefinder = { rank = "LT" }, rhylib_kama_arc = { rank = "SGT" }, rhylib_pauldron_arc = { rank = "SGT" } }` | Gear cabinet parts that need a rank (rank prefix, rhylib_roster) or a qualification (`qual` id); your battalion kit is always allowed. |
| `kamaBlastMult` | `0.5` | Kama: blast damage to the legs (body part damage) is multiplied by this. |
| `kamaFractureChance` | `0.5` | Kama: chance a leg actually breaks when it would. |
| `pauldronDrainMult` | `0.8` | Pauldron: armour lost per hit is multiplied by this. |
| `lightNeeded` | `true` | The flashlight key only works with helmet lights worn. |
| `lightFov` | `26` | Helmet lights: width of each beam (degrees). |
| `lightGap` | `-4.7` | Helmet lights: extra degrees each beam turns outwards past touching (positive = a dark gap in the middle, negative = overlap). |
| `lightOverlapDim` | `0.6` | Helmet lights: each beam's brightness where the two overlap (1 = no dimming). |
| `lightOverlapFlip` | `false` | Helmet lights: mirror the dimmed band if it shows on the outer edges instead of the middle. |
| `lightRange` | `2000` | Helmet lights: how far the beams reach. |
| `lightBrightness` | `3.5` | Helmet lights: brightness of each beam. |
| `lightMaxPlayers` | `2` | Helmet lights: other players whose beams light the world for you (nearest first, no shadows; your own always do). Further ones show only the lamp glow. |
| `bareHeadshotDowns` | `true` | With the helmet off, any head hit downs you. |
| `visorZoom` | `3` | Sun visor: the zoom its zoom toggle gives (the optics mode key). |
| `nvMode` | `1` | Night vision: 1 = amplified (a wide shadowless light from your eyes that turns itself down where it's already bright), 2 = the world drawn fully lit, 0 = only the green filter. |
| `nvGain` | `2.5` | Night vision (amplified): strength of the light in the dark. |
| `nvLift` | `0.04` | Night vision: how much the darkest parts are lifted. |
| `nvBoost` | `1.5` | Night vision: how much brighter the picture is made in the dark (1 = no boost). |
| `nvRange` | `0` | Night vision: fade the picture into dark green beyond this distance (units; 0 = off). |
| `nvFadeFrom` | `600` | Night vision: where that fade starts (units). |
| `nvLightRange` | `4000` | Night vision (amplified): how far its light reaches (units). |

Change them on the in-game Staff > Server settings page, or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
-- The 327th spawn with a kama and pauldron; everyone gets macrobinoculars.
Rhylib.Config.Set("gear", "kit", {
    ["327th"] = { "rhylib_kama", "rhylib_pauldron" },
    ["*"] = { "rhylib_macrobinoculars" },
})
-- Rangefinders need the "recon" qualification instead of a rank.
Rhylib.Config.Set("gear", "unlocks", { rhylib_rangefinder = { qual = "recon" } })
```

A kit key matches part of the player's roster battalion, or the DarkRP job's `battalion`, category or name (case-insensitive). Kit parts a player drops are not given again at spawn until they take one from the cabinet.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_gear_scan` | perm `rhylib.gear.admin` (default admin), or the server console | Lists every DarkRP job model's bodygroups and option names, skins and hair materials, and how many models have each group. Printed to your console and saved to `data/rhylib_gear_scan.txt` on the server. |

Use the scan when adding new player models: a part shows on a model if one of its `groups` has one of its `on` option names (see `G.ITEMS`).

### Placing things / saving

Nothing to place: parts come from `rhylib_armoury`'s gear cabinet. What players wear is saved with their inventory (rhylib_inventory).

## For players (short)

- Inventory: right-click a part > Wear, or drag it into its gear slot. HELMET ON/OFF button at the top of the right gear column.
- L (helmet gear key): macrobinoculars / rangefinder up or down; with a sun visor it cycles off → binoculars → visor → off; with helmet lights only, lights on / off.
- While looking through optics: mouse wheel zooms, F (flashlight key) night vision, middle mouse switches to weapon mode (shoot with night vision on) and back.
- Sun visor down: middle mouse toggles its zoom.
- F: helmet lights on / off.
- Keys can be changed in Settings > Controls, "Gear" section (`rhylib_optics_key`, `rhylib_optics_mode_key`).

## For developers

### Public functions

`Rhylib.Gear` (`G`). Shared unless noted.

- `G.Active(ply, slot)` → bool: a part is worn in the slot, the model shows it, and the helmet is on for helmet parts. Check this before any gear effect. `if Rhylib.Gear.Active(ply, "kama") then ... end`
- `G.Worn(ply, slot)` → item instance or nil (client: only your own).
- `G.ItemShown(ply, id)` → bool, `G.ModelHas(ply, slot)` → bool, `G.ModelInfo(ent)` → `{ groups = { [name] = { id, opts } } }`, `G.Option(group, names)` → index.
- `G.HelmetOn(ply)`, `G.VisorDown(ply)`, `G.VisorBlocked(ply)`, `G.OpticsUp(ply)`, `G.Looking(ply)`, `G.OpticsAllowed(ply, kind)`.
- `G.KitFor(ply)` → set of ids, `G.InBattalion(ply, key)`, `G.Unlocked(ply, id)` → true or false, reason.
- `G.Cfg(key)`: `Rhylib.Config.Get("gear", key)`.
- Server: `G.Apply(ply)` (set bodygroups now), `G.GiveKit(ply)`, `G.SetOptics(ply, kind, fire)`, `G.SetVisor(ply, on)`, `G.SetLights(ply, on)`, `G.LightsAllowed(ply)`, `G.Scan()`.
- Client: `G.NightVision()` → bool, `G.opticsFov`, `G.visorFov`.
- Tables: `G.ITEMS`, `G.SHOWS` (items + backpack + jetpack), `G.ORDER`, `G.ALL_GROUPS`, `G.ON_HELMET`, `G.OPTICS_SLOT`, `G.ZOOM_RANGE`.

### Hooks

This addon fires no hooks of its own. It answers:

- `Rhylib.CanWear(ply, def)` → false, reason (rhylib_inventory): model can't show it, or lights vs optics.
- `Rhylib.GearStockFor(ply, list)`, `Rhylib.GearReturnable(set)` (rhylib_armoury gear cabinet), `Rhylib.CanTakeStock(ply, storage, id)` → false, reason (rank / qualification unlocks).
- `Rhylib.LoadoutDropped(ply, id)` (remembers dropped kit), `Rhylib.InventoryChanged(ply)` (re-applies bodygroups).
- `Rhylib.BlastPartMult(ply, limb)`, `Rhylib.FractureChance(ply, limb)` (rhylib_medical, kama), `Rhylib.ArmorDrainMult(ply)` (rhylib_weapons armour, pauldron).
- `PlayerSwitchFlashlight` (always refuses the engine flashlight and toggles the helmet lights), `EntityTakeDamage` (bare-head headshots, priority 80), `StartCommand`, `CalcView`, and the usual drawing hooks.
- `Rhylib.ModuleLoaded` (registers items once rhylib_inventory is loaded).

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `rhylib.gear.optics` | client → server | UInt 2 kind (0 = down), Bool weapon mode | Optics up / down / mode. Rate 8/s. |
| `rhylib.gear.visor` | client → server | Bool down | Sun visor. Rate 6/s. |
| `rhylib.gear.lights` | client → server | (empty) | Helmet lights on / off (helmet gear key). Rate 4/s. |
| `rhylib.gear.helmet` | client → server | (empty) | Helmet on / off (inventory button). Rate 3/s. |

Networked player state: NW2Int `rhylib_optics` (0 / 1 / 2), NW2Bools `rhylib_opticsFire`, `rhylib_visorDown`, `rhylib_lights`, `rhylib_helmetOff`. Reads rhylib_roster's `rhylib_hair`, `rhylib_fhair`, `rhylib_haircol`, `rhylib_skin`.

### Saved data

`Rhylib.Data` module `"gear"`, key `"kitoff_<SteamID64>"`: `{ [item id] = true }`, kit parts the player dropped (not given again at spawn).

### Examples

**A gear effect from your own addon** (server):

```lua
-- Shoulder antenna: longer radio range (your radio addon)
local function radioRange(ply)
    local G = Rhylib.Gear
    if G and G.Active(ply, "comms") then return 2000 end
    return 1000
end
```

**A new part** for a bodygroup the scan found. Add it to `G.ITEMS` before the items are registered, i.e. after rhylib_gear and before rhylib_inventory have loaded: a shared autorun file whose name sorts between theirs (e.g. `lua/autorun/rhylib_gear_myparts.lua`), or edit `sh_00_config.lua`. Also add it to `G.ORDER` so it can claim its group:

```lua
local G = Rhylib and Rhylib.Gear
if not G then return end   -- rhylib_gear not installed (or not loaded yet)
G.ITEMS.rhylib_backpack_medic = { slot = "back", name = "Medic backpack", desc = "Worn on the back",
    groups = { "backpack", "back" }, on = { "medic_backpack" },   -- (the option name your scan printed)
    w = 2, h = 2, weight = 2, grid = { 3, 3 }, gridName = "backpack", model = "models/props_c17/suitcase001a.mdl" }
G.SHOWS.rhylib_backpack_medic = G.ITEMS.rhylib_backpack_medic
table.insert(G.ORDER, "rhylib_backpack_medic")
G.ALL_GROUPS.backpack, G.ALL_GROUPS.back = true, true
```

Group and option names are lower case without `.smd`, as `rhylib_gear_scan` prints them.

**Lock a part behind a qualification** (host file): `Rhylib.Config.Set("gear", "unlocks", { rhylib_sunvisor = { qual = "arc" } })` (this replaces the whole default list, so copy the entries you want to keep).

## Notes and gotchas

- Option ORDER differs between models (the 327th kama is option 0, the 104th's option 1), so parts are always matched by name. Every group any part uses is set explicitly, to the worn part's option or `empty`.
- `G.ORDER` decides who gets a shared bodygroup: macrobinoculars before the sun visor, and the back items share `backpack` / `back`.
- Items are registered when rhylib_inventory loads (it loads after this addon); the item list can't change after that without a map change.
- Kit changes (`kit`) apply at the next spawn. Old kit is only removed while the player is in a job with a `battalion`, so the cadet job you spawn as after a map change doesn't strip it.
- A model change without a respawn is noticed within a second (1 s timer).
- Night vision is client side only: the light from your eyes isn't seen by anyone else.
- Helmet lights: each lit player costs two projected textures for whoever sees them; `lightMaxPlayers` caps the others drawn per client.
- `bareHeadshotDowns` raises a head hit's damage above health + armour before armour is applied (players already downed are skipped). Head hits come from Rhylib bolts, or the engine's hit group for bullet damage only.
