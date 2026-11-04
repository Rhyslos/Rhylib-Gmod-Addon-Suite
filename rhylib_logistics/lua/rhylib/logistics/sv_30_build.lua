--[[
    Rhy's Logistics (server): placing, building, repairing and removing
    field structures, and building supply crates. How it plays: see
    sh_30_build.lua.

    Net logi.build (client -> server), rate 8/s:
      UInt 2 op: 1 place = UInt 5 structure index (L.STRUCTURES), UInt 3
        turn (45 degree steps added to your facing snapped to 45); the
        server traces your own aim. 2 remove = Entity (a structure).
      Checked: a build tool in hand, alive and able to act, in reach,
      flat enough ground, the caps (buildMaxTotal / buildMaxPlayer),
      the supplies nearby (unless buildSupplies is off), and for remove
      that you placed it (or are staff).
    Building and repairing run in the tool's Think while LMB is held
    (L.BuildTick); progress goes out at most every 0.1 s, health every
    0.2 s.

    L.PlaceStructure(ply, index, turn) -> structure or nil
    L.BuildTick(ply, tool, dt)
    L.RemoveStructure(ply, e)
    L.TakeSupplies(pos, n) -> true if n came out of crates near pos
    L.GiveSupplies(pos, n) -> into the nearest crate in range, else a new one
    L.AddCrateSupplies(ply, tr, n) -> the crate (building supplies item)
]]

local L = Rhylib.Logistics

local function sid(ply) return ply:SteamID64() or "" end

local function mayAct(ply)
    if not (IsValid(ply) and ply:Alive()) then return false end
    local S = Rhylib.State
    return not (S and S.CanAct and not S.CanAct(ply))
end

local function isStaff(ply)
    return IsValid(ply) and ply:IsAdmin()
end

-- (crates within buildSupplyRange of pos, nearest first, not being carried)
local function cratesNear(pos)
    local r = L.Cfg("buildSupplyRange")
    local list = {}
    for c in pairs(L.crates) do
        if IsValid(c) and not c:GetCarried() and c:GetPos():DistToSqr(pos) < r * r then
            list[#list + 1] = { c = c, d = c:GetPos():DistToSqr(pos) }
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

function L.TakeSupplies(pos, n)
    if n <= 0 then return true end
    if L.SuppliesNear(pos) < n then return false end
    for _, x in ipairs(cratesNear(pos)) do
        local c = x.c
        local take = math.min(c:GetSupplies(), n)
        c:SetSupplies(c:GetSupplies() - take)
        n = n - take
        if c:GetSupplies() <= 0 then c:Remove() end
        if n <= 0 then break end
    end
    return true
end

-- (a crate standing on the ground at pos)
local function newCrate(pos, n)
    local c = ents.Create("rhylib_build_crate")
    if not IsValid(c) then return nil end
    c:SetPos(pos + Vector(0, 0, 4))
    c:Spawn()
    local mins = c:OBBMins()
    if mins.z < 0 then c:SetPos(c:GetPos() - Vector(0, 0, mins.z + 4)) end
    c:SetSupplies(n)
    if L.Unstick then L.Unstick(c) end
    return c
end

function L.GiveSupplies(pos, n)
    if n <= 0 then return end
    local near = cratesNear(pos)
    if near[1] then
        local c = near[1].c
        c:SetSupplies(c:GetSupplies() + n)
        return c
    end
    local tr = util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
    return newCrate(tr.Hit and tr.HitPos or pos, n)
end

-- Building supplies put down (weapons/rhylib_build_supplies.lua): into a
-- crate within 120 units of the spot, else a new crate there.
function L.AddCrateSupplies(ply, tr, n)
    for c in pairs(L.crates) do
        if IsValid(c) and not c:GetCarried() and c:GetPos():DistToSqr(tr.HitPos) < 120 * 120 then
            c:SetSupplies(c:GetSupplies() + n)
            Rhylib.Notify(ply, "Building supplies added: the crate holds " .. c:GetSupplies(), "good", "Logistics")
            return c
        end
    end
    local c = newCrate(tr.HitPos, n)
    if IsValid(c) then
        if c.CPPISetOwner then c:CPPISetOwner(ply) end
        Rhylib.Notify(ply, "Building supplies set down: " .. n, "good", "Logistics")
    end
    return c
end

local function counts(ply)
    local all, mine = 0, 0
    local me = IsValid(ply) and sid(ply)
    for e in pairs(L.structures) do
        if IsValid(e) then
            all = all + 1
            if me and e:GetOwnerSid() == me then mine = mine + 1 end
        end
    end
    return all, mine
end

function L.PlaceStructure(ply, index, turn)
    local def = L.StructureAt(index)
    if not def or not L.HeldTool(ply) or not mayAct(ply) then return end
    local reach = L.Cfg("buildReach")
    local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * reach, filter = ply, mask = MASK_SOLID })
    if not tr.Hit or tr.HitSky or tr.HitNormal.z < 0.6 then
        return Rhylib.Notify(ply, "Look at flat ground close by to place it", "bad", "Logistics")
    end
    local all, mine = counts(ply)
    if all >= math.max(1, math.floor(L.Cfg("buildMaxTotal"))) then
        return Rhylib.Notify(ply, "There are as many structures out as the server allows", "bad", "Logistics")
    end
    if mine >= math.max(1, math.floor(L.Cfg("buildMaxPlayer"))) then
        return Rhylib.Notify(ply, "You have " .. mine .. " structures out already: remove one first (Z)", "bad", "Logistics")
    end
    local cost = L.CostFor(ply, def)
    if cost > 0 and not L.TakeSupplies(tr.HitPos, cost) then
        return Rhylib.Notify(ply, string.format("%s needs %d building supplies in a crate close by (%d here)", def.name, cost, L.SuppliesNear(tr.HitPos)), "bad", "Logistics")
    end
    local e = ents.Create("rhylib_structure")
    if not IsValid(e) then return end
    e:SetKind(index)
    e:SetPos(tr.HitPos)
    e:SetAngles(Angle(0, L.PlaceYaw(ply, turn), 0))
    e:Spawn()
    local mins = e:OBBMins()
    if mins.z < 0 then e:SetPos(e:GetPos() - Vector(0, 0, mins.z)) end
    e:SetOwnerSid(sid(ply))
    e.paid = cost
    e.prog = 0
    if e.CPPISetOwner then e:CPPISetOwner(ply) end
    ply:EmitSound("buttons/button14.wav", 60, 120)
    return e
