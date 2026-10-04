--[[
    Skills on the server: saving, learning, resetting, and the effects
    that only the server works out (damage, Momentum, the cell rack).

    Data "skills" key "s"..SteamID64 = { n = { ids } }.
    Nets: skills.learn (node index, 8 bits), skills.reset.
    K.SetSkills(ply, set) applies a set (NW2String, save, inventory grids).
    K.DamageMult(ply, bolt, ent, tr, group) for rhylib_weapons (Point blank,
    Headhunter, Shotgun drills, crits);
    returns mult, crit.
    K.ExtraGrids(ply) for rhylib_inventory: { [cid] = { w, h } } the
    player's skills open (Load bearer: the cell rack; Ammo belt).
    On a change: items the player may no longer carry are dropped
    (droid poppers without Droid popper), Spring legs jump power,
    Reinforced max health.
    Damage taken (EntityTakeDamage 95, before armour): Hard landings,
    Blast hardened, Aerial stability, Combat drop, Juggernaut, Under fire.
    Death from above: OnPlayerHitGround.
]]

local K = Rhylib.Skills
local Data = Rhylib.Data

Rhylib.Net.Register("skills.note")

local function key(ply) return "s" .. (ply:SteamID64() or "0") end

-- Renamed skills (old saves keep working).
local RENAMED = { burst_fire = "rapid_fire", thruster_dodge = "combat_drop" }

