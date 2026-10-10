--[[
    Saved data upkeep (server console or a superadmin). Every purge only
    lists what it would remove; add "confirm" to remove it. Change the map
    after a purge so every module reads its data again.

        rhylib_data_stats
            rows and size per module.
        rhylib_purge_bots [confirm]
            everything saved for bots (load test bots, test dummies).
        rhylib_purge_maps [confirm]
            placements (armoury, spawns, computers, med bay, jail, training
            beacons) saved for maps the server no longer has.
        rhylib_purge_inactive <days> [confirm]
            everything saved for players not seen for that many days
            (character, inventory, locker, skills, ...), their roster
            memberships and clone numbers. Never ranks or bans (admin).
        rhylib_purge_battalion <name> / rhylib_purge_battalions [confirm]
            (rhylib_roster) old battalions.

    After removing, hook Rhylib.DataPurged runs so modules drop what they
    cached (roster characters, datapad).

    Checks: a player must be superadmin (IsSuperAdmin, not a permission).
    Bot rows: keys containing "9007199684" (bot SteamID64s) or exactly
    "BOT". Map modules: armoury, spawns, dp_places, med_places, mp_places,
    training (rows keyed by map name, removed when maps/<name>.bsp is
    missing; the current map never). Inactive: "seen" in module "char"
    (rhylib_roster) older than <days>; every row (not module admin) whose
    key holds that SteamID64, roster member lists, Data "char_nums"/"all".
    Example: rhylib_purge_inactive 90 (lists), then rhylib_purge_inactive 90 confirm
]]

local Data = Rhylib.Data
local TABLE = "rhylib_kv"

local MAP_MODULES = { "armoury", "spawns", "dp_places", "med_places", "mp_places", "training" }
local KEEP_MODULES = { admin = true }   -- (ranks and bans stay, whatever happens)

local function decode(str)
    local t = util.JSONToTable(str or "")
    return t and t.v
end

local function sayer(ply)
    return function(msg)
        if IsValid(ply) then ply:ChatPrint(msg) end
        print(msg)
    end
end

local function allowed(ply, say)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        say("Only superadmins (or the server console) can do that")
        return false
    end
    Data.Flush()   -- (pending writes first, so the queries see them)
    return true
end

local function finish(say, n)
    Data.Flush()
    hook.Run("Rhylib.DataPurged")
    say(string.format("[Rhylib] Removed %d saved rows. Change the map so every module reads its data again.", n))
end

-- Rows as { module, key }, optionally only some modules.
local function allKeys()
    return sql.Query("SELECT module, key FROM " .. TABLE) or {}
end

concommand.Add("rhylib_data_stats", function(ply)
    local say = sayer(ply)
    if not allowed(ply, say) then return end
    local rows = sql.Query("SELECT module, COUNT(*) AS n, SUM(LENGTH(value)) AS b FROM " .. TABLE .. " GROUP BY module ORDER BY b DESC") or {}
    local total, bytes = 0, 0
    say("[Rhylib] Saved data per module (rows, size):")
    for _, r in ipairs(rows) do
        local n, b = tonumber(r.n) or 0, tonumber(r.b) or 0
        total, bytes = total + n, bytes + b
        say(string.format("  %-14s %6d rows %9.1f KB", r.module, n, b / 1024))
    end
    say(string.format("  total          %6d rows %9.1f KB", total, bytes / 1024))
end)

-- Bot ids: SteamID64s from 90071996842377216 up, or "BOT".
local function isBotKey(key)
    return string.find(key, "9007199684", 1, true) ~= nil or key == "BOT"
end

concommand.Add("rhylib_purge_bots", function(ply, _, args)
    local say = sayer(ply)
    if not allowed(ply, say) then return end
    local hits = {}
    for _, r in ipairs(allKeys()) do
        if not KEEP_MODULES[r.module] and isBotKey(r.key) then hits[#hits + 1] = r end
    end
    if args[1] ~= "confirm" then
        return say(string.format("[Rhylib] %d saved rows belong to bots. Run rhylib_purge_bots confirm to remove them.", #hits))
    end
    for _, r in ipairs(hits) do Data.Delete(r.module, r.key) end
    finish(say, #hits)
end)

concommand.Add("rhylib_purge_maps", function(ply, _, args)
    local say = sayer(ply)
    if not allowed(ply, say) then return end
    local hits, maps = {}, {}
    for _, mod in ipairs(MAP_MODULES) do
        for _, r in ipairs(sql.Query("SELECT key FROM " .. TABLE .. " WHERE module = " .. sql.SQLStr(mod)) or {}) do
            if r.key ~= game.GetMap() and not file.Exists("maps/" .. r.key .. ".bsp", "GAME") then
                hits[#hits + 1] = { module = mod, key = r.key }
                maps[r.key] = true
            end
        end
    end
    local names = table.GetKeys(maps)
    table.sort(names)
    if args[1] ~= "confirm" then
        return say(string.format("[Rhylib] %d placement rows for maps not on the server%s. Run rhylib_purge_maps confirm to remove them.",
            #hits, #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
    end
    for _, r in ipairs(hits) do Data.Delete(r.module, r.key) end
    finish(say, #hits)
end)

concommand.Add("rhylib_purge_inactive", function(ply, _, args)
    local say = sayer(ply)
    if not allowed(ply, say) then return end
    local days = tonumber(args[1])
    if not days or days < 7 then return say("Usage: rhylib_purge_inactive <days, at least 7> [confirm]") end
    local cutoff = os.time() - days * 86400

    -- Who: characters last seen before the cutoff, not online now.
    local online = {}
    for _, p in ipairs(player.GetHumans()) do online[p:SteamID64() or ""] = true end
    local gone = {}
    local count = 0
    for _, r in ipairs(sql.Query("SELECT key, value FROM " .. TABLE .. " WHERE module = 'char'") or {}) do
        local c = decode(r.value)
        if istable(c) and (tonumber(c.seen) or 0) < cutoff and not online[r.key] then
            gone[r.key] = true
            count = count + 1
        end
    end

    -- Their rows: any key with their SteamID64 in it (sid, "s"..sid, "c"..sid ...).
    local hits = {}
    for _, r in ipairs(allKeys()) do
        if not KEEP_MODULES[r.module] then
            local sid = string.match(r.key, "7656119%d%d%d%d%d%d%d%d%d%d")
            if sid and gone[sid] then hits[#hits + 1] = r end
        end
    end
    if args[2] ~= "confirm" then
        return say(string.format("[Rhylib] %d players not seen for %d days, %d saved rows. Run rhylib_purge_inactive %d confirm to remove them.",
            count, days, #hits, days))
    end
    for _, r in ipairs(hits) do Data.Delete(r.module, r.key) end

    -- Battalion member lists and taken clone numbers.
    for _, r in ipairs(sql.Query("SELECT key, value FROM " .. TABLE .. " WHERE module = 'roster'") or {}) do
        local t = decode(r.value)
        if istable(t) then
            local changed = false
            for k in pairs(t) do
                if gone[string.sub(tostring(k), 2)] then
                    t[k] = nil
                    changed = true
                end
            end
            if changed then Data.Set("roster", r.key, t) end
        end
    end
    local nums = Data.Get("char_nums", "all")
    if istable(nums) then
        local changed = false
        for k, sid in pairs(nums) do
            if gone[tostring(sid)] then
                nums[k] = nil
                changed = true
            end
        end
        if changed then Data.Set("char_nums", "all", nums) end
    end
    finish(say, #hits)
end)
