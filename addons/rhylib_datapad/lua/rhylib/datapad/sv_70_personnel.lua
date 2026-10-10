--[[
    Battalion computer (server): personnel files, the Personnel tab
    (needs rhylib_roster; without it the member list is empty).

    A file per character, kept across battalions:
      Data "dp_pf"/sid = { next, c = commendations, s = strikes, n = notes }
        c: list { id, t, by, bn, txt }
        s: list { id, t, exp, by, bn, txt }   (active until exp; config strikeDays)
        n: { txt, by, t }                     NCO notes (managers only)
    Qualifications live on the character (Rhylib.Roster.SetQual).

    Who sees what (anyone who can read the computer sees the list, ranks,
    quals, commendations and stats): strikes - managers, MPs, admins and the
    person; notes - managers and admins.
    Who does what: managers (rank manageRank+) on members ranked below them
    (strikes, quals, notes, removing); commendations on anyone but
    themselves; admins anything. 50 entries kept per list, 30 newest sent.

      dp.plist   entity -> dp.pmembers: entity, count 8 x (sid, name,
                 rank 8, online, last seen 32, commendations 8, active
                 strikes 4, roster note e.g. LOA)
      dp.pget    entity, sid -> dp.pfile: entity, sid, name, rank name,
                 online, seen 32, can commend, can discipline, quals (count
                 5; id, name, held), all-time stats here (11 x 32),
                 commendations (count 8; id 16, time 32, by, battalion,
                 text), can see strikes + strikes (count 8; id 16, time 32,
                 expires 32, by, text), can see notes + notes (text, by, time 32)
      dp.pcom / dp.pstrike / dp.pnote   entity, sid, text
      dp.pdel    entity, sid, kind (1 bit: 0 commendation, 1 strike), entry id (16)
      dp.pqual   entity, sid, qual id, on
    Every action is also written to the roster log (Rhylib.Roster.Log) and
    the member is told in chat if online.
]]

local D = Rhylib.Datapad
local Data = Rhylib.Data

for _, n in ipairs({ "dp.pmembers", "dp.pfile" }) do Rhylib.Net.Register(n) end

local KEEP, SEND_MAX = 50, 30   -- entries kept per list / sent (newest; keeps the message small)

local function R() return Rhylib.Roster end
local function sid(ply) return ply:SteamID64() or "" end
local function validSid(id) return isstring(id) and #id <= 20 and string.match(id, "^%d+$") ~= nil end

-- D.File(sid): a character's file { next, c, s, n } (live table; save with
-- D.Store("dp_pf", sid, f)). Also read by sv_50 (My file) and sv_60 (applications).
function D.File(id)
    local f = D.Load("dp_pf", id, nil)
    if not f.next then f.next, f.c, f.s = 1, {}, {} end
    return f
end

local function activeStrikes(f)
    local n, now = 0, os.time()
    for _, x in ipairs(f.s) do
        if (x.exp or 0) > now then n = n + 1 end
    end
    return n
end

local function online(id)
    for _, p in ipairs(player.GetHumans()) do
        if sid(p) == id then return p end
    end
end

local function canTerm(ent) return not D.IsMedTerm(ent) and ent:GetBattalion() ~= "" and R() ~= nil end

-- Rights of ply over the member id (character c) at battalion bn:
-- commend (managers, not on themselves), discipline (strikes, quals,
-- notes, removing: managers on lower ranks), strikes (who may read them),
-- notes (who may read them). Admins (a.admin) may do everything.
local function rights(ply, bn, a, id, c)
    local self = sid(ply) == id
    local manager = D.IsUnitManager(ply, bn, a.admin)
    local below = a.admin or (manager and not self and (c.r or 0) < D.UnitRank(ply, bn))
    return {
        commend = a.admin or (manager and not self),
        discipline = below,
        strikes = a.admin or manager or D.IsMP(ply) or self,
        notes = a.admin or manager,
    }
end

-- The member at this computer, or nil.
local function member(ent, id)
    if not validSid(id) then return nil end
    local c = R().Char(id)
    if not c or c.bn ~= ent:GetBattalion() then return nil end
    return c
end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

