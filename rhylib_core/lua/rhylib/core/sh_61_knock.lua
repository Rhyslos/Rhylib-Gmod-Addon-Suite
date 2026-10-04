--[[
    Knocked down (shared): a lying body (sh_60_lying.lua) with no input for
    a while. Used by explosion knockdowns (rhylib_weapons) and training
    eliminations (rhylib_training).

      L.Knock(ply, secs, push)   lie down; secs 0 = until L.Unknock; push
                                 = velocity added to the body
      L.Unknock(ply)             get up (not if downed meanwhile)
      L.Knocked(ply)             true while knocked

    NW2Float rhylib_knockEnd: when it ends (-1 = no set end, 0 = not knocked).
]]

local L = Rhylib.Lying

function L.Knocked(ply)
    return ply:GetNW2Float("rhylib_knockEnd", 0) ~= 0
end

-- No input while knocked; looking around is fine.
Rhylib.Hook.Add("StartCommand", "core.knock", function(ply, cmd)
    if ply:GetNW2Float("rhylib_knockEnd", 0) ~= 0 then
        cmd:ClearButtons()
        cmd:ClearMovement()
    end
end, -140)

Rhylib.Hook.Add("SetupMove", "core.knock", function(ply, mv)
    if ply:GetNW2Float("rhylib_knockEnd", 0) == 0 then return end
    mv:SetForwardSpeed(0)
    mv:SetSideSpeed(0)
    mv:SetUpSpeed(0)
    mv:SetButtons(0)
end, -94)

if CLIENT then return end

local VIEW_LOW = Vector(0, 0, 14)

local function restoreView(ply)
    local vo = ply.rhylibKnockView
    if not vo then return end
    ply:SetViewOffset(vo[1])
    ply:SetViewOffsetDucked(vo[2])
    ply.rhylibKnockView = nil
end

function L.Unknock(ply)
    if not IsValid(ply) then return end
    timer.Remove("Rhylib.Knock." .. ply:EntIndex())
    if not L.Knocked(ply) then return end
    ply:SetNW2Float("rhylib_knockEnd", 0)
    restoreView(ply)
    if not ply.rhylibDown and L.Ragdoll(ply) then
        -- (stunned meanwhile: rhylib_mp gets them up)
        local MP = Rhylib.MP
        if not (MP and MP.IsStunned and MP.IsStunned(ply)) then L.End(ply) end
    end
    hook.Run("Rhylib.PlayerUnknocked", ply)
end

-- Returns true if they went down.
function L.Knock(ply, secs, push)
    if not IsValid(ply) or not ply:Alive() or ply.rhylibDown or L.Knocked(ply) or L.Ragdoll(ply) then return false end
    if ply:InVehicle() then ply:ExitVehicle() end
    L.Begin(ply)
    local rag = L.Ragdoll(ply)
    if not IsValid(rag) then return false end
    if push then
        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local phys = rag:GetPhysicsObjectNum(i)
            if IsValid(phys) then phys:AddVelocity(push) end
        end
    end
    secs = secs or 0
    ply:SetNW2Float("rhylib_knockEnd", secs > 0 and CurTime() + secs or -1)
    if not ply.rhylibKnockView then
        ply.rhylibKnockView = { ply:GetViewOffset(), ply:GetViewOffsetDucked() }
        ply:SetViewOffset(VIEW_LOW)
        ply:SetViewOffsetDucked(VIEW_LOW)
    end
    if secs > 0 then
        timer.Create("Rhylib.Knock." .. ply:EntIndex(), secs, 1, function() L.Unknock(ply) end)
    end
    return true
end

-- Downed while knocked: medical takes the real view and the body.
Rhylib.Hook.Add("Rhylib.PlayerDowned", "core.knock", function(ply)
    if not L.Knocked(ply) then return end
    if ply.rhylibKnockView then ply.rhylibViewOff = ply.rhylibKnockView end
    ply.rhylibKnockView = nil
    timer.Remove("Rhylib.Knock." .. ply:EntIndex())
    ply:SetNW2Float("rhylib_knockEnd", 0)
    hook.Run("Rhylib.PlayerUnknocked", ply)
end)

local function clear(ply)
    timer.Remove("Rhylib.Knock." .. ply:EntIndex())
    restoreView(ply)
    -- Died lying: the body becomes the corpse (L.End keeps it when dead).
    if L.Knocked(ply) and not ply:Alive() and not ply.rhylibDown and L.Ragdoll(ply) then L.End(ply) end
    if ply:GetNW2Float("rhylib_knockEnd", 0) ~= 0 then
        ply:SetNW2Float("rhylib_knockEnd", 0)
        hook.Run("Rhylib.PlayerUnknocked", ply)
    end
end
Rhylib.Hook.Add("PlayerDeath", "core.knock", clear)
Rhylib.Hook.Add("PlayerSilentDeath", "core.knock", clear)
Rhylib.Hook.Add("PlayerSpawn", "core.knock", clear, -110)   -- (before lying's own clean-up at -100)
Rhylib.Hook.Add("PlayerDisconnected", "core.knock", function(ply) timer.Remove("Rhylib.Knock." .. ply:EntIndex()) end)

-- No job changes or suicide while knocked.
Rhylib.Hook.Add("CanPlayerSuicide", "core.knock", function(ply)
    if L.Knocked(ply) then return false end
end)
Rhylib.Hook.Add("playerCanChangeTeam", "core.knock", function(ply)
    if L.Knocked(ply) then return false, "You can't change job while knocked down" end
end)
