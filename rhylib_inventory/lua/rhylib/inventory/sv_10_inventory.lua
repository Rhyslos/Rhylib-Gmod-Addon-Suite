--[[
    Server inventory. The server owns every container; clients only ask.

    Each player has a state table:
        { cont = { [1] = main grid, [2] = backpack grid (while worn), [3] = back slot },
          byUid = { [uid] = inst }, nextUid, ready }
    Container ids and placement rules are in sh_00_items.lua.

    Networking (to the owner only):
      - "inv.full"  everything, sent once when the client asks after joining
      - "inv.upd"   batched per tick: changed items, removed items, and
                    container size changes (backpack put on or taken off)
    Client requests (rate limited): inv.req, inv.move, inv.drop, inv.use,
    inv.split, inv.combine. Outside containers (lockers, armouries,
    crates) are in sv_30_storage.lua.

    Issued gear (data.issued, from an armoury or ammo cabinet) isn't
    dropped on the ground: dropping it hands it back.

    Saving: changed inventories are marked dirty and written to SQLite
    every few seconds (Rhylib.Data batches the writes further).

    Weapons: an item with a `weapon` class gives that weapon while it's in
    any container, and strips it when the item leaves. Clip and power cell
    are stored in the item via the weapon's GetInventoryData / SetInventoryData.

    Other modules can listen to:
      Rhylib.InventoryChanged(ply)
      Rhylib.InventoryWeaponPickup(ply, class)   -- a new weapon was picked up
]]

Rhylib.Inventory = Rhylib.Inventory or {}
local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local Config = Rhylib.Config

local MAIN, BACK, SLOT_BACK, RACK, BELT, HOLSTER = Items.MAIN, Items.BACK, Items.SLOT_BACK, Items.RACK, Items.BELT, Items.HOLSTER
local IsWorn = Items.IsWorn

Config.Register("inventory", "width", 5, "Personal inventory width in cells")
Config.Register("inventory", "height", 3, "Personal inventory height in cells")
Config.Register("inventory", "saveInterval", 2, "Seconds between saves of changed inventories")
Config.Register("inventory", "worldItemLife", 600, "Seconds before a dropped item on the ground is removed (0 = never)")
Config.Register("inventory", "issuedDropLife", 300, "Seconds before dropped issued (armoury) gear is removed")
Config.Register("inventory", "worldItemMax", 300, "Most dropped items on the ground at once; the oldest goes first")
Config.Register("inventory", "worldItemPerPlayer", 15, "Most dropped items one player can have on the ground; their oldest goes first")
Config.Register("inventory", "autoHotbar", true, "New weapons go into the first free hotbar slot")
Config.Register("inventory", "combineTime", 1.5, "Combining munitions: seconds per partly used magazine or cell (total at least 3 s, at most combineMax)")
Config.Register("inventory", "combineMax", 30, "Combining munitions: longest it takes (seconds)")

Inv.states = Inv.states or {}  -- [ply] = state
Inv.dirty = Inv.dirty or {}    -- [ply] = true

Rhylib.Net.Register("inv.full")
Rhylib.Net.Register("inv.busy")
Rhylib.Net.Register("inv.note")

local OP_REMOVE, OP_SET, OP_DIMS = 0, 1, 2

local updBatch = Rhylib.Net.CreateBatch("inv.upd", function(ch)
    net.WriteUInt(ch.op, 2)
    if ch.op == OP_SET then
        Items.WriteInstance(ch.inst)
    elseif ch.op == OP_REMOVE then
        net.WriteUInt(ch.uid, Items.UID_BITS)
    else
        net.WriteUInt(ch.cid, Items.CONT_BITS)
        net.WriteUInt(ch.w, 5)
        net.WriteUInt(ch.h, 5)
    end
end)

--------------------------------------------------------------------------
-- Weapons
--------------------------------------------------------------------------

-- Another item of the same gun still carried (an officer's two DC-17s
-- share one weapon entity), or nil.
local function twinOf(ply, inst)
    local st = Inv.states[ply]
    if not st then return nil end
    for uid, o in pairs(st.byUid) do
        if uid ~= inst.uid and o.id == inst.id then return o end
    end
end

-- Data for a second copy that isn't the gun in your hands: empty, or in
-- dual mode the second magazine, taken out of the live gun (take = true).
local function spareData(wep, take)
    local live = wep:GetInventoryData() or {}
    local data = { mag = live.mag, clip = 0, mode = 1, magIssued = live.magIssued }
    if take and wep.GetFireModeName and wep:GetFireModeName() == "dual" then
        local single = math.floor(wep:GetMagSize() / (wep.DualMags or 2))
        local extra = math.min(wep:Clip1() - single, single)
        if extra > 0 then
            wep:SetClip1(wep:Clip1() - extra)
            data.clip = extra
        end
    end
    return data
end

-- The weapon's state (clip, mode...) into its item. staying: the item stays
-- with the player (saving); otherwise it's about to leave. With two copies
-- the one leaving only takes a spare's share (no ammo copied).
local function captureWeapon(ply, inst, staying, primary)
    local def = Items.defs[inst.id]
    if not def or not def.weapon then return end
    local wep = ply:GetWeapon(def.weapon)
    if IsValid(wep) and wep.GetInventoryData then
        local issued, loadout = inst.data and inst.data.issued, inst.data and inst.data.loadout
        local twin = twinOf(ply, inst)
        if twin and not staying then
            inst.data = spareData(wep, true)
        elseif twin and primary == false then
            inst.data = spareData(wep, false)
        else
            inst.data = wep:GetInventoryData() or inst.data
        end
        inst.data.issued, inst.data.loadout = issued, loadout  -- keep the armoury / job marks
    end
end

local function giveWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon or not ply:Alive() or ply:HasWeapon(def.weapon) then return end
    ply.rhylibGiving = true
    local wep = ply:Give(def.weapon, true)
    ply.rhylibGiving = false
    if IsValid(wep) and wep.SetInventoryData then
        wep:SetInventoryData(inst.data)
    end
