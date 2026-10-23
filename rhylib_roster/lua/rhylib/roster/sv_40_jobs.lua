--[[
    Jobs made in game (server): saving, checks and the messages for
    Staff > Jobs. How jobs are made and kept in step: sh_40_jobs.lua.

    Data: "roster_jobs"/"all" = { cats, jobs = { def }, edits, off }
    (see sh_40_jobs.lua). Permission: rhylib.roster.jobs (superadmin).

    Messages:
      roster.jobsreq  client -> server (empty): send me the job list
                      (asked at InitPostEntity); rate 1/s
      roster.jobs     server -> client(s): UInt 32 length + the state
                      (J.Pack: compressed JSON); to the asker, and to
                      everyone after every change
      roster.jobedit  client -> server: op (UInt 3), UInt 16 length +
                      compressed JSON payload; rate 4/s
                        0 save      { cmd, new (bool), newCat (bool), d = def }
                        1 on / off  { cmd, off (bool) }
                        2 delete    { cmd }   (jobs made in game)
                        3 reset     { cmd }   (file jobs: back to jobs.lua)
                        4 battalion { name, prefix, col, mp (bool),
                                      models = { trooper, medic, sergeant,
                                      officer, commander } }
      roster.jobmsg   server -> client: ok (bool), message (string)

    After a change: the jobs are made / updated here, saved, sent to
    everyone, and players whose job is now off or out of reach go to their
    home job (R.CheckJob).
]]

local R = Rhylib.Roster
local J = R.Jobs
local Data = Rhylib.Data
local Net = Rhylib.Net

for _, n in ipairs({ "roster.jobs", "roster.jobmsg" }) do Net.Register(n) end
Rhylib.Perms.Register("rhylib.roster.jobs", "superadmin", "Create, edit and switch off jobs in game (Staff > Jobs)")

J.OP_SAVE, J.OP_OFF, J.OP_DELETE, J.OP_RESET, J.OP_BATTALION = 0, 1, 2, 3, 4

J.live = J.live or {}   -- our jobs this session, in team order: { d = def, dead = bool }

local function load()
    local t = Data.Get("roster_jobs", "all")
    t = istable(t) and t or {}
    for _, k in ipairs({ "cats", "jobs", "edits", "off" }) do
        if not istable(t[k]) then t[k] = {} end
    end
    return t
end

local function save() Data.Set("roster_jobs", "all", J.data) end

