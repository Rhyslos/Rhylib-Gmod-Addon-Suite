--[[
    Jetpack settings and the jetpack item.

    The jetpack is worn in the Back slot, so a player carries either a
    jetpack or a backpack. Needs rhylib_inventory for the item; without
    it, admins can still give the jetpack with rhylib_jetpack_give.

    State lives in the player's own network vars, which the engine
    predicts, so flight feels instant even with ping:
        DTBool 31  wearing a jetpack
        DTBool 30  locked (ran dry, must land and recharge)
        DTBool 29  thrusting right now (for effects)
        DTFloat 30 fuel, 0 to 1
        DTFloat 31 time the player landed (0 while in the air)
    Slots 29-31 are used so they don't clash with player classes that
    use the low slots.
]]

Rhylib.Jetpack = Rhylib.Jetpack or {}
local J = Rhylib.Jetpack

J.DT_HAS = 31
J.DT_LOCKED = 30
J.DT_THRUST = 29
J.DT_FUEL = 30
J.DT_LANDED = 31

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

function J.Has(ply)
    return ply:GetDTBool(J.DT_HAS)
end

-- In the air with a jetpack on (large weapons can't fire then).
function J.Flying(ply)
    return J.Has(ply) and not ply:OnGround()
end

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
