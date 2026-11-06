--[[
    Stealth (shared): the settings (Server settings > NPCs > Droids &
    clones > Stealth), the state codes clients see, and the pure maths of
    the detection meter (D.StealthMath; no GMod calls, so it can be tested
    offline).

    Stealth is opt-in: every droid is "alert" (sees as it always did)
    unless a GM sets it, or its squad, to "unaware" (the toolgun's
    Alertness when placing, Command mode's order wheel, or the
    stealthDefault setting). Clones never use it. stealthOn off = every
    droid behaves as alert whatever it is set to.

    An unaware droid notices players with a meter (0-1) per player (at
    most 3): it fills faster close up and in its central view, slower in
    the corner of its eye, not at all behind it; slower when you are
    crouched, still, partly hidden, in foliage, in fog or a sandstorm;
    faster when you sprint or have helmet lights on. At stealthSuspect it
    gets suspicious (stops, turns, walks over slowly: "?" over it), at 1
    it is alerted and fights as usual. Losing sight while suspicious it
    searches the spot for stealthSearchTime, then goes back to unaware.
    Shots, blasts, being shot, stun hits and a mate killed close by
    startle or alert it. An alerted droid radios its squad and calls help
    only after stealthAlarmDelay seconds alive ("!" over it).

    NW2Int rhylib_sstate on droids (D.SSTATE): 0 alert / normal, 1 unaware,
    2 suspicious, 3 searching, 4 radioing the alarm. NW2Float rhylib_salert:
    when it was last alerted out of stealth (the brief "!").

    Distances are in units (about 52 units to the metre).
]]

local D = Rhylib.Droids
local Config = Rhylib.Config
-- (a meta table of its own for each key: Config.Meta writes into it)
local function reg(k, v, desc, meta)
    Config.Register("droids", k, v, desc, { section = "Stealth" })
    if meta then Config.Meta("droids", k, meta) end
end

reg("stealthOn", true, "Stealth is available: droids a GM sets to Unaware use the detection meter. Off = every droid behaves as Alert (sees you at once, all round) whatever it is set to")
reg("stealthDefault", "alert", "Alertness of new droids: alert (sees you at once, as always) or unaware (stealth: has to notice you first). The toolgun's Alertness choice and Command mode beat it",
    { options = { { "alert", "Alert" }, { "unaware", "Unaware (stealth)" } } })
reg("stealthHud", "meter", "What players see while unaware droids notice them: meter (one bar under the crosshair), arcs (a mark round the crosshair toward each droid noticing you, up to 3) or none",
    { options = { { "meter", "Meter" }, { "arcs", "Arcs" }, { "none", "None" } } })
