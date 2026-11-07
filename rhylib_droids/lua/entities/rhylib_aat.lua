--[[
    AAT droid tank: the droid brain (rhylib_b1) with the "aat" row of
    Rhylib.Droids.KINDS, as a repulsor hover tank. Modes, orders,
    aggression, Command mode, stealth and calls for help are the shared
    brain's; it is never put in a squad (kind.noSquad) and clones count it
    as aatOdds droids (kind.weight).

    Model: aatModel (models/starwarsbattlefrontii/vehicles/aat.mdl, skin
    aatSkin; missing: D.AAT_FALLBACK, the HL2 APC prop). In game the
    model's front is the entity's forward as it is (aatYawOffset 0); its
    root bone is turned by aatYawOffset (fallback: aatFallbackYawOffset)
    if a model needs it.
    Bones turned on clients (ManipulateBoneAngles; which angle of the bone
    each uses: aatTurretAxis, aatBarrelAxis, aatSideYawAxis,
    aatSidePitchAxis): main_gun (turret, left / right), main_gun_part
    (barrel, up / down), gun_side_L / gun_side_R (side lasers, both).

    Moving: a square hull aatHullHalf x 2 wide, aatHullHeight tall. Routes
    are navmesh paths whose areas fit that hull (an area fits when the free
    span across it is 1.6 x aatHullHalf both ways; checked by a timer, at
    most 30 areas per 0.1 s within 4000 units of a tank, cached for the
    map; not yet checked: allowed at double cost; the goal's own area
    always; a goal with no route is not searched again for 8 s), no ladders, jumps,
    crouch areas or steps higher than its step height. Drives at aatSpeed
    (aatAccel), its hull turning at aatTurnRate; slower while it still
    points away from the way it goes. Stuck: backs off a little; stuck
    three times on one route: gives the route up (in a fight: holds its
    spot and fights for 8 s). In a fight it stops to
    fire (aggression 3 with the target in sight, a post or a defence),
    else drives up to aatStandoff from it (aggression 5: 60% of it);
    aggression 1-2 as for any droid (retreat, fallback point).

    Two variants (kind field aatRole): the tank ("aat") fires its cannon
    direct, side lasers and rocket barrages, never the mortar; the mortar
    tank ("aat_mortar", entities/rhylib_aat_mortar.lua) hangs back
    (aatMortarStandoff) and its cannon only lobs mortar shots (the B2
    mortar's purple rocket, rhylib_b2_rocket with r.damage / r.radius =
    aatCannonDamage / aatCannonRadius and r.life for long flights), at its
    target in sight too, with its side lasers for defence (ENT:AatIsMortar).

    Weapons (server, every NextBot body update, ENT:BodyUpdate):
      turret cannon   one shell (entities/rhylib_aat_shell.lua) every
                      aatCannonInterval s. The turret turns at
                      aatTurretRate (it keeps its aim while the hull turns)
                      and fires once it points within 2 degrees of the shot:
                        direct  at a target in sight further than
                                aatCannonMin and within the barrel's
                                angles (else lasers and rockets only):
                                the middle of its group
                                (enemies within aatClusterRadius), else it,
                                led by its speed; event targets their middle
                        mortar  a high arc (aatMortarPitch, at most
                                aatMortarMaxFlight s) at a target out of its
                                sight within aatMortarRange: where it lost
                                sight of its own target, or, while idle, one
                                another droid sees (D.SpottedTarget); shots
                                at the same target walk in (aatMortarSpread);
                                never under a low ceiling or into an EOD
                                Signal blackout
      side lasers     two guns, each with its own target (players and
                      clones in sight within aatLaserRange and its
                      aatLaserArc), turning at aatLaserTurn, firing droid
                      bolts at aatLaserRPM (aatLaserDamage,
                      aatLaserSpread)
      rocket barrage  aatRocketCount B2 rockets (rhylib_b2_rocket with
                      aatRocketDamage / aatRocketRadius) from the front
                      tubes (aatRocketFwd / Side / Up) at a group of at least
                      aatRocketCluster enemies within aatClusterRadius,
                      aatRocketMin-aatRocketMax away, in sight and in front;
                      then aatRocketCooldown s
    Unaware (stealth) and not alerted it fires nothing (no side lasers,
    no spotted-target mortar). Shots leave from where the guns are on the model, worked out from the
    turret and gun angles (model-space pivots below, aatCannonLength /
    aatLaserLength along the barrel). Commander boost and suppression
    change the aim like any droid's.

    Networked: DT floats AimYaw / AimPitch (where the turret is turning
    to, world yaw and barrel angle), LYaw / LPitch, RYaw / RPitch (the side
    guns), StunEnd. Clients turn the bones toward them at the same rates,
    so a DT changes only when the aim moves (at most ~10 times a second).

    Armour (EntityTakeDamage "droids.aat.armour", -150, after the
    friendly-fire check):
      droid popper EMP (DMG_SHOCK)   no damage; stunned aatStunTime s: no
                                     moving, no firing (sparks, the hover
                                     sinks)
      high explosive charge          stuck on it or going off within
                                     aatChargeReach of its hull: destroyed
                                     (also by hook Rhylib.Explosion kind "he")
      a direct rocket hit            (rhylib_weapons W.directHit) a
                                     locked top-attack rocket (W.topAttackHit,
                                     rhylib_topattack fired with a lock):
                                     1/aatLockonHits of its
                                     health; any other (fired, or laser
                                     guided without a lock): from the rear
                                     destroyed, else 1/aatRocketHits; that
                                     rocket's own blast adds nothing
      anything else                  x aatBlasterMult (bolts, bullets,
                                     grenades, other blasts), x aatRearMult
                                     from the rear
    Rear: the hit lands on its back aatRearShare of its length, or (not
    blasts) the shooter is within aatRearAngle of straight behind it.
    The fixed outcomes (rocket hit counts, kills) are set again by
    EntityTakeDamage "droids.aat.fixed" (1000, last), so later multipliers
    (skills' Anti-armour) never change them; other blasts on it may still
    be scaled by them.

    Destroyed: OnNPCKilled, a big blast (aatDeathDamage / aatDeathRadius,
    credited to itself: droids are never hurt), and a burning wreck
    (prop_dynamic, not solid, never made permanent) for aatWreckTime s;
    the NPC is removed.
]]

AddCSLuaFile()

local Base = baseclass.Get("rhylib_b1")

ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "AAT droid tank"
-- (the mortar variant, rhylib_aat_mortar, is this entity with kind "aat_mortar")
ENT.Category = "Rhy's Droid tanks"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "aat"
ENT.QuietAnims = true   -- (no animations: one "ragdoll" sequence)
ENT.IsAAT = true

-- Model-space pivots of the AAT model, in the tank's own frame (forward,
-- left, up from its feet; the model's -Y is forward, +X left).
local TUR_F, TUR_U = -157.3, 121.8        -- turret (main_gun)
local PIV_F, PIV_U = 96.4, 30.6           -- barrel (main_gun_part), from the turret, turned with it
local SIDE_F, SIDE_L, SIDE_U = -15.6, 100, 114.5   -- side guns (gun_side_L / R)
local HALF_LEN, HALF_WID, TOP = 213, 169, 207      -- its body

local BONES = { turret = "main_gun", barrel = "main_gun_part", left = "gun_side_L", right = "gun_side_R" }

-- Adds v to the angle part named by spec ("p", "y", "r", "-p", ...).
local function axisAdd(spec, v, ang)
    spec = tostring(spec or "")
    if string.sub(spec, 1, 1) == "-" then
        v = -v
        spec = string.sub(spec, 2)
    end
    if spec == "p" then ang.p = ang.p + v
    elseif spec == "y" then ang.y = ang.y + v
    elseif spec == "r" then ang.r = ang.r + v end
end

-- Degrees the model is turned on its root bone (the real model or the fallback).
-- ENT:AatMortarRange(): aatMortarRange, or its sight range when further. Shared.
function ENT:AatMortarRange()
    return math.max(Rhylib.Droids.Cfg("aatMortarRange"), self:SightRange())
end

local function yawOffset(self)
    local D = Rhylib.Droids
    local real = string.lower(self:GetModel() or "") == string.lower(tostring(D.Cfg("aatModel")))
    return tonumber(D.Cfg(real and "aatYawOffset" or "aatFallbackYawOffset")) or 0
end

-- Bone ids per model (false = the model has no such bone).
local boneOf = {}
local function bones(self)
    local mdl = self:GetModel() or ""
    local b = boneOf[mdl]
    if not b then
        b = {}
        for k, name in pairs(BONES) do b[k] = self:LookupBone(name) or false end
        boneOf[mdl] = b
    end
    return b
end

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "AimYaw")
    self:NetworkVar("Float", 1, "AimPitch")
    self:NetworkVar("Float", 2, "LYaw")
    self:NetworkVar("Float", 3, "LPitch")
    self:NetworkVar("Float", 4, "RYaw")
    self:NetworkVar("Float", 5, "RPitch")
    self:NetworkVar("Float", 6, "StunEnd")
