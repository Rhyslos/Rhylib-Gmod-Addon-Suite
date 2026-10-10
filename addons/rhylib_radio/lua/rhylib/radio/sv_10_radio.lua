--[[
    Radio (server): radio state, who hears whom, squads and channels.

    Squads:   R.squads[id] = { id, name, open, leader, ro, members = { [ply] = joined }, n }
    Channels: R.channels[id] = { id, name, mode, pass, bn, members = { [ply] = true }, n }
    A player: ply.rhylibRadio = { slots = { [1] = chanId, [2] = chanId }, call = callId }

    Messages (rates are per player: rate/s, burst)
      radio.dir     server -> everyone (next tick after a change, then at
                    most once per 1.5 s), or one player on request:
                    squad count (9), per squad id (9), name, open (bool),
                    leader, RO (entities), member count (8), per member
                    entindex (8) + role (5); channel count (9), per channel
                    id (9), name, mode (2), battalion ("" unless mode 2),
                    listeners (8). No passwords.
      radio.me      server -> player: own channel slot 1, slot 2, call id
                    (9 bits each, 0 = none)
      radio.pos     server -> squad members, every second: count (8), per
                    mate entindex (8) + x, y, z (Int 16 each)
      radio.note    server -> player: a short message (string) for chat
      radio.txev    server -> everyone who hears the old or new target:
                    talker entindex (8), tx kind (2), id (9)
      radio.state   client: off, muted, deafened (3 bools). 6, 6
      radio.role    client: role index (5). 3, 4
      radio.tx      client: radio key down: true + slot (2: 1 squad,
                    2 channel 1, 3 channel 2), or false (up). 12, 8
      radio.txoff   client: radio key up (no data). 40, 40
      radio.squad   client: op (3) + create/rename name | join squad id (9)
                    | kick/leader/RO player entity. 4, 6
      radio.chan    client: op (2) + slot - 1 (1) + create: name, mode (2),
                    password | join: channel id (9), password. 4, 6
      radio.dirreq  client: send me the directory and my slots. 1, 3

    State lives in memory only: a map change or restart clears every
    squad, channel and call.
]]

local R = Rhylib.Radio
local band, rshift = bit.band, bit.rshift

R.squads = R.squads or {}
R.channels = R.channels or {}

for _, n in ipairs({ "radio.dir", "radio.me", "radio.pos", "radio.note", "radio.txev" }) do Rhylib.Net.Register(n) end

-- R.P(ply): the server-side radio table of a player (made on first use):
-- { slots = { [1] = chanId, [2] = chanId }, call = callId }.
function R.P(ply)
    local p = ply.rhylibRadio
    if not p then
        p = { slots = {} }
        ply.rhylibRadio = p
    end
    return p
end

-- R.Note(ply, text): a "[Radio] text" chat line for one player. Server.
-- (The client has its own R.Note(text) in cl_10_client.lua.)
function R.Note(ply, text)
    if not IsValid(ply) then return end
    Rhylib.Net.Start("radio.note")
    net.WriteString(text)
    net.Send(ply)
end

-- R.Set(ply, fields): change some fields of a player's radio state
-- (names as in R.Unpack); writes the NW2Int only if it changed. Use
-- R.SetTx for txKind/txId so listeners get radio.txev too. Server.
-- Example: Rhylib.Radio.Set(ply, { muted = true })
function R.Set(ply, fields)
    local t = R.Unpack(R.Raw(ply))
    for k, v in pairs(fields) do t[k] = v end
    local v = R.Pack(t)
    if v ~= R.Raw(ply) then ply:SetNW2Int("rhylib_radio", v) end
end

