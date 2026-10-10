--[[
    Grapple hook, server side: firing the hook and laying the rope.

    The hook flies as a bolt (sv_10_bolts.lua) with its own hit handling.
    Where it grips, the rope is laid; if it can't grip or runs out of
    range, the hook drops there as an item to be picked up.

    The rope is worked out once, when the hook grips, with a handful of
    traces (about 10 to 40, depending on the shape of the surface):
      - Hook on top of something (a roof): walk back toward the shooter to
        find the edge, then hang the rope over it. The roof behind the
        edge becomes the ledge climbers are pulled onto.
      - Hook on a wall: hang from there. If the hook is just below the top
        of the wall and there's room to stand up there, that's the ledge.
      - Hook on a ceiling: hang straight down.
    Then the rope drops, sliding down any slope it lands on (walkable or
    not), until the ground is nearly flat or it runs out of length or points.

    Realm: server. Public: G.BuildRope, G.DropHook, G.Fire.
]]

local W = Rhylib.Weapons
local G = W.Grapple
local Config = Rhylib.Config

local UP = Vector(0, 0, 1)
local FLAT = 0.95  -- surface normal z at or above this = flat ground (under about 18 degrees): the rope stops
local DOWN = Vector(0, 0, -1)
local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 72)

local function cfg(key)
    return Config.Get("grapple", key)
end

-- The rope lies on the map and on anything solid that isn't a person.
local function notPeople(ent)
    return not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or ent:IsWeapon())
end

local tr = {}
local td = { output = tr, mask = MASK_PLAYERSOLID, filter = notPeople }
local function trace(a, b)
    td.start, td.endpos = a, b
    util.TraceLine(td)
    return tr
end

local htr = {}
local htd = { output = htr, mask = MASK_PLAYERSOLID, mins = HULL_MIN, maxs = HULL_MAX, filter = notPeople }
-- Is there room for a standing player with their feet at pos?
local function roomToStand(pos)
    htd.start, htd.endpos = pos + UP * 2, pos + UP * 2
    util.TraceHull(htd)
    return not htr.StartSolid and not htr.Hit
end

local function flat(v)
    local f = Vector(v.x, v.y, 0)
    if f:LengthSqr() < 0.0001 then return nil end
    f:Normalize()
    return f
end

-- Is a wall close behind this point (in direction -n)? Decides whether a
-- rope segment lies against the wall or hangs free.
local function wallBehind(p, n)
    return trace(p, p - n * 28).Hit
end

