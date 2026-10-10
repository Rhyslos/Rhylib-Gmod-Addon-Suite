--[[
    Staff ranks and permissions (shared: server and client both load it).
    Also registers every "admin" config key, makes ply:IsAdmin() /
    IsSuperAdmin() follow the rank levels, answers CAMI permission checks,
    allows the noclip key for staff, and holds the !scale hull helper.

    Ranks (config "admin.ranks", highest last is fine, order by level):
        { id, name, level, color, inherits = { ids }, perms = { names } }
    A rank has its own perms plus everything its `inherits` ranks have;
    "*" = everything. Permission names are admin command ids ("kick"),
    a few powers ("spawn", "noclip.self" ...) and Rhylib.Perms / CAMI
    privilege names ("rhylib.chat.event"). A privilege the rank doesn't
    list falls back to its MinAccess: "user" everyone, "admin" level >=
    adminLevel, "superadmin" level >= superLevel.

    Rank id is the engine usergroup (ply:GetUserGroup()), so other addons
    see it; IsAdmin / IsSuperAdmin follow the levels. Staff can only act
    on players ranked below them (and themselves), and only give ranks
    below their own.

        Admin.Rank(ply) / Admin.Level(ply) / Admin.Has(ply, perm, minAccess)
        Admin.CanTarget(ply, target)

    The rank id is all a client needs: the engine networks the usergroup,
    so these functions give the same answer on both sides.
    The "admin" config module is protected: it can't be changed from the
    in-game Server settings page (a bad value could lock staff out). Set it
    in a host config file instead.
]]

Rhylib.Admin = Rhylib.Admin or {}
local Admin = Rhylib.Admin
local Config = Rhylib.Config

-- Default ranks. A rank's id is the usergroup name other addons see;
-- "user" must exist (everyone without a stored rank gets it).
Config.Register("admin", "ranks", {
    { id = "user", name = "User", level = 0, color = Color(200, 200, 200) },
    { id = "trialmod", name = "Trial Moderator", level = 30, color = Color(120, 200, 140),
      perms = { "goto", "bring", "return", "freeze", "unfreeze", "mute", "unmute", "gag", "ungag", "kick", "warn",
                "respawn", "logs", "spectate", "noclip.self", "info", "tell", "free", "rhylib.chat.admin" } },
    { id = "gamemaster", name = "Gamemaster", level = 40, color = Color(230, 170, 70),
      perms = { "goto", "bring", "return", "teleport", "freeze", "unfreeze", "respawn", "slay",
                "noclip", "noclip.self", "god", "cloak", "notarget", "hp", "armor", "give", "spawn",
                "map", "cleanup", "announce", "setjob", "spectate", "info", "tell", "revive", "heal", "buddha",
                "scale", "speed", "jump", "model", "playsound", "stopsound", "slap", "ignite", "free", "infect", "cure",
                "freezeprops", "cleardecals", "call", "rhylib.chat.event", "rhylib.weapons.infammo", "rhylib.eod.gm" } },
    { id = "moderator", name = "Moderator", level = 50, color = Color(90, 170, 240), inherits = { "trialmod" },
      perms = { "ban", "slay", "teleport", "noclip", "god", "cloak", "notarget", "hp", "armor", "bans", "setjob",
                "jail", "unjail", "revive", "heal", "stopsound", "freezeprops", "cleardecals", "ignite", "hidecells" } },
    { id = "admin", name = "Admin", level = 70, color = Color(230, 80, 80), inherits = { "moderator", "gamemaster" },
      perms = { "permaban", "banid", "unban", "rank", "roster", "charreset", "unwarn", "money" } },
    { id = "superadmin", name = "Superadmin", level = 90, color = Color(200, 90, 230), perms = { "*" } },
    { id = "owner", name = "Owner", level = 100, color = Color(255, 210, 90), perms = { "*" } },
}, "Staff ranks: { id, name, level, color, inherits = { rank ids }, perms = { permission names } }")
-- owners: write the SteamID64s as strings ("7656119..."): a Lua number
-- that big loses its last digits and won't match.
Config.Register("admin", "owners", {}, "SteamID64s that are always Owner (set this first, or use the server console)")
Config.Register("admin", "adminLevel", 70, "Level from which ply:IsAdmin() is true and \"admin\" privileges are granted (70 = Admin; moderators get only what their rank lists)")
Config.Register("admin", "superLevel", 90, "Level from which ply:IsSuperAdmin() is true")
Config.Register("admin", "banMaxMinutes", 10080, "Longest ban without the permaban permission (minutes; 10080 = 7 days)")
Config.Register("admin", "echo", true, "Tell everyone about admin actions (kicks, bans, ...); staff always see them")
Config.Register("admin", "calls", {
    { id = "briefing", name = "Call to briefing", sub = "All personnel report to the briefing room", minutes = 0 },
    { id = "debrief", name = "Call to debrief", sub = "All personnel report for debrief", minutes = 0 },
    { id = "prep", name = "Mission prep", sub = "Grab your gear at the armoury", minutes = 10 },
    { id = "formup", name = "Form up", sub = "Fall in with your battalion", minutes = 0 },
}, "!call presets: { id, name, sub, minutes (default timer, 0 = none) }; !call custom <minutes> <text> for anything else")
Config.Register("admin", "callSound", "ambient/alarms/warningbell1.wav", "Sound when a call goes out")
Config.Register("admin", "callShowFor", 900, "Seconds an untimed call is still shown to players who join")
Config.Register("admin", "prefixes", { "!", "/" }, "Chat prefixes for admin commands (!kick ..., /kick ...)")

