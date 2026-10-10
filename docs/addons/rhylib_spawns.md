# rhylib_spawns: Spawn points

Named respawn points for each battalion, and event spawns staff switch on for an event. While dead, players see a list of the points they may use and pick one with the number keys; every spawn (respawn, job change, joining) then puts them on a point that fits them. Staff press E on a point to rename it, set its battalion, open or close an event spawn, or teleport every living player to it.

## Requirements

- Required: rhylib_core.
- Recommended: rhylib_menus (the respawn list and the staff edit menu; without it nobody sees the list and players go to their default point), rhylib_toolgun (placing and naming), DarkRP (battalions come from job `battalion` fields and job categories), rhylib_roster (roster battalion).
- Optional: rhylib_mp (jailed players aren't moved).
- Model: config `model`, default `models/props_combine/combine_mine01.mdl` (ships with GMod).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_spawns.lua` | shared | Loads the module. |
| `lua/entities/rhylib_spawn_point.lua` | shared | Spawn point entity (blue). |
| `lua/entities/rhylib_event_spawn.lua` | shared | Event spawn (orange), based on the spawn point. |
| `lua/rhylib/spawns/sh_00_config.lua` | shared | Settings, permission, `S.InBattalion`, `S.Options`. |
| `lua/rhylib/spawns/sv_10_spawns.lua` | server | Respawn list, placement, staff edits, teleport, saving. |
| `lua/rhylib/spawns/cl_10_spawns.lua` | client | Respawn list panel, staff edit menu. |

## For server owners

### Settings

Config module `spawns`:

| Key | Default | What it does |
|---|---|---|
| `model` | `"models/props_combine/combine_mine01.mdl"` | Spawn point model. |

```lua
Rhylib.Config.Set("spawns", "model", "models/mypack/spawnpad.mdl")
```

### Commands and permissions

| Permission | Default | Used for |
|---|---|---|
| `rhylib.spawns.admin` | admin | E edit menu, event open/close, teleport everyone, `rhylib_spawns_save`. |

| Command | Who | What it does |
|---|---|---|
| `rhylib_spawns_save` | console or `rhylib.spawns.admin` | Saves this map's permanent spawn points now. |

Staff edit menu (E on a point):

- Rename (shown in the respawn list; max 40 characters).
- Battalion (spawn points only): Everyone, or one of the jobs' `battalion` values / DarkRP job categories.
- Event spawns: Open / Close (chat message to everyone; dead players' lists refresh) and Teleport everyone here (every living, non-jailed player, in rings of 8 around the point).

### Placing things / saving

- Place with the toolgun (Spawns > "Spawn point" / "Event spawn"; the "Beacon name" box names it) or the spawn menu (Rhylib: Spawn points, admin only).
- Make it permanent with the toolgun's Permanent tool (Staff tools). Only permanent points are saved, in Data `spawns`/`<map>`, and come back at map load and after a cleanup.
- Event spawns always come back closed.

## For players (short)

- While dead, a "Respawn point" panel shows on the right: number keys 1-9 pick (the highlighted one is where you'll come back), then respawn as usual.
- Order of the list: open event spawns, your battalion's points, points for everyone. Nothing picked = the first one.
- No points for you = the map's normal spawns.

## For developers

### Public functions (`Rhylib.Spawns`)

| Function | Realm | Returns | Description |
|---|---|---|---|
| `InBattalion(ply, bn)` | shared | bool | Roster battalion (NW2 `rhylib_bn`), job `battalion` or job category matches; `""` = everyone. |
| `IsPoint(ent)` | shared | bool | A spawn point or event spawn. |
| `Options(ply)` | shared | list | `{ { ent, event }, ... }` best first. |
| `Target(ply)` | server | entity/nil | Their pick if still allowed, else the first option. |
| `SendList(ply)` | server | — | Send the respawn list. |
| `RefreshDead()` | server | — | Re-send lists to every dead player. |
| `OpenEdit(ply, ent)` | server | — | Staff edit menu (checks the perm). |
| `TeleportAll(ent)` | server | count | Teleport everyone alive and not jailed to the point. |
| `Save()` / `Load()` | server | count / — | Save permanent points / respawn the saved ones. |

Entity: NetworkVars `BeaconName` (String), `Battalion` (String, "" = everyone), `Active` (Bool, event spawns: open); `ENT.Event`; `ENT:SpawnPos()` (top of the model).

```lua
-- server: open every event spawn on the map
for _, e in ipairs(ents.FindByClass("rhylib_event_spawn")) do e:SetActive(true) end
Rhylib.Spawns.RefreshDead()
```

### Hooks

Listens to (server): `PlayerDeath` (list 0.5 s later), `PlayerSpawn` (closes the list, moves the player to `S.Target` a tick later, then `Rhylib.Lying.Unstick`), `PlayerDisconnected`, `EntityRemoved` (lists refresh), `InitPostEntity` (load +1 s), `PostCleanupMap` (load). Client: `PlayerBindPress` (slot1-9 while the list is up, priority -30). Fires none.

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `spawn.list` | server → dead player | Bool open; UInt6 count; per point UInt13 entindex, String name, Bool event, UInt16 metres; UInt13 pick | Respawn list (false = close). |
| `spawn.pick` | client → server | UInt13 entindex (0 = default) | Choose a point (rate 5/s, dead only). |
| `spawn.edit` | server → staff | Entity | Open the edit menu. |
| `spawn.set` | client → server | Entity, UInt3 op, [String text for op 0/1] | Rename / battalion / event toggle / teleport (rate 4/s). |

### Saved data

`Data "spawns"/<map>` = `{ { class, name, bn, pos = {x,y,z}, yaw } }` (permanent points only). The list is in `Rhylib.PLACEMENT_CLASSES` (rhylib_admin's freezeprops leaves them alone). `rhylib_purge_maps` (core) removes rows for maps the server no longer has.

### Examples

Make your own respawn rule: a medic-only point (shared, extend `S.Options`):

```lua
local S = Rhylib.Spawns
local base = S.Options
function S.Options(ply)
    local list = base(ply)
    if not (Rhylib.Medical and Rhylib.Medical.IsMedic(ply)) then
        for i = #list, 1, -1 do
            if list[i].ent:GetBeaconName() == "Med bay" then table.remove(list, i) end
        end
    end
    return list
end
```

## Notes and gotchas

- Placement runs a tick after PlayerSpawn; anything that moves players later (admin revive, the jail) wins.
- Placing alone saves nothing: use the Permanent tool.
- Only open event spawns are offered; their Battalion field isn't used.
