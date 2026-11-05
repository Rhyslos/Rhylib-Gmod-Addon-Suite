--[[
    Quartermaster (server): saved loadouts, checking and applying them.
    sh_50_quartermaster.lua has the settings and constants; the window is
    cl_50_quartermaster.lua; the NPC is entities/rhylib_quartermaster.lua.

    Three loadout slots per player (rhylib_roster has one character per
    player, so per player; wiped with it by Rhylib.CharacterReset). Saved:
    Data "armoury_qm" / "s" .. SteamID64 = { s1 = slot, s2 = slot, s3 = slot },
    slot = { name, t (os.time saved), kg, rows = { { id, container, x, y,
    rot 0/1, count, hotbar 0-6 }, ... } }.

    Saving stores what you carry that he can take in (see "What he takes
    in" in the shared file): worn gear, backpack and contents included,
    job gear (data.loadout) never.

    Applying, all on the server:
      1. Plan on a copy of the inventory state: job gear stays where it is
         (and a worn backpack / pouch holding job gear stays on, meeting the
         loadout's own row of that item: nothing issued twice); the rest
         is handed in; each saved row is then checked against the player
         as they are now, with the depot take's own checks: Inv.MayHold
         (carry skills), hook Rhylib.CanTakeStock (rhylib_gear unlocks),
         the cabinets' stock lists for this player (A.Roles specialist
         roles, gear cabinet per player), Inv.Limit (one-only guns),
         the armoury stock (hook Rhylib.DepotStock, after what the hand-in
         puts back) and Inv.WeightRoom (the weight ceiling). Then each item
         goes back to its saved spot, or anywhere it fits (I.findSpot,
         where Inv.AddItem would put it); what fits nowhere stays in stock.
      2. Hand in: everything but job gear is removed; stock-marked items
         (Inv.StockMarked) fire Rhylib.DepotReturned, like a depot hand-in.
      3. Issue the plan: fresh, full, issued items ({ fill = 1 for fill
         items, issued = true, stock = true when counted }), weapons given
         (I.giveWeapon; a gun the player still holds gets the fresh state
         with SetInventoryData), hotbar keys as saved when free; counted the
         moment each is in, then Rhylib.DepotTook per item. Saved at once.
         Whatever couldn't be handed in is issued that much less.
    Nothing changes when planning fails. Carrying anything he can't take in
    refuses applying.

    Two steps: op check -> net armoury.qmprob (what can't be issued and
    why, maybe nothing) -> the client confirms with an option -> the server
    plans again and applies, or asks again if something new (or more of
    something) is in the way. The cabinets' lists are cached (Q.ForgetLists).

    Handout: with qmIssueTime > 0 a confirmed apply starts a timed handout
    (Q.StartHand: the slot's rows copied, one per player, net armoury.qmhand
    once with the start and duration). It stops (nothing changes, no
    cooldown) when the player walks off, dies, goes down, is cuffed, closes
    the window, presses Stop, or the NPC goes (Q.Tick, twice a second); at
    the end (Q.FinishHand) a changed slot stops it, then the plan is made
    and checked again exactly like a confirm and applied (Q.ApplyNow); the
    cooldown starts then. Nothing else is accepted while it runs.

    Editor (qmEditor): op editor 0 sends net armoury.qmcat (the catalogue
    with each shelf's tab, stock, one-only limit and why it's locked, the
    empty inventory's grids, the slot's rows, what you carry); op editor 1
    saves rows the client built: Q.ValidateRows checks every row (Q.RuleCheck,
    stack sizes, one-only limits, placed on an empty copy of the inventory,
    weight within the ceiling, at most Q.MAX_ROWS) and refuses the whole
    save with a reason (net armoury.qmeditres).

    Nets:
      armoury.qmact  (client -> server) npc Entity, op UInt 3, slot UInt 2
                     (1-3; 0 with close / stop), then: apply option UInt 2;
                     rename String; editor: sub UInt 1 (0 open, 1 save),
                     save: name String, rows UInt 7 x (item NET_BITS,
                     container UInt 5, x UInt 5, y UInt 5, rot Bool, count
                     UInt 8, hotbar UInt 3), at most 16384 bits. Range qmRange, alive, not down / cuffed /
                     unable to act, inventory not locked. Rate 4/s, burst 6.
                     Applies at most once per qmCooldown seconds.
      armoury.qm     (server -> player) npc Entity, weight UInt 12 (0.1 kg),
                     cooldown left UInt 8 (s), last applied slot UInt 2,
                     carried rows UInt 8: item NET_BITS, count UInt 8, kind
                     UInt 2 (0 issuable, 1 job gear, 2 blocked), worn Bool,
                     fill UInt 7 (0-100, 127 = none); blocked UInt 6: item
                     NET_BITS, why UInt 2; then 3 slots: has Bool; name
                     String, age UInt 32 (s), weight UInt 12 (0.1 kg), kinds
                     UInt 7: item NET_BITS, count UInt 8, worn Bool, stock
                     UInt 2 (0 fine, 1 low, 2 not enough, 3 out).
      armoury.qmprob (server -> player) npc Entity, slot UInt 2, nothing
                     Bool (nothing can be issued), again Bool (changed since
                     the last check), count UInt 7: item NET_BITS (0 =
                     unknown, then its id String), count UInt 8, why UInt 3,
                     reason String.
      armoury.qmhand (server -> player) npc Entity, running Bool; running:
                     slot UInt 2, start Float, duration Float, backpack Bool.
      armoury.qmcat  (server -> player) see Q.SendCatalogue.
      armoury.qmeditres (server -> player) saved Bool, reason String.
    Hooks fired: Rhylib.DepotReturned, Rhylib.DepotTook (as the depots do),
    asks Rhylib.DepotStock, Rhylib.CanTakeStock (storage = a stand-in
    depot table with quartermaster = true), Rhylib.GearReturnable.
    Listens: Rhylib.InventoryChanged (refresh an open window),
    Rhylib.CharacterReset (loadouts deleted), PlayerDisconnected.
    Placements: Rhylib.Perma.Placements "armoury_qm" (Data
    "armoury_qm_places" / map), console rhylib_quartermaster_save.
]]

local A = Rhylib.Armoury
local Q = A.QM
local cfg = Rhylib.Config.For("armoury")

Rhylib.Net.Register("armoury.qm")
Rhylib.Net.Register("armoury.qmprob")

local DATA = "armoury_qm"
local PENDING = 31        -- (a container id no grid uses: planned items not placed yet)
local TAG = "Quartermaster"

Q.cache = Q.cache or {}       -- [sid] = saved table
Q.viewers = Q.viewers or {}   -- [ply] = npc, window open
Q.applied = Q.applied or {}   -- [ply] = slot last applied this session

local function Inv() return Rhylib.Inventory end
local function II() return Rhylib.Inventory and Rhylib.Inventory.Internal end
local function Items() return Rhylib.Items end

local function note(ply, text, kind) Rhylib.Notify(ply, text, kind or "info", TAG) end

--------------------------------------------------------------------------
-- Saved loadouts
--------------------------------------------------------------------------

local function dataKey(sid) return "s" .. sid end

local function savedOf(ply)
    local sid = ply:SteamID64()
    if not sid then return nil end
    local t = Q.cache[sid]
    if t then return t end
    t = Rhylib.Data.Get(DATA, dataKey(sid))
    if not istable(t) then t = {} end
    Q.cache[sid] = t
    return t
end

local function store(ply)
    local sid = ply:SteamID64()
    local t = sid and Q.cache[sid]
    if not t then return end
    if next(t) == nil then Rhylib.Data.Delete(DATA, dataKey(sid)) else Rhylib.Data.Set(DATA, dataKey(sid), t) end
end

-- (a saved slot with sane rows, or nil)
local function slotOf(ply, n)
    local t = savedOf(ply)
    local s = t and t["s" .. n]
    if not (istable(s) and istable(s.rows)) then return nil end
    return s
end

local function rowOk(r)
    return istable(r) and isstring(r[1]) and isnumber(r[2]) and isnumber(r[3]) and isnumber(r[4]) and isnumber(r[6])
end

local function slotTitle(slot, s)
    local name = s and isstring(s.name) and s.name ~= "" and s.name or Q.DefaultName(slot)
    if name == Q.DefaultName(slot) then return name end
    return "Loadout " .. slot .. " · " .. name
end

--------------------------------------------------------------------------
-- What the armouries issue
--------------------------------------------------------------------------

local function addAll(set, list)
    for _, id in ipairs(list or {}) do set[id] = true end
end

local function isTraining(id, def)
    return def.category == "training" or Items().GroupOf(def) == "training" or string.find(id, "_training", 1, true) ~= nil
end

local function returnable()
    local back = {}
    hook.Run("Rhylib.GearReturnable", back)
    return back
end

-- The lists that don't depend on the player, built once and kept until
-- an armoury setting changes, items are registered again (a new
-- Items.byNet table) or the map's entities are in (InitPostEntity):
-- { weapons = set, ammo = set, base = the catalogue without the player's
-- own gear cabinet parts }.
local shared
local function sharedLists()
    local It = Items()
    It.EnsureReady()
    if shared and shared.byNet == It.byNet then return shared end
    local weaponsSet, ammo, base = {}, {}, {}
    addAll(weaponsSet, A.WeaponStock())
    addAll(ammo, A.AmmoStock())
    for id in pairs(weaponsSet) do base[id] = true end
    for id in pairs(ammo) do base[id] = true end
    local cabinets = {}
    for id in pairs(base) do cabinets[id] = true end
    addAll(base, A.GearStock())
    addAll(cabinets, A.GearStock())
    for id in pairs(returnable()) do base[id] = true cabinets[id] = true end
    local roleOnly = {}
    local roles = cfg("roles")
    if istable(roles) then
        local names = {}
        for r in pairs(roles) do names[#names + 1] = r end
        local roleItems = {}
        addAll(roleItems, A.RoleStock(names, "weapons"))
        addAll(roleItems, A.RoleStock(names, "gear"))
        for id in pairs(roleItems) do
            base[id] = true
            if not cabinets[id] then roleOnly[id] = true end
        end
    end
    shared = { byNet = It.byNet, weapons = weaponsSet, ammo = ammo, base = base, roleOnly = roleOnly, roleWho = {} }
    return shared
end
function Q.ForgetLists() shared = nil end
Rhylib.Hook.Add("Rhylib.ConfigChanged", "armoury.qm", function(m) if m == "armoury" then shared = nil end end)
Rhylib.Hook.Add("InitPostEntity", "armoury.qm", function() shared = nil end)
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "armoury.qm", function() shared = nil end)

-- Q.Catalogue(ply) -> { [id] = true }: everything the armoury depots on
-- this server hand out (any role; the gear cabinet's parts; no training).
function Q.Catalogue(ply)
    local It = Items()
    local sh = sharedLists()
    local set = {}
    for id in pairs(sh.base) do set[id] = true end
    if IsValid(ply) then addAll(set, A.GearStock(ply)) end
    for id in pairs(set) do
        local def = It.defs[id]
        if not def or isTraining(id, def) then set[id] = nil end
    end
    return set
end

-- Q.Offered(ply) -> { [id] = true }: what the cabinets would give this
-- player now (weapons armoury, ammo cabinet, their gear cabinet stock,
-- their roles' specialist racks).
function Q.Offered(ply)
    local sh = sharedLists()
    local set = {}
    for id in pairs(sh.weapons) do set[id] = true end
    for id in pairs(sh.ammo) do set[id] = true end
    addAll(set, A.GearStock(ply))
    local roles = A.Roles(ply)
    addAll(set, A.RoleStock(roles, "weapons"))
    addAll(set, A.RoleStock(roles, "gear"))
    return set
end

local ROLE_NAMES = { mp = "military police", medic = "medics", trooper = "troopers" }
local function roleName(r)
    if ROLE_NAMES[r] then return ROLE_NAMES[r] end
    local R = Rhylib.Roster
    local q = R and R.QualName and R.QualName(r)
    return isstring(q) and q ~= "" and q or r
end

local function notOfferedReason(id, back)
    if hook.Run("Rhylib.ItemDisabled", id) then return "Not issued on this server right now" end
    -- (the roles text per item is kept with the cached lists)
    local sh = sharedLists()
    local known = sh.roleWho[id]
    if known ~= nil then
        if known then return known end
        if back[id] then return "The gear cabinet doesn't issue this to you (your model or rank)" end
        return "The armouries don't issue this to you"
    end
    local roles = cfg("roles")
    local who = {}
    if istable(roles) then
        for r, t in SortedPairs(roles) do
            for _, kind in ipairs({ "weapons", "gear" }) do
                if istable(t) and istable(t[kind]) and table.HasValue(t[kind], id) then
                    who[#who + 1] = roleName(r)
                    break
                end
            end
        end
    end
    sh.roleWho[id] = #who > 0 and ("Only issued to " .. table.concat(who, ", ")) or false
    if #who > 0 then return sh.roleWho[id] end
    if back[id] then return "The gear cabinet doesn't issue this to you (your model or rank)" end
    return "The armouries don't issue this to you"
end

-- What's left of an item in the armoury stock (nil = endless), as a
-- counted depot asks.
local function stockLeft(id)
    local n = hook.Run("Rhylib.DepotStock", id)
    return isnumber(n) and math.max(0, math.floor(n)) or nil
end

local function stockMax(id)
    local L = Rhylib.Logistics
    return L and L.StockMax and L.StockMax(id) or nil
end

-- Sorts the inventory into job gear (stays), items he takes in, and items
-- he won't take in ({ inst, why }).
local function classify(st, cat)
    local keep, handIn, blocked = {}, {}, {}
    for _, inst in pairs(st.byUid) do
        local data = inst.data
        if istable(data) and data.loadout then keep[#keep + 1] = inst
        elseif Q.OwnData(data) then blocked[#blocked + 1] = { inst = inst, why = Q.BLOCK_DATA }
        elseif not cat[inst.id] then blocked[#blocked + 1] = { inst = inst, why = Q.BLOCK_FOREIGN }
        else handIn[#handIn + 1] = inst end
    end
    return keep, handIn, blocked
end

--------------------------------------------------------------------------
-- Planning on a copy of the state
--------------------------------------------------------------------------

-- The container ids a worn item adds (backpack grid, pouches...).
local function gridsOf(def)
    local out = {}
    if def.grid then out[#out + 1] = def.gridCid or Items().BACK end
    for _, eg in ipairs(def.extraGrids or {}) do out[#out + 1] = eg.cid end
    return out
end

local function wornGridSet()
    local set = {}
    for _, def in pairs(Items().defs) do
        for _, c in ipairs(gridsOf(def)) do set[c] = true end
    end
    return set
end

local function packMult(ply)
    local K = Rhylib.Skills
    return K and K.BackpackMult and K.BackpackMult(ply) or 1
end

-- (the grids a worn item makes, sized as rhylib_inventory sizes them)
local function vAddGrids(V, ply, def)
    local It = Items()
    if def.grid then
        local gcid = def.gridCid or It.BACK
        local w, h = def.grid[1], def.grid[2]
        if gcid == It.BACK then
            local m = packMult(ply)
            if m ~= 1 then h = math.max(1, math.floor(h * m)) end
        end
        if not V.cont[gcid] then V.cont[gcid] = { w = w, h = h, items = {} } end
    end
    for _, eg in ipairs(def.extraGrids or {}) do
        if not V.cont[eg.cid] then V.cont[eg.cid] = { w = eg.w, h = eg.h, items = {} } end
    end
end

local function vUid(V)
    local u = V.nextUid
    while V.byUid[u] do u = u + 1 end
    V.nextUid = u + 1
    return u
end

local function vPlace(V, ply, vi, cid, x, y, rot)
    local old = vi.c and V.cont[vi.c]
    if old then old.items[vi.uid] = nil end
    vi.c, vi.x, vi.y, vi.rot = cid, x, y, rot
    V.cont[cid].items[vi.uid] = vi
    V.byUid[vi.uid] = vi
    if Items().IsWorn(cid) then
        local def = Items().defs[vi.id]
        if def then vAddGrids(V, ply, def) end
    end
end

local function vDrop(V, vi)
    local c = vi.c and V.cont[vi.c]
    if c then c.items[vi.uid] = nil end
    V.byUid[vi.uid] = nil
    vi.c = nil
end

-- The copy: the player's grids without the ones handed-in gear makes,
-- with the job gear in its place, plus the pending pile.
local function buildVirtual(ply, st, keep)
    local It = Items()
    local wornGrids = wornGridSet()
    local V = { cont = {}, byUid = {}, nextUid = 1, ready = false, ply = ply }
    local provided = {}
    for _, inst in ipairs(keep) do
        if It.IsWorn(inst.c) then
            local def = It.defs[inst.id]
            if def then for _, c in ipairs(gridsOf(def)) do provided[c] = true end end
        end
    end
    for cid, c in pairs(st.cont) do
        if cid ~= It.EXT and (not wornGrids[cid] or provided[cid]) then
            V.cont[cid] = { w = c.w, h = c.h, items = {} }
        end
    end
    for _, inst in ipairs(keep) do
        local vc = V.cont[inst.c]
        if vc then
            local copy = { uid = inst.uid, id = inst.id, c = inst.c, x = inst.x, y = inst.y, rot = inst.rot, count = inst.count, data = inst.data, hb = inst.hb }
            vc.items[inst.uid] = copy
            V.byUid[inst.uid] = copy
        end
    end
    V.cont[PENDING] = { w = 0, h = 0, items = {} }
    return V
end

-- A worn item whose grid holds job gear can't come off: it stays too.
-- Returns the list of those it kept.
local function keepHolders(keep, handIn)
    local It = Items()
    local held = {}
    for _ = 1, 3 do
        local need = {}
        for _, inst in ipairs(keep) do need[inst.c] = true end
        local moved = false
        for i = #handIn, 1, -1 do
            local inst = handIn[i]
            local def = It.IsWorn(inst.c) and It.defs[inst.id]
            if def then
                for _, c in ipairs(gridsOf(def)) do
                    if need[c] then
                        table.remove(handIn, i)
                        keep[#keep + 1] = inst
                        held[#held + 1] = inst
                        moved = true
                        break
                    end
                end
            end
        end
        if not moved then break end
    end
    return held
end

local function stand_in_depot(npc)
    return { kind = "depot", counted = true, ent = npc, title = "Quartermaster", quartermaster = true, items = {}, viewers = {}, subs = {} }
end
Q.StandInDepot = stand_in_depot

-- Q.RuleCheck(ply, id, cat, offered, depot, back) -> nil when this player
-- may draw the item now, else why not: the depot take's own checks (in
-- the catalogue, Inv.MayHold carry skills, hook Rhylib.CanTakeStock, what
-- the cabinets offer this player). Used by the plan and the editor.
function Q.RuleCheck(ply, id, cat, offered, depot, back)
    local I = Inv()
    if not cat[id] then return "The armouries don't issue this any more" end
    if not I.MayHold(ply, id) then return I.HoldReason(id) end
    local okTake, why = hook.Run("Rhylib.CanTakeStock", ply, depot, id)
    if okTake == false then return why or "You can't take that" end
    if not offered[id] then return notOfferedReason(id, back) end
    return nil
end

-- plan(ply, npc, rows) -> plan, or nil and the error. plan = { blocked,
-- problems = { { id, n, why, text } }, entries = { { vi } } (in placing
-- order), handIn, keep, stocked = { [id] = true } }.
local function plan(ply, npc, rows)
    local I, It, Int = Inv(), Items(), II()
    It.EnsureReady()
    local st = I.Get(ply)
    local cat = Q.Catalogue(ply)
    local keep, handIn, blocked = classify(st, cat)
    local p = { blocked = blocked, problems = {}, entries = {}, handIn = handIn, keep = keep, stocked = {} }
    if #blocked > 0 then return p end
    -- (a kept holder counts as the loadout's own copy of it: one saved row
    -- of that item is met by it, nothing new issued, no stock taken)
    local heldLeft = {}
    for _, inst in ipairs(keepHolders(keep, handIn)) do
        heldLeft[inst.id] = (heldLeft[inst.id] or 0) + (inst.count or 1)
    end

    -- (the hand-in comes first: what it puts back can be issued again)
    local returned = {}
    for _, inst in ipairs(handIn) do
        if I.StockMarked(inst.data) then returned[inst.id] = (returned[inst.id] or 0) + inst.count end
    end
    local avail = {}   -- [id] = left after the hand-in, false = endless
    local function availOf(id)
        if avail[id] == nil then
            local left = stockLeft(id)
            if left == nil then
                avail[id] = false
            else
                left = left + (returned[id] or 0)
                local mx = stockMax(id)
                if mx then left = math.min(left, mx) end
                avail[id] = left
            end
        end
        return avail[id]
    end

    local byKey = {}
    local function problem(id, n, why, text)
        if n <= 0 then return end
        local k = id .. ":" .. why
        local pr = byKey[k]
        if pr then pr.n = pr.n + n return end
        pr = { id = id, n = n, why = why, text = text }
        byKey[k] = pr
        p.problems[#p.problems + 1] = pr
    end

    local offered = Q.Offered(ply)
    local depot = stand_in_depot(npc)
    local back = returnable()
    local V = buildVirtual(ply, st, keep)

    -- Worn gear first (the backpack before what goes in it), then as saved.
    local list = {}
    for i, r in ipairs(rows) do
        if rowOk(r) then list[#list + 1] = { i = i, r = r } end
    end
    table.sort(list, function(a, b)
        local wa, wb = It.IsWorn(a.r[2]) and 0 or 1, It.IsWorn(b.r[2]) and 0 or 1
        if wa ~= wb then return wa < wb end
        if wa == 0 then
            local da, db = It.defs[a.r[1]], It.defs[b.r[1]]
            local ra, rb = da and tonumber(da.wornRank) or 0, db and tonumber(db.wornRank) or 0
            if ra ~= rb then return ra < rb end
        end
        return a.i < b.i
    end)

    local pending = {}
    local function fresh(def, id)
        local counted = availOf(id) ~= false
        if counted then p.stocked[id] = true end
        return { fill = def.fill and 1 or nil, issued = true, stock = counted and true or nil }
    end

    local function planRow(r)
        local id, cid, x, y, rot = r[1], math.floor(r[2]), math.floor(r[3]), math.floor(r[4]), r[5] == 1
        local n = math.max(1, math.floor(r[6]))
        local hb = math.floor(tonumber(r[7]) or 0)
        local def = It.defs[id]
        if not def then return problem(id, n, Q.WHY_GONE, "No longer exists on this server") end
        if (heldLeft[id] or 0) > 0 then
            local met = math.min(heldLeft[id], n)
            heldLeft[id] = heldLeft[id] - met
            n = n - met
            if n <= 0 then return end
        end
        local why = Q.RuleCheck(ply, id, cat, offered, depot, back)
        if why then return problem(id, n, Q.WHY_RULE, why) end
        local want = n
        if It.Unique(def) then
            want = 1
            local room = I.Limit(ply, id) - I.Count(ply, id)
            if room < 1 then return problem(id, n, Q.WHY_RULE, I.LimitText(ply, id)) end
        end
        local left = availOf(id)
        if left ~= false and left < want then
            problem(id, want - left, Q.WHY_STOCK, "Out of stock: it comes back with a resupply")
            want = left
        end
        if want <= 0 then return end
        local room = I.WeightRoom(ply, id, want)
        if room < want then
            problem(id, want - room, Q.WHY_HEAVY, I.TOO_HEAVY)
            want = room
        end
        if want <= 0 then return end
        if left ~= false then avail[id] = left - want end

        -- One stack on the saved spot; the rest (and a spot that's taken)
        -- waits for any free spot.
        local cap = It.StackFor(def, ply)
        local data = fresh(def, id)
        local first = math.min(want, cap)
        local vi = { uid = vUid(V), id = id, count = first, data = data, hb = hb > 0 and hb or nil, planned = true }
        local worn = It.IsWorn(cid)
        if V.cont[cid] and It.CanPlace(V, id, cid, x, y, rot) and (not worn or It.CanWear(ply, def)) then
            vPlace(V, ply, vi, cid, x, y, rot)
            p.entries[#p.entries + 1] = { vi = vi }
        else
            vPlace(V, ply, vi, PENDING, 0, 0, false)
            pending[#pending + 1] = vi
        end
        local rest = want - first
        while rest > 0 do
            local m = math.min(rest, cap)
            local more = { uid = vUid(V), id = id, count = m, data = table.Copy(data), planned = true }
            vPlace(V, ply, more, PENDING, 0, 0, false)
            pending[#pending + 1] = more
            rest = rest - m
        end
    end

    -- Anywhere it fits: onto a planned stack, else where AddItem would put it.
    local function placeAnywhere(vi)
        local def = It.defs[vi.id]
        vDrop(V, vi)
        local cap = It.StackFor(def, ply)
        if cap > 1 then
            for _, en in ipairs(p.entries) do
                local o = en.vi
                if vi.count <= 0 then break end
                if o.id == vi.id and not It.IsWorn(o.c) and o.count < cap then
                    local add = math.min(cap - o.count, vi.count)
                    o.count = o.count + add
                    vi.count = vi.count - add
                end
            end
            if vi.count <= 0 then return end
        end
        local c2, x2, y2, r2 = Int.findSpot(V, vi.id)
        if c2 then
            vPlace(V, ply, vi, c2, x2, y2, r2)
            p.entries[#p.entries + 1] = { vi = vi }
        else
            problem(vi.id, vi.count, Q.WHY_ROOM, "No room for it: it stays in stock")
            if avail[vi.id] then avail[vi.id] = avail[vi.id] + vi.count end
        end
    end

    -- (Inv.Count / AtLimit / WeightRoom read Inv.Get(ply): pointed at the
    -- copy for the checks, always put back)
    local real = I.states[ply]
    I.states[ply] = V
    local ok, err = pcall(function()
        for _, e in ipairs(list) do planRow(e.r) end
        table.sort(pending, function(a, b)
            local da, db = It.defs[a.id], It.defs[b.id]
            local sa, sb = da.slot and 0 or 1, db.slot and 0 or 1
            if sa ~= sb then return sa < sb end
            return da.w * da.h > db.w * db.h
        end)
        for _, vi in ipairs(pending) do placeAnywhere(vi) end
    end)
    I.states[ply] = real
    if not ok then return nil, err end

    -- Hotbar keys: as saved where free (job gear keeps its own), weapons
    -- that lost theirs get the first free one (the inventory's own rule).
    local used = {}
    for _, o in pairs(V.byUid) do
        if not o.planned and o.hb then used[o.hb] = true end
    end
    local size = It.HotbarSize(V)
    local lost = {}
    for _, en in ipairs(p.entries) do
        local vi = en.vi
        if vi.hb and (vi.hb > size or used[vi.hb]) then
            vi.hb = nil
            lost[#lost + 1] = vi
        end
        if vi.hb then used[vi.hb] = true end
    end
    for _, vi in ipairs(lost) do I.AutoHotbar(V, vi) end
    return p
end

-- A plan's problems as { ["id:why"] = count } (to see whether something
-- new came up, or more of it, between the check and the confirm).
local function signature(p)
    local set = {}
    for _, pr in ipairs(p.problems) do
        local k = pr.id .. ":" .. pr.why
        set[k] = (set[k] or 0) + pr.n
    end
    return set
end

--------------------------------------------------------------------------
-- Doing it
--------------------------------------------------------------------------

-- execute(ply, p) -> issued { [id] = n }, missed { [id] = n }
local function execute(ply, p)
    local I, It, Int = Inv(), Items(), II()
    local st = I.Get(ply)
    if I.CancelCombine then I.CancelCombine(ply) end

    -- 1. Hand in: grid contents first, then worn gear (a backpack comes
    -- off once it's empty). As at a depot: stock-marked ones go back up.
    table.sort(p.handIn, function(a, b)
        local wa, wb = It.IsWorn(a.c) and 1 or 0, It.IsWorn(b.c) and 1 or 0
        return wa < wb
    end)
    -- (what couldn't be handed in stays, so that much less is issued:
    -- nothing doubles up)
    local stayed = {}
    for _, inst in ipairs(p.handIn) do
        local id, n, data = inst.id, inst.count, inst.data
        local marked = I.StockMarked(data)   -- (before removing: the weapon capture replaces data)
        local ok, removed = pcall(I.Remove, ply, inst.uid)
        if not ok then
            Rhylib.Error("armoury", "Quartermaster hand-in failed for %s: %s", tostring(id), tostring(removed))
        end
        if ok and removed then
            if marked then hook.Run("Rhylib.DepotReturned", ply, id, n, data) end
        elseif st.byUid[inst.uid] == inst then
            stayed[id] = (stayed[id] or 0) + n
        end
    end

    -- Guns the player still holds (a kept job copy of the same gun): the
    -- issued copy shares that weapon, so its fresh state goes into it below.
    local had = {}
    for _, en in ipairs(p.entries) do
        local def = It.defs[en.vi.id]
        if def and def.weapon and had[def.weapon] == nil then had[def.weapon] = ply:HasWeapon(def.weapon) and true or false end
    end

    -- 2. Issue: the planned spot, else wherever it fits. Counted the
    -- moment it's in, so a later error can't hand out anything the stock
    -- doesn't lose.
    local issued, missed, fresh = {}, {}, {}
    local function count(id, n)
        if n > 0 then issued[id] = (issued[id] or 0) + n end
    end
    for _, en in ipairs(p.entries) do
        local vi = en.vi
        local n = vi.count
        local skip = math.min(stayed[vi.id] or 0, n)
        if skip > 0 then
            stayed[vi.id] = stayed[vi.id] - skip
            n = n - skip
        end
        if n > 0 then
            local def = It.defs[vi.id]
            local ok, err = pcall(function()
                local hb = vi.hb
                if hb then
                    for _, o in pairs(st.byUid) do
                        if o.hb == hb then hb = nil break end
                    end
                end
                local worn = It.IsWorn(vi.c)
                if st.cont[vi.c] and It.CanPlace(st, vi.id, vi.c, vi.x, vi.y, vi.rot) and (not worn or It.CanWear(ply, def)) then
                    local inst = { uid = Int.nextUid(st), id = vi.id, count = n, data = table.Copy(vi.data), hb = hb }
                    Int.place(ply, st, inst, vi.c, vi.x, vi.y, vi.rot)
                    count(vi.id, n)
                    -- (one bad weapon can't stop the rest)
                    local okGive, giveErr = pcall(Int.giveWeapon, ply, inst)
                    if not okGive then Rhylib.Error("armoury", "Quartermaster could not give %s: %s", tostring(vi.id), tostring(giveErr)) end
                else
                    local left = I.AddItem(ply, vi.id, n, table.Copy(vi.data))
                    count(vi.id, n - left)
                    if left > 0 then missed[vi.id] = (missed[vi.id] or 0) + left end
                end
            end)
            if not ok then
                Rhylib.Error("armoury", "Quartermaster issue failed for %s: %s", tostring(vi.id), tostring(err))
            end
            if def and def.weapon and had[def.weapon] and issued[vi.id] then fresh[def.weapon] = vi.data end
        end
    end

    -- The gun that was already there gets the fresh, full state.
    for class, data in pairs(fresh) do
        local wep = ply:GetWeapon(class)
        if IsValid(wep) and wep.SetInventoryData then
            local ok, err = pcall(wep.SetInventoryData, wep, table.Copy(data))
            if not ok then Rhylib.Error("armoury", "Quartermaster could not refill %s: %s", class, tostring(err)) end
        end
    end

    -- 3. The stock goes down by what was really issued.
    for id, n in pairs(issued) do
        if p.stocked[id] and n > 0 then hook.Run("Rhylib.DepotTook", ply, id, n) end
    end
    if I.Save then I.Save(ply) end
    return issued, missed
end

--------------------------------------------------------------------------
-- The window's data
--------------------------------------------------------------------------

local CAT_RANK = { weapon = 1, ammo = 2, medical = 3, gear = 4, misc = 5, training = 6 }

local function cooldownLeft(ply)
    return math.max(0, math.ceil((ply.rhylibQMNext or 0) - CurTime()))
end

local function sendState(ply, npc)
    local I, It = Inv(), Items()
    if not (I and It) then return end
    It.EnsureReady()
    local st = I.Get(ply)
    local cat = Q.Catalogue(ply)
    local groups, list, blocked, seenBlock = {}, {}, {}, {}
    for _, inst in pairs(st.byUid) do
        local def = It.defs[inst.id]
        if def then
            local data = inst.data
            local kind, why = Q.KIND_ISSUABLE, nil
            if istable(data) and data.loadout then kind = Q.KIND_JOB
            elseif Q.OwnData(data) then kind, why = Q.KIND_BLOCKED, Q.BLOCK_DATA
            elseif not cat[inst.id] then kind, why = Q.KIND_BLOCKED, Q.BLOCK_FOREIGN end
            local worn = It.IsWorn(inst.c)
            local key = inst.id .. "|" .. kind .. (worn and "|w" or "")
            local g = groups[key]
            if not g then
                g = { id = inst.id, def = def, kind = kind, worn = worn, n = 0, stacks = 0 }
                groups[key] = g
                list[#list + 1] = g
            end
            g.n = g.n + (inst.count or 1)
            g.stacks = g.stacks + 1
            if def.fill then g.fill = istable(data) and data.fill or 1 end
            if why and not seenBlock[inst.id .. why] then
                seenBlock[inst.id .. why] = true
                blocked[#blocked + 1] = { def = def, why = why }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind < b.kind end
        if a.worn ~= b.worn then return not a.worn end
        local ca, cb = CAT_RANK[a.def.category] or 9, CAT_RANK[b.def.category] or 9
        if ca ~= cb then return ca < cb end
        return a.def.name < b.def.name
    end)
    local weight = I.CarryNow and I.CarryNow(ply) or 0

    Rhylib.Net.Start("armoury.qm")
    net.WriteEntity(npc)
    net.WriteUInt(math.Clamp(math.Round(weight * 10), 0, 4095), 12)
    net.WriteUInt(math.min(cooldownLeft(ply), 255), 8)
    net.WriteUInt(math.Clamp(Q.applied[ply] or 0, 0, 3), 2)
    local nc = math.min(#list, 255)
    net.WriteUInt(nc, 8)
    for i = 1, nc do
        local g = list[i]
        net.WriteUInt(It.NetId(g.id), It.NET_BITS)
        net.WriteUInt(math.Clamp(g.n, 0, 255), 8)
        net.WriteUInt(g.kind, 2)
        net.WriteBool(g.worn)
        local pct = 127
        if g.fill and g.stacks == 1 and g.n == 1 and g.fill < 0.995 then pct = math.Clamp(math.floor(g.fill * 100 + 0.5), 0, 100) end
        net.WriteUInt(pct, 7)
    end
    local nb = math.min(#blocked, 63)
    net.WriteUInt(nb, 6)
    for i = 1, nb do
        net.WriteUInt(It.NetId(blocked[i].def.id), It.NET_BITS)
        net.WriteUInt(blocked[i].why, 2)
    end
    for n = 1, Q.SLOTS do
        local s = slotOf(ply, n)
        net.WriteBool(s ~= nil)
        if s then
            net.WriteString(isstring(s.name) and s.name ~= "" and s.name or Q.DefaultName(n))
            net.WriteUInt(math.Clamp(os.time() - (tonumber(s.t) or os.time()), 0, 4294967295), 32)
            net.WriteUInt(math.Clamp(math.Round((tonumber(s.kg) or 0) * 10), 0, 4095), 12)
            -- (kinds: one line per item, counts added up)
            local kinds, byId = {}, {}
            for _, r in ipairs(s.rows) do
                if rowOk(r) and It.defs[r[1]] then
                    local k = byId[r[1]]
                    if not k then
                        k = { id = r[1], n = 0, worn = false }
                        byId[r[1]] = k
                        kinds[#kinds + 1] = k
                    end
                    k.n = k.n + math.max(1, math.floor(r[6]))
                    if It.IsWorn(r[2]) then k.worn = true end
                end
            end
            local nk = math.min(#kinds, 127)
            net.WriteUInt(nk, 7)
            for i = 1, nk do
                local k = kinds[i]
                net.WriteUInt(It.NetId(k.id), It.NET_BITS)
                net.WriteUInt(math.Clamp(k.n, 0, 255), 8)
                net.WriteBool(k.worn)
                local mark = 0
                local left = stockLeft(k.id)
                if left then
                    local mx = stockMax(k.id)
                    if left <= 0 then mark = 3
                    elseif left < k.n then mark = 2
                    elseif mx and left < mx * 0.6 then mark = 1 end
                end
                net.WriteUInt(mark, 2)
            end
        end
    end
    net.Send(ply)
end
Q.SendState = sendState

local function sendProblems(ply, npc, slot, p, again)
    local It = Items()
    Rhylib.Net.Start("armoury.qmprob")
    net.WriteEntity(npc)
    net.WriteUInt(slot, 2)
    net.WriteBool(#p.entries == 0)
    net.WriteBool(again and true or false)
    local n = math.min(#p.problems, 127)
    net.WriteUInt(n, 7)
    for i = 1, n do
        local pr = p.problems[i]
        local nid = It.defs[pr.id] and It.NetId(pr.id) or 0
        net.WriteUInt(nid, It.NET_BITS)
        if nid == 0 then net.WriteString(string.sub(pr.id, 1, 60)) end
        net.WriteUInt(math.Clamp(pr.n, 0, 255), 8)
        net.WriteUInt(pr.why, 3)
        net.WriteString(string.sub(pr.text or "", 1, 160))
    end
    net.Send(ply)
end

--------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------

local function blockedText(blocked)
    local names, seen = {}, {}
    for _, b in ipairs(blocked) do
        local def = Items().defs[b.inst.id]
        local nm = def and def.name or b.inst.id
        if not seen[nm] then
            seen[nm] = true
            names[#names + 1] = nm
        end
    end
    return table.concat(names, ", ")
end

-- Q.SaveKit(ply, slot, quiet) -> true when saved.
function Q.SaveKit(ply, slot, quiet)
    local I, It = Inv(), Items()
    local st = I.Get(ply)
    local _, handIn, blocked = classify(st, Q.Catalogue(ply))
    local rows, kg = {}, 0
    for _, inst in ipairs(handIn) do
        local def = It.defs[inst.id]
        if def and #rows < Q.MAX_ROWS then
            local n = math.max(1, math.floor(inst.count or 1))
            rows[#rows + 1] = { inst.id, inst.c or It.MAIN, inst.x or 0, inst.y or 0, inst.rot and 1 or 0, n, inst.hb or 0 }
            kg = kg + (def.weight or 0) * n
        end
    end
    if #rows == 0 then
        if not quiet then note(ply, "Nothing to save: you carry nothing the armouries issue (job gear isn't saved)", "bad") end
        return false
    end
    local t = savedOf(ply)
    if not t then return false end
    local old = t["s" .. slot]
    local name = istable(old) and isstring(old.name) and old.name ~= "" and old.name or Q.DefaultName(slot)
    t["s" .. slot] = { name = name, t = os.time(), kg = math.Round(kg, 1), rows = rows }
    store(ply)
    if Q.applied[ply] == slot then Q.applied[ply] = nil end
    if not quiet then
        if #blocked > 0 then
            note(ply, "Saved " .. slotTitle(slot, t["s" .. slot]) .. ". Left out what he can't take in: " .. blockedText(blocked), "good")
        else
            note(ply, "Saved " .. slotTitle(slot, t["s" .. slot]), "good")
        end
    end
    return true
end

local function check(ply, npc, slot, again)
    local s = slotOf(ply, slot)
    if not s then
        note(ply, "Nothing is saved in that slot", "bad")
        return sendState(ply, npc)
    end
    local cd = cooldownLeft(ply)
    if cd > 0 then
        note(ply, "One swap at a time: ready again in " .. cd .. " s", "bad")
        return sendState(ply, npc)
    end
    local p, err = plan(ply, npc, s.rows)
    if not p then
        Rhylib.Error("armoury", "Quartermaster plan failed: %s", tostring(err))
        note(ply, "Something went wrong: your kit wasn't changed", "bad")
        return sendState(ply, npc)
    end
    if #p.blocked > 0 then
        note(ply, "He can't take these in, so he won't swap your kit: " .. blockedText(p.blocked), "bad")
        return sendState(ply, npc)
    end
    ply.rhylibQMCheck = { slot = slot, sig = signature(p), at = CurTime() }
    sendProblems(ply, npc, slot, p, again)
end

local function apply(ply, npc, slot, option)
    local chk = ply.rhylibQMCheck
    -- (the client confirms what it was shown: no recent check, check first)
    if not chk or chk.slot ~= slot or CurTime() - chk.at > 120 then return check(ply, npc, slot) end
    local s = slotOf(ply, slot)
    if not s then
        note(ply, "Nothing is saved in that slot", "bad")
        return sendState(ply, npc)
    end
    local cd = cooldownLeft(ply)
    if cd > 0 then
        note(ply, "One swap at a time: ready again in " .. cd .. " s", "bad")
        return sendState(ply, npc)
    end
    local p, err = plan(ply, npc, s.rows)
    if not p then
        Rhylib.Error("armoury", "Quartermaster plan failed: %s", tostring(err))
        note(ply, "Something went wrong: your kit wasn't changed", "bad")
        return sendState(ply, npc)
    end
    if #p.blocked > 0 then
        note(ply, "He can't take these in, so he won't swap your kit: " .. blockedText(p.blocked), "bad")
        return sendState(ply, npc)
    end
    -- Something new in the way since the check (stock ran out, a skill
    -- went): show the list again instead.
    local sig = signature(p)
    local changed = option == Q.APPLY_PLAIN and next(sig) ~= nil
    for k, n in pairs(sig) do
        if not chk.sig[k] or n > chk.sig[k] then changed = true break end
    end
    if changed or #p.entries == 0 then
        ply.rhylibQMCheck = { slot = slot, sig = sig, at = CurTime() }
        return sendProblems(ply, npc, slot, p, true)
    end
    ply.rhylibQMCheck = nil
    -- (a handout at the counter first: the plan is made again when it ends)
    if cfg("qmIssueTime") > 0 then return Q.StartHand(ply, npc, slot, option, s, sig, p) end
    Q.ApplyNow(ply, npc, slot, option, p, s)
end

-- Q.ApplyNow(ply, npc, slot, option, plan, s): hand in, issue, the
-- cooldown, the notice and the window. The checks are done.
function Q.ApplyNow(ply, npc, slot, option, p, s)
    ply.rhylibQMNext = CurTime() + math.max(0, cfg("qmCooldown"))
    local _, missed = execute(ply, p)
    Q.applied[ply] = slot
    if option == Q.APPLY_AND_SAVE then Q.SaveKit(ply, slot, true) end

    -- What didn't come with it.
    local It = Items()
    local out, seen = {}, {}
    local function add(id, n)
        if n <= 0 then return end
        local def = It.defs[id]
        local k = def and def.name or id
        seen[k] = (seen[k] or 0) + n
        if seen[k] == n then out[#out + 1] = k end
    end
    for _, pr in ipairs(p.problems) do add(pr.id, pr.n) end
    for id, n in pairs(missed) do add(id, n) end
    local title = slotTitle(slot, slotOf(ply, slot) or s)
    if #out == 0 then
        note(ply, title .. ": issued, full and fresh", "good")
    else
        for i, k in ipairs(out) do if seen[k] > 1 then out[i] = k .. " x" .. seen[k] end end
        note(ply, title .. ": issued without " .. table.concat(out, ", "), "info")
    end
    sendState(ply, npc)
end

-- (the gate every request passes)
local function canUse(ply, npc, quiet)
    if not (IsValid(npc) and npc:GetClass() == Q.CLASS) then return false end
    if not (IsValid(ply) and ply:Alive()) then return false end
    local r = cfg("qmRange")
    if ply:GetPos():DistToSqr(npc:GetPos()) > r * r then
        if not quiet then note(ply, "Stand closer to the quartermaster", "bad") end
        return false
    end
    local St = Rhylib.State
    if St and ((St.IsDown and St.IsDown(ply)) or (St.IsCuffed and St.IsCuffed(ply)) or (St.CanAct and not St.CanAct(ply))) then
        if not quiet then note(ply, "You can't do that right now", "bad") end
        return false
    end
    local I = Inv()
    if not (I and I.Get and II() and II().findSpot) then
        if not quiet then note(ply, "Needs Rhy's Inventory", "bad") end
        return false
    end
    if I.Locked and I.Locked(ply) then
        if not quiet then note(ply, "You can't use your kit right now", "bad") end
        return false
    end
    return true
end

-- Q.Use(ply, npc): E on the quartermaster (ENT:Use).
function Q.Use(ply, npc)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if (ply.rhylibQMUse or 0) > CurTime() then return end   -- (one press at a time)
    ply.rhylibQMUse = CurTime() + 0.5
    if not canUse(ply, npc) then return end
    local h = Q.hands[ply]
    if h and h.npc ~= npc then
        return note(ply, "You're being handed a loadout at another quartermaster: finish or stop that first", "bad")
    end
    Q.viewers[ply] = npc
    sendState(ply, npc)
    if h and Q.ResendHand then Q.ResendHand(ply) end   -- (a handout still running)
end

--------------------------------------------------------------------------
-- The handout: applying takes qmIssueTime seconds at the counter
--------------------------------------------------------------------------

Rhylib.Net.Register("armoury.qmhand")
Q.hands = Q.hands or {}   -- [ply] = { npc, slot, option, rows, slotRef, t, sig, start, dur }

local function handTimer(ply) return "Rhylib.Armoury.QMHand." .. ply:EntIndex() end

-- (net armoury.qmhand: npc Entity, running Bool; running: slot UInt 2,
-- duration Float, seconds left Float, backpack Bool)
local function sendHand(ply, npc, h)
    Rhylib.Net.Start("armoury.qmhand")
    net.WriteEntity(IsValid(npc) and npc or NULL)
    net.WriteBool(h ~= nil)
    if h then
        net.WriteUInt(h.slot, 2)
        net.WriteFloat(h.dur)
        net.WriteFloat(math.max(0, h.start + h.dur - CurTime()))
        net.WriteBool(h.backpack and true or false)
    end
    net.Send(ply)
end

-- Q.StopHand(ply, why): stops a running handout; nothing changes (no
-- cooldown either: nothing was handed in or out). why: the notice.
function Q.StopHand(ply, why)
    local h = Q.hands[ply]
    if not h then return end
    Q.hands[ply] = nil
    if not IsValid(ply) then return end
    timer.Remove(handTimer(ply))
    if why then note(ply, why .. ": you keep your current kit", "bad") end
    sendHand(ply, h.npc, nil)
end

-- Q.StartHand(ply, npc, slot, option, s, sig, plan): the checks passed;
-- the swap happens when the time is up (Q.FinishHand). The slot's rows
-- are copied now: a slot changed meanwhile stops it.
function Q.StartHand(ply, npc, slot, option, s, sig, p)
    if Q.hands[ply] then return end
    local It = Items()
    local backpack = false
    for _, en in ipairs(p.entries) do
        local def = It.defs[en.vi.id]
        if def and def.grid and It.IsWorn(en.vi.c) then backpack = true break end
    end
    local h = { npc = npc, slot = slot, option = option, rows = table.Copy(s.rows), slotRef = s, t = s.t, sig = sig,
        start = CurTime(), dur = math.Clamp(cfg("qmIssueTime"), 0, 30), backpack = backpack, life = ply.rhylibQMLife or 0 }
    Q.hands[ply] = h
    timer.Create(handTimer(ply), h.dur, 1, function()
        if IsValid(ply) then Q.FinishHand(ply) end
    end)
    sendHand(ply, npc, h)
end

function Q.ResendHand(ply)
    local h = Q.hands[ply]
    if h then sendHand(ply, h.npc, h) end
end

-- Why a running handout has to stop now, or nil.
local function handBroken(ply, h)
    if not IsValid(h.npc) then return "The quartermaster is gone" end
    if not ply:Alive() or (ply.rhylibQMLife or 0) ~= h.life then return "You died" end
    local r = cfg("qmRange") + 30
    if ply:GetPos():DistToSqr(h.npc:GetPos()) > r * r then return "You walked away from the counter" end
    local St = Rhylib.State
    if St and ((St.IsDown and St.IsDown(ply)) or (St.IsCuffed and St.IsCuffed(ply)) or (St.CanAct and not St.CanAct(ply))) then return "You can't take it now" end
    local I = Inv()
    if I and I.Locked and I.Locked(ply) then return "You can't take it now" end
    return nil
end

-- Q.FinishHand(ply): the time is up: everything is planned and checked
-- again (as a confirm is), then applied at once.
function Q.FinishHand(ply)
    local h = Q.hands[ply]
    if not h then return end
    Q.hands[ply] = nil
    timer.Remove(handTimer(ply))
    local npc = h.npc
    local why = handBroken(ply, h)
    if why then
        note(ply, why .. ": you keep your current kit", "bad")
        return sendHand(ply, npc, nil)
    end
    sendHand(ply, npc, nil)
    local s = slotOf(ply, h.slot)
    if s ~= h.slotRef or s.t ~= h.t then
        note(ply, "That loadout changed meanwhile: you keep your current kit", "bad")
        return sendState(ply, npc)
    end
    local p, err = plan(ply, npc, h.rows)
    if not p then
        Rhylib.Error("armoury", "Quartermaster plan failed: %s", tostring(err))
        note(ply, "Something went wrong: your kit wasn't changed", "bad")
        return sendState(ply, npc)
    end
    if #p.blocked > 0 then
        note(ply, "He can't take these in, so he won't swap your kit: " .. blockedText(p.blocked), "bad")
        return sendState(ply, npc)
    end
    local sig = signature(p)
    local changed = h.option == Q.APPLY_PLAIN and next(sig) ~= nil
    for k, n in pairs(sig) do
        if not h.sig[k] or n > h.sig[k] then changed = true break end
    end
    if changed or #p.entries == 0 then
        ply.rhylibQMCheck = { slot = h.slot, sig = sig, at = CurTime() }
        return sendProblems(ply, npc, h.slot, p, true)
    end
    Q.ApplyNow(ply, npc, h.slot, h.option, p, s)
end

--------------------------------------------------------------------------
-- The loadout editor (setting qmEditor)
--------------------------------------------------------------------------

Rhylib.Net.Register("armoury.qmcat")
Rhylib.Net.Register("armoury.qmeditres")

local WEAPON_GROUPS = { rifle = true, carbine = true, pistol = true, heavy = true, shotgun = true, sniper = true, weapon = true }
local function tabOf(id, def, sh)
    if sh.roleOnly[id] then return 6 end
    local g = Items().GroupOf(def)
    if WEAPON_GROUPS[g] then return 1 end
    if g == "ammo" then return 2 end
    if g == "grenade" then return 3 end
    if g == "medical" or def.category == "medical" then return 5 end
    return 4
end

-- (one row on the wire: item NET_BITS, container UInt 5, x UInt 5, y UInt 5,
-- rot Bool, count UInt 8, hotbar UInt 3)
local function writeRow(It, id, c, x, y, rot, n, hb)
    net.WriteUInt(It.NetId(id), It.NET_BITS)
    net.WriteUInt(math.Clamp(c, 0, 31), 5)
    net.WriteUInt(math.Clamp(x, 0, 31), 5)
    net.WriteUInt(math.Clamp(y, 0, 31), 5)
    net.WriteBool(rot)
    net.WriteUInt(math.Clamp(n, 1, 255), 8)
    net.WriteUInt(math.Clamp(hb or 0, 0, 7), 3)
end

local function writeRows(It, rows)
    local list = {}
    for _, r in ipairs(rows) do
        if rowOk(r) and It.defs[r[1]] then list[#list + 1] = r end
        if #list >= 127 then break end
    end
    net.WriteUInt(#list, 7)
    for _, r in ipairs(list) do writeRow(It, r[1], r[2], r[3], r[4], r[5] == 1, r[6], tonumber(r[7]) or 0) end
end

-- The editor's empty copy of the inventory: the player's grids, with
-- their job gear (data.loadout) in place, so a job backpack's grid and
-- hotbar keys are there and the loadout is built around it, as applying
-- fits it around it.
local function editorCopy(ply, st)
    local job = {}
    for _, inst in pairs(st.byUid) do
        if istable(inst.data) and inst.data.loadout then job[#job + 1] = inst end
    end
    return buildVirtual(ply, st, job)
end

-- Net armoury.qmcat (server -> player): what the editor needs. npc
-- Entity, slot UInt 2, name String, backpack rows factor in tenths
-- UInt 7, the empty inventory's grids UInt 5 x (container UInt 5, w UInt 5,
-- h UInt 5), the distinct lock reasons UInt 7 x String, shelves UInt 9 x
-- (item NET_BITS, tab UInt 3, stock UInt 11 (2047 no limit), carry limit
-- UInt 2 (one-only items), reason UInt 7 (0 = may take, else its index)),
-- then rows: the job gear in place, the slot's rows, what you carry that
-- he takes in.
function Q.SendCatalogue(ply, npc, slot)
    local I, It = Inv(), Items()
    It.EnsureReady()
    local st = I.Get(ply)
    local cat = Q.Catalogue(ply)
    local offered = Q.Offered(ply)
    local depot = stand_in_depot(npc)
    local back = returnable()
    local sh = sharedLists()
    local shelves = {}
    for id in pairs(cat) do
        local def = It.defs[id]
        shelves[#shelves + 1] = { id = id, def = def, tab = tabOf(id, def, sh) }
    end
    table.sort(shelves, function(a, b)
        if a.tab ~= b.tab then return a.tab < b.tab end
        local ga, gb = It.GroupRank(It.GroupOf(a.def)), It.GroupRank(It.GroupOf(b.def))
        if ga ~= gb then return ga < gb end
        return a.def.name < b.def.name
    end)
    local V = editorCopy(ply, st)
    local grids = {}
    for cid, c in pairs(V.cont) do
        if cid ~= PENDING then grids[#grids + 1] = { cid = cid, w = c.w, h = c.h } end
    end
    local fixed = {}
    for _, o in pairs(V.byUid) do
        fixed[#fixed + 1] = { o.id, o.c, o.x or 0, o.y or 0, o.rot and 1 or 0, math.max(1, math.floor(o.count or 1)), o.hb or 0 }
    end
    -- (each reason once; shelves point at it)
    local reasons, reasonAt = {}, {}
    local n = math.min(#shelves, 511)
    for i = 1, n do
        local why = Q.RuleCheck(ply, shelves[i].id, cat, offered, depot, back)
        if why then
            why = string.sub(why, 1, 120)
            if not reasonAt[why] and #reasons < 127 then
                reasons[#reasons + 1] = why
                reasonAt[why] = #reasons
            end
            shelves[i].why = reasonAt[why] or #reasons
        end
    end
    local s = slotOf(ply, slot)
    local _, handIn = classify(st, cat)
    local carry = {}
    for _, inst in ipairs(handIn) do
        carry[#carry + 1] = { inst.id, inst.c or It.MAIN, inst.x or 0, inst.y or 0, inst.rot and 1 or 0, math.max(1, math.floor(inst.count or 1)), inst.hb or 0 }
    end

    Rhylib.Net.Start("armoury.qmcat")
    net.WriteEntity(npc)
    net.WriteUInt(slot, 2)
    net.WriteString(s and isstring(s.name) and s.name or Q.DefaultName(slot))
    net.WriteUInt(math.Clamp(math.Round(packMult(ply) * 10), 1, 127), 7)
    net.WriteUInt(math.min(#grids, 31), 5)
    for i = 1, math.min(#grids, 31) do
        net.WriteUInt(grids[i].cid, 5)
        net.WriteUInt(math.Clamp(grids[i].w, 0, 31), 5)
        net.WriteUInt(math.Clamp(grids[i].h, 0, 31), 5)
    end
    net.WriteUInt(#reasons, 7)
    for _, r in ipairs(reasons) do net.WriteString(r) end
    net.WriteUInt(n, 9)
    for i = 1, n do
        local sh1 = shelves[i]
        net.WriteUInt(It.NetId(sh1.id), It.NET_BITS)
        net.WriteUInt(sh1.tab, 3)
        local left = stockLeft(sh1.id)
        net.WriteUInt(left and math.Clamp(left, 0, Q.NO_LIMIT - 1) or Q.NO_LIMIT, 11)
        net.WriteUInt(It.Unique(sh1.def) and math.Clamp(I.Limit(ply, sh1.id), 1, 3) or 0, 2)
        net.WriteUInt(sh1.why or 0, 7)
    end
    writeRows(It, fixed)
    writeRows(It, s and s.rows or {})
    writeRows(It, carry)
    net.Send(ply)
end

-- Q.ValidateRows(ply, npc, rows) -> nil, kg when the loadout is fine,
-- else the reason. rows: { { id, container, x, y, rot (bool), count,
-- hotbar } }. Every row is checked against the player now (Q.RuleCheck,
-- stack size, one-only limits) and placed on an empty copy of their
-- inventory with the inventory's own rules (worn gear first, its grids
-- appear with it); the total weight must stay within the ceiling.
function Q.ValidateRows(ply, npc, rows)
    local I, It = Inv(), Items()
    It.EnsureReady()
    if #rows == 0 then return "The loadout is empty" end
    if #rows > Q.MAX_ROWS then return "Too many items (at most " .. Q.MAX_ROWS .. ")" end
    local st = I.Get(ply)
    local cat, offered = Q.Catalogue(ply), Q.Offered(ply)
    local depot, back = stand_in_depot(npc), returnable()
    local V = editorCopy(ply, st)
    local list = {}
    for i, r in ipairs(rows) do list[#list + 1] = { i = i, r = r } end
    table.sort(list, function(a, b)
        local wa, wb = It.IsWorn(a.r[2]) and 0 or 1, It.IsWorn(b.r[2]) and 0 or 1
        if wa ~= wb then return wa < wb end
        return a.i < b.i
    end)
    local real = I.states[ply]
    I.states[ply] = V
    local ok, res, kg = pcall(function()
        local hbUsed = {}
        for _, o in pairs(V.byUid) do
            if o.hb then hbUsed[o.hb] = true end   -- (the job gear's own keys)
        end
        for _, e in ipairs(list) do
            local id, c, x, y, rot, n, hb = e.r[1], e.r[2], e.r[3], e.r[4], e.r[5], e.r[6], e.r[7]
            local def = It.defs[id]
            if not def then return "An item that doesn't exist" end
            local why = Q.RuleCheck(ply, id, cat, offered, depot, back)
            if why then return def.name .. ": " .. why end
            if c == It.EXT or c == PENDING or not V.cont[c] then return def.name .. ": that place doesn't exist" end
            local cap = It.Unique(def) and 1 or It.StackFor(def, ply)
            if n < 1 or n > cap then return def.name .. ": at most " .. cap .. " in one stack" end
            -- (the job gear counts: Inv.Count reads the copy)
            if It.Unique(def) and I.Count(ply, id) >= I.Limit(ply, id) then return def.name .. ": " .. I.LimitText(ply, id) end
            if It.IsWorn(c) then
                local okWear, wearWhy = It.CanWear(ply, def)
                if not okWear then return def.name .. ": " .. (wearWhy or "you can't wear that") end
            end
            if not It.CanPlace(V, id, c, x, y, rot) then return def.name .. " doesn't fit there" end
            vPlace(V, ply, { uid = vUid(V), id = id, count = n, data = {} }, c, x, y, rot)
            if hb > 0 then
                if hbUsed[hb] then return "Hotbar key " .. hb .. " is taken" end
                hbUsed[hb] = true
            end
        end
        local size = It.HotbarSize(V)
        for k in pairs(hbUsed) do
            if k > size then return "Hotbar key " .. k .. " needs a backpack" end
        end
        local w, capKg = I.CarryNow(ply)
        local lim = Rhylib.Config.Get("inventory", "weightCeiling")
        if lim > 0 and w > capKg * lim + 1e-6 then
            return string.format("Too heavy: %.1f kg, you can carry %.1f kg", w, capKg * lim)
        end
        return nil, w
    end)
    I.states[ply] = real
    if not ok then
        Rhylib.Error("armoury", "Quartermaster editor check failed: %s", tostring(res))
        return "Something went wrong checking it"
    end
    return res, kg
end

local function editResult(ply, okSave, text)
    Rhylib.Net.Start("armoury.qmeditres")
    net.WriteBool(okSave)
    net.WriteString(text or "")
    net.Send(ply)
end

-- Q.EditorSave(ply, npc, slot, name, rows): checks and stores an edited
-- loadout (or answers why not).
function Q.EditorSave(ply, npc, slot, name, rows)
    local why, kg = Q.ValidateRows(ply, npc, rows)
    if why then return editResult(ply, false, why) end
    local t = savedOf(ply)
    if not t then return editResult(ply, false, "Something went wrong") end
    local clean = Q.CleanName(name)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { r[1], r[2], r[3], r[4], r[5] and 1 or 0, r[6], r[7] } end
    t["s" .. slot] = { name = clean ~= "" and clean or Q.DefaultName(slot), t = os.time(), kg = math.Round(kg or 0, 1), rows = out }
    store(ply)
    if Q.applied[ply] == slot then Q.applied[ply] = nil end
    editResult(ply, true, "")
    note(ply, "Saved " .. slotTitle(slot, t["s" .. slot]), "good")
    sendState(ply, npc)
end

--------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------

-- (an editor save's rows; nil when the message is malformed)
local function readEditRows()
    local It = Items()
    local n = net.ReadUInt(7)
    local rows = {}
    for _ = 1, n do
        local def = It.FromNet(net.ReadUInt(It.NET_BITS))
        local c, x, y = net.ReadUInt(5), net.ReadUInt(5), net.ReadUInt(5)
        local rot = net.ReadBool()
        local cnt, hb = net.ReadUInt(8), net.ReadUInt(3)
        if not def then return nil end
        rows[#rows + 1] = { def.id, c, x, y, rot, cnt, hb }
    end
    return rows
end

Rhylib.Net.Receive("armoury.qmact", function(ply, len)
    local npc = net.ReadEntity()
    local op = net.ReadUInt(3)
    local slot = net.ReadUInt(2)
    if op == Q.OP_CLOSE then
        Q.viewers[ply] = nil
        ply.rhylibQMCheck = nil
        Q.StopHand(ply, "You closed the window")
        return
    end
    if op == Q.OP_STOP then
        Q.StopHand(ply, "Stopped")
        return
    end
    local option = op == Q.OP_APPLY and net.ReadUInt(2) or nil
    local name = op == Q.OP_RENAME and net.ReadString() or nil
    local sub, rows
    if op == Q.OP_EDITOR then
        sub = net.ReadUInt(1)
        if sub == 1 then
            if (len or 0) > 16384 then   -- (the most a full loadout needs, with room to spare)
                return editResult(ply, false, "Too many items (at most " .. Q.MAX_ROWS .. ")")
            end
            name = net.ReadString()
            rows = readEditRows()
        end
    end
    if slot < 1 or slot > Q.SLOTS then return end
    if not canUse(ply, npc) then return end
    Q.viewers[ply] = npc
    -- (one thing at a time: nothing else while a handout runs)
    if Q.hands[ply] then return note(ply, "Wait for the handout to finish (or stop it)", "bad") end
    if op == Q.OP_CHECK then
        check(ply, npc, slot)
    elseif op == Q.OP_APPLY then
        apply(ply, npc, slot, option)
    elseif op == Q.OP_SAVE then
        Q.SaveKit(ply, slot)
        sendState(ply, npc)
    elseif op == Q.OP_RENAME then
        local s = slotOf(ply, slot)
        if not s then return end
        local clean = Q.CleanName(name)
        s.name = clean ~= "" and clean or Q.DefaultName(slot)
        store(ply)
        sendState(ply, npc)
    elseif op == Q.OP_CLEAR then
        local t = savedOf(ply)
        if not (t and t["s" .. slot]) then return end
        t["s" .. slot] = nil
        store(ply)
        if Q.applied[ply] == slot then Q.applied[ply] = nil end
        note(ply, "Loadout " .. slot .. " cleared", "info")
        sendState(ply, npc)
    elseif op == Q.OP_EDITOR then
        if not cfg("qmEditor") then return note(ply, "The loadout editor is off on this server", "bad") end
        if sub == 0 then
            -- (building the catalogue isn't cheap: once every 1.5 s)
            if (ply.rhylibQMCat or 0) > CurTime() then return end
            ply.rhylibQMCat = CurTime() + 1.5
            Q.SendCatalogue(ply, npc, slot)
        elseif not rows then
            editResult(ply, false, "An item that doesn't exist")
        else
            Q.EditorSave(ply, npc, slot, name or "", rows)
        end
    end
end, { rate = 4, burst = 6 })

-- An open window follows changes to what you carry (at most twice a
-- second); walking away forgets it.
Rhylib.Hook.Add("Rhylib.InventoryChanged", "armoury.qm", function(ply)
    if Q.viewers[ply] then ply.rhylibQMDirty = true end
end)

-- Q.Tick(): runs twice a second (handouts that have to stop, windows to
-- refresh or forget).
function Q.Tick()
    for ply, h in pairs(Q.hands) do
        if not IsValid(ply) then
            Q.hands[ply] = nil
        else
            local why = handBroken(ply, h)
            if why then Q.StopHand(ply, why) end
        end
    end
    if next(Q.viewers) == nil then return end
    for ply, npc in pairs(Q.viewers) do
        local r = cfg("qmRange") + 100
        if not (IsValid(ply) and IsValid(npc) and ply:Alive()) or ply:GetPos():DistToSqr(npc:GetPos()) > r * r then
            Q.viewers[ply] = nil
            if IsValid(ply) then ply.rhylibQMDirty, ply.rhylibQMCheck = nil, nil end
        elseif ply.rhylibQMDirty and not Q.hands[ply] then
            ply.rhylibQMDirty = nil
            sendState(ply, npc)
        end
    end
end
timer.Create("Rhylib.Armoury.QM", 0.5, 0, function() Q.Tick() end)

-- (a death stops a handout at once; the life count catches a respawn
-- between two checks)
Rhylib.Hook.Add("PlayerDeath", "armoury.qm", function(ply)
    ply.rhylibQMLife = (ply.rhylibQMLife or 0) + 1
    if Q.hands[ply] then Q.StopHand(ply, "You died") end
end)
Rhylib.Hook.Add("PlayerSpawn", "armoury.qm", function(ply)
    ply.rhylibQMLife = (ply.rhylibQMLife or 0) + 1
end)

Rhylib.Hook.Add("PlayerDisconnected", "armoury.qm", function(ply)
    Q.hands[ply] = nil
    timer.Remove(handTimer(ply))
    Q.viewers[ply] = nil
    Q.applied[ply] = nil
    local sid = ply:SteamID64()
    if sid then Q.cache[sid] = nil end
end)

-- A reset character (rhylib_roster's !charreset) has no loadouts.
Rhylib.Hook.Add("Rhylib.CharacterReset", "armoury.qm", function(sid, ply)
    if not sid or sid == "" then return end
    Q.cache[sid] = nil
    Rhylib.Data.Delete(DATA, dataKey(sid))
    if IsValid(ply) then Q.applied[ply] = nil end
end)

-- Quartermasters stay where they're placed once made permanent (the
-- toolgun's Permanent tool; Data "armoury_qm_places" / map).
if Rhylib.Perma and Rhylib.Perma.Placements then
    Q.places = Rhylib.Perma.Placements("armoury_qm", {
        classes = { Q.CLASS },
        dataModule = "armoury_qm_places",
        command = "rhylib_quartermaster_save",
        perm = "rhylib.armoury.admin",
    })
end
