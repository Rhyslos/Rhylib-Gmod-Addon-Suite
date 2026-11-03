--[[
    Squads (server): droids or clones that move together in a formation.

    A squad has a leader that does the normal job (its mode: guard,
    patrol, attack, roam, a GM move order) and plans the only navmesh
    route. Every other member keeps a slot beside or behind the leader
    (brain/squad.lua): it walks straight to the slot when the way is clear,
    else to a point on the leader's own trail (in a corridor or a doorway
    they fall in single file and spread out again after), else plans its
    own route. Members keep a little room between each other. The leader
    slows down while members lag behind. In a fight everyone fights on its
    own; squad members charging a target spread out sideways by their slot
    instead of all running at the same spot.

    Formations (squad.formation): "wedge" (default), "line", "column",
    "spread" (a loose wedge). Slots are worked out from the leader's
    heading (the way it walks; standing still: squad.face, else where it
    faces).

    Squads are made when the toolgun places several NPCs at once, a preset
    squad (cut into squads of squadSize), or a GM groups NPCs in the
    toolgun's Command mode (D.MakeSquad). Clones following an officer,
    artillery and the NPCs guarding it keep their own way of following and
    are never put in a squad.

    Roam and patrol groups (D.WanderGroups): NPCs given roam or patrol are
    cut into groups of wanderClones / wanderDroids (roaming droids left
    over: a group of 4 or 2; one left over goes alone). Patrols walk in
    column, roaming droids spread out, roaming clones as a wedge. One placed
    at a time, they join the last one placed (D.WanderJoin).

    Calls for help (D.CallHelp, from ENT:Look on fresh contact): idle
    roaming, patrolling and guarding groups of the caller's side within callRadius (clones
    ctCallRadius) come, whole groups, nearest first, until callHelpers
    (clones ctCallHelpers) are coming. The group's leader gets
    reinforceTo (it runs there, the members run with it) and every member
    npc.helpUntil (D.Helping: a patrol or guard may fight outside its area,
    kept on while it fights; after, it walks back to its range or post).

    Per squad aggression (squad.aggro 1-5, nil = the global level) beats
    the global droid aggression and the clones' own (ENT:Aggro).

    One timer for every squad (0.25 s): drops dead or removed members, picks
    a new leader when the leader is gone (a commander first), keeps the
    leader's trail (a point every 48 units, the last 40) and heading, and
    how far behind its members are (squad.lag).

    Data: D.squads = { [id] = squad }, squad = { id, side (1 clones, 2
    droids), members = { [npc] = true }, list (in slot order), leader,
    formation, aggro, face (yaw), trail = { Vector... }, heading (yaw),
    lag }. On the NPC: npc.squad, npc.slotIdx (0 = leader). NW2Int
    rhylib_squad on each member (the squad id, for the toolgun's selection
    and labels), NW2Int rhylib_saggro (the squad's aggression, 0 = global).
]]

local D = Rhylib.Droids

D.squads = D.squads or {}
D.nextSquadId = D.nextSquadId or 1

D.FORMATIONS = { "box", "wedge", "line", "column", "spread" }
D.FORMATION_NAMES = { box = "Box", wedge = "Wedge", line = "Line", column = "Column", spread = "Spread out" }

