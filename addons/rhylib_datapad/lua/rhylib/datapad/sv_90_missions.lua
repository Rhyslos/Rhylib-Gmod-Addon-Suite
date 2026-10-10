--[[
    Missions (server): the one thing uploaded from the datapad. A battalion has at
    most one mission at a time; officers (rank boardRank+) post it from
    their datapad (title, date, objectives, sub objectives, info), edit it,
    start it and end it. Everyone else gets it with the datapad download.

    While a mission is active, every online member of the battalion is
    added to it (checked every 20 s); each one gets the "ev" (Events) stat
    once. Ending it moves it to the battalion computer's Missions archive,
    where officers can delete it.

    Data "dp_mis"/bn = current mission ({} = none):
        { ti, date, obj, sub, info, by, t, active, started, people = { ["s"..sid] = name } }
    Data "dp_misarc"/bn = { next, list { id, ti, date, obj, sub, info, by, t,
        started, ended, endedBy, people } } (newest first, 100 kept)

      datapad:   dp.mget -> dp.mcur (can edit, mission)
                 dp.msave (title, date, objectives, sub objectives, info)
                 dp.mstart   dp.mend    (officers; each answers dp.mcur)
      computer:  dp.mlist -> dp.mlistr (entity, can delete, current mission,
                 archive: count 7; id 16, title, date, by, started 32,
                 ended 32, people 8)
                 dp.mread id (16) -> dp.mfull (id, objectives, sub
                 objectives, info, ended by, people: count 8, names)
                 dp.mdel id (16) (officers)
    Text limits: title 80, date 40, objectives / sub objectives 1000,
    info 3000 characters.
]]

local D = Rhylib.Datapad

for _, n in ipairs({ "dp.mcur", "dp.mlistr", "dp.mfull" }) do Rhylib.Net.Register(n) end

local ARC_KEEP = 100

local function current(bn) return D.Load("dp_mis", bn, {}) end
local function exists(m) return m.ti ~= nil end
local function archive(bn)
    local t = D.Load("dp_misarc", bn, nil)
    if not t.list then t.next, t.list = 1, {} end
    return t
end

