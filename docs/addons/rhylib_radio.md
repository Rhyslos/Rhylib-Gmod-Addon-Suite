# rhylib_radio: Radio, squads and comms jammers

Splits voice chat into local voice and radio. The normal voice key is local: only players nearby hear you, in 3D. Holding the radio key (B) sends your voice on your radio instead: to your squad, or to one of two channels you've joined, or to a hail call. Players make squads (with a leader, a radio operator and visual roles), create open, password or battalion-only channels, hail a squad or a player for a private line, and ping spots for their squad (move here, enemy, hold, regroup, medic...). The HUD shows which radio you're on, voice meters, an optional squad compass, markers over squad mates and hail cards. Radio voices get squelch clicks, tiny drop-outs and the odd burst of interference.

For server owners it adds comms jammers in four sizes: inside one, the radio is dead (static, local voice only) and the radio text channels close. Only explosives destroy them. Squads, channels and calls live in memory and reset on map change; jammers are saved per map.

## Requirements

- Required: `rhylib_core`, `rhylib_menus` (squads, channels and hails are made on the Radio page; the ping wheel uses its wheel).
- Works better with:
  - `rhylib_hud`: the radio squares, meters and compass sit in the helmet visor. Without it they're on a panel at the right edge.
  - `rhylib_chat`: the Squad chat channel, jammers closing the radio text channels, radio colours in the voice list.
  - `rhylib_republic` / `rhylib_weapons`: grenades, rockets and HE charges are the only things that destroy jammers.
  - `rhylib_roster`: battalion-only channels use the roster battalion (else the DarkRP job category).
  - `rhylib_toolgun`: placing jammers; `rhylib_core`'s Permanent tool keeps them on the map.
  - `rhylib_skills`: squad mates share marks and command orders through the radio squad; jammed players can't call reinforcements.
  - `rhylib_eod`: its interference device jams the radio like a jammer.
- Workshop content: the jammer models (paths in the settings below) come from Star Wars prop packs; if a model isn't installed the jammer uses `jammerFallbackModel` (an HL2 radio receiver). All sounds are HL2.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_radio.lua` | shared | Loads the module through `Rhylib.LoadModule("radio")`. |
| `lua/rhylib/radio/sh_00_config.lua` | shared | `Rhylib.Radio` table, config keys, the state bits (`R.Pack` / `R.Unpack` / `R.State`), roles, jammer sizes and jam helpers. |
| `lua/rhylib/radio/sh_40_pings.lua` | shared | Ping types `R.PINGS` and the ping config keys. |
| `lua/rhylib/radio/sv_10_radio.lua` | server | Radio state, who hears whom, squads, channels, the directory, squad mate positions, the jam timer, jammer explosions and saves. |
| `lua/rhylib/radio/sv_20_hails.lua` | server | Hail calls: ringing, answering, hanging up. |
| `lua/rhylib/radio/sv_30_pings.lua` | server | Checks a ping and sends it to the squad. |
| `lua/rhylib/radio/cl_05_icons.lua` | client | Vector symbols for roles, leader, RO, hails (`R.DrawIcon`, `R.DrawTags`). |
| `lua/rhylib/radio/cl_10_client.lua` | client | What the client knows, the radio keys, requests to the server, settings rows, the "Hail" wheel option. |
| `lua/rhylib/radio/cl_20_hud.lua` | client | Radio squares, voice meters, squad compass (with the jammer glitch), mate markers, hail card. |
| `lua/rhylib/radio/cl_25_fx.lua` | client | Radio voice effects and the jammer static and chat notes. |
| `lua/rhylib/radio/cl_30_page.lua` | client | The Radio page in the pause menu. |
| `lua/rhylib/radio/cl_40_pings.lua` | client | Ping wheel, ping markers on screen and on the compass. |
| `lua/entities/rhylib_comms_jammer.lua` | shared | The comms jammer (small), base of the others. |
| `lua/entities/rhylib_comms_jammer_medium.lua`, `_large.lua`, `_map.lua` | shared | The bigger jammers (only their name differs; the class picks the config keys). |

## For server owners

### Settings

Config module `"radio"`:

