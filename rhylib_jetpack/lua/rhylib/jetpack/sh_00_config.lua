--[[
    Jetpack settings and the jetpack item (shared file). Adds
    Rhylib.Jetpack (J): DT slot numbers, Fuel, SetLine, Has, Flying.
    Flight is sh_10_move.lua, equipping sv_10_equip.lua, visuals
    cl_10_effects.lua.

    The jetpack is worn in the Back slot, so a player carries either a
    jetpack or a backpack. Needs rhylib_inventory for the item; without
    it, admins can still give the jetpack with rhylib_jetpack_give.

    State lives in the player's own network vars, which the engine
    predicts, so flight feels instant even with ping (slots from
    Rhylib.DT, core's table of player DT slots):
        J.DT_HAS    (Bool  "jetpack.has")    wearing a jetpack
        J.DT_LOCKED (Bool  "jetpack.locked") locked (ran dry, must land and recharge)
        J.DT_THRUST (Bool  "jetpack.thrust") thrusting right now (for effects)
        J.DT_FUEL   (Float "jetpack.fuel")   fuel at the start of the line, 0 to 1
        J.DT_FROM   (Float "jetpack.from")   when the line starts (in the future while refill waits)
        J.DT_RATE   (Float "jetpack.rate")   fuel per second along the line (minus = thrusting)
    Fuel is a line like rhylib_stamina's: fuel now = FUEL + RATE *
    max(0, now - FROM), clamped to 0..1. It is only rewritten when the
    slope changes, so a long flight sends nothing tick by tick. Read it
    with J.Fuel(ply).
    Hook Rhylib.ForceRelease(ply) (core knockdowns) cuts thrust.

    Per-player values: rhylib_skills (K.JetCfg) can change fuelTime,
    rechargeTime, climbSpeed, airAccel, maxAirSpeed and hoverFuel for one
    player (Airborne skills); the config values are everyone's base.
]]

Rhylib.Jetpack = Rhylib.Jetpack or {}
local J = Rhylib.Jetpack

-- Player DT slots, claimed in core's table (sh_05_dt.lua) under their
-- seeded names; rhylib_stamina reads "jetpack.has" by name too.
local DT = Rhylib.DT
J.DT_HAS = DT.Claim("Bool", "jetpack.has", 31)
J.DT_LOCKED = DT.Claim("Bool", "jetpack.locked", 30)
J.DT_THRUST = DT.Claim("Bool", "jetpack.thrust", 29)
J.DT_FUEL = DT.Claim("Float", "jetpack.fuel", 30)
J.DT_FROM = DT.Claim("Float", "jetpack.from", 31)
J.DT_RATE = DT.Claim("Float", "jetpack.rate", 23)
-- (rhylib_weapons' grapple rope, read to hold thrust while on a rope)
J.DT_ROPE = DT.Claim("Entity", "grapple.rope", 31)
J.DT_ZIP = DT.Claim("Entity", "grapple.zip", 30)   -- (and its zipline)

local Config = Rhylib.Config
Config.Describe("jetpack", { name = "Jetpack", category = "Soldiers", sections = { "Fuel", "Flight" } })
Config.Register("jetpack", "fuelTime", 10, "Seconds of thrust from a full tank (rhylib_skills Airborne: skills airborneFuel)", { section = "Fuel" })
Config.Register("jetpack", "rechargeTime", 6, "Seconds to refill an empty tank while on the ground", { section = "Fuel" })
Config.Register("jetpack", "rechargeDelay", 0.5, "Seconds on the ground before refilling starts", { section = "Fuel" })
Config.Register("jetpack", "unlockAt", 0.35, "After running dry, fuel needed before the jetpack works again", { section = "Fuel" })
Config.Register("jetpack", "climbSpeed", 230, "Vertical speed the jetpack steers toward while thrusting (units/s)", { section = "Flight" })
Config.Register("jetpack", "climbTau", 0.35, "How quickly it reaches climb speed when already rising (seconds)", { section = "Flight" })
Config.Register("jetpack", "brakeTau", 0.12, "How quickly it cancels a fall (seconds); lower = harder braking", { section = "Flight" })
Config.Register("jetpack", "maxAccel", 1500, "Cap on the upward force while rising (units/s^2)", { section = "Flight" })
Config.Register("jetpack", "brakeAccel", 640, "Cap on the braking force while falling (units/s^2). Lower = long falls take longer to stop, so you must start braking early", { section = "Flight" })
Config.Register("jetpack", "airAccel", 420, "Sideways steering while thrusting (units/s^2)", { section = "Flight" })
Config.Register("jetpack", "maxAirSpeed", 235, "Top sideways speed from steering (units/s)", { section = "Flight" })
Config.Register("jetpack", "airStopTau", 0.3, "How quickly sideways movement stops with no keys held (seconds); lower = stops faster", { section = "Flight" })
Config.Register("jetpack", "loadFuelMult", 0.3, "At a full load the jetpack burns this much more fuel (0.3 = 30% faster)", { section = "Fuel" })
Config.Register("jetpack", "hoverFuel", 1, "Fuel burn multiplier while hovering (rhylib_skills Hover: skills hoverFuelMult)", { section = "Fuel" })

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

-- J.Has(ply): wearing a jetpack (J.DT_HAS).
function J.Has(ply)
    return ply:GetDTBool(J.DT_HAS)
end

-- In the air with a jetpack on (large weapons can't fire then).
function J.Flying(ply)
    return J.Has(ply) and not ply:OnGround()
end

-- The item, once rhylib_inventory has loaded (Rhylib.After: now, or right
-- after it). Its model is a setting on the Models page (item.jetpack)
-- and is also the model drawn on players' backs.
Rhylib.After("inventory", function()
    if not Rhylib.Items then return end
    Rhylib.Items.Register("jetpack", {
        name = "Jetpack",
        w = 2, h = 2,
        category = "gear",
        slot = "back",
        weight = 8,
        model = "models/thrusters/jetpack.mdl",  -- placeholder (GMod thruster model)
    })
end)

-- Knockdowns and anything else that must stop a player moving (core hook
-- Rhylib.ForceRelease) cut the thrust. Shared, harmless on the client.
Rhylib.Hook.Add("Rhylib.ForceRelease", "jetpack.release", function(ply)
    if IsValid(ply) and ply:GetDTBool(J.DT_THRUST) then ply:SetDTBool(J.DT_THRUST, false) end
end)
