--[[
    Quick response calls from the datapad (config "calls"): call MPs, a
    medic, the bomb squad, reinforcements, resupply (with a list of what's needed).

    A call goes to the players its "to" names (not the caller). Calls
    with accept = false show the caller's position to them at once; with
    accept = true only to those who answer. Whoever answers is listed for
    the caller ("Medic inbound: ..."). A call ends when the caller
    cancels it, leaves, or after callLife seconds. Calls live in memory.

      dp.call   datapad: kind (3), items (16 bits)
      dp.callr  respond to call id     dp.callx  caller: end call id
      dp.callu  server -> player: a call's state (or that it ended)
      dp.callp  server -> player: call id, caller position (every 3 s)
]]

local D = Rhylib.Datapad

for _, n in ipairs({ "dp.callu", "dp.callp" }) do Rhylib.Net.Register(n) end

D.calls = D.calls or {}   -- [id] = { id, kind, caller, name, pos, t, items, to = {[ply]=true}, resp = {ply...} }
local nextId = D.callNextId or 1
local lastCall = {}         -- [ply] = { [kind] = CurTime }

local function def(kind) return (D.Cfg("calls") or {})[kind] end

local function wants(p, d, caller)
    if p == caller or not p:Alive() then return false end
    if d.to == "mp" then return D.IsMP(p) end
    if d.to == "medic" then return D.IsMedic(p) end
    if d.to == "eod" then return D.IsBombSquad(p) end
    if d.to == "battalion" then
        local bn = D.Battalion(caller)
        return bn ~= "" and D.Battalion(p) == bn
    end
    return true
end

local function responded(c, p)
    for _, r in ipairs(c.resp) do
        if r == p then return true end
    end
    return false
end

-- 0 asked, 1 responding, 2 caller.
local function roleOf(c, p)
    if p == c.caller then return 2 end
    return responded(c, p) and 1 or 0
end

local function seesPos(c, p)
    local r = roleOf(c, p)
    return r ~= 0 or not def(c.kind).accept
end

local function involved(c)
    local out = { c.caller }
    for p in pairs(c.to) do
        if IsValid(p) then out[#out + 1] = p end
    end
    return out
end

local function sendCall(c, p, active)
    if not IsValid(p) then return end
    Rhylib.Net.Start("dp.callu")
    net.WriteUInt(c.id, 16)
    net.WriteBool(active)
    if active then
        net.WriteUInt(c.kind, 3)
        net.WriteEntity(c.caller)
        net.WriteString(c.name)
        net.WriteUInt(os.time() - c.t, 16)   -- age
        net.WriteUInt(c.items, 16)
        net.WriteUInt(roleOf(c, p), 2)
        local see = seesPos(c, p)
        net.WriteBool(see)
        if see then net.WriteVector(c.pos) end
        local n = math.min(#c.resp, 31)
        net.WriteUInt(n, 5)
        for i = 1, n do net.WriteString(IsValid(c.resp[i]) and c.resp[i]:Nick() or "?") end
    end
    net.Send(p)
end

local function update(c)
    for _, p in ipairs(involved(c)) do sendCall(c, p, true) end
end

local function endCall(c)
    D.calls[c.id] = nil
    for _, p in ipairs(involved(c)) do sendCall(c, p, false) end
end

local function nick(p) return IsValid(p) and p:Nick() or "?" end

D.PadRecv("dp.call", function(ply)
    local kind, items = net.ReadUInt(3), net.ReadUInt(16)
    local d = def(kind)
    if not d then return end
    if not d.items then items = 0 end
    if d.items and items == 0 then return end
    -- Cooldown per kind.
    lastCall[ply] = lastCall[ply] or {}
    local now = CurTime()
    if now < (lastCall[ply][kind] or 0) + D.Cfg("callCooldown") then
        ply:ChatPrint("Wait a moment before calling again")
        return
    end
    lastCall[ply][kind] = now
    -- One open call per kind: a new one replaces it.
    for _, c in pairs(D.calls) do
        if c.caller == ply and c.kind == kind then endCall(c) end
    end
    local c = { id = nextId, kind = kind, caller = ply, name = ply:Nick(), pos = ply:GetPos(), t = os.time(), items = items, to = {}, resp = {} }
    nextId = nextId % 65535 + 1
    D.callNextId = nextId
    for _, p in ipairs(player.GetHumans()) do
        if wants(p, d, ply) then c.to[p] = true end
    end
    D.calls[c.id] = c
    local n = table.Count(c.to)
    ply:ChatPrint((d.short or d.name) .. " call sent" .. (n == 0 and " (nobody can answer it right now)" or (" to " .. n .. " player" .. (n == 1 and "" or "s"))))
    update(c)
end, { rate = 2, burst = 4 })

Rhylib.Net.Receive("dp.callr", function(ply)
    local c = D.calls[net.ReadUInt(16)]
    if not c or not c.to[ply] or responded(c, ply) or not ply:Alive() then return end
    c.resp[#c.resp + 1] = ply
    local d = def(c.kind)
    if IsValid(c.caller) then c.caller:ChatPrint((d and d.inbound or "Help") .. " inbound: " .. ply:Nick()) end
    update(c)
end, { rate = 3, burst = 5 })

Rhylib.Net.Receive("dp.callx", function(ply)
    local c = D.calls[net.ReadUInt(16)]
    if c and c.caller == ply then endCall(c) end
end, { rate = 3, burst = 5 })

-- Positions, and old calls.
timer.Create("Rhylib.Datapad.Calls", 3, 0, function()
    local now = os.time()
    local life = D.Cfg("callLife")
    for _, c in pairs(D.calls) do
        if not IsValid(c.caller) or now - c.t > life then
            endCall(c)
        else
            -- People who can answer now (respawned, joined, changed job).
            local d = def(c.kind)
            for _, p in ipairs(player.GetHumans()) do
                if d and not c.to[p] and wants(p, d, c.caller) then
                    c.to[p] = true
                    sendCall(c, p, true)
                end
            end
            if c.caller:Alive() then c.pos = c.caller:GetPos() end
            local list = {}
            for _, p in ipairs(involved(c)) do
                if p ~= c.caller and seesPos(c, p) then list[#list + 1] = p end
            end
            if #list > 0 then
                Rhylib.Net.Start("dp.callp")
                net.WriteUInt(c.id, 16)
                net.WriteVector(c.pos)
                net.Send(list)
            end
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "datapad.calls", function(ply)
    lastCall[ply] = nil
    for _, c in pairs(D.calls) do
        if c.caller == ply then
            endCall(c)
        else
            c.to[ply] = nil
            for i = #c.resp, 1, -1 do
                if c.resp[i] == ply then
                    table.remove(c.resp, i)
                    update(c)
                end
            end
        end
    end
end)
