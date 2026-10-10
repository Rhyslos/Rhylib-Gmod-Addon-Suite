--[[
    Client copy of your own inventory (client only). Filled once from
    "inv.full", then kept up to date by the batched "inv.upd" changes. The
    UI reads it. Also has every Inv.Request* function: the client never
    changes items itself, it asks the server (see sv_10_inventory and
    sv_30_storage for what each message holds).

    Same shape as the server: Inv.cont[cid] = { w, h, items }, Inv.byUid.
    An open outside container (locker, armoury, crate) is Inv.cont[EXT]
    with its own uids, plus Inv.ext = { title, depot, canLock, locked, bulk, bulkOnly }.
    Because Rhylib.Inventory has a `cont` table, it can be passed to the
    shared rules as a state: Items.CanPlace(Rhylib.Inventory, ...),
    Items.Weight(Rhylib.Inventory).
]]

Rhylib.Inventory = Rhylib.Inventory or {}
local Inv = Rhylib.Inventory
local Items = Rhylib.Items

-- (gear slots come with the server's full copy)
Inv.cont = Inv.cont or { [Items.MAIN] = { w = 6, h = 3, items = {} }, [Items.SLOT_BACK] = { w = 1, h = 1, items = {} } }
Inv.byUid = Inv.byUid or {}

local EXT = Items.EXT
Inv.ext = Inv.ext or nil
Inv.busyEnd = Inv.busyEnd or 0   -- combining munitions until this time

local function setInst(inst)
    if not inst.id then return end
    local old = Inv.byUid[inst.uid]
    if old and Inv.cont[old.c] then Inv.cont[old.c].items[old.uid] = nil end
    local c = Inv.cont[inst.c]
    if not c then return end
    c.items[inst.uid] = inst
    Inv.byUid[inst.uid] = inst
end

local function removeInst(uid)
    local old = Inv.byUid[uid]
    if not old then return end
    if Inv.cont[old.c] then Inv.cont[old.c].items[uid] = nil end
    Inv.byUid[uid] = nil
end

local function setDims(cid, w, h)
    if w == 0 or h == 0 then
        Inv.cont[cid] = nil
        return
    end
    local cur = Inv.cont[cid]
    Inv.cont[cid] = { w = w, h = h, items = cur and cur.items or {} }
end

net.Receive(Rhylib.Net.Name("inv.full"), function()
    Items.EnsureReady()
    Inv.cont = {}
    Inv.byUid = {}
    local nc = net.ReadUInt(Items.CONT_BITS + 1)
    for _ = 1, nc do
        local cid = net.ReadUInt(Items.CONT_BITS)
        setDims(cid, net.ReadUInt(5), net.ReadUInt(5))
    end
    local n = net.ReadUInt(8)
    for _ = 1, n do setInst(Items.ReadInstance()) end
end)

Rhylib.Net.ReceiveBatch("inv.upd", function()
    local op = net.ReadUInt(2)
    if op == 1 then return { op = 1, inst = Items.ReadInstance() } end
    if op == 0 then return { op = 0, uid = net.ReadUInt(Items.UID_BITS) } end
    return { op = 2, cid = net.ReadUInt(Items.CONT_BITS), w = net.ReadUInt(5), h = net.ReadUInt(5) }
end, function(ch)
    if ch.op == 1 then
        setInst(ch.inst)
    elseif ch.op == 0 then
        removeInst(ch.uid)
    else
        setDims(ch.cid, ch.w, ch.h)
    end
end)

-- Outside container ------------------------------------------------------

net.Receive(Rhylib.Net.Name("inv.ext"), function()
    Items.EnsureReady()
    if not net.ReadBool() then
        Inv.cont[EXT] = nil
        Inv.ext = nil
        return
    end
    local ext = {
        title = net.ReadString(),
        depot = net.ReadBool(),
    }
    local w, h = net.ReadUInt(5), net.ReadUInt(5)
    ext.canLock = net.ReadBool()
    ext.locked = net.ReadBool()
    local bulk = net.ReadUInt(2)
    ext.bulk = bulk > 0
    ext.bulkOnly = bulk == 2
    local c = { w = w, h = h, items = {} }
    for _ = 1, net.ReadUInt(8) do
        local inst = Items.ReadInstance()
        if inst.id then c.items[inst.uid] = inst end
    end
    Inv.cont[EXT] = c
    Inv.ext = ext
    -- (another storage: quick takes queued for the old one are dropped)
    if IsValid(Inv.panel) then Inv.panel.quick = nil end
    if not IsValid(Inv.panel) then Inv.Toggle() end
end)

Rhylib.Net.ReceiveBatch("inv.extupd", function()
    if net.ReadUInt(1) == 1 then return { set = Items.ReadInstance() } end
    return { uid = net.ReadUInt(Items.UID_BITS) }
end, function(ch)
    local c = Inv.cont[EXT]
    if not c then return end
    if ch.set then
        if ch.set.id then c.items[ch.set.uid] = ch.set end
    else
        c.items[ch.uid] = nil
    end
end)

-- Inv.ShowNote(text): a short note in the window (from the client
-- itself); a notification when the window is shut.
function Inv.ShowNote(text)
    if not text then return end
    Inv.note, Inv.noteTime = text, RealTime()
    if not IsValid(Inv.panel) then notification.AddLegacy(text, NOTIFY_GENERIC, 3) end
end

-- Short messages from the server, shown in the inventory window.
net.Receive(Rhylib.Net.Name("inv.note"), function()
    Inv.note = net.ReadString()
    Inv.noteTime = RealTime()
    if not IsValid(Inv.panel) then notification.AddLegacy(Inv.note, NOTIFY_GENERIC, 3) end
end)

net.Receive(Rhylib.Net.Name("inv.busy"), function()
    Inv.busyEnd = net.ReadFloat()
    Inv.busyStart = CurTime()
end)

-- Inv.RequestTake(inst, cid, x, y, rot, single): take a storage item into
-- your container cid at x, y.
function Inv.RequestTake(inst, cid, x, y, rot, single)
    Rhylib.Net.Start("inv.take")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(cid, Items.CONT_BITS)
    net.WriteUInt(x, Items.POS_BITS)
    net.WriteUInt(y, Items.POS_BITS)
    net.WriteBool(rot)
    net.WriteBool(single or false)
    net.SendToServer()
end

-- Inv.RequestQuickTake(inst, single): right-click quick take: the server
-- puts it wherever it fits.
function Inv.RequestQuickTake(inst, single)
    Rhylib.Net.Start("inv.quick")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteBool(single or false)
    net.SendToServer()
end

-- Inv.RequestBulk(action): bulk storages: 0 = store all, 1 = take all, 2 = empty.
function Inv.RequestBulk(action)
    Rhylib.Net.Start("inv.bulk")
    net.WriteUInt(action, 2)
    net.SendToServer()
end

-- Something came into (or went out of) your inventory from a storage.
net.Receive(Rhylib.Net.Name("inv.took"), function()
    surface.PlaySound("items/ammo_pickup.wav")
end)

-- Inv.RequestExtMove(inst, x, y, rot, single): move an item inside the
-- open grid storage.
function Inv.RequestExtMove(inst, x, y, rot, single)
    Rhylib.Net.Start("inv.extmove")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(x, Items.POS_BITS)
    net.WriteUInt(y, Items.POS_BITS)
    net.WriteBool(rot)
    net.WriteBool(single or false)
    net.SendToServer()
end

-- Inv.CloseExt(): close the open storage (closing the window does this).
function Inv.CloseExt()
    if not Inv.ext then return end
    Inv.cont[EXT] = nil
    Inv.ext = nil
    Rhylib.Net.Start("inv.close")
    net.SendToServer()
end

-- Inv.RequestHotbar(inst, n): put an item in hotbar slot n, or empty the
-- slot (inst nil).
function Inv.RequestHotbar(inst, n)
    Rhylib.Net.Start("inv.hotbar")
    net.WriteUInt(inst and inst.uid or 0, Items.UID_BITS)
    net.WriteUInt(n, 3)
    net.SendToServer()
end

-- Inv.HotbarItem(n): the item in hotbar slot n, if any (the HUD hotbar
-- reads this).
function Inv.HotbarItem(n)
    for _, inst in pairs(Inv.byUid) do
        if inst.hb == n then return inst end
    end
end

-- Inv.RequestSplit(inst) / Inv.RequestCombine(): split a stack / combine
-- partly used magazines and cells.
function Inv.RequestSplit(inst)
    Rhylib.Net.Start("inv.split")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.SendToServer()
end

function Inv.RequestCombine()
    Rhylib.Net.Start("inv.combine")
    net.SendToServer()
end

-- Requests ------------------------------------------------------------------

-- Inv.RequestFull(): ask for the whole inventory again (inv.req).
function Inv.RequestFull()
    Rhylib.Net.Start("inv.req")
    net.SendToServer()
end

-- Inv.RequestMove(inst, cid, x, y, rot, single): move one of your items.
-- Moves locally right away so dragging feels instant; the server confirms
-- or sends the item back where it was. single: just one off a stack
-- (not moved locally; the server's answer shows it). Moving into the
-- outside container (cid EXT) is decided by the server too.
function Inv.RequestMove(inst, cid, x, y, rot, single)
    local c = Inv.cont[cid]
    if not c then return end
    if cid ~= inst.c then
        local canLeave, why = Items.CanLeave(Inv, inst)
        if not canLeave then
            if Inv.ShowNote then Inv.ShowNote(why) end
            return
        end
        if Items.IsWorn(cid) then
            local okWear, wearWhy = Items.CanWear(LocalPlayer(), Items.defs[inst.id])
            if not okWear then
                if Inv.ShowNote then Inv.ShowNote(wearWhy) end
                return
            end
        end
    end
    single = single and inst.count > 1

    local merge = not Items.IsWorn(cid) and Items.MergeTarget(c.items, inst, x, y, cid ~= EXT and LocalPlayer() or nil)
    if not merge and not single and cid ~= EXT then
        if not Items.CanPlace(Inv, inst.id, cid, x, y, rot, inst.uid) then return end
        local moved = { uid = inst.uid, id = inst.id, c = cid, x = x, y = y, rot = rot, count = inst.count, data = inst.data }
        setInst(moved)
    end

    Rhylib.Net.Start("inv.move")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteUInt(cid, Items.CONT_BITS)
    net.WriteUInt(x, Items.POS_BITS)
    net.WriteUInt(y, Items.POS_BITS)
    net.WriteBool(rot)
    net.WriteBool(single or false)
    net.SendToServer()
end

-- Inv.RequestDrop(inst, single): drop it (or one of a stack) on the ground.
function Inv.RequestDrop(inst, single)
    Rhylib.Net.Start("inv.drop")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteBool(single or false)
    net.SendToServer()
end

-- Inv.RequestGive(inst, single, target): hand it to another player
-- (sv_40_give checks range and sight).
function Inv.RequestGive(inst, single, target)
    Rhylib.Net.Start("inv.give")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.WriteBool(single or false)
    net.WriteEntity(target)
    net.SendToServer()
end

-- Inv.RequestHold(uid): hold a hotbar item (def.hand) in your hand
-- (rhylib_hand weapon; the HUD hotbar calls it).
function Inv.RequestHold(uid)
    Rhylib.Net.Start("inv.hold")
    net.WriteUInt(uid, Items.UID_BITS)
    net.SendToServer()
end

-- Inv.GiveTarget(): the player you're looking at, close enough to give to
-- (or nil). Picked from the interaction wheel: that player for 60 s while
-- in range.
function Inv.GiveTarget()
    local ply = LocalPlayer()
    local r = Rhylib.Config.Get("inventory", "giveRange") or 130
    local w = Inv.giveTo
    if IsValid(w) and w:Alive() and RealTime() - (Inv.giveToAt or 0) < 60 and w:GetPos():DistToSqr(ply:GetPos()) < r * r then return w end
    local tr = util.TraceHull({
        start = ply:EyePos(), endpos = ply:EyePos() + ply:GetAimVector() * r,
        filter = ply, mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), mask = MASK_SHOT_HULL,
    })
    local e = tr.Entity
    if IsValid(e) and e:IsPlayer() and e:Alive() then return e end
end

-- Inv.RequestHide(inst): hide / unhide a contraband item from searches (rhylib_mp).
function Inv.RequestHide(inst)
    Rhylib.Net.Start("inv.hide")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.SendToServer()
end

-- Inv.RequestUse(inst): switch to that weapon item's weapon.
function Inv.RequestUse(inst)
    Rhylib.Net.Start("inv.use")
    net.WriteUInt(inst.uid, Items.UID_BITS)
    net.SendToServer()
end

Rhylib.Hook.Add("InitPostEntity", "inventory.request", function()
    Inv.RequestFull()
end)

-- After a Lua refresh the player already exists, so ask again.
if IsValid(LocalPlayer()) then Inv.RequestFull() end
