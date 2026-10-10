--[[
    Illness (server): infections, symptoms, blood samples, the analyser,
    test strips and dosing. See sh_50_illness.lua for the rules.

    Med.ill[ply] = { kind, load, told } (saved as Data "med_ill"/SteamID64
    = { k = kind, l = load }, so leaving doesn't cure it; never saved for
    bots). A 30 s timer grows the load and plays the symptoms.

    Network (client asks, server checks; uid = item uid, Items.UID_BITS):
      ill.draw    (target)            start drawing blood (timed)
      ill.scan    (bench, uid)        analyse a carried sample (timed)
      ill.strip   (uid)               put a sample on a test strip
      ill.look    (uid)               show a used strip's result again
      ill.discard (uid)               throw away a sample or used strip
      ill.dose    (target, med 2 bits, units 6 bits)   give medicine (timed)
      ill.open    server -> client: the analyser window for that entity
      ill.cass    server -> client: the used strip window (uid, name,
                  elapsed s 16 bits, develop time 10, kind 2, load 7)
      ill.beep    server -> client: strip started (false) / ready (true) + name
      ill.stop    server -> client: a timed step was cancelled (uid or 0)

    Public: Med.Infect, Med.Cure, Med.Illness, Med.ApplyDose,
    Med.FindCassette, Med.SpoilSamples, Med.AnalyserUse.
]]

local Med = Rhylib.Medical
local Data = Rhylib.Data

local function cfg(k) return Med.Cfg(k) end
local function Inv() return Rhylib.Inventory end
-- (item uid size; rhylib_inventory may be missing: the illness flow then does nothing)
local function uidBits() return Rhylib.Items and Rhylib.Items.UID_BITS or 16 end

Rhylib.Net.Register("ill.open")
Rhylib.Net.Register("ill.cass")
Rhylib.Net.Register("ill.beep")
Rhylib.Net.Register("ill.stop")

Med.ill = Med.ill or {}   -- [ply] = { kind, load }

local function sid(ply) return ply:SteamID64() or ply:SteamID() end

local function stageOf(load)
    if load <= 0 then return 0 end
    if load < 35 then return 1 end
    if load < 70 then return 2 end
    return 3
end

-- What the patient notices as it gets worse (they never see the load).
local FEEL = {
    "You feel a bit off",
    "You feel sick: coughing, short of breath",
    "You feel really ill. Find a medic",
}

local function publish(ply)
    local s = Med.ill[ply]
    if s then
        local st = stageOf(s.load)
        if st > (s.told or 0) and FEEL[st] then ply:ChatPrint(FEEL[st]) end
        s.told = st
    end
    local v = s and (s.kind + stageOf(s.load) * 4) or 0
    if ply:GetNW2Int("rhylib_ill", 0) ~= v then ply:SetNW2Int("rhylib_ill", v) end
end

