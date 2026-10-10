--[[
    Jetpack flight. Runs in SetupMove on both server and client, so the
    client predicts it and it feels as responsive as walking.

    Hold jump in the air to climb, or shift to hover at your current
    height. Vertical speed is steered toward climbSpeed (or 0 when
    hovering). Braking a fall is limited by brakeAccel: a short drop is
    caught in about a second, but a fall at top speed takes about five
    seconds to stop, so you have to start braking early. Climbing uses
    the stronger maxAccel so take-off stays responsive.

    Fuel drains while thrusting and refills once you've been on the
    ground for rechargeDelay. Running dry locks the jetpack until the
    tank is back to unlockAt.

    Shared. Hook: SetupMove "jetpack.move" (priority 0; medical's downed
    hook at -100 runs first). Writes DTBool 29 (thrusting) and 30 (locked)
    and the fuel line. In the air without thrusting the fuel holds. On a
    grapple rope (DTEntity 31 set, rhylib_weapons) thrust is off and fuel
    holds. No thrust under water (WaterLevel 2+) or off MOVETYPE_WALK.
    Shift (sprint key) = hover, jump = climb.
]]

local J = Rhylib.Jetpack
local Config = Rhylib.Config
local gravityVar = GetConVar("sv_gravity")

local function cfg(key)
    return Config.Get("jetpack", key)
end

-- Per-player values (rhylib_skills Airborne changes fuel and speed).
local PER_PLAYER = { fuelTime = true, rechargeTime = true, climbSpeed = true, airAccel = true, maxAirSpeed = true, hoverFuel = true }
local function pcfg(ply, key)
    local v = cfg(key)
    local K = Rhylib.Skills
    if PER_PLAYER[key] and K and K.JetCfg then return K.JetCfg(ply, key, v) end
    return v
end

-- Rewrite the fuel line only when its slope changes.
local function setRate(ply, fuel, now, rate)
    if math.abs(ply:GetDTFloat(J.DT_RATE) - rate) > 1e-4 then J.SetLine(ply, fuel, now, rate) end
end

Rhylib.Hook.Add("SetupMove", "jetpack.move", function(ply, mv)
    if not ply:GetDTBool(J.DT_HAS) then return end
    local now = CurTime()
    if IsValid(ply:GetDTEntity(31)) then
        -- On a grapple rope (rhylib_weapons): no thrust, flames off, fuel held.
        if ply:GetDTBool(J.DT_THRUST) then ply:SetDTBool(J.DT_THRUST, false) end
        setRate(ply, J.Fuel(ply, now), now, 0)
        return
    end

    local dt = FrameTime()
    local fuel = J.Fuel(ply, now)
    local locked = ply:GetDTBool(J.DT_LOCKED)
    local onGround = ply:OnGround()
    if fuel <= 0 then locked = true end

    -- Refill on the ground after rechargeDelay (a line that starts in the future).
    if onGround then
        local recharge = 1 / pcfg(ply, "rechargeTime")
        local rate = ply:GetDTFloat(J.DT_RATE)
        if rate <= 0 then
            J.SetLine(ply, fuel, now + cfg("rechargeDelay"), recharge)   -- just landed
        elseif math.abs(rate - recharge) > 1e-4 then
            J.SetLine(ply, fuel, math.max(now, ply:GetDTFloat(J.DT_FROM)), recharge)   -- skills changed
        end
        if locked and fuel >= cfg("unlockAt") then locked = false end
    end

    -- Shift hovers (holds height); jump climbs. Shift wins if both are held.
    local hover = mv:KeyDown(IN_SPEED)
    local thrusting = not onGround and not locked and fuel > 0
        and (mv:KeyDown(IN_JUMP) or hover)
        and ply:GetMoveType() == MOVETYPE_WALK
        and ply:WaterLevel() < 2

    if thrusting then
        -- Heavier loads burn fuel faster (weight and cap come from rhylib_inventory).
        local cap = ply:GetNW2Float("rhylib_carry", 0)
        local load = cap > 0 and math.min(ply:GetNW2Float("rhylib_weight", 0) / cap, 1) or 0
        local burn = (1 + cfg("loadFuelMult") * load) / pcfg(ply, "fuelTime")
        if hover then burn = burn * pcfg(ply, "hoverFuel") end   -- (Airborne Hover)
        setRate(ply, fuel, now, -burn)

        local vel = mv:GetVelocity()

        -- Vertical: steer toward the climb speed, hard when falling.
        local vz = vel.z
        local target = hover and 0 or pcfg(ply, "climbSpeed")
        local tau = vz < 0 and cfg("brakeTau") or cfg("climbTau")
        local change = (target - vz) * (1 - math.exp(-dt / tau))
        local cap = (vz < 0 and cfg("brakeAccel") or cfg("maxAccel")) * dt
        change = math.Clamp(change, -cap, cap)
        -- (the engine adds gravity after this hook: add this tick's share back)
        local g = gravityVar:GetFloat() * (ply:GetGravity() ~= 0 and ply:GetGravity() or 1)
        vel.z = vz + change + g * dt  -- also cancels the engine's gravity for this tick

        -- Sideways: the jetpack holds you still unless you press a
        -- movement key, and cancels drift that isn't where you're going.
        local ang = mv:GetMoveAngles()
        local yaw = Angle(0, ang.y, 0)
        local wish = yaw:Forward() * mv:GetForwardSpeed() + yaw:Right() * mv:GetSideSpeed()
        wish.z = 0
        local h = Vector(vel.x, vel.y, 0)
        local damp = math.exp(-dt / cfg("airStopTau"))
        if wish:LengthSqr() > 1 then
            wish:Normalize()
            local along = h:Dot(wish)
            h = wish * along + (h - wish * along) * damp   -- keep the wanted direction, kill sideways drift
            local speed = h:Length()
            local nh = h + wish * (pcfg(ply, "airAccel") * dt)
            local top = pcfg(ply, "maxAirSpeed")
            local limit = math.max(top, speed)
            if nh:Length() > limit then nh = nh:GetNormalized() * limit end
            -- Faster than the jetpack's own top speed (e.g. launched): bleed it off.
            if limit > top then nh = nh * damp end
            h = nh
        else
            h = h * damp  -- no keys: slow to a stop and hover in place
        end
        vel.x, vel.y = h.x, h.y

        mv:SetVelocity(vel)
    elseif not onGround then
        setRate(ply, fuel, now, 0)   -- in the air, not thrusting: fuel holds
    end

    if ply:GetDTBool(J.DT_LOCKED) ~= locked then ply:SetDTBool(J.DT_LOCKED, locked) end
    if ply:GetDTBool(J.DT_THRUST) ~= thrusting then ply:SetDTBool(J.DT_THRUST, thrusting) end
end)
