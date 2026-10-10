# rhylib_chat: Chat box and voice list

Replaces Garry's Mod's chat box with one in the Rhylib house style. Players get channels (Public, Local, Advert, Admin, private messages, RP actions, Event announcements, Comms, and Squad / Battalion / Command for the people in them), command suggestions as they type, and the sender's helmet portrait next to each line. In first person with the helmet visor HUD the chat sits in the visor's left cheek. Everything other addons print with `chat.AddText` (DarkRP, admin mods, join messages) still shows in it. It also replaces GMod's "who is talking" panels with a list of portraits, names and jobs.

For server owners: commands that aren't Rhylib's (DarkRP's `/job`, admin mods' `!goto`, ...) are passed on untouched, so they keep working.

## Requirements

- Required: `rhylib_core`.
- Works better with: `rhylib_hud` (visor layout), `rhylib_radio` (Squad channel, comms jammers, radio colours in the voice list), `rhylib_roster` (battalion and rank for the Battalion and Command channels), `rhylib_admin` (mutes), `rhylib_menus` (the "Keep the chat visible" setting row).
- No Workshop content.

## Files

| File | Realm | What it does |
|---|---|---|
| `lua/autorun/rhylib_chat.lua` | shared | Loads the module through `Rhylib.LoadModule` (needs rhylib_core). |
| `lua/rhylib/chat/sh_00_config.lua` | shared | Channel list, config keys, who may use which channel, and `Chat.Parse` (what a typed line is). |
| `lua/rhylib/chat/sv_10_chat.lua` | server | Checks each message, sends it to the players its channel reaches, typing indicator. |
| `lua/rhylib/chat/cl_10_chat.lua` | client | The chat window, the fading feed, suggestions, channel picker, Event banner. |
| `lua/rhylib/chat/cl_20_voice.lua` | client | The voice list that replaces GMod's voice panels. |

## For server owners

### Settings

Config module `"chat"`:

| Key | Default | What it does |
|---|---|---|
| `defaultChannel` | `"public"` | Channel plain text goes to until a player picks another (`public`, `comms`, `local`, ...). |
| `localRange` | `600` | How far Local chat carries, in units. |
| `advertCooldown` | `30` | Seconds between adverts per player. |
| `maxLength` | `300` | Longest message in characters (the server cuts longer ones). |
| `commandRank` | `"LT"` | Lowest roster rank allowed in the Command channel (jobs with `commander = true` always are). |

Change them in game on the Staff > Server settings page (Units & roles > Chat), or in a host config file (`lua/rhylib_config/*.lua` in your own addon, see `docs/config-example.lua`):

```lua
Rhylib.Config.Set("chat", "defaultChannel", "comms")   -- plain text goes to Comms
Rhylib.Config.Set("chat", "localRange", 800)
```

### Channels

