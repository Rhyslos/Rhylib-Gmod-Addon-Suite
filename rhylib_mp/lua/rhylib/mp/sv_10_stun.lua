--[[
    Stun, cuffs and escort (server).

    Stun: MP.Stun lays a player down for stunTime seconds (rhylib_core
    Rhylib.Lying draws the body), with a low view and their weapon stowed.
    Only MPs' stun bolts count (hook Rhylib.StunHit from rhylib_weapons).
    After getting up they can't be stunned again for stunImmune seconds.

    Cuffs: MP.Cuff / MP.Uncuff set NW2 rhylib_cuffed. MP.cuffed lists
    cuffed players so the escort timer only walks those.

    Escort: MP.SetEscort links prisoner (rhylib_escortBy) and MP
    (rhylib_escorting); the pull itself is in sh_10_move. A 0.5 s timer
    ends escorts when the MP dies, is downed, cuffed or 400+ units away.

    Left alone: the same timer runs config cuffAutoRelease. A cuffed
    player who isn't escorted, isn't jailed and has no MP within
    cuffNearRange gets NW2Float rhylib_cuffFree = when the cuffs come off
    (the HUD counts it down); anyone holding them again clears it. At that
    time MP.Uncuff(ply) and a chat line. Binders prisoners (rhylibBound)
    are skipped: rhylib_bounty runs its own wait (bindAutoRelease).

    Also here: clearing everything on death/spawn/leave, re-cuffing
    players who left while cuffed, blocks on job change / vehicles /
    suicide / weapon pickups, and the interaction wheel actions (mp.wheel).
]]

local MP = Rhylib.MP

-- Downed right now (rhylib_medical's own answer, not Rhylib.State's
-- per-tick cache: these run inside the same tick a player goes down).
local function downNow(ply)
    local Med = Rhylib.Medical
    return Med ~= nil and Med.IsDown ~= nil and Med.IsDown(ply)
end
local STOWED = "rhylib_stowed"

MP.cuffed = MP.cuffed or {}   -- [ply] = true, for the escort check timer

local VIEW_LOW = Vector(0, 0, 14)

local function stow(ply)
    if not ply:HasWeapon(STOWED) and weapons.GetStored(STOWED) then ply:Give(STOWED) end
    if ply:HasWeapon(STOWED) then ply:SelectWeapon(STOWED) end
end

local function getUp(ply)
    if not IsValid(ply) then return end
    timer.Remove("Rhylib.MP.Stun." .. ply:EntIndex())
    ply:SetNW2Float(Rhylib.NW.STUN_END, 0)
    local vo = ply.rhylibStunView
    if vo then
        ply:SetViewOffset(vo[1])
        ply:SetViewOffsetDucked(vo[2])
        ply.rhylibStunView = nil
    end
    ply.rhylibStunImmune = CurTime() + MP.Cfg("stunImmune")
    if Rhylib.Lying and not downNow(ply) then Rhylib.Lying.End(ply) end
end

-- MP.EndStun(ply): ends a stun now (used by rhylib_admin !free). Server.
function MP.EndStun(ply)
    if IsValid(ply) and MP.IsStunned(ply) then getUp(ply) end
end

-- MP.Stun(ply, by): ply collapses for stunTime seconds. by = who stunned
-- them (passed to hooks). Does nothing if ply is dead, downed, knocked
-- down, already stunned, still immune, or hook Rhylib.CanStun returns
-- false. Does not check that by is an MP (callers do). Server only.
-- Example: Rhylib.MP.Stun(target, mp)
function MP.Stun(ply, by)
    if not IsValid(ply) or not ply:Alive() then return end
    if downNow(ply) then return end                         -- already downed (rhylib_medical)
    local L = Rhylib.Lying
    if L and L.Knocked and L.Knocked(ply) then return end     -- knocked down / out of a simulation (rhylib_core)
    if MP.IsStunned(ply) then return end                      -- no chain stuns
    if (ply.rhylibStunImmune or 0) > CurTime() then return end
    if hook.Run("Rhylib.CanStun", ply, by) == false then return end
    local t = MP.Cfg("stunTime")
    if ply:InVehicle() then ply:ExitVehicle() end
    ply:SetNW2Float("rhylib_stunYaw", ply:EyeAngles().y)
    ply:SetNW2Float(Rhylib.NW.STUN_END, CurTime() + t)
    if not ply.rhylibStunView then
        ply.rhylibStunView = { ply:GetViewOffset(), ply:GetViewOffsetDucked() }
        ply:SetViewOffset(VIEW_LOW)
        ply:SetViewOffsetDucked(VIEW_LOW)
    end
    stow(ply)
    -- Body centred on the player's position (rhylib_core; clients draw a ragdoll).
    if Rhylib.Lying then Rhylib.Lying.Begin(ply) end
    ply:EmitSound("weapons/1misc_guns/sw_stun.ogg", 80)   -- (Star Wars shared resources pack stun)
    timer.Create("Rhylib.MP.Stun." .. ply:EntIndex(), t, 1, function() getUp(ply) end)
    hook.Run("Rhylib.PlayerStunned", ply, by)
