--[[
    Chat channels and command parsing (shared: loaded on server and client).

    Adds: Rhylib.Chat (the addon's table), Chat.CHANNELS (the channel list),
    Chat.byId / Chat.byCmd lookups, the "chat" config keys, and the helpers
    both sides use: Chat.SquadOf, Chat.BattalionOf, Chat.InCommand,
    Chat.CanUse, Chat.FindPlayer and Chat.Parse. The server (sv_10_chat)
    routes messages with them; the client (cl_10_chat) uses them for the
    channel picker, the "/" suggestions and to read what you typed.

    Channels: public, local, advert, admin, private messages, RP (public
    roleplay actions) and Event (event announcements to everyone, sent by
    staff with the rhylib.chat.event permission).
    Squad (your radio squad), Battalion (your battalion) and Command
    (officers from commandRank up and battalion commanders, any battalion)
    only show for players who can use them (Chat.CanUse).

    Typing:
      plain text            goes to your current channel (click the
                            channel name to change it, or type /local etc.)
      /public text  /p text  // text  /ooc text   public
      /local text   /l text               people near you
      /advert text  /ad text              everyone, highlighted, with a cooldown
      /admin text   /a text               admins (anyone can send, for reports)
      /rp text                            everyone, as an action: "* Name text"
      /event text   /ev text              everyone, highlighted with a banner (staff)
      /squad text   /sq text              your radio squad
      /battalion text /bn text            your battalion
      /command text /cmd text             officers and commanders
      /comms text   /co text              everyone, tagged [Comms] (like public;
                                          set chat defaultChannel "comms" to make it the default)
      /pm name text  /pm "two words" text a private message
      /local (nothing else)               switches your current channel

    Anything else starting with / or ! is passed on untouched, so DarkRP's
    commands (/job, /dropmoney, ...) and admin mod commands (!goto, ...)
    keep working. That choice is made in one place, Chat.Parse below: to
    take those over later, handle them there instead of returning "pass".
]]

Rhylib.Chat = Rhylib.Chat or {}
local Chat = Rhylib.Chat

-- index = network id (4 bits), keep the order stable.
-- Fields of a channel:
--   id       name used in code, routes (sv_10_chat) and hooks
--   name     shown in the chat ("[Local] ...") and the picker
--   color    tag and picker colour
--   cmds     slash commands that pick it (without the "/")
--   desc     one line shown in the picker and suggestions
--   private  needs a target player (/pm name text)
--   action   drawn as "* Name text" (roleplay action)
--   staff    CAMI permission needed to send (checked on the server)
--   needs    "squad" | "battalion" | "command": hidden and refused for
--            players outside it (Chat.CanUse)
--   jammable carried by radio: dead inside a rhylib_radio comms jammer
Chat.CHANNELS = {
    { id = "public", name = "Public", color = Color(228, 227, 220), cmds = { "public", "p", "ooc" }, desc = "Everyone on the server" },
    { id = "local", name = "Local", color = Color(151, 196, 89), cmds = { "local", "l" }, desc = "People near you" },
    { id = "advert", name = "Advert", color = Color(239, 159, 39), cmds = { "advert", "ad" }, desc = "Everyone, highlighted (cooldown)" },
    { id = "admin", name = "Admin", color = Color(226, 75, 74), cmds = { "admin", "a" }, desc = "Reach the admins" },
    { id = "pm", name = "PM", color = Color(190, 150, 255), cmds = { "pm", "w", "msg" }, desc = "Private message: /pm name text", private = true },
    { id = "rp", name = "RP", color = Color(120, 190, 230), cmds = { "rp" }, desc = "Roleplay actions, everyone sees them", action = true },
    { id = "event", name = "Event", color = Color(255, 205, 80), cmds = { "event", "ev" }, desc = "Event announcements to everyone (staff)", staff = "rhylib.chat.event" },
    { id = "squad", name = "Squad", color = Color(110, 220, 200), cmds = { "squad", "sq" }, desc = "Your radio squad", needs = "squad", jammable = true },
    { id = "battalion", name = "Battalion", color = Color(140, 170, 255), cmds = { "battalion", "bn" }, desc = "Your battalion", needs = "battalion", jammable = true },
    { id = "command", name = "Command", color = Color(235, 185, 120), cmds = { "command", "cmd" }, desc = "Officers and commanders", needs = "command", jammable = true },
    { id = "comms", name = "Comms", color = Color(130, 205, 235), cmds = { "comms", "co" }, desc = "Everyone, as radio comms", jammable = true },
}  -- 15 channels max with 4 bits; add new ones at the end
-- Chat.byId["local"] -> channel, Chat.byCmd["l"] -> channel.
Chat.byId, Chat.byCmd = {}, {}
for i, c in ipairs(Chat.CHANNELS) do
    c.index = i
    Chat.byId[c.id] = c
    for _, cmd in ipairs(c.cmds) do Chat.byCmd[cmd] = c end
end
Chat.CHANNEL_BITS = 4  -- bits for a channel index in chat.msg / chat.send (0 = system note)

local Config = Rhylib.Config
Config.Register("chat", "defaultChannel", "public", "Channel plain text goes to until a player picks another (public, comms, local, ...)")
Config.Register("chat", "localRange", 600, "How far local chat carries (units)")
Config.Register("chat", "advertCooldown", 30, "Seconds between adverts per player")
Config.Register("chat", "maxLength", 300, "Longest message in characters")
Config.Register("chat", "commandRank", "LT", "Lowest roster rank in the Command channel (battalion commanders always are)")

-- Who a channel reaches (shared: the server routes with it, the client
-- only lists channels you can use).

-- Chat.SquadOf(ply): the player's rhylib_radio squad id, 0 when not in a
-- squad (or rhylib_radio isn't installed).
function Chat.SquadOf(ply)
    local Radio = Rhylib.Radio
    return Radio and Radio.SquadOf and Radio.SquadOf(ply) or 0
end

-- Chat.BattalionOf(ply): your battalion name, "" for none.
-- rhylib_roster's (NW2 rhylib_bn), else your DarkRP job's `battalion` field
-- (not the Recruits category).
function Chat.BattalionOf(ply)
    local bn = ply:GetNW2String("rhylib_bn", "")
    if bn ~= "" then return bn end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and isstring(job.battalion) and job.battalion or ""
end

-- Chat.InCommand(ply): true if the player may use the Command channel:
-- a job with commander = true, or roster rank >= config chat commandRank
-- (needs rhylib_roster for the rank part).
function Chat.InCommand(ply)
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    if job and job.commander then return true end
    local Roster = Rhylib.Roster
    if not (Roster and Roster.RankIndex) then return false end
    local need = Roster.RankIndex(Rhylib.Config.Get("chat", "commandRank")) or 6
    return ply:GetNW2Int("rhylib_rank", 0) >= need
end

-- Chat.CanUse(ply, ch): can this player send on / see channel ch?
-- Returns true, or false and a reason to show them. Checks the radio
-- jammer (jammable channels) and the `needs` field. The staff permission
-- of the Event channel is checked separately on the server.
-- Example: local ok, why = Rhylib.Chat.CanUse(ply, Rhylib.Chat.byId.squad)
function Chat.CanUse(ply, ch)
    -- (rhylib_radio comms jammer: the radio-carried channels go dead)
    if ch.jammable and IsValid(ply) and ply:GetNW2Bool("rhylib_jammed", false) then
        return false, "Comms are jammed here: only local, public and admin chat work"
    end
    if ch.needs == "squad" then
        if Chat.SquadOf(ply) == 0 then return false, "You're not in a radio squad" end
    elseif ch.needs == "battalion" then
        if Chat.BattalionOf(ply) == "" then return false, "You're not in a battalion" end
    elseif ch.needs == "command" then
        if not Chat.InCommand(ply) then return false, "Only officers (" .. tostring(Rhylib.Config.Get("chat", "commandRank")) .. " and up) and commanders use the Command channel" end
    end
    return true
end

-- Chat.FindPlayer(name): finds a player by (part of) their name, case
-- insensitive. Exact matches win, else the first partial match. nil if none.
function Chat.FindPlayer(name)
    name = string.lower(name or "")
    if name == "" then return nil end
    local partial
    for _, p in ipairs(player.GetAll()) do
        local nick = string.lower(p:Nick())
        if nick == name then return p end
        if not partial and string.find(nick, name, 1, true) then partial = p end
    end
    return partial
end

--[[
    Works out what a line of typed text is. Returns one of:
      "send", channel, body, targetName   a Rhylib channel message
      "switch", channel                   just a channel command: change channel
      "pass"                              not ours: send it as normal chat
      "usage", text                       a Rhylib command used wrongly
    current: the channel plain text goes to.
    Example: Rhylib.Chat.Parse("/l hello", Rhylib.Chat.byId.public)
             --> "send", <Local channel>, "hello"
]]
function Chat.Parse(text, current)
    if string.sub(text, 1, 2) == "//" then
        return "send", Chat.byId.public, string.Trim(string.sub(text, 3))
    end
    local first = string.sub(text, 1, 1)
    if first ~= "/" and first ~= "!" then
        return "send", current, text
    end
    if first == "!" then return "pass" end

    local cmd, rest = string.match(text, "^/(%S+)%s*(.*)$")
    local ch = cmd and Chat.byCmd[string.lower(cmd)]
    if not ch then return "pass" end  -- DarkRP's and other addons' commands

    if ch.private then
        local target, body = string.match(rest, '^"([^"]+)"%s*(.*)$')
        if not target then target, body = string.match(rest, "^(%S+)%s*(.*)$") end
        if not target or body == "" then return "usage", "Usage: /pm name message (\"quotes\" for names with spaces)" end
        return "send", ch, body, target
    end
    if rest == "" then return "switch", ch end
    return "send", ch, rest
end
