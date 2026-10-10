--[[
    Damage feedback (server): every hit a player takes is sent to them
    (batched, flushed once a tick) with where it came from, so their HUD
    can show a direction marker, a flash and play a hit sound.

      hud.dmg   (server -> the player hit, Rhylib.Net batch, one item per hit)
                amount 8 bits (health lost, rounded up, capped at 255),
                armour 8 bits (armour lost, same), flags 4 bits (SIM 1,
                BLAST 2, NODIR 4, HEAD 8), then the source position as a
                vector unless NODIR is set

    Real damage: what armour took is read from rhylib_weapons' record of
    the hit (Rhylib.Armor.pending) at PostEntityTakeDamage -1001, just
    before armour puts it away at -1000.
    Sim hits (rhylib_training) call HUD.SendHit themselves.
]]

local HUD = Rhylib.HUD

-- Flag bits for HUD.SendHit and the hud.dmg message (cl_70_damage.lua
-- has its own copy of these numbers):
--   SIM    a training (sim) hit: yellow marker, beep, no flash or shake
--   BLAST  explosion damage: stronger shake, ear ringing on big ones
--   NODIR  no source position (falls); set by SendHit when from is nil
--   HEAD   a real head hit: cracks the visor
HUD.DMG_SIM, HUD.DMG_BLAST, HUD.DMG_NODIR, HUD.DMG_HEAD = 1, 2, 4, 8

local batch = Rhylib.Net.CreateBatch("hud.dmg", function(h)
    net.WriteUInt(math.Clamp(math.ceil(h.amount), 0, 255), 8)
    net.WriteUInt(math.Clamp(math.ceil(h.armour), 0, 255), 8)
    net.WriteUInt(h.flags, 4)
    if bit.band(h.flags, HUD.DMG_NODIR) == 0 then net.WriteVector(h.from) end
end)

-- HUD.SendHit(ply, amount, armour, from, flags): tells a player's HUD
-- they were hit (direction marker, flash, sound). Server only.
--   amount  health lost, armour  armour lost (hits under 0.5 of both are skipped)
--   from    world position the hit came from (nil = no direction, e.g. a fall)
--   flags   HUD.DMG_* bits, optional
-- Bots get nothing. Real damage is sent by this file's own hook; call it
-- yourself only for damage the engine never sees (rhylib_training does
-- this for sim hits). Returns nothing.
-- Example: Rhylib.HUD.SendHit(ply, 20, 0, attacker:WorldSpaceCenter(), Rhylib.HUD.DMG_SIM)
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
    -- (bolts set rhylibHitGroup for the length of the hit)
    if (ent.rhylibHitGroup or ent:LastHitGroup()) == HITGROUP_HEAD and bit.band(dmg:GetDamageType(), DMG_BULLET) ~= 0 then
        flags = bit.bor(flags, HUD.DMG_HEAD)
    end
    local from = (bit.band(dmg:GetDamageType(), DMG_FALL) == 0) and source(dmg, ent) or nil
    HUD.SendHit(ent, dmg:GetDamage(), armour, from, flags)
end, 0)   -- (after armour's -1000 put the armour back)

Rhylib.Hook.Add("PlayerDisconnected", "hud.dmg", function(ply) cost[ply] = nil end)
