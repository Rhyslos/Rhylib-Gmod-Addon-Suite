--[[
    Damage feedback (server): every hit a player takes is sent to them
    (batched, flushed once a tick) with where it came from, so their HUD
    can show a direction marker, a flash and play a hit sound.

      hud.dmg   amount 8 bits (health lost), armour 8 bits (armour lost),
                flags 3 bits (SIM, BLAST, NODIR), source position (when
                there's a direction)

    Real damage: what armour took is read from rhylib_weapons' record of
    the hit (Rhylib.Armor.pending) at PostEntityTakeDamage -1001, just
    before armour puts it away at -1000.
    Sim hits (rhylib_training) call HUD.SendHit themselves.
]]

local HUD = Rhylib.HUD

HUD.DMG_SIM, HUD.DMG_BLAST, HUD.DMG_NODIR = 1, 2, 4

local batch = Rhylib.Net.CreateBatch("hud.dmg", function(h)
    net.WriteUInt(math.Clamp(math.ceil(h.amount), 0, 255), 8)
    net.WriteUInt(math.Clamp(math.ceil(h.armour), 0, 255), 8)
    net.WriteUInt(h.flags, 3)
    if bit.band(h.flags, HUD.DMG_NODIR) == 0 then net.WriteVector(h.from) end
end)

-- from: where the hit came from (nil = no direction, e.g. a fall).
function HUD.SendHit(ply, amount, armour, from, flags)
    if not (IsValid(ply) and ply:IsPlayer()) or ply:IsBot() then return end
    if amount < 0.5 and armour < 0.5 then return end
    flags = flags or 0
    if not from then flags = bit.bor(flags, HUD.DMG_NODIR) end
    batch:Send(ply, { amount = amount, armour = armour, flags = flags, from = from })
end

-- Where a hit came from: the thing that exploded, else the attacker.
local function source(dmg, ply)
    local inf, att = dmg:GetInflictor(), dmg:GetAttacker()
    if IsValid(inf) and inf ~= att and not inf:IsWeapon() and inf ~= ply then return inf:WorldSpaceCenter() end
    if IsValid(att) and att ~= ply and not att:IsWorld() then return att:WorldSpaceCenter() end
    if bit.band(dmg:GetDamageType(), DMG_BLAST) ~= 0 then return dmg:GetDamagePosition() end
    return nil
end

-- What armour took from this hit: read from rhylib_weapons' own record
-- (Armor.pending costs, one per open hit) just before it's put away at
-- -1000, then sent at 0. Nested hits and killing hits come out right.
local cost = {}   -- [ply] = armour this hit cost

Rhylib.Hook.Add("PostEntityTakeDamage", "hud.dmg.armour", function(ent)
    if not ent:IsPlayer() then return end
    local A = Rhylib.Armor
    local p = A and A.pending and A.pending[ent]
    cost[ent] = p and p.costs[#p.costs] or 0
end, -1001)

Rhylib.Hook.Add("PostEntityTakeDamage", "hud.dmg", function(ent, dmg, took)
    if not ent:IsPlayer() then return end
    local armour = cost[ent] or 0
    cost[ent] = nil
    if not took then return end
    local flags = bit.band(dmg:GetDamageType(), DMG_BLAST) ~= 0 and HUD.DMG_BLAST or 0
    local from = (bit.band(dmg:GetDamageType(), DMG_FALL) == 0) and source(dmg, ent) or nil
    HUD.SendHit(ent, dmg:GetDamage(), armour, from, flags)
end, 0)   -- (after armour's -1000 put the armour back)

Rhylib.Hook.Add("PlayerDisconnected", "hud.dmg", function(ply) cost[ply] = nil end)
