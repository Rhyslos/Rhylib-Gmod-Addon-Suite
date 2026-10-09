--[[
    Admin commands (shared list; the server runs them, sv_10_admin.lua).

    { id, name, cat, perm (default = id), target, args, desc, aliases }
      target: "player"  an online player (required)
              "self"    an online player, or yourself when left out
              "opt"     an online player, or nobody when left out
              "id"      an online player or any SteamID / SteamID64
              nil       no target
      args: { { key, label, kind, need = true, opt = true } } in order
            (need: a text argument asked for when left out; opt: may be
            left out, and a word that doesn't fit goes to the next one); kinds:
              text (the rest of the line), word, number, duration ("30m",
              "2h", "1d", "1w", "perm"), rank, rosterrank, battalion,
              qual, onoff, map (picker), class, job, minutes, scale, mult,
              model, sound, call (a preset id), callmins
      mass: true = "*" targets everyone you outrank (not you).
    Chat: !id target args  (or /id); quotes for names with spaces.
    Targets: name (or part of it), SteamID, SteamID64, ^ = you, @ = the
    player you're looking at, * = everyone (mass commands).
    A chat command missing its player or arguments opens pickers for the
    rest (admin.ask).
]]

local Admin = Rhylib.Admin

Admin.COMMANDS = {
    -- Discipline
    { id = "kick", name = "Kick", cat = "Discipline", target = "player", args = { { "reason", "Reason", "text" } }, desc = "Disconnect a player" },
    { id = "ban", name = "Ban", cat = "Discipline", target = "id",
      args = { { "time", "Length (30m, 2h, 1d, 1w, perm)", "duration" }, { "reason", "Reason", "text" } },
      desc = "Ban by name or SteamID (offline too); perm or over the limit needs permaban" },
    { id = "unban", name = "Unban", cat = "Discipline", target = "id", args = {}, desc = "Lift a ban (SteamID)" },
    { id = "warn", name = "Warn", cat = "Discipline", target = "player", args = { { "reason", "Reason", "text", need = true } }, desc = "A logged warning the player sees" },
    { id = "mute", mass = true, name = "Mute chat", cat = "Discipline", target = "player", args = {}, desc = "No text chat until unmuted or they leave" },
    { id = "unmute", mass = true, name = "Unmute chat", cat = "Discipline", target = "player", args = {} },
    { id = "gag", mass = true, name = "Gag voice", cat = "Discipline", target = "player", args = {}, desc = "No voice until ungagged or they leave" },
    { id = "ungag", mass = true, name = "Ungag voice", cat = "Discipline", target = "player", args = {} },
    { id = "freeze", mass = true, name = "Freeze", cat = "Discipline", target = "player", args = {} },
    { id = "unfreeze", mass = true, name = "Unfreeze", cat = "Discipline", target = "player", args = {} },
    { id = "slay", name = "Slay", cat = "Discipline", target = "player", args = {} },
    { id = "respawn", mass = true, name = "Respawn", cat = "Discipline", target = "self", args = {} },
    { id = "warnings", name = "Show warnings", cat = "Discipline", perm = "warn", target = "id", args = {}, desc = "Their warning history (to you)" },
    { id = "setjob", name = "Set job", cat = "Discipline", target = "self", args = { { "job", "Job command or name", "job" } }, desc = "DarkRP job, skipping its checks" },
    { id = "spectate", name = "Spectate", cat = "Teleport", target = "player", args = {}, aliases = { "spec" }, desc = "Watch them; run again (or !unspectate) to stop" },
    { id = "unspectate", name = "Stop spectating", cat = "Teleport", perm = "spectate", args = {} },
    { id = "jail", name = "Jail", cat = "Discipline", target = "player", args = { { "minutes", "Minutes", "minutes" }, { "reason", "Reason", "text" } }, desc = "Into a jail cell (rhylib_mp); items go to evidence" },
    { id = "unjail", name = "Release from jail", cat = "Discipline", target = "player", args = {} },
    { id = "free", name = "Uncuff / unstun", cat = "Discipline", mass = true, target = "self", args = {}, aliases = { "uncuff", "unstun" } },
    { id = "unwarn", name = "Clear warnings", cat = "Discipline", target = "id", args = {}, aliases = { "clearwarns" } },
    { id = "slap", name = "Slap", cat = "Discipline", mass = true, target = "player", args = {} },
    { id = "ignite", name = "Set on fire", cat = "Discipline", mass = true, target = "player", args = {} , desc = "10 seconds" },
    { id = "extinguish", name = "Put out fire", cat = "Discipline", perm = "ignite", mass = true, target = "self", args = {} },
    { id = "tell", name = "Private message", cat = "Discipline", target = "player", args = { { "text", "Message", "text", need = true } }, aliases = { "psay" }, desc = "Shown to them as a staff message" },
    { id = "info", name = "Player info", cat = "Discipline", target = "id", args = {}, aliases = { "pinfo" }, desc = "Rank, job, character, warnings, ban (to you)" },
    { id = "who", name = "Staff online", cat = "Server", perm = "logs", args = {}, desc = "Lists online staff and their ranks (to you)" },

    -- Moving people
    { id = "goto", name = "Go to", cat = "Teleport", target = "player", args = {} },
    { id = "bring", mass = true, name = "Bring", cat = "Teleport", target = "player", args = {} },
    { id = "return", mass = true, name = "Return", cat = "Teleport", target = "self", args = {}, desc = "Back to where they were before goto / bring / teleport" },
    { id = "teleport", name = "Teleport to aim", cat = "Teleport", target = "self", args = {}, aliases = { "tp" }, desc = "To where you're looking" },

    -- Powers (toggles; on yourself when no target)
    { id = "noclip", name = "Noclip", cat = "Powers", target = "self", args = {}, desc = "Toggle (staff with noclip can also use the noclip key)" },
    { id = "god", mass = true, name = "God mode", cat = "Powers", target = "self", args = {} },
    { id = "cloak", mass = true, name = "Invisible", cat = "Powers", target = "self", args = {}, aliases = { "invis" } },
    { id = "notarget", mass = true, name = "No target", cat = "Powers", target = "self", args = {}, desc = "NPCs and droids ignore them" },
    { id = "hp", mass = true, name = "Set health", cat = "Powers", target = "self", args = { { "amount", "Health", "number" } }, aliases = { "health" } },
    { id = "armor", mass = true, name = "Set armour", cat = "Powers", target = "self", args = { { "amount", "Armour", "number" } }, aliases = { "armour" } },
    { id = "give", mass = true, name = "Give weapon", cat = "Powers", target = "self", args = { { "class", "Weapon class", "class" } } },

    { id = "revive", name = "Revive", cat = "Powers", mass = true, target = "self", args = {}, desc = "Gets a downed player up; a dead one respawns where they fell" },
    { id = "heal", name = "Heal fully", cat = "Powers", mass = true, target = "self", args = {}, desc = "Full health and armour, injuries gone, revived if down" },
    { id = "infect", name = "Infect (illness)", cat = "Powers", mass = true, target = "self",
      args = { { "kind", "Kind", "illness" }, { "load", "Strength 1-100", "illload", opt = true } },
      desc = "Gives them an illness for medics to find and treat (rhylib_medical)" },
    { id = "cure", name = "Cure illness", cat = "Powers", mass = true, target = "self", args = {}, desc = "Takes an illness away" },
    { id = "buddha", name = "Buddha", cat = "Powers", target = "self", args = {}, desc = "Takes damage but never drops below 1 health" },
    { id = "money", name = "Give money", cat = "Powers", target = "self", args = { { "amount", "Amount (negative takes)", "number" } }, aliases = { "addmoney" } },
    { id = "setmoney", name = "Set money", cat = "Powers", perm = "money", target = "self", args = { { "amount", "Amount", "number" } } },

    -- Events (until they respawn)
    { id = "scale", name = "Size", cat = "Events", mass = true, target = "self", args = { { "size", "Size (1 = normal, 0.2 - 5)", "scale" } }, aliases = { "size" } },
    { id = "speed", name = "Speed", cat = "Events", mass = true, target = "self", args = { { "mult", "Speed (1 = normal, 0.1 - 10)", "mult" } } },
    { id = "jump", name = "Jump height", cat = "Events", mass = true, target = "self", args = { { "mult", "Jump (1 = normal, 0 - 10)", "mult" } } },
    { id = "model", name = "Model", cat = "Events", mass = true, target = "self", args = { { "model", "Model path, or reset", "model" } }, aliases = { "setmodel" } },
    { id = "playsound", name = "Play sound", cat = "Events", args = { { "sound", "Sound path", "sound" } }, aliases = { "sound" }, desc = "Everyone hears it" },
    { id = "stopsound", name = "Stop sounds", cat = "Events", args = {}, desc = "Stops every sound for everyone" },
    { id = "call", name = "Call (briefing, prep...)", cat = "Events",
      args = { { "preset", "Call", "call" }, { "minutes", "Timer", "callmins", opt = true }, { "text", "Message (optional)", "text" } },
      desc = "A banner for everyone (and anyone joining); timed calls show a countdown" },
    { id = "endcall", name = "End call", cat = "Events", perm = "call", args = {}, aliases = { "callend" }, desc = "Takes the banner and countdown away" },

    -- Ranks
    { id = "rank", name = "Set staff rank", cat = "Ranks", target = "id", args = { { "rank", "Rank", "rank" } }, desc = "Below your own rank only" },
    { id = "rrank", name = "Set roster rank", cat = "Ranks", perm = "roster", target = "id", args = { { "rank", "Rank", "rosterrank" } }, aliases = { "rosterrank" } },
    { id = "battalion", name = "Set battalion", cat = "Ranks", perm = "roster", target = "id", args = { { "bn", "Battalion", "battalion" } }, desc = "Moves them in as PVT" },
    { id = "unbattalion", name = "Remove from battalion", cat = "Ranks", perm = "roster", target = "id", args = {} },
    { id = "train", name = "Pass basic training", cat = "Ranks", perm = "roster", target = "id", args = {} },
    { id = "qual", name = "Qualification", cat = "Ranks", perm = "roster", target = "id", args = { { "qual", "Qualification", "qual" }, { "on", "On / off", "onoff" } } },
    { id = "charreset", name = "Reset character", cat = "Ranks", target = "player", args = {}, desc = "They pick a new number and nickname" },

    -- Server / events
    { id = "map", name = "Change map", cat = "Server", args = { { "map", "Map", "map" } }, desc = "Pick from a list (or !map part-of-name); 10 s countdown" },
    { id = "cleanup", name = "Clean up spawned things", cat = "Server", target = "opt", args = {}, desc = "Everything that isn't part of the map or made permanent (toolgun Permanent tool); or one player's things with a target (^ = yours)" },
    { id = "cancelmap", name = "Cancel map change", cat = "Server", perm = "map", args = {} },
    { id = "restartmap", name = "Restart map", cat = "Server", perm = "map", args = {}, aliases = { "maprestart" }, desc = "Reloads this map after a 10 s countdown" },
    { id = "hidecells", name = "Show / hide jail cells", cat = "Server", args = {}, desc = "Hides the jail cell rings for everyone (again to show them)" },
    { id = "freezeprops", name = "Freeze all props", cat = "Server", args = {}, aliases = { "nolag" }, desc = "Stops every moving prop (lag)" },
    { id = "cleardecals", name = "Clear decals", cat = "Server", args = {}, desc = "Blood, scorch marks and client death ragdolls, for everyone" },
    { id = "announce", name = "Announcement", cat = "Server", args = { { "text", "Text", "text", need = true } }, aliases = { "a" }, desc = "A banner for everyone" },
}

-- How the staff menu groups the commands (rhylib_menus cl_30_commands.lua).
-- Anything not listed lands in "Other"; call/endcall have their own block.
Admin.SECTIONS = {
    player = {
        { "Info & messages", { "info", "warnings", "tell", "warn", "unwarn" } },
        { "Move", { "goto", "bring", "return", "teleport", "spectate" } },
        { "Health", { "heal", "revive", "hp", "armor", "respawn", "infect", "cure" } },
        { "Restrain", { "freeze", "unfreeze", "free", "jail", "unjail" } },
        { "Chat & voice", { "mute", "unmute", "gag", "ungag" } },
        { "Powers", { "god", "buddha", "noclip", "cloak", "notarget", "give" } },
        { "Event fun", { "scale", "speed", "jump", "model", "slap", "ignite", "extinguish" } },
        { "Job & money", { "setjob", "money", "setmoney" } },
        { "Roster & staff rank", { "rank", "rrank", "battalion", "unbattalion", "train", "qual", "charreset" } },
        { "Punish", { "slay", "kick", "ban" } },
    },
    server = {
        { "Map", { "map", "restartmap", "cancelmap" } },
        { "Announcements & sound", { "announce", "playsound", "stopsound" } },
        { "Cleanup", { "cleanup", "freezeprops", "cleardecals", "hidecells" } },
        { "Staff", { "who", "unspectate" } },
    },
    skip = { call = true, endcall = true, unban = true },
}

Admin.byId = {}
Admin.byAlias = {}
for i, c in ipairs(Admin.COMMANDS) do
    c.order = i
    c.perm = c.perm or c.id
    Admin.byId[c.id] = c
    Admin.byAlias[c.id] = c
    for _, a in ipairs(c.aliases or {}) do Admin.byAlias[a] = c end
end

-- "30m" / "2h" / "1d" / "1w" / "perm" / "0" / "45" (minutes) -> minutes (0 = forever), or nil.
function Admin.ParseDuration(s)
    s = string.lower(string.Trim(s or ""))
    if s == "perm" or s == "permanent" or s == "forever" or s == "0" then return 0 end
    local n, u = string.match(s, "^(%d+%.?%d*)%s*([mhdwy]?)$")
    n = tonumber(n)
    if not n or n <= 0 or n ~= n or n == math.huge then return nil end
    local mult = { [""] = 1, m = 1, h = 60, d = 1440, w = 10080, y = 525600 }
    return math.max(1, math.ceil(n * mult[u]))   -- never 0 (that's "perm")
end

function Admin.FormatMinutes(m)
    if not m or m <= 0 then return "permanently" end
    if m % 10080 == 0 then return (m / 10080) .. " week" .. (m == 10080 and "" or "s") end
    if m % 1440 == 0 then return (m / 1440) .. " day" .. (m == 1440 and "" or "s") end
    if m % 60 == 0 then return (m / 60) .. " hour" .. (m == 60 and "" or "s") end
    return m .. " minute" .. (m == 1 and "" or "s")
end

-- Splits a command line into words; "quoted text" stays one word.
function Admin.Split(line)
    local out = {}
    line = line or ""
    local i = 1
    while i <= #line do
        local c = string.sub(line, i, i)
        if c == " " or c == "\t" then
            i = i + 1
        elseif c == '"' then
            local j = string.find(line, '"', i + 1, true) or (#line + 1)
            out[#out + 1] = string.sub(line, i + 1, j - 1)
            i = j + 1
        else
            local j = string.find(line, "[ \t]", i) or (#line + 1)
            out[#out + 1] = string.sub(line, i, j - 1)
            i = j
        end
    end
    return out
end
