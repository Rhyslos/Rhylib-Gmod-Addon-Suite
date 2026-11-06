--[[
    Stealth (server): alertness per droid and squad, hearing, the alarm,
    and what players and staff are sent. The detection look itself is in
    brain/stealth.lua (ENT:StealthLook, ENT:StealthStep), the settings and
    maths in sh_50_stealth.lua, foliage in sv_55_foliage.lua.

    Alertness (npc.alertness, the GM's setting): "alert" (default: sees
    as always) or "unaware". An unaware droid that isn't fighting has
    npc.stealth (its live state: unaware / suspicious / searching, up to 3
    meters) and is in D.stealthy. Alerted, npc.stealth goes (the normal
    brain takes over) but npc.alertness stays "unaware", so !alarm off can
    put it back. Clones are never unaware.

    Hearing (only droids in D.stealthy; one pass per sound):
      shots (rhylib_weapons Bolts.Fire -> D.HearShot) within
      stealthHearShot and blasts (W.Explode, the HE charge -> D.HearNoise
      "blast"; EOD bombs and mines through hook Rhylib.Explosion)
      within stealthHearBlast startle: the droid turns to the
      sound and is alerted after its reaction time. Stun hits and baton
      hits (hook Rhylib.PlayerStunned) within stealthHearStun make it
      suspicious, and so does a droid destroyed within stealthBody that it
      can see (D.StealthBody from ENT:OnKilled).
    The alarm: a droid alerted out of stealth radios for
    stealthAlarmDelay s ("!" over it, NW2Int rhylib_sstate 4) and only then
    alerts its squad and calls help (D.CallHelp, whose helpers become
    alert). Destroyed before then: no call.

    API (server): D.StealthOn(), D.SetAlertness(npc, "alert"|"unaware"),
    D.SetSquadAlertness(sq, v), D.MakeUnaware(npc), D.StealthAlert(npc,
    who, spot, noCall, spotted), D.StealthSuspect(npc, pos),
    D.HearNoise(pos, kind, src) (kind "shot", "blast", "stun"),
    D.HearShot(src, pos, quiet) (sounds are queued and heard once a
    tick: D.StealthHearQueued), D.StealthBody(dead), D.StealthTraces(n)
    -> bool (the per-tick trace budget), D.StealthWeather() -> multiplier,
    D.RaiseAlarm(npc), D.Alarm(on, by) -> count.

    Nets (server -> client):
      droids.seen    to one player, 4 a second at most while unaware
                     droids notice them and the value changes, a last
                     empty one when it ends: Bool spotted (alerted by
                     stealth just now), UInt 2 n, n x (UInt 13 droid
                     entity, UInt 8 meter 0-255, UInt 2 state 1 noticing
                     2 suspicious/searching). Meter HUD: n <= 1 (the
                     highest); arcs: up to 3. Nothing with stealthHud none.
      droids.smeter  to staff holding the toolgun, 4 a second at most on
                     change: UInt 7 n, n x (UInt 13 droid, UInt 8 meter).
    Command: rhylib_alarm [off] (!alarm, perm rhylib.droids.alarm).
]]

local D = Rhylib.Droids
local M = D.StealthMath

D.stealthy = D.stealthy or {}   -- [droid] = true while its stealth look runs
D.alarms = D.alarms or {}       -- [droid] = true while it radios the alarm

local RADIO_ON = "npc/combine_soldier/vo/on2.wav"
local RADIO_OFF = "npc/combine_soldier/vo/off1.wav"

function D.StealthOn() return D.Cfg("stealthOn") == true end

local function setState(npc, code)
    if npc:GetNW2Int("rhylib_sstate", 0) ~= code then npc:SetNW2Int("rhylib_sstate", code) end
end
D.StealthSetState = setState

