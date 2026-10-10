--[[
    Bombs in the world (server): one 0.2 s timer for every bomb and
    interference device (coverage, anti-jam, motion sensors, timers,
    frequency hops, the GM's spotter, tilt, torch, gas leaks, viewers),
    detonation (blast, large-bomb kill radius, gas and virus clouds),
    remote signals, droid popper EMPs, the GM window's operations and the
    interference device (placing, settings, cell drain, scanner).
    Also the training bomb setup (net eod.train).

    Fires hook Rhylib.Explosion(pos, reach, tier, attacker, inflictor,
    "bomb") when a bomb goes off (mines nearby listen to it). Listens to
    Rhylib.EMP (rhylib_republic droid popper).

    Nets (prefix "rhylib."):
      eod.boom     server -> viewers + players within 2500: bomb index
                   (13 bits), cause (string, an E.CAUSES key), position
      eod.far      server -> everyone: large bomb position, radius (float)
      eod.gas      server -> players within cloud radius + 4000: position,
                   radius, seconds (floats), virus (bool)
      eod.gmopen   server -> GM: bomb, note (string), len (16 bits),
                   compressed JSON of gmInfo (the answers)
      eod.gm       GM -> server: bomb, op (4 bits), op 4 JSON string,
                   op 7 / 9 seconds (11 bits); rate 8/s
      eod.dev      server -> player: device entity (open its window)
      eod.devscan  server -> device viewers: device, count (4 bits), then
                   per receiver: freq - 2400 (7 bits), strength 1-100
                   (7 bits), hops (bool)
      eod.place    client -> server: item uid (Items.UID_BITS); rate 3/s
      eod.devset   client -> server: device, op (3 bits), argument; rate 12/s
      eod.train    client -> server: training bomb, op (3 bits), op 0 JSON
      eod.trainopen server -> player: training bomb, len (16 bits),
                   compressed JSON of its feature table f
]]

local E = Rhylib.EOD
local Net = Rhylib.Net

for _, n in ipairs({ "eod.dev", "eod.devscan" }) do Net.Register(n) end

E.devices = E.devices or {}   -- [interference device entity] = true
E.clouds = E.clouds or {}     -- list of gas / virus clouds { pos, kind, r, untilT, hit = { [ply] = true } }

local function walkOk(p) return IsValid(p) and p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP end

-- E.Powered(st) -> bool: a battery or a capacitor at 5%+ still feeds it.
local function powered(st) return E.AnySupply(st) or E.CapNow(st) >= 5 end
E.Powered = powered

--------------------------------------------------------------------------
-- Setting up a bomb (entities call this in Initialize)
--------------------------------------------------------------------------

-- The 3D2D readout on the bomb (entity file) reads these NW2 vars:
-- rhylib_eodEnd (running timer's end time, 0 = not running),
-- rhylib_eodLeft (seconds shown while not running), rhylib_eodStop
-- (stopped: no power). Only set when they change (cached on the entity).
-- E.SyncDisplay(bomb).
local function syncDisplay(bomb)
    local st = bomb.eod
    local endT, left, stop = 0, 0, false
    if st.timerSecs then
        if st.timerEnd then endT = st.timerEnd
        else
            left = st.timerLeft or st.timerSecs
            stop = st.timerStopped or false
        end
    end
    if bomb.eodShowEnd ~= endT then bomb.eodShowEnd = endT bomb:SetNW2Float("rhylib_eodEnd", endT) end
    if bomb.eodShowLeft ~= left then bomb.eodShowLeft = left bomb:SetNW2Float("rhylib_eodLeft", left) end
    if bomb.eodShowStop ~= stop then bomb.eodShowStop = stop bomb:SetNW2Bool("rhylib_eodStop", stop) end
end
E.SyncDisplay = syncDisplay

-- E.SetupBomb(bomb, f): give an entity a bomb state built from features f
-- (E.Build), register it in E.bombs, set its NW2 vars (rhylib_eodKind,
-- rhylib_eodTimer, rhylib_eodSafe) and the model for its size. Server.
-- Doesn't close open windows: use E.Rebuild on a bomb already in play.
-- Example: local f = Rhylib.EOD.Roll("small") f.mods.chip = true
--          Rhylib.EOD.SetupBomb(ent, f)
function E.SetupBomb(bomb, f)
    local st = E.Build(f)
    st.armAt = CurTime() + 4   -- (motion sensors wait a moment: the GM just placed it)
    bomb.eod = st
    E.bombs[bomb] = true
    bomb.eodShowEnd, bomb.eodShowLeft, bomb.eodShowStop = nil, nil, nil
    bomb:SetNW2String("rhylib_eodKind", st.kindName)
    bomb:SetNW2Bool("rhylib_eodTimer", st.timerSecs ~= nil)
    bomb:SetNW2Bool("rhylib_eodSafe", false)
    local mdl = E.Cfg(st.big and "modelLarge" or "modelSmall")
    if not (isstring(mdl) and util.IsValidModel(mdl)) then mdl = st.big and "models/props_lab/powerbox01a.mdl" or "models/props_c17/consolebox01a.mdl" end
    if bomb:GetModel() ~= mdl then
        bomb:SetModel(mdl)
        bomb:PhysicsInit(SOLID_VPHYSICS)
        local ph = bomb:GetPhysicsObject()
        if IsValid(ph) then ph:EnableMotion(false) end
    end
    syncDisplay(bomb)
    if bomb.IsTrainingBomb then E.ArmedBeep(bomb) end
end

-- Training bombs: a rising two-tone beep each time they (re)arm.
-- E.ArmedBeep(ent): also used by training mines (sv_30_mines).
function E.ArmedBeep(ent)
    if not IsValid(ent) then return end
    -- Delayed a moment: a bomb set up in Initialize isn't on clients yet.
    local id = "Rhylib.EOD.Armed." .. ent:EntIndex()
    timer.Create(id, 0.15, 1, function()
        if not IsValid(ent) then return end
        ent:EmitSound("buttons/blip1.wav", 75, 90)
        timer.Create(id, 0.18, 1, function()
            if IsValid(ent) then ent:EmitSound("buttons/blip1.wav", 75, 130) end
        end)
    end)
end

-- GM re-roll / new type: close every window, new state in place.
-- E.Rebuild(bomb, f). Example: Rhylib.EOD.Rebuild(bomb, Rhylib.EOD.Roll("large"))
function E.Rebuild(bomb, f)
    local old = bomb.eod
    if old then
        for p in pairs(old.viewers) do
            if IsValid(p) then E.CloseFor(p, bomb) end
        end
    end
    E.SetupBomb(bomb, f)
end

--------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------

-- E.StartTimer(bomb, secs) -> bool: start (or resume) a timer bomb's
-- countdown, from secs or what it had left. False if it has no timer,
-- is safe or over, or has no battery supply (a capacitor alone doesn't
-- run the clock). Normally the world timer starts it when a player
-- comes within timerWake.
-- E.PauseTimer(bomb) -> bool: GM pause; it then waits (gmHeld) until the
-- GM starts it again, never waking on its own.
function E.StartTimer(bomb, secs)
    local st = bomb.eod
    if not st.timerSecs or st.over or st.safe or not E.AnySupply(st) then return false end
    st.timerWaiting = false
    st.timerStopped = false
    st.timerEnd = CurTime() + (secs or st.timerLeft or st.timerSecs)
    st.timerLeft = nil
    syncDisplay(bomb)
    E.Changed(bomb)
    return true
end

function E.PauseTimer(bomb)
    local st = bomb.eod
    if not st.timerEnd then return false end
    st.timerLeft = math.max(0, st.timerEnd - CurTime())
    st.timerEnd = nil
    st.timerWaiting = true   -- (waits again until the GM resumes it: gmHeld stops the wake-up)
    st.gmHeld = true
    syncDisplay(bomb)
    E.Changed(bomb)
    return true
end

--------------------------------------------------------------------------
-- Detonation
--------------------------------------------------------------------------

-- eod.boom to viewers and everyone within 2500 units (fail overlay or a chat line).
local function sendBoom(bomb, st, pos, cause)
    local rec = {}
    for p in pairs(st.viewers) do if IsValid(p) then rec[p] = true end end
    for _, p in ipairs(player.GetAll()) do
        if p:GetPos():DistToSqr(pos) < 2500 * 2500 then rec[p] = true end
    end
    local list = table.GetKeys(rec)
    if #list == 0 then return end
    Net.Start("eod.boom")
    net.WriteUInt(bomb:EntIndex(), 13)
    net.WriteString(cause or "gm")
    net.WriteVector(pos)
    net.Send(list)
end

-- Who a large bomb can hit: living players, rhylib_droids droids and
-- clones, and every npc_* entity.
local function victims()
    local list = {}
    for _, p in ipairs(player.GetAll()) do if p:Alive() then list[#list + 1] = p end end
    local D = Rhylib.Droids
    if D then
        for e in pairs(D.active or {}) do if IsValid(e) then list[#list + 1] = e end end
        for e in pairs(D.clones or {}) do if IsValid(e) then list[#list + 1] = e end end
    end
    for _, e in ipairs(ents.FindByClass("npc_*")) do list[#list + 1] = e end
    return list
end

local function hurt(e, dmg, bomb, pos)
    local d = DamageInfo()
    d:SetDamage(dmg)
    d:SetDamageType(DMG_BLAST)
    d:SetAttacker(bomb)
    d:SetInflictor(bomb)
    d:SetDamagePosition(pos)
    d:SetDamageForce((e:WorldSpaceCenter() - pos):GetNormalized() * dmg * 300)
    e:TakeDamageInfo(d)
end

-- Small bomb: an ordinary util.BlastDamage (smallRadius / smallDamage).
local function blastSmall(bomb, pos)
    local ed = EffectData()
    ed:SetOrigin(pos)
    util.Effect("Explosion", ed, true, true)
    util.Effect("HelicopterMegaBomb", ed, true, true)
    sound.Play("weapons/explosives_cannons_superlazers/sw_detonator_explosion.ogg", pos, 120, 90)
    local r = E.Cfg("smallRadius") or 600
    util.BlastDamage(bomb, bomb, pos, r, E.Cfg("smallDamage") or 300)
    util.ScreenShake(pos, 12, 150, 1.2, r * 3)
    util.Decal("Scorch", pos + Vector(0, 0, 8), pos - Vector(0, 0, 60), bomb)
end

-- Large bomb: inside largeKill everyone dies, walls or not (players are
-- killed outright, god mode spared; others take 100000). From largeKill
-- out to largeRadius the damage falls in a straight line from
-- largeDamage to 0, halved when a brush is between. util.BlastDamage
-- does only the near props. Everyone on the server gets eod.far.
local function blastLarge(bomb, pos)
    local kill, r = E.Cfg("largeKill") or 2200, E.Cfg("largeRadius") or 7000
    local peak = E.Cfg("largeDamage") or 450
    for i = 0, 5 do
        local ed = EffectData()
        local a = i * 60
        ed:SetOrigin(pos + (i == 0 and vector_origin or Vector(math.cos(math.rad(a)), math.sin(math.rad(a)), 0.3) * 260))
        ed:SetScale(3)
        util.Effect(i == 0 and "HelicopterMegaBomb" or "Explosion", ed, true, true)
    end
    sound.Play("ambient/explosions/explode_" .. math.random(1, 3) .. ".wav", pos, 150, 70)
    sound.Play("weapons/explosives_cannons_superlazers/sw_detonator_explosion.ogg", pos, 150, 65)
    util.ScreenShake(pos, 25, 80, 3, r * 1.5)
    util.BlastDamage(bomb, bomb, pos, 900, 600)   -- (props and close things; the rest below)
    for _, e in ipairs(victims()) do
        if IsValid(e) and e ~= bomb and (not e:IsPlayer() or not e:HasGodMode()) then
            local c = e:WorldSpaceCenter()
            local d = c:Distance(pos)
            if d <= kill then
                if e:IsPlayer() then e:Kill() else hurt(e, 100000, bomb, pos) end
            elseif d < r then
                local dmg = peak * (1 - (d - kill) / (r - kill))
                if util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY }).Hit then dmg = dmg * 0.5 end
                if dmg >= 1 then hurt(e, dmg, bomb, pos) end
            end
        end
    end
    -- everyone hears and feels it
    Net.Start("eod.far")
    net.WriteVector(pos)
    net.WriteFloat(r)
    net.Broadcast()
end

-- Gas and virus clouds: a list checked once a second.
-- E.Cloud(pos, kind, radius, secs): kind "gas" or "virus". Server.
-- With rhylib_medical (not simplified): each player whose eyes are inside
-- gets Med.Infect once per cloud (gas = illness kind 3 poison, virus =
-- kind 1 viral), load gasLoad, raised by half again if they already have
-- that illness (max 100). Otherwise: 5 (gas) / 3 (virus) nerve gas
-- damage per second inside.
-- Example: Rhylib.EOD.Cloud(pos, "gas", 550, 25)
function E.Cloud(pos, kind, radius, secs)
    local c = { pos = pos, kind = kind, r = radius, untilT = CurTime() + secs, hit = {} }
    E.clouds[#E.clouds + 1] = c
    local rec = {}
    for _, p in ipairs(player.GetAll()) do
        if p:GetPos():DistToSqr(pos) < (radius + 4000) ^ 2 then rec[#rec + 1] = p end
    end
    if #rec > 0 then
        Net.Start("eod.gas")
        net.WriteVector(pos)
        net.WriteFloat(radius)
        net.WriteFloat(secs)
        net.WriteBool(kind == "virus")
        net.Send(rec)
    end
end

local function cloudTick()
    local now = CurTime()
    local Med = Rhylib.Medical
    for i = #E.clouds, 1, -1 do
        local c = E.clouds[i]
        if now >= c.untilT then
            table.remove(E.clouds, i)
        else
            local r2 = c.r * c.r
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() and not p:HasGodMode() and p:EyePos():DistToSqr(c.pos) <= r2 then
                    if Med and Med.Simple and not Med.Simple() and Med.Infect then
                        if not c.hit[p] then
                            c.hit[p] = true
                            local kind = c.kind == "virus" and 1 or 3
                            local cur = Med.Illness and Med.Illness(p)
                            local load = E.Cfg("gasLoad") or 35
                            if cur and cur.kind == kind then load = math.max(load, cur.load + load * 0.5) end
                            Med.Infect(p, kind, math.min(100, load))
                        end
                    else
                        local d = DamageInfo()
                        d:SetDamage(c.kind == "virus" and 3 or 5)
                        d:SetDamageType(DMG_NERVEGAS)
                        d:SetAttacker(game.GetWorld())
                        d:SetInflictor(game.GetWorld())
                        p:TakeDamageInfo(d)
                    end
                end
            end
        end
    end
end
timer.Create("Rhylib.EOD.Clouds", 1, 0, cloudTick)

-- E.Detonate(bomb, cause): set the bomb off. cause = an E.CAUSES key
-- (shown to players). Server. HE: small or large blast; gas / virus: a
-- small pop (none for "leak") and a cloud (×3 radius on big bombs).
-- Interference devices within the blast are wrecked. Fires
-- Rhylib.Explosion (reach: largeKill / smallRadius / 180 for gas;
-- tier 3 large, 2 small, 1 gas), then removes the bomb 0.2 s later.
-- A permanent bomb stays in the map save (E.KeepForNextMap).
-- Training bombs: only a spark and the fail overlay, then the same
-- setup again after 3 s.
-- Example: Rhylib.EOD.Detonate(bomb, "gm")
function E.Detonate(bomb, cause)
    if not IsValid(bomb) or not bomb.eod or bomb.eod.over then return end
    local st = bomb.eod
    st.over = true
    local pos = bomb:WorldSpaceCenter()
    sendBoom(bomb, st, pos, cause)
    st.viewers = {}
    -- Training bomb: nobody gets hurt; it re-arms with the same setup.
    if bomb.IsTrainingBomb then
        local ed = EffectData()
        ed:SetOrigin(pos)
        util.Effect("StunstickImpact", ed, true, true)
        sound.Play("buttons/button10.wav", pos, 75, 80)
        sound.Play("ambient/levels/labs/electric_explosion1.wav", pos, 70, 140)
        local f = table.Copy(st.f)
        f.mods = table.Copy(st.f.mods or {})
        timer.Simple(3, function() if IsValid(bomb) and bomb.eod == st then E.SetupBomb(bomb, f) end end)
        return
    end
    bomb:SetNoDraw(true)
    bomb:SetNotSolid(true)
    local charge = st.f.charge
    if charge == "he" then
        if st.big then blastLarge(bomb, pos) else blastSmall(bomb, pos) end
    else
        -- a pop, then the cloud (a leak only vents the cloud)
        if cause ~= "leak" then
            local ed = EffectData()
            ed:SetOrigin(pos)
            util.Effect("Explosion", ed, true, true)
            util.BlastDamage(bomb, bomb, pos, 180, 40)
        end
        sound.Play("ambient/gas/steam2.wav", pos, 90, 80)
        local r = (E.Cfg("gasRadius") or 550) * (st.big and 3 or 1)
        E.Cloud(pos, charge, r, E.Cfg("gasTime") or 25)
    end
    -- interference devices caught in it are wrecked
    local reach = charge == "he" and (st.big and (E.Cfg("largeKill") or 2200) or (E.Cfg("smallRadius") or 600) * 0.6) or 0
    if reach > 0 then
        for dev in pairs(E.devices) do
            if IsValid(dev) and dev:GetPos():DistToSqr(pos) <= reach * reach then
                local ed = EffectData()
                ed:SetOrigin(dev:GetPos())
                util.Effect("cball_explode", ed, true, true)
                dev:Remove()
            end
        end
    end
    hook.Run("Rhylib.Explosion", pos, charge == "he" and (st.big and E.Cfg("largeKill") or E.Cfg("smallRadius")) or 180,
        charge == "he" and (st.big and 3 or 2) or 1, nil, bomb, "bomb")
    E.bombs[bomb] = nil
    E.KeepForNextMap(bomb)
    timer.Simple(0.2, function() if IsValid(bomb) then bomb:Remove() end end)
end

-- Made safe outright (GM, or a lucky droid popper).
-- E.Disarm(bomb, why): detonator cut, valve sealed, stabiliser done,
-- timer stopped, spotter called off; why = a log line for viewers (or nil).
-- Example: Rhylib.EOD.Disarm(bomb, "The game master made it safe")
function E.Disarm(bomb, why)
    local st = bomb.eod
    if not st or st.over or st.done then return end
    st.safe = true
    st.gasSealed = true
    st.leakEnd = nil
    if st.stab then st.stab.done = true end
    if st.timerEnd then st.timerLeft = math.max(0, st.timerEnd - CurTime()) st.timerEnd = nil end
    st.timerStopped = true
    st.timerWaiting = false
    st.spotAt = nil
    for p in pairs(st.viewers) do if IsValid(p) and why then E.Msg(p, why) end end
    E.CheckDone(bomb)
    syncDisplay(bomb)
    E.Changed(bomb)
end

--------------------------------------------------------------------------
-- Remote signal
--------------------------------------------------------------------------

-- Returns true if it went off, else false and why.
-- E.RemoteSignal(bomb) -> ok, reason: the enemy sends the remote signal.
-- It fails on a timer bomb, a bomb made safe, a dead receiver (antenna
-- cut or relay redirected), a jammed bomb, or one with no power.
-- Example: local went, why = Rhylib.EOD.RemoteSignal(bomb)
function E.RemoteSignal(bomb)
    local st = bomb.eod
    if not st or st.over then return false, "No bomb" end
    if st.f.det ~= "remote" then return false, "It has a timer, not a receiver" end
    if st.done or st.safe then return false, "The detonator is disconnected" end
    if st.remoteDead then return false, st.relayed and "The relay sends it into the dummy load" or "The antenna is cut" end
    if E.Covered(bomb) then return false, "Jammed: an interference device blocked the signal" end
    if not powered(st) then return false, "No power: the receiver is dead" end
    E.Detonate(bomb, "remote")
    return true
end

--------------------------------------------------------------------------
-- Droid popper EMP (hook from rhylib_republic's grenade)
--------------------------------------------------------------------------

-- Rhylib.EMP(pos, radius, attacker, inflictor): bombs in brush sight get
-- a zap and a popperChance roll to be disarmed; running interference
-- devices in the radius switch off.
Rhylib.Hook.Add("Rhylib.EMP", "eod.emp", function(pos, radius, attacker, inflictor)
    local r2 = (radius or 0) ^ 2
    for bomb in pairs(E.bombs) do
        if IsValid(bomb) and bomb.eod and not bomb.eod.over and not bomb.eod.done then
            local c = bomb:WorldSpaceCenter()
            if c:DistToSqr(pos) <= r2 and not util.TraceLine({ start = pos, endpos = c, mask = MASK_SOLID_BRUSHONLY, filter = bomb }).Hit then
                local zap = EffectData()
                zap:SetOrigin(c)
                zap:SetFlags(1)
                util.Effect("rhylib_emp", zap, true, true)
                if math.random() < (E.Cfg("popperChance") or 0.1) then
                    E.Disarm(bomb, "The EMP fried the bomb's electronics")
                    if IsValid(attacker) and attacker:IsPlayer() then E.Msg(attacker, "Lucky: the droid popper fried the bomb") end
                end
            end
        end
    end
    for dev in pairs(E.devices) do
        if IsValid(dev) and dev:GetActive() and dev:WorldSpaceCenter():DistToSqr(pos) <= r2 then
            E.DevSetActive(dev, false)
            local ed = EffectData()
            ed:SetOrigin(dev:WorldSpaceCenter())
            ed:SetFlags(1)
            util.Effect("rhylib_emp", ed, true, true)
        end
    end
end)

--------------------------------------------------------------------------
-- Interference devices
--------------------------------------------------------------------------

local TUNE_TOL = 2.5   -- MHz either side of the dial

-- Cell charge (0-1) as a line: the device stores Cell (fill at CellAt)
-- and Rate (fill lost per second while on), so the client can work out
-- the fill itself and nothing is networked while it runs.
-- E.DevFill(dev) -> 0..1 now (same maths as ENT:Fill).
function E.DevFill(dev)
    local f = dev:GetCell()
    if dev:GetActive() then f = f - (CurTime() - dev:GetCellAt()) * dev:GetRate() end
    return math.Clamp(f, 0, 1)
end

-- Fold the drain so far into Cell before a change.
local function commit(dev)
    dev:SetCell(E.DevFill(dev))
    dev:SetCellAt(CurTime())
end

-- Fill lost per second at the device's current radius and mode.
local function rate(dev)
    return 1 / math.max(1, E.CellLife(dev:GetRadius(), dev:GetTuned(), dev.eodLong))
end

-- E.DevSetActive(dev, on) -> bool: switch an interference device on or
-- off. False (stays off) when switching on with an empty cell.
function E.DevSetActive(dev, on)
    commit(dev)
    if on and dev:GetCell() <= 0.001 then return false end
    dev:SetRate(rate(dev))
    dev:SetActive(on and true or false)
    dev:EmitSound(on and "buttons/button9.wav" or "buttons/button8.wav", 65)
    return true
end

local function devRange(dev) return dev:GetRadius() * E.UNITS_PER_M end

-- Does this device block this bomb's remote signal right now?
-- Returns blocked, wideband. Wideband blocks every bomb in its circle
-- (and blinds motion sensors); tuned only a receiver within ±2.5 MHz of
-- the dial (a hopping receiver jumps at least 10 MHz every hopEvery s).
local function blocks(dev, bomb, st)
    if not dev:GetActive() then return false end
    if bomb:GetPos():DistToSqr(dev:GetPos()) > devRange(dev) ^ 2 then return false end
    if not dev:GetTuned() then return true, true end
    return math.abs(dev:GetDial() - st.freq) <= TUNE_TOL, false
end

-- Viewers of a device's window get the scanner (bombs' receivers in range).
-- Live, powered receivers within SCAN_RANGE units (~60 m), at most 12;
-- strength = 100 at the device, falling to 1 at the edge. Viewers more
-- than 250 units away are dropped.
local SCAN_RANGE = 3200
local function sendScan(dev)
    local rec = {}
    for p in pairs(dev.viewers or {}) do
        if IsValid(p) and p:Alive() and p:GetPos():DistToSqr(dev:GetPos()) < 250 * 250 then rec[#rec + 1] = p
        else dev.viewers[p] = nil end
    end
    if #rec == 0 then return end
    local list = {}
    for bomb in pairs(E.bombs) do
        local st = IsValid(bomb) and bomb.eod
        if st and not st.over and st.f.det == "remote" and not st.remoteDead and powered(st) then
            local d = bomb:GetPos():Distance(dev:GetPos())
            if d < SCAN_RANGE and #list < 12 then
                list[#list + 1] = { st.freq - E.F0, math.Clamp(math.floor(100 * (1 - d / SCAN_RANGE)), 1, 100), st.f.hop and true or false }
            end
        end
    end
    Net.Start("eod.devscan")
    net.WriteEntity(dev)
    net.WriteUInt(#list, 4)
    for _, s in ipairs(list) do
        net.WriteUInt(math.Clamp(s[1], 0, 127), 7)
        net.WriteUInt(s[2], 7)
        net.WriteBool(s[3])
    end
    net.Send(rec)
end

-- E.OpenDevice(ply, dev): open the device window for ply (within 200
-- units, alive, not noclipping). ENT:Use calls it.
function E.OpenDevice(ply, dev)
    if not (IsValid(dev) and walkOk(ply)) or ply:GetPos():DistToSqr(dev:GetPos()) > 200 * 200 then return end
    dev.viewers = dev.viewers or {}
    dev.viewers[ply] = true
    Net.Start("eod.dev")
    net.WriteEntity(dev)
    net.Send(ply)
    sendScan(dev)
end

-- Placing one from the inventory (right-click "Place interference device").
-- Takes the device item and the player's best power cell ("cell" item;
-- its fill and issued flag go into the device), puts it on the ground
-- they look at (within 110 units) or in front of their feet. Starts off.
Net.Receive("eod.place", function(ply)
    local uid = net.ReadUInt(Rhylib.Items and Rhylib.Items.UID_BITS or 16)
    local Inv = Rhylib.Inventory
    if not (Inv and walkOk(ply)) or (Inv.Locked and Inv.Locked(ply)) then return end
    local inst = Inv.Get(ply).byUid[uid]
    if not inst or inst.id ~= E.DEVICE then return end
    if not Inv.Has(ply, "cell") then E.Msg(ply, "It needs a power cell", true) return end
    local tr = util.TraceLine({ start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * 110, filter = ply, mask = MASK_SOLID })
    if not tr.Hit or tr.HitNormal.z < 0.6 then
        tr = util.TraceLine({ start = ply:GetPos() + Vector(0, 0, 10) + ply:GetForward() * 40, endpos = ply:GetPos() + ply:GetForward() * 40 - Vector(0, 0, 80), filter = ply, mask = MASK_SOLID })
        if not tr.Hit then E.Msg(ply, "Put it on the ground", true) return end
    end
    if not Inv.Remove(ply, uid, 1) then return end
    local fill, issued = Inv.TakeBest(ply, "cell")
    fill = fill or 1
    local dev = ents.Create("rhylib_interference_dev")
    if not IsValid(dev) then Inv.AddOrDrop(ply, E.DEVICE, 1) Inv.AddOrDrop(ply, "cell", 1, { fill = fill }) return end
    dev:SetPos(tr.HitPos)
    dev:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    dev.eodLong = false
    dev.eodOwner = ply
    dev:Spawn()
    dev:SetPos(tr.HitPos - Vector(0, 0, dev:OBBMins().z))
    dev:SetCell(math.Clamp(tonumber(fill) or 1, 0, 1))
    dev:SetCellAt(CurTime())
    dev:SetRate(rate(dev))
    dev.eodIssued = issued
    dev:SetNW2Bool("rhylib_eodLong", dev.eodLong and true or false)
    E.Msg(ply, "Interference device placed: press E on it to set it up")
end, { rate = 3, burst = 3 })

-- Settings: 0 on/off, 1 radius, 2 mode, 3 dial, 4 swap cell, 5 pick up, 6 close.
-- Arguments: 1 radius in metres (4 bits, 1-15, also capped by
-- deviceMaxRadius), 2 tuned (bool), 3 dial - 2400 (7 bits, 0-80).
-- commit() folds the drain so far into Cell before anything that
-- changes the rate. Any player near it may change it (not only the owner).
Net.Receive("eod.devset", function(ply)
    local dev = net.ReadEntity()
    local op = net.ReadUInt(3)
    local a
    if op == 1 then a = net.ReadUInt(4)
    elseif op == 2 then a = net.ReadBool()
    elseif op == 3 then a = net.ReadUInt(7) end
    if not (IsValid(dev) and dev:GetClass() == "rhylib_interference_dev") then return end
    if op == 6 then if dev.viewers then dev.viewers[ply] = nil end return end
    if not walkOk(ply) or ply:GetPos():DistToSqr(dev:GetPos()) > 220 * 220 then return end
    local Inv = Rhylib.Inventory
    if op == 0 then
        if not E.DevSetActive(dev, not dev:GetActive()) then E.Msg(ply, "The cell is empty", true) end
    elseif op == 1 then
        commit(dev)
        dev:SetRadius(math.Clamp(a, 1, math.min(15, E.Cfg("deviceMaxRadius") or 15)))
        dev:SetRate(rate(dev))
    elseif op == 2 then
        commit(dev)
        dev:SetTuned(a and true or false)
        dev:SetRate(rate(dev))
    elseif op == 3 then
        dev:SetDial(E.F0 + math.Clamp(a, 0, E.F1 - E.F0))
    elseif op == 4 then
        if not Inv then return end
        if not Inv.Has(ply, "cell") then E.Msg(ply, "You have no power cell", true) return end
        commit(dev)
        local old = dev:GetCell()
        local fill, issued = Inv.TakeBest(ply, "cell")
        fill = fill or 1
        if old > 0.01 then Inv.AddOrDrop(ply, "cell", 1, { fill = old, issued = dev.eodIssued }) end
        dev.eodIssued = issued
        dev:SetCell(math.Clamp(tonumber(fill) or 1, 0, 1))
        dev:SetCellAt(CurTime())
        dev:EmitSound("items/battery_pickup.wav", 60)
    elseif op == 5 then
        if not Inv then return end
        local fill = E.DevFill(dev)
        dev:Remove()
        Inv.AddOrDrop(ply, E.DEVICE, 1)
        if fill > 0.01 then Inv.AddOrDrop(ply, "cell", 1, { fill = fill, issued = dev.eodIssued }) end
        E.Msg(ply, "Interference device picked up")
    end
end, { rate = 12, burst = 12 })

--------------------------------------------------------------------------
-- The world timer
--------------------------------------------------------------------------

-- The speed a motion sensor allows: walk speed ×1.15 (normal), or the
-- slower of slow-walk and crouch-walk ×1.15 (sensitive).
local function motionLimit(p, sensitive)
    local walk = p:GetWalkSpeed()
    if sensitive then
        return math.min(p:GetSlowWalkSpeed(), walk * p:GetCrouchedWalkSpeed()) * 1.15
    end
    return walk * 1.15
end

-- The first player moving too fast within sensorRange and in brush
-- sight of the bomb, or nil. Skips cloaked players, noclip, toolgun
-- holders, and the first 4 s after the bomb was set up (armAt).
local function tooFast(bomb, st, now)
    if now < (st.armAt or 0) then return nil end
    local r = E.Cfg("sensorRange") or 315
    local c = bomb:WorldSpaceCenter()
    for _, p in ipairs(player.GetAll()) do
        if walkOk(p) and not p:GetNW2Bool("rhylib_cloak", false) then
            local w = p:GetActiveWeapon()
            if not (IsValid(w) and w:GetClass() == "rhylib_toolgun") then   -- (the GM setting it up)
                local pc = p:WorldSpaceCenter()
                if pc:DistToSqr(c) <= r * r and p:GetVelocity():Length() > motionLimit(p, st.f.motion == "sensitive")
                    and not util.TraceLine({ start = c, endpos = pc, mask = MASK_SOLID_BRUSHONLY }).Hit then
                    return p
                end
            end
        end
    end
end

local function holdsTool(p)
    local w = p:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

local function anyoneNear(pos, r)
    for _, p in ipairs(player.GetAll()) do
        if walkOk(p) and not holdsTool(p) and p:GetPos():DistToSqr(pos) <= r * r then return true end
    end
    return false
end

local lastScan = 0

-- Signal blackout (rhylib_droids asks, D.Blackout): is pos inside a running
-- wideband device placed by someone with the skill?
-- E.InBlackout(pos) -> bool. Server. E.blackouts is rebuilt every tick.
-- Example (rhylib_droids): if Rhylib.EOD.InBlackout(droid:GetPos()) then ... end
E.blackouts = E.blackouts or {}
function E.InBlackout(pos)
    for _, dev in ipairs(E.blackouts) do
        if IsValid(dev) and dev:GetActive() then
            local r = dev:GetRadius() * E.UNITS_PER_M
            if dev:WorldSpaceCenter():DistToSqr(pos) <= r * r then return true end
        end
    end
    return false
end

-- Every 0.2 s ("Rhylib.EOD.World", under pcall). Per bomb, in order:
-- 1. coverage from active devices (eodCovered, eodMotionBlock);
-- 2. at most one way to go off: anti-jam jammed > motion sensor > timer
--    at zero > gas leak > spotter's signal (only the first that applies);
-- 3. timer wake-up (a player, not holding the toolgun, within
--    timerWake, battery power, not GM-held), frequency hop, tilt bubble
--    (paused while nobody has the window open; fires past radius 1);
-- 4. torch on the sealed plate (cut progress and heat);
-- 5. viewers who walked off (reach + 80), died or left get closed;
--    readout NW2 vars refreshed.
-- Each step re-checks the bomb, since an earlier one may have set it off.
local function tick()
    local now = CurTime()
    -- devices: running out of power
    local devs = {}
    for dev in pairs(E.devices) do
        if not IsValid(dev) then
            E.devices[dev] = nil
        else
            if dev:GetActive() and E.DevFill(dev) <= 0 then
                E.DevSetActive(dev, false)
                dev:EmitSound("hl1/fvox/power_level_is.wav", 55, 140)
            end
            if dev:GetActive() then devs[#devs + 1] = dev end
        end
    end
    -- Signal blackout (EOD skill): wideband devices whose owner has it.
    local bo = {}
    for _, dev in ipairs(devs) do
        if not dev:GetTuned() and IsValid(dev.eodOwner) and E.Skill(dev.eodOwner, "eod_blackout") then bo[#bo + 1] = dev end
    end
    E.blackouts = bo
    local scan = now - lastScan >= 0.5
    if scan then
        lastScan = now
        for dev in pairs(E.devices) do if IsValid(dev) and dev.viewers and next(dev.viewers) then sendScan(dev) end end
    end

    for bomb in pairs(E.bombs) do
        local st = IsValid(bomb) and bomb.eod
        if not st then
            E.bombs[bomb] = nil
        elseif not st.over then
            -- coverage (remote signal blocked; wideband also blinds motion sensors)
            local covered, wide = false, false
            for _, dev in ipairs(devs) do
                local b, w = blocks(dev, bomb, st)
                if b then covered = true end
                if w then wide = true end
            end
            if covered then bomb.eodCovered = now + 0.5 end
            bomb.eodMotionBlock = wide or nil
            local live = not st.safe and powered(st)

            if covered and live and st.antiJam and st.f.det == "remote" and not st.remoteDead then
                E.Detonate(bomb, "antijam")
            elseif live and st.f.motion and st.sensorOn ~= false and not wide and not st.done and tooFast(bomb, st, now) then
                E.Detonate(bomb, "motion")
            elseif st.timerEnd and now >= st.timerEnd then
                E.Detonate(bomb, "timer")
            elseif st.leakEnd and not st.gasSealed and now >= st.leakEnd then
                E.Detonate(bomb, "leak")
            elseif st.spotAt and now >= st.spotAt then
                st.spotAt = nil
                E.RemoteSignal(bomb)
            end
        end

        if IsValid(bomb) and st and not st.over then
            -- timers wake up when someone comes close
            if st.timerWaiting and not st.gmHeld and now >= (st.armAt or 0) and E.AnySupply(st) and not st.safe and anyoneNear(bomb:GetPos(), E.Cfg("timerWake") or 900) then
                E.StartTimer(bomb)
            end
            -- frequency hopping
            if st.f.hop and not st.remoteDead and now >= st.hopAt then
                local f = st.freq
                for _ = 1, 5 do
                    f = 2405 + math.random(0, 70)
                    if math.abs(f - st.freq) >= 10 then break end
                end
                st.freq = f
                st.hopAt = now + (E.Cfg("hopEvery") or 25)
            end
            -- tilt switch
            local t = st.tilt
            if t and t.t0 and not st.safe then
                if next(st.viewers) == nil then
                    if not t.pausedAt then t.pausedAt = now end
                else
                    if E.TiltResume(st) then E.Changed(bomb) end
                    local x, y = E.TiltPos(t, now)
                    if x * x + y * y >= 1 then E.Detonate(bomb, "tilt") end
                end
            end
        end

        if IsValid(bomb) and st and not st.over then
            -- torch on the sealed plate
            local tp = st.torchBy
            if tp then
                if not (IsValid(tp) and st.viewers[tp]) or st.sealedOpen then
                    st.torchBy = nil
                    E.Changed(bomb)
                else
                    local dt = now - (st.torchTick or now)
                    st.torchTick = now
                    if dt > 0 then
                        st.sealedP = math.min(1, st.sealedP + dt / math.max(0.5, E.Cfg("torchTime") or 5))
                        -- (st = nil: it went off, skip the rest)
                        if E.AddHeat(bomb, tp, (E.Cfg("heatTorch") or 26) * dt, true) then st = nil end
                    end
                    if st and st.sealedP >= 1 then
                        st.sealedOpen = true
                        st.torchBy = nil
                        E.Msg(tp, "The sealed plate is cut open")
                        E.Changed(bomb)
                    elseif st and now - (st.torchSent or 0) >= 0.5 then
                        st.torchSent = now
                        E.Changed(bomb)
                    end
                end
            else
                st.torchTick = nil
            end
        end

        if IsValid(bomb) and st and not st.over then
            -- windows: walked off, died or left
            local r = (E.Cfg("reach") or 130) + 80
            for p in pairs(st.viewers) do
                if not IsValid(p) then
                    st.viewers[p] = nil
                elseif not p:Alive() or p:GetPos():DistToSqr(bomb:GetPos()) > r * r then
                    E.CloseFor(p, bomb)
                end
            end
            syncDisplay(bomb)
        end
    end
end
timer.Create("Rhylib.EOD.World", 0.2, 0, function()
    local ok, err = pcall(tick)
    if not ok then ErrorNoHaltWithStack("[Rhylib] EOD world timer: " .. tostring(err)) end
end)

--------------------------------------------------------------------------
-- Using a bomb, and the GM window
--------------------------------------------------------------------------

-- What the GM window shows: the features, the wires with their kinds,
-- timer state, spotter, and the module answers (chip code row, dose,
-- fake board order).
local function gmInfo(bomb)
    local st = bomb.eod
    local wires = {}
    for i, w in ipairs(st.wires) do
        wires[i] = { k = w.k, a = w.a, b = w.b, c = st.colors[i], cut = st.cut[i] or false }
    end
    return {
        f = st.f, kind = st.kindName, type = st.type, freq = st.freq, wires = wires,
        timer = st.timerSecs and { secs = st.timerSecs, ends = st.timerEnd or 0, left = st.timerLeft or st.timerSecs,
            waiting = st.timerWaiting, stopped = st.timerStopped or false, held = st.gmHeld or false } or nil,
        spotAt = st.spotAt or 0, now = CurTime(), inspected = st.inspected, open = st.open, safe = st.safe, done = st.done,
        covered = E.Covered(bomb), powered = powered(st), viewers = table.Count(st.viewers),
        chip = st.chip and E.CHIP_CODES[st.chip.code] or nil, stab = st.stab and st.stab.dose or nil,
        fake = st.fake and st.fake.order or nil,
    }
end

local function sendGM(ply, bomb, note)
    local data = util.Compress(util.TableToJSON(gmInfo(bomb)))
    if not data then return end
    Net.Start("eod.gmopen")
    net.WriteEntity(bomb)
    net.WriteString(note or "")
    net.WriteUInt(#data, 16)
    net.WriteData(data, #data)
    net.Send(ply)
end

local function isGMTool(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() == "rhylib_toolgun"
end

-- E.UseBomb(ply, bomb): what E on a bomb does (ENT:Use). Toolgun out and
-- rhylib.eod.gm -> GM window; otherwise the defusal window.
function E.UseBomb(ply, bomb)
    if not (IsValid(bomb) and bomb.eod and IsValid(ply)) or bomb.eod.over then return end
    if isGMTool(ply) then
        Rhylib.Perms.Check(ply, "rhylib.eod.gm", function(ok)
            if not (IsValid(ply) and IsValid(bomb)) then return end
            if ok then sendGM(ply, bomb) elseif walkOk(ply) then E.OpenFor(ply, bomb) end
        end)
        return
    end
    if walkOk(ply) then E.OpenFor(ply, bomb) end
end

-- Custom bombs: the GM's features (JSON from the GM window), checked.
-- E.CustomFeatures(json, kind) -> f or nil. kind = f.type ("custom" by
-- default, "training" for training bombs). Unknown values fall back to
-- defaults; anti-jam, hopping and remote-only modules need det "remote";
-- timerSecs is clamped to 20-1800. Under 2000 characters.
-- Example: E.CustomFeatures('{"det":"remote","antiJam":true,"mods":["chip","fake"]}')
local function customFeatures(js, kind)
    local t = isstring(js) and #js < 2000 and util.JSONToTable(js)
    if not istable(t) then return nil end
    local function pick(v, ok, def) return ok[v] and v or def end
    local f = {
        type = kind or "custom",
        det = pick(t.det, { timer = true, remote = true }, "timer"),
        motion = pick(t.motion, { normal = true, sensitive = true }, nil),
        lid = t.lid == true,
        battery = pick(t.battery, { single = true, dual = true, capacitor = true, collapse = true }, "single"),
        sensor = t.sensor == true,
        charge = pick(t.charge, { he = true, gas = true, virus = true }, "he"),
        mods = {},
    }
    f.antiJam = f.det == "remote" and t.antiJam == true
    f.hop = f.det == "remote" and t.hop == true
    if istable(t.mods) then
        for _, id in ipairs(t.mods) do
            local m = E.MOD_BY[id]
            if m and not (m.remote and f.det ~= "remote") then f.mods[id] = true end
        end
    end
    local secs = tonumber(t.timerSecs)
    if secs then f.timerSecs = math.Clamp(math.floor(secs), 20, 1800) end
    return f
end
E.CustomFeatures = customFeatures

-- GM ops: 0 re-roll, 1 simplified, 2 small, 3 large, 4 custom (JSON),
-- 5 start timer, 6 pause/resume, 7 set seconds, 8 remote signal now,
-- 9 spotter in N s (0 = cancel), 10 detonate, 11 disarm, 12 refresh,
-- 13 open the defusal window.
-- Every op is checked against rhylib.eod.gm; after it the GM window is
-- sent again with a note (not after 10 or 13).
Net.Receive("eod.gm", function(ply)
    local bomb = net.ReadEntity()
    local op = net.ReadUInt(4)
    local arg
    if op == 4 then arg = net.ReadString()
    elseif op == 7 or op == 9 then arg = net.ReadUInt(11) end
    if not (IsValid(bomb) and bomb.eod) or bomb.eod.over then return end
    Rhylib.Perms.Check(ply, "rhylib.eod.gm", function(ok)
        if not ok or not (IsValid(ply) and IsValid(bomb) and bomb.eod) or bomb.eod.over then return end
        local st = bomb.eod
        local note
        if op == 0 then
            if st.type == "custom" or st.type == "training" then
                local f = table.Copy(st.f)
                f.mods = table.Copy(st.f.mods)
                E.Rebuild(bomb, f)
            else
                E.Rebuild(bomb, E.Roll(st.type))
            end
            note = "Re-rolled"
        elseif op >= 1 and op <= 3 then
            E.Rebuild(bomb, E.Roll(({ "simple", "small", "large" })[op]))
            note = "New " .. bomb.eod.kindName:lower()
        elseif op == 4 then
            local f = customFeatures(arg)
            if not f then note = "That custom bomb didn't read right" else E.Rebuild(bomb, f) note = "Custom bomb built" end
        elseif op == 5 then
            st.gmHeld = nil
            note = E.StartTimer(bomb) and "Timer started" or "No timer, no power, or already safe"
        elseif op == 6 then
            if st.timerEnd then E.PauseTimer(bomb) note = "Timer paused"
            else st.gmHeld = nil note = E.StartTimer(bomb) and "Timer running" or "Can't run: no timer, no power, or safe" end
        elseif op == 7 then
            local s = math.Clamp(arg or 0, 10, 1800)
            if not st.timerSecs then note = "It has no timer"
            else
                st.timerSecs = s
                if st.timerEnd then st.timerEnd = CurTime() + s else st.timerLeft = s end
                syncDisplay(bomb)
                E.Changed(bomb)
                note = "Timer set to " .. string.FormattedTime(s, "%02i:%02i")
            end
        elseif op == 8 then
            local went, why = E.RemoteSignal(bomb)
            note = went and "Boom" or ("Signal didn't fire it: " .. why)
        elseif op == 9 then
            if st.f.det ~= "remote" then note = "Only remote bombs have a spotter"
            elseif (arg or 0) <= 0 then st.spotAt = nil note = "Spotter called off"
            else st.spotAt = CurTime() + arg note = "The spotter sends the signal in " .. arg .. " s" end
        elseif op == 10 then
            E.Detonate(bomb, "gm")
            return
        elseif op == 11 then
            E.Disarm(bomb, "The game master made it safe")
            note = "Disarmed"
        elseif op == 13 then
            E.OpenFor(ply, bomb)
            return
        end
        if IsValid(bomb) and bomb.eod and not bomb.eod.over then sendGM(ply, bomb, note) end
    end)
end, { rate = 8, burst = 8 })

--------------------------------------------------------------------------
-- Training bombs (2026-10-09z): anyone near one sets it up like a custom
-- bomb (or rolls a random one); failing only fails, then it re-arms.
-- eod.train ops: 0 build (JSON), 1 again (same setup, fresh board),
-- 2 random simplified, 3 random small, 4 random large, 5 open the setup.
--------------------------------------------------------------------------

Net.Register("eod.trainopen")

-- A random roll of that kind, but as a training bomb (f.type "training").
local function trainingFrom(kind)
    local f = E.Roll(kind)
    f.type = "training"
    return f
end

-- Anyone alive within 300 units may set up a training bomb (no permission).
Net.Receive("eod.train", function(ply)
    local bomb = net.ReadEntity()
    local op = net.ReadUInt(3)
    local js = op == 0 and net.ReadString() or nil
    if not (IsValid(bomb) and bomb.IsTrainingBomb and bomb.eod) or not walkOk(ply) then return end
    if ply:GetPos():DistToSqr(bomb:GetPos()) > 300 * 300 then return end
    if op == 5 then
        local data = util.Compress(util.TableToJSON(bomb.eod.f))
        if not data then return end
        Net.Start("eod.trainopen")
        net.WriteEntity(bomb)
        net.WriteUInt(#data, 16)
        net.WriteData(data, #data)
        net.Send(ply)
        return
    end
    local f
    if op == 0 then f = customFeatures(js, "training")
    elseif op == 1 then
        f = table.Copy(bomb.eod.f)
        f.mods = table.Copy(bomb.eod.f.mods or {})
    elseif op >= 2 and op <= 4 then f = trainingFrom(({ "simple", "small", "large" })[op - 1]) end
    if not f then return end
    E.Rebuild(bomb, f)
    E.Msg(ply, "Training bomb set up: " .. (op == 1 and "the same again" or "ready"))
end, { rate = 4, burst = 4 })
