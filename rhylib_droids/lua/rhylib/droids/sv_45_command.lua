--[[
    Command mode orders (server): what the toolgun's Command mode
    (rhylib_toolgun cl_20_command.lua) sends for the NPCs a GM selected.

    Net droids.cmd (client -> server; rate 10/s, permission rhylib.toolgun):
      UInt 4 op, UInt 7 count (at most 100), count x UInt 13 entity index,
      then by op:
        1 MOVE      Vector spot, Bool has facing, Float yaw: the selection
                    goes there in formation (squads side by side, facing
                    yaw, else the way they walk). NPCs not in a squad are
                    made into squads first.
        2 ATTACK    UInt 13 target entity: hunt it (attack mode toward
                    it, and they know where it is).
        3 AGGRO     UInt 3 level (0 = back to the global level, 1-5); loose
                    NPCs keep their own level (no squads are made).
        4 MODE      UInt 3 (1 hold / guard where they stand, 2 patrol,
                    3 hunt = attack mode, 4 roam, 5 retreat). Only MOVE,
                    FORMATION and GROUP make squads out of loose NPCs.
        5 FORMATION the next formation (box > wedge > line > column >
                    spread > box).
        6 GROUP     all of them into one squad (at most squadMax).
        7 SPLIT     out of their squads.
        8 REMOVE    removes them.
        9 ASSAULT   Vector spot: attack mode with that spot as their
                    objective (squads in formation); remembered as the
                    side's assault point (D.assault[side]): NPCs placed
                    as ASSAULT go there too, so a GM can send wave after
                    wave of only those.
       10 SPREAD    Vector centre, UInt 12 radius: out of their squads,
                    each to its own spot spread over the circle (navmesh
                    hiding spots first, as far apart as they can be),
                    holding it facing outward.
       11 DEFEND    Vector centre, UInt 12 radius: a ring all round the
                    centre, each on a spot of the ring (cover that faces
                    out where there is some), facing outward; clones
                    crouch; they hold the ring (postRadius) in a fight.
       12 AREA      Vector centre, UInt 12 radius: patrol that circle
                    (squads in formation, loose ones each on their own).
       13 ROUTE     UInt 4 n (2-12), n x Vector: patrol the points in a
                    loop, starting at the nearest (loose NPCs are made
                    into squads first).
    Only Rhylib droids and clones count; a selection with both sides is
    split into each side's own squads. A reply notice says what happened.
]]

local D = Rhylib.Droids

local OPS = { "move", "attack", "aggro", "mode", "formation", "group", "split", "remove",
    "assault", "spread", "defend", "area", "route" }
D.CMD_OPS = OPS
local MODES = { "guard", "patrol", "attack", "roam", "retreat" }
local MODE_SAY = { guard = "Hold", patrol = "Patrol", attack = "Hunt", roam = "Roam", retreat = "Retreat" }

local function note(ply, text, kind)
    Rhylib.Notify(ply, text, kind or "info", "Droids")
end

