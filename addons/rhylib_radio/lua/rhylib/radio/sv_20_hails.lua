--[[
    Hails (server): a private radio line outside the channels.

    Hail a squad (rings its leader and radio operator) or one player. Those
    rung hear a beep until they answer or decline on the Radio page, or
    hailTime runs out. Answering joins the call; the radio key then sends
    on it. The caller hanging up ends it for everyone; anyone else hanging
    up only leaves. A call with one person left and nobody ringing ends.

    R.calls[id] = { id, caller, label, members = { [ply] = true }, ringing = { [ply] = until }, started }

    Messages (client rates per player: rate/s, burst)
      radio.hail    client: kind (2) then squad id (9, kind 1) or player
                    entity (kind 2). 1, 3
      radio.answer  client: call id (9), yes / no (bool). 4, 4
      radio.hangup  client: no data. 2, 3
      radio.ring    server -> player rung: call id (9), on (bool); when on
                    also caller entity and label (string)
      radio.call    server -> people in a call (and the caller while it
                    rings): id (9; 0 = no call, nothing follows), started
                    (float, CurTime), label, caller entity, ringing count
                    (8), member count (8), member entities

    The label is what the people rung see: the caller's squad name, or
    their own name when they have no squad. Calls are tx kind 3
    (R.TX_CALL); while a call has 2+ members the radio key sends on it.
    Memory only, like squads.
]]

local R = Rhylib.Radio

R.calls = R.calls or {}

for _, n in ipairs({ "radio.ring", "radio.call" }) do Rhylib.Net.Register(n) end

local function ring(ply, c, on)
    if not IsValid(ply) then return end
    Rhylib.Net.Start("radio.ring")
    net.WriteUInt(c.id, R.ID_BITS)
    net.WriteBool(on)
    if on then
        net.WriteEntity(c.caller)
        net.WriteString(c.label)
    end
    net.Send(ply)
end