end

-- Stun guns (rhylib_weapons bolts with SWEP.Stun).
Rhylib.Hook.Add("Rhylib.StunHit", "mp.stun", function(ply, by)
    if MP.IsMP(by) then MP.Stun(ply, by) end
end)

-- Downed while stunned: medical takes over the low view, the stun ends.
Rhylib.Hook.Add("Rhylib.PlayerDowned", "mp.stun", function(ply)
    -- Medical saved the (already low) stun view; give it the real one.
    if ply.rhylibStunView then ply.rhylibViewOff = ply.rhylibStunView end
    ply.rhylibStunView = nil
    timer.Remove("Rhylib.MP.Stun." .. ply:EntIndex())
    ply:SetNW2Float(Rhylib.NW.STUN_END, 0)
end)

--------------------------------------------------------------------------
-- Cuffs
--------------------------------------------------------------------------

-- MP.Cuff(ply, by): cuffs ply (no checks on who or range: callers do that).
-- Stows their weapon and fires Rhylib.PlayerCuffed(ply, by). Server only.
-- Example: Rhylib.MP.Cuff(target, mp)
function MP.Cuff(ply, by)
    if not IsValid(ply) or MP.IsCuffed(ply) then return end
    ply:SetNW2Bool(Rhylib.NW.CUFFED, true)
    MP.ClearEscorter(ply)
    ply:SetNW2Entity("rhylib_escortBy", NULL)
    MP.cuffed[ply] = true
    ply.rhylibCuffFreeAt = nil
    ply:SetNW2Float("rhylib_cuffFree", 0)
    stow(ply)
    ply:EmitSound("npc/metropolice/gear" .. math.random(1, 6) .. ".wav", 65)
    hook.Run("Rhylib.PlayerCuffed", ply, by)
end

-- MP.Uncuff(ply, by): removes cuffs and any escort. by may be nil (system
-- uncuff, no sound). Fires Rhylib.PlayerUncuffed(ply, by). Server only.
function MP.Uncuff(ply, by)
    if not IsValid(ply) then return end
    ply:SetNW2Bool(Rhylib.NW.CUFFED, false)
    MP.ClearEscorter(ply)
    ply:SetNW2Entity("rhylib_escortBy", NULL)
    MP.cuffed[ply] = nil
    ply.rhylibCuffFreeAt = nil
    ply:SetNW2Float("rhylib_cuffFree", 0)
    if IsValid(by) then ply:EmitSound("npc/metropolice/gear" .. math.random(1, 6) .. ".wav", 65) end
    hook.Run("Rhylib.PlayerUncuffed", ply, by)
end

-- ply stops being escorted: their MP points at another prisoner they
-- still escort, or nobody.
function MP.ClearEscorter(ply)
    local by = MP.EscortedBy(ply)
    if not (by and by:GetNW2Entity("rhylib_escorting") == ply) then return end
    local other = NULL
    for p in pairs(MP.cuffed) do
        if IsValid(p) and p ~= ply and MP.EscortedBy(p) == by then other = p break end
    end
    by:SetNW2Entity("rhylib_escorting", other)
end

-- MP.SetEscort(ply, by): the cuffed ply is now escorted by MP by (nil = let
-- go). Only works on cuffed players. Server only.
-- Example: Rhylib.MP.SetEscort(prisoner, mp)
function MP.SetEscort(ply, by)
    if not MP.IsCuffed(ply) then return end
    MP.ClearEscorter(ply)
    ply:SetNW2Entity("rhylib_escortBy", IsValid(by) and by or NULL)
    if IsValid(by) then by:SetNW2Entity("rhylib_escorting", ply) end
end

-- MP.FreeWait(ply, held, secs, msg): the "left alone" wait for a
-- restrained player. held = someone holds them now (the wait is cleared);
-- otherwise it starts (secs > 0) and at its end MP.Uncuff(ply) and msg in
-- their chat. Keeps NW2Float rhylib_cuffFree in step (only on changes).
-- rhylib_bounty uses it for binders. Server only.
function MP.FreeWait(ply, held, secs, msg)
    if held or not secs or secs <= 0 then
        if ply.rhylibCuffFreeAt then
            ply.rhylibCuffFreeAt = nil
            ply:SetNW2Float("rhylib_cuffFree", 0)
        end
        return
    end
    if not ply.rhylibCuffFreeAt then
        ply.rhylibCuffFreeAt = CurTime() + secs
        ply:SetNW2Float("rhylib_cuffFree", ply.rhylibCuffFreeAt)
    elseif CurTime() >= ply.rhylibCuffFreeAt then
        MP.Uncuff(ply)
        if msg then Rhylib.Notify(ply, msg, "info", "MP") end
    end