| Key | Default | What it does |
|---|---|---|
| `localRange` | `800` | Local voice reaches this far (units, 800 = 15 m). |
| `maxChannels` | `200` | Most custom channels on the server at once. |
| `hailTime` | `30` | Seconds a hail rings before it counts as missed. |
| `squadNames` | `{ "Aurek", "Besh", "Cresh", "Dorn", "Esk", "Forn", "Grek", "Herf", "Isk", "Jenth" }` | Squad name suggestions (a number is added after). |
| `fxDropEvery` | `7` | Radio voice: average seconds between tiny drop-outs per talker (0 = none). |
| `fxDropLen` | `0.08` | Radio voice: length of a drop-out in seconds (used between 0.02 and 0.25). |
| `fxNoiseEvery` | `20` | Radio voice: average seconds between interference bursts while someone talks on the radio (0 = none). |
| `fxSquelchOn` | `"npc/combine_soldier/vo/on1.wav"` | Click when someone starts talking on your radio. |
| `fxSquelchOff` | `"npc/combine_soldier/vo/off1.wav"` | Click when they stop. |
| `fxCrackle` | `{ "ambient/energy/zap1.wav", "ambient/energy/zap2.wav", "ambient/energy/zap3.wav" }` | Crackles at a drop-out (one picked at random). |
| `fxNoise` | `{ "ambient/levels/prison/radio_random1.wav", ... radio_random5.wav }` | Interference bursts (one picked at random). |
| `jammerRange` | `1800` | Small comms jammer: radius it jams (units, 1800 = 34 m). |
| `jammerModel` | `"models/props/starwars/weapons/hoth_bomb.mdl"` | Small comms jammer: model. |
| `jammerRangeMedium` | `3600` | Medium comms jammer: radius. |
| `jammerModelMedium` | `"models/lordtrilobite/starwars/props/barrel_scarif2c_phys.mdl"` | Medium comms jammer: model. |
| `jammerRangeLarge` | `7200` | Large comms jammer: radius (meant to cover about a quarter of a map). |
| `jammerPointsLarge` | `6` | Large comms jammer: damage points to destroy it (they add up). |
| `jamPointsHE` | `6` | Damage points of a high explosive charge (large jammer). |
| `jamPointsRocket` | `3` | Damage points of an RPS-6 rocket (large jammer). |
| `jamPointsBreach` | `2` | Damage points of a breaching charge (large jammer). |
| `jammerModelLarge` | `"models/starwars/syphadias/props/sw_tor/bioware_ea/props/neutral/neu_industrial_tower.mdl"` | Large comms jammer: model. |
| `jammerChargesMap` | `4` | Map-wide comms jammer: high explosive charges needed to destroy it. |
| `jammerChargeWindow` | `3` | Jammers needing several HE charges: seconds within which they must all go off (0 = any time). |
| `jammerModelMap` | `"models/props/starwars/tech/imperial_deflector.mdl"` | Map-wide comms jammer: model. |
| `jammerFallbackModel` | `"models/props_lab/reciever01a.mdl"` | Used when a jammer's own model isn't installed. |
| `jammerFringe` | `0.35` | Interference zone outside a jammer's range, as a part of the range (0.35 = 35% further out). |
| `jamReconnect` | `4` | Seconds the radio stays jammed after leaving the range. |
| `jamStatic` | `"ambient/energy/electric_loop.wav"` | The static loop you hear when you key the radio while jammed. |
| `pingRange` | `12000` | Squad pings: how far you can ping (units). |
| `pingCooldown` | `0.6` | Squad pings: seconds between two pings from one player. |

