--[[
    Stamina use and recovery. Runs in SetupMove on both server and client,
    so the client predicts it: sprint stops the moment you run dry, with
    no rubber-banding.

    Stamina is a straight line in the network vars (see sh_00_config.lua).
    This only writes a new line when the slope changes, so a long sprint
    or a long rest sends nothing tick by tick.

    Sprinting = holding sprint, pressing a movement key, on the ground.
    Jumps are free for jetpack wearers (the jetpack does the work).
]]

local S = Rhylib.Stamina
local Config = Rhylib.Config
local J_DT_HAS = 31  -- rhylib_jetpack's "wearing a jetpack" bool

local function cfg(key)
    return Config.Get("stamina", key)
end

-- Start a new line: stamina st at time from, changing by rate per second.
local function setLine(ply, st, from, rate)
    ply:SetDTFloat(S.DT_STAMINA, st)
    ply:SetDTFloat(S.DT_FROM, from)
    ply:SetDTFloat(S.DT_RATE, rate)
end

Rhylib.Hook.Add("SetupMove", "stamina.move", function(ply, mv)
    if not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:InVehicle() then
        -- Ladders, noclip, vehicles: a sprint line must not keep draining.
        if ply:GetDTFloat(S.DT_RATE) < 0 then
            local now = CurTime()
            setLine(ply, S.Get(ply, now), now + cfg("regenDelay"), cfg("regen"))
        end
        return
    end

    local now = CurTime()
    local st = S.Get(ply, now)
    local rate = ply:GetDTFloat(S.DT_RATE)
    local exhausted = ply:GetDTBool(S.DT_EXHAUSTED)
    local penalty, over = S.Penalty(ply)
    local onGround = ply:OnGround()
    local regen = cfg("regen") * (1 - penalty * 0.5)
    local K = Rhylib.Skills
    if K and K.RegenMult then regen = regen * K.RegenMult(ply) end   -- (Second wind)

    -- Ran dry while sprinting: exhausted until back to exhaustedUntil
    -- (the line below then switches to resting).
    if rate < 0 and st <= 0 then exhausted = true end

    -- Sprinting
    local moving = mv:GetForwardSpeed() ~= 0 or mv:GetSideSpeed() ~= 0
    local wantsSprint = mv:KeyDown(IN_SPEED) and moving and onGround and not mv:KeyDown(IN_DUCK)
    local sprinting = wantsSprint and not exhausted and not over and st > 0

    if sprinting then
        local drain = -cfg("sprintDrain") * (1 + penalty)
        if K and K.FreeSprint and K.FreeSprint(ply) then drain = 0 end   -- (Momentum, Second wind)
        if math.abs(rate - drain) > 1e-3 then setLine(ply, st, now, drain) end
    else
        if wantsSprint then
            -- Can't sprint right now: hold the player to walking speed.
            mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed()))
        end
        if rate < 0 or (rate == 0 and ply:GetDTFloat(S.DT_FROM) <= now) then
            -- Just stopped sprinting (a Momentum sprint has rate 0): rest a moment, then recover.
            setLine(ply, st, now + cfg("regenDelay"), regen)
        elseif math.abs(rate - regen) > 1e-3 then
            -- The load changed: same stamina, new recovery speed (a wait
            -- that is still running keeps going).
            setLine(ply, st, math.max(now, ply:GetDTFloat(S.DT_FROM)), regen)
        end
    end

    -- Over the carry cap: slower walk.
    if over then
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), ply:GetWalkSpeed() * cfg("overloadWalkMult")))
    end

    -- Jumping
    if mv:KeyPressed(IN_JUMP) and onGround and not ply:GetDTBool(J_DT_HAS) then
        local cost = cfg("jumpCost")
        if st >= cost then
            st = st - cost
            if sprinting then
                setLine(ply, st, now, ply:GetDTFloat(S.DT_RATE))
            else
                setLine(ply, st, now + cfg("regenDelay"), regen)
            end
        else
            mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))  -- too tired to jump
        end
    end

    if exhausted and st >= cfg("exhaustedUntil") then exhausted = false end
    if exhausted ~= ply:GetDTBool(S.DT_EXHAUSTED) then ply:SetDTBool(S.DT_EXHAUSTED, exhausted) end
end)

if SERVER then
    -- Everyone spawns rested.
    Rhylib.Hook.Add("PlayerSpawn", "stamina.reset", function(ply)
        setLine(ply, cfg("max"), 0, 0)
        ply:SetDTBool(S.DT_EXHAUSTED, false)
    end)
end
