--[[
    Rhy's Logistics (shared): field building with the E-tool and the
    repair tool (weapons/rhylib_etool.lua, weapons/rhylib_repairtool.lua),
    building supplies (weapons/rhylib_build_supplies.lua, the crate
    entities/rhylib_build_crate.lua) and the structures
    (entities/rhylib_structure.lua). Server side: sv_30_build.lua,
    sv_40_carry.lua; client: cl_30_build.lua.

    How it plays:
      - R (hold) with a tool out: the build menu (rhylib_menus list wheel;
        without menus R steps through the list). The picked structure
        follows your aim as a see-through ghost; E / Q turn it 45 degrees.
      - Snap dots (L.SnapDots: the corners and side middles of the box's
        bottom): one of the ghost's within buildSnap of another
        structure's turns green and the ghost moves so they meet, keeping
        its own facing (L.SnapPlace).
      - RMB places it: a hologram everyone sees, nothing collides with it.
        Placing spends its supplies at once from building supply crates
        within buildSupplyRange of the spot (none while buildSupplies is
        off). Refused past buildMaxTotal on the server or buildMaxPlayer
        of yours.
      - Only the E-tool places (the menu, the ghost, RMB, E / Q turning);
        the repair tool helps build holograms already placed and repairs.
      - LMB held on a hologram (within buildWorkReach, about 2 m) builds
        it (a progress bar; several builders
        add up: two builders twice as fast). The E-tool builds at etoolSpeed, the repair tool at
        repairBuildSpeed; Field technicians with E-tool drills (rhylib_skills
        eod_etool) build skillSpeed faster and pay skillCost of the price.
        Done: it turns into a solid, frozen prop with its own health,
        unless someone stands inside it (it waits).
      - LMB held on a damaged structure with the repair tool repairs it
        (repairRate health a second); the E-tool can't repair.
      - Z (the undo key) removes the structure you look at: only whoever
        placed it (and staff). A hologram's supplies go back into a
        crate in range (a new one if there's none).
      - Built structures take damage from bolts and explosions and break
        at 0. Nothing is saved over a map change.
      - Building supplies: an inventory item (gear cabinet, anyone); hold
        it and click the ground: one unit (buildSupplyUnit) goes down as a
        crate, or into a crate close by. The crate shows how much it holds.
      - Crates are carried with E (sv_40_carry.lua): up to crateLightMax
        it's light (one trooper), above that heavy (two troopers, or one
        with Heavy lifter, rhylib_skills heavy_lifter).

    L.STRUCTURES = { { id, name, model, time (s), health, cost, size } }
    in menu order; L.Structure(id) / L.StructureIndex(id). Settings in
    module logistics, section "Building".
]]

local L = Rhylib.Logistics
local Config = Rhylib.Config

local S = { section = "Building" }
Config.Register("logistics", "buildSupplies", true, "Building: structures cost building supplies from a crate nearby (off = building is free)", S)
Config.Register("logistics", "buildMaxTotal", 60, "Building: most structures (holograms and built) on the whole server at once", S)
Config.Register("logistics", "buildMaxPlayer", 10, "Building: most structures one player can have placed at once", S)
Config.Register("logistics", "buildSupplyRange", 600, "Building: how close a building supply crate must be to the spot to pay for a structure (units)", S)
Config.Register("logistics", "buildSupplyUnit", 50, "Building supplies: how much one item puts into a crate", S)
Config.Register("logistics", "buildSnap", 40, "Building: a snap dot of the ghost this close to a snap dot of another structure snaps the two together (units; 0 = no snapping)", S)
Config.Register("logistics", "buildReach", 300, "Building: how far away you can place (and remove) a structure (units)", S)
Config.Register("logistics", "buildWorkReach", 110, "Building: how close you must be to a structure to build it up or repair it (units from your eyes to its edge; 110 = about 2 m)", S)
Config.Register("logistics", "etoolSpeed", 1, "Building: E-tool build speed (1 = a structure's own build time)", S)
Config.Register("logistics", "repairBuildSpeed", 0.6, "Building: repair tool build speed (share of the E-tool's)", S)
Config.Register("logistics", "repairRate", 40, "Building: health a second the repair tool gives back to a damaged structure", S)
Config.Register("logistics", "skillSpeed", 1.25, "Building: build speed multiplier with E-tool drills (Field technician)", S)
Config.Register("logistics", "skillCost", 0.8, "Building: share of the supply cost paid with E-tool drills (Field technician)", S)
Config.Register("logistics", "crateLightMax", 100, "Building supplies: a crate holding more than this is heavy (two to carry, or Heavy lifter)", S)
Config.Register("logistics", "carryDrain", 3, "Carrying a crate: stamina a second (heavy alone with Heavy lifter: twice)", S)
Config.Register("logistics", "carrySpeed", 130, "Carrying a crate: top speed (units a second)", S)
Config.Register("logistics", "staffCrate", 200, "Building supplies: what a crate staff place with the toolgun holds", S)
Config.Register("logistics", "crateModel", "models/props_junk/wood_crate001a.mdl", "Building supply crate: model (a placeholder)", S)

