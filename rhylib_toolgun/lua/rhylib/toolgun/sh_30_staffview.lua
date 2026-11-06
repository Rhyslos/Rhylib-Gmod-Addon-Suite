--[[
    Staff view, shared part (the client part is cl_30_staffview.lua).

    Command rhylib_xray (chat !xray, /xray): staff with rhylib.toolgun
    switch their X-ray on or off (the server tells their client to flip
    rhylib_tool_xray). Anyone else gets "Staff only" (then nothing for 2 s).

    Server:
      net tool.xray      client -> server: bool on, uint8 range (metres),
                         uint4 kinds (1 players, 2 NPCs, 4 spawned things,
                         8 bombs / mines); sent when the setting changes,
                         when the toolgun is drawn and every 10 s while on
                         (rate 2/s). The server checks rhylib.toolgun (again
                         every 5 s), then while they hold the toolgun adds
                         spots of those kinds within range to their PVS, so
                         X-ray isn't cut short by walls: every 0.5 s, by
                         priority (players, NPCs, bombs / mines, spawned
                         things), nearest first, one spot per 512-unit
                         cell, 48 at most. Candidates come from tracked
                         sets (OnEntityCreated / EntityRemoved), not a
                         sphere search.
      net tool.xray.flip server -> client: flip rhylib_tool_xray.
      NW2String rhylib_spawnedBy  who spawned a thing (spawn menu and
                         toolgun placing), for the X-ray label.
      Tool.MarkPlacedBy(ent, ply)  sets it (sv_10_tool.lua uses it).
]]

local Tool = Rhylib.Tool
local M = 0.01905   -- metres per unit

if SERVER then
    Rhylib.Net.Register("tool.xray.flip")
end

Rhylib.Command.Add({
    name = "rhylib_xray",
    chat = { "xray" },
    help = "Staff view: X-ray on / off (toolgun out)",
    tag = "Toolgun",
    fn = function(ply)
        if not IsValid(ply) then return "Players only" end
        if CurTime() < (ply.rhylibXrayDenied or 0) then return end   -- (refused a moment ago)
        Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
            if not IsValid(ply) then return end
            if not ok then
                ply.rhylibXrayDenied = CurTime() + 2
                Rhylib.Notify(ply, "Staff only", "bad", "Toolgun")
                return
            end
            Rhylib.Net.Start("tool.xray.flip")
            net.Send(ply)
        end)
    end,
})

if CLIENT then return end

--------------------------------------------------------------------------
-- Tracked things (weak sets, refilled on a Lua refresh)
--------------------------------------------------------------------------

Tool.xrSets = Tool.xrSets or {
    npc = setmetatable({}, { __mode = "k" }),
    eod = setmetatable({}, { __mode = "k" }),
    spawned = setmetatable({}, { __mode = "k" }),
}
local SETS = Tool.xrSets

local function isEod(c)
    return string.sub(c, 1, 14) == "rhylib_eod_bom" or string.sub(c, 1, 14) == "rhylib_eod_min" or string.sub(c, 1, 15) == "rhylib_rep_mine"
end

local function classify(e)
    if not IsValid(e) or e:IsPlayer() or e:IsWeapon() then return end
    if e:IsNPC() or e:IsNextBot() then SETS.npc[e] = true return end
    if isEod(e:GetClass()) then SETS.eod[e] = true return end
    if e.rhylibToolSpawned or e.rhylibToolPlaced or e:GetNW2String("rhylib_spawnedBy", "") ~= "" then SETS.spawned[e] = true end
end

Rhylib.Hook.Add("OnEntityCreated", "toolgun.xray", function(e)
    -- (next tick: the class, NPC flags and the toolgun / perma marks are set by then)
    timer.Simple(0, function() classify(e) end)
end)

Rhylib.Hook.Add("EntityRemoved", "toolgun.xray", function(e)
    SETS.npc[e], SETS.eod[e], SETS.spawned[e] = nil, nil, nil
end)

if not Tool.xrSeeded then
    Tool.xrSeeded = true
    for _, e in ipairs(ents.GetAll()) do classify(e) end
end

-- Who spawned it (short name), for the X-ray label.
function Tool.MarkPlacedBy(ent, ply)
    if not (IsValid(ent) and IsValid(ply)) then return end
    if ent:IsNPC() or ent:IsNextBot() then return end   -- (NPCs have their own label)
    ent:SetNW2String("rhylib_spawnedBy", string.sub(ply:Nick(), 1, 32))
    if not isEod(ent:GetClass()) then SETS.spawned[ent] = true end
end

local function byModel(ply, _, ent) Tool.MarkPlacedBy(ent, ply) end
local function byEnt(ply, ent) Tool.MarkPlacedBy(ent, ply) end
Rhylib.Hook.Add("PlayerSpawnedProp", "toolgun.spawnedby", byModel)
Rhylib.Hook.Add("PlayerSpawnedRagdoll", "toolgun.spawnedby", byModel)
Rhylib.Hook.Add("PlayerSpawnedEffect", "toolgun.spawnedby", byModel)
Rhylib.Hook.Add("PlayerSpawnedSENT", "toolgun.spawnedby", byEnt)
Rhylib.Hook.Add("PlayerSpawnedVehicle", "toolgun.spawnedby", byEnt)

