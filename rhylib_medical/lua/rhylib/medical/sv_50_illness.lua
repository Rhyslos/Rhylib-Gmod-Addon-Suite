--[[
    Illness (server): infections, symptoms, blood samples, the analyser,
    test strips and dosing. See sh_50_illness.lua for the rules.

    Med.ill[ply] = { kind, load } (saved as Data "med_ill"/sid, so leaving
    doesn't cure it). A 30 s timer grows the load and plays the symptoms.

    Network (client asks, server checks):
      ill.draw   (target)            start drawing blood (timed)
      ill.scan   (analyser, uid)     analyse a carried sample (timed)
      ill.strip  (uid)               test a sample on a strip
      ill.dose   (target, med 2 bits, units 6 bits)   give medicine (timed)
      ill.open   server -> client: the analyser window for that entity
      ill.stop   server -> client: a timed step was cancelled
]]

local Med = Rhylib.Medical
local Data = Rhylib.Data

local function cfg(k) return Med.Cfg(k) end
local function Inv() return Rhylib.Inventory end

Rhylib.Net.Register("ill.open")
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
    local s = Med.ill[ply]
    if s then
        Data.Set("med_ill", sid(ply), { k = s.kind, l = math.Round(s.load, 1) })
    else
        Data.Delete("med_ill", sid(ply))
    end
end

-- kind 1-3, load 1-100 (default 40). Infecting again replaces it.
function Med.Infect(ply, kind, load)
    if not (IsValid(ply) and Med.ILL[kind]) then return false end
    Med.ill[ply] = { kind = kind, load = math.Clamp(tonumber(load) or 40, 1, 100) }
    publish(ply)
    save(ply)
    return true
end

function Med.Cure(ply)
    if not IsValid(ply) then return end
    local had = Med.ill[ply] ~= nil
    Med.ill[ply] = nil
    publish(ply)
    if had then save(ply) end
end

function Med.Illness(ply)
    return Med.ill[ply]
end

Rhylib.Hook.Add("PlayerInitialSpawn", "medical.illness", function(ply)
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
    local rates = cfg("loadRate") or {}
    for ply, s in pairs(Med.ill) do
        if not IsValid(ply) then
            Med.ill[ply] = nil
        elseif ply:Alive() then
            local k = Med.ILL[s.kind]
            s.load = math.min(100, s.load + (tonumber(rates[s.kind]) or 0.5) * 0.5)
            local stage = stageOf(s.load)
            -- Poison at full load: down (then it eases so it can be treated).
            if s.kind == Med.ILL_POISON and s.load >= 100 then
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
    return IsValid(ply) and ply:Alive() and not Med.IsDown(ply) and not (Inv() and Inv().Locked and Inv().Locked(ply))
end

-- uid: the analyser sample that stopped (0 = a drawing or dose).
local function stop(ply, msg, uid)
    if msg then Med.Note(ply, msg) end
    Rhylib.Net.Start("ill.stop")
    net.WriteUInt(uid or 0, Rhylib.Items.UID_BITS)
    net.Send(ply)
end

-- A timed step: check() every 0.1 s (false = cancelled), done() at the
-- end, cancelled() whenever it doesn't finish.
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

local function sampleNote(d)
    local who = tostring(d.who or "?")
    if utf8.len(who) and utf8.len(who) > 22 then who = string.sub(who, 1, (utf8.offset(who, 23) or 23) - 1) .. "…" end
    local parts = { who }
    parts[#parts + 1] = d.reading or "not analysed"
    if d.colour then parts[#parts + 1] = "strip: " .. d.colour end
    return table.concat(parts, " · ")
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
    local t = net.ReadEntity()
    if not (able(ply) and Med.IsMedic(ply) and IsValid(t) and t:IsPlayer() and t ~= ply) then return end
    if not Med.OnSofa(t) then return stop(ply, "They need to lie on a med sofa") end
    if not near(ply, t, 150) then return stop(ply) end
    if (Inv() and Inv().Count(ply, Med.BLOOD_KIT) or 0) < 1 then return stop(ply, "You need a blood sample kit") end
    local secs = cfg("drawTime") * (chemist(ply) and 0.67 or 1)
    timed(ply, "draw", secs, function()
        if not (able(ply) and IsValid(t) and Med.OnSofa(t) and near(ply, t, 170)) then return false, "Cancelled" end
        return true
    end, function()
        if not takeOne(ply, Med.BLOOD_KIT) then return stop(ply, "You need a blood sample kit") end
        local s = Med.ill[t]
        local data = { sid = sid(t), who = t:Nick(), kind = s and s.kind or 0, load = s and math.floor(s.load) or 0 }
        data.note = sampleNote(data)
        local left = Inv().AddItem(ply, Med.SAMPLE, 1, data)
        if left > 0 then Inv().AddOrDrop(ply, Med.SAMPLE, left, data) end
        ply:EmitSound("items/medshot4.wav", 60, 115)
        Med.Note(ply, "Blood sample from " .. t:Nick())
    end)
end, { rate = 3, burst = 3 })

--------------------------------------------------------------------------
-- 2. Analyser
--------------------------------------------------------------------------

function Med.AnalyserUse(ent, ply)
    if not (IsValid(ply) and ply:IsPlayer() and able(ply)) then return end
    Rhylib.Net.Start("ill.open")
    net.WriteEntity(ent)
    net.Send(ply)
end

Rhylib.Net.Receive("ill.scan", function(ply)
    local ent, uid = net.ReadEntity(), net.ReadUInt(Rhylib.Items.UID_BITS)
    if not (able(ply) and Med.IsMedic(ply) and IsValid(ent) and ent:GetClass() == "rhylib_med_analyser" and near(ply, ent, 160)) then return end
    local inst = carriedItem(ply, uid, Med.SAMPLE)
    if not inst or inst.data.reading then return end
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
            local band = chemist(ply) and cfg("scanBandChemist") or cfg("scanBand")
            local shown = math.Clamp(math.Round(load + math.Rand(-band, band) * 0.7), 1, 100)
            o.data.reading = "infected, load " .. shown .. " ± " .. band
        end
        updateSample(ply, o)
        ent:EmitSound("buttons/button24.wav", 60, 110)
        Med.Note(ply, "Analysis: " .. o.data.reading)
    end, free, uid)
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- 3. Test strip (right-click the sample)
--------------------------------------------------------------------------

Rhylib.Net.Receive("ill.strip", function(ply)
    local uid = net.ReadUInt(Rhylib.Items.UID_BITS)
    if not able(ply) then return end
    local inst = carriedItem(ply, uid, Med.SAMPLE)
    if not inst or inst.data.colour then return end
    if not takeOne(ply, Med.STRIP) then return Med.Note(ply, "You need a test strip") end
    inst = carriedItem(ply, uid, Med.SAMPLE)
    if not inst then return end
    local k = Med.ILL[tonumber(inst.data.kind) or 0]
    inst.data.colour = k and k.colour or "clear"
    updateSample(ply, inst)
    ply:EmitSound("items/medshot4.wav", 55, 140)
    Med.Note(ply, "The strip turns " .. string.lower(inst.data.colour))
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- 4. Dosing
--------------------------------------------------------------------------

local function overdose(t, secs, hp)
    t:SetNW2Float("rhylib_overdose", CurTime() + secs)
    if hp > 0 then t:SetHealth(math.max(1, t:Health() - hp)) end
end

-- What a dose does: the right medicine within tolerance cures.
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
        t:EmitSound("items/medshot4.wav", 60, 100)
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