Change them on the Staff > Server settings page (Units & roles > Radio; model paths also on the Model overrides page), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("radio", "localRange", 600)
Rhylib.Config.Set("radio", "squadNames", { "Aurek", "Besh", "Cresh" })
Rhylib.Config.Set("radio", "fxDropEvery", 0)   -- no drop-outs
```

A new jammer model only applies to jammers placed after the change (or after a map change).

### Comms jammers

| Class | Toolgun entry (Base) | Range | Destroyed by |
|---|---|---|---|
| `rhylib_comms_jammer` | Comms jammer (small) | `jammerRange` | Any player grenade (tier 1) or stronger. |
| `rhylib_comms_jammer_medium` | Comms jammer (medium) | `jammerRangeMedium` | An RPS-6 rocket or a breaching charge (tier 2), or an HE charge. |
| `rhylib_comms_jammer_large` | Comms jammer (large) | `jammerRangeLarge` | Damage points adding up to `jammerPointsLarge`: HE charge 6, rocket 3, breaching charge 2 (grenades don't count). |
| `rhylib_comms_jammer_map` | Comms jammer (whole map) | every living player | `jammerChargesMap` HE charges going off within `jammerChargeWindow`. |

Inside a jammer's range a player can't key the radio (they hear static, and people near them still hear them as local voice), hears no radio, and can't use the jammable chat channels (squad, battalion, command, comms). Near the edge (the fringe) the compass glitches and radio voices crackle more. After leaving, the radio reconnects for `jamReconnect` seconds. Gunfire only sparks a jammer and tells the shooter what's needed. A destroyed jammer goes dark and stops jamming but isn't removed: it's back after a map change or cleanup.

### Commands and permissions

| Command / permission | Who | What it does |
|---|---|---|
| `rhylib.radio.admin` | default admin | Place, switch (E) and save comms jammers. |
| `rhylib_radio_save` | `rhylib.radio.admin` or the server console | Saves the permanent jammers for this map now. |
| E on a jammer | `rhylib.radio.admin` | Switches it on or off (and saves). |
| `rhylib_radio` | anyone (client) | Opens the Radio page. |

### Placing things / saving

Place jammers with the toolgun (Base category). Placing alone doesn't save: make them permanent with the toolgun's Permanent tool (or run `rhylib_radio_save`, which saves the jammers that are permanent). Saves go to Data `"radio_jammers"` / `<map>`; they spawn 1 s after the map loads and again after a map cleanup. Staff holding the toolgun see each jammer's range as a red ring on the ground.

## For players (short)

| Key (default) | What it does |
|---|---|
| Voice key | Local voice: people near you. |
| B (hold) | Talk on the radio: your selected slot (squad, channel 1, channel 2), or the hail call you're in. |
| K | Switch the slot the radio key talks on. |
| T | Radio page (squads, channels, hails, compass). |
| O (hold) | Squad ping wheel; let go on a ping to send it. |
| unbound | Mute your radio / deafen it / turn it on or off. |

All keys can be changed in Settings > Controls ("Radio" section); channel colours and the ping chat line are in Settings > Interface. The game asks once per server whether the radio may use your microphone. Radio voice effects and their volume are in Settings > Audio. The squad compass on the HUD is switched on under the compass on the Radio page.

The squares on the visor's left cheek (L, SQ, 1, 2): grey = not joined, dim = joined, bright = talking on it, red = radio muted, dark grey = radio off; a small notch marks the slot B talks on. Your mic meter is under the left stamina strip, the incoming meter mirrored on the right.

## For developers

The module table is `Rhylib.Radio` (`R` below).

### Public functions

Shared:

| Function | What it does |
|---|---|
| `R.Cfg(key)` → value | A radio config value. |
| `R.State(ply)` → table | Unpacked radio state `{ off, muted, deaf, txKind, txId, squad, role, leader, ro }`, cached per value. Read only. |
| `R.Unpack(v)` / `R.Pack(t)` / `R.Raw(ply)` | The packed NW2Int `rhylib_radio` and its fields. |
| `R.SquadOf(ply)` → id | Squad id (0 = none). On the client, other players' come from the directory. |
| `R.RoleOf(ply)`, `R.IsLeader(ply)`, `R.IsRO(ply)` | Role index, squad leader, radio operator. |
| `R.Battalion(ply)` → name | Roster battalion, else DarkRP category, else "". |
| `R.CleanName(s)` → name | Squad / channel name cleaned and cut to 24 characters. |
| `R.Jammed(ply)` → bool | Jammed (inside a jammer, or reconnecting). |
| `R.Reconnecting(ply)` → seconds or nil | Time left reconnecting. |
| `R.JamLevel(ply)` → 0-1 | Jam strength (1 inside, fringe level outside). |
| `R.JammerSize(entOrClass)` → row, `R.JammerRange(entOrClass)` → units | Jammer size info and radius (`math.huge` for the whole-map one). |

Server:

| Function | What it does |
|---|---|
| `R.Note(ply, text)` | "[Radio] text" chat line to one player. |
| `R.Set(ply, fields)` | Changes fields of a player's radio state. |
| `R.SetTx(ply, kind, id)` | Starts / stops sending (`R.TX_*`); tells the listeners at once. `R.SetTx(ply, 0, 0)` stops. |
| `R.JoinSquad(ply, sq)`, `R.LeaveSquad(ply)` | Squad membership (`sq` from `R.squads`). |
| `R.LeaveChannel(ply, slot)` | Leaves channel slot 1 or 2. |
| `R.HangUp(ply)` | Leaves / ends their hail call and declines rings. |
| `R.CallLive(id)` → bool | A call with 2+ members. |
| `R.Dirty()` | Schedules a directory broadcast. |
| `R.SendMe(ply)` | Sends a player their channel slots and call. |
| `R.P(ply)` → table | Server radio table `{ slots, call }`. |
| `R.SaveJammers()` → count, `R.SpawnJammers()` | Jammer save / load for this map. |

Server tables: `R.squads[id] = { id, name, open, leader, ro, members = { [ply] = joinTime }, n }`, `R.channels[id] = { id, name, mode, pass, bn, members = { [ply] = true }, n }`, `R.calls[id]`, `R.jammers[ent] = true`. Player field `ply.rhylibJammed` (true while jammed).

Client:

| Function | What it does |
|---|---|
| `R.Mine()` → state, `R.Selected()` → slot | Your own state and the slot the radio key uses. |
| `R.SlotOn(slot)`, `R.SlotName(slot)`, `R.SlotColor(slot)` | Slot 1 squad, 2 channel 1, 3 channel 2. |
| `R.HeardOn(talker)` → 1-3, 4 (call) or nil | Which of your slots a talker reaches you on. |
| `R.SpeakerColor(ply)` → colour or nil | Colour for a talker (nil = local voice). |
| `R.InCall()`, `R.RadarOn()` | In an answered call; compass switched on. |
| `R.Toggle("off" / "muted" / "deaf")`, `R.SetRole(i)`, `R.CycleSlot()`, `R.OpenPage()` | Player actions. |
| `R.SquadOp(op, arg)` (`R.SQ.*`), `R.ChanCreate / ChanJoin / ChanLeave`, `R.HailSquad(id)`, `R.HailPlayer(ply)`, `R.Answer(id, yes)`, `R.HangUp()` | Requests to the server. |
| `R.DrawRadar(cx, cy, r, names, ox, oy)` | Draws the squad compass (with the jam glitch). |
| `R.DrawIcon(name, x, y, size, col, bg)`, `R.DrawTags(ply, x, y, size, col)` | Vector symbols (`R.ICONS`). |
| `R.MatePos(p)` → pos or nil | A squad mate's position, also while out of view (last `radio.pos`). |
| `R.CompassChatWidth()`, `R.VisorGeo()` | Visor layout numbers (rhylib_chat asks for its width). |
| `R.Choose(title, { { label, fn } })` | A small choice window over the pause menu. |
| `R.Changed()` | Rebuild the Radio page soon. |

Client data: `R.dir` (squads, channels, `sqOf` / `roleOf` by entindex), `R.me` (slots, call), `R.call`, `R.rings`, `R.mates`, `R.speaking`, `R.tx`, `R.pings`, `R.txOn`.

Tables you can add to: `R.ROLES` (add at the end; 31 at most), `R.PINGS` (add at the end; 15 at most), `R.ICONS`, `R.PALETTE`.

### Hooks

Fired by this addon: none.

Listened to:
- `PlayerCanHearPlayersVoice` "radio.voice" (priority 10, after rhylib_admin's gag at -50): decides radio vs local voice.
- `Rhylib.Explosion(pos, reach, tier, attacker, inflictor, kind)` "radio.jammers": damages jammers in reach (fired by rhylib_republic, rhylib_weapons, rhylib_eod).
- `Rhylib.WheelOptions` "radio.wheel" (rhylib_menus): adds "Hail" to the interaction wheel.
- `PlayerStartVoice` / `PlayerEndVoice` at -100 / -110 (before rhylib_chat's voice list, which stops the event), `PlayerDisconnected`, `PlayerDeath`, `InitPostEntity`, `PostCleanupMap`, `PlayerBindPress`, `Think`, `HUDPaint`, `EntityRemoved`, `ShutDown`.

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `radio.dir` | server → everyone (or one player) | squads: id 9, name, open, leader, RO, members (entindex 8 + role 5); channels: id 9, name, mode 2, battalion, listeners 8 | The directory (no passwords). At most one broadcast per 1.5 s. |
| `radio.me` | server → player | channel slot 1, slot 2, call id (9 bits each) | Own slots and call. |
| `radio.pos` | server → squad, every 1 s | count 8, per mate: entindex 8, x/y/z Int 16 | Mate markers while out of view. |
| `radio.note` | server → player | string | Chat note. |
| `radio.txev` | server → listeners of the old and new target | talker entindex 8, kind 2, id 9 | Who's talking on what, at once. |
| `radio.state` | client → server | off, muted, deafened (bools) | Radio switches. |
| `radio.role` | client → server | role index 5 | Squad role. |
| `radio.tx` | client → server | bool on, slot 2 | Radio key down / up. |
| `radio.txoff` | client → server | nothing | Radio key up (sent twice, loose rate limit). |
| `radio.squad` | client → server | op 3 + name / squad id 9 / player | Create, join, leave, lock, rename, kick, leader, RO. |
| `radio.chan` | client → server | op 2, slot 1 + name, mode 2, password / id 9, password | Create, join, leave a channel. |
| `radio.dirreq` | client → server | nothing | Send me the directory and my slots. |
| `radio.hail` | client → server | kind 2 + squad id 9 or player | Hail a squad (its leader and RO) or a player. |
| `radio.answer` | client → server | call id 9, bool | Answer / decline. |
| `radio.hangup` | client → server | nothing | Leave / end the call. |
| `radio.ring` | server → player rung | call id 9, bool on (+ caller, label) | Start / stop ringing. |
| `radio.call` | server → call members | id 9 (0 = none) + started float, label, caller, ringing 8, members | The call you're in. |
| `radio.ping` | client → server, then server → squad mates not jammed | up: kind 4. down: sender, kind 4, position, tracked entity | Squad pings (rate 4/s per player plus `pingCooldown`). |

Networked values: NW2Int `rhylib_radio` (packed state, bits in `sh_00_config.lua`), NW2Bool `rhylib_jammed`, NW2Float `rhylib_jamLevel` (5% steps), NW2Float `rhylib_jamUntil` (when the reconnect ends), jammer NetworkVar Bool `Active`.

### Saved data

| Data module / key | What's stored |
|---|---|
| `"radio_jammers"` / `<map name>` | List of `{ pos = {x,y,z}, ang = {p,y,r}, on, class }` for the permanent jammers. |

Squads, channels and calls are never saved. Each player's own settings (keys, states, role, slot, colours) are client convars.

### Examples

Check the radio from your own addon (e.g. block an action while jammed, find the squad):

```lua
local R = Rhylib.Radio
if R and R.Jammed(ply) then return false, "Comms jammed" end
local sq = R and R.squads[R.SquadOf(ply)]   -- server
if sq then for mate in pairs(sq.members) do --[[ ... ]] end end
```

Make your own explosive count against jammers (server):

```lua
-- tier 1 = grenade, 2 = rocket / breaching charge, 3 = HE charge
hook.Run("Rhylib.Explosion", pos, 250, 2, attackerPlayer, self, "rocket")
```

Add a ping type (shared, so both realms have it; add at the end):

```lua
local R = Rhylib.Radio
R.PINGS[#R.PINGS + 1] = { id = "vehicle", label = "Vehicle", short = "VEHICLE", icon = "rocket",
    col = Color(200, 120, 255), life = 20, chat = "enemy vehicle" }
```

Count something as a jammer (like rhylib_eod's interference device): add the entity to `R.jammers` on the server, give it `GetActive()` and optionally `ENT:JamRange()`, and remove it in `OnRemove`:

```lua
function ENT:Initialize()
    -- ...
    local R = Rhylib.Radio
    if R and R.jammers then R.jammers[self] = true end
end
function ENT:JamRange() return 1200 end
```

## Notes and gotchas

- Voice is turned on with `permissions.EnableVoiceChat` (Lua can't run `+voicerecord`); the game asks each player once per server.
- Squads, channels and hails reset on every map change.
- Other players' NW2 state arrives late while they're out of view, so the client takes squad, role, leader and RO of others from the directory and talk events from `radio.txev`. Only your own state is read from NW2.
- `PlayerCanHearPlayersVoice` runs for every pair of players; it only reads a per-tick snapshot per player (alive, state, position, jammed). Keep anything you add to it as cheap.
- Dead players are heard by nobody, not even locally.
- The jam check runs every 0.5 s on the server; dying clears jamming at once (no reconnect).
- Destroyed jammers are kept (dark, not solid) so a save made afterwards still has them; they come back on the next map load or cleanup.
- Changing `localRange` takes up to 5 s to apply.
