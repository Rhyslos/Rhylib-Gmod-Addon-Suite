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
    A new Q replaces that player's marks. Marks only show the target (and
    feed Priority target); there's no damage bonus any more.
    Marks live on the target: ent.rhylibMarks = { [marker] = { untilT } };
    K.marks[marker] = { [ent] = true }.
    skills.mark (marker 13, replace bit, seconds 6, count 3, targets 13
    each) goes to the marker and their squad only (rhylib_radio squads).
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
    if not ply:Alive() or ply.rhylibDown or not K.Has(ply, "mark_target") then return end
    local now = CurTime()
    if (ply.rhylibMarkNext or 0) > now then return end
    ply.rhylibMarkNext = now + K.Cfg("markCooldown")

    local G = Rhylib.Gear
    local optics = opticsReq and G and G.Looking and G.Looking(ply) or false
    local list
    if optics then
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
    if #list > 0 then K.PlaceMarks(ply, list, K.Cfg("markTime"), true) end
end, { rate = 4, burst = 4 })

-- Mark these targets for ply (replace: drop ply's older marks first) and
-- tell them and their squad.
function K.PlaceMarks(ply, list, secs, replace)
    local mine = K.marks[ply]
    if replace and mine then
        for e in pairs(mine) do
            if IsValid(e) and e.rhylibMarks then e.rhylibMarks[ply] = nil end
        end
        mine = nil
    end
    mine = mine or {}
    K.marks[ply] = mine
    local untilT = CurTime() + secs
    local n = math.min(#list, 7)
    for i = 1, n do
        local e = list[i]
        mine[e] = true
        e.rhylibMarks = e.rhylibMarks or {}
        e.rhylibMarks[ply] = { untilT = untilT }
    end
    Rhylib.Net.Start("skills.mark")
    net.WriteUInt(ply:EntIndex(), 13)
    net.WriteBool(replace == true)
    net.WriteUInt(math.Clamp(math.Round(secs), 0, 63), 6)
    net.WriteUInt(n, 3)
    for i = 1, n do net.WriteUInt(list[i]:EntIndex(), 13) end   -- (indexes: targets may be outside a mate's view)
    net.Send(viewers(ply))
end

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
