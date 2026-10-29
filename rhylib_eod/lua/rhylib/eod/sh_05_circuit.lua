--[[
    The bomb circuit model (shared, pure): rolling a bomb, building its
    board and state, the rules for cutting, shorting and jumpering, and
    what the probe reads. No entities, net messages, timers or CurTime:
    time comes in as `now`, randomness as `rnd` (a function that behaves
    like math.random: rnd() -> 0..1, rnd(n) -> 1..n, rnd(a, b) -> a..b;
    default math.random). sv_10_bomb.lua wraps these for real bombs and
    tools/tests/eod_circuit_test.lua runs them offline.

    Rule functions change the state table and return an outcome:
      { lines = { { text, bad }, ... }, boom = cause or nil, timerEnd = n or nil }
    lines are the window log lines in order (sent before a boom), boom an
    E.CAUSES key (the caller detonates), timerEnd a new timer end the
    caller must also publish (tamper loop). An empty outcome = nothing
    happened (refused quietly).

    How a bomb works:
      features f   C.Roll(kind) or a builder (GM custom / training) picks
                   what the bomb has: det, battery, antiJam, motion, lid,
                   sensor, charge, hop, mods, timerSecs.
      parts        C.BuildBoard(f) places boxes on a 760 x 420 board. Each
                   part has an id ("bat", "cap", "det", ...); parts with
                   term = true get + and − terminals for jumpers.
      wires        { k = kind, a = part id, b = part id, [armoured],
                   [sealed] }. The kind (supply, feed, det, ...) is the
                   wire's job; players never see it, only its colour and
                   the probe's reading (C.Reading).
      state st     C.Build(f, now): cut[i], drained[part], capacitor time,
                   timer, heat, and one sub-table per module.
      done         cutting the detonator line ("det") while it reads DEAD
                   sets st.safe; C.ReadyDone then also waits for the gas
                   valve and the stabiliser.

    Power: "powered" = any supply wire not cut (and its battery not
    shorted) OR a capacitor still at 5% or more. The capacitor starts to
    drain (capDrain seconds) only once every supply is gone.

    Roll odds live in E.ROLL (below), next to E.TIERS (sh_00_config).
]]

local E = Rhylib.EOD
E.Circuit = E.Circuit or {}
local C = E.Circuit

-- What a random bomb gets (C.Roll). Per size: chance of each feature,
-- weights for battery and charge. A module that fits the tier's budget
-- is taken with modChance.
E.ROLL = {
    small = {
        remote = 0.5, antiJam = 0.2, motion = 0.5, sensitive = 0, lid = 0.4, sensor = 0.2, hop = 0,
        battery = { single = 40, capacitor = 30, collapse = 30 },
        charge = { he = 70, gas = 20, virus = 10 },
    },
    large = {
        remote = 0.6, antiJam = 0.4, motion = 0.7, sensitive = 0.5, lid = 0.5, sensor = 0.3, hop = 0.3,
        battery = { dual = 30, capacitor = 25, collapse = 25, single = 20 },
        charge = { he = 80, gas = 10, virus = 10 },
    },
    modChance = 0.75,
    tamperSmall = 0.5,   -- small bombs with a timer get a tamper loop this often (others always, simplified never)
}

local function R(rnd) return rnd or math.random end

local function chance(rnd, p) return rnd() < p end

-- Weighted pick: { key = weight, ... } -> a key.
local function pickW(rnd, o)
    local t = 0
    for _, v in pairs(o) do t = t + v end
    local x = rnd() * t
    for k, v in pairs(o) do
        x = x - v
        if x < 0 then return k end
    end
    return next(o)
end

local function copy(t)
    if table.Copy then return table.Copy(t) end
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end

