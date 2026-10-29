--[[
    Commands (shared registry, run on the server): one place that makes a
    console command and its chat versions, checks the permission and
    answers through Rhylib.Notify.

        Rhylib.Command.Add({
            name = "rhylib_mp_save",          -- console command
            chat = { "mpsave" },              -- also !mpsave and /mpsave (true = !name, /name)
            perm = "rhylib.mp.admin",         -- Rhylib.Perms name (nil = anyone)
            minAccess = "admin",              -- registers perm with this default (optional)
            help = "Re-save the permanent jail cells and terminals",
            args = "[confirm]",               -- shown in help
            tag = "MP",                       -- Notify tag for replies
            fn = function(ply, args, argStr)  -- ply = NULL/nil for the server console
                return "Saved 4 jail cells"   -- a string (or string, kind) is sent back
            end,
        })

    fn(ply, args, argStr): args is the list of words after the command
    (quotes keep spaces together on the console; chat splits on spaces),
    argStr the raw rest. Return a reply text (and optionally "good" /
    "bad"), or reply yourself with Rhylib.Notify. Errors are caught and
    reported as "That command failed" plus a console error.
    The server console may run every command. Players need perm (checked
    with Rhylib.Perms.Check, so CAMI / rhylib_admin ranks apply).
    Chat: one PlayerSay handler ("core.commands"); "!name args" or
    "/name args" runs it and hides the line. Register on both realms (a sh_
    file) so clients can list them; only the server runs fn.

    Rhylib.Command.List() -> sorted list of { name, chat, perm, help, args }
    (help pages). Rhylib.Command.Get(name) -> the definition.
]]

Rhylib.Command = Rhylib.Command or {}
local Cmd = Rhylib.Command
Cmd.defs = Cmd.defs or {}       -- [name] = def
Cmd.byChat = Cmd.byChat or {}   -- [lower chat word] = def

local function aliases(def)
    if def.chat == true then return { def.name } end
    if istable(def.chat) then return def.chat end
    return {}
end

-- Cmd.Add(def): see the top. Same name again replaces it (refresh-safe).
function Cmd.Add(def)
    assert(istable(def) and isstring(def.name) and isfunction(def.fn), "Rhylib.Command.Add needs { name, fn }")
    local old = Cmd.defs[def.name]
    if old then
        for _, a in ipairs(aliases(old)) do Cmd.byChat[string.lower(a)] = nil end
    end
    Cmd.defs[def.name] = def
    for _, a in ipairs(aliases(def)) do Cmd.byChat[string.lower(a)] = def end
    if def.perm and def.minAccess and Rhylib.Perms and Rhylib.Perms.Register and not (Rhylib.Perms.list and Rhylib.Perms.list[def.perm]) then
        Rhylib.Perms.Register(def.perm, def.minAccess, def.help or def.name)
    end
    if SERVER then
        concommand.Add(def.name, function(ply, _, args, argStr)
            Cmd.Run(def.name, IsValid(ply) and ply or nil, args or {}, argStr or "")
        end, nil, def.help)
    end
    return def
end

function Cmd.Get(name) return Cmd.defs[name] end

function Cmd.List()
    local out = {}
    for _, d in pairs(Cmd.defs) do
        out[#out + 1] = { name = d.name, chat = aliases(d), perm = d.perm, help = d.help or "", args = d.args or "" }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

if CLIENT then return end

local function reply(ply, def, text, kind)
    if not text or text == "" then return end
    Rhylib.Notify(IsValid(ply) and ply or nil, text, kind or "info", def.tag)
end

local function exec(def, ply, args, argStr)
    local ok, text, kind = pcall(def.fn, ply, args, argStr)
    if not ok then
        Rhylib.Error("core", "command %s: %s", def.name, tostring(text))
        reply(ply, def, "That command failed", "bad")
        return
    end
    if isstring(text) then reply(ply, def, text, kind) end
end

-- Cmd.Run(name, ply, args, argStr): run a command as ply (nil = console),
-- with the permission check. Used by the console command and chat.
function Cmd.Run(name, ply, args, argStr)
    local def = Cmd.defs[name]
    if not def then return end
    if not IsValid(ply) or not def.perm then return exec(def, ply, args, argStr) end
    Rhylib.Perms.Check(ply, def.perm, function(allowed)
        if not IsValid(ply) then return end
        if not allowed then return reply(ply, def, "You don't have permission for " .. name, "bad") end
        exec(def, ply, args, argStr)
    end)
end

-- Chat: "!word args" / "/word args".
Rhylib.Hook.Add("PlayerSay", "core.commands", function(ply, text)
    local first = string.sub(text, 1, 1)
    if first ~= "!" and first ~= "/" then return end
    local word, rest = string.match(text, "^[!/](%S+)%s*(.-)%s*$")
    if not word then return end
    local def = Cmd.byChat[string.lower(word)]
    if not def then return end
    local args = {}
    for w in string.gmatch(rest or "", "%S+") do args[#args + 1] = w end
    Cmd.Run(def.name, ply, args, rest or "")
    return ""
end)
