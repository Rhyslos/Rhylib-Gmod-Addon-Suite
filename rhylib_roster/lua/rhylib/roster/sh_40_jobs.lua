--[[
    Jobs made in game (shared): staff create, edit and switch off DarkRP
    jobs from Staff > Jobs (cl_40_jobs.lua) instead of editing jobs.lua.
    Saving, checks and messages: sv_40_jobs.lua.

    What staff can do (permission rhylib.roster.jobs, superadmin):
      - create a job, or a whole battalion (category + Clone Trooper, Medic,
        Sergeant, Officer, Commander, like battalion() in jobs.lua)
      - edit any job, also the ones from jobs.lua (the file stays as it is;
        Reset goes back to the file version)
      - switch any job off (hidden, nobody can take it, players on it go to
        their home job) and on again
      - delete a job made in game (hidden at once, gone after a map change)
    The default job (cadet) and the CT job can't be switched off.

    How it stays in step: DarkRP numbers jobs in the order they're made,
    and the number is what the engine sends for each player's team, so
    server and clients must make the same jobs in the same order. Both
    realms make jobs.lua first (DarkRP), then ours in the saved order
    (hook postLoadCustomDarkRPItems). The server reads them from Data
    "roster_jobs"/"all"; a client uses its own copy from the last visit
    (data/rhylib/roster_jobs_<crc of the server address>.json) and fixes
    it when the server's list
    arrives (roster.jobs, asked for at InitPostEntity): jobs that differ
    are removed from the end and made again in the server's order. During
    a session jobs are only added at the end; a deleted job stays (hidden)
    until the map changes, so numbers never shift while people play.

    The state (server Data, roster.jobs payload and the client file):
      { static = how many jobs jobs.lua made (wire only; a client with a
                 different number leaves our jobs out)
        broken = { { cmd, name } }   saved jobs DarkRP refused (wire only)
        cats  = { { name, col = { r, g, b }, order } }   categories we made
        jobs  = { { d = def, dead = bool } }            our jobs, in order
                                                        (Data keeps only
                                                        the defs: { def })
        edits = { ["c" .. command] = def }               edited file jobs
        off   = { ["c" .. command] = true } }            switched off
    A def (all fields optional except name, cmd, models, cat):
      { cmd, name, col = { r, g, b }, models = { path }, desc, max, salary,
        order, admin (0 everyone, 1 admins, 2 superadmins), cat, weapons =
        { class }, bn, minRank, trained, prefix, medic, mp, commander, eod,
        qual, role ("heavy,pilot"), armor, hands, bountyHunter }
    They map onto the job fields the suite reads: bn -> battalion,
    trained -> needsTraining, prefix -> namePrefix, hands -> handsModel,
    role -> role (a list when it has commas), armor -> armor; see
    J.FIELDS. Keys are prefixed with "c": JSON turns bare number-like keys
    into numbers.

    Job flags set here: job.rhylibOff (switched off or deleted; also
    job.hidden for the job lists), job.rhylibDead (deleted),
    job.rhylibMade (made in game), job.rhylibEdited (file job with edits).

    Example (server, the same as Staff > Jobs > New job):
        Rhylib.Roster.Jobs.Save(nil, { cmd = "arc", name = "ARC Trooper",
            col = { 70, 120, 200 }, models = { "models/ct_trp/pm_ct_trp.mdl" },
            cat = "Recruits", trained = true, max = 4 }, true)
]]

local R = Rhylib.Roster
R.Jobs = R.Jobs or {}
local J = R.Jobs

-- J.CacheFile(): the client's copy of a server's job list (one per server).
function J.CacheFile()
    local addr = isfunction(game.GetIPAddress) and game.GetIPAddress() or ""
    return "rhylib/roster_jobs_" .. util.CRC(tostring(addr)) .. ".json"
end

-- { def key, job key, kind }. Kinds: string (always set), number, color,
-- models, list, opt (string; "" / nil leaves it off), flag (true or nil),
-- optnum (number or nil), role (comma list -> string or list).
J.FIELDS = {
    { "name", "name", "string" },
    { "col", "color", "color" },
    { "models", "model", "models" },
    { "desc", "description", "string" },
    { "max", "max", "number" },
    { "salary", "salary", "number" },
    { "order", "sortOrder", "number" },
    { "admin", "admin", "number" },
    { "cat", "category", "string" },
    { "weapons", "weapons", "list" },
    { "bn", "battalion", "opt" },
    { "minRank", "minRank", "opt" },
    { "trained", "needsTraining", "flag" },
    { "prefix", "namePrefix", "opt" },
    { "medic", "medic", "flag" },
    { "mp", "mp", "flag" },
    { "commander", "commander", "flag" },
    { "eod", "eod", "flag" },
    { "bountyHunter", "bountyHunter", "flag" },   -- (rhylib_bounty)
    { "qual", "qual", "opt" },
    { "role", "role", "role" },
    { "armor", "armor", "optnum" },
    { "hands", "handsModel", "opt" },
}

