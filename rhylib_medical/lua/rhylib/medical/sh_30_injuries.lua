--[[
    Injuries. Each player has six body parts:
        head, torso, left arm, right arm, left leg, right leg
    and each part has:
        dmg     0-100   how hurt it is (white -> red in the H menu); heals
                        by itself while the part isn't bleeding
        bleed   0/1/2   none, light, heavy: health lost over time. Light
                        stops by itself after lightBleedStops s; heavy
                        bleeds until someone treats it
        limp    bool    (legs) this leg is why you limp
        frac    bool    (hardcore, arms and legs) broken bone
        burn    0-100   (hardcore) burns from fire and blasts
    A limp (NW2Float rhylib_limp = until) comes from a hard leg hit, a fall
    or a blast and wears off by itself after limpTime s: no sprinting.

    Hardcore (Med.Hardcore(), config hardcore): no limps; instead an arm
    or leg hit of hcFractureAt or a fall of hcFallFractureAt breaks a bone,
    fire and blasts burn, bleeding starts at hcLightBleedAt / hcHeavyBleedAt
    (a part at 80+ bleeds heavily) and light bleeding stops after
    hcLightBleedStops s. A part only recovers with no bleeding, fracture or
    burns (hcRecover / hcBurnRecover).

    Effects (worked out here, used by movement, stamina and weapons):
        legs    limping: no sprinting (hardcore: broken: slower walk
                (hcFractureWalkMult) and no sprinting; hcLegNoSprintAt
                damage: no sprinting)
        arms    more spread the more hurt; from armNoAimAt no aiming down
                sights (hardcore: hcArmNoAimAt, or broken: no aiming, full
                spread)
        torso   hurt: lower stamina cap; torso hits also drain stamina
                (hardcore: hcTorsoStaminaCap / hcTorsoStaminaHit)
        burns   (hardcore) extra spread (hcBurnSpread)

    The server owns the state and sends it to the injured player and to
    anyone looking at them in the H menu ("med.inj", on change). Other
    clients don't know it (the limp is an NW2 value everyone has).

    Treatment is one kit, worst problem first (sv_20_actions.lua): a
    medkit or first aid kit on someone (left click) or yourself (right
    click). The H menu only shows the body. Hardcore: drag a kit onto one
    part in the H menu (Med.TreatPart, sv_30_injuries.lua).

    This file (shared): the injury config keys, the part list, the effect
    checks other addons call (Med.NoSprint, Med.Limping, Med.BrokenLeg, Med.CanAim,
    Med.SpreadPenalty used by rhylib_weapons, Med.StaminaCap used by
    rhylib_stamina), the leg SetupMove limiter and the med.inj wire format.
    Every effect is off while Med.Muted (simplified system, Field triage).
]]

local Med = Rhylib.Medical
local Config = Rhylib.Config

Med.LIMBS = { "head", "torso", "larm", "rarm", "lleg", "rleg" }
Med.LIMB_INDEX = {}
for i, l in ipairs(Med.LIMBS) do Med.LIMB_INDEX[l] = i end
Med.LIMB_NAMES = { head = "Head", torso = "Torso", larm = "Left arm", rarm = "Right arm", lleg = "Left leg", rleg = "Right leg" }
Med.ARMS = { "larm", "rarm" }
Med.LEGS = { "lleg", "rleg" }

