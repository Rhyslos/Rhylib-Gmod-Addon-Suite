--[[
    Server bolt simulation.

    A bolt is a row in one Lua table, never an entity. One Tick handler
    moves all bolts and does one line trace per bolt per tick.

    Hit registration:
      1. First leg: the server rewinds other players to what the shooter
         saw (lag compensation) and traces the distance the bolt covered
         during the shooter's ping, capped by weapons.lagCompMax.
      2. The rest of the flight runs in real time, tick by tick.

    Other players get one small "shot" event (batched per tick) and draw
    the bolt themselves. The shooter's own client already drew it.

    Rockets are bolts too (weapon.Explosive set): slower, longer lived,
    and they do blast damage where they hit instead of a direct hit.

    Realm: server. Public: Bolts.Fire, Bolts.ApplyHits, Bolts.Speed,
    W.TrainingBlast, Bolts.active (the live bolt list).
    Console: rhylib_boltrange.
    Hooks fired:
      Rhylib.TrainingHit(ply, attacker, damage, inflictor, group)
          a training bolt or blast hit a player (rhylib_training answers:
          true = that eliminated them, false = ignored, no hit marker)
      Rhylib.StunHit(ply, attacker, weapon)
          a stun bolt hit a player (rhylib_mp decides what it does)
      Rhylib.Explosion(pos, reach, tier, attacker, inflictor, "rocket")
          a real (not training) rocket went off (rhylib_radio jammers)
    Other addons read during a hit: Rhylib.Skills.DamageMult (damage
    multiplier and crits), Rhylib.Weapons.ShieldBlocks (riot shields),
    Rhylib.Lying (hits on a lying player's ragdoll count for the player).
    Fields set on the target during TakeDamageInfo: ply.rhylibHitGroup
    (the body part, read by rhylib_medical), ply.rhylibFwd (hit came in
    through the ragdoll).
]]

local W = Rhylib.Weapons
W.Bolts = W.Bolts or {}
local Bolts = W.Bolts
Bolts.active = Bolts.active or {}

local Config = Rhylib.Config

-- Shot events. Each shot is written once: shots are grouped per tick by
-- the area they start in (cubes of SHOT_CELL units), and each group goes
-- in one message to the players near that area, in the core's batch
-- format (read on the client with Rhylib.Net.ReceiveBatch). A group with
-- one shooter skips them (they drew it already); in a mixed group the
-- client skips its own.
Rhylib.Net.Register("wep.shot")
local SHOT_CELL = 1024

-- Net "wep.shot" (server -> players near the shot), one item per bolt in
-- the core's batch format:
--   shooter UInt 13 (entity index), origin Vector, dir Normal,
--   speed UInt 15 (units/s, so up to 32767), color UInt 4 (BoltColor style),
--   left Bool (dual pistols: the left gun fired), ahead UInt 6.
-- ahead: the server bolt's head start (first leg) in 1/100 s, 6 bits.
local AHEAD_MAX = 63
local function writeShot(s)
    net.WriteUInt(s.shooter, 13)
    net.WriteVector(s.origin)
    net.WriteNormal(s.dir)
    net.WriteUInt(s.speed, 15)
    net.WriteUInt(s.color, 4)
    net.WriteBool(s.left)
    net.WriteUInt(s.ahead, 6)
end

-- Hit confirm to the shooter: 0 body, 1 head, 2 down/kill.
-- Net "wep.hit" (server -> the shooter, batched): kind UInt 2. Drives the
-- crosshair hit marker and hit sound (cl_20_crosshair.lua).
Bolts.HIT_BODY, Bolts.HIT_HEAD, Bolts.HIT_KILL = 0, 1, 2
local hitBatch = Rhylib.Net.CreateBatch("wep.hit", function(h)
    net.WriteUInt(h.kind, 2)
end)

local LIMBS = {
    [HITGROUP_LEFTARM] = true,
    [HITGROUP_RIGHTARM] = true,
    [HITGROUP_LEFTLEG] = true,
    [HITGROUP_RIGHTLEG] = true,
}

-- Reused for every trace so the bolt loop creates no garbage.
local traceResult = {}
local traceData = { mask = MASK_SHOT, output = traceResult }

-- Bolts fly through: soft-knocked players (hidden, can't be hurt), and
-- friendlies (rhylib_droids clone NPCs, 2026-10-06az): players' and
-- clones' bolts pass clones, clones' bolts pass players.
-- (cloneShot: the bolt came from a clone, even if that clone is gone now)
local function passes(e, owner, cloneShot)
    local fromClone = cloneShot or (owner ~= nil and owner.IsRhylibClone == true)
    if e:IsPlayer() then
        if e:GetNW2Bool("rhylib_knockSoft", false) then return true end
        return fromClone
    end
    if e.IsRhylibClone == true then return fromClone or (owner ~= nil and owner:IsPlayer()) end
    -- (a lying player's ragdoll counts as the player)
    local L = Rhylib.Lying
    return fromClone and L and L.Owner and IsValid(L.Owner(e)) or false
end

local function trace(from, to, filter, cloneShot)
    traceData.start = from
    traceData.endpos = to
    traceData.filter = filter
    local tr = util.TraceLine(traceData)
    local owner = IsValid(filter) and filter or nil
    local skip
    for _ = 1, 4 do
        if not (IsValid(tr.Entity) and passes(tr.Entity, owner, cloneShot)) then break end
        skip = skip or { filter }
        skip[#skip + 1] = tr.Entity
        traceData.filter = skip
        tr = util.TraceLine(traceData)
    end
    traceData.filter = nil
    return tr
end

--[[
    Training blasts (rockets, grenades and droid rockets with training
    ammo): no real damage. Players in range and in sight lose sim health
    (hook Rhylib.TrainingHit, rhylib_training), training droids take
    normal blast damage. Falloff like util.BlastDamage.

    W.TrainingBlast(pos, radius, damage, attacker, inflictor): server.
    Returns true if a hit marker was sent to the attacker.
    Example: Rhylib.Weapons.TrainingBlast(pos, 250, 100, ply, ent)
]]
local blastTr = {}
local blastData = { mask = MASK_SOLID_BRUSHONLY, output = blastTr }
function W.TrainingBlast(pos, radius, damage, attacker, inflictor)
    attacker = IsValid(attacker) and attacker or game.GetWorld()
    local marked = false
    for _, e in ipairs(ents.FindInSphere(pos, radius)) do
        local isPly = e:IsPlayer() and e:Alive()
        local isDroid = e.IsRhylibDroid and e.Training and e:Health() > 0
        if isPly or isDroid then
            local c = isPly and e:EyePos() or e:WorldSpaceCenter()
            blastData.start, blastData.endpos = pos, c
            util.TraceLine(blastData)
            if not blastTr.Hit then
                local amount = damage * math.Clamp(1 - pos:Distance(c) / radius, 0, 1)
                if amount >= 1 then
                    if isPly then
                        local out = hook.Run("Rhylib.TrainingHit", e, attacker, amount, inflictor)
                        if attacker:IsPlayer() and e ~= attacker and out ~= false then
                            hitBatch:Send(attacker, { kind = out == true and Bolts.HIT_KILL or Bolts.HIT_BODY })
                            marked = true
                        end
                    else
                        local d = DamageInfo()
                        d:SetDamage(amount)
                        d:SetDamageType(DMG_BLAST)
                        d:SetAttacker(attacker)
                        d:SetInflictor(IsValid(inflictor) and inflictor or attacker)
                        d:SetDamagePosition(c)
                        d:SetDamageForce((c - pos):GetNormalized() * amount * 300)
                        e:TakeDamageInfo(d)
                    end
                end
            end
        end
    end
    return marked
end

-- Rockets: blast damage and an explosion where they hit.
local function explode(bolt, pos, normal)
    local owner = bolt.owner
    local attacker = IsValid(owner) and owner or game.GetWorld()
    local inflictor = IsValid(bolt.weapon) and bolt.weapon or attacker
    local ex = bolt.explosive
    local at = pos + normal * 4  -- just off the surface, so walls don't eat the blast
    if bolt.training then
        W.TrainingBlast(at, ex.radius, ex.damage, attacker, inflictor)
    else
        util.BlastDamage(inflictor, attacker, at, ex.radius, ex.damage)
        -- (comms jammers, rhylib_radio: a rocket is strength 2)
        hook.Run("Rhylib.Explosion", at, ex.radius, ex.tier or 2, attacker, inflictor, "rocket")
    end

    local ed = EffectData()
    ed:SetOrigin(at)
    ed:SetNormal(normal)
    ed:SetMagnitude(1)
    ed:SetScale(1)
    util.Effect("Explosion", ed, true, true)
end

-- Hit group, also for models whose hitboxes are all "generic" (guessed
-- from the hit position) and lying ragdolls.
local function hitGroup(ent, rag, tr)
    local L = Rhylib.Lying
    if rag then return L.HitGroup(rag, tr.HitPos) end
    local group = tr.HitGroup
    if group == HITGROUP_GENERIC and (ent:IsPlayer() or ent:IsNextBot()) and Rhylib.HitGroupAt then
        group = Rhylib.HitGroupAt(ent, tr.HitPos)
    end
    return group
end

local function groupMult(group)
    if group == HITGROUP_HEAD then return Config.Get("weapons", "headMult") end
    if LIMBS[group] then return Config.Get("weapons", "limbMult") end
    return 1
end

-- Training bolts: players lose sim health only (rhylib_training answers
-- Rhylib.TrainingHit; true = that eliminated them). Returns true when the
-- hit is done, false for a training droid (normal damage).
local function trainingHit(bolt, tr, ent, rag, group)
    if ent.IsRhylibDroid then
        if ent.Training then return false end
        local fx = EffectData()
        fx:SetOrigin(tr.HitPos)
        fx:SetNormal(-bolt.dir)
        util.Effect("MetalSpark", fx, true, true)
        return true
    end
    if not ent:IsPlayer() or not ent:Alive() then return true end
    group = group or hitGroup(ent, rag, tr)
    local owner = bolt.owner
    local attacker = IsValid(owner) and owner or game.GetWorld()
    local out = hook.Run("Rhylib.TrainingHit", ent, attacker, bolt.damage * groupMult(group), bolt.weapon, group)
    if IsValid(owner) and owner:IsPlayer() and out ~= false then
        local kind = group == HITGROUP_HEAD and Bolts.HIT_HEAD or Bolts.HIT_BODY
        if out == true then kind = Bolts.HIT_KILL end
        hitBatch:Send(owner, { kind = kind })
    end
    return true
end

-- The entity a hit counts for: a lying player's ragdoll (rhylib_core)
-- counts for the player. Returns ent, rag.
local function hitTarget(tr)
    local ent = tr.Entity
    if not IsValid(ent) then return nil end
    local L = Rhylib.Lying
    local rag = L and L.Owner and L.Owner(ent) and ent or nil
    if rag then ent = L.Owner(rag) end
    return ent, rag
end

-- group: worked out while players were rewound (first leg), or nil.
local function applyHit(bolt, tr, group)
    if bolt.onHit then
        bolt.onHit(bolt, tr)  -- special bolts (the grapple hook) handle their own hits
        return
    end
    if bolt.explosive then
        explode(bolt, tr.HitPos, tr.HitNormal)
        return
    end
    local ent, rag = hitTarget(tr)
    if not IsValid(ent) then return end
    -- Clone NPC bolts never hurt players or clones (rhylib_droids).
    if bolt.clone and (ent:IsPlayer() or ent.IsRhylibClone) then return end
    -- Riot shields (sh_60_shield.lua): a bolt from the front stops on the shield.
    if ent:IsPlayer() and Rhylib.Weapons.ShieldBlocks and Rhylib.Weapons.ShieldBlocks(ent, bolt.dir) then
        local fx = EffectData()
        fx:SetOrigin(tr.HitPos)
        fx:SetNormal(-bolt.dir)
        util.Effect("MetalSpark", fx, true, true)
        ent:EmitSound("physics/metal/metal_solid_impact_bullet" .. math.random(1, 4) .. ".wav", 70)
        return
    end
    if bolt.training and trainingHit(bolt, tr, ent, rag, group) then return end
    -- Stun bolts (SWEP.Stun or the "stun" fire mode): no damage; rhylib_mp decides what a hit does.
    if bolt.stun then
        if ent:IsPlayer() then hook.Run("Rhylib.StunHit", ent, bolt.owner, bolt.weapon) end
        return
    end

    group = group or hitGroup(ent, rag, tr)
    local mult = groupMult(group)

    local owner = bolt.owner
    local attacker = IsValid(owner) and owner or game.GetWorld()

    -- Skills (rhylib_skills): Point blank, critical hits.
    local crit = false
    local K = Rhylib.Skills
    if K and K.DamageMult and IsValid(owner) and owner:IsPlayer() then
        local sm
        sm, crit = K.DamageMult(owner, bolt, ent, tr, group)
        mult = mult * sm
    end

    local dmg = DamageInfo()
    dmg:SetDamage(bolt.damage * mult)
    dmg:SetAttacker(attacker)
    dmg:SetInflictor(IsValid(bolt.weapon) and bolt.weapon or attacker)
    dmg:SetDamageType(DMG_BULLET)
    dmg:SetDamagePosition(tr.HitPos)
    dmg:SetDamageForce(bolt.dir * bolt.damage * 60)
    -- Which body part was hit (rhylib_medical reads it during the hit).
    local living = ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
    local wasDown = ent.rhylibDown
    if ent:IsPlayer() then ent.rhylibHitGroup = group end
    if rag then ent.rhylibFwd = true end   -- (a hit on the ragdoll counts for its lying player)
    ent:TakeDamageInfo(dmg)
    ent.rhylibFwd = nil
    if ent:IsPlayer() then ent.rhylibHitGroup = nil end

    if IsValid(owner) and owner:IsPlayer() and living then
        local kind = (group == HITGROUP_HEAD or crit) and Bolts.HIT_HEAD or Bolts.HIT_BODY
        -- Dropped them: killed, or downed (rhylib_medical).
        if ent:Health() <= 0 or (ent:IsPlayer() and not ent:Alive()) or (ent.rhylibDown and not wasDown) then
            kind = Bolts.HIT_KILL
        end
        hitBatch:Send(owner, { kind = kind })
    end
end

-- player.GetHumans() builds a new table each call. Build it once per tick,
-- not once per shot (a firefight can be dozens of shots in one tick).
local humans, humansTick = {}, -1
local function getHumans()
    local tick = engine.TickCount()
    if tick ~= humansTick then
        humans, humansTick = player.GetHumans(), tick
    end
    return humans
end

-- Groups of this tick's shots, by area. Group tables are reused.
local groups, groupKeys, groupPool = {}, {}, {}
local floor = math.floor

local function sendShot(owner, color, origin, dir, speed, left, ahead)
    local cx, cy, cz = floor(origin.x / SHOT_CELL), floor(origin.y / SHOT_CELL), floor(origin.z / SHOT_CELL)
    local key = (cx + 128) * 65536 + (cy + 128) * 256 + (cz + 128)
    local g = groups[key]
    if not g then
        g = table.remove(groupPool) or { items = {} }
        g.only = owner   -- (one shooter in the group: they don't need it)
        g.x, g.y, g.z = (cx + 0.5) * SHOT_CELL, (cy + 0.5) * SHOT_CELL, (cz + 0.5) * SHOT_CELL
        groups[key] = g
        groupKeys[#groupKeys + 1] = key
    end
    if g.only ~= owner then g.only = false end
    g.items[#g.items + 1] = {
        shooter = owner:EntIndex(),
        origin = origin,
        dir = dir,
        speed = math.min(math.floor(speed), 32767),
        color = color,
        left = left and true or false,
        ahead = math.Clamp(math.floor(ahead * 100 + 0.5), 0, AHEAD_MAX),
    }
end

local recipients = {}
local centre = Vector()
local function flushShots()
    if #groupKeys == 0 then return end
    -- Players within shot range of any point in the cube get the group.
    local reach = Config.Get("weapons", "shotRange") + SHOT_CELL * 0.87
    local reachSqr = reach * reach
    local list = getHumans()
    -- A shooter's own client drew their bolts already (not in singleplayer).
    local sp = game.SinglePlayer()
    for k = 1, #groupKeys do
        local key = groupKeys[k]
        local g = groups[key]
        centre:SetUnpacked(g.x, g.y, g.z)
        local skip = not sp and g.only or nil
        local n = 0
        for i = 1, #list do
            local ply = list[i]
            if ply ~= skip and IsValid(ply) and ply:GetPos():DistToSqr(centre) < reachSqr then
                n = n + 1
                recipients[n] = ply
            end
        end
        for i = #recipients, n + 1, -1 do recipients[i] = nil end

        local items = g.items
        if n > 0 then
            local ok, err = pcall(Rhylib.Net.SendItems, "wep.shot", items, writeShot, net.Send, recipients)
            if not ok then Rhylib.Error("weapons", "shot send failed: %s", tostring(err)) end
        end
        for i = #items, 1, -1 do items[i] = nil end
        groups[key] = nil
        groupKeys[k] = nil
        groupPool[#groupPool + 1] = g
    end
end

-- After the weapons have fired this tick (the core's batches flush at 1000).
Rhylib.Hook.Add("Tick", "weapons.shots.flush", flushShots, 990)

-- Bolts.Speed(weapon): a gun's bolt speed in units/s: SWEP.BoltSpeed (7000
-- if unset) x config boltSpeedMult. Rockets (SWEP.Explosive) aren't scaled.
function Bolts.Speed(weapon)
    local s = weapon.BoltSpeed or 7000
    if weapon.Explosive then return s end
    return s * (Config.Get("weapons", "boltSpeedMult") or 1)
end

-- Seconds the shooter's view lags behind the server: ping plus their
-- interpolation delay (what LagCompensation rewinds). Cached per player.
local function viewLag(ply)
    local now = CurTime()
    if not ply.rhylibLerpAt or now > ply.rhylibLerpAt then
        ply.rhylibLerpAt = now + 5
        local interp = ply:GetInfoNum("cl_interp", 0.1)
        local ratio, rate = ply:GetInfoNum("cl_interp_ratio", 2), math.max(ply:GetInfoNum("cl_updaterate", 33), 1)
        ply.rhylibLerp = math.Clamp(math.max(interp, ratio / rate), 0, 0.2)
    end
    return ply:Ping() / 1000 + (ply.rhylibLerp or 0.1)
end

-- Copy of a trace result for a hit applied later (Bolts.ApplyHits).
local function copyTrace(tr)
    return {
        Hit = tr.Hit, HitWorld = tr.HitWorld, Entity = tr.Entity, HitGroup = tr.HitGroup,
        HitPos = Vector(tr.HitPos), HitNormal = Vector(tr.HitNormal), Fraction = tr.Fraction,
    }
end

-- Hit group of a first-leg hit, worked out while players are still
-- rewound (Rhylib.HitGroupAt reads the target's position and angles).
local function rewoundGroup(bolt, tr)
    if bolt.onHit or bolt.explosive then return nil end
    local ent, rag = hitTarget(tr)
    if not IsValid(ent) then return nil end
    return hitGroup(ent, rag, tr)
end

local function firstLegTrace(bolt, from, to, owner)
    local tr = trace(from, to, owner, bolt.clone)
    return tr, tr.Hit and rewoundGroup(bolt, tr) or nil
end

-- Bolts.Fire(owner, weapon, origin, dir, damage, opts, hits): server.
-- Fires one bolt. Called from the weapon's PrimaryAttack (rhylib_base
-- FireShot), and by NPCs (rhylib_droids passes a plain table as weapon:
-- it only needs BoltSpeed, BoltColor, Damage and the like).
--   owner    player or NPC that fired (gets the kill credit)
--   weapon   the SWEP (or a table with the same fields)
--   origin   start point (usually owner:GetShootPos()), dir a unit vector
--   damage   per hit (nil = weapon.Damage)
--   opts     (optional) speed, color, life, stun, training,
--            onHit(bolt, tr), onExpire(bolt): override the weapon's own
--            bolt settings (used by the grapple hook and stun mode)
--   hits     (optional) the caller has lag compensation on already
--            (pellets); first-leg hits are queued in this list, and the
--            caller runs Bolts.ApplyHits(hits) after turning it off.
-- Returns nothing. Sends the wep.shot event to nearby players.
-- Example: Rhylib.Weapons.Bolts.Fire(npc, { BoltSpeed = 6000, BoltColor = 2, Damage = 12 },
--              npc:EyePos(), (target:EyePos() - npc:EyePos()):GetNormalized())
function Bolts.Fire(owner, weapon, origin, dir, damage, opts, hits)
    local speed = opts and opts.speed or Bolts.Speed(weapon)
    local isPly = owner:IsPlayer()
    -- The first leg covers what the shooter saw: the bolt's flight during
    -- their ping and interpolation, against players where they saw them.
    local lag = isPly and math.min(viewLag(owner), Config.Get("weapons", "lagCompMax")) or 0
    local ahead = math.max(lag, engine.TickInterval())
    local firstLeg = speed * ahead

    local life = opts and opts.life or weapon.BoltLife or Config.Get("weapons", "boltLife")
    -- Optional reach cap (config boltRange, 0 = off). Rockets keep their
    -- life (their blast is seen and felt where they land), scoped guns their
    -- full reach.
    local cap = Rhylib.Weapons.BoltRange()
    if cap > 0 and not (opts and opts.life) and not weapon.Explosive and not weapon.Scope then
        life = math.min(life, math.max(cap - firstLeg, 0) / speed)
    end
    local bolt = {
        owner = owner,
        weapon = weapon,
        pos = origin,
        start = Vector(origin),   -- (Point blank measures from here)
        dir = dir,
        speed = speed,
        damage = damage or weapon.Damage,
        die = CurTime() + life,
        explosive = weapon.Explosive,
        stun = weapon.Stun or (opts and opts.stun) or nil,
        training = weapon.Training or (opts and opts.training) or nil,   -- (rhylib_training)
        clone = owner.IsRhylibClone == true or nil,   -- (rhylib_droids clone NPC: never hurts friendlies)
        onHit = opts and opts.onHit,
        onExpire = opts and opts.onExpire,
    }

    -- (dual pistols: which gun, as the fire anim; others can't see the clip)
    local left = weapon.GetFireModeName and weapon:GetFireModeName() == "dual" and weapon:Clip1() % 2 == 1
    sendShot(owner, opts and opts.color or weapon.BoltColor or 1, origin, dir, speed, left, ahead)

    local comp = isPly and not hits
    local tr, group
    if comp then
        owner:LagCompensation(true)
        local ok, a, b = pcall(firstLegTrace, bolt, origin, origin + dir * firstLeg, owner)
        owner:LagCompensation(false)   -- (always, even after an error)
        if not ok then error(a, 0) end
        tr, group = a, b
    else
        tr, group = firstLegTrace(bolt, origin, origin + dir * firstLeg, owner)
    end

    if tr.Hit then
        if hits then
            hits[#hits + 1] = { bolt, copyTrace(tr), group }
        else
            applyHit(bolt, tr, group)
        end
        return
    end

    -- Two position vectors per bolt, swapped each tick, plus a fixed step,
    -- so the tick loop below allocates no vectors.
    bolt.pos = Vector(tr.HitPos)
    bolt.nextPos = Vector()
    bolt.step = dir * (speed * engine.TickInterval())
    Bolts.active[#Bolts.active + 1] = bolt
end

-- Bolts.ApplyHits(hits): applies first-leg hits queued by
-- Bolts.Fire(..., hits), then empties the list. Server.
function Bolts.ApplyHits(hits)
    for i = 1, #hits do
        local h = hits[i]
        hits[i] = nil
        applyHit(h[1], h[2], h[3])
    end
end

Rhylib.Hook.Add("Tick", "weapons.bolts", function()
    local list = Bolts.active
    if #list == 0 then return end

    local now = CurTime()
    local i = 1
    while i <= #list do
        local b = list[i]
        local remove = now > b.die or not b.step  -- (bolts from before an autorefresh)
        if remove and b.onExpire and b.step then b.onExpire(b) end

        if not remove then
            local to = b.nextPos
            to:Set(b.pos)
            to:Add(b.step)
            local owner = b.owner
            local tr = trace(b.pos, to, IsValid(owner) and owner or nil, b.clone)
            if tr.Hit then
                applyHit(b, tr)
                remove = true
            else
                b.nextPos, b.pos = b.pos, to
            end
        end

        if remove then
            list[i] = list[#list]
            list[#list] = nil
        else
            i = i + 1
        end
    end
end)

--------------------------------------------------------------------------
-- Bolt reach cap, live (owner: unsure about it, so it's easy to try)
--   rhylib_boltrange          shows the current value
--   rhylib_boltrange 6000     bolts stop after 6000 units (~115 m)
--   rhylib_boltrange 0        off: bolts fly their full life
-- Saved (Data "weapons"/"boltRange"), so it stays after a restart.
-- Permission rhylib.weapons.boltrange (default admin). Clients learn the
-- value through Global2Int "rhylib_boltRange" (W.BoltRange()).
--------------------------------------------------------------------------

local function applyBoltRange(n)
    Config.Set("weapons", "boltRange", n)
    SetGlobal2Int("rhylib_boltRange", n)
end

Rhylib.Hook.Add("InitPostEntity", "weapons.boltrange", function()
    local saved = tonumber(Rhylib.Data.Get("weapons", "boltRange"))
    applyBoltRange(math.max(0, math.floor(saved or tonumber(Config.Get("weapons", "boltRange")) or 0)))
end)

Rhylib.Perms.Register("rhylib.weapons.boltrange", "admin", "Change the bolt reach cap (rhylib_boltrange)")

concommand.Add("rhylib_boltrange", function(ply, _, args)
    local function reply(t) if IsValid(ply) then ply:ChatPrint(t) else print(t) end end
    Rhylib.Perms.Check(ply, "rhylib.weapons.boltrange", function(ok)
        if not ok then return reply("You don't have permission for rhylib_boltrange") end
        local n = tonumber(args[1] or "")
        if not n then
            local cur = Rhylib.Weapons.BoltRange()
            return reply("Bolt reach cap: " .. (cur > 0 and (cur .. " units (~" .. math.Round(cur * 0.019) .. " m)") or "off") .. ". Use rhylib_boltrange <units> (0 = off).")
        end
        n = math.Clamp(math.floor(n), 0, 60000)
        applyBoltRange(n)
        Rhylib.Data.Set("weapons", "boltRange", n)
        reply("Bolt reach cap " .. (n > 0 and ("set to " .. n .. " units (~" .. math.Round(n * 0.019) .. " m)") or "off"))
    end)
end)
