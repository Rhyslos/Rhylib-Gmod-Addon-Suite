--[[
    Droid orders (server, owner 2026-10-06): what GMs tell droids to do.

      Modes (per droid, NW2String rhylib_dmode for the GM labels):
        guard   hold a post (droid.home) and fight within guardRadius
        patrol  walk around a centre (droid.home) within patrolRadius
        attack  push on: to an attack marker (droid.objective), else
                hunt the nearest players
      Droids spawned any other way (spawn menu, load test) guard where
      they were spawned.

      Markers (rhylib_droid_marker, only admins see them): attack here,
      defend this, fall back here. Droids within markerRadius follow a new
      marker, and so does every droid the toolgun places after it.
      Removing a marker frees the droids it held (they guard where they are).

      Aggression 1-5 (config droids aggression, Global2Int
      rhylib_droidAggro for clients): one level for every droid, changed
      live with !droidaggro <1-5> or the toolgun's buttons (staff with the
      toolgun permission). Not saved: a map change goes back to the config.
]]

local D = Rhylib.Droids

D.markers = D.markers or {}   -- [marker] = kind name

local KIND_NAMES = { "attack", "defend", "fallback" }
D.MARKER_KINDS = KIND_NAMES

-- Mode for a droid (and where its area is).
function D.SetMode(droid, mode, center)
    if not (IsValid(droid) and (droid.IsRhylibDroid or droid.IsRhylibClone)) then return end
    if mode ~= "guard" and mode ~= "patrol" and mode ~= "attack" and mode ~= "roam" then mode = "guard" end
    droid.leader, droid.advanceTo, droid.leaderNpc = nil, nil, nil   -- (a new mode ends following an officer / buddy)
    droid.roamGoal, droid.reinforceTo = nil, nil
    droid.mode = mode
    if center then droid.home = center end
    if mode ~= "attack" then droid.objective, droid.objectiveMarker = nil, nil end
    droid:SetNW2String("rhylib_dmode", mode)
end

