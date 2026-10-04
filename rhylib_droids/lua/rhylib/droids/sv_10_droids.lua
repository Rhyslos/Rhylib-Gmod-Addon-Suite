--[[
    Droids (server): who can be targeted (one list for every droid,
    rebuilt a few times a second), the active cap, and no droid-on-droid
    damage.
]]

local D = Rhylib.Droids

D.active = D.active or {}   -- [droid] = true

function D.Count()
    local n = 0
    for e in pairs(D.active) do
        if IsValid(e) then n = n + 1 else D.active[e] = nil end
    end
    return n
end

-- Living players droids may shoot: not noclipping, spectating, downed or
-- eliminated in a simulation.
local targets, targetsAt = {}, 0
function D.Targets()
    local now = CurTime()
    if now - targetsAt < 0.25 then return targets end
    targetsAt = now
    targets = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP and p:GetObserverMode() == OBS_MODE_NONE
            and not p.rhylibDown and not p:IsFlagSet(FL_NOTARGET)
            and not p:GetNW2Bool("rhylib_simOut", false) then   -- (eliminated in training)
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

-- Droids don't shoot each other to pieces.
Rhylib.Hook.Add("EntityTakeDamage", "droids.friendly", function(ent, dmg)
    if not ent.IsRhylibDroid then return end
    local att = dmg:GetAttacker()
    if IsValid(att) and att.IsRhylibDroid then return true end
end, -200)
