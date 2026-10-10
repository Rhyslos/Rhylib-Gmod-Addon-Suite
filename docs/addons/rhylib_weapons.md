# rhylib_weapons: Blasters, bolts, armour and the gun base

Rhylib's combat core. It adds the SWEP base every Rhylib gun is built on (`rhylib_base`): bolts that fly as real projectiles instead of hitscan bullets, a three-arc crosshair drawn from the gun's real spread, view recoil you pull down yourself, typed magazines and power cells that come from the inventory, fire modes and safety, a radial reload menu, a grapple hook fire mode, riot shield blocking rules, four-tier armour, explosion knockdowns and a per-gun stats panel (hold C). For server owners it gives one place to tune every gun (Server settings > Gun stats) and the general combat numbers. The guns themselves (DC-15A, DC-15S, DC-17, Z-6, RPS-6...) are in **rhylib_republic**; this addon has no spawnable gun of its own except the ammo pack.

## Requirements

- **Required:** `rhylib_core`.
- **Recommended:** `rhylib_republic` (the actual guns), `rhylib_inventory` (magazines and cells become inventory items; without it a simple per-player pouch is used), `rhylib_hud` (ammo counter), `rhylib_menus` (settings rows, interaction wheel), `rhylib_skills` (skill-gated modes, ammo pack).
- **Workshop content:** "[TFA] StarWars Reworked Shared Resources and Assets" (1741985166) for the first-person carrier viewmodels and all gun / impact sounds (without it the sounds are silent and guns float in first person). The default first-person arms (`models/aussiwozzi/cgi/base/trooper_arms.mdl`) need that clone model pack. Gun prop models (jajoff TC-13J) are listed by rhylib_republic.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_weapons.lua` | shared | Loads the module through rhylib_core. |
| `lua/weapons/rhylib_base.lua` | shared | The SWEP base: firing, fire modes, safety, sprint lowering, reloads, aiming, scope, first-person carrier/prop drawing, dual pistols, proxies, extra props, the editors (`rhylib_vm_editor`, `rhylib_wm_editor`, `rhylib_extra_editor`). |
| `lua/weapons/rhylib_ammo_pack.lua` | shared | Ammo pack (skill item): tops up a teammate's magazines. |
| `lua/entities/rhylib_item_base.lua` | shared | Base for pick-up items (E to take). |
| `lua/entities/rhylib_item_*.lua` | shared | Pick-ups: small/medium/large magazine, rocket, power cell, grapple hook (`rhylib_item_mag` is an old name). |
| `lua/entities/rhylib_rope.lua` | shared | A laid grapple rope (points in network vars, no physics). |
| `rhylib/weapons/sh_00_config.lua` | shared | `Rhylib.Weapons`, config module `weapons`, magazine types `W.MagTypes`, ammo types, inventory items. |
| `rhylib/weapons/sh_10_spread.lua` | shared | Spread and crosshair kick maths (`W.Spread`), predicted. |
| `rhylib/weapons/sh_20_move.lua` | shared | `SWEP:GetMoveMult()` slows the holder (Z-6 spin). |
| `rhylib/weapons/sh_30_grapple.lua` | shared | Grapple settings, rope maths, predicted climbing. |
| `rhylib/weapons/sh_40_armor.lua` | shared | Armour tiers (`Rhylib.Armor`), config module `armor`. |
| `rhylib/weapons/sh_50_compat.lua` | shared | Removes the TFA "install TFA Base" popup and hides TFA weapons when TFA Base isn't installed. |
| `rhylib/weapons/sh_60_shield.lua` | shared | Riot shield blocking rules (`W.ShieldBlocks` etc.). |
| `rhylib/weapons/sh_70_gunstats.lua` | shared | Per-gun stats as settings (config module `guns`). |
| `rhylib/weapons/sv_10_bolts.lua` | server | Bolt simulation, hits, damage, shot events, `rhylib_boltrange`. |
| `rhylib/weapons/sv_20_pouch.lua` | server | Where magazines/cells come from (`W.Pouch`), fire mode / reload requests, `rhylib_infammo`. |
| `rhylib/weapons/sv_30_grapple.lua` | server | Firing the hook and laying the rope. |
| `rhylib/weapons/sv_40_armor.lua` | server | Replaces the engine's armour maths. |
| `rhylib/weapons/sv_50_hands.lua` | server | First-person arms model. |
| `rhylib/weapons/sv_60_knockdown.lua` | server | Explosion knockdowns. |
| `rhylib/weapons/cl_10_bolts.lua` | client | Drawing bolts, impacts, near-miss whizz. |
| `rhylib/weapons/cl_20_crosshair.lua` | client | The crosshair, hit markers, crosshair settings. |
| `rhylib/weapons/cl_30_reload.lua` | client | R key: reload, radial menu, fire mode / safety keys. |
| `rhylib/weapons/cl_40_grapple.lua` | client | Grapple landing marker, belt line. |
| `rhylib/weapons/cl_50_recoil.lua` | client | View recoil. |
| `rhylib/weapons/cl_70_stats.lua` | client | Hold C: weapon stats panel. |

## For server owners

### Settings

Change them in game on **Staff > Server settings** (superadmin), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`), e.g.

