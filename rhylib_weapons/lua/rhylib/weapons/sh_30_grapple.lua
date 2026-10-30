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

    Zipline mode (the second grapple fire mode): see "Zipline mode" below.

    Realm: shared. Config module "grapple" below. Files: this one (maths,
    climbing, zipline riding), sv_30_grapple.lua (firing, laying the rope,
    rigging ziplines), cl_40_grapple.lua (landing marker, belt line),
    entities/rhylib_rope.lua, entities/rhylib_zipline.lua.
]]

local W = Rhylib.Weapons
W.Grapple = W.Grapple or {}
local G = W.Grapple

G.ITEM = "grapple"          -- inventory item id (and pouch kind)
G.AMMO = "rhylib_grapple"   -- ammo type mirroring how many hooks you carry (client checks)
G.MAX_POINTS = 16  -- must match the network vars in rhylib_rope.lua
-- Player DT slots, claimed through the core registry (rhylib_core sh_05_dt.lua).
local DT = Rhylib.DT
G.DT_ROPE = DT and DT.Claim("Entity", "grapple.rope", 31) or 31     -- the rope you're on
G.DT_S = DT and DT.Claim("Float", "grapple.s", 27) or 27            -- where along it
G.DT_MANTLE = DT and DT.Claim("Bool", "grapple.mantle", 27) or 27   -- climbing over the top
G.ropes = G.ropes or {}  -- [rope entity] = true, on server and client
G.zips = G.zips or {}    -- [zipline entity] = true, on server and client
G.DT_ZIP = DT and DT.Claim("Entity", "grapple.zip", 30) or 30     -- the zipline you hang from
G.DT_ZIPV = DT and DT.Claim("Float", "grapple.zipv", 22) or 22    -- your speed along it (+ = toward the far end)
-- (where along the zipline uses DT_S: you're never on a rope and a zipline at once)
G.SKILL = "zip_rigger"   -- Autorifleman skill: free far end + skillRange on both modes
G.ZIP_SPEC = "autorifleman"   -- only this skill specialisation gets the zipline mode
G.POST_H = 84            -- a post's top (where the line ties on) above the ground
G.HANG = 80              -- a rider's feet hang this far below the line

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
Config.Register("grapple", "skillRange", 862, "Zipline rigger skill (Autorifleman): extra hook range on both modes (units; 862 makes the default range about 45 m)")
-- Zipline mode
Config.Register("grapple", "zipMin", 150, "Zipline: shortest line (units)")
Config.Register("grapple", "zipTwoWayAngle", 5, "Zipline: steepest slope you can still ride uphill (degrees); steeper lines only take you down")
Config.Register("grapple", "zipMaxAngle", 60, "Zipline: steepest line it will rig at all (degrees)")
Config.Register("grapple", "zipAccel", 260, "Zipline: how hard W / S push you along (units/s²)")
Config.Register("grapple", "zipGravity", 0.5, "Zipline: how much the slope speeds you up downhill (1 = full gravity along the line)")
Config.Register("grapple", "zipDrag", 0.7, "Zipline: drag (share of your speed lost per second)")
Config.Register("grapple", "zipMaxSpeed", 475, "Zipline: top speed (units/s)")
Config.Register("grapple", "zipMaxRiders", 4, "Zipline: players on one line at once")
Config.Register("grapple", "zipAttachDist", 52, "Zipline: how close your hands must be to the line to grab on (units)")
Config.Register("grapple", "hitsToFall", 2, "Hits that knock a player off a rope, zipline or personal hook (0 = never)")
Config.Register("grapple", "hitsWindow", 5, "Seconds within which those hits must land (a longer gap starts the count again)")
Config.Register("grapple", "zipPostModel", "", "Zipline post model (empty = a plain drawn pole)", { name = "Zipline post", group = "Grapple" })

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
    local cls = ent:GetClass()
    if cls == "rhylib_rope" or cls == "rhylib_zipline" or cls == "rhylib_zipline_end" or cls == "rhylib_world_item" then return false end
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
    if SERVER then ply.rhylibLineHits = nil end
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

--------------------------------------------------------------------------
-- Zipline mode
--
-- The zipline fire mode (after GRAPPLE on E + R, Autorifleman skill
-- specialisation only: G.CanZip) shoots the hook the same way, but strings
-- a straight line from a post planted where you stand to where the hook
-- grips (a wall, a ceiling, anything above the floor). The hook is used up:
-- a line can't be taken down for the hook again. It stays until it's shot
-- (either post or the far hook), what it gripped goes, its rigger leaves
-- the server, staff remove it, or the map changes. With the Zipline rigger
-- skill the far end can be anywhere: a hook on the floor plants a second
-- post there, and both modes reach skillRange further. Riding (anyone, up
-- to zipMaxRiders a line):
--   E near the line     grab on (your hands at the line, feet hanging)
--   W / S               slide the way you look / the other way
--   Jump / E            let go (Jump keeps your speed)
-- Lines flatter than zipTwoWayAngle ride both ways; steeper ones only take
-- you down (you can't push uphill and the slope pulls you down). Gravity
-- along the line speeds you up downhill, drag slows you, zipMaxSpeed caps
-- it; you stop at either end, or where something blocks your body. Taking
-- hitsToFall hits on a rope or a line knocks you off (sv_30_grapple.lua).
-- Predicted in SetupMove like climbing.
-- Player state: DTEntity G.DT_ZIP (the line), DTFloat G.DT_S (distance
-- from the near post), DTFloat G.DT_ZIPV (speed along it).
--------------------------------------------------------------------------

-- G.Range(ply): how far ply's hook flies (range, + skillRange with the skill).
function G.Range(ply)
    local r = cfg("range")
    if G.HasRigger(ply) then r = r + (cfg("skillRange") or 0) end
    return r
end

-- G.HasRigger(ply): has the Zipline rigger skill (rhylib_skills).
function G.HasRigger(ply)
    local K = Rhylib.Skills
    return IsValid(ply) and K ~= nil and K.Has ~= nil and K.Has(ply, G.SKILL) or false
end

-- G.CanZip(ply): may use the zipline fire mode: an Autorifleman (any skill
-- of that specialisation, not borrowed). Without rhylib_skills: anyone.
function G.CanZip(ply)
    local K = Rhylib.Skills
    if not (K and K.Set and K.byId) then return true end
    if not IsValid(ply) then return false end
    local set = K.Set(ply)
    for id in pairs(set) do
        local n = K.byId[id]
        if n and n.spec == G.ZIP_SPEC and not (K.Borrowed and K.Borrowed(set, id)) then return true end
    end
    return false
end

-- G.ZipSlope(a, b): the line's slope in degrees (0 = level) and whether
-- it rides both ways (at or under zipTwoWayAngle).
function G.ZipSlope(a, b)
    local dir = b - a
    local len = dir:Length()
    if len < 1 then return 0, true end
    local deg = math.deg(math.asin(math.Clamp(math.abs(dir.z) / len, 0, 1)))
    return deg, deg <= cfg("zipTwoWayAngle")
end

-- G.ZipOn(ply): the zipline ply hangs from, or nil.
function G.ZipOn(ply)
    local z = ply:GetDTEntity(G.DT_ZIP)
    return IsValid(z) and z or nil
end

-- G.ZipRiders(zip, except): how many players hang from this zipline.
function G.ZipRiders(zip, except)
    local n = 0
    for _, p in ipairs(player.GetAll()) do
        if p ~= except and p:GetDTEntity(G.DT_ZIP) == zip then n = n + 1 end
    end
    return n
end

local function zipDetach(ply, mv, vel)
    if SERVER then
        ply.rhylibLineHits = nil
        ply.rhylibZipLeft = CurTime() + 0.5   -- (no fall damage just after: sv_30_grapple)
    end
    ply:SetDTEntity(G.DT_ZIP, NULL)
    ply:SetDTFloat(G.DT_ZIPV, 0)
    if mv then mv:SetVelocity(vel or Vector(0, 0, 0)) end
end
-- G.ZipDetach(ply, mv, vel): lets go of the zipline (knockdowns, downing).
G.ZipDetach = zipDetach

-- Where the near post may go: just behind the shooter (clear of their
-- body, so their own shots don't start inside it), else to their left or
-- right. G.ZipSpots(ply) -> list of positions to try, in order.
G.POST_OFF = 30
function G.ZipSpots(ply)
    local pos = ply:GetPos()
    local f = ply:GetAimVector()
    f.z = 0
    if f:LengthSqr() < 0.0001 then f = Vector(1, 0, 0) end
    f:Normalize()
    local r = Vector(f.y, -f.x, 0)
    local o = G.POST_OFF
    return { pos - f * o, pos - r * o, pos + r * o }
end

-- G.ZipGround(ply): the ground the near post would stand on (client marker
-- and the hook visual; the server's G.ZipNear also checks room for the
-- post), or nil.
local zgtr = {}
local zgtd = { output = zgtr, mask = MASK_PLAYERSOLID }
function G.ZipGround(ply)
    for _, pos in ipairs(G.ZipSpots(ply)) do
        zgtd.start, zgtd.endpos, zgtd.filter = pos + UP * 8, pos - UP * 32, ply
        util.TraceLine(zgtd)
        if zgtr.Hit and not zgtr.StartSolid and zgtr.HitNormal.z >= 0.7 and G.CanGrip(zgtr) then
            return zgtr.HitPos
        end
    end
    return nil
end

-- G.ZipMargin(dir): how far from each end riders stop: 20 units out from
-- a wall or post sideways, so more along steep lines.
function G.ZipMargin(dir)
    local horiz = math.sqrt(math.max(0, 1 - dir.z * dir.z))
    return 20 / math.max(0.3, horiz)
end

-- G.ZipHang(pt, ply): how far below the line point pt a rider's feet
-- hang: G.HANG, or less where the ground is closer (a ledge the line
-- leaves from, a slope under it), so the body glides over it instead of
-- catching on it. One hull trace (players and ziplines skipped), the same
-- on both realms (predicted).
local hangTr = {}
local hangTd = { output = hangTr, mask = MASK_PLAYERSOLID, mins = Vector(-14, -14, 0), maxs = Vector(14, 14, 70),
    filter = function(e)
        if e:IsPlayer() then return false end
        local c = e:GetClass()
        return c ~= "rhylib_zipline" and c ~= "rhylib_zipline_end"
    end }
local HANG_MIN = 20   -- (over a ledge the rider holds the line at the chest, then drops to G.HANG past the edge)
function G.ZipHang(pt)
    hangTd.start, hangTd.endpos = pt - UP * HANG_MIN, pt - UP * G.HANG
    util.TraceHull(hangTd)
    if hangTr.StartSolid or not hangTr.Hit then return G.HANG end
    return math.max(HANG_MIN, pt.z - hangTr.HitPos.z - 4)   -- (feet just clear of the ground: no friction)
end

-- E near a zipline: grab on where your hands are closest to it.
local function tryZip(ply, mv)
    if next(G.zips) == nil then return false end
    local hands = mv:GetOrigin() + UP * G.HANG
    local best, bestS, bestDist
    for z in pairs(G.zips) do
        if IsValid(z) then
            local d = z:GetZipData()
            if d then
                local t = math.Clamp((hands - d.a):Dot(d.dir), d.margin, d.len - d.margin)
                local dist = (d.a + d.dir * t):Distance(hands)
                if dist < cfg("zipAttachDist") and (not bestDist or dist < bestDist) then
                    best, bestS, bestDist = z, t, dist
                end
            end
        end
    end
    if not best or G.ZipRiders(best, ply) >= cfg("zipMaxRiders") then return false end
    ply:SetDTEntity(G.DT_ZIP, best)
    ply:SetDTFloat(G.DT_S, bestS)
    ply:SetDTFloat(G.DT_ZIPV, 0)
    return true
end

local function rideZip(ply, mv, zip)
    local d = zip:GetZipData()
    if not d or not ply:Alive() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:InVehicle() then
        zipDetach(ply)
        return
    end
    local s, v = ply:GetDTFloat(G.DT_S), ply:GetDTFloat(G.DT_ZIPV)
    local dir = d.dir
    -- Where the body really is along the line: something in the way (another
    -- rider) holds you there instead of the line running on without you.
    local origin = mv:GetOrigin()
    -- (measured flat, so how far below the line you hang doesn't matter;
    -- lines are never steeper than zipMaxAngle, so horiz is never tiny)
    local off = origin - d.a
    local horiz = math.max(0.3, math.sqrt(dir.x * dir.x + dir.y * dir.y))
    local real = (off.x * dir.x + off.y * dir.y) / (horiz * horiz)
    if math.abs(real - s) > 12 then s, v = real, 0 end

    if mv:KeyPressed(IN_JUMP) then
        zipDetach(ply, mv, dir * v + UP * 160)
        return
    end
    if mv:KeyPressed(IN_USE) then
        zipDetach(ply, mv, dir * v)
        return
    end

    local dt = FrameTime()
    local g = gravityVar:GetFloat() * (ply:GetGravity() ~= 0 and ply:GetGravity() or 1)

    -- W / S along the line, the way you look (S the other way).
    local fm = mv:GetForwardSpeed()
    local push = 0
    if fm ~= 0 then
        local look = mv:GetAngles():Forward():Dot(dir) >= 0 and 1 or -1
        push = (fm > 0 and 1 or -1) * look
    end
    -- One-way lines: no pushing uphill. Uphill is toward the far end when it's higher.
    local uphill = dir.z > 0 and 1 or -1
    if not d.twoWay and push == uphill then push = 0 end
    local a = push * cfg("zipAccel") - dir.z * g * cfg("zipGravity")
    v = v + a * dt
    v = v - v * math.min(1, cfg("zipDrag") * dt)
    local top = cfg("zipMaxSpeed")
    v = math.Clamp(v, -top, top)
    s = s + v * dt
    local m = d.margin
    if s <= m then s, v = m, math.max(v, 0) end
    if s >= d.len - m then s, v = d.len - m, math.min(v, 0) end

    -- Head for the hanging point at a capped speed (no spring, like climbing).
    local linePt = d.a + dir * s
    local target = linePt - UP * G.ZipHang(linePt)
    if origin:DistToSqr(target) > 96 * 96 then   -- (something blocked you: let go)
        zipDetach(ply, mv)
        return
    end
    local vel = (target - origin) / dt
    local speed = vel:Length()
    if speed > 1600 then vel = vel * (1600 / speed) end
    -- Dropping to full hang past a ledge eases down (never much faster than
    -- the line itself goes down), so landing isn't a deadly fall.
    vel.z = math.max(vel.z, math.min(0, dir.z * v) - 250)
    -- (pulled up off the ground: let go of it, or the engine keeps you on it)
    if vel.z > 0 and ply:OnGround() then ply:SetGroundEntity(NULL) end
    vel.z = vel.z + g * dt   -- cancel this tick's gravity

    mv:SetVelocity(vel)
    mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_JUMP, IN_SPEED, IN_DUCK))))
    ply:SetDTFloat(G.DT_S, s)
    ply:SetDTFloat(G.DT_ZIPV, v)