Config.Register("medical", "injuries", true, "Body part injuries (H menu)")
Config.Register("medical", "lightBleedAt", 25, "A hit this strong (or more) starts light bleeding")
Config.Register("medical", "heavyBleedAt", 50, "A hit this strong (or more) starts heavy bleeding (a part at 90+ damage also bleeds heavily)")
Config.Register("medical", "lightBleed", 0.4, "Health lost per second from each lightly bleeding part")
Config.Register("medical", "heavyBleed", 1.5, "Health lost per second from each heavily bleeding part")
Config.Register("medical", "lightBleedStops", 30, "Seconds before light bleeding stops by itself (heavy doesn't)")
Config.Register("medical", "limpAt", 35, "A leg hit this strong (or more) makes you limp")
Config.Register("medical", "limpFallAt", 20, "Fall damage this high (or more) makes you limp")
Config.Register("medical", "limpBlastAt", 40, "Blast damage this high (or more) makes you limp")
Config.Register("medical", "limpTime", 15, "Seconds a limp lasts (no sprinting); a new one starts the time again")
Config.Register("medical", "recover", 0.5, "Damage a part recovers per second by itself (only while it isn't bleeding)")
Config.Register("medical", "armNoAimAt", 70, "Arm damage from which you can't aim down sights")
Config.Register("medical", "armSpread", 0.8, "Extra spread at a fully hurt arm, as a share of the weapon's resting cone")
Config.Register("medical", "torsoStaminaHit", 0.5, "Stamina lost per point of torso damage taken")
Config.Register("medical", "torsoStaminaCap", 0.3, "Share of max stamina lost at a fully hurt torso")
Config.Register("medical", "medkitLimbRepair", 40, "Damage a medic's medkit takes off every body part")
Config.Register("medical", "regenEvery", 6, "Recovery (medic skill): seconds between heals")
Config.Register("medical", "regenHealth", 4, "Recovery: health per heal (a percent of max health in the simplified medical system)")
Config.Register("medical", "regenAffliction", 4, "Recovery: damage each of your body parts loses per heal (bleeding also eases one step)")
Config.Register("medical", "viewRange", 120, "How close you must be to open someone's injury menu (units)")
-- Hardcore numbers (used instead of the ones above while hardcore is on).
Config.Register("medical", "hcLightBleedAt", 12, "Hardcore: a hit this strong (or more) starts light bleeding")
Config.Register("medical", "hcHeavyBleedAt", 35, "Hardcore: a hit this strong (or more) starts heavy bleeding (a part at 80+ damage also bleeds heavily)")
Config.Register("medical", "hcLightBleedStops", 60, "Hardcore: seconds before light bleeding stops by itself (heavy doesn't)")
Config.Register("medical", "hcFractureAt", 30, "Hardcore: an arm or leg hit this strong (or more) breaks the bone")
Config.Register("medical", "hcFallFractureAt", 20, "Hardcore: fall damage this high (or more) breaks a leg")
Config.Register("medical", "hcRecover", 0.25, "Hardcore: damage a part recovers per second by itself (only with no bleeding, fracture or burns)")
Config.Register("medical", "hcBurnRecover", 0.05, "Hardcore: burns a part recovers per second by itself")
Config.Register("medical", "hcLegNoSprintAt", 40, "Hardcore: leg damage from which you can't sprint (a broken leg can't either)")
Config.Register("medical", "hcFractureWalkMult", 0.7, "Hardcore: walk speed with a broken leg")
Config.Register("medical", "hcArmNoAimAt", 40, "Hardcore: arm damage from which you can't aim down sights (a broken arm can't either)")
Config.Register("medical", "hcBurnSpread", 0.25, "Hardcore: extra spread at full burns, as a share of the weapon's resting cone")
Config.Register("medical", "hcTorsoStaminaHit", 0.8, "Hardcore: stamina lost per point of torso damage taken")
Config.Register("medical", "hcTorsoStaminaCap", 0.5, "Hardcore: share of max stamina lost at a fully hurt torso")
Config.Register("medical", "hcFirstAidLimbTime", 4, "Hardcore: seconds to treat one body part with a first aid kit")
Config.Register("medical", "hcMedkitLimbTime", 3, "Hardcore: seconds to treat one body part with a medkit")
Config.Register("medical", "hcFirstAidLimbHealth", 50, "Hardcore: health a first aid kit gives when treating a body part (from its charge)")
Config.Register("medical", "hcTankSetBones", 8, "Hardcore: seconds in a bacta tank before broken bones are set")

local function cfg(k) return Config.Get("medical", k) end
-- The standard key, or its hardcore one while hardcore is on.
local function mcfg(std, hard) return Config.Get("medical", Med.Hardcore() and hard or std) end
Med.ModeCfg = mcfg

-- An empty part, for players we know nothing about.
local EMPTY = { dmg = 0, bleed = 0, limp = false, frac = false, burn = 0 }
Med.EMPTY_LIMB = EMPTY

