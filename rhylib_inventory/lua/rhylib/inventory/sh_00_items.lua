--[[
    Item registry and shared grid rules.

    Register an item (shared, at load time):
        Rhylib.Items.Register("mag", {
            name = "Blaster magazine",
            w = 1, h = 1,          -- size in cells
            stack = 5,             -- max per stack (1 = doesn't stack)
            fill = true,           -- has a 0-1 fill level (partly used magazines, cells)
            category = "ammo",     -- weapon, ammo, medical, gear, misc (sets the colour)
            model = "models/items/boxmrounds.mdl",  -- used when dropped
        })
    Optional: large = true (not allowed in backpacks), slot = "back" (worn
    in the back slot), grid = { 5, 2 } (a worn item that adds a grid),
    weight = 0.5 (kg, per item), carry = 6 (worn item that raises the
    carry cap by this many kg), rounds = 60 (magazines: shots when full).

    Weapons become items automatically if their SWEP table sets InvW/InvH.
    Optional SWEP fields: InvStack (stack size, e.g. medical kits),
    InvUses (uses when full; stored as fill), InvCharge (a 0-1 charge
    shown as %), InvCategory, InvWeight.
    Per-player stack size: Items.StackFor(def, ply) (hook Rhylib.ItemStack
    can lower it, e.g. medkits 3 for troopers, 5 for medics).

    An item instance:
        { uid, c, id, x, y, rot, count, data }     -- c = container id (see below)
    x, y are the top-left cell (0-based). rot swaps width and height.
    Only items with fill = true stack when full; partly used ones stay single.

    On the network each item type is a small number (netId), assigned by
    sorting ids, so server and client agree without sending names.
]]

Rhylib.Items = Rhylib.Items or {}
local Items = Rhylib.Items

Items.defs = Items.defs or {}
Items.byNet = Items.byNet or {}
Items.finalized = false

Items.UID_BITS = 16
Items.NET_BITS = 10       -- up to 1023 item types
Items.POS_BITS = 5        -- containers up to 32 x 32 (the training deposit grows to 31 rows)
Items.COUNT_BITS = 8

function Items.Register(id, def)
    def.id = id
    def.name = def.name or id
    def.w = def.w or 1
    def.h = def.h or 1
    def.stack = def.stack or 1
    def.category = def.category or "misc"
    Items.defs[id] = def
    Items.finalized = false
end

function Items.Get(id)
    return Items.defs[id]
end

-- Groups for storage shelves (depots lay their stock out under headings).
-- def.group overrides (guns: SWEP.InvGroup rifle / carbine / pistol / heavy /
-- shotgun / sniper / grenade); back-slot items are "back"; else def.category.
Items.GROUP_ORDER = { "rifle", "carbine", "pistol", "heavy", "shotgun", "sniper", "weapon", "grenade", "training", "ammo", "medical", "back", "body", "helmet", "gear", "misc" }
Items.GROUP_NAMES = { rifle = "Rifles", carbine = "Carbines", pistol = "Pistols", heavy = "Heavy", shotgun = "Shotguns",
    sniper = "Snipers", grenade = "Grenades & charges", weapon = "Other weapons", training = "Training", ammo = "Ammunition", medical = "Medical",
    back = "Back", body = "Body armour & kit", helmet = "Helmet gear", gear = "Equipment", misc = "Other" }

function Items.GroupOf(def)
    if not def then return "misc" end
    if def.group then return def.group end
    if def.slot == "back" then return "back" end
    return def.category or "misc"
end

-- Sort key of a group (unknown groups after the known ones).
function Items.GroupRank(g)
    for i, k in ipairs(Items.GROUP_ORDER) do if k == g then return i end end
    return #Items.GROUP_ORDER + 1
end

-- A weapon item you can only carry one of (guns). Stacking weapon items
-- (medical kits) can be carried in several stacks.
function Items.Unique(def)
    return def and def.weapon and def.stack <= 1 or false
end

function Items.Finalize()
    local ids = {}
    for id in pairs(Items.defs) do ids[#ids + 1] = id end
    table.sort(ids)
    Items.byNet = {}
    for i, id in ipairs(ids) do
        Items.defs[id].netId = i
        Items.byNet[i] = Items.defs[id]
    end
    Items.finalized = true
end

-- Weapons are registered as items once, then ids are assigned.
function Items.EnsureReady()
    if not Items.weaponsDone then
        Items.RegisterWeapons()
        Items.weaponsDone = true
    end
    if not Items.finalized then Items.Finalize() end
end

function Items.NetId(id)
    Items.EnsureReady()
    local def = Items.defs[id]
    return def and def.netId or 0
end

function Items.FromNet(n)
    Items.EnsureReady()
    return Items.byNet[n]
end

-- Any weapon that declares an inventory size becomes an item.
function Items.RegisterWeapons()
    for _, stored in ipairs(weapons.GetList()) do
        local class = stored.ClassName
        if class and not Items.defs[class] then
            local full = weapons.Get(class)
            if full and full.InvW then
                Items.Register(class, {
                    name = full.PrintName or class,
                    w = full.InvW,
                    h = full.InvH or 1,
                    model = full.WorldModel,
                    category = full.InvCategory or "weapon",
                    group = full.InvGroup,
                    weapon = class,
                    large = full.InvLarge,
                    weight = full.InvWeight,
                    stack = full.InvStack,
                    fill = (full.InvUses or full.InvCharge) and true or nil,
                    rounds = full.InvUses,
                    unit = full.InvUses and "uses" or nil,
                    carrySkill = full.CarrySkill,   -- (rhylib_skills: only players with it may carry it)
                    -- Fits a holster: SWEP.InvHolster (true/false), or a small pistol.
                    -- (Not SWEP.Holster: that's the weapon's holster function, so
                    -- every gun had a function here and none fitted.)
                    holster = (full.InvHolster ~= nil and full.InvHolster == true)
                        or (full.InvHolster == nil and full.HoldType == "pistol"
                        and (full.InvW or 1) <= 2 and (full.InvH or 1) <= 1) or nil,
                })
            end
        end
    end
end

-- Weapons are registered by now on both server and client.
Rhylib.Hook.Add("InitPostEntity", "inventory.items", function()
    Items.weaponsDone = false
    Items.EnsureReady()
end, -10)

-- Placeholder model; no bodygroups yet.
Items.Register("backpack", {
    name = "Backpack",
    w = 2, h = 2,
    category = "gear",
    slot = "back",
    grid = { 5, 2 },
    weight = 1.5,
    carry = 6,
    model = "models/props_c17/suitcase001a.mdl",
})

--------------------------------------------------------------------------
-- Weight
--
-- Total = every item's weight x count. Items inside a backpack count at
-- backpackWeightMult, because the pack spreads the load. The carry cap is
-- baseCarry plus the `carry` of whatever is worn on the back.
-- The server sends both numbers to the stamina module through two NW2
-- vars; the inventory window works them out itself from its own copy.
--------------------------------------------------------------------------

local Config = Rhylib.Config
Config.Register("inventory", "baseCarry", 18, "Carry cap in kg without a backpack")
Config.Register("inventory", "giveRange", 130, "How close you must be to give someone an item")
Config.Register("inventory", "backpackWeightMult", 0.8, "Items inside a backpack count at this fraction of their weight")
Config.Register("inventory", "contraband", {}, "Contraband item ids: players can hide up to 3 of them from searches, and they're never returned from jail")

-- Contraband (config list), cached per change of the list.
local cbList, cbSet
function Items.IsContraband(id)
    local list = Config.Get("inventory", "contraband")
    if list ~= cbList then
        cbList, cbSet = list, {}
        if istable(list) then for _, v in ipairs(list) do cbSet[v] = true end end
    end
    return cbSet[id] == true
end

Items.HIDE_MAX = 3   -- hidden items per player (data.hidden = their SteamID64)

-- state: { cont = { [cid] = { items } } }. Returns weight, cap in kg.
function Items.Weight(state)
    local total, cap = 0, Config.Get("inventory", "baseCarry")
    local packMult = Config.Get("inventory", "backpackWeightMult")
    -- Worn items can lighten others (def.weightMults = { [id] = mult }: a
    -- gun belt carries the DC-15A and RPS-6); the lightest applies.
    local lighter
    for wcid in pairs(Items.WORN) do
        local wc = state.cont[wcid]
        for _, o in pairs(wc and wc.items or {}) do
            local d = Items.defs[o.id]
            if d and d.weightMults then
                lighter = lighter or {}
                for id, m in pairs(d.weightMults) do lighter[id] = math.min(lighter[id] or 1, m) end
            end
        end
    end
    for cid, c in pairs(state.cont) do
        if cid ~= Items.EXT then  -- an open locker isn't carried
            local mult = cid == Items.BACK and packMult or 1
            for _, o in pairs(c.items) do
                local def = Items.defs[o.id]
                if def then
                    total = total + (def.weight or 0) * o.count * mult * (lighter and lighter[o.id] or 1)
                    if Items.WORN[cid] and def.carry then cap = cap + def.carry end
                end
            end
        end
    end
    return total, cap
end

-- Weight and cap for any player, from the networked values.
function Items.PlayerWeight(ply)
    return ply:GetNW2Float("rhylib_weight", 0), ply:GetNW2Float("rhylib_carry", Config.Get("inventory", "baseCarry"))
end

--------------------------------------------------------------------------
-- Grid rules (used by the server to validate and the client to preview)
--------------------------------------------------------------------------

function Items.Size(id, rot)
    local def = Items.defs[id]
    if not def then return 1, 1 end
    if rot then return def.h, def.w end
    return def.w, def.h
end

function Items.IsFull(inst)
    local def = Items.defs[inst.id]
    return not (def and def.fill) or (inst.data and inst.data.fill or 1) >= 1
end

-- Can item `id` sit at x, y in a w x h container holding `items` (uid -> inst)?
function Items.Fits(cw, ch, items, id, x, y, rot, ignoreUid)
    if not Items.defs[id] then return false end
    local w, h = Items.Size(id, rot)
    if x < 0 or y < 0 or x + w > cw or y + h > ch then return false end
    for uid, o in pairs(items) do
        if uid ~= ignoreUid then
            local ow, oh = Items.Size(o.id, o.rot)
            if x < o.x + ow and x + w > o.x and y < o.y + oh and y + h > o.y then
                return false
            end
        end
    end
    return true
end

-- The item covering cell x, y, if any.
function Items.At(items, x, y, ignoreUid)
    for uid, o in pairs(items) do
        if uid ~= ignoreUid then
            local ow, oh = Items.Size(o.id, o.rot)
            if x >= o.x and x < o.x + ow and y >= o.y and y < o.y + oh then
                return o
            end
        end
    end
end

-- First free spot for item `id` in a container { w, h, items }: x, y, rot.
function Items.FindSpot(c, id)
    local def = Items.defs[id]
    if not def or not c then return nil end
    local square = def.w == def.h
    for y = 0, c.h - 1 do
        for x = 0, c.w - 1 do
            if Items.Fits(c.w, c.h, c.items, id, x, y, false) then return x, y, false end
            if not square and Items.Fits(c.w, c.h, c.items, id, x, y, true) then return x, y, true end
        end
    end
end

-- Stack size in this player's inventory (def.stack, or less if the
-- Rhylib.ItemStack hook says so).
function Items.StackFor(def, ply)
    if not ply then return def.stack end
    local r = hook.Run("Rhylib.ItemStack", def, ply)
    return isnumber(r) and math.Clamp(math.floor(r), 1, def.stack) or def.stack
end

-- If dropping `inst` with its top-left on x, y should merge into a stack,
-- return that stack. ply: a player's container (their stack size applies).
function Items.MergeTarget(items, inst, x, y, ply)
    local def = Items.defs[inst.id]
    if not def or def.stack <= 1 or not Items.IsFull(inst) then return nil end
    local cap = Items.StackFor(def, ply)
    local target = Items.At(items, x, y, inst.uid)
    if target and target.id == inst.id and target.count < cap and Items.IsFull(target)
        and Items.SameIssued(target, inst) then
        return target
    end
end

-- Issued (armoury) and normal items never stack together, or the issued
-- mark could be lost.
function Items.SameIssued(a, b)
    local ia = a.data and a.data.issued and true or false
    local ib = b.data and b.data.issued and true or false
    local la = a.data and a.data.loadout and true or false
    local lb = b.data and b.data.loadout and true or false
    return ia == ib and la == lb   -- (job loadout gear keeps to itself too)
end

--------------------------------------------------------------------------
-- Containers
--
-- A player has up to four containers, each with its own items table:
--   1  main grid (6 x 3, config inventory width / height)
--   2  backpack grid, only while a backpack is worn (size from the backpack)
--   3  back slot: holds one item with slot = "back"
--   5  cell rack: only power cells, opened by a skill (rhylib_skills)
--   6  ammo belt (rhylib_skills)
--   7  holster: pistols, while a holster is worn
--   8-17 worn gear slots (kama, pauldron, binoculars, rangefinder, helmet
--      light, holster, sun visor, forearm, shoulder antenna, belt pouches),
--      one item each with that `slot` (rhylib_gear)
--   4  an outside container the player has open (locker, armoury, crate),
--      see sv_30_storage.lua. Its items have their own uids.
-- Worn slots (the back slot and the gear slots) hold one item each; a worn
-- item with `grid` adds a container (gridCid, default the backpack grid)
-- and can only come off while that container is empty.
-- Both server and client keep state shaped like { cont = { [id] = { w, h, items } } }
-- so the same placement rules run on both.
--------------------------------------------------------------------------

Items.MAIN = 1
Items.BACK = 2
Items.SLOT_BACK = 3
Items.EXT = 4
Items.RACK = 5       -- cell rack (rhylib_skills Load bearer): power cells only
Items.BELT = 6       -- ammo belt (rhylib_skills Ammo belt): no worn items, no long guns (5+ cells)
Items.HOLSTER = 7    -- pistols (def.holster), while a holster is worn (2x2: both holsters)
Items.POUCH = 18     -- belt pouches (worn belt pouches): like the ammo belt
Items.CELLPACK = 19  -- ARC backpack's side pouch: power cells only
Items.CONT_BITS = 5   -- (containers 0-31; gear slots 8-17)

-- Worn slots: [cid] = { slot = def.slot, title }. GEAR_SLOTS in display order.
Items.WORN = {
    [Items.SLOT_BACK] = { slot = "back", title = "Back" },
    [8] = { slot = "kama", title = "Kama" },
    [9] = { slot = "pauldron", title = "Pauldron" },
    [10] = { slot = "binos", title = "Binoculars" },
    [11] = { slot = "rangefinder", title = "Rangefinder" },
    [12] = { slot = "light", title = "Helmet light" },
    [13] = { slot = "holster", title = "Holster" },
    [14] = { slot = "visor", title = "Sun visor" },
    [15] = { slot = "forearm", title = "Forearm" },
    [16] = { slot = "comms", title = "Shoulder antenna" },
    [17] = { slot = "belt", title = "Belt pouches" },
}
Items.GEAR_SLOTS = { 8, 9, 15, 17, 13, 16, 10, 11, 12, 14 }
Items.WORN_BY_SLOT = {}
for cid, w in pairs(Items.WORN) do Items.WORN_BY_SLOT[w.slot] = cid end

function Items.IsWorn(cid) return Items.WORN[cid] ~= nil end

-- Is any item worn in this slot registered? (No rhylib_gear: no gear slots.)
function Items.SlotUsed(slot)
    for _, def in pairs(Items.defs) do
        if def.slot == slot then return true end
    end
    return false
end

-- Can ply wear this item now? (rhylib_gear: only parts their model shows.)
-- Hook Rhylib.CanWear(ply, def) returns false, reason to refuse.
function Items.CanWear(ply, def)
    if not (def and def.slot) or def.slot == "back" or not IsValid(ply) then return true end
    local ok, why = hook.Run("Rhylib.CanWear", ply, def)
    if ok == false then return false, why or "You can't wear that" end
    return true
end

-- Hotbar: each item can sit in one numbered slot (inst.hb). 4 slots, or
-- 6 while a backpack is worn. Anything you hold that isn't in the
-- inventory (force-given) goes in an overflow slot after them.
Items.HOTBAR = 4
Items.HOTBAR_PACK = 6

function Items.HotbarSize(state)
    return state.cont[Items.BACK] and Items.HOTBAR_PACK or Items.HOTBAR
end

-- Which items a container accepts at all.
function Items.ContainerAllows(cid, def)
    local worn = Items.WORN[cid]
    if worn then return def.slot == worn.slot end
    if cid == Items.HOLSTER then return def.holster == true end
    if cid == Items.EXT then return true end  -- the storage itself decides (sv_30_storage.lua)
    if cid == Items.BACK then return not def.large and not def.grid end
    if cid == Items.RACK or cid == Items.CELLPACK then return def.id == "cell" end
    if cid == Items.BELT or cid == Items.POUCH then return not def.grid and not def.slot and not (def.weapon and def.w >= 5) end
    return true
end

-- Can item `id` go to container cid at x, y? ignoreUid: the item being moved.
function Items.CanPlace(state, id, cid, x, y, rot, ignoreUid)
    local def = Items.defs[id]
    local c = state.cont[cid]
    if not def or not c or not Items.ContainerAllows(cid, def) then return false end
    if Items.WORN[cid] then
        if x ~= 0 or y ~= 0 then return false end
        for uid in pairs(c.items) do
            if uid ~= ignoreUid then return false end
        end
        return true
    end
    return Items.Fits(c.w, c.h, c.items, id, x, y, rot, ignoreUid)
end

-- A worn item that adds a container (backpack, holster) can only come off
-- when that container is empty. Returns false, reason.
function Items.CanLeave(state, inst)
    if Items.WORN[inst.c] then
        local def = Items.defs[inst.id]
        if def and def.grid then
            local g = state.cont[def.gridCid or Items.BACK]
            if g and next(g.items) ~= nil then
                return false, "Empty the " .. string.lower(def.gridName or "backpack") .. " first"
            end
        end
        -- (def.extraGrids = { { cid, w, h, name } }: more containers it adds)
        for _, eg in ipairs(def and def.extraGrids or {}) do
            local g = state.cont[eg.cid]
            if g and next(g.items) ~= nil then
                return false, "Empty the " .. string.lower(eg.name or "pouch") .. " first"
            end
        end
    end
    return true
end

--------------------------------------------------------------------------
-- Network encoding: about 6 bytes per item. data.issued (gear from an
-- armoury or ammo cabinet) is one bit.
--------------------------------------------------------------------------

function Items.WriteInstance(inst)
    local def = Items.defs[inst.id]
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(inst.c or Items.MAIN, Items.CONT_BITS)
    net.WriteUInt(Items.NetId(inst.id), Items.NET_BITS)
    net.WriteUInt(inst.x, Items.POS_BITS)
    net.WriteUInt(inst.y, Items.POS_BITS)
    net.WriteBool(inst.rot and true or false)
    net.WriteUInt(math.Clamp(inst.count, 0, 255), Items.COUNT_BITS)
    net.WriteBool(inst.data and inst.data.issued or false)
    net.WriteUInt(inst.hb or 0, 3)  -- hotbar slot, 0 = none
    net.WriteBool(inst.data and isstring(inst.data.hidden) or false)
    if def and def.fill then
        net.WriteUInt(math.Round(math.Clamp(inst.data and inst.data.fill or 1, 0, 1) * 255), 8)
    end
    -- def.note: a short text the item carries (blood samples: patient, reading)
    if def and def.note then
        local note = tostring(inst.data and inst.data.note or "")
        if #note > 120 then note = string.sub(note, 1, (utf8.offset(note, 100) or 101) - 1) end   -- (whole characters)
        net.WriteString(note)
    end
end

function Items.ReadInstance()
    local uid = net.ReadUInt(Items.UID_BITS)
    local c = net.ReadUInt(Items.CONT_BITS)
    local def = Items.FromNet(net.ReadUInt(Items.NET_BITS))
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    local count = net.ReadUInt(Items.COUNT_BITS)
    local data = { issued = net.ReadBool() or nil }
    local hb = net.ReadUInt(3)
    data.hidden = net.ReadBool() or nil
    if def and def.fill then data.fill = net.ReadUInt(8) / 255 end
    if def and def.note then data.note = net.ReadString() end
    return { uid = uid, c = c, id = def and def.id, x = x, y = y, rot = rot, count = count, data = data, hb = hb > 0 and hb or nil }
end

-- The "item in your hand" weapon (lua/weapons/rhylib_hand.lua): hotbar
-- items with def.hand (magazines, cells) are held with it.
Rhylib.Inventory = Rhylib.Inventory or {}
Rhylib.Inventory.HAND = "rhylib_hand"
