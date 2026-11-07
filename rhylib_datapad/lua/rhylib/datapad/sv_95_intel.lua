--[[
    Intel datapads (server; sh_95_intel.lua has the settings).

    E on a pad (D.IntelUse):
      toolgun out + rhylib.datapad.intel -> the setup window (view 3)
      cracked, and you may read it      -> the intel (view 2)
      encrypted, field technician       -> cracking starts (view 1)
      encrypted, anyone else            -> "only field technicians" (view 0)

    Cracking: three rounds. For each the server picks a seed (sent with
    view 1) and starts the round's clock (D.INTEL_NEXT_WAIT after a
    locked round, intelFailWait after a miss). The client plays it and
    on Space reports the lock (op 1: round, its time into the round,
    both knobs). The server takes it only from the player it started
    for, for the round it is on, close by, with a time that fits its own
    clock (no later than it, at most INTEL_LAG s earlier), at least
    intelMinLock into the round (earlier: ignored, the client never sends
    one), with knobs that could have turned that far since the start
    (D.IntelReachable), and works out the wave itself (D.IntelInBand with the same seed): inside the band
    the next round starts, outside it the crack goes back to round 1
    after intelFailWait. After round 3 the pad is cracked (NW2
    rhylib_intelCracked) and the intel goes to that player. Closing the
    window or walking off starts over.

    Nets:
      dp.intel     server -> client: Entity pad, UInt 2 view, then for
                   view 1: UInt 2 round, UInt 32 seed, UInt 2 why (0
                   start, 1 the last round locked, 2 missed: back to
                   round 1), UInt 7 tenths of a second until it starts;
                   for views 2 and 3: String title, String text, String
                   cracked by ("" = not yet), Bool only whoever cracked it
                   may read it, (view 3) Bool cracked.
      dp.intelact  client -> server: Entity pad, UInt 3 op: 1 lock (UInt 2
                   round, Float seconds into the round, Float frequency
                   knob, Float amplitude knob), 2 save the intel (game
                   master: String title, String text, Bool onlyCracker),
                   3 lock it again (game master), 4 closed the window.

    Saved with the pad when it's permanent (core placements, Data
    "dp_intel"/map rows: title, text, only); it comes back encrypted.
    A report that can't count (too far, dead, wrong round, someone else
    cracked it first) closes the client's window with a note.
]]

local D = Rhylib.Datapad

Rhylib.Net.Register("dp.intel")

