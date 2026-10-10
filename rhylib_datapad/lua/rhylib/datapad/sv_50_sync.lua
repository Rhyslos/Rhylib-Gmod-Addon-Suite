--[[
    Datapad sync (server): download the battalion computer's logs and board
    (and orders, LOA, stats, your file, info, mission) to the datapad,
    anywhere (uploading still happens at the computer).

    Each battalion has a version (os.time of its last change, Data
    "dp_ver"/battalion). Any change to its logs or board bumps it and tells
    the battalion's online members (dp.ver), so their datapad can show
    that there's something new.

      dp.ver    server -> battalion members: battalion, version (32)
      dp.dl     datapad: download -> dp.dldata (version, log list, board list)
                and dp.dlx (orders, LOA, stats, your own file) and dp.dlm
                (battalion info, mission). Stats don't bump the version.
      dp.dldata battalion, version 32, logs (count 8, at most 200; id 20,
                author, title, time 32, mp), posts (count 7, at most 120;
                id 16, section 3, title, author, time 32, session time 32,
                pinned, outcome 2). No texts: those come with dp.dread.
      dp.dlx    battalion, manager, orders (D.WriteOrders), LOA (count 6;
                name, from 32, to 32, reason), stats: battalion this week,
                you this week, you all time (11 x UInt 32 each), quals
                (count 5), commendations (total 8, count 4 sent: time, by,
                text), active strikes (count 4: time, expires, by, text)
      dp.dlm    battalion info (D.WriteInfo), mission (D.WriteMission)
      dp.dread  datapad: kind (1 bit: 0 log, 1 post), id (20) -> dp.dbody
                (kind 1, id 20, text)

    Data "dp_ver"/battalion = { v = version }.
]]

local D = Rhylib.Datapad

for _, n in ipairs({ "dp.ver", "dp.dldata", "dp.dlx", "dp.dlm", "dp.dbody" }) do Rhylib.Net.Register(n) end

-- D.Version(bn): the battalion's current version number (0 = never changed).
function D.Version(bn)
    return D.Load("dp_ver", bn, {}).v or 0
end

