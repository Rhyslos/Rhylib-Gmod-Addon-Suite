--[[
    Grapple hook: shared settings, rope maths and climbing (predicted).

    The grapple hook is an inventory item. While you carry one, the DC-15S,
    DC-15A and DC-17 (SWEP.Grapple = true) get a "GRAPPLE" fire mode on
    E + R. Firing it shoots the hook as a projectile (straight line,
    hookSpeed, max `range`). Where it grips, a rope is worked out once on
    the server and lowered down the surface at lowerSpeed. It stays until
    someone picks the hook up again (E on the hook). A hook that doesn't
    grip (or flies out of range) drops where it ended up, to be picked up.

    What the hook grips (G.CanGrip): map geometry, and anything that won't
    move: map props, brush entities, frozen props. Not players, NPCs,
    vehicles, weapons, loose physics props or the sky. If what it gripped
    is removed, the rope goes and the hook drops.

    The rope is one static entity (rhylib_rope) with its points in network
    vars: no physics, no Think, nothing sent after it's created. Players
    who come near later get it from the engine like any other entity.

    Climbing (anyone, up to maxClimbers per rope):
      E near the rope   clip on at the belt
      W / S             climb up / down (you can look around and shoot)
      Jump              let go, with a small push away from the wall
      E                 unclip
      Top               keep pushing W: if there's a ledge you're pulled
                        over it, otherwise you hang at the top
      Bottom            walk down until your feet touch the ground

    Movement runs in SetupMove on server and client with a fixed speed and
    no springs, so it's predicted and can't bounce. Player state:
        DTEntity 31  the rope you're on (NULL = not climbing)
        DTFloat 27   how far down the climbing part of the rope you are
        DTBool 27    being pulled over the top ledge

    Realm: shared. Config module "grapple" below. Files: this one (maths,
    climbing), sv_30_grapple.lua (firing, laying the rope),
    cl_40_grapple.lua (landing marker, belt line), entities/rhylib_rope.lua.
]]

local W = Rhylib.Weapons
W.Grapple = W.Grapple or {}
local G = W.Grapple

G.ITEM = "grapple"          -- inventory item id (and pouch kind)
G.AMMO = "rhylib_grapple"   -- ammo type mirroring how many hooks you carry (client checks)
G.MAX_POINTS = 16  -- must match the network vars in rhylib_rope.lua
G.DT_ROPE = 31
G.DT_S = 27
G.DT_MANTLE = 27
G.ropes = G.ropes or {}  -- [rope entity] = true, on server and client

local Config = Rhylib.Config
Config.Register("grapple", "range", 1500, "Max distance the hook flies (units, about 30 m)")
Config.Register("grapple", "ropeMax", 2500, "Max rope length down from the hook (units)")
Config.Register("grapple", "climbUp", 140, "Climbing speed up the rope (units/s)")
Config.Register("grapple", "climbDown", 220, "Climbing speed down the rope (units/s)")
Config.Register("grapple", "maxClimbers", 3, "Players on one rope at once")
Config.Register("grapple", "maxRopes", 64, "Ropes on the map at once; new hooks won't grip past this")
Config.Register("grapple", "attachDist", 56, "How close to the rope you must be to clip on (units)")
Config.Register("grapple", "cooldown", 1, "Seconds between grapple shots")
Config.Register("grapple", "showLanding", true, "Show where the hook will land while in grapple mode (false = troopers judge it themselves)")
Config.Register("grapple", "hookSpeed", 2500, "How fast the hook flies (units/s)")
Config.Register("grapple", "lowerSpeed", 450, "How fast the rope lowers after the hook grips (units/s)")

local WALL_OFFSET = 18   -- climber's centre this far from the wall (hull half width + a bit)
local BELT = 38          -- belt height above the feet, where the rope attaches
local UP = Vector(0, 0, 1)
local gravityVar = GetConVar("sv_gravity")

local function cfg(key)
    return Config.Get("grapple", key)
end

game.AddAmmoType({ name = G.AMMO, dmgtype = DMG_GENERIC, tracer = TRACER_NONE, plydmg = 0, npcdmg = 0, force = 0, maxcarry = 9999 })
if CLIENT then language.Add(G.AMMO .. "_ammo", "Grapple hooks") end

if Rhylib.Items then
    Rhylib.Items.Register(G.ITEM, {
        name = "Grapple hook",
        w = 2, h = 1,
        stack = 1,
        weight = 1.2,
        category = "gear",
        model = "models/props_junk/meathook001a.mdl",  -- placeholder
    })
end

--------------------------------------------------------------------------
-- What the hook can grip. The server can see whether a prop is frozen;
-- the client can't, so its landing marker is hopeful about props.
--------------------------------------------------------------------------

