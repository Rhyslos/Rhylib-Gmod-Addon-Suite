--[[
    Downed movement, pose and input (shared, runs in prediction).

    Downed:  no moving, jumping, crouching, shooting or using; the view
             turns only a little around the body (it lies still). Holding
             Jump counts toward giving up. A small hull keeps the body
             low, and the camera sits near the floor.
    Dragged: the body trails the dragger on a leash. The server moves it
             after the dragger's own move (traces, no physics), so it
             follows the dragger's input, not the downed player's. Downed
             players don't collide with other players (collision group).
    Helpers: no shooting while doing an action; stabilising and treating
             lock you in place, and pressing a move key, Jump or E stops.
             Revive on the move (Combat medic): right click while dragging
             revives with a kit as you walk (NW2Bool rhylib_medDrag);
             letting go of the body stops it.
    Dragger: capped at dragSpeed (Field drag: dragSpeedSkill), no sprint;
    letting go of attack drops.
]]

local Med = Rhylib.Medical
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local DOWN_STRIP = bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_DUCK, IN_SPEED, IN_WALK, IN_ZOOM)
local MOVE_STRIP = bor(IN_JUMP, IN_DUCK, IN_SPEED)
local ACT_STRIP = bor(IN_ATTACK, IN_ATTACK2, IN_RELOAD)
local DRAG_ACT_STRIP = bor(IN_ATTACK2, IN_RELOAD, IN_SPEED)
local CANCEL_KEYS = { IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT, IN_JUMP, IN_USE }

local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 16)  -- under step height
Med.VIEW_DOWN = Vector(0, 0, 14)

-- Small hull while down, normal hull when up. Called on the server when
-- the state changes, and from SetupMove on the client for the local player.
function Med.ApplyHull(ply, down)
    ply.rhylibHullDown = down
    if down then
        ply:SetHull(HULL_MIN, HULL_MAX)
        ply:SetHullDuck(HULL_MIN, HULL_MAX)
    elseif Rhylib.Admin and Rhylib.Admin.ScaleHull then
        Rhylib.Admin.ScaleHull(ply)   -- (keeps an admin !scale size)
    else
        ply:ResetHull()
    end
end

-- Keep the view near the body's facing so the lying model doesn't spin.
local YAW_RANGE, PITCH_MIN, PITCH_MAX = 20, -60, 40
local function clampView(ply, ang)
    local base = ply:GetNW2Float("rhylib_downYaw", ang.y)
    local dy = math.NormalizeAngle(ang.y - base)
    local p = math.Clamp(math.NormalizeAngle(ang.p), PITCH_MIN, PITCH_MAX)
    if dy > YAW_RANGE or dy < -YAW_RANGE or p ~= ang.p then
        return Angle(p, base + math.Clamp(dy, -YAW_RANGE, YAW_RANGE), 0), true
    end
    return ang, false
end

Rhylib.Hook.Add("StartCommand", "medical.input", function(ply, cmd)
    if Med.IsDown(ply) then
        cmd:RemoveKey(DOWN_STRIP)
        if SERVER then
            local ang, changed = clampView(ply, cmd:GetViewAngles())
            if changed then cmd:SetViewAngles(ang) end
        end
    elseif ply:GetNW2Int("rhylib_medAct", 0) ~= 0 then
        -- (reviving while dragging: attack stays held for the drag)
        if ply:GetNW2Bool("rhylib_medDrag", false) then
            cmd:RemoveKey(DRAG_ACT_STRIP)
        else
            cmd:RemoveKey(ACT_STRIP)
        end
    elseif Med.Dragging(ply) then
        cmd:RemoveKey(IN_SPEED)
    end
end)

if CLIENT then
    -- The real view is turned on the client; the server clamps the same way.
    Rhylib.Hook.Add("CreateMove", "medical.view", function(cmd)
        local ply = LocalPlayer()
        if not Med.IsDown(ply) then return end
        local ang, changed = clampView(ply, cmd:GetViewAngles())
        if changed then cmd:SetViewAngles(ang) end
    end, 100)  -- after the third-person aim fix
end

Rhylib.Hook.Add("SetupMove", "medical.move", function(ply, mv, cmd)
    local down = Med.IsDown(ply)
    if CLIENT and (ply.rhylibHullDown or false) ~= down then Med.ApplyHull(ply, down) end

    if down then
        -- Giving up: hold Jump.
        if mv:KeyDown(IN_JUMP) then
            ply.rhylibGiveUp = ply.rhylibGiveUp or CurTime()
            if SERVER and CurTime() - ply.rhylibGiveUp >= Med.Cfg("giveUpTime") then
                Med.GiveUp(ply)
            end
        else
            ply.rhylibGiveUp = nil
        end
        mv:SetButtons(band(mv:GetButtons(), bnot(MOVE_STRIP)))
        mv:SetForwardSpeed(0)
        mv:SetSideSpeed(0)
        mv:SetUpSpeed(0)
        return
    end
    if ply.rhylibGiveUp then ply.rhylibGiveUp = nil end

    local act = ply:GetNW2Int("rhylib_medAct", 0)
    -- (a revive while dragging, Revive on the move: walking and the drag go on)
    if act ~= 0 and not ply:GetNW2Bool("rhylib_medDrag", false) then
        if SERVER then
            for _, k in ipairs(CANCEL_KEYS) do
                if mv:KeyPressed(k) then
                    Med.Cancel(ply)
                    return
                end
            end
        end
        mv:SetForwardSpeed(0)
        mv:SetSideSpeed(0)
        mv:SetButtons(band(mv:GetButtons(), bnot(MOVE_STRIP)))
        return
    end

    local dragging = Med.Dragging(ply)
    if dragging then
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), Med.DragSpeed(ply)))
        if SERVER and (not mv:KeyDown(IN_ATTACK) or not Med.HoldingHands(ply)) then
            Med.StopDrag(ply)
        elseif SERVER and act == 0 and mv:KeyPressed(IN_ATTACK2) and Med.DragRevive then
            Med.DragRevive(ply, dragging)   -- (Revive on the move, sv_20_actions.lua)
        end
        return
    end

    if SERVER and mv:KeyPressed(IN_ATTACK) and Med.HoldingHands(ply) and ply:Alive() then
        local t = Med.FindDowned(ply, Med.downList)
        if t then Med.StartDrag(ply, t) end
    end