--------------------------------------------------------------------------
-- Who has X-ray on
--------------------------------------------------------------------------

-- want[ply] = { on, range (units), bits, gen, checkAt }: what the client
-- last asked for. on[ply] = that record once the permission check passed.
-- spots[ply] = { n = count, Vector, ... }.
Tool.xrayWant = Tool.xrayWant or {}
Tool.xrayOn = Tool.xrayOn or {}
Tool.xraySpots = Tool.xraySpots or {}
local want, on, spots = Tool.xrayWant, Tool.xrayOn, Tool.xraySpots
local MAX_SPOTS = 48
local CELL = 512
local RECHECK = 5

local function drop(ply) on[ply], spots[ply] = nil, nil end

-- Check the permission for what they want now; a newer request wins.
local function grant(ply)
    local w = want[ply]
    if not (w and w.on) then return drop(ply) end
    local gen = w.gen
    w.checkAt = CurTime() + RECHECK
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) then return end
        local cur = want[ply]
        if not cur or cur.gen ~= gen or not cur.on then return end
        if ok then on[ply] = cur else drop(ply) end
    end)
end

Rhylib.Net.Receive("tool.xray", function(ply)
    local w = want[ply] or { gen = 0 }
    want[ply] = w
    w.gen = w.gen + 1
    w.on = net.ReadBool()
    w.range = math.Clamp(net.ReadUInt(8), 10, 200) / M
    w.bits = net.ReadUInt(4)
    if not w.on then return drop(ply) end
    grant(ply)
end, { rate = 2, burst = 6 })

Rhylib.Hook.Add("PlayerDisconnected", "toolgun.xray", function(ply)
    want[ply] = nil
    drop(ply)
end)

local function holding(ply)
    if not (IsValid(ply) and ply:Alive()) then return false end
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

--------------------------------------------------------------------------
-- Spots: by priority, nearest first, one per cell
--------------------------------------------------------------------------

local pool, arr, seen = {}, {}, {}
local nArr = 0

local function byDist(a, b) return a.d2 < b.d2 end

local function add(e, eye, r2)
    local d2 = eye:DistToSqr(e:GetPos())
    if d2 > r2 then return end
    nArr = nArr + 1
    local r = pool[nArr]
    if not r then r = {} pool[nArr] = r end
    r.e, r.d2 = e, d2
    arr[nArr] = r
end

-- Sort what add() collected and put it on the list; returns the new count.
local function take(list, n)
    for i = nArr + 1, #arr do arr[i] = nil end
    table.sort(arr, byDist)
    for i = 1, nArr do
        if n >= MAX_SPOTS then break end
        local pos = arr[i].e:WorldSpaceCenter()
        local key = (math.floor(pos.x / CELL) + 128) * 65536 + (math.floor(pos.y / CELL) + 128) * 256 + (math.floor(pos.z / CELL) + 128)
        if not seen[key] then
            seen[key] = true
            n = n + 1
            list[n] = pos
        end
    end
    for i = 1, nArr do arr[i] = nil end
    nArr = 0
    return n
end

local function fromSet(set, eye, r2, alive)
    for e in pairs(set) do
        if IsValid(e) and not IsValid(e:GetParent()) and (not alive or e:Health() > 0) then add(e, eye, r2) end
    end
end

local function fill(ply, w)
    local list = spots[ply] or { n = 0 }
    spots[ply] = list
    for k in pairs(seen) do seen[k] = nil end
    local eye, r2, bits, n = ply:EyePos(), w.range * w.range, w.bits, 0
    if bit.band(bits, 1) ~= 0 then
        for _, p in ipairs(player.GetAll()) do
            if p ~= ply and p:Alive() then add(p, eye, r2) end
        end
        n = take(list, n)
    end
    if bit.band(bits, 2) ~= 0 and n < MAX_SPOTS then
        fromSet(SETS.npc, eye, r2, true)
        n = take(list, n)
    end
    if bit.band(bits, 8) ~= 0 and n < MAX_SPOTS then
        fromSet(SETS.eod, eye, r2)
        n = take(list, n)
    end
    if bit.band(bits, 4) ~= 0 and n < MAX_SPOTS then
        fromSet(SETS.spawned, eye, r2)
        n = take(list, n)
    end
    for i = n + 1, list.n do list[i] = nil end
    list.n = n
end

timer.Create("rhylib.toolgun.xraypvs", 0.5, 0, function()
    if next(want) == nil then return end
    local now = CurTime()
    for ply, w in pairs(want) do
        if not IsValid(ply) then
            want[ply] = nil
            drop(ply)
        elseif w.on then
            if now >= (w.checkAt or 0) then grant(ply) end   -- (a demotion takes it away)
            if on[ply] and holding(ply) then fill(ply, w) else spots[ply] = nil end
        end
    end
end)

Rhylib.Hook.Add("SetupPlayerVisibility", "toolgun.xray", function(ply)
    local list = spots[ply]
    if not list or list.n == 0 or not on[ply] or not holding(ply) then return end
    for i = 1, list.n do AddOriginToPVS(list[i]) end
end)