-- G.CanGrip(tr): true if a trace result is somewhere the hook can grip.
function G.CanGrip(tr)
    if not tr.Hit or tr.HitSky then return false end
    if tr.HitWorld then return true end
    local ent = tr.Entity
    if not IsValid(ent) then return false end
    if ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or ent:IsVehicle() or ent:IsWeapon() then return false end
    if ent:GetClass() == "rhylib_rope" or ent:GetClass() == "rhylib_world_item" then return false end
    if SERVER and ent:GetMoveType() == MOVETYPE_VPHYSICS then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) and phys:IsMotionEnabled() then return false end  -- loose prop
    end
    return true
end

--------------------------------------------------------------------------
-- Rope maths. A rope's data (from rhylib_rope:GetRopeData):
--   pts[i]  points from the hook down, nrm[i] wall normal of segment i
--   (nil = hangs free), top = index where climbing starts (the edge for
--   hooks on a rooftop), cum[i] = distance from top to pts[i], len.
--   all[i] = distance from the hook to pts[i], head = all[top],
--   total = all[n], born = when the rope started lowering.
--------------------------------------------------------------------------

-- Where the climber's belt sits relative to a rope segment: out from a
-- wall, or standing on a slope (feet on the surface).
local function beltOffset(n)
    if n.z > 0.3 then return UP * (BELT + 2) end
    return n * WALL_OFFSET
end

-- G.PosAt(d, s, offset): point on the climbing line at distance s from the
-- top (d = rope:GetRopeData()). offset = true moves it out from the wall to
-- where the climber's belt should be.
function G.PosAt(d, s, offset)
    local pts, cum = d.pts, d.cum
    for i = d.top, d.n - 1 do
        if s <= cum[i + 1] or i == d.n - 1 then
            local segLen = cum[i + 1] - cum[i]
            local f = segLen > 0 and math.Clamp((s - cum[i]) / segLen, 0, 1) or 0
            local p = pts[i] + (pts[i + 1] - pts[i]) * f
            if offset and d.nrm[i] then p = p + beltOffset(d.nrm[i]) end
            return p
        end
    end
    return pts[d.n]
end

-- How much of the rope has come down so far (from the hook).
function G.Lowered(d)
    return math.min(d.total, (CurTime() - d.born) * cfg("lowerSpeed"))
end

-- How far down the climbing part a climber can go right now.
function G.ClimbLimit(d)
    return math.Clamp(G.Lowered(d) - d.head, 0, d.len)
end

-- Closest distance along the rope to a world point, and how far away it is.
-- Only the part that has come down counts.
function G.ClosestS(d, point)
    local bestS, bestDist = 0, math.huge
    local pts, cum = d.pts, d.cum
    for i = d.top, d.n - 1 do
        local a, b = pts[i], pts[i + 1]
        local ab = b - a
        local lenSqr = ab:LengthSqr()
        local t = lenSqr > 0 and math.Clamp((point - a):Dot(ab) / lenSqr, 0, 1) or 0
        local q = a + ab * t
        if d.nrm[i] then q = q + beltOffset(d.nrm[i]) end
        local dist = q:Distance(point)
        if dist < bestDist then
            bestS, bestDist = cum[i] + (cum[i + 1] - cum[i]) * t, dist
        end
    end
    local limit = G.ClimbLimit(d)
    if bestS > limit then
        bestS = limit
        bestDist = G.PosAt(d, limit, true):Distance(point)
    end
    return bestS, bestDist
end

-- G.Climbers(rope, except): how many players are on this rope (not
-- counting except).
function G.Climbers(rope, except)
    local n = 0
    for _, p in ipairs(player.GetAll()) do
        if p ~= except and p:GetDTEntity(G.DT_ROPE) == rope then n = n + 1 end
    end
    return n
end

-- G.Attached(ply): true while ply is on a rope.
function G.Attached(ply)
    return IsValid(ply:GetDTEntity(G.DT_ROPE))
end

local function detach(ply, mv, push)
    ply:SetDTEntity(G.DT_ROPE, NULL)
    ply:SetDTBool(G.DT_MANTLE, false)
    if mv then
        local vel = push or Vector(0, 0, 0)
        mv:SetVelocity(vel)
    end
end
-- G.Detach(ply, mv, push): takes ply off the rope; with a move data mv
-- their velocity is set to push (or stopped). Used by rhylib_core's
-- knockdowns and rhylib_medical's downing.
G.Detach = detach

