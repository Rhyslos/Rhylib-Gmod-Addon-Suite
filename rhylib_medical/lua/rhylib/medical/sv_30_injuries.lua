--[[
    Injuries, server side (see sh_30_injuries.lua for the model).

    Damage -> body part:
      fall damage        both legs (a hard fall makes one limp)
      blast and fire     spread over the body (a big blast makes a leg limp)
      everything else    the part that was hit (rhylib bolts tag the hit
                         group; engine bullets use LastHitGroup). Models
                         with only "generic" hitboxes: guessed from the
                         damage position (Rhylib.HitGroupAt), else a
                         random part (torso most likely)
    Bleeding: a hit of lightBleedAt bleeds lightly (stops by itself after
    lightBleedStops s), heavyBleedAt (or a part at 90+) heavily (until
    treated); blasts, fire and falls never bleed. A leg hit of limpAt, a
    fall of limpFallAt or a blast of limpBlastAt makes you limp for
    limpTime s (Med.Limp).
    Once a second, only for injured players: bleeding takes health (a
    bleed that would kill downs you instead), light bleeds stop, limps
    run out, and parts that aren't bleeding slowly recover.

    Hardcore (Med.Hardcore()): the hc* keys instead (sh_30_injuries.lua).
    No limps: an arm or leg hit of hcFractureAt or a fall of
    hcFallFractureAt breaks a bone (Rhylib.CanFracture /
    Rhylib.FractureChance, Hard landings: no fall fractures); fire and
    blasts also burn the parts they hit; a part recovers only with no
    bleeding, fracture or burns; burns fade slowly (hcBurnRecover).
    Treatment is per part from the H menu (net med.treat ->
    A_TREAT -> Med.TreatPart): a trooper's medkit stops that part's
    bleeding and heals medkitHeal; a medic's medkit also sets the bone and
    takes medkitLimbRepair off its damage and burns (+medkitHealMedic); a
    first aid kit fixes the part (+hcFirstAidLimbHealth from its charge).
    The bacta tank also takes burns off and sets bones after
    hcTankSetBones s. Switching hardcore on ends limps; off clears
    fractures and burns.
    State goes to the owner, and to anyone with the owner's H menu open
    (in range, in sight), at most once per tick, when it changes.

    Test dummies (Med.IsPatient) get injuries the same way: their hit
    group comes from rhylib bolts (rhylibHitGroup), the engine bullet's
    trace (the dummy's OnTraceAttack, Med.HitGroupOf) or the hit position;
    their state only goes to viewers, and the limp / blast / fall hooks
    and skills aren't asked for them (they wear nothing, learn nothing).

    Also here: the Recovery medic skill timer, the treatment effect
    (Med.TreatWounds, used by the kits in sv_20_actions.lua), the bacta
    tank's healing step (Med.TankTick) and switching the simplified system
    on.
    Public: Med.MarkInjuries, Med.ClearInjuries, Med.BleedRate, Med.Limp,
    Med.CanLimp, Med.CanFracture, Med.TreatWounds, Med.HasWounds,
    Med.TreatPart, Med.TankTick, Med.HitGroupOf, Med.ForgetPatient.
    Hooks asked: Rhylib.CanLimp(ply, limb) (false = no limp),
    Rhylib.LimpChance(ply, limb) (0-1), Rhylib.CanFracture(ply, limb)
    (false = can't break), Rhylib.FractureChance(ply, limb) (0-1; both
    hardcore), Rhylib.BlastPartMult(ply, limb) (blast damage multiplier
    for that part). Fired: Rhylib.PlayerHealed.
    Nets: med.inj (server -> owner + viewers, see sh_30_injuries.lua),
    med.view (client -> server) entity: "I opened this patient's H menu"
    (NULL = closed), med.treat (client -> server, hardcore) patient
    entity, part 3 bits (index into Med.LIMBS), kit Med.TREAT_BITS
    (Med.TREAT_ITEMS).
]]

local Med = Rhylib.Medical
local Config = Rhylib.Config
local function cfg(k) return Config.Get("medical", k) end
local mcfg = Med.ModeCfg   -- (standard key, or its hardcore one)

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
    for _, l in ipairs(Med.LIMBS) do t[l] = { dmg = 0, bleed = 0, limp = false, frac = false, burn = 0, bleedEnd = 0 } end
    return t
end

local function getState(ply)
    local t = inj[ply]
    if not t then
        t = newState()
        inj[ply] = t
    elseif not t.hcFields then
        -- tables made before a Lua refresh may lack the hardcore fields
        for _, l in ipairs(Med.LIMBS) do
            local p = t[l]
            if p then p.burn = p.burn or 0 p.frac = p.frac or false end
        end
        t.hcFields = true
    end
    return t
end

local function healthy(t)
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p.dmg > 0 or p.bleed > 0 or p.limp or p.frac or p.burn > 0 then return false end
    end
    return true
end

-- What the owner last got, as whole numbers (as sent over the net), so
-- tiny changes aren't sent. Each part packs into one number below 163216
-- (damage, bleed, limp, fracture, burns); three parts fit exactly in one
-- double, so six parts make two numbers.
local SIG_BASE = 163216
local function packPart(p)
    local dmg = math.Clamp(math.ceil(p.dmg), 0, 100)
    local burn = math.Clamp(math.ceil(p.burn), 0, 100)
    return (((dmg * 4 + math.Clamp(p.bleed, 0, 3)) * 2 + (p.limp and 1 or 0)) * 2 + (p.frac and 1 or 0)) * 101 + burn
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

-- Med.MarkInjuries(ply): call after changing a player's parts. Drops the
-- table if everything healed and queues a send for the next tick (only
-- sent if the rounded numbers changed).
-- Example: local t = Rhylib.Medical.inj[ply]
--          if t then t.torso.bleed = 0 Rhylib.Medical.MarkInjuries(ply) end
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
                -- (a test dummy has no screen: only its viewers get it)
                local list = ply:IsPlayer() and { ply } or {}
                local v = viewers[ply]
                if v then
                    for viewer in pairs(v) do
                        if canView(viewer, ply) then list[#list + 1] = viewer else v[viewer] = nil end
                    end
                    if next(v) == nil then viewers[ply] = nil end
                end
                if #list > 0 then sendTo(ply, list) end
            end
        end
    end
end)

-- Med.ClearInjuries(ply): heals every part and ends a limp (health is not
-- changed). Run on spawn and death (test dummies: Med.DummyReset).
function Med.ClearInjuries(ply)
    if IsValid(ply) and ply:GetNW2Float("rhylib_limp", 0) ~= 0 then ply:SetNW2Float("rhylib_limp", 0) end
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
-- No idea where it hit: a random part, torso most often.
local RANDOM_LIMB = { "torso", "torso", "torso", "head", "larm", "rarm", "lleg", "rleg" }
local IS_LEG = { lleg = true, rleg = true }
local IS_LIMB = { larm = true, rarm = true, lleg = true, rleg = true }

-- Can this leg limp? (rhylib_skills Hard landings: never from falls;
-- other addons can answer Rhylib.CanLimp(ply, limb) with false, or
-- Rhylib.LimpChance(ply, limb) with a 0-1 chance: rhylib_gear's kama.)
local function canLimp(ply, limb, fall)
    if not ply:IsPlayer() then return true end   -- (test dummies: no skills, no gear)
    if fall then
        local K = Rhylib.Skills
        if K and K.Has and K.Has(ply, "hard_landings") then return false end
    end
    if hook.Run("Rhylib.CanLimp", ply, limb) == false then return false end
    local chance = hook.Run("Rhylib.LimpChance", ply, limb)   -- (a local: tonumber() of no value errors)
    chance = tonumber(chance)
    if chance and math.random() >= chance then return false end
    return true
end
Med.CanLimp = canLimp

-- Can this arm or leg break (hardcore)? rhylib_skills Hard landings: never
-- from falls; other addons can answer Rhylib.CanFracture(ply, limb) with
-- false, or Rhylib.FractureChance(ply, limb) with a 0-1 chance
-- (rhylib_gear's kama).
local function canBreak(ply, limb, fall)
    if not ply:IsPlayer() then return true end   -- (test dummies: no skills, no gear)
    if fall then
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

-- A bone breaks (hardcore); a note the first time.
local function breakBone(ply, p, limb)
    if p.frac then return end
    p.frac = true
    if not Med.Muted(ply) then
        Med.Note(ply, Med.LIMB_NAMES[limb] .. " broken: a medic has to set it")
    end
end

-- Med.Limp(ply, limb): ply limps on that leg for limpTime s (a new limp
-- starts the time again). Server; call Med.MarkInjuries after.
function Med.Limp(ply, limb)
    local t = getState(ply)
    for _, l in ipairs(Med.LEGS) do t[l].limp = (l == limb) end
    if ply:GetNW2Float("rhylib_limp", 0) <= CurTime() and not Med.Muted(ply) then
        Med.Note(ply, Med.LIMB_NAMES[limb] .. " hurt: limping, no sprinting for " .. cfg("limpTime") .. " s")
    end
    ply:SetNW2Float("rhylib_limp", CurTime() + cfg("limpTime"))
end

-- Adds damage to a part: a hit of heavyBleedAt (or a part at 90+) bleeds
-- heavily, lightBleedAt lightly (stops after lightBleedStops s); a direct
-- leg hit (not a blast, fire or fall) of limpAt makes it limp.
-- Hardcore: the hc keys, a part at 80+ bleeds heavily, and an arm or leg
-- taking hcFractureAt at once (any hit, blast share or fall share) breaks
-- the bone instead of a limp. fall: the damage is a fall's.
local function hurt(ply, t, limb, amount, canBleed, now, direct, fall)
    local p = t[limb]
    local hard = Med.Hardcore()
    p.dmg = math.min(100, p.dmg + amount)
    if canBleed then
        if amount >= mcfg("heavyBleedAt", "hcHeavyBleedAt") or p.dmg >= (hard and 80 or 90) then
            p.bleed = 2
        elseif amount >= mcfg("lightBleedAt", "hcLightBleedAt") and p.bleed < 1 then
            p.bleed = 1
            p.bleedEnd = now + mcfg("lightBleedStops", "hcLightBleedStops")
        end
    end
    if hard then
        if IS_LIMB[limb] and amount >= cfg("hcFractureAt") and canBreak(ply, limb, fall) then breakBone(ply, p, limb) end
    elseif direct and IS_LEG[limb] and amount >= cfg("limpAt") and canLimp(ply, limb) then
        Med.Limp(ply, limb)
    end
end

-- Med.HitGroupOf(ent): the hit group of the hit being worked out: rhylib
-- bolts' and lying ragdolls' rhylibHitGroup first, then the engine's
-- (a player's LastHitGroup; a test dummy's trace from its OnTraceAttack
-- this tick), or nil. Server.
function Med.HitGroupOf(ent)
    if ent.rhylibHitGroup then return ent.rhylibHitGroup end
    if ent:IsPlayer() then return ent:LastHitGroup() end
    if ent.rhylibTraceAt == CurTime() then return ent.rhylibTraceGroup end
end

-- Every hit that took (after armour and the downed check) becomes an
-- injury. Bleed-out damage (rhylibBleedTick) is skipped. Priority 50.
Rhylib.Hook.Add("PostEntityTakeDamage", "medical.injuries", function(ply, dmg, took)
    if not took or not Med.IsPatient(ply) or ply.rhylibBleedTick then return end
    local person = ply:IsPlayer()
    if not cfg("injuries") or Med.Simple() or not ply:Alive() then
        ply.rhylibHitGroup = nil
        return
    end
    local amount = dmg:GetDamage()
    if amount <= 0 then return end
    local now = CurTime()
    local t = getState(ply)
    local dtype = dmg:GetDamageType()
    local hard = Med.Hardcore()

    if bit.band(dtype, DMG_FALL) ~= 0 then
        hurt(ply, t, "lleg", amount * 0.6, false, now, false, true)
        hurt(ply, t, "rleg", amount * 0.6, false, now, false, true)
        local leg = math.random(2) == 1 and "lleg" or "rleg"
        if hard then
            if amount >= cfg("hcFallFractureAt") and canBreak(ply, leg, true) then breakBone(ply, t[leg], leg) end
        elseif amount >= cfg("limpFallAt") and canLimp(ply, leg, true) then
            Med.Limp(ply, leg)
        end
    elseif bit.band(dtype, bit.bor(DMG_BLAST, DMG_BURN, DMG_SLOWBURN, DMG_PLASMA)) ~= 0 then
        local blast = bit.band(dtype, DMG_BLAST) ~= 0
        for limb, share in pairs(SPREAD) do
            -- (hook Rhylib.BlastPartMult(ply, limb): rhylib_gear's kama shields the legs)
            local m = 1
            if blast and person then
                local hm = hook.Run("Rhylib.BlastPartMult", ply, limb)
                m = tonumber(hm) or 1
            end
            hurt(ply, t, limb, amount * share * m, false, now)
            -- (hardcore: fire and blasts burn too)
            if hard then t[limb].burn = math.min(100, t[limb].burn + amount * share * m) end
        end
        if blast and not hard and amount >= cfg("limpBlastAt") then
            local leg = math.random(2) == 1 and "lleg" or "rleg"
            if canLimp(ply, leg) then Med.Limp(ply, leg) end
        end
    else
        local group = Med.HitGroupOf(ply)
        if (not group or group == HITGROUP_GENERIC) and Rhylib.HitGroupAt then
            group = Rhylib.HitGroupAt(ply, dmg:GetDamagePosition())
        end
        local limb = GROUP_LIMB[group]
        if not limb or group == HITGROUP_GENERIC then limb = RANDOM_LIMB[math.random(#RANDOM_LIMB)] end
        hurt(ply, t, limb, amount, bit.band(dtype, bit.bor(DMG_BULLET, DMG_SLASH, DMG_CLUB, DMG_GENERIC, DMG_BUCKSHOT, DMG_SNIPER)) ~= 0 or dtype == 0, now, true)
        -- Torso hits knock the wind out of you.
        -- (not with the Shock Assault skill)
        local K = Rhylib.Skills
        if person and limb == "torso" and Rhylib.Stamina and Rhylib.Stamina.Drain and not Med.Muted(ply)
            and not (K and K.Has and K.Has(ply, "shock_assault")) then
            Rhylib.Stamina.Drain(ply, amount * mcfg("torsoStaminaHit", "hcTorsoStaminaHit"))
        end
    end
    ply.rhylibHitGroup = nil
    Med.MarkInjuries(ply)
end, 50)

Rhylib.Hook.Add("PlayerSpawn", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerDeath", "medical.injuries", Med.ClearInjuries)
Rhylib.Hook.Add("PlayerSilentDeath", "medical.injuries", Med.ClearInjuries)
-- Med.ForgetPatient(ply): drops everything kept about ply's injuries and
-- whom they view (a player leaving, a test dummy removed). Server.
function Med.ForgetPatient(ply)
    inj[ply] = nil
    dirty[ply] = nil
    viewers[ply] = nil
    for _, v in pairs(viewers) do v[ply] = nil end
end
Rhylib.Hook.Add("PlayerDisconnected", "medical.injuries", Med.ForgetPatient)

-- Opening (or closing, with no patient) someone's injury menu.
-- med.view: one entity. The viewer is dropped from every other patient,
-- then added if in viewRange and sight; they get the state at once.
Rhylib.Net.Receive("med.view", function(ply)
    local patient = net.ReadEntity()
    for p, v in pairs(viewers) do
        v[ply] = nil
        if next(v) == nil then viewers[p] = nil end
    end
    if not (Med.IsPatient(patient) and patient ~= ply) or Med.Simple() then return end
    local r = Config.Get("medical", "viewRange")
    if not ply:Alive() or ply.rhylibDown or ply:GetPos():DistToSqr(patient:GetPos()) > r * r or not Med.CanSee(ply, patient) then return end
    viewers[patient] = viewers[patient] or {}
    viewers[patient][ply] = true
    sendTo(patient, ply)  -- what they look like now
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- Bleeding and recovery (once a second, injured players only)
--------------------------------------------------------------------------

-- Med.BleedRate(ply): health lost per second from bleeding right now
-- (lightBleed per light part + heavyBleed per heavy part).
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
    local hard = Med.Hardcore()
    local rec = mcfg("recover", "hcRecover")
    local burnRec = cfg("hcBurnRecover")
    for ply, t in pairs(inj) do
        if not IsValid(ply) then
            inj[ply] = nil
        elseif ply:Alive() then
            local loss = 0
            local limping = ply:GetNW2Float("rhylib_limp", 0) > now
            for _, l in ipairs(Med.LIMBS) do
                local p = t[l]
                if p.bleed == 1 and now >= p.bleedEnd then p.bleed = 0 end
                if p.bleed == 1 then loss = loss + light elseif p.bleed == 2 then loss = loss + heavy end
                if p.burn > 0 then p.burn = math.max(0, p.burn - burnRec) end
                -- (hardcore: only with no bleeding, fracture or burns)
                if p.bleed == 0 and p.dmg > 0 and not (hard and (p.frac or p.burn > 0)) then
                    p.dmg = math.max(0, p.dmg - rec)
                end
                if p.limp and not limping then p.limp = false end
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
-- Recovery (medic skill): every regenEvery seconds, regenHealth health and
-- the medic's own afflictions ease at the same pace: each part's damage
-- (and burns) -regenAffliction, bleeding one step (heavy -> light ->
-- stopped), a fracture knits once its part has no damage left. Not while
-- down.
--------------------------------------------------------------------------

-- Med.Bacta(ply, dt): called by a bacta grenade's mist (rhylib_republic
-- rhylib_smoke_cloud) for each player standing in it, dt seconds at a time.
-- Downed: the bleed-out is held (time added back, as if stabilised).
-- Otherwise bactaHeal health per second, and every bactaBleedStep seconds
-- in it each bleeding part steps down one level. Server.
function Med.Bacta(ply, dt)
    if not (IsValid(ply) and ply:Alive()) then return end
    local now = CurTime()
    if now - (ply.rhylibBactaAt or 0) > 1 then ply.rhylibBactaBleed = 0 end   -- (a fresh visit starts the bleed step over)
    ply.rhylibBactaAt = now
    if ply.rhylibDown or Med.IsDown(ply) then
        if not Med.StabilisedBy(ply) then
            ply:SetNW2Float(Rhylib.NW.DOWN_END, ply:GetNW2Float(Rhylib.NW.DOWN_END, 0) + dt)
        end
        return
    end
    local max = ply:GetMaxHealth()
    if ply:Health() < max then
        ply.rhylibBactaHp = (ply.rhylibBactaHp or 0) + cfg("bactaHeal") * dt
        local add = math.floor(ply.rhylibBactaHp)
        if add >= 1 then
            ply.rhylibBactaHp = ply.rhylibBactaHp - add
            ply:SetHealth(math.min(max, ply:Health() + add))
        end
    end
    local t = inj[ply]
    if not t then return end
    ply.rhylibBactaBleed = (ply.rhylibBactaBleed or 0) + dt
    if ply.rhylibBactaBleed < cfg("bactaBleedStep") then return end
    ply.rhylibBactaBleed = 0
    local changed = false
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p.bleed > 0 then
            p.bleed = p.bleed - 1
            if p.bleed == 1 then p.bleedEnd = CurTime() + mcfg("lightBleedStops", "hcLightBleedStops") end
            changed = true
        end
    end
    if changed then Med.MarkInjuries(ply) end
end

local function recover(ply)
    local max = ply:GetMaxHealth()
    local hp = cfg("regenHealth")
    if Med.Simple() then hp = math.ceil(max * hp / 100) end
    if ply:Health() < max then ply:SetHealth(math.min(max, ply:Health() + hp)) end
    local t = inj[ply]
    if not t then return end
    local step = cfg("regenAffliction")
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p.bleed > 0 then
            p.bleed = p.bleed - 1
            if p.bleed == 1 then p.bleedEnd = CurTime() + mcfg("lightBleedStops", "hcLightBleedStops") end
        end
        p.dmg = math.max(0, p.dmg - step)
        p.burn = math.max(0, p.burn - step)
        if p.frac and p.dmg <= 0 then p.frac = false end
    end
    if healthy(t) then
        inj[ply] = nil
        dirty[ply] = true
    else
        Med.MarkInjuries(ply)
    end
end

-- Players with the Recovery skill: worked out every 5 s (skills change
-- rarely), so the 1 s heal timer only walks them.
local regenSet, regenScan = {}, 0
timer.Create("Rhylib.Medical.Recovery", 1, 0, function()
    if not (Rhylib.Skills and Rhylib.Skills.Has) then return end
    local now = CurTime()
    if now >= regenScan then
        regenScan = now + 5
        regenSet = {}
        for _, p in ipairs(player.GetAll()) do
            if Med.Skill(p, "recovery") then regenSet[p] = true else p.rhylibRegenAt = nil end
        end
    end
    local every = math.max(1, tonumber(cfg("regenEvery")) or 6)
    for ply in pairs(regenSet) do
        if IsValid(ply) and ply:Alive() and not ply.rhylibDown then
            if not ply.rhylibRegenAt then
                ply.rhylibRegenAt = now + every
            elseif now >= ply.rhylibRegenAt then
                ply.rhylibRegenAt = now + every
                recover(ply)
            end
        elseif IsValid(ply) then
            ply.rhylibRegenAt = nil
        end
    end
end)

--------------------------------------------------------------------------
-- Treatment (the kits, sv_20_actions.lua)
--------------------------------------------------------------------------

-- Med.HasWounds(ply, full): true if a kit has something to fix besides
-- health: any bleeding; with full (a medic's kit) also a limp (even one
-- Field triage mutes), a fracture, burns or a part at 5+ damage.
function Med.HasWounds(ply, full)
    local t = inj[ply]
    if full and Med.LimpLeft(ply) > 0 then return true end
    if not t then return false end
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p.bleed > 0 or (full and (math.ceil(p.dmg) >= 5 or p.frac or p.burn > 0)) then return true end
    end
    return false
end

-- Med.TreatWounds(ply, how): a kit's effect on the wounds (health is the
-- kit's own business). how:
--   "worst"   a trooper's medkit: stops the worst bleed (heavy first)
--   "medkit"  a medic's medkit: stops all bleeding, ends the limp,
--             -medkitLimbRepair damage on every part
--   "full"    a first aid kit: everything fixed
-- (Standard system; in hardcore the kits treat one part, Med.TreatPart.
-- Fractures and burns only exist in hardcore; "medkit" and "full" clear
-- them too.)
-- Returns a short note of what it did ("" when nothing). Server.
function Med.TreatWounds(ply, how)
    local t = inj[ply]
    local did = {}
    if how ~= "worst" and Med.LimpLeft(ply) > 0 then
        ply:SetNW2Float("rhylib_limp", 0)
        did[#did + 1] = "limp"
    end
    if t then
        if how == "worst" then
            local worst
            for _, l in ipairs(Med.LIMBS) do
                local p = t[l]
                if p.bleed > 0 and (not worst or p.bleed > t[worst].bleed) then worst = l end
            end
            if worst then
                t[worst].bleed = 0
                did[#did + 1] = string.lower(Med.LIMB_NAMES[worst]) .. " bleeding"
            end
        else
            local bled = false
            local r = how == "full" and 100 or cfg("medkitLimbRepair")
            for _, l in ipairs(Med.LIMBS) do
                local p = t[l]
                if p.bleed > 0 then bled = true end
                p.bleed = 0
                p.dmg = math.max(0, p.dmg - r)
                p.burn = math.max(0, p.burn - r)
                p.limp, p.frac = false, false
            end
            if bled then table.insert(did, 1, "bleeding") end
        end
        Med.MarkInjuries(ply)
    end
    return table.concat(did, ", ")
end

--------------------------------------------------------------------------
-- Hardcore: treatment one part at a time from the H menu
--------------------------------------------------------------------------

local function nothingWrong(p)
    return not p or (p.dmg <= 0 and p.bleed == 0 and not p.frac and p.burn <= 0)
end

-- Why this kit can't help on this part, or nil if it can. p: the part,
-- hurtHP: health is missing.
local function wontHelp(kit, p, hurtHP, medic)
    if kit == Med.MEDKIT then
        if p.bleed > 0 or hurtHP then return nil end
        if medic and (p.dmg > 0 or p.burn > 0 or p.frac) then return nil end
        if p.frac or p.burn > 0 then return "Only a medic can set bones and treat burns" end
        return "Nothing a medkit can do: it heals by itself once it stops bleeding"
    elseif kit == Med.FIRST_AID then
        return nil
    end
    return "That can't treat anything"
end

-- Med.TreatPart(helper, patient, limb, kit): the effect of a part
-- treatment (hardcore), when its timer ends (A_TREAT in sv_20_actions.lua).
-- kit is Med.FIRST_AID or Med.MEDKIT. Checks again that it still helps,
-- uses the kit, changes the part and notes the helper. Returns true if it
-- treated. Server.
--   first aid kit   (medics) fixes the part: bleeding, fracture, burns,
--                   damage; +hcFirstAidLimbHealth health from its charge
--   medkit, medic   stops its bleeding, sets the bone, -medkitLimbRepair
--                   damage and burns, +medkitHealMedic
--   medkit          stops its bleeding, +medkitHeal
function Med.TreatPart(helper, patient, limb, kit)
    if not Med.Hardcore() or not Med.LIMB_NAMES[limb] then return false end
    local t = getState(patient)
    local p = t[limb]
    local name = Med.LIMB_NAMES[limb]
    local medic = Med.IsMedic(helper)
    local hp, maxHp = patient:Health(), patient:GetMaxHealth()
    local hurtHP = hp < maxHp
    if nothingWrong(p) and not hurtHP then
        Med.Note(helper, name .. ": nothing left to treat")
        Med.MarkInjuries(patient)
        return false
    end
    local why = wontHelp(kit, p, hurtHP, medic)
    if why then
        Med.Note(helper, why)
        Med.MarkInjuries(patient)
        return false
    end
    local did
    if kit == Med.FIRST_AID then
        local want = math.min(cfg("hcFirstAidLimbHealth"), maxHp - hp)
        local have = Med.KitCharge(helper)
        if have < 1 then Med.Note(helper, "Your first aid kit is empty") return false end
        local heal = math.max(0, math.min(want, have))
        Med.SpendCharge(helper, math.min(have, math.max(heal, cfg("firstAidMinCost"))))
        did = p.frac and "bone set and treated" or "treated"
        p.dmg, p.bleed, p.burn, p.frac = 0, 0, 0, false
        patient:SetHealth(math.min(maxHp, hp + math.floor(heal + 0.5)))
    else
        if not Med.Consume(helper, Med.MEDKIT) then return false end
        local bled = p.bleed > 0
        p.bleed = 0
        patient:SetHealth(math.min(maxHp, hp + (medic and cfg("medkitHealMedic") or cfg("medkitHeal"))))
        if medic then
            local r = cfg("medkitLimbRepair")
            did = p.frac and "bone set" or "patched up"
            p.frac = false
            p.dmg = math.max(0, p.dmg - r)
            p.burn = math.max(0, p.burn - r)
        else
            did = bled and "bleeding stopped" or "bandaged"
        end
    end
    Med.MarkInjuries(patient)
    Med.Note(helper, (patient == helper and "" or (patient:Nick() .. ", ")) .. name .. ": " .. did)
    return true
end

-- med.treat (client -> server, cl_30_injuries.lua): the helper dropped a
-- kit on a part of patient (patient may be the helper). Checks what it
-- can do, then starts a timed A_TREAT (Med.Start checks the rest).
Rhylib.Net.Receive("med.treat", function(ply)
    local patient = net.ReadEntity()
    local limb = Med.LIMBS[net.ReadUInt(3)]
    local kit = Med.TREAT_ITEMS[net.ReadUInt(Med.TREAT_BITS)]
    if not limb or not kit or not ply:Alive() or ply.rhylibDown then return end
    if not Med.Hardcore() then return end
    if not (Med.IsPatient(patient) and patient:Alive()) then return end
    if patient ~= ply then
        local r = cfg("viewRange")
        if ply:GetPos():DistToSqr(patient:GetPos()) > r * r or not Med.CanSee(ply, patient) then
            Med.Note(ply, "Too far away")
            return
        end
    end
    if Med.acts[ply] then return end
    if patient.rhylibDown then
        Med.Note(ply, "Revive them first")
        return
    end
    local p = inj[patient] and inj[patient][limb] or Med.EMPTY_LIMB
    local name = Med.LIMB_NAMES[limb]
    -- (missing health can be treated on any part)
    local hurtHP = patient:Health() < patient:GetMaxHealth()
    if not hurtHP and nothingWrong(p) then
        Med.Note(ply, name .. ": nothing to treat")
        return
    end
    local why = wontHelp(kit, p, hurtHP, Med.IsMedic(ply))
    if why then
        Med.Note(ply, why)
        return
    end
    Med.Start(ply, Med.A_TREAT, patient, { kit = kit, limb = limb })
end, { rate = 4, burst = 4 })

--------------------------------------------------------------------------
-- Bacta tank (rhylib_bacta_tank): heals the occupant over time
--------------------------------------------------------------------------

-- Med.TankTick(ply, dt, mult): dt seconds in a bacta tank at rate mult
-- (2 with a Bacta specialist near). Heals tankHeal/s (simplified: % of
-- max per second, at least 1 per step), stops all bleeding and the limp,
-- repairs tankRepair/s of part damage (hardcore: and burns; bones are set
-- after hcTankSetBones s inside, ply.rhylibTankTime).
-- Returns true when nothing is left to heal. Called by sv_40_medbay.lua.
function Med.TankTick(ply, dt, mult)
    local heal = cfg("tankHeal") * dt * mult
    if Med.Simple() then heal = heal * ply:GetMaxHealth() / 100 end   -- (simplified: tankHeal = percent per second)
    ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + math.max(1, math.floor(heal + 0.5))))
    if ply:GetNW2Float("rhylib_limp", 0) ~= 0 then ply:SetNW2Float("rhylib_limp", 0) end
    local t = inj[ply]
    if t then
        local rep = cfg("tankRepair") * dt * mult
        ply.rhylibTankTime = (ply.rhylibTankTime or 0) + dt * mult
        local setBones = ply.rhylibTankTime >= cfg("hcTankSetBones")
        for _, l in ipairs(Med.LIMBS) do
            local p = t[l]
            p.bleed = 0
            p.limp = false
            p.dmg = math.max(0, p.dmg - rep)
            p.burn = math.max(0, p.burn - rep)
            if p.frac and setBones then p.frac = false end
        end
        Med.MarkInjuries(ply)
    end
    return ply:Health() >= ply:GetMaxHealth() and (not inj[ply] or healthy(inj[ply]))
end

-- Simplified medical system switched on: everyone's injuries and illnesses go
-- (offline players' saved illnesses stay frozen until they're cured), and
-- blood packs under way stop.
Rhylib.Hook.Add("Rhylib.ConfigChanged", "medical.simple", function(m, k)
    if m ~= "medical" or k ~= "simplified" or not Med.Simple() then return end
    for _, p in ipairs(player.GetAll()) do
        Med.ClearInjuries(p)
        if Med.Cure then Med.Cure(p) end   -- (illnesses go too)
    end
    for d in pairs(Med.dummies) do
        if IsValid(d) then
            Med.ClearInjuries(d)
            if Med.Cure then Med.Cure(d) end
        end
    end
    for h, a in pairs(Med.acts or {}) do
        if a.kind == Med.A_BLOOD then Med.Cancel(h) end
    end
end)

-- Hardcore switched on or off (or the simplified system, which wins over
-- it): on ends every limp; off clears fractures and burns and stops part
-- treatments under way.
local function convertMode(ent, hard)
    if not IsValid(ent) then return end
    local t = inj[ent]
    if hard then
        if ent:GetNW2Float("rhylib_limp", 0) ~= 0 then ent:SetNW2Float("rhylib_limp", 0) end
        if t then for _, l in ipairs(Med.LIMBS) do t[l].limp = false end end
    elseif t then
        for _, l in ipairs(Med.LIMBS) do t[l].frac, t[l].burn = false, 0 end
    end
    if t then Med.MarkInjuries(ent) end
end

Rhylib.Hook.Add("Rhylib.ConfigChanged", "medical.hardcore", function(m, k)
    if m ~= "medical" or (k ~= "hardcore" and k ~= "simplified") then return end
    local hard = Med.Hardcore()
    for _, p in ipairs(player.GetAll()) do convertMode(p, hard) end
    for d in pairs(Med.dummies) do convertMode(d, hard) end
    -- a treatment under way follows the old mode's rules, so stop it
    for h, a in pairs(Med.acts or {}) do
        if (not hard and a.kind == Med.A_TREAT) or (hard and (a.kind == Med.A_MEDKIT or a.kind == Med.A_FA_HEAL)) then
            Med.Cancel(h)
        end
    end
end)