-- Med.Injuries(ply): the injury table of a player: { [limb] = part }, or
-- nil when unhurt. Server: everyone's. Client: your own and the patient
-- you're looking at (Med.injOf); anyone else reads as unhurt (nil).
-- Treat it as read-only; on the server change parts then call
-- Med.MarkInjuries(ply).
function Med.Injuries(ply)
    if SERVER then return Med.inj and Med.inj[ply] end
    return Med.injOf and Med.injOf[ply]
end

-- Med.Part(ply, limb): one part ({ dmg, bleed, limp, frac, burn }), or Med.EMPTY_LIMB
-- when unknown/unhurt. limb is one of Med.LIMBS.
-- Example: if Rhylib.Medical.Part(ply, "lleg").bleed > 0 then ... end
function Med.Part(ply, limb)
    local t = Med.Injuries(ply)
    return t and t[limb] or EMPTY
end

-- Effects ------------------------------------------------------------

-- Med.Muted(ply): true when afflictions have no effect. Field triage
-- (rhylib_skills officer order, NW2Float rhylib_afflMute = until) mutes
-- them for a while; the simplified medical system mutes them all the time.
function Med.Muted(ply)
    return Med.Simple() or ply:GetNW2Float("rhylib_afflMute", 0) > CurTime()
end

-- Damage rounded up, as the client gets it over the net (med.inj), so
-- predicted checks agree on server and client.
local ceil = math.ceil

-- Med.LimpLeft(ply): seconds of limp left (0 = none). Everyone can read it
-- (NW2Float rhylib_limp).
function Med.LimpLeft(ply)
    return math.max(0, ply:GetNW2Float("rhylib_limp", 0) - CurTime())
end

-- Med.Limping(ply): true while a limp lasts (and afflictions aren't muted).
function Med.Limping(ply)
    if Med.Muted(ply) then return false end
    return ply:GetNW2Float("rhylib_limp", 0) > CurTime()
end

-- Med.BrokenLeg(ply): true in hardcore while a leg is broken (slower
-- walk, no sprinting).
function Med.BrokenLeg(ply)
    if not Med.Hardcore() or Med.Muted(ply) then return false end
    local t = Med.Injuries(ply)
    if not t then return false end
    return (t.lleg and t.lleg.frac) or (t.rleg and t.rleg.frac) or false
end

-- Med.NoSprint(ply): true while limping; in hardcore while a leg is broken
-- or at hcLegNoSprintAt damage or more.
function Med.NoSprint(ply)
    if not Med.Hardcore() then return Med.Limping(ply) end
    if Med.Muted(ply) then return false end
    local t = Med.Injuries(ply)
    if not t then return false end
    local at = cfg("hcLegNoSprintAt")
    for _, l in ipairs(Med.LEGS) do
        local p = t[l]
        if p and (p.frac or ceil(p.dmg) >= at) then return true end
    end
    return false
end

-- Med.CanAim(ply): false if an arm is at armNoAimAt damage or more
-- (hardcore: hcArmNoAimAt, or broken). rhylib_weapons asks this before
-- aiming down sights.
function Med.CanAim(ply)
    if Med.Muted(ply) then return true end
    local t = Med.Injuries(ply)
    if not t then return true end
    local hard = Med.Hardcore()
    local at = cfg(hard and "hcArmNoAimAt" or "armNoAimAt")
    for _, l in ipairs(Med.ARMS) do
        local p = t[l]
        if p and ((hard and p.frac) or ceil(p.dmg) >= at) then return false end
    end
    return true
end

-- Med.SpreadPenalty(ply, baseCone): extra spread in degrees from hurt
-- arms: the worse arm's damage/100 (hardcore: 1 when broken) × armSpread
-- × baseCone (the weapon's resting cone); in hardcore plus the worst
-- burn/100 × hcBurnSpread × baseCone.
-- Example: cone = cone + Rhylib.Medical.SpreadPenalty(ply, restCone)
function Med.SpreadPenalty(ply, baseCone)
    local t = Med.Injuries(ply)
    if not t or Med.Muted(ply) then return 0 end
    local hard = Med.Hardcore()
    local arm = 0
    for _, l in ipairs(Med.ARMS) do
        local p = t[l]
        if p then arm = math.max(arm, (hard and p.frac) and 1 or ceil(p.dmg) / 100) end
    end
    local pen = arm * cfg("armSpread")
    if hard then
        local burn = 0
        for _, l in ipairs(Med.LIMBS) do
            local p = t[l]
            if p and ceil(p.burn) > burn then burn = ceil(p.burn) end
        end
        pen = pen + burn / 100 * cfg("hcBurnSpread")
    end
    return pen * baseCone
end

-- Med.StaminaCap(ply): share of max stamina you can have, 0-1. Torso
-- damage lowers it by up to torsoStaminaCap (hardcore: hcTorsoStaminaCap);
-- an illness multiplies it too (Med.IllStaminaMult). rhylib_stamina reads it.
function Med.StaminaCap(ply)
    if Med.Muted(ply) then return 1 end
    local ill = Med.IllStaminaMult and Med.IllStaminaMult(ply) or 1   -- (illness, sh_50_illness.lua)
    local p = Med.Part(ply, "torso")
    return (1 - math.Clamp(ceil(p.dmg) / 100, 0, 1) * mcfg("torsoStaminaCap", "hcTorsoStaminaCap")) * ill
end

-- Med.BleedLevel(ply): the worst bleeding of any part: 0 none, 1 light,
-- 2 heavy (for the HUD).
function Med.BleedLevel(ply)
    local t = Med.Injuries(ply)
    if not t then return 0 end
    local worst = 0
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p and p.bleed > worst then worst = p.bleed end
    end
    return worst
end

-- Limping (hardcore: a broken or hurt leg): no sprinting; hardcore broken
-- leg: slower walk too. Runs before rhylib_stamina (which reads the sprint
-- key from mv), after the downed movement (-100).
local band, bnot = bit.band, bit.bnot
Rhylib.Hook.Add("SetupMove", "medical.legs", function(ply, mv)
    if not ply:Alive() or Med.IsDown(ply) then return end
    if mv:KeyDown(IN_SPEED) and Med.NoSprint(ply) then
        mv:SetButtons(band(mv:GetButtons(), bnot(IN_SPEED)))
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed()))
    end
    if Med.BrokenLeg(ply) then
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed() * cfg("hcFractureWalkMult")))
    end
