# rhylib_datapad: Datapad and battalion computers

Gives every trooper a datapad and every battalion a computer. On the datapad
players write notes (logs; medics also write medical records), call for help
with one click (MPs, a medic, the bomb squad, reinforcements, resupply), and
sync their battalion's board, orders, logs, leave list, stats, their own file
and the current mission. MPs get extra tabs to look up records and jail
cuffed prisoners. The battalion computer is where logs are uploaded and where
the unit is run: a board with sessions (sign-ups, check-in) and after-action
reports, orders with a status, missions, leave of absence, personnel files
(commendations, strikes, qualifications, NCO notes), stats, applications and
upload bans. A medical holotable does the same job for medical records.

For a server owner: place one computer per battalion (battalion = DarkRP job
category), make it permanent, and stock the datapad in your armoury.

## Requirements

- **Required:** `rhylib_core`, `rhylib_menus` (every window is built with its Kit),
  the external datapad weapon `sw_datapad` (or any SWEP you name in config
  `class`). DarkRP is the gamemode: battalions are DarkRP job categories.
- **Recommended:** `rhylib_roster` (ranks: managers, officers, personnel files,
  applications, order targets), `rhylib_mp` (MP tabs, arrest records, jailing).
- **Optional:** `rhylib_medical` (medics, medical records, heals/revives
  stats), `rhylib_eod` (EOD manual tab, bomb squad calls), `rhylib_armoury`
  (stocks the datapad: trooper role gear), `rhylib_inventory` (the datapad as
  a 1x1 item).