-- Roles of a battalion and their job titles (New battalion; same as
-- battalion() in jobs.lua).
J.BATTALION_ROLES = {
    { "trooper", "Clone Trooper", { order = 1, salary = 20, minRank = 1 } },
    { "medic", "Medic", { order = 2, salary = 25, max = 6, minRank = 1, medic = true } },
    { "sergeant", "Sergeant", { order = 3, salary = 30, max = 6, minRank = 4 } },
    { "officer", "Officer", { order = 4, salary = 40, max = 4, minRank = 6 } },
    { "commander", "Commander", { order = 5, salary = 50, max = 1, minRank = 9, commander = true } },
}
J.BATTALION_DESC = {
    trooper = "The backbone of the battalion.",
    medic = "Treats injuries, revives the downed and keeps medical records.",
    sergeant = "Leads a squad in the field.",
    officer = "Lieutenants and captains: plan and lead operations.",
    commander = "Commands the battalion and moderates its computer.",
}

local function key(cmd) return "c" .. tostring(cmd) end
J.Key = key

local function darkrp() return DarkRP ~= nil and RPExtraTeams ~= nil and DarkRP.createJob ~= nil end

-- J.FromJob(job): the def of a DarkRP job table (a fresh table).
function J.FromJob(job)
    local d = { cmd = job.command }
    for _, f in ipairs(J.FIELDS) do
        local v, kind = job[f[2]], f[3]
        if kind == "color" then
            local c = istable(v) and v or { r = 255, g = 255, b = 255 }
            d[f[1]] = { c.r or c[1] or 255, c.g or c[2] or 255, c.b or c[3] or 255 }
        elseif kind == "models" then
            d[f[1]] = istable(v) and table.Copy(v) or { tostring(v or "") }
        elseif kind == "list" then
            d[f[1]] = istable(v) and table.Copy(v) or {}
        elseif kind == "role" then
            d[f[1]] = istable(v) and table.concat(v, ",") or v
        elseif kind == "flag" then
            d[f[1]] = v and true or nil
        else
            d[f[1]] = v
        end
    end
    return d
end

