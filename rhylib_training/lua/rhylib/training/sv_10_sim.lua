--[[
    Sim health, elimination and respawn beacons (server).

    Training hits arrive as hook Rhylib.TrainingHit(ply, attacker, amount,
    inflictor, group) from rhylib_weapons (bolts and training blasts).
    Returns true = that eliminated them, false = ignored, nil = a hit.

    State: T.hp[ply] (only while hurt), NW2Int rhylib_sim, NW2Bool
    rhylib_simOut, NW2Float rhylib_simOutAt. Eliminated players lie down
    (rhylib_core Lying.Knock with no end) until they respawn at a beacon.

    Messages
      train.out    server -> player: open (attacker name, beacons) / close
      train.pick   client: beacon entity index (0 = nearest)
]]

local T = Rhylib.Training
local L = Rhylib.Lying

T.hp = T.hp or {}        -- [ply] = sim health while below full
T.lastHit = T.lastHit or {}
T.out = T.out or {}      -- [ply] = { at, pick }

Rhylib.Net.Register("train.out")
Rhylib.Perms.Register("rhylib.training.admin", "admin", "Save training respawn beacons")

local BEACON = "rhylib_training_beacon"

local function setHealth(ply, hp)
    local max = T.Cfg("simHealth")
    hp = math.Clamp(math.ceil(hp), 0, max)
    if hp >= max then
        T.hp[ply], T.lastHit[ply] = nil, nil
    else
        T.hp[ply] = hp
    end
    if ply:GetNW2Int("rhylib_sim", max) ~= hp then ply:SetNW2Int("rhylib_sim", hp) end
end