-- A fresh live state (the tables are kept on the droid and reused).
local function fresh(npc)
    local st = npc.stealthKeep
    if not st then
        st = { e = {}, spot = Vector(0, 0, 0) }
        for i = 1, 3 do st.e[i] = { ent = nil, v = 0, seenAt = 0, stepAt = 0, pos = Vector(0, 0, 0) } end
        npc.stealthKeep = st
    end
    local now = CurTime()
    st.state, st.lastAt, st.nextAt, st.lostAt, st.searchUntil, st.stopUntil = "unaware", now, 0, now, 0, 0
    st.startleAt, st.startleSrc = nil, nil
    st.startlePos = st.startlePos or Vector(0, 0, 0)
    local p = npc:GetPos()
    st.px, st.py, st.pz = p.x, p.y, p.z   -- (its spot for hearing, plain numbers; StealthLook keeps it current)
    st.focus, st.reached = nil, false
    for i = 1, 3 do
        local x = st.e[i]
        x.ent, x.v, x.seenAt, x.stepAt, x.skipAt, x.sightAt = nil, 0, 0, 0, 0, -100
    end
    return st
end

-- D.MakeUnaware(npc): starts the stealth look (not while it fights).
function D.MakeUnaware(npc)
    if not (IsValid(npc) and npc.IsRhylibDroid) or npc.IsRhylibClone then return false end
    npc.alertness = "unaware"
    if IsValid(npc.target) then return false end
    npc.stealth = fresh(npc)
    D.stealthy[npc] = true
    D.alarms[npc], npc.alarmAt, npc.alarmEnemy = nil, nil, nil
    setState(npc, D.StealthOn() and 1 or 0)
    return true
end

-- D.SetAlertness(npc, v): "unaware" (stealth) or anything else = alert.
-- Clones and non-droids: false.
-- Example: Rhylib.Droids.SetAlertness(droid, "unaware")
function D.SetAlertness(npc, v)
    if not (IsValid(npc) and npc.IsRhylibDroid) or npc.IsRhylibClone then return false end
    if v == "unaware" then
        D.MakeUnaware(npc)
        return true
    end
    npc.alertness = "alert"
    npc.stealth = nil
    D.stealthy[npc] = nil
    D.alarms[npc], npc.alarmAt, npc.alarmEnemy = nil, nil, nil
    setState(npc, 0)
    return true
end

-- D.SetSquadAlertness(sq, v): every member of a squad.
function D.SetSquadAlertness(sq, v)
    local n = 0
    for _, d in ipairs(sq and sq.list or {}) do
        if D.SetAlertness(d, v) then n = n + 1 end
    end
    return n
end

local sendSpotted   -- (below)

-- D.StealthAlert(npc, who, spot, noCall, spotted): out of stealth into
-- the normal brain. who = the enemy (it knows where they are now), else
-- spot = where to look. noCall: no radio call of its own (it was called,
-- or !alarm). spotted: who filled its meter (they get SPOTTED).
function D.StealthAlert(npc, who, spot, noCall, spotted)
    if not (IsValid(npc) and npc.stealth) then return end
    npc.stealth = nil
    D.stealthy[npc] = nil
    local now = CurTime()
    if IsValid(who) then
        npc.lastSeen, npc.lastSeenAt = who:GetPos(), now
    elseif spot then
        npc.lastSeen, npc.lastSeenAt = Vector(spot), now
    end
    npc.nextLook, npc.woken, npc.redirect, npc.planAt = 0, true, true, 0
    npc:SetNW2Float("rhylib_salert", now)
    if noCall then
        setState(npc, 0)
    else
        npc.alarmAt = now + math.max(D.Cfg("stealthAlarmDelay"), 0)
        npc.alarmEnemy = IsValid(who) and who or nil
        D.alarms[npc] = true
        setState(npc, 4)
        npc:EmitSound(RADIO_ON, 65, 100)
    end
    if spotted and IsValid(who) and who:IsPlayer() and sendSpotted then sendSpotted(who) end
end

-- D.StealthSuspect(npc, pos): something odd there: suspicious (walks
-- over to look); already suspicious or searching: looks there instead.
function D.StealthSuspect(npc, pos)
    local st = npc.stealth
    if not st then return end
    local now = CurTime()
    st.spot:Set(pos)
    st.reached = false
    if st.state == "unaware" then
        st.state, st.lostAt, st.stopUntil = "suspicious", now, now + 1
        setState(npc, 2)
    elseif st.state == "searching" then
        st.searchUntil = math.max(st.searchUntil, now + 8)
    else
        st.lostAt = now
    end
    npc.redirect, npc.woken = true, true
