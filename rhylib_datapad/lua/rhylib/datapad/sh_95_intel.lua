--[[
    Intel datapads (shared): a game master places one (toolgun Base, or
    the spawn menu) and writes its intel (E with the toolgun out:
    title, text, who may read it once cracked). Field technicians (any
    Field technician skill, rhylib_skills spec "eod") crack it: three
    signal locks in a row, easy, moderate, hard. Two knobs (frequency,
    amplitude) match a drifting signal to a target band, then Space
    locks it: inside the band the round passes, outside it the crack
    starts over at round 1 after intelFailWait. A lock only counts
    intelMinLock seconds or more into a round. Then the intel shows.

    D.IntelRound(r) -> { drift, band, jumps } read from config.
    The signal of a round comes from a seed the server picks, so client
    and server work out the same thing:
      D.IntelSignal(seed, r) -> sg { tf, ta (target), kf, ka (knobs at
                                the start), drift, band, ... }
      D.IntelDrift(sg, t)    -> df, da at t seconds into the round
      D.IntelLive(sg, t, kf, ka) -> the live frequency and amplitude
      D.IntelError(sg, lf, la)   -> mean gap between the two waves
      D.IntelInBand(sg, t, kf, ka) -> inside the band?, error
    D.INTEL_NEXT_WAIT: seconds between a locked round and the next.
    D.IntelMinLock(): seconds into a round before Space locks.
    D.IntelReachable(sg, t, kf, ka): could the knobs have got from
      their start to kf / ka in t seconds (D.INTEL_TURN_F / _A per
      second, loose enough for a fast mouse drag)?
    D.IsFieldTech(ply). Permission rhylib.datapad.intel (write intel;
    admin by default).
    Server: sv_95_intel.lua. Client: cl_95_intel.lua.
]]

local D = Rhylib.Datapad
local Config = Rhylib.Config

local S = { section = "Intel datapads" }
Config.Register("datapad", "intelRange", 120, "Intel datapads: how close you must stand to open or crack one (units)", S)
Config.Register("datapad", "intelTitleMax", 60, "Intel datapads: longest title (characters)", S)
Config.Register("datapad", "intelTextMax", 2000, "Intel datapads: longest intel text (characters)", S)
Config.Register("datapad", "intelDrift", { 0.25, 0.4, 0.5 }, "Intel datapads: how hard the signal drifts in rounds 1, 2 and 3", S)
Config.Register("datapad", "intelBand", { 0.17, 0.13, 0.1 }, "Intel datapads: how wide the target band is in rounds 1, 2 and 3 (smaller = harder)", S)
Config.Register("datapad", "intelFailWait", 2, "Intel datapads: seconds after a lock outside the band before signal 1 starts again (0-10)", S)
Config.Register("datapad", "intelMinLock", 1.5, "Intel datapads: seconds into each signal before Space locks it (0-10; earlier presses do nothing)", S)

Rhylib.Perms.Register("rhylib.datapad.intel", "admin", "Write and reset intel datapads")

-- D.IntelRound(r) -> { drift, band, jumps } for round 1-3.
function D.IntelRound(r)
    local function at(k, def) local t = D.Cfg(k) return istable(t) and tonumber(t[r]) or def end
    return {
        drift = math.Clamp(at("intelDrift", 0.4), 0, 3),
        band = math.Clamp(at("intelBand", 0.12), 0.02, 0.6),
        jumps = r >= 3,
    }
end
D.INTEL_ROUND_NAMES = { "EASY", "MODERATE", "HARD" }
D.INTEL_NEXT_WAIT = 1.5
D.INTEL_TURN_F, D.INTEL_TURN_A = 3, 1   -- (knob turn per second the server accepts; the keys turn 1.1 / 0.35)

function D.IntelMinLock() return math.Clamp(tonumber(D.Cfg("intelMinLock")) or 1.5, 0, 10) end

function D.IntelReachable(sg, t, kf, ka)
    return math.abs(kf - sg.kf) <= 0.2 + D.INTEL_TURN_F * t and math.abs(ka - sg.ka) <= 0.1 + D.INTEL_TURN_A * t
end

local F_MIN, F_MAX, A_MIN, A_MAX = 1, 4, 0.25, 1
local SAMPLES = 96
local JUMPS = 160   -- (round 3: jumps every 3-6 s, so over 8 minutes of them)