local function save(ply)
    if ply:IsBot() then return end   -- (bots share ids; a test dummy's illness must not come back on the next one)
    local s = Med.ill[ply]
    if s then
        Data.Set("med_ill", sid(ply), { k = s.kind, l = math.Round(s.load, 1) })
    else
        Data.Delete("med_ill", sid(ply))
    end
end

-- Med.Infect(ply, kind, load): makes ply ill. kind 1-3 (Med.ILL_VIRAL,
-- _BACTERIAL, _POISON), load 1-100 (default 40). Infecting again replaces
-- it. Returns false if refused (bad kind, simplified system). Server only.
-- Example: Rhylib.Medical.Infect(ply, Rhylib.Medical.ILL_POISON, 35)
function Med.Infect(ply, kind, load)
    if not (IsValid(ply) and Med.ILL[kind]) or Med.Simple() then return false end
    Med.ill[ply] = { kind = kind, load = math.Clamp(tonumber(load) or 40, 1, 100) }
    publish(ply)
    save(ply)
    return true
end

-- Med.Cure(ply): ends ply's illness (and its saved row). Server only.
function Med.Cure(ply)
    if not IsValid(ply) then return end
    local had = Med.ill[ply] ~= nil
    Med.ill[ply] = nil
    publish(ply)
    if had then save(ply) end
end

-- Med.Illness(ply): { kind, load, told } or nil. Read only. Server only.
function Med.Illness(ply)
    return Med.ill[ply]
end

Rhylib.Hook.Add("PlayerInitialSpawn", "medical.illness", function(ply)
    if ply:IsBot() then
        Data.Delete("med_ill", sid(ply))   -- (clears rows saved for bots before this fix)
        return
    end
    local d = Data.Get("med_ill", sid(ply))
    if istable(d) and Med.ILL[tonumber(d.k) or 0] then
        Med.ill[ply] = { kind = tonumber(d.k), load = math.Clamp(tonumber(d.l) or 40, 1, 100) }
        timer.Simple(1, function() if IsValid(ply) then publish(ply) end end)
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "medical.illness", function(ply)
    if Med.ill[ply] then save(ply) end
    Med.ill[ply] = nil
end)

--------------------------------------------------------------------------
-- Symptoms (every 30 s)
--------------------------------------------------------------------------

local COUGHS = { "ambient/voices/cough1.wav", "ambient/voices/cough2.wav", "ambient/voices/cough3.wav", "ambient/voices/cough4.wav" }

timer.Create("Rhylib.Medical.Illness", 30, 0, function()
    if Med.Simple() then return end   -- (simplified medical system: illnesses wait, no symptoms)
    local rates = cfg("loadRate") or {}
    for ply, s in pairs(Med.ill) do
        if not IsValid(ply) then
            Med.ill[ply] = nil
        elseif ply:Alive() then
            local k = Med.ILL[s.kind]
            -- loadRate is per minute; this runs every half minute.
            s.load = math.min(100, s.load + (tonumber(rates[s.kind]) or 0.5) * 0.5)
            local stage = stageOf(s.load)
            -- Poison at full load: down (then it eases so it can be treated).
            -- (nothing while Field triage mutes it)
            if Med.Muted and Med.Muted(ply) then
                -- muted
            elseif s.kind == Med.ILL_POISON and s.load >= 100 then
                s.load = cfg("poisonAfterDown")
                if not Med.IsDown(ply) and Med.Down then
                    ply:ChatPrint("The poison takes you down")
                    Med.Down(ply, ply, ply)
                end
            elseif not Med.IsDown(ply) then
                -- Slow drain, never below the kind's floor.
                local floor = math.max(1, math.floor(ply:GetMaxHealth() * k.floor))
                local drain = math.ceil(cfg("illDrain") * stage / 3)
                if drain > 0 and ply:Health() > floor then ply:SetHealth(math.max(floor, ply:Health() - drain)) end
                if stage > 0 and math.random() < 0.35 + stage * 0.15 then
                    timer.Simple(math.Rand(0, 20), function()
                        if IsValid(ply) and ply:Alive() and Med.ill[ply] then ply:EmitSound(COUGHS[math.random(#COUGHS)], 65, math.random(95, 108)) end
                    end)
                end
            end
            publish(ply)
            save(ply)
        end
    end
end)

--------------------------------------------------------------------------
-- Shared checks
--------------------------------------------------------------------------

local function near(a, b, r)
    if not (IsValid(a) and IsValid(b)) then return false end
    local pos = b:IsPlayer() and (Rhylib.Lying and Rhylib.Lying.BodyPos and Rhylib.Lying.BodyPos(b) or b:GetPos()) or b:GetPos()
    return a:GetPos():DistToSqr(pos) < r * r
end

local function able(ply)
    if Med.Simple() then return false end   -- (simplified medical system: no illness work)
    return IsValid(ply) and ply:Alive() and not Med.IsDown(ply) and not (Inv() and Inv().Locked and Inv().Locked(ply))
end

-- uid: the analyser sample that stopped (0 = a drawing or dose).
local function stop(ply, msg, uid)
    if msg then Med.Note(ply, msg) end
    Rhylib.Net.Start("ill.stop")
    net.WriteUInt(uid or 0, uidBits())
    net.Send(ply)
end

-- A timed step: check() every 0.1 s (false = cancelled), done() at the
-- end, cancelled() whenever it doesn't finish. Moving more than 40 units
-- from where it started cancels too. One timer per player and key, so
-- asking again restarts it.
local function timed(ply, key, secs, check, done, cancelled, uid)
    local name = "Rhylib.Medical.Ill." .. key .. "." .. ply:EntIndex()
    local ends, from = CurTime() + secs, ply:GetPos()
    timer.Create(name, 0.1, 0, function()
        if not IsValid(ply) then
            if cancelled then cancelled() end
            return timer.Remove(name)
        end
        local ok, why = check()
        if not ok or ply:GetPos():DistToSqr(from) > 40 * 40 then
            timer.Remove(name)
            if cancelled then cancelled() end
            return stop(ply, why or "Cancelled (you moved)", uid)
        end
        if CurTime() >= ends then
            timer.Remove(name)
            done()
        end
    end)
end

-- Chemists (the Chemistry skill opens the spec) do it better.
local function chemist(ply)
    return Med.Skill(ply, "chem_bench")
end

-- A carried item by uid with the given id.
local function carriedItem(ply, uid, id)
    local I = Inv()
    if not (I and I.Get) then return nil end
    local inst = I.Get(ply).byUid[uid]
    if inst and inst.id == id then return inst end
end

local function takeOne(ply, id)
    local I = Inv()
    for uid, o in pairs(I.Get(ply).byUid) do
        if o.id == id then
            I.Remove(ply, uid, 1)
            return true
        end
    end
    return false
end

local function shortName(who)
    who = tostring(who or "?")
    if utf8.len(who) and utf8.len(who) > 22 then who = string.sub(who, 1, (utf8.offset(who, 23) or 23) - 1) .. "…" end
    return who
end

local function sampleNote(d)
    local parts = { shortName(d.who) }
    parts[#parts + 1] = d.reading or (d.tested and "strip running" or "no strip yet")
    return table.concat(parts, " · ")
end

-- Seconds a strip takes: a worse infection shows sooner.
local function devTime(kind, load)
    local hi, lo = cfg("stripMax"), cfg("stripMin")
    if (kind or 0) == 0 or (load or 0) <= 0 then return hi end
    return math.Round(hi - (hi - lo) * math.Clamp(load / 100, 0, 1))
end

local function cassetteReady(d)
    return d and d.start and os.time() >= d.start + (d.dev or 0)
end

local function cassetteNote(d)
    return shortName(d.who) .. " · " .. (cassetteReady(d) and "result ready" or "developing")
end

local function updateSample(ply, inst)
    inst.data.note = sampleNote(inst.data)
    local I = Inv()
    I.Internal.update(ply, I.Get(ply), inst)
end

--------------------------------------------------------------------------
-- 1. Drawing blood (patient on a med sofa)
--------------------------------------------------------------------------

Rhylib.Net.Receive("ill.draw", function(ply)
    if not (Inv() and Inv().Get) then return end   -- (needs rhylib_inventory)
    local t = net.ReadEntity()
    if not (able(ply) and Med.IsMedic(ply) and IsValid(t) and t:IsPlayer() and t ~= ply) then return end
    if not (Med.OnSofa(t) or t.rhylibDummy) then return stop(ply, "They need to lie on a med sofa") end   -- (test dummies: standing is fine)
    if not near(ply, t, 150) then return stop(ply) end
    if (Inv() and Inv().Count(ply, Med.BLOOD_KIT) or 0) < 1 then return stop(ply, "You need a blood sample kit") end
    local secs = cfg("drawTime") * (chemist(ply) and 0.67 or 1)
    timed(ply, "draw", secs, function()
        if not (able(ply) and IsValid(t) and (Med.OnSofa(t) or t.rhylibDummy) and near(ply, t, 170)) then return false, "Cancelled" end
        return true
    end, function()
        if not takeOne(ply, Med.BLOOD_KIT) then return stop(ply, "You need a blood sample kit") end
        local s = Med.ill[t]
        local data = { sid = sid(t), who = t:Nick(), kind = s and s.kind or 0, load = s and math.floor(s.load) or 0,
            key = string.format("%08x", math.random(0, 0x7fffffff)), at = os.time() }
        data.note = sampleNote(data)
        local left = Inv().AddItem(ply, Med.SAMPLE, 1, data)
        if left > 0 then Inv().AddOrDrop(ply, Med.SAMPLE, left, data) end
        ply:EmitSound("weapons/2misc_non_guns/sw_syringe.ogg", 60, 115)
        Med.Note(ply, "Blood sample from " .. t:Nick())
    end)
end, { rate = 3, burst = 3 })

--------------------------------------------------------------------------
-- 2. Analyser
--------------------------------------------------------------------------

-- Med.AnalyserUse(ent, ply): opens the analyser window for ent on ply's
-- screen (net ill.open). (The bench itself opens it client side through
-- the wheel or its menu; nothing in this addon calls this now.)
function Med.AnalyserUse(ent, ply)
    if not (IsValid(ply) and ply:IsPlayer() and able(ply)) then return end
    Rhylib.Net.Start("ill.open")
    net.WriteEntity(ent)
    net.Send(ply)
end

Rhylib.Net.Receive("ill.scan", function(ply)
    if not (Inv() and Inv().Get) then return end   -- (needs rhylib_inventory)
    local ent, uid = net.ReadEntity(), net.ReadUInt(uidBits())
    if not (able(ply) and Med.IsMedic(ply) and IsValid(ent) and ent:GetClass() == "rhylib_chem_bench" and near(ply, ent, 160)) then return end
    local inst = carriedItem(ply, uid, Med.SAMPLE)
    if not inst or inst.data.reading then return end
    -- The analyser reads the sample together with its developed strip.
    local cas = Med.FindCassette(ply, inst.data.key)
    if not cas then return stop(ply, "Apply the sample to a test strip first, and keep the strip on you", uid) end
    if not cassetteReady(cas.data) then return stop(ply, "Its test strip is still developing", uid) end
    ply.rhylibScans = ply.rhylibScans or {}
    if ply.rhylibScans[uid] then return end   -- (already running)
    if ent:GetBusy() >= 4 then return stop(ply, "The analyser is full (4 samples)", uid) end
    ent:SetBusy(ent:GetBusy() + 1)
    ply.rhylibScans[uid] = true
    local secs = cfg("scanTime") * (chemist(ply) and 0.5 or 1)
    local function free()
        if IsValid(ent) then ent:SetBusy(math.max(0, ent:GetBusy() - 1)) end
        if IsValid(ply) and ply.rhylibScans then ply.rhylibScans[uid] = nil end
    end
    ply:EmitSound("buttons/button17.wav", 60, 100)
    timed(ply, "scan" .. uid, secs, function()
        if not (able(ply) and IsValid(ent) and near(ply, ent, 200) and carriedItem(ply, uid, Med.SAMPLE)) then
            return false, "Analysis stopped"
        end
        return true
    end, function()
        free()
        local o = carriedItem(ply, uid, Med.SAMPLE)
        if not o then return end
        local load = tonumber(o.data.load) or 0
        if load <= 0 or (tonumber(o.data.kind) or 0) == 0 then
            o.data.reading = "no infection"
        else
            -- Shown as the dose it needs (load / 5 units), give or take a band.
            -- band = scanBand / 5 rounded (at least 1 unit); the shown number
            -- is off by up to 0.7 × band before rounding.
            local band = math.max(1, math.Round((chemist(ply) and cfg("scanBandChemist") or cfg("scanBand")) / 5))
            local shown = math.max(1, math.Round(load / 5 + math.Rand(-band, band) * 0.7))
            o.data.reading = "infected, dose ~" .. shown .. " units (± " .. band .. ")"
        end
        updateSample(ply, o)
        ent:EmitSound("buttons/button24.wav", 60, 110)
        Med.Note(ply, "Analysis: " .. o.data.reading)
    end, free, uid)
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- 3. Test strip (right-click the sample): a used strip item that develops
--    over stripMin-stripMax seconds (worse = sooner). control channel = it works,
--    a lit test channel = infected (colour = kind). The analyser needs the
--    developed strip with its sample.
--------------------------------------------------------------------------

-- Med.FindCassette(ply, key): the used strip in ply's inventory made from
-- the sample with this data.key, or nil. Needs rhylib_inventory.
function Med.FindCassette(ply, key)
    if not key then return nil end
    for _, o in pairs(Inv().Get(ply).byUid) do
        if o.id == Med.CASSETTE and o.data and o.data.key == key then return o end
    end
end

-- The strip beeps for its medic: when it starts and when the result is in
-- (with a note naming whose it is), window open or not.
local function beep(ply, done, who)
    Rhylib.Net.Start("ill.beep")
    net.WriteBool(done)
    net.WriteString(who or "")
    net.Send(ply)
end

local function sendCassette(ply, inst)
    local d = inst.data
    Rhylib.Net.Start("ill.cass")
    net.WriteUInt(inst.uid, uidBits())
    net.WriteString(shortName(d.who))
    net.WriteUInt(math.Clamp(os.time() - (d.start or os.time()), 0, 65535), 16)
    net.WriteUInt(math.Clamp(d.dev or 120, 1, 1023), 10)
    net.WriteUInt(tonumber(d.kind) or 0, 2)
    net.WriteUInt(math.Clamp(math.floor(tonumber(d.load) or 0), 0, 100), 7)
    net.Send(ply)
end

Rhylib.Net.Receive("ill.strip", function(ply)
    if not (Inv() and Inv().Get) then return end   -- (needs rhylib_inventory)
    local uid = net.ReadUInt(uidBits())
    if not able(ply) then return end
    local inst = carriedItem(ply, uid, Med.SAMPLE)
    if not inst or inst.data.tested then return end
    if not takeOne(ply, Med.STRIP) then return Med.Note(ply, "You need a test strip") end
    inst = carriedItem(ply, uid, Med.SAMPLE)
    if not inst then return end
    local d = inst.data
    d.key = d.key or string.format("%08x", math.random(0, 0x7fffffff))
    d.tested = true
    updateSample(ply, inst)
    local cd = { key = d.key, who = d.who, kind = d.kind, load = d.load, start = os.time(), dev = devTime(d.kind, d.load), at = os.time() }
    cd.note = cassetteNote(cd)
    Inv().AddOrDrop(ply, Med.CASSETTE, 1, cd)
    ply:EmitSound("weapons/2misc_non_guns/sw_syringe.ogg", 55, 140)
    local cas = Med.FindCassette(ply, d.key)
    if cas then sendCassette(ply, cas) end
    beep(ply, false)
    -- Once developed: its note says "result ready" and it beeps.
    local key = d.key
    timer.Simple(cd.dev + 0.5, function()
        if not IsValid(ply) then return end
        local c = Med.FindCassette(ply, key)
        if c then
            c.data.note = cassetteNote(c.data)
            Inv().Internal.update(ply, Inv().Get(ply), c)
            beep(ply, true, shortName(c.data.who))
        end
    end)
end, { rate = 4, burst = 4 })

-- Look at a used strip again.
Rhylib.Net.Receive("ill.look", function(ply)
    if not (Inv() and Inv().Get) then return end   -- (needs rhylib_inventory)
    if Med.Simple() then return end
    local inst = carriedItem(ply, net.ReadUInt(uidBits()), Med.CASSETTE)
    if inst then sendCassette(ply, inst) end
end, { rate = 4, burst = 4 })

-- Throw away a sample or a used strip.
Rhylib.Net.Receive("ill.discard", function(ply)
    if not (Inv() and Inv().Get) then return end   -- (needs rhylib_inventory)
    local uid = net.ReadUInt(uidBits())
    local inst = carriedItem(ply, uid, Med.SAMPLE) or carriedItem(ply, uid, Med.CASSETTE)
    if inst then Inv().Remove(ply, uid) end
end, { rate = 6, burst = 6 })

-- Med.SpoilSamples(): removes samples and used strips older than
-- sampleLife (data.at, os.time) from every player. Runs every 30 s.
function Med.SpoilSamples()
    local life = cfg("sampleLife")
    local now = os.time()
    local I = Inv()
    if not (I and I.Get) then return end
    for _, ply in ipairs(player.GetHumans()) do
        local old = {}
        for uid, o in pairs(I.Get(ply).byUid) do
            if (o.id == Med.SAMPLE or o.id == Med.CASSETTE) and o.data and o.data.at and now - o.data.at > life then old[#old + 1] = uid end
        end
        for _, uid in ipairs(old) do I.Remove(ply, uid) end
        if #old > 0 then Med.Note(ply, #old == 1 and "An old blood test spoiled" or (#old .. " old blood tests spoiled")) end
    end
end
timer.Create("Rhylib.Medical.Spoil", 30, 0, function() Med.SpoilSamples() end)

--------------------------------------------------------------------------
-- 4. Dosing
--------------------------------------------------------------------------

local function overdose(t, secs, hp)
    t:SetNW2Float("rhylib_overdose", CurTime() + secs)
    if hp > 0 then t:SetHealth(math.max(1, t:Health() - hp)) end
end

-- Med.ApplyDose(t, medId, units, by): what a dose does to patient t.
-- Right dose = load / 5 units, tolerance max(1, doseTolerance × it).
-- Returns "no effect" (wrong medicine or not ill: 15 s blur, -5 HP),
-- "too little" (load drops by units × 5), "cured", or "too much" (cured,
-- 30 s blur, 10-60 HP; over twice the dose also downs them, no frag).
-- `by` (the medic) is not used. Server only.
function Med.ApplyDose(t, medId, units, by)
    local s = Med.ill[t]
    local k = s and Med.ILL[s.kind]
    if not k or k.medicine ~= medId then
        overdose(t, 15, 5)   -- (wrong medicine: a mild side effect, nothing else)
        return "no effect"
    end
    local right = math.max(1, s.load / 5)
    local tol = math.max(1, right * cfg("doseTolerance"))
    if units < right - tol then
        s.load = math.max(1, s.load - units * 5)
        publish(t)
        save(t)
        return "too little"
    end
    Med.Cure(t)
    if units > right + tol then
        local over = (units - right) / right
        overdose(t, 30, math.Clamp(math.floor(10 + over * 40), 10, 60))
        if units > right * 2 and Med.Down and not Med.IsDown(t) then Med.Down(t, t, t) end   -- (not the medic's kill)
        return "too much"
    end
    return "cured"
end

Rhylib.Net.Receive("ill.dose", function(ply)
    if not (Inv() and Inv().Get) then return end   -- (needs rhylib_inventory)
    local t, which, units = net.ReadEntity(), net.ReadUInt(2), net.ReadUInt(6)
    if not (able(ply) and Med.IsMedic(ply) and IsValid(t) and t:IsPlayer() and t:Alive()) then return end
    local m = Med.MEDICINES[which + 1]
    if not m or units < 1 then return end
    local medId = m[1]
    if not near(ply, t, 150) then return stop(ply) end
    if (Inv().Count(ply, medId) or 0) < units then return stop(ply, "You don't carry that much") end
    timed(ply, "dose", cfg("doseTime"), function()
        if not (able(ply) and IsValid(t) and t:Alive() and near(ply, t, 170)) then return false, "Cancelled" end
        return true
    end, function()
        local I = Inv()
        if (I.Count(ply, medId) or 0) < units then return stop(ply, "You don't carry that much") end
        local left = units
        for uid, o in pairs(I.Get(ply).byUid) do
            if left <= 0 then break end
            if o.id == medId then
                local n = math.min(left, o.count)
                I.Remove(ply, uid, n)
                left = left - n
            end
        end
        local result = Med.ApplyDose(t, medId, units, ply)
        t:EmitSound("weapons/2misc_non_guns/sw_syringe.ogg", 60, 100)
        -- The medic only learns what the patient shows.
        Med.Note(ply, units .. " units of " .. m[2] .. " given to " .. t:Nick())
        if result == "too much" or result == "no effect" then
            t:ChatPrint("You feel sick and dizzy")
        elseif result == "cured" then
            t:ChatPrint("You start to feel better")
        else
            t:ChatPrint("You feel a little better")
        end
    end)
end, { rate = 3, burst = 3 })