-- The structures (models from the owner's Workshop packs).
L.STRUCTURES = {
    { id = "trench", name = "Trench (long)", model = "models/trancher/trancher.mdl", time = 30, health = 1500, cost = 60 },
    { id = "fence1", name = "Fence", model = "models/reizer_props/alysseum_project/fances/fance_01_s/fance_01_s.mdl", time = 25, health = 1200, cost = 50 },
    { id = "fence1c", name = "Fence corner", model = "models/reizer_props/alysseum_project/fances/fance_01_s_corner/fance_01_s_corner.mdl", time = 25, health = 1200, cost = 50 },
    { id = "fence2", name = "Fence, tall", model = "models/reizer_props/alysseum_project/fances/fance_02_s/fance_02_s.mdl", time = 30, health = 1400, cost = 60 },
    { id = "fencem", name = "Fence section", model = "models/reizer_props/alysseum_project/fances/fance_s_misc/fance_s_misc.mdl", time = 25, health = 1200, cost = 50 },
    { id = "fencem3", name = "Fence section, wide", model = "models/reizer_props/alysseum_project/fances/fance_s_misc_3/fance_s_misc_3.mdl", time = 30, health = 1400, cost = 60 },
    { id = "barrier", name = "Barrier", model = "models/niksacokica/neu/neu_fence_barrier.mdl", time = 10, health = 500, cost = 20 },
    { id = "blocker", name = "Tank blocker", model = "models/niksacokica/neu/neu_battlefield_tank_blocker_01.mdl", time = 12, health = 800, cost = 25 },
}

local byId = {}
for i, s in ipairs(L.STRUCTURES) do s.index = i byId[s.id] = s end

function L.Structure(id) return byId[id] end
function L.StructureAt(i) return L.STRUCTURES[i] end

-- L.HasEtoolDrills(ply) -> the Field technician skill E-tool drills.
function L.HasEtoolDrills(ply)
    local K = Rhylib.Skills
    return K and K.Has and IsValid(ply) and K.Has(ply, "eod_etool") or false
end

-- L.HasHeavyLifter(ply) -> the Heavy skill Heavy lifter.
function L.HasHeavyLifter(ply)
    local K = Rhylib.Skills
    return K and K.Has and IsValid(ply) and K.Has(ply, "heavy_lifter") or false
end

-- L.CostFor(ply, def) -> supplies placing def costs ply (0 while
-- buildSupplies is off).
function L.CostFor(ply, def)
    if not L.Cfg("buildSupplies") then return 0 end
    local c = def.cost or 0
    if L.HasEtoolDrills(ply) then c = c * math.Clamp(L.Cfg("skillCost"), 0, 1) end
    return math.ceil(c)
end

-- L.PlaceYaw(ply, turn): the facing a placement gets: your facing snapped
-- to 45 degrees, plus turn x 45 (the client's ghost uses the same).
function L.PlaceYaw(ply, turn)
    return math.Round(ply:EyeAngles().y / 45) * 45 + (turn % 8) * 45
end

-- L.BuildTools = the tool classes and their build speed key.
L.BuildTools = { rhylib_etool = true, rhylib_repairtool = true }

-- Snap dots: 8 on the bottom of a structure's box (the 4 corners and the
-- middle of each side). L.SnapDots(mins, maxs) -> local points.
function L.SnapDots(mins, maxs)
    local z = mins.z
    local cx, cy = (mins.x + maxs.x) * 0.5, (mins.y + maxs.y) * 0.5
    return {
        Vector(mins.x, mins.y, z), Vector(cx, mins.y, z), Vector(maxs.x, mins.y, z), Vector(maxs.x, cy, z),
        Vector(maxs.x, maxs.y, z), Vector(cx, maxs.y, z), Vector(mins.x, maxs.y, z), Vector(mins.x, cy, z),
    }
end

-- L.StructureDots(e) -> e's snap dots in the world.
function L.StructureDots(e)
    local pos, ang = e:GetPos(), e:GetAngles()
    local out = {}
    for i, d in ipairs(L.SnapDots(e:OBBMins(), e:OBBMaxs())) do out[i] = LocalToWorld(d, angle_zero, pos, ang) end
    return out
end

-- L.SnapPlace(mins, maxs, origin, yaw, ignore) -> origin, neighbour, the
-- point where the two dots meet (or nil): snapping. mins / maxs = the
-- new structure's box, origin / yaw = where it would stand unsnapped (the
-- facing is kept). When one of its snap dots is within buildSnap of a snap
-- dot of another structure (any but ignore, bottoms within 150 units of
-- height), the nearest pair is joined: the new one moves so the two dots
-- meet. Shared: the client's ghost and the server's placing use the same.
function L.SnapPlace(mins, maxs, origin, yaw, ignore)
    local dist = L.Cfg("buildSnap")
    if not dist or dist <= 0 then return nil end
    local ang = Angle(0, yaw, 0)
    local mine = {}
    for i, d in ipairs(L.SnapDots(mins, maxs)) do mine[i] = LocalToWorld(d, angle_zero, origin, ang) end
    local reach = math.max(maxs.x - mins.x, maxs.y - mins.y) + dist
    local best, bestD, bestE, bestG, bestS
    for e in pairs(L.structures) do
        if IsValid(e) and e ~= ignore then
            local emn, emx = e:OBBMins(), e:OBBMaxs()
            local far = reach + math.max(emx.x - emn.x, emx.y - emn.y)
            if e:GetPos():DistToSqr(origin) < far * far then
                for _, sd in ipairs(L.StructureDots(e)) do
                    for _, gd in ipairs(mine) do
                        local dx, dy = sd.x - gd.x, sd.y - gd.y
                        local d = dx * dx + dy * dy
                        if d <= dist * dist and math.abs(sd.z - gd.z) < 150 and (not bestD or d < bestD) then
                            bestD, bestE, bestG, bestS = d, e, gd, sd
                        end
                    end
                end
            end
        end
    end
    if not bestE then return nil end
    return origin + (bestS - bestG), bestE, bestS
