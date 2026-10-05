--[[
    Explosion knockdowns: a blast of knockMin damage or more (before
    armour) throws the player down for a random knockTimeMin-knockTimeMax
    seconds (rhylib_core Lying.Knock, soft: a client ragdoll, no damage
    meanwhile), away from the blast. With knockDropChance they lose the
    gun in their hands: it lands on the ground as an item (not job gear).
]]

local Config = Rhylib.Config
local function cfg(k) return Config.Get("weapons", k) end

local pending = {}   -- [ply] = { amount, force, pos } from this hit

Rhylib.Hook.Add("EntityTakeDamage", "weapons.knock", function(ent, dmg)
    if not ent:IsPlayer() or bit.band(dmg:GetDamageType(), DMG_BLAST) == 0 then return end
    if dmg:GetDamage() < cfg("knockMin") then return end
    pending[ent] = { amount = dmg:GetDamage(), force = dmg:GetDamageForce(), pos = dmg:GetDamagePosition() }
end, 90)   -- (before armour at 100 changes the amount)

local function dropGun(ply)
    local Inv = Rhylib.Inventory
    local wep = ply:GetActiveWeapon()
    if not (Inv and Inv.Get and Inv.Drop and IsValid(wep) and wep.IsRhylib and wep.Mags) then return end   -- (guns only)
    local st = Inv.Get(ply)
    local class = wep:GetClass()
    for uid, inst in pairs(st.byUid or {}) do
        if inst.id == class then
            if inst.data and inst.data.loadout then return end   -- (job gear would just vanish)
            Inv.Drop(ply, uid, true)
            return
        end
    end
end

Rhylib.Hook.Add("PostEntityTakeDamage", "weapons.knock", function(ent, dmg, took)
    local p = pending[ent]
    if not p then return end
    pending[ent] = nil
    if cfg("knockTimeMax") <= 0 then return end   -- (0 = knockdowns off)
    if not took or not ent:Alive() or ent.rhylibDown or ent.rhylibGoingDown then return end   -- (going down: medical's body)
    if hook.Run("Rhylib.CanKnockDown", ent) == false then return end   -- (rhylib_skills: Press forward)
    local L = Rhylib.Lying
    if not (L and L.Knock) or L.Knocked(ent) or L.Ragdoll(ent) then return end
    -- Thrown away from the blast, harder for bigger hits.
    local dir = p.force:LengthSqr() > 1 and p.force:GetNormalized() or (ent:WorldSpaceCenter() - p.pos):GetNormalized()
    dir.z = math.max(dir.z, 0.35)
    dir:Normalize()
    local push = dir * cfg("knockPush") * math.Clamp(p.amount / cfg("knockMin"), 1, 2.5)
    -- The gun goes before the body does (the dropped item spawns at the eyes).
    local drop = math.random() < cfg("knockDropChance")
    if drop then dropGun(ent) end
    local lo = math.max(cfg("knockTimeMin"), 0.5)
    local secs = math.Rand(lo, math.max(cfg("knockTimeMax"), lo))
    if L.Knock(ent, secs, push, true) and drop then
        ent:ChatPrint("You dropped your weapon")
    end
end, -500)

Rhylib.Hook.Add("PlayerDisconnected", "weapons.knock", function(ply) pending[ply] = nil end)
