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

    Zipline mode: G.Fire(owner, wep, true) plants the near post under the
    shooter (G.ZipNear; refused off the ground before the hook is used),
    then where the hook lands G.ZipFar picks the far end (a wall-type grip,
    or with the Zipline rigger skill a post on the floor), G.ZipCheck wants
    zipMin length, no steeper than zipMaxAngle and a clear line, and a
    rhylib_zipline is made. Ropes and ziplines share maxRopes.

    Realm: server. Public: G.BuildRope, G.DropHook, G.Fire, G.ZipNear,
    G.ZipFar, G.ZipCheck. Listens to Rhylib.ForceRelease (lets go of the
    rope or zipline).
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
-- rope lost what it was hanging from). issued: the hook came from the
-- armoury (the dropped item stays issued, so it can't be laundered).
function G.DropHook(pos, issued)
    local inv = Rhylib.Inventory and Rhylib.Inventory.AddItem
    if inv and Rhylib.Inventory.MakeWorldRoom then Rhylib.Inventory.MakeWorldRoom() end
    local ent = ents.Create(inv and "rhylib_world_item" or "rhylib_item_grapple")
    if not IsValid(ent) then return end
    if ent.SetItem then ent:SetItem(G.ITEM, 1, issued and { issued = true } or {}) end
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
    if IsValid(ply) then Rhylib.Notify(ply, msg, "bad", "Grapple") end
end

-- How many ropes and ziplines are up (they share maxRopes).
local function lineCount()
    local n = 0
    for e in pairs(G.ropes) do if IsValid(e) then n = n + 1 end end
    for e in pairs(G.zips) do if IsValid(e) then n = n + 1 end end
    return n
end

-- The hook hit something.
local function onHookHit(bolt, t, issued)
    local hitPos, hitNormal, hitEnt = Vector(t.HitPos), Vector(t.HitNormal), t.Entity
    local owner = bolt.owner
    if not G.CanGrip(t) then
        tell(owner, "The hook couldn't grip that")
        G.DropHook(hitPos + hitNormal * 6, issued)
        return
    end

    local pts, nrm, top, ledge
    if lineCount() >= cfg("maxRopes") then
        nrm = "Too many ropes on the map"
    else
        pts, nrm, top, ledge = G.BuildRope(hitPos, hitNormal, bolt.dir)
    end
    if not pts then
        tell(owner, nrm)
        G.DropHook(hitPos + hitNormal * 6, issued)
        return
    end

    local rope = ents.Create("rhylib_rope")
    if not IsValid(rope) then
        G.DropHook(hitPos + hitNormal * 6, issued)
        return
    end
    rope.rhylibIssued = issued   -- (rhylib_rope drops the hook with it)
    rope:SetPos(hitPos)
    rope:SetAngles(hitNormal:Angle())
    rope:Spawn()
    rope:SetRope(pts, nrm, top, ledge)
    if IsValid(hitEnt) and not hitEnt:IsWorld() then rope:SetGripped(hitEnt) end
    rope:EmitSound("physics/metal/metal_box_impact_hard2.wav", 75)
end

-- The hook flew its full range without hitting anything.
local function onHookMiss(bolt, issued)
    tell(bolt.owner, "Out of range")
    G.DropHook(bolt.pos, issued)
end

-- Zipline -----------------------------------------------------------------

-- Firm ground a post can stand on: the map or a frozen prop (G.CanGrip),
-- facing up. Not people, NPCs, vehicles or loose props.
local function firmGround(t)
    return t.Hit and not t.StartSolid and t.HitNormal.z >= 0.7 and G.CanGrip(t)
end

-- The ground under pos (within depth), or nil.
local function groundBelow(pos, depth)
    local t = trace(pos, pos + DOWN * (depth or 96))
    if not firmGround(t) then return nil end
    return Vector(t.HitPos)
end

-- A post from foot up to its top: nothing in the way (a low ceiling).
local function postClear(foot)
    return not trace(foot + UP * 2, foot + UP * G.POST_H).Hit
end

-- G.ZipNear(ply): where the near post goes (on the ground under the
-- shooter) and the line's tie-on point on top of it, or nil + a message.
function G.ZipNear(ply)
    local foot = groundBelow(ply:GetPos() + UP * 8, 40)
    if not foot then return nil, nil, "Stand on solid ground to rig a zipline" end
    if not postClear(foot) then return nil, nil, "No room for the post here" end
    return foot, foot + UP * G.POST_H
end

-- G.ZipFar(t, ply): the far end for a hook that hit trace t: a hook in a
-- wall / ceiling / anything above the floor, or (Zipline rigger skill) a
-- post on the floor where it landed. Returns b, postB, hookNormal, or nil
-- + a message.
function G.ZipFar(t, ply)
    local n = Vector(t.HitNormal)
    local rigger = G.HasRigger(ply)
    if G.CanGrip(t) and n.z < 0.7 then
        return Vector(t.HitPos) + n * 3, false, n
    end
    if rigger and t.Hit and not t.HitSky then
        local ground = firmGround(t) and Vector(t.HitPos) or groundBelow(Vector(t.HitPos) + n * 4, 2000)
        if not ground then return nil, nil, nil, "No ground there for the far post" end
        if not postClear(ground) then return nil, nil, nil, "No room for the far post there" end
        return ground + UP * G.POST_H, true, UP
    end
    if G.CanGrip(t) then
        return nil, nil, nil, "The hook needs a wall or something above the floor (the Zipline rigger skill can plant it on the floor)"
    end
    return nil, nil, nil, "The hook couldn't grip that"
end

-- G.ZipCheck(a, b): can a line run from a to b? nil if fine, else why.
function G.ZipCheck(a, b)
    local len = a:Distance(b)
    if len < cfg("zipMin") then return "Too short for a zipline" end
    local deg = G.ZipSlope(a, b)
    if deg > cfg("zipMaxAngle") then return "Too steep for a zipline" end
    local dir = (b - a):GetNormalized()
    local t = trace(a + dir * 4, b - dir * 8)
    if t.Hit then return "Something is in the way of the line" end
    -- Room for a rider hanging under it, end stop to end stop.
    local m = G.ZipMargin(dir)
    if len <= m * 2 then return "Too short for a zipline" end
    local hang = UP * G.HANG
    htd.start, htd.endpos = a + dir * m - hang + UP * 2, b - dir * m - hang + UP * 2
    util.TraceHull(htd)
    if htr.Hit or htr.StartSolid then return "Not enough room under the line" end
    return nil
end

local function onZipHit(bolt, t, issued, foot, a)
    local owner = bolt.owner
    local hitPos, hitNormal, hitEnt = Vector(t.HitPos), Vector(t.HitNormal), t.Entity
    local b, postB, hookN, why = G.ZipFar(t, owner)
    if b and lineCount() >= cfg("maxRopes") then b, why = nil, "Too many ropes on the map" end
    if b then why = G.ZipCheck(a, b) end
    if not b or why then
        tell(owner, why or "The hook couldn't grip that")
        G.DropHook(hitPos + hitNormal * 6, issued)
        return
    end
    local zip = ents.Create("rhylib_zipline")
    if not IsValid(zip) then
        G.DropHook(hitPos + hitNormal * 6, issued)
        return
    end
    zip.rhylibIssued = issued   -- (picked up again as the same kind of hook)
    zip:SetPos(foot)
    zip:Spawn()
    zip:SetZip(a, b, postB, hookN)
    if not postB and IsValid(hitEnt) and not hitEnt:IsWorld() then zip:SetGripped(hitEnt) end
    zip:EmitSound("physics/metal/metal_box_impact_hard2.wav", 75)
    if IsValid(owner) then
        local _, twoWay = G.ZipSlope(a, b)
        Rhylib.Notify(owner, twoWay and "Zipline up: rides both ways" or "Zipline up: too steep to ride uphill, one way down", "good", "Grapple")
    end
end

-- G.Fire(owner, wep, zipline): fired from the weapon's grapple or
-- zipline fire mode (rhylib_base SWEP:FireGrapple). The hook leaves the
-- inventory now; it's a rope, a zipline or an item on the ground after
-- this. The hook flies as a bolt (Bolts.Fire with opts onHit / onExpire,
-- BoltColor 5), G.Range(owner) far.
function G.Fire(owner, wep, zipline)
    local foot, a
    if zipline then
        local why
        foot, a, why = G.ZipNear(owner)
        if not foot then
            tell(owner, why)
            return   -- (nothing taken: try again from the ground)
        end
    end
    local Pouch = W.Pouch
    local got, issued = Pouch.TakeBest(owner, G.ITEM)
    if not got then
        tell(owner, "No grapple hooks")
        wep:LeaveGrappleMode()
        return
    end

    local speed = cfg("hookSpeed")
    W.Bolts.Fire(owner, wep, owner:GetShootPos(), owner:GetAimVector(), 0, {
        speed = speed,
        color = 5,  -- the hook look in cl_10_bolts.lua
        life = G.Range(owner) / speed,
        onHit = zipline and function(b, t) return onZipHit(b, t, issued, foot, a) end
            or function(b, t) return onHookHit(b, t, issued) end,
        onExpire = function(b) return onHookMiss(b, issued) end,
    })

    -- One shot, then back to the normal fire mode.
    wep:LeaveGrappleMode()
end

-- Hook Rhylib.ForceRelease(ply, why) (rhylib_core knock, and anything else
-- that throws a player about): let go of the rope.
Rhylib.Hook.Add("Rhylib.ForceRelease", "weapons.grapple", function(ply)
    if IsValid(ply) and G.Attached(ply) then G.Detach(ply) end
    if IsValid(ply) and G.ZipOn(ply) then G.ZipDetach(ply) end
end)