```lua
Rhylib.Config.Set("weapons", "headMult", 2.5)
Rhylib.Config.Set("armor", "spawnArmor", 150)
Rhylib.Config.Set("guns", "dc15a_damage", 40)
```

#### Config module "weapons"

| Key | Default | What it does |
|---|---|---|
| `handsModel` | `"models/aussiwozzi/cgi/base/trooper_arms.mdl"` | First-person arms for everyone (a c_arms model; a DarkRP job's `handsModel` overrides it; `""` = the player model's own). |
| `lagCompMax` | `0.35` | Max seconds (ping + interpolation) covered by lag compensation on a bolt's first leg. |
| `boltSpeedMult` | `1.3` | Multiplies every gun's bolt speed (rockets aren't scaled). |
| `recoilMult` | `1` | Multiplies every gun's view recoil (`SWEP.Recoil`). |
| `crouchSpread` | `0.8` | Spread while crouched on the ground, as a share of the standing cone (1 = no bonus). |
| `firstShotMult` | `0.35` | Spread of a first shot from rest (0.35 s without firing), as a share of the normal cone. |
| `shotRange` | `6000` | Players further than this (units) from a shot don't receive it (don't see the bolt). |
| `boltRange` | `0` | Bolts stop after this many units; 0 = off. Scoped guns and rockets never stop early. Also set live with `rhylib_boltrange`. |
| `boltLife` | `1.2` | Seconds before a bolt that hit nothing disappears (a gun's `BoltLife` overrides it). |
| `headMult` | `2` | Damage multiplier for head hits. |
| `limbMult` | `0.75` | Damage multiplier for arm and leg hits. |
| `knockMin` | `30` | Explosions: damage (before armour) that knocks a player down. |
| `knockTimeMin` | `2` | Explosions: shortest knockdown (seconds). |
| `knockTimeMax` | `8` | Explosions: longest knockdown (random in between; 0 = knockdowns off). |
| `knockPush` | `260` | Explosions: how hard the body is thrown (units/s, up to 2.5x for big hits). |
| `knockDropChance` | `0.1` | Explosions: chance a knocked-down player drops the gun in their hands (0-1). |
| `lowCellThreshold` | `0.1` | Below this power cell charge (0-1), damage starts to drop. |
| `lowCellMinDamage` | `0.5` | Damage multiplier when the power cell is completely drained. |
| `reloadHoldTime` | `0.2` | Seconds R must be held to open the reload menu. |
| `maxMags` | `12` | Without rhylib_inventory: spare magazines of each type a player can carry. |
| `maxCells` | `4` | Without rhylib_inventory: spare power cells a player can carry. |
| `shieldArc` | `60` | Riot shield aimed: blocks bolts within this many degrees of straight ahead. |
| `shieldSideCenter` | `55` | Riot shield not aimed: middle of the covered wedge, degrees left of where you look. |
| `shieldSideArc` | `30` | Riot shield not aimed: width of that wedge (degrees). |
| `cgShieldArc` | `75` | CG riot shield aimed: front cone (degrees). |
| `cgShieldSideArc` | `50` | CG riot shield not aimed: wedge width (degrees). |
| `cgShieldBlast` | `0.5` | CG riot shield aimed at an explosion: damage multiplier (breaching charges are stopped by either shield). |
| `phalanxRange` | `140` | Phalanx skill: covers teammates up to this far behind the shield (units). |
| `phalanxWidth` | `40` | Phalanx skill: how far to the side of the shield's line a teammate is covered (units). |

Other addons add more keys to the `weapons` module (rhylib_republic's grenades and charges, for example); they are documented there.

#### Config module "armor"

| Key | Default | What it does |
|---|---|---|
| `mitigation` | `{ 0.15, 0.30, 0.45, 0.60 }` | Share of damage blocked per tier (tier 1 = last quarter of armour ... tier 4 = above 75%). |
| `drain` | `0.5` | Armour lost per point of incoming damage, before mitigation, rounded up. |
| `spawnArmor` | `100` | Armour players spawn with (a DarkRP job's `armor = N` overrides it). |
| `bypass` | `DMG_FALL + DMG_DROWN + DMG_POISON + DMG_RADIATION` | Damage types armour ignores. |

At 0 armour a hit does full damage. Downed players (rhylib_medical) skip armour.

#### Config module "grapple"

| Key | Default | What it does |
|---|---|---|
| `range` | `1500` | Max distance the hook flies (units, about 30 m). |
| `ropeMax` | `2500` | Max rope length down from the hook (units). |
| `climbUp` | `140` | Climbing speed up (units/s). |
| `climbDown` | `220` | Climbing speed down (units/s). |
| `maxClimbers` | `3` | Players on one rope at once. |
| `maxRopes` | `64` | Ropes on the map at once; new hooks won't grip past this. |
| `attachDist` | `56` | How close you must be to clip on (units). |
| `cooldown` | `1` | Seconds between grapple shots. |
| `showLanding` | `true` | Show where the hook will land in grapple mode. |
| `hookSpeed` | `2500` | How fast the hook flies (units/s). |
| `lowerSpeed` | `450` | How fast the rope lowers after the hook grips (units/s). |

#### Config module "skills" (ammo pack, registered here)

| Key | Default | What it does |
|---|---|---|
| `ammoPackPool` | `300` | Rounds in a full ammo pack. |
| `ammoPackLargeCost` | `0.72` | Pool cost of one large-magazine round. |

#### Config module "guns" (per gun)

Made at map load for every gun built on `rhylib_base` (not training copies, the toolgun, riot shields, grenades, or guns with `SWEP.NoGunStats`). Key = gun class without `rhylib_` plus a stat, e.g. `dc15a_damage`. Stats: `_damage`, `_rpm`, `_boltSpeed`, `_reload`, `_spreadHip`, `_spreadAim`, `_bloomPerShot`, `_bloomMax`, `_kickMain`, `_kickSide`, `_recoilUp`, `_recoilSide`. Defaults are the numbers in each weapon file. A change applies at once to guns already held, and to training copies that don't set the value themselves. Limits: rpm 1-6000, reload 0.05-30 s, bolt speed 100-32767, bloom up to 5.1, kicks up to 10.2.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_boltrange [units]` | perm `rhylib.weapons.boltrange` (admin), or server console | No number: shows the bolt reach cap. A number: sets it (0 = off) and saves it (Data `weapons`/`boltRange`). |
| `rhylib_infammo` | perm `rhylib.weapons.infammo` (admin) | Toggles test ammo for yourself: shots use nothing, reloads are free and full. |
| `rhylib_vm_editor` | client, anyone | First-person tuning window for the gun in your hands (see "Making your own gun"). |
| `rhylib_wm_editor` | client, anyone | Third-person tuning window with an orbit camera. |
| `rhylib_extra_editor` | client, anyone | Extra props (shields), carrier arm moves, third-person arm turns. |
| `rhylib_vm_info`, `rhylib_vm_bones` | client | Print the viewmodel's bones (the carrier's gun bone is marked). |
| `rhylib_vm_aim x y z`, `rhylib_vm_fov n`, `rhylib_vm_tune x y z p y r` | client | Older one-line tuning commands; they print the line for the weapon file. |

The editors only change your own copy of the weapon until it's removed; nothing reaches the server or other players.

### Placing things / saving

Pick-ups (`rhylib_item_mag_small/medium/large`, `rhylib_item_rocket`, `rhylib_item_cell`, `rhylib_item_grapple`) are in the spawn menu under "Rhylib: Items & ammo". Grapple ropes are made by players and are never saved. Nothing else here is placed.

## For players (short)

| Key | What it does |
|---|---|
| Left mouse | Fire. Semi and burst need a fresh pull; auto keeps firing. |
| Right mouse (hold) | Aim: slight zoom, tighter spread. Scoped guns look through the scope. |
| R (tap) | Reload the best magazine (same type if you have one). |
| R (hold) | Radial menu: pick a magazine type or a power cell, release R on it. Middle = cancel. |
| E + R | Next fire mode (semi, auto, burst, dual, stun, grapple...). |
| Shift + E + R | Safety on/off (gun lowered, can't fire). |
| Sprint | Lowers the gun; it comes back up a moment after you stop. |
| C (hold) | Weapon stats panel with your skills applied. |
| Grapple mode, fire | Shoots the hook. E near the rope clips on, W/S climb, Jump lets go, E unclips; keep pushing W at the top to climb over. E on the hook picks it back up. |

Settings > Interface, "Weapons" section: crosshair style, colour, centre size, outline, hit markers, thickness, opacity; hit sounds are in Settings > Audio. Client convar `rhylib_whizz 0` turns off near-miss sounds.

## For developers

### Public functions

All on `Rhylib.Weapons` (`W`) unless named otherwise.

| Function | Realm | Returns / does |
|---|---|---|
| `W.Bolts.Fire(owner, weapon, origin, dir, damage, opts, hits)` | server | Fires one bolt. `weapon` may be a plain table with `BoltSpeed`, `BoltColor`, `Damage` (NPCs do this). `opts`: `speed`, `color`, `life`, `stun`, `training`, `onHit(bolt, tr)`, `onExpire(bolt)`. |
| `W.Bolts.ApplyHits(hits)` | server | Applies first-leg hits queued by `Fire(..., hits)` (several pellets under one lag compensation). |
| `W.Bolts.Speed(weapon)` | server | `BoltSpeed` x `boltSpeedMult` (rockets not scaled). |
| `W.Bolts.Spawn(shooter, origin, dir, speed, color, left, ahead)` | client | Draws a visual bolt. |
| `W.TrainingBlast(pos, radius, damage, attacker, inflictor)` | server | Training explosion: sim health for players, real damage to training droids. True if a hit marker was sent. |
| `W.BoltRange()` | shared | Bolt reach cap in units (0 = none). |
| `W.Pouch.Count(ply, kind)` / `Add(ply, kind, fill, force, issued)` / `TakeBest(ply, kind)` | server | Magazines, cells and hooks the player carries (inventory or fallback pouch). `kind` = `"mag_small"`, `"cell"`, `"grapple"`... |
| `W.BaseMag(id)`, `W.TrainingMag(id)` | shared | Map between a magazine and its training copy (`"mag_small"` <-> `"mag_small_t"`). |
| `W.Spread.MeanCone(wep, t)`, `BaseCone(wep)`, `SkillMult(wep)`, `StanceMult(ply)` | shared | Cone sizes in degrees (see sh_10_spread.lua for the rest). |
| `W.Crosshair.Draw(wep, x, y)` | client | Draws the crosshair at x, y. |
| `W.Recoil.Kick(wep)` | client | Adds one shot's view kick. |
| `W.ShieldUp(ply)`, `ShieldAimed`, `ShieldProficient`, `ShieldFaces(ply, dir)`, `ShieldBlocks(ply, dir)`, `ShieldNear(ply, pos)` | shared | Riot shield rules. |
| `W.Grapple.Attached(ply)`, `Detach(ply, mv, push)`, `CanGrip(tr)`, `Climbers(rope)` | shared | Grapple state. `G.Fire`, `G.BuildRope`, `G.DropHook` are server. |
| `W.GunStats.Apply(class)` | shared | Re-applies the `guns` settings of one gun. |
| `Rhylib.Armor.Tier(armor, max)`, `Mitigation(armor, max)` | shared | Armour tier 0-4 and share blocked. |
| `Rhylib.Armor.Get(ply)` | server | Armour counting a hit still being worked out; use it in damage hooks instead of `ply:Armor()`. |
| `Rhylib.Armor.SpawnArmor(ply)` | server | Armour this player spawns with. |

SWEP methods meant for other code are listed in the header of `rhylib_base.lua` (`GetFireModeName`, `GetMag`, `GetMagSize`, `IsLowered`, `StartReload`, `GetInventoryData`...).

### Hooks

Fired by this addon (all with `hook.Run`, so `Rhylib.Hook.Add` or `hook.Add` both work):

| Hook | When | Return value |
|---|---|---|
| `Rhylib.TrainingHit(ply, attacker, damage, inflictor, group)` | A training bolt or blast hits a player. | `true` = they were eliminated (kill marker), `false` = ignored (no marker). rhylib_training answers it. |
| `Rhylib.StunHit(ply, attacker, weapon)` | A stun bolt hits a player. | Ignored. rhylib_mp does the stun. |
| `Rhylib.Explosion(pos, reach, tier, attacker, inflictor, kind)` | A real rocket explodes (`kind` = `"rocket"`, tier from `SWEP.Explosive.tier`, default 2). | Ignored. |
| `Rhylib.ArmorDrainMult(ply)` | Each hit that costs armour. | A number scales the armour cost. |
| `Rhylib.CanKnockDown(ply)` | Before an explosion knockdown. | `false` stops it. |

Listened to: `Rhylib.InventoryChanged` (mirror counts, leave dual mode when a pistol goes), `Rhylib.InventoryWeaponPickup` (start ammo), `Rhylib.SkillsChanged` (Phalanx holders), `Rhylib.ConfigChanged` (`guns` module), plus engine hooks (Tick, SetupMove, EntityTakeDamage at 90/100/-100, PostEntityTakeDamage at -500/-1000, PlayerSpawn, CreateMove at -20, CalcView at -60 for the editor camera).

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `wep.shot` | server -> players near the shot | batch: shooter UInt 13, origin Vector, dir Normal, speed UInt 15, color UInt 4, left Bool, ahead UInt 6 (1/100 s) | Other players draw the bolt. One group per 1024-unit cube per tick; the shooter is skipped. |
| `wep.hit` | server -> shooter | batch: kind UInt 2 (0 body, 1 head, 2 down/kill) | Hit marker and sound. |
| `wep.mode` | client -> server | safety Bool | E + R / Shift + E + R. Rate 4/s. |
| `wep.reload` | client -> server | req UInt 4 (0 best, 1-14 magazine index, 15 cell) | Reload request. Rate 4/s. |
| `wheel.supply` | client -> server | target Entity | Ammo pack from the interaction wheel. Rate 2/s. |

Network vars on the weapon: `Recoil`, `RecoilB` (packed kicks and bloom), `KickTime`, `ReloadEnd`, `Cell`, `SpinStart`, `ReloadKind`, `FireMode`, `BurstLeft`, `MagType`, `ReloadMag`, `Aiming`, `Safety`, `TriggerReady`, `Lowered`. On the player: DTEntity 31 / DTFloat 27 / DTBool 27 (grapple), NW2Bool `rhylib_infammo`. Global2Int `rhylib_boltRange`.

### Saved data

| Data module / key | What |
|---|---|
| `weapons` / `boltRange` | The bolt reach cap set with `rhylib_boltrange`. |

Clip, magazine type, cell, fire mode and safety of a stored gun live in its inventory item (`SWEP:GetInventoryData`), saved by rhylib_inventory.

### Examples

React to rockets from your own addon:

```lua
Rhylib.Hook.Add("Rhylib.Explosion", "myaddon.rockets", function(pos, reach, tier, attacker, inflictor, kind)
    if kind ~= "rocket" then return end
    -- e.g. break your own entities within reach
end)
```

A gear item that makes armour last longer (like rhylib_gear's pauldron):

```lua
Rhylib.Hook.Add("Rhylib.ArmorDrainMult", "myaddon.plating", function(ply)
    if ply:GetNW2Bool("myaddon_plating") then return 0.7 end
end)
```

Fire a bolt from an NPC or a turret (server):

```lua
local GUN = { BoltSpeed = 6000, BoltColor = 2, Damage = 15 }
local from = turret:GetPos() + Vector(0, 0, 40)
Rhylib.Weapons.Bolts.Fire(turret, GUN, from, (target:EyePos() - from):GetNormalized())
```

A training copy of a gun (the whole file):

```lua
AddCSLuaFile()
SWEP.Base = "rhylib_mygun"
SWEP.PrintName = "My gun (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.Training = true
SWEP.TrainingOf = "rhylib_mygun"
SWEP.BoltColor = 7                       -- training yellow
SWEP.InvCategory = "training"
SWEP.Mags = { "mag_medium_t" }           -- training magazines only
SWEP.FireModes = { "semi", "auto" }      -- no stun mode
```

## Making your own gun

A gun is one file in `lua/weapons/` of your own addon, named after its class (`lua/weapons/rhylib_mygun.lua` makes `rhylib_mygun`). It only sets fields; all behaviour comes from `rhylib_base`. Start from a copy of a rhylib_republic gun that is close to what you want, or from the file below.

Rules that catch people out:

- **`Primary`, `Secondary`, `Spread` and `Recoil` are not merged with the base.** If you set one, write the whole table.
- `Primary.Automatic` must stay `true`; `FireModes` decides semi/auto.
- Keep `Primary.ClipSize` / `DefaultClip` equal to the rounds of `Mags[1]` (a gun spawned from the menu comes loaded; spare magazines come from the inventory).
- The class name should start with `rhylib_` if you want it to get Server settings > Gun stats keys and model overrides.
- A gun file is shared: keep `AddCSLuaFile()` at the top.

### Example file

```lua
--[[
    My blaster carbine: an example gun on the Rhylib base.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_base"
SWEP.PrintName = "MK-1 carbine"
SWEP.Category = "Rhylib: Carbines"     -- spawn menu category
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.InvGroup = "carbine"              -- armoury shelf: rifle, carbine, pistol, heavy, shotgun, sniper
SWEP.HoldType = "ar2"                  -- third-person hold ("pistol", "smg", "ar2", "rpg"...)
SWEP.Slot = 2

---------------------------------------------------------------- models
-- The gun itself is a plain prop model (no arms, no animations).
SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/dc15s.mdl"
SWEP.WorldModel = SWEP.PropModel       -- inventory pictures and the dropped gun
SWEP.PropScale = 1                     -- third-person size (and first person if PropBoneScale is nil)
SWEP.PropMuzzle = Vector(20, 0, 2)     -- muzzle in the prop's own coordinates (bolts leave here)

-- First person: a "carrier" c_ viewmodel plays its animations with the
-- player's hands. Its gun bone is shrunk away and the prop drawn on it.
-- If the carrier model isn't installed, the prop floats at PropVMPos/Ang
-- and ViewModel is shown as a placeholder.
SWEP.ViewModel = "models/weapons/c_smg1.mdl"             -- placeholder only
SWEP.UseHands = false                                    -- (turned on when the carrier is used)
SWEP.CarrierVM = "models/bf2017/c_e11.mdl"               -- from Reworked Assets (Workshop 1741985166)
SWEP.CarrierBone = "v_e11_reference001"                  -- its gun bone (rhylib_vm_info lists the bones)
SWEP.CarrierBoneMove = nil                               -- optional Vector to move that bone
SWEP.PropBonePos = Vector(0, 0, 0)     -- prop from the gun bone: forward, right, up (tune in game)
SWEP.PropBoneAng = nil                 -- nil = worked out once so it points straight ahead (printed to console)
SWEP.PropBoneScale = 1                 -- first-person size
SWEP.VMOffset = nil                    -- whole viewmodel: right, forward, up (nil = matched to PropVMPos once)
SWEP.CarrierFOV = 54                   -- viewmodel FOV with the carrier
SWEP.PropVMPos = Vector(18, 7, -8)     -- floating prop: forward, right, up (also the target for VMOffset = nil)
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(0, 0, 0)       -- third person: forward, right, up from the right hand
SWEP.PropWMAng = Angle(0, 0, 0)
SWEP.ReloadTime = 2                    -- seconds; nil = the carrier's reload animation length
-- SWEP.SafePose = { PropBonePos = ..., PropBoneAng = ..., VMOffset = ..., CarrierFOV = ... }
--     optional pose while lowered (safety, sprint); rhylib_vm_editor opened while lowered edits it
-- SWEP.SafeBlendTime = 0.2

SWEP.AimPos = Vector(-2, 0, 1)         -- viewmodel offset while aiming: right, forward, up
SWEP.AimFov = 0.85                     -- zoom while aiming (FOV multiplier)

---------------------------------------------------------------- ammo
SWEP.Primary = {                       -- whole table (not merged with the base)
    ClipSize = 60,                     -- rounds of Mags[1]
    DefaultClip = 60,
    Automatic = true,                  -- must stay true
    Ammo = "rhylib_mag_medium",        -- mirror ammo type of Mags[1] (HUD)
}
SWEP.Secondary = {
    ClipSize = -1, DefaultClip = -1, Automatic = true,
    Ammo = "rhylib_cell",              -- "none" if the gun has no power cell
}
SWEP.Mags = { "mag_medium", "mag_small" }   -- magazine types it takes, preferred first
                                            -- (mag_small 30, mag_medium 60, mag_large 250, rocket 1)
SWEP.ClipCap = nil                     -- most rounds loaded from one magazine (DC-15X: 15)
SWEP.UsesCell = true                   -- also drains a power cell
SWEP.CellShots = 500                   -- shots from a full cell
SWEP.CellReloadMult = 1.6              -- a cell swap takes this much longer than a magazine
SWEP.StartMags = 4                     -- spare magazines given on pickup (testing)
SWEP.StartCells = 1
SWEP.AutoReload = false                -- true = reloads by itself when empty

---------------------------------------------------------------- firing
SWEP.Damage = 25                       -- per bolt (x head 2 / limb 0.75, config)
SWEP.FireRate = 500                    -- rounds per minute
SWEP.BoltSpeed = 7000                  -- units/s (x boltSpeedMult; max 32767)
SWEP.BoltColor = 1                     -- 1 blue, 2 red, 3 green, 7 training yellow...
SWEP.BoltLife = nil                    -- seconds; nil = config boltLife
SWEP.FireSound = "weapons/dc15s/dc15s_fire.ogg"   -- or a list: one is picked per shot
SWEP.FireSoundLevel = 140              -- dB (140 carries like real gunfire)
SWEP.FireSoundPitch = 1
SWEP.ReloadSound = nil                 -- nil = the standard reload sound

-- Fire modes, first = default. E + R cycles. "auto" and "overcharge" keep
-- firing; every other mode is one shot per pull. "burst" uses BurstCount,
-- BurstDelay, BurstFireRate. "stun" is military police only (rhylib_mp).
-- "dual" needs two of the gun carried (DualMirror / DualHoldType...).
SWEP.FireModes = { "semi", "auto", "stun" }
SWEP.SkillModes = { auto = "full_auto" }   -- modes that need a rhylib_skills skill (id)
SWEP.Grapple = true                    -- adds a "grapple" mode while a grapple hook is carried

-- Optional extras:
-- SWEP.Pellets = 6                    -- shotgun: bolts per shot, one round each
-- SWEP.PelletCone = 4.5               -- their extra spread (degrees)
-- SWEP.Explosive = { radius = 200, damage = 250, tier = 2 }   -- rocket: blast where it hits
-- SWEP.Scope = true                   -- aiming looks through a scope (AimFov is the zoom)
-- SWEP.ScopeSkill = "long_gun"        -- skill needed for the scope
-- SWEP.SpinUp = 0.6                   -- rotary: hold fire this long before it shoots
-- SWEP.SpinMoveMult = 0.6             -- walk speed while spinning
-- SWEP.Stun = true                    -- every bolt is a stun bolt

---------------------------------------------------------------- accuracy
-- View recoil per shot (whole table): degrees up, random sideways,
-- lean (-1 left .. 1 right), share that settles back, multiplier while aiming.
SWEP.Recoil = { up = 0.6, side = 0.25, bias = 0, recover = 0.6, aimMult = 0.65 }

-- Spread in degrees (whole table). The crosshair is drawn from these.
SWEP.Spread = {
    hip = 1.4,                         -- resting cone, hip-fire
    aim = 0.7,                         -- resting cone, aiming
    kickMain = 0.35,                   -- crosshair kick on the arc nearest the shot
    kickSide = 0.1,                    -- kick on the other two arcs
    bloomPerShot = 0.11,               -- shared bloom per shot
    bloomMax = 2.0,                    -- (max 5.1)
    aimKickMult = 0.5,                 -- kicks and bloom while aiming
    aimOffsetMult = 0.6,               -- arc offsets while aiming
}

---------------------------------------------------------------- inventory
SWEP.InvW = 3                          -- size in inventory cells
SWEP.InvH = 1
SWEP.InvLarge = false                  -- true: too big for a backpack, can't fire while flying a jetpack
SWEP.InvWeight = 3                     -- kg
-- SWEP.CarrySkill = "some_skill"      -- only players with this skill may carry it (rhylib_skills)
-- SWEP.NoArmoury = true               -- keep it out of the weapons armoury
-- SWEP.NoGunStats = true              -- no Server settings > Gun stats keys
```

The skill ids in `SkillModes`, `ScopeSkill` and `CarrySkill` come from rhylib_skills (`K.NODES`); without that addon nothing is gated.

### Tuning the viewmodel (first person): `rhylib_vm_editor`

1. Join a local or test server, take the gun out, open the console and run `rhylib_vm_editor`.
2. With a carrier in use the window edits the gun on the hands' gun bone: Forward / Right / Up / Pitch / Yaw / Roll / Size (`PropBonePos`, `PropBoneAng`, `PropBoneScale`). Without a carrier it edits the floating gun (`PropVMPos`, `PropVMAng`).
3. "Hands and gun on screen" moves the whole viewmodel (`VMOffset`). "Point the gun straight ahead" works out `PropBoneAng` again; "Move to the old floating gun position" works out `VMOffset` so the gun sits at `PropVMPos`.
4. "Aiming" edits `AimPos`; tick **Preview aim** to see it without holding right mouse. "Viewmodel" FOV edits `CarrierFOV`.
5. Type a value and press Enter, or use - / +. Changes show at once.
6. **Copy lines for the weapon file** puts the lines on the clipboard (also printed in the console). Paste them over the old values in your gun file.

Special cases: open the editor while the gun is lowered (safety on: Shift + E + R) to edit `SafePose`; in a fire mode drawn on another viewmodel (`ModeProxies`) it edits that block; dual-pistol guns with `DualMirror` get left-pistol fields. On grenades (not Rhylib guns) it edits `PropVMPos` / `PropVMAng` / `PropVMScale` on the grenade bone. `rhylib_vm_info` lists the viewmodel's bones (the gun bone is marked), which is how you find `CarrierBone` for a new carrier.

### Tuning the world model (third person): `rhylib_wm_editor`

1. Take the gun out and run `rhylib_wm_editor`.
2. The camera circles your right hand: preset buttons (Front, Back, Left, Right, Top, Below), drag the pad to turn, mouse wheel or the slider to zoom. Untick "Orbit camera on" for your normal view.
3. Edit Forward / Right / Up / Pitch / Yaw / Roll / Size (`PropWMPos`, `PropWMAng`, `PropScale`). Guns with a left pistol (`DualPropWMPos`) get its fields too; switch to dual to see it.
4. **Copy lines for the weapon file** and paste them in.

Check the gun in a few poses (standing, crouching, lowered) since the hold type moves the hand. Clone NPCs (rhylib_droids) that carry a gun with the same `PropModel` use these third-person values too.

Shields and other extra props (`SWEP.ExtraProps`) are tuned with `rhylib_extra_editor` the same way.

## Notes and gotchas

- **Tables don't merge.** A derived gun that sets `Spread.hip` alone loses every other spread field. Copy the whole table.
- **Bolts are not bullets.** They're table rows moved each tick on the server, with one lag-compensated first leg. `FireBullets` hooks (EntityFireBullets) never see them; damage arrives as `DMG_BULLET` (`DMG_BLAST` for rockets) through `TakeDamageInfo`.
- **Hit markers only for living things.** Bolt hits on props give no marker.
- **Clients only see shots within `shotRange`** (6000 units) of where the shot starts.
- **Armour is set to 0 during a hit** so the engine skips its own maths. In EntityTakeDamage / PostEntityTakeDamage hooks read `Rhylib.Armor.Get(ply)`, not `ply:Armor()`.
- **`rhylib_boltrange` wins over host files.** A value saved with the command is loaded at InitPostEntity and set with `Config.Set`, so it replaces what a host file set (an in-game override on the Server settings page still wins over both).
- **Gun stats keys appear at map load** (InitPostEntity), after host files run; `Rhylib.Config.Set("guns", ...)` in a host file still works because Get reads it then.
- **Sounds and carriers need the Reworked Assets pack** (Workshop 1741985166) as a required item, or guns are silent and float in first person.
- **Without rhylib_inventory** magazines live in a per-player pouch that empties on respawn (`maxMags` / `maxCells` limits) and picking a gun up gives `StartMags` / `StartCells`.
- **Editors are local.** They change only your client's copy; nothing is saved until you paste the lines into the file.
- **`VMOffset = nil` / `PropBoneAng = nil`** are worked out on the first idle frame and printed to the console (`[Rhylib] class: SWEP.VMOffset = ...`); paste the printed line into the file so it doesn't change between sessions.
