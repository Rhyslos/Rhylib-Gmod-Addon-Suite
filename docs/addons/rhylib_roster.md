# rhylib_roster: Characters, ranks and battalions

Every player makes a clone character on first join: a 4-digit clone number, a nickname and their looks (hair, facial hair, hair colour, skin). Their DarkRP name becomes `PREFIX-NUMBER Nickname` (CC-1234 Fives as a cadet, CT-1234 after basic training, PVT-1234 / SGT-1234 ... in a battalion). Cadets are passed through basic training by a Sergeant or higher, then added to a battalion as Privates and promoted up one shared rank ladder. The Battalion page in the pause menu lists the members, their ranks and a roster log. Characters can also hold qualifications (pilot, heavy weapons, ...) that unlock jobs and armoury roles.

For server owners: DarkRP jobs say what they need with a few extra fields (`needsTraining`, `battalion`, `minRank`, `qual`), and the job list shows players why a job is locked.

## Requirements

- Required: `rhylib_core`, `rhylib_menus` (the character creator, look window and Battalion page are built with its UI kit).
- Gamemode: DarkRP (rpname, jobs, `changeTeam`).
- Recommended: `rhylib_gear` (puts the chosen hair, hair colour and skin on the player model; without it looks are saved but not shown).
- Used by other addons: rhylib_datapad (personnel, applications, board), rhylib_admin (rank and character tools), rhylib_skills (rank checks), rhylib_chat (Command channel), rhylib_armoury (qualifications as roles).
- Workshop content: the clone model packs the jobs use; the creator preview uses `models/ct_trp/pm_ct_trp.mdl` (falls back to the player's model if missing).

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_roster.lua` | shared | Loads the module through `Rhylib.LoadModule` (needs rhylib_core). |
| `lua/rhylib/roster/sh_00_config.lua` | shared | Config (ranks, quals, ...), look lists, name/number checks, `R.Get`, `R.JobBlock`, the DarkRP job wrapper. |
| `lua/rhylib/roster/sv_10_roster.lua` | server | Saving characters, names, membership, ranks, qualifications, the roster page data, `/roster`, `/look`, `rhylib_char_reset`. |
| `lua/rhylib/roster/sv_30_purge.lua` | server | `rhylib_purge_battalion(s)`: removing an old battalion's saved data. |
| `lua/rhylib/roster/cl_10_creator.lua` | client | The forced character creator on first join. |
| `lua/rhylib/roster/cl_15_look.lua` | client | Looks: preview model, steppers, hair colour materials, the looks window and Character > Appearance page. |
| `lua/rhylib/roster/cl_20_roster.lua` | client | The Battalion page (members, manage, cadets, CTs to add, log). |

## For server owners

### Settings

Config module `"roster"`:

| Key | Default | What it does |
|---|---|---|
| `ranks` | `{ { "PVT", "Private" }, { "PFC", "Private First Class" }, { "CPL", "Corporal" }, { "SGT", "Sergeant" }, { "SSG", "Staff Sergeant" }, { "LT", "Lieutenant" }, { "CPT", "Captain" }, { "MAJ", "Major" }, { "CMD", "Commander" } }` | The rank ladder, lowest first: { prefix, name } |
| `manageRank` | `"SGT"` | Lowest rank that can add members, pass cadets and promote |
| `boardRank` | `"LT"` | Lowest rank that can post on the battalion board |
| `blockedNumbers` | `{ "1337", "6969", "0420", "6767", "6967", "6769" }` | Clone numbers nobody can take |
| `nickMax` | `20` | Longest nickname |
| `quals` | `{ { "heavy", "Heavy weapons" }, { "marksman", "Marksman" }, { "demo", "Demolitions" }, { "jump", "Jump trooper" }, { "pilot", "Pilot" }, { "engineer", "Engineer" } }` | Qualifications: { id, name }. The id is also an armoury role and a job's qual = id |

Change them in game on the Staff > Server settings page, or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("roster", "manageRank", "SSG")
Rhylib.Config.Set("roster", "quals", { { "pilot", "Pilot" }, { "medic", "Field medic" } })
```

Ranks are saved as an index into the ladder (1 = the first entry). Reordering or removing ranks changes what saved characters' ranks mean.

The creator preview model is setting `roster.preview` on the Models page ("Character creator preview").

### Jobs

Fields this addon reads on DarkRP jobs (in your darkrpmodification `jobs.lua`):

| Field | Meaning |
|---|---|
| `needsTraining = true` | Only for players who passed basic training. |
| `battalion = "212th"` | Only for members of that battalion. |
| `minRank = "SGT"` | With `battalion`: at least this rank. |
| `qual = "pilot"` | Needs that qualification. |
| `namePrefix = "CT"` | The name prefix in this job (cadet "CC", trooper "CT"); otherwise battalion jobs use the rank prefix. |
| `medic = true` | Never picked as anyone's automatic "home job". |

Globals used: `TEAM_CADET` (else `GAMEMODE.DefaultTeam`) and `TEAM_CT`. When a player joins, passes training or joins a battalion, and when their job stops being allowed, they are moved to their home job: the battalion job with the highest `minRank` they meet that has a free slot, else CT or cadet.

### Commands and permissions

| Command | Who | What it does |
|---|---|---|
| `/roster` or `!roster` (chat) | everyone | Opens the Battalion page. |
| `/look` or `!look` (chat), `rhylib_look` (console) | players with a character | Change your looks. |
| `rhylib_char_reset <SteamID64, clone number or name>` | permission `rhylib.roster.admin` (default: admin) | Deletes a character; the player gets the creator again. |
| `rhylib_purge_battalion <name>` | server console or a superadmin | Removes every saved row keyed by that battalion (roster, log, datapad data), takes its members out, clears it from saved spawns and computers on every map. Change the map afterwards. |
| `rhylib_purge_battalions [confirm]` | server console or a superadmin | Lists battalions with saved data that no job uses any more; with `confirm` purges them all. |
| `rhylib_hair_debug` (client console) | anyone | Prints your model's materials and which one is the hair (for hair colour problems). |

On the Battalion page, members with rank `manageRank` or higher manage their own battalion: promote, demote and remove members ranked below them (to ranks below their own), add trained CTs (someone from another battalion only if ranked below them; they move over as PVT), and pass cadets through basic training. Admins (`rhylib.roster.admin`) can pick any battalion and do anything.

### Placing things / saving

Nothing is placed. Everything is saved in the database (see Saved data).

## For players (short)

- First join: pick a clone number (4 digits, no "00"), a nickname and your looks. The window can't be skipped.
- Pause menu > Battalion (or `/roster`): your battalion's members and log; Sergeants and up manage it.
- Pause menu > Character > Appearance (or `/look`): change hair, facial hair, hair colour and skin. Shown with the helmet off.

## For developers

All functions are on `Rhylib.Roster` (called `R` in the code).

### Public functions

Shared (`sh_00_config.lua`; these read NW2 vars, so they work on both realms):

| Function | Returns | What it does |
|---|---|---|
| `R.Get(ply)` | `{ has, num, nick, trained, bn, rank }` | The player's character from NW2 vars. `rank` is an index (0 = none), `bn` "" = no battalion. |
| `R.FullName(ply, job)` | string or nil | `PREFIX-NUMBER Nickname`. |
| `R.Prefix(ply, job)` | string | Name prefix for that job (default: current). |
| `R.JobBlock(ply, job)` | reason or nil | Why the player can't take a DarkRP job. |
| `R.HasQual(ply, id)` | bool | Has the qualification. |
| `R.Ranks()`, `R.RankIndex(prefix)`, `R.RankPrefix(i)`, `R.RankName(i)` | | The rank ladder and lookups. |
| `R.Quals()`, `R.QualName(id)` | | Qualification list and names. |
| `R.Cfg(key)` | value | A `roster` config value. |
| `R.ValidNumber(num)`, `R.ValidNick(nick)`, `R.CleanNick(nick)`, `R.ValidLook(hair, fhair, hcol, skin)` | | Input checks. |
| `R.HairMatName(origMaterial, colour)` | string | Name of a tinted hair material (rhylib_gear sets it). |

Server (`sv_10_roster.lua`). These do no permission or rank checks: the caller checks. `sid` is a SteamID64 string; `by` is a name for the roster log.

| Function | What it does |
|---|---|
| `R.Char(sid)` | The saved character record (online or not), or nil. |
| `R.SaveChar(sid, record)` | Save a record. Call `R.Publish(ply)` too if they're online. |
| `R.Publish(ply)` | Copy the record to the player's NW2 vars. |
| `R.ApplyName(ply)` | Set the DarkRP rpname from the character. |
| `R.Members(bn)` | `{ { id = sid, c = record } }` of a battalion. |
| `R.AddMember(sid, bn, how)` | Into a battalion as PVT (moved out of any other). Fires `Rhylib.RosterJoined`. |
| `R.SetRank(sid, index, by)`, `R.RemoveMember(sid, by)`, `R.Train(sid, by)` | Rank, out of the battalion, pass training. Return true if something changed. |
| `R.SetQual(sid, qual, on, by)` | Give or take a qualification. |
| `R.ResetChar(sid)` | Delete the character; the player makes a new one. |
| `R.Log(bn, text)` | Add a roster log line. |
| `R.FullCharName(record)` | Full name from a record (offline characters too). |
| `R.SendRoster(ply, bn)` | Send the Battalion page data. |
| `R.ForgetChars()` | Drop the character cache (after the database changed behind it). |

Client (`cl_15_look.lua`): `R.LookPreview(parent, getLook)`, `R.LookControls(parent, look)`, `R.LookStepper(parent, title, list, get, set)`, `R.WriteLook(look)`, `R.ApplyHairColour(ent, colour)`, `R.OpenLook()`.

### Hooks

Fired by this addon:

- `Rhylib.RosterJoined(sid, bn)` (server): after `R.AddMember`. Return value ignored.
- `Rhylib.RosterNote(bn, sid)` (server): return a short string shown next to that member on the roster page (rhylib_datapad: leave of absence).

Listened to: `Rhylib.CanPostBoard(ply, bn)` (returns true for members of that battalion at `boardRank` or higher), `Rhylib.PlayerRoles(ply)` (returns the player's qualification ids as armoury roles), `Rhylib.DataPurged` (clears the cache), `Rhylib.ModelCatalogue` (the preview model), `CanChangeRPName` (blocks `/rpname` for players with a character), DarkRP's `DarkRPFinishedLoading` and `InitPostEntity` (wrap the jobs), `PlayerInitialSpawn`, `PlayerSpawn`, `OnPlayerChangedTeam`, `PlayerDisconnected`, `PlayerSay`.

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `roster.need` | server → client | — | Open the character creator. |
| `roster.hello` | client → server | — | "Do I still need a character?" (every 6 s while you have none). |
| `roster.create` | client → server | number, nickname (strings), hair, fhair (strings), hair colour (UInt 4), skin (UInt 4) | Make the character. |
| `roster.created` | server → client | ok (bool), message (string) | Creator result. |
| `roster.look` | client → server | hair, fhair, hair colour (4), skin (4) | Save new looks. |
| `roster.lookopen` | server → client | — | Open the looks window (`/look`). |
| `roster.get` | client → server | battalion (string, "" = mine) | Ask for the Battalion page. |
| `roster.data` | server → client | battalion, admin, manager, rank limit (UInt 8), members (count UInt 8: sid, name, rank UInt 8, online, last seen UInt 32, note), cadets (count UInt 6: sid, name), CTs (count UInt 6: sid, name), log (count UInt 6, max 40: time UInt 32, text) | The Battalion page. |
| `roster.act` | client → server | action (UInt 2: 0 train, 1 add, 2 rank, 3 remove), target sid, value (UInt 8) | A manage action. |
| `roster.open` | server → client | — | Open the Battalion page (`/roster`). |

Player NW2 vars: `rhylib_char` (bool), `rhylib_num`, `rhylib_nick`, `rhylib_trained` (bool), `rhylib_bn`, `rhylib_rank` (int), `rhylib_quals` (",a,b,"), `rhylib_hair`, `rhylib_fhair`, `rhylib_haircol` (int), `rhylib_skin` (int).

### Saved data

`Rhylib.Data` modules (keys are prefixed because JSON would turn number-like keys into numbers):

- `"char"` / SteamID64 = `{ num, nick, trained, bn, r, seen, hair, fhair, hcol, skin, q = { [qual] = true } }`. `r` is the rank index; `seen` the last disconnect (os.time).
- `"char_nums"` / `"all"` = `{ ["n" .. num] = sid }`: taken clone numbers.
- `"roster"` / battalion = `{ ["s" .. sid] = true }`: members, online or not.
- `"roster_log"` / battalion = list of `{ t, txt }`, newest first, 200 kept.

### Examples

**Check a rank or qualification from your own addon** (works on both realms):

```lua
local R = Rhylib.Roster
if R and R.RankIndex and ply:GetNW2Int("rhylib_rank", 0) >= (R.RankIndex("LT") or 99) then
    -- officers only
end
if R and R.HasQual and R.HasQual(ply, "pilot") then ... end
```

**A job that needs a battalion, a rank and a qualification** (darkrpmodification `jobs.lua`):

```lua
TEAM_212_PILOT = DarkRP.createJob("212th Pilot", {
    -- ... the usual DarkRP fields ...
    category = "212th",
    battalion = "212th", minRank = "CPL", qual = "pilot",
})
```

**React when someone joins a battalion** (server):

```lua
Rhylib.Hook.Add("Rhylib.RosterJoined", "myaddon.welcome", function(sid, bn)
    local ply = player.GetBySteamID64(sid)
    if IsValid(ply) then ply:ChatPrint("Welcome to the " .. bn) end
end)
```

**Give a qualification from your own code** (server; you check who may):

```lua
Rhylib.Roster.SetQual(target:SteamID64(), "pilot", true, admin:Nick())
```

## Notes and gotchas

- Bots get no character and are skipped by the roster.
- A forced move (training, joining, a blocked job) clears DarkRP's `ply.LastJob`, so the job-change wait doesn't apply to it.
- The first `roster.need` can arrive before the client is ready; the client's `roster.hello` timer asks again until a character exists.
- `R.SaveChar` doesn't update NW2 vars; call `R.Publish(ply)` for online players (the `R.AddMember` / `SetRank` / ... helpers do it).
- One battalion at a time: adding a member of another battalion transfers them (as PVT).
- Hair colour is a tint made on every client from the model's own hair material; the server (rhylib_gear) only swaps in its name, so nothing extra is downloaded. It's only applied with the helmet off.
- The purge commands read the SQLite table directly and ask for a map change, because other addons (the datapad) keep copies in memory.
- Changing the `ranks` list re-labels saved rank indexes; it doesn't convert them.