-- C.Shuffle(list, rnd) -> a shuffled copy (the list itself is left alone).
function C.Shuffle(t, rnd)
    rnd = R(rnd)
    t = copy(t)
    for i = #t, 2, -1 do
        local j = rnd(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end
local shuffle = C.Shuffle

--------------------------------------------------------------------------
-- Rolling and building
--------------------------------------------------------------------------

-- C.Roll(kind, rnd) -> f: a random feature table for "simple" / "small" /
-- "large". Fields:
--   type       "simple" | "small" | "large" (callers may change it to
--              "custom" / "training" afterwards)
--   det        "timer" | "remote"
--   antiJam    bool (remote only)       motion   nil | "normal" | "sensitive"
--   lid        bool (lid switch)        battery  "single" | "dual" | "capacitor" | "collapse"
--   sensor     bool (self-powered charge: own cell + sensor)
--   charge     "he" | "gas" | "virus"   hop      bool (frequency hopping, large remote only)
--   mods       { [module id] = true }   timerSecs (optional; builders set it)
-- Simplified bombs are fixed: timer, lid switch, single battery, HE.
function C.Roll(kind, rnd)
    rnd = R(rnd)
    if kind == "simple" then
        return { type = "simple", det = "timer", antiJam = false, motion = nil, lid = true, battery = "single",
            sensor = false, charge = "he", hop = false, mods = {} }
    end
    local large = kind == "large"
    local o = large and E.ROLL.large or E.ROLL.small
    -- (the order of random draws below is the same as it always was, so a
    -- seeded random gives the same bomb)
    local det = chance(rnd, o.remote) and "remote" or "timer"
    local f = {
        type = large and "large" or "small", det = det,
        antiJam = det == "remote" and chance(rnd, o.antiJam),
        motion = chance(rnd, o.motion) and (large and chance(rnd, o.sensitive) and "sensitive" or "normal") or nil,
        lid = chance(rnd, o.lid),
        battery = pickW(rnd, o.battery),
        sensor = chance(rnd, o.sensor),
        charge = pickW(rnd, o.charge),
        hop = large and det == "remote" and chance(rnd, o.hop),
        mods = {},
    }
    -- Modules within the tier's budget: points = ranks, and a cap on how many.
    -- (modules in random order; each one that fits is taken modChance of the time)
    local t = E.TIERS[f.type]
    local left, n = t.budget, 0
    for _, m in ipairs(shuffle(E.MODS, rnd)) do
        if n >= t.max then break end
        if not (m.remote and det ~= "remote") and m.rank <= left and chance(rnd, E.ROLL.modChance) then
            f.mods[m.id] = true
            left = left - m.rank
            n = n + 1
        end
    end
    return f
end

-- C.BuildBoard(f, rnd) -> parts, wires.
-- parts (list, in this order: the client and net eod.act refer to a part
-- by its index here); wires (list; the index is the wire number in
-- eod.act / eod.read, so at most 31 wires: 5 bits).
--
-- Part ids:  bat / batB (batteries), cap (capacitor), col (collapse
-- circuit), aj (anti-jam), rx (receiver), tmr (timer), det (detonator),
-- chip (logic chip), relay + load (signal relay + dummy load), ant
-- (antenna), chg (charge), cell (charge cell of a self-powered charge).
-- Three columns: L (power), M (detonator side), R (antenna and charge).
--
-- Wire kinds (w.k) and what they join:
--   supply   bat/batB -> cap, else tmr, else det   battery power
--   feed     cap -> tmr or det                     capacitor output
--   tmrline  tmr -> det                            timer to detonator
--   collapse col -> bat                            collapse sense (LOOP 3V)
--   antenna  ant -> rx                             armoured with a relay
--   ajmon    aj -> rx                              anti-jam monitor (MON)
--   relay    rx -> relay, trig relay -> det        armoured (relay module)
--   sense    bat -> chg                            self-powered charge sensor
--   det      det -> chg                            the detonator line (sealed
--                                                  with the sealed module)
--   logic    chip -> det                           logic chip line
--   tamper   tmr -> chg                            tamper loop (LOOP 5V)
--   decoy    a pair not already wired              does nothing (1, or 2 on
--                                                  large/custom)
-- A new wire kind needs: a W(...) line here, a branch in C.Reading (what
-- the probe says), a branch in C.Cut (what cutting it does), a name in
-- cl_20_gm KIND_NAMES, and a row in the manual's probe table.
function C.BuildBoard(f, rnd)
    rnd = R(rnd)
    local P, parts = {}, {}
    -- add(id, label, sub-label, x, y, w, h, term): term = has + / − terminals
    local function add(id, label, sub, x, y, w, h, term)
        local p = { id = id, label = label, sub = sub, x = x, y = y, w = w, h = h, term = term or nil }
        parts[#parts + 1] = p
        P[id] = p
    end
    local L, M, Rc = 20, 310, 590
    add("bat", f.battery == "dual" and "Battery A" or "Battery", "9V cell", L, 20, 130, 62, true)
    if f.battery == "dual" then add("batB", "Battery B", "9V cell", L, 100, 130, 62, true) end
    if f.battery == "capacitor" then add("cap", "Capacitor", "C-40", L, 180, 130, 62, true) end
    if f.battery == "collapse" then add("col", "Collapse", "circuit", L, 260, 130, 56) end
    if f.antiJam then add("aj", "Anti-jam", "module", L, 334, 130, 56) end
    if f.det == "remote" then add("rx", "Receiver", "RX-9", M, 20, 140, 58) end
    if f.det == "timer" then add("tmr", "Timer", "", M, 100, 140, 62) end
    add("det", "Detonator", "", M, 190, 140, 84, true)
    if f.mods.chip then add("chip", "Logic chip", "LED", M, 300, 140, 70) end
    local relay = f.mods.relay and f.det == "remote"
    if relay then
        add("relay", "Relay", "armoured", M, 100, 140, 62, true)
        add("load", "Dummy load", "", 458, 112, 126, 56, true)
    end
    if f.det == "remote" then add("ant", "Antenna", "", Rc, 20, 150, 48) end
    local sub = (f.charge == "gas" and "gas canister") or (f.charge == "virus" and "bio canister") or "HE block"
    add("chg", "Charge", f.sensor and (sub .. " · cell") or sub, Rc, 96, 150, 300)
    if f.sensor then add("cell", "Charge cell", "+ sensor", Rc + 12, 316, 126, 64, true) end

    local wires = {}
    -- W(kind, from part, to part, extra fields such as armoured / sealed)
    local function W(k, a, b, extra)
        local w = { k = k, a = a, b = b }
        if extra then for kk, vv in pairs(extra) do w[kk] = vv end end
        wires[#wires + 1] = w
    end
    local nxt = P.cap and "cap" or P.tmr and "tmr" or "det"
    W("supply", "bat", nxt)
    if P.batB then W("supply", "batB", nxt) end
    if P.cap then W("feed", "cap", P.tmr and "tmr" or "det") end
    if P.tmr then W("tmrline", "tmr", "det") end
    if P.col then W("collapse", "col", "bat") end
    if P.ant then W("antenna", "ant", "rx", relay and { armoured = true } or nil) end
    if P.aj then W("ajmon", "aj", "rx") end
    if relay then
        W("relay", "rx", "relay", { armoured = true })
        W("trig", "relay", "det", { armoured = true })
    end
    if f.sensor then W("sense", "bat", "chg") end
    W("det", "det", "chg", f.mods.sealed and { sealed = true } or nil)
    if P.chip then W("logic", "chip", "det") end
    -- (tamper loop: never on simplified, tamperSmall of the small bombs, always otherwise)
    if P.tmr and f.type ~= "simple" and (f.type ~= "small" or chance(rnd, E.ROLL.tamperSmall)) then W("tamper", "tmr", "chg") end
    -- decoys: pairs of parts that exist and aren't wired yet
    local cand = {}
    for _, c in ipairs({ { "bat", "chg" }, { "rx", "chg" }, { "tmr", "chg" }, { "col", "chg" }, { "aj", "chg" }, { "chip", "chg" }, { "cap", "chg" }, { "batB", "det" } }) do
        local dup = false
        for _, w in ipairs(wires) do if w.a == c[1] and w.b == c[2] then dup = true end end
        if P[c[1]] and P[c[2]] and not dup then cand[#cand + 1] = c end
    end
    local nd = (f.type == "large" or f.type == "custom") and 2 or 1
    for i, c in ipairs(shuffle(cand, rnd)) do
        if i > nd then break end
        W("decoy", c[1], c[2])
    end
    if not relay then f.mods.relay = nil end   -- (a relay asked for on a timer bomb is dropped)
    return parts, wires
end

-- Tilt switch drift: three sines (slow, medium, fast) with random
-- amplitude, speed and phase. See E.TiltPos in sh_00_config.
-- (rand(a, b) = a + (b - a) * rnd(), exactly GMod's math.Rand)
function C.SineSet(amp, rnd)
    rnd = R(rnd)
    local function rand(a, b) return a + (b - a) * rnd() end
    local s = { a = {}, w = {}, p = {} }
    local base, periods = { 0.3, 0.2, 0.12 }, { { 7, 13 }, { 4, 8 }, { 2.5, 4.5 } }
    for i = 1, 3 do
        s.a[i] = base[i] * amp * rand(0.85, 1.15)
        s.w[i] = 2 * math.pi / rand(periods[i][1], periods[i][2])
        s.p[i] = rand(0, 2 * math.pi)
    end
    return s
end

-- C.Build(f, now, rnd) -> st: a fresh state for features f. Main fields:
--   f, type, kindName, big, mods, parts, wires, colors[i] (E.COLOURS index per wire)
--   freq (MHz, 2405-2475), hopAt     viewers { [ply] = true } (window open)
--   inspected, open, lidReleased     cut[i], drained[partId], jumps, jumpers left
--   antiJam / collapse / sensor      start from f; cutting MON / LOOP 3V or
--                                    shorting the charge cell turns them off
--   remoteDead, relayed              receiver can't fire the bomb any more
--   timerSecs, timerEnd, timerLeft, timerWaiting, timerStopped
--   capAt, capZero                   capacitor drain start / shorted empty
--   safe, gasSealed, done, over      detonator cut / valve sealed / finished / gone off
--   heat, heatAt                     thermal heat (cools heatCool per second)
-- Module state (nil when the bomb doesn't have the module):
--   sealedOpen, sealedP (0-1)        sealed plate (always open without the module)
--   tilt  { x, y = sine sets, nx, ny = nudges, mult, t0, pausedAt }
--   chip  { code = E.CHIP_CODES row, ok }
--   liquid { band (green band start), period, ph, drained }
--   fake  { removed, xrays, order (mount numbers in cut order), n, cut[3], cols[3] }
--   stab  { dose (0.75-5.0 ml in 0.25 steps), done }
-- A new module adds its own sub-table here, guarded by f.mods.<id>.
function C.Build(f, now, rnd)
    rnd = R(rnd)
    now = now or 0
    local parts, wires = C.BuildBoard(f, rnd)
    local t = E.TIERS[f.type] or E.TIERS.small
    local all = {}
    for i = 1, #E.COLOURS do all[i] = i end
    local cols = shuffle(all, rnd)
    -- (fields in the same order as always: the constructor draws random
    -- numbers left to right)
    local st = {
        f = f, type = f.type, kindName = t.name, big = t.big, mods = f.mods, parts = parts, wires = wires,
        colors = {}, freq = 2405 + rnd(0, 70), hopAt = now + E.Cfg("hopEvery"),
        viewers = {},
        inspected = false, open = false, lidReleased = false,
        cut = {}, drained = {}, jumps = {}, jumpers = E.Cfg("jumpers"),
        antiJam = f.antiJam and true or false, collapse = f.battery == "collapse", sensor = f.sensor and true or false,
        remoteDead = f.det ~= "remote", relayed = false,
        timerSecs = f.det == "timer" and (f.timerSecs or (f.type == "simple" and 150 or t.big and 240 or 180)) or nil,
        timerWaiting = f.det == "timer",
        safe = false, gasSealed = false, done = false, over = false, recovered = false,
        heat = 0, heatAt = now, sealedOpen = not f.mods.sealed, sealedP = 0,
        tilt = f.mods.tilt and { x = C.SineSet(1, rnd), y = C.SineSet(1, rnd), nx = 0, ny = 0, mult = t.big and 1 or 0.85 } or nil,
        chip = f.mods.chip and { code = rnd(#E.CHIP_CODES), ok = false } or nil,
        liquid = f.mods.liquid and { band = 15 + rnd() * 60, period = 3.5 + rnd() * 3, ph = rnd() * 6.283, drained = false } or nil,
        fake = f.mods.fake and { removed = false, xrays = E.Cfg("xrays"), order = shuffle({ 1, 2, 3 }, rnd), n = 0, cut = { false, false, false }, cols = {} } or nil,
        stab = f.mods.stab and { dose = 0.75 + rnd(0, 17) * 0.25, done = false } or nil,
    }
    for i = 1, #wires do st.colors[i] = cols[(i - 1) % #cols + 1] end
    if st.fake then
        local c2 = shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 }, rnd)
        st.fake.cols = { c2[1], c2[2], c2[3] }
    end
    return st
end

--------------------------------------------------------------------------
-- Circuit state
--------------------------------------------------------------------------

-- C.AnySupply(st) -> bool: a supply wire not cut whose battery wasn't shorted.
function C.AnySupply(st)
    for i, w in ipairs(st.wires) do
        if w.k == "supply" and not st.cut[i] and not st.drained[w.a] then return true end
    end
    return false
end
local anySupply = C.AnySupply

-- C.CapNow(st, now) -> 0-100: capacitor charge. 100 until the supply is
-- gone (capAt), then a straight line down to 0 over capDrain seconds; 0
-- once shorted (capZero) or with no capacitor.
function C.CapNow(st, now)
    if st.f.battery ~= "capacitor" or st.capZero then return 0 end
    if not st.capAt then return 100 end
    return math.max(0, 100 - (now - st.capAt) * 100 / math.max(1, E.Cfg("capDrain")))
end
local capNow = C.CapNow

-- C.Powered(st, now): a battery, or the capacitor at 5% or more.
function C.Powered(st, now) return anySupply(st) or capNow(st, now) >= 5 end
local powered = C.Powered

-- C.HeatNow(st, now): heat at heatAt minus cooling since.
function C.HeatNow(st, now) return math.max(0, st.heat - (now - st.heatAt) * E.Cfg("heatCool")) end

-- C.AddHeat(st, n, now, always) -> true when the board went past 100.
-- Only bombs with the thermal fuse heat up, unless always (the torch).
function C.AddHeat(st, n, now, always)
    if not (st.mods.fuse or always) then return false end
    st.heat = C.HeatNow(st, now) + n
    st.heatAt = now
    return st.heat >= 100
end

-- C.Jolt(st, k, rnd): knock the tilt bubble k in a random direction
-- (cuts 0.12, jumpers 0.16, mount cuts 0.1). Nothing once safe.
function C.Jolt(st, k, rnd)
    local t = st.tilt
    if not t or st.safe then return end
    local a = R(rnd)() * 2 * math.pi
    t.nx = t.nx + math.cos(a) * k
    t.ny = t.ny + math.sin(a) * k
end

-- C.PowerGone(st, now) -> cause or nil. Power is gone (every supply cut
-- or drained): a self-powered charge still armed fires ("sensor");
-- otherwise the capacitor starts draining and a timer stops (keeping the
-- time it had left).
function C.PowerGone(st, now)
    if st.sensor then return "sensor" end
    if st.f.battery == "capacitor" and not st.capAt and not st.capZero then st.capAt = now end
    if st.timerEnd then
        st.timerLeft = math.max(0, st.timerEnd - now)
        st.timerEnd = nil
    end
    if st.timerSecs then st.timerStopped = true st.timerWaiting = false end
    return nil
end

-- C.ReadyDone(st) -> bool: detonator cut, gas valve sealed (gas / virus)
-- and the stabiliser dosed (if any). A new module that must be finished
-- after the detonator line adds its check here.
function C.ReadyDone(st)
    if st.done or st.over or not st.safe then return false end
    if st.f.charge ~= "he" and not st.gasSealed then return false end
    if st.stab and not st.stab.done then return false end
    return true
end

local function isBattery(id) return id == "bat" or id == "batB" end
C.IsBattery = isBattery

local function partOf(st, id)
    for _, p in ipairs(st.parts) do if p.id == id then return p end end
end
C.PartOf = partOf

-- C.ColourName(st, i): the colour name of wire i ("Red").
function C.ColourName(st, i) return E.COLOURS[st.colors[i] or 1][1] end
local colourName = C.ColourName

-- C.Reading(st, i, now) -> string: what the probe says about wire i. This
-- is the only way players learn a wire's job, so each kind has its own
-- wording (the manual's "Probe readings" table explains them):
--   supply "LIVE 9V" / "DEAD (drained)"; feed / det / tmrline: "LIVE 9V"
--   (tmrline adds "· CLOCK"), "LIVE · CAP n%", "DEAD · CAP n%" (under 5%),
--   "DEAD"; antenna "SIGNAL · f GHz" / "JAMMED · f GHz" / "DEAD";
--   ajmon "MON ..."; collapse "LOOP 3V"; sense "LIVE 9V · SENSE";
--   tamper "LOOP 5V"; logic "LOGIC · pulsing" / "DEAD · chip safe";
--   relay / trig "RELAY ..." / "TRIGGER ..."; decoy "DEAD".
-- st.covered must be set first for the JAMMED reading.
local function round(x) return math.floor(x + 0.5) end
function C.Reading(st, i, now)
    if st.cut[i] then return "CUT" end
    local w = st.wires[i]
    local k = w.k
    local cap = capNow(st, now)
    if k == "supply" then return st.drained[w.a] and "DEAD (drained)" or "LIVE 9V" end
    if k == "feed" or k == "det" or k == "tmrline" then
        if anySupply(st) then return "LIVE 9V" .. (k == "tmrline" and " · CLOCK" or "") end
        if st.f.battery == "capacitor" and cap >= 5 then return "LIVE · CAP " .. round(cap) .. "%" end
        if st.f.battery == "capacitor" and k ~= "tmrline" and cap > 0 then return "DEAD · CAP " .. round(cap) .. "%" end
        return "DEAD"
    end
    local freq = string.format("%.3f GHz", st.freq / 1000)
    if k == "antenna" then
        local base = (st.remoteDead and not st.relayed) and "DEAD" or ((st.covered and "JAMMED · " or "SIGNAL · ") .. freq)
        return base .. (w.armoured and " · armoured" or "")
    end
    if k == "ajmon" then return "MON · watching receiver" end
    if k == "collapse" then return "LOOP 3V" end
    if k == "sense" then return anySupply(st) and "LIVE 9V · SENSE" or "DEAD" end
    if k == "tamper" then return "LOOP 5V" end
    if k == "logic" then return st.chip and st.chip.ok and "DEAD · chip safe" or "LOGIC · pulsing" end
    if k == "relay" then return st.relayed and "SIGNAL → DUMMY LOAD · armoured" or ("RELAY · " .. freq .. " · armoured") end
    if k == "trig" then return st.relayed and "DEAD · armoured" or "TRIGGER · armed · armoured" end
    return "DEAD"
end

--------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------

local function out() return { lines = {} } end
local function say(o, text, bad) o.lines[#o.lines + 1] = { text, bad and true or false } end

-- C.Cut(st, i, now) -> outcome: wirecutters on wire i. By wire kind:
--   supply   collapse armed -> boom; else cut; last supply -> PowerGone
--   feed / tmrline   still powered -> boom
--   antenna  anti-jam armed -> boom; else the receiver is dead
--   sense    self-powered charge still armed -> boom
--   ajmon    disarms anti-jam      collapse  disarms the collapse circuit
--   tamper   halves a running timer (outcome.timerEnd)
--   logic    chip not in safe mode -> boom
--   det      liquid charge still full, chip not safe, or still powered
--            -> boom; else SAFE (gas / virus: the valve leaks, seal it
--            within leakTime)
--   decoy    nothing
-- Sealed wires can't be cut until the plate is open; armoured never
-- (outcome.refused = true). "was" = powered before this cut, so cutting
-- the last supply and then a line doesn't count as live. outcome.cut =
-- true when a wire was actually cut (the caller then jolts and heats).
function C.Cut(st, i, now)
    local o = out()
    local w = st.wires[i]
    if not w or st.cut[i] then return o end
    if w.sealed and not st.sealedOpen then say(o, "That wire runs under the sealed plate") o.refused = true return o end
    if w.armoured then say(o, colourName(st, i) .. " is armoured: the cutters won't go through", true) o.refused = true return o end
    local name = colourName(st, i)
    local was = powered(st, now)
    local k = w.k
    if k == "supply" then
        if st.collapse then o.boom = "collapse" return o end
        st.cut[i] = true
        say(o, "Cut " .. name .. " (battery supply)")
        if not anySupply(st) then
            local c = C.PowerGone(st, now)
            if c then o.boom = c return o end
        end
    elseif k == "feed" then
        if was then o.boom = "feed" return o end
        st.cut[i] = true
        say(o, "Cut " .. name .. " (capacitor feed, dead)")
    elseif k == "tmrline" then
        if was then o.boom = "tmrline" return o end
        st.cut[i] = true
        say(o, "Cut " .. name .. " (timer line, dead)")
    elseif k == "antenna" then
        if st.antiJam then o.boom = "antenna" return o end
        st.cut[i] = true
        st.remoteDead = true
        say(o, "Cut " .. name .. ": receiver dead")
    elseif k == "sense" then
        if st.sensor then o.boom = "sensor" return o end
        st.cut[i] = true
        say(o, "Cut " .. name .. " (SENSE line, sensor already dead)")
    elseif k == "ajmon" then
        st.cut[i] = true
        st.antiJam = false
        say(o, "Cut " .. name .. ": anti-jam disarmed")
    elseif k == "collapse" then
        st.cut[i] = true
        st.collapse = false
        say(o, "Cut " .. name .. ": collapse circuit disarmed")
    elseif k == "tamper" then
        st.cut[i] = true
        if st.timerEnd then
            local left = (st.timerEnd - now) / 2
            st.timerEnd = now + left
            o.timerEnd = st.timerEnd
            say(o, "Cut " .. name .. ": tamper loop, the timer halved", true)
        else
            say(o, "Cut " .. name .. " (tamper loop)")
        end
    elseif k == "logic" then
        if not (st.chip and st.chip.ok) then o.boom = "chip" return o end
        st.cut[i] = true
        say(o, "Cut " .. name .. " (logic line, chip already safe)")
    elseif k == "det" then
        if st.liquid and not st.liquid.drained then o.boom = "liquidfull" return o end
        if st.chip and not st.chip.ok then o.boom = "chip" return o end
        if was then o.boom = "det" return o end
        st.cut[i] = true
        st.safe = true
        say(o, "Cut " .. name .. ": detonator disconnected")
        if st.f.charge ~= "he" then
            st.leakEnd = now + E.Cfg("leakTime")
            say(o, "The canister valve is open: seal it", true)
        end
    else
        st.cut[i] = true
        say(o, "Cut " .. name .. ": nothing happened")
    end
    o.cut = true
    return o
end

-- C.Short(st, id, now) -> outcome: a jumper from a part's + to its own −.
--   relay -> boom (latches closed)        load -> nothing
--   cell  -> self-powered charge disarmed
--   cap   -> supply still live: boom; else emptied at once
--   det   -> powered: boom; else nothing
--   bat / batB -> collapse armed: boom; else that battery is drained
--                 (the last one -> PowerGone)
function C.Short(st, id, now)
    local o = out()
    local label = (partOf(st, id) or {}).label or id
    if id == "relay" then o.boom = "relayshort" return o end
    if id == "load" then say(o, "Shorted the dummy load: no effect") return o end
    if id == "cell" then
        st.sensor = false
        say(o, "Shorted the charge cell: sparks, then nothing. Sensor dead")
        return o
    end
    if id == "cap" then
        if anySupply(st) then o.boom = "capshort" return o end
        st.capZero = true
        say(o, "Shorted the capacitor: emptied")
        return o
    end
    if id == "det" then
        if powered(st, now) then o.boom = "detshort" return o end
        say(o, "Shorted the detonator: no power, nothing happened")
        return o
    end
    if isBattery(id) then
        if st.collapse then o.boom = "collapse" return o end
        st.drained[id] = true
        say(o, "Shorted " .. label .. ": drained")
        if not anySupply(st) then o.boom = C.PowerGone(st, now) end
        return o
    end
    say(o, "Jumper across " .. label .. ": no effect")
    return o
end

-- C.Jump(st, x, y, now) -> outcome: a jumper between two different parts
-- (terminal polarity doesn't matter here):
--   relay <-> load -> the relay is redirected: the remote can't fire it
--   relay <-> det  -> boom
--   det <-> a live battery or a capacitor at 5%+ -> boom
--   anything else  -> nothing (it still uses up the jumper)
function C.Jump(st, x, y, now)
    local o = out()
    local a, b = x, y
    if a > b then a, b = b, a end   -- (sorted, so each pair is checked once)
    if a == "load" and b == "relay" then
        st.relayed = true
        st.remoteDead = true
        say(o, "Relay redirected into the dummy load: the remote can't reach the detonator")
        return o
    end
    if a == "det" and b == "relay" then o.boom = "relaydet" return o end
    local other = x == "det" and y or y == "det" and x or nil
    if other then
        local live = (isBattery(other) and not st.drained[other] and anySupply(st)) or (other == "cap" and capNow(st, now) >= 5)
        if live then o.boom = "jumpdet" return o end
    end
    say(o, "Jumper from " .. ((partOf(st, x) or {}).label or x) .. " to " .. ((partOf(st, y) or {}).label or y) .. ": no effect")
    return o
end

-- C.Chip(st, sw) -> outcome: set the logic chip's switches ("0101").
-- Wrong -> boom (st.chipWrong keeps the wrong setting); right -> safe
-- mode (outcome.ok; the caller adds 10 heat).
function C.Chip(st, sw)
    local o = out()
    if sw ~= E.CHIP_CODES[st.chip.code][2] then
        st.chipWrong = sw
        o.boom = "chipwrong"
        return o
    end
    st.chip.ok = true
    o.ok = true
    say(o, "Logic chip in safe mode")
    return o
end

-- C.Drain(st, now, at) -> outcome: open the liquid charge's drain valve.
-- Still powered (at `now`) -> boom; the needle at time `at` outside
-- band - 2 .. band + 16 (2 units of slack each side of the 14-wide green
-- band) -> boom.
function C.Drain(st, now, at)
    local o = out()
    if powered(st, now) then o.boom = "liquidpower" return o end
    local n = E.LiquidNeedle(st.liquid, at)
    if n < st.liquid.band - 2 or n > st.liquid.band + 16 then o.boom = "liquid" return o end
    st.liquid.drained = true
    say(o, "Liquid charge drained")
    return o
end

-- C.Mount(st, m) -> outcome: cut fake board mount m (1-3). Out of order
-- -> boom. The caller jolts, heats, and lifts the cover once n reaches 3
-- (outcome.cut).
function C.Mount(st, m)
    local o = out()
    if st.fake.order[st.fake.n + 1] ~= m then o.boom = "fake" return o end
    st.fake.cut[m] = true
    st.fake.n = st.fake.n + 1
    o.cut = true
    return o
end

-- C.Stab(st, q) -> outcome: inject q quarters of a ml. Any other dose
-- than the label -> boom (st.stabSet keeps what was given).
function C.Stab(st, q)
    local o = out()
    local dose = q * 0.25
    if math.abs(dose - st.stab.dose) > 0.01 then
        st.stabSet = dose
        o.boom = "stab"
        return o
    end
    st.stab.done = true
    say(o, "Charge stabilised")
    return o
end
