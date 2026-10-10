# rhylib_toolgun: Staff toolgun

The host's spawn tool, held like the DC-17 with a BTX-42 pistol model. LMB places the chosen thing where you aim (droids, clones, preset squads, armouries, medical fixtures, computers, jail parts, jammers, spawn points, training beacons, test dummies...), facing you; RMB removes a Rhylib thing or anything the toolgun spawned; R opens the spawn window with a "Rhylib" tab of everything it can place. It also paints orders onto droid and clone NPCs, makes things permanent (the only way anything placed is saved), and can spawn any prop, entity, NPC, vehicle or weapon picked in the spawn window ("Spawn with Rhy's toolgun").

## Requirements

- Required: rhylib_core, rhylib_weapons (the toolgun is built on `rhylib_base`).
- Recommended: rhylib_menus (the spawn window and its Rhylib tab), rhylib_droids (NPCs, orders, presets, follow tool, droid mode / aggression row), rhylib_armoury, rhylib_medical, rhylib_datapad, rhylib_mp, rhylib_radio, rhylib_spawns, rhylib_training, rhylib_eod (their entries only appear when installed).
- Workshop content: "[TFA] StarWars Reworked Shared Resources and Assets" (1741985166: the DC-17 carrier `models/bf2017/c_scoutblaster.mdl`) and the jajoff TC-13J pack (BTX-42 `models/jajoff/sps/cgiweapons/tc13j/btx42_pistol.mdl`).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_toolgun.lua` | shared | Loads the module. |
| `lua/weapons/rhylib_toolgun.lua` | shared | The SWEP (fires nothing; clicks go to `Rhylib.Tool.Click`). |
| `lua/rhylib/toolgun/sh_00_config.lua` | shared | Entry list, categories, entry models, Permanent target, access checks. |
| `lua/rhylib/toolgun/sv_10_tool.lua` | server | Placing, spawning, removing, Permanent tool, follow, giving, !keeptoolgun. |
| `lua/rhylib/toolgun/cl_10_tool.lua` | client | Chosen entry, the spawn window tab, R key, HUD, outlines, aim ring, droid mode labels. |

## For server owners

### Settings

No config settings of its own. The toolgun's models are on the Models page (`weapon.rhylib_toolgun.*`). Placed things use their own addons' settings (droid caps `droids maxActive` / `cloneMax`, brush radius, etc.).

### Commands and permissions

| Permission | Default | Used for |
|---|---|---|
| `rhylib.toolgun` | admin | Holding the toolgun and using every entry, spawn-window spawning, Re-save. |
| entry `perm` (e.g. `rhylib.eod.gm`) | set by that addon | Limited access: only those entries (and removing their things, never permanent ones). |

| How | What it does |
|---|---|
| `!toolgun` / `/toolgun` (chat), `rhylib_toolgun` (console), spawn menu Weapons > Rhylib: Staff tools | Gives and selects the toolgun. |
| `!keeptoolgun` / `/keeptoolgun` | Toggle: you get the toolgun again 0.5 s after every spawn (saved per player). |

### Placing things / saving

- Pick an entry in R > Rhylib tab, LMB to place. Placed things face you, sit on the surface, are frozen and get an undo entry.
- "Droids at once" 1/3/5 places that many in a ring (entries with a count). "Beacon name" names spawn points and beacons. With rhylib_droids: "New droids" Guard/Patrol/Attack/Roam and the live Aggression 1-5 for every droid.
- Nothing placed is saved. Staff tools > Permanent: LMB makes the aimed thing permanent (or saves where it is now), RMB stops keeping it. While picked, permanent things have an orange outline and the aimed one a light blue one. "Re-save permanent things" saves everything permanent again where it stands. See rhylib_core's guide (Permanent things).
- RMB removes: Rhylib entries' classes, droids, clones, B2 rockets, droid markers (aim within 80 units), mines (within 32), and anything the toolgun or spawn window spawned. Never players or map entities. Removing a permanent thing keeps it gone after a map change.

Categories in the Rhylib tab, in order: Staff tools, Clone NPCs, Clone orders, Droid NPCs, Droid orders, EOD, Spawns, Armoury, Medical, Base, Training, Testing, then any others alphabetically.

## For players (short)

Staff only:

| Key | What it does |
|---|---|
| LMB | Place / paint the order / make permanent / spawn the picked thing. |
| RMB | Remove what you aim at / stop keeping it (Permanent) / clones follow (follow tool). |
| R | Tap: open the spawn window (stays open). Hold: open while held. Tap twice: GMod's old Q menu. |

Client convars: `rhylib_tool_entry`, `rhylib_tool_count`, `rhylib_tool_name`, `rhylib_tool_droidmode`, `rhylib_tool_custom`.

## For developers

### Public functions (`Rhylib.Tool`)

| Function | Realm | Returns | Description |
|---|---|---|---|
| `Entries()` | shared | list | Installed entries (built once; fires `Rhylib.ToolEntries`). |
| `ById(id)`, `ByClass(class)` | shared | entry/nil | Look up an entry. |
| `ClassModel(class)`, `EntryModel(entry)` | shared | path/nil | The model an entry places (tile pictures, previews). |
| `PermaTarget(ply)` | shared | entity/nil | What the Permanent tool works on: the aimed entity, else the nearest scripted entity within 48 units of the hit point. |
| `FullAccess(ply)`, `CanEntry(ply, e)`, `EntryPerms()` | shared | | Access checks (client list; the server re-checks with Perms). |
| `AnyAccess(ply, cb)` | server | | cb(true) with rhylib.toolgun or any entry perm. |
| `Give(ply)` | server | | Give and select the toolgun. |
| `KeepsToolgun(ply)` | server | bool | !keeptoolgun state. |
| `Chosen()` | client | entry | The entry LMB uses now. |
| `Click(wep, which)`, `DrawHUD(wep)`, `DrawPermaHUD()` | client | | Used by the SWEP. |
| `CAT_ORDER`, `RANGE` (6000), `KINDS` | | | Category order; reach; spawn-window kinds. |

### Entry fields

| Field | Meaning |
|---|---|
| `id`, `name`, `cat` | Unique id, label, category. |
| `class` | Entity LMB creates (RMB can remove it). |
| `count = true` | Uses "Droids at once". |
| `named = true` | Gets the beacon name (`SetBeaconName`). |
| `marker`, `side` | Droid marker kind 1-3, side 1 = clones. |
| `order`, `side` | Brush: `D.PaintMode(pos, order, side)`. |
| `preset` | `D.SpawnPreset` squad. |
| `follow = true` | Clone follow tool. |
| `perma = true` | Permanent tool. |
| `place = fn(ply, tr, count, yaw)` | Own placing; return the entities made (undo, owner set for you). |
| `perm = "permission"` | Staff with only this permission may use it. |

### Hooks

Fired: `Rhylib.ToolEntries(list)` (both realms, once, when the list is first built): append entries.

Listens to: `PlayerSpawnedSENT/NPC/Vehicle/SWEP` (marks spawn-window spawns), `PlayerSpawn` (!keeptoolgun), `PlayerSay` (chat commands, priority -50); client `PlayerBindPress` (+reload, -30), `Think`, `PreDrawHalos`, `PostDrawTranslucentRenderables`, `HUDPaint`, `InitPostEntity` (adds the spawn-window tab).

Spawn-window spawning goes through sandbox's own code (`PlayerSpawnObject`, `PlayerSpawnProp`, `Spawn_SENT` ...), so the gamemode's limits and prop protection apply; things spawned get `ent.rhylibToolSpawned` + NW2Bool `rhylib_toolSpawned`.

### Network messages

All client → server; the server traces the player's own aim and checks the toolgun is held.

| Name | Contents | Purpose |
|---|---|---|
| `tool.place` | String id, UInt3 count, String name, UInt3 droid mode | LMB with an entry (rate 20/s). |
| `tool.spawn` | UInt3 kind, String name, UInt6 skin, String bodygroups, String NPC weapon | LMB with a spawn-window pick (full access, rate 20/s). |
| `tool.remove` | — | RMB remove (rate 20/s). |
| `tool.perma` | Bool on | Permanent tool LMB/RMB (rate 10/s). |
| `tool.follow` | — | Follow tool RMB (rate 10/s). |
| `tool.save` | — | Re-save every permanent thing (rate 1/s). |
| `tool.give` | — | Give me a toolgun (rate 1/s). |

### Saved data

`Data "toolgun"/"keep_<SteamID64>"` = true while !keeptoolgun is on.

### Examples

Add your addon's entity to the toolgun (shared file):

```lua
Rhylib.Hook.Add("Rhylib.ToolEntries", "myaddon.tool", function(list)
    list[#list + 1] = { id = "my_crate", name = "Supply crate (mine)", cat = "Base", class = "myaddon_crate" }
end)
```

Let gamemasters place only your entries:

```lua
Rhylib.Perms.Register("myaddon.gm", "admin", "Place event props with the toolgun")
Rhylib.Hook.Add("Rhylib.ToolEntries", "myaddon.tool", function(list)
    list[#list + 1] = { id = "my_barricade", name = "Barricade", cat = "Events", class = "myaddon_barricade", perm = "myaddon.gm" }
end)
```

An entry that places several things at once:

```lua
{ id = "my_wall", name = "Sandbag wall", cat = "Base", class = "myaddon_sandbag",
  place = function(ply, tr, count, yaw)
      local out = {}
      for i = -1, 1 do
          local e = ents.Create("myaddon_sandbag")
          e:SetPos(tr.HitPos + Angle(0, yaw, 0):Right() * i * 40)
          e:SetAngles(Angle(0, yaw, 0))
          e:Spawn()
          out[#out + 1] = e
      end
      return out
  end }
```

## Notes and gotchas

- `Tool.Entries()` is built once and cached in `Rhylib.Tool.list` (kept across a Lua refresh); a hook added after the first call isn't seen until a map change. Hook-added entries aren't checked for an installed class.
- A hook-added entry needs a `class` or one of `order`/`preset`/`follow`/`perma`: the Rhylib tab builds its tooltip from `class` otherwise.
- If a new entity's model isn't from a known source, add it to `Tool.ClassModel` or set `ENT.Model` so the tile and preview show it.
- The toolgun is not an inventory item and isn't in any armoury.
