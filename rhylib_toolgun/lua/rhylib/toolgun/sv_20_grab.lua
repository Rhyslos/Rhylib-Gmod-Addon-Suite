--[[
    Toolgun physgun mode (server): the toolgun itself picks things up and
    moves them, like the sandbox physgun, so it keeps its own model and
    the beam comes out of it (cl_30_grab.lua draws it).

    Mode: NW2Int rhylib_toolMode on the toolgun (0 placing, 1 physgun),
    set by net tool.mode (UInt 2) from the hold-E wheel or the physgun key.
    Physgun mode needs full toolgun access (rhylib.toolgun).

    In physgun mode (read from the player's own commands, StartCommand):
      LMB held      grab what you aim at (props, ragdolls, NPCs, Rhylib
                    fixtures; not players or held weapons; the gamemode's
                    PhysgunPickup rules apply, so prop protection does) and
                    carry it at the same distance in front of you, turning
                    with you.
      wheel         nearer / further (net tool.grabdist, Int 4 steps).
      R held        rotate it with the mouse (the view stops turning).
      RMB           while holding: freeze it there and let go. Not
                    holding: unfreeze the frozen thing you aim at.
      let go of LMB drop it (it falls).
    Letting go of a permanent thing (rhylib_core Perma) saves its new spot.
    Grabbing anything with physics wakes and unfreezes it while held.

    Tool.grabs = { [ply] = grab }. NW2 on the player for the beam:
    rhylib_grabEnt (entity), rhylib_grabLocal (the held point, in the
    entity's own space, or the held bone's for ragdolls), rhylib_grabBone
    (that bone, -1 if not a ragdoll). Pickup runs PhysgunPickup, letting
    go PhysgunDrop, freezing OnPhysgunFreeze, unfreezing asks
    CanPlayerUnfreeze. Only props with physics and NPCs can be held. One Think hook moves the held things, only while
    someone holds something.
]]

local Tool = Rhylib.Tool
local CLASS = "rhylib_toolgun"

Tool.grabs = Tool.grabs or {}
local grabs = Tool.grabs

local function note(ply, text, kind)
    Rhylib.Notify(ply, text, kind or "info", "Toolgun")
end

-- Tool.PhysOn(ply) -> holding the toolgun in physgun mode?
-- (only for whoever switched it on: a toolgun that changes hands drops
-- back to placing)
function Tool.PhysOn(ply)
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == CLASS and w:GetNW2Int("rhylib_toolMode", 0) == 1) then return false end
    if w.rhylibPhysOwner ~= ply then
        w:SetNW2Int("rhylib_toolMode", 0)
        return false
    end
    return true
end

Rhylib.Net.Register("tool.mode")
Rhylib.Net.Receive("tool.mode", function(ply)
    local mode = net.ReadUInt(2)
    local w = ply:GetActiveWeapon()
    if not (IsValid(w) and w:GetClass() == CLASS) then return end
    if mode ~= 1 then
        w:SetNW2Int("rhylib_toolMode", 0)
        return
    end
    Rhylib.Perms.Check(ply, "rhylib.toolgun", function(ok)
        if not IsValid(ply) or not IsValid(w) then return end
        if not ok then return note(ply, "Physgun mode needs full toolgun access", "bad") end
        if w:GetOwner() ~= ply then return end
        w.rhylibPhysOwner = ply
        w:SetNW2Int("rhylib_toolMode", 1)
    end)
end, { rate = 6, burst = 6 })

local MAX_REACH = 4096

-- What may be picked up: NPCs and physics props (like the physgun: not
-- map doors, lifts or anything parented), within the gamemode's and prop
-- protection's own rules (PhysgunPickup).
local function canGrab(ply, ent)
    if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() then return false end
    if ent:IsWeapon() and IsValid(ent:GetOwner()) then return false end
    if IsValid(ent:GetParent()) then return false end
    local npc = ent:IsNPC() or ent:IsNextBot()
    if not npc and not (ent:GetMoveType() == MOVETYPE_VPHYSICS and IsValid(ent:GetPhysicsObject())) then return false end
    if hook.Run("PhysgunPickup", ply, ent) == false then return false end
    return true
