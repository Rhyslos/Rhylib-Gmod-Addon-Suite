--[[
    Injuries (Barotrauma style). Each player has six body parts:
        head, torso, left arm, right arm, left leg, right leg
    and each part has:
        dmg     0-100   how hurt it is (white -> red in the H menu)
        bleed   0/1/2   none, light, heavy: health lost over time
        frac    bool    fracture (arms and legs)
        splint  bool    the fracture is splinted (no limp, can aim; still
                        no sprinting, and only the med bay sets it)
        burn    0-100   burns (explosions, fire)
    Painkillers (NW2Float rhylib_painkill, until): hurt limbs, a hurt
    torso and burns don't count for a while; fractures still do.

    Effects (worked out here, used by movement, stamina and weapons):
        legs    hurt or broken: no sprinting; broken: slower walk
        arms    hurt or broken: no aiming down sights, more spread
        torso   hurt: lower stamina cap; torso hits also drain stamina
        burns   pain: a little extra spread

    The server owns the state and sends it to the injured player and to
    anyone looking at them in the H menu ("med.inj", on change). Other
    clients don't know it.

    Treatment: drag a kit onto a body part in the H menu (your own body,
    or the person you looked at when pressing H). It takes a moment
    (medkitLimbTime / firstAidLimbTime; yourself: selfMult times longer):
      troopers  medkit: stops the part's bleeding, gives medkitHeal health.
      medics    first aid kit: fixes the part completely (bleeding,
                fracture, burns, damage), uses charge. Medkit: stops
                bleeding and heals damage and burns, but doesn't set bones.
    Medics also see exact numbers, fractures, burns and effects; troopers
    see roughly how hurt each part is and whether it bleeds.
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
Config.Register("medical", "lightBleedAt", 12, "A hit this strong (or more) starts light bleeding")
Config.Register("medical", "heavyBleedAt", 35, "A hit this strong (or more) starts heavy bleeding")
Config.Register("medical", "lightBleed", 0.4, "Health lost per second from each lightly bleeding part")
Config.Register("medical", "heavyBleed", 1.5, "Health lost per second from each heavily bleeding part")
Config.Register("medical", "lightBleedStops", 60, "Seconds before light bleeding stops by itself (heavy doesn't)")
Config.Register("medical", "fractureAt", 30, "An arm or leg hit this strong (or more) breaks the bone")
Config.Register("medical", "fallFractureAt", 20, "Fall damage this high (or more) breaks a leg")
Config.Register("medical", "recover", 0.25, "Damage a part recovers per second by itself (only with no bleeding, fracture or burns)")
Config.Register("medical", "burnRecover", 0.05, "Burns a part recovers per second by itself")
Config.Register("medical", "legNoSprintAt", 40, "Leg damage from which you can't sprint")
Config.Register("medical", "fractureWalkMult", 0.7, "Walk speed with a broken leg")
Config.Register("medical", "armNoAimAt", 40, "Arm damage from which you can't aim down sights")
Config.Register("medical", "armSpread", 0.8, "Extra spread at a fully hurt (or broken) arm, as a share of the weapon's resting cone")
Config.Register("medical", "burnSpread", 0.25, "Extra spread at full burns (pain), as a share of the resting cone")
Config.Register("medical", "torsoStaminaHit", 0.8, "Stamina lost per point of torso damage taken")
Config.Register("medical", "torsoStaminaCap", 0.5, "Share of max stamina lost at a fully hurt torso")
Config.Register("medical", "firstAidLimbHealth", 50, "Health a first aid kit gives when treating a body part (from its charge)")
Config.Register("medical", "medkitLimbRepair", 40, "Damage and burns a medkit use removes from a body part")
Config.Register("medical", "viewRange", 120, "How close you must be to open someone's injury menu (units)")

local function cfg(k) return Config.Get("medical", k) end

-- An empty part, for players we know nothing about.
local EMPTY = { dmg = 0, bleed = 0, frac = false, splint = false, burn = 0 }
Med.EMPTY_LIMB = EMPTY

-- The injury table of a player: { [limb] = part }. Server: everyone's.
-- Client: your own and the patient you're looking at (Med.injOf);
-- anyone else reads as unhurt.
function Med.Injuries(ply)
    if SERVER then return Med.inj and Med.inj[ply] end
    return Med.injOf and Med.injOf[ply]
end

function Med.Part(ply, limb)
    local t = Med.Injuries(ply)
    return t and t[limb] or EMPTY
end

-- Effects ------------------------------------------------------------

function Med.Painkilled(ply)
    return ply:GetNW2Float("rhylib_painkill", 0) > CurTime()
end

-- Field triage (officer order) mutes every affliction until this time;
-- the simplified medical system mutes them all the time.
function Med.Muted(ply)
    return Med.Simple() or ply:GetNW2Float("rhylib_afflMute", 0) > CurTime()
end

local function broken(p) return p.frac and not p.splint end

-- Damage and burns rounded up, as the client gets them over the net
-- (med.inj), so predicted checks agree on server and client.
local ceil = math.ceil

function Med.NoSprint(ply)
    if Med.Muted(ply) then return false end
    local at = Med.Painkilled(ply) and 1000 or cfg("legNoSprintAt")
    for _, l in ipairs(Med.LEGS) do
        local p = Med.Part(ply, l)
        if p.frac or ceil(p.dmg) >= at then return true end
    end
    return false
end

function Med.BrokenLeg(ply)
    if Med.Muted(ply) then return false end
    return broken(Med.Part(ply, "lleg")) or broken(Med.Part(ply, "rleg"))
end

function Med.CanAim(ply)
    if Med.Muted(ply) then return true end
    local at = Med.Painkilled(ply) and 1000 or cfg("armNoAimAt")
    for _, l in ipairs(Med.ARMS) do
        local p = Med.Part(ply, l)
        if broken(p) or ceil(p.dmg) >= at then return false end
    end
    return true
end

-- Extra spread in degrees from hurt arms and burns.
function Med.SpreadPenalty(ply, baseCone)
    local t = Med.Injuries(ply)
    if not t or Med.Muted(ply) then return 0 end
    local pk = Med.Painkilled(ply)
    local arm = 0
    for _, l in ipairs(Med.ARMS) do
        local p = t[l]
        if p then arm = math.max(arm, broken(p) and 1 or (p.frac and 0.5 or (pk and 0 or ceil(p.dmg) / 100))) end
    end
    if pk then return arm * cfg("armSpread") * baseCone end
    local burn = 0
    for _, l in ipairs(Med.LIMBS) do
        local p = t[l]
        if p and ceil(p.burn) > burn then burn = ceil(p.burn) end
    end
    return (arm * cfg("armSpread") + burn / 100 * cfg("burnSpread")) * baseCone
end

-- Share of max stamina you can have (torso injuries lower it).
function Med.StaminaCap(ply)
    if Med.Muted(ply) then return 1 end
    local ill = Med.IllStaminaMult and Med.IllStaminaMult(ply) or 1   -- (illness, sh_50_illness.lua)
    if Med.Painkilled(ply) then return ill end
    local p = Med.Part(ply, "torso")
    return (1 - math.Clamp(ceil(p.dmg) / 100, 0, 1) * cfg("torsoStaminaCap")) * ill
end

-- Anything wrong at all (for the HUD).
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

-- Legs: no sprinting when hurt, slower walk when broken. Runs before
-- rhylib_stamina (which reads the sprint key from mv), after the downed
-- movement (-100).
local band, bnot = bit.band, bit.bnot
Rhylib.Hook.Add("SetupMove", "medical.legs", function(ply, mv)
    if not ply:Alive() or Med.IsDown(ply) or not Med.Injuries(ply) then return end
    if Med.NoSprint(ply) and mv:KeyDown(IN_SPEED) then
        mv:SetButtons(band(mv:GetButtons(), bnot(IN_SPEED)))
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed()))
    end
    if Med.BrokenLeg(ply) then
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed() * cfg("fractureWalkMult")))
    end
