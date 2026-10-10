# rhylib_admin: Staff ranks, commands and bans

Rhylib's own admin mod. It replaces ULX, SAM and FAdmin. Server owners get staff ranks with permission lists, chat
and console commands (`!kick`, `!bring`, `!ban` ...), bans and warnings that are saved, a staff log, staff powers
(noclip, god mode, invisible, spectate), event tools (size, speed, sounds, announcements), a map picker and "calls"
(a "Call to briefing" banner, with an optional countdown, on everyone's screen). Other addons see the ranks through
the usual `ply:IsAdmin()` / `ply:IsSuperAdmin()`, the engine usergroup and CAMI, so most admin-aware addons just work.
Players mostly meet it as the call banner, announcements and staff notices in chat.

## Requirements

- **Required:** `rhylib_core`.
- **Recommended:** `rhylib_menus` (the Staff > Commands page, the player and argument pickers, and the map picker;
  without it every command has to be typed in full). Several commands only work when another Rhylib addon is
  installed and say so otherwise: `rhylib_roster` (rrank, battalion, unbattalion, train, qual, charreset),
  `rhylib_mp` (jail, unjail, free, hidecells), `rhylib_medical` (revive of downed players, infect, cure),
  `rhylib_chat` (announcement banner, mute rules for the admin channel and PMs). DarkRP is needed for setjob,
  money, setmoney and battalion.
- No Workshop content. The call sound is an HL2 sound.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_admin.lua` | shared | Loader: `Rhylib.LoadModule("admin")`. |
| `lua/rhylib/admin/sh_00_config.lua` | shared | Config keys, ranks and permission sets, `Admin.Has / CanTarget / Rank / Level`, IsAdmin / IsSuperAdmin, the noclip key, CAMI provider, `Admin.ScaleHull`. |
| `lua/rhylib/admin/sh_10_commands.lua` | shared | The command list `Admin.COMMANDS`, staff menu layout `Admin.SECTIONS`, `ParseDuration`, `FormatMinutes`, `Split`. |
| `lua/rhylib/admin/sv_10_admin.lua` | server | Rank storage, bans, warnings, the log, finding targets, `Admin.Exec` (runs every command), chat / console / net entry points, map list and staff lists. |
| `lua/rhylib/admin/sv_20_handlers.lua` | server | What each command does (`Admin.handlers`), plus the powers (cloak, notarget, god, buddha, spawn rights, gag, spectate, cleanup). |
| `lua/rhylib/admin/sv_30_calls.lua` | server | `!call` / `!endcall`, `Admin.StartCall / EndCall` (state in Global2 vars). |
| `lua/rhylib/admin/cl_10_admin.lua` | client | Chat notices, announcements, map countdown, `Admin.Run`, pickers (`PickPlayer`, `AskArgs`), `RequestList`, cloak weapon hiding. |
| `lua/rhylib/admin/cl_20_maps.lua` | client | The map picker window (`Admin.MapPicker`). |
| `lua/rhylib/admin/cl_30_calls.lua` | client | Call banner, countdown plate, `Admin.CurrentCall`, console `rhylib_call_status`. |

## For server owners

### Settings

Config module `"admin"`. **This module is protected:** it does not show on the in-game Staff > Server settings page
and can't be changed there (a wrong rank list could lock every staff member out or promote someone). Set it in a host
config file instead (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`). These files load on
both server and client, which matters because the client needs the same ranks.

| Key | Default | What it does |
|---|---|---|
| `ranks` | 7 ranks (below) | Staff ranks: `{ id, name, level, color, inherits = { rank ids }, perms = { permission names } }`. |
| `owners` | `{}` | SteamID64s that are always the top rank. Write them as strings. |
| `adminLevel` | `70` | Level from which `ply:IsAdmin()` is true and "admin" privileges are granted. |
| `superLevel` | `90` | Level from which `ply:IsSuperAdmin()` is true. |
| `banMaxMinutes` | `10080` | Longest ban without the `permaban` permission (minutes; 10080 = 7 days). |
| `echo` | `true` | Tell everyone about admin actions; staff always see them. |
| `calls` | 4 presets (below) | `!call` presets: `{ id, name, sub, minutes }` (minutes = default timer, 0 = none). |
| `callSound` | `"ambient/alarms/warningbell1.wav"` | Sound when a call goes out. |
| `callShowFor` | `900` | Seconds an untimed call is still shown to players who join. |
| `prefixes` | `{ "!", "/" }` | Chat prefixes for admin commands. |

Default ranks:

| id | Name | Level | Inherits | Own permissions |
|---|---|---|---|---|
| `user` | User | 0 | | |
| `trialmod` | Trial Moderator | 30 | | goto, bring, return, freeze, unfreeze, mute, unmute, gag, ungag, kick, warn, respawn, logs, spectate, noclip.self, info, tell, free, rhylib.chat.admin |
| `gamemaster` | Gamemaster | 40 | | goto, bring, return, teleport, freeze, unfreeze, respawn, slay, noclip, noclip.self, god, cloak, notarget, hp, armor, give, spawn, map, cleanup, announce, setjob, spectate, info, tell, revive, heal, buddha, scale, speed, jump, model, playsound, stopsound, slap, ignite, free, infect, cure, freezeprops, cleardecals, call, rhylib.chat.event, rhylib.weapons.infammo, rhylib.eod.gm |
| `moderator` | Moderator | 50 | trialmod | ban, slay, teleport, noclip, god, cloak, notarget, hp, armor, bans, setjob, jail, unjail, revive, heal, stopsound, freezeprops, cleardecals, ignite, hidecells |
| `admin` | Admin | 70 | moderator, gamemaster | permaban, banid, unban, rank, roster, charreset, unwarn, money |
| `superadmin` | Superadmin | 90 | | `*` (everything) |
| `owner` | Owner | 100 | | `*` (everything) |

Note that the gamemaster does **not** inherit the trial moderator: gamemasters run events, they can't kick, mute or warn.

Default call presets: `briefing` "Call to briefing", `debrief` "Call to debrief", `prep` "Mission prep" (10 minute
timer), `formup` "Form up".

How ranks and permissions work:

- A rank has its own `perms` plus everything its `inherits` ranks have (followed all the way down). `"*"` means everything.
- A permission name is a command's permission (usually its id, see the table below), a power (`spawn`,
  `noclip.self`, `logs`, `bans`, `banid`, `permaban`) or a Rhylib / CAMI privilege name from another addon
  (`rhylib.chat.event`, `rhylib.toolgun`, `rhylib.settings` ...).
- A privilege the rank doesn't list falls back to its MinAccess: "user" = everyone, "admin" = level >= `adminLevel`,
  "superadmin" = level >= `superLevel`. Rhylib's own permissions mostly default to "admin" or "superadmin", so a
  moderator (50) gets only what their rank lists.