| # | Id | Commands | Who sees it |
|---|---|---|---|
| 1 | `public` | `/public`, `/p`, `/ooc`, `// text` | Everyone. |
| 2 | `local` | `/local`, `/l` | Players within `localRange`. |
| 3 | `advert` | `/advert`, `/ad` | Everyone, highlighted; `advertCooldown` between adverts. |
| 4 | `admin` | `/admin`, `/a` | The sender and anyone with `rhylib.chat.admin`. Anyone can send (for reports). |
| 5 | `pm` | `/pm`, `/w`, `/msg` + name | The sender and the target. `/pm "two words" text` for names with spaces. |
| 6 | `rp` | `/rp` | Everyone, drawn as an action: `* Name text`. |
| 7 | `event` | `/event`, `/ev` | Everyone, gold, plus a banner at the top. Only senders with `rhylib.chat.event`. |
| 8 | `squad` | `/squad`, `/sq` | Your radio squad (needs rhylib_radio). |
| 9 | `battalion` | `/battalion`, `/bn` | Your battalion (roster battalion, else the DarkRP job's `battalion` field). |
| 10 | `command` | `/command`, `/cmd` | Officers from `commandRank` up and jobs with `commander = true`, any battalion. |
| 11 | `comms` | `/comms`, `/co` | Everyone, tagged `[Comms]`. |

Squad, Battalion and Command only show for players who can use them. Channels marked `jammable` (Squad, Battalion, Command, Comms) stop working inside a rhylib_radio comms jammer: players there can't send on them and don't receive them.

### Commands and permissions

| Permission | Default | What it allows |
|---|---|---|
| `rhylib.chat.admin` | admin | See the Admin channel. |
| `rhylib.chat.event` | admin | Post in the Event channel. |

Chat-only commands (handled on the client, never sent): `/togglechat` (or `/pinchat`) keeps the chat window on screen. Client convar: `rhylib_chat_pinned` (0/1).

## For players (short)

- Your chat key (Y by default) opens it. Plain text goes to your current channel (shown left of the input line; click it to pick another).
- `/local` + space switches channel straight away. `/local hello` sends one line to Local without switching.
- Typing `/` lists matching commands; after `/pm ` it lists player names. Tab or Enter fills one in, Up/Down picks.
- With no list open, Up/Down walks through what you sent before.
- Mouse wheel scrolls the history. Esc closes.
- `/togglechat` keeps the window on screen (Settings > Interface > "Keep the chat visible" does the same).

## For developers

### Public functions

| Function | Realm | Returns | What it does |
|---|---|---|---|
| `Chat.CanUse(ply, ch)` | shared | `ok, reason` | Can this player send on / see channel `ch` (jammer and `needs` checks). |
| `Chat.Parse(text, current)` | shared | see below | What a typed line is: `"send", ch, body, targetName` / `"switch", ch` / `"pass"` / `"usage", text`. |
| `Chat.SquadOf(ply)` | shared | number | Radio squad id, 0 = none. |
| `Chat.BattalionOf(ply)` | shared | string | Battalion name, `""` = none. |
| `Chat.InCommand(ply)` | shared | bool | May use the Command channel. |
| `Chat.FindPlayer(name)` | shared | player or nil | By (part of) the name; exact matches win. |
| `Chat.Note(ply, text)` | server | — | A grey system line in one player's chat. |
| `Chat.Add(segs, sid)` | client | — | Adds a line to the box. `segs = { { Color, text }, ... }`, `sid` = sender SteamID64 for the portrait. |
| `Chat.ShowEvent(by, text)` | client | — | Shows the gold Event banner. |
| `Chat.Open()` / `Chat.Close()` | client | — | Open or close the chat window. |
| `Chat.Rect()` | client | `x, y, w, h, visor` | Where the chat sits on screen (rhylib_radio lays out around it). |
| `Chat.VisorEdgeX(y)` | client | number | x of the visor chat's curved edge at screen height `y`. |

(`Chat` is `Rhylib.Chat`.) Tables: `Chat.CHANNELS` (list, index = network id), `Chat.byId`, `Chat.byCmd`, `Chat.CHANNEL_BITS` (4).

```lua
-- Server: tell one player something in grey.
Rhylib.Chat.Note(ply, "Your squad was disbanded")

-- Client: a coloured line of your own.
Rhylib.Chat.Add({ { Color(110, 220, 200), "[Squad] " }, { color_white, "Moving out" } })
```

### Hooks

Fired by this addon (server):

- `Rhylib.CanChat(ply, channelId, text, target)`: before a message goes out. Return `false, "reason"` to stop it (the player is told the reason). `target` is the PM receiver, else nil. rhylib_admin uses it for mutes.
- `Rhylib.ChatMessage(sender, channelId, text, target)`: after a message was sent (logs, Discord relays). `target` only for PMs.

The client also fires the standard GMod hooks `StartChat`, `FinishChat` and `ChatTextChanged`, so addons that watch the chat box keep working.

Listened to: `ChatText` (join/leave and engine lines), `PlayerBindPress` (`messagemode` opens ours), `HUDShouldDraw` (hides `CHudChat`), `PlayerStartVoice` / `PlayerEndVoice` (voice list; returning true hides GMod's panels), `PlayerSpawn` / `PlayerDeath` (clear the typing flag).

### Network messages

| Name | Direction | Contents | Purpose |
|---|---|---|---|
| `rhylib.chat.send` | client → server | channel index (4 bits), target entity (PM, else NULL), text | Send a message. Rate 2/s, burst 5. |
| `rhylib.chat.msg` | server → recipients | channel index (4 bits, 0 = system note), sender entity, target entity, text | A message (or a note) to show. |
| `rhylib.chat.typing` | client → server | bool | Typing or not; sets NW2Bool `rhylib_typing` (the HUD's icon above heads). Rate 6/s, burst 10. |

### Saved data

None.

### Examples

Log every chat line to a file (server, your own addon):

```lua
Rhylib.Hook.Add("Rhylib.ChatMessage", "mylog.chat", function(sender, channelId, text, target)
    file.Append("chatlog.txt", os.date("%H:%M ") .. sender:Nick() .. " [" .. channelId .. "] " .. text .. "\n")
end)
```

Block Advert for players under some rule (server):

```lua
Rhylib.Hook.Add("Rhylib.CanChat", "myrules.adverts", function(ply, channelId)
    if channelId == "advert" and ply:Team() == TEAM_CADET then
        return false, "Cadets can't post adverts"
    end
end)
```

Make Comms the default channel for everyone (host config file):

```lua
Rhylib.Config.Set("chat", "defaultChannel", "comms")
```

## Notes and gotchas

- Channel indexes go over the network in 4 bits: at most 15 channels. Add new ones at the end of `Chat.CHANNELS`, never in the middle (the index is the network id). A new channel also needs a route in `sv_10_chat.lua` (`route[id]`), or nothing is sent.
- `Chat.Parse` is the only place that decides which `/` commands are Rhylib's. Everything starting with `!`, and any `/` command it doesn't know, is sent with `say` so DarkRP and admin mods handle it.
- The Event channel's permission is checked asynchronously (CAMI); the message goes out once the check answers.
- The client lists only channels you can use, but the server checks `Chat.CanUse` again, so a modified client can't post in a channel it isn't allowed in.
- A player still set to Squad after leaving their squad gets a "pick another channel" note instead of the line silently going to Public.
- The chat keeps 150 lines. Closed, lines fade after 12 s unless the chat is pinned.