-- The call as its members see it.
local function sendCall(c, to)
    local mem = {}
    for p in pairs(c.members) do if IsValid(p) then mem[#mem + 1] = p end end
    local n = 0
    for p in pairs(c.ringing) do if IsValid(p) then n = n + 1 end end
    Rhylib.Net.Start("radio.call")
    net.WriteUInt(c.id, R.ID_BITS)
    net.WriteFloat(c.started or 0)
    net.WriteString(c.label)
    net.WriteEntity(c.caller)
    net.WriteUInt(n, 8)
    net.WriteUInt(#mem, 8)
    for _, p in ipairs(mem) do net.WriteEntity(p) end
    net.Send(to or mem)
end

local function noCall(ply)
    if not IsValid(ply) then return end
    Rhylib.Net.Start("radio.call")
    net.WriteUInt(0, R.ID_BITS)
    net.Send(ply)
end

-- R.CallLive(id): true when call id exists and has 2 or more members
-- (someone answered). Server.
function R.CallLive(id)
    local c = R.calls[id]
    return c ~= nil and table.Count(c.members) >= 2
end

local function endCall(c, why)
    if not R.calls[c.id] then return end
    R.calls[c.id] = nil
    for p in pairs(c.ringing) do ring(p, c, false) end
    for p in pairs(c.members) do
        if IsValid(p) then
            local pd = R.P(p)
            if pd.call == c.id then pd.call = nil end
            R.ClearTx(p, R.TX_CALL, c.id)
            noCall(p)
            if why then R.Note(p, why) end
        end
    end
end

-- Nobody left to talk to: end it.
local function checkEnd(c)
    if R.calls[c.id] and table.Count(c.members) < 2 and next(c.ringing) == nil then
        endCall(c, "No answer")
        return true
    end
end

-- R.HangUp(ply): leaves (or, for the caller, ends) whatever call the
-- player is in, and declines anything still ringing for them. Also runs
-- when they turn the radio off or disconnect. Server.
-- Example: Rhylib.Radio.HangUp(ply)
function R.HangUp(ply)
    local p = R.P(ply)
    local c = p.call and R.calls[p.call]
    if c then
        if c.caller == ply then
            endCall(c, "Hail ended")
        else
            c.members[ply] = nil
            p.call = nil
            R.ClearTx(ply, R.TX_CALL, c.id)
            noCall(ply)
            if table.Count(c.members) < 2 and next(c.ringing) == nil then
                endCall(c, "Hail ended")
            else
                sendCall(c)
            end
        end
    end
    p.call = nil
    -- Also stop anything still ringing for them.
    for _, cc in pairs(R.calls) do
        if cc.ringing[ply] then
            cc.ringing[ply] = nil
            ring(ply, cc, false)
            if not checkEnd(cc) then sendCall(cc, cc.caller) end
        end
    end
end

local function ringTargets(caller, kind, target)
    if kind == 1 then
        local sq = R.squads[target]
        if not sq then return nil end
        local list = {}
        if IsValid(sq.leader) and sq.leader ~= caller then list[#list + 1] = sq.leader end
        if IsValid(sq.ro) and sq.ro ~= caller and sq.ro ~= sq.leader then list[#list + 1] = sq.ro end
        return list, sq.name
    end
    if IsValid(target) and target:IsPlayer() and target ~= caller then return { target }, target:Nick() end
end

Rhylib.Net.Receive("radio.hail", function(ply)
    local kind = net.ReadUInt(2)
    local target
    if kind == 1 then target = net.ReadUInt(R.ID_BITS) else target = net.ReadEntity() end
    local st = R.State(ply)
    if st.off then return R.Note(ply, "Your radio is off") end
    local list, name = ringTargets(ply, kind, target)
    if not list or #list == 0 then return R.Note(ply, "Nobody to hail there") end
    local reach = {}
    for _, t in ipairs(list) do
        if R.State(t).off then R.Note(ply, t:Nick() .. "'s radio is off") else reach[#reach + 1] = t end
    end
    if #reach == 0 then return end
    R.HangUp(ply)
    local id
    for i = 1, R.MAX_ID do if not R.calls[i] then id = i break end end
    if not id then return end
    -- What the people rung see: the caller's squad, or their name.
    local mySq = R.squads[R.SquadOf(ply)]
    local c = { id = id, caller = ply, label = mySq and mySq.name or ply:Nick(), members = { [ply] = true }, ringing = {}, target = name }
    R.calls[id] = c
    R.P(ply).call = id
    local untilT = CurTime() + R.Cfg("hailTime")
    for _, t in ipairs(reach) do
        c.ringing[t] = untilT
        ring(t, c, true)
    end
    sendCall(c, ply)
    R.Note(ply, "Hailing " .. name .. "...")
end, { rate = 1, burst = 3 })

Rhylib.Net.Receive("radio.answer", function(ply)
    local c = R.calls[net.ReadUInt(R.ID_BITS)]
    local yes = net.ReadBool()
    if not (c and c.ringing[ply]) then return end
    c.ringing[ply] = nil
    ring(ply, c, false)
    if not yes then
        R.Note(c.caller, ply:Nick() .. " declined the hail")
        if not checkEnd(c) then sendCall(c, c.caller) end
        return
    end
    if R.State(ply).off then
        R.Note(ply, "Turn your radio on first")
        if not checkEnd(c) then sendCall(c, c.caller) end
        return
    end
    local p = R.P(ply)
    if p.call and p.call ~= c.id then R.HangUp(ply) end
    c.members[ply] = true
    p.call = c.id
    c.started = c.started or CurTime()
    sendCall(c)
end, { rate = 4, burst = 4 })

Rhylib.Net.Receive("radio.hangup", function(ply)
    R.HangUp(ply)
end, { rate = 2, burst = 3 })

-- Rings running out (hailTime), once a second. A call whose caller left
-- ends; a call nobody answered ends with "No answer".
timer.Create("Rhylib.Radio.Hails", 1, 0, function()
    if next(R.calls) == nil then return end
    local now = CurTime()
    for _, c in pairs(R.calls) do
        for p, untilT in pairs(c.ringing) do
            if not IsValid(p) or now >= untilT then
                c.ringing[p] = nil
                if IsValid(p) then
                    ring(p, c, false)
                    R.Note(p, "Missed hail from " .. (IsValid(c.caller) and c.caller:Nick() or "?") .. " (" .. c.label .. ")")
                end
            end
        end
        if not IsValid(c.caller) then
            endCall(c)
        elseif table.Count(c.members) < 2 and next(c.ringing) == nil then
            endCall(c, "No answer")
        end
    end
end)
