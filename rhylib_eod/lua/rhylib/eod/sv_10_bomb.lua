--[[
    Bombs (server): rolling a bomb, its board, the rules, and what the
    defusal window may see (E.View: never the wire kinds, only colours,
    ends and flags; readings come from the probe).

    bomb.eod = st (state). Viewers (window open) get eod.state (compressed
    JSON of E.View) after every change; the probe answers with eod.read.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

for _, n in ipairs({ "eod.state", "eod.read", "eod.msg", "eod.boom", "eod.done", "eod.xray", "eod.close", "eod.gmopen", "eod.gas", "eod.far" }) do
    Net.Register(n)
end

E.bombs = E.bombs or {}

local function chance(p) return math.random() < p end
local function pickW(o)
    local t = 0
    for _, v in pairs(o) do t = t + v end
    local x = math.random() * t
    for k, v in pairs(o) do
        x = x - v
        if x < 0 then return k end
    end
    return next(o)
end
local function shuffle(t)
    t = table.Copy(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end
E.Shuffle = shuffle

--------------------------------------------------------------------------
-- Rolling and building
--------------------------------------------------------------------------

-- Features for a bomb type (simple / small / large). Custom bombs pass
-- their own (GM window).
function E.Roll(kind)
    if kind == "simple" then
        return { type = "simple", det = "timer", antiJam = false, motion = nil, lid = true, battery = "single",
            sensor = false, charge = "he", hop = false, mods = {} }
    end
    local large = kind == "large"
    local det = chance(large and 0.6 or 0.5) and "remote" or "timer"
    local f = {
        type = large and "large" or "small", det = det,
        antiJam = det == "remote" and chance(large and 0.4 or 0.2),
        motion = chance(large and 0.7 or 0.5) and (large and chance(0.5) and "sensitive" or "normal") or nil,
        lid = chance(large and 0.5 or 0.4),
        battery = pickW(large and { dual = 30, capacitor = 25, collapse = 25, single = 20 } or { single = 40, capacitor = 30, collapse = 30 }),
        sensor = chance(large and 0.3 or 0.2),
        charge = pickW(large and { he = 80, gas = 10, virus = 10 } or { he = 70, gas = 20, virus = 10 }),
        hop = large and det == "remote" and chance(0.3),
        mods = {},
    }
    -- Modules within the tier's budget: points = ranks, and a cap on how many.
    local t = E.TIERS[f.type]
    local left, n = t.budget, 0
    for _, m in ipairs(shuffle(E.MODS)) do
        if n >= t.max then break end
        if not (m.remote and det ~= "remote") and m.rank <= left and chance(0.75) then
            f.mods[m.id] = true
            left = left - m.rank
            n = n + 1
        end
    end
    return f
end

-- The board: parts (board units, 760 x 420) and wires.
local function buildBoard(f)
    local P, parts = {}, {}
    local function add(id, label, sub, x, y, w, h, term)
        local p = { id = id, label = label, sub = sub, x = x, y = y, w = w, h = h, term = term or nil }
        parts[#parts + 1] = p
        P[id] = p
    end
    local L, M, R = 20, 310, 590
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
    if f.det == "remote" then add("ant", "Antenna", "", R, 20, 150, 48) end
    local sub = (f.charge == "gas" and "gas canister") or (f.charge == "virus" and "bio canister") or "HE block"
    add("chg", "Charge", f.sensor and (sub .. " · cell") or sub, R, 96, 150, 300)
    if f.sensor then add("cell", "Charge cell", "+ sensor", R + 12, 316, 126, 64, true) end

    local wires = {}
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
    if P.tmr and f.type ~= "simple" and (f.type ~= "small" or chance(0.5)) then W("tamper", "tmr", "chg") end
    local cand = {}
    for _, c in ipairs({ { "bat", "chg" }, { "rx", "chg" }, { "tmr", "chg" }, { "col", "chg" }, { "aj", "chg" }, { "chip", "chg" }, { "cap", "chg" }, { "batB", "det" } }) do
        local dup = false
        for _, w in ipairs(wires) do if w.a == c[1] and w.b == c[2] then dup = true end end
        if P[c[1]] and P[c[2]] and not dup then cand[#cand + 1] = c end
    end
    local nd = (f.type == "large" or f.type == "custom") and 2 or 1
    for i, c in ipairs(shuffle(cand)) do
        if i > nd then break end
        W("decoy", c[1], c[2])
    end
    if not relay then f.mods.relay = nil end
    return parts, wires
end

local function sineSet(amp)
    local s = { a = {}, w = {}, p = {} }
    local base, periods = { 0.3, 0.2, 0.12 }, { { 7, 13 }, { 4, 8 }, { 2.5, 4.5 } }
    for i = 1, 3 do
        s.a[i] = base[i] * amp * math.Rand(0.85, 1.15)
        s.w[i] = 2 * math.pi / math.Rand(periods[i][1], periods[i][2])
        s.p[i] = math.Rand(0, 2 * math.pi)
    end
    return s
end

-- A fresh state for features f.
function E.Build(f)
    local parts, wires = buildBoard(f)
    local t = E.TIERS[f.type] or E.TIERS.small
    local all = {}
    for i = 1, #E.COLOURS do all[i] = i end
    local cols = shuffle(all)
    local st = {
        f = f, type = f.type, kindName = t.name, big = t.big, mods = f.mods, parts = parts, wires = wires,
        colors = {}, freq = 2405 + math.random(0, 70), hopAt = CurTime() + (E.Cfg("hopEvery") or 25),
        viewers = {},
        inspected = false, open = false, lidReleased = false,
        cut = {}, drained = {}, jumps = {}, jumpers = E.Cfg("jumpers") or 3,
        antiJam = f.antiJam and true or false, collapse = f.battery == "collapse", sensor = f.sensor and true or false,
        remoteDead = f.det ~= "remote", relayed = false,
        timerSecs = f.det == "timer" and (f.timerSecs or (f.type == "simple" and 150 or t.big and 240 or 180)) or nil,
        timerWaiting = f.det == "timer",
        safe = false, gasSealed = false, done = false, over = false, recovered = false,
        heat = 0, heatAt = CurTime(), sealedOpen = not f.mods.sealed, sealedP = 0,
        tilt = f.mods.tilt and { x = sineSet(1), y = sineSet(1), nx = 0, ny = 0, mult = t.big and 1 or 0.85 } or nil,
        chip = f.mods.chip and { code = math.random(#E.CHIP_CODES), ok = false } or nil,
        liquid = f.mods.liquid and { band = 15 + math.random() * 60, period = 3.5 + math.random() * 3, ph = math.random() * 6.283, drained = false } or nil,
        fake = f.mods.fake and { removed = false, xrays = E.Cfg("xrays") or 2, order = shuffle({ 1, 2, 3 }), n = 0, cut = { false, false, false }, cols = {} } or nil,
        stab = f.mods.stab and { dose = 0.75 + math.random(0, 17) * 0.25, done = false } or nil,
    }
    for i = 1, #wires do st.colors[i] = cols[(i - 1) % #cols + 1] end
    if st.fake then
        local c2 = shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })
        st.fake.cols = { c2[1], c2[2], c2[3] }
    end
    return st
end

--------------------------------------------------------------------------
-- Circuit helpers
--------------------------------------------------------------------------

local function anySupply(st)
    for i, w in ipairs(st.wires) do
        if w.k == "supply" and not st.cut[i] and not st.drained[w.a] then return true end
    end
    return false
end
E.AnySupply = anySupply

local function capNow(st)
    if st.f.battery ~= "capacitor" or st.capZero then return 0 end
    if not st.capAt then return 100 end
    return math.max(0, 100 - (CurTime() - st.capAt) * 100 / math.max(1, E.Cfg("capDrain") or 15))
end
E.CapNow = capNow

local function powered(st) return anySupply(st) or capNow(st) >= 5 end

function E.Covered(bomb) return (bomb.eodCovered or 0) > CurTime() end

local function heatNow(st) return math.max(0, st.heat - (CurTime() - st.heatAt) * (E.Cfg("heatCool") or 9)) end
E.HeatNow = heatNow

local function isBattery(id) return id == "bat" or id == "batB" end

local function partOf(st, id)
    for _, p in ipairs(st.parts) do if p.id == id then return p end end
end

local function colourName(st, i) return E.COLOURS[st.colors[i] or 1][1] end

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

local function msg(ply, text, bad)
    if not IsValid(ply) then return end
    Net.Start("eod.msg")
    net.WriteString(text)
    net.WriteBool(bad and true or false)
    net.Send(ply)
end
E.Msg = msg

-- What the inspection tells this player (Trained eye: battery, board, modules).
local function facts(st, ply)
    local f = st.f
    local eye = E.Skill(ply, "eod_eye")
    local list = {
        { "Size", st.kindName },
        { "Detonator", f.det == "remote" and "remote (antenna)" or "timer" },
        { "Anti-jam", f.antiJam and "YES" or "no", f.antiJam },
        { "Motion sensor", f.motion or "none", f.motion and true or nil },
        { "Lid switch", f.lid and "YES" or "no", f.lid },
        { "Charge", ((f.charge == "gas" and "poison gas") or (f.charge == "virus" and "virus") or "explosive") .. (f.sensor and " · self-powered" or ""), f.sensor },
    }
    local mods = {}
    for _, m in ipairs(E.MODS) do if st.mods[m.id] then mods[#mods + 1] = m end end
    if eye then
        list[#list + 1] = { "Battery", ({ single = "single", dual = "dual supply", capacitor = "single + capacitor", collapse = "single + collapse circuit" })[f.battery] }
        list[#list + 1] = { "Board", #st.wires .. " wires" }
        local names = {}
        for _, m in ipairs(mods) do names[#names + 1] = m.name .. " (" .. m.rank .. ")" end
        list[#list + 1] = { "Modules", #names > 0 and table.concat(names, ", ") or "none", #names > 0 }
    else
        list[#list + 1] = { "Battery", "? (Trained eye)" }
        list[#list + 1] = { "Modules", #mods > 0 and (#mods .. " (Trained eye names them)") or "none", #mods > 0 }
    end
    return list
end

function E.View(bomb, ply)
    local st = bomb.eod
    local now = CurTime()
    local v = {
        kind = st.kindName, big = st.big, parts = st.open and st.parts or {}, mods = st.open and st.mods or {}, open = st.open, lid = st.lidReleased,
        jumps = st.jumps, jumpers = st.jumpers, safe = st.safe, done = st.done, gas = st.f.charge ~= "he", gasSealed = st.gasSealed,
        leakEnd = st.leakEnd, relayed = st.relayed, now = now, wires = {},
        heat = heatNow(st), torching = st.torchBy ~= nil, sealedOpen = st.sealedOpen, sealedP = st.sealedP,
        recover = st.done and not st.recovered and E.Skill(ply, "eod_render") and Rhylib.Items and Rhylib.Items.Get("rhylib_he_charge") and true or nil,
        kit = E.HasKit(ply),
    }
    for i, w in ipairs(st.wires) do
        v.wires[i] = { a = w.a, b = w.b, c = st.colors[i], cut = st.cut[i] or false, sealed = w.sealed or false, arm = w.armoured or false }
    end
    if st.timerSecs then
        v.timer = { secs = st.timerSecs, ends = st.timerEnd or 0, left = st.timerLeft or st.timerSecs, waiting = st.timerWaiting, stopped = st.timerStopped or false }
    end
    if st.inspected then v.insp = facts(st, ply) end
    if st.tilt then
        local t = st.tilt
        v.tilt = { x = t.x, y = t.y, nx = t.nx, ny = t.ny, mult = t.mult, t0 = t.t0 or 0 }
    end
    if st.chip then v.chip = { ok = st.chip.ok, code = st.open and E.CHIP_CODES[st.chip.code][1] or nil } end
    if st.liquid then v.liquid = { band = st.liquid.band, period = st.liquid.period, ph = st.liquid.ph, drained = st.liquid.drained } end
    if st.fake then v.fake = { removed = st.fake.removed, xrays = st.fake.xrays, n = st.fake.n, cut = st.fake.cut, cols = st.fake.cols } end
    if st.stab then v.stab = { dose = st.open and st.stab.dose or nil, done = st.stab.done } end
    return v
end

local function sendTo(bomb, ply)
    local js = util.TableToJSON(E.View(bomb, ply))
    local data = util.Compress(js)
    if not data then return end
    Net.Start("eod.state")
    net.WriteEntity(bomb)
    net.WriteUInt(#data, 16)
    net.WriteData(data, #data)
    net.Send(ply)
end

-- Send to every viewer next tick (several changes in one tick: once).
function E.Changed(bomb)
    if not IsValid(bomb) or bomb.eodQueued then return end
    bomb.eodQueued = true
    timer.Simple(0, function()
        if not IsValid(bomb) then return end
        bomb.eodQueued = nil
        local st = bomb.eod
        if not st then return end
        for p in pairs(st.viewers) do
            if IsValid(p) then sendTo(bomb, p) else st.viewers[p] = nil end
        end
    end)
end

function E.HasKit(ply)
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.Has) then return true end
    return Inv.Has(ply, E.KIT)
end

--------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------

local function fail(bomb, cause) E.Detonate(bomb, cause) return true end

local function addHeat(bomb, ply, n, always)
    local st = bomb.eod
    if not (st.mods.fuse or always) then return false end
    if E.Skill(ply, "eod_heat") then n = n * 0.6 end
    st.heat = heatNow(st) + n
    st.heatAt = CurTime()
    if st.heat >= 100 then return fail(bomb, "heat") end
    return false
end
E.AddHeat = addHeat

local function jolt(bomb, ply, k)
    local t = bomb.eod.tilt
    if not t or bomb.eod.safe then return end
    if E.Skill(ply, "eod_steady") then k = k * 0.5 end
    local a = math.random() * 2 * math.pi
    t.nx = t.nx + math.cos(a) * k
    t.ny = t.ny + math.sin(a) * k
end

-- Power is gone (every supply cut or drained).
local function powerGone(bomb)
    local st = bomb.eod
    if st.sensor then return fail(bomb, "sensor") end
    if st.f.battery == "capacitor" and not st.capAt and not st.capZero then st.capAt = CurTime() end
    if st.timerEnd then
        st.timerLeft = math.max(0, st.timerEnd - CurTime())
        st.timerEnd = nil
    end
    if st.timerSecs then st.timerStopped = true st.timerWaiting = false end
    return false
end

function E.CheckDone(bomb)
    local st = bomb.eod
    if st.done or st.over or not st.safe then return end
    if st.f.charge ~= "he" and not st.gasSealed then return end
    if st.stab and not st.stab.done then return end
    st.done = true
    st.leakEnd = nil
    st.torchBy = nil
    bomb:SetNW2Bool("rhylib_eodSafe", true)
    bomb:SetNW2Float("rhylib_eodEnd", 0)
    for p in pairs(st.viewers) do
        if IsValid(p) then
            Net.Start("eod.done")
            net.WriteEntity(bomb)
            net.Send(p)
        end
    end
end

function E.Reading(st, i)
    if st.cut[i] then return "CUT" end
    local w = st.wires[i]
    local k = w.k
    local cap = capNow(st)
    if k == "supply" then return st.drained[w.a] and "DEAD (drained)" or "LIVE 9V" end
    if k == "feed" or k == "det" or k == "tmrline" then
        if anySupply(st) then return "LIVE 9V" .. (k == "tmrline" and " · CLOCK" or "") end
        if st.f.battery == "capacitor" and cap >= 5 then return "LIVE · CAP " .. math.Round(cap) .. "%" end
        if st.f.battery == "capacitor" and k ~= "tmrline" and cap > 0 then return "DEAD · CAP " .. math.Round(cap) .. "%" end
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

local function cutWire(bomb, ply, i)
    local st = bomb.eod
    local w = st.wires[i]
    if not w or st.cut[i] then return end
    if w.sealed and not st.sealedOpen then msg(ply, "That wire runs under the sealed plate") return end
    if w.armoured then msg(ply, colourName(st, i) .. " is armoured: the cutters won't go through", true) return end
    local name = colourName(st, i)
    local was = powered(st)
    local k = w.k
    if k == "supply" then
        if st.collapse then return fail(bomb, "collapse") end
        st.cut[i] = true
        msg(ply, "Cut " .. name .. " (battery supply)")
        if not anySupply(st) and powerGone(bomb) then return true end
    elseif k == "feed" then
        if was then return fail(bomb, "feed") end
        st.cut[i] = true
        msg(ply, "Cut " .. name .. " (capacitor feed, dead)")
    elseif k == "tmrline" then
        if was then return fail(bomb, "tmrline") end
        st.cut[i] = true
        msg(ply, "Cut " .. name .. " (timer line, dead)")
    elseif k == "antenna" then
        if st.antiJam then return fail(bomb, "antenna") end
        st.cut[i] = true
        st.remoteDead = true
        msg(ply, "Cut " .. name .. ": receiver dead")
    elseif k == "sense" then
        if st.sensor then return fail(bomb, "sensor") end
        st.cut[i] = true
        msg(ply, "Cut " .. name .. " (SENSE line, sensor already dead)")
    elseif k == "ajmon" then
        st.cut[i] = true
        st.antiJam = false
        msg(ply, "Cut " .. name .. ": anti-jam disarmed")
    elseif k == "collapse" then
        st.cut[i] = true
        st.collapse = false
        msg(ply, "Cut " .. name .. ": collapse circuit disarmed")
    elseif k == "tamper" then
        st.cut[i] = true
        if st.timerEnd then
            local left = (st.timerEnd - CurTime()) / 2
            st.timerEnd = CurTime() + left
            bomb:SetNW2Float("rhylib_eodEnd", st.timerEnd)
            msg(ply, "Cut " .. name .. ": tamper loop, the timer halved", true)
        else
            msg(ply, "Cut " .. name .. " (tamper loop)")
        end
    elseif k == "logic" then
        if not (st.chip and st.chip.ok) then return fail(bomb, "chip") end
        st.cut[i] = true
        msg(ply, "Cut " .. name .. " (logic line, chip already safe)")
    elseif k == "det" then
        if st.liquid and not st.liquid.drained then return fail(bomb, "liquidfull") end
        if st.chip and not st.chip.ok then return fail(bomb, "chip") end
        if was then return fail(bomb, "det") end
        st.cut[i] = true
        st.safe = true
        msg(ply, "Cut " .. name .. ": detonator disconnected")
        if st.f.charge ~= "he" then
            st.leakEnd = CurTime() + (E.Cfg("leakTime") or 20)
            msg(ply, "The canister valve is open: seal it", true)
        end
    else
        st.cut[i] = true
        msg(ply, "Cut " .. name .. ": nothing happened")
    end
    jolt(bomb, ply, 0.12)
    if addHeat(bomb, ply, E.Cfg("heatCut") or 24) then return true end
    return false
end

local function shortPart(bomb, ply, id)
    local st = bomb.eod
    local label = (partOf(st, id) or {}).label or id
    if id == "relay" then return fail(bomb, "relayshort") end
    if id == "load" then msg(ply, "Shorted the dummy load: no effect") return false end
    if id == "cell" then
        st.sensor = false
        msg(ply, "Shorted the charge cell: sparks, then nothing. Sensor dead")
        return false
    end
    if id == "cap" then
        if anySupply(st) then return fail(bomb, "capshort") end
        st.capZero = true
        msg(ply, "Shorted the capacitor: emptied")
        return false
    end
    if id == "det" then
        if powered(st) then return fail(bomb, "detshort") end
        msg(ply, "Shorted the detonator: no power, nothing happened")
        return false
    end
    if isBattery(id) then
        if st.collapse then return fail(bomb, "collapse") end
        st.drained[id] = true
        msg(ply, "Shorted " .. label .. ": drained")
        if not anySupply(st) then return powerGone(bomb) end
        return false
    end
    msg(ply, "Jumper across " .. label .. ": no effect")
    return false
end

local function jumpParts(bomb, ply, x, y)
    local st = bomb.eod
    local a, b = x, y
    if a > b then a, b = b, a end
    if a == "load" and b == "relay" then
        st.relayed = true
        st.remoteDead = true
        msg(ply, "Relay redirected into the dummy load: the remote can't reach the detonator")
        return false
    end
    if a == "det" and b == "relay" then return fail(bomb, "relaydet") end
    local other = x == "det" and y or y == "det" and x or nil
    if other then
        local live = (isBattery(other) and not st.drained[other] and anySupply(st)) or (other == "cap" and capNow(st) >= 5)
        if live then return fail(bomb, "jumpdet") end
    end
    msg(ply, "Jumper from " .. ((partOf(st, x) or {}).label or x) .. " to " .. ((partOf(st, y) or {}).label or y) .. ": no effect")
    return false
end

--------------------------------------------------------------------------
-- Window and actions
--------------------------------------------------------------------------

local function near(ply, bomb)
    local r = E.Cfg("reach") or 130
    return IsValid(bomb) and bomb.eod and IsValid(ply) and ply:Alive() and ply:GetPos():DistToSqr(bomb:GetPos()) <= (r + 40) ^ 2
end

function E.OpenFor(ply, bomb)
    if not near(ply, bomb) or bomb.eod.over then return end
    bomb.eod.viewers[ply] = true
    E.TiltResume(bomb.eod)
    sendTo(bomb, ply)
end

function E.CloseFor(ply, bomb)
    if IsValid(bomb) and bomb.eod then
        bomb.eod.viewers[ply] = nil
        if bomb.eod.torchBy == ply then bomb.eod.torchBy = nil E.Changed(bomb) end
    end
    Net.Start("eod.close")
    net.WriteEntity(bomb)
    net.Send(ply)
end

Net.Receive("eod.close", function(ply)
    local bomb = net.ReadEntity()
    if IsValid(bomb) and bomb.eod then
        bomb.eod.viewers[ply] = nil
        if bomb.eod.torchBy == ply then bomb.eod.torchBy = nil E.Changed(bomb) end
    end
end, { rate = 10, burst = 10 })

local OPS = {}

OPS[0] = function(ply, bomb) ply.eodInspect = { bomb = bomb, t = CurTime() } end

OPS[1] = function(ply, bomb)
    local st = bomb.eod
    local need = (E.Cfg("inspectTime") or 2.5) * (E.Skill(ply, "eod_quick") and 0.6 or 1)
    local ins = ply.eodInspect
    ply.eodInspect = nil
    if st.inspected or not ins or ins.bomb ~= bomb or CurTime() - ins.t < need * 0.9 then return end
    st.inspected = true
    msg(ply, "First inspection done")
end

OPS[2] = function(ply, bomb)
    local st = bomb.eod
    if not E.HasKit(ply) or st.open then return end
    st.lidReleased = true
    msg(ply, st.f.lid and "Lid-switch tab released" or "There's no lid switch on this one")
end

OPS[3] = function(ply, bomb)
    local st = bomb.eod
    if not E.HasKit(ply) or st.open then return end
    if st.f.lid and not st.lidReleased then return fail(bomb, "lid") end
    st.open = true
    st.tech = ply
    if st.tilt then
        st.tilt.t0 = CurTime()
        if E.Skill(ply, "eod_steady") then st.tilt.mult = st.tilt.mult * 0.6 end
    end
    if st.fake then st.fake.xrays = st.fake.xrays + (E.Skill(ply, "eod_xray") and 1 or 0) end
    st.jumpers = st.jumpers + (E.Skill(ply, "eod_jumpers") and 2 or 0)
    msg(ply, "Casing open: the board is exposed")
end

local function boardReady(ply, st)
    if not E.HasKit(ply) then msg(ply, "You need an EOD kit", true) return false end
    if not st.open or st.safe and false then return false end
    if st.fake and not st.fake.removed then msg(ply, "The board cover is still on") return false end
    return true
end

OPS[4] = function(ply, bomb, i)
    local st = bomb.eod
    if not boardReady(ply, st) or not st.wires[i] then return end
    if st.wires[i].sealed and not st.sealedOpen then msg(ply, "That wire runs under the sealed plate") return end
    st.covered = E.Covered(bomb)
    Net.Start("eod.read")
    net.WriteUInt(i, 5)
    net.WriteString(E.Reading(st, i))
    net.Send(ply)
    return "noSend"
end

OPS[5] = function(ply, bomb, i)
    local st = bomb.eod
    if not boardReady(ply, st) then return end
    cutWire(bomb, ply, i)
end

OPS[6] = function(ply, bomb, pa, pola, pb, polb)
    local st = bomb.eod
    if not boardReady(ply, st) then return end
    local A, B = st.parts[pa], st.parts[pb]
    if not (A and B and A.term and B.term) or (pa == pb and pola == polb) then return end
    if st.jumpers <= 0 then msg(ply, "No jumper wires left", true) return end
    st.jumpers = st.jumpers - 1
    st.jumps[#st.jumps + 1] = { a = pa, pa = pola, b = pb, pb = polb }
    local boom
    if pa == pb then boom = shortPart(bomb, ply, A.id) else boom = jumpParts(bomb, ply, A.id, B.id) end
    if boom then return end
    jolt(bomb, ply, 0.16)
    addHeat(bomb, ply, E.Cfg("heatJumper") or 30)
end

OPS[7] = function(ply, bomb, dx, dy)
    local st = bomb.eod
    if not (st.tilt and st.open) or st.safe then return end
    st.tilt.nx = math.Clamp(st.tilt.nx + dx * 0.14, -3, 3)
    st.tilt.ny = math.Clamp(st.tilt.ny + dy * 0.14, -3, 3)
end

OPS[8] = function(ply, bomb, on)
    local st = bomb.eod
    if not (st.mods.sealed and st.open) or st.sealedOpen or not E.HasKit(ply) then return end
    if on then
        st.torchBy = ply
        st.torchAt = CurTime()
    elseif st.torchBy == ply then
        st.torchBy = nil
    end
end

OPS[9] = function(ply, bomb, sw)
    local st = bomb.eod
    if not (st.chip and st.open) or st.chip.ok or not E.HasKit(ply) then return end
    if sw ~= E.CHIP_CODES[st.chip.code][2] then
        st.chipWrong = sw
        return fail(bomb, "chipwrong")
    end
    st.chip.ok = true
    msg(ply, "Logic chip in safe mode")
    addHeat(bomb, ply, 10)
end

OPS[10] = function(ply, bomb)
    local st = bomb.eod
    if not (st.liquid and st.open) or st.liquid.drained or not E.HasKit(ply) then return end
    if powered(st) then return fail(bomb, "liquidpower") end
    -- (a little slack for latency: the needle moves ~10%/0.1 s at most)
    local n = E.LiquidNeedle(st.liquid, CurTime() - math.min(0.25, ply:Ping() / 1000))
    if n < st.liquid.band - 2 or n > st.liquid.band + 16 then return fail(bomb, "liquid") end
    st.liquid.drained = true
    msg(ply, "Liquid charge drained")
end

OPS[11] = function(ply, bomb)
    local st = bomb.eod
    if not (st.fake and st.open) or st.fake.removed or st.fake.xrays <= 0 or not E.HasKit(ply) then return end
    st.fake.xrays = st.fake.xrays - 1
    local secs = (E.Cfg("xrayTime") or 5) + (E.Skill(ply, "eod_xray") and 3 or 0)
    Net.Start("eod.xray")
    net.WriteEntity(bomb)
    for k = 1, 3 do net.WriteUInt(st.fake.order[k], 2) end
    net.WriteFloat(secs)
    net.Send(ply)
    msg(ply, "X-ray: the mount order shows for " .. secs .. " s")
end

OPS[12] = function(ply, bomb, m)
    local st = bomb.eod
    if not (st.fake and st.open) or st.fake.removed or not E.HasKit(ply) or st.fake.cut[m] == nil or st.fake.cut[m] then return end
    if st.fake.order[st.fake.n + 1] ~= m then return fail(bomb, "fake") end
    st.fake.cut[m] = true
    st.fake.n = st.fake.n + 1
    jolt(bomb, ply, 0.1)
    if addHeat(bomb, ply, 20) then return end
    if st.fake.n >= 3 then
        st.fake.removed = true
        msg(ply, "Fake board lifted: the real board is underneath")
    end
end

OPS[13] = function(ply, bomb, q)
    local st = bomb.eod
    if not st.stab or not st.safe or st.stab.done or not E.HasKit(ply) then return end
    local dose = q * 0.25
    if math.abs(dose - st.stab.dose) > 0.01 then
        st.stabSet = dose
        return fail(bomb, "stab")
    end
    st.stab.done = true
    msg(ply, "Charge stabilised")
end

OPS[14] = function(ply, bomb)
    local st = bomb.eod
    if not st.safe or st.f.charge == "he" or st.gasSealed then return end
    st.gasSealed = true
    st.leakEnd = nil
    msg(ply, "Valve sealed")
end

OPS[15] = function(ply, bomb)
    local st = bomb.eod
    if not st.done or st.recovered or not E.Skill(ply, "eod_render") then return end
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.AddOrDrop and Rhylib.Items and Rhylib.Items.Get("rhylib_he_charge")) then return end
    st.recovered = true
    local n = st.big and 2 or 1
    Inv.AddOrDrop(ply, "rhylib_he_charge", n)
    msg(ply, "Recovered the charge: " .. n .. " high explosive charge" .. (n == 1 and "" or "s"))
end

Net.Receive("eod.act", function(ply)
    local bomb = net.ReadEntity()
    local op = net.ReadUInt(4)
    local a, b, c, d
    if op == 4 or op == 5 then a = net.ReadUInt(5)
    elseif op == 6 then a = net.ReadUInt(4) b = net.ReadBool() c = net.ReadUInt(4) d = net.ReadBool()
    elseif op == 7 then a = net.ReadInt(3) b = net.ReadInt(3)
    elseif op == 8 then a = net.ReadBool()
    elseif op == 9 then a = net.ReadString()
    elseif op == 12 then a = net.ReadUInt(2)
    elseif op == 13 then a = net.ReadUInt(5) end
    if not near(ply, bomb) then return end
    local st = bomb.eod
    if st.over or (st.done and op ~= 15) or not st.viewers[ply] then return end
    if op == 7 then a = math.Clamp(a, -1, 1) b = math.Clamp(b, -1, 1) end
    if op == 9 and not (isstring(a) and #a == 4) then return end
    local f = OPS[op]
    if not f then return end
    local r = f(ply, bomb, a, b, c, d)
    if not IsValid(bomb) or st.over then return end
    if r ~= "noSend" then
        E.CheckDone(bomb)
        E.Changed(bomb)
    end
end, { rate = 20, burst = 20 })
