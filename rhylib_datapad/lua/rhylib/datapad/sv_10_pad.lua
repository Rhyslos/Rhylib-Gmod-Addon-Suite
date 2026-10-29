--[[
    Datapad (server): the cached storage every datapad file uses, notes on
    the pad, and the MP tools. Also registers the admin permission.

    Messages (client -> server need the datapad in hand: D.PadRecv):
      dp.open    open: server answers dp.state
      dp.state   bn, mp, medic, banned, limit (8), version (32),
                 notes (count 8; id 16, kind 1, title, patient, time 32),
                 cuffed nearby (count 4, entities; MPs only)
      dp.get     note id (16) -> dp.body (id 16, text)
      dp.save    id (16, 0 = new), kind (1), title, body, patient entity
      dp.del     note id (16)
      dp.find    MP: name search -> dp.found (count 5; sid, name, arrests 8)
      dp.rec     MP: sid -> dp.record (sid, name, arrests (count 6; time 32,
                 by, minutes 10, reason), then the logs they wrote)
      dp.olog    MP: logs written by MPs -> dp.ologs
      dp.lread   MP: battalion, id (20) -> dp.lbody (author, title, time, text)
      dp.jail    MP: prisoner entity, minutes (7), reason
    Log lists (dp.record, dp.ologs): count 7; battalion, id 20, author,
    title, time 32.

    Data "dp_pad"/sid = list of notes { id, k kind, ti, b, t, p patient
    sid, pn patient name }. Uploading moves them to a book (sv_20).
    Storage helpers: D.Load / D.Store / D.StoreQuiet (one value per key)
    and the row books D.RowBook / D.SaveBook (D.ROW_BOOKS: log books,
    boards and mission archives, one Data row per entry plus an index;
    old whole-book values are moved over the first time they're read).
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

local cache = {}   -- ["module/key"] = the live table (edit it, then D.Store)

-- D.Load(ns, key, default): the saved table for Data module ns / key,
-- cached in memory. Not a table yet = default (or {}), also cached.
-- Returns the live table: change it and call D.Store to save.
-- Example: local pad = D.Load("dp_pad", ply:SteamID64(), {})
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

-- D.ClearCache(): forget every cached copy (after saved data was changed
-- behind it, e.g. rhylib_purge_battalion or a core purge: hook Rhylib.DataPurged).
-- Row books (below) are forgotten too.
function D.ClearCache()
    cache = {}
    D.ForgetBooks()
end
Rhylib.Hook.Add("Rhylib.DataPurged", "datapad.cache", function() D.ClearCache() end)

-- D.Store(ns, key, v): save v (cache + Rhylib.Data). Plain values only: a
-- row book (D.ROW_BOOKS) saved this way goes through D.SaveBook with every
-- entry rewritten, so other code that still stores whole books keeps working.
-- D.StoreQuiet is the same; neither bumps a version (row books bump in
-- D.SaveBook; everything else calls D.Touch itself).
function D.Store(ns, key, v)
    if D.ROW_BOOKS[ns] and key ~= "__index" and istable(v) and istable(v.list) then
        return D.SaveBook(ns, key, v, true)
    end
    cache[ns .. "/" .. key] = v
    Data.Set(ns, key, v)
end
function D.StoreQuiet(ns, key, v)
    if D.ROW_BOOKS[ns] and key ~= "__index" and istable(v) and istable(v.list) then
        return D.SaveBook(ns, key, v, true, true)
    end
    D.Store(ns, key, v)
end

--------------------------------------------------------------------------
-- Row books: append-mostly lists kept one Data row per entry
--------------------------------------------------------------------------
-- A book is { next, list (newest first) } in memory, as before. Saved as:
--   Data <ns>/<key>            = { v = 2, next, ids = { id, ... newest first } }
--   Data <rows ns>/<key>|<id>  = the entry
-- so a new log or post writes one small row and the index, not the whole
-- book. Books in the old whole-book shape ({ next, list }) are moved to
-- rows the first time they're read (logged once per book).
-- D.ROW_BOOKS[ns] = rows ns. dp_log: battalion log books and "__medical";
-- dp_board: battalion boards; dp_misarc: mission archives.
-- (dp_log "__index" stays a plain list of battalion names.)
D.ROW_BOOKS = { dp_log = "dp_logent", dp_board = "dp_boardent", dp_misarc = "dp_misent" }
local BUMP = { dp_log = true, dp_board = true }   -- (changes show as "new data" on members' pads)

local books, savedIds = {}, {}   -- ["ns/key"] = live book / { [id] = the entry table saved as that row }

function D.ForgetBooks() books, savedIds = {}, {} end

local function rowKey(key, id) return key .. "|" .. tostring(id) end

local function indexOf(book)
    local ids = {}
    for _, e in ipairs(book.list) do
        if e.id ~= nil then ids[#ids + 1] = e.id end
    end
    return { v = 2, next = book.next, ids = ids }
end

-- Every row of one book in one query (queued writes are flushed first so
-- the query sees them).
local function loadRows(rowNs, key, ids)
    if Data.Flush then Data.Flush() end
    local prefix = key .. "|"
    local like = string.gsub(prefix, "[\\%%_]", "\\%0") .. "%"
    local tbl = Data.TABLE or "rhylib_kv"
    local found = {}
    local rows = sql.Query("SELECT key, value FROM " .. tbl .. " WHERE module = " .. sql.SQLStr(rowNs)
        .. " AND key LIKE " .. sql.SQLStr(like) .. " ESCAPE '\\'")
    for _, r in ipairs(istable(rows) and rows or {}) do
        if string.sub(r.key or "", 1, #prefix) == prefix then   -- (LIKE ignores ASCII case)
            local t = util.JSONToTable(r.value or "")
            found[r.key] = t and t.v
        end
    end
    local out = {}
    for _, id in ipairs(ids) do
        local e = found[rowKey(key, id)]
        if not istable(e) then e = Data.Get(rowNs, rowKey(key, id)) end
        if istable(e) then out[#out + 1] = e end
    end
    return out
end

-- D.RowBook(ns, key): the live book { next, list } (cached). Change it and
-- call D.SaveBook.
function D.RowBook(ns, key)
    local ck = ns .. "/" .. key
    local b = books[ck]
    if b then return b end
    local rowNs = D.ROW_BOOKS[ns]
    local raw = Data.Get(ns, key)
    b = { next = 1, list = {} }
    local saved = {}
    if istable(raw) and raw.v == 2 and istable(raw.ids) then
        b.next = tonumber(raw.next) or 1
        b.list = loadRows(rowNs, key, raw.ids)
        for _, e in ipairs(b.list) do saved[e.id] = e end
    elseif istable(raw) and istable(raw.list) then
        -- Old whole-book shape: write every entry as its own row, then the
        -- index over the old value (idempotent: a second read finds v = 2).
        b.list = raw.list
        local top = tonumber(raw.next) and (tonumber(raw.next) - 1) or 0
        for _, e in ipairs(b.list) do top = math.max(top, tonumber(e.id) or 0) end
        for _, e in ipairs(b.list) do
            -- (an entry without an id, or sharing one with an earlier entry,
            -- gets a fresh id so no row overwrites another)
            if e.id == nil or saved[e.id] then
                top = top + 1
                e.id = top
            end
            Data.Set(rowNs, rowKey(key, e.id), e)
            saved[e.id] = e
        end
        b.next = top + 1
        Data.Set(ns, key, indexOf(b))
        Rhylib.Print("datapad", "Moved %s \"%s\" to one row per entry (%d entries)", ns, key, #b.list)
    end
    books[ck], savedIds[ck] = b, saved
    return b
end

-- D.SaveBook(ns, key, book, changed, quiet): save a row book. New entries
-- (not saved yet) and removed ones are found by themselves; pass the
-- entries you edited as `changed` (one entry, a list of them, or true for
-- every entry). Writes the index too. dp_log / dp_board bump the
-- battalion's version (D.Touch) unless quiet or the key starts with "__".
function D.SaveBook(ns, key, book, changed, quiet)
    local rowNs = D.ROW_BOOKS[ns]
    local ck = ns .. "/" .. key
    local saved = savedIds[ck] or {}
    local now = {}
    for _, e in ipairs(book.list) do
        now[e.id] = e
        -- (new, or a different table under a reused id, or everything)
        if saved[e.id] ~= e or changed == true then Data.Set(rowNs, rowKey(key, e.id), e) end
    end
    if istable(changed) then
        local list = changed.id ~= nil and { changed } or changed
        for _, e in ipairs(list) do
            if istable(e) and now[e.id] == e and saved[e.id] == e then Data.Set(rowNs, rowKey(key, e.id), e) end
        end
    end
    for id in pairs(saved) do
        if not now[id] then Data.Delete(rowNs, rowKey(key, id)) end
    end
    books[ck], savedIds[ck] = book, now
    Data.Set(ns, key, indexOf(book))
    if BUMP[ns] and not quiet and string.sub(key, 1, 2) ~= "__" and D.Touch then D.Touch(key) end
end

-- D.Book(key): a computer's log book (key = battalion, or D.MED_KEY):
-- { next = id, list = { newest first } }. Entries: { id, s author sid,
-- a author name, ti, b, t, mp (written by an MP), p/pn patient }.
-- Save with D.SaveBook("dp_log", key, book[, edited entries]).
function D.Book(key)
    return D.RowBook("dp_log", key)
end

-- D.Battalions(): every battalion that has logs (for MP lookups): a list
-- of names, Data "dp_log"/"__index". D.HasBattalion(bn): is it in that list.
function D.Battalions()
    return D.Load("dp_log", "__index", {})
end

function D.HasBattalion(bn)
    for _, b in ipairs(D.Battalions()) do
        if b == bn then return true end
    end
    return false
end

-- D.Banned(key, sid): is sid banned from writing/uploading to that book?
-- Bans are Data "dp_ban"/key = { ["s" .. sid] = name } (prefixed: JSON
-- would turn a bare SteamID64 key into a rounded number).
function D.Banned(key, sid)
    return sid ~= "" and D.Load("dp_ban", key, {})["s" .. sid] ~= nil
end

-- D.Note(pad, id): the note with that id on a pad list, and its index.
function D.Note(pad, id)
    for i, n in ipairs(pad) do
        if n.id == id then return n, i end
    end
end

local function sid(ply) return ply:SteamID64() or "" end

-- D.Pad(ply): the notes on this player's pad (live list from D.Load).
function D.Pad(ply)
    return D.Load("dp_pad", sid(ply), {})
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

-- Cuffed players an MP may jail/search from the datapad: escorted by them,
-- or within arrestRange with a clear line from the MP's eyes. Not jailed.
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

-- D.SendState(ply): send dp.state (what the datapad window shows). Sent on
-- open and after every pad change; an open window rebuilds from it.
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

-- D.PadRecv(name, fn(ply, len), limits, mpOnly): receive a datapad
-- message: the pad must be in hand and the sender alive. mpOnly: MPs only.
-- limits: Rhylib.Net rate limit (default 4/s, burst 6). Used here and by
-- sv_50/60/80/90.
function D.PadRecv(name, fn, limits, mpOnly)
    Rhylib.Net.Receive(name, function(ply, len)
        if not ply:Alive() or not D.Holding(ply) then return end
        if mpOnly and not D.IsMP(ply) then return end
        fn(ply, len)
    end, limits or { rate = 4, burst = 6 })
end

D.PadRecv("dp.open", function(ply) D.SendState(ply) end, { rate = 2, burst = 3 })

D.PadRecv("dp.get", function(ply)
    local id = net.ReadUInt(16)
    local n = D.Note(D.Pad(ply), id)
    if not n then return end
    Rhylib.Net.Start("dp.body")
    net.WriteUInt(id, 16)
    net.WriteString(n.b or "")
    net.Send(ply)
end)

D.PadRecv("dp.save", function(ply)
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
            Rhylib.Notify(ply, "You're banned from your battalion's logs", "bad", "Datapad")
            return
        end
        local limit = D.Limit(ply)
        if #pad >= (limit > 0 and limit or D.HARD_CAP) then
            Rhylib.Notify(ply, "Your datapad is full. Upload your notes at your battalion computer", "bad", "Datapad")
            return
        end
        local top = 0
        for _, o in ipairs(pad) do top = math.max(top, o.id or 0) end
        local n = { id = top % 65535 + 1, k = kind, ti = title, b = body, t = os.time() }   -- id: next free 16-bit id
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

D.PadRecv("dp.del", function(ply)
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
-- Hook Rhylib.MPSearchTool(ply, weapon) (rhylib_mp asks it): returns the
-- reach (arrestRange): the datapad searches anyone it could jail.
Rhylib.Hook.Add("Rhylib.MPSearchTool", "datapad", function(ply, w)
    if w:GetClass() == D.Cfg("class") then return D.Cfg("arrestRange") end
end)

-- Online players by name, plus everyone rhylib_mp has on file (Data
-- "mp_idx"/"all" = { ["s"..sid] = name }); at most 20.
D.PadRecv("dp.find", function(ply)
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

D.PadRecv("dp.rec", function(ply)
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

D.PadRecv("dp.olog", function(ply)
    Rhylib.Net.Start("dp.ologs")
    writeLogs(findLogs(function(e) return e.mp end, 80))
    net.Send(ply)
end, { rate = 2, burst = 3 }, true)

D.PadRecv("dp.lread", function(ply)
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

-- Jail from the datapad: the prisoner must still be in cuffedNear;
-- rhylib_mp's MP.Jail does the rest (and refuses with a reason).
D.PadRecv("dp.jail", function(ply)
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
        Rhylib.Notify(ply, "They need to be cuffed and close to you", "bad", "Datapad")
        return
    end
    local done, err = MP.Jail(p, ply, minutes, why)
    if not done and err then Rhylib.Notify(ply, err, "bad", "Datapad") end
    D.SendState(ply)
end, { rate = 2, burst = 3 }, true)

-- Config datapad giveOnSpawn (default on): a datapad for everyone on
-- spawn, so quick response calls are always to hand. Given the tick after
-- spawning, so rhylib_inventory takes it in as job gear (loadout).
Rhylib.Hook.Add("PlayerSpawn", "datapad.give", function(ply)
    if not D.Cfg("giveOnSpawn") or ply:IsBot() then return end
    timer.Simple(0, function()
        if not IsValid(ply) or not ply:Alive() then return end
        local class = D.Cfg("class")
        if not weapons.GetStored(class) or ply:HasWeapon(class) then return end
        local Inv = Rhylib.Inventory
        if Inv and Inv.Has and Inv.Has(ply, class) then return end
        ply:Give(class)
    end)
end)