end

Inv.STOWED = "rhylib_stowed"  -- the empty weapon (lua/weapons/rhylib_stowed.lua)

-- Put the gun away: hold the empty Stowed weapon.
function Inv.Stow(ply)
    if not ply:HasWeapon(Inv.STOWED) then ply:Give(Inv.STOWED) end
    ply:SelectWeapon(Inv.STOWED)
end

local function stripWeapon(ply, inst)
    local def = Items.defs[inst.id]
    if not def or not def.weapon then return end
    -- Another stack of the same kit is still carried: keep the weapon.
    local st = Inv.states[ply]
    if st then
        for uid, o in pairs(st.byUid) do
            if uid ~= inst.uid and o.id == inst.id then return end
        end
    end
    captureWeapon(ply, inst)
    if ply:HasWeapon(def.weapon) then
        local active = ply:GetActiveWeapon()
        local wasActive = IsValid(active) and active:GetClass() == def.weapon
        ply:StripWeapon(def.weapon)
        if wasActive then Inv.Stow(ply) end
    end
end

function Inv.CaptureWeapons(ply)
    local st = Inv.states[ply]
    if not st then return end
    -- (two copies of one gun: the lowest uid holds the live state)
    local first = {}
    for uid, inst in pairs(st.byUid) do
        if not first[inst.id] or uid < first[inst.id] then first[inst.id] = uid end
    end
    for uid, inst in pairs(st.byUid) do captureWeapon(ply, inst, true, first[inst.id] == uid) end
end

