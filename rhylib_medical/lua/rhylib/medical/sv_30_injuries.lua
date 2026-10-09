--[[
    Injuries, server side (see sh_30_injuries.lua for the model).

    Damage -> body part:
      fall damage        both legs (a hard fall breaks one)
      blast and fire     spread over the body as damage and burns
      everything else    the part that was hit (rhylib bolts tag the hit
                         group; engine bullets use LastHitGroup). Models
                         with only "generic" hitboxes: guessed from the
                         damage position (Rhylib.HitGroupAt), else a
                         random part (torso most likely)
    Once a second, only for injured players: bleeding takes health (a
    bleed that would kill downs you instead), light bleeds stop after a
    while, and parts with nothing else wrong slowly recover.
    State goes to the owner, and to anyone with the owner's H menu open
    (in range, in sight), at most once per tick, when it changes.
]]

local Med = Rhylib.Medical
local Config = Rhylib.Config
local function cfg(k) return Config.Get("medical", k) end

Med.inj = Med.inj or {}          -- [ply] = { [limb] = part }; nil when unhurt
local inj = Med.inj
local dirty = {}
Med.viewers = Med.viewers or {}  -- [patient] = { [viewer] = true }
local viewers = Med.viewers

Rhylib.Net.Register("med.inj")

local function sendTo(patient, recipients)
    Rhylib.Net.Start("med.inj")
    net.WriteEntity(patient)
    Med.WriteInjuries(inj[patient])
    net.Send(recipients)
end

-- Still allowed to look at this patient?
local function canView(viewer, patient)
    if not (IsValid(viewer) and IsValid(patient) and viewer:Alive() and patient:Alive()) then return false end
    if viewer.rhylibDown then return false end
    local r = Config.Get("medical", "viewRange") * 1.5
    if viewer:GetPos():DistToSqr(patient:GetPos()) > r * r then return false end
    return Med.CanSee(viewer, patient)
end

local function newState()
    local t = {}
    for _, l in ipairs(Med.LIMBS) do t[l] = { dmg = 0, bleed = 0, frac = false, splint = false, burn = 0, bleedEnd = 0 } end
    return t
end

local function getState(ply)
    local t = inj[ply]
    if not t then
        t = newState()
        inj[ply] = t
    end
    return t
end

local function healthy(t)
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p.dmg > 0 or p.bleed > 0 or p.frac or p.burn > 0 then return false end
    end
    return true
end

-- What the owner last got, as whole numbers (as sent over the net), so
-- tiny changes aren't sent. Each part packs into one number below 122412;
-- three parts fit exactly in one double, so six parts make two numbers.
local SIG_BASE = 122412
local function packPart(p)
    local frac = p.frac and (p.splint and 2 or 1) or 0
    local dmg = math.Clamp(math.ceil(p.dmg), 0, 100)
    local burn = math.Clamp(math.ceil(p.burn), 0, 100)
    return ((dmg * 4 + math.Clamp(p.bleed, 0, 3)) * 3 + frac) * 101 + burn
end

local function signature(t)
    if not t then return -1, -1 end
    local a, b = 0, 0
    for i, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p then
            if i <= 3 then a = a * SIG_BASE + packPart(p) else b = b * SIG_BASE + packPart(p) end
        end
    end
    return a, b
end

function Med.MarkInjuries(ply)
    local t = inj[ply]
    if t and healthy(t) then inj[ply] = nil end
    dirty[ply] = true
end

