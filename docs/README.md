# Rhylib documentation

This folder explains how Rhylib works, so you can run it, change it, or build on it.

- **Server owners:** start with [Setting up a server](#setting-up-a-server), then open the guide for each addon you install. Every guide has a "For server owners" section with every setting, command and permission.
- **Developers and modders:** read [How the code is organised](#how-the-code-is-organised) and [The core building blocks](#the-core-building-blocks), then [rhylib_core](addons/rhylib_core.md), which is the API every other addon uses. [Making your own addon](#making-your-own-addon) walks through a complete small one.

Every Lua file also explains itself: each starts with a header saying what it does, which realm it runs in and how it fits with the rest. Functions other code may call have a comment with their arguments, return values and usually an example.

## The addons

Each folder in `addons/` is its own Garry's Mod addon (and its own Workshop item). `rhylib_core` is required; the rest are optional, but some need others to work.

| Addon | What it adds | Needs (besides core) |
| --- | --- | --- |
| [rhylib_core](addons/rhylib_core.md) | Loader, settings, hooks, networking, saving, permissions, profiler, lying bodies, Server settings page, permanent placements | nothing |
| [rhylib_admin](addons/rhylib_admin.md) | Staff ranks, commands, bans, cloak/god/noclip, event calls (replaces ULX/SAM/FAdmin) | |
| [rhylib_menus](addons/rhylib_menus.md) | Pause menu, UI kit, settings and controls pages, interaction wheel, spawn window, scoreboard, killfeed | |
| [rhylib_chat](addons/rhylib_chat.md) | Chat box with channels, voice list | |
| [rhylib_hud](addons/rhylib_hud.md) | Helmet visor HUD, ammo, hotbar, damage feedback | |
| [rhylib_thirdperson](addons/rhylib_thirdperson.md) | Over-the-shoulder camera | |
| [rhylib_stamina](addons/rhylib_stamina.md) | Sprint/jump stamina, weight slowdown | |
| [rhylib_weapons](addons/rhylib_weapons.md) | The gun base, bolts, spread, recoil, magazines, armour, shields, grapple | |
| [rhylib_republic](addons/rhylib_republic.md) | Clone guns, grenades, charges, shields, launchers | weapons |
| [rhylib_inventory](addons/rhylib_inventory.md) | Grid inventory, items, storages, hotbar, weight | |
| [rhylib_armoury](addons/rhylib_armoury.md) | Armouries, ammo/gear cabinets, lockers, crates | inventory |
| [rhylib_gear](addons/rhylib_gear.md) | Wearable armour parts (bodygroups), optics, helmet lights, sun visor | inventory |
| [rhylib_jetpack](addons/rhylib_jetpack.md) | Jetpack | (inventory to get one) |
| [rhylib_medical](addons/rhylib_medical.md) | Downing, injuries, medics, med bay, illness | |
| [rhylib_mp](addons/rhylib_mp.md) | Military police: stun, cuffs, search, jail | |
| [rhylib_datapad](addons/rhylib_datapad.md) | Datapad, battalion computers, orders, missions, stats, quick response calls | menus, the `sw_datapad` SWEP |
| [rhylib_roster](addons/rhylib_roster.md) | Characters, clone numbers, ranks, battalions, looks | menus |
| [rhylib_radio](addons/rhylib_radio.md) | Local/radio voice, squads, channels, hails, pings, comms jammers | menus |
| [rhylib_skills](addons/rhylib_skills.md) | Skill trees, command orders, marks, class mode | menus |
| [rhylib_droids](addons/rhylib_droids.md) | Droid and clone NPCs, orders, presets, artillery | weapons |
| [rhylib_eod](addons/rhylib_eod.md) | Bombs, defusal, mines, interference device, Republic mines | inventory, menus |
| [rhylib_training](addons/rhylib_training.md) | Sim health, training eliminations, respawn beacons | weapons |
| [rhylib_spawns](addons/rhylib_spawns.md) | Battalion and event spawn points | |
| [rhylib_toolgun](addons/rhylib_toolgun.md) | Staff placing tool and the Permanent tool | weapons |

The gamemode is DarkRP. Model packs (clone armour, guns, droids, props) are Workshop items; each guide names the ones it uses. Rhylib never ships other authors' files.

## Setting up a server

1. Subscribe to (or copy) `rhylib_core` and the addons you want. Check the "Needs" column above.
2. Subscribe to the model packs the addons list in their guides, and add them to your server's Workshop collection so players download them.
3. Start the server. The console prints `[Rhylib:core] Loaded module ...` once per addon (except rhylib_republic, which has only weapons and entities, no module).
4. Change settings in game: Esc > Staff > **Server settings** (superadmin). Changes are saved and sent to everyone. Model paths can be swapped there too (Model overrides).
5. Or set them in a file of your own: copy [config-example.lua](config-example.lua) to `garrysmod/addons/rhylib_config/lua/rhylib_config/settings.lua` and add lines like
   ```lua
   Rhylib.Config.Set("medical", "simplified", true)
   Rhylib.Config.Set("stamina", "max", 120)
   ```
   Keeping it in its own addon means updates never overwrite it. A value changed on the Server settings page wins over the file; Reset on the page goes back to the file's value.
6. Place armouries, spawn points, computers and so on with the toolgun (`!toolgun`), then make them permanent with the toolgun's **Permanent** entry so they come back after a map change.

When does a change need a restart?
- Editing an existing Lua file: saved files reload by themselves in game (Lua refresh). Some values are read only at load time; a map change picks those up.
- New files (a new entity, weapon or module file), new models or materials: restart the map or the server.

## How the code is organised

```
addons/rhylib_<id>/
  addon.json                       -- Workshop metadata (not every addon has one yet)
  lua/autorun/rhylib_<id>.lua      -- one line: Rhylib.LoadModule("<id>", { name = ..., version = ... })
  lua/rhylib/<id>/sh_00_config.lua -- shared: settings, tables, helpers
  lua/rhylib/<id>/sv_10_*.lua      -- server only
  lua/rhylib/<id>/cl_10_*.lua      -- client only
  lua/weapons/*.lua                -- SWEPs (Garry's Mod loads these itself)
  lua/entities/*.lua               -- scripted entities
  lua/effects/*.lua                -- effects
```

- **Realms.** The file name prefix decides where a module file runs: `sh_` on both, `sv_` on the server, `cl_` on clients (the core sends `sh_` and `cl_` files to clients for you). Weapons and entities are shared files; their server and client parts sit in `if SERVER then ... end` / `if CLIENT then ... end` blocks.
- **Load order.** `rhylib_core` loads first (its autorun file is `_rhylib_core.lua`). Each addon's files then load shared first, then server, then client, alphabetically in each group, so the numbers in the names (`sh_00`, `sv_10`, `sv_20`) set the order. Addons themselves load in the order of their autorun file names (the same as the folder names), so an addon that needs another addon's tables should look them up when they're used (or at `InitPostEntity`), not at file load. Hook `Rhylib.ModuleLoaded(id)` fires as each one finishes.
- **One table per addon.** Each addon keeps everything on one global table, created refresh-safe: `Rhylib.Medical = Rhylib.Medical or {}` and usually a short local (`local Med = Rhylib.Medical`). Other addons call into it only after checking it exists, so any addon can be left out:
  ```lua
  local Med = Rhylib.Medical
  if Med and Med.IsDown and Med.IsDown(ply) then return end
  ```
- **Networking state.** Per-player state other clients need is usually an NW2 variable set when it changes (e.g. `rhylib_down`), read with a helper (`Med.IsDown(ply)`). Events and lists go through named net messages (`Rhylib.Net`). Each guide lists both.

## The core building blocks

All in `rhylib_core`; see [its guide](addons/rhylib_core.md) for every function.

| Need | Use | Instead of |
| --- | --- | --- |
| A setting server owners can change | `Rhylib.Config.Register(module, key, default, desc)`, then `Rhylib.Config.Get(module, key)` when you need it | hard-coded numbers, `CreateConVar` |
| A hook | `Rhylib.Hook.Add(event, "addon.name", fn, priority)` (lower priority runs first; returning anything other than nil stops the rest) | `hook.Add` |
| A net message | `Rhylib.Net.Register(name)` (server), `Rhylib.Net.Start(name)`, server `Rhylib.Net.Receive(name, fn, { rate, burst })` (rate limited per player) | `util.AddNetworkString` + `net.Receive` |
| Many small events per tick | `Rhylib.Net.CreateBatch(name, writeItem)` | one message per event |
| Saving | `Rhylib.Data.Set(module, key, value)` / `Get` / `Delete` (SQLite, batched) | `file.Write`, raw `sql.Query` |
| Permissions | `Rhylib.Perms.Register(name, "admin", desc)`, `Rhylib.Perms.Check(ply, name, function(ok) ... end)` | `ply:IsAdmin()` |
| Placed things that survive a map change | `Rhylib.Perma.Register(classes, saveFn)` (or nothing: the generic saver keeps any entity staff make permanent) | your own save command |
| A model hosts can swap | a `ENT.Model` / `SWEP.WorldModel` field, a `.mdl` config default, or hook `Rhylib.ModelCatalogue` | a path hard-coded in a function |

Code rules the whole suite follows (they keep 80 players plus droids running smoothly):

1. Refresh-safe code: `X = X or {}`, named hook ids, `timer.Create` with a name.
2. Nothing networked every tick; send changes, only to players who need them, with exact bit sizes. No `net.WriteTable` for frequent messages.
3. Timers (0.1 to 0.5 s) instead of per-frame checks wherever that's precise enough.
4. The server checks every request; the client only asks.
5. Standard Lua (`~=`, `and`, `--`), not Garry's Mod's C-style extras.
6. `surface.DrawPoly` vertices go clockwise on screen, and call `draw.NoTexture()` before untextured polygons.
7. On a client, `util.IsValidModel` is false for models nobody has loaded yet: also accept `file.Exists(path, "GAME")`.

## Making your own addon

A small complete addon that uses the core: a "ration bar" item you eat from the inventory's right-click menu, with a setting, a rate-limited net message, a permission-checked chat command and a hook other addons can listen to.

```
addons/myserver_rations/
  lua/autorun/myserver_rations.lua
  lua/rhylib/rations/sh_00_config.lua
  lua/rhylib/rations/sv_10_rations.lua
  lua/rhylib/rations/cl_10_rations.lua
```

`lua/autorun/myserver_rations.lua`:
```lua
-- Loads lua/rhylib/rations/ through the Rhylib core (shared files first,
-- then server, then client; the core sends sh_ and cl_ files to clients).
if not Rhylib then return end
Rhylib.LoadModule("rations", { name = "Rations", version = "1.0.0" })
```

`lua/rhylib/rations/sh_00_config.lua` (shared):
```lua
Rhylib.Rations = Rhylib.Rations or {}
local R = Rhylib.Rations
R.ITEM = "ration_bar"

-- Shows on Staff > Server settings under "rations".
Rhylib.Config.Register("rations", "heal", 15, "Health a ration bar gives")

-- The item. rhylib_inventory may load after us, so register now and again
-- when it has loaded.
local function register()
    local Items = Rhylib.Items
    if not (Items and Items.Register) or Items.Get(R.ITEM) then return end
    Items.Register(R.ITEM, {
        name = "Ration bar", w = 1, h = 1, weight = 0.2, stack = 5,
        category = "misc", desc = "Right-click: eat it.",
        model = "models/props_junk/garbage_metalcan001a.mdl",
    })
end
register()
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "rations.items", function(id)
    if id == "inventory" then register() end
end)
```

`lua/rhylib/rations/sv_10_rations.lua` (server):
```lua
local R = Rhylib.Rations

-- R.Eat(ply): heals and tells other addons (hook Rhylib.RationEaten(ply)).
function R.Eat(ply)
    local heal = Rhylib.Config.Get("rations", "heal")
    ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + heal))
    ply:EmitSound("npc/barnacle/barnacle_crunch2.wav", 60)
    hook.Run("Rhylib.RationEaten", ply)
end

-- rations.eat (client -> server): item uid. The server checks the item is
-- really theirs before using it. At most 2 a second per player.
Rhylib.Net.Receive("rations.eat", function(ply)
    local uid = net.ReadUInt(Rhylib.Items.UID_BITS)
    local Inv = Rhylib.Inventory
    local inst = Inv.Get(ply).byUid[uid]
    if not (inst and inst.id == R.ITEM and ply:Alive()) then return end
    Inv.Remove(ply, uid, 1)
    R.Eat(ply)
end, { rate = 2, burst = 2 })

-- !rations <name part> (admins): hand out five.
Rhylib.Perms.Register("rations.give", "admin", "Give ration bars with !rations")
Rhylib.Hook.Add("PlayerSay", "rations.cmd", function(ply, text)
    local name = string.match(text, "^!rations%s+(.+)$")
    if not name then return end
    Rhylib.Perms.Check(ply, "rations.give", function(ok)
        if not (ok and IsValid(ply)) then return end
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(name), 1, true) then
                Rhylib.Inventory.AddOrDrop(p, R.ITEM, 5)
            end
        end
    end)
    return ""   -- (hide the command from chat)
end)
```

`lua/rhylib/rations/cl_10_rations.lua` (client):
```lua
local R = Rhylib.Rations

-- The inventory's right-click menu on one of your items.
Rhylib.Hook.Add("Rhylib.ItemMenu", "rations.menu", function(inst, menu)
    if inst.id ~= R.ITEM then return end
    menu:AddOption("Eat", function()
        Rhylib.Net.Start("rations.eat")
        net.WriteUInt(inst.uid, Rhylib.Items.UID_BITS)
        net.SendToServer()
    end)
end)
```

Another addon can now react without knowing anything else about yours:
```lua
Rhylib.Hook.Add("Rhylib.RationEaten", "myhud.rations", function(ply)
    print(ply:Nick() .. " had a snack")
end)
```

Each guide's "For developers" section has examples like this for its own addon: making a gun on `rhylib_base`, a new droid kind, a skill node, a pause-menu page, an admin command, a bomb module, and more.

## Testing

- `rhylib_status` (server) lists the loaded modules.
- Esc > Staff > **Profiler** shows live server cost per addon, hook and net message; `rhylib_profile 1` and `rhylib_profile_report` print it.
- `rhylib_loadtest <bots> [fire 0/1] [droids]` fills the server with bots (start it with enough `maxplayers`); `rhylib_loadtest_stop` removes them.
- `tools/tests/shield_test.lua` checks the riot shield maths offline: `lua5.1 tools/tests/shield_test.lua addons` from the repo root.
- Test networking on a dedicated server; a listen server's host is both server and client and hides networking mistakes.

## Other files here

- [config-example.lua](config-example.lua): a host config file to copy.
- `gear_scan_2026-10-04.txt`: bodygroup names of the clone armour models (used by rhylib_gear).
- `../CLAUDE.md` (repo root): the full development log: every design decision, number and change, with the owner's reasons. Long, but it's where to look for "why is it like this?".
