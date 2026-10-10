--[[
    EOD (owner 2026-10-09): enemy bombs placed by the GM, defused by
    players. Each bomb is a small simulated circuit built from parts and
    rules, so players learn the rules, not one answer:

      detonator   timer / remote (receiver + antenna, frequency, may hop)
      battery     single / dual / capacitor / collapse circuit
      charge      explosive / poison gas / virus; may be self-powered
                  (own cell + sensor: fires if the bomb's power stops)
      safeguards  anti-jam (jamming = signal lost = boom), motion sensor
                  (normal / sensitive), lid switch, tamper loop
      board       wires between the parts, random colours, decoys

    Modules on top (rank = difficulty; a small bomb gets up to 3 points
    and 2 modules, a large one 6 points and 3; simplified bombs none; a GM
    custom bomb can have all): thermal fuse 1, charge stabiliser 1, tilt
    switch 2, sealed compartment 2, signal relay 2 (remote only), logic
    chip 3, liquid charge 3, fake board 3.

    Tools: the EOD kit item (probe, wirecutters, jumper wires, torch),
    the interference device item (placed, cell powered, wideband or tuned
    to one frequency; it also jams your own side's radio and compass in
    wideband), droid poppers (10% to fry a bomb).

    Files: sv_10_bomb (state, rules, nets), sv_20_world (timer: motion
    sensors, interference, timers, detonation, gas, EMP, GM), sv_30_mines,
    sv_35_repmines, cl_10_window (defusal window), cl_20_gm, cl_30_device,
    cl_40_manual (datapad tab), cl_50_mines, cl_55_repmines, cl_60_training.

    This file (shared, loads first): config module "eod", the shared
    tables both sides read (E.MODS, E.TIERS, E.CHIP_CODES, E.COLOURS,
    E.CAUSES), the permission rhylib.eod.gm, the eod_kit and
    eod_interference items, ammo cabinet stock, the toolgun entries, and
    the maths the server and the client must agree on (tilt bubble,
    liquid needle, mine needle, scanner direction, cell life). It also
    holds the "click" that freezes a player who steps on a mine
    (StartCommand / SetupMove), since that has to run on both sides.
]]

Rhylib.EOD = Rhylib.EOD or {}
local E = Rhylib.EOD
local Config = Rhylib.Config

local function reg(k, v, d) Config.Register("eod", k, v, d) end
-- E.Cfg(key): the current value of an "eod" config key (shared).
-- Read on demand, so changes from Server settings apply at once.
-- Example: local r = Rhylib.EOD.Cfg("smallRadius")
function E.Cfg(k) return Config.Get("eod", k) end

reg("smallRadius", 600, "Small bomb blast radius (units)")
reg("smallDamage", 300, "Small bomb blast damage at the centre")
reg("largeRadius", 7000, "Large bomb radius (units; ~a quarter of a big map)")
reg("largeKill", 2200, "Large bomb: inside this radius everything dies, walls or not")
reg("largeDamage", 450, "Large bomb: damage just outside the kill radius (falls off to 0 at largeRadius; halved behind cover)")
reg("gasRadius", 550, "Gas and virus charges: cloud radius (units)")
reg("gasTime", 25, "Gas and virus charges: seconds the cloud lasts")
reg("gasLoad", 35, "Gas and virus charges: illness load given (rhylib_medical; simplified medical: damage instead)")
reg("sensorRange", 315, "Motion sensors: range (units, ~6 m)")
reg("timerWake", 900, "Timer bombs start counting once a player comes this close (units), unless the GM starts them")
reg("capDrain", 15, "Capacitor: seconds to drain after the supply is cut")
reg("jumpers", 3, "Jumper wires per bomb")
reg("xrays", 2, "Fake board: X-ray shots per bomb")
reg("xrayTime", 5, "Fake board: seconds the X-ray shows the mount order")
reg("inspectTime", 2.5, "Seconds to hold for the first inspection")
reg("reach", 130, "How close you must be to work on a bomb (units)")
reg("heatCut", 24, "Thermal fuse: heat per cut")
reg("heatJumper", 30, "Thermal fuse: heat per jumper")
reg("heatTorch", 26, "Torch heat per second (sealed compartment)")
reg("heatCool", 9, "Heat lost per second")
reg("torchTime", 5, "Seconds of torching to cut the sealed plate open")
reg("leakTime", 20, "Gas charges: seconds to seal the valve after cutting the detonator line")
reg("hopEvery", 25, "Frequency hopping receivers: seconds between hops")
reg("popperChance", 0.1, "Chance a droid popper's EMP fries a bomb")
reg("deviceMaxRadius", 15, "Interference device: largest radius (metres)")
reg("deviceDrain", 3840, "Interference device: one cell lasts this / radius² seconds in wideband (×4 tuned), at most 900 s (×4)")
reg("modelSmall", "models/props/starwars/weapons/seismic_charge.mdl", "Small, simplified and training bomb model (HL2 console box if missing)")
reg("modelLarge", "models/cire992/props2/gethbomb01.mdl", "Large and custom bomb model (HL2 power box if missing)")
reg("modelDevice", "models/props_lab/reciever01a.mdl", "Interference device model")
-- Mines (2026-10-09y)
reg("apRadius", 260, "AP mine: blast radius (units)")
reg("apDamage", 170, "AP mine: blast damage at the centre")
reg("lapRadius", 420, "LAP mine (large AP): blast radius (units)")
reg("lapDamage", 320, "LAP mine: blast damage at the centre")
reg("apTrigger", 26, "AP mine: how close a foot must come to press it (units)")
reg("lapTrigger", 38, "LAP mine: how close a foot must come to press it (units)")
reg("mineShift", 16, "Standing on a mine: moving further than this (units) sets it off")
reg("mineVisible", 240, "Mines: how close you see one without a scanner (units)")
reg("mineDigTime", 3, "Mines: seconds to dig one out")
reg("mineLiftTime", 2, "Mines: seconds to lift a pinned mine away")
reg("mineScanRange", 700, "Mine scanner: reach of its beam (units)")
reg("mineScanCone", 22, "Mine scanner: half-angle of its beam (degrees)")
reg("mineModel", "models/props/starwars/weapons/ap_mine.mdl", "AP mine model (HL2 hopper mine if missing)")
reg("mineModelLarge", "models/props/starwars/weapons/lasertrap.mdl", "LAP (large AP) mine model (HL2 hopper mine if missing)")
reg("mineSize", 20, "AP mine: width it is drawn at (units; the model is scaled to fit, LAP ×1.4)")
reg("mineChain", 140, "Mines: another mine within this (units) of an explosion goes off too")
-- Republic mines (EOD Republic mines skill, 2026-10-10)
reg("repDamage", 260, "Republic mine: blast damage to droids at the centre")
reg("repRadius", 280, "Republic mine: blast radius (units; Minefield ×repFieldRadius)")
reg("repTrigger", 45, "Republic mine: how close a droid must come to set it off (units)")
reg("repLimit", 3, "Republic mines: how many one player may have out")
reg("repLimitField", 6, "Republic mines: how many with the Minefield skill")
reg("repFieldRadius", 1.3, "Republic mines: blast radius multiplier with Minefield")

-- Item / weapon class names used across the addon.
E.KIT = "eod_kit"                       -- item: needed to open and work on a bomb or mine
E.SCANNER = "rhylib_mine_scanner"       -- weapon
E.DEVICE = "eod_interference"           -- item: placed as rhylib_interference_dev
E.ARMORKIT = "rhylib_armor_kit"         -- weapon (item via its Inv fields)
E.LAUNCHER = "rhylib_grenade_launcher"  -- weapon in rhylib_republic (named here for reference)
E.RMINE = "rhylib_rep_mine"             -- weapon: the Republic mine stack
E.UNITS_PER_M = 52.5                    -- Source units per metre (as everywhere in Rhylib)
E.F0, E.F1 = 2400, 2480   -- frequency band (MHz) on the scanner

-- Modules: id, name, rank (difficulty), remote = only on remote bombs.
-- The order here is the order they show in the GM / training builders
-- and the manual. To add a module: add a row here, give it state in
-- E.Build (sv_10_bomb), rules (an OPS entry and/or a check in cutWire),
-- a section in cl_10_window's buildLeft, a CAUSES entry for each way it
-- can fire, and steps in cl_40_manual's MODULE_STEPS. See the guide
-- docs/addons/rhylib_eod.md "Adding a module".
-- (index is filled in below; E.MOD_BY[id] finds a row by id)
E.MODS = {
    { id = "fuse", name = "Thermal fuse", rank = 1 },
    { id = "stab", name = "Charge stabiliser", rank = 1 },
    { id = "tilt", name = "Tilt switch", rank = 2 },
    { id = "sealed", name = "Sealed compartment", rank = 2 },
    { id = "relay", name = "Signal relay", rank = 2, remote = true },
    { id = "chip", name = "Logic chip", rank = 3 },
    { id = "liquid", name = "Liquid charge", rank = 3 },
    { id = "fake", name = "Fake board", rank = 3 },
}
E.MOD_BY = {}
for i, m in ipairs(E.MODS) do m.index = i E.MOD_BY[m.id] = m end

-- Bomb types. budget = module points (sum of ranks) a random roll may
-- spend, max = most modules, name = shown in windows and over the bomb,
-- big = large-bomb blast (kill radius, quarter-map damage), big model,
-- 3× gas cloud and a 240 s default timer (else 180; simplified 150).
-- custom and training features come from a builder (or a "large" /
-- "small" roll when first placed), so their budget and max are never
-- read: a builder may pick every module.
E.TIERS = {
    simple = { budget = 0, max = 0, name = "Simplified bomb", big = false },
    small = { budget = 3, max = 2, name = "Small bomb", big = false },
    large = { budget = 6, max = 3, name = "Large bomb", big = true },
    custom = { budget = 99, max = 99, name = "Custom bomb", big = true },
    training = { budget = 99, max = 99, name = "Training bomb", big = false },
}

-- Logic chip: blink pattern (S short, L long) -> switch setting.
-- A bomb stores the row number (st.chip.code); the player sends the four
-- switches as a "0101" string (net eod.act op 9) and it must match [2].
E.CHIP_CODES = {
    { "SSS", "1010" }, { "SSL", "0110" }, { "SLS", "1100" }, { "SLL", "0011" },
    { "LSS", "1001" }, { "LSL", "0101" }, { "LLS", "1110" }, { "LLL", "0111" },
}
-- E.ChipText(pattern): "SLS" -> "· — · " (dots and dashes for windows).
function E.ChipText(p) return (string.gsub(string.gsub(p, "S", "· "), "L", "— ")) end

-- Wire colours (index on the wire, random per bomb). { name, Color }.
-- E.Build shuffles all 16 and hands them out, so a board never repeats a
-- colour unless it has more than 16 wires.
E.COLOURS = {
    { "Red", Color(229, 72, 77) }, { "Blue", Color(62, 142, 247) }, { "Yellow", Color(245, 217, 10) },
    { "Green", Color(70, 167, 88) }, { "White", Color(236, 239, 241) }, { "Black", Color(53, 59, 65) },
    { "Orange", Color(247, 107, 21) }, { "Purple", Color(164, 110, 224) },
    { "Pink", Color(240, 130, 190) }, { "Brown", Color(140, 90, 50) }, { "Grey", Color(140, 146, 152) },
    { "Cyan", Color(60, 210, 220) }, { "Lime", Color(170, 230, 60) }, { "Navy", Color(40, 60, 150) },
    { "Teal", Color(30, 140, 130) }, { "Maroon", Color(130, 30, 50) },
}

-- Detonation causes: title, what happened, what the manual says.
-- The key is the cause string passed to E.Detonate / E.MineBoom and sent
-- in net eod.boom; the client shows [1] and [2] on the fail overlay and
-- [3] as "Manual: ...". cl_40_manual lists them in "Why bombs go off"
-- (add a new key to its list there too). An unknown key shows as "gm".
E.CAUSES = {
    motion = { "Motion sensor", "Someone moved too fast inside the bomb's motion sensor range.", "Walk inside 6 m (crouch-walk for a sensitive sensor), or blind the sensor with a wideband interference device." },
    antijam = { "Anti-jam safeguard", "An interference device blocked the bomb's remote signal, and its anti-jam safeguard fires when the signal is lost.", "Inspect before jamming. With anti-jam, cut the MON line first, or redirect a relay." },
    lid = { "Lid switch", "Lifting the lid closed the lid switch.", "Release the lid-switch tab before lifting the lid." },
    collapse = { "Collapse circuit", "The supply was cut while the collapse circuit was armed.", "Cut the collapse sense line (LOOP 3V) before the battery supply." },
    feed = { "Capacitor discharge", "The capacitor feed still carried charge when it was cut.", "Cut the supply and wait for the capacitor to drain under 5% (or short it) first." },
    det = { "Live detonator line", "The detonator line still had power when it was cut.", "Every supply cut, any capacitor drained: the probe must read DEAD." },
    tmrline = { "Timer line", "The timer line still had battery power when it was cut.", "Kill the supply first." },
    antenna = { "Anti-jam safeguard", "Cutting the antenna counts as losing the signal, and the anti-jam safeguard was armed.", "Cut the anti-jam monitor line (MON) first." },
    timer = { "Timer ran out", "The timer reached zero.", "Cutting the supply stops the timer. Cutting the tamper loop halves what's left." },
    remote = { "Remote detonation", "The remote signal reached a live receiver.", "Jam it (if there's no anti-jam), cut the antenna lead or redirect the relay early." },
    sensor = { "Self-powered charge", "The bomb's power stopped while the charge's sensor was armed, so it fired on its own cell.", "Short the charge cell (jumper + to −) before cutting or shorting the supply or the SENSE line." },
    capshort = { "Capacitor surge", "The capacitor was shorted while the battery supply was live.", "Cut the supply first, then short the capacitor." },
    detshort = { "Detonator shorted", "A powered detonator was shorted. That's the same as firing it.", "Only touch the detonator once it reads DEAD." },
    jumpdet = { "Power into the detonator", "A jumper fed a live source straight into the detonator.", "Never jumper a battery or charged capacitor to the detonator." },
    relayshort = { "Signal relay", "The relay was shorted, latched closed and fired the detonator.", "Jumper the relay to the dummy load, never to itself." },
    relaydet = { "Signal relay", "The relay's signal was jumpered straight into the detonator.", "The relay goes to the dummy load." },
    tilt = { "Tilt switch", "The bubble reached the edge of the level.", "Keep nudging it back to the middle. Cuts and jumpers jolt it." },
    heat = { "Overheated", "The board went past 100°.", "Pause between cuts and torch in short bursts so it cools." },
    chip = { "Logic chip", "The logic chip was still armed when its line or the detonator line was cut.", "Set the chip's switches from its blink code first." },
    chipwrong = { "Wrong chip code", "The switch setting didn't match the chip's blink code.", "Count the short and long blinks, then check the table in the manual." },
    liquid = { "Liquid charge foamed", "The drain valve opened while the pressure was outside the green band.", "Wait until the needle sits in the green band." },
    liquidpower = { "Liquid charge pump", "The liquid charge was drained while the bomb still had power.", "Cut every supply first." },
    liquidfull = { "Liquid charge", "The detonator line was cut with the liquid charge still full.", "Drain the liquid charge before the detonator line." },
    fake = { "Fake board", "The cover's mounts were cut in the wrong order.", "Take an X-ray and cut the mounts in the numbered order." },
    stab = { "Unstable charge", "The stabiliser dose didn't match the charge label.", "Inject exactly the dose printed on the charge." },
    leak = { "Gas leak", "The canister vented before the valve was sealed.", "Seal the valve straight after cutting the detonator line." },
    gm = { "Detonated", "The game master set it off.", "" },
    mine = { "Mine", "Someone stepped off a pressed mine (or moved on it).", "Freeze the moment it clicks. Someone with an EOD kit digs it out and pins the fuse." },
    minepin = { "Mine fuse", "The safety pin went in at the wrong moment.", "Push the pin while the needle is inside the marked zone." },
}

-- E.Skill(ply, id): true if ply has the rhylib_skills node id (Field
-- technician path on the Specialist page; category id "airborne").
-- False without rhylib_skills. Shared. No skill makes defusing easier;
-- skills only unlock extras (manual, Render safe recovery, Republic
-- mines, Minefield, Signal blackout).
-- Example: if Rhylib.EOD.Skill(ply, "eod_manual") then ... end
function E.Skill(ply, id)
    local K = Rhylib.Skills
    return K and K.Has and IsValid(ply) and K.Has(ply, id) or false
end

-- Permission for the GM window and the EOD toolgun entries (default rank
-- admin; rhylib_admin's gamemaster rank also has it by default).
if Rhylib.Perms and Rhylib.Perms.Register then
    Rhylib.Perms.Register("rhylib.eod.gm", "admin", "Set up, re-roll, start, signal and detonate EOD bombs")
end

-- Items (rhylib_inventory loads after us: also on Rhylib.ModuleLoaded).
local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) then return end
    if not Items.Get(E.KIT) then
        Items.Register(E.KIT, {
            name = "EOD kit", w = 2, h = 1, weight = 1.5, category = "gear", group = "gear",
            desc = "Probe, wirecutters, jumper wires and a torch. Press E on a bomb to work on it.",
            model = "models/props_c17/BriefCase001a.mdl",
        })
    end
    if not Items.Get(E.DEVICE) then
        Items.Register(E.DEVICE, {
            name = "Interference device", w = 2, h = 2, weight = 3, category = "gear", group = "gear",
            desc = "Right-click: place it. Blocks remote signals (and, wideband, motion sensors and your own side's radio) in a circle. Runs on a power cell.",
            model = "models/props_lab/reciever01a.mdl",
        })
    end
end
registerItems()
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "eod.items", function(id) if id == "inventory" then registerItems() end end)

