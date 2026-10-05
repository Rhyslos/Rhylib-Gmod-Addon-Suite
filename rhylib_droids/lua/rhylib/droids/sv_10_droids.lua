--[[
    Droids (server): who can be targeted (one list for every droid,
    rebuilt a few times a second), the active cap, and no droid-on-droid
    damage.
]]

local D = Rhylib.Droids

D.active = D.active or {}   -- [droid] = true
D.commanders = D.commanders or {}   -- [commander droid] = true

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

-- Near a living commander other than itself (checked at most twice a second).
function D.Boosted(droid)
    local now = CurTime()
    if (droid.rhylibBoostAt or 0) > now then return droid.rhylibBoost end
    droid.rhylibBoostAt = now + 0.5
    local boost = false
    if next(D.commanders) then
        local r = D.Cfg("cmdRadius")
        local pos = droid:GetPos()
        for c in pairs(D.commanders) do
            if not IsValid(c) then
                D.commanders[c] = nil
            elseif c ~= droid and c:Health() > 0 and c:GetPos():DistToSqr(pos) < r * r then
                boost = true
                break
            end
        end
    end
    droid.rhylibBoost = boost
    return boost
end

-- A commander was destroyed: droids it was boosting aim worse for a while.
function D.Rattle(cmd)
    local secs = D.Cfg("cmdDeathTime")
    if secs <= 0 then return end
    local r = D.Cfg("cmdRadius")
    local pos = cmd:GetPos()
    for d in pairs(D.active) do
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

-- Droids don't shoot each other to pieces.
Rhylib.Hook.Add("EntityTakeDamage", "droids.friendly", function(ent, dmg)
    if not ent.IsRhylibDroid then return end
    local att = dmg:GetAttacker()
    if IsValid(att) and att.IsRhylibDroid then return true end
end, -200)