-- A seeded generator (Park-Miller, exact in doubles: the same numbers on
-- client and server). rnd(lo, hi) -> a number in [lo, hi].
local function gen(seed)
    local st = (math.floor(tonumber(seed) or 1) % 2147483646) + 1
    return function(lo, hi)
        st = (st * 16807) % 2147483647
        return lo + (hi - lo) * ((st - 1) / 2147483646)
    end
end

function D.IntelSignal(seed, r)
    local cfg = D.IntelRound(r)
    local rnd = gen(seed)
    local sg = { round = r, drift = cfg.drift, band = cfg.band }
    sg.tf = rnd(F_MIN + 0.4, F_MAX - 0.4)
    sg.ta = rnd(0.5, 0.8)
    local sf = rnd(0, 1) < 0.5 and -1 or 1
    sg.kf = math.Clamp(sg.tf + sf * rnd(0.8, 1.4), F_MIN, F_MAX)
    local sa = rnd(0, 1) < 0.5 and -1 or 1
    sg.ka = math.Clamp(sg.ta + sa * rnd(0.2, 0.35), A_MIN, A_MAX)
    local p = {}
    for i = 1, 8 do p[i] = rnd(0, 6.2832) end
    sg.p = p
    if cfg.jumps then
        local jt, jf, ja = {}, {}, {}
        local t = 0
        for i = 1, JUMPS do
            t = t + rnd(3, 6)
            jt[i] = t
            local a = rnd(0, 1) < 0.5 and -1 or 1
            jf[i] = a * rnd(0.25, 0.45)
            local b = rnd(0, 1) < 0.5 and -1 or 1
            ja[i] = b * rnd(0.05, 0.12)
        end
        sg.jt, sg.jf, sg.ja = jt, jf, ja
    end
    return sg
end

-- Drift of frequency and amplitude t seconds into the round (added to
-- the knobs): two quick waves, a slow wander, and in round 3 sudden
-- jumps that fade out over a few seconds.
function D.IntelDrift(sg, t)
    local d, p = sg.drift, sg.p
    local sin = math.sin
    local df = d * (0.6 * sin(t * 0.7 + p[1]) + 0.4 * sin(t * 1.9 + p[2]))
        + d * 0.35 * (sin(t * 0.23 + p[5]) + sin(t * 0.41 + p[6]))
    local da = d * 0.3 * (0.6 * sin(t * 0.9 + p[3]) + 0.4 * sin(t * 2.3 + p[4]))
        + d * 0.15 * (sin(t * 0.29 + p[7]) + sin(t * 0.47 + p[8]))
    local jt = sg.jt
    if jt then
        local jf, ja = 0, 0
        for i = 1, #jt do
            local age = t - jt[i]
            if age < 0 then break end
            if age < 20 then
                local k = math.exp(-0.5 * age)
                jf = jf + sg.jf[i] * k
                ja = ja + sg.ja[i] * k
            end
        end
        df = df + math.Clamp(jf, -0.45, 0.45)
        da = da + math.Clamp(ja, -0.12, 0.12)
    end
    return math.Clamp(df, -1, 1), math.Clamp(da, -0.25, 0.25)
end

function D.IntelLive(sg, t, kf, ka)
    local df, da = D.IntelDrift(sg, t)
    return math.Clamp(kf + df, 0.5, 5), math.Clamp(ka + da, 0.05, 1.3)
end

function D.IntelError(sg, lf, la)
    local sum, tf, ta = 0, sg.tf, sg.ta
    for i = 0, SAMPLES - 1 do
        local x = i / (SAMPLES - 1)
        sum = sum + math.abs(la * math.sin(6.2832 * lf * x) - ta * math.sin(6.2832 * tf * x))
    end
    return sum / SAMPLES
end

function D.IntelInBand(sg, t, kf, ka)
    local err = D.IntelError(sg, D.IntelLive(sg, t, kf, ka))
    return err < sg.band, err
end

-- D.IsFieldTech(ply): any Field technician skill. False without rhylib_skills.
function D.IsFieldTech(ply)
    local K = Rhylib.Skills
    if not (K and K.NODES and K.Has and IsValid(ply)) then return false end
    for _, n in ipairs(K.NODES) do
        if n.spec == "eod" and K.Has(ply, n.id) then return true end
    end
    return false
end