end

-- D.RaiseAlarm(npc): its squad is alerted and help is called.
function D.RaiseAlarm(npc)
    local enemy = IsValid(npc.target) and npc.target or (IsValid(npc.alarmEnemy) and npc.alarmEnemy) or nil
    local spot = enemy and enemy:GetPos() or npc.lastSeen
    local sq = npc.squad
    if sq then
        for _, m in ipairs(sq.list) do
            if m ~= npc and IsValid(m) and m.stealth then D.StealthAlert(m, enemy, spot, true) end
        end
    end
    if D.CallHelp and not (npc.Retreating and npc:Retreating()) then D.CallHelp(npc, enemy) end
end

-- The radio calls going out.
timer.Create("Rhylib.Droids.Alarms", 0.2, 0, function()
    if not next(D.alarms) then return end
    local now = CurTime()
    for npc in pairs(D.alarms) do
        if not IsValid(npc) or npc:Health() <= 0 then
            D.alarms[npc] = nil   -- (destroyed first: no call)
        elseif now >= (npc.alarmAt or 0) then
            D.alarms[npc] = nil
            npc.alarmAt = nil
            setState(npc, 0)
            npc:EmitSound(RADIO_OFF, 65, 100)
            D.RaiseAlarm(npc)
            npc.alarmEnemy = nil
        end
    end
end)

--------------------------------------------------------------------------
-- Sight budget, weather
--------------------------------------------------------------------------

local budTick, budUsed = -1, 0
-- D.StealthTraces(n) -> true if n more stealth traces fit in this tick.
function D.StealthTraces(n)
    local t = engine.TickCount()
    if t ~= budTick then budTick, budUsed = t, 0 end
    if budUsed + n > D.Cfg("stealthTraces") then return false end
    budUsed = budUsed + n
    return true
end

local wxAt, wxMult = -1, 1
-- D.StealthWeather() -> noticing multiplier from rhylib_weather (1 without).
function D.StealthWeather()
    local now = CurTime()
    if now < wxAt then return wxMult end
    wxAt = now + 1
    local W = Rhylib.Weather
    if W and W.Kind and W.Intensity then
        local ok, v = pcall(M.WeatherMult, W.Kind(), W.Intensity(), D.Cfg)
        wxMult = ok and tonumber(v) or 1
    else
        wxMult = 1
    end
    return wxMult
end

--------------------------------------------------------------------------
-- Hearing
--------------------------------------------------------------------------

-- Startled: turns to the sound, alerted after its reaction time
-- (brain/stealth StealthLook / StealthStep). pos is copied.
local function startle(npc, st, pos, src)
    local now = CurTime()
    if st.startleAt and st.startleAt <= now + 0.1 then return end
    local react = D.Cfg(npc:Kind().reaction) * math.Rand(0.8, 1.3)
    local at = now + react
    if st.startleAt and st.startleAt < at then at = st.startleAt end
    st.startleAt, st.startleSrc = at, src
    st.startlePos:Set(pos)
    npc.redirect, npc.woken = true, true
end

-- Sounds are queued and heard once a tick, in one pass over the unaware
-- droids: plain numbers, no allocation per sound. Sounds of one kind
-- within MERGE units of a queued one join it; at most QMAX a tick.
local QMAX, MERGE2 = 8, 300 * 300
local KIND = { shot = 1, blast = 2, stun = 3 }
local qn = 0
local qx, qy, qz, qk, qs = {}, {}, {}, {}, {}
local qv = Vector(0, 0, 0)
local R2 = {}   -- (hearing radius squared by kind, refreshed each pass)