end, -90)

-- Wire format ("med.inj", server -> owner and viewers): the patient
-- (entity), then per part dmg 7 bits, bleed 2, limp 1, fracture 1, burn 7
-- (18 bits × 6 parts = 108 bits). Damage and burns are rounded up.
function Med.WriteInjuries(t)
    for _, l in ipairs(Med.LIMBS) do
        local p = t and t[l] or EMPTY
        net.WriteUInt(math.Clamp(math.ceil(p.dmg), 0, 100), 7)
        net.WriteUInt(p.bleed, 2)
        net.WriteBool(p.limp and true or false)
        net.WriteBool(p.frac and true or false)
        net.WriteUInt(math.Clamp(math.ceil(p.burn or 0), 0, 100), 7)
    end
end

function Med.ReadInjuries()
    local t = {}
    for _, l in ipairs(Med.LIMBS) do
        t[l] = { dmg = net.ReadUInt(7), bleed = net.ReadUInt(2), limp = net.ReadBool(), frac = net.ReadBool(), burn = net.ReadUInt(7) }
    end
    return t
end

-- Client: Med.injOf[ply] = last received table (nil when unhurt; weak keys
-- so gone players drop out), Med.myInj = your own.
if CLIENT then
    Med.injOf = Med.injOf or setmetatable({}, { __mode = "k" })
    Rhylib.Net.Receive("med.inj", function()
        local who = net.ReadEntity()
        local t = Med.ReadInjuries()
        if not IsValid(who) then return end
        local any = false
        for _, l in ipairs(Med.LIMBS) do
            local p = t[l]
            if p.dmg > 0 or p.bleed > 0 or p.limp or p.frac or p.burn > 0 then any = true break end
        end
        Med.injOf[who] = any and t or nil
        if who == LocalPlayer() then Med.myInj = Med.injOf[who] end
    end)
end
