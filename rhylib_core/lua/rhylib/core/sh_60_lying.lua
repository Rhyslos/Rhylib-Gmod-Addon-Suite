--[[
    Lying players (downed in rhylib_medical, stunned in rhylib_mp) become a
    server ragdoll (prop_ragdoll), the same for everyone.

    Begin(ply): a ragdoll from the player's current pose and speed (it
    falls naturally); the player is hidden (and their weapon), kept
    standing on the ground under the ragdoll's pelvis (0.1 s timer) and
    can't be hit through it. After SETTLE seconds the ragdoll freezes (no
    more physics or network updates); dragging unfreezes it and pulls it by
    the chest (Rhylib.Lying.Pull, rhylib_medical).
    End(ply): the player is put where the body lies and shown again; the
    ragdoll goes. Dying while lying leaves it as the corpse (the engine's
    death ragdoll is hidden) until respawn.
    Damage to the ragdoll goes to its player (hit group from the nearest
    bone); attacks that hit the hidden player directly (its invisible pose)
    are blocked, so nothing hits twice. Lying players pass through other
    players (COLLISION_GROUP_WEAPON) and are unstuck when they get up. NW2: player rhylib_rag (the ragdoll), rhylib_ragCorpse; ragdoll
    rhylib_ragOwner.

    Rhylib.Lying.Is(ply): downed or stunned (asks the modules that exist).
    Rhylib.Lying.BodyPos(ply): the body's centre (ragdoll pelvis).
    Rhylib.Lying.Owner(ent): the player a lying ragdoll belongs to.
]]

Rhylib.Lying = Rhylib.Lying or {}
local L = Rhylib.Lying

local UP = Vector(0, 0, 6)
local SETTLE = 2.5

function L.Is(ply)
    local Med, MP = Rhylib.Medical, Rhylib.MP
    if Med and Med.IsDown and Med.IsDown(ply) then return true end
    if MP and MP.IsStunned and MP.IsStunned(ply) then return true end
    if ply:GetNW2Float("rhylib_knockEnd", 0) ~= 0 then return true end   -- (sh_61_knock.lua)
    return false
end

-- The held pose under the hidden player (hitboxes): straight to the end.
function L.Cycle() return 0.99 end

function L.Ragdoll(ply)
    local r = ply:GetNW2Entity("rhylib_rag")
    return IsValid(r) and r or nil
end

function L.Owner(ent)
    if not IsValid(ent) or ent:GetClass() ~= "prop_ragdoll" then return nil end
    local o = ent:GetNW2Entity("rhylib_ragOwner")
    return IsValid(o) and o or nil
end

function L.BodyPos(ply)
    local r = L.Ragdoll(ply)
    if r then return r:GetPos() + UP end
    return ply:GetPos() + Vector(0, 0, 10)
end

-- Our ragdolls never touch players: the hidden player stands right under
-- the body and would hold it up like a ball (and others walk through it).
Rhylib.Hook.Add("ShouldCollide", "core.lying", function(a, b)
    if a:IsPlayer() and b:GetNW2Bool("rhylib_lyingRag") then return false end
    if b:IsPlayer() and a:GetNW2Bool("rhylib_lyingRag") then return false end
end)

if CLIENT then return end

L.active = L.active or {}   -- [ply] = ragdoll (lying)
L.corpse = L.corpse or {}   -- [ply] = ragdoll (died lying)

local function eachPhys(rag, fn)
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then fn(phys, i) end
    end
end

local function setFrozen(rag, frozen)
    if rag.rhylibFrozen == frozen then return end
    rag.rhylibFrozen = frozen
    eachPhys(rag, function(phys)
        phys:EnableMotion(not frozen)
        if not frozen then phys:Wake() end
    end)
end

