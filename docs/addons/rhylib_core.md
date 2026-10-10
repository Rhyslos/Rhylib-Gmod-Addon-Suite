# rhylib_core: Core library

The base every other Rhylib addon needs. On its own it adds little a player sees: the lying-body system (downed, stunned and knocked-down players become ragdolls), the first-person body camera, gun sway and footstep feel, and chat/voice portraits. For server owners it adds the in-game Server settings page (with model overrides), the "Permanent" save system for placed things, a profiler, a bot load test and saved-data clean-up commands. For developers it is the API the rest of the suite is built on: the module loader, config, a hook bus with priorities, rate-limited networking with batches, a key/value database, permissions, and UI helpers.

## Requirements

- Required: nothing. Install it first; every other Rhylib addon needs it.
- Gamemode: DarkRP for the full suite. The core itself works in any sandbox-derived gamemode (the load test's job picking uses DarkRP's `RPExtraTeams` / `changeTeam` when present).
- Works with ULX, SAM, sAdmin and other CAMI admin mods for permissions; with `rhylib_admin` installed its ranks answer instead.
- No Workshop content.

## Files

All module files are in `lua/rhylib/core/`. The prefix sets the realm: `sh_` both, `sv_` server, `cl_` client.

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/_rhylib_core.lua` | shared | Loader: `Rhylib` table, `Print/Warn/Error`, `LoadModule`, `LoadConfigFiles`. Runs first (underscore). |
| `sh_00_config.lua` | shared | `Rhylib.Config`: register, get and set settings. |
| `sh_10_profiler.lua` | shared | `Rhylib.Profiler`: hook time and net bytes; `rhylib_profile*`, `rhylib_status`. |
| `sh_20_hooks.lua` | shared | `Rhylib.Hook`: the hook bus (priorities, one GMod hook per event). |
| `sh_25_models.lua` | shared | `Rhylib.Models`: every model path becomes a setting in module `models`. |
| `sh_30_net.lua` | shared | `Rhylib.Net`: prefixed messages, rate-limited receive, batches; profiler net counting. |
| `sh_40_perms.lua` | shared | `Rhylib.Perms`: permissions through rhylib_admin, CAMI or GMod flags. |
| `sh_50_hitgroup.lua` | shared | `Rhylib.HitGroupAt`: body part from a hit position. |
| `sh_60_lying.lua` | shared | `Rhylib.Lying`: lying players become a server ragdoll. |
| `sh_61_knock.lua` | shared | Knockdowns (`L.Knock` / `L.Unknock`), soft and ragdoll. |
| `sh_62_perma.lua` | shared (mostly server) | `Rhylib.Perma`: permanent things and their saving. |
| `sv_10_data.lua` | server | `Rhylib.Data`: SQLite key/value store with batched writes. |
| `sv_15_settings.lua` | server | Server settings page: overrides, saving, checks, nets. |
| `sv_17_profiler.lua` | server | Live profiler data for the staff Profiler page. |
| `sv_18_loadtest.lua` | server | `rhylib_loadtest` bot load test. |
| `sv_19_purge.lua` | server | `rhylib_data_stats` and the purge commands. |
| `cl_10_ui.lua` | client | `Rhylib.UI.Colors`, `Rhylib.UI.Font`. |
| `cl_15_settings.lua` | client | `Rhylib.Settings` on the client: receives overrides, asks for changes. |
| `cl_20_portrait.lua` | client | `Rhylib.UI.DrawPortrait`: cached head-and-shoulders renders. |
| `cl_60_lying.lua` | client | Lying ragdolls' colour/visibility; soft-knock client ragdolls. |
| `cl_65_bodycam.lua` | client | First-person body camera while lying or dead. |
| `cl_66_motion.lua` | client | Gun sway, landing dip, footstep feel, idle sway, optional camera bob. |

## For server owners

### Settings

Config module `core`:

| Key | Default | What it does |
|---|---|---|
| `dataFlushDelay` | `3` | Seconds between batched database saves. |

Config module `models`: one setting per model the suite reads from a table field (weapons, entities, items, plus tables addons add). Key = an id such as `weapon.rhylib_dc15a.WorldModel`, `entity.<class>`, `item.jetpack`, or an addon's own (rhylib_armoury's cabinets are `armoury.<key>`); default = the model the code ships with. They appear on the Server settings page's Models list together with other modules' model settings (any setting whose default ends in `.mdl`).

How to change settings:

- In game: Staff > Server settings (needs `rhylib_menus` and the `rhylib.settings` permission). Changes apply at once, are saved (Data `core`/`settings`), and are sent to every client. "Reset" goes back to the host file value or the default.
- A host config file: any `lua/rhylib_config/*.lua`, ideally in its own addon folder (e.g. `garrysmod/addons/rhylib_config/lua/rhylib_config/settings.lua`) so Workshop updates never overwrite it. See `docs/config-example.lua`.

```lua
Rhylib.Config.Set("core", "dataFlushDelay", 5)
Rhylib.Config.Set("models", "item.jetpack", "models/mypack/jetpack.mdl")
```

Order: Server settings page > host file > default.

The `admin` module's settings can't be changed from the page (a bad value could lock everyone out); use a host file for those.

Model settings from the page: the path must look like `models/folder/name.mdl` (no `..`, `:`, backslashes or control characters) and the server must have it (`util.IsValidModel`). Empty = back to the shipped model. Things already placed keep their old model until made again; the page marks the setting "map change needed".

### Commands and permissions

Permissions (default ranks; change them in your admin mod):

| Permission | Default | Used for |
|---|---|---|
| `rhylib.settings` | superadmin | The Server settings page and `rhylib_settings_reset`. |
| `rhylib.profiler` | superadmin | The live Profiler page. |

Console commands. "Console or superadmin" commands check `IsSuperAdmin()` directly, not a permission.

| Command | Who | What it does |
|---|---|---|
| `rhylib_settings_reset <module> [key]` | console or `rhylib.settings` | Removes page overrides (one key, or the whole module). The undo for a value that broke something. |
| `rhylib_profile 0/1` | anyone on their own realm (server convar: server console) | Records hook time and net bytes. Server and client convars are separate. |
| `rhylib_profile_report` | console or superadmin | Prints the top 25 hook handlers (ms/s) and net messages (B/s) since the last reset. |
| `rhylib_profile_report_cl` | client | The same for your client. |
| `rhylib_profile_reset` | console or superadmin | Clears the server numbers. |
| `rhylib_status` | console or superadmin | Lists loaded Rhylib modules, versions and file counts. |
| `rhylib_loadtest <bots> [fire 0/1] [droids]` | console or superadmin | Adds load bots up to `<bots>` (max 128; needs free player slots), gives each a battalion trooper job and a rifle with infinite test ammo, and lets them roam and fire (fire 1 is the default). `[droids]` spawns up to 200 droids near them (needs `rhylib_droids`; the droid limit applies). Load bots don't hurt each other and respawn 5 s after dying. |
| `rhylib_loadtest_stop` | console or superadmin | Kicks the load bots, removes the load droids. |
| `rhylib_data_stats` | console or superadmin | Rows and KB of saved data per module. |
| `rhylib_purge_bots [confirm]` | console or superadmin | Saved rows of bots (keys containing `9007199684`, or `BOT`). |
| `rhylib_purge_maps [confirm]` | console or superadmin | Placement rows (armoury, spawns, dp_places, med_places, mp_places, training) for maps the server no longer has. |
| `rhylib_purge_inactive <days> [confirm]` | console or superadmin | Everything saved for players whose character (rhylib_roster) wasn't seen for `<days>` (at least 7) and who aren't online: every row whose key holds their SteamID64, roster member lists, clone numbers. Never the `admin` module (ranks, bans). |

Every purge is a dry run that only counts, unless the last word is `confirm`. After a purge, change the map so every module reads its data again.

Bot load test notes: start the server with enough slots (e.g. `maxplayers 82` for 80 bots). Bots run no client code, so this measures the server and bandwidth only. Watch it on Staff > Profiler or with `rhylib_profile_report`.

### Placing things / saving (permanent things)

Nothing placed with the toolgun or spawn menu is saved by itself. Staff make a thing permanent with the toolgun's "Permanent" entry (rhylib_toolgun, category Staff tools): LMB = make it permanent (it is frozen in place) or save where it stands now; RMB = stop keeping it. Permanent things come back every map load and after a map cleanup; `!cleanup` (rhylib_admin) wipes the rest.

- Rhylib fixtures (armouries, med bay, jail, computers, training beacons, spawn points, jammers) are saved by their own addon, but only the permanent ones.
- Everything else (props, ragdolls in their pose, other addons' entities) goes in Data `perma`/`<map>`.
- Can't be made permanent: the world, players, map entities, NPCs/NextBots, vehicles, held weapons, lying bodies, live explosives, things parented to something else.
- Removing a permanent thing (toolgun RMB, undo, remover, breaking) saves the list again without it.

## For players (short)

Client settings, in the pause menu Settings > Camera & motion tab (with rhylib_menus), or the console:

| Convar | Default | What it does |
|---|---|---|
| `rhylib_bodycam` | 1 | First person: while you're down, stunned, knocked or dead the view sits in your body's eyes. |
| `rhylib_gunbob` / `rhylib_gunbob_scale` | 1 / 1 | Gun and hands sway with your steps (the view stays still). Scale 0-2. |
| `rhylib_idlesway` | 1 | Standing still, the gun drifts with your breathing (more when out of stamina, less aiming or crouched). |
| `rhylib_landdip` | 1 | The gun dips when you land. |
| `rhylib_footstepfeel` / `rhylib_footstepfeel_scale` | 1 / 1 | Your own footsteps a bit louder, plus a smooth extra gun sway and roll per step. |
| `rhylib_camerabob` / `rhylib_camerabob_scale` | 0 / 1 | A small up/down camera dip per step while sprinting (off by default: can cause motion sickness). |

While lying alive with the body camera you can look around a little with the mouse (70° sideways, 45° up/down); getting up turns you to where the head was looking.

## For developers

Everything lives under the global `Rhylib`. Realms are noted where a function isn't on both.

### Making an addon (loader)

```lua
-- addons/myaddon/lua/autorun/myaddon.lua
if not Rhylib then
    print("[myaddon] needs rhylib_core")
    return
end
Rhylib.LoadModule("myaddon", { name = "My addon", version = "1.0.0" })
```

`Rhylib.LoadModule(id, info)` → module record `{ id, name, version, files }` (also `Rhylib.Modules[id]`). Loads every file in `lua/rhylib/<id>/`: all `sh_` files, then `sv_` (server only), then `cl_` (sent to and run on clients), alphabetical within each group, so number them: `sh_00_config.lua`, `sv_10_logic.lua`, `cl_10_hud.lua`. A second call with the same id does nothing. Fires `Rhylib.ModuleLoaded(id, mod)`.

Other addons load in their autorun file order (roughly alphabetical by file name), so another addon's table may not exist yet when your file loads. Check for it when you use it, or wait for `Rhylib.ModuleLoaded`:

```lua
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "myaddon.inv", function(id)
    if id == "inventory" then registerMyItems() end
end)
```

Write refresh-safe code: `MyAddon = MyAddon or {}`, named hook ids, `timer.Create` with fixed names.

`Rhylib.Print(module, fmt, ...)`, `Rhylib.Warn(...)`, `Rhylib.Error(...)`: console lines tagged `[Rhylib:<module>]`; `Error` uses `ErrorNoHalt`.

```lua
Rhylib.Print("myaddon", "Loaded %d crates", #crates)
```

`Rhylib.LoadConfigFiles()`: loads `lua/rhylib_config/*.lua` (both realms). Called once by the loader right after the core module; hook `Rhylib.CoreLoaded()` fires after it.

### Config (`Rhylib.Config`, shared)

| Function | Returns | What it does |
|---|---|---|
| `Register(module, key, default, desc, meta)` | — | Declares a setting. The default's type is the setting's type. `meta` (optional): `{ name, group }` for the settings page. |
| `Get(module, key)` | value | Override > host value > default. Unknown key: nil and a one-time warning. |
| `Set(module, key, value)` | — | Host file value. Works before or after Register. |
| `SetOverride(module, key, value or nil)` | — | Sets/clears the page override on this realm and fires `Rhylib.ConfigChanged`. Doesn't save or network (the settings code does that). |
| `Base(module, key)` | value | The value without the override. |
| `IsModelDefault(default)` | bool | True for a string ending in `.mdl`. |

Register in a `sh_` file when client code reads the value: shared (predicted) code then reads the same number on both sides, since overrides are copied to every client.

```lua
-- sh_00_config.lua
Rhylib.Config.Register("myaddon", "range", 500, "How far the scanner reaches (units)")
Rhylib.Config.Register("myaddon", "crateModel", "models/props_junk/wood_crate001a.mdl", "Crate model")

-- anywhere, when needed (not copied at file load)
local range = Rhylib.Config.Get("myaddon", "range")

-- react to a change from the Server settings page
Rhylib.Hook.Add("Rhylib.ConfigChanged", "myaddon.cfg", function(module, key, value)
    if module == "myaddon" and key == "range" then rebuildSomething(value) end
end)
```

Caveat: code that copies a value into a local at file load keeps the old value (server: until a map change; clients: always the base value, because overrides arrive after their Lua loaded).

### Hook bus (`Rhylib.Hook`, shared)

Use it instead of `hook.Add`. For each event the bus adds one GMod hook (`"Rhylib.Bus"`) and calls its handlers from a flat array.

| Function | What it does |
|---|---|
| `Add(event, id, fn, priority)` | Adds a handler, or replaces the one with the same id. `priority` default 0. |
| `Remove(event, id)` | Removes it. |
| `RebuildAll()` | Remakes every dispatcher (used by the profiler). |

Rules:

- Lower priority runs first; equal priority runs in the order added. Negative numbers are fine.
- A handler that returns anything other than nil stops the chain, and that value goes back to the engine or `hook.Run` caller. `false` is a value: it stops the chain too. Return nothing to let the others run.
- Up to 6 return values are passed on.
- Priorities only order Rhylib handlers among themselves. Against other addons' plain `hook.Add` handlers the order is whatever GMod gives.
- The id's part before the first `.` is the module name the live profiler groups by: use `"myaddon.something"`.
- Custom events work the same way: `hook.Run("Rhylib.X", ...)` reaches handlers added with `Rhylib.Hook.Add("Rhylib.X", ...)`.

```lua
-- runs before armour (0) and medical; blocks all damage to god-mode players
Rhylib.Hook.Add("EntityTakeDamage", "myaddon.god", function(ent, dmg)
    if ent.myGodMode then return true end
end, -500)

-- last in the tick (the batch flush is at 1000)
Rhylib.Hook.Add("Tick", "myaddon.late", function() ... end, 900)
```

Some priorities the suite uses (for placing your own): `EntityTakeDamage` soft knock -1000, load-test friendly fire -1300, lying ragdoll forward -300, lying direct block -350; `PlayerSpawn` knock clean-up -110, lying clean-up -100; `StartCommand` knock -140; `SetupMove` knock -94; `CalcView` body camera -50, camera bob -40; `Tick` batch flush 1000.

### Networking (`Rhylib.Net`, shared)

Names are short (`"inv.move"`); every function adds the `rhylib.` prefix. Read and write exact bit sizes; never `net.WriteTable` for frequent messages; send only to the players who need it.

| Function | Realm | What it does |
|---|---|---|
| `Name(name)` | both | `"rhylib." .. name` (for raw `net.Receive`). |
| `Register(name)` | server | `util.AddNetworkString`. Needed for messages the server only sends. |
| `Start(name)` | both | `net.Start` with the prefix. |
| `Receive(name, fn(ply, len), { rate, burst })` | server | Registers and handles a client message, rate limited per player (token bucket: `rate` per second, default 10; `burst` saved up, default = rate). Over the limit = dropped silently. |
| `Receive(name, fn(len))` | client | Handles a server message. |
| `CreateBatch(name, writeItem)` | server | Batch object; see below. |
| `SendItems(name, items, write, sendFn, target)` | server | Writes a list in the batch format, split as needed, sent with `sendFn(target)`. |
| `ReceiveBatch(name, readItem, onItem)` | client | Reads a batch message; `onItem(item)` per item. |
| `MSG_SOFT_LIMIT` | both | 60000 bytes: a batch message is closed past this. |

Client request with a rate limit:

```lua
-- server (sv_ file)
Rhylib.Net.Receive("myaddon.use", function(ply, len)
    local ent = net.ReadEntity()
    -- the client only asks: check everything
    if not IsValid(ent) or ent:GetClass() ~= "myaddon_crate" then return end
    if ent:GetPos():DistToSqr(ply:GetPos()) > 120 * 120 then return end
    Rhylib.Perms.Check(ply, "myaddon.use", function(ok)
        if ok and IsValid(ply) and IsValid(ent) then ent:Open(ply) end
    end)
end, { rate = 4, burst = 8 })

-- client
Rhylib.Net.Start("myaddon.use")
net.WriteEntity(crate)
net.SendToServer()
```

Server to client:

```lua
-- server
Rhylib.Net.Register("myaddon.score")            -- at file load
Rhylib.Net.Start("myaddon.score")
net.WriteUInt(score, 10)
net.Send(ply)

-- client
Rhylib.Net.Receive("myaddon.score", function(len)
    MyAddon.score = net.ReadUInt(10)
end)
```

Batches: many small events per tick in one message per recipient. Queued items are written at the end of the server tick (Tick hook, priority 1000); nothing is sent on a tick with nothing queued. Wire format: a 1-bit "item follows" before each item, a 0 bit at the end; a message is closed and a new one started once it passes ~60 KB. A writer that errors is reported and that queue dropped. The client reads at most 4096 items per message.

```lua
-- server: create once at file load
local pings = Rhylib.Net.CreateBatch("myaddon.ping", function(item)
    net.WriteVector(item.pos)
    net.WriteUInt(item.kind, 3)
end)
pings:Send(ply, { pos = tr.HitPos, kind = 2 })       -- one player
pings:SendTo(squad, { pos = tr.HitPos, kind = 2 })   -- a list of players
pings:Broadcast({ pos = tr.HitPos, kind = 1 })       -- everyone

-- client
Rhylib.Net.ReceiveBatch("myaddon.ping", function()
    return { pos = net.ReadVector(), kind = net.ReadUInt(3) }
end, function(item)
    MyAddon.AddPing(item.pos, item.kind)
end)
```

Make a new table per item: items are written at the end of the tick, so changing a table after queueing it changes what gets sent.

The server wraps `net.Start` and `net.Send/Broadcast/SendOmit/SendPVS/SendPAS` once to count every message (other addons' too) for the profiler: bytes × human recipients (bots count 0; PVS/PAS counted once). It costs nothing while the profiler is off.

### Data (`Rhylib.Data`, server)

A key/value store per module in GMod's SQLite (`garrysmod/sv.db`, table `rhylib_kv`, value stored as JSON `{"v": value}`).

| Function | What it does |
|---|---|
| `Get(module, key)` | The value or nil. Reads the queue first, so it always returns the latest value. |
| `Set(module, key, value)` | Queues a save. Value: table, string, number or boolean. |
| `Delete(module, key)` | Queues a delete. |
| `Flush()` | Writes the queue now in one transaction (also runs `dataFlushDelay` s after the first change, and on `ShutDown`, which includes map changes). |

```lua
local sid = ply:SteamID64()
local stats = Rhylib.Data.Get("myaddon", sid) or { kills = 0 }
stats.kills = stats.kills + 1
Rhylib.Data.Set("myaddon", sid, stats)

-- per map
Rhylib.Data.Set("myaddon", game.GetMap(), rows)
```

Notes: keys become strings. JSON doesn't keep Vectors, Angles or Colors as such (store numbers: `{ p.x, p.y, p.z }`) and number keys of tables may come back as strings. `Get` runs a query when the key isn't queued, so cache what you read often. Use SteamID64 for per-player keys and the map name for per-map keys: the purge commands rely on that (a key containing a SteamID64 is removed with that player).

### Permissions (`Rhylib.Perms`, shared; checks on the server)

| Function | What it does |
|---|---|
| `Register(name, minAccess, desc)` | Declares a permission; `minAccess` `"user"`, `"admin"` (default) or `"superadmin"` is the rank an admin mod gives it by default. Registered with CAMI too (again at `Initialize`, for admin mods that load later). |
| `Check(ply, name, callback(allowed))` | Asks. The server console (`ply` nil/NULL) always passes. Unknown names fail and warn. |
| `list` | `[name] = { minAccess, desc }`. |

Who answers: `rhylib_admin` (`Rhylib.Admin.Has`) if installed, else CAMI, else GMod's admin/superadmin flags. With CAMI the callback may come later: re-check `IsValid(ply)` inside it.

```lua
Rhylib.Perms.Register("myaddon.spawn", "admin", "Spawn crates")   -- sh_ file

Rhylib.Perms.Check(ply, "myaddon.spawn", function(ok)
    if not IsValid(ply) then return end
    if not ok then return ply:ChatPrint("No permission") end
    spawnCrate(ply)
end)
```

### Profiler (`Rhylib.Profiler`, shared)

| Function / field | What it does |
|---|---|
| `enabled` | true while recording. |
| `SetEnabled(on)` | Turn on/off (clears the numbers; the hook bus swaps to timed dispatchers). |
| `Reset()` | Clear the numbers. |
| `AddTime(key, seconds)` | Add a timing (hook bus uses `"<event>/<handler id>"`). Doesn't check `enabled`. |
| `AddNet(name, bytes)` | Add net bytes (only while enabled). |
| `Report(printFn)` | Top 25 handlers and messages per second of play. |
| `hooks`, `net` | `[key] = { t, n }`, `[name] = { bytes, n }`. |

Time your own heavy code:

```lua
local P = Rhylib.Profiler
local t = P.enabled and SysTime()
scanEverything()
if t then P.AddTime("myaddon/scan", SysTime() - t) end
```

The live Profiler page (rhylib_menus, perm `rhylib.profiler`) subscribes with `core.profsub`; while anyone watches, the server profiler is on and `core.profdata` arrives every second (ticks/s, slowest tick, Rhylib hook ms per tick, net bytes, Lua memory, player/bot/entity/droid/bolt counts, per-module and top-15 lists). When the last viewer leaves it goes back to the `rhylib_profile` setting. State in `Rhylib.ProfLive`.

### Settings page (`Rhylib.Settings`)

Client:

| Function / field | What it does |
|---|---|
| `Request()` | Asks for the catalogue; the answer lands in `list`, then `onList()` runs. |
| `Set(m, k, value)` | Asks for a change (`nil` = reset). The server checks permission and value. |
| `list` | Rows `{ m, k, d, b, o, s, x, p }`: module, key, default, base, override, description, meta, map-change-needed. |
| `onList`, `onChanged(m, k)` | Set by the page to redraw. |

Server: `Rhylib.Settings.FixColors(value)` turns `{r,g,b,a}` tables back into Colors (JSON loses the metatable).

Value checks on the server: same type as the default; numbers finite and |v| ≤ 1e6, not negative where the default isn't; arrays stay arrays (same kind of first item); model settings must be a valid model path the server has.

### Model overrides (`Rhylib.Models`, shared)

Every model the suite reads from a table field is a setting in module `models`, and the registry writes the setting's value back into that field on both realms, so the code that reads the field uses the new model.

Found automatically (classes starting `rhylib_`, own fields only):

- Weapons: `PropModel`, `WorldModel` (also updates the weapon's inventory item model), `ViewModel`, `CarrierVM`, `DualCarrierVM`, `ModeProxies[mode].model`.
- Entities: `ENT.Model`, unless `ENT.ModelFromConfig` is set (then a module setting picks the model).
- Items (non-weapon): `def.model`, `def.iconModel`.

| Function / field | What it does |
|---|---|
| `Field(key, name, group, get, field, onApply)` | Register a field. `get()` returns the table holding it (nil = not on this realm now). The field's current `.mdl` path becomes the default. `onApply(value, entry)` runs after each apply. |
| `ApplyOne(key)`, `ApplyAll()` | Write the setting's value into the field. |
| `Current(key)` | The model in force for an entry. |
| `Scan()` | Find everything, run `Rhylib.ModelCatalogue`, apply all. Runs at Initialize, InitPostEntity, +2 s and on Lua refresh. |
| `pending` | (server) settings changed this map: "map change needed". |

Add your own table:

```lua
-- sh_ file
MyAddon.MODELS = MyAddon.MODELS or { crate = "models/props_junk/wood_crate001a.mdl" }

Rhylib.Hook.Add("Rhylib.ModelCatalogue", "myaddon.models", function(add)
    add("myaddon.crate", "Supply crate", "Entities: My addon",
        function() return MyAddon.MODELS end, "crate")
end)

-- read MyAddon.MODELS.crate when you create the entity (not a local copy)
```

On the client, a weapon whose fields change gets `SWEP:RhylibModelsChanged()` called (if defined) 0.2 s later, so it can rebuild cached props.

### Permanent things (`Rhylib.Perma`)

| Function | Realm | What it does |
|---|---|---|
| `Is(ent)` | shared | True if permanent (NW2Bool `rhylib_perma`). |
| `Register(classes, saveFn)` | server | Your addon saves these classes itself; `saveFn()` must save only `Is` entities. |
| `Mark(ent, on)` | server | Set the flag without saving (call it on what your loader spawns). |
| `Why(ent)` | server | nil if allowed, else the reason. |
| `Set(ent, on)` | server | What the toolgun calls: mark (and freeze) or unmark, then save. Returns `ok, message`. |
| `Save(class)` | server | Save that class's group 0.3 s later (debounced). |
| `Forget(ent)` | server | Remove it; it's saved again without it. |
| `SaveGeneric()`, `LoadGeneric()` | server | The plain list in Data `perma`/`<map>`. |
| `FreezeAll(ent)`, `TagMap()` | server | Freeze every physics part; mark what exists now as part of the map for `!cleanup`. |

Your own fixture with its own save data:

```lua
local function save()
    local rows = {}
    for _, e in ipairs(ents.FindByClass("myaddon_crate")) do
        if not Rhylib.Perma or Rhylib.Perma.Is(e) then
            local p = e:GetPos()
            rows[#rows + 1] = { pos = { p.x, p.y, p.z }, yaw = e:GetAngles().y }
        end
    end
    Rhylib.Data.Set("myaddon", game.GetMap(), rows)
    return #rows
end

local function load()
    for _, r in ipairs(Rhylib.Data.Get("myaddon", game.GetMap()) or {}) do
        local e = ents.Create("myaddon_crate")
        e:SetPos(Vector(r.pos[1], r.pos[2], r.pos[3]))
        e:SetAngles(Angle(0, r.yaw, 0))
        e:Spawn()
        if Rhylib.Perma then Rhylib.Perma.Mark(e, true) end
    end
end

if Rhylib.Perma then Rhylib.Perma.Register({ "myaddon_crate" }, save) end
Rhylib.Hook.Add("InitPostEntity", "myaddon.load", function() timer.Simple(1, load) end)
Rhylib.Hook.Add("PostCleanupMap", "myaddon.load", load)
```

Without a saver of your own, nothing is needed: permanent entities of any class go in the generic list (class, model, position, angles, skin, material, colour, render mode, collision group, frozen, bodygroups, and ragdoll limb positions).

### Lying players and knockdowns (`Rhylib.Lying`)

Downed (rhylib_medical), stunned (rhylib_mp) and knocked-down players become a server `prop_ragdoll` built from their pose and speed. The real player is hidden, kept on the ground under the ragdoll's pelvis (0.1 s timer), passes through other players, and can only be hurt through the ragdoll (hits on it are forwarded with the hit group of the nearest bone). The ragdoll freezes after 2.5 s. Dying while lying keeps the ragdoll as the corpse until respawn.

| Function | Realm | What it does |
|---|---|---|
| `Is(ply)` | shared | Downed, stunned or knocked. |
| `Ragdoll(ply)` | shared | The lying ragdoll or nil (client: also a soft-knock client ragdoll). |
| `Owner(ent)` | shared | The player a lying ragdoll belongs to, or nil. |
| `BodyPos(ply)` | shared | Ragdoll position + 6 up (else feet + 10): aim, distance and marker checks. |
| `Knocked(ply)`, `SoftKnocked(ply)` | shared | Knock state. |
| `Begin(ply)` | server | Lie down as a ragdoll. |
| `End(ply, noMove)` | server | Get up on the body (or stay put with `noMove`); dead = keep as corpse. |
| `Pull(ply, to, leash, speed)` | server | Drag: pull the chest towards `to` (call repeatedly). |
| `Unstick(ply)` | server | Nudge to the nearest clear spot (up to 40 units). |
| `HitGroup(rag, pos)` | server | Hit group of the ragdoll part nearest `pos`. |
| `Knock(ply, secs, push, soft)` | server | Knock down for `secs` (0 = until Unknock). Returns true if it happened. |
| `Unknock(ply)` | server | Get up now. |
| `ThirdPersonOn()`, `BodyCamOn()` | client | Third person wanted; view currently in the body. |
| `motion.Sway(wep, phaseShift, breathShift)` | client | The current gun sway: side, dip, pitch, yaw, roll (or nil). |

Soft knock (`soft = true`, used by explosion knockdowns): no server ragdoll. The player is thrown (`push`, at least 170 up), held crouched with no input, and takes no damage at all while down; each client shows its own ragdoll pulled towards the player. Ragdoll knock (training eliminations) uses `Begin`.

```lua
-- server: a 3 s knockdown away from a blast
local push = (ply:GetPos() - blastPos):GetNormalized() * 300
Rhylib.Lying.Knock(ply, 3, push, true)

-- find the player behind a body you aimed at
local target = Rhylib.Lying.Owner(tr.Entity) or tr.Entity
```

Network state: player NW2 `rhylib_rag` (ragdoll), `rhylib_ragCorpse`, `rhylib_corpse`, `rhylib_knockEnd` (Float: end time, -1 open-ended, 0 none), `rhylib_knockSoft`; ragdoll NW2 `rhylib_lyingRag`, `rhylib_ragOwner`.

Physgun, gravity gun, tools and properties can't touch lying ragdolls.

### Hit groups

`Rhylib.HitGroupAt(ent, pos)` → a `HITGROUP_` constant guessed from where `pos` is on `ent` (height share of the hull and side), for models whose hitboxes all say "generic". Shared, no traces.

```lua
local group = Rhylib.HitGroupAt(tr.Entity, tr.HitPos)
if group == HITGROUP_HEAD then dmg:ScaleDamage(2) end
```

### UI helpers (client)

| Function / field | What it does |
|---|---|
| `Rhylib.UI.Colors` | Palette: `bg`, `panel`, `border`, `text`, `textDim`, `accent`, `good`, `warn`, `bad`. |
| `Rhylib.UI.Font(size, weight)` | Font name; `size` is pixels at 1080p, scaled to the screen; weight default 500 (Roboto). Cached, safe every frame. Recreated on resolution change. |
| `Rhylib.UI.DrawPortrait(plyOrModel, x, y, size, alpha)` | Head-and-shoulders render of a model (128 px, 48 cached, one new render per frame; a plain plate until ready). |
| `Rhylib.UI.PortraitMaterial(model)` | The cached material or nil (queues it). |

```lua
Rhylib.Hook.Add("HUDPaint", "myaddon.hud", function()
    local C = Rhylib.UI.Colors
    Rhylib.UI.DrawPortrait(LocalPlayer(), 20, 20, 64)
    draw.SimpleText("Squad lead", Rhylib.UI.Font(18, 700), 92, 40, C.text)
end)
```

The full menu kit (windows, buttons, plates) is in rhylib_menus (`Rhylib.Menus.Kit`).

### Hooks

Fired by the core:

| Hook | Realm | When | Return value |
|---|---|---|---|
| `Rhylib.ModuleLoaded(id, mod)` | both | After each `LoadModule`. | ignored |
| `Rhylib.CoreLoaded()` | both | After the core module and host config files. | ignored |
| `Rhylib.ConfigChanged(module, key, newValue)` | both | A Server settings override set or cleared (also on clients when overrides arrive). | ignored |
| `Rhylib.ModelCatalogue(add)` | both | During `Models.Scan`; call `add(...)` (= `Models.Field`). | ignored |
| `Rhylib.ModelsChanged(key)` | both | A model setting changed. | ignored |
| `Rhylib.PlayerUnknocked(ply)` | server | A knockdown ended (any way). | ignored |
| `Rhylib.DataPurged()` | server | After a purge command removed rows (also from rhylib_roster's purges). | ignored |

Listened to: `Rhylib.PlayerDowned(ply)` (rhylib_medical: a knock hands over to the downed state). The core also asks `Rhylib.Medical.IsDown`, `Rhylib.MP.IsStunned`, `Rhylib.Admin.Has`, `Rhylib.ThirdPerson.Wanted`, `Rhylib.Stamina.Frac`, `Rhylib.Menus.AddSetting` and others when those addons exist.

### Network messages

| Name (`rhylib.` +) | Direction | Contents | Purpose |
|---|---|---|---|
| `core.cfgallreq` | client → server | empty | Sent at InitPostEntity, once per player: send me the overrides. |
| `core.cfgall` | server → client | parts: UInt8 part, UInt8 count, UInt32 length, compressed JSON `{ {m,k,v} }` | Every override. |
| `core.cfgreq` | client → server | empty | Staff page asks for the catalogue (rate 1/s). |
| `core.cfglist` | server → client | parts as above, rows `{ m,k,d,b,o,s,x,p }` | Catalogue (empty when denied). |
| `core.cfgset` | client → server | String m, String k, Bool has, [String JSON `{v=}`] | Change or reset one setting (rate 4/s). |
| `core.cfgsync` | server → all | String m, String k, Bool has, [String JSON] | One setting changed. |
| `core.profsub` | client → server | Bool | Watch / stop watching the live profiler. |
| `core.profdata` | server → viewers | UInt16 length, compressed JSON | Live profiler sample, every 1 s. |

### Saved data

| Module / key | What's stored |
|---|---|
| `core` / `settings` | Server settings overrides `{ { m, k, v } }`. |
| `perma` / `<map>` | Generic permanent things `{ { c, m, p, a, s, mat, col, rm, cg, fz, bg, b } }`. |

### Examples

React to a soft knockdown ending, from your own addon (server):

```lua
Rhylib.Hook.Add("Rhylib.PlayerUnknocked", "myaddon.up", function(ply)
    if IsValid(ply) and ply:Alive() then ply:ChatPrint("Back on your feet") end
end)
```

A host file that changes settings of several addons:

```lua
-- garrysmod/addons/rhylib_config/lua/rhylib_config/settings.lua
Rhylib.Config.Set("core", "dataFlushDelay", 5)
Rhylib.Config.Set("stamina", "sprintDrain", 10)
Rhylib.Config.Set("thirdperson", "mode", "first")
```

A tracker that sends hits to a squad once per tick:

```lua
local hits = Rhylib.Net.CreateBatch("myaddon.hit", function(it)
    net.WriteUInt(it.victim, 8)            -- entindex of a player (max 255)
    net.WriteUInt(math.min(it.dmg, 255), 8)
end)
Rhylib.Hook.Add("PostEntityTakeDamage", "myaddon.hit", function(ent, dmg, took)
    if took and ent:IsPlayer() then
        hits:SendTo(player.GetHumans(), { victim = ent:EntIndex(), dmg = math.floor(dmg:GetDamage()) })
    end
end)
```

## Notes and gotchas

- Load order: shared, then server, then client files, alphabetical in each group. Settings overrides load in `sv_15_settings.lua`, before other addons, so server code sees them from the start; clients get them only after InitPostEntity.
- A setting registered only in an `sv_` file has no default on clients: `Get` there returns nil and warns.
- Hook bus: returning `false` stops the chain like any other value. Priorities don't order you against plain `hook.Add` handlers of other addons.
- `Net.Receive` on the server drops over-limit messages silently: if a feature "sometimes does nothing" when spammed, check its rate.
- `Rhylib.Data` values go through JSON: no Vectors/Angles/Colors, number keys may come back as strings.
- Perms with CAMI can answer later than the call; always re-check `IsValid` in the callback.
- `rhylib_profile` is per realm (server and each client have their own).
- The load test needs free player slots and makes bots real players: DarkRP jobs, deaths and saved data happen for them (`rhylib_purge_bots` cleans that up).
- Model overrides: things already in the world keep their model until a map change; a weapon's world model change also updates its inventory item.
- Lying ragdolls are real server entities (one per downed/stunned/eliminated player).
- Placing with the toolgun saves nothing; only the Permanent tool does.
