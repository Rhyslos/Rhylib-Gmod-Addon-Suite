--[[
    Spread and crosshair recoil, shared by server and client.

    The crosshair is not decoration: it is drawn from exactly these values.
    Every shot lands inside the current crosshair circle, and the arc
    closest to the shot gets kicked outward (see the design plan).

    Recoil patterns: each gun's SWEP.RecoilPattern gives the direction of
    every shot in a spray (Spread.PatternAngle; the shot number is the
    pattern bits of the predicted RecoilB network var (Spread.PatternShot),
    back to 1 after PATTERN_RESET s
    without firing). From the second shot on, the shot lands that way
    inside the cone (a little jitter), so the arc on that side kicks out
    and shows where the spray is going; the first shot from rest goes
    anywhere in the cone as before. cl_50_recoil kicks the view the same way.

    All spread values are cone angles in degrees. State is stored in the
    weapon's predicted network vars, so server and client always agree:
        Recoil (kicks 1-3), RecoilB (bloom, streak, last arc), KickTime, Aiming
    (declared in rhylib_base SWEP:SetupDataTables). The cone sizes come
    from the gun's SWEP.Spread table:
        hip, aim         resting cone (degrees) hip-fire / aiming
        kickMain         kick on the arc nearest the shot (x the streak, up to STREAK_MAX)
        kickSide         kick on the other two arcs
        bloomPerShot     shared bloom added per shot, up to bloomMax
        aimKickMult      kicks and bloom added while aiming are multiplied by this
        aimOffsetMult    every arc offset while aiming is multiplied by this
    Values decay over time, calculated from KickTime, so nothing has to
    be sent while they settle.

    Weapon network vars go to every client that can see the weapon, so a
    shot should change as few as possible: the kicks and the bloom are
    stored in 0.01 and 0.005 degree steps and packed into two Ints.
]]

local Spread = {}
Rhylib.Weapons.Spread = Spread   -- (W.Spread; the functions below are shared)

-- Arc centre directions in screen space (0 = right, 90 = down):
-- 1 = down-left, 2 = top, 3 = down-right.
Spread.ARC_CENTRES = { math.rad(150), math.rad(270), math.rad(30) }

Spread.KICK_TAU = 0.12       -- per-arc kick decay, seconds
Spread.BLOOM_TAU = 0.45      -- shared bloom decay, seconds
Spread.STREAK_WINDOW = 0.6   -- seconds between same-arc shots to keep a streak
Spread.STREAK_MAX = 2   -- (recoil patterns send runs of shots to the same arc)
Spread.REST_TIME = 0.35      -- seconds without firing before the next shot counts as "from rest"
Spread.PATTERN_RESET = 0.45  -- seconds without firing before a spray's recoil pattern starts over
Spread.PATTERN_JITTER = math.rad(22)   -- shots land within this many degrees of the pattern direction
-- Guns without SWEP.RecoilPattern: straight up, then a small wobble.
Spread.DEFAULT_PATTERN = { 270, 270, 270, 260, 280, 255, 285, 260, 280 }

-- Spread.PatternAngle(wep, n): screen angle (radians) of shot n of a spray.
function Spread.PatternAngle(wep, n)
    local p = wep.RecoilPattern or Spread.DEFAULT_PATTERN
    local len = #p
    if len == 0 then return math.rad(270) end
    n = math.max(1, n or 1)
    if n > len then
        local loop = math.Clamp(wep.RecoilPatternLoop or 4, 1, len)
        n = len - loop + 1 + (n - len - 1) % loop
    end
    return math.rad(p[n])
end

-- Spread.PatternShot(wep): the number of the last shot of this spray
-- (RecoilB bits 15-22; 0 = none yet).
function Spread.PatternShot(wep)
    if not wep.GetRecoilB then return 0 end
    return math.floor(wep:GetRecoilB() / 32768) % 256
end

-- Spread.NextPatternShot(wep, t): the number the next shot will have.
function Spread.NextPatternShot(wep, t)
    if not wep.GetKickTime then return 1 end
    if t - wep:GetKickTime() > Spread.PATTERN_RESET then return 1 end
    return math.min(Spread.PatternShot(wep) + 1, 255)
end

-- Packing: Recoil = three kicks, 10 bits each (0.01 degree steps, up to
-- 10.23); RecoilB = bloom 10 bits (0.005 steps, up to 5.115), streak
-- 3 bits, last arc 2 bits, recoil pattern shot number 8 bits.
local BLOOM_STEP, KICK_STEP = 0.005, 0.01
local BLOOM_MAX_Q, KICK_MAX_Q = 1023, 1023

local floor = math.floor
local function q(v, step, maxQ)
    v = floor(v / step + 0.5)
    if v < 0 then return 0 end
    if v > maxQ then return maxQ end
    return v
end

-- Spread.Unpack(wep): raw stored values, not decayed: bloom, kick1, kick2,
-- kick3 (degrees), streak (0-7), last arc (1-3, 0 = none yet).
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