-- D.HearNoise(pos, kind, src): a sound at pos ("shot", "blast", "stun").
function D.HearNoise(pos, kind, src)
    if not pos or not next(D.stealthy) then return end
    local k = KIND[kind] or 1
    local x, y, z = pos.x, pos.y, pos.z
    for i = 1, qn do
        if qk[i] == k then
            local dx, dy, dz = qx[i] - x, qy[i] - y, qz[i] - z
            if dx * dx + dy * dy + dz * dz < MERGE2 then return end
        end
    end
    if qn >= QMAX then return end
    qn = qn + 1
    qx[qn], qy[qn], qz[qn], qk[qn], qs[qn] = x, y, z, k, src
end

-- D.HearShot(src, pos, quiet): a bolt fired (rhylib_weapons). One sound
-- per shooter a second; quiet (stun bolts) makes none.
function D.HearShot(src, pos, quiet)
    if quiet or not next(D.stealthy) then return end
    if IsValid(src) then
        local now = CurTime()
        if (src.rhylibNoiseAt or 0) > now then return end
        src.rhylibNoiseAt = now + 1
    end
    D.HearNoise(pos, "shot", src)
end

-- D.StealthHearQueued(): hear this tick's sounds (Tick hook). Each
-- unaware droid's position is read from st.px / py / pz (set by its look).
function D.StealthHearQueued()
    if qn == 0 then return end
    local n = qn
    qn = 0
    if not D.StealthOn() then
        for i = 1, n do qs[i] = nil end
        return
    end
    local rShot, rBlast, rStun = D.Cfg("stealthHearShot"), D.Cfg("stealthHearBlast"), D.Cfg("stealthHearStun")
    R2[1], R2[2], R2[3] = rShot * rShot, rBlast * rBlast, rStun * rStun
    for npc in pairs(D.stealthy) do
        local st = IsValid(npc) and npc.stealth
        if st then
            local px, py, pz = st.px, st.py, st.pz
            if px then
                for i = 1, n do
                    local k = qk[i]
                    local dx, dy, dz = qx[i] - px, qy[i] - py, qz[i] - pz
                    if dx * dx + dy * dy + dz * dz < R2[k] then
                        qv:SetUnpacked(qx[i], qy[i], qz[i])
                        if k == 3 then D.StealthSuspect(npc, qv) else startle(npc, st, qv, qs[i]) end
                        if not npc.stealth then break end
                    end
                end
            end
        else
            D.stealthy[npc] = nil
        end
    end
    for i = 1, n do qs[i] = nil end
end
Rhylib.Hook.Add("Tick", "droids.stealthhear", function() if qn > 0 then D.StealthHearQueued() end end)

Rhylib.Hook.Add("Rhylib.PlayerStunned", "droids.stealth", function(ply, by)
    if IsValid(ply) then D.HearNoise(ply:GetPos(), "stun", by) end
end)

-- EOD bombs and mines (rhylib_eod fires Rhylib.Explosion for them;
-- weapon blasts come through W.Explode and the HE charge already).
local EOD_KINDS = { bomb = true, mine = true, repmine = true }
Rhylib.Hook.Add("Rhylib.Explosion", "droids.stealth", function(pos, reach, tier, attacker, inflictor, kind)
    if EOD_KINDS[kind] then D.HearNoise(pos, "blast", attacker) end
end)


-- D.StealthBody(dead): a droid destroyed: unaware droids close by that
-- can see the spot get suspicious (one trace each, at most 6).
local btr = {}
local btrData = { mask = MASK_VISIBLE_AND_NPCS, output = btr }
local bFilter = {}
function D.StealthBody(dead)
    if not (IsValid(dead) and next(D.stealthy) and D.StealthOn()) then return end
    local pos = dead:WorldSpaceCenter()
    local r = D.Cfg("stealthBody")
    local cosWide = math.cos(math.rad(D.Cfg("stealthFovWide") * 0.5))
    local tries = 0
    for npc in pairs(D.stealthy) do
        if tries >= 6 then break end
        if IsValid(npc) and npc.stealth and npc ~= dead then
            local eye = npc:Eye()
            local dir = pos - eye
            local len = dir:Length()
            if len < r and len > 1 and npc:GetForward():Dot(dir / len) >= cosWide and D.StealthTraces(1) then
                tries = tries + 1
                bFilter[1], bFilter[2] = npc, dead
                btrData.start, btrData.endpos, btrData.filter = eye, pos, bFilter
                util.TraceLine(btrData)
                if not btr.Hit then D.StealthSuspect(npc, dead:GetPos()) end
            end
        end
    end
    bFilter[1], bFilter[2] = nil, nil
