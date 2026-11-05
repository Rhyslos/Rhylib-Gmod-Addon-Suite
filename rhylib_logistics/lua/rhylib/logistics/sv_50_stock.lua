--[[
    Rhy's Logistics (server): the armoury stock (sh_40_stock.lua has the
    settings).

    L.stock[id] = how many are left (an item missing from it is full).
    rhylib_inventory asks through hook Rhylib.DepotStock(id) for counted
    depots (the armoury's weapons armoury, ammo and gear cabinets and
    specialist racks) and tells us through Rhylib.DepotTook (lower),
    Rhylib.DepotReturned (handed in: back up) and Rhylib.WorldItemExpired
    (left on the ground and gone: back up); both only for items a counted
    depot handed out (data.stock, Inv.StockMarked: not training, crate or
    spawned copies, not part-used magazines). Every
    change is pushed to whoever has a counted depot open (throttled).

    L.StockLeft(id) -> left, max (nil = endless). L.Restock(share, by)
    puts back share of each max (the resupply crate). L.SetStock(id, n).
    L.LowStock(n) -> the items with the lowest share left (for the
    command post). Saved: Data "logistics" "stock" (stockSave on).
    Command !stock [full | <item> <n>] (rhylib.logistics.admin).
]]

local L = Rhylib.Logistics
local Inv = Rhylib.Inventory

L.stock = L.stock or {}

local loaded = false
local function load()
    if loaded then return end
    loaded = true
    if not L.Cfg("stockSave") then return end
    local saved = Rhylib.Data.Get("logistics", "stock")
    if istable(saved) then
        for id, n in pairs(saved) do
            if isstring(id) and tonumber(n) then L.stock[id] = math.max(0, math.floor(tonumber(n))) end
        end
    end
end

local function save()
    if not L.Cfg("stockSave") then return end
    Rhylib.Data.Set("logistics", "stock", L.stock)
end

function L.StockLeft(id)
    load()
    local max = L.StockMax(id)
    if not max then return nil end
    local n = L.stock[id]
    if n == nil then return max, max end
    return math.Clamp(n, 0, max), max
end

-- Pushes new counts to open depots: at most twice a second.
local pending = false
local function changed()
    save()
    if pending then return end
    pending = true
    timer.Simple(0.5, function()
        pending = false
        if Inv and Inv.RefreshDepotStock then Inv.RefreshDepotStock() end
    end)
end

function L.SetStock(id, n)
    local _, max = L.StockLeft(id)
    if not max then return false end
    n = math.Clamp(math.floor(n), 0, max)
    -- (full: nothing to keep, so a raised max shows as full too)
    L.stock[id] = n < max and n or nil
    changed()
    return true
end

local function add(id, n)
    local left = L.StockLeft(id)
    if not left or not n or n == 0 then return end
    L.SetStock(id, left + n)
end

Rhylib.Hook.Add("Rhylib.DepotStock", "logistics.stock", function(id)
    local left = L.StockLeft(id)
    return left
end)

Rhylib.Hook.Add("Rhylib.DepotTook", "logistics.stock", function(ply, id, n)
    add(id, -(tonumber(n) or 1))
end)

Rhylib.Hook.Add("Rhylib.DepotReturned", "logistics.stock", function(ply, id, n)
    add(id, tonumber(n) or 1)
end)

-- (only what a counted armoury handed out: data.stock, full ones)
Rhylib.Hook.Add("Rhylib.WorldItemExpired", "logistics.stock", function(id, n, data)
    local marked = Inv and Inv.StockMarked
    if marked and marked(data) then add(id, tonumber(n) or 1) end
end)

-- L.Restock(share): each counted item gets share of its max back.
-- Returns how many kinds of item went up.
function L.Restock(share)
    load()
    local Items = Rhylib.Items
    if not (Items and Items.defs) then return 0 end
    local up = 0
    for id in pairs(Items.defs) do
        local left, max = L.StockLeft(id)
        if left and left < max then
            L.stock[id] = math.min(max, left + math.max(1, math.ceil(max * share)))
            if L.stock[id] >= max then L.stock[id] = nil end
            up = up + 1
        end
    end
    if up > 0 then changed() end
    return up