-- Admin.Cfg(key): a setting of config module "admin".
-- Example: Rhylib.Admin.Cfg("banMaxMinutes")   -- 10080
function Admin.Cfg(k) return Config.Get("admin", k) end

-- Ranks by id with resolved permission sets (rebuilt when the config changes).
-- `seen` stops a loop if two ranks inherit from each other.
local cache = { src = nil }
local function ranks()
    local list = Admin.Cfg("ranks") or {}
    if cache.src == list then return cache end
    local byId = {}
    for _, r in ipairs(list) do byId[r.id] = r end
    local sets = {}
    local function resolve(id, seen)
        if sets[id] then return sets[id] end
        local r = byId[id]
        local set = {}
        if not r or seen[id] then return set end
        seen[id] = true
        for _, p in ipairs(r.perms or {}) do set[p] = true end
        for _, parent in ipairs(r.inherits or {}) do
            for p in pairs(resolve(parent, seen)) do set[p] = true end
        end
        sets[id] = set
        return set
    end
    for id in pairs(byId) do resolve(id, {}) end
    local sorted = table.Copy(list)
    table.sort(sorted, function(a, b) return (a.level or 0) < (b.level or 0) end)
    cache = { src = list, byId = byId, sets = sets, sorted = sorted }
    return cache
end

