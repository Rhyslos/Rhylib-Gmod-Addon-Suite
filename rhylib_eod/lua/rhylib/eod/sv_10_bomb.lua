--[[
    Bombs (server): rolling a bomb, its board, the rules, and what the
    defusal window may see (E.View: never the wire kinds, only colours,
    ends and flags; readings come from the probe).

    bomb.eod = st (state). Viewers (window open) get eod.state (compressed
    JSON of E.View) after every change; the probe answers with eod.read.

    The circuit model itself (rolling, the board, the rules, readings)
    is pure and lives in sh_05_circuit.lua (E.Circuit); this file plays
    its outcomes on real bombs: log lines (eod.msg), the timer readout,
    detonation (fail -> E.Detonate with an E.CAUSES key), the tilt jolt
    and heat after cuts and jumpers, and the OPS table (one function per
    window action). The world timer in sv_20_world runs motion,
    anti-jam, timer, gas leak, tilt and torch.

    Power: "powered" = any supply wire not cut (and its battery not
    shorted) OR a capacitor still at 5% or more. The capacitor starts to
    drain (capDrain seconds) only once every supply is gone.

    Nets (all "rhylib." prefixed by Rhylib.Net):
      eod.act    client -> server  bomb, op (4 bits), op arguments (see
                                   the receiver at the bottom); rate 20/s
      eod.close  both ways         bomb (the window was closed)
      eod.state  server -> viewer  bomb, len (16 bits), compressed JSON of E.View
      eod.read   server -> prober  wire index (5 bits), reading string
      eod.msg    server -> player  text, bad (bool): a log line in the window
      eod.done   server -> viewers bomb (made safe: plays a sound)
      eod.xray   server -> player  bomb, mount order (3 × 2 bits), seconds (float)
      eod.boom / eod.gas / eod.far / eod.gmopen: sent from sv_20_world.
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

for _, n in ipairs({ "eod.state", "eod.read", "eod.msg", "eod.boom", "eod.done", "eod.xray", "eod.close", "eod.gmopen", "eod.gas", "eod.far" }) do
    Net.Register(n)
end

E.bombs = E.bombs or {}   -- [bomb entity] = true, every set-up bomb (the world timer walks it)

local C = E.Circuit   -- (sh_05_circuit.lua: the pure circuit model)

-- E.Shuffle(list) -> a shuffled copy (the list itself is left alone).
function E.Shuffle(t) return C.Shuffle(t) end

--------------------------------------------------------------------------
-- Rolling and building (sh_05_circuit.lua has the model and the rules)
--------------------------------------------------------------------------

-- E.Roll(kind) -> f: a random feature table (see C.Roll). Server only.
-- Example: E.Rebuild(bomb, E.Roll("large"))
function E.Roll(kind) return C.Roll(kind) end

-- E.Build(f) -> st: a fresh state (see C.Build). Server only. Doesn't
-- touch any entity: E.SetupBomb (sv_20_world) stores it as bomb.eod.
function E.Build(f) return C.Build(f, CurTime()) end

--------------------------------------------------------------------------
-- Circuit helpers (now = CurTime())
--------------------------------------------------------------------------

-- E.AnySupply(st) -> bool: is any battery still feeding the board?
E.AnySupply = C.AnySupply
local anySupply = C.AnySupply

-- E.CapNow(st) -> 0-100: capacitor charge now.
function E.CapNow(st) return C.CapNow(st, CurTime()) end
local capNow = E.CapNow

-- Live power anywhere: a battery, or the capacitor at 5% or more.
local function powered(st) return C.Powered(st, CurTime()) end

-- E.Covered(bomb) -> bool: an active interference device blocked this
-- bomb's remote signal in the last 0.5 s (the world timer refreshes it).
function E.Covered(bomb) return (bomb.eodCovered or 0) > CurTime() end

-- E.HeatNow(st): board heat now.
function E.HeatNow(st) return C.HeatNow(st, CurTime()) end
local heatNow = E.HeatNow

--------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------

-- E.Msg(ply, text, bad): a line in the player's defusal window log (or
-- chat when no window is open). bad = red, with a warning sound.
-- Example: Rhylib.EOD.Msg(ply, "The canister valve is open: seal it", true)
local function msg(ply, text, bad)
    if not IsValid(ply) then return end
    Net.Start("eod.msg")
    net.WriteString(text)
    net.WriteBool(bad and true or false)
    net.Send(ply)
end
E.Msg = msg

-- What the inspection tells (the same for everyone).
-- A list of { label, value, warn } rows; warn = shown in the warning colour.
local function facts(st, ply)
    local f = st.f
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
    list[#list + 1] = { "Modules", #mods > 0 and (#mods .. " (lift the lid to see them)") or "none", #mods > 0 }
    return list
end

-- E.View(bomb, ply) -> table: what this player's defusal window may know.
-- Wires carry only ends, colour and flags (cut, sealed, arm = armoured),
-- never the kind. Parts and modules are empty until the lid is off; the
-- chip code and stabiliser dose only show once open. Live values (heat,
-- timer, tilt) are sent with now = CurTime() so the client can run them
-- on between messages. A new module adds its own v.<id> entry here.
function E.View(bomb, ply)
    local st = bomb.eod
    local now = CurTime()
    local v = {
        kind = st.kindName, big = st.big, parts = st.open and st.parts or {}, mods = st.open and st.mods or {}, open = st.open, lid = st.lidReleased,
        jumps = st.jumps, jumpers = st.jumpers, safe = st.safe, done = st.done, gas = st.f.charge ~= "he", gasSealed = st.gasSealed,
        leakEnd = st.leakEnd, relayed = st.relayed, now = now, wires = {},
        heat = heatNow(st), torching = st.torchBy ~= nil, sealedOpen = st.sealedOpen, sealedP = st.sealedP,
        recover = st.done and not st.recovered and not bomb.IsTrainingBomb and E.Skill(ply, "eod_render") and Rhylib.Items and Rhylib.Items.Get("rhylib_he_charge") and true or nil,
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

-- net eod.state: bomb, length (16 bits), compressed JSON of E.View.
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
-- E.Changed(bomb): call after changing bomb.eod so open windows update.
-- Example: bomb.eod.jumpers = 5  Rhylib.EOD.Changed(bomb)
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

-- E.HasKit(ply) -> bool: carries an EOD kit (always true without
-- rhylib_inventory, so the addon still works without it). Server.
function E.HasKit(ply)
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.Has) then return true end
    return Inv.Has(ply, E.KIT)
end

-- Bomb squad (datapad "Call the bomb squad"): any Field technician skill,
-- or an EOD kit carried. nil = let the datapad decide (job eod = true).
-- E.IsBombSquad(ply) -> bool (the hook below turns false into nil).
function E.IsBombSquad(ply)
    local K = Rhylib.Skills
    if K and K.NODES and K.Has then
        for _, n in ipairs(K.NODES) do
            if n.spec == "eod" and K.Has(ply, n.id) then return true end
        end
    end
    local Inv = Rhylib.Inventory
    return Inv and Inv.Has and Inv.Has(ply, E.KIT) or false
end
Rhylib.Hook.Add("Rhylib.IsBombSquad", "eod.squad", function(ply)
    if E.IsBombSquad(ply) then return true end
end)

--------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------

-- Every rule that sets the bomb off ends here. Returns true so a rule
-- can "return fail(bomb, cause)" and its caller knows to stop.
local function fail(bomb, cause) E.Detonate(bomb, cause) return true end

-- E.AddHeat(bomb, ply, amount, always) -> true if it went past 100 and
-- fired. Only bombs with the thermal fuse heat up, unless always (the
-- torch on a sealed plate heats any bomb).
local function addHeat(bomb, ply, n, always)
    if C.AddHeat(bomb.eod, n, CurTime(), always) then return fail(bomb, "heat") end
    return false
end
E.AddHeat = addHeat

-- Tilt switch: knock the bubble k in a random direction.
local function jolt(bomb, ply, k) C.Jolt(bomb.eod, k) end

-- E.CheckDone(bomb): once the detonator is cut (st.safe), the gas valve
-- sealed (gas / virus) and the stabiliser dosed (if any), mark the bomb
-- done: the readout says SAFE and viewers get eod.done. Called after
-- every action (C.ReadyDone has the conditions).
function E.CheckDone(bomb)
    local st = bomb.eod
    if not C.ReadyDone(st) then return end
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

-- E.Reading(st, i) -> string: what the probe says about wire i now (C.Reading).
-- st.covered must be set first (OPS[4] does) for the JAMMED reading.
function E.Reading(st, i) return C.Reading(st, i, CurTime()) end

-- Play an outcome from the circuit rules: a new timer end onto the
-- bomb's readout, its log lines to ply, then the detonation if any.
-- Returns true if the bomb went off.
local function apply(bomb, ply, o)
    if o.timerEnd then bomb:SetNW2Float("rhylib_eodEnd", o.timerEnd) end
    for _, l in ipairs(o.lines) do msg(ply, l[1], l[2]) end
    if o.boom then return fail(bomb, o.boom) end
    return false
end

-- Wirecutters on wire i (rules: C.Cut). Every cut jolts the tilt bubble
-- and heats a fused board. Returns true if the bomb went off.
local function cutWire(bomb, ply, i)
    local o = C.Cut(bomb.eod, i, CurTime())
    if apply(bomb, ply, o) then return true end
    if not o.cut then return end
    jolt(bomb, ply, 0.12)
    if addHeat(bomb, ply, E.Cfg("heatCut")) then return true end
    return false
end

--------------------------------------------------------------------------
-- Window and actions
--------------------------------------------------------------------------

-- Close enough to work on it: reach + 40 units of slack for movement.
local function near(ply, bomb)
    local r = E.Cfg("reach")
    return IsValid(bomb) and bomb.eod and IsValid(ply) and ply:Alive() and ply:GetPos():DistToSqr(bomb:GetPos()) <= (r + 40) ^ 2
end

-- E.OpenFor(ply, bomb): open the defusal window for ply (adds them to
-- the viewers and sends the view). Needs them within reach. Server.
-- E.CloseFor(ply, bomb): take them off the viewers and close their window.
-- Example: Rhylib.EOD.OpenFor(ply, bomb)
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

-- The client closed its window (bomb entity).
Net.Receive("eod.close", function(ply)
    local bomb = net.ReadEntity()
    if IsValid(bomb) and bomb.eod then
        bomb.eod.viewers[ply] = nil
        if bomb.eod.torchBy == ply then bomb.eod.torchBy = nil E.Changed(bomb) end
    end
end, { rate = 10, burst = 10 })

-- Window actions, by op number (net eod.act). Each gets (ply, bomb, a, b,
-- c, d) with the arguments read in the receiver below; the receiver has
-- already checked the player is near, is a viewer, and the bomb isn't
-- over (or done, except op 15). Return "noSend" to skip the state resend
-- (the probe answers on its own). A new module action takes the next
-- free op (16 needs the op field to grow past 4 bits on both sides).
local OPS = {}

-- 0 / 1: first inspection, a hold. 0 = started, 1 = finished; the server
-- checks at least 90% of inspectTime passed between them.
OPS[0] = function(ply, bomb) ply.eodInspect = { bomb = bomb, t = CurTime() } end

OPS[1] = function(ply, bomb)
    local st = bomb.eod
    local need = E.Cfg("inspectTime")
    local ins = ply.eodInspect
    ply.eodInspect = nil
    if st.inspected or not ins or ins.bomb ~= bomb or CurTime() - ins.t < need * 0.9 then return end
    st.inspected = true
    msg(ply, "First inspection done")
end

-- 2: release the lid-switch tab.
OPS[2] = function(ply, bomb)
    local st = bomb.eod
    if not E.HasKit(ply) or st.open then return end
    st.lidReleased = true
    msg(ply, st.f.lid and "Lid-switch tab released" or "There's no lid switch on this one")
end

-- 3: lift the lid (lid switch not released -> boom). Starts the tilt bubble.
OPS[3] = function(ply, bomb)
    local st = bomb.eod
    if not E.HasKit(ply) or st.open then return end
    if st.f.lid and not st.lidReleased then return fail(bomb, "lid") end
    st.open = true
    st.tech = ply
    if st.tilt then st.tilt.t0 = CurTime() end
    msg(ply, "Casing open: the board is exposed")
end

-- The board can be worked on: kit, lid off, fake board cover gone.
-- (the "st.safe and false" part is always false: the board stays
-- workable after the detonator is cut)
local function boardReady(ply, st)
    if not E.HasKit(ply) then msg(ply, "You need an EOD kit", true) return false end
    if not st.open or st.safe and false then return false end
    if st.fake and not st.fake.removed then msg(ply, "The board cover is still on") return false end
    return true
end

-- 4: probe wire i -> eod.read (wire index 5 bits, reading) to this player only.
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

-- 5: cut wire i (see cutWire).
OPS[5] = function(ply, bomb, i)
    local st = bomb.eod
    if not boardReady(ply, st) then return end
    cutWire(bomb, ply, i)
end

-- 6: jumper from part index pa (terminal pola: true = +) to part pb
-- (polb). Both parts need terminals. Same part = a short (C.Short),
-- two parts = C.Jump. Uses one jumper even if nothing happens.
OPS[6] = function(ply, bomb, pa, pola, pb, polb)
    local st = bomb.eod
    if not boardReady(ply, st) then return end
    local A, B = st.parts[pa], st.parts[pb]
    if not (A and B and A.term and B.term) or (pa == pb and pola == polb) then return end
    if st.jumpers <= 0 then msg(ply, "No jumper wires left", true) return end
    st.jumpers = st.jumpers - 1
    st.jumps[#st.jumps + 1] = { a = pa, pa = pola, b = pb, pb = polb }
    local o
    if pa == pb then o = C.Short(st, A.id, CurTime()) else o = C.Jump(st, A.id, B.id, CurTime()) end
    if apply(bomb, ply, o) then return end
    jolt(bomb, ply, 0.16)
    addHeat(bomb, ply, E.Cfg("heatJumper"))
end

-- 7: nudge the tilt bubble (dx, dy each -1..1; 0.14 per nudge, offsets kept within ±3).
-- (no resend needed for the nudging client: it moved its own copy; the
-- resend still goes out so other viewers see it)
OPS[7] = function(ply, bomb, dx, dy)
    local st = bomb.eod
    if not (st.tilt and st.open) or st.safe then return end
    st.tilt.nx = math.Clamp(st.tilt.nx + dx * 0.14, -3, 3)
    st.tilt.ny = math.Clamp(st.tilt.ny + dy * 0.14, -3, 3)
end

-- 8: torch on (true) / off (false) on the sealed plate. The world timer
-- does the cutting and heating while st.torchBy is set.
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

-- 9: logic chip switches, a "0101" string. Wrong -> boom; right -> safe
-- mode (+10 heat on a fused board).
OPS[9] = function(ply, bomb, sw)
    local st = bomb.eod
    if not (st.chip and st.open) or st.chip.ok or not E.HasKit(ply) then return end
    if apply(bomb, ply, C.Chip(st, sw)) then return end
    addHeat(bomb, ply, 10)
end

-- 10: open the liquid charge's drain valve. Still powered -> boom;
-- needle outside band - 2 .. band + 16 (2 units of slack each side of
-- the 14-wide green band) -> boom.
OPS[10] = function(ply, bomb)
    local st = bomb.eod
    if not (st.liquid and st.open) or st.liquid.drained or not E.HasKit(ply) then return end
    -- (a little slack for latency: the needle moves ~10%/0.1 s at most)
    local now = CurTime()
    apply(bomb, ply, C.Drain(st, now, now - math.min(0.25, ply:Ping() / 1000)))
end

-- 11: X-ray the fake board: eod.xray to this player only (the order is
-- never in the shared view).
OPS[11] = function(ply, bomb)
    local st = bomb.eod
    if not (st.fake and st.open) or st.fake.removed or st.fake.xrays <= 0 or not E.HasKit(ply) then return end
    st.fake.xrays = st.fake.xrays - 1
    local secs = E.Cfg("xrayTime")
    Net.Start("eod.xray")
    net.WriteEntity(bomb)
    for k = 1, 3 do net.WriteUInt(st.fake.order[k], 2) end
    net.WriteFloat(secs)
    net.Send(ply)
    msg(ply, "X-ray: the mount order shows for " .. secs .. " s")
end

-- 12: cut fake board mount m (1-3). Out of order -> boom; +20 heat on a
-- fused board; all three cut -> the cover comes off.
OPS[12] = function(ply, bomb, m)
    local st = bomb.eod
    if not (st.fake and st.open) or st.fake.removed or not E.HasKit(ply) or st.fake.cut[m] == nil or st.fake.cut[m] then return end
    if apply(bomb, ply, C.Mount(st, m)) then return end
    jolt(bomb, ply, 0.1)
    if addHeat(bomb, ply, 20) then return end
    if st.fake.n >= 3 then
        st.fake.removed = true
        msg(ply, "Fake board lifted: the real board is underneath")
    end
end

-- 13: inject the stabiliser, q quarters of a ml (5 bits). Only after the
-- detonator is cut; any other dose -> boom.
OPS[13] = function(ply, bomb, q)
    local st = bomb.eod
    if not st.stab or not st.safe or st.stab.done or not E.HasKit(ply) then return end
    apply(bomb, ply, C.Stab(st, q))
end

-- 14: seal the gas valve (gas / virus charges, after the detonator cut).
-- Needs an EOD kit, like every other step on the board.
OPS[14] = function(ply, bomb)
    local st = bomb.eod
    if not st.safe or st.f.charge == "he" or st.gasSealed then return end
    if not E.HasKit(ply) then msg(ply, "You need an EOD kit", true) return end
    st.gasSealed = true
    st.leakEnd = nil
    msg(ply, "Valve sealed")
end

-- 15: Render safe skill (eod_render): take the charge from a finished
-- bomb as rhylib_he_charge items (1, or 2 from a big bomb), once; never
-- from a training bomb.
-- Needs rhylib_republic (the item) and rhylib_inventory.
OPS[15] = function(ply, bomb)
    local st = bomb.eod
    -- Never from training bombs (anyone can re-arm those: endless charges).
    if not st.done or st.recovered or bomb.IsTrainingBomb or not E.Skill(ply, "eod_render") then return end
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.AddOrDrop and Rhylib.Items and Rhylib.Items.Get("rhylib_he_charge")) then return end
    st.recovered = true
    local n = st.big and 2 or 1
    Inv.AddOrDrop(ply, "rhylib_he_charge", n)
    msg(ply, "Recovered the charge: " .. n .. " high explosive charge" .. (n == 1 and "" or "s"))
end

-- net eod.act: bomb entity, op (4 bits), then by op:
--   4, 5   wire index (5 bits)
--   6      part A index (4 bits), A plus (bool), part B index (4 bits), B plus (bool)
--   7      dx (signed 3 bits), dy (signed 3 bits), clamped to -1..1
--   8      on (bool)        9   switches (string, 4 chars)
--   12     mount (2 bits)   13  dose in quarter ml (5 bits)
--   others nothing
-- Rate limit 20 per second per player.
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