-- Who can hear a radio target (for radio.txev).
local function hearers(kind, id)
    local list = {}
    if kind == R.TX_SQUAD then
        local sq = R.squads[id]
        for p in pairs(sq and sq.members or {}) do if IsValid(p) then list[#list + 1] = p end end
    elseif kind == R.TX_CHAN then
        local c = R.channels[id]
        for p in pairs(c and c.members or {}) do if IsValid(p) then list[#list + 1] = p end end
    elseif kind == R.TX_CALL then
        local c = R.calls and R.calls[id]
        for p in pairs(c and c.members or {}) do if IsValid(p) then list[#list + 1] = p end end
    end
    return list
end

-- R.SetTx(ply, kind, id): start / stop sending (kind R.TX_*, id of the
-- squad / channel / call; 0, 0 = stop). Besides the NW2 state (late for
-- players out of view), the people who hear that target get a small
-- event (radio.txev) so their meters and voice list know at once.
-- Example: Rhylib.Radio.SetTx(ply, 0, 0)   -- let go of the radio key
function R.SetTx(ply, kind, id)
    local t = R.State(ply)
    if t.txKind == kind and t.txId == id then return end
    local oldKind, oldId = t.txKind, t.txId
    R.Set(ply, { txKind = kind, txId = id })
    local to = {}
    local seen = {}
    for _, l in ipairs({ hearers(oldKind, oldId), hearers(kind, id) }) do
        for _, p in ipairs(l) do
            if not seen[p] and p ~= ply then seen[p] = true to[#to + 1] = p end
        end
    end
    if #to == 0 then return end
    Rhylib.Net.Start("radio.txev")
    net.WriteUInt(ply:EntIndex(), 8)
    net.WriteUInt(kind, 2)
    net.WriteUInt(id, R.ID_BITS)
    net.Send(to)
end

-- Stop sending if it was on this target.
local function clearTx(ply, kind, id)
    local t = R.State(ply)
    if t.txKind == kind and (id == nil or t.txId == id) then R.SetTx(ply, 0, 0) end
end
R.ClearTx = clearTx

-- Lowest unused id in a table keyed 1..R.MAX_ID (nil when full).
local function freeId(tbl)
    for i = 1, R.MAX_ID do
        if not tbl[i] then return i end
    end
end

--------------------------------------------------------------------------
-- Directory and own state
--------------------------------------------------------------------------

local function writeDir()
    local list = {}
    for _, sq in pairs(R.squads) do list[#list + 1] = sq end
    net.WriteUInt(#list, R.ID_BITS)
    for _, sq in ipairs(list) do
        net.WriteUInt(sq.id, R.ID_BITS)
        net.WriteString(sq.name)
        net.WriteBool(sq.open)
        net.WriteEntity(sq.leader)
        net.WriteEntity(IsValid(sq.ro) and sq.ro or NULL)
        local mem = {}
        for p in pairs(sq.members) do if IsValid(p) then mem[#mem + 1] = p end end
        -- Oldest first, so the list doesn't jump around.
        table.sort(mem, function(a, b) return sq.members[a] < sq.members[b] end)
        net.WriteUInt(#mem, 8)
        for _, p in ipairs(mem) do
            net.WriteUInt(p:EntIndex(), 8)
            net.WriteUInt(R.RoleOf(p), 5)
        end
    end
    local ch = {}
    for _, c in pairs(R.channels) do ch[#ch + 1] = c end
    net.WriteUInt(#ch, R.ID_BITS)
    for _, c in ipairs(ch) do
        net.WriteUInt(c.id, R.ID_BITS)
        net.WriteString(c.name)
        net.WriteUInt(c.mode, 2)
        net.WriteString(c.mode == R.MODE_BN and c.bn or "")
        net.WriteUInt(math.min(c.n, 255), 8)
    end
end

local function sendDir(target)
    Rhylib.Net.Start("radio.dir")
    writeDir()
    if target then net.Send(target) else net.Broadcast() end
end

-- R.Dirty(): the directory changed; schedule a radio.dir broadcast.
-- At most one broadcast per 1.5 s: the first change goes out next tick,
-- a burst after it (event start, many joins) goes out once at the end.
local lastDir = 0
function R.Dirty()
    if timer.Exists("Rhylib.Radio.Dir") then return end
    local wait = math.max(0, lastDir + 1.5 - CurTime())
    timer.Create("Rhylib.Radio.Dir", wait, 1, function()
        lastDir = CurTime()
        sendDir()
    end)
end

-- R.SendMe(ply): sends radio.me (own channel slots and call) to ply.
function R.SendMe(ply)
    if not IsValid(ply) then return end
    local p = R.P(ply)
    Rhylib.Net.Start("radio.me")
    net.WriteUInt(p.slots[1] or 0, R.ID_BITS)
    net.WriteUInt(p.slots[2] or 0, R.ID_BITS)
    net.WriteUInt(p.call or 0, R.ID_BITS)
    net.Send(ply)
end

--------------------------------------------------------------------------
-- Squads
--------------------------------------------------------------------------

local function setRanks(sq)
    for p in pairs(sq.members) do
        if IsValid(p) then R.Set(p, { leader = sq.leader == p, ro = sq.ro == p }) end
    end
end

-- R.LeaveSquad(ply): takes ply out of their squad (stops their squad
-- talk). If they led it, the RO takes over, else whoever joined first.
-- An empty squad (or one left with no valid leader) is removed.
-- (`quiet` is unused.) Server.
function R.LeaveSquad(ply, quiet)
    local id = R.SquadOf(ply)
    local sq = R.squads[id]
    if IsValid(ply) then
        R.Set(ply, { squad = 0, leader = false, ro = false })
        clearTx(ply, R.TX_SQUAD)
    end
    if not sq then return end
    sq.members[ply] = nil
    sq.n = sq.n - 1
    if sq.ro == ply then sq.ro = nil end
    if sq.leader == ply then
        -- The RO takes over, else whoever has been in longest.
        local nxt = IsValid(sq.ro) and sq.ro or nil
        if not nxt then
            local best
            for p, t in pairs(sq.members) do
                if IsValid(p) and (not best or t < best) then nxt, best = p, t end
            end
        end
        sq.leader = nxt
        if nxt == sq.ro then sq.ro = nil end
        if IsValid(nxt) then R.Note(nxt, "You lead " .. sq.name .. " now") end
    end
    if sq.n <= 0 or not IsValid(sq.leader) then
        for p in pairs(sq.members) do
            if IsValid(p) then R.Set(p, { squad = 0, leader = false, ro = false }) clearTx(p, R.TX_SQUAD) end
        end
        R.squads[id] = nil
    else
        setRanks(sq)
    end
    R.Dirty()
end

-- R.JoinSquad(ply, sq): puts ply in squad table sq (from R.squads),
-- leaving their old squad first. Does not check sq.open (the net
-- handler does). Server.
-- Example: Rhylib.Radio.JoinSquad(ply, Rhylib.Radio.squads[3])
function R.JoinSquad(ply, sq)
    if R.SquadOf(ply) == sq.id then return end
    if R.SquadOf(ply) ~= 0 then R.LeaveSquad(ply) end
    sq.members[ply] = SysTime()
    sq.n = sq.n + 1
    R.Set(ply, { squad = sq.id, leader = sq.leader == ply, ro = sq.ro == ply })
    R.Dirty()
end

local function newSquad(ply, name)
    local id = freeId(R.squads)
    if not id then return R.Note(ply, "No room for more squads") end
    name = R.CleanName(name)
    if name == "" then name = "Squad " .. id end
    local sq = { id = id, name = name, open = true, leader = ply, members = {}, n = 0 }
    R.squads[id] = sq
    R.JoinSquad(ply, sq)
    setRanks(sq)
end

-- radio.squad ops (client side: R.SQ in cl_10_client.lua). Lock, rename,
-- kick, leader and RO need the sender to lead the squad.
local SQ_CREATE, SQ_JOIN, SQ_LEAVE, SQ_LOCK, SQ_RENAME, SQ_KICK, SQ_LEADER, SQ_RO = 0, 1, 2, 3, 4, 5, 6, 7

Rhylib.Net.Receive("radio.squad", function(ply)
    local op = net.ReadUInt(3)
    local mine = R.squads[R.SquadOf(ply)]
    if op == SQ_CREATE then
        newSquad(ply, net.ReadString())
    elseif op == SQ_JOIN then
        local sq = R.squads[net.ReadUInt(R.ID_BITS)]
        if not sq then return end
        if not sq.open then return R.Note(ply, sq.name .. " is locked") end
        R.JoinSquad(ply, sq)
    elseif op == SQ_LEAVE then
        if mine then R.LeaveSquad(ply) end
    elseif mine and mine.leader == ply then
        if op == SQ_LOCK then
            mine.open = not mine.open
        elseif op == SQ_RENAME then
            local n = R.CleanName(net.ReadString())
            if n ~= "" then mine.name = n end
        else
            local t = net.ReadEntity()
            if not (IsValid(t) and t:IsPlayer() and mine.members[t]) or t == ply then return end
            if op == SQ_KICK then
                R.LeaveSquad(t)
                R.Note(t, "You were removed from " .. mine.name)
            elseif op == SQ_LEADER then
                if mine.ro == t then mine.ro = nil end
                mine.leader = t
                R.Note(t, "You lead " .. mine.name .. " now")
                setRanks(mine)
            elseif op == SQ_RO then
                mine.ro = (mine.ro ~= t) and t or nil
                setRanks(mine)
            end
        end
        R.Dirty()
    end
end, { rate = 4, burst = 6 })

--------------------------------------------------------------------------
-- Channels
--------------------------------------------------------------------------

-- R.LeaveChannel(ply, slot): leaves the channel in slot 1 or 2; a channel
-- with nobody left is removed. Server.
function R.LeaveChannel(ply, slot)
    local p = R.P(ply)
    local id = p.slots[slot]
    if not id then return end
    p.slots[slot] = nil
    clearTx(ply, R.TX_CHAN, id)
    local c = R.channels[id]
    if c and c.members[ply] then
        c.members[ply] = nil
        c.n = c.n - 1
        if c.n <= 0 then R.channels[id] = nil end
    end
    R.SendMe(ply)
    R.Dirty()
end

local function joinChannel(ply, slot, c)
    local p = R.P(ply)
    if p.slots[slot] == c.id then return end
    local other = slot == 1 and 2 or 1
    if p.slots[other] == c.id then return R.Note(ply, "You're already in " .. c.name) end
    if p.slots[slot] then R.LeaveChannel(ply, slot) end
    p.slots[slot] = c.id
    c.members[ply] = true
    c.n = c.n + 1
    R.SendMe(ply)
    R.Dirty()
end

local CH_CREATE, CH_JOIN, CH_LEAVE = 0, 1, 2
-- (create: an empty name is refused, mode password with no password
-- becomes open, the creator's battalion is stored for battalion mode)

Rhylib.Net.Receive("radio.chan", function(ply)
    local op = net.ReadUInt(2)
    local slot = net.ReadUInt(1) + 1
    if op == CH_CREATE then
        local name = R.CleanName(net.ReadString())
        local mode = net.ReadUInt(2)
        local pass = string.sub(net.ReadString(), 1, R.NAME_LEN)
        if name == "" then return R.Note(ply, "Give the channel a name") end
        if table.Count(R.channels) >= R.Cfg("maxChannels") then return R.Note(ply, "No room for more channels") end
        local id = freeId(R.channels)
        if not id then return end
        if mode > R.MODE_BN then mode = R.MODE_OPEN end
        if mode == R.MODE_PASS and pass == "" then mode = R.MODE_OPEN end
        local c = { id = id, name = name, mode = mode, pass = pass, bn = R.Battalion(ply), members = {}, n = 0 }
        R.channels[id] = c
        joinChannel(ply, slot, c)
    elseif op == CH_JOIN then
        local c = R.channels[net.ReadUInt(R.ID_BITS)]
        local pass = net.ReadString()
        if not c then return end
        if c.mode == R.MODE_PASS and pass ~= c.pass then return R.Note(ply, "Wrong password for " .. c.name) end
        if c.mode == R.MODE_BN and R.Battalion(ply) ~= c.bn then return R.Note(ply, c.name .. " is for " .. c.bn .. " only") end
        joinChannel(ply, slot, c)
    elseif op == CH_LEAVE then
        R.LeaveChannel(ply, slot)
    end
end, { rate = 4, burst = 6 })

--------------------------------------------------------------------------
-- Radio state, role, sending
--------------------------------------------------------------------------

Rhylib.Net.Receive("radio.state", function(ply)
    local off, muted, deaf = net.ReadBool(), net.ReadBool(), net.ReadBool()
    R.Set(ply, { off = off, muted = muted, deaf = deaf })
    if off or muted then R.SetTx(ply, 0, 0) end
    if off and R.HangUp then R.HangUp(ply) end
end, { rate = 6, burst = 6 })

Rhylib.Net.Receive("radio.role", function(ply)
    local r = net.ReadUInt(5)
    if R.ROLES[r] then
        R.Set(ply, { role = r })
        if R.SquadOf(ply) ~= 0 then R.Dirty() end
    end
end, { rate = 3, burst = 4 })

-- Radio key: slot 1 squad, 2 channel 1, 3 channel 2. A hail call wins.
Rhylib.Net.Receive("radio.tx", function(ply)
    local on = net.ReadBool()
    local slot = net.ReadUInt(2)
    if not on then
        R.SetTx(ply, 0, 0)
        return
    end
    local t = R.State(ply)
    if t.off or t.muted or not ply:Alive() then return end
    if ply.rhylibJammed then return end   -- (jammer: static only, heard as local voice)
    local p = R.P(ply)
    if p.call and R.CallLive and R.CallLive(p.call) then
        R.SetTx(ply, R.TX_CALL, p.call)
    elseif slot == 1 and t.squad ~= 0 then
        R.SetTx(ply, R.TX_SQUAD, t.squad)
    elseif (slot == 2 or slot == 3) and p.slots[slot - 1] then
        R.SetTx(ply, R.TX_CHAN, p.slots[slot - 1])
    end
end, { rate = 12, burst = 8 })

-- Key up on its own message with a loose limit, so a dropped one can't
-- leave the radio stuck on (the client also sends it twice).
Rhylib.Net.Receive("radio.txoff", function(ply)
    R.SetTx(ply, 0, 0)
end, { rate = 40, burst = 40 })

Rhylib.Net.Receive("radio.dirreq", function(ply)
    sendDir(ply)
    R.SendMe(ply)
end, { rate = 1, burst = 3 })

--------------------------------------------------------------------------
-- Who hears whom (called by the engine for every pair, often: lookups only)
--------------------------------------------------------------------------

-- Local voice range squared, re-read from config every 5 s (so a
-- Server settings change applies without a map change).
local range2 = 800 * 800
timer.Create("Rhylib.Radio.Range", 5, 0, function()
    local r = R.Cfg("localRange") or 800
    range2 = r * r
end)

-- The engine asks for every pair of players (80 players = ~6300 pairs) on
-- each voice update, so each player's alive flag, radio state and position
-- are read once per tick into a reused table.
local function snap(p)
    local s = p.rhylibVoiceSnap
    if not s then
        s = {}
        p.rhylibVoiceSnap = s
    end
    local tick = engine.TickCount()
    if s.tick ~= tick then
        s.tick = tick
        s.alive = p:Alive()
        s.rv = p:GetNW2Int("rhylib_radio", 0)
        s.jam = p.rhylibJammed == true
        local pos = p:GetPos()
        s.x, s.y, s.z = pos.x, pos.y, pos.z
    end
    return s
end

-- Returns hear, 3D. Radio (not 3D) when the talker sends on a target the
-- listener is in, both radios on, talker not muted, listener not
-- deafened, neither jammed; otherwise local 3D voice within localRange.
-- Dead talkers are heard by nobody. Priority 10: after rhylib_admin's
-- gag (-50). The bit tests: band(tv, 3) == 0 = not off and not muted,
-- band(lv, 5) == 0 = not off and not deafened (see sh_00_config).
Rhylib.Hook.Add("PlayerCanHearPlayersVoice", "radio.voice", function(listener, talker)
    if listener == talker then return end
    local ts = snap(talker)
    if not ts.alive then return false, false end
    local tv = ts.rv
    local kind = band(rshift(tv, 3), 3)
    if kind ~= 0 and band(tv, 3) == 0 and not ts.jam and not snap(listener).jam then   -- (comms jammer: local only)
        local lv = snap(listener).rv
        if band(lv, 5) == 0 then
            local id = band(rshift(tv, 5), 511)
            local hear
            if kind == 1 then
                hear = band(rshift(lv, 14), 511) == id and band(rshift(tv, 14), 511) == id
            elseif kind == 2 then
                local c = R.channels[id]
                hear = c and c.members[listener] and c.members[talker]
            else
                local c = R.calls and R.calls[id]
                hear = c and c.members[listener] and c.members[talker]
            end
            if hear then return true, false end
        end
    end
    local ls = snap(listener)
    local dx, dy, dz = ls.x - ts.x, ls.y - ts.y, ls.z - ts.z
    return dx * dx + dy * dy + dz * dz <= range2, true
end, 10)

--------------------------------------------------------------------------
-- Squad mates' positions, once a second, to each squad
--------------------------------------------------------------------------

timer.Create("Rhylib.Radio.Pos", 1, 0, function()
    for _, sq in pairs(R.squads) do
        if sq.n > 1 then
            local list = {}
            for p in pairs(sq.members) do if IsValid(p) and p:Alive() then list[#list + 1] = p end end
            if #list > 1 then
                Rhylib.Net.Start("radio.pos")
                net.WriteUInt(#list, 8)
                for _, p in ipairs(list) do
                    local pos = p:GetPos()
                    net.WriteUInt(p:EntIndex(), 8)
                    net.WriteInt(math.Clamp(math.floor(pos.x), -32767, 32767), 16)
                    net.WriteInt(math.Clamp(math.floor(pos.y), -32767, 32767), 16)
                    net.WriteInt(math.Clamp(math.floor(pos.z), -32767, 32767), 16)
                end
                net.Send(list)
            end
        end
    end
end)

--------------------------------------------------------------------------
-- Leaving
--------------------------------------------------------------------------

Rhylib.Hook.Add("PlayerDisconnected", "radio.leave", function(ply)
    if R.HangUp then R.HangUp(ply) end
    if R.SquadOf(ply) ~= 0 then R.LeaveSquad(ply) end
    local p = R.P(ply)
    for slot = 1, 2 do
        local id = p.slots[slot]
        local c = id and R.channels[id]
        if c and c.members[ply] then
            c.members[ply] = nil
            c.n = c.n - 1
            if c.n <= 0 then R.channels[id] = nil end
        end
    end
    p.slots = {}
    R.Dirty()
end)

-- Dying lets go of the radio key.
Rhylib.Hook.Add("PlayerDeath", "radio.death", function(ply)
    R.SetTx(ply, 0, 0)
end)

--------------------------------------------------------------------------
-- Comms jammers (2026-10-07): who is inside one, twice a second
--------------------------------------------------------------------------

-- Every jammer entity: [ent] = true. Jammers add themselves in
-- Initialize (rhylib_eod's interference devices too); any entry needs
-- GetActive() and is measured with R.JammerRange.
R.jammers = R.jammers or {}

-- Per player: inside a jammer's range = jammed. In the fringe outside it
-- (radio jammerFringe × range) NW2Float rhylib_jamLevel rises from 0 at the
-- outer edge towards 1 at the range (the client breaks up the compass and
-- adds static). Leaving the range keeps the radio jammed for
-- jamReconnect seconds (NW2Float rhylib_jamUntil = when it reconnects).
local function setLevel(p, lvl)
    lvl = math.floor(lvl * 20 + 0.5) / 20   -- (5% steps: no NW2 spam)
    if p.rhylibJamLevel ~= lvl then
        p.rhylibJamLevel = lvl
        p:SetNW2Float("rhylib_jamLevel", lvl)
    end
end

local function setJammed(p, jam)
    if (p.rhylibJammed == true) == jam then return end
    p.rhylibJammed = jam or nil
    p:SetNW2Bool("rhylib_jammed", jam)
    if jam then R.SetTx(p, 0, 0) end   -- (drop a radio key already held)
end

timer.Create("Rhylib.Radio.Jam", 0.5, 0, function()
    local list, wholeMap = {}, false
    for j in pairs(R.jammers) do
        if not IsValid(j) then
            R.jammers[j] = nil
        elseif j:GetActive() then
            local r = R.JammerRange(j)
            if r == math.huge then wholeMap = true else list[#list + 1] = { j:GetPos(), r } end
        end
    end
    local fringe = math.max(0, R.Cfg("jammerFringe") or 0.35)
    local reconnect = math.max(0, R.Cfg("jamReconnect") or 4)
    local now = CurTime()
    for _, p in ipairs(player.GetAll()) do
        local inside, lvl = false, 0
        if p:Alive() then
            if wholeMap then
                inside = true
            elseif #list > 0 then
                local pos = p:GetPos()
                for _, e in ipairs(list) do
                    local d = e[1]:Distance(pos)
                    if d <= e[2] then inside = true break end
                    local band = e[2] * fringe
                    if band > 0 and d < e[2] + band then
                        lvl = math.max(lvl, 1 - (d - e[2]) / band)
                    end
                end
            end
        end
        if inside then
            p.rhylibJamUntil = nil
            if p:GetNW2Float("rhylib_jamUntil", 0) ~= 0 then p:SetNW2Float("rhylib_jamUntil", 0) end
            setJammed(p, true)
            setLevel(p, 1)
        elseif p.rhylibJammed and p:Alive() and reconnect > 0 then
            -- left the range: reconnecting, still jammed until it's done
            if not p.rhylibJamUntil then
                p.rhylibJamUntil = now + reconnect
                p:SetNW2Float("rhylib_jamUntil", p.rhylibJamUntil)
            end
            if now >= p.rhylibJamUntil then
                p.rhylibJamUntil = nil
                p:SetNW2Float("rhylib_jamUntil", 0)
                setJammed(p, false)
            end
            setLevel(p, lvl)
        else
            if p.rhylibJamUntil then
                p.rhylibJamUntil = nil
                p:SetNW2Float("rhylib_jamUntil", 0)
            end
            setJammed(p, false)
            setLevel(p, lvl)
        end
    end
end)

-- Explosions (hook Rhylib.Explosion(pos, reach, tier, attacker, inflictor,
-- kind) from rhylib_republic grenades and HE charges, rhylib_weapons
-- rockets): jammers within reach (nearest point of the model) get
-- ENT:ExplosiveHit(tier, attacker, kind). Only players' explosions count
-- (or an inflictor flagged rhylibPlayerCharge).
Rhylib.Hook.Add("Rhylib.Explosion", "radio.jammers", function(pos, reach, tier, attacker, inflictor, kind)
    local byPlayer = IsValid(attacker) and attacker:IsPlayer()
    if not byPlayer and not (IsValid(inflictor) and inflictor.rhylibPlayerCharge) then return end
    local r2 = (reach or 0) ^ 2
    for j in pairs(R.jammers) do
        if IsValid(j) and not j.destroyed and j.ExplosiveHit and j:NearestPoint(pos):DistToSqr(pos) <= r2 then
            j:ExplosiveHit(tier or 1, IsValid(attacker) and attacker or nil, kind)
        end
    end
end)

-- Saved per map with rhylib_radio_save (toolgun entries jammer*).
local JAMMER = "rhylib_comms_jammer"

-- R.SaveJammers(): writes Data "radio_jammers" / <map> = list of
-- { pos = {x,y,z}, ang = {p,y,r}, on, class } for every jammer that is
-- permanent (rhylib_core Rhylib.Perma; without it, every jammer).
-- Returns how many were saved. Server.
function R.SaveJammers()
    local rows = {}
    for _, j in ipairs(ents.FindByClass(JAMMER .. "*")) do
        if R.JAMMER_SIZES[j:GetClass()] and (not Rhylib.Perma or Rhylib.Perma.Is(j)) then   -- (only permanent ones, 2026-10-09u)
            local p, a = j:GetPos(), j:GetAngles()
            -- (a shot-up jammer is saved as it was before: it's back next map)
            local on = j.destroyed and j.wasOn or j:GetActive()
            rows[#rows + 1] = { pos = { p.x, p.y, p.z }, ang = { a.p, a.y, a.r }, on = on, class = j:GetClass() }
        end
    end
    Rhylib.Data.Set("radio_jammers", game.GetMap(), rows)
    return #rows
end

-- R.SpawnJammers(): spawns the saved jammers for this map and marks them
-- permanent. Runs 1 s after InitPostEntity and after every map cleanup.
-- Old rows without a class load as small jammers. Server.
function R.SpawnJammers()
    local rows = Rhylib.Data.Get("radio_jammers", game.GetMap())
    if not istable(rows) then return end
    for _, row in ipairs(rows) do
        local class = R.JAMMER_SIZES[row.class or ""] and row.class or JAMMER
        local j = ents.Create(class)
        if IsValid(j) then
            j:SetPos(Vector(row.pos[1], row.pos[2], row.pos[3]))
            j:SetAngles(Angle(row.ang[1], row.ang[2], row.ang[3]))
            j.startOff = row.on == false
            j:Spawn()
            if Rhylib.Perma then Rhylib.Perma.Mark(j, true) end
        end
    end
end

Rhylib.Hook.Add("InitPostEntity", "radio.jammers", function() timer.Simple(1, R.SpawnJammers) end)
Rhylib.Hook.Add("PostCleanupMap", "radio.jammers", R.SpawnJammers)
-- Placement classes (rhylib_admin's !freezeprops leaves them alone), and
-- the Permanent tool's saver for these classes (rhylib_core Rhylib.Perma).
Rhylib.PLACEMENT_CLASSES = Rhylib.PLACEMENT_CLASSES or {}
for class in pairs(R.JAMMER_SIZES) do Rhylib.PLACEMENT_CLASSES[class] = true end
if Rhylib.Perma and Rhylib.Perma.Register then
    local list = {}
    for class in pairs(R.JAMMER_SIZES) do list[#list + 1] = class end
    Rhylib.Perma.Register(list, R.SaveJammers)
end

Rhylib.Perms.Register("rhylib.radio.admin", "admin", "Place, switch and save comms jammers")
-- rhylib_radio_save: save the jammers now (perm rhylib.radio.admin, or the
-- server console).
concommand.Add("rhylib_radio_save", function(ply)
    local function reply(m) if IsValid(ply) then ply:ChatPrint(m) else print(m) end end
    Rhylib.Perms.Check(ply, "rhylib.radio.admin", function(ok)
        if not ok then return reply("You don't have permission for rhylib_radio_save") end
        reply("Saved " .. R.SaveJammers() .. " comms jammers for " .. game.GetMap())
    end)
end)