end

-- Someone (a player or an NPC) standing inside the structure's box?
local function blocked(e)
    local mn, mx = e:WorldSpaceAABB()
    for _, x in ipairs(ents.FindInBox(mn, mx)) do
        if IsValid(x) and (x:IsPlayer() and x:Alive() or x:IsNPC() or x:IsNextBot()) then return true end
    end
    return false
end

-- One tick of LMB held with a build tool: build the hologram you aim at,
-- or (repair tool) repair the built structure you aim at.
function L.BuildTick(ply, tool, dt)
    if not mayAct(ply) then return end
    local e = L.AimedStructure(ply, L.structures)
    if not IsValid(e) then return end
    local now = CurTime()
    local repair = tool:GetClass() == "rhylib_repairtool"
    if e:GetBuilt() then
        if not repair then return end
        local max = e:GetSMaxHealth()
        e.hpf = math.min(max, (e.hpf or e:GetSHealth()) + L.Cfg("repairRate") * dt)
        if now >= (e.hpAt or 0) or e.hpf >= max then
            e.hpAt = now + 0.2
            e:SetSHealth(math.floor(e.hpf))
        end
        return
    end
    local def = e:Def()
    if not def then return end
    local speed = L.Cfg("etoolSpeed") * (repair and L.Cfg("repairBuildSpeed") or 1)
    if L.HasEtoolDrills(ply) then speed = speed * L.Cfg("skillSpeed") end
    e.prog = math.min(1, (e.prog or e:GetProgress()) + dt * speed / math.max(1, def.time))
    if e.prog >= 1 then
        if blocked(e) then
            e.prog = 0.99
            if now >= (ply.rhylibBuildWarn or 0) then
                ply.rhylibBuildWarn = now + 3
                Rhylib.Notify(ply, "Someone is standing in it: it finishes once they step out", "info", "Logistics")
            end
        else
            e:Finish()
            return
        end
    end
    if now >= (e.progAt or 0) then
        e.progAt = now + 0.1
        e:SetProgress(e.prog)
    end
end

function L.RemoveStructure(ply, e)
    if not (IsValid(e) and e:GetClass() == "rhylib_structure") or e.removing then return end
    if e:GetOwnerSid() ~= sid(ply) and not isStaff(ply) then
        return Rhylib.Notify(ply, "Only whoever placed it can remove it", "bad", "Logistics")
    end
    e.removing = true
    -- (a hologram's supplies go back into a crate)
    if not e:GetBuilt() and (e.paid or 0) > 0 then L.GiveSupplies(e:GetPos(), e.paid) end
    e:Remove()
    ply:EmitSound("buttons/button15.wav", 60)
end

Rhylib.Net.Receive("logi.build", function(ply)
    local op = net.ReadUInt(2)
    if not L.HeldTool(ply) then return end
    if op == 1 then
        local index, turn = net.ReadUInt(5), net.ReadUInt(3)
        L.PlaceStructure(ply, index, turn)
    elseif op == 2 then
        local e = net.ReadEntity()
        if not IsValid(e) or ply:GetShootPos():DistToSqr(e:WorldSpaceCenter()) > (L.Cfg("buildReach") + 300) ^ 2 then return end
        if not mayAct(ply) then return end
        L.RemoveStructure(ply, e)
    end
end, { rate = 8, burst = 4 })

-- The gear cabinet (rhylib_armoury): the repair tool and building
-- supplies for everyone, the E-tool only for field technicians.
local TOOL_ITEMS = { "rhylib_repairtool", "rhylib_build_supplies" }
Rhylib.Hook.Add("Rhylib.GearStock", "logistics.build", function(list)
    local defs = Rhylib.Items and Rhylib.Items.defs
    if not defs then return end
    local have = {}
    for _, id in ipairs(list) do have[id] = true end
    for _, id in ipairs(TOOL_ITEMS) do
        if defs[id] and not have[id] then list[#list + 1] = id end
    end
end)
Rhylib.Hook.Add("Rhylib.GearStockFor", "logistics.etool", function(ply, list)
    local defs = Rhylib.Items and Rhylib.Items.defs
    if not (defs and defs.rhylib_etool) or not L.IsFieldTech(ply) then return end
    for _, id in ipairs(list) do if id == "rhylib_etool" then return end end
    list[#list + 1] = "rhylib_etool"
end)
