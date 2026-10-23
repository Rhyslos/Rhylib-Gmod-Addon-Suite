--[[
    Bounty hunter skills (server effects). The tree and the shared effects
    (Quick draw, Steady scope, Quiet steps) are in sh_00_config.lua; the
    office and puck read Guild licence, Field kit, Tuned puck, Bring them
    in, Relentless and Finisher (collecting) where they happen.

    Here:
      Stun rounds   stun bolts from a bounty gun stun the target (rhylib_mp
                    MP.Stun), hook Rhylib.StunHit
      Marked man    ×skillMults.marked damage to the target of a contract
                    the shooter carries (wraps rhylib_skills K.DamageMult)
      Dead shot     ×skillMults.deadShot on headshots with bounty guns
      Finisher      a downed (rhylib_medical) player with an open dead /
                    either bounty dies to the hunter's next hit
]]

local B = Rhylib.Bounty

Rhylib.Hook.Add("Rhylib.StunHit", "bounty.stun", function(ply, by, wep)
    if not (IsValid(wep) and wep.BountyWeapon and IsValid(by) and B.Has(by, "bh_stun")) then return end
    local MP = Rhylib.MP
    if MP and MP.Stun then MP.Stun(ply, by) end
end)

-- Wrap the bolt damage multiplier (called from B.WrapSkills once skills loaded).
function B.WrapServerSkills()
    local K = Rhylib.Skills
    if not (K and K.DamageMult) or K.bountyDamageWrapped then return end
    K.bountyDamageWrapped = true
    local old = K.DamageMult
    K.DamageMult = function(ply, bolt, ent, tr, group)
        local m, crit = old(ply, bolt, ent, tr, group)
        if not (IsValid(ply) and ply:IsPlayer()) then return m, crit end
        if IsValid(ent) and K.Has(ply, "bh_marked") then
            local key = B.TargetKey(ent)
            if key and B.ContractTargets(ply)[key] then m = m * B.Mult("marked") end
        end
        local wep = bolt and bolt.weapon
        if group == HITGROUP_HEAD and IsValid(wep) and wep.BountyWeapon and K.Has(ply, "bh_deadshot") then
            m = m * B.Mult("deadShot")
        end
        return m, crit
    end
end
if Rhylib.Skills then B.WrapServerSkills() end

-- Finisher: one hit ends a downed bounty target.
Rhylib.Hook.Add("EntityTakeDamage", "bounty.finisher", function(ent, dmg)
    if not (IsValid(ent) and ent:IsPlayer() and ent.rhylibDown) then return end
    local by = dmg:GetAttacker()
    if not (IsValid(by) and by:IsPlayer() and B.Has(by, "bh_finisher")) then return end
    local key = "p" .. (ent:SteamID64() or "")
    for _, b in pairs(B.list) do
        if b.tkey == key and b.mode ~= "alive" then
            dmg:SetDamage(math.max(dmg:GetDamage(), 100000))
            return
        end
    end
end, 140)   -- (before medical's downed handling at 150)