local function setString(set)
    local ids = {}
    for _, n in ipairs(K.NODES) do
        if set[n.id] then ids[#ids + 1] = n.id end
    end
    return #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or ""
end

-- Saved set, read on demand (the inventory may ask before PlayerInitialSpawn).
function K.Stored(ply)
    if ply.rhylibSkillsLoaded then return ply.rhylibSkills end
    local set = {}
    if not ply:IsBot() then
        local d = Data.Get("skills", key(ply))
        if istable(d) and istable(d.n) then
            for _, id in ipairs(d.n) do
                id = RENAMED[id] or id
                if K.byId[id] then set[id] = true end
            end
        end
    end
    ply.rhylibSkills = set
    ply.rhylibSkillsLoaded = true
    return set
end

function K.Note(ply, text, bad)
    Rhylib.Net.Start("skills.note")
    net.WriteBool(bad and true or false)
    net.WriteString(text)
    net.Send(ply)
end

-- Grids an inventory gets from skills.
function K.ExtraGrids(ply)
    local out = {}
    local Items = Rhylib.Items
    if Items and Items.RACK and K.Stored(ply).load_bearer then
        local r = K.Cfg("cellRack") or { 5, 2 }
        out[Items.RACK] = { r[1], r[2] }
    end
    if Items and Items.BELT and K.Stored(ply).ammo_belt then
        local b = K.Cfg("ammoBelt") or { 5, 1 }
        out[Items.BELT] = { b[1], b[2] }
    end
    return out
end

local function syncGrids(ply)
    local Inv, Items = Rhylib.Inventory, Rhylib.Items
    if not (Inv and Inv.SetGrid and Items and Items.RACK) then return end
    local want = K.ExtraGrids(ply)
    for _, cid in ipairs({ Items.RACK, Items.BELT }) do
        local g = want[cid]
        Inv.SetGrid(ply, cid, g and g[1] or 0, g and g[2] or 0)
    end
    if Inv.MarkChanged then Inv.MarkChanged(ply) end   -- carry limit
end

-- Items the player may no longer carry (def.carrySkill) are dropped.
local function dropForbidden(ply)
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.Get and Inv.MayHold and Inv.Drop) or not ply:Alive() then return end
    local out = {}
    for uid, o in pairs(Inv.Get(ply).byUid) do
        if not Inv.MayHold(ply, o.id) then out[#out + 1] = uid end
    end
    for _, uid in ipairs(out) do Inv.Drop(ply, uid) end
end

-- Reinforced: max health on top of the job's. Health itself only goes
-- up with it at spawn (relearning mid-fight doesn't heal).
local function applyHealth(ply, spawned)
    local want = K.Has(ply, "reinforced") and K.Cfg("reinforcedHealth") or 0
    local have = ply.rhylibReinforced or 0
    if want == have then return end
    ply.rhylibReinforced = want
    ply:SetMaxHealth(math.max(1, ply:GetMaxHealth() - have + want))
    if ply:Alive() and not ply.rhylibDown then
        local hp = ply:Health()
        if spawned then hp = hp + math.max(0, want - have) end
        ply:SetHealth(math.Clamp(hp, 1, ply:GetMaxHealth()))
    end
end

-- Spring legs: jump power, applied on top of whatever the job set.
local function applyJump(ply)
    local want = K.Has(ply, "spring_legs")
    if want and not ply.rhylibSpringBase then
        ply.rhylibSpringBase = ply:GetJumpPower()
        ply:SetJumpPower(ply.rhylibSpringBase * K.Cfg("springJump"))
    elseif not want and ply.rhylibSpringBase then
        ply:SetJumpPower(ply.rhylibSpringBase)
        ply.rhylibSpringBase = nil
    end
end

function K.SetSkills(ply, set)
    ply.rhylibSkills = set
    ply.rhylibSkillsLoaded = true
    ply:SetNW2String("rhylib_skills", setString(set))
    if not ply:IsBot() then
        local ids = {}
        for id in pairs(set) do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids > 0 then Data.Set("skills", key(ply), { n = ids }) else Data.Delete("skills", key(ply)) end
    end
    syncGrids(ply)
    dropForbidden(ply)
    applyJump(ply)
    applyHealth(ply)
    -- A gun on a mode its owner lost goes back to its first mode.
    for _, w in ipairs(ply:GetWeapons()) do
        if w.IsRhylib and w.FixFireMode then w:FixFireMode() end
    end
    hook.Run("Rhylib.SkillsChanged", ply)
end

Rhylib.Hook.Add("PlayerInitialSpawn", "skills.load", function(ply)
    local set = K.Stored(ply)
    ply:SetNW2String("rhylib_skills", setString(set))
end)

-- The spawn sets the job's jump power; ours goes on top a moment later.
Rhylib.Hook.Add("PlayerSpawn", "skills.spawn", function(ply)
    ply.rhylibSpringBase = nil
    -- Take Reinforced off now (this runs before the gamemode's spawn, which
    -- may or may not set max health again); it goes back on just after.
    if (ply.rhylibReinforced or 0) ~= 0 then
        ply:SetMaxHealth(math.max(1, ply:GetMaxHealth() - ply.rhylibReinforced))
        ply.rhylibReinforced = 0
    end
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        applyJump(ply)
        applyHealth(ply, true)
        dropForbidden(ply)
    end)
end)

Rhylib.Hook.Add("PlayerDisconnected", "skills.clear", function(ply)
    ply.rhylibSkills, ply.rhylibSkillsLoaded = nil, nil
end)

Rhylib.Net.Receive("skills.learn", function(ply)
    local n = K.NODES[net.ReadUInt(8)]
    if not n then return end
    local set = table.Copy(K.Stored(ply))
    local ok, why = K.CanLearn(ply, set, n.id)
    if not ok then return K.Note(ply, why, true) end
    set[n.id] = true
    K.SetSkills(ply, set)
    K.Note(ply, "Learned " .. n.name)
end, { rate = 4, burst = 8 })

Rhylib.Net.Receive("skills.reset", function(ply)
    if next(K.Stored(ply)) == nil then return end
    if not K.Cfg("freePoints") and hook.Run("Rhylib.CanResetSkills", ply) ~= true then
        return K.Note(ply, "You can't reset your skills right now", true)
    end
    K.SetSkills(ply, {})
    K.Note(ply, "Skills reset")
end, { rate = 1, burst = 2 })

-- Admins: rhylib_skills_reset <name> (or yourself).
concommand.Add("rhylib_skills_reset", function(ply, _, args)
    local function reply(t) if IsValid(ply) then ply:ChatPrint(t) else print(t) end end
    Rhylib.Perms.Check(ply, "rhylib.skills.admin", function(ok)
        if not ok then return reply("You don't have permission for rhylib_skills_reset") end
        local target = IsValid(ply) and ply or nil
        if args[1] then
            target = nil
            for _, p in ipairs(player.GetAll()) do
                if string.find(string.lower(p:Nick()), string.lower(args[1]), 1, true) then target = p end
            end
        end
        if not IsValid(target) then return reply("No such player") end
        K.SetSkills(target, {})
        reply("Reset the skills of " .. target:Nick())
    end)
end)
Rhylib.Perms.Register("rhylib.skills.admin", "admin", "Reset other players' skills")

--------------------------------------------------------------------------
-- Damage (called by rhylib_weapons for each bolt hit)
--------------------------------------------------------------------------

function K.DamageMult(ply, bolt, ent, tr, group)
    if not IsValid(ply) or not ply:IsPlayer() then return 1, false end
    local set = K.Set(ply)
    if next(set) == nil then return 1, false end
    local m, crit = 1, false
    if set.point_blank and bolt.start then
        local d = bolt.start:Distance(tr.HitPos)
        local near, far = K.Cfg("pointBlankNear"), K.Cfg("pointBlankFar")
        local f = d <= near and 1 or (d >= far and 0 or 1 - (d - near) / math.max(far - near, 1))
        m = m * (1 + (K.Cfg("pointBlankMult") - 1) * f)
    end
    if set.headhunter and group == HITGROUP_HEAD then m = m * K.Cfg("headhunterMult") end
    if set.shotgun_drills and IsValid(bolt.weapon) and K.GunClass(bolt.weapon) == K.DP24 then
        m = m * K.Cfg("shotgunDamage")
    end
    if set.crits and math.random() < K.Cfg("critChance") then
        m = m * K.Cfg("critMult")
        crit = true
    end
    return m, crit
end

--------------------------------------------------------------------------
-- Momentum: a kill (or downing someone) frees sprinting for a while
--------------------------------------------------------------------------

local function onKill(attacker)
    if not (IsValid(attacker) and attacker:IsPlayer() and K.Has(attacker, "momentum")) then return end
    local untilT = CurTime() + K.Cfg("momentumTime")
    attacker:SetNW2Float("rhylib_momentum", untilT)
    attacker.rhylibMomentumReload = untilT + 6   -- the next reload in the next few seconds
end
K.OnKill = onKill

Rhylib.Hook.Add("OnNPCKilled", "skills.momentum", function(_, attacker) onKill(attacker) end)
Rhylib.Hook.Add("PlayerDeath", "skills.momentum", function(victim, _, attacker)
    if attacker ~= victim then onKill(attacker) end
end)
Rhylib.Hook.Add("Rhylib.PlayerDowned", "skills.momentum", function(_, attacker) onKill(attacker) end)

--------------------------------------------------------------------------
-- Damage taken: Airborne and Combat medic (before armour at 100)
--------------------------------------------------------------------------

Rhylib.Hook.Add("EntityTakeDamage", "skills.resist", function(ent, dmg)
    if not ent:IsPlayer() or ent.rhylibDown then return end
    if bit.band(dmg:GetDamageType(), DMG_DIRECT) ~= 0 then return end   -- (bleeding, bleed-out)
    local m = 1
    local set = K.Set(ent)
    if next(set) ~= nil then
        local t = dmg:GetDamageType()
        if set.hard_landings and bit.band(t, DMG_FALL) ~= 0 then m = m * K.Cfg("fallMult") end
        if set.blast_hardened and bit.band(t, DMG_BLAST) ~= 0 then m = m * K.Cfg("blastMult") end
        if set.aerial_stability and bit.band(t, DMG_FALL) == 0 and not ent:OnGround()
            and ent:GetMoveType() == MOVETYPE_WALK then
            m = m * K.Cfg("airMult")
        end
        if set.combat_drop and (ent.rhylibDropUntil or 0) > CurTime() then m = m * K.Cfg("combatDropMult") end
        if set.juggernaut then m = m * K.Cfg("juggernautMult") end
        if set.under_fire then
            local Med = Rhylib.Medical
            local a = Med and Med.acts and Med.acts[ent]
            if a and a.kind ~= Med.A_STAB then m = m * K.Cfg("underFireMult") end
        end
        if set.hold_line and K.HoldingLine(ent) then m = m * K.Cfg("holdLineMult") end
        -- Shock Assault: no push from hits.
        if set.shock_assault then dmg:SetDamageForce(vector_origin) end
    end
    if m ~= 1 then dmg:ScaleDamage(m) end
end, 95)

-- Suppression: a Z-6 hit on a droid rattles the droids around it.
Rhylib.Hook.Add("EntityTakeDamage", "skills.suppress", function(ent, dmg)
    if not ent.IsRhylibDroid then return end
    local att, inf = dmg:GetAttacker(), dmg:GetInflictor()
    if not (IsValid(att) and att:IsPlayer() and IsValid(inf) and inf:IsWeapon() and K.GunClass(inf) == K.Z6 and K.Has(att, "suppression")) then return end
    local D = Rhylib.Droids
    if not (D and D.Suppress and D.active) then return end
    local now = CurTime()
    if (ent.rhylibSuppressCheck or 0) > now then return end   -- (once per 0.25 s per droid hit)
    ent.rhylibSuppressCheck = now + 0.25
    local pos, r2 = ent:GetPos(), K.Cfg("suppressRadius") ^ 2
    for d in pairs(D.active) do
        if IsValid(d) and d:GetPos():DistToSqr(pos) <= r2 then D.Suppress(d, K.Cfg("suppressTime"), K.Cfg("suppressMult")) end
    end
end)

-- Hold the line: shield up and another MP close by.
function K.HoldingLine(ply)
    local W, MP = Rhylib.Weapons, Rhylib.MP
    if not (W and W.ShieldUp and W.ShieldUp(ply) and MP and MP.IsMP) then return false end
    local r2 = K.Cfg("holdLineRange") ^ 2
    local pos = ply:GetPos()
    for _, o in ipairs(player.GetAll()) do
        if o ~= ply and o:Alive() and MP.IsMP(o) and o:GetPos():DistToSqr(pos) <= r2 then return true end
    end
    return false
end

-- Combat drop: landing after combatDropAir seconds of jetpack flight (in
-- the air the whole time, thrusting at some point) gives combatDropTime
-- seconds of less damage. Only players with the skill are tracked.
Rhylib.Hook.Add("PlayerTick", "skills.combatdrop", function(ply)
    if not K.Has(ply, "combat_drop") then
        ply.rhylibAirFrom = nil
        return
    end
    local J = Rhylib.Jetpack
    if ply:OnGround() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:WaterLevel() >= 2 or not (J and J.Has and J.Has(ply))
        or IsValid(ply:GetDTEntity(31)) then   -- (on a grapple rope)
        ply.rhylibAirFrom, ply.rhylibAirJet = nil, nil
        return
    end
    if not ply.rhylibAirFrom then ply.rhylibAirFrom = CurTime() end
    if ply:GetDTBool(J.DT_THRUST) then ply.rhylibAirJet = true end
end)

Rhylib.Hook.Add("OnPlayerHitGround", "skills.combatdrop", function(ply, inWater)
    local from, jet = ply.rhylibAirFrom, ply.rhylibAirJet
    ply.rhylibAirFrom, ply.rhylibAirJet = nil, nil
    if inWater or not from or not jet or not K.Has(ply, "combat_drop") then return end
    if CurTime() - from < K.Cfg("combatDropAir") then return end
    local t = K.Cfg("combatDropTime")
    ply.rhylibDropUntil = CurTime() + t
    ply:EmitSound("npc/roller/mine/rmine_blades_in2.wav", 70, 90)
    K.Note(ply, "Combat drop: " .. math.Round((1 - K.Cfg("combatDropMult")) * 100) .. "% less damage for " .. t .. " s")
end)

-- Death from above: a hard landing slams droids (NPCs and NextBots) nearby.
Rhylib.Hook.Add("OnPlayerHitGround", "skills.slam", function(ply, inWater, _, speed)
    if inWater or speed < K.Cfg("slamSpeed") or not K.Has(ply, "death_from_above") then return end
    local pos = ply:GetPos()
    local r = K.Cfg("slamRadius")
    local base = K.Cfg("slamDamage") * math.min(2, speed / K.Cfg("slamSpeed"))
    for _, e in ipairs(ents.FindInSphere(pos, r)) do
        if IsValid(e) and e ~= ply and (e:IsNPC() or e:IsNextBot()) and e:Health() > 0
            and not util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = e:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then
            local to = e:WorldSpaceCenter() - pos
            local f = 1 - math.Clamp(to:Length() / r, 0, 1) * 0.6
            local d = DamageInfo()
            d:SetDamage(base * f)
            d:SetDamageType(DMG_CLUB)
            d:SetAttacker(ply)
            d:SetInflictor(ply)
            d:SetDamagePosition(e:WorldSpaceCenter())
            to.z = 0
            d:SetDamageForce(to:GetNormalized() * 12000 + Vector(0, 0, 6000))
            e:TakeDamageInfo(d)
        end
    end
    local fx = EffectData()
    fx:SetOrigin(pos)
    fx:SetScale(r)
    util.Effect("ThumperDust", fx, true, true)
    ply:EmitSound("physics/concrete/boulder_impact_hard" .. math.random(1, 4) .. ".wav", 80)
    util.ScreenShake(pos, 6, 20, 0.6, r * 2)
end)
