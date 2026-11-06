--[[
    BX commando droid (kind "bx"): the B1 brain (rhylib_b1) with its own
    moving while fighting. Also the base of rhylib_bx_captain (kind
    "bx_captain": a commander that boosts only commandos, kind field
    leads = "bx") and rhylib_bx_training (kind "bx_training").
    Rows and config: rhylib/droids/sh_00_config.lua (bx* keys).

      Health: the row's health key, times its healthMult key when it has
      one (bx: b1Health x bxHealthMult). Faster acceleration and a higher
      jump than a B1 (navmesh jump links).
      Flanking (ENT:PlanMove): at aggression 3 and up, unless an order
      keeps it in place (defending, guarding, following, falling back,
      retreating, reinforcement steps, a friend in the line of fire: the
      B1's plan), each commando fighting a target takes its own angle
      round it (D.bxRing[target]: one slot per commando, measured from
      the line between the target and its squad's middle, so a group
      spreads to both sides and behind), bxFlankMin..bxFlankMax away
      (closer at aggression 5). Of a few navmesh spots there it takes the
      highest one with a clear shot. Picked again every bxFlankRepick s,
      when the target moves far, or when no route is found (then ground
      spots only for a while).
      Leap (ENT:BxTryLeap, BxStartLeap, BxLeapTick): when it picks a
      flank spot, with chance bxLeapChance once bxLeapCooldown has run
      out, it looks for a spot bxLeapMinHeight..bxLeapMaxHeight above it
      within bxLeapRange (navmesh areas up there, plus a few traces down
      from above), off to its flank side, standing room (hull), ground
      under it and a clear shot at the target; the arc there must be
      clear (traces of its own hull along it). Then it flies the arc by
      hand from where it stands (its gravity off, one hull trace a tick:
      anything in the way and it drops from there), holding fire, playing
      a jump animation (bxSeqJump, else ACT_JUMP-like activities) if the
      model has one. Anything in the fight that waits (Face, the grenade
      at the last seen spot, smoke fire, Go) flies a leap to its end first.
      Up there it holds and fights (perched); with no one in sight it
      leaps down (ENT:BxPerchDown, from where it stands): to where it came
      up from, the nearest navmesh below or a ground spot round it, tried
      again every 2 s; after 15 s a step off the edge and a traced fall.
      Animation: bxSeqIdle / bxSeqWalk / bxSeqRun sequence names
      override the base's activity choice (empty = the base's).
]]

AddCSLuaFile()

local Base = baseclass.Get("rhylib_b1")

ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "BX commando droid"
ENT.Category = "Rhy's Commando droids"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.DroidKind = "bx"

-- Sequence overrides per model (and the config names): [key] = { idle,
-- walk, run, jump = sequence ids, jumpAct = ACT_* }.
local SEQ_ORDER = { "idle", "walk", "run", "jump" }
local SEQ_KEY = { idle = "bxSeqIdle", walk = "bxSeqWalk", run = "bxSeqRun", jump = "bxSeqJump" }
local JUMP_ACTS = { ACT_JUMP, ACT_HL2MP_JUMP_AR2, ACT_HL2MP_JUMP_SMG1, ACT_GLIDE }
local animsOf = {}

local function resolve(ent)
    local D = Rhylib.Droids
    local mdl = ent:GetModel() or ""
    local key = mdl
    for _, n in ipairs(SEQ_ORDER) do key = key .. "|" .. tostring(D.Cfg(SEQ_KEY[n])) end
    local a = animsOf[key]
    if a then return a end
    a = {}
    for _, n in ipairs(SEQ_ORDER) do
        local name = D.Cfg(SEQ_KEY[n])
        if isstring(name) and name ~= "" then
            local seq = ent:LookupSequence(name)
            if seq and seq >= 0 then
                a[n] = seq
            elseif SERVER then
                Rhylib.Warn("droids", "%s has no sequence \"%s\" (%s)", mdl, name, SEQ_KEY[n])
            end
        end
    end
    if not a.jump then
        for _, act in ipairs(JUMP_ACTS) do
            if act and ent:SelectWeightedSequence(act) > 0 then a.jumpAct = act break end
        end
    end
    animsOf[key] = a
    if SERVER then
        Rhylib.Print("droids", "bx %s: jump animation %s", mdl, a.jump and "sequence" or a.jumpAct and "activity" or "none")
    end
    return a