reg("stealthFov", 90, "Unaware droids: central view cone (degrees) where they notice at full rate")
reg("stealthFovWide", 150, "Unaware droids: whole view cone (degrees); outside the central cone they notice at stealthPeriph; behind it they don't see at all")
reg("stealthPeriph", 0.3, "Unaware droids: noticing rate in the corner of the eye (outside the central cone)")
reg("stealthNear", 420, "Unaware droids: closer than this (units, 420 = 8 m) the meter fills at stealthRateNear")
reg("stealthMid", 1580, "Unaware droids: at this distance (units, 1580 = 30 m) the meter fills at stealthRateMid")
reg("stealthRateNear", 2.0, "Unaware droids: meter filled per second up close (2 = full in half a second)")
reg("stealthRateMid", 0.5, "Unaware droids: meter filled per second at stealthMid")
reg("stealthRateFar", 0.25, "Unaware droids: meter filled per second at the edge of their sight range")
reg("stealthDrain", 0.15, "Unaware droids: meter lost per second while they don't see you")
reg("stealthVis2", 0.6, "Two of three body points visible (head, chest, knees): noticing rate multiplier")
reg("stealthVis1", 0.3, "One of three body points visible: noticing rate multiplier")
reg("stealthCrouch", 0.5, "Crouched (or lying): noticing rate multiplier")
reg("stealthStill", 0.6, "Standing still: noticing rate multiplier")
reg("stealthSprint", 1.6, "Sprinting: noticing rate multiplier")
reg("stealthBushCrouch", 0.25, "Inside foliage, crouched: noticing rate multiplier (sprinting cancels it)")
reg("stealthBushStand", 0.6, "Inside foliage, standing: noticing rate multiplier (sprinting cancels it)")
reg("stealthBushBetween", 0.5, "Foliage between the droid and you: noticing rate multiplier")
reg("stealthFog", 0.4, "Mist or fog (rhylib_weather): noticing rate multiplier at full intensity")
reg("stealthSand", 0.5, "Sandstorm or heavy snow (rhylib_weather): noticing rate multiplier at full intensity")
reg("stealthStorm", 0.7, "Heavy storm (rhylib_weather): noticing rate multiplier at full intensity")
reg("stealthLights", 2, "Helmet lights on (rhylib_gear): noticing rate multiplier")
reg("stealthLightsRange", 2, "Helmet lights on: sight range multiplier for unaware droids")
reg("stealthNight", 1, "Night: noticing rate multiplier for every unaware droid (a game master's dial: 0.5 = half as fast)")
reg("stealthSuspect", 0.5, "Meter at which an unaware droid gets suspicious (stops, turns and walks over slowly; 0.01-1)", { min = 0.01, max = 1, step = 0.05 })
reg("stealthLoseTime", 3, "Seconds a suspicious droid goes without seeing you before it searches the spot")
reg("stealthSearchTime", 20, "Seconds a droid searches the last spot before it goes back to unaware")
reg("stealthSearchMult", 2, "Searching droids: noticing rate multiplier (they alert fast)")
reg("stealthSlow", 0.6, "Suspicious droids: walking speed multiplier while they walk over to look")
reg("stealthTraces", 120, "Most sight traces all unaware droids use in one tick (spreads the cost; the rest look next time)")
reg("stealthHearShot", 2100, "Blaster shots this close (units, 2100 = 40 m) startle unaware droids: they turn and are alerted after their reaction time")
reg("stealthHearBlast", 3150, "Explosions this close (units, 3150 = 60 m) startle unaware droids")
reg("stealthHearStun", 315, "Stun shots and baton hits this close (units, 315 = 6 m) make unaware droids suspicious")
reg("stealthStepSprint", 420, "Sprinting this close (units, 420 = 8 m) adds stealthStepSprintAdd to the meter once a second, seen or not")
reg("stealthStepSprintAdd", 0.3, "Meter added by sprinting close by (once a second)")
reg("stealthStepWalk", 160, "Walking this close (units, 160 = 3 m) adds stealthStepWalkAdd to the meter once a second, seen or not")
reg("stealthStepWalkAdd", 0.1, "Meter added by walking close by (once a second)")
reg("stealthBody", 525, "A droid destroyed this close (units, 525 = 10 m) and seen by an unaware droid makes it suspicious")
reg("stealthAlarmDelay", 3, "Seconds an alerted droid (that was unaware) radios before its squad and nearby groups are called; destroyed before then = no call")
reg("stealthFoliageMap", true, "Read the map's foliage props (bushes, trees, ferns...) from the map file at map start")
reg("stealthFoliageProps", true, "Spawned props with a foliage model count as foliage too")
reg("stealthFoliage", { "bush=48", "shrub=48", "hedge=64", "fern=40", "foliage=56", "undergrowth=56", "plant=36", "tree=64", "pine=64", "palm=56",
    "leaf=40", "leaves=40", "ivy=40", "vine=36", "reed=32", "cattail=32", "grass=32", "flower=28" },
    "Foliage models: word=radius pairs; a model whose file name has the word counts as foliage of that radius (units), first match wins; a change reads the map and spawned props again")
reg("stealthFoliageSkip", { "street", "treasure", "pottery" }, "Foliage models: file names with any of these words never count (\"street\" has \"tree\" in it)")

-- !alarm / !alarm off and !foliage (game masters and up).
Rhylib.Perms.Register("rhylib.droids.alarm", "admin", "Droids: raise or stand down the alarm for unaware (stealth) droids, see the foliage count")

-- State codes on the wire (NW2Int rhylib_sstate).
D.SSTATE = { alert = 0, unaware = 1, suspicious = 2, searching = 3, radio = 4 }
D.SSTATE_NAMES = { [0] = "Alert", "Unaware", "Suspicious", "Searching", "Raising the alarm" }

--------------------------------------------------------------------------
-- D.StealthMath: pure functions (c = a config getter, c(key) -> value)
--------------------------------------------------------------------------

