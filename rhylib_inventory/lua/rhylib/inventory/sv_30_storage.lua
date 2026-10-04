--[[
    Outside containers ("storages"): anything a player opens next to their
    own inventory, like a locker, a supply crate or an armoury.

    Two kinds:
      grid   a normal container with its own items (lockers, crates).
      depot  an endless supply: one of each stocked item, always there.
             Taking one gives a fresh, full, *issued* item; putting a
             stocked item back just removes it.

    Other addons create them on an entity:
        Inv.CreateStorage(ent, {
            kind = "grid", w = 6, h = 6, title = "Locker",
            onChanged = function(storage) ... end,   -- save it, etc.
            controls = function(storage, ply) return { canLock = true, locked = false } end,
        })
        Inv.CreateStorage(ent, { kind = "depot", title = "Armoury", stock = { "rhylib_dc15s", ... } })
        Inv.OpenStorage(ply, ent)

    noDeposit = true: items can only be taken out (property lockers).
    bulk = true: "Store all" / "Take all" / "Empty" buttons (training deposit).
    bulkOnly = true: only those buttons, no dragging in, out or around and
        no quick take; Store all only while it's empty (one trip at a time).
    grow = true: the grid gets taller as it fills (up to GROW_MAX rows),
        so it's as good as endless.
    variant = function(storage, ply) return sub end   -- optional: a different
        storage per player (role armouries). Make subs with Inv.NewStorage
        and keep them in storage.subs[key]; they share the entity.

    One open storage per player, shown as container Items.EXT (4) in the
    inventory window. Everyone looking into the same storage sees changes.
    Storages close when you walk away, die, or the entity is removed.

    Network:
      inv.ext     (to one player) open with the full contents, or closed
      inv.extupd  (batched, to viewers) item changed / removed
      inv.take    (request) storage item -> your container at x, y
      inv.extmove (request) move within a grid storage
      inv.close   (request) you closed the window
      inv.quick   (request) right-click quick take: storage item -> anywhere it fits
      inv.bulk    (request) store all / take all / empty (bulk storages)
      inv.took    (to one player) something came in or went out: play the sound
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local I = Inv.Internal

local EXT = Items.EXT
local SLOT_BACK = Items.SLOT_BACK
local OP_REMOVE, OP_SET = 0, 1
local MAX_DIST = 160
local GROW_MIN, GROW_MAX = 6, 31   -- (rows; 31 is the most inv.ext can send)
Inv.STORAGE_DIST = MAX_DIST  -- also used by rhylib_armoury (claiming lockers)

Inv.storages = Inv.storages or {}  -- [entity] = storage

Rhylib.Net.Register("inv.ext")
Rhylib.Net.Register("inv.took")
local extBatch = Rhylib.Net.CreateBatch("inv.extupd", function(ch)
    net.WriteUInt(ch.op, 1)
    if ch.op == OP_SET then
        Items.WriteInstance(ch.inst)
    else
        net.WriteUInt(ch.uid, Items.UID_BITS)
    end
end)

--------------------------------------------------------------------------
-- Creating
--------------------------------------------------------------------------

local function nextUid(storage)
    for _ = 1, 65535 do
        local uid = storage.nextUid
        storage.nextUid = uid % 65535 + 1
        if not storage.items[uid] then return uid end
    end
end

-- Lays the depot's stock out in a grid, one of each, like a shop shelf.
local function layoutDepot(storage)
    Items.EnsureReady()
    local c = { w = storage.w, h = 16, items = {} }
    local used = 0
    for i, id in ipairs(storage.stock) do
        local def = Items.defs[id]
        if def then
            -- Lying flat reads best on a shelf; only turn it if it can't fit flat.
            local x, y, rot
            for yy = 0, c.h - 1 do
                for xx = 0, c.w - 1 do
                    if not x and Items.Fits(c.w, c.h, c.items, id, xx, yy, false) then x, y, rot = xx, yy, false end
                end
            end
            if not x then x, y, rot = Items.FindSpot(c, id) end
            if x then
                local h = rot and def.w or def.h
                local inst = { uid = i, id = id, x = x, y = y, rot = rot, c = EXT,
                    count = Items.Unique(def) and 1 or def.stack, data = def.fill and { fill = 1 } or {} }
                c.items[i] = inst
                used = math.max(used, y + h)
            end
        end
    end
    storage.items = c.items
    storage.h = math.max(used, 1)
end

-- A storage that isn't registered on the entity (a variant's sub-storage).
function Inv.NewStorage(ent, opts)
    local storage = {
        ent = ent,
        kind = opts.kind or "grid",
        w = opts.w or 6,
        h = opts.h or 6,
        title = opts.title or "Storage",
        stock = opts.stock,
        items = {},
        nextUid = 1,
        viewers = {},
        onChanged = opts.onChanged,
        controls = opts.controls,
        variant = opts.variant,
        noDeposit = opts.noDeposit,
        bulk = opts.bulk or opts.bulkOnly,
        bulkOnly = opts.bulkOnly,
        grow = opts.grow,
        subs = {},
    }
    if storage.grow then storage.h = math.max(storage.h, GROW_MIN) end
    if storage.kind == "depot" then layoutDepot(storage) end
    return storage
end

function Inv.CreateStorage(ent, opts)
    local storage = Inv.NewStorage(ent, opts)
    Inv.storages[ent] = storage
    return storage
end

-- The storage itself and its variants.
local function eachStorage(storage, fn)
    fn(storage)
    for _, sub in pairs(storage.subs) do fn(sub) end
end

function Inv.GetStorage(ent)
    return Inv.storages[ent]
end

-- Adds items to a grid storage (for filling crates, loading lockers).
-- Returns how many didn't fit.
function Inv.StorageAdd(storage, id, count, data, x, y, rot)
    local def = Items.defs[id]
    if not def then return count end
    local left = count or 1
    while left > 0 do
        local px, py, prot = x, y, rot
        if px == nil or not Items.Fits(storage.w, storage.h, storage.items, id, px, py, prot) then
            px, py, prot = Items.FindSpot(storage, id)
        end
        if not px then break end
        local full = not def.fill or ((data and data.fill) or 1) >= 1
        local n = full and math.min(def.stack, left) or 1
        local inst = { uid = nextUid(storage), id = id, c = EXT, x = px, y = py, rot = prot, count = n, data = table.Copy(data or {}) }
        storage.items[inst.uid] = inst
        left = left - n
        x = nil
    end
    return left
end

-- For saving: plain rows.
function Inv.StorageSerialize(storage)
    local out = {}
    for _, o in pairs(storage.items) do
        out[#out + 1] = { o.id, o.x, o.y, o.rot and 1 or 0, o.count, o.data }
    end
    return out
end

-- A growing storage: as tall as its items need, plus two empty rows.
local function fitHeight(storage)
    if not storage.grow then return false end
    local used = 0
    for _, o in pairs(storage.items) do
        local def = Items.defs[o.id]
        local h = def and (o.rot and def.w or def.h) or 1
        used = math.max(used, o.y + h)
    end
    local h = math.Clamp(used + 2, GROW_MIN, GROW_MAX)
    if h == storage.h then return false end
    storage.h = h
    return true
end

function Inv.StorageLoad(storage, rows)
    storage.items = {}
    if storage.grow then storage.h = GROW_MAX end
    if istable(rows) then
        Items.EnsureReady()
        for _, row in ipairs(rows) do
            if Items.defs[row[1]] then
                Inv.StorageAdd(storage, row[1], row[5] or 1, istable(row[6]) and row[6] or {}, row[2], row[3], row[4] == 1)
            end
        end
    end
    fitHeight(storage)
end

--------------------------------------------------------------------------
-- Viewers
--------------------------------------------------------------------------

local function sendChange(storage, op, inst, uid)
    for ply in pairs(storage.viewers) do
        if IsValid(ply) then
            extBatch:Send(ply, op == OP_SET and { op = OP_SET, inst = inst } or { op = OP_REMOVE, uid = uid })
        end
    end
end

-- ply: who changed it. A saved storage (a locker) saves straight away,
-- and so does that player's inventory, so both land in the same database
-- write and a crash can't duplicate or lose the item that moved.
local sendOpen
local function changedStorage(storage, ply)
    -- (grown or shrunk: everyone looking gets the new size)
    if fitHeight(storage) then
        for p in pairs(storage.viewers) do
            if IsValid(p) then sendOpen(p, storage) end
        end
    end
    if storage.onChanged then
        storage.onChanged(storage)
        if IsValid(ply) and Inv.Save then Inv.Save(ply) end
    end
end

function sendOpen(ply, storage)
    local ctl = storage.controls and storage.controls(storage, ply) or {}
    local list = {}
    for _, o in pairs(storage.items) do list[#list + 1] = o end
    Rhylib.Net.Start("inv.ext")
    net.WriteBool(true)
    net.WriteString(storage.title)
    net.WriteBool(storage.kind == "depot")
    net.WriteUInt(storage.w, 5)
    net.WriteUInt(storage.h, 5)
    net.WriteBool(ctl.canLock or false)
    net.WriteBool(ctl.locked or false)
    net.WriteUInt(storage.bulkOnly and 2 or (storage.bulk and 1 or 0), 2)
    net.WriteUInt(#list, 8)
    for _, o in ipairs(list) do Items.WriteInstance(o) end
    Rhylib.Profiler.AddNet("inv.ext", net.BytesWritten() or 0)
    net.Send(ply)
end

function Inv.OpenStorage(ply, ent)
    local storage = Inv.storages[ent]
    if not storage then return end
    if storage.variant then
        storage = storage.variant(storage, ply)
        if not storage then return end
    end
    Inv.CloseStorage(ply, true)
    Inv.Get(ply).ext = storage
    storage.viewers[ply] = true
    sendOpen(ply, storage)
end

-- Resend the whole storage to everyone looking at it (after lock changes etc.).
function Inv.RefreshStorage(ent)
    local storage = Inv.storages[ent]
    if not storage then return end
    eachStorage(storage, function(s)
        for ply in pairs(s.viewers) do
            if IsValid(ply) then sendOpen(ply, s) end
        end
    end)
end

-- quiet: don't tell the client (it closed the window itself, or another opens).
function Inv.CloseStorage(ply, quiet)
    local st = Inv.states[ply]
    local storage = st and st.ext
    if not storage then return end
    st.ext = nil
    storage.viewers[ply] = nil
    if not quiet and IsValid(ply) then
        Rhylib.Net.Start("inv.ext")
        net.WriteBool(false)
        net.Send(ply)
    end
end

function Inv.RemoveStorage(ent)
    local storage = Inv.storages[ent]
    if not storage then return end
    eachStorage(storage, function(s)
        for ply in pairs(s.viewers) do
            if IsValid(ply) then Inv.CloseStorage(ply) end
        end
    end)
    Inv.storages[ent] = nil
end

-- Close storages for anyone who walked away (checked twice a second).
timer.Create("Rhylib.Inventory.StorageRange", 0.5, 0, function()
    for ent, storage in pairs(Inv.storages) do
        if not IsValid(ent) then
            Inv.RemoveStorage(ent)
        else
            local pos = ent:GetPos()
            eachStorage(storage, function(s)
                for ply in pairs(s.viewers) do
                    if not IsValid(ply) or not ply:Alive() or ply:GetPos():DistToSqr(pos) > MAX_DIST * MAX_DIST then
                        if IsValid(ply) then Inv.CloseStorage(ply) else s.viewers[ply] = nil end
                    end
                end
            end)
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "inventory.storage", function(ply)
    Inv.CloseStorage(ply, true)
end, -20)  -- before the inventory state is thrown away

--------------------------------------------------------------------------
-- Moving items in and out
--------------------------------------------------------------------------

local function openStorage(ply)
    local st = Inv.Get(ply)
    local storage = st.ext
    if not storage or not IsValid(storage.ent) then return nil end
    -- The range timer closes it within half a second; check here too.
    if not ply:Alive() or ply:GetPos():DistToSqr(storage.ent:GetPos()) > MAX_DIST * MAX_DIST then return nil end
    return st, storage
end

-- Your item -> the storage (dragged onto it at x, y).
function Inv.Deposit(ply, uid, x, y, rot, single)
    if Inv.Locked and Inv.Locked(ply) then return end
    local st, storage = openStorage(ply)
    if not st then return end
    local inst = st.byUid[uid]
    if not inst then return end
    if storage.bulkOnly then
        Inv.Note(ply, "Use Store all")
        I.sendSet(ply, st, inst)
        return
    end
    local canLeave, why = Items.CanLeave(st, inst)
    if not canLeave then
        Inv.Note(ply, why)
        I.sendSet(ply, st, inst)
        return
    end
    local n = single and 1 or inst.count
    if storage.noDeposit then
        Inv.Note(ply, "You can only take things out of here")
        I.sendSet(ply, st, inst)
        return
    end

    if storage.kind == "depot" then
        -- Handing stocked gear back: it's just removed.
        local stocked = false
        for _, id in ipairs(storage.stock) do
            if id == inst.id then stocked = true break end
        end
        if not stocked or not (inst.data and inst.data.issued) then
            -- Only issued gear goes back (your own items would just vanish).
            Inv.Note(ply, stocked and "Only issued gear can be handed back here" or "That doesn't go in here")
            I.sendSet(ply, st, inst)
            return
        end
        if n >= inst.count then I.removeInst(ply, st, uid) else
            inst.count = inst.count - n
            I.update(ply, st, inst)
        end
        return
    end

    -- Grid storage: merge onto a matching stack, or place at x, y.
    if inst.data and inst.data.loadout then
        Inv.Note(ply, "Job gear can't be stored")
        I.sendSet(ply, st, inst)
        return
    end
    I.captureWeapon(ply, inst)
    -- (uid -1: your item's uid means nothing inside the storage)
    local probe = { uid = -1, id = inst.id, count = n, data = inst.data }
    local target = Items.MergeTarget(storage.items, probe, x, y)
    if target then
        local def = Items.defs[inst.id]
        n = math.min(n, def.stack - target.count)
        target.count = target.count + n
        sendChange(storage, OP_SET, target)
    elseif Items.Fits(storage.w, storage.h, storage.items, inst.id, x, y, rot) then
        local o = { uid = nextUid(storage), id = inst.id, c = EXT, x = x, y = y, rot = rot, count = n, data = table.Copy(inst.data or {}) }
        o.data.hidden = nil
        storage.items[o.uid] = o
        sendChange(storage, OP_SET, o)
    else
        I.sendSet(ply, st, inst)
        return
    end
    if n >= inst.count then I.removeInst(ply, st, uid) else
        inst.count = inst.count - n
        I.update(ply, st, inst)
    end
    changedStorage(storage, ply)
end

-- Storage item -> your container cid at x, y.
function Inv.Take(ply, suid, cid, x, y, rot, single)
    if Inv.Locked and Inv.Locked(ply) then return end
    local st, storage = openStorage(ply)
    if not st or cid == EXT then return end
    if storage.bulkOnly then return Inv.Note(ply, "Use Take all") end
    local so = storage.items[suid]
    if not so then return end
    local def = Items.defs[so.id]
    if not def then return end
    if Items.Unique(def) and Inv.Has(ply, so.id) then
        Inv.Note(ply, "You already carry one")
        return
    end
    if not Inv.MayHold(ply, so.id) then
        Inv.Note(ply, Inv.HoldReason(so.id))
        return
    end
    -- (rhylib_gear: parts a rank or qualification unlocks)
    local okTake, takeWhy = hook.Run("Rhylib.CanTakeStock", ply, storage, so.id)
    if okTake == false then
        Inv.Note(ply, takeWhy or "You can't take that")
        return
    end

    if Items.IsWorn(cid) then
        local okWear, wearWhy = Items.CanWear(ply, def)
        if not okWear then
            Inv.Note(ply, wearWhy)
            return
        end
    end

    local depot = storage.kind == "depot"
    local n = single and 1 or so.count
    local data = depot and { fill = def.fill and 1 or nil, issued = true } or table.Copy(so.data or {})

    -- Merge onto a matching stack of yours, or place at x, y.
    local c = st.cont[cid]
    local probe = { uid = -1, id = so.id, count = n, data = data }
    local target = c and not Items.IsWorn(cid) and Items.MergeTarget(c.items, probe, x, y, ply)
    if target then
        n = math.min(n, Items.StackFor(def, ply) - target.count)
        if n <= 0 then return end
        target.count = target.count + n
        if data.issued then target.data.issued = true end
        I.update(ply, st, target)
    elseif Items.CanPlace(st, so.id, cid, x, y, rot) then
        n = math.min(n, Items.StackFor(def, ply))   -- (your stack size; the rest stays)
        local inst = { uid = I.nextUid(st), id = so.id, count = n, data = data }
        Inv.AutoHotbar(st, inst)
        I.place(ply, st, inst, cid, x, y, rot)
        I.giveWeapon(ply, inst)
    else
        return
    end

    if depot then return end  -- endless: nothing leaves the depot
    if n >= so.count then
        storage.items[suid] = nil
        sendChange(storage, OP_REMOVE, nil, suid)
    else
        so.count = so.count - n
        sendChange(storage, OP_SET, so)
    end
    changedStorage(storage, ply)
end

local function tookSound(ply)
    Rhylib.Net.Start("inv.took")
    net.Send(ply)
end

-- Right-click quick take: storage item -> wherever it fits in your
-- inventory (stacks first). single: just one.
function Inv.QuickTake(ply, suid, single)
    if Inv.Locked and Inv.Locked(ply) then return end
    local st, storage = openStorage(ply)
    if not st then return end
    if storage.bulkOnly then return Inv.Note(ply, "Use Take all") end
    local so = storage.items[suid]
    if not so then return end
    local def = Items.defs[so.id]
    if not def then return end
    if Items.Unique(def) and Inv.Has(ply, so.id) then
        Inv.Note(ply, "You already carry one")
        return
    end
    if not Inv.MayHold(ply, so.id) then
        Inv.Note(ply, Inv.HoldReason(so.id))
        return
    end
    -- (rhylib_gear: parts a rank or qualification unlocks)
    local okTake, takeWhy = hook.Run("Rhylib.CanTakeStock", ply, storage, so.id)
    if okTake == false then
        Inv.Note(ply, takeWhy or "You can't take that")
        return
    end
    local depot = storage.kind == "depot"
    local n = single and 1 or so.count
    if depot then n = math.min(n, Items.StackFor(def, ply)) end
    local data = depot and { fill = def.fill and 1 or nil, issued = true } or table.Copy(so.data or {})
    local taken = n - Inv.AddItem(ply, so.id, n, data)
    if taken <= 0 then
        Inv.Note(ply, "No room for that")
        return
    end
    tookSound(ply)
    if depot then return end   -- endless
    if taken >= so.count then
        storage.items[suid] = nil
        sendChange(storage, OP_REMOVE, nil, suid)
    else
        so.count = so.count - taken
        sendChange(storage, OP_SET, so)
    end
    changedStorage(storage, ply)
end

local BULK_FROM = { Items.MAIN, Items.BACK, Items.RACK, Items.BELT, Items.HOLSTER }

-- Store all: everything you carry goes in, except job gear and the
-- backpack you wear (its contents do go in).
local function storeAll(ply, st, storage)
    if storage.bulkOnly and next(storage.items) ~= nil then
        Inv.Note(ply, "Take your stored gear back (or empty it) first")
        return
    end
    local list = {}
    for _, cid in ipairs(BULK_FROM) do
        local c = st.cont[cid]
        if c then
            for _, inst in pairs(c.items) do
                if not (inst.data and inst.data.loadout) and Items.CanLeave(st, inst) then list[#list + 1] = inst end
            end
        end
    end
    if #list == 0 then
        Inv.Note(ply, "Nothing to store (job gear stays with you)")
        return
    end
    -- Big things first: they pack better.
    table.sort(list, function(a, b)
        local da, db = Items.defs[a.id], Items.defs[b.id]
        return (da and da.w * da.h or 1) > (db and db.w * db.h or 1)
    end)
    if storage.grow then storage.h = GROW_MAX end
    local stored, full = 0, false
    for _, inst in ipairs(list) do
        local def = Items.defs[inst.id]
        if def then
            I.captureWeapon(ply, inst)
            local data = table.Copy(inst.data or {})
            data.hidden = nil
            local left = inst.count
            -- Top up matching full stacks first.
            if def.stack > 1 and Items.IsFull(inst) then
                for _, o in pairs(storage.items) do
                    if left <= 0 then break end
                    if o.id == inst.id and o.count < def.stack and Items.IsFull(o) and Items.SameIssued(o, inst) then
                        local add = math.min(def.stack - o.count, left)
                        o.count = o.count + add
                        left = left - add
                    end
                end
            end
            if left > 0 then left = Inv.StorageAdd(storage, inst.id, left, data) end
            local moved = inst.count - left
            if moved > 0 then
                stored = stored + 1
                if moved >= inst.count then I.removeInst(ply, st, inst.uid) else
                    inst.count = left
                    I.update(ply, st, inst)
                end
            end
            if left > 0 then full = true end
        end
    end
    if full then Inv.Note(ply, "The deposit is full: some things stayed with you") end
    return stored > 0
end

-- Take all: everything back that fits; the rest stays stored.
local function takeAll(ply, st, storage)
    local list = {}
    for _, o in pairs(storage.items) do list[#list + 1] = o end
    if #list == 0 then
        Inv.Note(ply, "Nothing stored here")
        return
    end
    table.sort(list, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    local took, left = false, false
    for _, so in ipairs(list) do
        local n = so.count - Inv.AddItem(ply, so.id, so.count, table.Copy(so.data or {}))
        if n > 0 then
            took = true
            if n >= so.count then storage.items[so.uid] = nil else so.count = so.count - n end
        end
        if storage.items[so.uid] then left = true end
    end
    if left then Inv.Note(ply, "Not everything fit: the rest is still stored") end
    return took
end

-- action 0: store all, 1: take all, 2: empty (deletes everything in it).
function Inv.Bulk(ply, action)
    if Inv.Locked and Inv.Locked(ply) then return end
    local st, storage = openStorage(ply)
    if not st or not storage.bulk or storage.kind ~= "grid" then return end
    local did
    if action == 0 then
        did = storeAll(ply, st, storage)
    elseif action == 1 then
        did = takeAll(ply, st, storage)
    else
        did = next(storage.items) ~= nil
        storage.items = {}
        if did then Inv.Note(ply, "Emptied") end
    end
    fitHeight(storage)
    -- Many changes at once: send the whole storage again.
    for p in pairs(storage.viewers) do
        if IsValid(p) then sendOpen(p, storage) end
    end
    if did then
        if action ~= 2 then tookSound(ply) end
        changedStorage(storage, ply)
    end
end

-- Rearranging inside a grid storage.
function Inv.StorageMove(ply, suid, x, y, rot, single)
    local st, storage = openStorage(ply)
    if not st or storage.kind == "depot" then return end
    if storage.bulkOnly then
        local so = storage.items[suid]
        if so then sendChange(storage, OP_SET, so) end   -- (put the client's copy back)
        return
    end
    local so = storage.items[suid]
    if not so then return end
    local def = Items.defs[so.id]
    local n = single and 1 or so.count

    local target = Items.MergeTarget(storage.items, so, x, y)
    if target and target ~= so then
        n = math.min(n, def.stack - target.count)
        target.count = target.count + n
        sendChange(storage, OP_SET, target)
    elseif n < so.count and Items.Fits(storage.w, storage.h, storage.items, so.id, x, y, rot) then
        local o = { uid = nextUid(storage), id = so.id, c = EXT, x = x, y = y, rot = rot, count = n, data = table.Copy(so.data or {}) }
        storage.items[o.uid] = o
        sendChange(storage, OP_SET, o)
    elseif n >= so.count and Items.Fits(storage.w, storage.h, storage.items, so.id, x, y, rot, suid) then
        so.x, so.y, so.rot = x, y, rot
        sendChange(storage, OP_SET, so)
        changedStorage(storage, ply)
        return
    else
        sendChange(storage, OP_SET, so)  -- put the client's copy back
        return
    end
    if n >= so.count then
        storage.items[suid] = nil
        sendChange(storage, OP_REMOVE, nil, suid)
    else
        so.count = so.count - n
        sendChange(storage, OP_SET, so)
    end
    changedStorage(storage, ply)
end

--------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------

Rhylib.Net.Receive("inv.take", function(ply)
    local suid = net.ReadUInt(Items.UID_BITS)
    local cid = net.ReadUInt(Items.CONT_BITS)
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    local single = net.ReadBool()
    Inv.Take(ply, suid, cid, x, y, rot, single)
end, { rate = 20, burst = 10 })

Rhylib.Net.Receive("inv.extmove", function(ply)
    local suid = net.ReadUInt(Items.UID_BITS)
    local x = net.ReadUInt(Items.POS_BITS)
    local y = net.ReadUInt(Items.POS_BITS)
    local rot = net.ReadBool()
    local single = net.ReadBool()
    Inv.StorageMove(ply, suid, x, y, rot, single)
end, { rate = 20, burst = 10 })

Rhylib.Net.Receive("inv.quick", function(ply)
    local suid = net.ReadUInt(Items.UID_BITS)
    Inv.QuickTake(ply, suid, net.ReadBool())
end, { rate = 10, burst = 6 })

Rhylib.Net.Receive("inv.bulk", function(ply)
    Inv.Bulk(ply, net.ReadUInt(2))
end, { rate = 2, burst = 2 })

Rhylib.Net.Receive("inv.close", function(ply)
    Inv.CloseStorage(ply, true)
end, { rate = 5, burst = 5 })