end

-- L.LowStock(n) -> { { id, name, left, max }, ... } lowest share first,
-- only items below 60%.
function L.LowStock(n)
    load()
    local Items = Rhylib.Items
    local out = {}
    for id in pairs(L.stock) do
        local left, max = L.StockLeft(id)
        if left and left < max * 0.6 then
            local def = Items and Items.defs and Items.defs[id]
            out[#out + 1] = { id = id, name = def and def.name or id, left = left, max = max }
        end
    end
    table.sort(out, function(a, b) return a.left / a.max < b.left / b.max end)
    for i = #out, (n or 8) + 1, -1 do out[i] = nil end
    return out
end

-- (stock switched off and on, or saving switched: start clean)
Rhylib.Hook.Add("Rhylib.ConfigChanged", "logistics.stock", function(m, k)
    if m ~= "logistics" then return end
    if k == "stockOn" or k == "stockMax" or k == "stockDefault" then
        changed()
    elseif k == "stockSave" and not L.Cfg("stockSave") then
        Rhylib.Data.Delete("logistics", "stock")
    end
end)

-- ---------------------------------------------------------------------------
-- Resupply crates: set down near an armoury cabinet, they unload.

local RESTOCKS = { armoury = true, ammo = true, gear = true, spec = true }

-- Called by the resupply crate when it's set down (and when staff place
-- one right next to a cabinet). True when it unloaded.
function L.ResupplyAt(crate, by)
    if not IsValid(crate) or crate.rhylibUnloaded then return false end
    local range = L.Cfg("resupplyRange")
    local near
    for _, e in ipairs(ents.FindInSphere(crate:GetPos(), range)) do
        if IsValid(e) and RESTOCKS[e.ArmouryKind or ""] then near = e break end
    end
    if not near then
        if IsValid(by) then Rhylib.Notify(by, "Set it down next to an armoury, ammo or gear cabinet to restock", "info", "Logistics") end
        return false
    end
    crate.rhylibUnloaded = true
    local share = L.Cfg("resupplyAmount")
    local up = L.Restock(share)
    local who = IsValid(by) and by:Nick() or "Someone"
    Rhylib.Print("logistics", "%s unloaded an armoury resupply crate (%d items restocked)", who, up)
    local text = up > 0 and ("Armoury restocked: " .. math.Round(share * 100) .. "% of each item put back")
        or "The armoury was already full: the crate goes back"
    local hear = {}
    for _, p in ipairs(player.GetAll()) do
        if p:GetPos():DistToSqr(crate:GetPos()) < 900 * 900 then hear[#hear + 1] = p end
    end
    if #hear > 0 then Rhylib.Notify(hear, text, up > 0 and "good" or "info", "Logistics") end
    crate:EmitSound("items/ammocrate_open.wav", 70)
    crate:Remove()
    return true
end

-- ---------------------------------------------------------------------------

Rhylib.Command.Add({
    name = "rhylib_stock", chat = { "stock" }, perm = "rhylib.logistics.admin", tag = "Logistics",
    args = "[full | low | <item id> <n>]", help = "Armoury stock: refill everything, list what's low, or set one item",
    fn = function(ply, args)
        local op = string.lower(args[1] or "")
        if not L.Cfg("stockOn") then return "Armoury stock is off (Server settings > Logistics stockOn): everything is endless", "info" end
        if op == "full" then
            L.stock = {}
            changed()
            return "Armoury stock refilled", "good"
        elseif op == "" or op == "low" then
            local low = L.LowStock(10)
            if #low == 0 then return "Armoury stock: nothing below 60%", "info" end
            local parts = {}
            for _, r in ipairs(low) do parts[#parts + 1] = r.name .. " " .. r.left .. "/" .. r.max end
            return "Low: " .. table.concat(parts, ", "), "info"
        end
        local n = tonumber(args[2] or "")
        if not n then return "Use !stock full, !stock low or !stock <item id> <n>", "bad" end
        if not L.SetStock(args[1], n) then return args[1] .. " isn't counted (unknown, endless or training)", "bad" end
        local left, max = L.StockLeft(args[1])
        return args[1] .. ": " .. left .. "/" .. max, "good"
    end,
})