-- Admin.Ranks(): every rank table, lowest level first (a copy; don't edit it).
function Admin.Ranks() return ranks().sorted end
-- Admin.RankById(id): the rank table with that id, or nil.
-- Example: Rhylib.Admin.RankById("moderator").level   -- 50
function Admin.RankById(id) return ranks().byId[id] end

local USER = { id = "user", name = "User", level = 0 }

-- The top rank ("owner", or the highest one if the config has no owner).
function Admin.TopRank()
    local c = ranks()
    return c.byId.owner or c.sorted[#c.sorted] or USER
end

-- Admin.Rank(ply): the player's rank table { id, name, level, color, ... }.
-- nil = the server console. Any other invalid player counts as a user.
-- A usergroup that isn't a configured rank also counts as user.
function Admin.Rank(ply)
    if ply == nil then return Admin.TopRank() end
    if not IsValid(ply) then return ranks().byId.user or USER end
    return ranks().byId[ply:GetUserGroup()] or ranks().byId.user or USER
end

-- Admin.Level(ply): the rank's level number (console = math.huge).
function Admin.Level(ply)
    if ply == nil then return math.huge end
    return Admin.Rank(ply).level or 0
end

local LEVEL_FOR = { user = function() return 0 end,
    admin = function() return Admin.Cfg("adminLevel") end,
    superadmin = function() return Admin.Cfg("superLevel") end }

-- Admin.Has(ply, perm, minAccess): true if the player's rank has the
-- permission (its own perms, inherited perms, or "*"). If not listed,
-- minAccess decides: "user" = everyone, "admin" = level >= adminLevel,
-- "superadmin" = level >= superLevel; nil = no. Console (nil) = always.
-- Works on both realms. Returns a boolean.
-- Example: if Rhylib.Admin.Has(ply, "kick") then ... end
-- Example: Rhylib.Admin.Has(ply, "rhylib.chat.event", "admin")
function Admin.Has(ply, perm, minAccess)
    if ply == nil then return true end
    if not IsValid(ply) then return false end
    local r = Admin.Rank(ply)
    local set = ranks().sets[r.id] or {}
    if set["*"] or set[perm] then return true end
    local need = LEVEL_FOR[minAccess or ""]
    if need then return (r.level or 0) >= need() end
    return false
end

-- Admin.CanTarget(ply, target): true if ply may act on target: it's
-- themselves, or target's level is lower. Console (nil) = always.
-- Example: if not Rhylib.Admin.CanTarget(admin, victim) then return end
function Admin.CanTarget(ply, target)
    if ply == nil or ply == target then return true end
    if not IsValid(ply) then return false end
    if not IsValid(target) then return false end
    return Admin.Level(ply) > Admin.Level(target)
end

-- Admin.RankColor(id): the rank's colour (grey if unknown). Used by the
-- scoreboard and menus.
function Admin.RankColor(id)
    local r = ranks().byId[id]
    return r and r.color or Color(200, 200, 200)
end

-- Engine flags follow our levels (other addons ask these). This replaces
-- the engine's own IsAdmin / IsSuperAdmin for every player.
local PLAYER = FindMetaTable("Player")
function PLAYER:IsAdmin() return IsValid(self) and Admin.Level(self) >= Admin.Cfg("adminLevel") end
function PLAYER:IsSuperAdmin() return IsValid(self) and Admin.Level(self) >= Admin.Cfg("superLevel") end

-- The noclip key (shared so prediction agrees): staff with "noclip" or
-- "noclip.self". Leaving noclip is always fine.
Rhylib.Hook.Add("PlayerNoClip", "admin.noclip", function(ply, want)
    if not want then return true end
    if Admin.Has(ply, "noclip") or Admin.Has(ply, "noclip.self") then return true end
end, -50)

-- CAMI: our ranks as usergroups, and we answer privilege checks.
-- Each rank is registered as inheriting from the rank just below it (by
-- level). That chain is only what CAMI reports to other addons; our own
-- checks use the `inherits` lists. Run at load and again at Initialize
-- (CAMI may load after this file).
local function registerCAMI()
    if not CAMI then return end
    local sorted = Admin.Ranks()
    for i, r in ipairs(sorted) do
        local parent = i > 1 and sorted[i - 1].id or "user"
        if r.id ~= "user" then CAMI.RegisterUsergroup({ Name = r.id, Inherits = parent }, "Rhylib") end
    end
end
Rhylib.Hook.Add("Initialize", "admin.cami", registerCAMI)
registerCAMI()

-- Any CAMI check (from ULX-style addons or Rhylib.Perms) is answered here
-- with Admin.Has, using the privilege's MinAccess ("admin" if unknown), and
-- also needs Admin.CanTarget when a target player is given. Returning true
-- tells CAMI the answer came from us.
Rhylib.Hook.Add("CAMI.PlayerHasAccess", "admin.cami", function(actor, priv, callback, target)
    if actor == nil or actor == NULL then callback(true, "server console") return true end
    if not IsValid(actor) then callback(false, "Rhylib") return true end
    local p = CAMI and CAMI.GetPrivilege and CAMI.GetPrivilege(priv)
    local ok = Admin.Has(actor, priv, p and p.MinAccess or "admin")
    if ok and IsValid(target) and target:IsPlayer() then ok = Admin.CanTarget(actor, target) end
    callback(ok, "Rhylib")
    return true
end)

-- Admin.ScaleHull(ply): sets the player's standing and crouching hull to
-- their !scale size (NW2Float rhylib_scale; 1 = the normal hull). Shared.
-- Hulls aren't networked, so both sides set them; the client keeps the
-- local player's in step (prediction). rhylib_medical calls this when a
-- downed player gets up, so the size survives being downed.
function Admin.ScaleHull(ply)
    local s = ply:GetNW2Float("rhylib_scale", 1)
    if s == 1 then ply:ResetHull() return end
    ply:SetHull(Vector(-16, -16, 0) * s, Vector(16, 16, 72) * s)
    ply:SetHullDuck(Vector(-16, -16, 0) * s, Vector(16, 16, 36) * s)
end

-- Client: apply a new size to the local player's hull. Skipped while
-- rhylib_medical has them on its small "downed" hull (rhylibHullDown).
if CLIENT then
    local applied = 1
    Rhylib.Hook.Add("Think", "admin.scale", function()
        local lp = LocalPlayer()
        if not IsValid(lp) or lp.rhylibHullDown then return end
        local s = lp:GetNW2Float("rhylib_scale", 1)
        if s ~= applied then
            applied = s
            Admin.ScaleHull(lp)
        end
    end)
end
