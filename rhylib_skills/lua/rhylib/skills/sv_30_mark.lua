--[[
    Mark target (Officer tier 1). Q (rhylib_menus turns +menu into hook
    Rhylib.MarkKey) sends skills.markreq; the server traces from the eyes
    (lag compensated) and marks the NPC, NextBot or player hit for
    markTime seconds. One mark per officer (a new one replaces it).

    Marked through macrobinoculars or a rangefinder (rhylib_gear
    G.Looking): bolt hits from the officer or their squad mates do
    markDamage more (K.MarkMult, called by K.DamageMult).
    Marks live on the target: ent.rhylibMarks = { [officer] = { untilT, optics } }
    so a hit checks only the marks on what it hit.
    skills.mark (target, officer, optics bit, seconds 6 bits) goes to the
    officer and their squad only (rhylib_radio squads).
]]

local K = Rhylib.Skills

Rhylib.Net.Register("skills.markreq")
Rhylib.Net.Register("skills.mark")

K.marks = K.marks or {}   -- [officer] = target

local function squadOf(p)
    local R = Rhylib.Radio
    return R and R.SquadOf and R.SquadOf(p) or 0
end

-- Who sees an officer's marks: the officer and their squad.
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

Rhylib.Net.Receive("skills.markreq", function(ply)
    if not ply:Alive() or ply.rhylibDown or not K.Has(ply, "mark_target") then return end
    local now = CurTime()
    if (ply.rhylibMarkNext or 0) > now then return end
    ply.rhylibMarkNext = now + K.Cfg("markCooldown")

    local G = Rhylib.Gear
    local optics = G and G.Looking and G.Looking(ply) or false
    ply:LagCompensation(true)
    local eye = ply:EyePos()
    local tr = util.TraceHull({ start = eye, endpos = eye + ply:GetAimVector() * K.Cfg("markRange"),
        mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8), filter = ply, mask = MASK_SHOT_HULL })
    ply:LagCompensation(false)
    local e = tr.Entity
    local L = Rhylib.Lying
    if IsValid(e) and L and L.Owner and L.Owner(e) then e = L.Owner(e) end
    if not markable(e, ply) then return end

    -- One mark per officer.
    local old = K.marks[ply]
    if IsValid(old) and old.rhylibMarks then old.rhylibMarks[ply] = nil end
    local secs = K.Cfg("markTime")
    K.marks[ply] = e
    e.rhylibMarks = e.rhylibMarks or {}
    e.rhylibMarks[ply] = { untilT = now + secs, optics = optics }

    Rhylib.Net.Start("skills.mark")
    net.WriteUInt(e:EntIndex(), 13)   -- (an index: the target may be outside a mate's view)
    net.WriteUInt(ply:EntIndex(), 13)
    net.WriteBool(optics)
    net.WriteUInt(math.Clamp(math.Round(secs), 0, 63), 6)
    net.Send(viewers(ply))
end, { rate = 4, burst = 4 })

-- Damage multiplier for a hit by shooter on ent: optics marks by the
-- shooter or a squad mate. Not stacked across several officers.
function K.MarkMult(shooter, ent)
    local marks = ent.rhylibMarks
    if not marks then return 1 end
    local now, sq = CurTime(), nil
    local hit = false
    for officer, mk in pairs(marks) do
        if mk.untilT <= now or not IsValid(officer) then
            marks[officer] = nil
        elseif mk.optics and not hit then
            if officer == shooter then
                hit = true
            else
                sq = sq or squadOf(shooter)
                if sq > 0 and squadOf(officer) == sq then hit = true end
            end
        end
    end
    if next(marks) == nil then ent.rhylibMarks = nil end
    return hit and K.Cfg("markDamage") or 1
end

-- Marks end when the target dies.
Rhylib.Hook.Add("PlayerDeath", "skills.mark", function(v) v.rhylibMarks = nil end)
Rhylib.Hook.Add("OnNPCKilled", "skills.mark", function(v) v.rhylibMarks = nil end)

Rhylib.Hook.Add("PlayerDisconnected", "skills.mark", function(ply)
    local e = K.marks[ply]
    if IsValid(e) and e.rhylibMarks then e.rhylibMarks[ply] = nil end
    K.marks[ply] = nil
end)
