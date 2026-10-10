--[[
    Jetpack settings and the jetpack item (shared file). Adds
    Rhylib.Jetpack (J): DT slot numbers, Fuel, SetLine, Has, Flying.
    Flight is sh_10_move.lua, equipping sv_10_equip.lua, visuals
    cl_10_effects.lua.

    The jetpack is worn in the Back slot, so a player carries either a
    jetpack or a backpack. Needs rhylib_inventory for the item; without
    it, admins can still give the jetpack with rhylib_jetpack_give.

    State lives in the player's own network vars, which the engine
    predicts, so flight feels instant even with ping:
        DTBool 31  wearing a jetpack
        DTBool 30  locked (ran dry, must land and recharge)
        DTBool 29  thrusting right now (for effects)
        DTFloat 30 fuel at the start of the line, 0 to 1
        DTFloat 31 when the line starts (in the future while refill waits)
        DTFloat 23 fuel per second along the line (minus = thrusting)
    Fuel is a line like rhylib_stamina's: fuel now = DTFloat 30 +
    DTFloat 23 * max(0, now - DTFloat 31), clamped to 0..1. It is only
    rewritten when the slope changes, so a long flight sends nothing
    tick by tick. Read it with J.Fuel(ply).
    High slots are used so they don't clash with player classes that
    use the low slots.

    Per-player values: rhylib_skills (K.JetCfg) can change fuelTime,
    rechargeTime, climbSpeed, airAccel, maxAirSpeed and hoverFuel for one
    player (Airborne skills); the config values are everyone's base.
]]

Rhylib.Jetpack = Rhylib.Jetpack or {}
local J = Rhylib.Jetpack

J.DT_HAS = 31
J.DT_LOCKED = 30
J.DT_THRUST = 29
J.DT_FUEL = 30
J.DT_FROM = 31
J.DT_RATE = 23

local Config = Rhylib.Config
Config.Register("jetpack", "fuelTime", 10, "Seconds of thrust from a full tank (rhylib_skills Airborne: skills airborneFuel)")
Config.Register("jetpack", "rechargeTime", 6, "Seconds to refill an empty tank while on the ground")
Config.Register("jetpack", "rechargeDelay", 0.5, "Seconds on the ground before refilling starts")
Config.Register("jetpack", "unlockAt", 0.35, "After running dry, fuel needed before the jetpack works again")
Config.Register("jetpack", "climbSpeed", 230, "Vertical speed the jetpack steers toward while thrusting (units/s)")
Config.Register("jetpack", "climbTau", 0.35, "How quickly it reaches climb speed when already rising (seconds)")
Config.Register("jetpack", "brakeTau", 0.12, "How quickly it cancels a fall (seconds); lower = harder braking")
Config.Register("jetpack", "maxAccel", 1500, "Cap on the upward force while rising (units/s^2)")
Config.Register("jetpack", "brakeAccel", 640, "Cap on the braking force while falling (units/s^2). Lower = long falls take longer to stop, so you must start braking early")
Config.Register("jetpack", "airAccel", 420, "Sideways steering while thrusting (units/s^2)")
Config.Register("jetpack", "maxAirSpeed", 235, "Top sideways speed from steering (units/s)")
Config.Register("jetpack", "airStopTau", 0.3, "How quickly sideways movement stops with no keys held (seconds); lower = stops faster")
Config.Register("jetpack", "loadFuelMult", 0.3, "At a full load the jetpack burns this much more fuel (0.3 = 30% faster)")
Config.Register("jetpack", "hoverFuel", 1, "Fuel burn multiplier while hovering (rhylib_skills Hover: skills hoverFuelMult)")

-- J.Fuel(ply, t): fuel at time t (default now), 0 to 1. Both realms.
-- Example: if Rhylib.Jetpack.Fuel(ply) < 0.2 then ... end
function J.Fuel(ply, t)
    local v = ply:GetDTFloat(J.DT_FUEL) + ply:GetDTFloat(J.DT_RATE) * math.max(0, (t or CurTime()) - ply:GetDTFloat(J.DT_FROM))
    return math.Clamp(v, 0, 1)
end

-- J.SetLine(ply, fuel, from, rate): start a new fuel line: fuel at time
-- from, changing by rate per second. Call it in predicted code (SetupMove)
-- or on the server.
-- Example: Rhylib.Jetpack.SetLine(ply, 1, 0, 0)   -- full tank
function J.SetLine(ply, fuel, from, rate)
    ply:SetDTFloat(J.DT_FUEL, fuel)
    ply:SetDTFloat(J.DT_FROM, from)
    ply:SetDTFloat(J.DT_RATE, rate)
end

-- J.Has(ply): wearing a jetpack (DTBool 31).
function J.Has(ply)
    return ply:GetDTBool(J.DT_HAS)
end

-- In the air with a jetpack on (large weapons can't fire then).
function J.Flying(ply)
    return J.Has(ply) and not ply:OnGround()
end

-- The item (only when rhylib_inventory loaded first; its autorun sorts
-- before ours). Its model is a setting on the Models page (item.jetpack)
-- and is also the model drawn on players' backs.
if Rhylib.Items then
    Rhylib.Items.Register("jetpack", {
        name = "Jetpack",
        w = 2, h = 2,
        category = "gear",
        slot = "back",
        weight = 8,
        model = "models/thrusters/jetpack.mdl",  -- placeholder (GMod thruster model)
    })
end
