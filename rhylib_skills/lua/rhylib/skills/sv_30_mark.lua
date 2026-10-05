--[[
    Mark target (Officer tier 1; the Marksman's Called shot marks by
    headshot). Q (rhylib_menus turns +menu into hook Rhylib.MarkKey) sends
    skills.markreq (looking-through-optics bit + the view's fov); the
    server picks what to mark and marks it for markTime seconds:
      - normally: what the eyes' hull trace hits (lag compensated), or else
        the enemy nearest the crosshair within markAimCone degrees;
      - through macrobinoculars / a rangefinder (no crosshair there): up to
        markMax enemies nearest the middle of the view (within a cone from
        the client's zoomed fov, capped by markOpticsCone), in sight.
      - sun visor down: the enemy the client rings (visor bit + its index),
        checked here (enemy, in sight, within markVisorCone of the aim).
    A Q mark is a LOCK: a new Q replaces that player's older locks (spots
    stay). Locks give the marker's squad mates (not Marksmen) x
    markLockDamage on that target (K.LockMult, from K.DamageMult); the
    marker sees a red ring on it, the squad a red diamond. Spots (visor)
    and Called shot marks only show the target. Any live mark feeds
    Priority target.
    Marks live on the target: ent.rhylibMarks = { [marker] = { untilT, lock } };
    K.marks[marker] = { [ent] = true }.
    skills.mark (marker 13, replace bit, quiet bit, lock bit, seconds 6,
    count 3, targets 13 each) goes to the marker and their squad only
    (rhylib_radio squads).
    Sun visor (rhylib_gear) down + Mark target: every visorSpotEvery s up to
    markMax enemies in sight within visorSpotCone of the view are spotted
    for visorSpotTime s (quiet, added to the player's marks).
]]

local K = Rhylib.Skills

Rhylib.Net.Register("skills.markreq")
Rhylib.Net.Register("skills.mark")

K.marks = K.marks or {}   -- [marker] = { [target] = true }

local function squadOf(p)
    local R = Rhylib.Radio
    return R and R.SquadOf and R.SquadOf(p) or 0
end

-- Who sees a player's marks: them and their squad.
local function viewers(ply)
    local out = { ply }
    local R = Rhylib.Radio
    local sq = squadOf(ply)
    local s = sq > 0 and R and R.squads and R.squads[sq]
    if s then
        for p in pairs(s.members) do
            if IsValid(p) and p ~= ply then out[#out + 1] = p end
        end
    end
    return out
end

local function markable(e, ply)
    if not IsValid(e) or e == ply then return false end
    if not (e:IsNPC() or e:IsNextBot() or e:IsPlayer()) then return false end
    return e:Health() > 0 and (not e:IsPlayer() or e:Alive())
end

local function enemy(e)
    return IsValid(e) and (e:IsNPC() or e:IsNextBot()) and e:Health() > 0
end

-- Enemies within coneDeg of the aim, nearest the middle first, in sight
-- (brush trace). At most max; at most 12 traces.
local function inCone(ply, coneDeg, max)
    local eye, aim = ply:EyePos(), ply:GetAimVector()
    local cosCone = math.cos(math.rad(coneDeg))
    local found = {}
    for _, e in ipairs(ents.FindInCone(eye, aim, K.Cfg("markRange"), cosCone)) do
        if enemy(e) then
            local d = e:WorldSpaceCenter() - eye
            local len = d:Length()
            if len > 1 then found[#found + 1] = { e = e, dot = aim:Dot(d / len) } end
        end
    end
    table.sort(found, function(a, b) return a.dot > b.dot end)
    local out, traces = {}, 0
    for _, f in ipairs(found) do
        if #out >= max or traces >= 12 then break end
        traces = traces + 1
        if not util.TraceLine({ start = eye, endpos = f.e:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then
            out[#out + 1] = f.e
        end
    end
    return out
end

Rhylib.Net.Receive("skills.markreq", function(ply)
    local opticsReq = net.ReadBool()
    local fov = net.ReadUInt(10) / 10
    local visorIdx = net.ReadBool() and net.ReadUInt(13) or nil
    if not ply:Alive() or ply.rhylibDown or not K.Has(ply, "mark_target") then return end
    local now = CurTime()
    if (ply.rhylibMarkNext or 0) > now then return end
    ply.rhylibMarkNext = now + K.Cfg("markCooldown")

    local G = Rhylib.Gear
    local optics = opticsReq and G and G.Looking and G.Looking(ply) or false
    local list
    if visorIdx and ply:GetNW2Bool("rhylib_visorDown", false) then
        -- The enemy the visor rings (the client picked it from the spots).
        local e = Entity(visorIdx)
        list = {}
        if enemy(e) then
            local eye = ply:EyePos()
            local d = e:WorldSpaceCenter() - eye
            local len = d:Length()
            if len > 1 and len <= K.Cfg("markRange") and ply:GetAimVector():Dot(d / len) >= math.cos(math.rad(K.Cfg("markVisorCone")))
                and not util.TraceLine({ start = eye, endpos = e:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then
                list[1] = e
            end
        end
    elseif optics then
        -- (the client's zoomed view: the middle 60% of its half-width)
        local cone = math.Clamp(fov * 0.5 * 0.6, 1, K.Cfg("markOpticsCone"))
        ply:LagCompensation(true)
        list = inCone(ply, cone, K.Cfg("markMax"))
        ply:LagCompensation(false)
    else
        ply:LagCompensation(true)
        local eye = ply:EyePos()
        local tr = util.TraceHull({ start = eye, endpos = eye + ply:GetAimVector() * K.Cfg("markRange"),
            mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8), filter = ply, mask = MASK_SHOT_HULL })
        local e = tr.Entity
        local L = Rhylib.Lying
        if IsValid(e) and L and L.Owner and L.Owner(e) then e = L.Owner(e) end
        if markable(e, ply) then
            list = { e }
        else
            list = inCone(ply, K.Cfg("markAimCone"), 1)   -- (forgiving: nearest the crosshair)
        end
        ply:LagCompensation(false)
    end
    if #list > 0 then K.PlaceMarks(ply, list, K.Cfg("markTime"), true, false, true) end
end, { rate = 4, burst = 4 })

-- Mark these targets for ply and tell them and their squad. replace: drop
-- ply's older locks first; lock: these are locks (a Q).
function K.PlaceMarks(ply, list, secs, replace, quiet, lock)
    local mine = K.marks[ply] or {}
    K.marks[ply] = mine
    local now = CurTime()
    if replace then
        for e in pairs(mine) do
            local mk = IsValid(e) and e.rhylibMarks and e.rhylibMarks[ply]
            if not mk or mk.lock or mk.untilT <= now then
                if mk then e.rhylibMarks[ply] = nil end
                mine[e] = nil
            end
        end
    end
    local untilT = now + secs
    local n = math.min(#list, 7)
    for i = 1, n do
        local e = list[i]
        mine[e] = true
        e.rhylibMarks = e.rhylibMarks or {}
        local old = e.rhylibMarks[ply]
        if old and old.untilT <= now then old = nil end
        if lock then
            e.rhylibMarks[ply] = { untilT = untilT, lock = true }
        else
            -- (a shorter spot never cuts a longer mark short, nor unlocks it)
            e.rhylibMarks[ply] = { untilT = math.max(untilT, old and old.untilT or 0), lock = old and old.lock or nil }
        end
    end
    Rhylib.Net.Start("skills.mark")
    net.WriteUInt(ply:EntIndex(), 13)
    net.WriteBool(replace == true)
    net.WriteBool(quiet == true)
    net.WriteBool(lock == true)
    net.WriteUInt(math.Clamp(math.Round(secs), 0, 63), 6)
    net.WriteUInt(n, 3)
    for i = 1, n do net.WriteUInt(list[i]:EntIndex(), 13) end   -- (indexes: targets may be outside a mate's view)
    net.Send(viewers(ply))
end

-- Sun visor auto spot (checked once a second, only for visor wearers).
timer.Create("Rhylib.Skills.VisorSpot", 1, 0, function()
    local now = CurTime()
    for _, ply in ipairs(player.GetHumans()) do
        if ply:GetNW2Bool("rhylib_visorDown", false) and ply:Alive() and not ply.rhylibDown
            and (ply.rhylibVisorSpot or 0) <= now and K.Has(ply, "mark_target") then
            ply.rhylibVisorSpot = now + K.Cfg("visorSpotEvery")
            local list = inCone(ply, K.Cfg("visorSpotCone"), K.Cfg("markMax"))
            if #list > 0 then K.PlaceMarks(ply, list, K.Cfg("visorSpotTime"), false, true) end
        end
    end
end)

-- Called shot (Marksman): a headshot adds the target to your marks.
-- Refreshed at most once a second, once per tick (pellets); placed a tick
-- later, so a killing shot marks nothing.
function K.CalledShot(ply, e)
    if e:IsPlayer() then return end   -- (droids and NPCs only: no marking team mates)
    if ply.rhylibCalledAt == CurTime() then return end
    local secs = K.Cfg("calledShotTime")
    local mk = e.rhylibMarks and e.rhylibMarks[ply]
    local left = mk and mk.untilT - CurTime() or 0
    if left > secs - 1 then return end
    ply.rhylibCalledAt = CurTime()
    timer.Simple(0, function()
        if IsValid(ply) and markable(e, ply) then K.PlaceMarks(ply, { e }, math.max(secs, left), false) end
    end)
end

-- Is this set a Marksman's (any Marksman skill, borrowed ones too)?
local function marksman(set)
    for id in pairs(set) do
        local n = K.byId[id]
        if n and n.spec == "marksman" then return true end
    end
    return false
end

-- Locked target: x markLockDamage for squad mates of whoever locked it
-- (not the marker, not Marksmen: they have Priority target).
function K.LockMult(ply, ent, set)
    local marks = IsValid(ent) and not ent:IsPlayer() and ent.rhylibMarks   -- (never against players)
    if not marks then return 1 end
    local now = CurTime()
    local sq
    for marker, mk in pairs(marks) do
        if mk.lock and mk.untilT > now and marker ~= ply and IsValid(marker) then
            sq = sq or squadOf(ply)
            if sq > 0 and squadOf(marker) == sq then
                if marksman(set) then return 1 end
                return K.Cfg("markLockDamage")
            end
        end
    end
    return 1
end

-- Priority target (Marksman): heavy droids and anything with a live mark.
function K.PriorityTarget(ent)
    local marks = ent.rhylibMarks
    if marks then
        local now = CurTime()
        for _, mk in pairs(marks) do
            if mk.untilT > now then return true end
        end
    end
    if ent.IsRhylibDroid and ent.Kind then
        local k = ent:Kind()
        return k.big == true or k.commander == true or ent.DroidKind == "b1_heavy"
    end
    return false
end

-- Marks end when the target dies.
Rhylib.Hook.Add("PlayerDeath", "skills.mark", function(v) v.rhylibMarks = nil end)
Rhylib.Hook.Add("OnNPCKilled", "skills.mark", function(v) v.rhylibMarks = nil end)

Rhylib.Hook.Add("PlayerDisconnected", "skills.mark", function(ply)
    for e in pairs(K.marks[ply] or {}) do
        if IsValid(e) and e.rhylibMarks then e.rhylibMarks[ply] = nil end
    end
    K.marks[ply] = nil
end)
