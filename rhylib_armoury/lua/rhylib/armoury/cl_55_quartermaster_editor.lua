--[[
    Quartermaster loadout editor (client; server setting armoury qmEditor).
    "Edit" on a filled slot card or "Create loadout" on an empty one asks
    for net armoury.qmcat (sv_50_quartermaster.lua) and this opens.

    Layout (Editor board): a header with EDIT LOADOUT n, the name box and
    Start from what I carry / Empty it / Cancel / Save loadout. Left: the
    armoury catalogue in tabs (Weapons, Ammo, Grenades, Equipment, Medical,
    Specialist; only tabs with items), one shelf per item with its kind,
    stock badge (N left / OUT / No limit), picture, name and size; shelves
    you may not draw now are faded with the reason and can't be dragged.
    Right: a virtual inventory with the real rules (Rhylib.Items
    CanPlace / ContainerAllows / CanWear): the weight bar against your
    carry cap (amber mark where you slow down), the worn slots row, the
    pockets and every grid your worn gear adds (sizes as the server sent,
    a backpack's rows times your Load bearer factor), the hotbar keys, and
    your job gear in place (dim, fixed: the loadout is built around it,
    as applying fits it around it).

    Drag a shelf into a grid or slot (R turns it while dragging), drag
    items around, drag one out of the inventory to remove it (a backpack
    only once it's empty), drop onto a matching stack to add to it, drag
    onto a hotbar key (right-click a key empties it), right-click a shelf
    to add a stack wherever it fits. Nothing is taken from stock. Save
    sends the rows (op editor, save); the server checks everything again
    and answers with net armoury.qmeditres (saved, or why not).
    Esc closes the editor first (UI closer "armoury.qmeditor").
]]

local A = Rhylib.Armoury
A.QM = A.QM or {}
local Q = A.QM
local UI = Rhylib.UI

-- (Q.editor: the open editor { frame, npc, slot, V, shelves, drag, ... })

local C_SHELF, C_TILE_EDGE, C_CELL, C_CELL_EDGE = Color(26, 30, 27), Color(47, 51, 46), Color(14, 16, 15), Color(31, 35, 32)
local C_LOCK, C_FAINT, C_BAD_DROP = Color(200, 176, 122), Color(92, 97, 91), Color(226, 75, 74, 40)
local C_OK_DROP, C_TAB_ON, C_TAB_TEXT = Color(133, 183, 235, 30), Color(228, 227, 220), Color(201, 200, 192)
local C_DARK = Color(20, 20, 19)

local GRID_TITLES = {}
local function gridTitle(cid)
    local It = Rhylib.Items
    if GRID_TITLES[cid] then return GRID_TITLES[cid] end
    local t = ({ [It.MAIN] = "POCKETS", [It.BACK] = "BACKPACK", [It.GUNBELT] = "GUN BELT", [It.HOLSTER] = "HOLSTER",
        [It.POUCH] = "BELT POUCHES", [It.CELLPACK] = "CELL POUCH", [It.CELLBELT] = "BELT CELL POUCH", [It.BELT] = "AMMO BELT",
        [It.RACK] = "CELL RACK" })[cid] or ("GRID " .. cid)
    GRID_TITLES[cid] = t
    return t
end
local GRID_ORDER   -- (filled on first use: Rhylib.Items is there by then)
local function gridOrder()
    if GRID_ORDER then return GRID_ORDER end
    local It = Rhylib.Items
    GRID_ORDER = { It.MAIN, It.BACK, It.GUNBELT, It.HOLSTER, It.POUCH, It.BELT, It.CELLPACK, It.CELLBELT, It.RACK }
    return GRID_ORDER
end

local function H() return Q.UIH end
local function S(n) return Q.UIH.S(n) end
local function F(a, b) return Q.UIH.F(a, b) end

--------------------------------------------------------------------------
-- Cached strings (no text built while painting)
--------------------------------------------------------------------------

local countText = {}
local function countOf(n)
    local t = countText[n]
    if not t then t = "x" .. n countText[n] = t end
    return t
end
local fitCache = setmetatable({}, { __mode = "k" })
-- (by item, font and width: plain table lookups, nothing built per frame)
local function fitName(def, font, w)
    w = math.floor(w)
    local byDef = fitCache[def]
    if not byDef then byDef = {} fitCache[def] = byDef end
    local byFont = byDef[font]
    if not byFont then byFont = {} byDef[font] = byFont end
    local t = byFont[w]
    if not t then t = H().K().Fit(def.name or "?", font, w) byFont[w] = t end
    return t
end

--------------------------------------------------------------------------
-- The virtual inventory
--------------------------------------------------------------------------

local function gridsOf(def)
    local It = Rhylib.Items
    local out = {}
    if def.grid then out[#out + 1] = def.gridCid or It.BACK end
    for _, eg in ipairs(def.extraGrids or {}) do out[#out + 1] = eg.cid end
    return out
end

local vPlace   -- (below)

-- A fresh copy: the grids the server sent, with the job gear in its place
-- (fixed: shown dim, can't be moved or saved; the loadout fits around it).
local function vNew(E)
    local It = Rhylib.Items
    local V = { cont = {}, byUid = {}, nextUid = 1 }
    for _, g in ipairs(E.base) do V.cont[g.cid] = { w = g.w, h = g.h, items = {} } end
    E.V = V
    local list = {}
    for _, r in ipairs(E.fixedRows or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b) return (It.IsWorn(a.c) and 0 or 1) < (It.IsWorn(b.c) and 0 or 1) end)
    for _, r in ipairs(list) do
        if r.def and V.cont[r.c] then
            local u = V.nextUid
            V.nextUid = u + 1
            local vi = { uid = u, id = r.def.id, count = r.n, data = {}, hb = r.hb > 0 and r.hb or nil, fixed = true }
            vPlace(E, vi, r.c, r.x, r.y, r.rot)
        end
    end
end

local function vAddGrids(E, def)
    local It, V = Rhylib.Items, E.V
    if def.grid then
        local gcid = def.gridCid or It.BACK
        local w, h = def.grid[1], def.grid[2]
        if gcid == It.BACK and E.mult ~= 1 then h = math.max(1, math.floor(h * E.mult)) end
        if not V.cont[gcid] then V.cont[gcid] = { w = w, h = h, items = {} } end
    end
    for _, eg in ipairs(def.extraGrids or {}) do
        if not V.cont[eg.cid] then V.cont[eg.cid] = { w = eg.w, h = eg.h, items = {} } end
    end
end

function vPlace(E, vi, cid, x, y, rot)
    local It, V = Rhylib.Items, E.V
    vi.c, vi.x, vi.y, vi.rot = cid, x, y, rot
    V.cont[cid].items[vi.uid] = vi
    V.byUid[vi.uid] = vi
    if It.IsWorn(cid) then vAddGrids(E, It.defs[vi.id]) end
end

-- (a worn item's grids go with it; only called once they're empty)
local function vRemove(E, vi)
    local It, V = Rhylib.Items, E.V
    local c = vi.c and V.cont[vi.c]
    if c then c.items[vi.uid] = nil end
    V.byUid[vi.uid] = nil
    if vi.c and It.IsWorn(vi.c) then
        local def = It.defs[vi.id]
        for _, g in ipairs(def and gridsOf(def) or {}) do
            local gc = V.cont[g]
            if gc and next(gc.items) == nil then V.cont[g] = nil end
        end
    end
end

local function newVi(E, id, n)
    local V = E.V
    local u = V.nextUid
    while V.byUid[u] do u = u + 1 end
    V.nextUid = u + 1
    return { uid = u, id = id, count = n, data = {} }
end

-- Where Inv.AddItem would put it (its worn slot, then the grids in the
-- inventory's order).
local function findSpot(E, id)
    local It, V = Rhylib.Items, E.V
    local def = It.defs[id]
    if not def then return nil end
    local wcid = def.slot and It.WORN_BY_SLOT[def.slot]
    if wcid and V.cont[wcid] and It.CanPlace(V, id, wcid, 0, 0, false) and It.CanWear(LocalPlayer(), def) then return wcid, 0, 0, false end
    for _, cid in ipairs({ It.CELLBELT, It.RACK, It.CELLPACK, It.HOLSTER, It.MAIN, It.BACK, It.GUNBELT, It.BELT, It.POUCH }) do
        local c = V.cont[cid]
        if c and It.ContainerAllows(cid, def) then
            local x, y, rot = It.FindSpot(c, id)
            if x then return cid, x, y, rot end
        end
    end
end

local function note(E, text)
    E.note, E.noteAt = text, RealTime()
end

local recalc   -- (below)

local function countId(E, id)
    local n = 0
    for _, o in pairs(E.V.byUid) do if o.id == id then n = n + 1 end end
    return n
end

local function shelfOf(E, id) return E.byId[id] end

-- Rows into the virtual inventory: their own spot when it's free, else
-- anywhere. Rows for items you may not take now are left out.
local function loadRows(E, rows)
    local It = Rhylib.Items
    vNew(E)
    local list = {}
    for i, r in ipairs(rows) do list[#list + 1] = { i = i, r = r } end
    table.sort(list, function(a, b)
        local wa, wb = It.IsWorn(a.r.c) and 0 or 1, It.IsWorn(b.r.c) and 0 or 1
        if wa ~= wb then return wa < wb end
        return a.i < b.i
    end)
    local dropped = 0
    for _, e in ipairs(list) do
        local r = e.r
        local def = r.def
        local sh = def and shelfOf(E, def.id)
        if not (def and sh and not sh.lock) then
            dropped = dropped + 1
        else
            local n = It.Unique(def) and 1 or math.Clamp(r.n, 1, It.StackFor(def, LocalPlayer()))
            if It.Unique(def) and countId(E, def.id) >= math.max(1, sh.limit) then
                dropped = dropped + 1
            else
                local vi = newVi(E, def.id, n)
                vi.hb = r.hb > 0 and r.hb or nil
                local cid, x, y, rot = r.c, r.x, r.y, r.rot
                if not (E.V.cont[cid] and It.CanPlace(E.V, def.id, cid, x, y, rot) and (not It.IsWorn(cid) or It.CanWear(LocalPlayer(), def))) then
                    cid, x, y, rot = findSpot(E, def.id)
                end
                if cid then vPlace(E, vi, cid, x, y, rot) else dropped = dropped + 1 end
            end
        end
    end
    recalc(E)
    if dropped > 0 then note(E, dropped .. " item" .. (dropped == 1 and "" or "s") .. " left out (not allowed now, or no room)") end
end

--------------------------------------------------------------------------
-- Weight and layout state (worked out on change, not while painting)
--------------------------------------------------------------------------

function recalc(E)
    local It = Rhylib.Items
    local w, cap = It.Weight(E.V)
    local K = Rhylib.Skills
    if K and K.AdjustWeight then
        local ok, w2, c2 = pcall(K.AdjustWeight, LocalPlayer(), E.V, w, cap)
        if ok and w2 then w, cap = w2, c2 end
    end
    E.weight, E.cap = w, cap
    E.ceil = Rhylib.Config.Get("inventory", "weightCeiling")
    E.weightText = string.format("%.1f", w)
    E.capText = string.format("/ %.0f kg", cap)
    if w <= cap * 0.75 then E.status, E.statusCol = "Sprinting OK", H().C.GREEN
    elseif w <= cap then E.status, E.statusCol = "Slower", H().C.AMBER
    else E.status, E.statusCol = "No sprinting", H().C.RED end
    -- (the grids shown: rebuilt when one comes or goes)
    local key = ""
    for _, cid in ipairs(gridOrder()) do
        local c = E.V.cont[cid]
        if c then key = key .. cid .. ":" .. c.w .. "x" .. c.h .. ";" end
    end
    if key ~= E.gridKey then
        E.gridKey = key
        if E.rebuildGrids then E.rebuildGrids() end
    end
    E.hotbarSize = It.HotbarSize(E.V)
    for _, o in pairs(E.V.byUid) do
        if o.hb and o.hb > E.hotbarSize then o.hb = nil end
    end
end

local function overweight(E)
    return E.ceil > 0 and E.weight > E.cap * E.ceil + 1e-6
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

-- One item tile: dark, a strip on top in its kind's colour, its picture,
-- name bottom left, count bottom right.
local function drawTile(def, x, y, w, h, rot, n, alpha)
    local C = H().C
    surface.SetDrawColor(C_SHELF.r, C_SHELF.g, C_SHELF.b, alpha or 255)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(C_TILE_EDGE.r, C_TILE_EDGE.g, C_TILE_EDGE.b, alpha or 255)
    surface.DrawOutlinedRect(x, y, w, h)
    local col = H().kindCol(def)
    surface.SetDrawColor(col.r, col.g, col.b, alpha or 255)
    surface.DrawRect(x + 1, y + 1, w - 2, S(3))
    local Inv = Rhylib.Inventory
    if Inv and Inv.Icons and Inv.Icons.Draw and h > S(30) and w > S(10) then Inv.Icons.Draw(def, x + S(3), y + S(6), w - S(6), h - S(22), rot, alpha) end
    local font = F(10, 500)
    local countW = n and n > 1 and S(22) or 0
    draw.SimpleText(fitName(def, font, math.max(S(10), w - S(8) - countW)), font, x + S(4), y + h - S(8), C.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if n and n > 1 then draw.SimpleText(countOf(n), F(10, 700), x + w - S(4), y + h - S(8), C.TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
end

local function hit(p)
    if not (IsValid(p) and p:IsVisible()) then return false end
    local x, y = p:LocalCursorPos()
    return x >= 0 and y >= 0 and x < p:GetWide() and y < p:GetTall(), x, y
end

--------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------

-- E.drag = { id, def, n, rot, vi (moving one) or nil (from a shelf), from = { c, x, y, rot } }
local function startDrag(E, d)
    E.drag = d
end

local function addNew(E, def, n, cid, x, y, rot)
    local It = Rhylib.Items
    local sh = shelfOf(E, def.id)
    if not sh or sh.lock then return false end
    if It.Unique(def) and countId(E, def.id) >= math.max(1, sh.limit) then
        note(E, sh.limit > 1 and ("You can carry " .. sh.limit .. " of those") or "You can carry one of those")
        return false
    end
    local vi = newVi(E, def.id, n)
    vPlace(E, vi, cid, x, y, rot)
    recalc(E)
    if overweight(E) then
        vRemove(E, vi)
        recalc(E)
        note(E, "Too heavy: that would be more than you can carry")
        return false
    end
    if def.weapon and not vi.hb and Rhylib.Config.Get("inventory", "autoHotbar") then
        local used = {}
        for _, o in pairs(E.V.byUid) do
            if o.hb then used[o.hb] = true end
        end
        for k = 1, E.hotbarSize do
            if not used[k] then vi.hb = k break end
        end
    end
    return true
end

-- (onto a matching stack under the cursor: adds what fits)
local function mergeInto(E, d, c, cx, cy)
    local It = Rhylib.Items
    local target = It.At(c.items, cx, cy)
    if not (target and not target.fixed and target.id == d.id and d.def.stack > 1) then return false end
    local cap = It.StackFor(d.def, LocalPlayer())
    local add = math.min(cap - target.count, d.n)
    if add <= 0 then return false end
    target.count = target.count + add
    recalc(E)
    if not d.vi and overweight(E) then
        target.count = target.count - add
        recalc(E)
        note(E, "Too heavy: that would be more than you can carry")
        return true
    end
    if d.vi then
        d.vi.count = d.vi.count - add
        if d.vi.count > 0 then return false end   -- (the rest goes where it was dropped, or back)
    end
    return true
end

local function placeAt(E, d, cid, x, y, rot)
    local It = Rhylib.Items
    local def = d.def
    if not (E.V.cont[cid] and It.CanPlace(E.V, d.id, cid, x, y, rot)) then return false end
    if It.IsWorn(cid) then
        local ok, why = It.CanWear(LocalPlayer(), def)
        if not ok then note(E, why or "You can't wear that") return false end
    end
    if d.vi then
        vPlace(E, d.vi, cid, x, y, rot)
        recalc(E)
        return true
    end
    return addNew(E, def, d.n, cid, x, y, rot)
end

local function restore(E, d)
    if d.vi and d.from then
        vPlace(E, d.vi, d.from.c, d.from.x, d.from.y, d.from.rot)
        recalc(E)
    end
end

local function drop(E)
    local d = E.drag
    E.drag = nil
    if not d then return end
    local It = Rhylib.Items
    -- a grid
    for _, gp in ipairs(E.gridPanels or {}) do
        local inside, lx, ly = hit(gp)
        if inside and hit(E.gridScroll) then
            local c = E.V.cont[gp.cid]
            local step = E.cs + E.gap
            local iw, ih = It.Size(d.id, d.rot)
            local cx, cy = math.floor(lx / step), math.floor(ly / step)
            if c and mergeInto(E, d, c, cx, cy) then return end
            local x = math.floor(lx / step - iw / 2 + 0.5)
            local y = math.floor(ly / step - ih / 2 + 0.5)
            if placeAt(E, d, gp.cid, x, y, d.rot) then return end
            if not It.ContainerAllows(gp.cid, d.def) then note(E, "That doesn't go in there") end
            return restore(E, d)
        end
    end
    -- a worn slot
    local inside, lx, ly = hit(E.wornPanel)
    if inside then
        for _, wr in ipairs(E.wornRects or {}) do
            if lx >= wr.x and ly >= wr.y and lx < wr.x + wr.w and ly < wr.y + wr.h then
                if placeAt(E, d, wr.cid, 0, 0, false) then return end
                note(E, It.ContainerAllows(wr.cid, d.def) and "Take that off first" or "That doesn't go there")
                return restore(E, d)
            end
        end
        return restore(E, d)
    end
    -- a hotbar key (items already in the loadout)
    inside, lx = hit(E.hotbarPanel)
    if inside then
        restore(E, d)
        if not d.vi then return end
        local n = math.floor(lx / (E.hotbarPanel:GetWide() / E.hotbarSize)) + 1
        if n >= 1 and n <= E.hotbarSize then
            for _, o in pairs(E.V.byUid) do
                if o.hb == n and o.fixed then return note(E, "Your job gear has that key") end
            end
            for _, o in pairs(E.V.byUid) do
                if o.hb == n then o.hb = nil end
            end
            d.vi.hb = n
        end
        return
    end
    -- the right column but nowhere in particular: back where it was
    if hit(E.right) then return restore(E, d) end
    -- outside the inventory: removed (a new one simply isn't added)
    if d.vi then recalc(E) end
end

--------------------------------------------------------------------------
-- Building the window
--------------------------------------------------------------------------

local function close()
    local E = Q.editor
    Q.editor = nil
    if E and IsValid(E.frame) then E.frame:Remove() end
end
Q.CloseEditor = close

if UI and UI.RegisterCloser then
    UI.RegisterCloser("armoury.qmeditor", function()
        if Q.editor and IsValid(Q.editor.frame) then
            close()
            return true
        end
        return false
    end)
end

local function shelfTile(E, parent, sh)
    local It = Rhylib.Items
    local C = H().C
    local def = sh.def
    local p = vgui.Create("DPanel", parent)
    local g = It.GroupOf(def)
    local kind = string.upper(It.GROUP_NAMES and It.GROUP_NAMES[g] or g)
    local stock, stockCol
    if sh.stock == Q.NO_LIMIT then stock, stockCol = "No limit", C.DIM
    elseif sh.stock <= 0 then stock, stockCol = "OUT", C.RED
    else
        local L = Rhylib.Logistics
        local mx = L and L.StockMax and L.StockMax(def.id)
        stock = sh.stock .. " left"
        stockCol = (mx and sh.stock < mx * 0.6) and C.AMBER or C.GREEN
    end
    local size = def.w .. " × " .. def.h
    local lock = sh.lock
    local alpha = lock and 150 or 255
    local shownName, shownLock, shownKind = def.name, lock, kind
    function p:PerformLayout(pw)
        shownName = H().K().Fit(def.name, F(13, 700), pw - S(60))
        shownKind = H().K().Fit(kind, F(10, 700), pw - S(80))
        if lock then shownLock = H().K().Fit(lock, F(11), pw - S(20)) end
    end
    function p:Paint(pw, ph)
        surface.SetDrawColor(C_SHELF)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(self:IsHovered() and not lock and C.BLUE or C.EDGE)
        surface.DrawOutlinedRect(0, 0, pw, ph)
        draw.SimpleText(shownKind, F(10, 700), S(11), S(16), C.LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(F(11, 700))
        local sw = surface.GetTextSize(stock) + S(12)
        surface.SetDrawColor(C.INSET)
        surface.DrawRect(pw - S(11) - sw, S(8), sw, S(17))
        draw.SimpleText(stock, F(11, 700), pw - S(11) - sw / 2, S(16), stockCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local Inv = Rhylib.Inventory
        if Inv and Inv.Icons and Inv.Icons.Draw then Inv.Icons.Draw(def, S(11), S(30), pw - S(22), ph - S(30) - (lock and S(40) or S(26)), false, alpha) end
        local ny = ph - (lock and S(28) or S(14))
        draw.SimpleText(shownName, F(13, 700), S(11), ny, lock and C.OFF or C.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(size, F(11), pw - S(11), ny, C.LABEL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if lock then draw.SimpleText(shownLock, F(11), S(11), ph - S(11), C_LOCK, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end
    function p:OnMousePressed(code)
        if lock then
            note(E, lock)
            return
        end
        local n = It.Unique(def) and 1 or It.StackFor(def, LocalPlayer())
        if code == MOUSE_LEFT then
            startDrag(E, { id = def.id, def = def, n = n, rot = false })
        elseif code == MOUSE_RIGHT then
            local cid, x, y, rot = findSpot(E, def.id)
            if not cid then return note(E, "No room for it") end
            addNew(E, def, n, cid, x, y, rot)
        end
    end
    return p
end

local function buildShelves(E)
    local area = E.shelfArea
    area:Clear()
    local tiles = {}
    for _, sh in ipairs(E.shelves) do
        if sh.tab == E.tab then tiles[#tiles + 1] = shelfTile(E, area, sh) end
    end
    function area:PerformLayout(pw)
        local gap, th = S(8), S(116)
        local cols = pw > S(900) and 4 or 3
        local tw = math.floor((pw - gap * (cols - 1)) / cols)
        for i, t in ipairs(tiles) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            t:SetPos(col * (tw + gap), row * (th + gap))
            t:SetSize(tw, th)
        end
        local want = math.max(1, math.ceil(#tiles / cols)) * (th + gap)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    area:InvalidateLayout()
end

local function buildTabs(E)
    local row = E.tabRow
    row:Clear()
    local counts = {}
    for _, sh in ipairs(E.shelves) do counts[sh.tab] = (counts[sh.tab] or 0) + 1 end
    local C = H().C
    local first
    for t, name in ipairs(Q.TABS) do
        if counts[t] then
            first = first or t
            local label = name
            local cnt = tostring(counts[t])
            local b = vgui.Create("DButton", row)
            b:SetText("")
            surface.SetFont(F(13, 700))
            local tw = surface.GetTextSize(label)
            surface.SetFont(F(11))
            b:SetWide(tw + surface.GetTextSize(cnt) + S(36))
            b:Dock(LEFT)
            b:DockMargin(0, 0, S(6), 0)
            function b:Paint(pw, ph)
                local on = E.tab == t
                if on then
                    surface.SetDrawColor(C_TAB_ON)
                    surface.DrawRect(0, 0, pw, ph)
                elseif self:IsHovered() then
                    surface.SetDrawColor(C.TILE)
                    surface.DrawRect(0, 0, pw, ph)
                end
                surface.SetDrawColor(on and C_TAB_ON or C.EDGE)
                surface.DrawOutlinedRect(0, 0, pw, ph)
                draw.SimpleText(label, F(13, on and 700 or 500), S(14), ph / 2, on and C_DARK or C_TAB_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(cnt, F(11), pw - S(14), ph / 2, on and C_DARK or C.LABEL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                return true
            end
            function b:DoClick()
                if E.tab == t then return end
                E.tab = t
                buildShelves(E)
            end
        end
    end
    if not counts[E.tab or 0] then E.tab = first end
end

-- The grids column: one section per grid, rebuilt when one comes or goes.
local function buildGrids(E)
    local It = Rhylib.Items
    local C = H().C
    local sp = E.gridScroll
    sp:Clear()
    E.gridPanels = {}
    local gap = S(4)
    local maxW = 1
    for _, cid in ipairs(gridOrder()) do
        local c = E.V.cont[cid]
        if c then maxW = math.max(maxW, c.w) end
    end
    local avail = E.right:GetWide() - S(40) - S(10)
    E.gap = gap
    E.cs = math.max(S(24), math.min(S(54), math.floor((avail - gap * (maxW - 1)) / maxW)))
    for _, cid in ipairs(gridOrder()) do
        local c = E.V.cont[cid]
        if c then
            local hd = vgui.Create("DPanel", sp)
            hd:Dock(TOP)
            hd:SetTall(S(22))
            local title = gridTitle(cid)
            local col = cid == It.MAIN and C.LABEL or C.BLUE
            function hd:Paint(pw, ph) draw.SimpleText(title, F(13, 800), 0, ph / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
            local g = vgui.Create("DPanel", sp)
            g:Dock(TOP)
            g.cid = cid
            local step = E.cs + gap
            g:SetTall(c.h * step - gap)
            g:DockMargin(0, S(2), S(10), S(10))
            function g:Paint(pw, ph)
                local cc = E.V.cont[cid]
                if not cc then return end
                local cs = E.cs
                for yy = 0, cc.h - 1 do
                    for xx = 0, cc.w - 1 do
                        surface.SetDrawColor(C_CELL)
                        surface.DrawRect(xx * step, yy * step, cs, cs)
                        surface.SetDrawColor(C_CELL_EDGE)
                        surface.DrawOutlinedRect(xx * step, yy * step, cs, cs)
                    end
                end
                for _, o in pairs(cc.items) do
                    local def = It.defs[o.id]
                    if def then
                        local iw, ih = It.Size(o.id, o.rot)
                        drawTile(def, o.x * step, o.y * step, iw * step - gap, ih * step - gap, o.rot, o.count, o.fixed and 110 or nil)
                    end
                end
                -- where a dragged item would land
                local d = E.drag
                if d then
                    local inside, lx, ly = hit(self)
                    if inside then
                        local iw, ih = It.Size(d.id, d.rot)
                        local x = math.floor(lx / step - iw / 2 + 0.5)
                        local y = math.floor(ly / step - ih / 2 + 0.5)
                        local okHere = It.CanPlace(E.V, d.id, cid, x, y, d.rot)
                        surface.SetDrawColor(okHere and C_OK_DROP or C_BAD_DROP)
                        surface.DrawRect(x * step, y * step, iw * step - gap, ih * step - gap)
                        surface.SetDrawColor(okHere and C.BLUE or C.RED)
                        surface.DrawOutlinedRect(x * step, y * step, iw * step - gap, ih * step - gap)
                    end
                end
            end
            function g:OnMousePressed(code)
                if code ~= MOUSE_LEFT then return end
                local _, lx, ly = hit(self)
                local cc = E.V.cont[cid]
                local o = cc and It.At(cc.items, math.floor(lx / step), math.floor(ly / step))
                if not o then return end
                if o.fixed then return note(E, "That's your job gear: it stays") end
                if not It.CanLeave(E.V, o) then return end
                local from = { c = o.c, x = o.x, y = o.y, rot = o.rot }
                vRemove(E, o)
                startDrag(E, { id = o.id, def = It.defs[o.id], n = o.count, rot = o.rot, vi = o, from = from })
            end
            E.gridPanels[#E.gridPanels + 1] = g
        end
    end
    local jn = H().K().Label(sp, "Your job gear (dim) stays where it is: the loadout is built around it.", 12, 400, C.LABEL)
    jn:Dock(TOP)
    jn:DockMargin(0, S(4), S(10), 0)
end

local function buildWorn(E)
    local It = Rhylib.Items
    local C = H().C
    local p = E.wornPanel
    local order = { It.SLOT_BACK }
    for _, cid in ipairs(It.GEAR_SLOTS) do order[#order + 1] = cid end
    local titles = {}
    function p:PerformLayout(pw)
        local tw, th, gap = S(92), S(50), S(8)
        local cols = math.max(1, math.floor((pw + gap) / (tw + gap)))
        E.wornRects = {}
        local i = 0
        for _, cid in ipairs(order) do
            if E.V.cont[cid] then
                local col, row = i % cols, math.floor(i / cols)
                E.wornRects[#E.wornRects + 1] = { cid = cid, x = col * (tw + gap), y = row * (th + gap), w = tw, h = th }
                titles[cid] = titles[cid] or string.upper(It.WORN[cid].title)
                i = i + 1
            end
        end
        local want = math.max(1, math.ceil(i / cols)) * (th + gap) - gap
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    function p:Paint(pw, ph)
        for _, r in ipairs(E.wornRects or {}) do
            local c = E.V.cont[r.cid]
            local _, o = next(c and c.items or {})
            if o then
                surface.SetDrawColor(C_SHELF)
                surface.DrawRect(r.x, r.y, r.w, r.h)
                surface.SetDrawColor(C_TILE_EDGE)
                surface.DrawOutlinedRect(r.x, r.y, r.w, r.h)
                local def = It.defs[o.id]
                if def then
                    local col = H().kindCol(def)
                    surface.SetDrawColor(col)
                    surface.DrawRect(r.x + 1, r.y + 1, r.w - 2, S(2))
                    draw.SimpleText(fitName(def, F(11, 500), r.w - S(14)), F(11, 500), r.x + S(8), r.y + r.h - S(13), C.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            else
                H().dashed(r.x, r.y, r.w, r.h, C.EDGE)
                draw.SimpleText("Empty", F(11, 500), r.x + S(8), r.y + r.h - S(13), C.OFF, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            draw.SimpleText(titles[r.cid] or "", F(9, 700), r.x + S(8), r.y + S(12), C.LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if E.drag then
                local inside, lx, ly = hit(self)
                if inside and lx >= r.x and ly >= r.y and lx < r.x + r.w and ly < r.y + r.h then
                    surface.SetDrawColor(It.ContainerAllows(r.cid, E.drag.def) and C.BLUE or C.RED)
                    surface.DrawOutlinedRect(r.x, r.y, r.w, r.h)
                end
            end
        end
    end
    function p:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        local _, lx, ly = hit(self)
        for _, r in ipairs(E.wornRects or {}) do
            if lx >= r.x and ly >= r.y and lx < r.x + r.w and ly < r.y + r.h then
                local c = E.V.cont[r.cid]
                local _, o = next(c and c.items or {})
                if not o then return end
                if o.fixed then return note(E, "That's your job gear: it stays") end
                local ok, why = It.CanLeave(E.V, o)
                if not ok then return note(E, why) end
                local from = { c = o.c, x = o.x, y = o.y, rot = o.rot }
                vRemove(E, o)
                recalc(E)
                startDrag(E, { id = o.id, def = It.defs[o.id], n = o.count, rot = o.rot, vi = o, from = from })
                return
            end
        end
    end
end

local function buildHotbar(E)
    local It = Rhylib.Items
    local C = H().C
    local p = E.hotbarPanel
    local keyText = {}
    for k = 1, 7 do keyText[k] = tostring(k) end
    function p:Paint(pw, ph)
        local n = E.hotbarSize or 4
        local gap = S(6)
        local kw = (pw - gap * (n - 1)) / n
        for k = 1, n do
            local x = (k - 1) * (kw + gap)
            surface.SetDrawColor(C.CARD)
            surface.DrawRect(x, 0, kw, ph)
            surface.SetDrawColor(C.EDGE)
            surface.DrawOutlinedRect(x, 0, kw, ph)
            draw.SimpleText(keyText[k], F(14, 800), x + S(10), ph / 2, C.BLUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local def
            for _, o in pairs(E.V.byUid) do
                if o.hb == k then def = It.defs[o.id] break end
            end
            if def then
                draw.SimpleText(fitName(def, F(11), kw - S(30)), F(11), x + S(26), ph / 2, C.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText("Empty", F(11), x + S(26), ph / 2, C.OFF, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end
    function p:OnMousePressed(code)
        if code ~= MOUSE_RIGHT then return end
        local _, lx = hit(self)
        local n = math.floor(lx / (self:GetWide() / (E.hotbarSize or 4))) + 1
        for _, o in pairs(E.V.byUid) do
            if o.hb == n and not o.fixed then o.hb = nil end
        end
    end
end

local function rowsOut(E)
    local rows = {}
    for _, o in pairs(E.V.byUid) do
        if not o.fixed then rows[#rows + 1] = o end
    end
    return rows
end

local function save(E)
    local It = Rhylib.Items
    local rows = rowsOut(E)
    if #rows == 0 then return note(E, "The loadout is empty") end
    if #rows > Q.MAX_ROWS then return note(E, "Too many items (at most " .. Q.MAX_ROWS .. ")") end
    if overweight(E) then return note(E, "Too heavy: that's more than you can carry") end
    if E.saving and E.saving > RealTime() then return end
    local name = Q.CleanName(IsValid(E.nameEntry) and E.nameEntry:GetValue() or "")
    E.saving = RealTime() + 4
    Rhylib.Net.Start("armoury.qmact")
    net.WriteEntity(E.npc)
    net.WriteUInt(Q.OP_EDITOR, 3)
    net.WriteUInt(E.slot, 2)
    net.WriteUInt(1, 1)
    net.WriteString(name)
    net.WriteUInt(#rows, 7)
    for _, o in ipairs(rows) do
        net.WriteUInt(It.NetId(o.id), It.NET_BITS)
        net.WriteUInt(o.c, 5)
        net.WriteUInt(o.x, 5)
        net.WriteUInt(o.y, 5)
        net.WriteBool(o.rot and true or false)
        net.WriteUInt(math.Clamp(o.count, 1, 255), 8)
        net.WriteUInt(o.hb or 0, 3)
    end
    net.SendToServer()
end

local function open(data)
    local k = H() and H().K()
    if not k then return end
    close()
    local It = Rhylib.Items
    local C = H().C
    local E = { npc = data.npc, slot = data.slot, mult = data.mult, base = data.grids, shelves = data.shelves, byId = {},
        slotRows = data.slotRows, carryRows = data.carryRows, fixedRows = data.fixedRows }
    for _, sh in ipairs(E.shelves) do E.byId[sh.def.id] = sh end
    Q.editor = E
    vNew(E)

    local f = vgui.Create("EditablePanel")
    f:SetSize(math.min(ScrW() - S(40), S(1440)), math.min(ScrH() - S(40), S(900)))
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f:DockPadding(0, S(72), 0, 0)
    E.frame = f
    local title = "EDIT LOADOUT " .. data.slot
    function f:Paint(pw, ph)
        surface.SetDrawColor(C.WIN)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(C.CARD)
        surface.DrawRect(0, 0, pw, S(72))
        surface.SetDrawColor(C.PURPLE)
        surface.DrawRect(0, 0, pw, S(3))
        surface.SetDrawColor(C.BLACK)
        surface.DrawRect(0, S(71), pw, 1)
        draw.SimpleText(title, F(24, 800), S(24), S(24), C.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Name", F(12), S(24), S(52), C.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(C.BLACK)
        surface.DrawOutlinedRect(0, 0, pw, ph)
    end
    -- the dragged item under the mouse
    function f:PaintOver(pw, ph)
        local d = E.drag
        if not d or not d.def then return end
        local mx, my = self:CursorPos()
        local iw, ih = It.Size(d.id, d.rot)
        local step = (E.cs or S(54)) + (E.gap or S(4))
        local w, h = iw * step - (E.gap or 0), ih * step - (E.gap or 0)
        drawTile(d.def, mx - w / 2, my - h / 2, w, h, d.rot, d.n, 200)
    end
    function f:Think()
        local me = LocalPlayer()
        local r = Rhylib.Config.Get("armoury", "qmRange") + 60
        if not IsValid(E.npc) or not IsValid(me) or not me:Alive() or me:GetPos():DistToSqr(E.npc:GetPos()) > r * r then
            close()
            return
        end
        if E.drag then
            -- R turns it (not while typing the name)
            local rDown = input.IsKeyDown(KEY_R) and vgui.GetKeyboardFocus() ~= E.nameEntry
            if rDown and not E.rWas and E.drag.def and E.drag.def.w ~= E.drag.def.h then E.drag.rot = not E.drag.rot end
            E.rWas = rDown
            if not input.IsMouseDown(MOUSE_LEFT) then drop(E) end
        end
    end

    local ne = k.TextEntry(f, Q.DefaultName(data.slot))
    ne:SetPos(S(64), S(40))
    ne:SetSize(S(180), S(26))
    ne:SetText(data.name or "")
    E.nameEntry = ne

    -- header buttons, right to left
    local bx = f:GetWide() - S(24)
    local function hbtn(label, style, w, fn, opts)
        local b = H().button(f, label, style, fn, nil, opts)
        bx = bx - w
        b:SetPos(bx, S(14))
        b:SetSize(w, S(44))
        bx = bx - S(8)
        return b
    end
    local sv = hbtn("Save loadout", "primary", S(150), function() save(E) end)
    sv.IsOn = function() return not (E.saving and E.saving > RealTime()) end
    hbtn("Cancel", "ghost", S(90), close, { font = F(13, 500) })
    hbtn("Empty it", "danger", S(100), function() vNew(E) recalc(E) end, { font = F(13, 500) })
    hbtn("Start from what I carry", "outline", S(200), function() loadRows(E, E.carryRows) end, { font = F(13, 500) })

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body.Paint = nil

    -- Right: the loadout inventory
    local right = vgui.Create("DPanel", body)
    right:Dock(RIGHT)
    right:SetWide(math.min(S(640), math.floor(f:GetWide() * 0.48)))
    right:DockPadding(S(20), S(16), S(20), S(16))
    function right:Paint(pw, ph)
        surface.SetDrawColor(C.SIDE)
        surface.DrawRect(0, 0, pw, ph)
        surface.SetDrawColor(C.BLACK)
        surface.DrawRect(0, 0, 1, ph)
    end
    E.right = right
    local wt = vgui.Create("DPanel", right)
    wt:Dock(TOP)
    wt:SetTall(S(34))
    function wt:Paint(pw, ph)
        draw.SimpleText("LOADOUT WEIGHT", F(13, 800), 0, S(9), C.LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(F(13, 800))
        local x = surface.GetTextSize("LOADOUT WEIGHT") + S(10)
        draw.SimpleText(E.weightText or "", F(16, 700), x, S(9), C.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont(F(16, 700))
        x = x + surface.GetTextSize(E.weightText or "") + S(6)
        draw.SimpleText(E.capText or "", F(12), x, S(9), C.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(E.status or "", F(12), pw, S(9), E.statusCol or C.DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local by, bh = S(22), S(8)
        surface.SetDrawColor(C.INSET)
        surface.DrawRect(0, by, pw, bh)
        surface.SetDrawColor(C.EDGE)
        surface.DrawOutlinedRect(0, by, pw, bh)
        local cap = math.max(1, E.cap or 1)
        local top = cap * math.max(1, E.ceil or 1)
        surface.SetDrawColor(overweight(E) and C.RED or C.BLUE)
        surface.DrawRect(1, by + 1, math.floor((pw - 2) * math.Clamp((E.weight or 0) / top, 0, 1)), bh - 2)
        surface.SetDrawColor(C.AMBER)
        surface.DrawRect(math.floor(pw * 0.75 * cap / top), by - S(3), S(2), bh + S(6))
        if top > cap then
            surface.SetDrawColor(C.RED)
            surface.DrawRect(math.floor(pw * cap / top) - S(2), by - S(3), S(2), bh + S(6))
        end
    end
    local worn = vgui.Create("DPanel", right)
    worn:Dock(TOP)
    worn:DockMargin(0, S(12), 0, S(12))
    worn:SetTall(S(50))
    E.wornPanel = worn
    local hot = vgui.Create("DPanel", right)
    hot:Dock(BOTTOM)
    hot:SetTall(S(42))
    hot:DockMargin(0, S(10), 0, 0)
    E.hotbarPanel = hot
    local gs = k.Scroll(right)
    gs:Dock(FILL)
    E.gridScroll = gs

    -- Left: the catalogue
    local left = vgui.Create("DPanel", body)
    left:Dock(FILL)
    left.Paint = nil
    local tabs = vgui.Create("DPanel", left)
    tabs:Dock(TOP)
    tabs:SetTall(S(36))
    tabs:DockMargin(S(20), S(14), S(20), S(14))
    tabs.Paint = nil
    E.tabRow = tabs
    local foot = vgui.Create("DPanel", left)
    foot:Dock(BOTTOM)
    foot:SetTall(S(40))
    local hint = "Drag onto your inventory · R turns it · right-click adds a stack · drag out to remove · nothing is taken from stock until you apply"
    local shownHint
    function foot:PerformLayout(pw) shownHint = H().K().Fit(hint, F(12), pw - S(40)) end
    function foot:Paint(pw, ph)
        surface.SetDrawColor(C.CARD)
        surface.DrawRect(0, 0, pw, 1)
        local fresh = E.note and RealTime() - (E.noteAt or 0) < 5
        if fresh then
            if E.noteText ~= E.note or E.noteW ~= pw then E.noteText, E.noteW, E.noteFit = E.note, pw, H().K().Fit(E.note, F(12, 700), pw - S(40)) end
            draw.SimpleText(E.noteFit, F(12, 700), S(20), ph / 2, C.AMBER, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(shownHint or "", F(12), S(20), ph / 2, C.LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local ss = k.Scroll(left)
    ss:Dock(FILL)
    ss:DockMargin(S(20), 0, S(10), S(10))
    local area = vgui.Create("DPanel", ss)
    area:Dock(TOP)
    area:DockMargin(0, 0, S(10), 0)
    area.Paint = nil
    E.shelfArea = area

    E.rebuildGrids = function()
        if IsValid(E.gridScroll) then buildGrids(E) end
        if IsValid(E.wornPanel) then E.wornPanel:InvalidateLayout() end
    end
    buildWorn(E)
    buildHotbar(E)
    buildTabs(E)
    buildShelves(E)
    -- (the grids need the column's width: built once it's laid out)
    f:InvalidateLayout(true)
    body:InvalidateLayout(true)
    E.gridKey = nil
    if #E.slotRows > 0 then loadRows(E, E.slotRows) else recalc(E) end
end
Q.OpenEditor = open

--------------------------------------------------------------------------
-- Nets
--------------------------------------------------------------------------

local function readRows(It)
    local out = {}
    local n = net.ReadUInt(7)
    for _ = 1, n do
        local def = It.FromNet(net.ReadUInt(It.NET_BITS))
        local r = { def = def }
        r.c = net.ReadUInt(5)
        r.x = net.ReadUInt(5)
        r.y = net.ReadUInt(5)
        r.rot = net.ReadBool()
        r.n = net.ReadUInt(8)
        r.hb = net.ReadUInt(3)
        out[#out + 1] = r
    end
    return out
end

Rhylib.Net.Receive("armoury.qmcat", function()
    local It = Rhylib.Items
    if not (It and Q.UIH) then return end
    local d = { grids = {}, shelves = {} }
    d.npc = net.ReadEntity()
    d.slot = net.ReadUInt(2)
    d.name = net.ReadString()
    d.mult = net.ReadUInt(7) / 10
    local ng = net.ReadUInt(5)
    for _ = 1, ng do
        local g = {}
        g.cid = net.ReadUInt(5)
        g.w = net.ReadUInt(5)
        g.h = net.ReadUInt(5)
        d.grids[#d.grids + 1] = g
    end
    local reasons = {}
    local nr = net.ReadUInt(7)
    for i = 1, nr do reasons[i] = net.ReadString() end
    local ns = net.ReadUInt(9)
    for _ = 1, ns do
        local def = It.FromNet(net.ReadUInt(It.NET_BITS))
        local sh = { def = def }
        sh.tab = net.ReadUInt(3)
        sh.stock = net.ReadUInt(11)
        sh.limit = net.ReadUInt(2)
        local ri = net.ReadUInt(7)
        if ri > 0 then sh.lock = reasons[ri] or "You can't take that" end
        if def then d.shelves[#d.shelves + 1] = sh end
    end
    d.fixedRows = readRows(It)
    d.slotRows = readRows(It)
    d.carryRows = readRows(It)
    local w = Q.win
    if w then w.busy = nil end
    if not IsValid(d.npc) then return end
    open(d)
end)

Rhylib.Net.Receive("armoury.qmeditres", function()
    local ok = net.ReadBool()
    local why = net.ReadString()
    local E = Q.editor
    if not E then return end
    E.saving = nil
    if ok then close() else note(E, "Not saved: " .. why) end
end)