local function sendList(ply, ent, a)
    local bn = ent:GetBattalion()
    local list = R().Members(bn)
    table.sort(list, function(x, y)
        if (x.c.r or 0) ~= (y.c.r or 0) then return (x.c.r or 0) > (y.c.r or 0) end
        return tostring(x.c.num) < tostring(y.c.num)
    end)
    local n = math.min(#list, 255)
    Rhylib.Net.Start("dp.pmembers")
    net.WriteEntity(ent)
    net.WriteUInt(n, 8)
    for i = 1, n do
        local m = list[i]
        local f = D.File(m.id)
        net.WriteString(m.id)
        net.WriteString(R().FullCharName(m.c))
        net.WriteUInt(math.Clamp(m.c.r or 0, 0, 255), 8)
        net.WriteBool(IsValid(online(m.id)))
        net.WriteUInt(m.c.seen or 0, 32)
        net.WriteUInt(math.min(#f.c, 255), 8)
        net.WriteUInt(math.min(activeStrikes(f), 15), 4)
        net.WriteString(hook.Run("Rhylib.RosterNote", bn, m.id) or "")
    end
    net.Send(ply)
end

local function sendFile(ply, ent, a, id)
    local c = member(ent, id)
    if not c then return end
    local bn = ent:GetBattalion()
    local Ro = R()
    local f = D.File(id)
    local rt = rights(ply, bn, a, id, c)
    Rhylib.Net.Start("dp.pfile")
    net.WriteEntity(ent)
    net.WriteString(id)
    net.WriteString(Ro.FullCharName(c))
    net.WriteString(Ro.RankName(c.r or 0))
    net.WriteBool(IsValid(online(id)))
    net.WriteUInt(c.seen or 0, 32)
    net.WriteBool(rt.commend)
    net.WriteBool(rt.discipline)
    -- Qualifications: every configured one, and whether they have it.
    local quals = Ro.Quals()
    local nq = math.min(#quals, 31)
    net.WriteUInt(nq, 5)
    for i = 1, nq do
        local q = quals[i]
        net.WriteString(q[1])
        net.WriteString(q[2])
        net.WriteBool(istable(c.q) and c.q[q[1]] and true or false)
    end
    -- All-time stats in this battalion (D.STAT_KEYS order).
    local st = D.Load("dp_stats", bn, {})
    local row = st.b and st.b.all and st.b.all.p and st.b.all.p["s" .. id] or {}
    for _, k in ipairs(D.STAT_KEYS) do net.WriteUInt(math.Clamp(row[k] or 0, 0, 2 ^ 31), 32) end
    -- Commendations, newest first.
    local nc = math.min(#f.c, SEND_MAX)
    net.WriteUInt(nc, 8)
    for i = 1, nc do
        local x = f.c[i]
        net.WriteUInt(x.id, 16)
        net.WriteUInt(x.t or 0, 32)
        net.WriteString(x.by or "?")
        net.WriteString(x.bn or "")
        net.WriteString(x.txt or "")
    end
    -- Strikes.
    net.WriteBool(rt.strikes)
    local ns = rt.strikes and math.min(#f.s, SEND_MAX) or 0
    net.WriteUInt(ns, 8)
    for i = 1, ns do
        local x = f.s[i]
        net.WriteUInt(x.id, 16)
        net.WriteUInt(x.t or 0, 32)
        net.WriteUInt(x.exp or 0, 32)
        net.WriteString(x.by or "?")
        net.WriteString(x.txt or "")
    end
    -- Notes.
    net.WriteBool(rt.notes)
    local n = rt.notes and f.n or {}
    net.WriteString(n.txt or "")
    net.WriteString(n.by or "")
    net.WriteUInt(n.t or 0, 32)
    net.Send(ply)
end

--------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------

D.TermRecv("dp.plist", {
    run = function(ply, ent, a)
        if not a.view then return end
        if canTerm(ent) then
            sendList(ply, ent, a)
        else
            Rhylib.Net.Start("dp.pmembers")   -- (empty: no roster)
            net.WriteEntity(ent)
            net.WriteUInt(0, 8)
            net.Send(ply)
        end
    end,
}, { rate = 3, burst = 4 })

D.TermRecv("dp.pget", {
    read = function() return string.sub(net.ReadString(), 1, 20) end,
    run = function(ply, ent, a, id)
        if canTerm(ent) and a.view then sendFile(ply, ent, a, id) end
    end,
}, { rate = 4, burst = 6 })

-- Shared start of every action: the member and the rights, or nil.
local function action(ply, ent, a, id)
    if not canTerm(ent) or not a.view then return nil end
    local c = member(ent, id)
    if not c then return nil end
    return c, rights(ply, ent:GetBattalion(), a, id, c)
end

local function readIdText(max)
    return function() return { id = string.sub(net.ReadString(), 1, 20), txt = D.Clip(net.ReadString(), max, true) } end
end

local function tell(id, msg)
    local p = online(id)
    if IsValid(p) then p:ChatPrint(msg) end
end

local function done(ply, ent, a, id)
    D.Store("dp_pf", id, D.File(id))
    sendFile(ply, ent, a, id)
    sendList(ply, ent, a)
end

D.TermRecv("dp.pcom", {
    read = readIdText(300),
    run = function(ply, ent, a, arg)
        local c, rt = action(ply, ent, a, arg.id)
        if not c or not rt.commend or arg.txt == "" then return end
        local f = D.File(arg.id)
        table.insert(f.c, 1, { id = f.next, t = os.time(), by = ply:Nick(), bn = ent:GetBattalion(), txt = arg.txt })
        f.next = f.next % 65535 + 1
        while #f.c > KEEP do table.remove(f.c) end
        R().Log(ent:GetBattalion(), ply:Nick() .. " commended " .. R().FullCharName(c) .. ": " .. arg.txt)
        tell(arg.id, "You were commended by " .. ply:Nick() .. ": " .. arg.txt)
        done(ply, ent, a, arg.id)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.pstrike", {
    read = readIdText(300),
    run = function(ply, ent, a, arg)
        local c, rt = action(ply, ent, a, arg.id)
        if not c or not rt.discipline or arg.txt == "" then return end
        local bn = ent:GetBattalion()
        local f = D.File(arg.id)
        local now = os.time()
        table.insert(f.s, 1, { id = f.next, t = now, exp = now + math.max(1, D.Cfg("strikeDays")) * 86400, by = ply:Nick(), bn = bn, txt = arg.txt })
        f.next = f.next % 65535 + 1
        while #f.s > KEEP do table.remove(f.s) end
        local name = R().FullCharName(c)
        R().Log(bn, ply:Nick() .. " gave " .. name .. " a strike: " .. arg.txt)
        tell(arg.id, "You got a strike from " .. ply:Nick() .. ": " .. arg.txt)
        -- Too many: tell the officers online.
        local n = activeStrikes(f)
        if n >= D.Cfg("strikeWarn") then
            for _, p in ipairs(player.GetHumans()) do
                if D.Battalion(p) == bn and D.IsUnitOfficer(p, bn, false) then
                    p:ChatPrint(name .. " now has " .. n .. " active strikes")
                end
            end
        end
        done(ply, ent, a, arg.id)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.pnote", {
    read = readIdText(2000),
    run = function(ply, ent, a, arg)
        local c, rt = action(ply, ent, a, arg.id)
        if not c or not rt.discipline then return end   -- (reading: rt.notes)
        D.File(arg.id).n = { txt = arg.txt, by = ply:Nick(), t = os.time() }
        done(ply, ent, a, arg.id)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.pdel", {
    read = function() return { id = string.sub(net.ReadString(), 1, 20), kind = net.ReadUInt(1), eid = net.ReadUInt(16) } end,
    run = function(ply, ent, a, arg)
        local c, rt = action(ply, ent, a, arg.id)
        if not c or not rt.discipline then return end
        local f = D.File(arg.id)
        local list = arg.kind == 0 and f.c or f.s
        for i, x in ipairs(list) do
            if x.id == arg.eid then
                table.remove(list, i)
                R().Log(ent:GetBattalion(), ply:Nick() .. (arg.kind == 0 and " removed a commendation of " or " pardoned a strike of ") .. R().FullCharName(c))
                break
            end
        end
        done(ply, ent, a, arg.id)
    end,
})

D.TermRecv("dp.pqual", {
    read = function() return { id = string.sub(net.ReadString(), 1, 20), q = string.sub(net.ReadString(), 1, 32), on = net.ReadBool() } end,
    run = function(ply, ent, a, arg)
        local c, rt = action(ply, ent, a, arg.id)
        if not c or not rt.discipline then return end
        local known = false
        for _, q in ipairs(R().Quals()) do
            if q[1] == arg.q then known = true end
        end
        if not known then return end
        if R().SetQual(arg.id, arg.q, arg.on, ply:Nick()) then
            tell(arg.id, (arg.on and "You are now qualified: " or "Qualification removed: ") .. R().QualName(arg.q))
        end
        sendFile(ply, ent, a, arg.id)
    end,
})