function Inv.GiveAllWeapons(ply)
    -- Lowest uid first: of two copies, that one's state is the live gun's.
    local list = {}
    for _, inst in pairs(Inv.Get(ply).byUid) do list[#list + 1] = inst end
    table.sort(list, function(a, b) return a.uid < b.uid end)
    for _, inst in ipairs(list) do giveWeapon(ply, inst) end
end

--------------------------------------------------------------------------
-- State and low-level changes
--------------------------------------------------------------------------

local function nextUid(st)
    for _ = 1, 65535 do
        local uid = st.nextUid
        st.nextUid = uid % 65535 + 1
        if not st.byUid[uid] then return uid end
    end
end

-- Changes are collected and Rhylib.InventoryChanged runs once per player
-- per tick, not once per item (a load or a stacked pickup can touch many
-- items at once, and listeners recount the whole inventory).
Inv.pending = Inv.pending or {}  -- [ply] = true

local function changed(ply)
    Inv.dirty[ply] = true
    Inv.pending[ply] = true
end

-- Before the net batches flush (priority 1000), so updates and listeners
-- land in the same tick.
Rhylib.Hook.Add("Tick", "inventory.changed", function()
    if next(Inv.pending) == nil then return end
    local list = Inv.pending
    Inv.pending = {}
    for ply in pairs(list) do
        if IsValid(ply) then
            -- Weight and carry cap for stamina, in two engine-networked vars.
            local st = Inv.states[ply]
            if st then
                local weight, cap = Items.Weight(st)
                local K = Rhylib.Skills
                if K and K.AdjustWeight then weight, cap = K.AdjustWeight(ply, st, weight, cap) end
                ply:SetNW2Float("rhylib_weight", math.Round(weight, 2))
                ply:SetNW2Float("rhylib_carry", cap)
            end
            hook.Run("Rhylib.InventoryChanged", ply)
        end
    end
end, 900)

local function sendSet(ply, st, inst)
    if st.ready then updBatch:Send(ply, { op = OP_SET, inst = inst }) end
end

local function sendDims(ply, st, cid)
    if not st.ready then return end
    local c = st.cont[cid]
    updBatch:Send(ply, { op = OP_DIMS, cid = cid, w = c and c.w or 0, h = c and c.h or 0 })
end

-- Wearing or removing a backpack or holster adds or removes its grid
-- (a worn item's `grid`, in container gridCid, default the backpack grid).
local GRID_CIDS = { BACK, HOLSTER }
local function updateBackpack(ply, st, depth)
    local want = {}
    for wcid in pairs(Items.WORN) do
        local c = st.cont[wcid]
        if c then
            for _, inst in pairs(c.items) do
                local def = Items.defs[inst.id]
                if def and def.grid then want[def.gridCid or BACK] = def.grid end
            end
        end
    end
    for _, gcid in ipairs(GRID_CIDS) do
        local grid, cur = want[gcid], st.cont[gcid]
        if grid then
            if not cur or cur.w ~= grid[1] or cur.h ~= grid[2] then
                st.cont[gcid] = { w = grid[1], h = grid[2], items = cur and cur.items or {} }
                sendDims(ply, st, gcid)
            end
        elseif cur then
            if next(cur.items) ~= nil and Inv.SetGrid then
                Inv.SetGrid(ply, gcid, 0, 0)   -- (what's in it moves elsewhere)
                -- (moving it may have put something on: work it out again)
                if (depth or 0) < 2 then return updateBackpack(ply, st, (depth or 0) + 1) end
            else
                st.cont[gcid] = nil
                sendDims(ply, st, gcid)
            end
        end
    end
end

-- Put an instance into a container (new, or moved from another one).
local function place(ply, st, inst, cid, x, y, rot)
    local old = inst.c and st.cont[inst.c]
    if old then old.items[inst.uid] = nil end
    local wasSlot = IsWorn(inst.c)

    inst.c, inst.x, inst.y, inst.rot = cid, x, y, rot
    st.cont[cid].items[inst.uid] = inst
    st.byUid[inst.uid] = inst
    sendSet(ply, st, inst)
    if wasSlot or IsWorn(cid) then updateBackpack(ply, st) end
    changed(ply)
end

local function update(ply, st, inst)
    sendSet(ply, st, inst)
    changed(ply)
end

local function removeInst(ply, st, uid)
    local inst = st.byUid[uid]
    if not inst then return end
    -- (one of two copies of a gun leaves: the other takes its hotbar slot)
    if inst.hb then
        local twin = twinOf(ply, inst)
        if twin and not twin.hb then
            twin.hb = inst.hb
            update(ply, st, twin)
        end
    end
    stripWeapon(ply, inst)
    st.cont[inst.c].items[uid] = nil
    st.byUid[uid] = nil
    if st.ready then updBatch:Send(ply, { op = OP_REMOVE, uid = uid }) end
    if IsWorn(inst.c) then updateBackpack(ply, st) end
    changed(ply)
    return inst
end

-- First free spot for a new item: worn slot if it fits there, then the
-- main grid, then the backpack.
local ROTS_SQUARE, ROTS_BOTH = { false }, { false, true }
local SEARCH = { RACK, HOLSTER, MAIN, BACK, BELT }   -- (the rack only takes cells, the holster pistols)

local function findSpot(st, id)
    local def = Items.defs[id]
    local wcid = def.slot and Items.WORN_BY_SLOT[def.slot]
    if wcid and Items.CanPlace(st, id, wcid, 0, 0, false) and Items.CanWear(st.ply, def) then
        return wcid, 0, 0, false
    end
    local rots = def.w == def.h and ROTS_SQUARE or ROTS_BOTH
    for i = 1, #SEARCH do
        local cid = SEARCH[i]
        local c = st.cont[cid]
        if c and Items.ContainerAllows(cid, def) then
            for y = 0, c.h - 1 do
                for x = 0, c.w - 1 do
                    for r = 1, #rots do
                        if Items.Fits(c.w, c.h, c.items, id, x, y, rots[r]) then return cid, x, y, rots[r] end
                    end
                end
            end
        end
    end
end

local function serialize(st)
    local out = {}
    for _, o in pairs(st.byUid) do
        out[#out + 1] = { o.id, o.x, o.y, o.rot and 1 or 0, o.count, o.data, o.c, o.hb }
    end
    return out
end

local function load(ply, st)
    local saved = Rhylib.Data.Get("inventory", ply:SteamID64())
    if not istable(saved) then return end
    -- Worn items first, so the backpack grid exists before its contents.
    for pass = 1, 2 do
        for _, row in ipairs(saved) do
            local cid = row[7] or MAIN
            if (pass == 1) == IsWorn(cid) then
                local id, x, y, rot, count = row[1], row[2], row[3], row[4] == 1, row[5]
                if Items.defs[id] and Items.CanPlace(st, id, cid, x, y, rot) then
                    local inst = { uid = nextUid(st), id = id, count = count, data = istable(row[6]) and row[6] or {}, hb = tonumber(row[8]) }
                    place(ply, st, inst, cid, x, y, rot)
                elseif Items.defs[id] and cid ~= MAIN and cid ~= BACK then
                    -- The rack, belt, holster or a gear slot is gone or taken: anywhere else.
                    local c2, x2, y2, r2 = findSpot(st, id)
                    local data = istable(row[6]) and row[6] or {}
                    if c2 then
                        place(ply, st, { uid = nextUid(st), id = id, count = count, data = data, hb = tonumber(row[8]) }, c2, x2, y2, r2)
                    elseif not data.loadout then
                        -- No room anywhere: on the ground once they're in.
                        timer.Simple(2, function()
                            if IsValid(ply) then Inv.SpawnWorldItem(ply, id, count, data) end
                        end)
                    end
                end
            end
        end
    end
    -- Saved before the hotbar existed: give the weapons slots once.
    local any = false
    for _, o in pairs(st.byUid) do
        if o.hb then any = true break end
    end
    if not any then
        for _, o in pairs(st.byUid) do Inv.AutoHotbar(st, o) end
    end
    Inv.dirty[ply] = nil
end

function Inv.Get(ply)
    local st = Inv.states[ply]
    if st then return st end
    Items.EnsureReady()
    st = {
        cont = {
            [MAIN] = { w = Config.Get("inventory", "width"), h = Config.Get("inventory", "height"), items = {} },
            [SLOT_BACK] = { w = 1, h = 1, items = {} },
        },
        byUid = {},
        nextUid = 1,
        ready = false,  -- true once the client has its full copy
        ply = ply,
    }
    for _, cid in ipairs(Items.GEAR_SLOTS) do
        if Items.SlotUsed(Items.WORN[cid].slot) then st.cont[cid] = { w = 1, h = 1, items = {} } end
    end
    -- Grids from skills (the cell rack), before the saved items go in.
    local K = Rhylib.Skills
    if K and K.ExtraGrids then
        for cid, g in pairs(K.ExtraGrids(ply)) do st.cont[cid] = { w = g[1], h = g[2], items = {} } end
    end
    Inv.states[ply] = st
    if ply:SteamID64() then load(ply, st) end
    return st
end

--------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------

function Inv.Count(ply, id)
    local n = 0
    for _, o in pairs(Inv.Get(ply).byUid) do
        if o.id == id then n = n + o.count end
    end
    return n
end

function Inv.Has(ply, id)
    return Inv.Count(ply, id) > 0
end

-- How many of a one-only item (a gun) this player may carry: 1, unless
-- hook Rhylib.CarryLimit(ply, id, def) says more (rhylib_skills: a second
-- DC-17 with Dual DC-17).
function Inv.Limit(ply, id)
    local def = Items.defs[id]
    if not Items.Unique(def) then return math.huge end
    return tonumber(hook.Run("Rhylib.CarryLimit", ply, id, def)) or 1
end

-- "You already carry one" / "... 2".
function Inv.LimitText(ply, id)
    local n = Inv.Limit(ply, id)
    return n > 1 and ("You already carry " .. n) or "You already carry one"
end

-- Carrying as many as allowed already?
function Inv.AtLimit(ply, id)
    local def = Items.defs[id]
    return Items.Unique(def) and Inv.Count(ply, id) >= Inv.Limit(ply, id) or false
end

-- May this player carry this item at all (def.carrySkill, rhylib_skills)?
function Inv.MayHold(ply, id)
    local def = Items.defs[id]
    if not (def and def.carrySkill) then return true end
    local K = Rhylib.Skills
    if not (K and K.Has) then return true end
    return K.Has(ply, def.carrySkill)
end

-- Why ply can't carry id, for messages.
function Inv.HoldReason(id)
    local def = Items.defs[id]
    local K = Rhylib.Skills
    local n = def and def.carrySkill and K and K.byId and K.byId[def.carrySkill]
    return "You need the " .. (n and n.name or "right") .. " skill to carry that"
end

-- Would one item of this type fit right now?
function Inv.CanAdd(ply, id)
    local st = Inv.Get(ply)
    local def = Items.defs[id]
    if not def then return false end
    if not Inv.MayHold(ply, id) then return false end
    if Inv.AtLimit(ply, id) then return false end
    local cap = Items.StackFor(def, ply)
    if cap > 1 then
        for _, o in pairs(st.byUid) do
            if o.id == id and not IsWorn(o.c) and o.count < cap and Items.IsFull(o) then return true end
        end
    end
    return findSpot(st, id) ~= nil
end

-- Adds items, stacking where possible. Returns how many didn't fit.
function Inv.AddItem(ply, id, count, data)
    local st = Inv.Get(ply)
    local def = Items.defs[id]
    count = count or 1
    if not def then return count end
    data = data or {}
    if Inv.AtLimit(ply, id) then return count end
    -- (one-only items: no more than the limit; the rest doesn't fit)
    local over = 0
    if Items.Unique(def) then
        local room = Inv.Limit(ply, id) - Inv.Count(ply, id)
        if count > room then over, count = count - room, room end
    end
    if not Inv.MayHold(ply, id) then return count + over end

    local cap = Items.StackFor(def, ply)
    local stackable = cap > 1 and (not def.fill or (data.fill or 1) >= 1)
    if stackable then
        local probe = { data = data }
        for _, o in pairs(st.byUid) do
            if count <= 0 then break end
            if o.id == id and o.count < cap and Items.IsFull(o) and Items.SameIssued(o, probe) then
                local add = math.min(cap - o.count, count)
                o.count = o.count + add
                count = count - add
                update(ply, st, o)
            end
        end
    end

    while count > 0 do
        local cid, x, y, rot = findSpot(st, id)
        if not cid then break end
        local n = stackable and math.min(cap, count) or 1
        local inst = { uid = nextUid(st), id = id, count = n, data = table.Copy(data) }
        Inv.AutoHotbar(st, inst)
        place(ply, st, inst, cid, x, y, rot)
        count = count - n
        giveWeapon(ply, inst)
    end
    return count + over
end

-- Removes `amount` (default all) from one item.
function Inv.Remove(ply, uid, amount)
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return end
    amount = amount or inst.count
    if amount >= inst.count then
        if not Items.CanLeave(st, inst) then return end
        return removeInst(ply, st, uid)
    end
    inst.count = inst.count - amount
    update(ply, st, inst)
    return inst
end

-- Takes one of the fullest item of this type (for reloads). Returns its
-- fill (0-1) and whether it was issued, or nil.
function Inv.TakeBest(ply, id)
    local best, bestFill
    for _, o in pairs(Inv.Get(ply).byUid) do
        if o.id == id then
            local f = o.data and o.data.fill or 1
            if not best or f > bestFill then best, bestFill = o, f end
        end
    end
    if not best then return nil end
    local issued = best.data and best.data.issued and true or nil
    Inv.Remove(ply, best.uid, 1)
    return bestFill, issued
end

-- Dropped items on the ground, oldest first: all of them, and per player.
-- Past the caps the oldest is removed, so drops always work but can't
-- fill the server's entity limit.
Inv.worldItems = Inv.worldItems or {}
Inv.worldItemsBy = Inv.worldItemsBy or setmetatable({}, { __mode = "k" })

-- (Removed entities stay valid until the end of the frame, so they're
-- marked and skipped, and can't be counted twice by the other list.)
local function prune(list)
    for i = #list, 1, -1 do
        local e = list[i]
        if not IsValid(e) or e.rhylibGone then table.remove(list, i) end
    end
end

local function makeRoom(list, max)
    prune(list)
    while #list >= max and #list > 0 do
        local old = table.remove(list, 1)
        if IsValid(old) then
            old.rhylibGone = true
            old:Remove()
        end
    end
end

-- Room for one more dropped item under the global cap (the grapple hook
-- uses this for hooks that didn't grip).
function Inv.MakeWorldRoom()
    makeRoom(Inv.worldItems, math.max(1, Config.Get("inventory", "worldItemMax")))
end

function Inv.SpawnWorldItem(ply, id, count, data)
    local mine = Inv.worldItemsBy[ply]
    if not mine then
        mine = {}
        Inv.worldItemsBy[ply] = mine
    end
    makeRoom(mine, math.max(1, Config.Get("inventory", "worldItemPerPlayer")))
    makeRoom(Inv.worldItems, math.max(1, Config.Get("inventory", "worldItemMax")))

    local ent = ents.Create("rhylib_world_item")
    if not IsValid(ent) then return end
    mine[#mine + 1] = ent
    Inv.worldItems[#Inv.worldItems + 1] = ent
    local start = ply:GetShootPos()
    local tr = util.TraceLine({ start = start, endpos = start + ply:GetAimVector() * 50, filter = ply })
    ent:SetItem(id, count, data)
    ent:SetPos(tr.HitPos + tr.HitNormal * 8)
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent:Spawn()
    return ent
end

-- Adds an item, and drops whatever doesn't fit at the player's feet.
function Inv.AddOrDrop(ply, id, count, data)
    local left = Inv.AddItem(ply, id, count, data)
    -- (Issued gear on the ground despawns sooner: rhylib_world_item.)
    if left > 0 then Inv.SpawnWorldItem(ply, id, left, data) end
end

-- single: drop just one off a stack (ctrl + drag out of the window).
function Inv.Drop(ply, uid, single)
    if Inv.Locked(ply) then return end
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return end
    local canLeave, leaveWhy = Items.CanLeave(st, inst)
    if not canLeave then
        Inv.Note(ply, leaveWhy)
        return
    end
    local n = (single and inst.count > 1) and 1 or inst.count
    -- Job loadout gear just vanishes (or die/respawn would farm it).
    if inst.data and inst.data.loadout then
        if n < inst.count then
            inst.count = inst.count - n
            update(ply, st, inst)
        else
            removeInst(ply, st, uid)
        end
        Inv.Note(ply, "Job gear handed back")
        return
    end
    -- Issued gear drops too (someone may need it), but despawns after a while.
    captureWeapon(ply, inst)
    if not IsValid(Inv.SpawnWorldItem(ply, inst.id, n, inst.data)) then return end
    if n < inst.count then
        inst.count = inst.count - n
        update(ply, st, inst)
    else
        removeInst(ply, st, uid)
    end
end

-- Moves one item off a stack to x, y (ctrl + drag).
local function moveOne(ply, st, inst, cid, x, y, rot)
    local c = st.cont[cid]
    local target = c and not IsWorn(cid) and Items.MergeTarget(c.items, inst, x, y, ply)
    if target and target ~= inst then
        target.count = target.count + 1
        inst.count = inst.count - 1
        update(ply, st, target)
        update(ply, st, inst)
        return
    end
    if Items.CanPlace(st, inst.id, cid, x, y, rot) then
        local one = { uid = nextUid(st), id = inst.id, count = 1, data = table.Copy(inst.data or {}) }
        inst.count = inst.count - 1
        update(ply, st, inst)
        place(ply, st, one, cid, x, y, rot)
    else
        sendSet(ply, st, inst)
    end
end

-- single: move just one off a stack.
function Inv.Move(ply, uid, cid, x, y, rot, single)
    if cid == Items.EXT then
        if Inv.Deposit then Inv.Deposit(ply, uid, x, y, rot, single) end
        return
    end
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst then return end

    if IsWorn(cid) and cid ~= inst.c then
        local okWear, wearWhy = Items.CanWear(ply, Items.defs[inst.id])
        if not okWear then
            Inv.Note(ply, wearWhy)
            sendSet(ply, st, inst)
            return
        end
    end

    if single and inst.count > 1 then
        moveOne(ply, st, inst, cid, x, y, rot)
        return
    end

    if cid ~= inst.c then
        local canLeave, leaveWhy = Items.CanLeave(st, inst)
        if not canLeave then
            Inv.Note(ply, leaveWhy)
            sendSet(ply, st, inst)
            return
        end
    end

    local c = st.cont[cid]
    local target = c and not IsWorn(cid) and Items.MergeTarget(c.items, inst, x, y, ply)
    if target then
        local def = Items.defs[inst.id]
        local add = math.min(Items.StackFor(def, ply) - target.count, inst.count)
        target.count = target.count + add
        inst.count = inst.count - add
        update(ply, st, target)
        if inst.count <= 0 then removeInst(ply, st, uid) else update(ply, st, inst) end
        return
    end

    if Items.CanPlace(st, inst.id, cid, x, y, rot, uid) then
        place(ply, st, inst, cid, x, y, rot)
    else
        sendSet(ply, st, inst)  -- rejected: put the client's copy back
    end
end

--------------------------------------------------------------------------
-- Hotbar slots (inst.hb). One item per slot.
--------------------------------------------------------------------------

-- New weapons go into the first free slot (if autoHotbar is on).
function Inv.AutoHotbar(st, inst)
    local def = Items.defs[inst.id]
    if inst.hb or not def or not def.weapon or not Config.Get("inventory", "autoHotbar") then return end
    local used = {}
    for _, o in pairs(st.byUid) do
        if o.hb then used[o.hb] = true end
        if o.id == inst.id and o.hb then return end  -- one slot per kit type
    end
    for n = 1, Items.HotbarSize(st) do
        if not used[n] then inst.hb = n return end
    end
end

-- Put item uid in slot n (uid 0: just empty slot n).
function Inv.SetHotbar(ply, uid, n)
    local st = Inv.Get(ply)
    if n < 1 or n > Items.HotbarSize(st) then return end
    local active = ply:GetActiveWeapon()
    for _, o in pairs(st.byUid) do
        if o.hb == n and o.uid ~= uid then
            o.hb = nil
            update(ply, st, o)
            -- Taken off the hotbar while in your hands: put it away.
            local def = Items.defs[o.id]
            -- (not if another copy of this gun is, or is going, on the hotbar)
            local other = false
            for _, o2 in pairs(st.byUid) do
                if o2 ~= o and o2.id == o.id and (o2.hb or o2.uid == uid) then other = true end
            end
            if def and def.weapon and not other and IsValid(active) and active:GetClass() == def.weapon then Inv.Stow(ply) end
            if IsValid(active) and active:GetClass() == Inv.HAND and ply:GetNW2Int("rhylib_handUid", 0) == o.uid then Inv.Stow(ply) end
        end
    end
    local inst = st.byUid[uid]
    if inst and inst.hb ~= n then
        inst.hb = n
        update(ply, st, inst)
    end
end

-- Splits a stack in two; the new half goes to the first free spot,
-- same container first.
function Inv.Split(ply, uid)
    local st = Inv.Get(ply)
    local inst = st.byUid[uid]
    if not inst or inst.count < 2 then return end
    local n = math.floor(inst.count / 2)
    local cid, x, y, rot = inst.c, Items.FindSpot(st.cont[inst.c], inst.id)
    if not x then cid, x, y, rot = findSpot(st, inst.id) end
    if not cid or not x then
        Inv.Note(ply, "No room to split the stack")
        return
    end
    local half = { uid = nextUid(st), id = inst.id, count = n, data = table.Copy(inst.data or {}) }
    inst.count = inst.count - n
    update(ply, st, inst)
    place(ply, st, half, cid, x, y, rot)
end

-- Adds items into one container first (stacking onto full stacks, then
-- free spots), and anything that doesn't fit anywhere else.
local function addInto(ply, st, id, count, data, cid)
    local def = Items.defs[id]
    local c = st.cont[cid]
    if count <= 0 or not def then return end
    local full = not def.fill or (data.fill or 1) >= 1
    local cap = Items.StackFor(def, ply)
    if c and full and cap > 1 then
        local probe = { data = data }
        for _, o in pairs(c.items) do
            if count <= 0 then break end
            if o.id == id and o.count < cap and Items.IsFull(o) and Items.SameIssued(o, probe) then
                local add = math.min(cap - o.count, count)
                o.count = o.count + add
                count = count - add
                update(ply, st, o)
            end
        end
    end
    while count > 0 and c do
        local x, y, rot = Items.FindSpot(c, id)
        if not x then break end
        local n = full and math.min(cap, count) or 1
        place(ply, st, { uid = nextUid(st), id = id, count = n, data = table.Copy(data) }, cid, x, y, rot)
        count = count - n
    end
    if count > 0 then Inv.AddOrDrop(ply, id, count, data) end
end

--------------------------------------------------------------------------
-- Combine munitions: partly used magazines and power cells you carry,
-- in the main grid or the backpack, are poured together (2 magazines at
-- 30% become one at 60%). The results go into the backpack if you wear
-- one, otherwise the main grid. Takes a moment; the result is worked out when the
-- timer ends.
--------------------------------------------------------------------------

-- A short message shown in the inventory window (it covers the HUD).
function Inv.Note(ply, text)
    Rhylib.Net.Start("inv.note")
    net.WriteString(text)
    net.Send(ply)
end

local function partials(st)
    local groups, n = {}, 0
    for _, cid in ipairs({ MAIN, BACK, RACK, BELT }) do
        local c = st.cont[cid]
        if c then
            for _, o in pairs(c.items) do
                local def = Items.defs[o.id]
                local fill = o.data and o.data.fill or 1
                if def and def.fill and fill < 0.999 and fill > 0 then
                    -- Issued and normal ones are combined separately.
                    local key = o.data.issued and (o.id .. "#issued") or o.id
                    groups[key] = groups[key] or {}
                    table.insert(groups[key], o)
                    n = n + 1
                end
            end
        end
    end
    return groups, n
end

local function sendBusy(ply, endTime)
    Rhylib.Net.Start("inv.busy")
    net.WriteFloat(endTime)
    net.Send(ply)
end

function Inv.StartCombine(ply)
    local st = Inv.Get(ply)
    if st.combineEnd and st.combineEnd > CurTime() then return end
    local groups, n = partials(st)
    local useful = false
    for _, list in pairs(groups) do
        if #list >= 2 then useful = true break end
    end
    if not useful then
        Inv.Note(ply, "Nothing to combine: needs 2+ partly used of the same kind")
        return
    end
    local dur = math.Clamp(n * Config.Get("inventory", "combineTime"), 3, Config.Get("inventory", "combineMax"))
    st.combineEnd = CurTime() + dur
    sendBusy(ply, st.combineEnd)
    timer.Create("Rhylib.Combine." .. ply:EntIndex(), dur, 1, function()
        if IsValid(ply) then Inv.FinishCombine(ply) end
    end)
end

function Inv.CancelCombine(ply)
    local st = Inv.states[ply]
    if not st or not st.combineEnd then return end
    st.combineEnd = nil
    timer.Remove("Rhylib.Combine." .. ply:EntIndex())
    sendBusy(ply, 0)
end

function Inv.FinishCombine(ply)
    local st = Inv.Get(ply)
    st.combineEnd = nil
    sendBusy(ply, 0)
    if not ply:Alive() then return end
    local into = st.cont[BACK] and BACK or MAIN

    local groups = partials(st)
    local merged = 0
    for _, list in pairs(groups) do
        if #list >= 2 then
            local id = list[1].id
            local sum, issued = 0, false
            for _, o in ipairs(list) do
                sum = sum + (o.data.fill or 1) * o.count
                issued = issued or o.data.issued or false
                removeInst(ply, st, o.uid)
            end
            local full = math.floor(sum + 0.0001)
            local rest = sum - full
            addInto(ply, st, id, full, { fill = 1, issued = issued or nil }, into)
            if rest > 0.005 then addInto(ply, st, id, 1, { fill = rest, issued = issued or nil }, into) end
            merged = merged + #list
        end
    end
    Inv.Note(ply, merged > 0 and ("Combined " .. merged .. " partly used items") or "Nothing left to combine")
end

function Inv.SendFull(ply)
    local st = Inv.Get(ply)
    st.ready = true

    local conts, list = {}, {}
    for cid, c in pairs(st.cont) do conts[#conts + 1] = { cid = cid, w = c.w, h = c.h } end
    for _, o in pairs(st.byUid) do list[#list + 1] = o end

    Rhylib.Net.Start("inv.full")
    net.WriteUInt(#conts, Items.CONT_BITS + 1)
    for _, c in ipairs(conts) do
        net.WriteUInt(c.cid, Items.CONT_BITS)
        net.WriteUInt(c.w, 5)
        net.WriteUInt(c.h, 5)
    end
    net.WriteUInt(#list, 8)
    for _, o in ipairs(list) do Items.WriteInstance(o) end
    Rhylib.Profiler.AddNet("inv.full", net.BytesWritten() or 0)
    net.Send(ply)
end

function Inv.Save(ply)
    local st = Inv.states[ply]
    if not st or not ply:SteamID64() then return end
    Inv.CaptureWeapons(ply)
    Rhylib.Data.Set("inventory", ply:SteamID64(), serialize(st))
end

--------------------------------------------------------------------------
-- Client requests
--------------------------------------------------------------------------

-- Cuffed, stunned or jailed players (rhylib_mp) can't drop, use or hand
-- over items. Other addons answer the Rhylib.InventoryLocked hook.
function Inv.Locked(ply)
    return hook.Run("Rhylib.InventoryLocked", ply) == true
end

Rhylib.Net.Receive("inv.req", function(ply)
    Inv.SendFull(ply)
end, { rate = 1, burst = 2 })

Rhylib.Net.Receive("inv.move", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local cid = net.ReadUInt(Items.CONT_BITS)
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    local single = net.ReadBool()
    Inv.Move(ply, uid, cid, x, y, rot, single)
end, { rate = 20, burst = 10 })

Rhylib.Net.Receive("inv.hotbar", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    Inv.SetHotbar(ply, uid, net.ReadUInt(3))
end, { rate = 10, burst = 10 })

Rhylib.Net.Receive("inv.split", function(ply)
    Inv.Split(ply, net.ReadUInt(Items.UID_BITS))
end, { rate = 5, burst = 5 })

Rhylib.Net.Receive("inv.combine", function(ply)
    Inv.StartCombine(ply)
end, { rate = 2, burst = 2 })

Rhylib.Net.Receive("inv.drop", function(ply)
    local uid = net.ReadUInt(Items.UID_BITS)
    local single = net.ReadBool()
    if Inv.Locked(ply) then return end
    Inv.Drop(ply, uid, single)
end, { rate = 8, burst = 8 })

-- Hide / unhide contraband from searches (rhylib_mp rolls for each hidden
-- item). data.hidden is the hider's SteamID64, so it lapses when the item
-- changes hands.
Rhylib.Net.Receive("inv.hide", function(ply)
    if Inv.Locked(ply) then return end
    local st = Inv.Get(ply)
    local inst = st.byUid[net.ReadUInt(Items.UID_BITS)]
    if not inst or IsWorn(inst.c) then return end
    inst.data = inst.data or {}
    if inst.data.hidden then
        inst.data.hidden = nil
    else
        if not Items.IsContraband(inst.id) then return end
        local sid, n = ply:SteamID64() or "0", 0
        for _, o in pairs(st.byUid) do
            if o.data and o.data.hidden == sid then n = n + 1 end
        end
        if n >= Items.HIDE_MAX then
            Inv.Note(ply, "You can hide " .. Items.HIDE_MAX .. " items at most")
            sendSet(ply, st, inst)
            return
        end
        inst.data.hidden = sid
    end
    update(ply, st, inst)
end, { rate = 5, burst = 5 })

Rhylib.Net.Receive("inv.use", function(ply)
    if Inv.Locked(ply) then return end
    local inst = Inv.Get(ply).byUid[net.ReadUInt(Items.UID_BITS)]
    local def = inst and Items.defs[inst.id]
    if def and def.weapon and ply:HasWeapon(def.weapon) then
        ply:SelectWeapon(def.weapon)
    end
end, { rate = 5, burst = 5 })

--------------------------------------------------------------------------
-- Game hooks
--------------------------------------------------------------------------

-- Weapons from the spawn menu, the map or other addons go into the
-- inventory instead of straight into the hands.
Rhylib.Hook.Add("PlayerCanPickupWeapon", "inventory.pickup", function(ply, wep)
    if ply.rhylibGiving then return end
    local class = wep:GetClass()
    local def = Items.defs[class]
    if not def then return end  -- not an inventory weapon: normal behaviour

    if wep.rhylibClaimed then return false end
    -- This hook runs every tick while touching a weapon: remember a "no"
    -- for half a second instead of scanning the grid each time.
    if ply.rhylibPickupNoWep == wep and (ply.rhylibPickupNoUntil or 0) > CurTime() then return false end

    -- Stacking kits from a job loadout only top up to one stack, so
    -- respawning (the inventory survives death) doesn't pile them up.
    if not Items.Unique(def) and ply.rhylibSpawnTick and engine.TickCount() - ply.rhylibSpawnTick <= 2
        and Inv.Count(ply, class) >= Items.StackFor(def, ply) then
        wep.rhylibClaimed = true
        timer.Simple(0, function() if IsValid(wep) then wep:Remove() end end)
        return false
    end
    if not Inv.MayHold(ply, class) then
        ply.rhylibPickupNoWep, ply.rhylibPickupNoUntil = wep, CurTime() + 0.5
        if (ply.rhylibFullNotice or 0) < CurTime() then
            ply.rhylibFullNotice = CurTime() + 2
            ply:PrintMessage(HUD_PRINTCENTER, Inv.HoldReason(class))
        end
        return false
    end
    if not Inv.CanAdd(ply, class) then
        ply.rhylibPickupNoWep, ply.rhylibPickupNoUntil = wep, CurTime() + 0.5
        if (ply.rhylibFullNotice or 0) < CurTime() then
            ply.rhylibFullNotice = CurTime() + 2
            ply:PrintMessage(HUD_PRINTCENTER, Inv.AtLimit(ply, class) and Inv.LimitText(ply, class) or "No room in your inventory")
        end
        return false
    end

    -- Given by the job loadout at spawn: marked loadout, so it vanishes
    -- when dropped and can't be given or stored (no "drop kits, die,
    -- respawn" farming).
    local loadout = ply.rhylibSpawnTick and engine.TickCount() - ply.rhylibSpawnTick <= 2
    wep.rhylibClaimed = true
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        -- ply:Give (spawn menu, admin mods) removes a weapon whose pickup
        -- was refused, so it may be gone already; nobody else could take
        -- it (claimed), so it still goes into the inventory.
        local gone = not IsValid(wep)
        -- Add first; the weapon only leaves the ground if it really went in
        -- (the inventory may have filled up during this tick).
        if Inv.AddItem(ply, class, 1, loadout and { issued = true, loadout = true } or {}) == 0 then
            if not gone then wep:Remove() end
            hook.Run("Rhylib.InventoryWeaponPickup", ply, class)
        elseif not gone then
            wep.rhylibClaimed = nil
        end
    end)
    return false
end)

Rhylib.Hook.Add("PlayerInitialSpawn", "inventory.load", function(ply)
    Inv.Get(ply)
end)

Rhylib.Hook.Add("PlayerSpawn", "inventory.weapons", function(ply)
    ply.rhylibSpawnTick = engine.TickCount()
    timer.Simple(0, function()
        if not (IsValid(ply) and ply:Alive()) then return end
        Inv.GiveAllWeapons(ply)
        Inv.Stow(ply)  -- everyone spawns with their guns stowed
    end)
end)

-- Inventory weapons can't be dropped as plain weapons (DarkRP /drop, drop
-- on death): the item stays in the inventory, so that would duplicate it.
-- Drop from the inventory window instead.
Rhylib.Hook.Add("canDropWeapon", "inventory.nodrop", function(ply, wep)
    if IsValid(wep) and (Items.defs[wep:GetClass()] or wep:GetClass() == Inv.HAND or wep:GetClass() == Inv.STOWED) then return false end
end)

Rhylib.Hook.Add("PlayerDroppedWeapon", "inventory.nodrop", function(ply, wep)
    if not IsValid(wep) or not Items.defs[wep:GetClass()] then return end
    local class = wep:GetClass()
    -- Keep the dropped weapon's clip and cell in the item before it's
    -- given back, or the ammo would roll back to the old values.
    if wep.GetInventoryData then
        for _, inst in pairs(Inv.Get(ply).byUid) do
            if inst.id == class then
                local issued, loadout = inst.data and inst.data.issued, inst.data and inst.data.loadout
                inst.data = wep:GetInventoryData() or inst.data
                inst.data.issued, inst.data.loadout = issued, loadout
                break
            end
        end
    end
    wep.rhylibClaimed = true
    timer.Simple(0, function()
        if IsValid(wep) then wep:Remove() end
        if not (IsValid(ply) and ply:Alive()) then return end
        for _, inst in pairs(Inv.Get(ply).byUid) do
            if inst.id == class then giveWeapon(ply, inst) break end
        end
    end)
end)

-- Keep clip and cell state before the weapons are removed on death.
Rhylib.Hook.Add("DoPlayerDeath", "inventory.capture", function(ply)
    Inv.CaptureWeapons(ply)
    Inv.CancelCombine(ply)
end)

Rhylib.Hook.Add("PlayerDisconnected", "inventory.save", function(ply)
    Inv.Save(ply)
    Inv.states[ply] = nil
    Inv.dirty[ply] = nil
    Inv.pending[ply] = nil
end)

timer.Create("Rhylib.Inventory.Save", Config.Get("inventory", "saveInterval"), 0, function()
    for ply in pairs(Inv.dirty) do
        if IsValid(ply) then Inv.Save(ply) end
    end
    Inv.dirty = {}
end)

Rhylib.Hook.Add("ShutDown", "inventory.save", function()
    for ply in pairs(Inv.states) do
        if IsValid(ply) then Inv.Save(ply) end
    end
end, -10)  -- before the data layer's final flush

-- A grid from a skill (cid, w x h); 0 removes it, and what was in it moves
-- to the other grids (or the ground).
function Inv.SetGrid(ply, cid, w, h)
    local st = Inv.states[ply]
    if not st then return end
    local cur = st.cont[cid]
    if w > 0 and h > 0 then
        if cur and cur.w == w and cur.h == h then return end
        st.cont[cid] = { w = w, h = h, items = cur and cur.items or {} }
        sendDims(ply, st, cid)
        return
    end
    if not cur then return end
    local moved = {}
    for _, inst in pairs(cur.items) do moved[#moved + 1] = inst end
    st.cont[cid] = nil
    sendDims(ply, st, cid)
    for _, inst in ipairs(moved) do
        -- Somewhere else in the inventory: same item, so it keeps its uid,
        -- hotbar slot and weapon.
        local c2, x2, y2, r2 = findSpot(st, inst.id)
        if c2 then
            inst.c = nil   -- (its old container is gone)
            place(ply, st, inst, c2, x2, y2, r2)
        else
            -- No room: off the player (weapon stripped), onto the ground;
            -- job loadout gear just goes.
            captureWeapon(ply, inst)
            st.cont[cid] = { w = 0, h = 0, items = { [inst.uid] = inst } }
            removeInst(ply, st, inst.uid)
            st.cont[cid] = nil
            if not (inst.data and inst.data.loadout) then Inv.SpawnWorldItem(ply, inst.id, inst.count, inst.data) end
        end
    end
    changed(ply)
end

-- Takes a worn item off (rhylib_gear: a part the new model can't show):
-- into the main grid or backpack, else onto the ground (job gear just goes).
-- A worn holster's pistol moves elsewhere too.
function Inv.TakeOff(ply, uid)
    local st = Inv.states[ply]
    local inst = st and st.byUid[uid]
    if not inst or not IsWorn(inst.c) then return end
    local rots = { false, true }
    for _, cid in ipairs({ MAIN, BACK }) do
        local c = st.cont[cid]
        if c then
            for y = 0, c.h - 1 do
                for x = 0, c.w - 1 do
                    for _, rot in ipairs(rots) do
                        if Items.CanPlace(st, inst.id, cid, x, y, rot) then
                            place(ply, st, inst, cid, x, y, rot)
                            return true
                        end
                    end
                end
            end
        end
    end
    captureWeapon(ply, inst)
    removeInst(ply, st, uid)
    if not (inst.data and inst.data.loadout) then Inv.SpawnWorldItem(ply, inst.id, inst.count, inst.data) end
    return false
end

-- Weight and carry limit sent again (a skill changed the limit).
function Inv.MarkChanged(ply)
    if Inv.states[ply] then changed(ply) end
end

-- For sv_30_storage.lua: the low-level helpers that keep the client, the
-- weapons and the save in step.
Inv.Internal = {
    place = place,
    update = update,
    removeInst = removeInst,
    nextUid = nextUid,
    giveWeapon = giveWeapon,
    captureWeapon = captureWeapon,
    sendSet = sendSet,
}
