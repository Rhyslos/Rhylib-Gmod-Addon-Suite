--[[
    Clone NPCs (server, 2026-10-06az): squads called by an officer
    (rhylib_skills Reinforcements), medic healing, pulling squads out.

      D.SpawnClone(kind, pos, yaw)         one clone, nil over cloneMax
      D.CallSquad(leader, kinds, life)     spawns them around the leader,
                                           returns how many came
    A called clone follows its officer (mode "follow", leader, followSlot),
    first walks a few steps toward the nearest droid (advanceTo) so it
    draws fire, and is pulled out after `life` seconds (0 = stays) or when
    the officer leaves the server.
]]

local D = Rhylib.Droids

function D.SpawnClone(kind, pos, yaw)
    local class = D.CLASSES[kind]
    local k = D.KINDS[kind]
    if not (class and k and k.side == "republic") then return nil end
    if D.CloneCount() >= D.Cfg("cloneMax") then return nil end
    local e = ents.Create(class)
    if not IsValid(e) then return nil end
    e:SetPos(pos)
    e:SetAngles(Angle(0, yaw or 0, 0))
    e:Spawn()
    e:Activate()
    if not IsValid(e) or e.overCap then return nil end
    return e
end

-- Is a clone-sized body free to stand at p?
local HULL_MIN, HULL_MAX = Vector(-14, -14, 4), Vector(14, 14, 72)
local function free(p)
    if not util.IsInWorld(p + Vector(0, 0, 36)) then return false end
    local tr = util.TraceHull({ start = p, endpos = p, mins = HULL_MIN, maxs = HULL_MAX, mask = MASK_NPCSOLID })
    return not tr.Hit and not tr.StartSolid
end

