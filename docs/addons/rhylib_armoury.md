# rhylib_armoury: Armouries, lockers and supply crates

The places troopers get their kit. Staff place a weapons armoury (one of every gun, endless), an ammo cabinet (magazines, cells, rockets, grenades, charges), a gear cabinet (backpacks, jetpacks and wearable gear), specialist racks that only show what your role may take (MP, medic, ...), supply crates and a medical crate that run out, personal lockers players claim and lock, and a training set (training armoury, training ammo, training deposit). Players press E on one and it opens next to their inventory; they drag things out. What comes from an armoury, a cabinet or a rack is "issued": dropping it hands it back. This addon decides what goes where; the storage windows themselves are `rhylib_inventory`'s.

## Requirements

- Required: `rhylib_core`, `rhylib_inventory` (without it, using any armoury just says "Needs rhylib_inventory").
- Works better with: `rhylib_weapons` and `rhylib_republic` (the guns and ammo), `rhylib_medical` (medical crate, medic rack), `rhylib_gear` (gear cabinet parts), `rhylib_mp` (MP rack, searching locked lockers), `rhylib_roster` (qualifications as roles), `rhylib_toolgun` (placing, Permanent tool).
- Workshop content: Reizer's sci-fi props (`models/reizer_props/srsp/sci_fi/...`) for every armoury model. Each model can be changed in Server settings > Models.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_armoury.lua` | shared | Loads the module through `Rhylib.LoadModule`. |
| `lua/rhylib/armoury/sh_00_config.lua` | shared | `Rhylib.Armoury` table, models, entity classes, ammo stock lists, config keys, `A.Roles`. |
| `lua/rhylib/armoury/sv_10_armoury.lua` | server | Builds each armoury's storage, lockers (claim, lock, save), crates, training deposit, saving placements, admin commands. |
| `lua/rhylib/armoury/cl_10_armoury.lua` | client | "Claim this locker?" question and the locker owner's Lock / Unclaim buttons. |
| `lua/entities/rhylib_armoury_base.lua` | shared | Base entity: frozen prop, E to use, name plate. |
| `lua/entities/rhylib_armoury.lua` | shared | Weapons armoury. |
| `lua/entities/rhylib_ammo_cabinet.lua` | shared | Ammo cabinet. |
| `lua/entities/rhylib_gear_cabinet.lua` | shared | Gear cabinet. |
| `lua/entities/rhylib_spec_weapons.lua`, `rhylib_spec_gear.lua` | shared | Specialist armoury (role weapons) and specialist gear (role equipment). |
| `lua/entities/rhylib_crate_small.lua`, `_medium.lua`, `_large.lua` | shared | Supply crates of one magazine size. |
| `lua/entities/rhylib_med_crate.lua` | shared | Medical crate. |
| `lua/entities/rhylib_locker.lua` | shared | Personal locker. |
| `lua/entities/rhylib_training_armoury.lua`, `rhylib_training_ammo.lua`, `rhylib_training_deposit.lua` | shared | Training armoury, training ammo, training deposit (yellow tint). |

## What each one holds

