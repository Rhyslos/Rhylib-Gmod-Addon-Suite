--[[
    Staff ranks and permissions (shared).

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
]]

Rhylib.Admin = Rhylib.Admin or {}
local Admin = Rhylib.Admin
local Config = Rhylib.Config

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
                "freezeprops", "cleardecals", "call", "rhylib.chat.event", "rhylib.weapons.infammo" } },
    { id = "moderator", name = "Moderator", level = 50, color = Color(90, 170, 240), inherits = { "trialmod" },
      perms = { "ban", "slay", "teleport", "noclip", "god", "cloak", "notarget", "hp", "armor", "bans", "setjob",
                "jail", "unjail", "revive", "heal", "stopsound", "freezeprops", "cleardecals", "ignite", "hidecells" } },
    { id = "admin", name = "Admin", level = 70, color = Color(230, 80, 80), inherits = { "moderator", "gamemaster" },
      perms = { "permaban", "banid", "unban", "rank", "roster", "charreset", "unwarn", "money" } },
    { id = "superadmin", name = "Superadmin", level = 90, color = Color(200, 90, 230), perms = { "*" } },
    { id = "owner", name = "Owner", level = 100, color = Color(255, 210, 90), perms = { "*" } },
}, "Staff ranks: { id, name, level, color, inherits = { rank ids }, perms = { permission names } }")
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

function Admin.Cfg(k) return Config.Get("admin", k) end

-- Ranks by id with resolved permission sets (rebuilt when the config changes).
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

function Admin.Ranks() return ranks().sorted end
function Admin.RankById(id) return ranks().byId[id] end

local USER = { id = "user", name = "User", level = 0 }

-- The top rank ("owner", or the highest one if the config has no owner).
function Admin.TopRank()
    local c = ranks()
    return c.byId.owner or c.sorted[#c.sorted] or USER
end

-- nil = the server console. Any other invalid player counts as a user.
function Admin.Rank(ply)
    if ply == nil then return Admin.TopRank() end
    if not IsValid(ply) then return ranks().byId.user or USER end
    return ranks().byId[ply:GetUserGroup()] or ranks().byId.user or USER
end

function Admin.Level(ply)
    if ply == nil then return math.huge end
    return Admin.Rank(ply).level or 0
end

local LEVEL_FOR = { user = function() return 0 end,
    admin = function() return Admin.Cfg("adminLevel") end,
    superadmin = function() return Admin.Cfg("superLevel") end }

-- minAccess: for privileges the rank doesn't list ("user", "admin", "superadmin").
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

-- Act on yourself, or on someone ranked below you.
function Admin.CanTarget(ply, target)
    if ply == nil or ply == target then return true end
    if not IsValid(ply) then return false end
    if not IsValid(target) then return false end
    return Admin.Level(ply) > Admin.Level(target)
end

function Admin.RankColor(id)
    local r = ranks().byId[id]
    return r and r.color or Color(200, 200, 200)
end

-- Engine flags follow our levels (other addons ask these).
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

Rhylib.Hook.Add("CAMI.PlayerHasAccess", "admin.cami", function(actor, priv, callback, target)
    if actor == nil or actor == NULL then callback(true, "server console") return true end
    if not IsValid(actor) then callback(false, "Rhylib") return true end
    local p = CAMI and CAMI.GetPrivilege and CAMI.GetPrivilege(priv)
    local ok = Admin.Has(actor, priv, p and p.MinAccess or "admin")
    if ok and IsValid(target) and target:IsPlayer() then ok = Admin.CanTarget(actor, target) end
    callback(ok, "Rhylib")
    return true
end)

-- !scale size (NW2Float rhylib_scale): hulls aren't networked, so both
-- sides set them; the client keeps the local player's in step (prediction).
function Admin.ScaleHull(ply)
    local s = ply:GetNW2Float("rhylib_scale", 1)
    if s == 1 then ply:ResetHull() return end
    ply:SetHull(Vector(-16, -16, 0) * s, Vector(16, 16, 72) * s)
    ply:SetHullDuck(Vector(-16, -16, 0) * s, Vector(16, 16, 36) * s)
end

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