-- Ground (navmesh first) at or under p, or nil.
local function ground(p)
    if navmesh and navmesh.GetNearestNavArea then
        local area = navmesh.GetNearestNavArea(p, false, 250, false, true)
        if IsValid(area) then return area:GetClosestPointOnArea(p) end
    end
    local tr = util.TraceLine({ start = p + Vector(0, 0, 40), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or nil
end

-- A spot near the leader for the i-th of n (an arc behind them, in sight
-- of them, so nobody appears behind a wall).
local function spotFor(leader, i, n)
    local origin = leader:GetPos()
    local eye = leader:EyePos()
    local yaw = leader:EyeAngles().y
    for try = 1, 8 do
        local a = math.rad(yaw + 180 + (i - (n + 1) / 2) * 45 + math.Rand(-20, 20) * try / 4)
        local r = math.Rand(90, 160) + try * 10
        local p = ground(origin + Vector(math.cos(a) * r, math.sin(a) * r, 0))
        if p and math.abs(p.z - origin.z) < 120 and free(p)
            and not util.TraceLine({ start = eye, endpos = p + Vector(0, 0, 40), mask = MASK_SOLID_BRUSHONLY }).Hit then
            return p
        end
    end
    return nil
end

-- Nearest real droid within reach of pos (distance only).
local function nearestDroid(pos, reach)
    local best, bestD = nil, reach * reach
    for _, d in ipairs(D.CloneTargets()) do
        local dd = IsValid(d) and d:GetPos():DistToSqr(pos) or math.huge
        if dd < bestD then best, bestD = d, dd end
    end
    return best
end

-- Where the slots sit around the officer (forward, right): out to the
-- sides and level with them, not behind (owner: they shot past him from
-- behind), so their line of fire to the front is clear.
local SLOTS = { Vector(20, -130, 0), Vector(20, 130, 0), Vector(-40, -210, 0), Vector(-40, 210, 0),
    Vector(60, -260, 0), Vector(60, 260, 0), Vector(-100, -150, 0), Vector(-100, 150, 0) }

function D.CallSquad(leader, kinds, life)
    if not (IsValid(leader) and istable(kinds)) then return 0 end
    local n = #kinds
    local made = 0
    local target = nearestDroid(leader:GetPos(), 3000)
    for i, kind in ipairs(kinds) do
        local p = spotFor(leader, i, n)
        if p then
            local face = target and (target:GetPos() - p):Angle().y or leader:EyeAngles().y
            local c = D.SpawnClone(kind, p, face)
            if c then
                made = made + 1
                c.leader = leader
                c.leaderSid = leader:SteamID64()
                c:SetNW2Entity("rhylib_lead", leader)   -- (the command wheel counts followers by it)
                c.reinfOf = c.leaderSid   -- (pulled out when this officer leaves)
                c.followSlot = SLOTS[(i - 1) % #SLOTS + 1]
                c.mode = "follow"
                c:SetNW2String("rhylib_dmode", "follow")
                c.recallAt = (life and life > 0) and CurTime() + life or nil
                -- (owner: at least three steps toward the enemy, to draw fire)
                local dir = target and (target:GetPos() - p) or leader:EyeAngles():Forward()
                dir.z = 0
                if dir:LengthSqr() > 1 then
                    dir:Normalize()
                    local to = ground(p + dir * math.Rand(130, 200))
                    if to then
                        c.advanceTo = to
                        c.advanceUntil = CurTime() + 5
                    end
                end
                local fx = EffectData()
                fx:SetOrigin(p)
                util.Effect("ThumperDust", fx, true, true)
            end
        end
    end
    return made
end

--------------------------------------------------------------------------
-- Medics: patients (downed, or dead a short while), afflictions, revives
--------------------------------------------------------------------------

-- Where and when players died (a dead player's entity may be moved by the
-- death camera).
Rhylib.Hook.Add("PlayerDeath", "droids.clones", function(ply)
    local corpse = ply:GetNW2Entity("rhylib_corpse")
    ply.rhylibDeathPos = IsValid(corpse) and corpse:GetPos() or ply:GetPos()
    ply.rhylibDeathAt = CurTime()
end)
Rhylib.Hook.Add("PlayerSpawn", "droids.clones", function(ply) ply.rhylibDeathAt = nil end)

-- Can a medic NPC still get this player up?
function D.PatientPending(p)
    if not IsValid(p) or not p:IsPlayer() then return false end
    if p:Alive() then return p.rhylibDown == true end
    local win = D.Cfg("ctMedicDeadWindow")
    return win > 0 and p.rhylibDeathAt ~= nil and CurTime() - p.rhylibDeathAt < win
        and p:GetObserverMode() ~= OBS_MODE_ROAMING   -- (not spectating somewhere else)
end

-- Where the body is.
function D.BodyPos(p)
    if p:Alive() then
        local L = Rhylib.Lying
        return L and L.BodyPos and L.BodyPos(p) or p:GetPos()
    end
    local corpse = p:GetNW2Entity("rhylib_corpse")
    if IsValid(corpse) then return corpse:GetPos() end
    return p.rhylibDeathPos
end

-- Up again: downed = medical revive; dead = back on their feet where
-- they fell (like the admin !revive), with ctMedicReviveHealth.
function D.NpcRevive(p)
    local frac = D.Cfg("ctMedicReviveHealth")
    local Med = Rhylib.Medical
    if p:Alive() then
        if Med and Med.Revive and p.rhylibDown then
            Med.Revive(p, math.max(1, p:GetMaxHealth() * frac), nil)   -- (no "by": stats are for players)
            D.ReviveShield(p)
        end
        return
    end
    local pos = D.BodyPos(p)
    local ang = p:EyeAngles()
    p:Spawn()
    -- (after the spawn point code's own timer(0), like !revive)
    timer.Simple(0, function()
        if not (IsValid(p) and p:Alive()) then return end
        if pos then
            local spot = pos
            for i = 0, 7 do
                local a = i / 8 * math.pi * 2
                local q = pos + (i == 0 and vector_origin or Vector(math.cos(a) * 40, math.sin(a) * 40, 0))
                if free(q + Vector(0, 0, 4)) then spot = q + Vector(0, 0, 4) break end
            end
            p:SetPos(spot)
        end
        p:SetEyeAngles(Angle(0, ang.y, 0))
        p:SetHealth(math.max(1, math.floor(p:GetMaxHealth() * frac)))
        D.ReviveShield(p)
    end)
end

-- Just got up by a medic NPC (owner: they were killed again at once):
-- reviveShield less damage for reviveShieldTime, to get away. It ends
-- the moment they fire: an escape tool, not a combat bonus.
function D.ReviveShield(p)
    local secs = D.Cfg("reviveShieldTime")
    if secs <= 0 or D.Cfg("reviveShield") <= 0 then return end
    p.rhylibReviveShield = CurTime() + secs
    p:ChatPrint(string.format("A clone medic got you up: %d%% less damage for %d s to get to safety (firing ends it).",
        math.Round(D.Cfg("reviveShield") * 100), secs))
end

Rhylib.Hook.Add("KeyPress", "droids.reviveshield", function(p, key)
    if key == IN_ATTACK and p.rhylibReviveShield then p.rhylibReviveShield = nil end
end)
Rhylib.Hook.Add("PlayerSpawn", "droids.reviveshield", function(p)
    -- (a medic's dead-revive sets it a tick after the spawn)
    p.rhylibReviveShield = nil
end)

-- Less damage: medics crouched on a body, players just got up.
-- (before armour 100 and the medical down hook 150)
Rhylib.Hook.Add("EntityTakeDamage", "droids.shields", function(ent, dmg)
    if ent.IsRhylibClone then
        if ent.crouching and ent.reviveTarget then dmg:ScaleDamage(1 - math.Clamp(D.Cfg("ctMedicShield"), 0, 1)) end
    elseif ent:IsPlayer() and ent.rhylibReviveShield then
        if CurTime() < ent.rhylibReviveShield then
            dmg:ScaleDamage(1 - math.Clamp(D.Cfg("reviveShield"), 0, 1))
        else
            ent.rhylibReviveShield = nil
        end
    end
end, 60)

-- Send free medics to patients (nearest medic per patient).
local function assignMedics(players)
    local r2 = D.Cfg("ctMedicReviveRadius") ^ 2
    local now = CurTime()
    for _, p in ipairs(players) do
        if D.PatientPending(p) and (p.rhylibNoMedicUntil or 0) < now then
            local taken = false
            for c in pairs(D.clones) do
                if IsValid(c) and c.reviveTarget == p then taken = true break end
            end
            if not taken then
                local body = D.BodyPos(p)
                local best, bestD = nil, r2
                if body then
                    for c in pairs(D.clones) do
                        if IsValid(c) and c:Health() > 0 and not c.reviveTarget and c:Kind().medic then
                            local d = c:GetPos():DistToSqr(body)
                            if d < bestD then best, bestD = c, d end
                        end
                    end
                end
                if best then
                    best.reviveTarget = p
                    best.reviveFails = nil
                    best.redirect = true
                    best.woken = true
                end
            end
        end
    end
end

-- Afflictions (rhylib_medical injuries) of a player near a medic: a step
-- a second: stop the worst bleed, else splint a break, else heal damage
-- and burns on every part.
local function treat(p, repair)
    local Med = Rhylib.Medical
    local t = Med and Med.inj and Med.inj[p]
    if not t then return end
    local worst, wl
    for limb, part in pairs(t) do
        if (part.bleed or 0) > 0 and (not worst or part.bleed > worst.bleed) then worst, wl = part, limb end
    end
    if worst then
        worst.bleed, worst.bleedEnd = 0, 0
    else
        local fixed = false
        for _, part in pairs(t) do
            if part.frac and not part.splint then
                part.splint = true
                fixed = true
                break
            end
        end
        if not fixed then
            for _, part in pairs(t) do
                part.dmg = math.max(0, (part.dmg or 0) - repair)
                part.burn = math.max(0, (part.burn or 0) - repair)
            end
        end
    end
    if Med.MarkInjuries then Med.MarkInjuries(p) end
end

-- Medics heal (1 s steps) and squads are pulled out (when their time is
-- up or their officer left).
local function heal(e, amount)
    local max = e:GetMaxHealth()
    if max > 0 and e:Health() < max then e:SetHealth(math.min(max, e:Health() + amount)) end
end

-- Downed players get clone guards (owner: friendly AIs stand over downed
-- friends until a medic gets there): up to ctDownGuards of the nearest
-- free clones within ctDownRadius (not ones on an attack order).
local function assignGuards(players)
    local want = D.Cfg("ctDownGuards")
    if want <= 0 then return end
    local r2 = D.Cfg("ctDownRadius") ^ 2
    for _, p in ipairs(players) do
        if p:Alive() and p.rhylibDown then
            local have = 0
            for c in pairs(D.clones) do
                if IsValid(c) and c.guardDowned == p then have = have + 1 end
            end
            if have < want then
                local pos = p:GetPos()
                local free = {}
                for c in pairs(D.clones) do
                    if IsValid(c) and c:Health() > 0 and not c.guardDowned and c.mode ~= "attack" then
                        local d = c:GetPos():DistToSqr(pos)
                        if d < r2 then free[#free + 1] = { c = c, d = d } end
                    end
                end
                table.sort(free, function(a, b) return a.d < b.d end)
                for i = 1, math.min(want - have, #free) do
                    local c = free[i].c
                    c.guardDowned = p
                    c.guardOldHome = c.home
                    c.guardSide = (have + i) % 2 == 0 and -1 or 1
                    c.advanceTo, c.reinforceTo = nil, nil
                    c.planAt = 0
                    c.woken = true   -- (ends an idle wait)
                    c.redirect = true   -- (ends a walk elsewhere)
                end
            end
        end
    end
end

timer.Create("Rhylib.Droids.Clones", 1, 0, function()
    if next(D.clones) == nil then return end
    local now = CurTime()
    local all = player.GetAll()
    assignGuards(all)
    assignMedics(all)
    local medics
    for c in pairs(D.clones) do
        if not IsValid(c) then
            D.clones[c] = nil
        elseif c.recallAt and now >= c.recallAt then
            c:Remove()
        elseif c:Health() > 0 and c:Kind().medic then
            medics = medics or {}
            medics[#medics + 1] = c
        end
    end
    if not medics then return end
    local amount, r = D.Cfg("ctMedicHeal"), D.Cfg("ctMedicRadius")
    local repair = D.Cfg("ctMedicRepair")
    local r2 = r * r
    for _, m in ipairs(medics) do
        local pos = m:GetPos()
        for _, p in ipairs(all) do
            if p:Alive() and not p.rhylibDown and p:GetPos():DistToSqr(pos) <= r2 then
                if amount > 0 then heal(p, amount) end
                if repair > 0 then treat(p, repair) end
            end
        end
        if amount > 0 then
            for c in pairs(D.clones) do
                if IsValid(c) and c:Health() > 0 and c:GetPos():DistToSqr(pos) <= r2 then heal(c, amount) end
            end
        end
    end
end)

-- An officer leaving takes their squad with them.
Rhylib.Hook.Add("PlayerDisconnected", "droids.clones", function(ply)
    local sid = ply:SteamID64()
    for c in pairs(D.clones) do
        if IsValid(c) and c.reinfOf and c.reinfOf == sid then c:Remove() end
    end
end)

--------------------------------------------------------------------------
-- Spread out, calls for help, odds, presets, follow picks (2026-10-06bd)
--------------------------------------------------------------------------

D.GroundAt = ground

-- b walks beside lead (a roaming pair). When lead dies, b roams alone.
function D.Buddy(b, lead)
    if not (IsValid(b) and IsValid(lead)) then return end
    b.mode = "follow"
    b.leader, b.leaderNpc, b.buddyRoam = lead, true, true
    b.followSlot = Vector(-50, 90, 0)
    b:SetNW2String("rhylib_dmode", "roam")
end

-- A random navmesh spot for roaming: within roamRadius, at least 600 away.
-- (The area list is fetched once per map; empty = no navmesh yet, retried.)
local areas, areasRetry = nil, 0
function D.RoamPoint(from)
    if not (navmesh and navmesh.GetAllNavAreas) then return nil end
    if not areas then
        if CurTime() < areasRetry then return nil end
        areas = navmesh.GetAllNavAreas() or {}
        if #areas == 0 then areas, areasRetry = nil, CurTime() + 10 return nil end
    end
    local r2 = D.Cfg("roamRadius") ^ 2
    -- (nearby areas first: on a big map few of all areas are in range)
    local near = navmesh.Find and navmesh.Find(from, D.Cfg("roamRadius"), 200, 200)
    local pool = (near and #near > 0) and near or areas
    for _ = 1, 16 do
        local a = pool[math.random(#pool)]
        if IsValid(a) and a:GetSizeX() >= 48 and a:GetSizeY() >= 48 and not a:IsUnderwater() then
            local d = a:GetCenter():DistToSqr(from)
            if d < r2 and d > 600 * 600 then return a:GetRandomPoint() end
        end
    end
    return nil
end

-- A clone spotted droids: up to ctCallHelpers idle clones within
-- ctCallRadius come to it (guards/patrols take up the new spot).
function D.CloneCall(caller, enemy)
    local now = CurTime()
    if (caller.callReady or 0) > now then return end
    caller.callReady = now + D.Cfg("ctCallCooldown")
    local from = caller:GetPos()
    local r2 = D.Cfg("ctCallRadius") ^ 2
    local free = {}
    for c in pairs(D.clones) do
        if c ~= caller and IsValid(c) and c:Health() > 0 and not IsValid(c.target) and not c.leader
            and not c.guardDowned and not c.reviveTarget and c.mode ~= "attack" then
            local d = c:GetPos():DistToSqr(from)
            if d < r2 then free[#free + 1] = { c = c, d = d } end
        end
    end
    if #free == 0 then return end
    table.sort(free, function(a, b) return a.d < b.d end)
    for i = 1, math.min(D.Cfg("ctCallHelpers"), #free) do
        local c = free[i].c
        if c.mode == "roam" then
            c.roamGoal, c.roamUntil = from, now + 30
        else
            c.reinforceTo, c.reinforceUntil = from, now + 20
            if c.mode == "guard" or c.mode == "patrol" then c.home = from end
        end
        c.redirect, c.woken, c.planAt = true, true, 0
    end
    caller:EmitSound("npc/combine_soldier/vo/on1.wav", 65, 110)
end

-- The odds around a clone: friends (clones and players) within
-- ctOddsFriends, enemies (B2s count double) within ctOddsEnemies, and
-- where the enemies are (their middle).
function D.CloneOdds(c)
    local pos = c:GetPos()
    local fr2, er2 = D.Cfg("ctOddsFriends") ^ 2, D.Cfg("ctOddsEnemies") ^ 2
    local f, e = 1, 0
    local sum = Vector(0, 0, 0)
    for o in pairs(D.clones) do
        if o ~= c and IsValid(o) and o:Health() > 0 and o:GetPos():DistToSqr(pos) < fr2 then f = f + 1 end
    end
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and not p.rhylibDown and p:GetPos():DistToSqr(pos) < fr2 then f = f + 1 end
    end
    for _, d in ipairs(D.CloneTargets()) do
        if IsValid(d) then
            local dp = d:GetPos()
            if dp:DistToSqr(pos) < er2 then
                local w = d:Kind().big and 2 or 1
                e = e + w
                sum:Add(dp * w)
            end
        end
    end
    return f, e, e > 0 and sum / e or nil
end

-- Preset squads: rows from the front (where you aim) back toward you.
-- Each entry: { kinds..., width = n }. "defend" makes the first kinds
-- named follow (guard) the given kind (mortar squad).
local PRESETS = {
    clone_squad = { side = 1, rows = {
        { "ct_trooper", "ct_rifleman", "ct_heavy", "ct_rifleman", "ct_trooper" },
        { "ct_medic", "ct_commander", "ct_medic" } } },
    clone_company = { side = 1, rows = {
        { "ct_trooper", "ct_rifleman", "ct_trooper", "ct_rifleman", "ct_trooper", "ct_rifleman" },
        { "ct_rifleman", "ct_trooper", "ct_heavy", "ct_heavy", "ct_trooper", "ct_rifleman" },
        { "ct_trooper", "ct_rifleman", "ct_trooper", "ct_rifleman", "ct_trooper", "ct_rifleman" },
        { "ct_medic", "ct_medic", "ct_commander", "ct_medic" } } },
    droid_small = { rows = {
        { "b1", "b1", "b1", "b1", "b1" }, { "b1", "b1", "b1", "b1", "b1" } } },
    droid_medium = { rows = {
        { "b1", "b1", "b1", "b1", "b1" }, { "b1", "b1", "b1", "b1", "b1" },
        { "b2", "b2", "b2", "b1_commander", "b2", "b2" } } },
    droid_large = { rows = {
        { "b1", "b1", "b1", "b1", "b1", "b1", "b1" }, { "b1", "b1", "b1", "b1", "b1", "b1", "b1" },
        { "b1", "b1", "b1", "b1", "b1", "b1" },
        { "b2", "b2", "b2_rocket", "b1_commander", "b2_rocket", "b2", "b2" },
        { "b2", "b2", "b2_rocket", "b2" } } },
    droid_b2 = { rows = { { "b2", "b2", "b2", "b2" }, { "b2", "b2", "b2", "b2" } } },
    droid_mortar = { rows = { { "b1", "b1", "b1" }, { "b1", "b1", "b1" }, { "b2_cannon", "b1_commander", "b2_cannon" } },
        defend = "b2_cannon" },
}
D.PRESETS = PRESETS

-- Returns the spawned list and how many the preset has.
function D.SpawnPreset(name, origin, yaw, mode)
    local pr = PRESETS[name]
    if not pr then return {}, 0 end
    local ang = Angle(0, yaw, 0)
    local fwd, right = ang:Forward(), ang:Right()
    local want, made = 0, {}
    local guards, wards = {}, {}
    for r, row in ipairs(pr.rows) do
        local w = #row
        for c, kind in ipairs(row) do
            want = want + 1
            local clone = D.KINDS[kind] and D.KINDS[kind].side == "republic"
            local room = clone and D.CloneCount() < D.Cfg("cloneMax") or not clone and D.Count() < D.Cfg("maxActive")
            local p = origin - fwd * ((r - 1) * 85) + right * ((c - (w + 1) / 2) * 75)
            local g = ground(p) or p
            if room and free(g + Vector(0, 0, 4)) then
                local e = ents.Create(D.CLASSES[kind] or "")
                if IsValid(e) then
                    e:SetPos(g + Vector(0, 0, 4))
                    e:SetAngles(Angle(0, yaw, 0))
                    e:Spawn()
                    e:Activate()
                    if IsValid(e) and not e.overCap then
                        made[#made + 1] = e
                        if D.ToolPlaced then D.ToolPlaced(e, mode) end
                        if pr.defend then
                            if kind == pr.defend then wards[#wards + 1] = e else guards[#guards + 1] = e end
                        end
                    end
                end
            end
        end
    end
    -- Mortar squad: the mortars are artillery (long range, mostly rockets),
    -- the rest stay with them (owner: defend them).
    for _, m in ipairs(wards) do
        m.artillery = true
        -- (they stay where they're set up, whatever marker or tool mode)
        D.SetMode(m, "guard", m:GetPos())
    end
    if #wards > 0 then
        for i, g in ipairs(guards) do
            local m = wards[(i - 1) % #wards + 1]
            g.mode = "follow"
            g.leader, g.leaderNpc = m, true
            g.followSlot = SLOTS[(i - 1) % #SLOTS + 1] * 0.8 + Vector(120, 0, 0)   -- (in front of and beside it)
            g:SetNW2String("rhylib_dmode", "follow")
        end
    end
    return made, want
end

-- Follow tool: LMB picks (a clone aimed at, else every clone near the
-- spot); RMB hands them to a player. Picks show as NW2Entity rhylib_pickBy.
function D.ToggleFollowPick(ply, tr)
    ply.rhylibPicks = ply.rhylibPicks or {}
    local picks = ply.rhylibPicks
    local e = tr.Entity
    if IsValid(e) and e.IsRhylibClone then
        if picks[e] then
            picks[e] = nil
            e:SetNW2Entity("rhylib_pickBy", NULL)
        else
            picks[e] = true
            e:SetNW2Entity("rhylib_pickBy", ply)
        end
    else
        local r2 = D.Cfg("brushRadius") ^ 2
        for c in pairs(D.clones) do
            local by = IsValid(c) and c:GetNW2Entity("rhylib_pickBy")
            if IsValid(c) and c:Health() > 0 and c:GetPos():DistToSqr(tr.HitPos) < r2
                and not (IsValid(by) and by ~= ply) then   -- (not another player's pick)
                picks[c] = true
                c:SetNW2Entity("rhylib_pickBy", ply)
            end
        end
    end
    local n = 0
    for c in pairs(picks) do
        if IsValid(c) then n = n + 1 else picks[c] = nil end
    end
    return n
end

function D.AssignFollow(ply, target)
    local picks = ply.rhylibPicks
    if not picks or not IsValid(target) then return 0 end
    local i = 0
    for c in pairs(picks) do
        if IsValid(c) and c:Health() > 0 then
            i = i + 1
            D.SetMode(c, "guard", c:GetPos())
            c.mode = "follow"
            c.leader, c.leaderSid, c.leaderNpc, c.buddyRoam = target, target:SteamID64(), nil, nil
            c.reinfOf, c.recallAt = nil, nil   -- (handed over: stays until killed or re-ordered)
            c.followSlot = SLOTS[(i - 1) % #SLOTS + 1]
            c:SetNW2String("rhylib_dmode", "follow")
            c:SetNW2Entity("rhylib_lead", target)
            c.planAt, c.woken, c.redirect = 0, true, true
            c:SetNW2Entity("rhylib_pickBy", NULL)
        end
    end
    ply.rhylibPicks = nil
    return i
end

-- Artillery spotting: an enemy some droid (not training) saw in the last
-- 3 s, within range of the mortar and not too close; nearest first.
function D.SpottedTarget(mortar, range)
    local pos = mortar:GetPos()
    local r2, min2 = range * range, D.Cfg("b2RocketMin") ^ 2
    local now = CurTime()
    local ok = {}   -- (only what droids may target now: no noclip, knocked down, ...)
    for _, t in ipairs(D.DroidTargets()) do ok[t] = true end
    local best, bestD
    for d in pairs(D.active) do
        if IsValid(d) and not d.Training and d:Health() > 0 then
            local t = d.target
            if IsValid(t) and ok[t] and now - (d.lastSeenAt or 0) < 3 and not t.rhylibDown and (t:IsPlayer() and t:Alive() or not t:IsPlayer() and t:Health() > 0) then
                local dist = t:GetPos():DistToSqr(pos)
                if dist < r2 and dist > min2 and (not bestD or dist < bestD) then best, bestD = t, dist end
            end
        end
    end
    return best
end

--------------------------------------------------------------------------
-- Command wheel (2026-10-06be, owner): a commander's own squad of clones
--------------------------------------------------------------------------

D.SQUAD_OPS = { "follow", "hold", "move", "aggroUp", "aggroDown", "dismiss", "regroup" }

-- Clones following this player.
function D.Followers(ply)
    local out = {}
    for c in pairs(D.clones) do
        if IsValid(c) and c:Health() > 0 and c.leader == ply and not c.leaderNpc then out[#out + 1] = c end
    end
    return out
end

-- Give the order; returns a line for the commander.
function D.SquadOrder(ply, op)
    local list = D.Followers(ply)
    local level = ply.rhylibSquadAggro or 3
    if op == "follow" or op == "regroup" then
        -- Regroup on me, and (follow) take in free clones nearby (up to the
        -- cap). Regroup: only the clones already following.
        local cap = D.Cfg("cmdMaxFollowers")
        local r2 = D.Cfg("cmdFollowRadius") ^ 2
        local pos = ply:GetPos()
        local free = {}
        for c in pairs(D.clones) do
            if IsValid(c) and c:Health() > 0 and not c.leader and not c.guardDowned and not c.reviveTarget and c.mode ~= "roam" then   -- (roam pairs: given an order)
                local d = c:GetPos():DistToSqr(pos)
                if d < r2 then free[#free + 1] = { c = c, d = d } end
            end
        end
        table.sort(free, function(a, b) return a.d < b.d end)
        if op == "follow" then
            for i = 1, math.min(#free, cap - #list) do list[#list + 1] = free[i].c end
        end
        if #list == 0 then return op == "follow" and "No clones nearby to follow you" or "No clones are following you" end
        for i, c in ipairs(list) do
            if c.leader ~= ply then
                D.SetMode(c, "guard", c:GetPos())
                c.mode = "follow"
                c.leader, c.leaderSid = ply, ply:SteamID64()
                c:SetNW2String("rhylib_dmode", "follow")
                c:SetNW2Entity("rhylib_lead", ply)
            end
            c.holdAt = nil
            c.followSlot = SLOTS[(i - 1) % #SLOTS + 1]
            c.orderAggro = level ~= 3 and level or nil
            c.planAt, c.woken, c.redirect = 0, true, true
        end
        return string.format("%d clone%s: %s", #list, #list == 1 and "" or "s", op == "follow" and "follow me" or "regroup on me")
    end
    if #list == 0 then return "No clones are following you" end
    if op == "hold" or op == "move" then
        local spot = ply:GetPos()
        if op == "move" then
            local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 6000, filter = ply, mask = MASK_SOLID_BRUSHONLY })
            spot = (tr.Hit and not tr.HitSky) and ground(tr.HitPos) or nil
            if not spot then return "No ground to move to there" end
        end
        for i, c in ipairs(list) do
            local p = c:GetPos()
            if op == "move" then
                local a = (i / #list) * math.pi * 2
                p = ground(spot + Vector(math.cos(a), math.sin(a), 0) * (60 + #list * 10)) or spot
            end
            c.holdAt = p
            c.advanceTo, c.reinforceTo = nil, nil
            c.planAt, c.woken, c.redirect = 0, true, true
        end
        return op == "hold" and "Hold this position" or "Move up there and hold"
    end
    if op == "aggroUp" or op == "aggroDown" then
        level = math.Clamp(level + (op == "aggroUp" and 1 or -1), 1, 5)
        ply.rhylibSquadAggro = level
        ply:SetNW2Int("rhylib_squadAggro", level)
        for _, c in ipairs(list) do
            c.orderAggro = level ~= 3 and level or nil
            c.doctrine, c.planAt = nil, 0
        end
        return "Aggression: " .. (D.SQUAD_AGGRO_NAMES[level] or level)
    end
    if op == "dismiss" then
        for _, c in ipairs(list) do D.SetMode(c, "guard", c:GetPos()) end
        return "Dismissed: they hold where they are"
    end
end
