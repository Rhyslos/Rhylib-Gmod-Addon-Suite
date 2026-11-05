--[[
    Intel datapads (server; sh_95_intel.lua has the settings).

    E on a pad (D.IntelUse):
      toolgun out + rhylib.datapad.intel -> the setup window (view 3)
      cracked, and you may read it      -> the intel (view 2)
      encrypted, field technician       -> cracking starts (view 1)
      encrypted, anyone else            -> "only field technicians" (view 0)

    Cracking: three rounds. The client plays each round and reports it
    locked (op 1, the round number); the server takes it only from the
    player it started for, in order, close by, and no sooner than that
    round's hold time after the last one (or the start). After round 3
    the pad is cracked (NW2 rhylib_intelCracked) and the intel goes to
    that player. Closing the window or walking off starts over.

    Nets:
      dp.intel     server -> client: Entity pad, UInt 2 view, then for
                   views 2 and 3: String title, String text, String
                   cracked by ("" = not yet), Bool only whoever cracked it
                   may read it, (view 3) Bool cracked.
      dp.intelact  client -> server: Entity pad, UInt 3 op: 1 round locked
                   (UInt 2 round), 2 save the intel (game master: String
                   title, String text, Bool onlyCracker), 3 lock it again
                   (game master), 4 closed the window.

    Saved with the pad when it's permanent (core placements, Data
    "dp_intel"/map rows: title, text, only); it comes back encrypted.
    A report that can't count (too far, dead, too soon, someone else
    cracked it first) closes the client's window with a note.
]]

local D = Rhylib.Datapad

Rhylib.Net.Register("dp.intel")

D.intelCrack = D.intelCrack or {}   -- [ply] = { pad, round, since }
local crack = D.intelCrack

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

local function send(ply, pad, view)
    local i = pad.intel or {}
    Rhylib.Net.Start("dp.intel")
    net.WriteEntity(pad)
    net.WriteUInt(view, 2)
    if view >= 2 then
        net.WriteString(i.title or "")
        net.WriteString(i.text or "")
        net.WriteString(i.cracked and (i.by or "someone") or "")
        net.WriteBool(i.onlyCracker and true or false)
        if view == 3 then net.WriteBool(i.cracked and true or false) end
    end
    net.Send(ply)
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
            crack[ply] = { pad = pad, round = 1, since = CurTime() }
            send(ply, pad, 1)
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
        -- (no sooner than the round's hold time, less a little for lag: the client only reports)
        if CurTime() - c.since < D.IntelRound(r).hold * 0.75 then return refuse("The signal was lost: start again") end
        if r < 3 then
            c.round = r + 1
            c.since = CurTime()
            return
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
