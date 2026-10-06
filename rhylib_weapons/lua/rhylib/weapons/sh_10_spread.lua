--[[
    Spread and crosshair recoil, shared by server and client.

    The crosshair is not decoration: it is drawn from exactly these values.
    Every shot lands inside the current crosshair circle, and the arc
    closest to the shot gets kicked outward (see the design plan).

    All spread values are cone angles in degrees. State is stored in the
    weapon's predicted network vars, so server and client always agree:
        Recoil (kicks 1-3), RecoilB (bloom, streak, last arc), KickTime, Aiming
    Values decay over time, calculated from KickTime, so nothing has to
    be sent while they settle.

    Weapon network vars go to every client that can see the weapon, so a
    shot should change as few as possible: the kicks and the bloom are
    stored in 0.01 and 0.005 degree steps and packed into two Ints.
]]

local Spread = {}
Rhylib.Weapons.Spread = Spread

-- Arc centre directions in screen space (0 = right, 90 = down):
-- 1 = down-left, 2 = top, 3 = down-right.
Spread.ARC_CENTRES = { math.rad(150), math.rad(270), math.rad(30) }

Spread.KICK_TAU = 0.12       -- per-arc kick decay, seconds
Spread.BLOOM_TAU = 0.45      -- shared bloom decay, seconds
Spread.STREAK_WINDOW = 0.6   -- seconds between same-arc shots to keep a streak
Spread.STREAK_MAX = 4
Spread.REST_TIME = 0.35      -- seconds without firing before the next shot counts as "from rest"

-- Packing: Recoil = three kicks, 10 bits each (0.01 degree steps, up to
-- 10.23); RecoilB = bloom 10 bits (0.005 steps, up to 5.115), streak
-- 3 bits, last arc 2 bits.
local BLOOM_STEP, KICK_STEP = 0.005, 0.01
local BLOOM_MAX_Q, KICK_MAX_Q = 1023, 1023

local floor = math.floor
local function q(v, step, maxQ)
    v = floor(v / step + 0.5)
    if v < 0 then return 0 end
    if v > maxQ then return maxQ end
    return v
end

-- Raw stored values: bloom, kick1, kick2, kick3, streak, last arc.
function Spread.Unpack(wep)
    local p = wep:GetRecoil()
    local k1 = p % 1024 p = floor(p / 1024)
    local k2 = p % 1024
    local k3 = floor(p / 1024) % 1024
    local r = wep:GetRecoilB()
    local b = r % 1024 r = floor(r / 1024)
    local streak = r % 8
    local arc = floor(r / 8) % 4
    return b * BLOOM_STEP, k1 * KICK_STEP, k2 * KICK_STEP, k3 * KICK_STEP, streak, arc
end

function Spread.Pack(wep, bloom, k1, k2, k3, streak, arc)
    local p = q(k3, KICK_STEP, KICK_MAX_Q)
    p = p * 1024 + q(k2, KICK_STEP, KICK_MAX_Q)
    p = p * 1024 + q(k1, KICK_STEP, KICK_MAX_Q)
    wep:SetRecoil(p)
    local r = arc * 8 + math.Clamp(streak, 0, 7)
    wep:SetRecoilB(r * 1024 + q(bloom, BLOOM_STEP, BLOOM_MAX_Q))
end

-- Decayed values at time t: bloom, kick1, kick2, kick3.
function Spread.GetState(wep, t)
    local dt = math.max(0, t - wep:GetKickTime())
    local kd = math.exp(-dt / Spread.KICK_TAU)
    local bd = math.exp(-dt / Spread.BLOOM_TAU)
    local b, k1, k2, k3 = Spread.Unpack(wep)
    return b * bd, k1 * kd, k2 * kd, k3 * kd
end

-- Crouching (2026-10-07, owner: show on the crosshair that crouching is
-- more accurate): weapons crouchSpread, eased in with the eyes going down
-- (the current view offset is predicted, so server, client and crosshair
-- agree and the arcs close smoothly as you duck). Only on the ground.
function Spread.StanceMult(owner)
    if not (IsValid(owner) and owner:IsPlayer() and owner:IsOnGround()) then return 1 end
    local m = Rhylib.Config.Get("weapons", "crouchSpread") or 1
    if m == 1 then return 1 end
    local stand, duck = owner:GetViewOffset().z, owner:GetViewOffsetDucked().z
    local f
    if stand - duck > 1 and owner.GetCurrentViewOffset then
        f = math.Clamp((stand - owner:GetCurrentViewOffset().z) / (stand - duck), 0, 1)
    else
        f = owner:Crouching() and 1 or 0
    end
    return 1 + (m - 1) * f
