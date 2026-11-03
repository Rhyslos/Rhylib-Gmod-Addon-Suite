--[[
    Sim health, elimination and respawn beacons (server).

    Training hits arrive as hook Rhylib.TrainingHit(ply, attacker, amount,
    inflictor, group) from rhylib_weapons (bolts and training blasts).
    Returns true = that eliminated them, false = ignored, nil = a hit.

    State: T.hp[ply] (only while hurt), NW2Int rhylib_sim, NW2Bool
    rhylib_simOut, NW2Float rhylib_simOutAt. Eliminated players lie down
    (rhylib_core Lying.Knock with no end) until they respawn at a beacon.

    Messages
      train.out    server -> player: Bool open (false = close); then String
                   attacker name, Float ready time (outMin), Float auto
                   time (chooseTime), UInt 6 count (max 32), per beacon:
                   UInt 13 entindex, String name, UInt 16 metres (nearest first)
      train.pick   client: UInt 13 beacon entity index (0 = nearest); rate 2/s.
                   Before outMin is up the pick waits until then.

    Ends early (no respawn): Rhylib.PlayerDowned, PlayerDeath, PlayerSpawn;
    getting up another way (Rhylib.PlayerUnknocked) clears the out state.
    Perm rhylib.training.admin (admin): rhylib_training_save.
    Cadet armour (end of this file, T.CheckCadetArmour): WeaponEquip /
    PlayerDroppedWeapon / EntityRemoved of a training weapon, PlayerSpawn
    and Rhylib.InventoryChanged check whether you still carry one.
    Saved: Data "training"/<map> = { { class, name, pos, ang } } (older rows
    { name, pos, yaw } still load), permanent beacons only, through core's
    Rhylib.Perma.Placements (T.places).
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
    if ply:GetNW2Int(Rhylib.NW.SIM, max) ~= hp then ply:SetNW2Int(Rhylib.NW.SIM, hp) end
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
    ply:SetNW2Bool(Rhylib.NW.SIM_OUT, false)
    if not quiet and IsValid(ply) then sendClose(ply) end
end

-- T.Respawn(ply, beacon): back in at a beacon (or the nearest, or where
-- they lie if there are none): up, full sim health, immune for a moment.
-- Does nothing if they aren't out.
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

-- T.Eliminate(ply, by): knock them down (L.Knock with no end), send the
-- beacon list, start the auto-pick timer. by = the attacker (for the name).
-- Returns true if they're out now.
-- Example: Rhylib.Training.Eliminate(ply, attacker)
function T.Eliminate(ply, by)
    if T.out[ply] then return false end
    -- Knocked by a blast meanwhile: up first, then out properly.
    if L.SoftKnocked and L.SoftKnocked(ply) then L.Unknock(ply) end
    if not L.Knock(ply, 0) then return false end
    local now = CurTime()
    T.out[ply] = { at = now }
    T.hp[ply], T.lastHit[ply] = nil, nil
    ply:SetNW2Int(Rhylib.NW.SIM, 0)
    ply:SetNW2Bool(Rhylib.NW.SIM_OUT, true)
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

-- The training hit: returns true when it eliminated them, false when the
-- hit was ignored (out, downed, lying, immune), nil for a normal hit. The
-- HUD hit marker is sent here too (rhylib_hud, yellow).
Rhylib.Hook.Add("Rhylib.TrainingHit", "training.hit", function(ply, attacker, amount, inflictor, group)
    -- (uncached downed check: it can change inside this tick)
    if not ply:IsPlayer() or not ply:Alive() or ply.rhylibDown or ply:GetNW2Bool(Rhylib.NW.DOWN, false) or T.out[ply] then return false end
    if (ply.rhylibSimImmune or 0) > CurTime() then return false end
    if L.Ragdoll(ply) then return false end   -- (stunned or knocked down: lying already)
    local hp = (T.hp[ply] or T.Cfg("simHealth")) - amount
    T.lastHit[ply] = CurTime()
    -- HUD hit feedback (rhylib_hud), yellow.
    local HUD = Rhylib.HUD
    if HUD and HUD.SendHit then
        local from = IsValid(attacker) and attacker ~= ply and not attacker:IsWorld() and attacker:WorldSpaceCenter() or nil
        HUD.SendHit(ply, amount, 0, from, bit.bor(HUD.DMG_SIM, group == HITGROUP_HEAD and HUD.DMG_HEAD or 0))
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
    if IsValid(ply) then ply:SetNW2Int(Rhylib.NW.SIM, T.Cfg("simHealth")) end
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
-- Beacons per map (Data "training"/map, core's Rhylib.Perma.Placements)
--------------------------------------------------------------------------

-- Rows { name, pos, yaw } (older, no class) or { class, name, pos, ang }.
T.places = Rhylib.Perma.Placements("training", {
    classes = { BEACON },
    dataModule = "training",
    defaultClass = BEACON,
    save = function(b) return { name = b:GetBeaconName() } end,
    preSpawn = function(b, row) b:SetBeaconName(tostring(row.name or "Beacon")) end,
    command = "rhylib_training_save",
    perm = "rhylib.training.admin",
    freeze = false,
})

-- T.SaveBeacons() -> count saved (this map's permanent beacons).
-- T.SpawnBeacons(): spawn the saved beacons again.
function T.SaveBeacons() return (T.places:Save()) end
function T.SpawnBeacons() return T.places:Load() end

Rhylib.PLACEMENT_CLASSES = Rhylib.PLACEMENT_CLASSES or {}
Rhylib.PLACEMENT_CLASSES[BEACON] = true

--------------------------------------------------------------------------
-- Cadet armour: carrying a training weapon swaps you into the cadet
-- model; with none left, your own model comes back. ply.rhylibCadetPrev
-- = the model to go back to (nil = not in cadet armour).
--------------------------------------------------------------------------

local function cadetModel()
    local m = T.Cfg("cadetModel")
    if isstring(m) and m ~= "" then return m end
    local t = TEAM_CADET or (GAMEMODE and GAMEMODE.DefaultTeam)
    local job = t and RPExtraTeams and RPExtraTeams[t]
    local jm = job and job.model
    if istable(jm) then jm = jm[1] end
    return isstring(jm) and jm ~= "" and jm or nil
end

local function carriesTraining(ply)
    for _, w in ipairs(ply:GetWeapons()) do
        if w.Training then return true end
    end
    return false
end

function T.CheckCadetArmour(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local want = T.Cfg("cadetArmour") and carriesTraining(ply)
    local m = want and cadetModel()
    if m then
        if string.lower(ply:GetModel() or "") ~= string.lower(m) then
            ply.rhylibCadetPrev = ply:GetModel()
            ply:SetModel(m)
            ply:SetupHands()
        end
    elseif ply.rhylibCadetPrev then
        local prev = ply.rhylibCadetPrev
        ply.rhylibCadetPrev = nil
        if isstring(prev) and prev ~= "" and util.IsValidModel(prev) then
            ply:SetModel(prev)
        else
            hook.Run("PlayerSetModel", ply)
        end
        ply:SetupHands()
    end
end

local function soon(ply)
    timer.Simple(0, function() T.CheckCadetArmour(ply) end)
end

Rhylib.Hook.Add("WeaponEquip", "training.armour", function(wep, ply)
    if wep.Training then soon(ply) end
end)
Rhylib.Hook.Add("PlayerDroppedWeapon", "training.armour", function(ply, wep)
    if IsValid(wep) and wep.Training then soon(ply) end
end)
-- (the inventory strips a weapon when its item leaves)
Rhylib.Hook.Add("EntityRemoved", "training.armour", function(ent)
    if not ent.Training or not ent:IsWeapon() then return end
    local o = ent:GetOwner()
    if IsValid(o) and o:IsPlayer() then soon(o) end
end)
Rhylib.Hook.Add("Rhylib.InventoryChanged", "training.armour", function(ply)
    if ply.rhylibCadetPrev then soon(ply) end   -- (in case a strip went unseen)
end)
-- A respawn sets the job's model again: start clean, then check (the
-- inventory gives the weapons back during the spawn).
Rhylib.Hook.Add("PlayerSpawn", "training.armour", function(ply)
    ply.rhylibCadetPrev = nil
    timer.Simple(0.6, function() T.CheckCadetArmour(ply) end)
end)
Rhylib.Hook.Add("Rhylib.ConfigChanged", "training.armour", function(m, k)
    if m ~= "training" or (k ~= "cadetArmour" and k ~= "cadetModel") then return end
    for _, p in ipairs(player.GetAll()) do T.CheckCadetArmour(p) end
end)