-- A marker's order on one droid.
function D.ApplyMarker(droid, marker)
    if not (IsValid(droid) and IsValid(marker)) then return end
    local kind = D.markers[marker]
    local pos = marker:GetPos()
    -- (a little spread, so they don't all stand on one spot)
    local spread = Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0) * 220
    -- (kept on the navmesh, so a spot inside a wall doesn't strand them)
    if navmesh and navmesh.GetNearestNavArea then
        local area = navmesh.GetNearestNavArea(pos + spread, false, 400, false, true)
        if IsValid(area) then spread = area:GetClosestPointOnArea(pos + spread) - pos end
    end
    if kind == "attack" then
        D.SetMode(droid, "attack")
        droid.objective = pos + spread
        droid.objectiveMarker = marker
    elseif kind == "defend" then
        D.SetMode(droid, "guard", pos + spread)
        droid.homeMarker = marker
    elseif kind == "fallback" then
        droid.fallback = pos + spread * 0.5
        droid.fallbackMarker = marker
    end
    droid.nextLook = 0
end

-- Markers have a side (2026-10-06bb, owner: clones need their own attack
-- and defend orders): side 1 = clone markers (D.clones, D.lastCloneOrder),
-- else droid markers (D.active, D.lastOrder / D.lastFallback).
local function sideList(side) return side == 1 and (D.clones or {}) or D.active end

function D.MarkerPlaced(marker, kind, side)
    D.markers[marker] = kind
    if side == 1 then
        D.lastCloneOrder = marker
    elseif kind == "fallback" then
        D.lastFallback = marker
    else
        D.lastOrder = marker
    end
    local r = D.Cfg("markerRadius")
    local pos = marker:GetPos()
    for d in pairs(sideList(side)) do
        if IsValid(d) and d:GetPos():DistToSqr(pos) < r * r then D.ApplyMarker(d, marker) end
    end
end

function D.MarkerRemoved(marker)
    D.markers[marker] = nil
    if D.lastOrder == marker then D.lastOrder = nil end
    if D.lastFallback == marker then D.lastFallback = nil end
    if D.lastCloneOrder == marker then D.lastCloneOrder = nil end
    local all = {}
    for d in pairs(D.active) do all[d] = true end
    for d in pairs(D.clones or {}) do all[d] = true end
    for d in pairs(all) do
        if IsValid(d) then
            if d.objectiveMarker == marker then
                d.objectiveMarker = nil
                D.SetMode(d, "guard", d:GetPos())
            end
            if d.homeMarker == marker then d.homeMarker = nil end
            if d.fallbackMarker == marker then
                d.fallbackMarker = nil
                d.fallback = nil
            end
        end
    end
end

-- A droid the toolgun placed: the picked mode, then the latest markers.
function D.ToolPlaced(droid, mode)
    if not (IsValid(droid) and (droid.IsRhylibDroid or droid.IsRhylibClone)) then return end
    D.SetMode(droid, mode or "guard", droid:GetPos())
    if droid.IsRhylibClone then
        -- (clones follow the latest clone marker)
        if IsValid(D.lastCloneOrder) then D.ApplyMarker(droid, D.lastCloneOrder) end
        return
    end
    if IsValid(D.lastOrder) then D.ApplyMarker(droid, D.lastOrder) end
    if IsValid(D.lastFallback) then D.ApplyMarker(droid, D.lastFallback) end
end

-- The toolgun's order brush: every droid near pos gets the mode, with its
-- area centred where it stands (attack: no area).
-- side 1 = clones (a GM can re-order a squad, which ends following an
-- officer), else droids.
function D.PaintMode(pos, mode, side)
    local r = D.Cfg("brushRadius")
    local n = 0
    local picked = {}
    for _, list in ipairs({ sideList(side) }) do
        for d in pairs(list) do
            if IsValid(d) and d:GetPos():DistToSqr(pos) < r * r then
                d.objectiveMarker, d.homeMarker = nil, nil
                D.SetMode(d, mode, d:GetPos())
                d.nextLook = 0
                n = n + 1
                picked[#picked + 1] = d
            end
        end
    end
    -- Spread out (owner: alone or two and two): pair them up; the second
    -- of each pair walks beside the first (D.Buddy).
    if mode == "roam" and D.Buddy then
        table.sort(picked, function(a, b) return a:EntIndex() < b:EntIndex() end)
        for i = 2, #picked, 2 do D.Buddy(picked[i], picked[i - 1]) end
    end
    return n
end

-- Aggression: live, for every droid.
-- Live aggression: kept here, not as a config override, so saving other
-- Server settings never saves it (a map change goes back to the config).
D.aggroLive = D.aggroLive or nil

local function publish()
    SetGlobal2Int("rhylib_droidAggro", D.Aggro())
end
publish()
Rhylib.Hook.Add("InitPostEntity", "droids.aggro", publish)
Rhylib.Hook.Add("Rhylib.ConfigChanged", "droids.aggro", function(m, k)
    -- (changed in Server settings: that wins over the live level)
    if m == "droids" and k == "aggression" then
        D.aggroLive = nil
        timer.Simple(0, publish)
    end
end)

function D.SetAggro(n, by)
    n = math.Clamp(math.Round(tonumber(n) or 3), 1, 5)
    D.aggroLive = n
    publish()
    -- (droids re-plan at once)
    for d in pairs(D.active) do
        if IsValid(d) then d.planAt = 0 end
    end
    local msg = string.format("[Droids] Aggression %d: %s%s", n, D.AGGRO_NAMES[n], IsValid(by) and (" (" .. by:Nick() .. ")") or "")
    for _, p in ipairs(player.GetHumans()) do
        if p:IsAdmin() then p:ChatPrint(msg) end
    end
    print(msg)
end

local function canOrder(ply, fn)
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) then return end
        if not ok then return ply:ChatPrint("You don't have permission to command droids") end
        fn()
    end)
end

Rhylib.Net.Register("droids.aggro")
Rhylib.Net.Receive("droids.aggro", function(ply)
    local n = net.ReadUInt(3)
    if n < 1 or n > 5 then return end
    canOrder(ply, function() D.SetAggro(n, ply) end)
end, { rate = 4, burst = 6 })

Rhylib.Hook.Add("PlayerSay", "droids.aggro", function(ply, text)
    local cmd, arg = string.match(string.lower(string.Trim(text or "")), "^[!/](%S+)%s*(%S*)")
    if cmd ~= "droidaggro" and cmd ~= "aggression" then return end
    local n = tonumber(arg)
    if not n then
        ply:ChatPrint(string.format("[Droids] Aggression is %d (%s). !droidaggro 1-5 changes it.", D.Aggro(), D.AGGRO_NAMES[D.Aggro()]))
        return ""
    end
    canOrder(ply, function() D.SetAggro(n, ply) end)
    return ""
end, -50)

concommand.Add("rhylib_droidaggro", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    D.SetAggro(args[1])
end)
