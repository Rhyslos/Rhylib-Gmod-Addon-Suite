--[[
    Binders (rhylib_bounty): a bounty hunter's restraints. They work like
    rhylib_mp's handcuffs (it is their base, so rhylib_mp is needed):
      LMB  bind a downed or stunned target who has an open "alive" or
           "dead or alive" bounty (hold it; Quick binders: half the time)
      RMB  free someone you (or another hunter) bound
      R    escort them (again: let go)
    Bring them to a Bounty Office and Turn in to claim the bounty.
    Players bound with binders are marked ply.rhylibBound (server) and
    NW2Bool rhylib_bound, so the binders can't free or move people the MPs
    cuffed and MPs can't free or move a hunter's prisoner.
    A bound prisoner goes free (uncuffed, with a chat line) when:
      - every bounty on them has closed (claimed, cancelled, expired);
      - the hunter who bound them dies or leaves;
      - nobody holds them for bounty bindAutoRelease seconds (not escorted,
        no bounty hunter within bindNearRange; rhylib_mp MP.FreeWait, so the
        HUD shows the same "Free in m:ss" countdown).
]]

AddCSLuaFile()

SWEP.Base = "rhylib_handcuffs"
SWEP.PrintName = "Binders"
SWEP.Category = "Rhy's Bounty hunters"
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Instructions = "LMB: bind   RMB: free   R: escort"
SWEP.Hint = "Hold LMB bind  ·  RMB free  ·  R escort"   -- (rhylib_handcuffs DrawHUD)

function SWEP:MayUse(ply, target, action)
    local B = Rhylib.Bounty
    if not (B and IsValid(target)) then return false end
    if action == "cuff" then
        if not B.MayHunt(ply) then
            Rhylib.Notify(ply, "Only bounty hunters use binders", "bad", "Bounty")
            return false
        end
        local key = B.PlayerKey and B.PlayerKey(target) or ("p" .. (target:SteamID64() or ""))
        for _, b in pairs(B.list or {}) do
            if b.tkey == key and b.mode ~= "dead" then return true end
        end
        Rhylib.Notify(ply, "Binders only hold someone with a bounty that wants them alive", "bad", "Bounty")
        return false
    end
    -- Freeing / escorting: only hunters, and only someone bound with binders.
    return target.rhylibBound ~= nil and B.MayHunt(ply)
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
        if IsValid(w) and w:GetClass() == "rhylib_binders" then
            ply.rhylibBound = by
            ply:SetNW2Bool("rhylib_bound", true)   -- (clients: MP wheel, HUD)
        end
    end)
    Rhylib.Hook.Add("Rhylib.PlayerUncuffed", "bounty.binders", function(ply)
        ply.rhylibBound = nil
        ply:SetNW2Bool("rhylib_bound", false)
    end)
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
            ply:SetNW2Bool("rhylib_bound", true)
        end
    end)

    -- Letting a bound prisoner go (no bounty left, hunter gone, left alone).
    local function free(p, msg)
        local MP = Rhylib.MP
        if not (IsValid(p) and p.rhylibBound and MP and MP.Uncuff) then return end
        MP.Uncuff(p)
        if msg then Rhylib.Notify(p, msg, "info", "Bounty") end
    end

    -- Every bounty on them closed (a claim turns them in and frees them itself).
    Rhylib.Hook.Add("Rhylib.BountyClosed", "bounty.binders.free", function(b, why)
        local B = Rhylib.Bounty
        if why == "claimed" or not (B and B.TargetPlayer and b.kind == "player") then return end
        local p = B.TargetPlayer(b)
        if p and p.rhylibBound and #B.OnTarget(b.tkey) == 0 then free(p, "There's no bounty on you any more: you're free") end
    end)

    -- The hunter who bound them died or left.
    local function hunterGone(h)
        local MP = Rhylib.MP
        for p in pairs(MP and MP.cuffed or {}) do
            if IsValid(p) and p.rhylibBound == h then free(p, "The hunter who bound you is gone: you got loose") end
        end
    end
    Rhylib.Hook.Add("PlayerDeath", "bounty.binders.free", hunterGone)
    Rhylib.Hook.Add("PlayerDisconnected", "bounty.binders.free", hunterGone)

    -- Left alone: the bindAutoRelease wait (rhylib_mp's escort timer skips
    -- rhylibBound prisoners).
    timer.Create("Rhylib.Bounty.BindWait", 1, 0, function()
        local MP, B = Rhylib.MP, Rhylib.Bounty
        if not (MP and MP.cuffed and MP.FreeWait and B) or next(MP.cuffed) == nil then return end
        local hunters
        for p in pairs(MP.cuffed) do
            if IsValid(p) and p.rhylibBound and MP.IsCuffed(p) then
                local held = MP.EscortedBy(p) ~= nil or MP.IsJailed(p)
                if not held then
                    if not hunters then
                        hunters = {}
                        for _, h in ipairs(player.GetAll()) do
                            if h:Alive() and not MP.IsCuffed(h) and B.MayHunt(h) then hunters[#hunters + 1] = h end
                        end
                    end
                    local r = tonumber(B.Cfg("bindNearRange")) or 1500
                    local pos = p:GetPos()
                    for _, h in ipairs(hunters) do
                        if h ~= p and h:GetPos():DistToSqr(pos) < r * r then held = true break end
                    end
                end
                MP.FreeWait(p, held, tonumber(B.Cfg("bindAutoRelease")) or 600, "[Bounty] Nobody came back for you: you worked the binders loose")
            end
        end
    end)
end