end

function ENT:Initialize()
    Base.Initialize(self)
    local D = Rhylib.Droids
    local k = self:Kind()
    if CLIENT then
        -- (the client's IsValidModel can miss an installed model)
        local mdl = D.KindModel(k)
        if isstring(mdl) and mdl ~= "" and self:GetModel() ~= mdl and file.Exists(mdl, "GAME") then
            util.PrecacheModel(mdl)
            self:SetModel(mdl)
        end
        return
    end
    if self.overCap then return end
    if k.healthMult then
        local hp = math.max(1, math.floor(D.Cfg(k.health) * D.Cfg(k.healthMult)))
        self:SetHealth(hp)
        self:SetMaxHealth(hp)
    end
    self.loco:SetAcceleration(900)
    self.loco:SetDeceleration(1100)
    self.loco:SetJumpHeight(64)
    self.bxAnims = resolve(self)
    self.nextLeap = CurTime() + math.Rand(4, 8)
end

if SERVER then
    local D = Rhylib.Droids

    -- Flank slots: [target] = { yaw, at, slots = { [commando] = n } }.
    D.bxRing = D.bxRing or setmetatable({}, { __mode = "k" })
    -- Slot n's angle from the line target -> squad middle (degrees).
    local OFFSETS = { 75, -75, 130, -130, 180, 40, -40, 105, -105, 155, -155 }
    local ARC_STEPS = 8
    local PROBES = 6
    local EYE_UP = Vector(0, 0, 62)

    local function flat(v)
        v.z = 0
        return v
    end

    -- The middle of its squad (alone: itself).
    local function squadMiddle(self)
        local sq = self.squad
        local pos = self:GetPos()
        if not sq then return pos end
        local sum, n = Vector(0, 0, 0), 0
        for _, m in ipairs(sq.list) do
            if IsValid(m) then sum:Add(m:GetPos()) n = n + 1 end
        end
        return n > 0 and sum / n or pos
    end

    -- ENT:BxFlankYaw(t) -> the world yaw of this commando's slot round t.
    function ENT:BxFlankYaw(t)
        local now = CurTime()
        local ring = D.bxRing[t]
        if not ring or now - ring.at > 10 then
            local c = flat(squadMiddle(self) - t:GetPos())
            ring = { yaw = c:LengthSqr() > 1 and c:Angle().y or self:GetAngles().y + 180, at = now, slots = {} }
            D.bxRing[t] = ring
        end
        ring.at = now
        local slots = ring.slots
        local mine = slots[self]
        if not mine then
            local used = {}
            for d, i in pairs(slots) do
                if IsValid(d) and d.target == t and d:Health() > 0 then used[i] = true else slots[d] = nil end
            end
            mine = 1
            while used[mine] do mine = mine + 1 end
            slots[self] = mine
        end
        return ring.yaw + OFFSETS[(mine - 1) % #OFFSETS + 1]
    end

    -- Clear shot from a spot (feet) to t's chest.
    local losTr = {}
    local losData = { mask = MASK_SHOT, output = losTr }
    local function shotFrom(self, feet, t)
        losData.start = feet + EYE_UP
        losData.endpos = t:WorldSpaceCenter() + Vector(0, 0, 8)
        losData.filter = self
        util.TraceLine(losData)
        return not losTr.Hit or losTr.Entity == t
    end

    -- The leap arc: straight across, a hump of h on top (f 0..1).
    local function arcPos(S, L, h, f)
        local p = LerpVector(f, S, L)
        p.z = S.z + (L.z - S.z) * f + 4 * h * f * (1 - f)
        return p
    end
    local function arcHump(S, L)
        return math.max(L.z - S.z, 0) * 0.6 + 56
    end

    local hullTr = {}
    local hMin, hMax = Vector(), Vector()
    local hullData = { mask = MASK_NPCSOLID, output = hullTr, mins = hMin, maxs = hMax }
    -- The droid's own hull, a unit in from the sides, 2 up from its feet.
    local function setHull(self)
        local mn, mx = self:OBBMins(), self:OBBMaxs()
        hMin.x, hMin.y, hMin.z = mn.x + 1, mn.y + 1, mn.z + 2
        hMax.x, hMax.y, hMax.z = mx.x - 1, mx.y - 1, mx.z - 1
        hullData.filter = self
    end
    local function hullClear(self, a, b)
        setHull(self)
        hullData.start, hullData.endpos = a, b
        util.TraceHull(hullData)
        return not (hullTr.Hit or hullTr.StartSolid)
    end
    -- The whole arc clear (ARC_STEPS hull traces)?
    local function arcClear(self, S, L, h)
        local last = S
        for i = 1, ARC_STEPS do
            local p = arcPos(S, L, h, i / ARC_STEPS)
            if not hullClear(self, last, p) then return false end
            last = p
        end
        return true
    end

    local groundTr = {}
    local groundData = { mask = MASK_PLAYERSOLID, output = groundTr }
    local function groundUnder(p)
        groundData.start = p + Vector(0, 0, 8)
        groundData.endpos = p - Vector(0, 0, 24)
        util.TraceLine(groundData)
        return groundTr.Hit and groundTr.HitNormal.z > 0.7
    end

    -- ENT:BxFlankPoint(t, L) -> where to go round t (or nil).
    function ENT:BxFlankPoint(t, L)
        local tp, pos = t:GetPos(), self:GetPos()
        local lo = D.Cfg("bxFlankMin")
        local r = math.Clamp(pos:Distance(tp), lo, math.max(lo, D.Cfg("bxFlankMax")))
        if L >= 5 then r = r * 0.6 end
        local yaw = self:BxFlankYaw(t)
        local high = CurTime() >= (self.bxNoHigh or 0)
        -- (ground spot, and the nearest navmesh to points raised above it:
        -- balconies, walkways, slopes)
        local cands = {}
        for i, dy in ipairs({ 0, 0, 25, -25 }) do
            if i == 1 or high then
                local p = tp + Angle(0, yaw + dy, 0):Forward() * r
                if i > 1 then p.z = p.z + 160 end
                p = D.SnapNav(p)
                cands[#cands + 1] = { p = p, s = math.Clamp(p.z - tp.z, -100, 300) - math.abs(dy) * 2 }
            end
        end
        table.sort(cands, function(a, b) return a.s > b.s end)
        for i = 1, math.min(2, #cands) do
            if shotFrom(self, cands[i].p, t) then return cands[i].p end
        end
        return cands[1] and cands[1].p
    end

    -- Is it still where it landed on a perch?
    function ENT:BxOnPerch()
        local p = self.bxPerch
        return p ~= nil and self:GetPos():DistToSqr(p.at) < 80 * 80
    end

    -- ENT:PlanMove(t): see the header.
    function ENT:PlanMove(t)
        self:UpdateHome()
        self:RetreatCheckClear()
        self.bxPlanned = false
        if self.bxPerch then
            if not self:BxOnPerch() then
                self.bxPerch = nil
            elseif not self:Retreating() then
                return nil   -- (up high: hold and fight)
            end
        end
        local L = self:Aggro()
        local now = CurTime()
        if self.artillery or self:Retreating() or L <= 2 or self.popRush or self.advanceTo or self.defending or self.guarding
            or self.mode == "follow" or (self.blockedUntil and now < self.blockedUntil) then
            return Base.PlanMove(self, t)
        end
        local pos, tp = self:GetPos(), t:GetPos()
        -- (the last flank goal had no route: StepMove dropped it)
        if self.bxWent and not self.moveGoal and self.bxGoal and pos:DistToSqr(self.bxGoal) > 120 * 120 then
            self.bxRepick = 0
            self.bxNoHigh = now + 8
        end
        self.bxWent = false
        if self.bxGoalFor ~= t or now >= (self.bxRepick or 0) or not self.bxGoal
            or (self.bxPickTp and tp:DistToSqr(self.bxPickTp) > 250 * 250) then
            self.bxGoalFor, self.bxPickTp = t, tp
            self.bxRepick = now + D.Cfg("bxFlankRepick") * math.Rand(0.8, 1.2)
            if now >= (self.nextLeap or 0) and math.random() < D.Cfg("bxLeapChance") then
                self.nextLeap = now + 3   -- (no spot: another try a little later)
                if self:BxTryLeap(t) then return nil end
            end
            self.bxGoal = self:BxFlankPoint(t, L)
        end
        local goal = self.bxGoal
        if not goal then return Base.PlanMove(self, t) end
        goal = self:InArea(goal)
        local d = goal:Distance(pos)
        if d < 90 then return nil end
        self.bxWent = true
        return goal, d > 220
    end

    -- ENT:BxTryLeap(t) -> true if a leap started (see the header). Spends
    -- one route budget slot.
    function ENT:BxTryLeap(t)
        if not self.loco:IsOnGround() or not D.TakeBudget() then return false end
        local S, tp = self:GetPos(), t:GetPos()
        local minH = D.Cfg("bxLeapMinHeight")
        local maxH = math.max(minH, D.Cfg("bxLeapMaxHeight"))
        local range = D.Cfg("bxLeapRange")
        local yaw = self:BxFlankYaw(t)
        local cands = {}
        local area, home = self:AreaRadius(), self.home
        local function add(c)
            local h = c.z - S.z
            if h < minH or h > maxH then return end
            if area and home and flat(c - home):Length() > area then return end   -- (guards / patrols: inside their area)
            local fromMe = flat(c - S):Length()
            local fromT = flat(c - tp):Length()
            if fromMe < 100 or fromMe > range or fromT < 220 then return end
            local side = math.abs(math.AngleDifference(flat(c - tp):Angle().y, yaw))
            cands[#cands + 1] = { p = c, s = (c.z - tp.z) * 0.5 - side * 1.5 - fromMe * 0.1 + math.Rand(0, 40) }
        end
        -- Navmesh areas up there.
        if navmesh.FindInBox then
            local areas = navmesh.FindInBox(S + Vector(-range, -range, minH), S + Vector(range, range, maxH))
            local n = areas and #areas or 0
            if n > 0 then
                local first = math.random(1, n)
                for i = 0, math.min(n, 24) - 1 do
                    local a = areas[(first + i - 1) % n + 1]
                    if IsValid(a) then add(a:GetCenter()) end
                    if #cands >= 8 then break end
                end
            end
        end
        -- A few traces down from above, toward its flank side.
        local toFlank = flat(tp + Angle(0, yaw, 0):Forward() * D.Cfg("bxFlankMin") - S)
        local baseYaw = toFlank:LengthSqr() > 1 and toFlank:Angle().y or self:GetAngles().y
        for _ = 1, PROBES do
            local p = S + Angle(0, baseYaw + math.Rand(-80, 80), 0):Forward() * math.Rand(120, range)
            local tr = util.TraceLine({ start = Vector(p.x, p.y, S.z + maxH + 48), endpos = Vector(p.x, p.y, S.z + minH - 8), mask = MASK_PLAYERSOLID })
            if tr.Hit and not tr.StartSolid and tr.HitWorld and tr.HitNormal.z > 0.7 then add(tr.HitPos) end
        end
        if #cands == 0 then return false end
        table.sort(cands, function(a, b) return a.s > b.s end)
        for i = 1, math.min(4, #cands) do
            local L = cands[i].p
            if groundUnder(L) and shotFrom(self, L, t) then
                local h = arcHump(S, L)
                if arcClear(self, S, L, h) then
                    self:BxStartLeap(S, L, h)
                    return true
                end
                if i == 1 and arcClear(self, S, L, h * 1.6) then
                    self:BxStartLeap(S, L, h * 1.6)
                    return true
                end
            end
        end
        return false
    end

    -- ENT:BxStartLeap(S, L, h): fly the arc S -> L. S is where it stands
    -- now (every caller passes its current position), so the first tick's
    -- trace starts from the droid itself.
    function ENT:BxStartLeap(S, L, h)
        local now = CurTime()
        local from, to = S, L
        local T = math.Clamp(0.45 + flat(L - S):Length() / 700 + h / 900, 0.6, 1.5)
        self.bxLeap = { S = S, L = L, h = h, T = T, at = now, last = self:GetPos(), up = to.z - from.z, grav = self.loco:GetGravity() }
        self.loco:SetGravity(0)
        self.loco:SetVelocity(vector_origin)
        self.moveGoal, self.pathGoal = nil, nil
        self.reactUntil = math.max(self.reactUntil or 0, now + T + 0.15)
        self.nextLeap = now + D.Cfg("bxLeapCooldown") * math.Rand(0.85, 1.25)
        local dir = flat(to - from)
        if dir:LengthSqr() > 1 then self:SetAngles(Angle(0, dir:Angle().y, 0)) end
        self:EmitSound("npc/combine_soldier/gear" .. math.random(1, 6) .. ".wav", 70, math.random(95, 105))
    end

    -- One tick of a leap: along the arc, a hull trace from the last spot.
    function ENT:BxLeapTick(t)
        local lp = self.bxLeap
        if not lp then return end
        local f = math.min((CurTime() - lp.at) / lp.T, 1)
        local p = arcPos(lp.S, lp.L, lp.h, f)
        if not hullClear(self, lp.last, p) then
            self:BxEndLeap(false)   -- (something in the way: drops from here)
            return
        end
        self:SetPos(p)
        self.loco:SetVelocity(vector_origin)
        lp.last = p
        if f > 0.5 and IsValid(t) then
            local to = flat(t:GetPos() - p)
            if to:LengthSqr() > 1 then self:SetAngles(Angle(0, to:Angle().y, 0)) end
        end
        if f >= 1 then self:BxEndLeap(true) end
    end

    function ENT:BxEndLeap(landed)
        local lp = self.bxLeap
        self.bxLeap = nil
        if not lp then return end
        self.loco:SetGravity(lp.grav and lp.grav > 0 and lp.grav or 1000)
        self.loco:SetVelocity(landed and vector_origin or Vector(0, 0, -60))
        self.planAt = CurTime() + 0.3
        self.bxGoal, self.bxRepick = nil, 0
        self.bxPerch = nil
        if landed then
            self:EmitSound("physics/metal/metal_solid_impact_soft" .. math.random(1, 3) .. ".wav", 70, math.random(90, 100))
            if lp.up >= D.Cfg("bxLeapMinHeight") * 0.5 then self.bxPerch = { from = lp.S, at = lp.L, h = lp.h } end
        end
    end

    -- Runs a leap under way to its end (yields; at most 3 s).
    function ENT:BxFinishLeap()
        local stop = CurTime() + 3
        while self.bxLeap do
            if CurTime() > stop then self:BxEndLeap(false) break end
            self:BxLeapTick(self.target)
            coroutine.yield()
        end
    end

    function ENT:StepMove(t)
        if self.bxLeap then self:BxLeapTick(t) return end
        Base.StepMove(self, t)
    end

    function ENT:StyleFire(t, now, st)
        if self.bxLeap then return now + 0.1 end   -- (holds fire in the air)
        return Base.StyleFire(self, t, now, st)
    end

    -- Ground spot under a point (a hull falling from it), lower than its
    -- start by 40+, or nil.
    local function fallTo(self, from, depth)
        setHull(self)
        hullData.start, hullData.endpos = from, from - Vector(0, 0, depth)
        util.TraceHull(hullData)
        if hullTr.StartSolid or not hullTr.Hit or hullTr.HitNormal.z < 0.7 then return nil end
        local p = hullTr.HitPos
        if p.z > from.z - 40 then return nil end
        return p + Vector(0, 0, 1)
    end

    -- ENT:BxPerchDown() -> true if a leap down started. Leaps from where it
    -- stands to: where it leapt up from, the nearest navmesh below, a few
    -- ground spots round it. Tried at most every 2 s; after 15 s of no
    -- way down, a drop off the edge (a short step out, then a traced fall);
    -- nothing at all: it stops trying (stays up there). One route budget
    -- slot per try.
    function ENT:BxPerchDown()
        local p = self.bxPerch
        if not p or self.bxLeap then return false end
        if not self:BxOnPerch() then self.bxPerch = nil return false end
        local now = CurTime()
        if now < (p.nextTry or 0) or not self.loco:IsOnGround() or not D.TakeBudget() then return false end
        p.nextTry = now + 2
        p.failSince = p.failSince or now
        local S = self:GetPos()
        local depth = math.max(D.Cfg("bxLeapMaxHeight"), 100) + 200
        local tries = { p.from }
        if navmesh.GetNearestNavArea then
            local q = Vector(S.x, S.y, p.from.z)
            local a = navmesh.GetNearestNavArea(q, false, 600, false, true)
            local c = IsValid(a) and a:GetClosestPointOnArea(q)
            if c and c.z < S.z - 40 then tries[#tries + 1] = c end
        end
        local yaw0 = math.Rand(0, 360)
        for i = 0, 3 do
            local dir = Angle(0, yaw0 + i * 90, 0):Forward()
            local out = S + dir * math.Rand(180, 320) + Vector(0, 0, 20)
            local tr = util.TraceLine({ start = out, endpos = out - Vector(0, 0, depth), mask = MASK_PLAYERSOLID })
            if tr.Hit and not tr.StartSolid and tr.HitNormal.z > 0.7 and tr.HitPos.z < S.z - 40 then tries[#tries + 1] = tr.HitPos end
        end
        for _, L in ipairs(tries) do
            local h = arcHump(S, L)
            if arcClear(self, S, L, h) then
                self:BxStartLeap(S, L, h)
                return true
            end
        end
        if now - p.failSince < 15 then return false end
        -- Last way down: a step out over the edge, then straight down.
        for i = 0, 7 do
            local dir = Angle(0, yaw0 + i * 45, 0):Forward()
            for _, d in ipairs({ 60, 120 }) do
                local out = S + dir * d + Vector(0, 0, 4)
                if hullClear(self, S + Vector(0, 0, 4), out) then
                    local g = fallTo(self, out, depth)
                    if g and arcClear(self, S, g, 12) then
                        self:BxStartLeap(S, g, 12)
                        return true
                    end
                end
            end
        end
        self.bxPerch = nil   -- (no way down found: stays up there)
        return false
    end

    -- A perch with nobody seen for a moment: try the way down (yields).
    local function perchDown(self)
        if self.bxPerch and not self.bxLeap and CurTime() - (self.lastSeenAt or 0) > 1.5 and self:BxPerchDown() then
            self:BxFinishLeap()
            return true
        end
        return false
    end

    function ENT:CoverCheck()
        if self.bxLeap then return false end
        -- (outside a fight: the brain's loop calls this first)
        if not IsValid(self.target) and perchDown(self) then return true end
        return Base.CoverCheck(self)
    end

    -- Things that wait (yield) from inside the fight: a leap under way is
    -- flown to its end first, so it never hangs in the air.
    function ENT:Face(pos, t)
        self:BxFinishLeap()
        return Base.Face(self, pos, t)
    end
    function ENT:LobAtLastSeen()
        self:BxFinishLeap()
        return Base.LobAtLastSeen(self)
    end
    function ENT:SuppressSmoke(t)
        self:BxFinishLeap()
        return Base.SuppressSmoke(self, t)
    end
    function ENT:Go(pos, maxTime, watch)
        self:BxFinishLeap()
        perchDown(self)
        return Base.Go(self, pos, maxTime, watch)
    end

    -- The fight, then: a leap under way finished; perched with nobody in
    -- sight: the way down (BxPerchDown, retried from CoverCheck / Go).
    function ENT:Engage()
        self.bxWent = false
        Base.Engage(self)
        self:BxFinishLeap()
        local p = self.bxPerch
        if not p then return end
        if not self:BxOnPerch() then self.bxPerch = nil return end
        self.nextLook = 0
        if self:Look() then return end   -- (someone in sight: fights on from up there)
        p.nextTry = 0
        if self:BxPerchDown() then self:BxFinishLeap() end
    end

    -- Animation: the base's, with bxSeq* sequences over it and a jump
    -- animation in a leap.
    function ENT:BodyUpdate()
        local A = self.bxAnims
        if not (A and self.anims) then return Base.BodyUpdate(self) end
        if self.bxLeap and (A.jump or A.jumpAct) then
            if A.jump then
                if self.bxCur ~= "jump" then
                    self.bxCur = "jump"
                    self:ResetSequence(A.jump)
                    self:SetCycle(0)
                end
            else
                if self:GetActivity() ~= A.jumpAct then self:StartActivity(A.jumpAct) end
                self.bxCur = "jumpAct"
            end
            self:FrameAdvance()
            return
        end
        local speed = self.loco:GetVelocity():Length2D()
        local want = speed > 10 and (speed > 110 and "run" or "walk") or "idle"
        local crouched = want == "idle" and (self.crouching or (self.crouchUntil or 0) > CurTime())
        local seq = not crouched and A[want] or nil
        if self.bxCur and (not seq or self.bxCur ~= want) then
            self.bxCur = nil
            self:StartActivity(self.anims.idle)   -- (the base then picks its own activity again)
        end
        local before = self:GetActivity()
        Base.BodyUpdate(self)
        if seq and (self.bxCur ~= want or self:GetActivity() ~= before) then
            self.bxCur = want
            self:ResetSequence(seq)
        end
    end
end