end, -90)

-- Wire format ("med.inj", server -> owner and viewers): the patient
-- (entity), then per part dmg 7 bits, bleed 2, fracture 1, splint 1, burn 7.
function Med.WriteInjuries(t)
    for _, l in ipairs(Med.LIMBS) do
        local p = t and t[l] or EMPTY
        net.WriteUInt(math.Clamp(math.ceil(p.dmg), 0, 100), 7)
        net.WriteUInt(p.bleed, 2)
        net.WriteBool(p.frac)
        net.WriteBool(p.splint and true or false)
        net.WriteUInt(math.Clamp(math.ceil(p.burn), 0, 100), 7)
    end
end

function Med.ReadInjuries()
    local t = {}
    for _, l in ipairs(Med.LIMBS) do
        t[l] = { dmg = net.ReadUInt(7), bleed = net.ReadUInt(2), frac = net.ReadBool(), splint = net.ReadBool(), burn = net.ReadUInt(7) }
    end
    return t
end

if CLIENT then
    Med.injOf = Med.injOf or setmetatable({}, { __mode = "k" })
    Rhylib.Net.Receive("med.inj", function()
        local who = net.ReadEntity()
        local t = Med.ReadInjuries()
        if not IsValid(who) then return end
        local any = false
        for _, l in ipairs(Med.LIMBS) do
            local p = t[l]
            if p.dmg > 0 or p.bleed > 0 or p.frac or p.burn > 0 then any = true break end
        end
        Med.injOf[who] = any and t or nil
        if who == LocalPlayer() then Med.myInj = Med.injOf[who] end
    end)
end