end

-- Skills (rhylib_skills): sprint-firing, Z-6 and pistol handling; and the
-- crouch bonus above.
function Spread.SkillMult(wep)
    local owner = wep:GetOwner()
    local m = Spread.StanceMult(owner)
    local K = Rhylib.Skills
    if not (K and K.SpreadMult) then return m end
    return K.SpreadMult(owner, wep) * m
end

-- Resting cone size (the arc radius).
function Spread.BaseCone(wep)
    return (wep:GetAiming() and wep.Spread.aim or wep.Spread.hip) * Spread.SkillMult(wep)
end

-- How far each arc has moved outward, in degrees. Low stamina (with
-- rhylib_stamina) pushes all three arcs out evenly.
function Spread.Offsets(wep, t)
    local bloom, k1, k2, k3 = Spread.GetState(wep, t)
    local m = (wep:GetAiming() and wep.Spread.aimOffsetMult or 1) * Spread.SkillMult(wep)
    local tired = 0
    local S = Rhylib.Stamina
    local owner = wep:GetOwner()
    if S and IsValid(owner) and owner:IsPlayer() then
        tired = S.SpreadPenalty(owner, Spread.BaseCone(wep))
    end
    -- Hurt arms and burns (rhylib_medical).
    local Med = Rhylib.Medical
    if Med and Med.SpreadPenalty and IsValid(owner) and owner:IsPlayer() then
        tired = tired + Med.SpreadPenalty(owner, Spread.BaseCone(wep))
    end
    return (bloom + k1) * m + tired, (bloom + k2) * m + tired, (bloom + k3) * m + tired
end

-- Average cone: the area shots actually land in.
function Spread.MeanCone(wep, t)
    local o1, o2, o3 = Spread.Offsets(wep, t)
    return Spread.BaseCone(wep) + (o1 + o2 + o3) / 3
end

function Spread.NearestArc(a)
    local best, bestD = 1, math.huge
    for i = 1, 3 do
        local d = math.abs(math.NormalizeAngle(math.deg(a - Spread.ARC_CENTRES[i])))
        if d < bestD then
            best, bestD = i, d
        end
    end
    return best
end

--[[
    Direction for one shot. Uses util.SharedRandom, which is seeded from the
    player's command, so the server and the shooter's client pick the same
    direction without sending anything.
    Returns the direction and the screen angle the shot went to.
]]
function Spread.ShotDirection(wep, aimAng, index)
    local now = CurTime()
    local cone = Spread.MeanCone(wep, now)
    -- A first shot from rest goes (almost) where the chevron points.
    if now - wep:GetKickTime() > Spread.REST_TIME then
        cone = cone * (Rhylib.Config.Get("weapons", "firstShotMult") or 1)
    end
    local a = util.SharedRandom("rhylib.spread.a", 0, 2 * math.pi, index or 0)
    local u = util.SharedRandom("rhylib.spread.r", 0, 1, index or 0)
    -- Centre-weighted (radius = u, not sqrt(u)): most shots land near the
    -- middle, a few reach the edge of the circle.
    local off = math.tan(math.rad(cone) * u * 0.95)

    local dir = aimAng:Forward() + aimAng:Right() * (math.cos(a) * off) - aimAng:Up() * (math.sin(a) * off)
    dir:Normalize()
    return dir, a
end

-- Record a shot that went toward the given arc: decay, then add kicks.
function Spread.AddShot(wep, arc, t)
    local cfg = wep.Spread
    local bloom, k1, k2, k3 = Spread.GetState(wep, t)

    local _, _, _, _, lastStreak, lastArc = Spread.Unpack(wep)
    local streak = 1
    if arc == lastArc and t - wep:GetKickTime() < Spread.STREAK_WINDOW then
        streak = math.min(lastStreak + 1, Spread.STREAK_MAX)
    end

    local m = wep:GetAiming() and cfg.aimKickMult or 1
    local main, side = cfg.kickMain * streak * m, cfg.kickSide * m

    Spread.Pack(wep,
        math.min(bloom + cfg.bloomPerShot * m, cfg.bloomMax),
        k1 + (arc == 1 and main or side),
        k2 + (arc == 2 and main or side),
        k3 + (arc == 3 and main or side),
        streak, arc)
    wep:SetKickTime(t)
end
