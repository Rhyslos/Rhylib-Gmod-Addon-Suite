--[[
    Battalion computer (server): orders, leave, applications, session
    sign-ups. Ranks come from rhylib_roster (Rhylib.Roster): "managers" are
    rank manageRank+ (SGT), "officers" boardRank+ (LT), admins always.
    Without rhylib_roster nobody below admin is a manager or officer.

    Orders        Data "dp_ord"/bn = { next, list { id, ti, b, to, by, bs, t,
                  st, sb, stt } }. to = { ["s"..sid] = name } or nil (whole
                  battalion). Managers issue them; status (D.ORDER_STATUS)
                  is set by managers (any) or the people ordered (In
                  progress / Completed), at the computer or on the datapad.
                  Assignees (or everyone) are told; the sync light blinks.
                  The old single text ("dp_orders") becomes the first order.
    Leave         Data "dp_loa"/bn = list { id, s, n, from, to, why }.
                  Members file their own; managers can remove any. Shown on
                  the roster page while it runs (Rhylib.RosterNote).
    Applications  Data "dp_apps"/bn = list { id, s, n, txt, t, st, by }
                  (st 0 pending, 1 accepted, 2 declined, 3 withdrawn) and
                  Data "dp_myapp"/sid = { bn, id, st }. A CT without a
                  battalion applies at its computer; managers accept or
                  decline. Accepted: a popup (now, or when they next join)
                  to join or turn it down. Not required: NCOs can still
                  whitelist directly on the roster page.
    Sessions      board posts (section Session) carry rv = { ["s"..sid] =
                  { n, s } } (1 attending, 2 maybe, 3 can't) and ci =
                  { ["s"..sid] = name } (checked in at the computer, from
                  15 min before to 60 min after the start; counts as the
                  "at" stat).

      dp.uopen  entity -> dp.unit: entity, member, manager, officer, can
                apply, my application's battalion + status (2), orders
                (D.WriteOrders), leave (count 6; id 16, name, from 32, to 32,
                reason, mine), applications for managers (count 6, at most
                30, pending first; id 16, name, text, time 32, status 2, by)
      dp.uorder   entity, title, text, n (7), n x sid (0 = whole battalion)
      dp.ustatus  entity, order id (16), status (3)
      dp.ostatus  (datapad, no entity) order id (16), status (3)
      dp.uodel    entity, order id (16)
      dp.uloa     entity, from (32), to (32), reason
      dp.uloadel  entity, leave id (16)
      dp.uapply   entity, text
      dp.udecide  entity, application id (16), accept (bool)
      dp.ursvp    entity, post id (16), choice (2: 1 attending, 2 maybe, 3 can't)
      dp.ucheck   entity, post id (16)
      dp.uwithdraw entity: withdraw your pending application
      dp.uappget  entity, application id -> dp.uappinfo (managers): the
                  applicant's own all-time stats, quals, commendations,
                  active strikes and arrest record (with reasons)
      dp.uanswer  (anywhere, bool) join? for an accepted application
      dp.uprompt  server -> player: kind (2: 0 pending note, 1 accepted
                  popup, 2 declined), battalion, decided by

    Hooks: answers Rhylib.RosterNote(bn, sid) ("on LOA until ...", shown on
    the roster page and personnel list); listens to Rhylib.RosterJoined
    (an application ends when the trooper joins any battalion) and
    PlayerInitialSpawn (applicants are told their status 12 s after joining).
]]

local D = Rhylib.Datapad
local Data = Rhylib.Data

for _, n in ipairs({ "dp.unit", "dp.uprompt", "dp.uappinfo" }) do Rhylib.Net.Register(n) end

local function sid(ply) return ply:SteamID64() or "" end
local function R() return Rhylib.Roster end

local function rankOf(ply, bn)
    local Ro = R()
    if not Ro then return 0 end
    local c = Ro.Get(ply)
    return c.bn == bn and c.rank or 0
end
local function atLeast(ply, bn, cfgKey, fallback)
    local Ro = R()
    local need = Ro and Ro.RankIndex(Ro.Cfg(cfgKey)) or fallback
    return rankOf(ply, bn) >= need
end
local function isManager(ply, bn, admin) return admin or atLeast(ply, bn, "manageRank", 4) end
local function isOfficer(ply, bn, admin) return admin or atLeast(ply, bn, "boardRank", 6) end
local function isMember(ply, bn) return bn ~= "" and D.Battalion(ply) == bn end
-- Exported rank helpers (server):
--   D.UnitRank(ply, bn)                -> rank index in bn (0 = not a member / no roster)
--   D.IsUnitManager(ply, bn, admin)    -> rank manageRank+ (SGT) in bn, or admin
--   D.IsUnitOfficer(ply, bn, admin)    -> rank boardRank+ (LT) in bn, or admin
--   D.IsUnitMember(ply, bn)            -> their job category is bn
-- The fallbacks 4 / 6 are SGT / LT on the default rank list.
D.UnitRank, D.IsUnitManager, D.IsUnitOfficer, D.IsUnitMember = rankOf, isManager, isOfficer, isMember

local function list(ns, bn)
    local t = D.Load(ns, bn, nil)
    if not t.list then t.next, t.list = 1, {} end
    return t
end

local function note(ply, msg) if IsValid(ply) then ply:ChatPrint(msg) end end

local function battalionPlayers(bn)
    local out = {}
    for _, p in ipairs(player.GetHumans()) do
        if D.Battalion(p) == bn then out[#out + 1] = p end
    end
    return out
end

--------------------------------------------------------------------------
-- Leave of absence
--------------------------------------------------------------------------

-- Leave that hasn't ended yet (drops old ones, a day after their end).
-- D.ActiveLeave(bn) -> { next, list } (sv_50 sends it in the download).
local function activeLeave(bn)
    local t = list("dp_loa", bn)
    local now = os.time()
    local keep, changed = {}, false
    for _, e in ipairs(t.list) do
        if (e.to or 0) + 86400 >= now then keep[#keep + 1] = e else changed = true end
    end
    if changed then
        t.list = keep
        D.Store("dp_loa", bn, t)
    end
    return t
end

D.ActiveLeave = activeLeave

Rhylib.Hook.Add("Rhylib.RosterNote", "datapad.loa", function(bn, id)
    local now = os.time()
    for _, e in ipairs(activeLeave(bn).list) do
        if e.s == id and e.from <= now + 86400 then
            return (e.from > now and "LOA from " .. os.date("%d %b", e.from) or "on LOA") .. " until " .. os.date("%d %b", e.to)
        end
    end
end)

--------------------------------------------------------------------------
-- Applications
--------------------------------------------------------------------------

-- The player's own application (Data "dp_myapp"/sid = { bn, id, st, by }), or nil.
local function myApp(id)
    local t = Data.Get("dp_myapp", id)
    if not istable(t) then return nil end
    -- Pending, but gone from the battalion's list (renamed, cleared): forget it.
    if t.st == 0 then
        local found = false
        for _, a in ipairs(list("dp_apps", t.bn or "").list) do
            if a.id == t.id and a.st == 0 then found = true break end
        end
        if not found then
            Data.Delete("dp_myapp", id)
            return nil
        end
    end
    return t
end

local function setApp(bn, appId, st, by)
    local t = list("dp_apps", bn)
    for _, a in ipairs(t.list) do
        if a.id == appId then
            a.st, a.by = st, by or a.by
            D.Store("dp_apps", bn, t)
            return a
        end
    end
end

-- What the applicant should be told (now, or when they join).
local function prompt(ply, kind, bn, by)
    Rhylib.Net.Start("dp.uprompt")
    net.WriteUInt(kind, 2)
    net.WriteString(bn)
    net.WriteString(by or "")
    net.Send(ply)
end

local function checkApplicant(ply)
    local id = sid(ply)
    local m = myApp(id)
    if not m then return end
    if m.st == 0 then
        prompt(ply, 0, m.bn)
    elseif m.st == 1 then
        prompt(ply, 1, m.bn, m.by)
    elseif m.st == 2 then
        prompt(ply, 2, m.bn, m.by)
        Data.Delete("dp_myapp", id)   -- told once
    end
end

Rhylib.Hook.Add("PlayerInitialSpawn", "datapad.apps", function(ply)
    timer.Simple(12, function() if IsValid(ply) then checkApplicant(ply) end end)
end)

-- Whitelisted another way: the application is done.
Rhylib.Hook.Add("Rhylib.RosterJoined", "datapad.apps", function(id, bn)
    local m = myApp(id)
    if m then
        if m.st == 0 or m.st == 1 then setApp(m.bn, m.id, m.bn == bn and 1 or 3) end
        Data.Delete("dp_myapp", id)
    end
end)

-- The applicant's answer to an accepted application (from the popup, anywhere).
Rhylib.Net.Receive("dp.uanswer", function(ply)
    local join = net.ReadBool()
    local id = sid(ply)
    local m = myApp(id)
    if not m or m.st ~= 1 then return end
    if join then
        local Ro = R()
        if Ro and Ro.AddMember(id, m.bn, ((m.by or "") ~= "" and m.by or "An officer") .. " accepted the application of") then
            Data.Delete("dp_myapp", id)   -- (RosterJoined clears it too)
            note(ply, "Welcome to the " .. m.bn .. "!")
        else
            note(ply, "You couldn't be added right now (already in a battalion, or not a trained trooper?)")
        end
    else
        Data.Delete("dp_myapp", id)
        setApp(m.bn, m.id, 3)
        note(ply, "You turned down the " .. m.bn .. ".")
    end
end, { rate = 2, burst = 3 })

--------------------------------------------------------------------------
-- The unit page
--------------------------------------------------------------------------

local STATUS = { [0] = "pending", [1] = "accepted", [2] = "declined", [3] = "withdrawn" }

function D.SendUnit(ply, ent, a)
    local bn = ent:GetBattalion()
    local admin = a.admin
    local member = isMember(ply, bn)
    local manager = a.view and isManager(ply, bn, admin) or false
    local leave = activeLeave(bn).list
    local m = myApp(sid(ply))
    local Ro = R()
    local c = Ro and Ro.Get(ply)

    Rhylib.Net.Start("dp.unit")
    net.WriteEntity(ent)
    net.WriteBool(member)
    net.WriteBool(manager)
    net.WriteBool(isOfficer(ply, bn, admin))
    -- Can apply: trained, no battalion, nothing pending.
    net.WriteBool(c and c.trained and c.bn == "" and not (m and (m.st == 0 or m.st == 1)) or false)
    net.WriteString(m and m.bn or "")
    net.WriteUInt(m and m.st or 0, 2)
    D.WriteOrders(ply, a.view and bn or "", manager)
    -- Leave (members and up see it).
    local nl = (member or admin) and math.min(#leave, 63) or 0
    net.WriteUInt(nl, 6)
    for i = 1, nl do
        local e = leave[i]
        net.WriteUInt(e.id, 16)
        net.WriteString(e.n or "?")
        net.WriteUInt(e.from or 0, 32)
        net.WriteUInt(e.to or 0, 32)
        net.WriteString(e.why or "")
        net.WriteBool(e.s == sid(ply))
    end
    -- Applications (managers): pending first, then the last few decided.
    local apps = {}
    if manager then
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.st == 0 and #apps < 30 then apps[#apps + 1] = x end
        end
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.st ~= 0 and #apps < 30 then apps[#apps + 1] = x end
        end
    end
    net.WriteUInt(#apps, 6)
    for _, x in ipairs(apps) do
        net.WriteUInt(x.id, 16)
        net.WriteString(x.n or "?")
        net.WriteString(x.txt or "")
        net.WriteUInt(x.t or 0, 32)
        net.WriteUInt(x.st or 0, 2)
        net.WriteString(x.by or "")
    end
    net.Send(ply)
end

local function unitTerm(ent) return not D.IsMedTerm(ent) and ent:GetBattalion() ~= "" end

D.TermRecv("dp.uopen", {
    run = function(ply, ent, a)
        if unitTerm(ent) then D.SendUnit(ply, ent, a) end
    end,
}, { rate = 3, burst = 4 })

--------------------------------------------------------------------------
-- Orders
--------------------------------------------------------------------------

-- Order statuses (index sent in 3 bits). 1-2 count as open, 3+ as closed.
-- cl_10_pad.lua has the same list for the clients.
D.ORDER_STATUS = { "Issued", "In progress", "Completed", "Success", "Failed", "Cancelled" }
local ORDER_KEEP, ORDER_SEND, ORDER_NAMES = 40, 25, 8   -- (keeps the message small)

local function orders(bn)
    local t = D.Load("dp_ord", bn, nil)
    if not t.list then
        t.next, t.list = 1, {}
        -- The old single text becomes the first order.
        local old = Data.Get("dp_orders", bn)
        if istable(old) and (old.txt or "") ~= "" then
            t.list[1] = { id = 1, ti = "Standing orders", b = old.txt, by = old.by or "?", t = old.t or os.time(), st = 1 }
            t.next = 2
            Data.Delete("dp_orders", bn)
            D.Store("dp_ord", bn, t)
        end
    end
    return t
end

local function assigned(o, id) return o.to == nil or o.to["s" .. id] ~= nil end

-- D.WriteOrders(ply, bn, manager): write bn's orders as ply sees them into
-- the current net message (read with D.ReadOrders on the client): count 6,
-- then per order id 16, title, text, by, time 32, status 3, status by,
-- status time 32, whole battalion, names in all (7), up to 8 names (4),
-- mine (named in it), can set status. Open ones first, newest first in each.
-- bn "" writes an empty list.
function D.WriteOrders(ply, bn, manager)
    local me = sid(ply)
    local open, closed = {}, {}
    if bn ~= "" then
        for _, o in ipairs(orders(bn).list) do
            if (o.st or 1) <= 2 then open[#open + 1] = o else closed[#closed + 1] = o end
        end
    end
    for _, o in ipairs(closed) do open[#open + 1] = o end
    local n = math.min(#open, ORDER_SEND)
    net.WriteUInt(n, 6)
    for i = 1, n do
        local o = open[i]
        net.WriteUInt(o.id, 16)
        net.WriteString(o.ti or "")
        net.WriteString(o.b or "")
        net.WriteString(o.by or "?")
        net.WriteUInt(o.t or 0, 32)
        net.WriteUInt(o.st or 1, 3)
        net.WriteString(o.sb or "")
        net.WriteUInt(o.stt or 0, 32)
        net.WriteBool(o.to == nil)
        local names = {}
        for _, name in pairs(o.to or {}) do names[#names + 1] = tostring(name) end
        table.sort(names)
        net.WriteUInt(math.min(#names, 127), 7)   -- how many in all
        local nn = math.min(#names, ORDER_NAMES)
        net.WriteUInt(nn, 4)
        for j = 1, nn do net.WriteString(names[j]) end
        local mine = o.to ~= nil and o.to["s" .. me] ~= nil
        net.WriteBool(mine)
        net.WriteBool(manager or (assigned(o, me) and o.to ~= nil))
    end
end

local function tellOrder(bn, o, msg)
    for _, p in ipairs(battalionPlayers(bn)) do
        if assigned(o, sid(p)) then p:ChatPrint(msg) end
    end
end

-- D.SetOrderStatus(ply, bn, id, st, admin): set an order's status.
-- Managers: any; the people named in it: In progress or Completed.
-- Returns true if it changed (saves, D.Touch, tells whoever issued it).
function D.SetOrderStatus(ply, bn, id, st, admin)
    if st < 1 or st > #D.ORDER_STATUS then return false end
    local t = orders(bn)
    for _, o in ipairs(t.list) do
        if o.id == id then
            local manager = isManager(ply, bn, admin)
            local named = o.to ~= nil and o.to["s" .. sid(ply)] ~= nil and isMember(ply, bn)
            if not manager and not (named and (st == 2 or st == 3)) then return false end
            if o.st == st then return false end
            o.st, o.sb, o.stt = st, ply:Nick(), os.time()
            D.Store("dp_ord", bn, t)
            D.Touch(bn)
            -- Tell whoever issued it (if online and not the one changing it).
            for _, p in ipairs(player.GetHumans()) do
                if p ~= ply and o.bs and sid(p) == o.bs then
                    p:ChatPrint(ply:Nick() .. " set your order \"" .. (o.ti or "") .. "\" to " .. D.ORDER_STATUS[st])
                end
            end
            return true
        end
    end
    return false
end

D.TermRecv("dp.uorder", {
    read = function()
        local arg = { ti = D.Clip(net.ReadString(), D.Cfg("titleMax")), b = D.Clip(net.ReadString(), 600, true), to = {} }
        for _ = 1, net.ReadUInt(7) do arg.to[#arg.to + 1] = string.sub(net.ReadString(), 1, 20) end
        return arg
    end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) or not a.view then return end
        local bn = ent:GetBattalion()
        if not isManager(ply, bn, a.admin) then return end
        if arg.ti == "" then arg.ti = "Orders" end
        -- Named members must be in the battalion.
        local to
        local Ro = R()
        if #arg.to > 0 and Ro then
            to = {}
            for _, id in ipairs(arg.to) do
                local c = string.match(id, "^%d+$") and Ro.Char(id)
                if c and c.bn == bn then to["s" .. id] = Ro.FullCharName(c) end
            end
            if next(to) == nil then
                note(ply, "None of those members are in the battalion any more")
                D.SendUnit(ply, ent, a)
                return
            end
        end
        local t = orders(bn)
        local o = { id = t.next, ti = arg.ti, b = arg.b, to = to, by = ply:Nick(), bs = sid(ply), t = os.time(), st = 1 }
        table.insert(t.list, 1, o)
        t.next = t.next % 65535 + 1
        -- Keep ORDER_KEEP: drop the oldest closed ones first, then the oldest.
        for i = #t.list, 1, -1 do
            if #t.list <= ORDER_KEEP then break end
            if (t.list[i].st or 1) > 2 then table.remove(t.list, i) end
        end
        while #t.list > ORDER_KEEP do table.remove(t.list) end
        D.Store("dp_ord", bn, t)
        D.Touch(bn)
        tellOrder(bn, o, "New order from " .. ply:Nick() .. ": " .. o.ti .. " (battalion computer or datapad)")
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.ustatus", {
    read = function() return { id = net.ReadUInt(16), st = net.ReadUInt(3) } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) or not a.view then return end
        D.SetOrderStatus(ply, ent:GetBattalion(), arg.id, arg.st, a.admin)
        D.SendUnit(ply, ent, a)
    end,
})

D.PadRecv("dp.ostatus", function(ply)
    local id, st = net.ReadUInt(16), net.ReadUInt(3)
    local bn = D.Battalion(ply)
    if bn ~= "" then D.SetOrderStatus(ply, bn, id, st, false) end
end, { rate = 3, burst = 4 })

D.TermRecv("dp.uodel", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not unitTerm(ent) or not a.view then return end
        local bn = ent:GetBattalion()
        if not isManager(ply, bn, a.admin) then return end
        local t = orders(bn)
        for i, o in ipairs(t.list) do
            if o.id == id then
                table.remove(t.list, i)
                D.Store("dp_ord", bn, t)
                D.Touch(bn)
                break
            end
        end
        D.SendUnit(ply, ent, a)
    end,
})

D.TermRecv("dp.uloa", {
    read = function() return { from = net.ReadUInt(32), to = net.ReadUInt(32), why = D.Clip(net.ReadString(), 120) } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isMember(ply, bn) then return end
        local now = os.time()
        if arg.to < arg.from or arg.to < now - 86400 or arg.to - arg.from > 120 * 86400 then
            note(ply, "Check the dates (at most 120 days, and not in the past)")
            return
        end
        local t = activeLeave(bn)
        -- One open leave per person: a new one replaces it.
        for i = #t.list, 1, -1 do
            if t.list[i].s == sid(ply) then table.remove(t.list, i) end
        end
        table.insert(t.list, 1, { id = t.next, s = sid(ply), n = ply:Nick(), from = arg.from, to = arg.to, why = arg.why })
        t.next = t.next % 65535 + 1
        D.Store("dp_loa", bn, t)
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 2, burst = 3 })

D.TermRecv("dp.uloadel", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        local t = activeLeave(bn)
        for i, e in ipairs(t.list) do
            if e.id == id and (e.s == sid(ply) or isManager(ply, bn, a.admin)) then
                table.remove(t.list, i)
                D.Store("dp_loa", bn, t)
                break
            end
        end
        D.SendUnit(ply, ent, a)
    end,
})

D.TermRecv("dp.uapply", {
    read = function() return D.Clip(net.ReadString(), 600, true) end,
    run = function(ply, ent, a, txt)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        local Ro = R()
        local c = Ro and Ro.Get(ply)
        local id = sid(ply)
        if id == "" or not c or not c.trained or c.bn ~= "" then
            note(ply, "Only clone troopers without a battalion can apply")
            return
        end
        local m = myApp(id)
        if m and (m.st == 0 or m.st == 1) then
            note(ply, "You already have an application with the " .. m.bn)
            return
        end
        if txt == "" then txt = "(no message)" end
        local t = list("dp_apps", bn)
        table.insert(t.list, 1, { id = t.next, s = id, n = ply:Nick(), txt = txt, t = os.time(), st = 0 })
        Data.Set("dp_myapp", id, { bn = bn, id = t.next, st = 0 })
        t.next = t.next % 65535 + 1
        -- Keep 100: drop the oldest decided ones (pending ones stay).
        for i = #t.list, 1, -1 do
            if #t.list <= 100 then break end
            if t.list[i].st ~= 0 then table.remove(t.list, i) end
        end
        D.Store("dp_apps", bn, t)
        note(ply, "Application sent to the " .. bn .. ". Check its status here at the battalion computer.")
        -- Tell the battalion's managers who are online.
        for _, p in ipairs(battalionPlayers(bn)) do
            if isManager(p, bn, false) then p:ChatPrint(ply:Nick() .. " applied to the " .. bn .. " (battalion computer, Applications)") end
        end
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 1, burst = 2 })

-- Withdraw your pending application (at that battalion's computer).
D.TermRecv("dp.uwithdraw", {
    run = function(ply, ent, a)
        if not unitTerm(ent) then return end
        local id = sid(ply)
        local m = myApp(id)
        if not m or m.st ~= 0 or m.bn ~= ent:GetBattalion() then return end
        setApp(m.bn, m.id, 3)
        Data.Delete("dp_myapp", id)
        note(ply, "Application withdrawn.")
        D.SendUnit(ply, ent, a)
    end,
}, { rate = 1, burst = 2 })

D.TermRecv("dp.uappget", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, appId)
        if not unitTerm(ent) or not a.view then return end
        local bn = ent:GetBattalion()
        if not isManager(ply, bn, a.admin) then return end
        local app
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.id == appId then app = x end
        end
        if not app or not app.s then return end
        local id = app.s
        Rhylib.Net.Start("dp.uappinfo")
        net.WriteUInt(appId, 16)
        local ps = D.PlayerStats and D.PlayerStats(id) or {}
        for _, k in ipairs(D.STAT_KEYS) do net.WriteUInt(math.Clamp(ps[k] or 0, 0, 2 ^ 31), 32) end
        -- Qualifications held.
        local Ro = R()
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
        -- Commendations and active strikes.
        local f = D.File and D.File(id) or { c = {}, s = {} }
        local strikes, now = 0, os.time()
        for _, x in ipairs(f.s or {}) do
            if (x.exp or 0) > now then strikes = strikes + 1 end
        end
        net.WriteUInt(math.min(#(f.c or {}), 255), 8)
        net.WriteUInt(math.min(strikes, 255), 8)
        -- Arrest record (rhylib_mp), newest first.
        local rec = Rhylib.MP and Rhylib.MP.GetRecord and Rhylib.MP.GetRecord(id) or {}
        local n = math.min(#rec, 50)
        net.WriteUInt(n, 6)
        for i = 1, n do
            local j = rec[i]
            net.WriteUInt(j.t or 0, 32)
            net.WriteString(j.by or "?")
            net.WriteUInt(math.Clamp(j.min or 0, 0, 1023), 10)
            net.WriteString(j.why or "")
        end
        net.Send(ply)
    end,
}, { rate = 4, burst = 6 })

D.TermRecv("dp.udecide", {
    read = function() return { id = net.ReadUInt(16), ok = net.ReadBool() } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isManager(ply, bn, a.admin) then return end
        local app
        for _, x in ipairs(list("dp_apps", bn).list) do
            if x.id == arg.id then app = x end
        end
        if not app or app.st ~= 0 then return end
        local st = arg.ok and 1 or 2
        setApp(bn, app.id, st, ply:Nick())
        local m = myApp(app.s)
        if m and m.bn == bn and m.id == app.id then
            m.st, m.by = st, ply:Nick()
            Data.Set("dp_myapp", app.s, m)
        end
        local target = player.GetBySteamID64(app.s)
        if IsValid(target) then checkApplicant(target) end
        D.SendUnit(ply, ent, a)
    end,
})

--------------------------------------------------------------------------
-- Sessions: sign-ups and check-in
--------------------------------------------------------------------------

local function findPost(bn, id)
    local b = D.Board(bn)
    for _, p in ipairs(b.list) do
        if p.id == id then return p, b end
    end
end

D.TermRecv("dp.ursvp", {
    read = function() return { id = net.ReadUInt(16), s = net.ReadUInt(2) } end,
    run = function(ply, ent, a, arg)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isMember(ply, bn) or arg.s < 1 or arg.s > 3 then return end
        local p, b = findPost(bn, arg.id)
        if not p or p.sec ~= D.SEC_SESSION then return end
        p.rv = p.rv or {}
        p.rv["s" .. sid(ply)] = { n = ply:Nick(), s = arg.s }
        D.StoreQuiet("dp_board", bn, b)
        D.SendPost(ply, p)
    end,
})

D.TermRecv("dp.ucheck", {
    read = function() return net.ReadUInt(16) end,
    run = function(ply, ent, a, id)
        if not unitTerm(ent) then return end
        local bn = ent:GetBattalion()
        if not isMember(ply, bn) then return end
        local p, b = findPost(bn, id)
        if not p or p.sec ~= D.SEC_SESSION then return end
        local now = os.time()
        if now < (p.at or 0) - 15 * 60 or now > (p.at or 0) + 60 * 60 then
            note(ply, "Check-in opens 15 minutes before the session and closes an hour after it starts")
            return
        end
        p.ci = p.ci or {}
        local key = "s" .. sid(ply)
        if p.ci[key] then return end
        p.ci[key] = ply:Nick()
        D.StoreQuiet("dp_board", bn, b)
        if D.AddStat then D.AddStat(ply, "at", 1) end
        note(ply, "Checked in for " .. (p.ti or "the session"))
        D.SendPost(ply, p)
    end,
})