end, -100)  -- before the jetpack and grapple, which read Jump

-- Dragged bodies follow the dragger on a leash: step up, slide across,
-- settle down, like a simple walk move. Server only, after the dragger moves.
local STEP = 16
local function dragBody(body, dragger)
    -- A ragdoll body (rhylib_core) is pulled by its chest; the player
    -- follows the ragdoll.
    local L = Rhylib.Lying
    if L and L.Pull and L.Pull(body, dragger:GetPos(), Med.Cfg("dragLeash"), 300) then return end
    local pos = body:GetPos()
    local to = dragger:GetPos() - pos
    to.z = 0
    local dist = to:Length()
    local leash = Med.Cfg("dragLeash")
    local dt = FrameTime()
    local move = vector_origin
    if dist > leash then
        move = to * (math.min(dist - leash, 400 * dt) / dist)
    end

    local mins, maxs = body:OBBMins(), body:OBBMaxs()
    local filter = { body, dragger }
    local up = util.TraceHull({ start = pos, endpos = pos + Vector(0, 0, STEP), mins = mins, maxs = maxs, filter = filter, mask = MASK_PLAYERSOLID })
    local across = util.TraceHull({ start = up.HitPos, endpos = up.HitPos + move, mins = mins, maxs = maxs, filter = filter, mask = MASK_PLAYERSOLID })
    local downTr = util.TraceHull({ start = across.HitPos, endpos = across.HitPos - Vector(0, 0, STEP * 2 + 600 * dt), mins = mins, maxs = maxs, filter = filter, mask = MASK_PLAYERSOLID })
    if downTr.StartSolid then return end
    if downTr.HitPos:DistToSqr(pos) > 0.01 then body:SetPos(downTr.HitPos) end
end

if SERVER then
    Rhylib.Hook.Add("FinishMove", "medical.drag", function(ply, mv)
        local body = ply:GetNW2Entity("rhylib_dragging")
        if IsValid(body) and body:GetNW2Entity("rhylib_dragBy") == ply then dragBody(body, ply) end
    end)
end

-- A dragged body doesn't move itself (the dragger moves it).
Rhylib.Hook.Add("Move", "medical.drag", function(ply, mv)
    if Med.IsDown(ply) and Med.DraggedBy(ply) then
        mv:SetVelocity(vector_origin)
        return true
    end
end)

-- Downed players can't change weapons.
Rhylib.Hook.Add("PlayerSwitchWeapon", "medical.noswitch", function(ply)
    if Med.IsDown(ply) then return true end
end)

--------------------------------------------------------------------------
-- Pose: a death animation played once, then its last frame held. Runs
-- on the server too, so hitboxes match. Clients draw a ragdoll once the
-- fall is over (rhylib_core cl_60_lying.lua).
--------------------------------------------------------------------------

local function downSequence(ply)
    local mdl = ply:GetModel()
    if ply.rhylibDownMdl ~= mdl then
        ply.rhylibDownMdl = mdl
        ply.rhylibDownSeq = -1
        local list = Med.Cfg("downSequences")
        if istable(list) then
            for _, name in ipairs(list) do
                local seq = ply:LookupSequence(name)
                if seq and seq > 0 then
                    ply.rhylibDownSeq = seq
                    break
                end
            end
        end
    end
    return ply.rhylibDownSeq
end

Rhylib.Hook.Add("CalcMainActivity", "medical.pose", function(ply)
    if not Med.IsDown(ply) then return end
    local seq = downSequence(ply)
    if seq > 0 then return ACT_MP_STAND_IDLE, seq end
end)

local POSE_ZERO = { "aim_yaw", "aim_pitch", "head_yaw", "head_pitch" }

Rhylib.Hook.Add("UpdateAnimation", "medical.pose", function(ply)
    local seq = Med.IsDown(ply) and downSequence(ply) or -1
    if seq <= 0 then return end
    ply:SetPlaybackRate(0)
    -- The fall plays once, then holds (rhylib_core), else the last frame.
    ply:SetCycle(Rhylib.Lying and Rhylib.Lying.Cycle(ply, seq) or 0.99)
    for i = 1, #POSE_ZERO do ply:SetPoseParameter(POSE_ZERO[i], 0) end
    if CLIENT then ply:SetRenderAngles(Angle(0, ply:GetNW2Float("rhylib_downYaw", 0), 0)) end
    return true
end)
