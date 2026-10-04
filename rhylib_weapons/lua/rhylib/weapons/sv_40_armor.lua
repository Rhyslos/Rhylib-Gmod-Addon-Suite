--[[
    Armour damage maths.

    The engine has its own armour (it blocks 80% and drains armour). To
    replace it, we set the armour aside for the length of one hit:
      EntityTakeDamage      scale the damage by our mitigation, work out
                            the armour left, set armour to 0 so the
                            engine skips its own maths
      PostEntityTakeDamage  put armour back: the new value if the hit
                            landed, the old one if it was blocked
                            (god mode, no friendly fire, ...)
    Both happen inside the same tick, so the engine only ever networks
    the final value. A timer(0) puts armour back if a hit never reaches
    PostEntityTakeDamage (another addon blocked it).

    A hit inside a hit (damage from a death or hurt hook) stacks on the
    same entry, using the armour left by the outer hit. While armour is
    set aside, read it with Rhylib.Armor.Get(ply), not ply:Armor().

    Mitigation runs late (priority 100) so other Rhylib damage changes
    come first; the restore runs first (priority -1000).
]]

local A = Rhylib.Armor
local Config = Rhylib.Config

A.pending = A.pending or {}   -- [ply] = { before, after, costs = { per open hit } }
local pending = A.pending
local flushQueued = false

-- Armour now, counting a hit that is still being worked out.
function A.Get(ply)
    local p = pending[ply]
    if p then return p.after end
    return ply:Armor()
end

local function finish(ply, p)
    pending[ply] = nil
    if not IsValid(ply) then return end
    -- Keep any value another addon set during the hit.
    if ply:Armor() ~= 0 then return end
    if ply:Alive() then ply:SetArmor(p.after) end
end

-- Hits that never reached PostEntityTakeDamage count as blocked.
local function flush()
    flushQueued = false
    for ply, p in pairs(pending) do
        for i = 1, #p.costs do p.after = p.after + p.costs[i] end
        p.after = math.min(p.after, p.before)
        finish(ply, p)
    end
end

local function cfgNum(key, fallback)
    return tonumber(Config.Get("armor", key)) or fallback
end

Rhylib.Hook.Add("EntityTakeDamage", "armor.mitigate", function(ent, dmg)
    if not ent:IsPlayer() then return end
    if ent.rhylibDown and not pending[ent] then return end  -- downed (rhylib_medical): no armour

    local p = pending[ent]
    local armor = p and p.after or ent:Armor()
    local cost = 0

    local amount = dmg:GetDamage()
    if armor > 0 and amount > 0 and bit.band(dmg:GetDamageType(), cfgNum("bypass", 0)) == 0 then
        -- (hook Rhylib.ArmorDrainMult(ply): rhylib_gear's pauldron)
        local dm = tonumber(hook.Run("Rhylib.ArmorDrainMult", ent)) or 1
        cost = math.min(armor, math.ceil(amount * math.max(0, cfgNum("drain", 1)) * dm))
        dmg:ScaleDamage(1 - A.Mitigation(armor, ent:GetMaxArmor()))
    elseif not p then
        return  -- nothing to do and nothing open
    end

    if not p then
        p = { before = armor, after = armor, costs = {} }
        pending[ent] = p
        ent:SetArmor(0)
        if not flushQueued then
            flushQueued = true
            timer.Simple(0, flush)
        end
    end
    p.after = p.after - cost
    p.costs[#p.costs + 1] = cost
end, 100)

Rhylib.Hook.Add("PostEntityTakeDamage", "armor.restore", function(ent, dmg, took)
    local p = pending[ent]
    if not p then return end
    local cost = table.remove(p.costs) or 0
    if not took then p.after = p.after + cost end
    if #p.costs == 0 then finish(ent, p) end
end, -1000)

Rhylib.Hook.Add("PlayerDisconnected", "armor.cleanup", function(ply)
    pending[ply] = nil
end)

-- Spawn armour: the job's armor field, else the config value. Set a tick
-- late so the gamemode's own spawn code can't reset it.
function A.SpawnArmor(ply)
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    local n = job and tonumber(job.armor) or cfgNum("spawnArmor", 100)
    return math.max(0, math.floor(n))
end

Rhylib.Hook.Add("PlayerSpawn", "armor.spawn", function(ply)
    timer.Simple(0, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        local n = A.SpawnArmor(ply)
        if ply.SetMaxArmor then ply:SetMaxArmor(math.max(100, n)) end
        ply:SetArmor(n)
    end)
end)