-- J.WireState(): the state as clients get it (see sh_40_jobs.lua).
function J.WireState()
    local d = J.data or {}
    -- Saved jobs DarkRP refused this session (Staff > Jobs lists them so
    -- they can be deleted).
    local broken = {}
    for _, def in ipairs(d.jobs or {}) do
        local live = false
        for _, e in ipairs(J.live) do if e.d == def then live = true break end end
        if not live then broken[#broken + 1] = { cmd = def.cmd, name = def.name } end
    end
    return { static = J.static, broken = broken, cats = d.cats or {}, jobs = J.live, edits = d.edits or {}, off = d.off or {} }
end

-- Called once by J.Boot (after jobs.lua): read Data, start the session list.
function J.ServerState()
    J.data = load()
    J.live = {}
    for _, d in ipairs(J.data.jobs) do
        if istable(d) and isstring(d.cmd) then J.live[#J.live + 1] = { d = d } end
    end
    return J.WireState()
end

-- Jobs DarkRP refused to make aren't in the session list (so the numbers
-- the clients work out stay right); they stay saved and are tried again
-- next map.
Rhylib.Hook.Add("Rhylib.JobsChanged", "roster.jobs.failed", function()
    for i = #J.live, 1, -1 do
        if J.live[i].failed then table.remove(J.live, i) end
    end
end)

-- J.Send(ply): the job list to one player, or everyone (ply nil).
function J.Send(ply)
    local raw = J.Pack(J.WireState())
    if #raw > 60000 then ErrorNoHalt("[Rhylib] Jobs: the job list is " .. #raw .. " bytes, close to the net limit\n") end
    Net.Start("roster.jobs")
    net.WriteUInt(#raw, 32)
    net.WriteData(raw, #raw)
    if ply then net.Send(ply) else net.Broadcast() end
end

Net.Receive("roster.jobsreq", function(ply) J.Send(ply) end, { rate = 1, burst = 3 })

--------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------

-- A string without control characters (keepLines: newlines stay), at most
-- max bytes; nil = "" ; anything else (or too long) -> nil.
local function str(v, max, keepLines)
    if v == nil then return "" end
    if not isstring(v) then return nil end
    v = string.gsub(v, "\r", "")
    v = string.gsub(v, keepLines and "[%z\1-\9\11-\31\127]" or "%c", "")
    v = string.Trim(v)
    if #v > max then return nil end
    return v
end

local function goodModel(m)
    if not isstring(m) then return false end
    m = string.lower(string.Trim((string.gsub(m, "\\", "/"))))
    if not string.match(m, "^models/[%w_%-%./ ]+%.mdl$") or string.find(m, "..", 1, true) then return false end
    if not (util.IsValidModel(m) or file.Exists(m, "GAME")) then return false end
    return m
end

local function nameTaken(name, exceptCmd)
    name = string.lower(name)
    for _, job in pairs(RPExtraTeams or {}) do
        if job.command ~= exceptCmd and not job.rhylibDead and string.lower(job.name or "") == name then return true end
    end
    return false
end

-- J.CleanCmd(cmd): a new job's command: lower case, 2-24 of a-z 0-9 _,
-- not used by a job or a DarkRP chat command. Returns cmd, or nil + why.
function J.CleanCmd(cmd)
    if not isstring(cmd) then return nil, "Give the job a command" end
    cmd = string.lower(string.Trim(cmd))
    if not string.match(cmd, "^[a-z0-9_]+$") or #cmd < 2 or #cmd > 24 then
        return nil, "The command must be 2-24 letters, digits or _ (no spaces)"
    end
    local t, job = J.ByCommand(cmd)
    if t then
        if job.rhylibDead then return nil, "A deleted job still uses /" .. cmd .. " until the next map change" end
        return nil, "/" .. cmd .. " is already the command of " .. tostring(job.name)
    end
    if DarkRP.getChatCommand and (DarkRP.getChatCommand(cmd) or DarkRP.getChatCommand("vote" .. cmd)) then
        return nil, "/" .. cmd .. " is already a chat command"
    end
    for _, c in ipairs(R.MONEY_COMMANDS or {}) do
        if c == cmd then return nil, "/" .. cmd .. " is a DarkRP money command" end
    end
    for _, d in ipairs(J.data and J.data.jobs or {}) do
        if d.cmd == cmd then return nil, "A saved job already uses /" .. cmd end
    end
    return cmd
end

-- J.Clean(src, cmd): a checked def from what a client sent (cmd = the
-- job's command, for the "name already used" check). Returns the def, or
-- nil and the reason. Every model must exist on the server.
function J.Clean(src, cmd)
    if not istable(src) then return nil, "Bad data" end
    local d = {}
    d.name = str(src.name, 48)
    if not d.name or d.name == "" then return nil, "Give the job a name (48 characters at most)" end
    if nameTaken(d.name, cmd) then return nil, "Another job is already called " .. d.name end

    local c = istable(src.col) and src.col or {}
    d.col = {}
    for i = 1, 3 do d.col[i] = math.Clamp(math.floor(tonumber(c[i]) or 150), 0, 255) end

    if not istable(src.models) or #src.models == 0 then return nil, "Add at least one player model" end
    d.models = {}
    for i, m in ipairs(src.models) do
        if i > 8 then return nil, "8 models at most" end
        local ok = goodModel(m)
        if not ok then return nil, "Model not found on the server: " .. tostring(m) end
        d.models[#d.models + 1] = ok
    end

    d.desc = str(src.desc, 600, true)
    if not d.desc then return nil, "The description is too long (600 characters at most)" end
    -- max: a whole number, or between 0 and 1 a share of the players (DarkRP)
    local max = math.max(0, tonumber(src.max) or 0)
    if max > 0 and max < 1 then d.max = math.max(0.01, math.floor(max * 100 + 0.5) / 100) else d.max = math.min(math.floor(max), 128) end
    d.salary = math.Clamp(math.floor(tonumber(src.salary) or 0), 0, 100000)
    d.order = math.Clamp(math.floor(tonumber(src.order) or 100), 0, 1000)
    d.admin = math.Clamp(math.floor(tonumber(src.admin) or 0), 0, 2)

    d.cat = str(src.cat, 48)
    if not d.cat or d.cat == "" then return nil, "Pick a category" end

    d.weapons = {}
    if istable(src.weapons) then
        for i, w in ipairs(src.weapons) do
            if i > 10 then return nil, "10 spawn weapons at most" end
            if not isstring(w) or not string.match(w, "^[%w_%.%-]+$") or #w > 64 then return nil, "Bad weapon class: " .. tostring(w) end
            d.weapons[#d.weapons + 1] = w
        end
    end

    local bn = str(src.bn, 48)
    if not bn then return nil, "The battalion name is too long" end
    if bn ~= "" then
        d.bn = bn
        local rank = isstring(src.minRank) and R.RankIndex(src.minRank) or nil
        d.minRank = R.RankPrefix(rank or 1)
    end

    d.trained = src.trained == true or nil
    local prefix = str(src.prefix, 6)
    if not prefix or not string.match(prefix, "^%w*$") then return nil, "The name prefix is 6 letters or digits at most" end
    d.prefix = prefix ~= "" and prefix or nil
    for _, f in ipairs({ "medic", "mp", "commander", "eod", "bountyHunter" }) do d[f] = src[f] == true or nil end

    local qual = str(src.qual, 32) or ""
    if qual ~= "" then
        local found = false
        for _, q in ipairs(R.Quals()) do if q[1] == qual then found = true end end
        if not found then return nil, "Unknown qualification " .. qual end
        d.qual = qual
    end

    local role = str(src.role, 128)
    if not role or not string.match(role, "^[%w_, ]*$") then return nil, "Armoury roles: ids separated by commas" end
    role = string.gsub(role, "%s", "")
    role = string.gsub(role, ",+", ",")
    role = string.gsub(role, "^,", "")
    role = string.gsub(role, ",$", "")
    d.role = role ~= "" and role or nil

    if src.armor ~= nil and src.armor ~= "" then
        local a = tonumber(src.armor)
        if not a then return nil, "Spawn armour must be a number" end
        d.armor = math.Clamp(math.floor(a), 0, 1000)
    end
    local hands = str(src.hands, 200) or ""
    if hands ~= "" then
        local ok = goodModel(hands)
        if not ok then return nil, "Hands model not found on the server: " .. hands end
        d.hands = ok
    end
    return d
end

--------------------------------------------------------------------------
-- Changes
--------------------------------------------------------------------------

local function reply(ply, ok, msg)
    if not IsValid(ply) then return end
    Net.Start("roster.jobmsg")
    net.WriteBool(ok)
    net.WriteString(msg or "")
    net.Send(ply)
end

local function nextCatOrder()
    local top = 0
    for _, c in ipairs(DarkRP.getCategories().jobs or {}) do top = math.max(top, tonumber(c.sortOrder) or 0) end
    return math.min(top + 1, 1000)
end

-- Make sure category name exists (made here when make is true).
local function needCat(name, col, make)
    if J.Category(name) then return true end
    if not make then return false end
    table.insert(J.data.cats, { name = name, col = table.Copy(col), order = nextCatOrder() })
    return true
end

-- Drop categories we made that no saved job uses any more (they go at the
-- next map change).
local function tidyCats()
    local used = {}
    for _, d in ipairs(J.data.jobs) do used[d.cat or ""] = true end
    for _, e in ipairs(J.live) do if istable(e.d) then used[e.d.cat or ""] = true end end   -- (deleted ones too: joiners still make them this session)
    for _, d in pairs(J.data.edits) do used[d.cat or ""] = true end
    for t = 1, J.static or 0 do
        local job = RPExtraTeams[t]
        if job and not J.data.edits[J.Key(job.command)] then used[job.category or ""] = true end
    end
    for i = #J.data.cats, 1, -1 do
        if not used[J.data.cats[i].name] then table.remove(J.data.cats, i) end
    end
end

-- After any change: make / update, save, tell everyone, move players.
local function commit()
    J.Apply(J.WireState())
    save()
    J.Send()
    for _, p in ipairs(player.GetHumans()) do
        local job = RPExtraTeams[p:Team()]
        if job and (job.rhylibOff or R.JobBlock(p, job)) and R.CheckJob then
            R.CheckJob(p)
        else
            R.ApplyName(p)
        end
    end
end

local function liveIndex(cmd)
    for i, e in ipairs(J.live) do
        if istable(e.d) and e.d.cmd == cmd then return i, e end
    end
end

local function dataIndex(cmd)
    for i, d in ipairs(J.data.jobs) do
        if d.cmd == cmd then return i, d end
    end
end

-- J.Save(ply, p, isNew): op 0. p = { cmd, newCat, d } (see the top).
-- Returns ok, message.
function J.Save(ply, p, isNew)
    local cmd = p.cmd
    local t, job
    if isNew then
        local why
        cmd, why = J.CleanCmd(cmd)
        if not cmd then return false, why end
    else
        t, job = J.ByCommand(cmd)
        if not job or job.rhylibDead then return false, "That job doesn't exist any more" end
    end
    local d, why = J.Clean(p.d, cmd)
    if not d then return false, why end
    d.cmd = cmd
    if not needCat(d.cat, d.col, p.newCat == true) then return false, "There's no category " .. d.cat end

    if isNew then
        table.insert(J.data.jobs, d)
        J.live[#J.live + 1] = { d = d }
        commit()
        local nt = J.ByCommand(cmd)
        if not nt then
            local i = dataIndex(cmd)
            if i then table.remove(J.data.jobs, i) end
            save()
            return false, "DarkRP refused the job (see the server console)"
        end
        return true, "Made " .. d.name .. " (/" .. cmd .. ")"
    end
    if job.rhylibMade then
        local _, e = liveIndex(cmd)
        local _, saved = dataIndex(cmd)
        local target = (e and e.d) or saved
        if not target then return false, "That job isn't saved" end
        for k in pairs(target) do target[k] = nil end
        for k, v in pairs(d) do target[k] = v end
        if e then e.d = target end
    else
        J.data.edits[J.Key(cmd)] = d
    end
    tidyCats()
    commit()
    return true, "Saved " .. d.name
end

local locked = J.Locked

-- J.SetOff(cmd, off): op 1. Returns ok, message.
function J.SetOff(cmd, off)
    local t, job = J.ByCommand(cmd)
    if not job or job.rhylibDead then return false, "That job doesn't exist any more" end
    if off and locked(t) then return false, job.name .. " is where new or homeless players go: it can't be switched off" end
    J.data.off[J.Key(cmd)] = off and true or nil
    commit()
    return true, job.name .. (off and " is switched off" or " is switched on")
end

-- J.Delete(cmd): op 2, jobs made in game only. Hidden now, gone next map.
function J.Delete(cmd)
    local t, job = J.ByCommand(cmd)
    if not job then
        -- A saved job DarkRP refused (listed under "couldn't be made").
        local i, d = dataIndex(cmd)
        if not i then return false, "That job doesn't exist any more" end
        table.remove(J.data.jobs, i)
        J.data.off[J.Key(cmd)] = nil
        tidyCats()
        save()
        J.Send()
        return true, tostring(d.name) .. " deleted"
    end
    if job.rhylibDead then return false, "That job is already deleted" end
    if not job.rhylibMade then return false, "Jobs from jobs.lua can only be switched off" end
    if locked(t) then return false, "That job can't be deleted" end
    local i = dataIndex(cmd)
    if i then table.remove(J.data.jobs, i) end
    J.data.off[J.Key(cmd)] = nil
    local _, e = liveIndex(cmd)
    if e then e.dead = true end
    tidyCats()
    commit()
    return true, job.name .. " deleted (gone after the next map change)"
end

-- J.Reset(cmd): op 3, back to the jobs.lua version of a file job.
function J.Reset(cmd)
    local _, job = J.ByCommand(cmd)
    if not job or job.rhylibMade then return false, "Only jobs from jobs.lua can be reset" end
    J.data.edits[J.Key(cmd)] = nil
    tidyCats()
    commit()
    return true, job.name .. " is back to the jobs.lua version"
end

-- The rank a battalion role needs, by prefix when the ladder has it.
local function roleRank(role)
    local n = #R.Ranks()
    if role == "sergeant" then return R.RankPrefix(R.RankIndex("SGT") or math.min(4, n)) end
    if role == "officer" then return R.RankPrefix(R.RankIndex("LT") or math.min(6, n)) end
    if role == "commander" then return R.RankPrefix(R.RankIndex("CMD") or n) end
    return R.RankPrefix(1)
end

-- J.NewBattalion(p): op 4 (see the top). The five jobs of battalion() in
-- jobs.lua, in a new category with the battalion's name.
function J.NewBattalion(p)
    local name = str(p.name, 32)
    if not name or #name < 2 then return false, "Give the battalion a name (2-32 characters)" end
    for _, job in pairs(RPExtraTeams) do
        if not job.rhylibDead and job.battalion == name then return false, "The " .. name .. " already has jobs" end
    end
    local prefix = isstring(p.prefix) and string.lower(string.Trim(p.prefix)) or ""
    if not string.match(prefix, "^[a-z0-9]+$") or #prefix > 10 then
        return false, "The command prefix is 1-10 letters or digits (212 makes /212trooper, /212medic, ...)"
    end
    local models = istable(p.models) and p.models or {}
    if not goodModel(models.trooper) then return false, "The trooper model isn't on the server" end

    local defs = {}
    for _, r in ipairs(J.BATTALION_ROLES) do
        local role, title, o = r[1], r[2], r[3]
        local cmd, why = J.CleanCmd(prefix .. role)
        if not cmd then return false, why end
        local m = (isstring(models[role]) and models[role] ~= "") and models[role] or models.trooper
        local d, why2 = J.Clean({
            name = name .. " " .. title, col = p.col, models = { m }, desc = J.BATTALION_DESC[role],
            max = o.max or 0, salary = o.salary, order = o.order, cat = name, bn = name, minRank = roleRank(role),
            medic = o.medic, commander = o.commander, mp = p.mp == true,
        }, cmd)
        if not d then return false, (why2 or "Bad data") .. " (" .. title .. ")" end
        d.cmd = cmd
        defs[#defs + 1] = d
    end
    needCat(name, defs[1].col, true)
    for _, d in ipairs(defs) do
        table.insert(J.data.jobs, d)
        J.live[#J.live + 1] = { d = d }
    end
    commit()
    return true, "Made the " .. name .. ": /" .. prefix .. "trooper, /" .. prefix .. "medic, /" .. prefix .. "sergeant, /" .. prefix .. "officer, /" .. prefix .. "commander"
end

Net.Receive("roster.jobedit", function(ply)
    local op = net.ReadUInt(3)
    local len = net.ReadUInt(16)
    if len > 32000 then return end
    local raw = net.ReadData(len)
    -- Permission first, then unpack (capped), so nobody else makes the
    -- server decompress anything.
    Rhylib.Perms.Check(ply, "rhylib.roster.jobs", function(ok)
        if not IsValid(ply) then return end
        if not ok then return reply(ply, false, "You can't change jobs") end
        local p = J.Unpack(raw, 65536)
        if not istable(p) then return reply(ply, false, "Bad data") end
        if not (J.booted and J.data) then return reply(ply, false, "DarkRP jobs aren't loaded") end
        local cmd = isstring(p.cmd) and p.cmd or ""
        local res, msg
        if op == J.OP_SAVE then res, msg = J.Save(ply, p, p.new == true)
        elseif op == J.OP_OFF then res, msg = J.SetOff(cmd, p.off == true)
        elseif op == J.OP_DELETE then res, msg = J.Delete(cmd)
        elseif op == J.OP_RESET then res, msg = J.Reset(cmd)
        elseif op == J.OP_BATTALION then res, msg = J.NewBattalion(p)
        else res, msg = false, "Unknown change" end
        reply(ply, res, msg)
        if res then Rhylib.Print("roster", "%s (%s): %s", ply:Nick(), ply:SteamID64() or "", msg) end
    end)
end, { rate = 4, burst = 6 })