| Entity (class) | Kind | Holds |
|---|---|---|
| Weapons armoury (`rhylib_armoury`) | endless, issued | Every spawnable Rhylib gun (`IsRhylib`, not training, no `NoArmoury`) except role items, DC-15A and DC-15S first, then biggest first. Or the config list `weapons`. |
| Ammo cabinet (`rhylib_ammo_cabinet`) | endless, issued | `A.AMMO_STOCK`: small / medium / large magazines, cells, rockets, grapple hooks, thermal detonators, droid poppers, ammo packs, HE charges (+ rhylib_eod's kits). |
| Gear cabinet (`rhylib_gear_cabinet`) | endless, issued, per player | Config `gearStock` (backpack, jetpack) + what hooks add: with rhylib_gear, the parts your model shows and your rank allows. Takes back any gear part. |
| Specialist armoury (`rhylib_spec_weapons`) | endless, issued, per role set | The `weapons` lists of your roles in config `roles`, minus items you may not hold yet (skill-locked). |
| Specialist gear (`rhylib_spec_gear`) | endless, issued, per role set | The `gear` lists of your roles. |
| Supply crates (`rhylib_crate_small` / `_medium` / `_large`) | finite, crateW × crateH | Full magazines of one size. Empty stays empty until refilled. |
| Medical crate (`rhylib_med_crate`) | finite | Config `medCrate`. Items `Rhylib.ItemDisabled` refuses (e.g. under rhylib_medical's simplified mode) are left out. |
| Personal locker (`rhylib_locker`) | lockerW × lockerH, saved | Claimed by one player (one locker each), lockable. Contents belong to the owner's SteamID. |
| Training armoury (`rhylib_training_armoury`) | endless, issued | Every training gun, or config `trainingWeapons`. |
| Training ammo (`rhylib_training_ammo`) | endless, issued | `A.TRAINING_AMMO_STOCK`: training magazines and rockets, cells, training thermals and poppers. |
| Training deposit (`rhylib_training_deposit`) | per player, saved | Store all / Take all / Empty only. Every deposit on the map shows the same contents for you. What's left after `depositTime` seconds of online time is deleted. |

Roles (`A.Roles`): everyone is `trooper`; `mp` from rhylib_mp, `medic` from rhylib_medical; a DarkRP job's `role = "name"` (or a list); and whatever hook `Rhylib.PlayerRoles` returns (rhylib_roster: qualification ids). Items in any role list are kept out of the weapons armoury.

## For server owners

### Settings

Config module `"armoury"`:

| Key | Default | What it does |
|---|---|---|
| `weapons` | `{}` | Weapon classes in the armoury, in order. Empty = every Rhylib weapon. |
| `trainingWeapons` | `{}` | Weapon classes in the training armoury, in order. Empty = every training weapon. |
| `gearStock` | `{ "backpack", "jetpack" }` | Gear cabinet: equipment it hands out (endless, issued). |
| `lockerW` | `6` | Personal locker width in cells. |
| `lockerH` | `6` | Personal locker height in cells. |
| `depositTime` | `7200` | Training deposit: seconds of online time before what's left in it is deleted. |
| `crateW` | `5` | Supply crate width in cells. |
| `crateH` | `4` | Supply crate height in cells. |
| `medCrate` | `{ { "rhylib_medkit", 10 }, { "rhylib_firstaid", 2 }, { "rhylib_revivekit", 3 }, { "rhylib_antiviral", 20 }, { "rhylib_antidote", 20 }, { "rhylib_antibiotics", 20 }, { "rhylib_splint", 4 }, { "rhylib_burngel", 3 }, { "rhylib_painkiller", 4 }, { "rhylib_bloodpack", 2 }, { "rhylib_med_supplies", 10 }, { "rhylib_blood_kit", 3 }, { "rhylib_test_strip", 5 } }` | What a medical crate is filled with: `{ item, count }`. |
| `roles` | `trooper = { weapons = {}, gear = { "sw_datapad" } }`, `mp = { weapons = { "rhylib_riotshield" }, gear = { "rhylib_stunbaton", "rhylib_handcuffs", "rhylib_flashcharge" } }`, `medic = { weapons = {}, gear = { "rhylib_medkit", "rhylib_firstaid", "rhylib_revivekit", "rhylib_antiviral", "rhylib_antidote", "rhylib_antibiotics", "rhylib_med_supplies", "rhylib_blood_kit", "rhylib_test_strip" } }` | Specialist armoury stock per role: `{ weapons = {...}, gear = {...} }`. |

Change them on the in-game Staff > Server settings page, or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
-- Only these guns in the weapons armoury, in this order:
Rhylib.Config.Set("armoury", "weapons", { "rhylib_dc15a", "rhylib_dc15s", "rhylib_dc17" })

-- A "pilot" role (jobs with role = "pilot") that gets a jetpack from the specialist gear rack.
-- Host files load before rhylib_armoury registers its defaults, so set the whole table
-- (copy the default roles from the row above and add yours):
Rhylib.Config.Set("armoury", "roles", {
    trooper = { weapons = {}, gear = { "sw_datapad" } },
    mp = { weapons = { "rhylib_riotshield" }, gear = { "rhylib_stunbaton", "rhylib_handcuffs", "rhylib_flashcharge" } },
    medic = { weapons = {}, gear = { "rhylib_medkit", "rhylib_firstaid", "rhylib_revivekit", "rhylib_antiviral",
        "rhylib_antidote", "rhylib_antibiotics", "rhylib_med_supplies", "rhylib_blood_kit", "rhylib_test_strip" } },
    pilot = { weapons = {}, gear = { "jetpack" } },
})
```

The lists are read when an armoury is first opened after a map start, so changes show after a map change. Models: Server settings > Models, "Armoury & storage".

### Commands and permissions

Permission `rhylib.armoury.admin` (default: admin). All three also work from the server console.

| Command | What it does |
|---|---|
| `rhylib_armoury_save` | Save every permanent armoury entity on this map (the toolgun's Permanent tool does this for you). |
| `rhylib_crate_refill [all]` | Refill the supply / medical crate you look at, or every crate on the map. |
| `rhylib_locker_unclaim` | Free the locker you look at. Its owner's items stay saved for their next locker. |

Military police (rhylib_mp) may open locked lockers (hook `Rhylib.CanSearchLocker`).

### Placing things / saving

Spawn them from the spawn menu (Rhylib tab, "Armoury & storage" and "Training"; admin only) or the toolgun. Make them permanent with the toolgun's Permanent tool (or `rhylib_armoury_save`): permanent ones are saved per map and come back at every map start and after a cleanup, frozen in place. Lockers keep their owner and lock state. Ones never made permanent are dropped the next time the armouries save.

## For players (short)

- E on an armoury: opens it next to your inventory. Drag out what you need, drag issued things back to hand them in. Right-click queues a quick take.
- E on a free locker: claim it (one per player). The locker window has Lock / Unlock and Unclaim buttons for the owner.
- Training deposit: "Store all" before training, "Take all" after. Cleared after `depositTime` of online time.

## For developers

### Public functions

`Rhylib.Armoury` (`A`):

- `A.Roles(ply)` → sorted list of role names. Shared. `for _, r in ipairs(Rhylib.Armoury.Roles(ply)) do print(r) end`
- `A.Setup(ent)` → storage (server): builds or returns the rhylib_inventory storage for an armoury entity.
- `A.Use(ent, ply)` (server): what E does.
- `A.FillCrate(ent, storage)` (server): refill a crate.
- `A.Claim(ply, ent)`, `A.ToggleLock(ent)`, `A.Unclaim(ent)`, `A.LoadLocker(ent, storage)`, `A.SaveLocker(ent)` (server): lockers.
- `A.SavePlacements()` → count, `A.SpawnPlacements()`, `A.UpdatePlacement(ent)` (server): placements.
- Tables: `A.MODELS`, `A.CLASSES` (saved classes), `A.CRATES`, `A.AMMO_STOCK`, `A.TRAINING_AMMO_STOCK`, `A.FIRST_WEAPONS`, `A.deposits` (server: seconds left per SteamID64).

### Hooks

Fired by this addon (all server, `hook.Run`, so the first answer wins):

- `Rhylib.PlayerRoles(ply)` → list of extra role names (in `A.Roles`, also on the client).
- `Rhylib.GearStock(list)`: add item ids to every player's gear cabinet. `Rhylib.GearStockFor(ply, list)`: add ids for one player (rhylib_gear). `Rhylib.GearReturnable(set)`: `set[id] = true` for ids the cabinet takes back.
- `Rhylib.ItemDisabled(id)` → true leaves an item out of crates and specialist racks (rhylib_medical).
- `Rhylib.CanSearchLocker(ply, ent)` → true lets someone open a locked locker (rhylib_mp).

Listened to: `Rhylib.ModelCatalogue` (models page), `Rhylib.StorageControl` (client, locker buttons), `OnPlayerChangedTeam` (closes an open specialist rack), `PlayerInitialSpawn` / `PlayerDisconnected` (deposit clock), `InitPostEntity` / `PostCleanupMap` (spawn placements).

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `rhylib.armoury.prompt` | server → client | Entity | Ask whether to claim this free locker. |
| `rhylib.armoury.claim` | client → server | Entity | Claim it. Rate 2/s. |
| `rhylib.armoury.control` | client → server | UInt 1: 0 lock / unlock, 1 unclaim | Locker owner's buttons. Rate 3/s. |

### Saved data

`Rhylib.Data` (server):

- `"armoury"` / `<map>`: list of `{ class, pos, ang, owner, ownerName, locked }`.
- `"locker"` / `<SteamID64>`: the player's locker contents (rhylib_inventory storage rows).
- `"train_dep"` / `<SteamID64>`: `{ rows, left }`: training deposit contents and seconds left.

### Examples

**Add an item to the ammo cabinet** (your addon, server or shared, before a cabinet is first opened):

```lua
if Rhylib.Armoury then table.insert(Rhylib.Armoury.AMMO_STOCK, "my_ammo_item") end
```

**Give a role from your own addon:**

```lua
Rhylib.Hook.Add("Rhylib.PlayerRoles", "myaddon.roles", function(ply)
    if ply:GetNW2Bool("my_pilot") then return { "pilot" } end
end)
```

(Only the first hook that returns a list counts: rhylib_roster already answers with qualifications. Adding a qualification id to `roles` may be simpler.)

**A new crate kind:** an entity file `lua/entities/my_grenade_crate.lua`, then add its class to the saved list.

```lua
AddCSLuaFile()
ENT.Type = "anim"
ENT.Base = "rhylib_armoury_base"
ENT.PrintName = "Grenade crate"
ENT.Category = "Rhylib: Armoury & storage"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.ArmouryKind = "crate"
ENT.ModelKey = "crate"
ENT.CrateStock = "grenadeCrate"      -- a config key in module "armoury" holding { { item, count }, ... }
ENT.Hint = "Grenades · Press E"
```

```lua
-- shared, after rhylib_armoury has loaded:
Rhylib.Config.Register("armoury", "grenadeCrate", { { "rhylib_thermal", 6 } }, "What a grenade crate holds")
Rhylib.Armoury.CLASSES.my_grenade_crate = true
table.insert(Rhylib.Armoury.CRATES, "my_grenade_crate")   -- so rhylib_crate_refill works on it
-- server: the Permanent tool must save it with the armoury rows, not the generic list
-- (rhylib_armoury registered its classes when it loaded; without this it is saved twice)
if SERVER and Rhylib.Perma then
    Rhylib.Perma.Register({ "my_grenade_crate" }, Rhylib.Armoury.SavePlacements)
end
```

## Notes and gotchas

- Each armoury builds its stock the first time someone opens it after a map start; config changes and items added later show after a map change.
- Crates fill when first opened, and only `rhylib_crate_refill` fills them again.
- Grenades are not in the weapons armoury (they aren't `IsRhylib`); they come from the ammo cabinet.
- Gear cabinet and specialist racks keep one sub-storage per distinct stock list, so players with the same list share the same view.
- Learning a skill that unlocks a rack item (e.g. the CG shield) shows it on the next open.
- The training deposit only counts online time, checked once a minute.
- `Rhylib.PlayerRoles` is a normal `hook.Run`: only one listener's list is used.
