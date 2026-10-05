--[[
    Chat channels and command parsing (shared).

    Channels: public, local, advert, admin, private messages, RP (public
    roleplay actions) and Event (event announcements to everyone, sent by
    staff with the rhylib.chat.event permission).
    Squad (your radio squad), Battalion (your battalion) and Command
    (officers from commandRank up and battalion commanders, any battalion)
    only show for players who can use them (Chat.CanUse).

    Typing:
      plain text            goes to your current channel (click the
                            channel name to change it, or type /local etc.)
      /public text  // text /ooc text      public
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
Chat.CHANNELS = {
    { id = "public", name = "Public", color = Color(228, 227, 220), cmds = { "public", "p", "ooc" }, desc = "Everyone on the server" },
    { id = "local", name = "Local", color = Color(151, 196, 89), cmds = { "local", "l" }, desc = "People near you" },
    { id = "advert", name = "Advert", color = Color(239, 159, 39), cmds = { "advert", "ad" }, desc = "Everyone, highlighted (cooldown)" },
    { id = "admin", name = "Admin", color = Color(226, 75, 74), cmds = { "admin", "a" }, desc = "Reach the admins" },
    { id = "pm", name = "PM", color = Color(190, 150, 255), cmds = { "pm", "w", "msg" }, desc = "Private message: /pm name text", private = true },
    { id = "rp", name = "RP", color = Color(120, 190, 230), cmds = { "rp" }, desc = "Roleplay actions, everyone sees them", action = true },
    { id = "event", name = "Event", color = Color(255, 205, 80), cmds = { "event", "ev" }, desc = "Event announcements to everyone (staff)", staff = "rhylib.chat.event" },
    { id = "squad", name = "Squad", color = Color(110, 220, 200), cmds = { "squad", "sq" }, desc = "Your radio squad", needs = "squad" },
    { id = "battalion", name = "Battalion", color = Color(140, 170, 255), cmds = { "battalion", "bn" }, desc = "Your battalion", needs = "battalion" },
    { id = "command", name = "Command", color = Color(235, 185, 120), cmds = { "command", "cmd" }, desc = "Officers and commanders", needs = "command" },
    { id = "comms", name = "Comms", color = Color(130, 205, 235), cmds = { "comms", "co" }, desc = "Everyone, as radio comms" },
}  -- 15 channels max with 4 bits; add new ones at the end
Chat.byId, Chat.byCmd = {}, {}
for i, c in ipairs(Chat.CHANNELS) do
    c.index = i
    Chat.byId[c.id] = c
    for _, cmd in ipairs(c.cmds) do Chat.byCmd[cmd] = c end
end
Chat.CHANNEL_BITS = 4

local Config = Rhylib.Config
Config.Register("chat", "defaultChannel", "public", "Channel plain text goes to until a player picks another (public, comms, local, ...)")
Config.Register("chat", "localRange", 600, "How far local chat carries (units)")
Config.Register("chat", "advertCooldown", 30, "Seconds between adverts per player")
Config.Register("chat", "maxLength", 300, "Longest message in characters")
Config.Register("chat", "commandRank", "LT", "Lowest roster rank in the Command channel (battalion commanders always are)")

-- Who a channel reaches (shared: the server routes with it, the client
-- only lists channels you can use).
function Chat.SquadOf(ply)
    local Radio = Rhylib.Radio
    return Radio and Radio.SquadOf and Radio.SquadOf(ply) or 0
end

-- Your battalion: rhylib_roster's, else your job's battalion (not the
-- Recruits category).
function Chat.BattalionOf(ply)
    local bn = ply:GetNW2String("rhylib_bn", "")
    if bn ~= "" then return bn end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and isstring(job.battalion) and job.battalion or ""
end

function Chat.InCommand(ply)
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    if job and job.commander then return true end
    local Roster = Rhylib.Roster
    if not (Roster and Roster.RankIndex) then return false end
    local need = Roster.RankIndex(Rhylib.Config.Get("chat", "commandRank")) or 6
    return ply:GetNW2Int("rhylib_rank", 0) >= need
end

-- ok, reason
function Chat.CanUse(ply, ch)
    if ch.needs == "squad" then
        if Chat.SquadOf(ply) == 0 then return false, "You're not in a radio squad" end
    elseif ch.needs == "battalion" then
        if Chat.BattalionOf(ply) == "" then return false, "You're not in a battalion" end
    elseif ch.needs == "command" then
        if not Chat.InCommand(ply) then return false, "Only officers (" .. tostring(Rhylib.Config.Get("chat", "commandRank")) .. " and up) and commanders use the Command channel" end
    end
    return true
end

-- Finds a player by (part of) their name. Exact matches win.
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
