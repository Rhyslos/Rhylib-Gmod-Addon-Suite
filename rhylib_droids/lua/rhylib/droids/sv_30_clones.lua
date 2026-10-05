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
    end)
end

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
                    c.advanceTo = nil
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
        if IsValid(c) and c.leaderSid and c.leaderSid == sid then c:Remove() end
    end
end)