end

local function release(ply, freeze)
    local g = grabs[ply]
    grabs[ply] = nil
    if IsValid(ply) then
        ply:SetNW2Entity("rhylib_grabEnt", NULL)
    end
    if not g then return end
    local ent = g.ent
    if not IsValid(ent) then return end
    local phys = g.phys
    if IsValid(phys) then
        phys:SetVelocityInstantaneous(Vector(0, 0, 0))
        if freeze then
            phys:EnableMotion(false)
            local w = IsValid(ply) and ply:GetActiveWeapon() or NULL
            hook.Run("OnPhysgunFreeze", w, phys, ent, ply)
        else
            phys:EnableMotion(true)
            phys:Wake()
        end
    end
    -- (prop protection and the like undo what they did on pickup)
    if IsValid(ply) then hook.Run("PhysgunDrop", ply, ent) end
    -- A permanent thing: saved where it is now.
    local P = Rhylib.Perma
    if P and P.Is and P.Is(ent) and IsValid(ply) then
        timer.Simple(0, function()
            if not (IsValid(ent) and IsValid(ply)) then return end
            local ok, msg = P.Set(ent, true)
            if msg then note(ply, msg, ok and "good" or "bad") end
        end)
    end
end
Tool.GrabRelease = release

local function grab(ply)
    local eye = ply:EyePos()
    local tr = util.TraceLine({ start = eye, endpos = eye + ply:GetAimVector() * MAX_REACH, filter = ply, mask = MASK_SHOT })
    local ent = tr.Entity
    if not canGrab(ply, ent) then return end
    local phys
    if not ent:IsNextBot() and not ent:IsNPC() then
        phys = ent:GetPhysicsObjectNum(math.max(tr.PhysicsBone or 0, 0))
        if not IsValid(phys) then phys = ent:GetPhysicsObject() end
        if not IsValid(phys) then phys = nil end
    end
    local yawAng = Angle(0, ply:EyeAngles().y, 0)
    local entAng = phys and phys:GetAngles() or ent:GetAngles()
    local _, angLocal = WorldToLocal(vector_origin, entAng, vector_origin, yawAng)
    local g = {
        ent = ent,
        phys = phys,
        ragdoll = ent:GetClass() == "prop_ragdoll",
        dist = math.max(tr.Fraction * MAX_REACH, 40),
        localHit = phys and phys:WorldToLocal(tr.HitPos) or ent:WorldToLocal(tr.HitPos),
        angLocal = angLocal,
    }
    if phys then
        phys:EnableMotion(true)
        phys:Wake()
    end
    grabs[ply] = g
    -- (ragdolls: the point on the held bone, so the beam follows the limb)
    local bone = -1
    if g.ragdoll and phys and ent.TranslatePhysBoneToBone then bone = ent:TranslatePhysBoneToBone(math.max(tr.PhysicsBone or 0, 0)) or -1 end
    ply:SetNW2Int("rhylib_grabBone", bone)
    ply:SetNW2Entity("rhylib_grabEnt", ent)
    ply:SetNW2Vector("rhylib_grabLocal", bone >= 0 and g.localHit or ent:WorldToLocal(tr.HitPos))
end

-- Unfreeze the frozen thing aimed at (RMB, not holding).
local function unfreeze(ply)
    local eye = ply:EyePos()
    local tr = util.TraceLine({ start = eye, endpos = eye + ply:GetAimVector() * MAX_REACH, filter = ply, mask = MASK_SHOT })
    local ent = tr.Entity
    if not IsValid(ent) or ent:IsPlayer() or IsValid(ent:GetParent()) or ent:GetMoveType() ~= MOVETYPE_VPHYSICS then return end
    local phys = ent:GetPhysicsObjectNum(math.max(tr.PhysicsBone or 0, 0))
    if not IsValid(phys) then phys = ent:GetPhysicsObject() end
    if IsValid(phys) and hook.Run("CanPlayerUnfreeze", ply, ent, phys) == false then return end
    if IsValid(phys) and not phys:IsMotionEnabled() then
        phys:EnableMotion(true)
        phys:Wake()
        ply:EmitSound("buttons/lightswitch2.wav", 50, 120)
    end