-- Box formation: each member keeps its own place in the block (npc.fmOff
-- = { forward, right } from the leader, in the squad's facing). A preset
-- keeps the block it was placed in; other squads get a grid (leader in
-- the middle of the front row, rows of about the square root of the
-- squad size).
local function boxGrid(sq)
    local list = sq.list
    local n = #list
    if n == 0 then return end
    local sp = D.Cfg("squadSpacing")
    local cols = math.max(2, math.ceil(math.sqrt(n * 1.5)))
    local cells = {}
    local rows = math.ceil(n / cols)
    for r = 0, rows do
        for c = 0, cols - 1 do cells[#cells + 1] = { r = r, c = c } end
    end
    local mid = (cols - 1) / 2
    table.sort(cells, function(a, b)
        if a.r ~= b.r then return a.r < b.r end
        return math.abs(a.c - mid) < math.abs(b.c - mid)
    end)
    local lc = cells[1]
    for i, d in ipairs(list) do
        local cell = cells[i]
        d.fmOff = { -(cell.r - lc.r) * sp * 1.05, (cell.c - lc.c) * sp * 0.95 }
    end
end
D.BoxGrid = boxGrid

-- Box offsets from where they stand now (a preset's block), in yaw's frame.
local function boxKeep(sq, yaw)
    local lead = sq.leader
    if not IsValid(lead) then return boxGrid(sq) end
    local ang = Angle(0, yaw or lead:GetAngles().y, 0)
    local fwd, right = ang:Forward(), ang:Right()
    local lp = lead:GetPos()
    for _, d in ipairs(sq.list) do
        local dv = d:GetPos() - lp
        d.fmOff = { dv:Dot(fwd), dv:Dot(right) }
    end
end

-- Can this NPC be in a squad? (Not following an officer or an NPC, not
-- artillery, alive.)
local function squadable(d)
    return IsValid(d) and (d.IsRhylibDroid or d.IsRhylibClone) and d:Health() > 0
        and not d.artillery and not d.leader and not d.overCap
end
D.Squadable = squadable

local function sideOf(d) return d.IsRhylibClone and 1 or 2 end

-- Slot order: commander first (leader), then by distance to the first.
local function relist(sq)
    local oldLead = sq.leader
    local list = {}
    for d in pairs(sq.members) do
        if IsValid(d) then list[#list + 1] = d else sq.members[d] = nil end
    end
    local lead = IsValid(sq.leader) and sq.members[sq.leader] and sq.leader or nil
    if not lead then
        for _, d in ipairs(list) do
            if d:Kind().commander then lead = d break end
        end
        lead = lead or list[1]
    end
    sq.leader = lead
    if not lead then sq.list = {} return end
    local lp = lead:GetPos()
    table.sort(list, function(a, b)
        if a == lead then return true end
        if b == lead then return false end
        return a:GetPos():DistToSqr(lp) < b:GetPos():DistToSqr(lp)
    end)
    sq.list = list
    for i, d in ipairs(list) do d.slotIdx = i - 1 end
    -- (box: the block stays where it is around the new leader)
    if lead ~= oldLead and lead.fmOff then
        local f0, r0 = lead.fmOff[1], lead.fmOff[2]
        for _, d in ipairs(list) do
            if d.fmOff then d.fmOff = { d.fmOff[1] - f0, d.fmOff[2] - r0 } end
        end
    end
    -- A new leader takes over the squad's job (kept by the timer while
    -- the old one led), so the squad doesn't wander back to its post.
    if lead ~= oldLead and oldLead ~= nil and sq.jMode and sq.jMode ~= "follow" then
        -- (answering a call for help: the new leader carries on)
        local help = lead.helpUntil
        D.SetMode(lead, sq.jMode, sq.jHome)
        lead.helpUntil = help
        lead.reinforceTo, lead.reinforceUntil, lead.reinforceEnemy = sq.jReinforce, sq.jReinforceUntil, sq.jReinforceEnemy
        lead.objective, lead.fallback = sq.jObjective, sq.jFallback
        lead.route, lead.routeIdx, lead.areaRadius = sq.jRoute, sq.jRouteIdx, sq.jArea
    end
end

local function publish(d, sq)
    d:SetNW2Int("rhylib_squad", sq and sq.id or 0)
    d:SetNW2Int("rhylib_saggro", sq and sq.aggro or d.ownAggro or 0)
end

-- D.LeaveSquad(npc): out of its squad (a squad left with one NPC ends).
function D.LeaveSquad(d)
    local sq = d.squad
    if not sq then return end
    d.squad, d.slotIdx = nil, nil
    sq.members[d] = nil
    if IsValid(d) then publish(d, nil) end
    local n = 0
    for m in pairs(sq.members) do if IsValid(m) then n = n + 1 end end
    if n <= 1 then
        for m in pairs(sq.members) do
            if IsValid(m) then m.squad, m.slotIdx = nil, nil publish(m, nil) end
        end
        D.squads[sq.id] = nil
    else
        relist(sq)
    end
end

-- D.MakeSquad(list, opts) -> the new squad (nil if fewer than 2 can join).
-- opts: formation, aggro, face (yaw), keep (box: keep the block they
-- stand in now, facing face). Members leave old squads first.
-- Example: Rhylib.Droids.MakeSquad({ d1, d2, d3 }, { formation = "line" })
function D.MakeSquad(list, opts)
    opts = opts or {}
    local ok = {}
    local side
    for _, d in ipairs(list) do
        if squadable(d) then
            side = side or sideOf(d)
            if sideOf(d) == side then ok[#ok + 1] = d end
        end
    end
    if #ok < 2 then return nil end
    local sq = { id = D.nextSquadId, side = side, members = {}, formation = opts.formation or D.Cfg("squadFormation"),
        aggro = opts.aggro, face = opts.face, trail = {}, lag = 0 }
    D.nextSquadId = D.nextSquadId % 60000 + 1
    if not D.FORMATION_NAMES[sq.formation] then sq.formation = "box" end
    for _, d in ipairs(ok) do
        D.LeaveSquad(d)
        sq.members[d] = true
        d.squad = sq
    end
    D.squads[sq.id] = sq
    relist(sq)
    if opts.keep then boxKeep(sq, opts.face) else boxGrid(sq) end
    for _, d in ipairs(sq.list) do publish(d, sq) end
    return sq
end

-- D.MakeSquads(list, opts) -> squads: like MakeSquad, cut into squads of
-- at most opts.size (default squadSize) (in list order, so a preset's rows stay together).
function D.MakeSquads(list, opts)
    local size = math.max(2, math.floor((opts and opts.size) or D.Cfg("squadSize")))
    local out, chunk = {}, {}
    local usable = {}
    for _, d in ipairs(list) do if squadable(d) then usable[#usable + 1] = d end end
    local nChunks = math.ceil(#usable / size)
    local per = nChunks > 0 and math.ceil(#usable / nChunks) or size   -- (even sizes: 31 → 8, 8, 8, 7)
    for _, d in ipairs(usable) do
        chunk[#chunk + 1] = d
        if #chunk >= per then
            out[#out + 1] = D.MakeSquad(chunk, opts)
            chunk = {}
        end
    end
    if #chunk > 0 then
        local sq = D.MakeSquad(chunk, opts)
        if sq then out[#out + 1] = sq
        elseif #chunk == 1 and out[#out] then
            -- (a single one left over joins the last squad)
            local last = out[#out]
            local d = chunk[1]
            if squadable(d) and sideOf(d) == last.side then
                D.LeaveSquad(d)
                last.members[d], d.squad = true, last
                relist(last)
                if opts and opts.keep then boxKeep(last, opts.face) else boxGrid(last) end
                for _, m in ipairs(last.list) do publish(m, last) end
            end
        end
    end
    return out
end

-- D.SetSquadAggro(sq, n): the squad's own aggression (1-5), nil = global.
function D.SetSquadAggro(sq, n)
    sq.aggro = n and math.Clamp(math.Round(n), 1, 5) or nil
    for d in pairs(sq.members) do
        if IsValid(d) then
            publish(d, sq)
            d.planAt = 0
        end
    end
end

-- D.SetFormation(sq, name)
function D.SetFormation(sq, name)
    if D.FORMATION_NAMES[name] then sq.formation = name end
    if name == "box" then boxGrid(sq) end
    for d in pairs(sq.members) do if IsValid(d) then d.fmAt = 0 end end
end

-- Slot offsets (forward, right) in units, i = 1.. (0 = the leader).
local function slotOffset(form, i, n)
    if i <= 0 then return 0, 0 end
    local sp = D.Cfg("squadSpacing")
    if form == "line" then
        -- (abreast of the leader, alternating right and left)
        local k = math.ceil(i / 2)
        return 0, (i % 2 == 1 and 1 or -1) * k * sp
    elseif form == "column" then
        -- (two files behind the leader)
        local row = math.floor((i + 1) / 2)
        return -row * sp * 0.9, (i % 2 == 1 and 0.5 or -0.5) * sp * 0.8
    end
    local mult = form == "spread" and 1.8 or 1
    local row = math.ceil(i / 2)
    return -row * sp * 0.8 * mult, (i % 2 == 1 and 1 or -1) * row * sp * mult
end
D.SlotOffset = slotOffset

-- D.MemberOffset(npc) -> forward, right of its slot from the leader.
function D.MemberOffset(d)
    local sq = d.squad
    if not sq then return 0, 0 end
    if sq.formation == "box" and d.fmOff then return d.fmOff[1], d.fmOff[2] end
    return slotOffset(sq.formation == "box" and "wedge" or sq.formation, d.slotIdx or 1, #sq.list)
end

-- D.SlotPos(npc) -> where this member should stand now (nil = leader or
-- no squad). Relative to the leader's heading.
function D.SlotPos(d)
    local sq = d.squad
    if not sq or not IsValid(sq.leader) or sq.leader == d then return nil end
    local f, r = D.MemberOffset(d)
    local yaw = sq.heading or sq.leader:GetAngles().y
    local ang = Angle(0, yaw, 0)
    return sq.leader:GetPos() + ang:Forward() * f + ang:Right() * r
end

-- D.SlotAt(npc, pos, yaw) -> the slot this member would have with the
-- leader at pos facing yaw (for spreading a move order's arrival spots).
function D.SlotAt(d, pos, yaw)
    local f, r = D.MemberOffset(d)
    local ang = Angle(0, yaw, 0)
    return pos + ang:Forward() * f + ang:Right() * r
end

-- D.TrailPoint(sq, back) -> the leader's trail point `back` steps (48
-- units each) behind it, or the oldest one.
function D.TrailPoint(sq, back)
    local t = sq.trail
    local n = #t
    if n == 0 then return nil end
    return t[math.max(1, n - back)]
end

-- D.SquadHalfWidth(sq) -> how far its widest member stands to the side.
function D.SquadHalfWidth(sq)
    local w = 0
    for _, d in ipairs(sq.list) do
        local _, r = D.MemberOffset(d)
        w = math.max(w, math.abs(r))
    end
    return w
end

-- D.SquadMembers(sq) -> the live members in slot order.
function D.SquadMembers(sq)
    return sq and sq.list or {}
end

-- D.SnapNav(pos) -> pos moved onto the navmesh (or unchanged).
function D.SnapNav(pos)
    if navmesh and navmesh.GetNearestNavArea then
        local a = navmesh.GetNearestNavArea(pos, false, 300, false, true)
        if IsValid(a) then return a:GetClosestPointOnArea(pos) or pos end
    end
    return pos
end

-- Every squad, 4 times a second.
local TRAIL_STEP, TRAIL_MAX = 48, 40
timer.Create("Rhylib.Droids.Squads", 0.25, 0, function()
    for id, sq in pairs(D.squads) do
        local dirty = false
        for d in pairs(sq.members) do
            if not IsValid(d) or d:Health() <= 0 or d.leader or d.artillery then
                sq.members[d] = nil
                if IsValid(d) then d.squad, d.slotIdx = nil, nil publish(d, nil) end
                dirty = true
            end
        end
        if dirty or not IsValid(sq.leader) or not sq.members[sq.leader] then
            relist(sq)
            if #sq.list <= 1 then
                for m in pairs(sq.members) do
                    if IsValid(m) then m.squad, m.slotIdx = nil, nil publish(m, nil) end
                end
                D.squads[id] = nil
                sq = nil
            else
                for _, d in ipairs(sq.list) do publish(d, sq) end
            end
        end
        if sq then
            local lead = sq.leader
            -- (the leader's job, for whoever takes over)
            sq.jMode, sq.jHome, sq.jObjective, sq.jFallback = lead.mode, lead.home, lead.objective, lead.fallback
            sq.jRoute, sq.jRouteIdx, sq.jArea = lead.route, lead.routeIdx, lead.areaRadius
            sq.jReinforce, sq.jReinforceUntil, sq.jReinforceEnemy = lead.reinforceTo, lead.reinforceUntil, lead.reinforceEnemy
            local lp = lead:GetPos()
            local t = sq.trail
            if #t == 0 or t[#t]:DistToSqr(lp) > TRAIL_STEP * TRAIL_STEP then
                t[#t + 1] = lp
                if #t > TRAIL_MAX then table.remove(t, 1) end
            end
            local v = lead.loco:GetVelocity()
            if v:Length2DSqr() > 900 then
                sq.heading = v:Angle().y
            elseif sq.face and lead.mode == "guard" then
                -- (a post's facing; patrolling squads keep the way they walked)
                sq.heading = sq.face
            end
            -- How far the members are from their slots (the leader waits).
            -- (only members actually trying to keep up; one stuck far
            -- behind for 10 s stops counting)
            local worst, now = 0, CurTime()
            for i = 2, #sq.list do
                local d = sq.list[i]
                if not IsValid(d.target) and d.InSquadFollow and d:InSquadFollow() then
                    local s = D.SlotPos(d)
                    if s then
                        local gap = d:GetPos():Distance(s)
                        if gap > D.Cfg("squadWait") then
                            d.lagSince = d.lagSince or now
                            if now - d.lagSince < 10 then worst = math.max(worst, gap) end
                        else
                            d.lagSince = nil
                        end
                    end
                end
            end
            sq.lag = worst
        end
    end
end)

-- A removed NPC leaves its squad at once.
Rhylib.Hook.Add("EntityRemoved", "droids.squads", function(e)
    if e.squad then D.LeaveSquad(e) end
end)

--------------------------------------------------------------------------
-- Orders for squads (the toolgun's Command mode, sv side in sv_45_command)
--------------------------------------------------------------------------

-- D.SquadMove(sq, pos, yaw): the whole squad to pos, facing yaw when there
-- (nil: the way they walk). The leader guards pos, members take their slots
-- around it.
function D.SquadMove(sq, pos, yaw)
    if not (sq and IsValid(sq.leader)) then return end
    pos = D.SnapNav(pos)
    sq.face = yaw
    sq.trail = {}
    local lead = sq.leader
    lead.objectiveMarker, lead.homeMarker = nil, nil
    D.SetMode(lead, "guard", pos)
    lead.lastSeen = nil
    lead.woken, lead.redirect, lead.planAt, lead.nextLook = true, true, 0, 0
    for i = 2, #sq.list do
        local d = sq.list[i]
        d.objectiveMarker, d.homeMarker = nil, nil
        D.SetMode(d, "guard", D.SnapNav(D.SlotAt(d, pos, yaw or (pos - lead:GetPos()):Angle().y)))
        d.lastSeen = nil
        d.woken, d.redirect, d.planAt, d.fmAt = true, true, 0, 0
    end
end

-- D.SquadMode(sq, mode, pos): the leader takes the mode (centred on pos or
-- where it stands), the members follow it in formation.
function D.SquadMode(sq, mode, pos)
    if not (sq and IsValid(sq.leader)) then return end
    for _, d in ipairs(sq.list) do
        d.objectiveMarker, d.homeMarker = nil, nil
        D.SetMode(d, mode, d == sq.leader and (pos or d:GetPos()) or d:GetPos())
        d.woken, d.redirect, d.planAt, d.nextLook = true, true, 0, 0
    end
    sq.face = nil
end

--------------------------------------------------------------------------
-- Roam and patrol groups, calls for help
--------------------------------------------------------------------------

local function wanderSize(side)
    return math.max(1, math.floor(D.Cfg(side == 1 and "wanderClones" or "wanderDroids")))
end

-- Group sizes for n NPCs: groups of size; roaming droids left over make a
-- group of 4 or 2 (an even number), and a single one left over goes alone.
local function wanderSizes(n, size, evenOnly)
    local out = {}
    while n >= size do out[#out + 1] = size n = n - size end
    if n > 0 then
        if evenOnly and n % 2 == 1 then
            if n > 1 then out[#out + 1] = n - 1 end
            out[#out + 1] = 1
        else
            out[#out + 1] = n
        end
    end
    return out
end
D.WanderSizes = wanderSizes

-- The formation of a roam / patrol group: patrols walk in column, roaming
-- droids spread out, a roaming clone pair walks as a wedge (side by side,
-- one a step behind).
local function wanderFormation(side, mode)
    if mode == "patrol" then return "column" end
    return side == 2 and "spread" or "wedge"
end

-- D.WanderGroups(list, mode, opts) -> squads: puts the NPCs in mode
-- ("roam" or "patrol", centred where each stands; ones already in that
-- mode keep their home and markers) and cuts them into groups by side
-- (wanderClones / wanderDroids; nearest neighbours together). opts:
-- whole = also the rest of any squad one of them is in, aggro = the new
-- groups' aggression (else the one their old squad had). Mortars and the
-- droids guarding them are left out. Called by the toolgun (placing, the
-- order brush, Command mode).
-- Example: Rhylib.Droids.WanderGroups(myDroids, "patrol")
function D.WanderGroups(list, mode, opts)
    if mode ~= "roam" and mode ~= "patrol" then return {} end
    opts = opts or {}
    local whole = opts.whole
    local all, seen = {}, {}
    -- (mortars and the droids guarding them stay as they are)
    local function add(d)
        if IsValid(d) and (d.IsRhylibDroid or d.IsRhylibClone) and not seen[d] and not d.artillery and not d.leaderNpc then
            seen[d] = true
            all[#all + 1] = d
        end
    end
    for _, d in ipairs(list) do
        add(d)
        if whole and IsValid(d) and d.squad then
            for _, m in ipairs(d.squad.list) do add(m) end
        end
    end
    local out = {}
    for side = 1, 2 do
        local left = {}
        local aggro = opts.aggro
        for _, d in ipairs(all) do
            if sideOf(d) == side then
                aggro = aggro or (d.squad and d.squad.aggro)
                D.LeaveSquad(d)
                if d.mode ~= mode then D.SetMode(d, mode, d:GetPos()) end
                if squadable(d) then left[#left + 1] = d end
            end
        end
        for _, size in ipairs(wanderSizes(#left, wanderSize(side), side == 2 and mode == "roam")) do
            -- (the first one left and its nearest neighbours)
            local seed = left[1]:GetPos()
            table.sort(left, function(a, b) return a:GetPos():DistToSqr(seed) < b:GetPos():DistToSqr(seed) end)
            local chunk = {}
            for i = 1, size do chunk[i] = table.remove(left, 1) end
            if #chunk > 1 then
                local sq = D.MakeSquad(chunk, { formation = wanderFormation(side, mode), aggro = aggro })
                if sq then out[#out + 1] = sq end
            end
        end
    end
    return out
end

-- One at a time: an NPC the toolgun places on its own in roam or patrol
-- joins the last one placed on its side (within 3 s and 500 units, same
-- mode) while that group has room (up to wanderClones / wanderDroids, so
-- roaming droids placed one by one can make a group of 3 or 5).
-- D.WanderJoin(npc, mode, aggro), from D.ToolPlaced.
D.wanderRecent = D.wanderRecent or {}
function D.WanderJoin(d, mode, aggro)
    if not (IsValid(d) and (mode == "roam" or mode == "patrol")) then return end
    local side = sideOf(d)
    local r = D.wanderRecent[side]
    local now = CurTime()
    D.wanderRecent[side] = { e = d, at = now, mode = mode }
    if not (r and IsValid(r.e) and r.e ~= d and r.mode == mode and r.e.mode == mode and now - r.at < 3
        and r.e:GetPos():DistToSqr(d:GetPos()) < 500 * 500) then return end
    local group = {}
    for _, m in ipairs(r.e.squad and r.e.squad.list or { r.e }) do group[#group + 1] = m end
    if #group >= wanderSize(side) then return end
    group[#group + 1] = d
    D.MakeSquad(group, { formation = wanderFormation(side, mode), aggro = aggro or (r.e.squad and r.e.squad.aggro) })
end

-- D.Helping(npc) -> true while it (or its squad) answers a call for help:
-- a patrol or guard then fights outside its area, and walks back after.
function D.Helping(d)
    return (d.helpUntil or 0) > CurTime()
end

-- Can this one answer a call? A free roam / patrol / guard NPC (not a
-- Command mode post: Spread out / Defend 360), not already on
-- its way to help, not fighting, not retreating or falling back
-- (aggression 1 or 2, a running retreat), not following anyone.
local function canHelp(u)
    return IsValid(u) and u:Health() > 0 and (u.mode == "roam" or u.mode == "patrol" or u.mode == "guard") and not u.posted
        and not IsValid(u.target) and not u.leader and not u.guardDowned and not u.reviveTarget
        and not u.artillery and not D.Helping(u) and not (u.Retreating and u:Retreating())
        and not (u.Aggro and u:Aggro() <= 2)
end

-- D.CallHelp(caller, enemy): a droid or clone on fresh contact calls
-- idle roaming, patrolling and guarding groups of its side within callRadius (clones
-- ctCallRadius) over, nearest first, whole groups until callHelpers
-- (clones ctCallHelpers) NPCs are coming. Their leader runs to the
-- caller, the group runs with it, and on arrival they go for the enemy.
-- One call per squad (or lone NPC) every callCooldown (ctCallCooldown) s.
-- Called from ENT:Look. (D.CloneCall is the old name.)
function D.CallHelp(caller, enemy)
    if not IsValid(caller) then return end
    local clone = caller.IsRhylibClone
    local now = CurTime()
    local holder = caller.squad or caller
    if (holder.callReady or 0) > now then return end
    holder.callReady = now + D.Cfg(clone and "ctCallCooldown" or "callCooldown")
    local from = caller:GetPos()
    local r2 = D.Cfg(clone and "ctCallRadius" or "callRadius") ^ 2
    local want = math.floor(D.Cfg(clone and "ctCallHelpers" or "callHelpers"))
    if want <= 0 then return end
    local groups = {}
    for u in pairs(clone and (D.clones or {}) or D.active) do
        -- (a squad counts once, through its leader; the caller's own squad is already there)
        local sq = IsValid(u) and u.squad
        if (not sq or sq.leader == u) and (not sq or sq ~= caller.squad) and u ~= caller and canHelp(u) then
            local d = u:GetPos():DistToSqr(from)
            if d < r2 then groups[#groups + 1] = { u = u, n = sq and #sq.list or 1, d = d } end
        end
    end
    if #groups == 0 then return end
    table.sort(groups, function(a, b) return a.d < b.d end)
    local to = D.SnapNav(from)
    local coming = 0
    for _, g in ipairs(groups) do
        if coming >= want then break end
        coming = coming + g.n
        local lead = g.u
        lead.reinforceTo, lead.reinforceUntil = to, now + 30
        lead.reinforceEnemy = IsValid(enemy) and enemy or nil
        lead.roamGoal, lead.patrolGoal = nil, nil
        for _, m in ipairs(lead.squad and lead.squad.list or { lead }) do
            m.helpUntil = now + 45
            m.woken, m.planAt = true, 0
        end
        lead.redirect = true
    end
    if clone then caller:EmitSound("npc/combine_soldier/vo/on1.wav", 65, 110) end
end
D.CloneCall = D.CallHelp
