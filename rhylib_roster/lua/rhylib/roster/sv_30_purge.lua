--[[
    Removing an old battalion's saved data (owner 2026-10-05: the 501st and
    327th were replaced by the 212th and 41st).

        rhylib_purge_battalion <name>     server console or a superadmin
        rhylib_purge_battalions [confirm] every battalion with saved data
                                          that no job uses any more (lists
                                          them; "confirm" removes them)

    Deletes every saved row keyed by the battalion's name (roster, roster
    log, datapad logs/board/orders/LOA/applications/info/missions/stats/
    bans), takes its members out of it (characters keep everything else,
    rank back to none), drops it from the datapad's battalion index and
    clears it from saved spawn points and computers on every map. Change
    the map afterwards so cached copies (datapad) are read again.
]]

local R = Rhylib.Roster
local Data = Rhylib.Data
local TABLE = "rhylib_kv"   -- (rhylib_core sv_10_data.lua)

local function decode(str)
    local t = util.JSONToTable(str or "")
    return t and t.v
end

local function purge(bn, say)
    Data.Flush()   -- (pending writes first, so the queries see them)
    local q = sql.SQLStr(bn)

    -- Rows keyed by the battalion's name, in any module.
    local rows = sql.Query("SELECT module FROM " .. TABLE .. " WHERE key = " .. q) or {}
    for _, row in ipairs(rows) do Data.Delete(row.module, bn) end

    -- Members: out of the battalion.
    local members = 0
    for _, row in ipairs(sql.Query("SELECT key, value FROM " .. TABLE .. " WHERE module = 'char'") or {}) do
        local c = decode(row.value)
        if istable(c) and c.bn == bn then
            c.bn, c.r = "", 0
            R.SaveChar(row.key, c)
            members = members + 1
            local p = player.GetBySteamID64(row.key)
            if IsValid(p) then
                R.Publish(p)
                -- (out of that battalion's job too)
                local job = RPExtraTeams and RPExtraTeams[p:Team()]
                if job and job.battalion == bn and p.changeTeam and GAMEMODE.DefaultTeam then
                    p:changeTeam(GAMEMODE.DefaultTeam, true)
                end
                if R.ApplyName then R.ApplyName(p) end
            end
        end
    end

    -- Applications to it.
    for _, row in ipairs(sql.Query("SELECT key, value FROM " .. TABLE .. " WHERE module = 'dp_myapp'") or {}) do
        local a = decode(row.value)
        if istable(a) and a.bn == bn then Data.Delete("dp_myapp", row.key) end
    end

    -- Datapad index of battalions with logs.
    local idx = Data.Get("dp_log", "__index")
    if istable(idx) then
        for i = #idx, 1, -1 do
            if idx[i] == bn then table.remove(idx, i) end
        end
        Data.Set("dp_log", "__index", idx)
    end

    -- Saved spawn points and computers on every map.
    local places = 0
    for _, mod in ipairs({ "spawns", "dp_places" }) do
        for _, row in ipairs(sql.Query("SELECT key, value FROM " .. TABLE .. " WHERE module = " .. sql.SQLStr(mod)) or {}) do
            local list = decode(row.value)
            local changed = false
            if istable(list) then
                for _, r in ipairs(list) do
                    if istable(r) and r.bn == bn then
                        r.bn = ""
                        changed = true
                        places = places + 1
                    end
                end
            end
            if changed then Data.Set(mod, row.key, list) end
        end
    end
    -- (and the ones standing on this map now)
    for _, e in ipairs(ents.GetAll()) do
        if e.GetBattalion and e.SetBattalion and e:GetBattalion() == bn then e:SetBattalion("") end
    end

    Data.Flush()
    -- (caches of what was read, e.g. the datapad's: forget them, so nothing old is written back)
    hook.Run("Rhylib.DataPurged")
    say(string.format("[Rhylib] Removed the %s: %d saved rows, %d members taken out, %d spawn points / computers cleared. Change the map now.",
        bn, #rows, members, places))
end

concommand.Add("rhylib_purge_battalion", function(ply, _, args)
    local say = function(msg) if IsValid(ply) then ply:ChatPrint(msg) end print(msg) end
    if IsValid(ply) and not ply:IsSuperAdmin() then return say("Only superadmins (or the server console) can do that") end
    local bn = string.Trim(table.concat(args, " "))
    if bn == "" then return say("Usage: rhylib_purge_battalion <battalion name>, e.g. rhylib_purge_battalion 501st") end
    purge(bn, say)
end)

-- Battalion-keyed modules (datapad and roster).
local BN_MODULES = { "roster", "roster_log", "dp_log", "dp_board", "dp_ver", "dp_ord", "dp_orders", "dp_loa",
    "dp_apps", "dp_info", "dp_mis", "dp_misarc", "dp_stats", "dp_ban" }

-- Battalions the jobs still have (their battalion field and category).
local function current()
    local set = {}
    for _, j in pairs(RPExtraTeams or {}) do
        if isstring(j.battalion) and j.battalion ~= "" then set[j.battalion] = true end
        if isstring(j.category) and j.category ~= "" then set[j.category] = true end
    end
    return set
end

concommand.Add("rhylib_purge_battalions", function(ply, _, args)
    local say = function(msg) if IsValid(ply) then ply:ChatPrint(msg) end print(msg) end
    if IsValid(ply) and not ply:IsSuperAdmin() then return say("Only superadmins (or the server console) can do that") end
    local keep = current()
    local quoted = {}
    for i, m in ipairs(BN_MODULES) do quoted[i] = sql.SQLStr(m) end
    local found = {}
    for _, row in ipairs(sql.Query("SELECT DISTINCT key FROM " .. TABLE .. " WHERE module IN (" .. table.concat(quoted, ",") .. ")") or {}) do
        local k = row.key
        if string.sub(k, 1, 2) ~= "__" and not keep[k] then found[#found + 1] = k end
    end
    if #found == 0 then return say("[Rhylib] No saved battalions without a job.") end
    if args[1] ~= "confirm" then
        return say("[Rhylib] Battalions with saved data but no job: " .. table.concat(found, ", ") .. ". Run rhylib_purge_battalions confirm to remove them.")
    end
    for _, bn in ipairs(found) do purge(bn, say) end
end)