-- Only undoes what we did (admin cloaks etc. keep their own state).
local function showPlayer(ply, show)
    if show and not ply.rhylibLieHidden then return end
    ply.rhylibLieHidden = not show or nil
    if show and ply.rhylibCloak then return end   -- (rhylib_admin invisible: stay hidden)
    ply:SetNoDraw(not show)
    ply:DrawShadow(show)
    ply:DrawWorldModel(show)
end

-- Ground under a point (the player stands there; props count).
local function ground(p, filter)
    local tr = util.TraceLine({ start = p + Vector(0, 0, 12), endpos = p - Vector(0, 0, 72), filter = filter, mask = MASK_PLAYERSOLID })
    return tr.Hit and tr.HitPos or p
end

-- Standing back up under something: move to the nearest clear spot.
local NUDGES = { Vector(0, 0, 0), Vector(0, 0, 12), Vector(24, 0, 4), Vector(-24, 0, 4), Vector(0, 24, 4), Vector(0, -24, 4),
    Vector(40, 0, 8), Vector(-40, 0, 8), Vector(0, 40, 8), Vector(0, -40, 8), Vector(0, 0, 36) }
function L.Unstick(ply)
    local pos = ply:GetPos()
    local mins, maxs = ply:GetHull()
    for _, off in ipairs(NUDGES) do
        local p = pos + off
        local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
        if not tr.StartSolid then
            if off ~= NUDGES[1] then ply:SetPos(p) end
            return
        end
    end
end

function L.Begin(ply)
    if L.Ragdoll(ply) or not ply:Alive() then return end
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return end
    rag:SetModel(ply:GetModel())
    rag:SetPos(ply:GetPos())
    rag:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    rag:SetSkin(ply:GetSkin())
    for _, bg in ipairs(ply:GetBodyGroups() or {}) do rag:SetBodygroup(bg.id, ply:GetBodygroup(bg.id)) end
    rag:SetColor(ply:GetColor())
    rag:SetMaterial(ply:GetMaterial())
    rag:SetNW2Bool("rhylib_lyingRag", true)
    rag:SetCustomCollisionCheck(true)   -- (ShouldCollide above)
    rag:Spawn()
    rag:Activate()
    rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)   -- players walk through it; shots still hit
    rag.rhylibOwner = ply
    rag:SetNW2Entity("rhylib_ragOwner", ply)

    -- Start from the player's pose and speed.
    local vel = ply:GetVelocity()
    -- (A bone at the player's origin means no real bone data: leave that
    -- part where the ragdoll put it, or the joints tear.)
    local origin = ply:GetPos()
    eachPhys(rag, function(phys, i)
        local b = ply:LookupBone(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)))
        local m = b and ply:GetBoneMatrix(b)
        local pos, ang = nil, nil
        if m then pos, ang = m:GetTranslation(), m:GetAngles() end
        if not pos and b then pos, ang = ply:GetBonePosition(b) end
        if pos and pos:DistToSqr(origin) > 1 then
            phys:SetPos(pos)
            phys:SetAngles(ang)
        end
        phys:SetVelocity(vel)
        phys:Wake()
    end)

    rag.rhylibFreezeAt = CurTime() + SETTLE
    rag.rhylibFrozen = false
    L.active[ply] = rag
    ply:SetNW2Entity("rhylib_rag", rag)
    showPlayer(ply, false)
    -- Others walk through the (hidden) player; medical may have done it already.
    if ply:GetCollisionGroup() ~= COLLISION_GROUP_WEAPON then
        ply.rhylibLieCG = ply:GetCollisionGroup()
        ply:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    end
    rag.rhylibSetPos = ply:GetPos()
end