-- G.BuildRope(hitPos, hitNormal, shootDir): works out a rope for a hook
-- that gripped at hitPos. Returns pts, nrm, top, ledge (see rhylib_rope
-- ENT:SetRope); or nil and a message for the shooter.
function G.BuildRope(hitPos, hitNormal, shootDir)
    local pts, nrm = {}, {}
    local top, ledge = 1, nil
    local cur, wallN

    if hitNormal.z >= FLAT then
        -- On top of something flat: find the edge back toward the shooter.
        local back = flat(-shootDir)
        if not back then return nil, "No edge to hang the rope from" end
        local edge
        for step = 8, 256, 8 do
            local q = hitPos + back * step + UP * 4
            if trace(q - back * 8, q).Hit then break end               -- a wall in the way
            if not trace(q, q + DOWN * 24).Hit then edge = hitPos + back * (step - 8) break end
        end
        if not edge then return nil, "No edge to hang the rope from" end

        pts[1], nrm[1] = hitPos + hitNormal * 2, UP
        pts[2] = edge + UP * 2
        top = 2
        local stand = edge - back * 24
        if roomToStand(stand) then ledge = stand end
        cur, wallN = edge + back * 4, back
    elseif hitNormal.z < -0.7 then
        -- Ceiling or overhang: hang straight down.
        pts[1] = hitPos + hitNormal * 2
        cur, wallN = pts[1], nil
    else
        -- Wall or slope: hang from the hook (the drop below slides down a
        -- slope), and look for a ledge just above it.
        wallN = flat(hitNormal)
        if not wallN then return nil, "The hook couldn't grip there" end
        pts[1] = hitPos + wallN * 3
        cur = pts[1]
        local over = hitPos - wallN * 24 + UP * 80
        local down = trace(over, over + DOWN * 100)
        if down.Hit and not down.StartSolid and down.HitNormal.z > 0.7 and down.HitPos.z >= hitPos.z - 8 then
            local stand = down.HitPos + UP * 2
            if roomToStand(stand) then ledge = stand end
        end
    end

    -- Drop the rope.
    local remaining = cfg("ropeMax")
    while #pts < G.MAX_POINTS and remaining > 8 do
        local t = trace(cur, cur + DOWN * remaining)
        local didHit = t.Hit  -- copy: the next trace reuses the result table
        local hit = Vector(t.HitPos)
        local hitN = Vector(t.HitNormal)
        remaining = remaining - cur:Distance(hit)

        -- The segment from the last point down to here.
        local mid = (pts[#pts] + hit) * 0.5
        nrm[#pts] = (wallN and wallBehind(mid, wallN)) and wallN or nil

        if not didHit or hitN.z >= FLAT then
            -- Dangling in the air, or down on flat ground.
            pts[#pts + 1] = didHit and hit + UP * 2 or hit
            break
        end

        -- A slope: follow it downhill.
        local p = hit + hitN * 3
        pts[#pts + 1] = p
        if #pts >= G.MAX_POINTS then break end
        local slide = DOWN - hitN * DOWN:Dot(hitN)
        if slide:LengthSqr() < 0.0001 then break end
        slide:Normalize()
        local s = trace(p, p + slide * math.min(remaining, 400))
        local sHit, sGround = s.Hit, s.Hit and s.HitNormal.z >= FLAT
        local sEnd = s.HitPos + (sHit and s.HitNormal * 3 or Vector(0, 0, 0))
        remaining = remaining - p:Distance(sEnd)
        nrm[#pts] = hitN
        pts[#pts + 1] = sEnd
        wallN = flat(hitN) or wallN
        cur = sEnd
        if sGround then break end
    end

    if #pts < 2 then return nil, "The hook couldn't grip there" end
    -- Too short to be worth climbing.
    local len = 0
    for i = top, #pts - 1 do len = len + pts[i]:Distance(pts[i + 1]) end
    if len < 40 then return nil, "Too close to the ground for a rope" end
    return pts, nrm, top, ledge
end

-- Drops a grapple hook item at pos (a hook that didn't grip, or whose
-- rope lost what it was hanging from).
function G.DropHook(pos)
    local inv = Rhylib.Inventory and Rhylib.Inventory.AddItem
    if inv and Rhylib.Inventory.MakeWorldRoom then Rhylib.Inventory.MakeWorldRoom() end
    local ent = ents.Create(inv and "rhylib_world_item" or "rhylib_item_grapple")
    if not IsValid(ent) then return end
    if ent.SetItem then ent:SetItem(G.ITEM, 1, {}) end
    ent:SetPos(pos)
    ent:Spawn()
    -- Counts toward the inventory's cap on dropped items; without the
    -- inventory it just goes away after a while.
    local list = Rhylib.Inventory and Rhylib.Inventory.worldItems
    if inv and list then
        list[#list + 1] = ent
    else
        SafeRemoveEntityDelayed(ent, 300)
    end
end

local function tell(ply, msg)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCENTER, msg) end
end

-- The hook hit something.
local function onHookHit(bolt, t)
    local hitPos, hitNormal, hitEnt = Vector(t.HitPos), Vector(t.HitNormal), t.Entity
    local owner = bolt.owner
    if not G.CanGrip(t) then
        tell(owner, "The hook couldn't grip that")
        G.DropHook(hitPos + hitNormal * 6)
        return
    end

    local count = 0
    for rope in pairs(G.ropes) do
        if IsValid(rope) then count = count + 1 end
    end
    local pts, nrm, top, ledge
    if count >= cfg("maxRopes") then
        nrm = "Too many ropes on the map"
    else
        pts, nrm, top, ledge = G.BuildRope(hitPos, hitNormal, bolt.dir)
    end
    if not pts then
        tell(owner, nrm)
        G.DropHook(hitPos + hitNormal * 6)
        return
    end

    local rope = ents.Create("rhylib_rope")
    if not IsValid(rope) then
        G.DropHook(hitPos + hitNormal * 6)
        return
    end
    rope:SetPos(hitPos)
    rope:SetAngles(hitNormal:Angle())
    rope:Spawn()
    rope:SetRope(pts, nrm, top, ledge)
    if IsValid(hitEnt) and not hitEnt:IsWorld() then rope:SetGripped(hitEnt) end
    rope:EmitSound("physics/metal/metal_box_impact_hard2.wav", 75)
end

-- The hook flew its full range without hitting anything.
local function onHookMiss(bolt)
    tell(bolt.owner, "Out of range")
    G.DropHook(bolt.pos)
end

-- G.Fire(owner, wep): fired from the weapon's grapple fire mode
-- (rhylib_base SWEP:FireGrapple). The hook leaves the inventory now; it's
-- either a rope or an item on the ground after this. The hook flies as a
-- bolt (Bolts.Fire with opts onHit / onExpire, BoltColor 5).
function G.Fire(owner, wep)
    local Pouch = W.Pouch
    if not Pouch.TakeBest(owner, G.ITEM) then
        tell(owner, "No grapple hooks")
        wep:LeaveGrappleMode()
        return
    end

    local speed = cfg("hookSpeed")
    W.Bolts.Fire(owner, wep, owner:GetShootPos(), owner:GetAimVector(), 0, {
        speed = speed,
        color = 5,  -- the hook look in cl_10_bolts.lua
        life = cfg("range") / speed,
        onHit = onHookHit,
        onExpire = onHookMiss,
    })

    -- One shot, then back to the normal fire mode.
    wep:LeaveGrappleMode()
end
