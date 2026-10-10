--[[
    Per-gun stats in Server settings (2026-10-07, owner: weapon accuracy
    and the like weren't in the settings page).

    Module "guns", one group of keys per Rhylib gun: <gun>_damage,
    _rpm, _boltSpeed, _reload, _spreadHip, _spreadAim, _bloomPerShot,
    _bloomMax, _kickMain, _kickSide, _recoilUp, _recoilSide.
    The defaults are the numbers in each weapon file. A change is written
    into the gun's class table (weapons.GetStored: new weapons and the
    training copy, which inherits it) and into every weapon of those
    classes that already exists, on the server and every client; the C
    stats panel reads the same.

    Head / limb multipliers are global: weapons headMult / limbMult.
    Grenades, the toolgun, the riot shield (it is a DC-15S) and training
    copies have no keys of their own (and any gun with SWEP.NoGunStats).

    Realm: shared (both realms write the same values). Note: the keys
    are registered at InitPostEntity, so a host config file sets them
    with Rhylib.Config.Set("guns", "dc15a_damage", 40) like any other key.
]]

local W = Rhylib.Weapons
local Config = Rhylib.Config

local GS = W.GunStats or {}
W.GunStats = GS
GS.defaults = GS.defaults or {}   -- [class] = { [stat] = number }
GS.src = GS.src or {}             -- [class] = the stored table the defaults came from
GS.classOf = GS.classOf or {}     -- [config key] = { class, stat }

-- { stat, label, field, sub-table or nil }
local STATS = {
    { "damage", "damage per bolt", "Damage" },
    { "rpm", "fire rate (rounds per minute, 1-6000)", "FireRate" },
    { "boltSpeed", "bolt speed (units per second, up to 32767)", "BoltSpeed" },
    { "reload", "reload time (seconds)", "ReloadTime" },
    { "spreadHip", "resting cone, hip-fire (degrees)", "hip", "Spread" },
    { "spreadAim", "resting cone, aiming (degrees)", "aim", "Spread" },
    { "bloomPerShot", "bloom added per shot (degrees)", "bloomPerShot", "Spread" },
    { "bloomMax", "most bloom (degrees, up to 5.1)", "bloomMax", "Spread" },
    { "kickMain", "crosshair kick on the nearest arc (degrees)", "kickMain", "Spread" },
    { "kickSide", "crosshair kick on the other arcs (degrees)", "kickSide", "Spread" },
    { "recoilUp", "view kick up per shot (degrees)", "up", "Recoil" },
    { "recoilSide", "view kick sideways per shot (degrees)", "side", "Recoil" },
}

local function shortName(class) return (string.gsub(class, "^rhylib_", "")) end
local function key(class, stat) return shortName(class) .. "_" .. stat end

-- Guns that get keys.
local function eligible(class, merged)
    if not (string.StartWith(class, "rhylib_") and weapons.IsBasedOn(class, "rhylib_base")) then return false end
    if class == "rhylib_base" or not merged then return false end
    if merged.Training or merged.ToolGun or merged.RiotShield or merged.NoGunStats then return false end
    return isnumber(merged.Damage) and isnumber(merged.FireRate)
end

local function readStat(merged, s)
    local t = s[4] and merged[s[4]] or merged
    return istable(t) and t[s[3]] or nil
end

-- Write one value into the class table (its own copy of Spread/Recoil, so
-- a gun that inherits the base's table doesn't change every other gun).
-- Limits (a 0 fire rate would never fire; bolt speed, bloom and kicks
-- are packed into fixed bits on the wire).
local LIMITS = {
    rpm = { 1, 6000 }, reload = { 0.05, 30 }, boltSpeed = { 100, 32767 }, damage = { 0, 10000 },
    bloomMax = { 0, 5.1 }, bloomPerShot = { 0, 5.1 }, kickMain = { 0, 10.2 }, kickSide = { 0, 10.2 },
}

local function writeStat(class, s, v)
    local lim = LIMITS[s[1]]
    if lim then v = math.Clamp(v, lim[1], lim[2]) end
    local stored = weapons.GetStored(class)
    if not stored then return end
    if s[4] then
        if rawget(stored, s[4]) == nil then
            local merged = weapons.Get(class)
            stored[s[4]] = table.Copy(merged and merged[s[4]] or {})
        end
        stored[s[4]][s[3]] = v
    else
        stored[s[3]] = v
    end
    -- Weapons that already exist hold their own copy of the class table
    -- (weapons.Get): update them too, and those of classes built on this
    -- one (training copies), unless that class sets the value itself.
    for _, e in ipairs(ents.FindByClass("rhylib_*")) do
        local c = e:IsWeapon() and e:GetClass()
        if c and (c == class or weapons.IsBasedOn(c, class)) then
            -- (any class between it and this one that sets the value keeps
            -- it: the Republic shield inherits the riot shield's own Spread)
            local field = s[4] or s[3]
            local ownsIt, cc, guard = false, c, 0
            while cc and cc ~= class and guard < 16 do
                local st = weapons.GetStored(cc)
                if not st then break end
                if rawget(st, field) ~= nil then ownsIt = true break end
                cc, guard = st.Base, guard + 1
            end
            if not ownsIt then
                if s[4] then
                    local t = e[s[4]]
                    if istable(t) then t[s[3]] = v end
                else
                    e[s[3]] = v
                end
            end
        end
    end
end

-- GS.Apply(class): writes every saved "guns" setting of that gun into
-- its class table and live weapons.
function GS.Apply(class)
    local d = GS.defaults[class]
    if not d then return end
    for _, s in ipairs(STATS) do
        if d[s[1]] ~= nil then
            local v = Config.Get("guns", key(class, s[1]))
            if isnumber(v) then writeStat(class, s, v) end
        end
    end
end

-- Register every gun's keys (defaults from the weapon files) and apply
-- what Server settings already holds.
function GS.Setup()
    for _, w in ipairs(weapons.GetList()) do
        local class = w.ClassName
        local stored = class and weapons.GetStored(class)
        local merged = stored and weapons.Get(class)
        if stored and eligible(class, merged) then
            -- (defaults only from a fresh class table: not after we wrote into it)
            if GS.src[class] ~= stored or not GS.defaults[class] then
                local d = {}
                for _, s in ipairs(STATS) do
                    local v = readStat(merged, s)
                    if isnumber(v) then d[s[1]] = v end
                end
                GS.defaults[class], GS.src[class] = d, stored
            end
            local name = merged.PrintName or class
            for _, s in ipairs(STATS) do
                local v = GS.defaults[class][s[1]]
                if v ~= nil then
                    local k = key(class, s[1])
                    Config.Register("guns", k, v, name .. ": " .. s[2])
                    GS.classOf[k] = { class, s }
                end
            end
            GS.Apply(class)
        end
    end
end

Rhylib.Hook.Add("InitPostEntity", "weapons.gunstats", GS.Setup)
Rhylib.Hook.Add("OnReloaded", "weapons.gunstats", function() timer.Simple(0, GS.Setup) end)
if weapons.GetStored("rhylib_base") then GS.Setup() end   -- (Lua refresh)

-- A change on the settings page (or its reset): write it in at once.
Rhylib.Hook.Add("Rhylib.ConfigChanged", "weapons.gunstats", function(m, k, v)
    if m ~= "guns" then return end
    local e = GS.classOf[k]
    if not e then return end
    if v == nil then v = GS.defaults[e[1]] and GS.defaults[e[1]][e[2][1]] end
    if isnumber(v) then writeStat(e[1], e[2], v) end
end)
