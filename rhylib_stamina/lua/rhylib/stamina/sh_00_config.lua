--[[
    Stamina settings and the maths shared by server, client and HUD.

    Stamina runs from 0 to max. Sprinting and jumping use it; it comes
    back after a short rest. Running completely dry leaves you exhausted:
    no sprinting until you're back to exhaustedUntil.

    Carried weight (from rhylib_inventory) makes it drain faster and
    recover slower:
        load    = weight / carry cap
        penalty = maxPenalty * load ^ penaltyCurve     (capped at load 1)
        drain   = sprintDrain * (1 + penalty)
        regen   = regen * (1 - penalty / 2)
    maxPenalty is lower with a backpack worn. Over the carry cap you
    can't sprint and walk slower (overloadWalkMult).

    State lives in the player's own network vars, predicted like movement.
    Player network vars go to every client that can see the player, so
    stamina is stored as a straight line that only changes when
    something changes (sprint starts or stops, a jump, the load changes),
    not every tick:
        DTFloat 28  stamina at the start of the line
        DTFloat 29  when the line starts (in the future while regen waits)
        DTFloat 26  stamina per second along the line (minus = sprinting)
        DTBool  28  exhausted
        stamina now = DTFloat 28 + DTFloat 26 * max(0, now - DTFloat 29),
                      kept between 0 and max
    The jetpack uses slots 29-31 for its bools and 30-31 for its floats.
]]

Rhylib.Stamina = Rhylib.Stamina or {}
local S = Rhylib.Stamina

S.DT_STAMINA = 28
S.DT_FROM = 29
S.DT_RATE = 26
S.DT_EXHAUSTED = 28

local Config = Rhylib.Config
Config.Register("stamina", "max", 100, "Full stamina")
Config.Register("stamina", "sprintDrain", 12, "Stamina per second while sprinting with no load (100 / 12 = about 8 s of sprint)")
Config.Register("stamina", "jumpCost", 8, "Stamina per jump")
Config.Register("stamina", "regen", 20, "Stamina per second while resting, with no load")
Config.Register("stamina", "regenDelay", 1, "Seconds after sprinting or jumping before stamina comes back")
Config.Register("stamina", "exhaustedUntil", 25, "After running dry, no sprinting until stamina is back to this")
Config.Register("stamina", "maxPenalty", 0.8, "Penalty at a full load without a backpack")
Config.Register("stamina", "maxPenaltyPack", 0.6, "Penalty at a full load with a backpack worn")
Config.Register("stamina", "penaltyCurve", 1.2, "Higher = light loads cost less, the last kilos cost more")
Config.Register("stamina", "heavyFrom", 0.75, "Above this share of your carry cap you also move slower")
Config.Register("stamina", "heavySlow", 0.1, "Speed lost at a full load (0.1 = 10% slower walk and sprint); grows from heavyFrom")
Config.Register("stamina", "overloadWalkMult", 0.8, "Walk speed multiplier while over the carry cap")
Config.Register("stamina", "lowAimBelow", 20, "Below this stamina, spread starts to grow")
Config.Register("stamina", "lowAimSpread", 0.5, "Extra spread at zero stamina, as a fraction of the weapon's resting cone")

local function cfg(key)
    return Config.Get("stamina", key)
end

-- Most stamina this player can have (a hurt torso lowers it, rhylib_medical).
function S.Max(ply)
    local Med = Rhylib.Medical
    local cap = Med and Med.StaminaCap and Med.StaminaCap(ply) or 1
    return cfg("max") * cap
end

-- Stamina at time t (default now).
function S.Get(ply, t)
    local v = ply:GetDTFloat(S.DT_STAMINA) + ply:GetDTFloat(S.DT_RATE) * math.max(0, (t or CurTime()) - ply:GetDTFloat(S.DT_FROM))
    return math.Clamp(v, 0, S.Max(ply))
end

function S.Frac(ply)
    return S.Get(ply) / cfg("max")
end

-- Take stamina away now (server; e.g. a torso hit). The line keeps its slope.
function S.Drain(ply, amount)
    if not SERVER or amount <= 0 then return end
    local now = CurTime()
    local st = math.max(0, S.Get(ply, now) - amount)
    local rate = ply:GetDTFloat(S.DT_RATE)
    ply:SetDTFloat(S.DT_STAMINA, st)
    ply:SetDTFloat(S.DT_FROM, rate < 0 and now or math.max(now, ply:GetDTFloat(S.DT_FROM)))
end

function S.Exhausted(ply)
    return ply:GetDTBool(S.DT_EXHAUSTED)
end

-- Weight and carry cap from rhylib_inventory (0 and the base cap without it).
function S.Load(ply)
    local weight = ply:GetNW2Float("rhylib_weight", 0)
    -- (only asked when rhylib_inventory registered it: no "unknown setting" warning without it)
    local base = (Config.defs.inventory and Config.Get("inventory", "baseCarry")) or 20
    local cap = ply:GetNW2Float("rhylib_carry", base)
    if cap <= 0 then cap = base end
    return weight / cap, cap > base
end

-- Penalty from 0 to maxPenalty, and whether the player is over the cap.
function S.Penalty(ply)
    local load, pack = S.Load(ply)
    local maxPen = pack and cfg("maxPenaltyPack") or cfg("maxPenalty")
    local K = Rhylib.Skills
    if K and K.WeightPenaltyMult then maxPen = maxPen * K.WeightPenaltyMult(ply) end   -- (Load bearer)
    return maxPen * math.min(load, 1) ^ cfg("penaltyCurve"), load > 1
end

-- Speed multiplier from weight: 1 up to heavyFrom of the cap, then down
-- to 1 - heavySlow at a full load.
function S.LoadSpeedMult(ply)
    local load = S.Load(ply)
    local from = cfg("heavyFrom") or 0.75
    if load <= from then return 1 end
    return 1 - (cfg("heavySlow") or 0) * math.min((load - from) / math.max(1 - from, 0.01), 1)
end

-- Extra spread in degrees for a weapon whose owner is low on stamina.
-- Used by rhylib_weapons (sh_10_spread.lua); all arcs grow evenly.
function S.SpreadPenalty(ply, baseCone)
    local below = cfg("lowAimBelow")
    local st = S.Get(ply)
    if st >= below then return 0 end
    return (1 - st / below) * cfg("lowAimSpread") * baseCone
end