end

-- Climbing movement, server and client (predicted). E near a rope clips
-- on (or near a zipline grabs it); riding a zipline is handled here too.
Rhylib.Hook.Add("SetupMove", "weapons.grapple", function(ply, mv)
    local zip = ply:GetDTEntity(G.DT_ZIP)
    if IsValid(zip) then
        rideZip(ply, mv, zip)
        return
    elseif ply:GetDTFloat(G.DT_ZIPV) ~= 0 then
        ply:SetDTFloat(G.DT_ZIPV, 0)   -- (the line went under you: you just drop)
    end
    local rope = ply:GetDTEntity(G.DT_ROPE)
    if not IsValid(rope) then
        -- (A rope that was picked up reads as NULL here too: you just drop.)
        if mv:KeyPressed(IN_USE) and ply:Alive() and ply:GetMoveType() == MOVETYPE_WALK then
            tryAttach(ply, mv)
            if not IsValid(ply:GetDTEntity(G.DT_ROPE)) then tryZip(ply, mv) end
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
-- Hanging from a zipline: the jump pose (legs off the ground).
Rhylib.Hook.Add("CalcMainActivity", "weapons.grapple", function(ply, vel)
    if IsValid(ply:GetDTEntity(G.DT_ZIP)) then return ACT_MP_JUMP, -1 end
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
