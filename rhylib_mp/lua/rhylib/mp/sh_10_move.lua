--[[
    Movement and pose (shared, runs in prediction).

    Stunned: no input at all, lying in a death pose (last frame).
    Cuffed:  slow walk, no sprint, jump, crouch, attack or use. Escorted
             prisoners are pulled toward the MP when they fall behind
             (server only; their client stops predicting near the leash).
]]

local MP = Rhylib.MP
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local CUFF_STRIP = bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_SPEED, IN_JUMP, IN_DUCK, IN_ZOOM)

-- Stunned view: facing where they fell, a little up/down look.
local function stunView(ply, ang)
    return Angle(math.Clamp(math.NormalizeAngle(ang.p), -25, 35), ply:GetNW2Float("rhylib_stunYaw", 0), 0)
end

Rhylib.Hook.Add("StartCommand", "mp.input", function(ply, cmd)
    if MP.IsStunned(ply) then
        cmd:ClearButtons()
        cmd:ClearMovement()
        cmd:SetViewAngles(stunView(ply, cmd:GetViewAngles()))
    elseif MP.IsCuffed(ply) then
        cmd:RemoveKey(CUFF_STRIP)
    end
end, -150)

if CLIENT then
    Rhylib.Hook.Add("CreateMove", "mp.stunview", function(cmd)
        local ply = LocalPlayer()
        if IsValid(ply) and MP.IsStunned(ply) then cmd:SetViewAngles(stunView(ply, cmd:GetViewAngles())) end
    end)
end

Rhylib.Hook.Add("SetupMove", "mp.move", function(ply, mv)
    if MP.IsStunned(ply) then
        mv:SetForwardSpeed(0)
        mv:SetSideSpeed(0)
        mv:SetUpSpeed(0)
        mv:SetButtons(0)
        return
    end
    if not MP.IsCuffed(ply) then
        -- Escorting slows the MP (rhylib_skills Escort drills: not at all).
        if MP.Escorting(ply) then
            local K = Rhylib.Skills
            if not (K and K.Has and K.Has(ply, "escort_drills")) then
                local m = MP.Cfg("escortSlow")
                mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * m)
                mv:SetMaxSpeed(mv:GetMaxSpeed() * m)
            end
        end
        return
    end
    mv:SetButtons(band(mv:GetButtons(), bnot(CUFF_STRIP)))
    mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), MP.Cfg("cuffWalk")))
    -- Escort: walk toward the MP when beyond the leash. Server only: the
    -- prisoner's client only has the MP's interpolated (late) position,
    -- so it couldn't predict this; it stops predicting near the leash
    -- instead (Move hook below) and shows where the server puts it.
    local by = SERVER and MP.EscortedBy(ply)
    if by then
        local to = by:GetPos() - ply:GetPos()
        to.z = 0
        local dist = to:Length()
        if dist > MP.Cfg("escortLeash") then
            local speed = math.min(by:GetVelocity():Length2D() + 60, 400)
            local v = to / dist * speed
            local cur = mv:GetVelocity()
            mv:SetVelocity(Vector(v.x, v.y, cur.z))
            mv:SetMaxClientSpeed(speed)
            mv:SetMaxSpeed(speed)
        end
    end
end, -95)

-- An escorted prisoner who has fallen behind isn't predicted on their own
-- client, so the client never fights the server's pull (like a dragged
-- body, rhylib_medical). Inside the leash they walk predicted as normal.
-- The MP's position here is late (interpolation + ping), so it is pushed
-- ahead by the MP's velocity, and the client hands over early (MARGIN
-- before the leash) and takes back late (2 x MARGIN), so the server never
-- pulls while the client still predicts, and the switch doesn't flicker.
if CLIENT then
    local MARGIN = 16
    local interpVar = GetConVar("cl_interp")

    Rhylib.Hook.Add("Move", "mp.escort", function(ply, mv)
        local by = MP.IsCuffed(ply) and MP.EscortedBy(ply)
        if not by then
            ply.rhylibEscortHeld = nil
            return
        end
        local lag = (interpVar and interpVar:GetFloat() or 0.1) + ply:Ping() / 1000
        local to = by:GetPos() + by:GetVelocity() * lag - mv:GetOrigin()
        to.z = 0
        local dist = to:Length()
        local leash = MP.Cfg("escortLeash")
        if ply.rhylibEscortHeld then
            if dist < math.max(0, leash - MARGIN * 2) then ply.rhylibEscortHeld = nil end
        elseif dist > math.max(0, leash - MARGIN) then
            ply.rhylibEscortHeld = true
        end
        if ply.rhylibEscortHeld then return true end
    end)
end

-- No switching weapons while cuffed or stunned.
Rhylib.Hook.Add("PlayerSwitchWeapon", "mp.noswitch", function(ply, old, new)
    if (MP.IsCuffed(ply) or MP.IsStunned(ply)) and not (IsValid(new) and new.IsRhylibStowed) then return true end
end)

--------------------------------------------------------------------------
-- Lying pose while stunned (same on server and client, so hitboxes match)
--------------------------------------------------------------------------

local function stunSequence(ply)
    local mdl = ply:GetModel()
    if ply.rhylibStunMdl ~= mdl then
        ply.rhylibStunMdl = mdl
        ply.rhylibStunSeq = -1
        local list = MP.Cfg("poses")
        if istable(list) then
            for _, name in ipairs(list) do
                local seq = ply:LookupSequence(name)
                if seq and seq > 0 then
                    ply.rhylibStunSeq = seq
                    break
                end
            end
        end
    end
    return ply.rhylibStunSeq
end

Rhylib.Hook.Add("CalcMainActivity", "mp.pose", function(ply)
    if not MP.IsStunned(ply) then return end
    local seq = stunSequence(ply)
    if seq > 0 then return ACT_MP_STAND_IDLE, seq end
end)

Rhylib.Hook.Add("UpdateAnimation", "mp.pose", function(ply)
    local seq = MP.IsStunned(ply) and stunSequence(ply) or -1
    if seq <= 0 then return end
    ply:SetPlaybackRate(0)
    -- The fall plays once, then holds (rhylib_core), else the last frame.
    ply:SetCycle(Rhylib.Lying and Rhylib.Lying.Cycle(ply, seq) or 0.99)
    ply:SetPoseParameter("aim_yaw", 0)
    ply:SetPoseParameter("aim_pitch", 0)
    ply:SetPoseParameter("head_yaw", 0)
    ply:SetPoseParameter("head_pitch", 0)
    if CLIENT then ply:SetRenderAngles(Angle(0, ply:GetNW2Float("rhylib_stunYaw", 0), 0)) end
    return true
end)
