--[[
    Datapad (server): notes on the pad, and the MP tools.

    Messages (client -> server need the datapad in hand):
      dp.open    open: server answers dp.state
      dp.state   bn, roles, ban, limit, notes (id, kind, title, patient, time), cuffed nearby (MP)
      dp.get     note id -> dp.body
      dp.save    id (0 = new), kind, title, body, patient
      dp.del     note id
      dp.find    MP: name search -> dp.found (sid, name, arrests)
      dp.rec     MP: sid -> dp.record (arrests, logs they wrote)
      dp.olog    MP: logs written by MPs -> dp.ologs
      dp.lread   MP: battalion, id -> dp.lbody
      dp.jail    MP: prisoner, minutes, reason
]]

local D = Rhylib.Datapad
local Data = Rhylib.Data

for _, n in ipairs({ "dp.state", "dp.body", "dp.found", "dp.record", "dp.ologs", "dp.lbody" }) do
    Rhylib.Net.Register(n)
end
Rhylib.Perms.Register("rhylib.datapad.admin", "admin", "Place datapad computers, set their battalion, moderate any of them")

--------------------------------------------------------------------------
-- Storage (cached: Data.Get reads SQLite every call)
--------------------------------------------------------------------------

local cache = {}

function D.Load(ns, key, default)
    local k = ns .. "/" .. key
    local v = cache[k]
    if v == nil then
        v = Data.Get(ns, key)
        if not istable(v) then v = default or {} end
        cache[k] = v
    end
    return v
end

-- Forget every cached copy (after saved data was changed behind it,
-- e.g. rhylib_purge_battalion).
function D.ClearCache() cache = {} end
Rhylib.Hook.Add("Rhylib.DataPurged", "datapad.cache", function() D.ClearCache() end)

function D.Store(ns, key, v)
    cache[ns .. "/" .. key] = v
    Data.Set(ns, key, v)
end

-- A computer's log book: { next = id, list = { newest first } }.
function D.Book(key)
    local b = D.Load("dp_log", key, nil)
    if not b.list then b.next, b.list = 1, {} end
    return b
end

-- Every battalion that has logs (for MP lookups): a list of names.
function D.Battalions()
    return D.Load("dp_log", "__index", {})
end

function D.HasBattalion(bn)
    for _, b in ipairs(D.Battalions()) do
        if b == bn then return true end
    end
    return false
end

-- Bans are { ["s" .. sid] = name } (prefixed: JSON would turn a bare
-- SteamID64 key into a rounded number).
function D.Banned(key, sid)
    return sid ~= "" and D.Load("dp_ban", key, {})["s" .. sid] ~= nil
end

-- A note on the pad by its id.
function D.Note(pad, id)
    for i, n in ipairs(pad) do
        if n.id == id then return n, i end
    end
end

local function sid(ply) return ply:SteamID64() or "" end

function D.Pad(ply)
    return D.Load("dp_pad", sid(ply), {})
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

