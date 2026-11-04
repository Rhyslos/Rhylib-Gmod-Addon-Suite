--[[
    Sensor array beacons (server). See sh_00_config.lua for how they play.

    L.beacons = { [ent] = { owner, count, at } }: every placed beacon.
    L.PlaceBeacon(ply, trace) -> beacon or nil (the kit calls it: checks
    sensorMax, puts the best power cell from the player's inventory in).
    L.PowerBeacon(ply, beacon), L.PickupBeacon(ply, beacon), L.BeaconUse.

    Once a second, for every powered beacon: inside an active comms jammer
    (rhylib_radio R.jammers) = jammed (DT Jammed, counts nothing); else
    the droids (rhylib_droids D.active) within sensorRadius are counted.
    When a count changes, every field technician and officer (L.Access 2+,
    re-checked every 5 s; someone who becomes one gets the alerts that are
    on, someone who stops being one gets net logi.clear, empty) gets net
    logi.alert: UInt 13 beacon entity index, UInt 7 count (0 =
    clear), Vector the beacon's position, String its label.

    Sensor kits come from the armoury's gear cabinet (hook
    Rhylib.GearStock).

    Net logi.beacon (client -> server, the beacon's wheel): Entity beacon,
    UInt 2 op (1 put in a power cell, 2 pick up); within 150 units. Rate 4/s.
]]

local L = Rhylib.Logistics

Rhylib.Net.Register("logi.alert")
Rhylib.Net.Register("logi.clear")

L.beacons = L.beacons or {}
L.nextLabel = L.nextLabel or 1

function L.AddBeacon(e)
    L.beacons[e] = L.beacons[e] or { count = 0, at = 0 }
end

function L.RemoveBeacon(e)
    local b = L.beacons[e]
    L.beacons[e] = nil
    if b and b.count > 0 and L.SendAlert then L.SendAlert(e, 0) end
end

local function Inv() return Rhylib.Inventory end

-- How many beacons this player has out.
local function countOf(ply)
    local n = 0
    for e, b in pairs(L.beacons) do
        if IsValid(e) and b.owner == ply then n = n + 1 end
    end
    return n
end

-- A power cell from the player's inventory into the beacon: its charge
-- (fill) x sensorPower seconds. -> true if one went in.
local function insertCell(ply, e)
    local I = Inv()
    local W = Rhylib.Weapons
    if not (I and I.TakeBest and W and W.CELL) then return false end
    local fill = I.TakeBest(ply, W.CELL)
    if not fill then return false end
    e:SetPowerEnd(CurTime() + math.max(10, L.Cfg("sensorPower")) * math.Clamp(tonumber(fill) or 1, 0.05, 1))
    e:EmitSound("items/battery_pickup.wav", 60, 110)
    return true
end

function L.PlaceBeacon(ply, tr)
    local most = math.max(1, math.floor(L.Cfg("sensorMax")))
    if countOf(ply) >= most then
        Rhylib.Notify(ply, "You have " .. most .. " sensor beacons out already: pick one up first", "bad", "Logistics")
        return nil
    end
    local e = ents.Create("rhylib_sensor_beacon")
    if not IsValid(e) then return nil end
    e:SetPos(tr.HitPos)
    e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    e:Spawn()
    -- (standing on the ground: lift by how far the model reaches below its origin)
    local mins = e:OBBMins()
    if mins.z < 0 then e:SetPos(e:GetPos() - Vector(0, 0, mins.z)) end
    if e.CPPISetOwner then e:CPPISetOwner(ply) end
    e:SetLabel("Sensor " .. L.nextLabel)
    L.nextLabel = L.nextLabel % 999 + 1
    L.AddBeacon(e)
    L.beacons[e].owner = ply
    if insertCell(ply, e) then
        Rhylib.Notify(ply, e:GetLabel() .. " set down and powered", "good", "Logistics")
    else
        Rhylib.Notify(ply, e:GetLabel() .. " set down, but you have no power cell: press E on it with one", "info", "Logistics")
    end
    return e
end

function L.PowerBeacon(ply, e)
    if not (IsValid(e) and L.beacons[e]) or e.takenBy then return end
    if not insertCell(ply, e) then
        return Rhylib.Notify(ply, "You have no power cell", "bad", "Logistics")
    end
    Rhylib.Notify(ply, e:GetLabel() .. ": new power cell in", "good", "Logistics")
end

-- (whoever set it down, field technicians and officers may pick it up)
local adminOk = {}   -- [ply] = { ok, at }: the rhylib.logistics.admin answer (async, kept 30 s)
local function isAdmin(p)
    local a = adminOk[p]
    if not a or CurTime() - a.at > 30 then
        adminOk[p] = adminOk[p] or { ok = false, at = 0 }
        adminOk[p].at = CurTime()
        Rhylib.Perms.Check(p, "rhylib.logistics.admin", function(ok)
            if IsValid(p) and adminOk[p] then adminOk[p].ok = ok and true or false end
        end)
    end
    return adminOk[p].ok
end

local function mayAct(ply)
    if not (IsValid(ply) and ply:Alive()) then return false end
    local S = Rhylib.State
    return not (S and S.CanAct and not S.CanAct(ply))
end

function L.PickupBeacon(ply, e)
    if not (IsValid(e) and L.beacons[e]) or e.takenBy then return end
    if L.beacons[e].owner ~= ply and L.Access(ply, isAdmin(ply)) < L.ACCESS_TECH then
        return Rhylib.Notify(ply, "Only whoever set it down, field technicians and officers can pick it up", "bad", "Logistics")
    end
    local I = Inv()
    if not (I and I.CanAdd and I.AddItem) then return end
    if not I.CanAdd(ply, L.KIT) then
        return Rhylib.Notify(ply, "No room for the sensor kit", "bad", "Logistics")
    end
    e.takenBy = ply   -- (Remove happens at the end of the tick)
    e:Remove()
    I.AddItem(ply, L.KIT, 1)
end

-- E without the wheel: a cell if it's below 90% and you carry one, else pick up.
function L.BeaconUse(ply, e)
    if not mayAct(ply) or ply:GetPos():DistToSqr(e:GetPos()) > 150 * 150 then return end
    local left = e:GetPowerEnd() - CurTime()
    local I, W = Inv(), Rhylib.Weapons
    local hasCell = I and I.Has and W and W.CELL and I.Has(ply, W.CELL)
    if hasCell and left < L.Cfg("sensorPower") * 0.9 then
        L.PowerBeacon(ply, e)
    else
        L.PickupBeacon(ply, e)
    end
end

Rhylib.Net.Receive("logi.beacon", function(ply)
    local e = net.ReadEntity()
    local op = net.ReadUInt(2)
    if not (IsValid(e) and e:GetClass() == "rhylib_sensor_beacon" and mayAct(ply)) then return end
    if ply:GetPos():DistToSqr(e:GetPos()) > 150 * 150 then return end
    if op == 1 then L.PowerBeacon(ply, e) elseif op == 2 then L.PickupBeacon(ply, e) end
end, { rate = 4, burst = 3 })

--------------------------------------------------------------------------
-- Sensing and alerts
--------------------------------------------------------------------------

-- Who gets the alerts (field technicians and officers), checked every 5 s.
local recipients, recipientSet, recipientsAt = {}, {}, 0

local function refreshRecipients()
    local now = CurTime()
    if now < recipientsAt then return end
    recipientsAt = now + 5
    local list, set, new = {}, {}, {}
    for _, p in ipairs(player.GetHumans()) do
        if L.Access(p, isAdmin(p)) >= L.ACCESS_TECH then
            list[#list + 1] = p
            set[p] = true
            if not recipientSet[p] then new[#new + 1] = p end
        end
    end
    -- (no longer one: their alerts go away, net logi.clear)
    local gone = {}
    for p in pairs(recipientSet) do
        if IsValid(p) and not set[p] then gone[#gone + 1] = p end
    end
    if #gone > 0 then
        Rhylib.Net.Start("logi.clear")
        net.Send(gone)
    end
    recipients, recipientSet = list, set
    -- (new ones get the alerts that are on now)
    if #new > 0 then
        for e, b in pairs(L.beacons) do
            if IsValid(e) and b.count > 0 then L.SendAlert(e, b.count, new) end
        end
    end
end

function L.SendAlert(e, count, to)
    local list = {}
    for _, p in ipairs(to or recipients) do if IsValid(p) then list[#list + 1] = p end end
    if #list == 0 then return end
    to = list
    Rhylib.Net.Start("logi.alert")
    net.WriteUInt(e:EntIndex(), 13)
    net.WriteUInt(math.min(count, 127), 7)
    net.WriteVector(e:GetPos())
    net.WriteString(e.GetLabel and e:GetLabel() or "Sensor")
    net.Send(to)
end

-- Inside an active comms jammer?
local function jammedAt(pos)
    local R = Rhylib.Radio
    if not (R and R.jammers and R.JammerRange) then return false end
    for j in pairs(R.jammers) do
        if IsValid(j) and j.GetActive and j:GetActive() then
            local r = R.JammerRange(j)
            if r == math.huge or j:GetPos():DistToSqr(pos) <= r * r then return true end
        end
    end
    return false
end

timer.Create("Rhylib.Logistics.Sensors", 1, 0, function()
    if not next(L.beacons) then return end
    refreshRecipients()
    local D = Rhylib.Droids
    local r = math.max(100, L.Cfg("sensorRadius"))
    local r2 = r * r
    local now = CurTime()
    for e, b in pairs(L.beacons) do
        if not IsValid(e) then
            L.beacons[e] = nil
        else
            local count = 0
            local jam = false
            if e:Powered() then
                local pos = e:GetPos()
                jam = jammedAt(pos)
                if not jam and D and D.active then
                    for d in pairs(D.active) do
                        if IsValid(d) and d:Health() > 0 and d:GetPos():DistToSqr(pos) <= r2 then count = count + 1 end
                    end
                end
            end
            if e:GetJammed() ~= jam then e:SetJammed(jam) end
            if count ~= b.count then
                b.count = count
                if count > 0 then b.at = now end
                L.SendAlert(e, count)
            end
        end
    end
end)

-- (someone leaves: their beacons go, and they're off the alert list)
Rhylib.Hook.Add("PlayerDisconnected", "logistics.sensors", function(ply)
    adminOk[ply] = nil
    recipientSet[ply] = nil
    for i = #recipients, 1, -1 do if recipients[i] == ply then table.remove(recipients, i) end end
    for e, b in pairs(L.beacons) do
        if IsValid(e) and b.owner == ply then e:Remove() end
    end
end)

-- The armoury's gear cabinet (rhylib_armoury) hands out sensor kits.
Rhylib.Hook.Add("Rhylib.GearStock", "logistics.kit", function(list)
    if not (Rhylib.Items and Rhylib.Items.defs and Rhylib.Items.defs[L.KIT]) then return end
    for _, id in ipairs(list) do if id == L.KIT then return end end
    list[#list + 1] = L.KIT
end)
