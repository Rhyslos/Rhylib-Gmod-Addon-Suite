--[[
    Riot shields (weapons with SWEP.RiotShield, e.g. rhylib_riotshield).

    W.ShieldUp(ply)            holding a shield, not lowered
    W.ShieldProficient(ply)    ... and it's the CG shield (Shock Trooper
                               bonuses: Hold the line, Phalanx)
    W.ShieldFaces(ply, dir)    the shield covers something coming along dir:
                               aiming = the shield is flat in front (within
                               shieldArc of straight ahead); not aiming = it
                               hangs on the left, turned out, and only covers
                               a wedge there (shieldSideCenter ± half of
                               shieldSideArc, degrees left of the aim); front,
                               right and back are open
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
Config.Register("weapons", "shieldSideCenter", 55, "Riot shield not aimed: middle of the covered wedge, degrees to the left of where you look")
Config.Register("weapons", "shieldSideArc", 30, "Riot shield not aimed: width of the covered wedge on the left (degrees)")
-- CG riot shield (SWEP.ShieldProficiency, owner 2026-10-09: "it needs to be better").
Config.Register("weapons", "cgShieldArc", 75, "CG riot shield aimed: blocks bolts within this many degrees of straight ahead")
Config.Register("weapons", "cgShieldSideArc", 50, "CG riot shield not aimed: width of the covered wedge on the left (degrees)")
Config.Register("weapons", "cgShieldBlast", 0.5, "CG riot shield aimed at an explosion: damage multiplier (breaching charges are stopped by either shield)")
Config.Register("weapons", "phalanxRange", 140, "Phalanx: covers teammates up to this far behind the shield (units)")
Config.Register("weapons", "phalanxWidth", 40, "Phalanx: how far to the side of the shield's line a teammate is covered (units)")

function W.ShieldUp(ply)
    local w = IsValid(ply) and ply:GetActiveWeapon()
    if not (IsValid(w) and w.RiotShield) then return false end
    return not (w.IsLowered and w:IsLowered())
end

-- A raised shield the Shock Trooper bonuses count for (the CG shield,
-- SWEP.ShieldProficiency; not the Republic shield anyone carries).
function W.ShieldProficient(ply)
    if not W.ShieldUp(ply) then return false end
    local w = ply:GetActiveWeapon()
    return w.ShieldProficiency == true
end

local function flat(v)
    local f = Vector(v.x, v.y, 0)
    f:Normalize()
    return f
end

-- Shield held in front (right mouse) rather than on the left side.
function W.ShieldAimed(ply)
    local w = IsValid(ply) and ply:GetActiveWeapon()
    return IsValid(w) and w.RiotShield and w.GetAiming and w:GetAiming() or false
end

function W.ShieldFaces(ply, dir)
    local fwd = flat(ply:GetAimVector())
    local from = -flat(dir)   -- (where the bolt comes from)
    local left = Vector(-fwd.y, fwd.x, 0)
    local a = math.deg(math.atan2(from:Dot(left), from:Dot(fwd)))   -- (+ = to the left)
    local w = ply:GetActiveWeapon()
    local cg = IsValid(w) and w.ShieldProficiency == true
    if W.ShieldAimed(ply) then
        return math.abs(a) <= Config.Get("weapons", cg and "cgShieldArc" or "shieldArc")
    end
    return math.abs(a - Config.Get("weapons", "shieldSideCenter")) <= Config.Get("weapons", cg and "cgShieldSideArc" or "shieldSideArc") * 0.5
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
    -- Phalanx: a shield held in front (aimed) ahead of ply, facing the shot,
    -- on the bolt's line.
    local list = phalanxHolders()
    if #list == 0 then return false end
    local range, width = Config.Get("weapons", "phalanxRange"), Config.Get("weapons", "phalanxWidth")
    local pos = ply:WorldSpaceCenter()
    local d = flat(dir)
    for i = 1, #list do
        local s = list[i]
        if s ~= ply and IsValid(s) and s:Alive() and W.ShieldProficient(s) and W.ShieldAimed(s) and W.ShieldFaces(s, dir) then
            local rel = pos - s:WorldSpaceCenter()
            rel.z = 0
            local along = rel:Dot(d)              -- ply further along the bolt = behind the shield
            if along > 0 and along <= range and (rel - d * along):Length() <= width then return true end
        end
    end
    return false
end

-- A breaching charge's blast stops on a raised shield facing it; the CG
-- shield held in front also softens every other blast (cgShieldBlast).
if SERVER then
    Rhylib.Hook.Add("EntityTakeDamage", "weapons.shieldblast", function(ent, dmg)
        if not ent:IsPlayer() or bit.band(dmg:GetDamageType(), DMG_BLAST) == 0 then return end
        local inf = dmg:GetInflictor()
        if IsValid(inf) and inf:GetClass() == "rhylib_grenade" and inf.GetKind and inf:GetKind() == inf.KIND_BREACH then
            if W.ShieldNear(ent, inf:GetPos()) then return true end
            return
        end
        -- (CG shield held in front of any other blast: cgShieldBlast of the damage)
        local from = IsValid(inf) and inf:GetPos() or dmg:GetDamagePosition()
        if W.ShieldProficient(ent) and W.ShieldAimed(ent) and W.ShieldNear(ent, from) then
            dmg:ScaleDamage(Config.Get("weapons", "cgShieldBlast"))
        end
    end, -100)
end