-- Beacons by distance from a point: { ent, name, dist }.
local function beaconsFrom(pos)
    local list = {}
    for _, b in ipairs(ents.FindByClass(BEACON)) do
        list[#list + 1] = { ent = b, name = b:GetBeaconName(), dist = b:GetPos():Distance(pos) }
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function sendClose(ply)
    Rhylib.Net.Start("train.out")
    net.WriteBool(false)
    net.Send(ply)
end

-- Out of the simulation state (no teleport). quiet: no close message.
local function clearOut(ply, quiet)
    if not T.out[ply] then return end
    T.out[ply] = nil
    timer.Remove("Rhylib.Training.Out." .. ply:EntIndex())
    ply:SetNW2Bool("rhylib_simOut", false)
    if not quiet and IsValid(ply) then sendClose(ply) end
end

-- Back in at a beacon (or the nearest, or where they lie if there are none).
function T.Respawn(ply, beacon)
    local o = T.out[ply]
    if not o then return end
    local from = L.BodyPos(ply)
    if not (IsValid(beacon) and beacon:GetClass() == BEACON) then
        local list = beaconsFrom(from)
        beacon = list[1] and list[1].ent or nil
    end
    clearOut(ply)
    L.Unknock(ply)
    setHealth(ply, T.Cfg("simHealth"))
    ply.rhylibSimImmune = CurTime() + T.Cfg("immune")
    if IsValid(beacon) then
        ply:SetPos(beacon:SpawnPos())
        ply:SetEyeAngles(Angle(0, beacon:GetAngles().y, 0))
        ply:SetVelocity(-ply:GetVelocity())
        if L.Unstick then L.Unstick(ply) end
    end
end

-- Returns true if they're out now.
function T.Eliminate(ply, by)
    if T.out[ply] then return false end
    if not L.Knock(ply, 0) then return false end
    local now = CurTime()
    T.out[ply] = { at = now }
    T.hp[ply], T.lastHit[ply] = nil, nil
    ply:SetNW2Int("rhylib_sim", 0)
    ply:SetNW2Bool("rhylib_simOut", true)
    ply:SetNW2Float("rhylib_simOutAt", now)
    ply:EmitSound("buttons/combine_button_locked.wav", 65, 90)

    local list = beaconsFrom(L.BodyPos(ply))
    Rhylib.Net.Start("train.out")
    net.WriteBool(true)
    net.WriteString(IsValid(by) and by:IsPlayer() and by:Nick() or (IsValid(by) and (by.PrintName or by:GetClass()) or ""))
    net.WriteFloat(now + T.Cfg("outMin"))
    net.WriteFloat(now + T.Cfg("chooseTime"))
    local n = math.min(#list, 32)
    net.WriteUInt(n, 6)
    for i = 1, n do
        net.WriteUInt(list[i].ent:EntIndex(), 13)   -- (an index: it may be dormant on the client)
        net.WriteString(list[i].name)
        net.WriteUInt(math.min(math.floor(list[i].dist / 52.5), 65535), 16)   -- metres
    end
    net.Send(ply)

    -- Nobody picked: the nearest.
    timer.Create("Rhylib.Training.Out." .. ply:EntIndex(), T.Cfg("chooseTime"), 1, function()
        if IsValid(ply) then T.Respawn(ply) end
    end)
    return true
end

Rhylib.Hook.Add("Rhylib.TrainingHit", "training.hit", function(ply, attacker, amount)
    if not ply:IsPlayer() or not ply:Alive() or ply.rhylibDown or T.out[ply] then return false end
    if (ply.rhylibSimImmune or 0) > CurTime() then return false end
    if L.Ragdoll(ply) then return false end   -- (stunned or knocked down: lying already)
    local hp = (T.hp[ply] or T.Cfg("simHealth")) - amount
    T.lastHit[ply] = CurTime()
    -- HUD hit feedback (rhylib_hud), yellow.
    local HUD = Rhylib.HUD
    if HUD and HUD.SendHit then
        local from = IsValid(attacker) and attacker ~= ply and not attacker:IsWorld() and attacker:WorldSpaceCenter() or nil
        HUD.SendHit(ply, amount, 0, from, HUD.DMG_SIM)
    end
    if hp <= 0 then
        if T.Eliminate(ply, attacker) then return true end
        hp = 1   -- (couldn't lie them down: hold at 1)
    end
    setHealth(ply, hp)
end)

Rhylib.Net.Receive("train.pick", function(ply)
    local o = T.out[ply]
    local idx = net.ReadUInt(13)
    local b = idx > 0 and Entity(idx) or nil
    if not o then return end
    -- At least outMin on the ground; a pick before then waits.
    local wait = o.at + T.Cfg("outMin") - CurTime()
    if wait > 0 then
        timer.Create("Rhylib.Training.Out." .. ply:EntIndex(), wait, 1, function()
            if IsValid(ply) then T.Respawn(ply, IsValid(b) and b or nil) end
        end)
        return
    end
    T.Respawn(ply, IsValid(b) and b or nil)
end, { rate = 2, burst = 3 })

-- Sim health refills a while after the last training hit.
timer.Create("Rhylib.Training.Regen", 1, 0, function()
    if next(T.hp) == nil then return end
    local now, wait = CurTime(), T.Cfg("simRegen")
    for ply in pairs(T.hp) do
        if not IsValid(ply) then
            T.hp[ply], T.lastHit[ply] = nil, nil
        elseif now - (T.lastHit[ply] or 0) >= wait then
            setHealth(ply, T.Cfg("simHealth"))
        end
    end
end)

-- Real trouble ends the simulation for them (medical / MP / core own the body then).
local function reset(ply)
    clearOut(ply)
    T.hp[ply], T.lastHit[ply] = nil, nil
    if IsValid(ply) then ply:SetNW2Int("rhylib_sim", T.Cfg("simHealth")) end
end
Rhylib.Hook.Add("Rhylib.PlayerDowned", "training.reset", reset)
Rhylib.Hook.Add("PlayerDeath", "training.reset", reset)
Rhylib.Hook.Add("PlayerSpawn", "training.reset", reset)
Rhylib.Hook.Add("Rhylib.PlayerUnknocked", "training.reset", function(ply)
    if T.out[ply] then clearOut(ply) end   -- (got up some other way, e.g. an admin)
end)
Rhylib.Hook.Add("PlayerDisconnected", "training.reset", function(ply)
    timer.Remove("Rhylib.Training.Out." .. ply:EntIndex())
    T.out[ply], T.hp[ply], T.lastHit[ply] = nil, nil, nil
end)

--------------------------------------------------------------------------
-- Beacons per map (Data "training"/map)
--------------------------------------------------------------------------

function T.SaveBeacons()
    local rows = {}
    for _, b in ipairs(ents.FindByClass(BEACON)) do
        local p, a = b:GetPos(), b:GetAngles()
        rows[#rows + 1] = { name = b:GetBeaconName(), pos = { p.x, p.y, p.z }, yaw = a.y }
    end
    Rhylib.Data.Set("training", game.GetMap(), rows)
    return #rows
end

function T.SpawnBeacons()
    local rows = Rhylib.Data.Get("training", game.GetMap())
    if not istable(rows) then return end
    for _, row in ipairs(rows) do
        local b = ents.Create(BEACON)
        if IsValid(b) then
            b:SetPos(Vector(row.pos[1], row.pos[2], row.pos[3]))
            b:SetAngles(Angle(0, row.yaw or 0, 0))
            b:SetBeaconName(tostring(row.name or "Beacon"))
            b:Spawn()
        end
    end
end

Rhylib.Hook.Add("InitPostEntity", "training.beacons", function() timer.Simple(1, T.SpawnBeacons) end)
Rhylib.Hook.Add("PostCleanupMap", "training.beacons", T.SpawnBeacons)

Rhylib.PLACEMENT_CLASSES = Rhylib.PLACEMENT_CLASSES or {}
Rhylib.PLACEMENT_CLASSES[BEACON] = true

concommand.Add("rhylib_training_save", function(ply)
    local function reply(m) if IsValid(ply) then ply:ChatPrint(m) else print(m) end end
    Rhylib.Perms.Check(ply, "rhylib.training.admin", function(ok)
        if not ok then return reply("You don't have permission for rhylib_training_save") end
        reply("Saved " .. T.SaveBeacons() .. " training beacons for " .. game.GetMap())
    end)
end)