Rhylib.Hook.Add("Tick", "medical.injuries.send", function()
    if next(dirty) == nil then return end
    for ply in pairs(dirty) do
        dirty[ply] = nil
        if IsValid(ply) then
            local sa, sb = signature(inj[ply])
            if sa ~= ply.rhylibInjSigA or sb ~= ply.rhylibInjSigB then
                ply.rhylibInjSigA, ply.rhylibInjSigB = sa, sb
                local list = { ply }
                local v = viewers[ply]
                if v then
                    for viewer in pairs(v) do
                        if canView(viewer, ply) then list[#list + 1] = viewer else v[viewer] = nil end
                    end
                    if next(v) == nil then viewers[ply] = nil end
                end
                sendTo(ply, list)
            end
        end
    end
end)

function Med.ClearInjuries(ply)
    if IsValid(ply) and ply:GetNW2Float("rhylib_painkill", 0) ~= 0 then ply:SetNW2Float("rhylib_painkill", 0) end
    if inj[ply] then
        inj[ply] = nil
        dirty[ply] = true
    end
end

--------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------

local GROUP_LIMB = {
    [HITGROUP_HEAD] = "head",
    [HITGROUP_CHEST] = "torso", [HITGROUP_STOMACH] = "torso", [HITGROUP_GENERIC] = "torso", [HITGROUP_GEAR] = "torso",
    [HITGROUP_LEFTARM] = "larm", [HITGROUP_RIGHTARM] = "rarm",
    [HITGROUP_LEFTLEG] = "lleg", [HITGROUP_RIGHTLEG] = "rleg",
}
-- How blast and fire spread over the body.
local SPREAD = { head = 0.1, torso = 0.3, larm = 0.15, rarm = 0.15, lleg = 0.15, rleg = 0.15 }
local IS_LIMB = { larm = true, rarm = true, lleg = true, rleg = true }
-- No idea where it hit: a random part, torso most often.
local RANDOM_LIMB = { "torso", "torso", "torso", "head", "larm", "rarm", "lleg", "rleg" }

-- Can this part break? (rhylib_skills Hard landings: legs never do;
-- other addons can answer Rhylib.CanFracture(ply, limb) with false, or
-- Rhylib.FractureChance(ply, limb) with a 0-1 chance: rhylib_gear's kama.)
local function canBreak(ply, limb)
    if limb == "lleg" or limb == "rleg" then
        local K = Rhylib.Skills
        if K and K.Has and K.Has(ply, "hard_landings") then return false end
    end
    if hook.Run("Rhylib.CanFracture", ply, limb) == false then return false end
    local chance = hook.Run("Rhylib.FractureChance", ply, limb)   -- (a local: tonumber() of no value errors)
    chance = tonumber(chance)
    if chance and math.random() >= chance then return false end
    return true
end
Med.CanFracture = canBreak

local function hurt(ply, t, limb, amount, canBleed, now)
    local p = t[limb]
    p.dmg = math.min(100, p.dmg + amount)
    if canBleed then
        if amount >= cfg("heavyBleedAt") or p.dmg >= 80 then
            p.bleed = 2
        elseif amount >= cfg("lightBleedAt") and p.bleed < 1 then
            p.bleed = 1
            p.bleedEnd = now + cfg("lightBleedStops")
        end
    end
    if IS_LIMB[limb] and amount >= cfg("fractureAt") and canBreak(ply, limb) then
        p.frac, p.splint = true, false
    end
end

Rhylib.Hook.Add("PostEntityTakeDamage", "medical.injuries", function(ply, dmg, took)
    if not took or not ply:IsPlayer() or ply.rhylibBleedTick then return end
    if not cfg("injuries") or Med.Simple() or not ply:Alive() then
        ply.rhylibHitGroup = nil
        return
    end
    local amount = dmg:GetDamage()
    if amount <= 0 then return end
    local now = CurTime()
    local t = getState(ply)
    local dtype = dmg:GetDamageType()

    if bit.band(dtype, DMG_FALL) ~= 0 then
        hurt(ply, t, "lleg", amount * 0.6, false, now)
        hurt(ply, t, "rleg", amount * 0.6, false, now)
        local leg = math.random(2) == 1 and "lleg" or "rleg"
        if amount >= cfg("fallFractureAt") and canBreak(ply, leg) then
            t[leg].frac, t[leg].splint = true, false
        end
    elseif bit.band(dtype, bit.bor(DMG_BLAST, DMG_BURN, DMG_SLOWBURN, DMG_PLASMA)) ~= 0 then
        for limb, share in pairs(SPREAD) do
            -- (hook Rhylib.BlastPartMult(ply, limb): rhylib_gear's kama shields the legs)
            local m = 1
            if bit.band(dtype, DMG_BLAST) ~= 0 then
                local hm = hook.Run("Rhylib.BlastPartMult", ply, limb)
                m = tonumber(hm) or 1
            end
            hurt(ply, t, limb, amount * share * m, false, now)
            t[limb].burn = math.min(100, t[limb].burn + amount * share * m)
        end
    else
        local group = ply.rhylibHitGroup or ply:LastHitGroup()
        if (not group or group == HITGROUP_GENERIC) and Rhylib.HitGroupAt then
            group = Rhylib.HitGroupAt(ply, dmg:GetDamagePosition())
        end
        local limb = GROUP_LIMB[group]
        if not limb or group == HITGROUP_GENERIC then limb = RANDOM_LIMB[math.random(#RANDOM_LIMB)] end
        hurt(ply, t, limb, amount, bit.band(dtype, bit.bor(DMG_BULLET, DMG_SLASH, DMG_CLUB, DMG_GENERIC, DMG_BUCKSHOT, DMG_SNIPER)) ~= 0 or dtype == 0, now)
        -- Torso hits knock the wind out of you.
        -- (not with the Shock Assault skill)
        local K = Rhylib.Skills
        if limb == "torso" and Rhylib.Stamina and Rhylib.Stamina.Drain and not Med.Muted(ply)
            and not (K and K.Has and K.Has(ply, "shock_assault")) then
            Rhylib.Stamina.Drain(ply, amount * cfg("torsoStaminaHit"))
        end
    end
    ply.rhylibHitGroup = nil
    Med.MarkInjuries(ply)
end, 50)

Rhylib.Hook.Add("PlayerSpawn", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerDeath", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerSilentDeath", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerDisconnected", "medical.injuries", function(ply)
    inj[ply] = nil
    dirty[ply] = nil
    viewers[ply] = nil
    for _, v in pairs(viewers) do v[ply] = nil end
end)

-- Opening (or closing, with no patient) someone's injury menu.
Rhylib.Net.Receive("med.view", function(ply)
    local patient = net.ReadEntity()
    for p, v in pairs(viewers) do
        v[ply] = nil
        if next(v) == nil then viewers[p] = nil end
    end
    if not (IsValid(patient) and patient:IsPlayer() and patient ~= ply) or Med.Simple() then return end
    local r = Config.Get("medical", "viewRange")
    if not ply:Alive() or ply.rhylibDown or ply:GetPos():DistToSqr(patient:GetPos()) > r * r or not Med.CanSee(ply, patient) then return end
    viewers[patient] = viewers[patient] or {}
    viewers[patient][ply] = true
    sendTo(patient, ply)  -- what they look like now
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- Bleeding and recovery (once a second, injured players only)
--------------------------------------------------------------------------

-- Health lost per second from bleeding right now.
function Med.BleedRate(ply)
    local t = inj[ply]
    if not t then return 0 end
    local r = 0
    for _, l in ipairs(Med.LIMBS) do
        local b = t[l].bleed
        if b == 1 then r = r + cfg("lightBleed") elseif b == 2 then r = r + cfg("heavyBleed") end
    end
    return r
end

local function bleedDamage(ply, amount)
    local hp = ply:Health()
    if hp - amount >= 1 then
        ply:SetHealth(math.floor(hp - amount + 0.5))
        return
    end
    -- Would bleed to death: a real hit, so rhylib_medical downs them.
    ply.rhylibBleedTick = true
    local d = DamageInfo()
    d:SetDamage(amount)
    d:SetDamageType(DMG_DIRECT)
    d:SetAttacker(game.GetWorld())
    d:SetInflictor(game.GetWorld())
    ply:TakeDamageInfo(d)
    ply.rhylibBleedTick = nil
end

timer.Create("Rhylib.Medical.Injuries", 1, 0, function()
    if next(inj) == nil or Med.Simple() then return end
    local now = CurTime()
    local light, heavy = cfg("lightBleed"), cfg("heavyBleed")
    local rec, burnRec = cfg("recover"), cfg("burnRecover")
    for ply, t in pairs(inj) do
        if not IsValid(ply) then
            inj[ply] = nil
        elseif ply:Alive() then
            local loss = 0
            for _, l in ipairs(Med.LIMBS) do
                local p = t[l]
                if p.bleed == 1 and now >= p.bleedEnd then p.bleed = 0 end
                if p.bleed == 1 then loss = loss + light elseif p.bleed == 2 then loss = loss + heavy end
                if p.burn > 0 then p.burn = math.max(0, p.burn - burnRec) end
                if p.bleed == 0 and not p.frac and p.burn <= 0 and p.dmg > 0 then
                    p.dmg = math.max(0, p.dmg - rec)
                end
            end
            -- (a treatment whose helper is gone no longer counts)
            if ply.rhylibTreated and not IsValid(ply:GetNW2Entity("rhylib_healBy")) then ply.rhylibTreated = nil end
            -- Bleeding while down is the bleed-out timer's job; none while being treated.
            -- (no bleeding while Field triage mutes afflictions)
            if loss > 0 and not ply.rhylibDown and not ply.rhylibTreated and not Med.Muted(ply) then
                -- Keep the fraction so slow bleeds still add up.
                ply.rhylibBleedAcc = (ply.rhylibBleedAcc or 0) + loss
                local whole = math.floor(ply.rhylibBleedAcc)
                if whole >= 1 then
                    ply.rhylibBleedAcc = ply.rhylibBleedAcc - whole
                    bleedDamage(ply, whole)
                end
            end
            Med.MarkInjuries(ply)
        end
    end
end)

--------------------------------------------------------------------------
-- Treatment from the H menu
--------------------------------------------------------------------------

local function nothingWrong(p)
    return not p or (p.dmg <= 0 and p.bleed == 0 and not p.frac and p.burn <= 0)
end

-- What's wrong that this item can't help with, or nil if it can.
-- p: the part (may be nil), hurtHP: missing health.
local function wontHelp(kit, p, hurtHP, helper, patient)
    local medic = Med.IsMedic(helper)
    if kit == Med.MEDKIT then
        -- Medkits stop bleeding and give health; medics also heal damage and burns.
        local canBleed = p and p.bleed > 0
        local canHeal = hurtHP or (medic and p and (p.dmg > 0 or p.burn > 0))
        if not canBleed and not canHeal then
            return medic and "A medkit can't set bones; use a first aid kit" or "A medkit can't fix that: find a medic"
        end
    elseif kit == Med.SPLINT then
        if not (p and p.frac) then return "Nothing broken there" end
        if p.splint then return "Already splinted: the med bay can set it" end
    elseif kit == Med.BURN_GEL then
        if not (p and p.burn > 0) then return "No burns there" end
    elseif kit == Med.FIRST_AID then
        -- Only a splinted bone left, away from the med bay: nothing to gain.
        if p and p.splint and not hurtHP and p.dmg <= 0 and p.bleed == 0 and p.burn <= 0
            and not (Med.InMedBay(patient) or Med.Skill(helper, "field_surgeon")) then
            return "Already splinted: the med bay can set it"
        end
    end
end

-- The effect of a part treatment, when its timer ends (sv_20_actions.lua).
function Med.TreatPart(helper, patient, limb, kit)
    local t = getState(patient)
    local p = t[limb]
    local name = Med.LIMB_NAMES[limb] or "Part"
    local medic = Med.IsMedic(helper)
    -- Nothing left to do by now (healed meanwhile): no kit used.
    local hurtHP = patient:Health() < patient:GetMaxHealth()
    if nothingWrong(p) and not hurtHP and kit ~= Med.PAINKILLER then
        Med.Note(helper, name .. ": nothing left to treat")
        Med.MarkInjuries(patient)
        return
    end
    local why = wontHelp(kit, p, hurtHP, helper, patient)
    if why then
        Med.Note(helper, why)
        return
    end
    if kit == Med.FIRST_AID then
        -- Fixes the part; heals some health from the charge. Bones and
        -- burns only fully in the med bay (or with Field surgeon).
        local want = math.min(cfg("firstAidLimbHealth"), patient:GetMaxHealth() - patient:Health())
        local have = Med.KitCharge(helper)
        local hp = math.max(0, math.min(want, have))
        Med.SpendCharge(helper, math.min(have, math.max(hp, cfg("firstAidMinCost"))))
        local full = Med.InMedBay(patient) or Med.Skill(helper, "field_surgeon")
        local partial = not full and (p.frac or p.burn > 0)
        p.dmg, p.bleed = 0, 0
        if full then
            p.frac, p.splint, p.burn = false, false, 0
        else
            if p.frac then p.splint = true end
            p.burn = math.floor(p.burn * 0.5)
        end
        patient:SetHealth(math.min(patient:GetMaxHealth(), patient:Health() + math.floor(hp + 0.5)))
        Med.Note(helper, name .. (partial and " patched up: the med bay can finish it" or " treated"))
    elseif kit == Med.MEDKIT then
        if not Med.Consume(helper, Med.MEDKIT) then return end
        local bled = p.bleed > 0
        p.bleed = 0
        patient:SetHealth(math.min(patient:GetMaxHealth(), patient:Health() + (medic and cfg("medkitHealMedic") or cfg("medkitHeal"))))
        if medic then
            local r = cfg("medkitLimbRepair")
            p.dmg = math.max(0, p.dmg - r)
            p.burn = math.max(0, p.burn - r)
        end
        Med.Note(helper, name .. (medic and " patched up" or (bled and ": bleeding stopped" or " bandaged")))
    else
        if not Med.Consume(helper, kit) then return end
        if kit == Med.SPLINT then
            p.splint = true
            Med.Note(helper, name .. " splinted")
        elseif kit == Med.BURN_GEL then
            p.burn = math.max(0, p.burn - cfg("burnGel"))
            Med.Note(helper, name .. ": burn gel on")
        elseif kit == Med.PAINKILLER then
            patient:SetNW2Float("rhylib_painkill", CurTime() + cfg("painkillerTime"))
            Med.Note(helper, "Painkillers given")
        end
    end
    hook.Run("Rhylib.PlayerHealed", patient, helper)
    Med.MarkInjuries(patient)
end

-- treater drags an item onto patient's body part (patient may be treater):
-- checks what can be done, then starts a timed treatment.
Rhylib.Net.Receive("med.treat", function(ply)
    local patient = net.ReadEntity()
    local limb = Med.LIMBS[net.ReadUInt(3)]
    local kit = Med.TREAT_ITEMS[net.ReadUInt(3)]
    if not limb or not kit or not ply:Alive() or ply.rhylibDown then return end
    if Med.Simple() then return Med.Note(ply, "The simplified medical system has no injuries to treat") end
    if not (IsValid(patient) and patient:IsPlayer() and patient:Alive()) then return end
    if patient ~= ply then
        local r = cfg("viewRange")
        if ply:GetPos():DistToSqr(patient:GetPos()) > r * r or not Med.CanSee(ply, patient) then
            Med.Note(ply, "Too far away")
            return
        end
    end
    if Med.acts[ply] then return end
    local t = inj[patient]
    local p = t and t[limb]
    local name = Med.LIMB_NAMES[limb]
    -- Missing health can be treated on any part (limbs heal on their own, health doesn't).
    local hurtHP = patient:Health() < patient:GetMaxHealth()
    if not hurtHP and nothingWrong(p) and kit ~= Med.PAINKILLER then
        Med.Note(ply, name .. ": nothing to treat")
        return
    end
    local why = wontHelp(kit, p, hurtHP, ply, patient)
    if why then
        Med.Note(ply, why)
        return
    end
    Med.Start(ply, Med.A_TREAT, patient, { kit = kit, limb = limb })
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- Bacta tank (rhylib_bacta_tank): heals the occupant over time
--------------------------------------------------------------------------

-- dt seconds in a tank at rate mult. Returns true when nothing is left.
function Med.TankTick(ply, dt, mult)
    local heal = cfg("tankHeal") * dt * mult
    if Med.Simple() then heal = heal * ply:GetMaxHealth() / 100 end   -- (simplified: tankHeal = percent per second)
    ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + math.max(1, math.floor(heal + 0.5))))
    local t = inj[ply]
    if t then
        local rep = cfg("tankRepair") * dt * mult
        ply.rhylibTankTime = (ply.rhylibTankTime or 0) + dt * mult
        for _, l in ipairs(Med.LIMBS) do
            local p = t[l]
            p.bleed = 0
            p.dmg = math.max(0, p.dmg - rep)
            p.burn = math.max(0, p.burn - rep)
            if p.frac and ply.rhylibTankTime >= cfg("tankSetBones") then p.frac, p.splint = false, false end
        end
        Med.MarkInjuries(ply)
    end
    return ply:Health() >= ply:GetMaxHealth() and (not inj[ply] or healthy(inj[ply]))
end

-- Simplified medical system switched on: everyone's injuries and illnesses go
-- (offline players' saved illnesses stay frozen until they're cured), and
-- treatments and blood packs under way stop.
Rhylib.Hook.Add("Rhylib.ConfigChanged", "medical.simple", function(m, k)
    if m ~= "medical" or k ~= "simplified" or not Med.Simple() then return end
    for _, p in ipairs(player.GetAll()) do
        Med.ClearInjuries(p)
        if Med.Cure then Med.Cure(p) end   -- (illnesses go too)
    end
    for h, a in pairs(Med.acts or {}) do
        if a.kind == Med.A_TREAT or a.kind == Med.A_BLOOD then Med.Cancel(h) end
    end
end)
