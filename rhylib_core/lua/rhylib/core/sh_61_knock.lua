--[[
    Knocked down (shared): no input for a while. Used by explosion
    knockdowns (rhylib_weapons, soft) and training eliminations
    (rhylib_training, a server ragdoll from sh_60_lying.lua).

      L.Knock(ply, secs, push, soft)   lie down; secs 0 = until L.Unknock;
                                       push = velocity added
      L.Unknock(ply)             get up (not if downed meanwhile)
      L.Knocked(ply)             true while knocked
      L.SoftKnocked(ply)         true while knocked the soft way

    Soft: no server ragdoll. The player (hidden on the clients: a NoDraw
    player isn't sent to others at all; crouched, others walk through)
    is thrown and slides to a stop; every client makes its own
    ragdoll pulled towards that spot (cl_60_lying.lua), and the player
    gets up where they are. Soft-knocked players take no damage at all
    (so they can't be downed or killed while the body is client-only) and
    bolts pass through them.

    NW2Float rhylib_knockEnd: when it ends (-1 = no set end, 0 = not knocked).
    NW2Bool rhylib_knockSoft.
    Hook fired: Rhylib.PlayerUnknocked(ply) when it ends (timer, L.Unknock,
    downed, death, spawn). Listens to Rhylib.PlayerDowned (rhylib_medical).
    While knocked: no suicide, no DarkRP job change.
    Example (server): Rhylib.Lying.Knock(ply, 4, Vector(0, 0, 200), true)
    -- a 4 s soft knockdown with a small throw.
]]

local L = Rhylib.Lying

-- L.Knocked(ply): true while knocked down (shared).
function L.Knocked(ply)
    return ply:GetNW2Float("rhylib_knockEnd", 0) ~= 0
end

function L.SoftKnocked(ply)
    return ply:GetNW2Bool("rhylib_knockSoft", false)
end

-- No input while knocked; looking around is fine. Soft: held crouched
-- (a low hull, like the body).
Rhylib.Hook.Add("StartCommand", "core.knock", function(ply, cmd)
    if ply:GetNW2Float("rhylib_knockEnd", 0) ~= 0 then
        cmd:ClearButtons()
        cmd:ClearMovement()
        if L.SoftKnocked(ply) then cmd:SetButtons(IN_DUCK) end
    end
end, -140)

Rhylib.Hook.Add("SetupMove", "core.knock", function(ply, mv)
    if ply:GetNW2Float("rhylib_knockEnd", 0) == 0 then return end
    mv:SetForwardSpeed(0)
    mv:SetSideSpeed(0)
    mv:SetUpSpeed(0)
    mv:SetButtons(L.SoftKnocked(ply) and IN_DUCK or 0)
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

-- Soft knockdown over. (The player moved as a real crouched hull, so
-- never inside anything: the engine stands them up when there's room.)
local function endSoft(ply)
    if not ply:GetNW2Bool("rhylib_knockSoft", false) then return end
    ply:SetNW2Bool("rhylib_knockSoft", false)
    if ply.rhylibKnockCG then
        if not L.Ragdoll(ply) then ply:SetCollisionGroup(ply.rhylibKnockCG) end
        ply.rhylibKnockCG = nil
    end
end

-- L.Unknock(ply) (server): get up now (the ragdoll goes unless they were
-- downed or stunned meanwhile). Fires Rhylib.PlayerUnknocked.
function L.Unknock(ply)
    if not IsValid(ply) then return end
    timer.Remove("Rhylib.Knock." .. ply:EntIndex())
    if not L.Knocked(ply) then return end
    ply:SetNW2Float("rhylib_knockEnd", 0)
    restoreView(ply)
    endSoft(ply)
    if not ply.rhylibDown and L.Ragdoll(ply) then
        -- (stunned meanwhile: rhylib_mp gets them up)
        local MP = Rhylib.MP
        if not (MP and MP.IsStunned and MP.IsStunned(ply)) then L.End(ply) end
    end
    hook.Run("Rhylib.PlayerUnknocked", ply)
end

-- L.Knock(ply, secs, push, soft) (server): knock down. Refused (returns
-- false) when dead, downed, already knocked or already lying (stunned).
-- secs 0/nil = until L.Unknock. push: a velocity (soft: added to the
-- player, with at least 170 up; else added to every ragdoll part).
-- soft: no server ragdoll (see the top).
-- Returns true if they went down.
function L.Knock(ply, secs, push, soft)
    if not IsValid(ply) or not ply:Alive() or ply.rhylibDown or L.Knocked(ply) or L.Ragdoll(ply) then return false end
    if ply:InVehicle() then ply:ExitVehicle() end
    if soft then
        -- Off a grapple rope or jetpack thrust first (they'd hold them up).
        local G = Rhylib.Weapons and Rhylib.Weapons.Grapple
        if G and G.Detach and G.Attached and G.Attached(ply) then G.Detach(ply) end
        local J = Rhylib.Jetpack
        if J and J.DT_THRUST and ply:GetDTBool(J.DT_THRUST) then ply:SetDTBool(J.DT_THRUST, false) end
        ply:SetNW2Bool("rhylib_knockSoft", true)
        if ply:GetCollisionGroup() ~= COLLISION_GROUP_WEAPON then
            ply.rhylibKnockCG = ply:GetCollisionGroup()
            ply:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        end
        if push then
            -- (under 140 up the movement code puts them straight back on the ground)
            push = Vector(push.x, push.y, math.max(push.z, 170))
            ply:SetGroundEntity(NULL)
            ply:SetPos(ply:GetPos() + Vector(0, 0, 2))
            ply:SetVelocity(push)   -- (adds to a player's velocity)
        end
    else
        L.Begin(ply)
        local rag = L.Ragdoll(ply)
        if not IsValid(rag) then return false end
        if push then
            for i = 0, rag:GetPhysicsObjectCount() - 1 do
                local phys = rag:GetPhysicsObjectNum(i)
                if IsValid(phys) then phys:AddVelocity(push) end
            end
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
    -- (medical restores the collision group when they're revived)
    if ply.rhylibKnockCG then
        ply.rhylibCollision = ply.rhylibKnockCG
        ply.rhylibKnockCG = nil
    end
    endSoft(ply)
    hook.Run("Rhylib.PlayerUnknocked", ply)
end)

-- Soft-knocked: no damage of any kind (before everything else).
Rhylib.Hook.Add("EntityTakeDamage", "core.knock.soft", function(ent, dmg)
    if ent:IsPlayer() and ent:GetNW2Bool("rhylib_knockSoft", false) then return true end
end, -1000)

-- Killed anyway (admin slay): shown before the engine makes the death ragdoll.
Rhylib.Hook.Add("DoPlayerDeath", "core.knock", function(ply)
    endSoft(ply)
end)

local function clear(ply)
    timer.Remove("Rhylib.Knock." .. ply:EntIndex())
    restoreView(ply)
    endSoft(ply)
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