end

-- Buttons and rotating, from the player's own commands.
Rhylib.Hook.Add("StartCommand", "toolgun.grab", function(ply, cmd)
    if not Tool.PhysOn(ply) or not ply:Alive() or ply:InVehicle() then
        if grabs[ply] then release(ply, false) end
        ply.rhylibGrabBtn, ply.rhylibGrabBtn2 = nil, nil
        return
    end
    local a1, a2 = cmd:KeyDown(IN_ATTACK), cmd:KeyDown(IN_ATTACK2)
    local was1, was2 = ply.rhylibGrabBtn, ply.rhylibGrabBtn2
    ply.rhylibGrabBtn, ply.rhylibGrabBtn2 = a1, a2
    local g = grabs[ply]
    if g and not IsValid(g.ent) then release(ply, false) g = nil end
    if a2 and not was2 then
        if g then
            release(ply, true)
            ply.rhylibGrabHoldOff = true   -- (no new grab until LMB is let go)
            return
        end
        unfreeze(ply)
    end
    if not a1 then ply.rhylibGrabHoldOff = nil end
    if a1 and not was1 and not g and not ply.rhylibGrabHoldOff then
        grab(ply)
        g = grabs[ply]
    elseif not a1 and g then
        release(ply, false)
        return
    end
    -- R held: the mouse turns it (the client stops the view turning).
    if g and cmd:KeyDown(IN_RELOAD) then
        local mx, my = cmd:GetMouseX(), cmd:GetMouseY()
        if mx ~= 0 or my ~= 0 then
            local a = Angle(g.angLocal.p, g.angLocal.y, g.angLocal.r)
            a:RotateAroundAxis(Vector(0, 0, 1), mx * 0.15)
            a:RotateAroundAxis(Vector(0, 1, 0), my * 0.15)
            g.angLocal = a
        end
    end
end)

-- Wheel: nearer / further.
Rhylib.Net.Register("tool.grabdist")
Rhylib.Net.Receive("tool.grabdist", function(ply)
    local steps = net.ReadInt(4)
    local g = grabs[ply]
    if not g then return end
    g.dist = math.Clamp(g.dist + steps * 24, 40, MAX_REACH)
end, { rate = 40, burst = 40 })

-- Move what's held, every tick while anyone holds something.
local ZERO = Vector(0, 0, 0)
Rhylib.Hook.Add("Think", "toolgun.grab", function()
    if next(grabs) == nil then return end
    for ply, g in pairs(grabs) do
        local ent = g.ent
        if not (IsValid(ply) and IsValid(ent)) then
            release(ply, false)
        else
            local eye = ply:EyePos()
            local target = eye + ply:GetAimVector() * g.dist
            local _, want = LocalToWorld(vector_origin, g.angLocal, vector_origin, Angle(0, ply:EyeAngles().y, 0))
            local phys = g.phys
            if IsValid(phys) then
                phys:Wake()
                if not g.ragdoll then
                    phys:SetAngles(want)
                    phys:SetAngleVelocityInstantaneous(ZERO)
                end
                local vel = (target - phys:LocalToWorld(g.localHit)) * 14
                local len = vel:Length()
                if len > 4000 then vel = vel * (4000 / len) end
                phys:SetVelocityInstantaneous(vel)
            else
                -- (NPCs and things without physics: placed directly, upright)
                ent:SetAngles(Angle(0, want.y, 0))
                ent:SetPos(ent:GetPos() + (target - ent:LocalToWorld(g.localHit)))
            end
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "toolgun.grab", function(ply) release(ply, false) end)
Rhylib.Hook.Add("PlayerDeath", "toolgun.grab", function(ply) release(ply, false) end)
