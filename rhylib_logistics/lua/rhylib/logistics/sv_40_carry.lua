--[[
    Rhy's Logistics (server): carrying building supply crates
    (entities/rhylib_build_crate.lua).

    E on a crate:
      - light (up to crateLightMax supplies), or heavy with Heavy lifter
        (rhylib_skills heavy_lifter): you pick it up and carry it in front
        of you on your own.
      - heavy without Heavy lifter: you take one end and wait (15 s, stay
        close); a second trooper presses E on it and the two of you carry
        it between you. Drifting more than about 4 m apart sets it down.
      - E again (on it, or with it in your hands): set it down.
    While carrying: no firing, no sprinting, top speed logistics
    carrySpeed (both carriers the same), stamina drains carryDrain a
    second (twice that carrying a heavy crate alone). Run out and you
    drop it, unless you have Heavy lifter. Downed, cuffed, dead or gone:
    it's set down where it is.

    L.carry = { [crate] = { a = ply, b = ply or nil } }; player NW2Bool
    rhylib_carrying (the shared movement limits are in sh_30_build.lua).
    L.CrateUse(ply, crate), L.DropCrate(crate), L.Unstick(crate) (a crate
    set down on a player stays passable until they step off it).
    Crates and built structures can't be picked up with the physgun
    (PhysgunPickup "logistics.carry"; staff can).
]]

local L = Rhylib.Logistics

L.carry = L.carry or {}
-- Other crates carried the same way (armoury resupply crates,
-- sv_50_stock.lua; supply crates and fuel canisters for supply depots,
-- sv_70_depots.lua): [crate] = true. They need IsHeavy, GetCarried,
-- SetCarried and SetHolders like the building crate.
L.carriables = L.carriables or {}
local function eachCrate(fn)
    for c in pairs(L.crates) do fn(c) end
    for c in pairs(L.carriables) do fn(c) end
end

local function mayAct(ply)
    if not (IsValid(ply) and ply:Alive()) then return false end
    local S = Rhylib.State
    return not (S and S.CanAct and not S.CanAct(ply))
end

local function setCarrying(ply, crate)
    if not IsValid(ply) then return end
    ply.rhylibCarry = crate
    ply:SetNW2Bool("rhylib_carrying", IsValid(crate))
end

-- Sets the crate down where it is (on the ground under it).
function L.DropCrate(c)
    local st = L.carry[c]
    L.carry[c] = nil
    if st then
        setCarrying(st.a, nil)
        setCarrying(st.b, nil)
    end
    if c.rhylibWaiting then setCarrying(c.rhylibWaiting, nil) end
    c.rhylibWaiting, c.rhylibWaitUntil = nil, nil
    if not IsValid(c) then return end
    c:SetParent(NULL)
    local pos = c:GetPos()
    local tr = util.TraceLine({ start = pos + Vector(0, 0, 20), endpos = pos - Vector(0, 0, 300), filter = c, mask = MASK_SOLID })
    if tr.Hit then
        local mins = c:OBBMins()
        c:SetPos(tr.HitPos - Vector(0, 0, mins.z))
    end
    c:SetAngles(Angle(0, c:GetAngles().y, 0))
    c:PhysicsInit(SOLID_VPHYSICS)
    c:SetSolid(SOLID_VPHYSICS)
    c:SetMoveType(MOVETYPE_VPHYSICS)
    local phys = c:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    c:SetCarried(false)
    c:SetHolders(0)
    L.Unstick(c)
    if st and c.OnSetDown then c:OnSetDown(st.a, st.b) end
end

-- A crate overlapping a player: passable (debris) until nobody stands in it.
local function playerIn(c)
    local mn, mx = c:WorldSpaceAABB()
    for _, p in ipairs(ents.FindInBox(mn - Vector(2, 2, 0), mx + Vector(2, 2, 0))) do
        if IsValid(p) and p:IsPlayer() and p:Alive() then return true end
    end
    return false
end
function L.Unstick(c)
    if not IsValid(c) or not playerIn(c) then return end
    c:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    local id = "Rhylib.Logistics.Unstick" .. c:EntIndex()
    timer.Create(id, 0.5, 0, function()
        if not IsValid(c) or c:GetCarried() then timer.Remove(id) return end
        if not playerIn(c) then
            c:SetCollisionGroup(COLLISION_GROUP_NONE)
            timer.Remove(id)
        end
    end)
end

local function pickUp(c, a, b)
    -- (whoever picks something up stops waiting at any other heavy crate)
    eachCrate(function(o)
        if IsValid(o) and o ~= c and (o.rhylibWaiting == a or o.rhylibWaiting == b) then
            o.rhylibWaiting, o.rhylibWaitUntil = nil, nil
            if not L.carry[o] then o:SetHolders(0) end
        end
    end)
    L.carry[c] = { a = a, b = b }
    c.rhylibWaiting, c.rhylibWaitUntil = nil, nil
    c:SetSolid(SOLID_NONE)
    c:SetMoveType(MOVETYPE_NONE)
    c:SetCarried(true)
    c:SetHolders(b and 2 or 1)
    setCarrying(a, c)
    if b then
        setCarrying(b, c)
    else
        -- (alone: it rides in front of you)
        c:SetParent(a)
        c:SetLocalPos(Vector(50, 0, 34))
        c:SetLocalAngles(Angle(0, 0, 0))
    end
    a:EmitSound("physics/wood/wood_box_impact_soft" .. math.random(1, 3) .. ".wav", 60)
end