-- Spread.Pack(wep, bloom, k1, k2, k3, streak, arc, pat): writes them back
-- (values are rounded to the steps above and capped; pat = pattern shot
-- number, nil keeps it).
function Spread.Pack(wep, bloom, k1, k2, k3, streak, arc, pat)
    local p = q(k3, KICK_STEP, KICK_MAX_Q)
    p = p * 1024 + q(k2, KICK_STEP, KICK_MAX_Q)
    p = p * 1024 + q(k1, KICK_STEP, KICK_MAX_Q)
    wep:SetRecoil(p)
    pat = math.Clamp(floor(pat or Spread.PatternShot(wep)), 0, 255)
    local r = (pat * 4 + arc) * 8 + math.Clamp(streak, 0, 7)
    wep:SetRecoilB(r * 1024 + q(bloom, BLOOM_STEP, BLOOM_MAX_Q))
end

-- Spread.GetState(wep, t): decayed values at time t (CurTime()): bloom,
-- kick1, kick2, kick3 in degrees. Kicks fade with KICK_TAU, bloom with
-- BLOOM_TAU, both counted from the last shot (KickTime).
function Spread.GetState(wep, t)
    local dt = math.max(0, t - wep:GetKickTime())
    local kd = math.exp(-dt / Spread.KICK_TAU)
    local bd = math.exp(-dt / Spread.BLOOM_TAU)
    local b, k1, k2, k3 = Spread.Unpack(wep)
    return b * bd, k1 * kd, k2 * kd, k3 * kd
end

-- Crouching is more accurate, and the crosshair shows it: weapons crouchSpread, eased in with the eyes going down
-- (the current view offset is predicted, so server, client and crosshair
-- agree and the arcs close smoothly as you duck). Only on the ground.
function Spread.StanceMult(owner)
    if not (IsValid(owner) and owner:IsPlayer() and owner:IsOnGround()) then return 1 end
    local m = Rhylib.Config.Get("weapons", "crouchSpread")
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

-- Spread.SkillMult(wep): multiplier on every cone of this weapon right
-- now: skills (rhylib_skills K.SpreadMult: sprint-firing, Z-6 and pistol
-- handling...) times the crouch bonus above. 1 = no change.
function Spread.SkillMult(wep)
    local owner = wep:GetOwner()
    local m = Spread.StanceMult(owner)
    local K = Rhylib.Skills
    if not (K and K.SpreadMult) then return m end
    return K.SpreadMult(owner, wep) * m
end

-- Spread.BaseCone(wep): resting cone size in degrees (the arc radius):
-- Spread.aim while aiming, else Spread.hip, times SkillMult.
function Spread.BaseCone(wep)
    return (wep:GetAiming() and wep.Spread.aim or wep.Spread.hip) * Spread.SkillMult(wep)
end

-- Spread.Offsets(wep, t): how far each arc has moved outward, in degrees
-- (three numbers). Low stamina (rhylib_stamina S.SpreadPenalty) and hurt
-- arms or burns (rhylib_medical Med.SpreadPenalty) push all three out evenly.
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

-- Spread.MeanCone(wep, t): average cone in degrees, the area shots actually
-- land in (base cone + the mean of the three offsets).
-- Example: local deg = Rhylib.Weapons.Spread.MeanCone(wep, CurTime())
function Spread.MeanCone(wep, t)
    local o1, o2, o3 = Spread.Offsets(wep, t)
    return Spread.BaseCone(wep) + (o1 + o2 + o3) / 3
end

-- Spread.NearestArc(a): 1-3, the arc whose centre is closest to screen
-- angle a (radians, as returned by ShotDirection).
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
    aimAng: the shooter's eye angles. index: a number to vary the random
    seed (0 for a normal shot).
]]
function Spread.ShotDirection(wep, aimAng, index)
    local now = CurTime()
    local cone = Spread.MeanCone(wep, now)
    -- A first shot from rest goes (almost) where the chevron points.
    if now - wep:GetKickTime() > Spread.REST_TIME then
        cone = cone * (Rhylib.Config.Get("weapons", "firstShotMult"))
    end
    -- (the direction follows the recoil pattern, with a little jitter)
    local n = Spread.NextPatternShot(wep, now)
    local a
    if n <= 1 then
        a = util.SharedRandom("rhylib.spread.a", 0, 2 * math.pi, index or 0)   -- (first shot: anywhere in the cone)
    else
        a = Spread.PatternAngle(wep, n)
            + util.SharedRandom("rhylib.spread.a", -Spread.PATTERN_JITTER, Spread.PATTERN_JITTER, index or 0)
    end
    local u = util.SharedRandom("rhylib.spread.r", 0, 1, index or 0)
    -- Centre-weighted (radius = u, not sqrt(u)): most shots land near the
    -- middle, a few reach the edge of the circle.
    local off = math.tan(math.rad(cone) * u * 0.95)

    local dir = aimAng:Forward() + aimAng:Right() * (math.cos(a) * off) - aimAng:Up() * (math.sin(a) * off)
    dir:Normalize()
    return dir, a
end

-- Spread.AddShot(wep, arc, t): record a shot that went toward the given
-- arc (1-3): decay, then add kicks and bloom, and set KickTime = t.
-- Shots at the same arc within STREAK_WINDOW grow the main kick (streak).
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

    local pat = Spread.NextPatternShot(wep, t)   -- (before KickTime moves)
    Spread.Pack(wep,
        math.min(bloom + cfg.bloomPerShot * m, cfg.bloomMax),
        k1 + (arc == 1 and main or side),
        k2 + (arc == 2 and main or side),
        k3 + (arc == 3 and main or side),
        streak, arc, pat)
    wep:SetKickTime(t)
end