D.StealthMath = D.StealthMath or {}
local M = D.StealthMath

-- M.BaseRate(d, range, near, mid, rNear, rMid, rFar) -> meter per second
-- at distance d: rNear up to near, down to rMid at mid, down to rFar at
-- range (straight lines in between).
function M.BaseRate(d, range, near, mid, rNear, rMid, rFar)
    if d <= near then return rNear end
    if d <= mid then
        local f = (d - near) / math.max(mid - near, 1)
        return rNear + (rMid - rNear) * f
    end
    local f = (d - mid) / math.max(range - mid, 1)
    if f > 1 then f = 1 end
    return rMid + (rFar - rMid) * f
end

-- M.VisMult(hits, c) -> multiplier for 0-3 visible body points.
function M.VisMult(hits, c)
    if hits >= 3 then return 1 end
    if hits == 2 then return c("stealthVis2") end
    if hits == 1 then return c("stealthVis1") end
    return 0
end

-- M.Rate(c, d, range, o) -> meter per second. o (reused by the caller):
-- vis 0-3, periph, crouch, move (0 still, 1 walk, 2 sprint), inside,
-- between, weather (multiplier), lights, searching.
function M.Rate(c, d, range, o)
    local r = M.VisMult(o.vis or 0, c)
    if r <= 0 then return 0 end
    r = r * M.BaseRate(d, range, c("stealthNear"), c("stealthMid"), c("stealthRateNear"), c("stealthRateMid"), c("stealthRateFar"))
    if o.periph then r = r * c("stealthPeriph") end
    if o.crouch then r = r * c("stealthCrouch") end
    if o.move == 0 then r = r * c("stealthStill") elseif o.move == 2 then r = r * c("stealthSprint") end
    -- (inside foliage counts unless sprinting; else foliage in the way)
    if o.inside and o.move ~= 2 then
        r = r * c(o.crouch and "stealthBushCrouch" or "stealthBushStand")
    elseif o.between then
        r = r * c("stealthBushBetween")
    end
    r = r * (o.weather or 1)
    if o.lights then r = r * c("stealthLights") end
    r = r * c("stealthNight")
    if o.searching then r = r * c("stealthSearchMult") end
    return r
end

-- M.WeatherMult(kind, intensity, c) -> multiplier for rhylib_weather's
-- kind (mist/fog: stealthFog, sandstorms and heavy snow: stealthSand,
-- heavy storm: stealthStorm), eased in by intensity (0.1-1).
function M.WeatherMult(kind, intensity, c)
    local full
    if kind == "mist" or kind == "fog" then full = c("stealthFog")
    elseif kind == "sandstorm" or kind == "heavysandstorm" or kind == "heavysnow" then full = c("stealthSand")
    elseif kind == "heavystorm" then full = c("stealthStorm")
    else return 1 end
    local i = math.min(math.max(tonumber(intensity) or 1, 0), 1)
    return 1 + (full - 1) * i
end

-- M.Step(v, rate, dt, drain, seen) -> the meter after dt seconds (0-1).
function M.Step(v, rate, dt, drain, seen)
    if seen then v = v + rate * dt else v = v - drain * dt end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- M.Advance(st, top, seen, now, suspectAt, loseTime, searchTime) -> what
-- changed: "alert", "suspicious", "searching", "unaware" or nil. st holds
-- state ("unaware" / "suspicious" / "searching"), lostAt, searchUntil
-- and is updated (except on "alert": the caller ends stealth). top = the
-- highest meter, seen = the droid saw (or heard) that one this look.
function M.Advance(st, top, seen, now, suspectAt, loseTime, searchTime)
    if top >= 1 then return "alert" end
    local s = st.state
    if s == "unaware" then
        if top >= suspectAt then
            st.state, st.lostAt = "suspicious", now
            return "suspicious"
        end
    elseif s == "suspicious" then
        if seen then
            st.lostAt = now
        elseif now - (st.lostAt or now) > loseTime then
            st.state, st.searchUntil = "searching", now + searchTime
            return "searching"
        end
    elseif s == "searching" then
        if seen then
            if (st.searchUntil or 0) < now + 5 then st.searchUntil = now + 5 end
        elseif now >= (st.searchUntil or 0) then
            st.state = "unaware"
            return "unaware"
        end
    end
    return nil
end
