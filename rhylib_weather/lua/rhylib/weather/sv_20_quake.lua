--[[
    Earthquake (server): a game master event for the whole map, started
    with !weather earthquake [1-3] [seconds] (sh_00_config.lua) or
    W.Quake. It runs alongside the weather and doesn't change it.

    W.Quake(level 1-3, secs) -> true, secs  or  false, why. One at a time.
    No secs: a random time from the level's range (quakeTimeLight /
    quakeTimeStrong / quakeTimeViolent: light ones short, violent long).
    Never shorter than 3 s or longer than 16 s, whatever is asked.
    Net weather.quake (server -> everyone, once): UInt 2 level, UInt 7
    seconds, Float start (CurTime). Each client shakes its own screen,
    plays the rumble and drops ceiling dust (cl_40_quake.lua); nothing is
    sent while it runs. A player who joins during one gets it too: their
    game asks once it's ready (net weather.quakereq, client -> server,
    empty, rate 1/s).

    Loose props (setting quakeProps): every 0.5 s, unfrozen prop_physics
    near players (500 units, the players taken in turns) get a small
    random shove and spin that follows the quake's build-up and fade, at
    most 40 props a tick in all. Frozen props (placements), permanent
    props (Rhylib.Perma, frozen or not), breakable and explosive ones (any
    with health) and ones already moving fast are left alone. Nobody is
    hurt or knocked over: from the start of a quake until 4 s after it
    ends, crush damage from any physics prop and blasts set off by a prop
    (a barrel knocked over, not one a player shot) are blocked
    (EntityTakeDamage "weather.quake", W.quakeSafeUntil).
]]

local W = Rhylib.Weather

Rhylib.Net.Register("weather.quake")

-- (a client that has just finished loading asks; sent if one is going)
Rhylib.Net.Receive("weather.quakereq", function(ply)
    local q = W.quake
    if IsValid(ply) and q and CurTime() < q.start + q.secs then
        Rhylib.Net.Start("weather.quake")
        net.WriteUInt(q.level, 2)
        net.WriteUInt(q.secs, 7)
        net.WriteFloat(q.start)
        net.Send(ply)
    end
end, { rate = 1, burst = 2 })

W.quake = W.quake or nil   -- { level, start, secs }

local function send(q, to)
    Rhylib.Net.Start("weather.quake")
    net.WriteUInt(q.level, 2)
    net.WriteUInt(q.secs, 7)
    net.WriteFloat(q.start)
    if to then net.Send(to) else net.Broadcast() end
end

function W.Quake(level, secs)
    local now = CurTime()
    if W.quake and now < W.quake.start + W.quake.secs then return false, "An earthquake is already going" end
    level = math.Clamp(math.floor(tonumber(level) or 2), 1, 3)
    if not tonumber(secs) then
        -- (a random time from the level's range)
        local r = W.Cfg(({ "quakeTimeLight", "quakeTimeStrong", "quakeTimeViolent" })[level])
        local lo = istable(r) and tonumber(r[1]) or 10
        local hi = istable(r) and tonumber(r[2]) or lo
        if hi < lo then lo, hi = hi, lo end
        secs = math.random(math.floor(lo), math.floor(hi))
    end
    -- (never longer than 16 s: a long shake makes people feel sick)
    secs = math.Clamp(math.floor(tonumber(secs)), 3, 16)
    local q = { level = level, start = now, secs = secs }
    W.quake = q
    W.quakeSafeUntil = now + secs + 4   -- (props still landing after it ends hurt nobody)
    send(q)
    return true, secs
end


-- Loose props rattling.
local PUSH = { 0, 35, 70, 110 }   -- (shove per unit of mass, by level)
local done = {}
local first = 1   -- (the player to start from: everyone's props get a turn)
timer.Create("Rhylib.Weather.Quake", 0.5, 0, function()
    local q = W.quake
    if not q then return end
    local now = CurTime()
    if now > q.start + q.secs then W.quake = nil return end
    if not W.Cfg("quakeProps") then return end
    local env = W.QuakeEnvelope(q, now)
    if env < 0.05 then return end
    for k in pairs(done) do done[k] = nil end
    local n = 0
    local push = PUSH[q.level + 1] * env
    local plys = player.GetAll()
    local np = #plys
    if np == 0 then return end
    first = (first % np) + 1
    for i = 0, np - 1 do
        if n >= 40 then break end
        local p = plys[(first + i - 1) % np + 1]
        if p:Alive() then
            for _, e in ipairs(ents.FindInSphere(p:GetPos(), 500)) do
                if n >= 40 then break end
                local P = Rhylib.Perma
                if not done[e] and (e:GetClass() == "prop_physics" or e:GetClass() == "prop_physics_multiplayer")
                    and not (P and P.Is and P.Is(e)) then
                    done[e] = true
                    local phys = e:GetPhysicsObject()
                    if IsValid(phys) and phys:IsMotionEnabled() and not e:IsPlayerHolding()
                        and e:Health() <= 0 and phys:GetVelocity():LengthSqr() < 150 * 150 then
                        n = n + 1
                        e.rhylibQuakeAt = now
                        local m = math.min(phys:GetMass(), 250)
                        phys:Wake()
                        phys:ApplyForceCenter(Vector(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(0.2, 0.6)) * m * push)
                        phys:AddAngleVelocity(VectorRand() * 40 * env * q.level)
                    end
                end
            end
        end
    end
end)

-- (props hurt nobody during a quake and for 4 s after: crush damage from
-- any physics prop, and a blast a prop set off itself, like a barrel
-- knocked off a shelf; a barrel a player shot still counts as theirs)
local function isProp(e)
    if not IsValid(e) then return false end
    local c = e:GetClass()
    return c == "prop_physics" or c == "prop_physics_multiplayer"
end
Rhylib.Hook.Add("EntityTakeDamage", "weather.quake", function(target, dmg)
    if CurTime() > (W.quakeSafeUntil or 0) then return end
    local inf, att = dmg:GetInflictor(), dmg:GetAttacker()
    if (isProp(inf) or isProp(att)) and (dmg:IsDamageType(DMG_CRUSH) or (dmg:IsExplosionDamage() and not (IsValid(att) and att:IsPlayer()))) then
        return true
    end
end)