end

--------------------------------------------------------------------------
-- !alarm
--------------------------------------------------------------------------

-- D.Alarm(on, by) -> count: on = every unaware droid becomes alert; off =
-- droids set unaware that were alerted and aren't fighting go back.
function D.Alarm(on, by)
    local n = 0
    if on then
        for npc in pairs(D.stealthy) do
            if IsValid(npc) and npc.stealth then
                D.StealthAlert(npc, nil, nil, true)
                n = n + 1
            end
        end
    else
        local now = CurTime()
        for d in pairs(D.active) do
            if IsValid(d) and d:Health() > 0 and d.alertness == "unaware" and not d.stealth and not IsValid(d.target)
                and now - (d.lastSeenAt or -100) > 5 then
                if D.MakeUnaware(d) then
                    d.lastSeen, d.helpUntil, d.reinforceTo = nil, nil, nil
                    n = n + 1
                end
            end
        end
    end
    local msg = string.format(on and "Alarm raised: %d droid%s alerted" or "Alarm off: %d droid%s back to unaware", n, n == 1 and "" or "s")
    if IsValid(by) then msg = msg .. " (" .. by:Nick() .. ")" end
    print("[Droids] " .. msg)
    return n, msg
end

Rhylib.Command.Add({
    name = "rhylib_alarm", chat = { "alarm" }, perm = "rhylib.droids.alarm", minAccess = "admin", tag = "Droids",
    help = "Every unaware (stealth) droid becomes alert; \"off\": the ones that were unaware and aren't fighting go back to unaware", args = "[off]",
    fn = function(ply, args)
        local off = string.lower(tostring(args[1] or "")) == "off"
        local _, msg = D.Alarm(not off, IsValid(ply) and ply or nil)
        return msg
    end,
})

-- Switched off / on: what clients see follows (the setting itself is kept).
Rhylib.Hook.Add("Rhylib.ConfigChanged", "droids.stealth", function(m, k)
    if m ~= "droids" or k ~= "stealthOn" then return end
    local on = D.StealthOn()
    local CODE = D.SSTATE
    for npc in pairs(D.stealthy) do
        if IsValid(npc) and npc.stealth then setState(npc, on and (CODE[npc.stealth.state] or 1) or 0) end
    end
end)

--------------------------------------------------------------------------
-- What players and staff are sent
--------------------------------------------------------------------------

Rhylib.Net.Register("droids.seen")
Rhylib.Net.Register("droids.smeter")

-- Per player scratch (reused): n, ent[], v[], s[] (top 3 by meter), and
-- what was sent last.
local per = setmetatable({}, { __mode = "k" })
local function slot(ply)
    local b = per[ply]
    if not b then
        b = { n = 0, ent = {}, v = {}, s = {}, ln = 0, lent = {}, lq = {}, ls = {} }
        per[ply] = b
    end
    return b
end

local function writeItems(b, n)
    net.WriteUInt(n, 2)
    for i = 1, n do
        net.WriteUInt(b.ent[i]:EntIndex(), 13)
        net.WriteUInt(math.Clamp(math.floor(b.v[i] * 255 + 0.5), 0, 255), 8)
        net.WriteUInt(b.s[i], 2)
    end
end

sendSpotted = function(ply)
    if D.Cfg("stealthHud") == "none" then return end
    Rhylib.Net.Start("droids.seen")
    net.WriteBool(true)
    net.WriteUInt(0, 2)
    net.Send(ply)
    local b = slot(ply)
    b.ln = 0
end

local staff, staffAt = {}, 0
local sOut = { ent = {}, q = {} }
local sLast = { n = 0, ent = {}, q = {}, staffN = 0, staff = {} }