-- Ammo cabinet stock (rhylib_armoury loads before us).
do
    local A = Rhylib.Armoury
    if A and A.AMMO_STOCK then
        for _, id in ipairs({ E.KIT, E.DEVICE, E.SCANNER, E.ARMORKIT, E.RMINE }) do
            if not table.HasValue(A.AMMO_STOCK, id) then A.AMMO_STOCK[#A.AMMO_STOCK + 1] = id end
        end
    end
end

-- E.CellLife(radiusM, tuned, longCells): seconds one full cell lasts in
-- an interference device at that radius (metres). Wideband:
-- deviceDrain / r², at most 900 s; tuned ×4; longCells ×1.5 (a leftover
-- from the old Signal discipline skill: the server always passes false
-- now). Shared (the device window shows it).
-- Example: E.CellLife(5, false) -> 153.6   (3840 / 25)
function E.CellLife(radiusM, tuned, longCells)
    local k = (tuned and 4 or 1) * (longCells and 1.5 or 1)
    return math.min(900 * k, (E.Cfg("deviceDrain") or 3840) * k / math.max(1, radiusM) ^ 2)
end

-- Shared maths (the server's rules and the client's window agree).

-- Tilt switch: three sines per axis (from the moment the lid came off)
-- plus the player's nudges; past radius 1 it fires.
-- Both sides compute the same position from the same numbers (amplitudes
-- a, speeds w, phases p, start time t0, nudge offsets nx/ny sent in the
-- view), so the bubble moves smoothly on the client without the server
-- streaming it. Each sine is shifted by -sin(p) so it starts at 0.
local function sineAt(s, dt)
    local v = 0
    for i = 1, 3 do v = v + s.a[i] * (math.sin(s.w[i] * dt + s.p[i]) - math.sin(s.p[i])) end
    return v
end

-- The tilt switch only drifts while someone has the window open.
-- E.TiltResume(st): un-pause the bubble by moving its start time t0 on
-- by how long it was paused. Returns true if it was paused (the caller
-- then resends the view so clients get the new t0).
function E.TiltResume(st)
    local t = st.tilt
    if t and t.t0 and t.pausedAt then
        t.t0 = t.t0 + (CurTime() - t.pausedAt)
        t.pausedAt = nil
        return true
    end
end

-- E.TiltPos(tilt, now) -> x, y: the bubble's position (radius 1 = the
-- edge; the server detonates at x² + y² >= 1). Before the lid comes off
-- (no t0) it is just the nudges.
function E.TiltPos(t, now)
    if not t.t0 then return t.nx, t.ny end
    local dt = (t.pausedAt or now) - t.t0   -- (paused while nobody has the window open)
    return sineAt(t.x, dt) * t.mult + t.nx, sineAt(t.y, dt) * t.mult + t.ny