-- D.Touch(bn): mark the battalion as changed: new version (at least
-- os.time, always higher than before) and dp.ver to its online members,
-- so their datapad's sync light blinks "New data".
-- Example: after editing "dp_ord" yourself: D.Store(...) then D.Touch(bn)
function D.Touch(bn)
    local t = D.Load("dp_ver", bn, {})
    t.v = math.max((t.v or 0) + 1, os.time())
    D.Store("dp_ver", bn, t)
    local list = {}
    for _, p in ipairs(player.GetHumans()) do
        if D.Battalion(p) == bn then list[#list + 1] = p end
    end
    if #list == 0 then return end
    Rhylib.Net.Start("dp.ver")
    net.WriteString(bn)
    net.WriteUInt(t.v, 32)
    net.Send(list)
end

-- Every save of a battalion's logs or board counts as a change
-- (D.StoreQuiet saves without that: sign-ups, check-ins). Other modules
-- (orders, info, missions) call D.Touch themselves. "__" keys (the medical
-- book, the index) never bump anything.
-- (This wraps whatever D.Store is at load time: reloading only this file
-- with Lua refresh wraps it twice. A map change puts it right.)
local store = D.Store
D.StoreQuiet = store
function D.Store(ns, key, v)
    store(ns, key, v)
    if (ns == "dp_log" or ns == "dp_board") and string.sub(key, 1, 2) ~= "__" then D.Touch(key) end
end

D.PadRecv("dp.dl", function(ply)
    local bn = D.Battalion(ply)
    if bn == "" then return end
    local logs = D.Book(bn).list
    local posts = D.Board and D.Board(bn).list or {}
    Rhylib.Net.Start("dp.dldata")
    net.WriteString(bn)
    net.WriteUInt(D.Version(bn), 32)
    local n = math.min(#logs, 200)
    net.WriteUInt(n, 8)
    for i = 1, n do
        local e = logs[i]
        net.WriteUInt(e.id, 20)
        net.WriteString(e.a or "?")
        net.WriteString(e.ti or "")
        net.WriteUInt(e.t or 0, 32)
        net.WriteBool(e.mp or false)
    end
    n = math.min(#posts, 120)
    net.WriteUInt(n, 7)
    for i = 1, n do
        local p = posts[i]
        net.WriteUInt(p.id, 16)
        net.WriteUInt(p.sec or 1, 3)
        net.WriteString(p.ti or "")
        net.WriteString(p.a or "?")
        net.WriteUInt(p.t or 0, 32)
        net.WriteUInt(p.at or 0, 32)
        net.WriteBool(p.pin or false)
        net.WriteUInt(p.oc or 0, 2)
    end
    net.Send(ply)
    D.SendExtra(ply, bn)
end, { rate = 1, burst = 2 })

-- D.SendExtra(ply, bn): the rest of a download: dp.dlx (orders, LOA, stats,
-- your own file) and dp.dlm (info, mission). Their own messages keep each
-- one small. Needs sv_60/70/90 for orders/file/mission (sends empty parts without).
function D.SendExtra(ply, bn)
    local id = ply:SteamID64() or ""
    local manager = D.IsUnitManager and D.IsUnitManager(ply, bn, false) or false
    Rhylib.Net.Start("dp.dlx")
    net.WriteString(bn)
    net.WriteBool(manager)
    if D.WriteOrders then D.WriteOrders(ply, bn, manager) else net.WriteUInt(0, 6) end
    -- LOA.
    local leave = D.ActiveLeave and D.ActiveLeave(bn).list or {}
    local nl = math.min(#leave, 63)
    net.WriteUInt(nl, 6)
    for i = 1, nl do
        local e = leave[i]
        net.WriteString(e.n or "?")
        net.WriteUInt(e.from or 0, 32)
        net.WriteUInt(e.to or 0, 32)
        net.WriteString(e.why or "")
    end
    -- Stats: the battalion this week, you this week, you all time.
    local b = D.Load("dp_stats", bn, {}).b or {}
    local keys = D.StatBucketKeys()
    local week, all = b[keys.week] or {}, b[keys.all] or {}
    local function row(t)
        for _, k in ipairs(D.STAT_KEYS) do net.WriteUInt(math.Clamp(t[k] or 0, 0, 2 ^ 31), 32) end
    end
    row(week.t or {})
    row(week.p and week.p["s" .. id] or {})
    row(all.p and all.p["s" .. id] or {})
    -- Your file: quals held, commendations, active strikes.
    local Ro = Rhylib.Roster
    local c = Ro and Ro.Char(id)
    local held = {}
    if c and istable(c.q) then
        for q, on in pairs(c.q) do
            if on then held[#held + 1] = Ro.QualName(tostring(q)) end
        end
    end
    table.sort(held)
    net.WriteUInt(math.min(#held, 31), 5)
    for i = 1, math.min(#held, 31) do net.WriteString(held[i]) end
    local f = D.File and D.File(id) or { c = {}, s = {} }
    net.WriteUInt(math.min(#f.c, 255), 8)
    local nc = math.min(#f.c, 10)
    net.WriteUInt(nc, 4)
    for i = 1, nc do
        net.WriteUInt(f.c[i].t or 0, 32)
        net.WriteString(f.c[i].by or "?")
        net.WriteString(f.c[i].txt or "")
    end
    local now, act = os.time(), {}
    for _, x in ipairs(f.s) do
        if (x.exp or 0) > now and #act < 10 then act[#act + 1] = x end
    end
    net.WriteUInt(#act, 4)
    for _, x in ipairs(act) do
        net.WriteUInt(x.t or 0, 32)
        net.WriteUInt(x.exp or 0, 32)
        net.WriteString(x.by or "?")
        net.WriteString(x.txt or "")
    end
    net.Send(ply)
    -- Battalion info and the current mission: their own message (size).
    Rhylib.Net.Start("dp.dlm")
    if D.WriteInfo then D.WriteInfo(bn) else net.WriteString("") net.WriteString("") net.WriteUInt(0, 32) end
    if D.WriteMission then D.WriteMission(bn) else net.WriteBool(false) end
    net.Send(ply)
end

D.PadRecv("dp.dread", function(ply)
    local kind = net.ReadUInt(1)
    local id = net.ReadUInt(20)
    local bn = D.Battalion(ply)
    if bn == "" then return end
    local list = kind == 0 and D.Book(bn).list or (D.Board and D.Board(bn).list or {})
    for _, e in ipairs(list) do
        if e.id == id then
            Rhylib.Net.Start("dp.dbody")
            net.WriteUInt(kind, 1)
            net.WriteUInt(id, 20)
            net.WriteString(e.b or "")
            net.Send(ply)
            return
        end
    end
end, { rate = 4, burst = 6 })