-- The value a def field gives a job field (nil = leave the field off).
local function jobValue(kind, v)
    if kind == "color" then
        v = istable(v) and v or {}
        return Color(tonumber(v[1]) or 255, tonumber(v[2]) or 255, tonumber(v[3]) or 255, 255)
    elseif kind == "models" then
        return (istable(v) and #v > 0) and table.Copy(v) or { "models/player/kleiner.mdl" }
    elseif kind == "list" then
        return istable(v) and table.Copy(v) or {}
    elseif kind == "string" then
        return tostring(v or "")
    elseif kind == "number" then
        return tonumber(v) or 0
    elseif kind == "optnum" then
        return tonumber(v)
    elseif kind == "flag" then
        return v and true or nil
    elseif kind == "role" then
        if not isstring(v) or v == "" then return nil end
        if not string.find(v, ",", 1, true) then return v end
        local out = {}
        for r in string.gmatch(v, "[^,]+") do out[#out + 1] = r end
        return out
    end
    if v == "" then return nil end
    return v
end

-- J.ToJob(d): a new DarkRP job table from a def (for DarkRP.createJob).
function J.ToJob(d)
    local t = { command = d.cmd, vote = false, hasLicense = false, candemote = false, rhylibMade = true }
    for _, f in ipairs(J.FIELDS) do
        if f[1] ~= "name" then t[f[2]] = jobValue(f[3], d[f[1]]) end
    end
    t.salary = math.max(0, math.floor(t.salary or 0))
    t.max = math.max(0, t.max or 0)
    t.admin = math.Clamp(math.floor(t.admin or 0), 0, 2)
    return t
end

local function same(a, b)
    if istable(a) and istable(b) then
        if #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    return a == b
end

-- J.ApplyDef(t, d): write a def's fields onto job t (an existing job).
-- Keeps DarkRP's team name/colour and category lists in step.
function J.ApplyDef(t, d)
    local job = RPExtraTeams[t]
    if not job then return end
    local old = J.FromJob(job)
    for _, f in ipairs(J.FIELDS) do
        local k = f[1]
        if not same(old[k], d[k]) then
            if k == "cat" then
                local newCat = tostring(d.cat or "Other")
                if job.category ~= newCat then
                    if DarkRP.removeFromCategory then pcall(DarkRP.removeFromCategory, job, "jobs") end
                    if DarkRP.addToCategory then pcall(DarkRP.addToCategory, job, "jobs", newCat) else job.category = newCat end
                end
            else
                job[f[2]] = jobValue(f[3], d[k])
            end
        end
    end
    team.SetUp(t, job.name, job.color)
end

-- J.Category(name): the DarkRP jobs category with that name, or nil.
function J.Category(name)
    if not (DarkRP and DarkRP.getCategories) then return nil end
    for _, c in ipairs(DarkRP.getCategories().jobs or {}) do
        if c.name == name then return c end
    end
end

-- Make (or update) the categories we added.
local function ensureCats(cats)
    for _, c in ipairs(cats or {}) do
        if isstring(c.name) and c.name ~= "" then
            local col = istable(c.col) and Color(tonumber(c.col[1]) or 200, tonumber(c.col[2]) or 200, tonumber(c.col[3]) or 200, 255) or Color(200, 200, 200, 255)
            local have = J.Category(c.name)
            if have then
                have.color = col
                have.sortOrder = tonumber(c.order) or have.sortOrder
            else
                local ok, err = pcall(DarkRP.createCategory, {
                    name = c.name, categorises = "jobs", startExpanded = true, color = col,
                    canSee = function() return true end, sortOrder = tonumber(c.order) or 50,
                })
                if not ok then ErrorNoHalt("[Rhylib] Jobs: couldn't make category " .. c.name .. ": " .. tostring(err) .. "\n") end
            end
        end
    end
end

-- Remove jobs from team number i to the end (client, before making ours
-- again in the server's order). Last first so the list stays gap-free.
-- Returns false if DarkRP refused one (the caller stops: a gap or a
-- half-removed job would shift every later number).
local function removeFrom(i)
    local oldPanel = DarkRP.getF4MenuPanel
    DarkRP.getF4MenuPanel = function() return nil end   -- (removeJob would close that panel: ours is the pause menu)
    local okAll = true
    for n = #RPExtraTeams, i, -1 do
        local ok, err = pcall(DarkRP.removeJob, n)
        if not ok then
            ErrorNoHalt("[Rhylib] Jobs: couldn't remove job " .. n .. ": " .. tostring(err) .. "\n")
            okAll = false
            break
        end
    end
    DarkRP.getF4MenuPanel = oldPanel
    return okAll
end

local function setOff(job, off, dead, origHidden)
    job.rhylibOff = off or nil
    job.rhylibDead = dead or nil
    job.hidden = (off or origHidden) and true or nil
end

-- DarkRP's order: sortOrder (100 when missing), then name.
local function byOrder(a, b)
    local x, y = tonumber(a.sortOrder) or 100, tonumber(b.sortOrder) or 100
    if x ~= y then return x < y end
    return tostring(a.name) < tostring(b.name)
end

-- Sort the job categories and their jobs again (an order changed in game
-- shows at once, the same for everyone).
local function resort()
    local cats = DarkRP.getCategories().jobs
    if not cats then return end
    table.sort(cats, byOrder)
    for _, c in ipairs(cats) do
        if istable(c.members) then table.sort(c.members, byOrder) end
    end
end

local function warnOnce(id, text)
    J.warned = J.warned or {}
    if J.warned[id] then return end
    J.warned[id] = true
    ErrorNoHalt("[Rhylib] Jobs: " .. text .. "\n")
end

-- J.Apply(state): make the realm's jobs match a state (see the top). On the
-- server only ever adds at the end; on a client it may remove and remake
-- our jobs (only while they are the last jobs in the list). J.teams[i] =
-- the team number of our i-th job. Returns how many of ours exist.
function J.Apply(state)
    if not darkrp() or not J.static then return 0 end
    state = istable(state) and state or {}
    if CLIENT and state.static and tonumber(state.static) ~= J.static then
        warnOnce("static", "this client has " .. J.static .. " jobs from jobs.lua and the server " .. tostring(state.static)
            .. "; jobs made in game are left out (is the darkrpmodification folder the same on both?)")
        return 0
    end
    ensureCats(state.cats)

    local edits = istable(state.edits) and state.edits or {}
    local off = istable(state.off) and state.off or {}

    -- jobs.lua jobs: edits on top of the file version.
    J.orig = J.orig or {}
    J.origHidden = J.origHidden or {}
    for t = 1, J.static do
        local job = RPExtraTeams[t]
        if job then
            local k = key(job.command)
            if not J.orig[k] then
                J.orig[k] = J.FromJob(job)
                J.origHidden[k] = job.hidden and true or false
            end
            local d = istable(edits[k]) and edits[k] or J.orig[k]
            d.cmd = job.command
            J.ApplyDef(t, d)
            job.rhylibEdited = istable(edits[k]) or nil
            setOff(job, off[k] and true or false, false, J.origHidden[k])
        end
    end

    -- Ours: keep the common start, remove the rest (client), make the others.
    J.teams = J.teams or {}
    local list = istable(state.jobs) and state.jobs or {}
    local keep = 0
    for i, e in ipairs(list) do
        local t = J.teams[i]
        local job = t and RPExtraTeams[t]
        if job and istable(e.d) and job.command == e.d.cmd then keep = i else break end
    end
    if #J.teams > keep then
        if SERVER then
            warnOnce("order", "the server's job list changed order; that shouldn't happen")
            return #J.teams
        end
        -- Client: ours from keep + 1 on must be the last jobs, in one run.
        local first = J.teams[keep + 1]
        local tail = J.teams[#J.teams] == #RPExtraTeams
        for n = keep + 1, #J.teams do
            if J.teams[n] ~= first + (n - keep - 1) then tail = false end
        end
        if not tail then
            warnOnce("tail", "another addon made jobs after ours; jobs made in game can't be updated until you rejoin")
            return #J.teams
        end
        if not removeFrom(first) then return keep end
        for n = #J.teams, keep + 1, -1 do J.teams[n] = nil end
    end
    for i, e in ipairs(list) do
        local d = istable(e.d) and e.d or nil
        local t
        if d and i <= keep then
            t = J.teams[i]
            J.ApplyDef(t, d)
        elseif d then
            -- New: it takes the next number. A job DarkRP refuses is marked
            -- failed: the server drops it from the list it sends (so the
            -- clients' numbers match); a client stops there.
            local want = #RPExtraTeams + 1
            local ok, res = pcall(DarkRP.createJob, tostring(d.name or d.cmd), J.ToJob(d))
            if ok and res == want then
                t = want
                J.teams[#J.teams + 1] = want
            else
                e.failed = true
                ErrorNoHalt("[Rhylib] Jobs: couldn't make job " .. tostring(d.name) .. ": " .. tostring(ok and "it got another number" or res) .. "\n")
                if CLIENT then break end
            end
        end
        local job = t and RPExtraTeams[t]
        if job then
            job.rhylibMade = true
            setOff(job, (e.dead or off[key(d.cmd)]) and true or false, e.dead)
        end
    end
    resort()
    if R.WrapJobs then R.WrapJobs() end
    J.made = #J.teams
    hook.Run("Rhylib.JobsChanged")
    return J.made
end

-- J.Locked(t): jobs that can't be switched off: the default job, the
-- cadet and the CT job (players are sent there).
function J.Locked(t)
    return (GAMEMODE and t == GAMEMODE.DefaultTeam) or (TEAM_CADET ~= nil and t == TEAM_CADET) or (TEAM_CT ~= nil and t == TEAM_CT) or false
end

-- J.Info(t): what Staff > Jobs shows about job t: { made, edited, off,
-- dead, locked (can't be switched off) }.
function J.Info(t)
    local job = RPExtraTeams and RPExtraTeams[t]
    if not job then return {} end
    return { made = job.rhylibMade or false, edited = job.rhylibEdited or false, off = job.rhylibOff or false,
        dead = job.rhylibDead or false, locked = J.Locked(t) }
end

-- J.ByCommand(cmd): team number and job table of a command, or nil.
function J.ByCommand(cmd)
    for t, job in pairs(RPExtraTeams or {}) do
        if job.command == cmd then return t, job end
    end
end

-- Boot: after jobs.lua (DarkRP's postLoadCustomDarkRPItems, both realms).
-- The server reads Data, a client its own file; J.static = how many jobs
-- jobs.lua made. Not again on a Lua refresh (the jobs already exist).
function J.Boot()
    if J.booted or not darkrp() then return end
    J.booted = true
    J.static = #RPExtraTeams
    local state
    if SERVER then
        state = J.ServerState and J.ServerState() or nil
    else
        local raw = file.Read(J.CacheFile(), "DATA")
        state = raw and util.JSONToTable(raw) or nil
    end
    if state then J.Apply(state) end
end
Rhylib.Hook.Add("postLoadCustomDarkRPItems", "roster.jobs", function() J.Boot() end)

-- Encode / decode the state for the wire (compressed JSON). Unpack stops
-- at max bytes unpacked (default 256 KB).
function J.Pack(state) return util.Compress(util.TableToJSON(state or {}) or "{}") or "" end
function J.Unpack(raw, max)
    if not isstring(raw) or raw == "" then return nil end
    local js = util.Decompress(raw, max or 262144)
    return js and util.JSONToTable(js) or nil
end
