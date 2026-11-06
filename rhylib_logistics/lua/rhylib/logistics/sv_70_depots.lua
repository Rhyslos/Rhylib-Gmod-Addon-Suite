--[[
    Supply depots (server; entities rhylib_supply_depot, rhylib_supply_crate,
    rhylib_fuel_canister).

    Once a second every depot (set L.depots) counts the supply crates and
    fuel canisters standing inside its ring (horizontal distance under its
    radius, within 100 units up or down, not being carried) into its DT
    Crates / Supplies / Fuel (written only when they change).

    L.DepotRows(pos, r) -> command post rows for the depots within r of pos:
    { name, kind = "Supplies", text, empty, dist } (sv_20_post.lua).

    Saved: Placements "logistics_depots" (Data "logistics_depots" / <map>):
    permanent depots (name n, radius r), supply crates (supplies s) and fuel
    canisters; console rhylib_depots_save (rhylib.logistics.admin). A
    carried one saves where it last stood (ent.rhylibHome, set when set
    down). A permanent crate or canister that is destroyed is gone from
    the save too.
]]

local L = Rhylib.Logistics

L.depots = L.depots or {}

local ITEM = { rhylib_supply_crate = true, rhylib_fuel_canister = true }
local UNITS_PER_M = 52.49

local seenAt = 0
local function count(depot)
    local pos, r = depot:GetPos(), math.max(16, depot:GetRadius())
    local r2 = r * r
    local crates, sup, fuel = 0, 0, 0
    -- (a crate / canister in two overlapping depots counts in the first only)
    for _, e in ipairs(ents.FindInSphere(pos, r + 100)) do
        if IsValid(e) and ITEM[e:GetClass()] and not e:GetCarried() and not e.broken and not e.boom then
            local p = e:GetPos()
            local dx, dy = p.x - pos.x, p.y - pos.y
            if dx * dx + dy * dy <= r2 and math.abs(p.z - pos.z) <= 100 and (e.rhylibDepotAt or 0) < seenAt then
                e.rhylibDepotAt = seenAt
                if e.rhylibDepotItem == "fuel" then
                    fuel = fuel + 1
                else
                    crates = crates + 1
                    sup = sup + e:GetSupplies()
                end
            end
        end
    end
    if depot:GetCrates() ~= crates then depot:SetCrates(crates) end
    if depot:GetSupplies() ~= sup then depot:SetSupplies(sup) end
    if depot:GetFuel() ~= fuel then depot:SetFuel(fuel) end
end

timer.Create("Rhylib.Logistics.Depots", 1, 0, function()
    seenAt = CurTime()
    for d in pairs(L.depots) do
        if IsValid(d) then count(d) else L.depots[d] = nil end
    end
end)

function L.DepotRows(pos, r)
    local rows = {}
    local r2 = r * r
    for d in pairs(L.depots) do
        if IsValid(d) and d:GetPos():DistToSqr(pos) <= r2 then
            local c, s, f = d:GetCrates(), d:GetSupplies(), d:GetFuel()
            local parts = {}
            if c > 0 then parts[#parts + 1] = c .. (c == 1 and " crate · " or " crates · ") .. s end
            if f > 0 then parts[#parts + 1] = f .. " fuel" end
            rows[#rows + 1] = { name = d:GetBeaconName(), kind = "Supplies", text = #parts > 0 and table.concat(parts, " · ") or "Empty",
                empty = #parts == 0, dist = math.floor(d:GetPos():Distance(pos) / UNITS_PER_M) }
        end
    end
    return rows
end

-- A crate destroyed: nothing to do beyond the next count (RP stock only).
function L.DepotItemLost(ent) end

if Rhylib.Perma and Rhylib.Perma.Placements then
    L.DepotPlaces = Rhylib.Perma.Placements("logistics_depots", {
        classes = { "rhylib_supply_depot", "rhylib_supply_crate", "rhylib_fuel_canister" },
        dataModule = "logistics_depots",
        -- (a crate / canister being carried saves where it last stood)
        posOf = function(e) return e.GetCarried and e:GetCarried() and e.rhylibHome or nil end,
        preSpawn = function(e, row)
            if row.r then e.ZoneRadius = tonumber(row.r) end
        end,
        save = function(e)
            local c = e:GetClass()
            if c == "rhylib_supply_depot" then return { n = e:GetBeaconName(), r = math.floor(e:GetRadius()) } end
            if c == "rhylib_supply_crate" then return { s = e:GetSupplies() } end
            return {}
        end,
        load = function(e, row)
            local c = e:GetClass()
            e.rhylibHome = e:GetPos()
            if c == "rhylib_supply_depot" then
                if isstring(row.n) and row.n ~= "" then e:SetBeaconName(string.sub(row.n, 1, 32)) end
                if tonumber(row.r) then e:SetRadius(math.Clamp(tonumber(row.r), 16, 4000)) end
            elseif c == "rhylib_supply_crate" and tonumber(row.s) then
                e:SetSupplies(math.Clamp(math.floor(tonumber(row.s)), 1, 100000))
            end
        end,
        command = "rhylib_depots_save",
        perm = "rhylib.logistics.admin",
    })
end