end

-- Liquid charge: the pressure needle (0-100); the green band is
-- band .. band + 14 (the server allows a little either side).
-- Mine fuse: the needle the safety pin must be pushed against (0-100).
-- Both are plain sines of CurTime(), so client and server agree without
-- any networking; the server checks a moment in the past (the player's
-- ping, at most 0.25 s) to allow for latency.
-- E.MineNeedle(period, phase, now) -> 4..96
function E.MineNeedle(period, ph, now) return 50 + 46 * math.sin(now * 2 * math.pi / period + ph) end

-- E.LiquidNeedle(liquidState, now) -> 3..97 (liquidState = st.liquid or the view's copy)
function E.LiquidNeedle(l, now) return 50 + 47 * math.sin(now * 2 * math.pi / l.period + l.ph) end

-- Toolgun entries (rhylib_toolgun, category "EOD").
-- Entry fields: id, name, cat, class (the entity the toolgun spawns),
-- count = true (the toolgun's count box is used), place = function(ply,
-- tr, n) that spawns the entities itself and returns them (used for
-- mines, which E.PlaceMines buries), perm = the permission that lets a
-- non-staff gamemaster use just these entries. Entries whose class isn't
-- registered are left out.
Rhylib.Hook.Add("Rhylib.ToolEntries", "eod.tool", function(list)
    for _, e in ipairs({
        { id = "eod_simple", name = "Bomb: simplified (timer, lid switch, wires)", cat = "EOD", class = "rhylib_eod_bomb_simple" },
        { id = "eod_small", name = "Bomb: small (random, up to 2 modules)", cat = "EOD", class = "rhylib_eod_bomb" },
        { id = "eod_large", name = "Bomb: large (random, up to 3 modules; quarter-map blast)", cat = "EOD", class = "rhylib_eod_bomb_large" },
        { id = "eod_custom", name = "Bomb: custom (E with the toolgun: pick everything)", cat = "EOD", class = "rhylib_eod_bomb_custom" },
        { id = "mine_ap", name = "Mine: AP (count = scattered mines)", cat = "EOD", class = "rhylib_eod_mine", count = true,
          place = function(ply, tr, n) return E.PlaceMines and E.PlaceMines(tr, n, n > 1 and 40 + n * 22 or 0, 0) end },
        { id = "mine_lap", name = "Mine: LAP, large AP (count = scattered mines)", cat = "EOD", class = "rhylib_eod_mine_lap", count = true,
          place = function(ply, tr, n) return E.PlaceMines and E.PlaceMines(tr, n, n > 1 and 40 + n * 22 or 0, 1) end },
        { id = "minefield", name = "Minefield (14 mines over ~10 m, a few LAP)", cat = "EOD", class = "rhylib_eod_mine",
          place = function(ply, tr) return E.PlaceMines and E.PlaceMines(tr, 14, 520, 0.25) end },
        { id = "minefield_big", name = "Minefield, large (30 mines over ~20 m)", cat = "EOD", class = "rhylib_eod_mine",
          place = function(ply, tr) return E.PlaceMines and E.PlaceMines(tr, 30, 1050, 0.25) end },
        -- Training (nobody gets hurt; set up from their own windows)
        { id = "eod_training", name = "Training bomb (set it up in its window)", cat = "Training", class = "rhylib_eod_bomb_training" },
        { id = "mine_training", name = "Training mine (count = scattered; set up in its window)", cat = "Training", class = "rhylib_eod_mine_training", count = true,
          place = function(ply, tr, n) return E.PlaceMines and E.PlaceMines(tr, n, n > 1 and 40 + n * 22 or 0, 0, "rhylib_eod_mine_training") end },
    }) do
        e.perm = "rhylib.eod.gm"   -- (gamemasters may place these without full toolgun access)
        if scripted_ents.GetStored(e.class) then list[#list + 1] = e end
    end
end)

-- The exposed top of a (half-buried) mine: blasts and sight lines start here.
-- E.MineTop(mine) -> world Vector. Shared.
function E.MineTop(m) return m:LocalToWorld(Vector(0, 0, m:OBBMaxs().z)) end

-- Something that goes away for good in play (a mine that went off or was
-- lifted, a bomb that went off) stays in the permanent map setup: it comes
-- back next map instead of being dropped from the save.
-- E.KeepForNextMap(ent): server. Clears the entity's permanent flag
-- before it is removed, so rhylib_core's Perma "removed: re-save" doesn't
-- drop its row. Call it right before removing a permanent mine or bomb
-- that was used up in play.
function E.KeepForNextMap(e)
    local P = Rhylib.Perma
    if P and P.Is and P.Is(e) then
        e:SetNW2Bool(P.NW, false)
        e.rhylibPerma = nil
    end
end

-- The click: for a moment after stepping on a mine you can't move (so you
-- get the chance to freeze); after that, moving sets it off.
-- Shared and predicted: the server sets NW2Entity rhylib_onMine and
-- NW2Float rhylib_mineAt on the player (sv_30_mines press()); both sides
-- then clear movement input and horizontal speed for E.MINE_GRACE
-- seconds, so the player's own client doesn't keep walking and rubber-band.
E.MINE_GRACE = 0.6
local function clicked(ply)
    return IsValid(ply:GetNW2Entity("rhylib_onMine")) and CurTime() - ply:GetNW2Float("rhylib_mineAt", 0) < E.MINE_GRACE
end
Rhylib.Hook.Add("StartCommand", "eod.mineclick", function(ply, cmd)
    if clicked(ply) then
        cmd:ClearMovement()
        cmd:RemoveKey(IN_JUMP)
    end
end)
Rhylib.Hook.Add("SetupMove", "eod.mineclick", function(ply, mv)
    if clicked(ply) then
        local v = mv:GetVelocity()
        mv:SetVelocity(Vector(0, 0, math.min(v.z, 0)))
    end
end)

-- Mine scanner beam: where you look, but always down at the ground
-- (at least 30° below level).
-- E.ScanDir(ply) -> unit Vector. Shared: the client draws the beam and
-- finds mines with it; the server rechecks marks (net eod.minemark) with it.
function E.ScanDir(ply)
    local a = ply:EyeAngles()
    a.p = math.max(a.p, 30)
    return a:Forward()
end