- **Models:** battalion computer `models/ace/sw/rh/cgi_holotable_bottom.mdl`,
  medical holotable `models/reizer_props/srsp/sci_fi/command_table_02/command_table_02.mdl`.
  The packs that ship them must be Workshop required items, or swap them in
  Server settings > Models.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_datapad.lua` | shared | Loads module `datapad` (needs rhylib_core). |
| `lua/entities/rhylib_bn_computer.lua` | shared | Battalion computer entity (NetworkVar `Battalion`, floating label, E opens it). |
| `lua/entities/rhylib_med_holotable.lua` | shared | Medical holotable, built on the battalion computer. |
| `rhylib/datapad/sh_00_config.lua` | shared | Config keys, terminal models, helpers (`D.Battalion`, `D.IsMP`, `D.Limit`, `D.Clip`...), datapad inventory size, label drawing. |
| `rhylib/datapad/sv_10_pad.lua` | server | Cached storage (`D.Load` / `D.Store`), notes on the pad, MP tools, admin permission. |
| `rhylib/datapad/sv_20_terminals.lua` | server | Computer access rules, upload, delete, ban, set battalion, admin commands, saving placements. |
| `rhylib/datapad/sv_30_board.lua` | server | Log search, the board and the battalion info. |
| `rhylib/datapad/sv_40_stats.lua` | server | Battalion and player stats (kills, deaths, revives, minutes...). |
| `rhylib/datapad/sv_50_sync.lua` | server | Battalion versions and the datapad download. |
| `rhylib/datapad/sv_60_unit.lua` | server | Orders, leave of absence, applications, session sign-ups and check-in, rank helpers. |
| `rhylib/datapad/sv_70_personnel.lua` | server | Personnel files: commendations, strikes, qualifications, NCO notes. |
| `rhylib/datapad/sv_80_calls.lua` | server | Quick response calls. |
| `rhylib/datapad/sv_90_missions.lua` | server | One mission per battalion and the mission archive. |
| `rhylib/datapad/cl_10_pad.lua` | client | Datapad window, sync, shared readers (`D.ReadOrders`, `D.ReadMission`, `D.BnColor`). |
| `rhylib/datapad/cl_20_terminal.lua` | client | Computer / holotable window, the "you got accepted" popup. |
| `rhylib/datapad/cl_30_calls.lua` | client | Open calls, HUD cards, markers, the answer key. |

## For server owners

### Settings

Config module `"datapad"`:

| Key | Default | What it does |
|---|---|---|
| `class` | `"sw_datapad"` | Datapad weapon class (left click with it out opens the datapad). A new class needs a map change. |
| `noteLimit` | `5` | Notes a trooper's datapad holds before they must upload (MPs and medics: no limit, but never more than 100). |
| `titleMax` | `48` | Longest note title (characters). Also board post and order titles. |
| `bodyMax` | `1500` | Longest note text (characters). Board posts too (AARs may be twice this). |
| `logCap` | `250` | Logs kept per battalion computer, max 255 (oldest are dropped). |
| `medCap` | `250` | Medical records kept on the medical holotable, max 255. |
| `arrestRange` | `250` | MPs can jail cuffed players this close with the datapad. Also the datapad's search reach. |
| `useRange` | `160` | How close you must stay to a computer to use it. |
| `strikeDays` | `30` | Days a strike stays active. |
| `calls` | 5 entries (below) | Quick response calls: `{ id, name, short, to = mp\|medic\|battalion\|eod\|all, accept, inbound, items }`. At most 7. |
| `supplyItems` | Medical crate, Light ammo, Medium ammo, Heavy ammo, Rockets, Grenades, Power cells | What a resupply request can ask for (at most 16). |
| `callLife` | `300` | Seconds a call stays open. |
| `callCooldown` | `20` | Seconds between two calls of the same kind from one player. |
| `strikeWarn` | `3` | Active strikes at which the battalion's officers are told. |

Default `calls`:

| id | name | to | accept | items |
|---|---|---|---|---|
| `mp` | Call military police | mp | false | |
| `medic` | Call a medic | medic | false | |
| `reinf` | Request reinforcements | all | true | |
| `supply` | Request resupply | all | true | yes |
| `eod` | Call the bomb squad | eod | false | |

`accept = false`: the people called see your position at once. `accept = true`:
only those who answer see it. `to = "eod"` reaches players for whom hook
`Rhylib.IsBombSquad` says true (rhylib_eod: Field technician skill or an EOD
kit), else jobs with `eod = true`.

Rank rules come from config `"roster"` (rhylib_roster): managers are rank
`manageRank` (SGT) and up, officers `boardRank` (LT) and up.

Change settings in game on the Staff > Server settings page (Units & roles >
Datapad), or in a host config file (`lua/rhylib_config/*.lua` in your own
addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("datapad", "noteLimit", 10)
Rhylib.Config.Set("datapad", "useRange", 200)
```

A saved `calls` override in Server settings hides calls added by later
updates (like the bomb squad) until you press Reset on it.

### Commands and permissions

Permission `rhylib.datapad.admin` (default rank: admin).

| Command | Who | What it does |
|---|---|---|
| `rhylib_datapad_inspect` | perm | Toggle reading and moderating every computer and the holotable ("Admin inspection"). Without it admins only use their own battalion's computer. |
| `rhylib_datapad_setbattalion <name>` | perm | Set the battalion of the computer you look at (within 400 units); no name clears it. |
| `rhylib_datapad_save` | perm or server console | Save this map's permanent computers (with their battalion). |

Client convar `rhylib_call_key` (default `j`): answers the newest quick
response call. Rebind it in Settings > Controls ("Datapad").

Who may do what at a battalion computer:

- **Read** (logs, board, orders, missions, LOA, personnel, stats): members of
  the battalion (job category). MPs and admins too only read their own,
  unless an admin is inspecting. Medics read the holotable.
- **Moderate** (delete logs, ban/unban uploaders): admins and commanders
  (job `commander = true` or hook `Rhylib.IsCommander`) of that battalion;
  medic commanders at the holotable.
- **Post on the board** (sessions, pins, battalion info): admins, rank
  `boardRank` (LT) and up (rhylib_roster), or the battalion's commander.
  Managers (SGT and up) may write AARs and edit/delete their own.
- **Orders**: managers issue, delete and set any status; named members set
  In progress / Completed.
- **Personnel**: managers act on members ranked below them (strikes,
  qualifications, notes, removing); commend anyone but themselves. Strikes
  are visible to managers, MPs, admins and the member; NCO notes to managers
  and admins.
- **Missions**: officers (`boardRank`+ in that battalion, rhylib_roster) post,
  edit, start and end the mission from their datapad (being an admin doesn't
  count there); at the computer officers and admins delete archived ones.

### Placing things / saving

- Spawn menu Entities > "Rhylib: Terminals" (admin only), or the toolgun.
- A new battalion computer has no battalion: open it (E) as an admin and use
  **Set battalion** (lists the DarkRP categories, or type a name). After that
  only `rhylib_datapad_setbattalion` changes it.
- Make computers permanent with the toolgun's **Permanent** tool (Staff tools),
  then they and their battalion come back after a map change. Only permanent
  computers are saved (Data `"dp_places"/<map>`).

## For players (short)

- Hold the datapad and **left click** to open it.
- **Notes**: New log (troopers hold `noteLimit` notes); medics also New
  medical record (pick the patient). Upload them at your battalion computer
  (logs) or the medical holotable (records).
- **Sync** (top right): downloads your battalion computer to the pad. The
  light blinks green when there is something new.
- **Quick response**: one button per call; answer incoming calls with **J**
  (or Respond on the pad). Cards show top right, markers show where the caller is.
- At the **battalion computer** (E): upload, read logs, board, sign up for and
  check in to sessions (15 min before to an hour after the start), file leave,
  apply to join (troopers without a battalion).
- MPs: **Records** (anyone's arrests and logs), **Officer logs**, **Arrest**
  (search or jail cuffed prisoners near you).

## For developers

All tables live on `Rhylib.Datapad` (`D` below).

### Public functions

Shared:

| Function | Returns | Notes |
|---|---|---|
| `D.Cfg(key)` | value | Datapad config value. |
| `D.Battalion(ply)` | string | DarkRP job category, or `""`. |
| `D.IsMP(ply)` / `D.IsMedic(ply)` | bool | Via rhylib_mp / rhylib_medical; false without them. |
| `D.IsBombSquad(ply)` | bool | Hook `Rhylib.IsBombSquad`, else job `eod = true`. |
| `D.IsCommander(ply)` | bool | Hook `Rhylib.IsCommander`, else job `commander = true`. |
| `D.Holding(ply)` | bool | Datapad in hand. |
| `D.Limit(ply)` | number | Notes the pad holds, 0 = no limit. |
| `D.Clip(s, n, keepLines)` | string | Clip to n UTF-8 characters, strip control characters. |
| `D.MODELS`, `D.MED_KEY`, `D.KIND_LOG`, `D.KIND_MED`, `D.HARD_CAP` | | Terminal models, holotable key `"__medical"`, note kinds 0/1, pad cap 100. |

Server:

| Function | Returns | Notes |
|---|---|---|
| `D.Load(ns, key, default)` / `D.Store(ns, key, v)` / `D.StoreQuiet(...)` / `D.ClearCache()` | table | Cached `Rhylib.Data`. `D.Store` of `dp_log`/`dp_board` bumps the version; `StoreQuiet` doesn't. |
| `D.Pad(ply)`, `D.Note(pad, id)`, `D.SendState(ply)` | | Notes on a pad; resend the datapad state. |
| `D.Book(key)`, `D.Battalions()`, `D.HasBattalion(bn)`, `D.Banned(key, sid)` | | Log books, battalions with logs, bans. |
| `D.SendTerminal(ply, ent)`, `D.UseTerminal(ent, ply)` | | Open/refresh the computer window. |
| `D.TermRecv(name, { read, run }, limits)`, `D.TermAccess`, `D.TermNear`, `D.IsMedTerm`, `D.TermKey` | | Add your own computer message with the same checks. |
| `D.PadRecv(name, fn, limits, mpOnly)` | | Add your own datapad message (pad in hand). |
| `D.SavePlacements(quiet)` | number | Save permanent computers. |
| `D.Board(bn)`, `D.CanPost(ply, bn, admin)`, `D.WriteInfo(bn)`, `D.SendPost(ply, p)` | | Board. |
| `D.AddStat(ply, stat, n)`, `D.PlayerStats(sid)`, `D.StatBucketKeys(now)` | | Stats (`D.STAT_KEYS`, `D.PERIODS`). |
| `D.Version(bn)`, `D.Touch(bn)`, `D.SendExtra(ply, bn)` | | Sync. |
| `D.UnitRank(ply, bn)`, `D.IsUnitManager(ply, bn, admin)`, `D.IsUnitOfficer(ply, bn, admin)`, `D.IsUnitMember(ply, bn)` | | Rank checks (rhylib_roster). |
| `D.ActiveLeave(bn)`, `D.SendUnit(ply, ent, a)`, `D.WriteOrders(ply, bn, manager)`, `D.SetOrderStatus(ply, bn, id, st, admin)` | | Unit (`D.ORDER_STATUS`). |
| `D.File(sid)` | table | Personnel file `{ next, c, s, n }`. |
| `D.WriteMission(bn)` | | Mission into a net message. |
| `D.calls` | table | Open calls `[id] = { kind, caller, to, resp, ... }` (memory only). |

Client:

| Function | Notes |
|---|---|
| `D.BnColor(bn)` | Battalion accent colour or nil. |
| `D.ReadOrders()`, `D.ReadMission()` | Read what the server wrote. |
| `D.OrderTo(o)`, `D.OrderSub(o)`, `D.OrderColor(st)`, `D.OrderStatusMenu(o, full, onPick)`, `D.IsMPBattalion(bn)` | Order and stats helpers. |
| `D.SendCall(kind, items)`, `D.RespondCall(id)`, `D.CancelCall(id)`, `D.CanCall(kind)` | Quick response calls. |
| `D.CallTitle(c)`, `D.CallInbound(c)`, `D.CallDistance(c)`, `D.CallItems(c)` | Call text helpers. |
| `D.PadRebuild(id)` | Rebuild the datapad if tab `id` is open. |
| `D.DrawLabel(ent, title, sub)` | The computers' floating label. |
| `D.state`, `D.sync`, `D.latest`, `D.calls` | Last dp.state, last download, newest versions, open calls. |
| `D.EodManualBuild`, `D.HasEodManual` | Set by rhylib_eod to add the EOD manual tab. |

### Hooks

Fired by this addon:

- `Rhylib.IsCommander(ply)` (shared, `D.IsCommander`): return true/false to
  decide who moderates their battalion's computer.
- `Rhylib.CanPostBoard(ply, bn)` (server): return true/false for full board
  rights; nil falls back to the commander check. rhylib_roster answers true
  for rank `boardRank`+.
- `Rhylib.IsBombSquad(ply)` (server when used): return true/false for the
  `eod` call; rhylib_eod answers.
- `Rhylib.RosterNote(bn, sid)` (server, personnel list): this addon also
  answers it with "on LOA until ...".

Listened to: `Rhylib.ModelCatalogue` (adds the two terminal models),
`Initialize` (datapad inventory size), `Rhylib.DataPurged` (clears the
cache), `Rhylib.MPSearchTool` (returns `arrestRange` while holding the
datapad), `InitPostEntity` / `PostCleanupMap` (spawn saved computers),
`OnNPCKilled`, `PlayerDeath`, `Rhylib.PlayerRevived`, `Rhylib.PlayerHealed`,
`Rhylib.PlayerJailed`, `playerWalletChanged`, `ShutDown` (stats),
`Rhylib.RosterJoined`, `PlayerInitialSpawn` (applications),
`PlayerDisconnected` (calls). Client: `PlayerBindPress` (left click opens),
`Think` (answer key), `HUDPaint` (call cards), `InitPostEntity` (settings row,
Esc closer).

### Network messages

All are `Rhylib.Net` messages. Bit sizes are in the file headers.

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `dp.open` / `dp.state` | C→S / S→C | – / battalion, roles, ban, limit, version, notes, cuffed nearby | Open the datapad. |
| `dp.get` / `dp.body` | C→S / S→C | note id / id, text | A note's text. |
| `dp.save`, `dp.del` | C→S | id, kind, title, text, patient / id | Write or delete a note. |
| `dp.find` / `dp.found` | C→S / S→C | name / sid, name, arrests | MP: find a person. |
| `dp.rec` / `dp.record` | C→S / S→C | sid / arrests + logs | MP: a record. |
| `dp.olog` / `dp.ologs` | C→S / S→C | – / logs | MP: logs by MPs. |
| `dp.lread` / `dp.lbody` | C→S / S→C | battalion, id / text | MP: read a log. |
| `dp.jail` | C→S | prisoner, minutes, reason | MP: jail from the pad. |
| `dp.term` | S→C | computer state, entries, bans | Open/refresh the computer window. |
| `dp.tread` / `dp.tbody` | C→S / S→C | entity, id / text | Read an entry. |
| `dp.tup`, `dp.tdel`, `dp.tban`, `dp.tunban`, `dp.tset` | C→S | entity, ... | Upload, delete, ban, unban, set battalion. |
| `dp.tfind` / `dp.tfound` | C→S / S→C | entity, text, days / ids | Log search. |
| `dp.bopen` / `dp.board` | C→S / S→C | entity / rights, posts, info | Board list. |
| `dp.bget` / `dp.bbody` | C→S / S→C | entity, id / text, sign-ups, check-ins | A post. |
| `dp.bsave`, `dp.bdel`, `dp.bpin`, `dp.binfo` | C→S | entity, ... | Board edits. |
| `dp.stats` / `dp.statsr` | C→S / S→C | entity, period / totals, members | Stats tab. |
| `dp.ver` | S→C | battalion, version | Something changed: sync light. |
| `dp.dl` / `dp.dldata`, `dp.dlx`, `dp.dlm` | C→S / S→C | – / logs+board, orders+LOA+stats+file, info+mission | Datapad download. |
| `dp.dread` / `dp.dbody` | C→S / S→C | kind, id / text | Read a downloaded log or post. |
| `dp.uopen` / `dp.unit` | C→S / S→C | entity / orders, leave, applications | Unit tabs. |
| `dp.uorder`, `dp.ustatus`, `dp.uodel`, `dp.ostatus` | C→S | ... | Orders (`dp.ostatus` from the pad). |
| `dp.uloa`, `dp.uloadel` | C→S | entity, dates, reason / id | Leave. |
| `dp.uapply`, `dp.uwithdraw`, `dp.udecide`, `dp.uanswer` | C→S | ... | Applications. |
| `dp.uappget` / `dp.uappinfo` | C→S / S→C | entity, id / stats, quals, strikes, arrests | Applicant record. |
| `dp.uprompt` | S→C | kind, battalion, by | Application news / accepted popup. |
| `dp.ursvp`, `dp.ucheck` | C→S | entity, post id (, choice) | Session sign-up, check-in. |
| `dp.plist` / `dp.pmembers` | C→S / S→C | entity / members | Personnel list. |
| `dp.pget` / `dp.pfile` | C→S / S→C | entity, sid / the file | A personnel file. |
| `dp.pcom`, `dp.pstrike`, `dp.pnote`, `dp.pdel`, `dp.pqual` | C→S | entity, sid, ... | Personnel actions. |
| `dp.call`, `dp.callr`, `dp.callx` | C→S | kind + items / id / id | Call, answer, end. |
| `dp.callu`, `dp.callp` | S→C | call state / id, position | Call updates. |
| `dp.mget` / `dp.mcur` | C→S / S→C | – / can edit, mission | Mission on the pad. |
| `dp.msave`, `dp.mstart`, `dp.mend` | C→S | texts / – / – | Officers run the mission. |
| `dp.mlist` / `dp.mlistr`, `dp.mread` / `dp.mfull`, `dp.mdel` | C→S / S→C | entity, ... | Mission archive. |

### Saved data

`Rhylib.Data` modules (keys with a SteamID64 inside a table are always
written `"s"..sid`: JSON would turn a bare SteamID64 into a rounded number):

| Module / key | Contents |
|---|---|
| `dp_pad` / sid | Notes on the pad. |
| `dp_log` / battalion, `"__medical"` | Log book `{ next, list }`. |
| `dp_log` / `"__index"` | Battalions that have logs. |
| `dp_ban` / battalion or `"__medical"` | `{ ["s"..sid] = name }`. |
| `dp_places` / map | Computer placements `{ class, pos, ang, bn }`. |
| `dp_board` / battalion | Board posts `{ next, list }`. |
| `dp_info` / battalion | Battalion info `{ txt, by, t }`. |
| `dp_ver` / battalion | `{ v }` version. |
| `dp_stats` / battalion | Stat buckets (today, week, month, all). |
| `dp_pst` / sid | A player's all-time totals. |
| `dp_ord` / battalion | Orders (the old `dp_orders` text is moved into it once). |
| `dp_loa` / battalion | Leave of absence. |
| `dp_apps` / battalion, `dp_myapp` / sid | Applications, and each applicant's own. |
| `dp_pf` / sid | Personnel file (commendations, strikes, notes). |
| `dp_mis` / battalion, `dp_misarc` / battalion | Current mission, archive (100). |

`rhylib_purge_battalion <name>` (rhylib_roster) removes a battalion's rows;
`rhylib_purge_maps` (core) removes `dp_places` rows of missing maps.

### Examples

React to a call or add a stat from your own addon (server):

```lua
-- Count a "training passed" in the datapad stats as an event.
Rhylib.Hook.Add("MyAddon.TrainingPassed", "myaddon.dpstat", function(ply)
    if Rhylib.Datapad and Rhylib.Datapad.AddStat then
        Rhylib.Datapad.AddStat(ply, "ev", 1)
    end
end)
```

Let a custom rank system decide who posts on the board (server):

```lua
Rhylib.Hook.Add("Rhylib.CanPostBoard", "myaddon.board", function(ply, bn)
    if ply:GetUserGroup() == "eventteam" then return true end
end)
```

Add a call kind from a host config file (write the whole list; keep the
order of the ones you keep; at most 7):

```lua
Rhylib.Config.Set("datapad", "calls", {
    { id = "mp", name = "Call military police", short = "MP", to = "mp", accept = false, inbound = "MP" },
    { id = "medic", name = "Call a medic", short = "Medic", to = "medic", accept = false, inbound = "Medic" },
    { id = "reinf", name = "Request reinforcements", short = "Reinforcements", to = "all", accept = true, inbound = "Reinforcements" },
    { id = "supply", name = "Request resupply", short = "Resupply", to = "all", accept = true, inbound = "Resupply", items = true },
    { id = "eod", name = "Call the bomb squad", short = "Bomb squad", to = "eod", accept = false, inbound = "Bomb squad" },
    { id = "pilot", name = "Request a pilot", short = "Pilot", to = "all", accept = true, inbound = "Pilot" },
})
```

Make a commander check from your own job flag (shared):

```lua
Rhylib.Hook.Add("Rhylib.IsCommander", "myaddon.cmd", function(ply)
    local j = RPExtraTeams and RPExtraTeams[ply:Team()]
    if j and j.isCO then return true end
end)
```

## Notes and gotchas

- Battalions are DarkRP job **categories** (the job's `category`), not roster
  battalions; rename a category and its computer, books and stats no longer
  match (use `rhylib_purge_battalion` for the old name).
- A computer's battalion can only be set from its window while it has none;
  change it with `rhylib_datapad_setbattalion`. Computers that aren't made
  permanent are gone after a map change.
- Everything is cached in memory on the server (`D.Load`). If you edit
  `dp_*` rows by hand or with another tool, call `Rhylib.Datapad.ClearCache()`
  or change the map.
- Stats are kept in memory and saved once a minute and at shutdown; a crash
  loses up to a minute.
- Quick response calls live in memory only (gone on a map change). A call's
  kind is its place in the `calls` list: changing the order mid-game can
  mislabel open calls.
- The datapad download only shows when both its parts arrived; the progress
  bar (3-15 s) is for feel. Leave changes don't light "New data" (only logs,
  board, info, orders and missions bump the version).
- Session times are made from the poster's local clock (`os.time` on their
  client) and shown in each viewer's own time zone.
- Without rhylib_roster nobody below admin is a manager or officer: orders,
  applications and personnel are admin only, missions can't be posted at
  all, and commanders (job `commander = true`) still post on the board.
- Reloading only `sv_50_sync.lua` with Lua refresh wraps `D.Store` a second
  time (double version bumps, and sign-ups start bumping it). A map change
  fixes it.