-- The selection, cut into units: existing squads (whole) and the loose
-- NPCs of each side.
local function units(list)
    local squads, seen, loose = {}, {}, { {}, {} }
    for _, d in ipairs(list) do
        local sq = d.squad
        if sq and D.squads[sq.id] == sq then
            if not seen[sq] then seen[sq] = true squads[#squads + 1] = sq end
        else
            local side = d.IsRhylibClone and 1 or 2
            loose[side][#loose[side] + 1] = d
        end
    end
    return squads, loose
end

-- Loose NPCs into squads (squadable ones); the rest stay single.
local function squadUp(squads, loose, opts)
    local singles = {}
    for side = 1, 2 do
        local made = #loose[side] > 1 and D.MakeSquads(loose[side], opts) or {}
        for _, sq in ipairs(made) do squads[#squads + 1] = sq end
        for _, d in ipairs(loose[side]) do
            if not d.squad then singles[#singles + 1] = d end
        end
    end
    return singles
end

D.assault = D.assault or {}   -- [side] = the latest assault point (1 clones, 2 droids)

local function wake(d)
    d.objectiveMarker, d.homeMarker = nil, nil
    d.lastSeen = nil
    d.woken, d.redirect, d.planAt, d.nextLook = true, true, 0, 0
end

-- Spots over a circle for Spread out: navmesh hiding spots and area
-- centres inside it, picked one by one as far from the others as they
-- can be (hiding spots count a little further). Fewer than n: points on
-- rings round the centre fill in.
local function spreadSpots(center, r, n)
    local cand = {}
    if navmesh and navmesh.Find then
        local areas = navmesh.Find(center, r, 200, 200) or {}
        for i = 1, math.min(#areas, 80) do
            local a = areas[i]
            local c = a:GetCenter()
            if c:DistToSqr(center) <= r * r then cand[#cand + 1] = { v = c, w = 1 } end
            local hs = a:GetHidingSpots(1) or {}
            for k = 1, math.min(#hs, 3) do
                if hs[k]:DistToSqr(center) <= r * r then cand[#cand + 1] = { v = hs[k], w = 1.25 } end
            end
        end
    end
    local out = {}
    if #cand > 0 then
        -- (the first one nearest the centre)
        local best, bd = 1, math.huge
        for i, c in ipairs(cand) do
            local d = c.v:DistToSqr(center)
            if d < bd then best, bd = i, d end
        end
        local minD = {}
        local function take(i)
            local v = cand[i].v
            out[#out + 1] = v
            for j, c in ipairs(cand) do
                local d = c.v:Distance(v)
                minD[j] = math.min(minD[j] or math.huge, d)
            end
        end
        take(best)
        while #out < n do
            local bi, bs = nil, 60   -- (no two closer than 60)
            for j, c in ipairs(cand) do
                local sc = (minD[j] or 0) * c.w
                if (minD[j] or 0) > 60 and sc > bs then bi, bs = j, sc end
            end
            if not bi then break end
            take(bi)
        end
    end
    local k = 0
    while #out < n do
        k = k + 1
        local a = k * 2.4   -- (a spiral: golden angle)
        local rr = r * math.sqrt(k / (n + 1))
        out[#out + 1] = D.SnapNav(center + Vector(math.cos(a) * rr, math.sin(a) * rr, 0))
    end
    return out
end

-- Spots on a ring for Defend 360, each with its outward yaw: the ring
-- point, or a hiding spot near it with something solid just outside it
-- (cover that faces out).
local function ringSpots(center, r, n)
    local out = {}
    for i = 1, n do
        local a = (i - 1) / n * math.pi * 2
        local dir = Vector(math.cos(a), math.sin(a), 0)
        local p = D.SnapNav(center + dir * r)
        local best
        if navmesh and navmesh.Find then
            local areas = navmesh.Find(p, 140, 80, 80) or {}
            local bd = math.huge
            for k = 1, math.min(#areas, 8) do
                for _, h in ipairs(areas[k]:GetHidingSpots(1) or {}) do
                    local d = h:DistToSqr(p)
                    if d < 140 * 140 and d < bd then
                        local tr = util.TraceLine({ start = h + Vector(0, 0, 36), endpos = h + Vector(0, 0, 36) + dir * 150, mask = MASK_SOLID })
                        if tr.Hit then best, bd = h, d end
                    end
                end
            end
        end
        out[i] = { v = best or p, yaw = math.deg(a) }
    end
    return out
end

-- Each spot to the nearest NPC still without one.
local function assign(list, spots)
    local left, pairsOut = {}, {}
    for _, d in ipairs(list) do left[d] = true end
    for _, s in ipairs(spots) do
        local v = s.v or s
        local best, bd = nil, math.huge
        for d in pairs(left) do
            local dd = d:GetPos():DistToSqr(v)
            if dd < bd then best, bd = d, dd end
        end
        if not best then break end
        left[best] = nil
        pairsOut[#pairsOut + 1] = { d = best, s = s }
    end
    return pairsOut
end

local NEXT_FORM = { box = "wedge", wedge = "line", line = "column", column = "spread", spread = "box" }

local function run(ply, op, list, pl)
    local squads, loose = units(list)
    local n = #list
    if op == "move" then
        local spot, hasFace, yaw = pl.spot, pl.hasFace, pl.yaw
        local singles = squadUp(squads, loose, {})
        -- Facing: given, else from the selection's middle to the spot.
        local mid = Vector(0, 0, 0)
        for _, d in ipairs(list) do mid = mid + d:GetPos() end
        mid = mid / math.max(n, 1)
        local face = hasFace and yaw or nil
        local lineYaw = face or (spot - mid):Angle().y
        local right = Angle(0, lineYaw, 0):Right()
        -- (several units side by side across the facing, each as wide as
        -- its formation, a gap between them)
        local sp = D.Cfg("squadSpacing")
        local units, total = {}, 0
        for _, sq in ipairs(squads) do
            local hw = D.SquadHalfWidth(sq) + sp * 0.75
            units[#units + 1] = { sq = sq, hw = hw }
            total = total + hw * 2
        end
        for _, d in ipairs(singles) do
            units[#units + 1] = { d = d, hw = sp * 0.75 }
            total = total + sp * 1.5
        end
        local x = -total / 2
        for _, u in ipairs(units) do
            local at = spot + right * (x + u.hw)
            x = x + u.hw * 2
            if u.sq then
                D.SquadMove(u.sq, at, face)
            else
                local d = u.d
                d.objectiveMarker, d.homeMarker = nil, nil
                D.SetMode(d, "guard", D.SnapNav(at))
                d.lastSeen, d.woken, d.redirect, d.planAt, d.nextLook = nil, true, true, 0, 0
            end
        end
        return string.format("%d moving%s", n, face and " (facing set)" or ""), "good"
    elseif op == "attack" then
        local t = Entity(pl.v)
        if not (IsValid(t) and (t:IsPlayer() or t:IsNPC() or t:IsNextBot())) then return "No target there", "bad" end
        local singles = {}
        for side = 1, 2 do for _, d in ipairs(loose[side]) do singles[#singles + 1] = d end end
        local now = CurTime()
        local function hunt(d)
            if not d:IsFoe(t) then return end
            d.objectiveMarker, d.homeMarker = nil, nil
            D.SetMode(d, "attack")
            d.objective = t:GetPos()
            d.lastSeen, d.lastSeenAt = t:GetPos(), now
            d.threatPos, d.threatAt = t:GetPos(), now
            d.woken, d.redirect, d.planAt, d.nextLook = true, true, 0, 0
        end
        for _, sq in ipairs(squads) do
            sq.face = nil
            for _, d in ipairs(sq.list) do hunt(d) end
        end
        for _, d in ipairs(singles) do hunt(d) end
        return string.format("%d attacking %s", n, t:IsPlayer() and t:Nick() or (t.PrintName or t:GetClass())), "good"
    elseif op == "aggro" then
        local lv = pl.v
        lv = (lv >= 1 and lv <= 5) and lv or nil
        local singles = {}
        for side = 1, 2 do for _, d in ipairs(loose[side]) do singles[#singles + 1] = d end end
        for _, sq in ipairs(squads) do D.SetSquadAggro(sq, lv) end
        for _, d in ipairs(singles) do
            d.ownAggro = lv
            d:SetNW2Int("rhylib_saggro", lv or 0)
            d.planAt = 0
        end
        return string.format("%d: aggression %s", n, lv and (lv .. " " .. D.AGGRO_NAMES[lv]) or "back to the global level"), "good"
    elseif op == "mode" then
        local mode = MODES[pl.v]
        if not mode then return end
        if mode == "roam" then
            -- (roaming: two and two, like the brush; squads break up)
            for _, d in ipairs(list) do D.LeaveSquad(d) end
            local done = {}
            for _, d in ipairs(list) do
                if not done[d] then
                    done[d] = true
                    D.SetMode(d, "roam", d:GetPos())
                end
            end
            if D.Buddy then
                for side = 1, 2 do
                    local s = {}
                    for _, d in ipairs(list) do if (d.IsRhylibClone and 1 or 2) == side then s[#s + 1] = d end end
                    for k = 2, #s, 2 do D.Buddy(s[k], s[k - 1]) end
                end
            end
        elseif mode == "retreat" then
            D.SetGroupMode(list, "retreat")
        else
            local singles = {}
            for side = 1, 2 do for _, d in ipairs(loose[side]) do singles[#singles + 1] = d end end
            for _, sq in ipairs(squads) do
                if mode == "guard" then
                    D.SquadMove(sq, sq.leader:GetPos(), sq.leader:GetAngles().y)
                else
                    D.SquadMode(sq, mode, sq.leader:GetPos())
                end
            end
            for _, d in ipairs(singles) do
                d.objectiveMarker, d.homeMarker = nil, nil
                D.SetMode(d, mode, d:GetPos())
                d.woken, d.planAt, d.nextLook = true, 0, 0
            end
        end
        return string.format("%d: %s", n, MODE_SAY[mode]), "good"
    elseif op == "formation" then
        local singles = squadUp(squads, loose, {})
        local name
        for _, sq in ipairs(squads) do
            name = name or NEXT_FORM[sq.formation] or "box"
            D.SetFormation(sq, name)
        end
        if not name then return "Pick two or more to make a formation", "bad" end
        return string.format("%d squad%s: %s", #squads, #squads == 1 and "" or "s", D.FORMATION_NAMES[name]), "good"
    elseif op == "group" then
        local out = {}
        for side = 1, 2 do
            local s = {}
            for _, d in ipairs(list) do
                if (d.IsRhylibClone and 1 or 2) == side and D.Squadable(d) then s[#s + 1] = d end
            end
            if #s > 1 then
                local made = D.MakeSquads(s, { size = D.Cfg("squadMax") })
                for _, sq in ipairs(made) do out[#out + 1] = sq end
            end
        end
        if #out == 0 then return "Pick two or more droids or clones (not artillery or followers)", "bad" end
        return string.format("%d in %d squad%s", n, #out, #out == 1 and "" or "s"), "good"
    elseif op == "split" then
        for _, d in ipairs(list) do D.LeaveSquad(d) end
        return string.format("%d out of their squads", n), "info"
    elseif op == "remove" then
        for _, d in ipairs(list) do d:Remove() end
        return string.format("Removed %d", n), "info"
    elseif op == "assault" then
        local spot = D.SnapNav(pl.spot)
        local singles = {}
        for side = 1, 2 do for _, d in ipairs(loose[side]) do singles[#singles + 1] = d end end
        local sides = {}
        for _, sq in ipairs(squads) do
            D.SquadMode(sq, "attack")
            for _, d in ipairs(sq.list) do d.objective = spot end
            sides[sq.leader.IsRhylibClone and 1 or 2] = true
        end
        for _, d in ipairs(singles) do
            wake(d)
            D.SetMode(d, "attack")
            d.objective = D.SnapNav(spot + Vector(math.Rand(-1, 1), math.Rand(-1, 1), 0) * 150)
            sides[d.IsRhylibClone and 1 or 2] = true
        end
        for side in pairs(sides) do D.assault[side] = spot end
        return string.format("%d assaulting the point (place more as ASSAULT to send them there too)", n), "good"
    elseif op == "spread" or op == "defend" then
        local center, r = pl.spot, pl.r
        for _, d in ipairs(list) do D.LeaveSquad(d) end
        local defend = op == "defend"
        local spots = defend and ringSpots(center, r, n) or spreadSpots(center, r, n)
        for _, pr in ipairs(assign(list, spots)) do
            local d, s = pr.d, pr.s
            local v = s.v or s
            wake(d)
            D.SetMode(d, "guard", v)
            local out = v - center
            out.z = 0
            d.posted = true
            d.areaRadius = D.Cfg("postRadius")
            d.holdYaw = s.yaw or (out:LengthSqr() > 50 * 50 and out:Angle().y or (v - d:GetPos()):Angle().y)
            d.defending = defend or nil
        end
        return string.format("%d %s (%d m)", n, defend and "setting up a defence all round" or "spreading out", math.Round(r * 0.019)), "good"
    elseif op == "area" then
        local center, r = D.SnapNav(pl.spot), pl.r
        local singles = {}
        for side = 1, 2 do for _, d in ipairs(loose[side]) do singles[#singles + 1] = d end end
        for _, sq in ipairs(squads) do
            D.SquadMode(sq, "patrol", center)
            for _, d in ipairs(sq.list) do d.home, d.areaRadius = center, r end
        end
        for _, d in ipairs(singles) do
            wake(d)
            D.SetMode(d, "patrol", center)
            d.areaRadius = r
        end
        return string.format("%d patrolling the area (%d m)", n, math.Round(r * 0.019)), "good"
    elseif op == "route" then
        local pts = pl.pts
        if #pts < 2 then return "A route needs two points or more", "bad" end
        for i, p in ipairs(pts) do pts[i] = D.SnapNav(p) end
        local singles = squadUp(squads, loose, {})
        local function start(d)
            local best, bd = 1, math.huge
            for i, p in ipairs(pts) do
                local dd = p:DistToSqr(d:GetPos())
                if dd < bd then best, bd = i, dd end
            end
            d.route, d.routeIdx = pts, best
        end
        for _, sq in ipairs(squads) do
            D.SquadMode(sq, "patrol", pts[1])
            for _, d in ipairs(sq.list) do d.areaRadius = D.Cfg("patrolRadius") end
            start(sq.leader)
        end
        for _, d in ipairs(singles) do
            wake(d)
            D.SetMode(d, "patrol", pts[1])
            start(d)
        end
        return string.format("%d on a %d point patrol route", n, #pts), "good"
    end
end

Rhylib.Net.Register("droids.cmd")
Rhylib.Net.Receive("droids.cmd", function(ply)
    local op = OPS[net.ReadUInt(4)]
    local count = math.min(net.ReadUInt(7), 100)
    local list = {}
    for _ = 1, count do
        local e = Entity(net.ReadUInt(13))
        if IsValid(e) and (e.IsRhylibDroid or e.IsRhylibClone) and e:Health() > 0 then list[#list + 1] = e end
    end
    if not op then return end
    -- (a real point in the map: no NaN or huge numbers)
    local function okVec(v)
        return v and v.x == v.x and v.y == v.y and v.z == v.z
            and math.abs(v.x) < 32768 and math.abs(v.y) < 32768 and math.abs(v.z) < 32768
    end
    -- (read the rest now: the permission check may answer later)
    local payload = {}
    if op == "move" then
        payload.spot, payload.hasFace, payload.yaw = net.ReadVector(), net.ReadBool(), net.ReadFloat()
    elseif op == "attack" then
        payload.v = net.ReadUInt(13)
    elseif op == "aggro" or op == "mode" then
        payload.v = net.ReadUInt(3)
    elseif op == "assault" then
        payload.spot = net.ReadVector()
    elseif op == "spread" or op == "defend" or op == "area" then
        payload.spot = net.ReadVector()
        payload.r = math.Clamp(net.ReadUInt(12), 100, 2500)
    elseif op == "route" then
        local k = net.ReadUInt(4)
        payload.pts = {}
        for i = 1, math.min(k, 12) do
            local v = net.ReadVector()
            if okVec(v) then payload.pts[#payload.pts + 1] = v end
        end
    end
    if (payload.spot and not okVec(payload.spot)) or (payload.yaw and payload.yaw ~= payload.yaw) then return end
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) then return end
        if not ok then return note(ply, "You don't have permission to command droids", "bad") end
        local live = {}
        for _, e in ipairs(list) do if IsValid(e) and e:Health() > 0 then live[#live + 1] = e end end
        if #live == 0 then return note(ply, "Nothing selected (LMB on droids or clones first)", "bad") end
        local okRun, msg, kind = pcall(run, ply, op, live, payload)
        if not okRun then
            Rhylib.Warn("droids", "command %s failed: %s", op, tostring(msg))
            return
        end
        if msg then note(ply, msg, kind) end
    end)
end, { rate = 10, burst = 10 })