end

-- Escorts end when the MP is gone, down, cuffed, or far away; cuffed
-- players nobody holds wait out cuffAutoRelease.
timer.Create("Rhylib.MP.Escort", 0.5, 0, function()
    if next(MP.cuffed) == nil then return end
    local mps   -- (gathered once, only if a prisoner needs it)
    for ply in pairs(MP.cuffed) do
        if not IsValid(ply) or not MP.IsCuffed(ply) then
            MP.cuffed[ply] = nil
        else
            local by = MP.EscortedBy(ply)
            if by and (not by:Alive() or Rhylib.State.IsDown(by) or MP.IsCuffed(by) or by:GetPos():DistToSqr(ply:GetPos()) > 400 * 400) then
                MP.SetEscort(ply, nil)
                by = nil
            end
            if not ply.rhylibBound then
                local held = by ~= nil or MP.IsJailed(ply)
                if not held then
                    if not mps then
                        mps = {}
                        for _, p in ipairs(player.GetAll()) do
                            if p:Alive() and MP.IsMP(p) and not MP.IsCuffed(p) then mps[#mps + 1] = p end
                        end
                    end
                    local r = MP.Cfg("cuffNearRange")
                    local pos = ply:GetPos()
                    for _, p in ipairs(mps) do
                        if p ~= ply and p:GetPos():DistToSqr(pos) < r * r then held = true break end
                    end
                end
                MP.FreeWait(ply, held, MP.Cfg("cuffAutoRelease"), "Nobody came back for you: you slipped the cuffs")
            end
        end
    end
end)

local function clearAll(ply)
    getUp(ply)
    ply.rhylibStunImmune = nil
    if MP.IsCuffed(ply) then MP.Uncuff(ply) end
    -- Anyone this player was escorting walks free of them.
    for p in pairs(MP.cuffed) do
        if IsValid(p) and MP.EscortedBy(p) == ply then MP.SetEscort(p, nil) end
    end
end

Rhylib.Hook.Add("PlayerDeath", "mp.clear", clearAll)
Rhylib.Hook.Add("PlayerSilentDeath", "mp.clear", clearAll)
Rhylib.Hook.Add("PlayerSpawn", "mp.clear", clearAll)
-- Leaving while cuffed doesn't shake the cuffs (until the map changes).
MP.leftCuffed = MP.leftCuffed or {}   -- [SteamID64] = true
Rhylib.Hook.Add("PlayerDisconnected", "mp.clear", function(ply)
    if MP.IsCuffed(ply) and not ply:IsBot() then MP.leftCuffed[ply:SteamID64() or ""] = true end
    clearAll(ply)
    MP.cuffed[ply] = nil
end)
Rhylib.Hook.Add("PlayerSpawn", "mp.recuff", function(ply)
    local id = ply:SteamID64()
    if not id or not MP.leftCuffed[id] then return end
    MP.leftCuffed[id] = nil
    timer.Simple(0.1, function()
        if IsValid(ply) and ply:Alive() and not MP.IsJailed(ply) then MP.Cuff(ply) end
    end)
end, 10)  -- after mp.clear

-- Cuffed or stunned: no job changes, no vehicles, no suicide escape.
Rhylib.Hook.Add("playerCanChangeTeam", "mp.nojob", function(ply)
    if MP.IsCuffed(ply) or MP.IsStunned(ply) then return false, "You can't change job while restrained" end
end)
Rhylib.Hook.Add("CanPlayerEnterVehicle", "mp.novehicle", function(ply)
    if MP.IsCuffed(ply) or MP.IsStunned(ply) then return false end
end)
Rhylib.Hook.Add("CanPlayerSuicide", "mp.nosuicide", function(ply)
    if MP.IsCuffed(ply) or MP.IsStunned(ply) then return false end
end)
Rhylib.Hook.Add("PlayerCanPickupWeapon", "mp.nopickup", function(ply, wep)
    if (MP.IsCuffed(ply) or MP.IsStunned(ply) or MP.IsJailed(ply)) and IsValid(wep) and not wep.IsRhylibStowed and wep:GetClass() ~= STOWED then return false end
end, -50)

-- MPs can search locked lockers with the stun baton in hand.
Rhylib.Hook.Add("Rhylib.CanSearchLocker", "mp.locker", function(ply)
    local w = ply:GetActiveWeapon()
    if MP.IsMP(ply) and IsValid(w) and w:GetClass() == "rhylib_stunbaton" then return true end
end)