function L.CrateUse(ply, c)
    if not mayAct(ply) then return end
    local now = CurTime()
    if (ply.rhylibCarryAt or 0) > now then return end
    ply.rhylibCarryAt = now + 0.4
    -- (carrying something: E sets it down)
    if IsValid(ply.rhylibCarry) then
        L.DropCrate(ply.rhylibCarry)
        return
    end
    if c:GetCarried() then
        return Rhylib.Notify(ply, "Someone is carrying it", "bad", "Logistics")
    end
    if L.HeldTool(ply) then
        return Rhylib.Notify(ply, "Put the tool away to carry the crate", "info", "Logistics")
    end
    local S = Rhylib.Stamina
    if S and S.Exhausted and S.Exhausted(ply) and not L.HasHeavyLifter(ply) then
        return Rhylib.Notify(ply, "You're out of breath: catch it first", "info", "Logistics")
    end
    local heavy = c:IsHeavy()
    if not heavy or L.HasHeavyLifter(ply) then
        pickUp(c, ply)
        return
    end
    -- Heavy: two to carry.
    local w = c.rhylibWaiting
    if IsValid(w) and w ~= ply and now < (c.rhylibWaitUntil or 0) and not IsValid(w.rhylibCarry) then
        pickUp(c, w, ply)
        return
    end
    if w == ply then
        -- (waiting yourself: E again lets go)
        L.DropCrate(c)
        return
    end
    c.rhylibWaiting, c.rhylibWaitUntil = ply, now + 15
    c:SetHolders(1)
    setCarrying(ply, nil)
    ply.rhylibCarry = nil
    Rhylib.Notify(ply, "It's heavy: a second trooper press E on the crate (or learn Heavy lifter)", "info", "Logistics")
end

function L.CrateRemoved(c)
    local st = L.carry[c]
    L.carry[c] = nil
    if st then
        setCarrying(st.a, nil)
        setCarrying(st.b, nil)
    end
end

-- Two carriers: the crate rides between them, every tick.
Rhylib.Hook.Add("Tick", "logistics.carry", function()
    if not next(L.carry) then return end
    for c, st in pairs(L.carry) do
        if IsValid(c) and st.b then
            local a, b = st.a, st.b
            if IsValid(a) and IsValid(b) then
                local pa, pb = a:GetPos(), b:GetPos()
                if pa:DistToSqr(pb) > 220 * 220 then
                    L.DropCrate(c)
                else
                    local mid = (pa + pb) * 0.5
                    local d = pb - pa
                    c:SetPos(mid + Vector(0, 0, 34))
                    c:SetAngles(Angle(0, d:Angle().y + 90, 0))
                end
            else
                L.DropCrate(c)
            end
        end
    end
end)

-- Every half second: stamina, still able to carry, waiting ends.
timer.Create("Rhylib.Logistics.Carry", 0.5, 0, function()
    local S = Rhylib.Stamina
    local now = CurTime()
    eachCrate(function(c)
        if IsValid(c) and c.rhylibWaiting then
            local w = c.rhylibWaiting
            if not IsValid(w) or now > (c.rhylibWaitUntil or 0) or w:GetPos():DistToSqr(c:GetPos()) > 160 * 160 or not mayAct(w) then
                c.rhylibWaiting, c.rhylibWaitUntil = nil, nil
                if not L.carry[c] then c:SetHolders(0) end
            end
        end
    end)
    for c, st in pairs(L.carry) do
        if not IsValid(c) then
            L.carry[c] = nil
        else
            local drop = false
            for _, p in ipairs({ st.a, st.b }) do
                if not mayAct(p) then drop = true end
            end
            if not drop and S and S.Drain and S.Exhausted then
                local alone = not st.b
                local drain = L.Cfg("carryDrain") * 0.5 * ((alone and c:IsHeavy()) and 2 or 1)
                for _, p in ipairs({ st.a, st.b }) do
                    if IsValid(p) then
                        S.Drain(p, drain)
                        if S.Exhausted(p) and not L.HasHeavyLifter(p) then
                            drop = true
                            Rhylib.Notify(p, "Out of breath: you put the crate down", "info", "Logistics")
                        end
                    end
                end
            end
            if drop then L.DropCrate(c) end
        end
    end
end)

-- E with a crate in your hands (looking anywhere): set it down.
Rhylib.Hook.Add("KeyPress", "logistics.carry", function(ply, key)
    if key ~= IN_USE or not IsValid(ply.rhylibCarry) then return end
    local now = CurTime()
    if (ply.rhylibCarryAt or 0) > now then return end
    ply.rhylibCarryAt = now + 0.4
    L.DropCrate(ply.rhylibCarry)
end)

-- (no physgunning crates or built structures past the carrying rules; staff may)
Rhylib.Hook.Add("PhysgunPickup", "logistics.carry", function(ply, e)
    if IsValid(e) and (e:GetClass() == "rhylib_build_crate" or e:GetClass() == "rhylib_structure" or e:GetClass() == "rhylib_resupply_crate"
        or e:GetClass() == "rhylib_supply_crate" or e:GetClass() == "rhylib_fuel_canister") and not ply:IsAdmin() then return false end
end)

Rhylib.Hook.Add("PlayerDeath", "logistics.carry", function(ply)
    if IsValid(ply.rhylibCarry) then L.DropCrate(ply.rhylibCarry) end
end)
Rhylib.Hook.Add("PlayerDisconnected", "logistics.carry", function(ply)
    if IsValid(ply.rhylibCarry) then L.DropCrate(ply.rhylibCarry) end
end)
