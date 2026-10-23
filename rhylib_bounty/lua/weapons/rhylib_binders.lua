--[[
    Binders (rhylib_bounty): a bounty hunter's restraints. They work like
    rhylib_mp's handcuffs (it is their base, so rhylib_mp is needed):
      LMB  bind a downed or stunned target who has an open "alive" or
           "dead or alive" bounty (hold it; Quick binders: half the time)
      RMB  free someone you (or another hunter) bound
      R    escort them (again: let go)
    Bring them to a Bounty Office and Turn in to claim the bounty.
    Players bound with binders are marked ply.rhylibBound (server) so the
    binders can't free or move people the MPs cuffed.
]]

AddCSLuaFile()

SWEP.Base = "rhylib_handcuffs"
SWEP.PrintName = "Binders"
SWEP.Category = "Rhy's Bounty hunters"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Instructions = "LMB: bind   RMB: free   R: escort"

function SWEP:MayUse(ply, target, action)
    local B = Rhylib.Bounty
    if not (B and IsValid(target)) then return false end
    if action == "cuff" then
        if not B.MayHunt(ply) then
            ply:ChatPrint("Only bounty hunters use binders")
            return false
        end
        local key = "p" .. (target:SteamID64() or "")
        for _, b in pairs(B.list or {}) do
            if b.tkey == key and b.mode ~= "dead" then return true end
        end
        ply:ChatPrint("Binders only hold someone with a bounty that wants them alive")
        return false
    end
    return target.rhylibBound ~= nil
end

function SWEP:CuffTime()
    local B = Rhylib.Bounty
    local t = Rhylib.MP.Cfg("cuffTime")
    if B and B.Has(self:GetOwner(), "bh_binders") then t = t * B.Mult("binders") end
    return t
end

if SERVER then
    -- Mark players bound with binders (and forget it when they're freed).
    Rhylib.Hook.Add("Rhylib.PlayerCuffed", "bounty.binders", function(ply, by)
        local w = IsValid(by) and by.GetActiveWeapon and by:GetActiveWeapon()
        if IsValid(w) and w:GetClass() == "rhylib_binders" then ply.rhylibBound = by end
    end)
    Rhylib.Hook.Add("Rhylib.PlayerUncuffed", "bounty.binders", function(ply) ply.rhylibBound = nil end)
    -- Leaving bound and coming back (rhylib_mp cuffs them again with no
    -- "by"): still bound by a hunter.
    local leftBound = {}
    Rhylib.Hook.Add("PlayerDisconnected", "bounty.binders", function(ply)
        if ply.rhylibBound then leftBound[ply:SteamID64() or ""] = true end
    end)
    Rhylib.Hook.Add("Rhylib.PlayerCuffed", "bounty.binders.rejoin", function(ply, by)
        local id = ply:SteamID64() or ""
        if leftBound[id] then
            leftBound[id] = nil
            if not ply.rhylibBound then ply.rhylibBound = true end
        end
    end)
end