end

-- L.HeldTool(ply) -> the build tool in ply's hands, or nil.
function L.HeldTool(ply)
    if not IsValid(ply) then return nil end
    local w = ply:GetActiveWeapon()
    if IsValid(w) and L.BuildTools[w:GetClass()] then return w end
end

-- L.HeldPlacer(ply) -> the tool in ply's hands if it can place structures
-- (the E-tool; the repair tool only helps build placed ones and repairs).
function L.HeldPlacer(ply)
    local w = L.HeldTool(ply)
    if w and w.CanPlace then return w end
end

-- L.AimedStructure(ply, list, reach) -> the structure ply's aim ray hits
-- within reach (default buildReach; holograms have no collision, so the
-- ray is tested against each one's box), and the distance. list = the
-- structures to test.
function L.AimedStructure(ply, list, reach)
    local start = ply:GetShootPos()
    local dir = ply:GetAimVector() * (reach or L.Cfg("buildReach"))
    local best, bestD
    for e in pairs(list) do
        if IsValid(e) then
            local hit = util.IntersectRayWithOBB(start, dir, e:GetPos(), e:GetAngles(), e:OBBMins(), e:OBBMaxs())
            if hit then
                local d = hit:DistToSqr(start)
                if not bestD or d < bestD then best, bestD = e, d end
            end
        end
    end
    return best, bestD and math.sqrt(bestD)
end

-- L.crates = { [crate] = true } (both realms; the crate entity keeps it).
L.crates = L.crates or {}
L.structures = L.structures or {}

-- L.SuppliesNear(pos) -> supplies in crates within buildSupplyRange.
function L.SuppliesNear(pos)
    local r = L.Cfg("buildSupplyRange")
    local n = 0
    for c in pairs(L.crates) do
        if IsValid(c) and c:GetPos():DistToSqr(pos) < r * r and not c:GetCarried() then n = n + c:GetSupplies() end
    end
    return n
end

-- Carrying a crate (sv_40_carry.lua; NW2Bool rhylib_carrying): no firing,
-- no sprinting, top speed carrySpeed. Shared so movement stays predicted.
Rhylib.Hook.Add("StartCommand", "logistics.carry", function(ply, cmd)
    if not ply:GetNW2Bool("rhylib_carrying", false) then return end
    cmd:RemoveKey(IN_ATTACK)
    cmd:RemoveKey(IN_ATTACK2)
    cmd:RemoveKey(IN_SPEED)
end)

Rhylib.Hook.Add("SetupMove", "logistics.carry", function(ply, mv)
    if not ply:GetNW2Bool("rhylib_carrying", false) then return end
    local cap = L.Cfg("carrySpeed")
    mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), cap))
    mv:SetMaxSpeed(math.min(mv:GetMaxSpeed(), cap))
end)