D.intelCrack = D.intelCrack or {}   -- [ply] = { pad, round, seed, since (the round's clock starts) }
local crack = D.intelCrack
local INTEL_LAG = 1.5   -- (a lock may be this much older than the server's clock: ping)

D.IntelPlaces = Rhylib.Perma.Placements("datapad_intel", {
    classes = { "rhylib_intel_pad" },
    dataModule = "dp_intel",
    -- (the intel only: a pad comes back encrypted after a map change)
    save = function(e)
        local i = e.intel or {}
        return { title = i.title or "", text = i.text or "", only = i.onlyCracker or nil }
    end,
    load = function(e, row)
        e.intel = { title = tostring(row.title or ""), text = tostring(row.text or ""), onlyCracker = row.only and true or false, cracked = false }
        e:SetNW2Bool("rhylib_intelCracked", false)
    end,
    command = "rhylib_intel_save",
    perm = "rhylib.datapad.intel",
})

local function resave(pad)
    if Rhylib.Perma and Rhylib.Perma.Is and Rhylib.Perma.Is(pad) and D.IntelPlaces then D.IntelPlaces:Save() end
end

local function near(ply, pad)
    return IsValid(ply) and IsValid(pad) and ply:Alive() and ply:GetPos():DistToSqr(pad:GetPos()) <= D.Cfg("intelRange") ^ 2
end

-- send(ply, pad, view, c, why, wait): c = the crack (view 1).
local function send(ply, pad, view, c, why, wait)
    local i = pad.intel or {}
    Rhylib.Net.Start("dp.intel")
    net.WriteEntity(pad)
    net.WriteUInt(view, 2)
    if view == 1 then
        net.WriteUInt(c.round, 2)
        net.WriteUInt(c.seed, 32)
        net.WriteUInt(why or 0, 2)
        net.WriteUInt(math.Clamp(math.floor((wait or 0) * 10 + 0.5), 0, 127), 7)
    elseif view >= 2 then
        net.WriteString(i.title or "")
        net.WriteString(i.text or "")
        net.WriteString(i.cracked and (i.by or "someone") or "")
        net.WriteBool(i.onlyCracker and true or false)
        if view == 3 then net.WriteBool(i.cracked and true or false) end
    end
    net.Send(ply)
end

-- startRound(ply, pad, r, wait, why): round r with a new seed, its clock
-- starting in wait seconds; tells the client.
local function startRound(ply, pad, r, wait, why)
    local c = { pad = pad, round = r, seed = math.random(1, 2147483645), since = CurTime() + wait }
    crack[ply] = c
    send(ply, pad, 1, c, why, wait)
end

local function isGMTool(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

local function canRead(ply, pad)
    local i = pad.intel or {}
    return not i.onlyCracker or i.bySid == ply:SteamID64()
end

-- D.IntelUse(ply, pad): what E on an intel datapad does.
function D.IntelUse(ply, pad)
    if not (IsValid(ply) and IsValid(pad)) then return end
    local function open()
        if not near(ply, pad) then return end
        local i = pad.intel or {}
        if i.cracked then
            if canRead(ply, pad) then send(ply, pad, 2)
            else Rhylib.Notify(ply, "Only whoever cracked this datapad can read it", "info", "Datapad") end
        elseif D.IsFieldTech(ply) then
            startRound(ply, pad, 1, 0, 0)
        else
            send(ply, pad, 0)
        end
    end
    if isGMTool(ply) then
        Rhylib.Perms.Check(ply, "rhylib.datapad.intel", function(ok)
            if not (IsValid(ply) and IsValid(pad)) then return end
            if ok then send(ply, pad, 3) else open() end
        end)
        return
    end
    open()
end

Rhylib.Net.Receive("dp.intelact", function(ply)
    local pad = net.ReadEntity()
    local op = net.ReadUInt(3)
    if not (IsValid(pad) and pad:GetClass() == "rhylib_intel_pad") then return end

    if op == 1 then
        local r = net.ReadUInt(2)
        local t, kf, ka = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
        local c = crack[ply]
        local i = pad.intel or {}
        -- (a report that can't count: tell the client, so it never hangs)
        local function refuse(why)
            crack[ply] = nil
            if i.cracked and canRead(ply, pad) and near(ply, pad) then send(ply, pad, 2) return end
            Rhylib.Notify(ply, why, "bad", "Datapad")
            send(ply, pad, 0)   -- (closes the cracking window)
        end
        if i.cracked then return refuse("Someone else cracked it first") end
        if not (near(ply, pad) and D.IsFieldTech(ply)) then return refuse("The signal was lost: stay close to the datapad") end
        if not (c and c.pad == pad and c.round == r) then return refuse("The signal was lost: start again") end
        -- (the lock's time must fit the server's clock; then the server
        -- works out the wave itself from the round's seed)
        local e = CurTime() - c.since
        if not (t == t and kf == kf and ka == ka) then return end
        -- (too early into the round: doesn't count, nothing changes)
        if t < D.IntelMinLock() then return end
        local ok = t <= e + 0.25 and t >= e - INTEL_LAG
        if ok then
            local sg = D.IntelSignal(c.seed, r)
            kf, ka = math.Clamp(kf, 0, 5), math.Clamp(ka, 0, 1.4)
            ok = D.IntelReachable(sg, t, kf, ka) and D.IntelInBand(sg, t, kf, ka)
        end
        if not ok then
            return startRound(ply, pad, 1, math.Clamp(D.Cfg("intelFailWait"), 0, 10), 2)
        end
        if r < 3 then
            return startRound(ply, pad, r + 1, D.INTEL_NEXT_WAIT, 1)
        end
        crack[ply] = nil
        i.cracked, i.by, i.bySid = true, ply:Nick(), ply:SteamID64()
        pad.intel = i
        pad:SetNW2Bool("rhylib_intelCracked", true)
        pad:EmitSound("buttons/button9.wav", 65, 110)
        Rhylib.Print("datapad", "%s cracked an intel datapad (%s)", ply:Nick(), i.title ~= "" and i.title or "untitled")
        resave(pad)
        send(ply, pad, 2)

    elseif op == 2 or op == 3 then
        local title, text, only
        if op == 2 then
            title = D.Clip(net.ReadString(), D.Cfg("intelTitleMax"))
            text = D.Clip(net.ReadString(), D.Cfg("intelTextMax"), true)
            only = net.ReadBool()
        end
        if not near(ply, pad) and ply:GetPos():DistToSqr(pad:GetPos()) > 600 * 600 then return end
        Rhylib.Perms.Check(ply, "rhylib.datapad.intel", function(ok)
            if not (ok and IsValid(ply) and IsValid(pad)) then return end
            local i = pad.intel or {}
            if op == 2 then
                i.title, i.text, i.onlyCracker = title, text, only
                Rhylib.Notify(ply, "Intel saved", "good", "Datapad")
            else
                i.cracked, i.by, i.bySid = false, nil, nil
                pad:SetNW2Bool("rhylib_intelCracked", false)
                Rhylib.Notify(ply, "The datapad is encrypted again", "good", "Datapad")
            end
            pad.intel = i
            resave(pad)
            send(ply, pad, 3)
        end)

    elseif op == 4 then
        if crack[ply] and crack[ply].pad == pad then crack[ply] = nil end
    end
end, { rate = 4, burst = 8 })

Rhylib.Hook.Add("PlayerDisconnected", "datapad.intel", function(ply) crack[ply] = nil end)