local function cuffedNear(mp)
    local MP = Rhylib.MP
    local out = {}
    if not MP then return out end
    local r = D.Cfg("arrestRange")
    for _, p in ipairs(player.GetAll()) do
        if p ~= mp and MP.IsCuffed(p) and not MP.IsJailed(p) then
            local ok = MP.EscortedBy(p) == mp
            if not ok and p:GetPos():DistToSqr(mp:GetPos()) <= r * r then
                -- In sight, not through a wall.
                local tr = util.TraceLine({ start = mp:EyePos(), endpos = p:WorldSpaceCenter(), filter = { mp, p }, mask = MASK_SOLID })
                ok = not tr.Hit
            end
            if ok then out[#out + 1] = p end
        end
    end
    return out
end

function D.SendState(ply)
    local pad = D.Pad(ply)
    local bn = D.Battalion(ply)
    local mp = D.IsMP(ply)
    Rhylib.Net.Start("dp.state")
    net.WriteString(bn)
    net.WriteBool(mp)
    net.WriteBool(D.IsMedic(ply))
    net.WriteBool(bn ~= "" and D.Banned(bn, sid(ply)))
    net.WriteUInt(D.Limit(ply), 8)
    net.WriteUInt(bn ~= "" and D.Version and D.Version(bn) or 0, 32)   -- newest change on the battalion computer
    net.WriteUInt(math.min(#pad, 255), 8)
    for i = 1, math.min(#pad, 255) do
        local n = pad[i]
        net.WriteUInt(n.id or 0, 16)
        net.WriteUInt(n.k or 0, 1)
        net.WriteString(n.ti or "")
        net.WriteString(n.pn or "")
        net.WriteUInt(n.t or 0, 32)
    end
    local cuffed = mp and cuffedNear(ply) or {}
    net.WriteUInt(math.min(#cuffed, 15), 4)
    for i = 1, math.min(#cuffed, 15) do net.WriteEntity(cuffed[i]) end
    net.Send(ply)
end

-- Every datapad message needs the pad in hand.
local function recv(name, fn, limits, mpOnly)
    Rhylib.Net.Receive(name, function(ply, len)
        if not ply:Alive() or not D.Holding(ply) then return end
        if mpOnly and not D.IsMP(ply) then return end
        fn(ply, len)
    end, limits or { rate = 4, burst = 6 })
end

D.PadRecv = recv   -- (sv_50_sync.lua)

recv("dp.open", function(ply) D.SendState(ply) end, { rate = 2, burst = 3 })

recv("dp.get", function(ply)
    local id = net.ReadUInt(16)
    local n = D.Note(D.Pad(ply), id)
    if not n then return end
    Rhylib.Net.Start("dp.body")
    net.WriteUInt(id, 16)
    net.WriteString(n.b or "")
    net.Send(ply)
end)

recv("dp.save", function(ply)
    local id = net.ReadUInt(16)
    local kind = net.ReadUInt(1)
    local title = D.Clip(net.ReadString(), D.Cfg("titleMax"))
    local body = D.Clip(net.ReadString(), D.Cfg("bodyMax"), true)
    local patient = net.ReadEntity()
    if title == "" then title = "Untitled" end
    if sid(ply) == "" then return end  -- bots
    local pad = D.Pad(ply)
    local bn = D.Battalion(ply)
    if id == 0 then
        if kind == D.KIND_MED and not D.IsMedic(ply) then return end
        if kind == D.KIND_LOG and bn ~= "" and D.Banned(bn, sid(ply)) then
            ply:ChatPrint("You're banned from your battalion's logs")
            return
        end
        local limit = D.Limit(ply)
        if #pad >= (limit > 0 and limit or D.HARD_CAP) then
            ply:ChatPrint("Your datapad is full. Upload your notes at your battalion computer")
            return
        end
        local top = 0
        for _, o in ipairs(pad) do top = math.max(top, o.id or 0) end
        local n = { id = top % 65535 + 1, k = kind, ti = title, b = body, t = os.time() }
        if kind == D.KIND_MED then
            if not (IsValid(patient) and patient:IsPlayer()) then return end
            n.p, n.pn = sid(patient), patient:Nick()
        end
        pad[#pad + 1] = n
    else
        local n = D.Note(pad, id)
        if not n then return end
        n.ti, n.b = title, body
    end
    D.Store("dp_pad", sid(ply), pad)
    D.SendState(ply)
end)

recv("dp.del", function(ply)
    local pad = D.Pad(ply)
    local _, i = D.Note(pad, net.ReadUInt(16))
    if not i then return end
    table.remove(pad, i)
    D.Store("dp_pad", sid(ply), pad)
    D.SendState(ply)
end)

--------------------------------------------------------------------------
-- MP tools
--------------------------------------------------------------------------

-- Search tool: with the datapad out, rhylib_mp's search works like the baton.
-- Returns the reach: the datapad searches anyone it could jail.
Rhylib.Hook.Add("Rhylib.MPSearchTool", "datapad", function(ply, w)
    if w:GetClass() == D.Cfg("class") then return D.Cfg("arrestRange") end
end)

recv("dp.find", function(ply)
    local q = string.lower(D.Clip(net.ReadString(), 32))
    if q == "" then return end
    local MP = Rhylib.MP
    local found, seen = {}, {}
    local function add(id, name)
        if seen[id] or #found >= 20 then return end
        if string.find(string.lower(name), q, 1, true) then
            seen[id] = true
            found[#found + 1] = { id, name, MP and #MP.GetRecord(id) or 0 }
        end
    end
    for _, p in ipairs(player.GetAll()) do add(sid(p), p:Nick()) end
    local idx = Data.Get("mp_idx", "all")
    if istable(idx) then
        for k, name in pairs(idx) do
            if isstring(k) and string.sub(k, 1, 1) == "s" then add(string.sub(k, 2), tostring(name)) end
        end
    end
    Rhylib.Net.Start("dp.found")
    net.WriteUInt(#found, 5)
    for _, f in ipairs(found) do
        net.WriteString(f[1])
        net.WriteString(f[2])
        net.WriteUInt(math.min(f[3], 255), 8)
    end
    net.Send(ply)
end, { rate = 2, burst = 4 }, true)

-- Logs matching filter(entry), newest first, across every battalion.
local function findLogs(filter, max)
    local out = {}
    for _, bn in ipairs(D.Battalions()) do
        for _, e in ipairs(D.Book(bn).list) do
            if filter(e) then out[#out + 1] = { bn = bn, e = e } end
        end
    end
    table.sort(out, function(a, b) return (a.e.t or 0) > (b.e.t or 0) end)
    while #out > max do table.remove(out) end
    return out
end

local function writeLogs(list)
    net.WriteUInt(#list, 7)
    for _, r in ipairs(list) do
        net.WriteString(r.bn)
        net.WriteUInt(r.e.id, 20)
        net.WriteString(r.e.a or "?")
        net.WriteString(r.e.ti or "")
        net.WriteUInt(r.e.t or 0, 32)
    end
end

recv("dp.rec", function(ply)
    local id = net.ReadString()
    if not string.match(id, "^%d+$") then return end
    local MP = Rhylib.MP
    local rec = MP and MP.GetRecord(id) or {}
    local name = id
    local idx = Data.Get("mp_idx", "all")
    if istable(idx) and idx["s" .. id] then name = tostring(idx["s" .. id]) end
    local p = player.GetBySteamID64(id)
    if IsValid(p) then name = p:Nick() end
    Rhylib.Net.Start("dp.record")
    net.WriteString(id)
    net.WriteString(name)
    net.WriteUInt(math.min(#rec, 63), 6)
    for i = 1, math.min(#rec, 63) do
        local r = rec[i]
        net.WriteUInt(r.t or 0, 32)
        net.WriteString(r.by or "?")
        net.WriteUInt(math.Clamp(r.min or 0, 0, 1023), 10)
        net.WriteString(r.why or "")
    end
    writeLogs(findLogs(function(e) return e.s == id end, 60))
    net.Send(ply)
end, { rate = 3, burst = 4 }, true)

recv("dp.olog", function(ply)
    Rhylib.Net.Start("dp.ologs")
    writeLogs(findLogs(function(e) return e.mp end, 80))
    net.Send(ply)
end, { rate = 2, burst = 3 }, true)

recv("dp.lread", function(ply)
    local bn = net.ReadString()
    local id = net.ReadUInt(20)
    if not D.HasBattalion(bn) then return end
    for _, e in ipairs(D.Book(bn).list) do
        if e.id == id then
            Rhylib.Net.Start("dp.lbody")
            net.WriteString(e.a or "?")
            net.WriteString(e.ti or "")
            net.WriteUInt(e.t or 0, 32)
            net.WriteString(e.b or "")
            net.Send(ply)
            return
        end
    end
end, { rate = 4, burst = 6 }, true)

recv("dp.jail", function(ply)
    local p = net.ReadEntity()
    local minutes = net.ReadUInt(7)
    local why = D.Clip(net.ReadString(), 80)
    local MP = Rhylib.MP
    if not (MP and MP.Jail) or not IsValid(p) then return end
    local ok = false
    for _, c in ipairs(cuffedNear(ply)) do
        if c == p then ok = true break end
    end
    if not ok then
        ply:ChatPrint("They need to be cuffed and close to you")
        return
    end
    local done, err = MP.Jail(p, ply, minutes, why)
    if not done and err then ply:ChatPrint(err) end
    D.SendState(ply)
end, { rate = 2, burst = 3 }, true)