local function tryAttach(ply, mv)
    if next(G.ropes) == nil then return end
    local tr = ply:GetEyeTrace()
    local pelvis = mv:GetOrigin() + UP * BELT
    local best, bestS, bestDist
    for rope in pairs(G.ropes) do
        if IsValid(rope) and tr.Entity ~= rope then  -- looking at the hook = pick it up instead
            local d = rope:GetRopeData()
            if d and G.ClimbLimit(d) > 0 then
                local s, dist = G.ClosestS(d, pelvis)
                if dist < cfg("attachDist") and (not bestDist or dist < bestDist) then
                    best, bestS, bestDist = rope, s, dist
                end
            end
        end
    end
    if not best or G.Climbers(best, ply) >= cfg("maxClimbers") then return end
    ply:SetDTEntity(G.DT_ROPE, best)
    ply:SetDTFloat(G.DT_S, bestS)
    ply:SetDTBool(G.DT_MANTLE, false)
end

-- Climbing movement, server and client (predicted). E near a rope clips on.
Rhylib.Hook.Add("SetupMove", "weapons.grapple", function(ply, mv)
    local rope = ply:GetDTEntity(G.DT_ROPE)
    if not IsValid(rope) then
        -- (A rope that was picked up reads as NULL here too: you just drop.)
        if mv:KeyPressed(IN_USE) and ply:Alive() and ply:GetMoveType() == MOVETYPE_WALK then
            tryAttach(ply, mv)
        end
        return
    end

    local d = rope:GetRopeData()
    if not d or not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:InVehicle() then
        detach(ply)
        return
    end

    local s = ply:GetDTFloat(G.DT_S)
    local nrm = d.nrm[d.top]

    -- Getting off
    if mv:KeyPressed(IN_JUMP) then
        local wall = nrm or Vector(0, 0, 0)
        detach(ply, mv, wall * 140 + UP * 120)
        return
    end
    if mv:KeyPressed(IN_USE) then
        detach(ply, mv)
        return
    end

    local dt = FrameTime()
    local origin = mv:GetOrigin()
    local fm = mv:GetForwardSpeed()
    local mantle = ply:GetDTBool(G.DT_MANTLE)
    local vel

    if mantle then
        -- Over the top: straight up past the edge, then onto the ledge.
        local ledge = d.ledge
        if origin.z < ledge.z + 2 then
            vel = Vector(0, 0, 260)
        else
            local to = ledge - origin
            to.z = 0
            local dist = to:Length()
            if dist < 6 then
                detach(ply, mv)
                return
            end
            vel = to * (math.min(dist / dt, 220) / dist)
        end
    else
        if fm > 0 then
            s = s - cfg("climbUp") * dt
        elseif fm < 0 then
            s = s + cfg("climbDown") * dt
            if ply:OnGround() then  -- feet on the ground at the bottom
                detach(ply, mv)
                return
            end
        end
        s = math.Clamp(s, 0, G.ClimbLimit(d))  -- can't go below the end while it's still lowering
        if s <= 0 and fm > 0 and d.ledge then
            mantle = true
            ply:SetDTBool(G.DT_MANTLE, true)
        end

        -- Head for the belt point on the rope at a capped speed: no spring,
        -- so nothing overshoots or bounces.
        local target = G.PosAt(d, s, true) - UP * BELT
        vel = (target - origin) / dt
        local speed = vel:Length()
        if speed > 600 then vel = vel * (600 / speed) end
    end

    -- Cancel this tick's gravity, like the jetpack does.
    local g = gravityVar:GetFloat() * (ply:GetGravity() ~= 0 and ply:GetGravity() or 1)
    vel.z = vel.z + g * dt

    mv:SetVelocity(vel)
    mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_JUMP, IN_SPEED))))
    ply:SetDTFloat(G.DT_S, s)
end, -5)  -- before the jetpack and stamina, which leave climbers alone

-- Climbing animation: walk while moving on the rope, stand when still.
Rhylib.Hook.Add("CalcMainActivity", "weapons.grapple", function(ply, vel)
    if not IsValid(ply:GetDTEntity(G.DT_ROPE)) then return end
    return vel:LengthSqr() > 100 and ACT_MP_WALK or ACT_MP_STAND_IDLE, -1
end)

Rhylib.Hook.Add("UpdateAnimation", "weapons.grapple", function(ply, vel)
    if not IsValid(ply:GetDTEntity(G.DT_ROPE)) then return end
    -- Climbing is mostly vertical, which the default code reads as standing
    -- still; keep the legs walking instead.
    local moving = vel:LengthSqr() > 100
    ply:SetPoseParameter("move_x", moving and 1 or 0)
    ply:SetPoseParameter("move_y", 0)
    ply:SetPlaybackRate(moving and 1 or 0)
    return true
end)
