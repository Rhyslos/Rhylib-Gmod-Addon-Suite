--[[
    Stun, cuffs and escort (server).
]]

local MP = Rhylib.MP
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
    ply:SetNW2Float("rhylib_stunEnd", 0)
    local vo = ply.rhylibStunView
    if vo then
        ply:SetViewOffset(vo[1])
        ply:SetViewOffsetDucked(vo[2])
        ply.rhylibStunView = nil
    end
    ply.rhylibStunImmune = CurTime() + MP.Cfg("stunImmune")
    if Rhylib.Lying and not ply.rhylibDown then Rhylib.Lying.End(ply) end
end

-- Ends a stun now (rhylib_admin !free).
function MP.EndStun(ply)
    if IsValid(ply) and MP.IsStunned(ply) then getUp(ply) end
end

-- Collapse for stunTime seconds. by: who stunned them (for logs/hooks).
function MP.Stun(ply, by)
    if not IsValid(ply) or not ply:Alive() then return end
    if ply.rhylibDown then return end                         -- already downed (rhylib_medical)
    local L = Rhylib.Lying
    if L and L.Knocked and L.Knocked(ply) then return end     -- knocked down / out of a simulation (rhylib_core)
    if MP.IsStunned(ply) then return end                      -- no chain stuns
    if (ply.rhylibStunImmune or 0) > CurTime() then return end
    if hook.Run("Rhylib.CanStun", ply, by) == false then return end
    local t = MP.Cfg("stunTime")
    if ply:InVehicle() then ply:ExitVehicle() end
    ply:SetNW2Float("rhylib_stunYaw", ply:EyeAngles().y)
    ply:SetNW2Float("rhylib_stunEnd", CurTime() + t)
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
    ply:SetNW2Float("rhylib_stunEnd", 0)
end)

--------------------------------------------------------------------------
-- Cuffs
--------------------------------------------------------------------------

function MP.Cuff(ply, by)
    if not IsValid(ply) or MP.IsCuffed(ply) then return end
    ply:SetNW2Bool("rhylib_cuffed", true)
    MP.ClearEscorter(ply)
    ply:SetNW2Entity("rhylib_escortBy", NULL)
    MP.cuffed[ply] = true
    stow(ply)
    ply:EmitSound("npc/metropolice/gear" .. math.random(1, 6) .. ".wav", 65)
    hook.Run("Rhylib.PlayerCuffed", ply, by)
end

function MP.Uncuff(ply, by)
    if not IsValid(ply) then return end
    ply:SetNW2Bool("rhylib_cuffed", false)
    MP.ClearEscorter(ply)
    ply:SetNW2Entity("rhylib_escortBy", NULL)
    MP.cuffed[ply] = nil
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

function MP.SetEscort(ply, by)
    if not MP.IsCuffed(ply) then return end
    MP.ClearEscorter(ply)
    ply:SetNW2Entity("rhylib_escortBy", IsValid(by) and by or NULL)
    if IsValid(by) then by:SetNW2Entity("rhylib_escorting", ply) end
end

-- Escorts end when the MP is gone, down, cuffed, or far away.
timer.Create("Rhylib.MP.Escort", 0.5, 0, function()
    if next(MP.cuffed) == nil then return end
    for ply in pairs(MP.cuffed) do
        if not IsValid(ply) or not MP.IsCuffed(ply) then
            MP.cuffed[ply] = nil
        else
            local by = MP.EscortedBy(ply)
            if by and (not by:Alive() or by.rhylibDown or MP.IsCuffed(by) or by:GetPos():DistToSqr(ply:GetPos()) > 400 * 400) then
                MP.SetEscort(ply, nil)
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
