# rhylib_republic: Republic weapons, grenades and shields

The Republic's guns and explosives for Rhylib. Players get the clone blasters (DC-15A, DC-15S, DC-17, DC-15X, DP-23, DP-24, Westar-M5, Z-6), the RPS-6 rocket launcher with a lock-on / laser-guided mode, the T-19 grenade launcher, thermal detonators (timed, impact or breaching charge), droid poppers (EMP), the MP flash charge, the high explosive charge for demolition, and two riot shields. Every gun has a yellow training copy whose shots only take "sim health". For a server owner it is a content addon: there are no module files, only weapons, entities and one effect. The guns run on `rhylib_weapons`' gun base (`rhylib_base`): bolts, spread, recoil, magazines and the crosshair all live there. This addon only sets each gun's numbers and adds the special weapons.

## Requirements

- Required: `rhylib_core`, `rhylib_weapons` (the gun base, bolts, magazine types, shields' blocking code).
- Works better with: `rhylib_inventory` (grenades, magazines and shields as items), `rhylib_armoury` (where players draw them), `rhylib_skills` (fire modes and items behind skills), `rhylib_mp` (stun, flash charge), `rhylib_droids` (EMP, lock-on targets), `rhylib_radio` (jammers that explosions damage), `rhylib_training` (sim health), `rhylib_menus` (HE charge timer window, bash key setting).
- Workshop content (required items for clients):
  - the jajoff TC-13J weapon models (`models/jajoff/sps/cgiweapons/tc13j/...`): every gun and the thermal detonator;
  - "[TFA] StarWars Reworked Shared Resources and Assets" (1741985166): the first-person hands viewmodels (`models/weapons/synbf3/...`, `models/bf2017/...`) and the gun sounds;
  - cs574's shields pack (`models/cs574/weapons/shields/...`): both riot shields. Older shield packs are used as fallbacks if it's missing.
- HL2 / GMod content is used for the RPS-6 hands (`c_rpg`), the grenade hands (`c_grenade`), the HE charge (`w_slam`) and the top-attack rocket.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/weapons/rhylib_dc15a.lua` | shared | DC-15A blaster rifle. |
| `lua/weapons/rhylib_dc15s.lua` | shared | DC-15S blaster carbine (also the base of both shields). |
| `lua/weapons/rhylib_dc17.lua` | shared | DC-17 blaster pistol, with the dual-pistol mode. |
| `lua/weapons/rhylib_dc15x.lua` | shared | DC-15X sniper rifle with a scope. |
| `lua/weapons/rhylib_dp23.lua` | shared | DP-23 blaster carbine. |
| `lua/weapons/rhylib_dp24.lua` | shared | DP-24 blaster shotgun (6 bolts a shot). |
| `lua/weapons/rhylib_westarm5.lua` | shared | Westar-M5 blaster rifle. |
| `lua/weapons/rhylib_z6.lua` | shared | Z-6 rotary blaster cannon (spins up). |
| `lua/weapons/rhylib_rps6.lua` | shared | RPS-6 rocket launcher, lock-on mode, lock-on HUD and its settings. |
| `lua/weapons/rhylib_grenade_launcher.lua` | shared | T-19 grenade launcher (fires thermal detonator items). |
| `lua/weapons/rhylib_riotshield.lua` | shared | CG riot shield + DC-15S: shield props, bash, bash key. |
| `lua/weapons/rhylib_riotshield_rep.lua` | shared | Republic shield + DC-15S (built on the CG shield). |
| `lua/weapons/rhylib_grenade_base.lua` | shared | Base for every grenade: throw, lob, modes (timed / impact / breach), first-person hands, breaching charge settings. |
| `lua/weapons/rhylib_thermal.lua` | shared | Thermal detonator. |
| `lua/weapons/rhylib_thermal_impact.lua` | shared | Impact detonator (hidden from the spawn menu, kept for old items and as a launcher round). |
| `lua/weapons/rhylib_droidpopper.lua` | shared | Droid popper (EMP grenade). |
| `lua/weapons/rhylib_flashcharge.lua` | shared | Flash charge (MP stun grenade). |
| `lua/weapons/rhylib_he_charge.lua` | shared | High explosive charge: placing, the timer window, net `he.set`. |
| `lua/weapons/rhylib_*_training.lua` | shared | Training copies (11 files, one per gun plus thermal and droid popper). |
| `lua/entities/rhylib_grenade.lua` | shared | The thrown grenade / placed breaching charge: physics, fuse, frag / EMP / flash / breach effects, empRadius setting. |
| `lua/entities/rhylib_he_planted.lua` | shared | A placed HE charge: timer, sync, beeps, blast, its settings. |
| `lua/entities/rhylib_topattack.lua` | shared | The RPS-6 top-attack rocket (locked or laser guided), its settings, the laser dot. |
| `lua/effects/rhylib_emp.lua` | client | EMP blast and the arcs on a hit droid (also used by rhylib_droids and rhylib_eod). |

## The weapons

Class name, what it is, and what it takes. "Skill" means the mode or item needs that `rhylib_skills` skill id; without `rhylib_skills` installed, skill checks pass. The stun mode is for military police only (`rhylib_mp`).

### Guns

| Class | Name | What it is | Ammo | Fire modes |
|---|---|---|---|---|
| `rhylib_dc15a` | DC-15A | Blaster rifle. | Medium or small magazines + power cell | semi, auto (skill `full_auto`), overcharge (skill `overcharge`), stun |
| `rhylib_dc15s` | DC-15S | Blaster carbine. | Medium or small magazines, no cell | semi, auto, sidearm (skill `carbine_sidearm`: held like a pistol, replaces semi), stun |
| `rhylib_dc17` | DC-17 | Blaster pistol. Two can be carried with the dual skill. | Small magazines | semi, dual (skill `dual_dc17`, needs two carried), stun |
| `rhylib_dc15x` | DC-15X | Sniper rifle. Loads at most 15 shots from a large magazine. Aiming looks through a scope (skill `long_gun`; without it, a normal aim). | Large magazines + power cell | semi |
| `rhylib_dp23` | DP-23 | Blaster carbine. | Small magazines + power cell | semi, auto, stun |
| `rhylib_dp24` | DP-24 | Blaster shotgun: each shot fires 6 bolts and uses 6 rounds. | Medium magazines + power cell | semi |
| `rhylib_westarm5` | Westar-M5 | Blaster rifle. | Medium or small magazines + power cell | semi, auto, stun |
| `rhylib_z6` | Z-6 | Rotary blaster cannon. Hold fire to spin up (0.6 s); you walk slower while it spins. Can't fire while flying a jetpack. | Large (skill `heavy_feed`), medium or small magazines + power cell | auto |
| `rhylib_rps6` | RPS-6 | Rocket launcher, one rocket per reload. Can't fire while flying. | Rockets | semi (straight rocket), lockon (skill `eod_lockon`) |
| `rhylib_grenade_launcher` | T-19 grenade launcher | Fires the thermal detonators you carry as impact rounds in a ballistic arc. Shows "RANGE n M" for your aim. Carrying it needs skill `eod_launcher`. | Thermal detonator items (training thermals fire training rounds) | semi |

Most guns also get a "grapple" fire mode while you carry a grapple hook (`SWEP.Grapple`, from `rhylib_weapons`). Fire mode: E + R; safety: Shift + E + R (both from `rhylib_weapons`).

RPS-6 lock-on mode: aim at a comms jammer or a (non-training) droid within `lockRange` and `lockCone` until the box says LOCKED, then fire. The rocket (`rhylib_topattack`) climbs and dives onto the target. Fired without a lock it is laser guided: it dives onto whatever you aim at (a red dot everyone sees) while you keep the RPS-6 out.

### Shields

| Class | Name | What it is |
|---|---|---|
| `rhylib_riotshield` | CG riot shield (DC-15S) | Coruscant Guard shield with a DC-15S. Carrying it needs skill `riot_shield`. Works with Hold the line and Phalanx, its bash stuns players (bash skill `shield_bash`, basher must be an MP), and it blocks a wider arc (`rhylib_weapons` settings `cgShieldArc`, `cgShieldSideArc`, `cgShieldBlast`). 7 kg. Specialist armoury (MP role). |
| `rhylib_riotshield_rep` | Republic shield (DC-15S) | Shield anyone may carry. Same blocking rules with the normal arcs, a bash that only shoves, no Shock Trooper bonuses. 9 kg. Weapons armoury. |

Both: semi and stun fire modes only, right mouse aims (the shield moves in front), the bash has its own key (X by default), they go in the back slot (not with a backpack or jetpack), and aiming without skill `riot_shield` is "full cover" (no firing). The blocking itself is in `rhylib_weapons` (`sh_60_shield.lua`).

### Grenades and charges

All built on `rhylib_grenade_base`: an inventory item that stacks. LMB throws, RMB lobs. E + R changes the mode on grenades that have one.

| Class | Name | What it is |
|---|---|---|
| `rhylib_grenade_base` | (base) | Not spawnable. Base for the others. |
| `rhylib_thermal` | Thermal detonator | Frag grenade, 3 s fuse. E + R: timed / impact, and breaching charge with skill `breaching` (stick it on a door: small blast, doors nearby are forced open and held open). Also a T-19 round. |
| `rhylib_thermal_impact` | Impact detonator | Explodes on the first hit. Not in the spawn menu (the thermal has an impact mode); still a T-19 round. |
| `rhylib_droidpopper` | Droid popper | EMP, 2 s fuse or impact. Kills Rhylib droids in `empRadius` and in sight, stuns players there, no other damage. Skill `droid_popper` to carry and throw. |
| `rhylib_flashcharge` | Flash charge | 1.5 s fuse. Players in 450 units and in sight get a white flash and an MP stun; droids aim worse for a while. No damage. Skill `flash_charge`. |
| `rhylib_he_charge` | High explosive charge | 2x2 item, stacks by 2. LMB / RMB sticks it to the surface you look at. E (with nothing close in front of you) opens a timer window: set a timer, or "Sync". Synced charges wait and all go off with your next timed charge. The only thing that brings down large comms jammers (explosion strength 3). |

### Training copies

`rhylib_dc15a_training`, `rhylib_dc15s_training`, `rhylib_dc15x_training`, `rhylib_dc17_training`, `rhylib_dp23_training`, `rhylib_dp24_training`, `rhylib_westarm5_training`, `rhylib_z6_training`, `rhylib_rps6_training`, `rhylib_thermal_training`, `rhylib_droidpopper_training`.

Each is the real weapon with training magazines (`mag_small_t` etc.), yellow bolts / tint, and `Training = true`: shots and blasts take sim health (`rhylib_training`) and only hurt training droids. No stun mode; the training RPS-6 has no lock-on. They are in the "Rhylib: Training" spawn menu category and the training armoury. Skills treat them as the real gun (`TrainingOf`).

### Entities and effect

| Class | What it is |
|---|---|
| `rhylib_grenade` | A thrown grenade or a stuck breaching charge (kinds fuse, impact, emp, emp_impact, breach, flash). Not spawnable. Also spawned by the T-19 and by rhylib_droids (B1 grenades, clone poppers). |
| `rhylib_he_planted` | A placed HE charge. Not spawnable. Its class differs from the weapon's on purpose (a SENT sharing a SWEP's class makes `ents.Create` build the weapon). |
| `rhylib_topattack` | The RPS-6 top-attack rocket. Not spawnable. |
| `rhylib_emp` (effect) | EMP blast (flags 0) and arcs on a hit droid (flags 1); colour 0 blue, 1 purple, 2 orange (training). |

## For server owners

### Settings

All of this addon's settings are in config module `"weapons"` (shared with `rhylib_weapons`). They are registered by the weapon / entity files, so they only exist while rhylib_republic is installed.

| Key | Default | What it does |
|---|---|---|
| `breachFuse` | `6` | Breaching charge: seconds from placing to the blast. |
| `breachRadius` | `130` | Breaching charge: blast radius (units, 130 = 2.5 m). |
| `breachDamage` | `70` | Breaching charge: damage at the centre. |
| `breachDoors` | `130` | Breaching charge: doors this close are forced open (units). |
| `breachHold` | `300` | Breaching charge: seconds a forced door stays open. |
| `breachReach` | `80` | Breaching charge: how far you can reach to place it (units). |
| `empRadius` | `190` | Droid popper (EMP): radius it kills droids and stuns players in (units). |
| `heFuse` | `30` | HE charge: default timer (seconds). |
| `heMinFuse` | `5` | HE charge: shortest timer you can set (seconds). |
| `heMaxFuse` | `120` | HE charge: longest timer you can set (seconds, up to 255). |
| `heReach` | `90` | HE charge: how far you can reach to place it (units). |
| `heRadius` | `350` | HE charge: blast radius (units). |
| `heDamage` | `400` | HE charge: damage at the centre. |
| `heJammerReach` | `250` | HE charge: how close a comms jammer must be to take the hit (units, to the nearest point of the jammer). |
| `heIdleLife` | `900` | HE charge: seconds a synced charge waits for a timer before it's removed. |
| `lockRange` | `6000` | RPS-6 lock-on: longest lock (units). |
| `lockCone` | `6` | RPS-6 lock-on: how close to the crosshair a target must be (degrees). |
| `lockTime` | `1.2` | RPS-6 lock-on: seconds of aiming at a target to lock it. |
| `topClimb` | `900` | RPS-6 top attack: highest climb before the dive (units). |
| `topSpeed` | `1500` | RPS-6 top attack: rocket speed (units/s). |
| `launcherRange` | `60` | Grenade launcher: longest shot on level ground (metres, aimed about 45° up). |
| `launcherSpread` | `0.6` | Grenade launcher: random aim error (degrees). |
| `launcherDamage` | `140` | Grenade launcher: blast damage at the centre. |
| `launcherRadius` | `300` | Grenade launcher: blast radius (units). |

Other numbers that affect these weapons live in `rhylib_weapons`: each gun's damage, fire rate, bolt speed, reload time, spread and recoil are settings in module `"guns"` (`<class>_damage`, `<class>_rpm`, ...; not for training copies, shields, grenades or the T-19), and the shields' arcs are `shieldArc`, `cgShieldArc` and friends. Fixed grenade numbers are on the entity: frag `ENT.Radius` 300 / `ENT.Damage` 140, flash `ENT.FlashRadius` 450.

Change settings on the in-game Staff > Server settings page, or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("weapons", "heFuse", 20)          -- HE charges start with a 20 s timer
Rhylib.Config.Set("weapons", "breachHold", 120)     -- breached doors close again after 2 minutes
```

Gun, prop and shield models can be swapped in Server settings > Models (rhylib_core reads `SWEP.WorldModel`, `PropModel`, `CarrierVM` etc.; the shields add their own entries). Things already spawned need a map change.

### Commands and permissions

This addon adds no commands or permissions of its own. Tuning tools that work on these weapons come from `rhylib_weapons`: `rhylib_vm_editor`, `rhylib_wm_editor`, `rhylib_extra_editor` (shields). Admin test ammo: `rhylib_infammo` (rhylib_weapons). Client debug: `rhylib_grenade_debug 1` draws a grenade's physics ball and model bounds.

### Placing things / saving

Nothing to place. Weapons are handed out by `rhylib_armoury`: the weapons armoury lists every spawnable Rhylib gun automatically (the CG shield is an MP role item in the specialist armoury), the ammo cabinet stocks thermals, droid poppers and HE charges, the training armoury and training ammo cabinet the training copies. Grenades and charges in the world are never saved.

## For players (short)

- LMB fire / throw, RMB aim / lob. R reload (T-19: loads the next thermal).
- E + R: next fire mode (grenades: timed / impact / breaching charge).
- RPS-6 in lock-on mode: hold aim on a jammer or droid until LOCKED, then fire; or fire without a lock and keep aiming to steer it.
- HE charge: E opens the timer window (Set timer / Sync).
- Shields: X shield bash (change it in Settings > Controls).

## For developers

### Public functions

All are methods on the weapon or entity (shared unless noted).

- `SWEP:LockOn()` → bool (RPS-6): in lock-on mode.
- `SWEP:LockedTarget()` → entity or nil (RPS-6): target once held for `lockTime`.
- `SWEP:FindLockTarget(owner)` → entity or nil (RPS-6, server).
- `ENT:LaserSpot()` → Vector or nil (`rhylib_topattack`): where the guide's laser lands.
- `SWEP:LaunchSpeed()`, `SWEP:RangeAt(pitch)` → metres, `SWEP:RoundsCarried()` → count (T-19).
- `SWEP:ImpactKey()` → NW2Bool name, `SWEP:IsImpact()`, `SWEP:IsBreach()`, `SWEP:CanBreach()`, `SWEP:SkillOK()` (grenade base).
- `SWEP:Throw(force, lift)`, `SWEP:PlaceBreach()`, `SWEP:UseOne(ply)` (grenade base): throw one, stick a breaching charge, use one up from the inventory.
- `SWEP:PlaceCharge()` (HE charge).
- `ENT:Centre()`, `ENT:EmpR()` (`rhylib_grenade`).
- `SWEP:CanBash()`, `SWEP:Bash()` (server), `SWEP:AimFireBlocked()` (shields).

Spawning a grenade from your own code (server):

```lua
local g = ents.Create("rhylib_grenade")
g:SetPos(pos)
g.kind = "fuse"          -- fuse / impact / emp / emp_impact / breach / flash
g.fuse = 2
g.thrower = npc          -- gets the kill
g.Damage, g.Radius = 100, 250
g:Spawn()
g:GetPhysicsObject():SetVelocity(dir * 600)
```

### Hooks

Fired by this addon:

- `Rhylib.Explosion(pos, reach, strength, attacker, inflictor, kind)` (server): after a player's grenade (`"grenade"`, strength 1), breaching charge (`"breach"`, 2), RPS-6 top-attack rocket (`"rocket"`, 2) or HE charge (`"he"`, 3). Not for training ones. rhylib_radio damages comms jammers with it, rhylib_eod sets off mines. Return value ignored.
- `Rhylib.EMP(pos, radius, attacker, inflictor)` (server): after a real (not training) droid popper EMP. rhylib_eod uses it to fry bombs and switch off devices. Return value ignored.

Listened to: `Rhylib.ModelCatalogue` (adds the two shield models to Server settings > Models). The weapons also define `SWEP:RhylibModelsChanged()` (shields), which rhylib_core calls after a model change.

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `rhylib.he.set` | client → server | UInt 8: seconds (0 = sync) | Timer for the HE charge in hand. Rate 6/s. |
| `rhylib.wep.shieldbash` | client → server | (empty) | The shield bash key was pressed. Rate 3/s. |

Networked state: grenade `Kind`, `Boom`, `Ball`, `Radius`, `Offset`; HE charge weapon `FuseSet`, placed charge `Boom`; RPS-6 `LockTarget`, `LockStart`; rocket `Guide` + NW2String `rhylib_guideGun`; player NW2Bools `rhylib_nadeImpact[_<class>]` and `..._breach` (grenade mode), NW2Int `rhylib_heSynced` (synced charges waiting).

### Saved data

None. A player's HE timer choice lives on the player (`ply.rhylibHeFuse`) until they leave.

### Examples

**A training copy of a gun.** One small file in your own addon, `lua/weapons/rhylib_mygun_training.lua`. Everything not set comes from the real gun. The training armoury picks it up by itself (it's `Spawnable`, `IsRhylib` and `Training`).

```lua
AddCSLuaFile()

SWEP.Base = "rhylib_mygun"              -- the real gun
SWEP.PrintName = "My gun (Training)"
SWEP.Category = "Rhylib: Training"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Training = true                    -- bolts take sim health, hurt training droids only
SWEP.TrainingOf = "rhylib_mygun"        -- skills treat it as the real gun
SWEP.BoltColor = 7                      -- training yellow (rockets: 9)
SWEP.InvCategory = "training"           -- yellow stripe in the inventory
SWEP.Mags = { "mag_medium_t", "mag_small_t" }   -- training copies of the real gun's magazines
SWEP.FireModes = { "semi", "auto" }     -- the real gun's modes without "stun" (and "lockon")
```

If the real gun has `MagSkills`, copy it with the training ids (see `rhylib_z6_training.lua`). Name it `<real class>_training`: the weapons armoury sorts training copies by that name.

**A new grenade type.** A file `lua/weapons/rhylib_mynade.lua`. It must use one of the kinds the `rhylib_grenade` entity knows (`fuse`, `impact`, `emp`, `flash`; `ImpactMode` adds impact, `BreachMode` adds the breaching charge).

```lua
AddCSLuaFile()
SWEP.Base = "rhylib_grenade_base"
SWEP.PrintName = "Short-fuse thermal"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"                  -- armoury shelf
SWEP.Spawnable = true

SWEP.GrenadeKind = "fuse"                  -- fuse / impact / emp / flash
SWEP.FuseTime = 1.5                        -- seconds
SWEP.ImpactMode = true                     -- E + R: timed / impact
SWEP.PropColor = Color(255, 160, 120)      -- tint of the thrown model
SWEP.ImpactColor = Color(255, 120, 90)     -- tint in impact mode
SWEP.ThrowForce, SWEP.LobForce = 900, 400  -- LMB / RMB speed
SWEP.InvStack = 2                          -- how many stack in one cell
SWEP.InvWeight = 0.8                       -- kg
SWEP.RequiresSkill = "my_skill"            -- optional: skill to throw it
SWEP.SkillName = "My skill"                -- shown when it's missing
-- SWEP.PropModel = "models/..."           -- another model (offsets are from its centre)
```

Then add it to the ammo cabinet from a host file or your addon (before the cabinet is first opened): `table.insert(Rhylib.Armoury.AMMO_STOCK, "rhylib_mynade")`. Blast damage and radius come from the entity (`rhylib_grenade` ENT.Damage 140 / ENT.Radius 300, EMP `empRadius`, flash `ENT.FlashRadius`), so all grenades of one kind share them. A new kind (smoke, gas...) needs code in `rhylib_grenade.lua`'s `ENT:Explode`.

**Reacting to explosions** (e.g. your own destructible entity):

```lua
Rhylib.Hook.Add("Rhylib.Explosion", "myaddon.walls", function(pos, reach, strength, attacker, inflictor, kind)
    for _, e in ipairs(ents.FindInSphere(pos, reach)) do
        if e:GetClass() == "my_wall" and strength >= 3 then e:Remove() end   -- only HE charges
    end
end)
```

**A gun variant.** Copy a gun file, change the class (file name), `PrintName` and the numbers. Every field is explained in `rhylib_weapons/lua/weapons/rhylib_base.lua`; tune the first-person / third-person placement in game with `rhylib_vm_editor` / `rhylib_wm_editor` and paste the lines they copy. Remember `Primary` and `Spread` must be written out whole (GMod doesn't merge tables from the base).

## Notes and gotchas

- The settings in this addon are registered from weapon and entity files, so they show up in Server settings only with rhylib_republic installed.
- `Spread`, `Recoil` and `Primary` are whole tables: a variant that sets one field must copy the rest.
- Every gun except the DC-15S and the DC-17 is `InvLarge` (DC-15A, DC-15X, DP-23, DP-24, Westar-M5, Z-6, RPS-6, T-19 and both shields): no backpacks, and no firing while flying a jetpack (the DP-23 can with the skill `dp23_prof`).
- The shields are DC-15S subclasses. Settings changes to the DC-15S in module `"guns"` don't reach their `Spread` (they have their own table).
- A placed breaching charge removes itself 60 s after placing, so a `breachFuse` above 60 means it never goes off. Keep it under 60.
- `rhylib_he_planted` must never be renamed to the weapon's class; old servers should delete a leftover `entities/rhylib_he_charge.lua`.
- The impact choice is per grenade class and per player (NW2Bool), so a training thermal remembers its own mode.
- Training RPS-6 rockets can't lock on; training EMPs only take out training droids; clone NPCs' poppers never stun players or kill training droids.
- Model packs missing on a client: guns float (no hands), shields fall back to the older packs, sounds are silent.