- `"<perm>.self"` lets a rank use a targeted command on itself only (the trial moderator's `noclip.self`).
- Staff can only act on players with a **lower** level (and on themselves), and only give ranks below their own.
  For offline SteamIDs the stored rank counts.
- The server console counts as the top rank and can do everything.

Example host file (`lua/rhylib_config/admin.lua` in your own addon):

```lua
-- Owners: SteamID64s as strings.
Rhylib.Config.Set("admin", "owners", { "76561198000000001" })

-- Bans up to 30 days without permaban; don't tell players about kicks/bans.
Rhylib.Config.Set("admin", "banMaxMinutes", 43200)
Rhylib.Config.Set("admin", "echo", false)

-- Your own call presets (replaces the whole list).
Rhylib.Config.Set("admin", "calls", {
    { id = "briefing", name = "Call to briefing", sub = "Hangar bay, now", minutes = 0 },
    { id = "deploy", name = "Deployment", sub = "Gunships leave in", minutes = 5 },
})
```

To change ranks, set the **whole** `ranks` table (copy the default from `sh_00_config.lua` and edit it). For example,
to let moderators use `!map` add `"map"` to the moderator's `perms`. Keep a `user` rank.

### Commands and permissions

Ways to run a command:

- Chat: `!kick bob spam` or `/kick bob spam` (prefixes from config `prefixes`). DarkRP's own `/` commands win over ours
  when the name is the same (`/give` stays DarkRP's money command; use `!give` for weapons).
- Console: `rhylib_admin kick bob spam` (from the server console you are the top rank). `rhylib_admin` alone lists
  every command id.
- The Staff > Commands page in the pause menu (needs `rhylib_menus`): pick a player, click a button.

Targets: a name or part of it (must match one player), a SteamID or SteamID64, `^` = you, `@` = the player you're
looking at (a lying body counts), `*` = everyone you outrank (only commands marked "mass" below; not you).
Use quotes for names with spaces: `!bring "Big Bob"`.

If you leave out the player, or an argument a command needs, a picker opens (players, then each argument as a menu
or a text box). Commands that target "you when left out" also work with just the arguments: `!hp 50` sets your own
health.

Lengths for `!ban`: `30m`, `2h`, `1d`, `1w`, `1y`, a bare number = minutes, `perm` / `0` = forever. Lengths round up
and are at least 1 minute.

Argument notation: `<player>` required online player; `[player]` online player, you when left out; `(player)` online
player, nobody when left out; `<id>` online player or any SteamID / SteamID64 (offline too). "Mass" = accepts `*`.

Ranks column: the default ranks that have it (TM trialmod, GM gamemaster, Mod moderator, Adm admin; superadmin and
owner always have everything).

| Command (aliases) | Arguments | Permission (ranks) | What it does |
|---|---|---|---|
| `kick` | `<player> [reason]` | `kick` (TM, Mod, Adm) | Disconnects the player with the reason. |
| `ban` | `<id> <length> [reason]` | `ban` (Mod, Adm) | Bans by name or SteamID. Offline players need `banid`; perm or longer than `banMaxMinutes` needs `permaban`. Family-shared accounts of the banned player are kicked too. |
| `unban` | `<id>` | `unban` (Adm) | Lifts a ban. Also a button on the Bans list. |
| `warn` | `<player> <reason>` | `warn` (TM, Mod, Adm) | Saved warning; the player sees it in chat. Keeps the last 50. |
| `warnings` | `<id>` | `warn` (TM, Mod, Adm) | Shows their last 10 warnings to you. |
| `unwarn` (clearwarns) | `<id>` | `unwarn` (Adm) | Deletes all their warnings. |
| `mute` | `<player>`, mass | `mute` (TM, Mod, Adm) | No text chat until unmuted or they leave. They can still use the admin channel, PM staff and run commands. |
| `unmute` | `<player>`, mass | `unmute` (TM, Mod, Adm) | Ends a mute. |
| `gag` | `<player>`, mass | `gag` (TM, Mod, Adm) | Nobody hears their voice until ungagged or they leave. |
| `ungag` | `<player>`, mass | `ungag` (TM, Mod, Adm) | Ends a gag. |
| `freeze` | `<player>`, mass | `freeze` (TM, GM, Mod, Adm) | Freezes them in place (kept through respawns). |
| `unfreeze` | `<player>`, mass | `unfreeze` (TM, GM, Mod, Adm) | Unfreezes. |
| `slay` | `<player>` | `slay` (GM, Mod, Adm) | Kills them. |
| `respawn` | `[player]`, mass | `respawn` (TM, GM, Mod, Adm) | Respawns them. |
| `setjob` | `[player] <job>` | `setjob` (GM, Mod, Adm) | DarkRP job by command or name (part of the name works), skipping the job's checks. |
| `jail` | `<player> <minutes> [reason]` | `jail` (Mod, Adm) | Into a jail cell (rhylib_mp); items go to evidence. Capped by rhylib_mp's `maxSentence`. |
| `unjail` | `<player>` | `unjail` (Mod, Adm) | Releases and processes them at once (no waiting). |
| `free` (uncuff, unstun) | `[player]`, mass | `free` (TM, GM, Mod, Adm) | Uncuffs and ends a stun (rhylib_mp). |
| `slap` | `<player>`, mass | `slap` (GM, Adm) | Throws them in a random direction, -5 health (never below 5). |
| `ignite` | `<player>`, mass | `ignite` (GM, Mod, Adm) | Sets them on fire for 10 seconds. |
| `extinguish` | `[player]`, mass | `ignite` (GM, Mod, Adm) | Puts the fire out. |
| `tell` (psay) | `<player> <message>` | `tell` (TM, GM, Mod, Adm) | Private staff message to them (logged). |
| `info` (pinfo) | `<id>` | `info` (TM, GM, Mod, Adm) | Rank, job, health, time online, jail, character, warnings and ban, to you. |
| `who` | | `logs` (TM, Mod, Adm) | Lists online staff and their ranks, to you. |
| `spectate` (spec) | `<player>` | `spectate` (TM, GM, Mod, Adm) | Watch them (you're hidden and NPCs ignore you); run again to stop. Ends when you respawn or they die or leave. |
| `unspectate` | | `spectate` (TM, GM, Mod, Adm) | Stop watching; you go back where you were. |
| `goto` | `<player>` | `goto` (TM, GM, Mod, Adm) | Teleports you behind them (a free spot nearby). |
| `bring` | `<player>`, mass | `bring` (TM, GM, Mod, Adm) | Teleports them in front of you. |
| `return` | `[player]`, mass | `return` (TM, GM, Mod, Adm) | Back to where they were before the last goto / bring / teleport. |
| `teleport` (tp) | `[player]` | `teleport` (GM, Mod, Adm) | To where you're looking. |
| `noclip` | `[player]` | `noclip` (GM, Mod, Adm); `noclip.self` (TM) on yourself | Toggles noclip. Staff with either permission can also use the normal noclip key. |
| `god` | `[player]`, mass | `god` (GM, Mod, Adm) | Toggles god mode (also no stuns or explosion knockdowns). Kept through respawns. |
| `cloak` (invis) | `[player]`, mass | `cloak` (GM, Mod, Adm) | Toggles invisible (model, weapon, shadow, name hidden; NPCs ignore them). Kept through respawns. |
| `notarget` | `[player]`, mass | `notarget` (GM, Mod, Adm) | Toggles: NPCs and droids ignore them. Kept through respawns. |
| `hp` (health) | `[player] <amount>`, mass | `hp` (GM, Mod, Adm) | Sets health (1-100000; raises max health if needed). |
| `armor` (armour) | `[player] <amount>`, mass | `armor` (GM, Mod, Adm) | Sets armour (0-100000; raises max armour if needed). |
| `give` | `[player] <class>`, mass | `give` (GM, Adm) | Gives a weapon by class. |
| `revive` | `[player]`, mass | `revive` (GM, Mod, Adm) | Gets a downed player up at full health; a dead one respawns where they fell. |
| `heal` | `[player]`, mass | `heal` (GM, Mod, Adm) | Full health and spawn armour, injuries and illness gone, fire out, revived if down. |
| `infect` | `[player] <kind> [strength]`, mass | `infect` (GM, Adm) | Gives an illness (rhylib_medical): `viral`, `bacterial` or `poison`, strength 1-100 (40 when left out). |
| `cure` | `[player]`, mass | `cure` (GM, Adm) | Takes an illness away. |
| `buddha` | `[player]` | `buddha` (GM, Adm) | Toggles: takes damage but never drops below 1 health. |
| `money` (addmoney) | `[player] <amount>` | `money` (Adm) | Gives DarkRP money (negative takes, never below 0). |
| `setmoney` | `[player] <amount>` | `money` (Adm) | Sets DarkRP money. |
| `scale` (size) | `[player] <size>`, mass | `scale` (GM, Adm) | Player size 0.2-5 (1 = normal), until respawn. |
| `speed` | `[player] <multiplier>`, mass | `speed` (GM, Adm) | Walk / run speed × 0.1-10, until respawn. |
| `jump` | `[player] <multiplier>`, mass | `jump` (GM, Adm) | Jump power × 0-10, until respawn. |
| `model` (setmodel) | `[player] <path or reset>`, mass | `model` (GM, Adm) | Player model `models/....mdl` (must exist on the server), until respawn. `reset` puts the job model back. |
| `playsound` (sound) | `<path>` | `playsound` (GM, Adm) | Everyone hears a sound (`.wav`, `.mp3`, `.ogg`, must exist on the server). |
| `stopsound` | | `stopsound` (GM, Mod, Adm) | Stops every sound for everyone. |
| `call` | `<preset or custom> [minutes] [text]` | `call` (GM, Adm) | Banner for everyone (and anyone joining). Timed calls show a countdown. `!call prep`, `!call briefing 0 Hangar bay`, `!call custom 10 Form up at the hangar`. Minutes left out = the preset's own timer. |
| `endcall` (callend) | | `call` (GM, Adm) | Takes the banner and countdown away. |
| `rank` | `<id> <rank>` | `rank` (Adm) | Sets a staff rank (rank id). Only ranks below your own. `user` removes the rank. |
| `rrank` (rosterrank) | `<id> <rank>` | `roster` (Adm) | Roster rank (number, prefix or name) of a battalion member (rhylib_roster). |
| `battalion` | `<id> <battalion>` | `roster` (Adm) | Puts them in a battalion as PVT (passes basic training if needed). |
| `unbattalion` | `<id>` | `roster` (Adm) | Removes them from their battalion. |
| `train` | `<id>` | `roster` (Adm) | Passes basic training. |
| `qual` | `<id> <qualification> <on/off>` | `roster` (Adm) | Gives or takes a qualification. |
| `charreset` | `<player>` | `charreset` (Adm) | They pick a new number and nickname. |
| `map` | `<map>` | `map` (GM, Adm) | Changes map after a 10 s countdown. A bare `!map` opens the map picker; a part of the name works if only one map matches. |
| `cancelmap` | | `map` (GM, Adm) | Stops the countdown. |
| `restartmap` (maprestart) | | `map` (GM, Adm) | Reloads this map after a 10 s countdown. |
| `cleanup` | `(player)` | `cleanup` (GM, Adm) | No target: removes everything spawned during play that isn't permanent (see below). With a target (`^` = yours): only that player's spawned things. |
| `freezeprops` (nolag) | | `freezeprops` (GM, Mod, Adm) | Freezes every moving `prop_physics` (not Rhylib fixtures). |
| `cleardecals` | | `cleardecals` (GM, Mod, Adm) | Blood, scorch marks and client death ragdolls, for everyone. |
| `hidecells` | | `hidecells` (Mod, Adm) | Hides (or shows again) the jail cell rings for everyone; kept across maps. |
| `announce` (a) | `<text>` | `announce` (GM, Adm) | Event banner for everyone (rhylib_chat) plus a chat line. Logged. |

Other permissions:

| Permission | Ranks | What it allows |
|---|---|---|
| `spawn` | GM, Adm | Spawn menu rights (props, entities, NPCs, weapons, vehicles, ragdolls, effects) whatever DarkRP or sandbox say, and tools on the world. Tools on entities still follow prop protection. |
| `noclip.self` | TM, GM, Mod, Adm | The noclip key and `!noclip` on yourself. |
| `logs` | TM, Mod, Adm | The Log tab in Staff > Commands, and `!who`. |
| `bans` | Mod, Adm | The Bans tab (also shown with `ban`). |
| `banid` | Adm | Banning players who aren't online. |
| `permaban` | Adm | Permanent bans, and bans longer than `banMaxMinutes`. |
| `rhylib.chat.admin` | TM, Mod, Adm | Reading and writing the admin chat channel (rhylib_chat). |

What `!cleanup` (no target) removes: things players spawned, toolgun-spawned things, NPCs, NextBots, vehicles, loose
weapons, any scripted entity, `prop_`, `spawned_`, `sent_`, `gmod_wire_`, `edit_`, `rhylib_`, `npc_` classes and the
usual sandbox tools (buttons, lamps, thrusters ...). It never removes map entities, players, held weapons, hands and
viewmodels, grapple ropes, lying bodies, things attached to a player or to something permanent, or permanent things
(Rhylib's toolgun "Permanent" tool, PermaProps, sandbox persistence). Rhylib fixtures (armouries, terminals, jail
cells ...) **are** removed unless they were made permanent. Other addons' self-spawned entities (vendor NPCs from a
config) go too.

### Placing things / saving

Nothing to place. What is saved (Data module `"admin"`): staff ranks, bans, warnings, the staff log (last 300 lines)
and the hidden-cells switch. Mutes, gags, freezes and `!return` spots last only while the player is online.

## For players (short)

- Staff notices appear in chat as `[Admin] ...`; red ones are errors meant for you.
- A call (briefing, prep ...) shows a banner in the top middle of the screen with a sound. A timed call keeps a
  countdown plate in the top-left corner; it turns amber in the last minute and says "Time's up" at 0.
- A map change shows "Map change: name in N" near the top of the screen.

## For developers

### Public functions

All on `Rhylib.Admin` (local name `Admin`). Shared unless noted.

| Function | Returns | Realm | What it does |
|---|---|---|---|
| `Admin.Cfg(key)` | value | shared | A setting of config module "admin". |
| `Admin.Ranks()` | list | shared | Every rank table, lowest level first. |
| `Admin.RankById(id)` | rank or nil | shared | One rank table. |
| `Admin.TopRank()` | rank | shared | `owner`, or the highest rank. |
| `Admin.Rank(ply)` | rank | shared | The player's rank (nil = console = top rank). |
| `Admin.Level(ply)` | number | shared | Rank level (console = `math.huge`). |
| `Admin.Has(ply, perm, minAccess)` | bool | shared | Permission check (see "How ranks and permissions work"). |
| `Admin.CanTarget(ply, target)` | bool | shared | Themselves, or target ranked lower. |
| `Admin.RankColor(id)` | Color | shared | Rank colour (grey if unknown). |
| `Admin.ScaleHull(ply)` | | shared | Applies the `!scale` size to the player's hull. |
| `Admin.ParseDuration(text)` | minutes or nil | shared | `"2h"` -> 120; 0 = forever. |
| `Admin.FormatMinutes(m)` | string | shared | 120 -> `"2 hours"`; 0 -> `"permanently"`. |
| `Admin.Split(line)` | list | shared | Splits a command line; quotes keep words together. |
| `Admin.COMMANDS`, `Admin.byId`, `Admin.byAlias`, `Admin.SECTIONS` | tables | shared | The command list and lookups (see "Adding your own admin command"). |
| `Admin.Exec(caller, id, words)` | | server | Runs a command as if typed (caller nil = console). |
| `Admin.Tell(ply, text, bad)` | | server | `[Admin]` chat line to one player (console: printed). |
| `Admin.Echo(text)` | | server | Action notice to everyone (or staff only when echo is off). |
| `Admin.Log(text)` | | server | Adds a staff log line (and ServerLog). |
| `Admin.SetRank(sid64, rankId, byName)` | bool | server | Saves and applies a staff rank (no checks). |
| `Admin.StoredRank(sid64)` | id or nil | server | The saved rank id. |
| `Admin.ApplyRank(ply)` | | server | Sets the usergroup from storage / owners / listen host. |
| `Admin.OnlineBySid(sid64)` | player or nil | server | Online human by SteamID64. |
| `Admin.Ban(sid64, minutes, reason, caller, name)` | ban table | server | Saves a ban and kicks (no checks). |
| `Admin.Unban(sid64)` | bool | server | Removes a ban; true if there was one. |
| `Admin.GetBan(sid64)` | ban or nil | server | Current ban (expired ones are removed). |
| `Admin.Warn(sid64, reason, byName)` | count | server | Adds a warning. |
| `Admin.Warnings(sid64)` / `Admin.ClearWarnings(sid64)` | list / | server | Read / delete warnings. |
| `Admin.FindPlayer(caller, text)` | player or nil, err | server | Name part, SteamID(64), `^`, `@`. |
| `Admin.FindId(caller, text)` | sid64, player or nil, err | server | Same, plus offline SteamIDs. |
| `Admin.MapList()` | list | server | Maps on the server (cached 60 s). |
| `Admin.SetCloak(ply, on)` / `Admin.SetNoTarget(ply, on)` | | server | The cloak and notarget powers. |
| `Admin.StopSpectate(ply, move)` | | server | Ends spectating. |
| `Admin.StartCall(title, sub, seconds, byName)` / `Admin.EndCall()` | / bool | server | Puts up / takes down a call. |
| `Admin.handlers[id]` | | server | Command handlers (see below). |
| `Admin.Run(id, words)` | | client | Asks the server to run a command. |
| `Admin.TargetWord(ply)` | string | client | How to name a player in `Admin.Run` (SteamID64). |
| `Admin.PickPlayer(cmd, done)` / `Admin.AskArgs(cmd, done, from)` | | client | Pickers (need rhylib_menus). |
| `Admin.RequestList(which, arg, cb)` | | client | 0 maps, 1 bans, 2 log, 3 warnings of a SteamID64. |
| `Admin.MapPicker(done)` | panel or nil | client | Map window (needs rhylib_menus). |
| `Admin.CurrentCall()` | call or nil | client | `{ title, sub, by, ends, left, total }`. |
| `Admin.TrackAsk(panel)` | panel | client | Frees the mouse while the panel is open. |

Examples:

```lua
-- Any realm: permission check with a fallback for players the rank list doesn't cover.
if Rhylib.Admin and Rhylib.Admin.Has(ply, "myaddon.edit", "admin") then ... end

-- Server: run a command from code as the console.
Rhylib.Admin.Exec(nil, "announce", { "Server restart in 5 minutes" })

-- Server: a timed call from your own event script.
Rhylib.Admin.StartCall("Mission prep", "Grab your gear at the armoury", 10 * 60, "Event")

-- Client: a button that brings the player you picked.
Rhylib.Admin.Run("bring", { Rhylib.Admin.TargetWord(ply) })
```

For permission checks in your own addon, prefer `Rhylib.Perms.Register` + `Rhylib.Perms.Check` (rhylib_core): with
rhylib_admin installed they use `Admin.Has`, and they still work with ULX/SAM or no admin mod.

### Hooks

Fired by this addon: no `Rhylib.*` hooks of its own. It calls `CAMI.SignalUserGroupChanged` when it sets a rank,
and `hook.Run("PlayerSetModel", ply)` for `!model reset`.

Listened to:

- `CAMI.PlayerHasAccess`: answers every CAMI check (`Admin.Has`, plus `CanTarget` when a target is given).
- `CAMI.PlayerUsergroupChanged`: another mod changing a usergroup is put back (ranks come only from this addon).
- `PlayerInitialSpawn` (rank, ban check), `PlayerAuthed` and `CheckPassword` (bans, family sharing too).
- `PlayerSay` at -50: chat commands and mute.
- `PlayerNoClip` (shared, -50): staff noclip key.
- `PlayerSpawnProp / SENT / NPC / SWEP / Vehicle / Ragdoll / Effect / Object`, `PlayerGiveSWEP` (-50), `CanTool`
  (-40): `spawn` rights. Return true only; they never block.
- `PlayerSpawned*`: remembers who spawned what (`ent.rhylibSpawner`) for `!cleanup <player>`.
- `PlayerCanHearPlayersVoice` (-50): gag.
- `Rhylib.CanChat` (rhylib_chat): mute; the admin channel and PMs to staff stay open.
- `Rhylib.CanStun`, `Rhylib.CanKnockDown`: god mode players can't be stunned or knocked down.
- `EntityTakeDamage` at 140: buddha (after armour, before rhylib_medical at 150).
- `PlayerSpawn`: keeps cloak, god, notarget and freeze; resets size, speed, jump; ends spectating.
- `PlayerSwitchWeapon`: hides a cloaked player's new weapon. `PostPlayerDeath` / `PlayerDisconnected`: end spectating
  of that player; clear mute / gag / return spot.
- `InitPostEntity`: loads the hidden-cells switch.
- Client `Think`: keeps the local player's hull at their size. Client `HUDPaint` / `PostRenderVGUI`: countdown, call plate, call banner.

### Network messages

All names get the `rhylib.` prefix from `Rhylib.Net`.

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `admin.msg` | server -> player(s) | Bool bad, String text | `[Admin]` chat line (replies, notices). |
| `admin.announce` | server -> all | String by, String text | Announcement banner. |
| `admin.countdown` | server -> all | String map (`""` = cancelled), UInt 6 seconds | Map change countdown. |
| `admin.ask` | server -> caller | String id, UInt 4 from (0 = player), UInt 4 n, n × String | Open pickers for what's missing. |
| `admin.client` | server -> all | UInt 2 kind (0 play, 1 stop sounds, 2 clear decals), String sound | Sound / decal commands. |
| `admin.list` | server -> asker | UInt 2 which, UInt 8 rows, per row UInt 3 n + n × String | Lists for the staff menu. |
| `admin.run` | client -> server | String id, UInt 4 n, n × String (each cut to 200 characters) | Run a command (rate 4/s, burst 8). |
| `admin.listget` | client -> server | UInt 2 which, String arg | Ask for a list (rate 2/s, burst 4; no reply without permission). |

Calls use no net messages: Global2 vars `rhylib_call_n` (Int, bumped on every new call or end), `rhylib_call_title`,
`rhylib_call_sub`, `rhylib_call_by` (Strings), `rhylib_call_at`, `rhylib_call_end` (Floats, CurTime; end 0 = untimed).
Other networked state: NW2Bool `rhylib_cloak`, NW2Float `rhylib_scale`, Global2Bool `rhylib_hideCells`, and the engine
usergroup.

### Saved data

`Rhylib.Data` module `"admin"` (`<sid>` = `"s"` + SteamID64, so keys are never bare numbers):

| Key | Value |
|---|---|
| `r<sid>` (e.g. `rs7656...`) | Staff rank id. No row = user. |
| `b<sid>` | Ban `{ reason, by, byName, at, untilT (os.time, 0 = forever), name }`. |
| `bans` | Index of bans `{ ["s"..sid] = name }`. |
| `w<sid>` | Warnings `{ { reason, byName, at } }`, at most 50. |
| `log` | Staff log `{ { t, text } }`, newest first, at most 300. |
| `hideCells` | 1 or 0. |

rhylib_core's data purges never touch module `admin`.

### Adding your own admin command

A command is a row in `Admin.COMMANDS` (shared, so the menus and pickers know it) and a handler in
`Admin.handlers` (server). The lookups `byId` / `byAlias` are built when rhylib_admin loads, so a command added later
has to be put into them by hand. Do it once every addon has loaded (Initialize), and on both realms.

Command row fields: `id` (chat word), `name` (button label), `cat` (group name, display only), `perm` (defaults to
the id), `target` (`"player"`, `"self"`, `"opt"`, `"id"` or nil), `args` (`{ key, label, kind, need = true, opt = true }`
in order), `mass = true` (allows `*`), `desc` (tooltip), `aliases`. Argument kinds: `text` (rest of the line),
`word`, `number`, `minutes`, `scale`, `mult`, `duration` (all checked on the server); anything else arrives as the
typed word and your handler checks it (`job`, `class`, `model`, `sound`, `onoff` ... also pick the client's choice menu).

Handler: `function(caller, target, args, ctx)`. `caller` is nil for the console; `target` is the player (already
checked: you may act on them); `args[key]` holds the parsed arguments; `ctx.sid` is the target's SteamID64, `ctx.mass`
is true when run for `*`. Return the text to echo and log, or `nil, "error for the caller"`, or nothing to stay quiet.

Example: `!strip <player>` takes all weapons. Put this in your own addon as a shared file, e.g.
`lua/autorun/myaddon_admin.lua` (with `AddCSLuaFile()` at the top on the server):

```lua
if SERVER then AddCSLuaFile() end
if not Rhylib then return end   -- rhylib_core missing

local function addStrip()
    local Admin = Rhylib and Rhylib.Admin
    if not (Admin and Admin.COMMANDS) or Admin.byId.strip then return end   -- no rhylib_admin, or already added

    local cmd = {
        id = "strip", name = "Strip weapons", cat = "Discipline",
        target = "player", mass = true, args = {},
        desc = "Takes all their weapons", aliases = { "stripweapons" },
    }
    cmd.perm = cmd.id
    Admin.COMMANDS[#Admin.COMMANDS + 1] = cmd
    cmd.order = #Admin.COMMANDS
    Admin.byId[cmd.id] = cmd
    Admin.byAlias[cmd.id] = cmd
    for _, a in ipairs(cmd.aliases) do Admin.byAlias[a] = cmd end

    -- Optional: a button in the "Punish" block of the Staff > Commands player panel
    -- (commands not in Admin.SECTIONS show under "Other").
    for _, sec in ipairs(Admin.SECTIONS.player) do
        if sec[1] == "Punish" then table.insert(sec[2], 1, "strip") end
    end

    if SERVER then
        Admin.handlers.strip = function(caller, t, args, ctx)
            if not t:Alive() then return nil, t:Nick() .. " is dead" end
            t:StripWeapons()
            return (IsValid(caller) and caller:Nick() or "Console") .. " stripped the weapons of " .. t:Nick()
        end
    end
end
Rhylib.Hook.Add("Initialize", "myaddon.adminstrip", addStrip)
```

Then give the permission to a rank in your host config (superadmin and owner have it already through `"*"`). The
ranks table must be set whole, so copy the default and add `"strip"` to the rank's `perms`:

```lua
-- lua/rhylib_config/admin.lua
Rhylib.Config.Set("admin", "ranks", {
    { id = "user", name = "User", level = 0, color = Color(200, 200, 200) },
    -- ... the other default ranks, unchanged ...
    { id = "moderator", name = "Moderator", level = 50, color = Color(90, 170, 240), inherits = { "trialmod" },
      perms = { "ban", "slay", --[==[ ... ]==] "hidecells", "strip" } },
    -- ...
})
```

`!strip bob`, `!strip *`, `rhylib_admin strip bob` and the menu button now all work, with the usual rank checks,
pickers, echo and log.

### Examples

React to staff ranks from your own addon (any realm):

```lua
-- Only staff ranked Moderator or higher may open the vault menu.
local function canOpenVault(ply)
    local Admin = Rhylib.Admin
    if not Admin then return ply:IsAdmin() end
    local mod = Admin.RankById("moderator")
    return Admin.Level(ply) >= (mod and mod.level or 50)
end
```

Set a staff rank from the server console (no rank checks):

```
rhylib_admin rank 76561198000000001 admin
```

Watch for calls on the client (e.g. to show them on your own HUD element):

```lua
local c = Rhylib.Admin.CurrentCall()
if c and c.left then draw.SimpleText(c.title .. " " .. math.ceil(c.left), "DermaDefault", 20, 20) end
```

## Notes and gotchas

- **Ranks come only from this addon.** `users.txt`, ULX/SAM rank changes and other CAMI sources are put back on the
  next tick. Use `!rank` (or `rhylib_admin rank ...` in the server console). The listen-server host and `owners` are
  always the top rank.
- **The first owner:** set `owners` in a host file, or run `rhylib_admin rank <your SteamID64> owner` in the server
  console. `owners` entries must be strings: a SteamID64 written as a Lua number loses its last digits.
- `ply:IsAdmin()` / `IsSuperAdmin()` are replaced for every player. With the defaults a moderator (50) is **not**
  IsAdmin; give them what they need by listing permission names in their rank.
- The CAMI usergroups are registered as a simple chain by level (each rank inherits the one below it). That chain is
  only what other CAMI addons see; it doesn't match the `inherits` lists (gamemaster doesn't really inherit trialmod).
  Our own answers to CAMI checks use the real permission sets.
- Changing the `ranks` table: copy the whole default first. Leaving out `user` makes unknown usergroups count as a
  built-in level 0 user.
- `/` commands DarkRP knows are DarkRP's (`/give`, `/job` ...). Use `!` for those admin commands.
- A muted player can still use commands, DarkRP commands that aren't talking, the admin channel and PMs to staff.
  Any other `!word` that isn't an admin command counts as talking and is blocked.
- Text sent from the staff menu is cut to 200 characters per word (`admin.run`); typed chat isn't.
- The map picker lists at most 255 maps.
- `!scale`, `!speed`, `!jump` and `!model` last until the player respawns. `!god`, `!cloak`, `!notarget` and
  `!freeze` survive respawns but not leaving the server.
- `!cleanup` with no target also removes Rhylib fixtures that weren't made permanent with the toolgun's
  Permanent tool.
- Bans are checked at connect (CheckPassword), on auth and after spawning, and for the account that owns the game when
  family sharing is used.
- The client shows the call sound and banner from a 0.25 s timer, so a call can appear up to a quarter second late.
- `rhylib_call_status` (client console) prints what your client sees of the current call, for testing.