-- noMove: don't put the player on the body (respawning elsewhere).
function L.End(ply, noMove)
    if not IsValid(ply) then return end
    local rag = L.active[ply]
    L.active[ply] = nil
    ply:SetNW2Entity("rhylib_rag", NULL)
    if ply.rhylibLieCG then
        ply:SetCollisionGroup(ply.rhylibLieCG)
        ply.rhylibLieCG = nil
    end
    if ply:Alive() then showPlayer(ply, true) end
    if not IsValid(rag) then return end
    if ply:Alive() then
        -- Up where the body lies, clear of walls and props.
        if not noMove then
            ply:SetPos(ground(rag:GetPos(), { ply, rag }))
            L.Unstick(ply)
        end
        rag:Remove()
    else
        -- Died lying: the ragdoll is the corpse until they respawn.
        ply:SetNW2Bool("rhylib_ragCorpse", true)
        rag:SetNW2Entity("rhylib_ragOwner", NULL)
        rag.rhylibOwner = nil
        if IsValid(L.corpse[ply]) then L.corpse[ply]:Remove() end
        L.corpse[ply] = rag
    end
end

-- Dragging (rhylib_medical): pull the chest towards `to`, at most `speed`.
local CHEST = "ValveBiped.Bip01_Spine2"
function L.Pull(ply, to, leash, speed)
    local rag = L.active[ply]
    if not IsValid(rag) then return false end
    setFrozen(rag, false)
    rag.rhylibFreezeAt = CurTime() + 1.5
    local b = rag:LookupBone(CHEST)
    local pi = b and rag:TranslateBoneToPhysBone(b)
    local phys = rag:GetPhysicsObjectNum(pi or 0)
    if not IsValid(phys) then return true end
    local d = to - phys:GetPos()
    d.z = 0
    local dist = d:Length()
    if dist > leash then
        local v = d * (math.min((dist - leash) * 8, speed) / dist)
        v.z = phys:GetVelocity().z
        phys:SetVelocity(v)
    end
    return true
end

-- Keep players on their body; freeze settled ragdolls.
timer.Create("Rhylib.Lying", 0.1, 0, function()
    local now = CurTime()
    for ply, rag in pairs(L.active) do
        if not IsValid(ply) then
            if IsValid(rag) then rag:Remove() end
            L.active[ply] = nil
        elseif not IsValid(rag) then
            L.active[ply] = nil
            ply:SetNW2Entity("rhylib_rag", NULL)
            if ply:Alive() then showPlayer(ply, true) end
        else
            if ply:Alive() then
                -- Moved by something else (admin teleport): the body comes along.
                local moved = ply:GetPos() - (rag.rhylibSetPos or ply:GetPos())
                if moved:LengthSqr() > 64 * 64 then
                    eachPhys(rag, function(phys) phys:SetPos(phys:GetPos() + moved) end)
                end
                local g = ground(rag:GetPos(), { ply, rag })
                if g:DistToSqr(ply:GetPos()) > 16 then ply:SetPos(g) end
                rag.rhylibSetPos = ply:GetPos()
            end
            if not rag.rhylibFrozen and now >= rag.rhylibFreezeAt then setFrozen(rag, true) end
        end
    end
end)

-- Before medical / MP clean up (-100): a respawn isn't put on the old body.
Rhylib.Hook.Add("PlayerSpawn", "core.lying", function(ply)
    if L.active[ply] then L.End(ply, true) end
    if IsValid(L.corpse[ply]) then L.corpse[ply]:Remove() end
    L.corpse[ply] = nil
    ply:SetNW2Bool("rhylib_ragCorpse", false)
    showPlayer(ply, true)
end, -100)

Rhylib.Hook.Add("PlayerDisconnected", "core.lying", function(ply)
    if IsValid(L.active[ply]) then L.active[ply]:Remove() end
    if IsValid(L.corpse[ply]) then L.corpse[ply]:Remove() end
    L.active[ply], L.corpse[ply] = nil, nil
end)

