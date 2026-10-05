--[[
    Riot shields (weapons with SWEP.RiotShield, e.g. rhylib_riotshield).

    W.ShieldUp(ply)            holding a shield, not lowered
    W.ShieldFaces(ply, dir)    the shield faces something coming along dir
                               (within ShieldArc of straight on)
    W.ShieldBlocks(ply, dir)   a bolt along dir is stopped: by ply's own
                               shield, or (rhylib_skills Phalanx) by a
                               shield held by someone just in front of ply
    W.ShieldNear(ply, pos)     ply's shield faces a point (breaching
                               charge blasts are blocked by it)
    Bolts call ShieldBlocks once per hit on a player; it only scans the
    other players when the target's own shield didn't stop it.
]]

local W = Rhylib.Weapons
local Config = Rhylib.Config

Config.Register("weapons", "shieldArc", 60, "Riot shield: blocks bolts within this many degrees of straight ahead")
Config.Register("weapons", "phalanxRange", 140, "Phalanx: covers teammates up to this far behind the shield (units)")
Config.Register("weapons", "phalanxWidth", 40, "Phalanx: how far to the side of the shield's line a teammate is covered (units)")

function W.ShieldUp(ply)
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w.RiotShield) then return false end
    return not (w.IsLowered and w:IsLowered())
end

local function flat(v)
    local f = Vector(v.x, v.y, 0)
    f:Normalize()
    return f
end

function W.ShieldFaces(ply, dir)
    local fwd = flat(ply:GetAimVector())
    local d = flat(dir)
    return fwd:Dot(d) <= -math.cos(math.rad(Config.Get("weapons", "shieldArc")))
end

function W.ShieldNear(ply, pos)
    if not W.ShieldUp(ply) then return false end
    return W.ShieldFaces(ply, ply:WorldSpaceCenter() - pos)
end

-- Phalanx holders, rebuilt at most every 0.5 s (or when skills change),
-- so a hit doesn't check every player's skills.
local holders, holdersAt = {}, -1
local function phalanxHolders()
    local now = CurTime()
    if now < holdersAt then return holders end
    holdersAt = now + 0.5
    for i = #holders, 1, -1 do holders[i] = nil end
    local K = Rhylib.Skills
    if not (K and K.Has) then return holders end
    for _, s in ipairs(player.GetAll()) do
        if K.Has(s, "phalanx") then holders[#holders + 1] = s end
    end
    return holders
end
Rhylib.Hook.Add("Rhylib.SkillsChanged", "weapons.phalanx", function() holdersAt = -1 end)

function W.ShieldBlocks(ply, dir)
    if W.ShieldUp(ply) and W.ShieldFaces(ply, dir) then return true end
    -- Phalanx: a shield in front of ply, facing the shot, on the bolt's line.
    local list = phalanxHolders()
    if #list == 0 then return false end
    local range, width = Config.Get("weapons", "phalanxRange"), Config.Get("weapons", "phalanxWidth")
    local pos = ply:WorldSpaceCenter()
    local d = flat(dir)
    for i = 1, #list do
        local s = list[i]
        if s ~= ply and IsValid(s) and s:Alive() and W.ShieldUp(s) and W.ShieldFaces(s, dir) then
            local rel = pos - s:WorldSpaceCenter()
            rel.z = 0
            local along = rel:Dot(d)              -- ply further along the bolt = behind the shield
            if along > 0 and along <= range and (rel - d * along):Length() <= width then return true end
        end
    end
    return false
end

-- A breaching charge's blast stops on a raised shield facing it (other
-- grenades still hurt).
if SERVER then
    Rhylib.Hook.Add("EntityTakeDamage", "weapons.shieldblast", function(ent, dmg)
        if not ent:IsPlayer() or bit.band(dmg:GetDamageType(), DMG_BLAST) == 0 then return end
        local inf = dmg:GetInflictor()
        if not (IsValid(inf) and inf:GetClass() == "rhylib_grenade" and inf.GetKind and inf:GetKind() == inf.KIND_BREACH) then return end
        if W.ShieldNear(ent, inf:GetPos()) then return true end
    end, -100)
end
