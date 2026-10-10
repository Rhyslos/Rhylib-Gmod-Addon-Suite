# rhylib_mp: Military police

Gives military police (MP) jobs the tools to arrest people. An MP stuns a target (a stun shot from their blaster's "stun" fire mode, or a hit with the stun baton), cuffs them while they lie on the floor, escorts them, searches their gear, and takes them to a jail terminal. There the MP sets a sentence and a reason. The prisoner's items go to evidence, and the prisoner is put in a jail cell. When the time is up they wait in the cell until an MP (or a timer) processes them out. They then collect their things from a property locker, minus contraband and anything an MP withheld. Sentences only count down while the prisoner is online, and they survive reconnects and map changes.

For server owners: mark MP jobs with `mp = true` in your DarkRP job table. Then place jail cells, a jail terminal and a property locker on each map and make them permanent.

## Requirements

- Required: `rhylib_core`.
- Works better with: `rhylib_menus` (the jail terminal and search windows, the interaction wheel), `rhylib_inventory` (searching, evidence, the property locker, hidden contraband), `rhylib_weapons` (the stun fire mode on blasters), `rhylib_skills` (Escort drills, Thorough search), `rhylib_admin` (`!jail`, `!unjail`, `!free`, `!hidecells`), `rhylib_datapad` (arrest records, the Arrest tab).
- Workshop content: the jail terminal uses Reizer's `console_01` prop (an HL2 console is used if it is missing). The stun sound is from the Star Wars shared resources pack. Both models can be changed in the settings.
- DarkRP is the gamemode (the job field `mp = true` decides who is an MP).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_mp.lua` | shared | Loads the `mp` module through `Rhylib.LoadModule` (needs rhylib_core). |
| `lua/rhylib/mp/sh_00_config.lua` | shared | `Rhylib.MP` table, config keys, who is an MP, state readers (`IsStunned`, `IsCuffed`, ...), `MP.Target`, inventory lock. |
| `lua/rhylib/mp/sh_10_move.lua` | shared | Input and movement while stunned or cuffed, the escort pull, the lying pose while stunned. |
| `lua/rhylib/mp/sv_10_stun.lua` | server | `MP.Stun`, `MP.Cuff`, `MP.Uncuff`, `MP.SetEscort`, escort checks, clearing on death/spawn/leave, restraint blocks. |
| `lua/rhylib/mp/sv_20_search.lua` | server | Searching (`mp.search` / `mp.list` / `mp.take`), hidden item rolls, interaction wheel actions (`mp.wheel`). |
| `lua/rhylib/mp/sv_30_jail.lua` | server | Jail, sentences, processing, arrest records, the terminal messages, saving placements (`rhylib_mp_save`). |
| `lua/rhylib/mp/sv_40_property.lua` | server | Property lockers: per-player storage of returned evidence. |
| `lua/rhylib/mp/cl_10_hud.lua` | client | Status plate: STUNNED / CUFFED / JAILED / AWAITING PROCESSING. |
| `lua/rhylib/mp/cl_20_search.lua` | client | Search window, interaction wheel options. |
| `lua/rhylib/mp/cl_30_terminal.lua` | client | Jail terminal window. |
| `lua/weapons/rhylib_handcuffs.lua` | shared | Handcuffs SWEP: cuff, uncuff, escort. |
| `lua/weapons/rhylib_stunbaton.lua` | shared | Stun baton SWEP: stun, search. |
| `lua/entities/rhylib_jail_cell.lua` | shared | Jail cell marker (where a prisoner stands). |
| `lua/entities/rhylib_jail_terminal.lua` | shared | Jail terminal (E opens the window for MPs). |
| `lua/entities/rhylib_property_locker.lua` | shared | Property locker (E: collect your things). |

## For server owners

### Settings

Config module `"mp"`:

| Key | Default | What it does |
|---|---|---|
| `stunTime` | `8` | Seconds a stun hit keeps someone down |
| `stunImmune` | `3` | Seconds after getting up before they can be stunned again |
| `batonRange` | `85` | Stun baton reach (units) |
| `propertyModel` | `"models/props_c17/lockers001a.mdl"` | Property locker model |
| `terminalModel` | `"models/reizer_props/srsp/sci_fi/console_01/console_01.mdl"` | Jail terminal model (HL2 console if missing) |
| `batonDelay` | `1.2` | Seconds between baton swings |
| `cuffRange` | `85` | How close you must be to cuff or uncuff |
| `cuffTime` | `1.5` | Seconds to put cuffs on |
| `cuffWalk` | `110` | Walk speed while cuffed |
| `escortLeash` | `60` | How far behind the MP an escorted prisoner walks |
| `escortSlow` | `0.75` | Speed multiplier for an MP escorting a prisoner (none with the Escort drills skill) |
| `searchRange` | `100` | How close you must be to search someone |
| `searchMemory` | `300` | Seconds an MP's search rolls on someone's hidden items are kept (searching again doesn't re-roll) |
| `processAuto` | `300` | Seconds after a sentence ends before the prisoner is processed out automatically |
| `maxSentence` | `60` | Longest sentence in minutes |
| `jailRadius` | `350` | A prisoner further than this from their cell is put back |
| `terminalRange` | `400` | Cuffed prisoners this close to a jail terminal can be jailed there |
| `poses` | `{ "death_04", "death_03", "death_02", "death_01", "zombie_slump_idle_02" }` | Lying poses while stunned, first that exists on the model wins |
| `propertyW` | `10` | Property locker width in cells |
| `propertyH` | `8` | Property locker height in cells |

Two fixed values live in the code: `MP.TERM_USE = 180` (how close an MP must stay to a terminal to use it) and `MP.REC_MAX = 50` (arrests kept per player).

Change settings in game on the Staff > Server settings page (Units & roles > Military police), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("mp", "stunTime", 10)       -- longer stuns
Rhylib.Config.Set("mp", "maxSentence", 30)    -- 30 minutes at most
Rhylib.Config.Set("mp", "processAuto", 120)   -- processed out 2 min after the sentence ends
```

Contraband (items that can be hidden, are never returned from evidence and show as "kept" on the terminal) is a list in rhylib_inventory's config (`inventory` `contraband`), not here.

### Who is an MP

A DarkRP job with `mp = true`:

```lua
TEAM_CG = DarkRP.createJob("Coruscant Guard", {
    -- ...
    mp = true,
})
```

Or answer the hook `Rhylib.IsMP` (see Examples).

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `rhylib_mp_save` | permission `rhylib.mp.admin` (default admin), or the server console | Saves this map's jail cells, terminals and property lockers (only permanent ones, see below). |

Related commands from other addons: rhylib_admin `!jail`, `!unjail` (calls `MP.Process`), `!free` (uncuff and end a stun), `!hidecells` (hides the cell rings from MPs and admins).

The handcuffs, stun baton and the three entities are admin-only in the spawn menu (category "Rhylib: Military police"). MPs normally get the weapons from the armoury's MP role stock (rhylib_armoury).

### Placing things / saving

1. Spawn **Jail cell** markers where prisoners should stand (one prisoner or more per cell; new prisoners go to a random cell among the emptiest). The marker faces away from you; prisoners face the same way. Only MPs and admins see its faint blue ring.
2. Spawn a **Jail terminal** near the cells.
3. Spawn a **Property locker** where released prisoners should collect their things. Processed prisoners appear 50 units in front of the locker nearest their cell.
4. Make each one permanent with the toolgun's **Permanent** entry (Staff tools), or run `rhylib_mp_save`. Placements are saved per map in Data `mp_places`/`<map>`. They come back at map start and after a map cleanup.

Without a locker, returned items go straight into the prisoner's inventory (or on the floor if it is full). Without any cell, `MP.Jail` fails with "No jail cells on this map".

## For players (short)

| Key | What it does |
|---|---|
| Blaster "stun" fire mode (E + R, MPs only) | Stun shots: the target collapses for `stunTime` seconds. |
| Stun baton LMB | Swing: an MP's hit stuns the target. |
| Stun baton RMB | Search the player you look at. Take items only if they are cuffed. With the baton out you can also open locked lockers. |
| Handcuffs LMB (hold) | Cuff a stunned or downed player (`cuffTime`, keep aiming). |
| Handcuffs RMB | Uncuff the cuffed player you look at. |
| Handcuffs R | Escort the cuffed player you look at; again to let go. |
| E (hold) on a player | Interaction wheel (rhylib_menus): Search, Cuff (needs handcuffs), Uncuff, Escort / Let go. |
| E on the jail terminal | Jail window (MPs). |
| E on a property locker | Collect your things after jail. |

Cuffed players walk slowly and can't sprint, jump, crouch, shoot, use things, switch weapons, use their inventory, change job, enter vehicles or kill themselves. Stunned players can't do anything and look where they fell.

## For developers

### Public functions

All on `Rhylib.MP` (`MP` below).

| Function | Realm | What it does |
|---|---|---|
| `MP.Cfg(key)` → value | shared | `Rhylib.Config.Get("mp", key)`. |
| `MP.IsMP(ply)` → bool | shared | Is ply military police (hook `Rhylib.IsMP`, else job `mp = true`). |
| `MP.IsStunned(ply)`, `MP.IsCuffed(ply)`, `MP.IsJailed(ply)` → bool | shared | State checks (`IsJailed` is also true while awaiting processing). |
| `MP.EscortedBy(ply)` → MP or nil | shared | Who is pulling this prisoner. |
| `MP.Escorting(mp)` → prisoner or nil | shared | Who this MP is escorting. |
| `MP.JailLeft(ply)` → seconds | shared | Sentence left (0 while awaiting processing). |
| `MP.Target(ply, range)` → player or nil | shared | Living player ply aims at; a lying player's ragdoll counts as them. |
| `MP.Stun(ply, by)` | server | Stun now (skips dead, downed, knocked down, already stunned, immune, or `Rhylib.CanStun` = false). Does not check that `by` is an MP. |
| `MP.EndStun(ply)` | server | End a stun now. |
| `MP.Cuff(ply, by)` / `MP.Uncuff(ply, by)` | server | Cuff / uncuff, no range or MP checks. |
| `MP.SetEscort(ply, by)` | server | Escort a cuffed ply (`by` nil = let go). |
| `MP.ClearEscorter(ply)` | server | Unlinks ply from their MP's `rhylib_escorting`. |
| `MP.CanSearch(mp, target)` → bool | server | MP, alive, in reach of the tool in hand, clear line. |
| `MP.SearchFinds(mp, target, inst)` → bool | server | Does this MP see this item (hidden-item roll). |
| `MP.SendList(mp, target)` | server | Send the search list (`mp.list`). |
| `MP.Jail(ply, by, minutes, why)` → ok, err | server | Jail now (no cuff/terminal check). |
| `MP.EndSentence(ply, by)` | server | Sentence over: awaiting processing. |
| `MP.Process(ply, by)` | server | Out of jail: evidence returned, respawn at the property locker. |
| `MP.Release(ply, by)` | server | One step: serving → awaiting → processed. |
| `MP.Returnable(entry)` → bool | server | Evidence goes back (not withheld, not contraband). |
| `MP.GetRecord(sid64)` → list | server | Arrests `{ t, by, min, why }`, newest first. |
| `MP.IndexPlayer(sid64, name)` | server | Adds a name to the records index. |
| `MP.OpenTerminal(mp, term)` | server | Send the terminal window. |
| `MP.SavePlaces()` → count | server | Save placements for this map. |
| `MP.StoreProperty(ply, list)` → leftover | server | Put `{ id, count, data }` entries in ply's property. |
| `MP.OpenProperty(ply, ent)` | server | Open ply's property at a locker. |
| `MP.OpenSearch(target)` | client | Ask the server to search target. |
| `MP.ShowSearch(target, cuffed, rows)` / `MP.ShowTerminal(term, cand, jailed)` | client | Build the windows (called by the net handlers). |

Small examples:

```lua
-- Server: stun someone from your own code (you check who may do it)
if Rhylib.MP.IsMP(officer) then
    Rhylib.MP.Stun(target, officer)
end

-- Server: a 10 minute sentence without the terminal
local ok, err = Rhylib.MP.Jail(target, officer, 10, "Desertion")
if not ok and err then officer:ChatPrint(err) end

-- Client: open the search window on the player you look at
local t = Rhylib.MP.Target(LocalPlayer(), Rhylib.MP.Cfg("searchRange"))
if t then Rhylib.MP.OpenSearch(t) end
```

### Hooks

Fired by this addon (`hook.Run`):

| Hook | When | Return value |
|---|---|---|
| `Rhylib.IsMP(ply)` | Every `MP.IsMP` call (shared). | `true`/`false` overrides the job check; `nil` = use the job. |
| `Rhylib.CanStun(ply, by)` | Before a stun starts. | `false` blocks it (rhylib_admin uses this for god mode). |
| `Rhylib.PlayerStunned(ply, by)` | After a stun starts. | ignored |
| `Rhylib.PlayerCuffed(ply, by)` | After cuffing. | ignored |
| `Rhylib.PlayerUncuffed(ply, by)` | After uncuffing (`by` nil when the system does it: death, jail, ...). | ignored |
| `Rhylib.MPConfiscated(mp, target, itemId, count)` | After an MP takes an item in a search. | ignored |
| `Rhylib.PlayerJailed(ply, by, minutes, why)` | After jailing (rhylib_datapad counts it). | ignored |
| `Rhylib.PlayerReleased(ply, by)` | After processing out (`by` nil when automatic). | ignored |
| `Rhylib.MPSearchTool(ply, weapon)` | Searching with a weapon that isn't the baton. | `true` = baton reach, a number = that reach (rhylib_datapad uses it). |

Listened to: `Rhylib.StunHit(ply, shooter, weapon)` (rhylib_weapons stun bolts: only an MP's hit stuns), `Rhylib.PlayerDowned` (medical takes over from a stun), `Rhylib.InventoryLocked` (returns true while cuffed, stunned or jailed), `Rhylib.CanSearchLocker` (true for an MP holding the baton), `Rhylib.WheelOptions` (adds the MP wheel entries), plus DarkRP's `playerCanChangeTeam` and GMod's `PlayerSpawn`, `PlayerDeath`, `PlayerDisconnected`, `PlayerLoadout`, `CanPlayerEnterVehicle`, `CanPlayerSuicide`, `PlayerCanPickupWeapon`, `PlayerSwitchWeapon`, `StartCommand`, `SetupMove`, `Move`, `CalcMainActivity`, `UpdateAnimation`.

### Network messages

All names get the `rhylib.` prefix on the wire (`Rhylib.Net`). Client → server messages are rate limited per player.

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `mp.search` | client → server | target Entity (NULL = close) | Open / close a search. |
| `mp.list` | server → MP | target Entity, cuffed Bool, count UInt 8, per item: uid (`Items.UID_BITS`), item net id (`Items.NET_BITS`), count UInt 8, fill % UInt 7, container (`Items.CONT_BITS`) | The search list. NULL target closes the window. |
| `mp.take` | client → server | target Entity, uid (`Items.UID_BITS`) | Take an item (target must be cuffed). |
| `mp.wheel` | client → server | op UInt 2 (0 cuff, 1 uncuff, 2 escort toggle), target Entity | Interaction wheel actions. |
| `mp.wheelx` | server → MP | (empty) | The timed cuff was cancelled: stop the progress bar. |
| `mp.term` | server → MP | terminal Entity; candidates UInt 5 + Entity each; prisoners UInt 6, each: Entity, reason String, awaiting Bool, processAt Float, evidence UInt 6 + (net id `Items.NET_BITS`, count UInt 8, withheld Bool, contraband Bool) | Terminal window contents. |
| `mp.jail` | MP → server | terminal Entity, prisoner Entity, minutes UInt 7, reason String (≤ 80) | Jail someone. |
| `mp.release` | MP → server | terminal Entity, prisoner Entity | Release (serving) or process (awaiting). |
| `mp.destroy` | MP → server | terminal Entity, prisoner Entity, index UInt 6, net id, count UInt 8 | Withhold / return one evidence item (toggle). |

State players see is NW2 on the player: `rhylib_stunEnd` (Float, CurTime), `rhylib_stunYaw` (Float), `rhylib_cuffed` (Bool), `rhylib_escortBy` (Entity), `rhylib_escorting` (Entity, on the MP), `rhylib_jailEnd` (Float), `rhylib_jailWhy` (String), `rhylib_jailAwait` (Bool).

### Saved data

`Rhylib.Data` (server, SQLite):

| Module / key | What's stored |
|---|---|
| `mp_jail` / SteamID64 | A sentence in progress: `{ left (seconds), why, by, evidence, awaiting, processLeft }`. Deleted when processed. |
| `mp_rec` / SteamID64 | Arrest record: list of `{ t, by, min, why }`, newest first, up to 50. |
| `mp_idx` / `"all"` | `{ ["s" .. SteamID64] = name }` of everyone on file (the "s" prefix keeps JSON from rounding the number). |
| `mp_places` / map name | Placed cells, terminals and property lockers: `{ class, pos, ang }`. |
| `mp_prop` / SteamID64 | Items waiting in that player's property locker (deleted when empty). |

### Examples

Make another job count as MP (for example by a roster qualification):

```lua
-- shared, in your own addon
hook.Add("Rhylib.IsMP", "myaddon.mp", function(ply)
    if ply:GetNW2String("rhylib_quals", ""):find(",mp,", 1, true) then return true end
end)
```

Announce every arrest:

```lua
-- server
hook.Add("Rhylib.PlayerJailed", "myaddon.announce", function(ply, by, minutes, why)
    PrintMessage(HUD_PRINTTALK, ply:Nick() .. " was jailed for " .. minutes .. " min: " .. why)
end)
```

Stop stuns in a safe zone:

```lua
-- server
hook.Add("Rhylib.CanStun", "myaddon.safezone", function(ply, by)
    if ply:GetPos():WithinAABox(SAFE_MIN, SAFE_MAX) then return false end
end)
```

Let your own scanner weapon search people, with a 150 unit reach:

```lua
-- server
hook.Add("Rhylib.MPSearchTool", "myaddon.scanner", function(ply, wep)
    if wep:GetClass() == "my_scanner" then return 150 end
end)
```

## Notes and gotchas

- `MP.Stun`, `MP.Cuff` and `MP.Jail` don't check that the caller is an MP or in range. The weapons, wheel and terminal do that; your own code must too.
- A stun shot from a non-MP does nothing (`Rhylib.StunHit` is only acted on for MPs). Anyone can swing the baton, but only an MP's hit stuns.
- Sentences count down only while the prisoner is online. A prisoner whose time ran out just before they left comes back "awaiting processing", so their evidence is never lost.
- Processing respawns the player (`ply:Spawn()`), so they get their job loadout back, then they are moved to the locker 0.1 s later.
- Contraband and withheld evidence is deleted at processing, not stored anywhere.
- Players who leave while cuffed are cuffed again on rejoin, but this is kept in memory only (a map change forgets it).
- An escort ends when the MP dies, is downed, is cuffed, or is more than 400 units away (checked every 0.5 s).
- The escorted prisoner is pulled on the server only. Their own client stops predicting movement while beyond the leash, so they see the server's position (no fighting the pull).
- The terminal window lists at most 31 candidates, 63 prisoners and 63 evidence items per prisoner.
- Placements are only saved if they are permanent (toolgun Permanent tool). Things placed but never made permanent are dropped the next time the class is saved.
- The lying pose while stunned uses rhylib_core's `Rhylib.Lying` body. If a player model has none of the `poses` sequences, no pose is forced.