-- Hits on the ragdoll hurt its player. Hit group from the nearest bone.
local GROUPS = {
    { "head", HITGROUP_HEAD }, { "neck", HITGROUP_HEAD },
    { "l_upperarm", HITGROUP_LEFTARM }, { "l_forearm", HITGROUP_LEFTARM }, { "l_hand", HITGROUP_LEFTARM },
    { "r_upperarm", HITGROUP_RIGHTARM }, { "r_forearm", HITGROUP_RIGHTARM }, { "r_hand", HITGROUP_RIGHTARM },
    { "l_thigh", HITGROUP_LEFTLEG }, { "l_calf", HITGROUP_LEFTLEG }, { "l_foot", HITGROUP_LEFTLEG },
    { "r_thigh", HITGROUP_RIGHTLEG }, { "r_calf", HITGROUP_RIGHTLEG }, { "r_foot", HITGROUP_RIGHTLEG },
    { "spine", HITGROUP_CHEST }, { "pelvis", HITGROUP_STOMACH },
}
function L.HitGroup(rag, pos)
    local best, bestD = HITGROUP_CHEST, math.huge
    eachPhys(rag, function(phys, i)
        local d = phys:GetPos():DistToSqr(pos)
        if d < bestD then
            local name = string.lower(rag:GetBoneName(rag:TranslatePhysBoneToBone(i)) or "")
            for _, g in ipairs(GROUPS) do
                if string.find(name, g[1], 1, true) then
                    best, bestD = g[2], d
                    break
                end
            end
        end
    end)
    return best
end

Rhylib.Hook.Add("EntityTakeDamage", "core.lying", function(ent, dmg)
    local ply = ent.rhylibOwner
    if not IsValid(ply) or ent:GetClass() ~= "prop_ragdoll" then return end
    local att = dmg:GetAttacker()
    -- Only real attacks (not props bumping into it).
    if IsValid(att) and (att:IsPlayer() or att:IsNPC() or att:IsNextBot()) and ply:Alive() then
        local fwd = DamageInfo()
        fwd:SetDamage(dmg:GetDamage())
        fwd:SetDamageType(dmg:GetDamageType())
        fwd:SetAttacker(att)
        fwd:SetInflictor(IsValid(dmg:GetInflictor()) and dmg:GetInflictor() or att)
        fwd:SetDamagePosition(dmg:GetDamagePosition())
        fwd:SetDamageForce(dmg:GetDamageForce())
        ply.rhylibHitGroup = L.HitGroup(ent, dmg:GetDamagePosition())
        ply.rhylibFwd = true
        ply:TakeDamageInfo(fwd)
        ply.rhylibFwd = nil
        ply.rhylibHitGroup = nil
    end
    return true   -- the ragdoll itself takes nothing
end, -300)

-- A lying player is only hurt through the ragdoll (rhylibFwd: forwarded,
-- or a bolt that hit it). Direct hits on the hidden pose and the second
-- half of a blast are dropped; bleeding out (DMG_DIRECT) and the world
-- (falls) still count.
Rhylib.Hook.Add("EntityTakeDamage", "core.lying.direct", function(ent, dmg)
    if not ent:IsPlayer() or not L.active[ent] or ent.rhylibFwd then return end
    if dmg:IsDamageType(DMG_DIRECT) then return end
    local att = dmg:GetAttacker()
    if IsValid(att) and (att:IsPlayer() or att:IsNPC() or att:IsNextBot()) then return true end
end, -350)

-- Nobody carries the bodies around with tools.
Rhylib.Hook.Add("PhysgunPickup", "core.lying", function(ply, ent)
    if ent.rhylibOwner then return false end
end)
Rhylib.Hook.Add("CanTool", "core.lying", function(ply, tr)
    if IsValid(tr.Entity) and tr.Entity.rhylibOwner then return false end
end)
Rhylib.Hook.Add("GravGunPickupAllowed", "core.lying", function(ply, ent)
    if ent.rhylibOwner then return false end
end)
Rhylib.Hook.Add("CanProperty", "core.lying", function(ply, prop, ent)
    if IsValid(ent) and ent.rhylibOwner then return false end
end)