local function names(people)
    local out = {}
    for _, n in pairs(people or {}) do out[#out + 1] = tostring(n) end
    table.sort(out)
    return out
end

-- D.WriteMission(bn): write bn's current mission into the net message (read
-- with D.ReadMission on the client): exists (bool); then title, date,
-- objectives, sub objectives, info, by, time 32, active, started 32,
-- people count (8), up to 40 names (6).
function D.WriteMission(bn)
    local m = bn ~= "" and current(bn) or {}
    net.WriteBool(exists(m))
    if not exists(m) then return end
    net.WriteString(m.ti or "")
    net.WriteString(m.date or "")
    net.WriteString(m.obj or "")
    net.WriteString(m.sub or "")
    net.WriteString(m.info or "")
    net.WriteString(m.by or "?")
    net.WriteUInt(m.t or 0, 32)
    net.WriteBool(m.active or false)
    net.WriteUInt(m.started or 0, 32)
    local list = names(m.people)
    net.WriteUInt(math.min(#list, 255), 8)
    local n = math.min(#list, 40)
    net.WriteUInt(n, 6)
    for i = 1, n do net.WriteString(list[i]) end
end

local function tellBattalion(bn, msg)
    for _, p in ipairs(player.GetHumans()) do
        if D.Battalion(p) == bn then p:ChatPrint(msg) end
    end
end

-- Online members join an active mission (once each: the Events stat).
local function enlist(bn, m)
    if not m.active then return false end
    m.people = m.people or {}
    local changed = false
    for _, p in ipairs(player.GetHumans()) do
        local key = "s" .. (p:SteamID64() or "")
        if D.Battalion(p) == bn and key ~= "s" and not m.people[key] then
            m.people[key] = p:Nick()
            D.AddStat(p, "ev", 1)
            changed = true
        end
    end
    return changed
end

timer.Create("Rhylib.Datapad.Missions", 20, 0, function()
    local seen = {}
    for _, p in ipairs(player.GetHumans()) do
        local bn = D.Battalion(p)
        if bn ~= "" and not seen[bn] then
            seen[bn] = true
            local m = current(bn)
            if exists(m) and enlist(bn, m) then D.Store("dp_mis", bn, m) end
        end
    end
end)

--------------------------------------------------------------------------
-- Datapad (officers)
--------------------------------------------------------------------------

local function officer(ply)
    local bn = D.Battalion(ply)
    return bn ~= "" and D.IsUnitOfficer and D.IsUnitOfficer(ply, bn, false), bn
end

local function sendCurrent(ply, bn, canEdit)
    Rhylib.Net.Start("dp.mcur")
    net.WriteBool(canEdit)
    D.WriteMission(bn)
    net.Send(ply)
end

D.PadRecv("dp.mget", function(ply)
    local ok, bn = officer(ply)
    if bn == "" then return end
    sendCurrent(ply, bn, ok)
end, { rate = 3, burst = 4 })

D.PadRecv("dp.msave", function(ply)
    local ti = D.Clip(net.ReadString(), 80)
    local date = D.Clip(net.ReadString(), 40)
    local obj = D.Clip(net.ReadString(), 1000, true)
    local sub = D.Clip(net.ReadString(), 1000, true)
    local info = D.Clip(net.ReadString(), 3000, true)
    local ok, bn = officer(ply)
    if not ok then return end
    if ti == "" then ti = "Mission" end
    local m = current(bn)
    local new = not exists(m)
    if new then
        m = { t = os.time(), active = false, people = {} }
    end
    m.ti, m.date, m.obj, m.sub, m.info, m.by = ti, date, obj, sub, info, ply:Nick()
    D.Store("dp_mis", bn, m)
    D.Touch(bn)
    tellBattalion(bn, (new and "Mission posted: " or "Mission updated: ") .. ti .. " (sync your datapad)")
    sendCurrent(ply, bn, true)
end, { rate = 1, burst = 3 })

D.PadRecv("dp.mstart", function(ply)
    local ok, bn = officer(ply)
    if not ok then return end
    local m = current(bn)
    if not exists(m) or m.active then return end
    m.active, m.started = true, os.time()
    enlist(bn, m)
    D.Store("dp_mis", bn, m)
    D.Touch(bn)
    tellBattalion(bn, "Mission started: " .. m.ti)
    sendCurrent(ply, bn, true)
end, { rate = 1, burst = 2 })

D.PadRecv("dp.mend", function(ply)
    local ok, bn = officer(ply)
    if not ok then return end
    local m = current(bn)
    if not exists(m) then return end
    local arc = archive(bn)
    table.insert(arc.list, 1, {
        id = arc.next, ti = m.ti, date = m.date, obj = m.obj, sub = m.sub, info = m.info, by = m.by, t = m.t,
        started = m.started or 0, ended = os.time(), endedBy = ply:Nick(), people = m.people or {},
    })
    arc.next = arc.next % 65535 + 1
    while #arc.list > ARC_KEEP do table.remove(arc.list) end
    D.Store("dp_misarc", bn, arc)
    D.Store("dp_mis", bn, {})
    D.Touch(bn)
    tellBattalion(bn, "Mission ended: " .. (m.ti or "") .. ". It's in the battalion computer's Missions archive.")
    sendCurrent(ply, bn, true)
end, { rate = 1, burst = 2 })

--------------------------------------------------------------------------
-- Battalion computer: the archive
--------------------------------------------------------------------------

local function missionTerm(ent) return not D.IsMedTerm(ent) and ent:GetBattalion() ~= "" end

local function sendList(ply, ent, a)
    local bn = ent:GetBattalion()
    local list = archive(bn).list
    Rhylib.Net.Start("dp.mlistr")
    net.WriteEntity(ent)
    net.WriteBool(D.IsUnitOfficer(ply, bn, a.admin))
    D.WriteMission(bn)
    local n = math.min(#list, 127)
    net.WriteUInt(n, 7)
    for i = 1, n do
        local x = list[i]
        net.WriteUInt(x.id, 16)
        net.WriteString(x.ti or "")
        net.WriteString(x.date or "")
        net.WriteString(x.by or "?")
        net.WriteUInt(x.started or 0, 32)
        net.WriteUInt(x.ended or 0, 32)
        net.WriteUInt(math.min(table.Count(x.people or {}), 255), 8)
    end
    net.Send(ply)
end

D.TermRecv("dp.mlist", {
    run = function(ply, ent, a)
        if missionTerm(ent) and a.view then sendList(ply, ent, a) end
    end,
}, { rate = 3, burst = 4 })

D.TermRecv("dp.mread", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not missionTerm(ent) or not a.view then return end
        for _, x in ipairs(archive(ent:GetBattalion()).list) do
            if x.id == id then
                Rhylib.Net.Start("dp.mfull")
                net.WriteUInt(id, 16)
                net.WriteString(x.obj or "")
                net.WriteString(x.sub or "")
                net.WriteString(x.info or "")
                net.WriteString(x.endedBy or "")
                local list = names(x.people)
                local n = math.min(#list, 255)
                net.WriteUInt(n, 8)
                for i = 1, n do net.WriteString(list[i]) end
                net.Send(ply)
                return
            end
        end
    end,
})

D.TermRecv("dp.mdel", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not missionTerm(ent) or not a.view then return end
        local bn = ent:GetBattalion()
        if not D.IsUnitOfficer(ply, bn, a.admin) then return end
        local arc = archive(bn)
        for i, x in ipairs(arc.list) do
            if x.id == id then
                table.remove(arc.list, i)
                D.Store("dp_misarc", bn, arc)
                break
            end
        end
        sendList(ply, ent, a)
    end,
})