end

-- ENT:AatRootTurn(): turns the model on its root bone so its front is the
-- entity's forward (both realms; again when the setting changes).
function ENT:AatRootTurn()
    local off = yawOffset(self)
    local mdl = self:GetModel()
    if self.aatRootOff == off and self.aatRootMdl == mdl then return end
    self.aatRootOff, self.aatRootMdl = off, mdl
    self.aatManip = {}   -- (client: every bone turned again)
    self:ManipulateBoneAngles(0, Angle(0, off, 0))
end

function ENT:Initialize()
    Base.Initialize(self)
    if CLIENT then
        -- (the client's IsValidModel can miss an installed model)
        local mdl = Rhylib.Droids.KindModel(self:Kind())
        if isstring(mdl) and mdl ~= "" and self:GetModel() ~= mdl and file.Exists(mdl, "GAME") then
            util.PrecacheModel(mdl)
            self:SetModel(mdl)
        end
        self:SetRenderBounds(Vector(-270, -270, -30), Vector(270, 270, 280))
        self:AatRootTurn()
        return
    end
    if self.overCap then return end
    local D = Rhylib.Droids
    self:SetSkin(math.floor(tonumber(D.Cfg("aatSkin")) or 0))
    self:AatRootTurn()
    local w, h = self:AatHull()
    self:SetCollisionBounds(Vector(-w, -w, 0), Vector(w, w, h))
    local accel = math.max(D.Cfg("aatAccel"), 10)
    self.loco:SetAcceleration(accel)
    self.loco:SetDeceleration(accel * 1.5)
    self.loco:SetStepHeight(30)
    self.loco:SetJumpHeight(30)
    self.loco:SetDeathDropHeight(300)
    self.loco:SetMaxYawRate(D.Cfg("aatTurnRate"))
    self.loco:SetDesiredSpeed(D.Cfg("aatSpeed"))
    self:AatFreeSpot()
    self.home = self:GetPos()   -- (moved off a wall: its post is where it stands)
    local y = self:GetAngles().y
    self.tYaw, self.tPitch = y, 0
    self.sides = { { sign = 1, yaw = y, pitch = 0, pickAt = 0, seeAt = 0, nextShot = 0, readyAt = 0 },
        { sign = -1, yaw = y, pitch = 0, pickAt = 0, seeAt = 0, nextShot = 0, readyAt = 0 } }
    self.aatSentV, self.aatSentAt = {}, {}
    self:SetAimYaw(y)
    self:SetLYaw(y)
    self:SetRYaw(y)
    self.nextCannon = CurTime() + math.Rand(1, 3)
    self.nextVolley = CurTime() + math.Rand(4, 8)
    self.anims = { idle = ACT_IDLE, walk = ACT_IDLE, run = ACT_IDLE }
    D.aatTanks = D.aatTanks or {}
    D.aatTanks[self] = true
    -- (the repulsor hum, louder and higher as it speeds up)
    self.hum = CreateSound(self, "vehicles/airboat/fan_motor_idle_loop1.wav")
    if self.hum then
        self.hum:SetSoundLevel(80)
        self.hum:PlayEx(0.5, 70)
    end
end

function ENT:OnRemove()
    if SERVER then
        Base.OnRemove(self)
        local D = Rhylib.Droids
        if D.aatTanks then D.aatTanks[self] = nil end
        if self.hum then self.hum:Stop() end
    end
end

if SERVER then
    local function D_() return Rhylib.Droids end

    local function alive(t)
        if not IsValid(t) then return false end
        if t:IsPlayer() then
            if not t:Alive() then return false end
            local S = Rhylib.State
            return not (S and S.IsDown and S.IsDown(t))
        end
        return t:Health() > 0
    end

    local function velOf(t)
        if t:IsNextBot() and t.loco then return t.loco:GetVelocity() end
        return t:GetVelocity()
    end

    local function lob(from, to, t, g)
        local v = (to - from) / t
        v.z = v.z + 0.5 * g * t
        return v
    end

    local function elev(v)
        return math.deg(math.atan2(v.z, math.max(v:Length2D(), 0.001)))
    end

    -- ENT:AatHull() -> half width, height.
    function ENT:AatHull()
        local D = D_()
        return math.Clamp(D.Cfg("aatHullHalf"), 32, 400), math.Clamp(D.Cfg("aatHullHeight"), 40, 400)
    end

    -- ENT:AatStunned() -> stopped by a droid popper's EMP now.
    function ENT:AatStunned()
        return (self.aatStunEnd or 0) > CurTime()
    end

    -- Placed into a wall or a prop: moved to the nearest free spot round it.
    function ENT:AatFreeSpot()
        local w, h = self:AatHull()
        local data = { mins = Vector(-w, -w, 0), maxs = Vector(w, w, h - 20), mask = MASK_NPCSOLID, filter = self }
        local function free(p)
            data.start, data.endpos = p + Vector(0, 0, 18), p + Vector(0, 0, 19)
            return not util.TraceHull(data).StartSolid
        end
        local pos = self:GetPos()
        if free(pos) then return end
        for _, r in ipairs({ 120, 240, 360, 480 }) do
            for i = 0, 7 do
                local a = i * math.pi / 4
                local p = pos + Vector(math.cos(a) * r, math.sin(a) * r, 0)
                local g = util.TraceLine({ start = p + Vector(0, 0, 60), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
                if g.Hit then
                    p = g.HitPos
                    if free(p) then
                        self:SetPos(p)
                        return
                    end
                end
            end
        end
    end

    function ENT:Eye()
        return self:GetPos() + Vector(0, 0, 175)
    end

    -- No hand-held blaster: FireAtPos is unused (side lasers: AatLaser).
    function ENT:FireAtPos() end
    function ENT:SuppressSmoke() return false end
    -- The turret aims on its own: the body never has to face the target to fire.
    function ENT:Facing() return true end

    -- ENT:SetPace(run): aatSpeed, or 75% of it.
    function ENT:SetPace(run)
        local speed = D_().Cfg("aatSpeed") * (run and 1 or 0.75)
        self.paceSpeed = speed
        self.running = run
        self.loco:SetDesiredSpeed(speed)
    end

    --------------------------------------------------------------------------
    -- Where things are on the model (see the header)
    --------------------------------------------------------------------------

    function ENT:AatTurretPivot()
        local a = Angle(0, self:GetAngles().y, 0)
        return self:GetPos() + a:Forward() * TUR_F + Vector(0, 0, TUR_U)
    end

    function ENT:AatPitchPivot(yaw)
        return self:AatTurretPivot() + Angle(0, yaw or self.tYaw, 0):Forward() * PIV_F + Vector(0, 0, PIV_U)
    end

    -- ENT:AatCannonMuzzle(yaw, pitch) -> the barrel's tip (world yaw, barrel angle up).
    function ENT:AatCannonMuzzle(yaw, pitch)
        yaw, pitch = yaw or self.tYaw, pitch or self.tPitch
        return self:AatPitchPivot(yaw) + Angle(-pitch, yaw, 0):Forward() * D_().Cfg("aatCannonLength")
    end

    function ENT:Muzzle()
        return self:AatCannonMuzzle()
    end

    -- ENT:AatSideOrigin(sign) -> a side gun's pivot (1 left, -1 right).
    function ENT:AatSideOrigin(sign)
        local a = Angle(0, self:GetAngles().y, 0)
        return self:GetPos() + a:Forward() * SIDE_F - a:Right() * (SIDE_L * sign) + Vector(0, 0, SIDE_U)
    end

    -- ENT:AatNear(p, reach) -> p within reach of its body.
    function ENT:AatNear(p, reach)
        local lp = self:WorldToLocal(p)
        local dx = math.max(math.abs(lp.x) - HALF_LEN, 0)
        local dy = math.max(math.abs(lp.y) - HALF_WID, 0)
        local dz = lp.z < 0 and -lp.z or math.max(lp.z - TOP, 0)
        return dx * dx + dy * dy + dz * dz <= reach * reach
    end

    -- ENT:AatFront(pos, dot) -> its hull points toward pos (cosine >= dot).
    function ENT:AatFront(pos, dot)
        local f = self:GetForward()
        f.z = 0
        local to = pos - self:GetPos()
        to.z = 0
        if to:LengthSqr() < 1 or f:LengthSqr() == 0 then return true end
        to:Normalize()
        f:Normalize()
        return f:Dot(to) >= dot
    end

    --------------------------------------------------------------------------
    -- Moving: routes that fit its hull, slow turns, backing off when stuck
    --------------------------------------------------------------------------

    -- [hull key][area id] = fits (nil: not checked yet). An area fits when
    -- the free span across it (thin hull traces from its middle to the
    -- walls, 54 units up so ramps pass) is at least 1.6 x aatHullHalf both
    -- ways; big areas fit without a trace. Checked a few at a time by the
    -- timer below, never inside a route search.
    local clearOf = {}
    local clrTr = {}
    local clrData = { mask = MASK_NPCSOLID_BRUSHONLY, output = clrTr, mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8) }
    local DIRS = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0) }
    local function fitsCache(w, h)
        local key = w * 1000 + h
        local c = clearOf[key]
        if not c then c = {} clearOf[key] = c end
        return c
    end
    local function checkArea(area, w, c)
        local need = w * 1.6
        if area:GetSizeX() >= need and area:GetSizeY() >= need then
            c[area:GetID()] = true
            return
        end
        local p = area:GetCenter() + Vector(0, 0, 54)
        local span = {}
        for i = 1, 4 do
            clrData.start = p
            clrData.endpos = p + DIRS[i] * need
            util.TraceHull(clrData)
            span[i] = clrTr.StartSolid and 0 or clrTr.Fraction * need
        end
        c[area:GetID()] = span[1] + span[2] >= need and span[3] + span[4] >= need
    end

    -- Areas round each tank, checked at most 30 per 0.1 s for all tanks.
    local queue, queued, qHead = {}, {}, 1
    timer.Create("Rhylib.Droids.AatAreas", 0.1, 0, function()
        local D = Rhylib.Droids
        local tanks = D and D.aatTanks
        if not tanks or next(tanks) == nil or not navmesh or not navmesh.Find then return end
        local now = CurTime()
        for tank in pairs(tanks) do
            if IsValid(tank) and tank.AatHull and now >= (tank.aatScanAt or 0) then
                tank.aatScanAt = now + 5
                local w, h = tank:AatHull()
                local c = fitsCache(w, h)
                for _, a in ipairs(navmesh.Find(tank:GetPos(), 4000, 400, 400) or {}) do
                    local id = a:GetID()
                    if c[id] == nil and not queued[id] then
                        queued[id] = true
                        queue[#queue + 1] = { a = a, c = c, w = w }
                    end
                end
            end
        end
        local n = 0
        while queue[qHead] and n < 30 do
            local q = queue[qHead]
            queue[qHead] = nil
            qHead = qHead + 1
            n = n + 1
            local id = IsValid(q.a) and q.a:GetID()
            if id then
                queued[id] = nil
                if q.c[id] == nil then checkArea(q.a, q.w, q.c) end
            end
        end
        if not queue[qHead] then queue, qHead = {}, 1 end
    end)

    -- ENT:AatGen() -> the route cost function (Path:Compute generator).
    function ENT:AatGen()
        local gen = self.aatGen
        if gen then return gen end
        local me = self
        gen = function(area, from, ladder, elevator, length)
            if not IsValid(from) then return 0 end
            if IsValid(ladder) or IsValid(elevator) then return -1 end
            if not me.loco:IsAreaTraversable(area) then return -1 end
            if area:HasAttributes(NAV_MESH_JUMP) or area:HasAttributes(NAV_MESH_CROUCH) then return -1 end
            local w, h = me:AatHull()
            -- (not checked yet: allowed, but it costs more)
            local fits = fitsCache(w, h)[area:GetID()]
            if fits == false and area ~= me.aatGoalArea then return -1 end
            local dz = from:ComputeAdjacentConnectionHeightChange(area)
            if dz > me.loco:GetStepHeight() or dz < -250 then return -1 end
            local dist = length and length > 0 and length or (area:GetCenter() - from:GetCenter()):Length()
            -- (open ground first: small areas cost more)
            if area:GetSizeX() < w * 2 or area:GetSizeY() < w * 2 then dist = dist * 1.5 end
            if fits == nil then dist = dist * 2 end
            return from:GetCostSoFar() + dist
        end
        self.aatGen = gen
        return gen
    end

    function ENT:AatPath()
        local path = self.path
        if not path then
            path = Path("Follow")
            path:SetMinLookAheadDistance(400)
            path:SetGoalTolerance(50)
            self.path = path
        end
        return path
    end

    -- ENT:AatCompute(path, goal) -> a route was found. The goal's own area
    -- may be tight (it gets as close as it can); a goal it found no route
    -- to is not searched again for 8 s (a failed search is the costly kind).
    function ENT:AatCompute(path, goal)
        local now = CurTime()
        local f = self.aatFail
        if f and now < f.untilT and f.pos:DistToSqr(goal) < 300 * 300 then return false end
        self.aatGoalArea = navmesh.GetNearestNavArea(goal, false, 400, false, true)
        local ok = path:Compute(self, goal, self:AatGen())
        self.aatGoalArea = nil
        if not ok then self.aatFail = { pos = Vector(goal), untilT = now + 8 } end
        return ok
    end

    -- One tick along a route: slower while the hull still points away
    -- from the way to go (it turns nearly on the spot).
    function ENT:AatDriveTick(path)
        local D = D_()
        local base = self.paceSpeed or D.Cfg("aatSpeed")
        local m = 1
        local seg = path:GetCurrentGoal()
        if seg and seg.pos then
            local to = seg.pos - self:GetPos()
            to.z = 0
            if to:LengthSqr() > 100 then
                to:Normalize()
                local f = self:GetForward()
                f.z = 0
                f:Normalize()
                m = math.Clamp((f:Dot(to) - 0.25) / 0.65, 0.1, 1)
            end
        end
        self.loco:SetDesiredSpeed(base * m)
        path:Update(self)
    end

    -- Backing off after getting stuck: true while it does.
    function ENT:AatBackTick()
        if (self.aatBackUntil or 0) <= CurTime() then return false end
        self.loco:SetDesiredSpeed(D_().Cfg("aatSpeed") * 0.4)
        self.loco:Approach(self:GetPos() + self.aatBackDir * 200, 1)
        return true
    end

    -- NextBot callback: stuck. Back off a little (forward again if it was
    -- just backing into something).
    function ENT:HandleStuck()
        self.loco:ClearStuck()
        local f = self:GetForward()
        f.z = 0
        f:Normalize()
        local backing = (self.aatBackUntil or 0) > CurTime() - 0.5
        self.aatBackDir = backing and f or -f
        self.aatBackUntil = CurTime() + 1.2
    end

    -- ENT:Go(pos, maxTime, watch): the shared brain's walk, on its own
    -- routes. False when there's no route or it got stuck three times. Yields.
    function ENT:Go(pos, maxTime, watch)
        local D = D_()
        local path = self:AatPath()
        local giveUp = CurTime() + 1
        while not D.TakeBudget() do
            if CurTime() > giveUp then return false end
            coroutine.yield()
        end
        self.redirect = nil
        if not self:AatCompute(path, pos) then return false end
        local stop = CurTime() + maxTime
        local stuck = 0
        while path:IsValid() and CurTime() < stop do
            if not self:AatBackTick() then
                self:AatDriveTick(path)
                if self.loco:IsStuck() then
                    stuck = stuck + 1
                    self:HandleStuck()
                    if stuck >= 3 then return false end
                end
            end
            if watch and self:Look() then return true end
            if self.redirect then
                self.redirect = nil
                return true
            end
            coroutine.yield()
        end
        return true
    end

    -- Can it drive straight there (its hull, ground under the far end)?
    local hullTr = {}
    local hullData = { mask = MASK_NPCSOLID, output = hullTr }
    function ENT:StraightTo(goal)
        local w, h = self:AatHull()
        hullData.start = self:GetPos() + Vector(0, 0, 34)
        hullData.endpos = goal + Vector(0, 0, 34)
        hullData.mins = Vector(-w, -w, 0)
        hullData.maxs = Vector(w, w, math.max(h - 34, 8))
        hullData.filter = self
        util.TraceHull(hullData)
        if hullTr.Hit then return false end
        local g = util.TraceLine({ start = goal + Vector(0, 0, 30), endpos = goal - Vector(0, 0, 80), mask = MASK_SOLID_BRUSHONLY })
        return g.Hit
    end

    -- ENT:PlanMove(t) -> goal or nil (stay), run. See the header.
    -- ENT:AatIsMortar(): the mortar variant (kind field aatRole "mortar").
    function ENT:AatIsMortar()
        local k = self.Kind and self:Kind()
        return k and k.aatRole == "mortar" or false
    end

    function ENT:PlanMove(t)
        self:UpdateHome()
        if self:Retreating() then return Base.PlanMove(self, t) end
        local D = D_()
        local L = self:Aggro()
        local pos, tp = self:GetPos(), t:GetPos()
        if L <= 2 then
            local fb = self:FallbackPoint()
            if fb and pos:DistToSqr(fb) > 300 * 300 then return fb, false end
            return nil
        end
        if self.defending or self.posted or self.guarding then return nil end
        if (self.aatHoldUntil or 0) > CurTime() then return nil end
        local st = self.styleState
        local seen = st and st.seen
        local d = pos:Distance(tp)
        if L == 3 and seen then return nil end
        local keep = D.Cfg("aatStandoff") * (L >= 5 and 0.6 or 1)
        if self:AatIsMortar() then
            -- (the mortar hangs back: it only closes in to its mortar range;
            -- aatMortarStandoff 0 = 60% of aatMortarRange)
            local range = self:AatMortarRange()
            local so = D.Cfg("aatMortarStandoff")
            keep = (so and so > 0) and math.min(so, range * 0.9) or range * 0.6
            if d <= keep then return nil end
        end
        if seen and d <= keep then return nil end
        local away = pos - tp
        away.z = 0
        if away:LengthSqr() < 1 then return nil end
        away:Normalize()
        local goal = tp + away * (seen and keep or math.min(keep, d * 0.5))
        goal = self:InArea(goal)
        if goal:DistToSqr(pos) < 150 * 150 then return nil end
        return goal, L >= 4
    end

    -- One tick of moving while fighting (ENT:Engage): to PlanMove's goal on
    -- its own routes; no goal: the hull turns to the target.
    function ENT:StepMove(t)
        local D = D_()
        local now = CurTime()
        if self:AatBackTick() then return end
        local path = self:AatPath()
        if now >= (self.planAt or 0) then
            self.planAt = now + math.Rand(0.6, 0.9)
            local goal, run = self:PlanMove(t)
            self.moveGoal = goal
            if goal then
                self:SetPace(run)
                local slack = math.max(150, goal:Distance(self:GetPos()) * 0.25)
                if not self.pathGoal or self.pathGoal:DistToSqr(goal) > slack * slack or not path:IsValid() then self.needPath = true end
            end
        end
        local goal = self.moveGoal
        if not goal then
            self.loco:FaceTowards(t:GetPos())
            return
        end
        if (self.needPath or not self.pathGoal) and D.TakeBudget() then
            self.needPath = false
            if self:AatCompute(path, goal) then
                self.pathGoal = goal
            else
                self.moveGoal, self.pathGoal = nil, nil
                self.planAt = now + 2   -- (no route: don't ask again at once)
                return
            end
        end
        if self.pathGoal and path:IsValid() then
            self:AatDriveTick(path)
            if self.loco:IsStuck() then
                self:HandleStuck()
                -- (stuck three times within 10 s: that goal is given up 8 s
                -- and it holds its spot and fights)
                if now - (self.aatStuckAt or 0) > 10 then self.aatStuckN = 0 end
                self.aatStuckAt = now
                self.aatStuckN = (self.aatStuckN or 0) + 1
                if self.aatStuckN >= 3 then
                    self.aatStuckN = 0
                    self.aatFail = { pos = Vector(goal), untilT = now + 8 }
                    self.aatHoldUntil = now + 8
                end
                self.moveGoal, self.pathGoal = nil, nil
            end
        else
            self.loco:FaceTowards(t:GetPos())
        end
    end

    -- NextBot: the brain is frozen while stunned (no moving, no new orders run).
    function ENT:BehaveUpdate(interval)
        if self:AatStunned() then return end
        local th = self.BehaveThread
        if not th then return end
        if coroutine.status(th) == "dead" then
            self.BehaveThread = nil
            return
        end
        local ok, msg = coroutine.resume(th)
        if not ok then
            self.BehaveThread = nil
            ErrorNoHalt(tostring(self) .. " Error: " .. tostring(msg) .. "\n")
        end
    end

    --------------------------------------------------------------------------
    -- Choosing shots (the brain asks; ENT:AatGunTick fires once aimed)
    --------------------------------------------------------------------------

    -- ENT:AatGroup(t) -> enemies within aatClusterRadius of t (t too), their middle.
    function ENT:AatGroup(t)
        local D = D_()
        local tp = t:GetPos()
        local r2 = D.Cfg("aatClusterRadius") ^ 2
        local n, sum = 0, Vector(0, 0, 0)
        for _, p in ipairs(self:TargetList()) do
            if IsValid(p) and not p.rhylibObjTarget and alive(p) and p:GetPos():DistToSqr(tp) <= r2 then
                n = n + 1
                sum:Add(p:GetPos())
            end
        end
        if n == 0 then return 1, tp end
        return n, sum / n
    end

    -- How long a mortar shell to target flies (nil: it can't: a ceiling
    -- over it, a blackout there, too steep).
    -- (the arc: aatMortarPitch first; when its top would hit the sky or a
    -- ceiling, flatter arcs down to 15 degrees, so a long shot under a low
    -- skybox still flies)
    local arcTr = { mask = MASK_SOLID_BRUSHONLY }
    local function arcClear(from, v, g, t)
        local prev = from
        for i = 1, 6 do
            local tt = t * i / 6
            local p = from + v * tt - Vector(0, 0, 0.5 * g * tt * tt)
            arcTr.start, arcTr.endpos = prev, i == 6 and p + Vector(0, 0, 40) or p
            local tr = util.TraceLine(arcTr)
            if tr.Hit and i < 6 then return false end
            prev = p
        end
        return true
    end
    function ENT:AatMortarFlight(target)
        local D = D_()
        if D.Blackout and D.Blackout(target) then return nil end
        local g = math.abs(physenv.GetGravity().z)
        if g <= 0 then return nil end
        local maxP = D.Cfg("aatBarrelMax")
        local yaw = (target - self:AatTurretPivot()):Angle().y
        local maxT = math.max(D.Cfg("aatMortarMaxFlight"), 1)
        local th = math.min(D.Cfg("aatMortarPitch"), maxP)
        while th >= 15 do
            local from = self:AatCannonMuzzle(yaw, th)
            local dv = target - from
            local q = dv:Length2D() * math.tan(math.rad(th)) - dv.z
            local t = q > 25 and math.sqrt(2 * q / g) or 1
            t = math.Clamp(t, 1, maxT)
            local v = lob(from, target, t, g)
            if elev(v) <= maxP + 1 and arcClear(from, v, g, t) then return t end
            th = th - 8
        end
        return nil
    end

    -- ENT:AatRequest(kind, ent, pos, lead) -> true if the shot is set:
    -- "direct" at ent (pos: a fixed point instead) or "mortar" at pos
    -- (lead: ent is seen by someone, lead it).
    function ENT:AatRequest(kind, ent, pos, lead)
        local D = D_()
        local now = CurTime()
        local shot = { kind = kind, ent = ent, pos = pos, expire = now + 7 }
        if kind == "mortar" then
            if IsValid(ent) and ent == self.aatLastMortar and now - (self.aatLastMortarAt or 0) < 20 then
                self.aatWalk = math.max(0.35, (self.aatWalk or 1) * 0.75)
            else
                self.aatWalk = 1
            end
            self.aatLastMortar, self.aatLastMortarAt = ent, now
            local target = Vector(pos)
            if lead and IsValid(ent) then target = target + velOf(ent) * 1.2 end
            local dist = target:Distance(self:GetPos())
            local miss = VectorRand() * D.Cfg("aatMortarSpread") * self.aatWalk * dist / 1000 * (D.SuppressMult and D.SuppressMult(self) or 1)
            miss.z = 0
            target = target + miss
            local g = util.TraceLine({ start = target + Vector(0, 0, 60), endpos = target - Vector(0, 0, 300), mask = MASK_SOLID_BRUSHONLY })
            if g.Hit then target = g.HitPos end
            local t = self:AatMortarFlight(target)
            if not t then
                self.nextCannon = now + 2
                return false
            end
            shot.target, shot.t = target, t
        end
        self.aatShot = shot
        return true
    end

    -- Fight style "aat" (ENT:Engage calls it): rocket barrage at a group,
    -- the cannon direct at a target in sight, a mortar shell where it just
    -- lost sight of it. Side lasers fire on their own.
    function ENT:StyleFire(t, now, st)
        if self:AatStunned() then return now + 0.3 end
        local D = D_()
        local pos, tp = self:GetPos(), t:GetPos()
        local d = pos:Distance(tp)
        if now >= (st.seeAt or 0) then st.seen, st.seeAt = self:CanSee(t), now + 0.25 end
        if self:AatIsMortar() then
            -- (the mortar variant: only mortar shells, at the target or where
            -- it was last seen; no rockets, no direct shots; its own target
            -- out of reach: one another droid spots within aatMortarRange)
            if not self.aatShot and now >= (self.nextCannon or 0) then
                if d >= D.Cfg("aatMortarMin") and d <= self:AatMortarRange() and (st.seen or self.lastSeen) then
                    self:AatRequest("mortar", t, st.seen and tp or self.lastSeen, st.seen)
                elseif D.SpottedTarget and (self.aatSpotAt or 0) <= now then
                    self.aatSpotAt = now + 1
                    local o = D.SpottedTarget(self, self:AatMortarRange())
                    if IsValid(o) and o:GetPos():DistToSqr(pos) >= D.Cfg("aatMortarMin") ^ 2 then self:AatRequest("mortar", o, o:GetPos(), true) end
                end
            end
            return now + 0.25
        end
        if st.seen and not self.aatVolley and now >= (self.nextVolley or 0) and d >= D.Cfg("aatRocketMin") and d <= D.Cfg("aatRocketMax")
            and not t.rhylibObjTarget and self:AatFront(tp, 0.5) then
            local n, mid = self:AatGroup(t)
            if n >= D.Cfg("aatRocketCluster") then self:AatStartVolley(mid) end
        end
        if not self.aatShot and now >= (self.nextCannon or 0) and d >= D.Cfg("aatCannonMin") then
            local need = elev((t.rhylibObjTarget and t:WorldSpaceCenter() or tp + Vector(0, 0, 20)) - self:AatPitchPivot())
            if st.seen and (need < D.Cfg("aatBarrelMin") - 2 or need > D.Cfg("aatBarrelMax") + 2) then
                -- (too steep for the barrel: lasers and rockets only)
            elseif st.seen then
                if t.rhylibObjTarget then
                    self:AatRequest("direct", t, t:WorldSpaceCenter())
                else
                    local n, mid = self:AatGroup(t)
                    self:AatRequest("direct", t, n >= 2 and mid + Vector(0, 0, 20) or nil)
                end
            end
        end
        return now + 0.25
    end

    -- Lost sight (the end of a fight): a mortar shell where it last saw them.
    function ENT:LobAtLastSeen()
        local D = D_()
        local pos = self.lastSeen
        local now = CurTime()
        if not self:AatIsMortar() then return end   -- (the tank variant has no mortar)
        if not pos or now - (self.lastSeenAt or 0) > 4 or self.aatShot or now < (self.nextCannon or 0) or self:AatStunned() then return end
        local d = pos:Distance(self:GetPos())
        if d >= D.Cfg("aatMortarMin") and d <= self:AatMortarRange() then self:AatRequest("mortar", self.target, pos) end
    end

    -- Idle: a mortar shell at a target another droid sees (once a second).
    -- Unaware (stealth) and not alerted: holds its fire like any droid.
    function ENT:AatUnaware()
        local D = D_()
        return self.stealth and D.StealthOn and D.StealthOn() and true or false
    end

    function ENT:AatSpottedMortar()
        if self:AatUnaware() or not self:AatIsMortar() then return end
        local now = CurTime()
        if self.aatShot or now < (self.nextCannon or 0) or self:AatStunned() or (self.aatSpotAt or 0) > now then return end
        self.aatSpotAt = now + 1
        local D = D_()
        if not D.SpottedTarget then return end
        local t = D.SpottedTarget(self, self:AatMortarRange())
        if not IsValid(t) or t:GetPos():DistToSqr(self:GetPos()) < D.Cfg("aatMortarMin") ^ 2 then return end
        self:AatRequest("mortar", t, t:GetPos(), true)
    end

    -- ENT:Idle(secs): the shared idle wait, with spotted-target mortar shots. Yields.
    function ENT:Idle(secs)
        local stop = CurTime() + secs
        self.woken = false
        while CurTime() < stop and not self.woken do
            self:AatSpottedMortar()
            local yaw = self.holdYaw
            if yaw and self.home and self:GetPos():DistToSqr(self.home) < 150 * 150 then
                local dir = Angle(0, yaw, 0):Forward() * 300
                local t = CurTime() + 0.5
                while CurTime() < t and not self.woken do
                    self.loco:FaceTowards(self:GetPos() + dir)
                    coroutine.yield()
                end
            else
                coroutine.wait(0.5)
            end
            if self:Look() then return end
        end
    end

    function ENT:AatStartVolley(mid)
        local D = D_()
        self.aatVolley = { left = math.Clamp(math.floor(D.Cfg("aatRocketCount")), 1, 20), i = 0, nextAt = CurTime() + 0.2, pos = mid }
        self.nextVolley = CurTime() + math.max(D.Cfg("aatRocketCooldown"), 1)
    end

    --------------------------------------------------------------------------
    -- Firing (every body update)
    --------------------------------------------------------------------------

    local function aimSpreadMult(self)
        local D = D_()
        local m = D.SuppressMult and D.SuppressMult(self) or 1
        if D.Boosted and D.Boosted(self) then m = m * D.Cfg("cmdSpread") end
        return m
    end

    function ENT:AatFireCannon(shot, now)
        local D = D_()
        local muzzle = self:AatCannonMuzzle()
        local vel, grav
        if shot.kind == "mortar" then
            local g = math.abs(physenv.GetGravity().z)
            vel, grav = lob(muzzle, shot.target, shot.t, g), true
        else
            local speed = math.max(D.Cfg("aatShellSpeed"), 200)
            local aim = shot.pos
            if not aim then
                local t = shot.ent
                local low = t:GetPos() + Vector(0, 0, 20)
                local fly = math.min(muzzle:Distance(low) / speed, 3)
                aim = low + velOf(t) * fly
            end
            local miss = VectorRand() * D.Cfg("aatCannonSpread") * aimSpreadMult(self) * muzzle:Distance(aim) / 1000
            miss.z = miss.z * 0.3
            vel = (aim + miss - muzzle):GetNormalized() * speed
        end
        if grav and self:AatIsMortar() then
            -- (the mortar tank: the B2 mortar's purple rocket, its own blast)
            local r = ents.Create("rhylib_b2_rocket")
            if IsValid(r) then
                r:SetPos(muzzle)
                r.vel = vel
                r.owner = self
                r.damage = D.Cfg("aatCannonDamage")
                r.radius = D.Cfg("aatCannonRadius")
                r.life = (shot.t or 8) + 4
                r:SetOwner(self)
                r:Spawn()
            end
        else
            local s = ents.Create("rhylib_aat_shell")
            if IsValid(s) then
                s:SetPos(muzzle)
                s.vel = vel
                s.grav = grav
                s.owner = self
                s.size = D.Cfg("aatShellSize")
                s:SetOwner(self)
                s:Spawn()
            end
        end
        if grav then
            self:EmitSound("weapons/explosives_cannons_superlazers/wpn_mortar_cannon_r1_shoot_0" .. math.random(1, 3) .. ".ogg", 130, 70)
        else
            self:EmitSound("weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_02.ogg", 140, 55)
        end
        util.ScreenShake(muzzle, 3, 60, 0.4, 700)
        local m = (D.Boosted and D.Boosted(self)) and D.Cfg("cmdPause") or 1
        self.nextCannon = now + math.max(D.Cfg("aatCannonInterval"), 0.5) * math.Rand(0.9, 1.15) * m
        self.aatShot = nil
    end

    -- Sends a DT aim value when it moved (at most every 0.1 s unless it
    -- jumped by 5 degrees or more).
    local SETTERS = { "SetAimYaw", "SetAimPitch", "SetLYaw", "SetLPitch", "SetRYaw", "SetRPitch" }
    local function send(self, i, v, now)
        local sv, sa = self.aatSentV, self.aatSentAt
        local last = sv[i]
        if last then
            local diff = math.abs(math.AngleDifference(v, last))
            if diff < 0.5 or (diff < 5 and now < (sa[i] or 0)) then return end
        end
        sv[i], sa[i] = v, now + 0.1
        self[SETTERS[i]](self, v)
    end

    -- The turret: turns toward the shot it was asked for (else its target,
    -- else straight ahead) and fires once it points there.
    function ENT:AatGunTick(now, dt)
        local D = D_()
        local shot = self.aatShot
        if shot and (now > shot.expire or (shot.kind == "direct" and not shot.pos and not alive(shot.ent))) then
            self.aatShot, shot = nil, nil
            self.nextCannon = math.max(self.nextCannon or 0, now + 1)
        end
        local hull = self:GetAngles().y
        local minP, maxP = D.Cfg("aatBarrelMin"), D.Cfg("aatBarrelMax")
        local wantYaw, wantPitch = hull, 0
        if shot then
            if shot.kind == "mortar" then
                local g = math.abs(physenv.GetGravity().z)
                local v = lob(self:AatCannonMuzzle(), shot.target, shot.t, g)
                wantYaw, wantPitch = v:Angle().y, elev(v)
            else
                local aim = shot.pos or (shot.ent:GetPos() + Vector(0, 0, 20))
                local dv = aim - self:AatPitchPivot()
                wantYaw, wantPitch = dv:Angle().y, elev(dv)
            end
        elseif IsValid(self.target) and alive(self.target) then
            local dv = self.target:WorldSpaceCenter() - self:AatPitchPivot()
            wantYaw, wantPitch = dv:Angle().y, elev(dv)
        end
        local pitchTo = math.Clamp(wantPitch, minP, maxP)
        local rate = math.max(D.Cfg("aatTurretRate"), 1) * dt
        self.tYaw = math.ApproachAngle(self.tYaw, wantYaw, rate)
        self.tPitch = math.Approach(self.tPitch, pitchTo, rate)
        send(self, 1, wantYaw, now)
        send(self, 2, pitchTo, now)
        -- (a shot the barrel can't reach: dropped at once)
        if shot and (wantPitch < minP - 3 or wantPitch > maxP + 3) then
            self.aatShot = nil
            self.nextCannon = math.max(self.nextCannon or 0, now + 1)
            return
        end
        if shot and math.abs(math.AngleDifference(self.tYaw, wantYaw)) < 2 and math.abs(self.tPitch - pitchTo) < 2 then
            self:AatFireCannon(shot, now)
        end
    end

    -- Side lasers: one bolt from gun g toward aim.
    function ENT:AatLaser(g, origin, aim, t)
        local D = D_()
        local Bolts = Rhylib.Weapons and Rhylib.Weapons.Bolts
        if not Bolts then return end
        local k = self:Kind()
        local dir = aim - origin
        dir:Normalize()
        local cone = math.rad((D.Cfg(k.spread) + velOf(t):Length2D() * D.Cfg("moveSpread")) * aimSpreadMult(self))
        local a = math.Rand(0, math.pi * 2)
        local r = math.tan(cone * math.sqrt(math.Rand(0, 1)))
        local ang = dir:Angle()
        local shotDir = dir + ang:Right() * math.cos(a) * r + ang:Up() * math.sin(a) * r
        shotDir:Normalize()
        local gun = D.Gun(self.DroidKind)
        Bolts.Fire(self, gun, origin + dir * D.Cfg("aatLaserLength"), shotDir, gun.Damage)
        local now = CurTime()
        if now >= (self.aatSndAt or 0) then
            self.aatSndAt = now + 0.09
            self:EmitSound(k.sound or D.E5_SOUND, 130, math.random(96, 104) * (k.pitch or 100) / 100, 0.8, CHAN_WEAPON)
        end
    end

    local sideTr = {}
    local sideData = { mask = MASK_SHOT, output = sideTr }
    local sideSelf
    local function sideFilter(e) return e ~= sideSelf and not e.IsRhylibDroid end
    sideData.filter = sideFilter
    -- Can gun g (pivot o) see t?
    local function sideSees(self, o, t)
        local at = t:WorldSpaceCenter()
        sideSelf = self
        sideData.start, sideData.endpos = o, at
        util.TraceLine(sideData)
        sideSelf = nil
        if sideTr.Hit and sideTr.Entity ~= t then return false end
        local W = Rhylib.Weapons
        if W and W.SmokeBlocks and W.SmokeBlocks(o, at) then return false end
        return true
    end

    -- Is p in gun g's arc and range? -> in, distance squared.
    local function inArc(self, o, p, hull)
        local D = D_()
        local dv = p:GetPos() - o
        local d2 = dv:LengthSqr()
        if d2 > D.Cfg("aatLaserRange") ^ 2 then return false end
        return math.abs(math.AngleDifference(dv:Angle().y, hull)) <= D.Cfg("aatLaserArc"), d2
    end

    -- Gun g picks a target: its tank's own (when not an event target) if it
    -- can, else the nearest (at most two sight checks).
    function ENT:AatSidePick(g, o, now, hull)
        local D = D_()
        local old = g.t
        local best
        local t = self.target
        if IsValid(t) and not t.rhylibObjTarget and alive(t) and inArc(self, o, t, hull) and sideSees(self, o, t) then best = t end
        if not best then
            local a, ad, b, bd
            for _, p in ipairs(self:TargetList()) do
                if IsValid(p) and p ~= t and not p.rhylibObjTarget and alive(p) then
                    local ok, d2 = inArc(self, o, p, hull)
                    if ok then
                        if not ad or d2 < ad then a, ad, b, bd = p, d2, a, ad
                        elseif not bd or d2 < bd then b, bd = p, d2 end
                    end
                end
            end
            if a and sideSees(self, o, a) then best = a
            elseif b and sideSees(self, o, b) then best = b end
        end
        g.t = best
        g.seen, g.seeAt = best ~= nil, now + 0.3
        if best and best ~= old then g.readyAt = now + D.Cfg(self:Kind().reaction) * math.Rand(0.4, 0.7) end
    end

    function ENT:AatSideTick(now, dt)
        if self:AatUnaware() then return end
        local D = D_()
        local hull = self:GetAngles().y
        local arc = D.Cfg("aatLaserArc")
        local rate = math.max(D.Cfg("aatLaserTurn"), 1) * dt
        local minP, maxP = D.Cfg("aatBarrelMin"), 60
        for i, g in ipairs(self.sides) do
            local o = self:AatSideOrigin(g.sign)
            if now >= g.pickAt then
                g.pickAt = now + 0.5 + math.Rand(0, 0.1)
                self:AatSidePick(g, o, now, hull)
            end
            local t = g.t
            if t and not alive(t) then t, g.t = nil, nil end
            if t and now >= g.seeAt then
                g.seeAt = now + 0.3
                g.seen = inArc(self, o, t, hull) and sideSees(self, o, t)
            end
            local wantYaw, wantPitch = hull, 0
            local aim
            if t and g.seen then
                aim = t:WorldSpaceCenter() + velOf(t) * 0.05
                local dv = aim - o
                wantYaw, wantPitch = dv:Angle().y, elev(dv)
                local rel = math.AngleDifference(wantYaw, hull)
                if math.abs(rel) > arc then wantYaw = hull + math.Clamp(rel, -arc, arc) end
            end
            local pitchTo = math.Clamp(wantPitch, minP, maxP)
            g.yaw = math.ApproachAngle(g.yaw, wantYaw, rate)
            g.pitch = math.Approach(g.pitch, pitchTo, rate)
            send(self, i == 1 and 3 or 5, wantYaw, now)
            send(self, i == 1 and 4 or 6, pitchTo, now)
            if aim and now >= g.readyAt and now >= g.nextShot and math.abs(math.AngleDifference(g.yaw, wantYaw)) < 4 and math.abs(g.pitch - wantPitch) < 4 then
                self:AatLaser(g, o, aim, t)
                local gap = 60 / math.max(D.Cfg("aatLaserRPM"), 1)
                if D.Boosted and D.Boosted(self) then gap = gap * D.Cfg("cmdPause") end
                g.nextShot = now + gap * math.Rand(0.9, 1.1)
            end
        end
    end

    -- Rocket barrage: one rocket every 0.2 s from the front tubes in turn.
    function ENT:AatVolleyTick(now)
        local v = self.aatVolley
        if not v or now < v.nextAt then return end
        local D = D_()
        local a = Angle(0, self:GetAngles().y, 0)
        local side = (v.i % 3) - 1
        local from = self:GetPos() + a:Forward() * D.Cfg("aatRocketFwd") - a:Right() * (side * D.Cfg("aatRocketSide")) + Vector(0, 0, D.Cfg("aatRocketUp"))
        local r0 = D.Cfg("aatRocketSpread") * math.sqrt(math.Rand(0, 1)) * aimSpreadMult(self)
        local th = math.Rand(0, math.pi * 2)
        local to = v.pos + Vector(math.cos(th) * r0, math.sin(th) * r0, 0)
        local g = math.abs(physenv.GetGravity().z)
        local dist = from:Distance(to)
        local t = math.Clamp(dist / 900, 0.9, 3)
        local apex = g * t * t / 8
        local up = util.TraceLine({ start = from, endpos = from + Vector(0, 0, apex + 40), mask = MASK_SOLID_BRUSHONLY })
        if up.Hit then t = math.Clamp(math.sqrt(math.max(up.HitPos.z - from.z - 40, 0) * 8 / g), 0.4, t) end
        local r = ents.Create("rhylib_b2_rocket")
        if IsValid(r) then
            r:SetPos(from)
            r.vel = lob(from, to, t, g)
            r.owner = self
            r.damage = D.Cfg("aatRocketDamage")
            r.radius = D.Cfg("aatRocketRadius")
            r:SetOwner(self)
            r:Spawn()
        end
        self:EmitSound("weapons/explosives_cannons_superlazers/wpn_rocket_launcher_shoot_01.ogg", 115, 120)
        v.i = v.i + 1
        v.left = v.left - 1
        v.nextAt = now + 0.2
        if v.left <= 0 then
            self.aatVolley = nil
            self.nextVolley = now + math.max(D.Cfg("aatRocketCooldown"), 1) * math.Rand(0.9, 1.2)
        end
    end

    -- NextBot callback (every body update): weapons, the hum, the turn rate.
    function ENT:BodyUpdate()
        if not self.sides then return end
        local now = CurTime()
        local dt = math.Clamp(now - (self.aatTickAt or now), 0, 0.25)
        self.aatTickAt = now
        local D = D_()
        if now >= (self.aatSlowAt or 0) then
            self.aatSlowAt = now + 0.5
            self:AatRootTurn()
            self.loco:SetMaxYawRate(D.Cfg("aatTurnRate"))
            if self.hum then
                local sp = self.loco:GetVelocity():Length2D() / math.max(D.Cfg("aatSpeed"), 1)
                self.hum:ChangePitch(65 + 35 * math.min(sp, 1), 0.5)
                self.hum:ChangeVolume(self:AatStunned() and 0.12 or 0.5, 0.5)
            end
        end
        if self:AatStunned() then return end
        self:AatGunTick(now, dt)
        self:AatSideTick(now, dt)
        self:AatVolleyTick(now)
    end

    --------------------------------------------------------------------------
    -- Stun, armour, death
    --------------------------------------------------------------------------

    function ENT:AatStun()
        local D = D_()
        local untilT = CurTime() + math.max(D.Cfg("aatStunTime"), 0)
        if untilT <= (self.aatStunEnd or 0) then return end
        self.aatStunEnd = untilT
        self:SetStunEnd(untilT)
        self.aatShot, self.aatVolley = nil, nil
        self.loco:SetDesiredSpeed(0)
        self:EmitSound("ambient/energy/zap7.wav", 85, 80)
    end

    -- ENT:AatRear(dmg) -> the hit is on its rear (see the header).
    function ENT:AatRear(dmg)
        local D = D_()
        local p = dmg:GetDamagePosition()
        if p and not p:IsZero() then
            local lp = self:WorldToLocal(p)
            if lp.x < -HALF_LEN + 2 * HALF_LEN * math.Clamp(D.Cfg("aatRearShare"), 0, 1) then return true end
        end
        if dmg:IsDamageType(DMG_BLAST) then return false end
        local att = dmg:GetAttacker()
        if not IsValid(att) or att == self then return false end
        local src
        if att.Eye then src = att:Eye()
        elseif att:IsPlayer() or att:IsNPC() or att:IsNextBot() then src = att:EyePos() end
        if not src then return false end
        local ls = self:WorldToLocal(src)
        ls.z = 0
        if ls:LengthSqr() < 1 then return false end
        ls:Normalize()
        return -ls.x >= math.cos(math.rad(D.Cfg("aatRearAngle")))
    end

    -- A fixed outcome: this damage, kept by "droids.aat.fixed" after
    -- every later multiplier (skills' Anti-armour and the like).
    local function fix(ent, dmg, v)
        dmg:SetDamage(v)
        ent.aatFixTick, ent.aatFixDmg = engine.TickCount(), v
    end
    local function kill(ent, dmg)
        fix(ent, dmg, math.max(dmg:GetDamage(), ent:Health() + 100))
    end

    -- After the friendly-fire check (-200). See the header.
    Rhylib.Hook.Add("EntityTakeDamage", "droids.aat.armour", function(ent, dmg)
        if not ent.IsAAT or not ent.AatRear then return end
        if ent.aatKillNow then return kill(ent, dmg) end
        local D, W = Rhylib.Droids, Rhylib.Weapons
        if dmg:IsDamageType(DMG_SHOCK) then
            ent:AatStun()
            dmg:SetDamage(0)
            ent:OnInjured(dmg)
            return true
        end
        local inf = dmg:GetInflictor()
        if dmg:IsDamageType(DMG_BLAST) and IsValid(inf) and inf:GetClass() == "rhylib_he_planted" then
            local p = dmg:GetDamagePosition()
            if inf:GetParent() == ent or ent:AatNear((p and not p:IsZero()) and p or inf:WorldSpaceCenter(), D.Cfg("aatChargeReach")) then
                return kill(ent, dmg)
            end
        end
        local tick = engine.TickCount()
        if W and W.directHit == ent then
            ent.aatDirectTick = tick
            local hits
            if W.topAttackHit then
                hits = D.Cfg("aatLockonHits")
            elseif ent:AatRear(dmg) then
                return kill(ent, dmg)
            else
                hits = D.Cfg("aatRocketHits")
            end
            fix(ent, dmg, math.ceil(math.max(ent:GetMaxHealth(), 1) / math.max(hits, 1)))
            return
        end
        -- (the blast that comes with a direct rocket hit: already counted)
        if ent.aatDirectTick == tick and dmg:IsDamageType(DMG_BLAST) then
            dmg:SetDamage(0)
            return
        end
        local m = ent:AatRear(dmg) and D.Cfg("aatRearMult") or D.Cfg("aatBlasterMult")
        dmg:ScaleDamage(math.max(m, 0))
    end, -150)

    -- Last: a fixed hit (rocket hit counts, kills) gets its value back
    -- whatever ran in between.
    Rhylib.Hook.Add("EntityTakeDamage", "droids.aat.fixed", function(ent, dmg)
        if not ent.IsAAT or ent.aatFixTick ~= engine.TickCount() then return end
        dmg:SetDamage(ent.aatFixDmg)
        ent.aatFixTick, ent.aatFixDmg = nil, nil
    end, 1000)

    -- A high explosive charge (rhylib_republic, kind "he") going off on or
    -- next to a tank destroys it, even where its blast didn't reach it.
    Rhylib.Hook.Add("Rhylib.Explosion", "droids.aat.he", function(pos, radius, tier, attacker, inflictor, kind)
        if kind ~= "he" then return end
        local D = Rhylib.Droids
        local reach = D.Cfg("aatChargeReach")
        for tank in pairs(D.aatTanks or {}) do
            if IsValid(tank) and tank:Health() > 0 and not tank.aatDead
                and (IsValid(inflictor) and inflictor:GetParent() == tank or tank:AatNear(pos, reach)) then
                local dmg = DamageInfo()
                dmg:SetDamage(tank:Health() + 100)
                dmg:SetDamageType(DMG_BLAST)
                dmg:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
                dmg:SetInflictor(IsValid(inflictor) and inflictor or game.GetWorld())
                dmg:SetDamagePosition(pos)
                tank.aatKillNow = true
                tank:TakeDamageInfo(dmg)
                if IsValid(tank) then tank.aatKillNow = nil end
            end
        end
    end)

    -- The burning wreck: the same model, turret where it pointed, dark,
    -- not solid, on fire, gone after aatWreckTime s.
    function ENT:AatWreck()
        local D = D_()
        local life = tonumber(D.Cfg("aatWreckTime")) or 0
        if life <= 0 then return end
        local w = ents.Create("prop_dynamic")
        if not IsValid(w) then return end
        w:SetModel(self:GetModel())
        w:SetSkin(self:GetSkin())
        w:SetPos(self:GetPos())
        w:SetAngles(self:GetAngles())
        w:SetKeyValue("solid", "0")
        w.rhylibNoPerma = true   -- (never made permanent: rhylib_core Perma)
        w:Spawn()
        w:SetSolid(SOLID_NONE)
        w:SetMoveType(MOVETYPE_NONE)
        w:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        w:SetColor(Color(70, 70, 70))
        w:ManipulateBoneAngles(0, Angle(0, yawOffset(self), 0))
        local b = bones(self)
        if b.turret then
            local a = Angle(0, 0, 0)
            axisAdd(D.Cfg("aatTurretAxis"), math.AngleDifference(self.tYaw or 0, self:GetAngles().y), a)
            w:ManipulateBoneAngles(b.turret, a)
        end
        if b.barrel then
            local a = Angle(0, 0, 0)
            axisAdd(D.Cfg("aatBarrelAxis"), self.tPitch or 0, a)
            w:ManipulateBoneAngles(b.barrel, a)
        end
        w:Ignite(life, 0)
        SafeRemoveEntityDelayed(w, life)
    end

    -- Destroyed: see the header.
    function ENT:OnKilled(dmg)
        if self.aatDead then return end
        self.aatDead = true
        local D = D_()
        hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
        if D.StealthBody then D.StealthBody(self) end
        local c = self:WorldSpaceCenter()
        local ed = EffectData()
        ed:SetOrigin(c)
        util.Effect("HelicopterMegaBomb", ed, true, true)
        local W = Rhylib.Weapons
        local r = D.Cfg("aatDeathRadius")
        if W and W.Explode then
            W.Explode({
                pos = c, radius = r, damage = D.Cfg("aatDeathDamage"),
                attacker = self, inflictor = self, tier = 2, kind = "aat",
                sound = { "ambient/explosions/explode_" .. math.random(1, 4) .. ".wav", 110, 80 },
                shake = { 12, 150, 1.2, r * 3 },
                decal = true, decalFilter = self,
            })
        end
        self:AatWreck()
        if self.hum then self.hum:Stop() end
        self:Remove()
    end
end

if CLIENT then
    -- Per frame (once, however many times it is drawn): turret and guns
    -- turned toward the networked aim, the hover bob and tilt, sparks
    -- while stunned.
    local upTr = {}
    local groundData = { mask = MASK_SOLID_BRUSHONLY, output = upTr }
    local function groundZ(p, fallback)
        groundData.start = p + Vector(0, 0, 80)
        groundData.endpos = p - Vector(0, 0, 220)
        util.TraceLine(groundData)
        return upTr.Hit and upTr.HitPos.z or fallback
    end

    local function manip(self, id, key, a)
        if not id then return end
        local m = self.aatManip
        local last = m[key]
        if last and math.abs(last.p - a.p) + math.abs(last.y - a.y) + math.abs(last.r - a.r) < 0.05 then return end
        m[key] = a
        self:ManipulateBoneAngles(id, a)
    end

    function ENT:AatClientFrame()
        local D = Rhylib.Droids
        local now = CurTime()
        local dt = math.Clamp(FrameTime(), 0, 0.1)
        local pos = self:GetPos()
        local ang = self:GetAngles()
        local hy = ang.y
        local stunned = self:GetStunEnd() > now
        self.aatManip = self.aatManip or {}
        self:AatRootTurn()

        -- Turret, barrel, side guns: toward the networked aim at the server's rates.
        local tdt = stunned and 0 or dt
        local rate = math.max(D.Cfg("aatTurretRate"), 1) * tdt
        self.cYaw = math.ApproachAngle(self.cYaw or hy, self:GetAimYaw(), rate)
        self.cPitch = math.Approach(self.cPitch or 0, self:GetAimPitch(), rate)
        local lrate = math.max(D.Cfg("aatLaserTurn"), 1) * tdt
        local arc = D.Cfg("aatLaserArc")
        self.cLYaw = math.ApproachAngle(self.cLYaw or hy, self:GetLYaw(), lrate)
        self.cLPitch = math.Approach(self.cLPitch or 0, self:GetLPitch(), lrate)
        self.cRYaw = math.ApproachAngle(self.cRYaw or hy, self:GetRYaw(), lrate)
        self.cRPitch = math.Approach(self.cRPitch or 0, self:GetRPitch(), lrate)
        local b = bones(self)
        local a = Angle(0, 0, 0)
        axisAdd(D.Cfg("aatTurretAxis"), math.AngleDifference(self.cYaw, hy), a)
        manip(self, b.turret, "t", a)
        a = Angle(0, 0, 0)
        axisAdd(D.Cfg("aatBarrelAxis"), self.cPitch, a)
        manip(self, b.barrel, "b", a)
        a = Angle(0, 0, 0)
        axisAdd(D.Cfg("aatSideYawAxis"), math.Clamp(math.AngleDifference(self.cLYaw, hy), -arc, arc), a)
        axisAdd(D.Cfg("aatSidePitchAxis"), self.cLPitch, a)
        manip(self, b.left, "l", a)
        a = Angle(0, 0, 0)
        axisAdd(D.Cfg("aatSideYawAxis"), math.Clamp(math.AngleDifference(self.cRYaw, hy), -arc, arc), a)
        axisAdd(D.Cfg("aatSidePitchAxis"), self.cRPitch, a)
        manip(self, b.right, "r", a)

        -- Hover: floats aatHover over the ground (sinks while stunned),
        -- bobs, follows the ground's slope, leans with speeding up and turning.
        local h = self.aatH or {}
        self.aatH = h
        if dt > 0 then
            local vel = h.lastPos and (pos - h.lastPos) / dt or Vector(0, 0, 0)
            h.lastPos = pos
            local oldVel = h.vel or vel
            h.vel = LerpVector(math.Clamp(dt * 5, 0, 1), oldVel, vel)
            local acc = (h.vel - oldVel) / dt
            h.acc = LerpVector(math.Clamp(dt * 3, 0, 1), h.acc or Vector(0, 0, 0), acc)
            local yawRate = math.AngleDifference(hy, h.lastYaw or hy) / dt
            h.lastYaw = hy
            h.yawRate = Lerp(math.Clamp(dt * 3, 0, 1), h.yawRate or 0, yawRate)
        end
        if now >= (h.groundAt or 0) then
            h.groundAt = now + 0.25
            local f, l = Angle(0, hy, 0):Forward(), -Angle(0, hy, 0):Right()
            local z = pos.z
            local zf, zb = groundZ(pos + f * 180, z), groundZ(pos - f * 180, z)
            local zl, zr = groundZ(pos + l * 140, z), groundZ(pos - l * 140, z)
            h.gp = math.Clamp(-math.deg(math.atan2(zf - zb, 360)), -12, 12)
            h.gr = math.Clamp(math.deg(math.atan2(zl - zr, 280)), -12, 12)
        end
        local fwdAcc = h.acc and h.acc:Dot(ang:Forward()) or 0
        local wantP = (h.gp or 0) + math.Clamp(-fwdAcc * 0.03, -4, 4)
        local wantR = (h.gr or 0) + math.Clamp(-(h.yawRate or 0) * 0.08, -4, 4) + math.sin(now * 1.1 + self:EntIndex()) * 0.5
        h.p = Lerp(math.Clamp(dt * 3, 0, 1), h.p or 0, wantP)
        h.r = Lerp(math.Clamp(dt * 3, 0, 1), h.r or 0, wantR)
        h.hover = Lerp(math.Clamp(dt * (stunned and 2 or 1.5), 0, 1), h.hover or 0, stunned and 2 or D.Cfg("aatHover"))
        local bob = stunned and 0 or math.sin(now * 1.7 + self:EntIndex() * 1.3) * 2.2
        self.aatROrigin = pos + Vector(0, 0, h.hover + bob)
        self.aatRAng = Angle(ang.p + h.p, hy, ang.r + h.r)

        if stunned and now >= (h.sparkAt or 0) then
            h.sparkAt = now + 0.15
            local ed = EffectData()
            ed:SetOrigin(pos + Vector(math.Rand(-150, 150), math.Rand(-150, 150), math.Rand(60, 190)))
            ed:SetMagnitude(2)
            ed:SetScale(1)
            ed:SetRadius(4)
            util.Effect("Sparks", ed)
        end
    end

    function ENT:Draw()
        local frame = FrameNumber()
        if self.aatFrame ~= frame then
            self.aatFrame = frame
            self:AatClientFrame()
        end
        if self.aatROrigin then
            self:SetRenderOrigin(self.aatROrigin)
            self:SetRenderAngles(self.aatRAng)
            self:InvalidateBoneCache()
        end
        self:DrawModel()
        if self.aatROrigin then
            self:SetRenderOrigin()
            self:SetRenderAngles()
        end
    end
end
