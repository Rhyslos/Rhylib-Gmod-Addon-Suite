--[[
    Droid orders (server, owner 2026-10-06): what GMs tell droids to do.

      Modes (per droid, NW2String rhylib_dmode for the GM labels):
        guard   hold a post (droid.home) and fight within guardRadius
        patrol  walk around a centre (droid.home) within patrolRadius
        attack  push on: to an attack marker (droid.objective), else
                hunt the nearest players
        roam    spread out: wander the map in twos (D.Buddy, D.RoamPoint)
        retreat withdraw from the enemy, nowhere in particular (run, turn
                and fight, run on; last stand when cornered; rhylib_b1
                ENT:RetreatPlan). Aggression 1 does the same.
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

    Net droids.aggro (client -> server, the toolgun's buttons): level
    UInt 3 (1-5). Checked against permission rhylib.toolgun (registered by
    rhylib_toolgun; without that addon the check always says no).
    Chat: !droidaggro / !aggression [1-5] (same permission; no number shows
    the level). Console: rhylib_droidaggro <1-5> (server console or
    superadmin; no number sets 3).
    Clone markers and orders use side 1 (see D.MarkerPlaced, D.PaintMode).
]]

local D = Rhylib.Droids

D.markers = D.markers or {}   -- [marker] = kind name

local KIND_NAMES = { "attack", "defend", "fallback" }
D.MARKER_KINDS = KIND_NAMES

-- D.SetMode(npc, mode, center): sets a droid's or clone's mode ("guard",
-- "patrol", "attack", "roam", "retreat"; anything else = "guard") and,
-- if given, its home (centre of its area). Ends following, command wheel
-- orders, a running retreat and roam pairing. Server.
-- Example: Rhylib.Droids.SetMode(droid, "patrol", droid:GetPos())
function D.SetMode(droid, mode, center)
    if not (IsValid(droid) and (droid.IsRhylibDroid or droid.IsRhylibClone)) then return end
    if mode ~= "guard" and mode ~= "patrol" and mode ~= "attack" and mode ~= "roam" and mode ~= "retreat" then mode = "guard" end
    droid.leader, droid.advanceTo, droid.leaderNpc = nil, nil, nil   -- (a new mode ends following an officer / buddy)
    droid.roamGoal, droid.reinforceTo = nil, nil
    droid.holdAt, droid.orderAggro = nil, nil   -- (command wheel orders end with the follow)
    droid.rt, droid.lastStand, droid.retreatDir = nil, nil, nil   -- (a retreat starts over)
    droid.buddyRoam = nil
    if droid.IsRhylibClone then droid:SetNW2Entity("rhylib_lead", NULL) end
    droid.mode = mode
    if center then droid.home = center end
    if mode ~= "attack" then droid.objective, droid.objectiveMarker = nil, nil end
    droid:SetNW2String("rhylib_dmode", mode)
end

-- D.ApplyMarker(npc, marker): applies one marker's order to one NPC:
-- attack -> attack mode toward a spot near it, defend -> guard there,
-- fallback -> its fallback point. Spots are spread 220 around the marker
-- and snapped to the navmesh.
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

-- D.MarkerPlaced(marker, kindName, side): called by a new marker entity a
-- tick after it spawns. Applies it to that side's NPCs within markerRadius
-- and remembers it so NPCs the toolgun places later follow it too.
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

-- D.MarkerRemoved(marker): called from the marker's OnRemove. Attackers it
-- sent guard where they stand; its fallback point is cleared.
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

-- Placed in roam mode: paired up two and two like the brush does (the
-- next one placed within 3 s and 500 units walks beside this one).
D.roamSolo = D.roamSolo or {}

-- D.ToolPlaced(npc, mode): a droid or clone the toolgun (or a preset)
-- placed: the picked mode, then the latest markers of its side. Roam
-- placements pair up (D.roamSolo). Called by rhylib_toolgun.
function D.ToolPlaced(droid, mode)
    if not (IsValid(droid) and (droid.IsRhylibDroid or droid.IsRhylibClone)) then return end
    D.SetMode(droid, mode or "guard", droid:GetPos())
    if mode == "roam" and D.Buddy then
        local side = droid.IsRhylibClone and 1 or 2
        local solo = D.roamSolo[side]
        if solo and IsValid(solo.e) and solo.e.mode == "roam" and CurTime() - solo.at < 3
            and solo.e:GetPos():DistToSqr(droid:GetPos()) < 500 * 500 then
            D.Buddy(droid, solo.e)
            D.roamSolo[side] = nil
        else
            D.roamSolo[side] = { e = droid, at = CurTime() }
        end
    end
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
-- D.PaintMode(pos, mode, side) -> how many NPCs got it. Called by the
-- toolgun's order entries (ord_*, cord_*).
-- Example: Rhylib.Droids.PaintMode(tr.HitPos, "attack")   -- droids near the spot
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
    -- Retreat: one shared way out for the group, away from the enemies
    -- around it (so they stay roughly together), and the alarm raised so
    -- they start moving even if nobody is shooting yet.
    if mode == "retreat" and #picked > 0 then
        local centre = Vector(0, 0, 0)
        for _, d in ipairs(picked) do centre = centre + d:GetPos() end
        centre = centre / #picked
        local foes = side == 1 and D.CloneTargets and D.CloneTargets() or (D.DroidTargets and D.DroidTargets()) or {}
        local mid, nf = Vector(0, 0, 0), 0
        for _, e in ipairs(foes) do
            if IsValid(e) and e:GetPos():DistToSqr(centre) < 4000 * 4000 then
                mid = mid + e:GetPos()
                nf = nf + 1
            end
        end
        local dir
        if nf > 0 then
            mid = mid / nf
            dir = centre - mid
        else
            -- (nobody about: back the way they face)
            dir = Vector(0, 0, 0)
            for _, d in ipairs(picked) do dir = dir - d:GetForward() end
        end
        dir.z = 0
        if dir:LengthSqr() > 0.01 then dir:Normalize() else dir = nil end
        local now = CurTime()
        for _, d in ipairs(picked) do
            d.retreatDir = dir
            if not d.threatAt or now - d.threatAt > 5 then
                d.threatPos = nf > 0 and mid or (dir and d:GetPos() - dir * 300) or nil
                d.threatAt = now
            end
            d.woken, d.redirect, d.planAt = true, true, 0
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

-- D.SetAggro(n, by): sets the live aggression for every droid (1-5,
-- rounded and clamped; not a number = 3), publishes it to clients, makes
-- droids re-plan and tells online admins in chat. by (player) is named in
-- the message, may be nil. Server. Not saved.
-- Example: Rhylib.Droids.SetAggro(5)   -- everyone charges
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
