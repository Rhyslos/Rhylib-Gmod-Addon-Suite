--[[
    Droids (server): who can be targeted (one list for every droid,
    rebuilt a few times a second), the active cap, and no droid-on-droid
    damage. Clone NPCs (rhylib_clone, 2026-10-06az) are the other side:
    D.clones, their own cap, targets and friendly-fire rules here too.
]]

local D = Rhylib.Droids

D.active = D.active or {}   -- [droid] = true
D.clones = D.clones or {}   -- [clone NPC] = true
D.commanders = D.commanders or {}   -- [commander droid or clone] = true

function D.CloneCount()
    local n = 0
    for e in pairs(D.clones) do
        if IsValid(e) then n = n + 1 else D.clones[e] = nil end
    end
    return n
end

function D.Count()
    local n = 0
    for e in pairs(D.active) do
        if IsValid(e) then n = n + 1 else D.active[e] = nil end
    end
    return n
end

-- Living players droids may shoot: not noclipping, spectating, downed,
-- eliminated in a simulation or just respawned from one.
local targets, targetsAt = {}, 0
function D.Targets()
    local now = CurTime()
    if now - targetsAt < 0.25 then return targets end
    targetsAt = now
    targets = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP and p:GetObserverMode() == OBS_MODE_NONE
            and not p.rhylibDown and not p:IsFlagSet(FL_NOTARGET)
            and not p:GetNW2Bool("rhylib_simOut", false)   -- (eliminated in training)
            and (p.rhylibSimImmune or 0) <= now   -- (training respawn protection)
            and p:GetNW2Float("rhylib_knockEnd", 0) == 0 then   -- (knocked down: can't be hurt)
            targets[#targets + 1] = p
        end
    end
    return targets
end

-- What droids shoot at: the players above plus living clone NPCs.
local mixed, mixedAt = {}, 0
function D.DroidTargets()
    local now = CurTime()
    if now - mixedAt < 0.25 then return mixed end
    mixedAt = now
    local base = D.Targets()
    if next(D.clones) == nil then
        mixed = base
        return mixed
    end
    mixed = {}
    for i = 1, #base do mixed[i] = base[i] end
    for c in pairs(D.clones) do
        if IsValid(c) and c:Health() > 0 then mixed[#mixed + 1] = c end
    end
    return mixed
end

-- What clones shoot at: living droids (training droids are for players).
local foes, foesAt = {}, 0
function D.CloneTargets()
    local now = CurTime()
    if now - foesAt < 0.25 then return foes end
    foesAt = now
    foes = {}
    for d in pairs(D.active) do
        if IsValid(d) and d:Health() > 0 and not d.Training then foes[#foes + 1] = d end
    end
    return foes
end

-- Worse aim for a while: the aim cone times mult (flash charges, the
-- Heavy Suppression skill). Each multiplier keeps its own timer; the
-- strongest one still running counts.
function D.Suppress(droid, secs, mult)
    if not IsValid(droid) then return end
    droid.rhylibSupp = droid.rhylibSupp or {}
    droid.rhylibSupp[mult] = math.max(droid.rhylibSupp[mult] or 0, CurTime() + secs)
end

function D.SuppressMult(droid)
    local t = droid.rhylibSupp
    if not t then return 1 end
    local now, m = CurTime(), 1
    for mult, ends in pairs(t) do
        if ends > now then
            if mult > m then m = mult end
        else
            t[mult] = nil
        end
    end
    return m
end

-- EOD Signal blackout (rhylib_eod): inside a player's wideband interference
-- device whose owner has the skill. Droids there get no commander boost,
-- react slower, and artillery doesn't fire on targets there.
function D.Blackout(pos)
    local E = Rhylib.EOD
    return E ~= nil and E.InBlackout ~= nil and E.InBlackout(pos) or false
end

-- A droid (not a clone) in a blackout (checked at most twice a second).
function D.BlackedOut(droid)
    if droid.IsRhylibClone then return false end
    local now = CurTime()
    if (droid.rhylibBlackAt or 0) > now then return droid.rhylibBlack end
    droid.rhylibBlackAt = now + 0.5
    droid.rhylibBlack = D.Blackout(droid:WorldSpaceCenter())
    return droid.rhylibBlack
end

-- Near a living commander of its own side other than itself (checked at
-- most twice a second). Clones are also led by players with the
-- Reinforcements skill (rhylib_skills; owner: the player is the commander).
function D.Boosted(droid)
    local now = CurTime()
    if (droid.rhylibBoostAt or 0) > now then return droid.rhylibBoost end
    droid.rhylibBoostAt = now + 0.5
    local boost = false
    local clone = droid.IsRhylibClone == true
    if D.BlackedOut(droid) then
        droid.rhylibBoost = false
        return false
    end
    local r = D.Cfg("cmdRadius")
    local pos = droid:GetPos()
    if next(D.commanders) then
        for c in pairs(D.commanders) do
            if not IsValid(c) then
                D.commanders[c] = nil
            elseif c ~= droid and (c.IsRhylibClone == true) == clone and c:Health() > 0 and c:GetPos():DistToSqr(pos) < r * r
                and not D.BlackedOut(c) then
                boost = true
                break
            end
        end
    end
    local K = Rhylib.Skills
    if not boost and clone and K and K.Has then
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and not p.rhylibDown and p:GetPos():DistToSqr(pos) < r * r and (K.HasReinforcements and K.HasReinforcements(p) or K.Has(p, "reinforcements")) then
                boost = true
                break
            end
        end
    end
    droid.rhylibBoost = boost
    return boost
end

-- A commander was destroyed: the NPCs it was boosting aim worse for a while.
function D.Rattle(cmd)
    local secs = D.Cfg("cmdDeathTime")
    if secs <= 0 then return end
    local r = D.Cfg("cmdRadius")
    local pos = cmd:GetPos()
    for d in pairs(cmd.IsRhylibClone and D.clones or D.active) do
        if IsValid(d) and d ~= cmd and d:GetPos():DistToSqr(pos) < r * r then
            D.Suppress(d, secs, D.Cfg("cmdDeathMult"))
            d.rhylibBoostAt = 0
        end
    end
end

-- Route / cover searches (Path:Compute, hiding spot lookups) share a small
-- budget per tick, so a crowd of droids doesn't search all at once.
local budgetTick, budgetUsed = -1, 0
function D.TakeBudget()
    local t = engine.TickCount()
    if t ~= budgetTick then budgetTick, budgetUsed = t, 0 end
    if budgetUsed >= D.Cfg("pathPerTick") then return false end
    budgetUsed = budgetUsed + 1
    return true
end

-- Cover spots in use: [key] = droid (two droids don't share one).
D.coverTaken = D.coverTaken or {}
function D.SpotKey(v) return math.floor(v.x / 16) .. ":" .. math.floor(v.y / 16) .. ":" .. math.floor(v.z / 16) end

-- Droids don't shoot each other to pieces; clones and players never hurt
-- each other (bolts already fly through friendlies, this covers blasts,
-- bashes and the rest).
Rhylib.Hook.Add("EntityTakeDamage", "droids.friendly", function(ent, dmg)
    local att = dmg:GetAttacker()
    if not IsValid(att) then return end
    if ent.IsRhylibDroid then
        if att.IsRhylibDroid then return true end
    elseif ent.IsRhylibClone then
        if att:IsPlayer() or att.IsRhylibClone then return true end
    elseif att.IsRhylibClone and ent:IsPlayer() then
        return true
    end
end, -200)