timer.Create("Rhylib.Droids.StealthNet", 0.25, 0, function()
    local mode = D.Cfg("stealthHud")
    local now = CurTime()
    for _, b in pairs(per) do b.n = 0 end
    local sn = 0
    local on = D.StealthOn()
    if on then
        for npc in pairs(D.stealthy) do
            local st = IsValid(npc) and npc.stealth
            if not st then
                D.stealthy[npc] = nil
            else
                local top = 0
                local code = (st.state == "unaware") and 1 or 2
                for i = 1, 3 do
                    local x = st.e[i]
                    local v = x.v
                    if v > 0.004 and IsValid(x.ent) then
                        if v > top then top = v end
                        -- (arcs point at the droid: only ones that saw you in the
                        -- last half second, never hearing alone or through walls)
                        if x.ent:IsPlayer() and mode ~= "none" and (mode ~= "arcs" or now - (x.sightAt or -100) < 0.5) then
                            -- (keep this player's top 3, highest first)
                            local b = slot(x.ent)
                            local n = b.n
                            local j = n + 1
                            while j > 1 and b.v[j - 1] < v do j = j - 1 end
                            if j <= 3 then
                                for k = math.min(n, 2), j, -1 do
                                    b.ent[k + 1], b.v[k + 1], b.s[k + 1] = b.ent[k], b.v[k], b.s[k]
                                end
                                b.ent[j], b.v[j], b.s[j] = npc, v, code
                                b.n = math.min(n + 1, 3)
                            end
                        end
                    end
                end
                if top > 0.004 and sn < 100 then
                    sn = sn + 1
                    sOut.ent[sn], sOut.q[sn] = npc, math.Clamp(math.floor(top * 255 + 0.5), 1, 255)
                end
            end
        end
    end
    -- Players: only on change, and an empty one when it ends.
    for ply, b in pairs(per) do
        if not IsValid(ply) then
            per[ply] = nil
        else
            local n = mode == "arcs" and b.n or math.min(b.n, 1)
            local changed = n ~= b.ln
            if not changed then
                for i = 1, n do
                    local q = math.floor(b.v[i] * 255 + 0.5)
                    if b.lent[i] ~= b.ent[i] or b.lq[i] ~= q or b.ls[i] ~= b.s[i] then changed = true break end
                end
            end
            if changed then
                Rhylib.Net.Start("droids.seen")
                net.WriteBool(false)
                writeItems(b, n)
                net.Send(ply)
                b.ln = n
                for i = 1, n do b.lent[i], b.lq[i], b.ls[i] = b.ent[i], math.floor(b.v[i] * 255 + 0.5), b.s[i] end
            end
        end
    end
    -- Staff holding the toolgun (list refreshed once a second).
    if now >= staffAt then
        staffAt = now + 1
        for i = #staff, 1, -1 do staff[i] = nil end
        for _, p in ipairs(player.GetHumans()) do
            local w = p:GetActiveWeapon()
            if IsValid(w) and w:GetClass() == "rhylib_toolgun" then staff[#staff + 1] = p end
        end
    end
    if #staff > 0 then
        -- (someone new took the toolgun out: send it all again)
        local changed = sn ~= sLast.n or #staff ~= sLast.staffN
        if not changed then
            for i = 1, #staff do
                if sLast.staff[i] ~= staff[i] then changed = true break end
            end
        end
        if not changed then
            for i = 1, sn do
                if sLast.ent[i] ~= sOut.ent[i] or sLast.q[i] ~= sOut.q[i] then changed = true break end
            end
        end
        if changed then
            Rhylib.Net.Start("droids.smeter")
            net.WriteUInt(sn, 7)
            for i = 1, sn do
                net.WriteUInt(sOut.ent[i]:EntIndex(), 13)
                net.WriteUInt(sOut.q[i], 8)
            end
            net.Send(staff)
            sLast.n, sLast.staffN = sn, #staff
            for i = 1, #staff do sLast.staff[i] = staff[i] end
            for i = 1, sn do sLast.ent[i], sLast.q[i] = sOut.ent[i], sOut.q[i] end
        end
    end
end)
