--[[
    Inventory window (client only).

    Press G (rhylib_inventory_key) or run rhylib_inventory to open or close.

    Layout:
      Header: INVENTORY, your name and job, the carry bar (kg / cap, amber
        mark where you get slower, red mark where sprinting stops, a word
        for how you're doing) and the close button.
      WORN (left column): your player model in the middle (drag to turn
        it) with the gear slots stacked as labelled tiles on both sides
        (body parts on the left; helmet on/off, helmet gear, antenna and
        holster on the right). A filled slot is a solid tile, an empty one
        a dashed outline. Under the model: the Back slot and the belt cell
        pouch, then Combine munitions.
      Right: POCKETS (the main grid) with the item card beside it (the
        item under the mouse: name, kind and size, stats, notes, hotbar
        key, hints), then BACKPACK and any other grids (gun belt, ammo
        belt, holster, belt pouches, cell pouch, cell rack) with captions,
        and the HOTBAR along the bottom as labelled key tiles (the one in
        your hands is filled light).
      With a locker, crate or armoury open, it shows on the right with
      its own header (title, Lock / Unclaim or Store all / Take all /
      Empty) and the item card moves next to it. Lockers, crates and
      deposits are a plain grid. Depots (armouries, cabinets, racks) are
      shelves: a tile per item with its kind, stock badge ("12 left",
      OUT, Endless) and a stock bar; tabs filter by group; click a shelf
      to pick it, and the card shows its stock with Take one / Take a
      stack. Out of stock shelves are faded.

    Items: a dark tile with a thin strip on top in the item kind's colour
    (guns blue, ammo amber, medical red, gear green, grenades purple), the
    picture, the name bottom-left and the count / rounds / charge
    bottom-right.

    Drag items to move them, press R while dragging to rotate, drop onto a
    matching stack to merge. Let go anywhere that isn't a grid or slot
    (inside the window too) to drop it on the ground. Drag onto a depot
    to hand it in. Hold Ctrl while starting a drag to take just one off a
    stack. Right-click an item for options (split a stack, equip, wear,
    take off, give, hide, drop; staff: adjust picture). Right-click a
    storage item for a quick take (Ctrl: just one; several queue up).
    Other addons add options with hook Rhylib.ItemMenu(inst, menu) and
    card lines with Rhylib.ItemTooltip(inst, lines).

    Long grid columns (cell rack, ammo belt) and big storages scroll with
    the mouse wheel. Hotbar: 4 slots, 6 with a backpack. Drag an item onto
    a key to put it there, drag it off or right-click the key to empty it.

    One panel paints everything; the only child panel is the model
    preview. The layout is worked out when something it depends on
    changes, not every frame. Nothing runs while the window is closed
    except a key check.

    Client convars: rhylib_inventory_key (default g), rhylib_inventory_cellsize
    (100; cell size in pixels at 1080p, 48-128). The window shrinks itself
    to fit the screen. Lock / Unclaim buttons on an owned locker run hook
    Rhylib.StorageControl("lock" / "unclaim") (rhylib_armoury answers it).
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items
local UI = Rhylib.UI

local MAIN, BACK, SLOT_BACK, EXT, RACK, BELT, HOLSTER = Items.MAIN, Items.BACK, Items.SLOT_BACK, Items.EXT, Items.RACK, Items.BELT, Items.HOLSTER

-- One take from a depot shelf: a stack (one of a gun you may only carry one of).
local function takeAmount(inst)
    local def = Items.Get(inst.id)
    if not def then return 1 end
    if Items.Unique and Items.Unique(def) then return 1 end
    return def.stack or 1
end

-- Gear slot labels, and which side of the model each sits on (2 = right).
local GEAR_LABEL = { kama = "KAMA", pauldron = "PAULDRON", helmet = "HELMET GEAR", holster = "HOLSTER",
    forearm = "FOREARM", comms = "ANTENNA", belt = "BELT POUCHES" }
local GEAR_SIDE = { kama = 1, pauldron = 1, forearm = 1, belt = 1, helmet = 2, comms = 2, holster = 2 }
-- Display order down each side (any other gear slot after these).
local GEAR_ORDER = {}
do
    local want, seen = { "kama", "pauldron", "forearm", "belt", "helmet", "comms", "holster" }, {}
    for _, slot in ipairs(want) do
        local cid = Items.WORN_BY_SLOT[slot]
        if cid and cid ~= SLOT_BACK then GEAR_ORDER[#GEAR_ORDER + 1] = cid seen[cid] = true end
    end
    for _, cid in ipairs(Items.GEAR_SLOTS) do
        if not seen[cid] then GEAR_ORDER[#GEAR_ORDER + 1] = cid end
    end
end

-- What an item is, by its shelf group.
local KIND = { rifle = "Rifle", carbine = "Carbine", pistol = "Pistol", heavy = "Heavy weapon", shotgun = "Shotgun",
    sniper = "Sniper rifle", grenade = "Grenade", weapon = "Weapon", training = "Training", ammo = "Ammunition",
    medical = "Medical", back = "Back", body = "Body armour", helmet = "Helmet gear", gear = "Equipment", misc = "Item" }
local KIND_CAPS = {}
for g, n in pairs(KIND) do KIND_CAPS[g] = string.upper(n) end

local keyVar = CreateClientConVar("rhylib_inventory_key", "g", true, false, "Key that opens the Rhylib inventory")
local sizeVar = CreateClientConVar("rhylib_inventory_cellsize", "100", true, false, "Inventory cell size in pixels at 1080p (48-128); everything else scales with it. Reopen the inventory to apply.")

local CATEGORY_COLORS = Inv.CATEGORY_COLORS
local Icons = Inv.Icons

-- Colours (the house style).
local C_PAGE = Color(11, 12, 11, 250)
local C_INSET = Color(14, 16, 15)
local C_SIDE = Color(18, 20, 19)
local C_CARD = Color(22, 25, 23)
local C_TILE = Color(26, 30, 27)
local C_EDGE = Color(0, 0, 0)
local C_BORDER = Color(42, 45, 41)
local C_BORDER2 = Color(47, 51, 46)
local C_FAINT = Color(31, 35, 32)
local C_MODEL = Color(22, 27, 24)
local C_TEXT = Color(228, 227, 220)
local C_DIM = Color(169, 168, 160)
local C_LABEL = Color(138, 140, 132)
local C_OFF = Color(111, 116, 109)
local C_TABTEXT = Color(201, 200, 192)
local C_DARK = Color(20, 20, 19)
local C_BLUE = Color(133, 183, 235)
local C_AMBER = Color(239, 159, 39)
local C_RED = Color(226, 75, 74)
local C_GREEN = Color(151, 196, 89)
local C_PURPLE = Color(164, 110, 224)
local C_GREYBAR = Color(58, 64, 59)
local C_DANGER_EDGE = Color(90, 42, 42)
local C_DANGER_TEXT = Color(240, 149, 149)
local C_HOVER_EDGE = Color(74, 80, 74)
local C_TEXT_EDGE = Color(0, 0, 0, 200)
local C_NOTE = Color(239, 159, 39)
local C_QUICK_BACK = Color(0, 0, 0, 170)

local scratch = Color(0, 0, 0)
-- surface.SetDrawColor with an extra alpha, without a new Color.
local function setCol(col, a)
    scratch.r, scratch.g, scratch.b, scratch.a = col.r, col.g, col.b, (col.a or 255) * (a or 255) / 255
    surface.SetDrawColor(scratch)
end

-- A dashed outline (empty slots, drop targets).
local function dashed(x, y, w, h, dash, t)
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    local step = dash * 2
    for i = 0, w - 1, step do
        local l = math.min(dash, w - i)
        surface.DrawRect(x + i, y, l, t)
        surface.DrawRect(x + i, y + h - t, l, t)
    end
    for i = 0, h - 1, step do
        local l = math.min(dash, h - i)
        surface.DrawRect(x, y + i, t, l)
        surface.DrawRect(x + w - t, y + i, t, l)
    end
end

local function ctrlDown()
    return input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
end

-- Cut text to fit a width, cached per font and width (no strings made
-- once it has been measured).
local fitCache = {}
local function fitText(text, font, maxW)
    maxW = math.floor(maxW)
    local byFont = fitCache[font]
    if not byFont then byFont = {} fitCache[font] = byFont end
    local byW = byFont[maxW]
    if not byW then byW = {} byFont[maxW] = byW end
    local cached = byW[text]
    if cached then return cached end
    surface.SetFont(font)
    local out = text
    if surface.GetTextSize(text) > maxW then
        out = ""
        for i = #text - 1, 1, -1 do
            -- (cut only between characters: the next byte must not be a UTF-8 continuation)
            local nb = string.byte(text, i + 1)
            if not (nb and nb >= 128 and nb < 192) then
                local try = string.sub(text, 1, i) .. "…"
                if surface.GetTextSize(try) <= maxW then out = try break end
            end
        end
    end
    byW[text] = out
    return out
end

-- Small number strings, made once.
local STR_X, STR_PCT, STR_LEFT, STR_ROUNDS, STR_SIZE, STR_N, STR_CARRY = {}, {}, {}, {}, {}, {}, {}
local function strX(n) local v = STR_X[n] if not v then v = "x" .. n STR_X[n] = v end return v end
local function strPct(n) local v = STR_PCT[n] if not v then v = n .. "%" STR_PCT[n] = v end return v end
local function strN(n) local v = STR_N[n] if not v then v = tostring(n) STR_N[n] = v end return v end
local function strLeft(n)
    local v = STR_LEFT[n]
    if not v then v = n >= 255 and "255+ left" or (n .. " left") STR_LEFT[n] = v end
    return v
end
local function strRounds(a, b)
    local t = STR_ROUNDS[b]
    if not t then t = {} STR_ROUNDS[b] = t end
    local v = t[a]
    if not v then v = a .. "/" .. b t[a] = v end
    return v
end
local function strSize(def)
    local v = STR_SIZE[def.id]
    if not v then v = def.w .. " × " .. def.h STR_SIZE[def.id] = v end
    return v
end

-- An item's kind word and its strip colour.
local function kindOf(def)
    local g = Items.GroupOf(def)
    return KIND[g] or (def.weapon and "Weapon" or "Item"), g
end
local function stripeOf(def)
    if Items.GroupOf(def) == "grenade" then return C_PURPLE end
    return (CATEGORY_COLORS[def.category] or CATEGORY_COLORS.misc).stripe
end

-- The most a counted depot keeps of an item (rhylib_logistics), or nil.
local function stockMax(id)
    local L = Rhylib.Logistics
    if L and L.StockMax then return L.StockMax(id) end
end

-- Words wrapped to a width, appended to out as { t, col, font }.
local function wrapInto(out, text, font, maxW, col)
    if not text or text == "" then return end
    surface.SetFont(font)
    local line
    for word in string.gmatch(text, "%S+") do
        local try = line and (line .. " " .. word) or word
        if line and surface.GetTextSize(try) > maxW then
            out[#out + 1] = { t = line, col = col, font = font }
            line = word
        else
            line = try
        end
    end
    if line then out[#out + 1] = { t = line, col = col, font = font } end
end

--------------------------------------------------------------------------
-- Model preview
--------------------------------------------------------------------------

local function setupModel(mdl)
    local ply = LocalPlayer()
    mdl:SetModel(ply:GetModel())
    local ent = mdl.Entity
    if not IsValid(ent) then return end

    ent:SetSkin(ply:GetSkin())
    ent.GetPlayerColor = function() return ply:GetPlayerColor() end
    local seq = ent:LookupSequence("idle_all_01")
    if seq and seq > 0 then ent:SetSequence(seq) end

    mdl.camHeight = nil   -- (camera worked out for the panel's size in Think)
end

-- Camera so the model fills about 95% of the panel's height. The FOV is
-- horizontal, so a tall panel sees more vertically: scale by its aspect.
local function fitCamera(mdl)
    local ent = mdl.Entity
    if not IsValid(ent) then return end
    local pw, ph = mdl:GetSize()
    if pw < 2 or ph < 2 then return end
    if mdl.camW == pw and mdl.camH == ph and mdl.camMdl == ent:GetModel() then return end
    mdl.camW, mdl.camH, mdl.camMdl = pw, ph, ent:GetModel()
    local mn, mx = ent:GetRenderBounds()
    local centre = (mn + mx) * 0.5
    local height = mx.z - mn.z
    local fov = 40
    local tanV = math.tan(math.rad(fov * 0.5)) * ph / pw
    local dist = height * 0.5 / (tanV * 0.95)
    mdl:SetFOV(fov)
    mdl:SetLookAt(centre)
    mdl:SetCamPos(centre + Vector(dist, 0, 0))
end

local function createModelPanel(parent)
    local mdl = vgui.Create("DModelPanel", parent)
    mdl.yaw = 20
    mdl.ang = Angle(0, 20, 0)
    setupModel(mdl)

    function mdl:LayoutEntity(ent)
        if self.dragging then
            local x = gui.MouseX()
            self.yaw = self.yaw + (x - self.lastX) * 0.6
            self.lastX = x
        end
        self.ang.y = self.yaw
        ent:SetAngles(self.ang)
        self:RunAnimation()
    end

    function mdl:OnMousePressed(code)
        if code ~= MOUSE_LEFT then return end
        self.dragging = true
        self.lastX = gui.MouseX()
        self:MouseCapture(true)
    end

    function mdl:OnMouseReleased()
        self.dragging = false
        self:MouseCapture(false)
    end

    function mdl:Think()
        local ply = LocalPlayer()
        if self:GetModel() ~= ply:GetModel() then setupModel(self) self.camW = nil self.hairCol = nil end
        fitCamera(self)
        -- Bodygroups follow the player's (worn gear, rhylib_gear).
        local ent = self.Entity
        if IsValid(ent) then
            for i = 0, ply:GetNumBodyGroups() - 1 do
                local v = ply:GetBodygroup(i)
                if ent:GetBodygroup(i) ~= v then ent:SetBodygroup(i, v) end
            end
            if ent:GetSkin() ~= ply:GetSkin() then ent:SetSkin(ply:GetSkin()) end
            -- Hair colour (rhylib_roster looks).
            local R = Rhylib.Roster
            local col = ply:GetNW2Bool("rhylib_helmetOff", false) and ply:GetNW2Int("rhylib_haircol", 0) or 0
            if R and R.ApplyHairColour and self.hairCol ~= col then
                self.hairCol = col
                R.ApplyHairColour(ent, col)
            end
        end
    end

    return mdl
end

--------------------------------------------------------------------------
-- Window: sizes and layout
--------------------------------------------------------------------------

local PANEL = {}

-- PANEL:SetScaleK(k): every size from the cell size (k = cell / 64 px at
-- 1080p), scaled again by screen height.
function PANEL:SetScaleK(k)
    self.k = k
    local s = ScrH() / 1080 * k
    self.s = s
    local function px(n) return math.floor(n * s) end
    self.cell = px(64)
    self.gap = math.max(2, px(4))
    self.step = self.cell + self.gap
    self.pad = px(18)
    self.header = px(64)
    self.cap = px(22)          -- caption row above a grid
    self.colGap = px(22)
    self.rowGap = px(16)
    self.tileW = px(92)        -- gear tiles
    self.tileH = px(60)
    self.tileGap = px(8)
    self.cardW = px(256)
    self.hbH = px(46)
    self.hbGap = px(6)
    self.footer = px(26)
    self.shelfW = px(148)
    self.shelfH = px(124)
    self.shelfGap = px(10)
    self.extHead = px(54)
    self.chipH = px(28)
    self.btnH = px(38)
    self.combineH = px(30)
end

function PANEL:Init()
    self.baseK = math.Clamp(sizeVar:GetFloat(), 48, 128) / 64  -- 128 still fits a 16:9 screen
    self:SetScaleK(self.baseK)
    self.drag = nil
    self.rDown = false
    self.refs, self.refGear = {}, {}
    self.buttons, self.nb = {}, 0
    self.hbInfo = {}
    self.scroll = {}
    self.model = createModelPanel(self)
    self:Relayout()
end

function PANEL:Font(size, weight)
    return UI.Font(math.max(9, math.Round(size * self.k)), weight)
end

function PANEL:SpanPx(n)
    return n * self.cell + (n - 1) * self.gap
end

-- A gear slot shows if your model can show something in it, or it holds
-- something (rhylib_gear; without it, every slot that exists).
local function gearShown(cid)
    local c = Inv.cont[cid]
    if not c then return false end
    local G = Rhylib.Gear
    if not (G and G.ModelHas) or next(c.items) then return true end
    return G.ModelHas(LocalPlayer(), Items.WORN[cid].slot) and true or false
end

-- Containers the layout depends on (their tables are replaced when their
-- size changes, so comparing the table is enough).
local WATCH = { MAIN, BACK, SLOT_BACK, EXT, RACK, BELT, HOLSTER, Items.POUCH, Items.CELLPACK, Items.CELLBELT, Items.GUNBELT }
for _, cid in ipairs(Items.GEAR_SLOTS) do WATCH[#WATCH + 1] = cid end

local function depotCount()
    local c = Inv.cont[EXT]
    if not (c and Inv.ext and Inv.ext.depot) then return 0 end
    local n = 0
    for _ in pairs(c.items) do n = n + 1 end
    return n
end
-- A cheap signature of the depot's uid set (a shelf swapped for another
-- with the same count changes it).
local function depotSig()
    local c = Inv.cont[EXT]
    if not (c and Inv.ext and Inv.ext.depot) then return 0 end
    local sum = 0
    for uid in pairs(c.items) do sum = sum + uid * (uid % 97 + 1) end
    return sum
end

-- PANEL:LayoutDirty(): has anything the layout depends on changed?
function PANEL:LayoutDirty()
    local refs = self.refs
    for i = 1, #WATCH do
        local cid = WATCH[i]
        if Inv.cont[cid] ~= refs[cid] then return true end
    end
    if Inv.ext ~= self.refExt then return true end
    if LocalPlayer():GetModel() ~= self.refModel then return true end
    if depotCount() ~= self.refDepot or depotSig() ~= self.refDepotSig then return true end
    local now = RealTime()
    if now >= (self.gearCheck or 0) then
        self.gearCheck = now + 0.25
        for _, cid in ipairs(Items.GEAR_SLOTS) do
            if gearShown(cid) ~= self.refGear[cid] then return true end
        end
    end
    return false
end

function PANEL:RememberLayout()
    for i = 1, #WATCH do self.refs[WATCH[i]] = Inv.cont[WATCH[i]] end
    self.refExt = Inv.ext
    self.refModel = LocalPlayer():GetModel()
    self.refDepot = depotCount()
    self.refDepotSig = depotSig()
    for _, cid in ipairs(Items.GEAR_SLOTS) do self.refGear[cid] = gearShown(cid) end
end

-- Works out where everything sits and sizes the window; with a storage
-- open on a narrow screen it goes compact first, then shrinks the cells.
function PANEL:Relayout()
    self.compact = false
    if self.baseK and self.k ~= self.baseK then self:SetScaleK(self.baseK) end
    self:LayoutOnce()
    local maxW, maxH = ScrW() * 0.98, ScrH() * 0.98
    local w, h = self:GetWide(), self:GetTall()
    if (w > maxW or h > maxH) and Inv.cont[EXT] and Inv.ext then
        self.compact = true
        self:LayoutOnce()
        w, h = self:GetWide(), self:GetTall()
    end
    if w > maxW or h > maxH then
        local f = math.min(maxW / w, maxH / h)
        self:SetScaleK(math.max(0.4, self.k * f * 0.99))
        self:LayoutOnce()
    end
    self.cardData = nil
end

-- Captions for the extra grids: title, note.
local GRID_CAPTION = {
    [BACK] = { "BACKPACK" },
    [Items.GUNBELT] = { "GUN BELT", "no long guns" },
    [BELT] = { "AMMO BELT", "no rifles or launchers" },
    [HOLSTER] = { "HOLSTER", "pistols only" },
    [Items.POUCH] = { "BELT POUCHES", "no rifles or launchers" },
    [Items.CELLPACK] = { "CELL POUCH", "power cells only" },
    [RACK] = { "CELL RACK", "power cells only" },
}
local FLOW = { BACK, Items.GUNBELT, BELT, HOLSTER, Items.POUCH, Items.CELLPACK, RACK }

function PANEL:LayoutOnce()
    self:RememberLayout()
    local s = self.s
    local pad, cap, cell = self.pad, self.cap, self.cell
    local hasExt = Inv.cont[EXT] ~= nil and Inv.ext ~= nil
    local main = Inv.cont[MAIN] or { w = 6, h = 3 }
    local top = self.header + pad
    self.top = top
    self.regions = {}
    self.hasExt = hasExt
    self.cardW = math.floor((self.compact and 220 or 256) * s)

    ------------------------------------------------------------------
    -- Worn column
    local hasGear = false
    for _, cid in ipairs(Items.GEAR_SLOTS) do if Inv.cont[cid] then hasGear = true end end
    local tileW, tileH, tg = hasGear and self.tileW or 0, self.tileH, self.tileGap
    local modelW = math.floor((self.compact and 120 or (hasExt and 150 or 180)) * s)
    local sideW = hasGear and (tileW + tg) or 0
    -- (wide enough for the Back slot, 2 cells at least, beside the belt cell pouch)
    local cb = Inv.cont[Items.CELLBELT]
    local pouchMin = cb and (self:SpanPx(cb.w) + self.gap * 4) or 0
    local backMin = self:SpanPx(2)
    local needInner = backMin + (cb and (pouchMin + tg) or 0)
    if modelW + sideW * 2 < needInner then modelW = needInner - sideW * 2 end
    local wornW = pad * 2 + modelW + sideW * 2
    self.wornW = wornW
    local innerW = wornW - pad * 2
    local tilesTop = top + cap

    local sides = { {}, {} }
    self.helmetRect = nil
    local G = Rhylib.Gear
    if hasGear and G and G.ModelInfo and G.ModelInfo(LocalPlayer()).groups.helmet then
        self.helmetRect = { helmet = true, pw = tileW, ph = tileH }
        sides[2][1] = self.helmetRect
    end
    for _, cid in ipairs(GEAR_ORDER) do
        if gearShown(cid) then
            local slot = Items.WORN[cid].slot
            local side = GEAR_SIDE[slot] or 1
            local r = { cid = cid, slot = true, gear = true, pw = tileW, ph = tileH,
                title = Items.WORN[cid].title, label = GEAR_LABEL[slot] or string.upper(Items.WORN[cid].title) }
            self.regions[#self.regions + 1] = r
            local list = sides[side]
            list[#list + 1] = r
        end
    end
    local nMax = math.max(#sides[1], #sides[2])
    local tilesH = nMax > 0 and (nMax * (tileH + tg) - tg) or 0

    -- Back slot and the belt cell pouch under the model.
    local pouchH = cb and (cap + self:SpanPx(cb.h) + self.gap * 3) or 0
    local backRowH = math.max(math.floor(64 * s), pouchH)
    local wornFixed = cap + self.rowGap + backRowH + self.rowGap + self.combineH
    local wornNat = wornFixed + math.max(tilesH, self:SpanPx(4))

    ------------------------------------------------------------------
    -- Own grids
    local ownX = wornW + self.colGap
    self.ownX = ownX
    local pocketsW, pocketsH = self:SpanPx(main.w), cap + self:SpanPx(main.h)
    self.regions[#self.regions + 1] = { cid = MAIN, x = ownX, baseY = top + cap, gw = main.w, gh = main.h, col = "own",
        caption = "POCKETS", note = main.w .. " × " .. main.h }
    local rowW = pocketsW
    local firstH = pocketsH
    self.cardRect = nil
    if not hasExt then
        local ch = math.max(pocketsH, math.floor(200 * s))
        self.cardRect = { x = ownX + pocketsW + self.colGap, baseY = top, w = self.cardW, h = ch, col = "own" }
        rowW = pocketsW + self.colGap + self.cardW
        firstH = ch
    end
    local list = {}
    local flowW = rowW
    for _, cid in ipairs(FLOW) do
        local c = Inv.cont[cid]
        if c then
            list[#list + 1] = cid
            flowW = math.max(flowW, self:SpanPx(c.w))
        end
    end
    local pm = Rhylib.Config.Get("inventory", "backpackWeightMult")
    local fx, fy, rowH = ownX, top + firstH + self.rowGap, 0
    local ownBottom = top + firstH
    self.noPack = nil
    if not Inv.cont[BACK] then
        -- (a dim note where the backpack grid would be)
        self.noPack = { x = fx, baseY = fy + math.floor(cap * 0.5) }
        fy = fy + cap + self.rowGap
        ownBottom = fy - self.rowGap
    end
    for _, cid in ipairs(list) do
        local c = Inv.cont[cid]
        local w, h = self:SpanPx(c.w), cap + self:SpanPx(c.h)
        if fx > ownX and fx + w > ownX + flowW then
            fx, fy, rowH = ownX, fy + rowH + self.rowGap, 0
        end
        local capt = GRID_CAPTION[cid]
        local note = capt[2]
        if cid == BACK then
            note = c.w .. " × " .. c.h .. ((pm and pm ~= 1) and (" · contents count at " .. math.Round(pm * 100) .. "%") or "")
        end
        self.regions[#self.regions + 1] = { cid = cid, x = fx, baseY = fy + cap, gw = c.w, gh = c.h, col = "own",
            caption = capt[1], note = note, accent = cid == BACK }
        fx = fx + w + self.colGap
        rowH = math.max(rowH, h)
        ownBottom = fy + rowH
    end
    local ownW = flowW
    local ownContent = ownBottom - top

    -- The tallest a column may be on this screen.
    local below = self.rowGap + cap + self.hbH + math.floor(self.rowGap * 0.5) + self.footer
    local screenMax = math.max(self:SpanPx(3), math.floor(ScrH() * 0.98) - top - below)

    ------------------------------------------------------------------
    -- Storage
    local extNat = 0
    local ext = Inv.cont[EXT]
    self.extRect = nil
    self.tabs = nil
    if hasExt then
        local extX = ownX + ownW + self.colGap * 2
        local depot = Inv.ext.depot
        local bodyW
        local r = { cid = EXT, col = "ext" }
        if depot then
            local n = math.max(1, depotCount())
            local cols = math.Clamp(n, 1, self.compact and 2 or 3)
            bodyW = cols * self.shelfW + (cols - 1) * self.shelfGap
            r.shelves, r.shelfCols, r.pw = true, cols, bodyW
        else
            bodyW = self:SpanPx(ext.w)
            r.gw, r.gh = ext.w, ext.h
        end
        local extW = bodyW + self.colGap + self.cardW
        -- Group tabs (depots with more than one group).
        local bodyTop = top + self.extHead + self.rowGap
        if depot then
            local counts, order = {}, {}
            for _, inst in pairs(ext.items) do
                local g = Items.GroupOf(Items.defs[inst.id])
                if not counts[g] then counts[g] = 0 order[#order + 1] = g end
                counts[g] = counts[g] + 1
            end
            if #order > 1 then
                table.sort(order, function(a, b) return Items.GroupRank(a) < Items.GroupRank(b) end)
                local tabs = { { g = false, label = "All", n = strN(depotCount()) } }
                for _, g in ipairs(order) do tabs[#tabs + 1] = { g = g, label = Items.GROUP_NAMES[g] or g, n = strN(counts[g]) } end
                local tf, nf = self:Font(13, 600), self:Font(11)
                local tx, ty = extX, bodyTop
                local cpad = math.floor(12 * s)
                for _, t in ipairs(tabs) do
                    surface.SetFont(tf)
                    local lw = surface.GetTextSize(t.label)
                    surface.SetFont(nf)
                    local nw = surface.GetTextSize(t.n)
                    t.w = cpad * 2 + lw + math.floor(7 * s) + nw
                    if tx > extX and tx + t.w > extX + extW then tx, ty = extX, ty + self.chipH + self.gap * 2 end
                    t.x, t.y = tx, ty
                    tx = tx + t.w + self.gap * 2
                end
                self.tabs = tabs
                bodyTop = ty + self.chipH + self.rowGap
                if self.shelfTab and not counts[self.shelfTab] then self.shelfTab = nil end
            else
                self.shelfTab = nil
            end
        end
        r.x, r.baseY = extX, bodyTop
        self.regions[#self.regions + 1] = r
        self.extRegion = r
        self.extRect = { x = extX, y = top, w = extW, bodyTop = bodyTop, bodyW = bodyW }
        local extContent = depot and 0 or self:SpanPx(ext.h)
        if depot then
            -- (sized for every shelf, so picking a tab never shrinks the view)
            local rows = math.max(1, math.ceil(depotCount() / r.shelfCols))
            extContent = rows * (self.shelfH + self.shelfGap) - self.shelfGap
        end
        self.cols = { ext = { x = extX, w = bodyW, top = bodyTop, view = 0, content = extContent } }
        extNat = (bodyTop - top) + math.min(extContent, screenMax - (bodyTop - top))
        self.width = extX + extW + pad
    else
        self.cols = {}
        self.extRegion = nil
        self.width = ownX + ownW + pad
    end

    ------------------------------------------------------------------
    -- Heights
    local contentH = math.max(wornNat, math.min(ownContent, screenMax), extNat)
    -- (tabs that wrap on a short screen: still room for the shelves and the card)
    if self.cols.ext then contentH = math.max(contentH, self.cols.ext.top - top + self:SpanPx(3)) end
    self.contentH = contentH
    self.cols.own = { x = ownX, w = ownW, top = top, view = math.min(ownContent, contentH), content = ownContent }
    if self.cols.ext then
        local ec = self.cols.ext
        ec.view = math.max(self.extRegion.shelves and self.shelfH or self.cell, math.min(ec.content, top + contentH - ec.top))
        self.extRect.cardH = top + contentH - ec.top
    end
    for k, c in pairs(self.cols) do
        self.scroll[k] = math.Clamp(self.scroll[k] or 0, 0, math.max(0, c.content - c.view))
    end

    -- Worn column positions: tiles down both sides of the model, the
    -- model filling the height between them.
    local bodyH = contentH - wornFixed
    local modelX = pad + sideW
    self.modelRect = { x = modelX, y = tilesTop, w = modelW, h = bodyH }
    self.model:SetPos(modelX, tilesTop)
    self.model:SetSize(modelW, bodyH)
    for side = 1, 2 do
        local x = side == 1 and pad or (modelX + modelW + tg)
        for i, r in ipairs(sides[side]) do
            r.x, r.y = x, tilesTop + (i - 1) * (tileH + tg)
        end
    end
    local backY = tilesTop + bodyH + self.rowGap
    local pouchW = 0
    if cb then
        pouchW = math.min(math.max(pouchMin, math.floor(innerW * 0.42)), innerW - tg - backMin)
        local px = pad + innerW - pouchW
        self.pouchBox = { x = px, y = backY, w = pouchW, h = backRowH }
        self.regions[#self.regions + 1] = { cid = Items.CELLBELT, x = px + self.gap * 2, y = backY + cap + self.gap,
            gw = cb.w, gh = cb.h }
    else
        self.pouchBox = nil
    end
    table.insert(self.regions, 1, { cid = SLOT_BACK, slot = true, back = true, x = pad, y = backY,
        pw = innerW - (cb and (pouchW + tg) or 0), ph = backRowH, title = "Back", label = "BACK" })
    self.combineRect = { x = pad, y = backY + backRowH + self.rowGap, w = innerW, h = self.combineH }

    ------------------------------------------------------------------
    -- Hotbar along the bottom, from the grids' left edge.
    self.hotbarN = Items.HotbarSize(Inv)
    local n = self.hotbarN
    local width = self.width
    local avail = width - pad - ownX
    local hbW = math.floor((avail - (n - 1) * self.hbGap) / n)
    hbW = math.Clamp(hbW, math.floor(96 * s), math.floor(170 * s))
    width = math.max(width, ownX + n * hbW + (n - 1) * self.hbGap + pad)
    self.hbW = hbW
    self.hotbarX = ownX
    self.hotbarY = top + contentH + self.rowGap + cap
    self.width = width

    self:SetSize(width, self.hotbarY + self.hbH + math.floor(self.rowGap * 0.5) + self.footer)
    self:Center()  -- stays centred when a grid appears or disappears

    self:RebuildShelves()
    self:ApplyScroll()
end

-- Depot shelves in order (the server's layout: group by group), filtered
-- by the picked tab. r.list = uids; self.shelfIdx[uid] = place.
function PANEL:RebuildShelves()
    local r = self.extRegion
    self.shelfIdx = {}
    self.shelfMax = {}
    if not (r and r.shelves) then return end
    local c = Inv.cont[EXT]
    local list = {}
    for uid, inst in pairs(c and c.items or {}) do
        if not self.shelfTab or Items.GroupOf(Items.defs[inst.id]) == self.shelfTab then list[#list + 1] = uid end
    end
    table.sort(list, function(a, b)
        local ia, ib = c.items[a], c.items[b]
        if ia.y ~= ib.y then return ia.y < ib.y end
        return ia.x < ib.x
    end)
    r.list = list
    for i, uid in ipairs(list) do
        self.shelfIdx[uid] = i
        self.shelfMax[uid] = stockMax(c.items[uid].id)
    end
    local ec = self.cols.ext
    if ec then
        local rows = math.max(1, math.ceil(#list / r.shelfCols))
        ec.content = rows * (self.shelfH + self.shelfGap) - self.shelfGap
        self.scroll.ext = math.Clamp(self.scroll.ext or 0, 0, math.max(0, ec.content - ec.view))
        self:ApplyScroll()
    end
end

-- Scrolled columns: where each region is drawn right now.
function PANEL:ApplyScroll()
    for _, r in ipairs(self.regions or {}) do
        if r.col then r.y = r.baseY - (self.scroll[r.col] or 0) end
    end
    local cr = self.cardRect
    if cr then cr.y = cr.baseY - (self.scroll.own or 0) end
    local np = self.noPack
    if np then np.y = np.baseY - (self.scroll.own or 0) end
end

function PANEL:OnMouseWheeled(delta)
    local mx = self:CursorPos()
    for k, c in pairs(self.cols or {}) do
        if mx >= c.x - self.pad and mx <= c.x + c.w + self.pad and c.content > c.view then
            self.scroll[k] = math.Clamp((self.scroll[k] or 0) - delta * self.step, 0, c.content - c.view)
            self:ApplyScroll()
            return true
        end
    end
end

-- Where shelf i sits (panel coordinates).
function PANEL:ShelfPos(r, i)
    local col = (i - 1) % r.shelfCols
    local row = math.floor((i - 1) / r.shelfCols)
    return r.x + col * (self.shelfW + self.shelfGap), r.y + row * (self.shelfH + self.shelfGap)
end

-- PANEL:HitTest(mx, my, margin): region and cell under panel coordinates
-- (shelves: region, shelf number or nil). Grids allow a small margin so
-- items can be dragged against the edge.
function PANEL:HitTest(mx, my, margin)
    margin = margin or 0
    for _, r in ipairs(self.regions) do
        local c = r.col and self.cols and self.cols[r.col]
        if c and (my < c.top - margin or my > c.top + c.view + margin) then
            -- (scrolled out of view)
        elseif r.slot then
            if r.x and mx >= r.x and mx <= r.x + r.pw and my >= r.y and my <= r.y + r.ph then
                return r, 0, 0
            end
        elseif r.shelves then
            if mx >= r.x - margin and mx <= r.x + r.pw + margin and my >= c.top - margin and my <= c.top + c.view + margin then
                local col = math.floor((mx - r.x) / (self.shelfW + self.shelfGap))
                local row = math.floor((my - r.y) / (self.shelfH + self.shelfGap))
                local inX = mx - r.x - col * (self.shelfW + self.shelfGap) <= self.shelfW
                local inY = my - r.y - row * (self.shelfH + self.shelfGap) <= self.shelfH
                local i = row * r.shelfCols + col + 1
                if col >= 0 and col < r.shelfCols and row >= 0 and inX and inY and r.list and r.list[i] then
                    return r, i, 0
                end
                return r, nil, 0
            end
        else
            local pw, ph = self:SpanPx(r.gw), self:SpanPx(r.gh)
            if mx >= r.x - margin and mx <= r.x + pw + margin and my >= r.y - margin and my <= r.y + ph + margin then
                return r, math.floor((mx - r.x) / self.step), math.floor((my - r.y) / self.step)
            end
        end
    end
end

-- Hotbar slot number under panel coordinates, or nil.
function PANEL:HotbarAt(mx, my)
    if not self.hotbarY or my < self.hotbarY or my > self.hotbarY + self.hbH then return nil end
    local stride = self.hbW + self.hbGap
    local n = math.floor((mx - self.hotbarX) / stride) + 1
    if n < 1 or n > self.hotbarN then return nil end
    if mx - self.hotbarX - (n - 1) * stride > self.hbW then return nil end  -- in the gap
    return n
end

function PANEL:ItemAtCursor()
    local mx, my = self:CursorPos()
    local r, cx, cy = self:HitTest(mx, my)
    if not r then return nil end
    local c = Inv.cont[r.cid]
    if not c then return nil end
    if r.slot then
        local _, inst = next(c.items)
        return inst, r, 0, 0
    end
    if r.shelves then
        local uid = cx and r.list[cx]
        return uid and c.items[uid], r, 0, 0
    end
    return Items.At(c.items, cx, cy), r, cx, cy
end

function PANEL:ItemRect(r, inst)
    if r.slot then return r.x, r.y, r.pw, r.ph end
    if r.shelves then
        local i = self.shelfIdx[inst.uid]
        if not i then return nil end
        local x, y = self:ShelfPos(r, i)
        return x, y, self.shelfW, self.shelfH
    end
    local w, h = Items.Size(inst.id, inst.rot)
    return r.x + inst.x * self.step, r.y + inst.y * self.step, self:SpanPx(w), self:SpanPx(h)
end

--------------------------------------------------------------------------
-- Drawing: item tiles, slots, shelves
--------------------------------------------------------------------------

-- PANEL:DrawItemBox(inst, x, y, pw, ph, alpha, endless, hover): one item
-- tile: dark body, kind strip on top, picture, name bottom-left, count /
-- rounds / charge bottom-right, hotbar key, HIDDEN. endless: depot stock.
function PANEL:DrawItemBox(inst, x, y, pw, ph, alpha, endless, hover)
    local def = Items.Get(inst.id)
    if not def then return end
    local s = self.s
    local pad = math.max(3, math.floor(5 * s))
    local strip = math.max(2, math.floor(3 * s))
    local font = self:Font(12)
    local nameH = draw.GetFontHeight(font)

    -- The picture (cl_15_icons). Its tile is opaque body colour, so while
    -- faded (dragged, ghost) the body goes around it, not under it.
    local ax, ay = x + pad, y + strip + pad
    local aw, ah = pw - pad * 2, ph - strip - pad * 3 - nameH
    local ix, iy, iw, ih
    if aw > 6 and ah > 6 then ix, iy, iw, ih = Icons.Fit(def, ax, ay, aw, ah, inst.rot) end
    setCol(C_TILE, alpha)
    if ix and alpha < 255 then
        surface.DrawRect(x, y, pw, iy - y)
        surface.DrawRect(x, iy + ih, pw, y + ph - iy - ih)
        surface.DrawRect(x, iy, ix - x, ih)
        surface.DrawRect(ix + iw, iy, x + pw - ix - iw, ih)
    else
        surface.DrawRect(x, y, pw, ph)
    end
    if ix then Icons.Draw(def, ax, ay, aw, ah, inst.rot, alpha) end
    setCol(stripeOf(def), alpha)
    surface.DrawRect(x, y, pw, strip)

    local active = LocalPlayer():GetActiveWeapon()
    local held = def.weapon and IsValid(active) and active:GetClass() == def.weapon
    if held or hover then
        setCol(C_BLUE, alpha)
        surface.DrawOutlinedRect(x, y, pw, ph, held and math.max(1, math.floor(2 * s)) or 1)
    else
        setCol(C_BORDER2, alpha)
        surface.DrawOutlinedRect(x, y, pw, ph)
    end

    local corner, cornerCol = nil, C_TEXT
    if endless == "stock" then
        corner = inst.count <= 0 and "OUT" or strLeft(inst.count)
    elseif endless then
        corner = "∞"
    elseif inst.count > 1 then
        corner = strX(inst.count)
    elseif def.rounds and def.rounds > 1 then
        corner = strRounds(math.floor((inst.data.fill or 1) * def.rounds + 0.5), def.rounds)
        cornerCol = C_BLUE
    elseif def.fill and def.rounds == nil then
        corner = strPct(math.ceil((inst.data.fill or 1) * 100))
    end
    local cw = 0
    local cfont = self:Font(12, 700)
    if corner then
        surface.SetFont(cfont)
        cw = surface.GetTextSize(corner) + pad
        draw.SimpleTextOutlined(corner, cfont, x + pw - pad, y + ph - pad, cornerCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, C_TEXT_EDGE)
    end
    local nw = pw - pad * 2 - cw
    if nw > 8 then
        draw.SimpleTextOutlined(fitText(def.name, font, nw), font, x + pad, y + ph - pad, C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, C_TEXT_EDGE)
    end
    if inst.hb and inst.c ~= EXT and inst.c then
        -- Hotbar key, top-left under the strip.
        local kf = self:Font(11, 700)
        local kw = math.floor(15 * s)
        setCol(C_INSET, alpha)
        surface.DrawRect(x + pad - 1, y + strip + pad - 1, kw, kw)
        draw.SimpleText(strN(inst.hb), kf, x + pad - 1 + kw * 0.5, y + strip + pad - 1 + kw * 0.5, C_BLUE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    if inst.data and inst.data.hidden and inst.c ~= EXT then
        draw.SimpleTextOutlined("HIDDEN", self:Font(11, 700), x + pw - pad, y + ph * 0.5, C_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 1, C_TEXT_EDGE)
    end
end

-- A labelled tile (gear slots, Back, helmet): label on top, value under.
-- filled: solid tile, else a dashed outline. a: alpha.
function PANEL:DrawTile(x, y, w, h, label, value, filled, a, valueCol, hover)
    local s = self.s
    local p = math.floor(9 * s)
    if filled then
        setCol(C_TILE, a)
        surface.DrawRect(x, y, w, h)
        setCol(hover and C_BLUE or C_BORDER2, a)
        surface.DrawOutlinedRect(x, y, w, h)
    else
        setCol(hover and C_BLUE or C_BORDER, a)
        dashed(x, y, w, h, math.max(3, math.floor(5 * s)), 1)
    end
    local lf = self:Font(10, 700)
    draw.SimpleText(fitText(label, lf, w - p * 2), lf, x + p, y + p, C_LABEL)
    if value then
        local vf = self:Font(12, 500)
        draw.SimpleText(fitText(value, vf, w - p * 2), vf, x + p, y + h - p, valueCol or (filled and C_TEXT or C_OFF), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end
end

-- A grid caption: TITLE in caps, a dim note after it.
function PANEL:Caption(x, y, w, title, note, accent)
    local tf = self:Font(13, 700)
    draw.SimpleText(title, tf, x, y, accent and C_BLUE or C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if note then
        surface.SetFont(tf)
        local tw = surface.GetTextSize(title) + math.floor(9 * self.s)
        local nf = self:Font(11)
        if w - tw > 20 then
            draw.SimpleText(fitText(note, nf, w - tw), nf, x + tw, y, C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end

function PANEL:PaintGridCells(r, ext)
    local cellCol, edgeCol = ext and C_INSET or C_SIDE, C_FAINT
    local c = r.col and self.cols[r.col]
    local y0, y1 = c and c.top - self.cell or -1e9, c and (c.top + c.view) or 1e9
    for y = 0, r.gh - 1 do
        local cy = r.y + y * self.step
        if cy + self.cell >= y0 and cy <= y1 then
            for x = 0, r.gw - 1 do
                local cx = r.x + x * self.step
                surface.SetDrawColor(cellCol)
                surface.DrawRect(cx, cy, self.cell, self.cell)
                surface.SetDrawColor(edgeCol)
                surface.DrawOutlinedRect(cx, cy, self.cell, self.cell)
            end
        end
    end
end

-- One depot shelf.
function PANEL:DrawShelf(inst, x, y, w, h, sel, hover)
    local def = Items.Get(inst.id)
    if not def then return end
    local s = self.s
    local ext = Inv.ext
    local counted = ext.counted and not (ext.endless and ext.endless[inst.uid])
    local out = counted and inst.count <= 0
    local max = counted and self.shelfMax[inst.uid]
    local share = (not counted) and 1 or (max and math.Clamp(inst.count / max, 0, 1) or (out and 0 or 1))
    local col = out and C_RED or ((max and share < 0.6) and C_AMBER or C_GREEN)
    local a = out and 190 or 255
    local p = math.floor(10 * s)

    -- (the same body as the item pictures, so they don't sit in a box;
    -- picked: blue edge and a blue bar on the left)
    surface.SetDrawColor(C_TILE)
    surface.DrawRect(x, y, w, h)
    setCol((sel or hover) and C_BLUE or C_BORDER, (sel or hover) and 255 or a)
    surface.DrawOutlinedRect(x, y, w, h)
    if sel then
        surface.SetDrawColor(C_BLUE)
        surface.DrawRect(x, y, math.max(2, math.floor(3 * s)), h)
    end

    -- Kind, stock badge.
    local _, g = kindOf(def)
    local kf, bf = self:Font(10, 700), self:Font(12, 700)
    local badge = counted and (out and "OUT" or strLeft(inst.count)) or "Endless"
    surface.SetFont(bf)
    local bw, bh = surface.GetTextSize(badge) + math.floor(12 * s), math.floor(19 * s)
    local bx, by = x + w - p - bw, y + p
    surface.SetDrawColor(out and C_RED or C_INSET)
    surface.DrawRect(bx, by, bw, bh)
    draw.SimpleText(badge, bf, bx + bw * 0.5, by + bh * 0.5, out and C_DARK or (counted and col or C_DIM), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(fitText(KIND_CAPS[g] or string.upper(g), kf, bx - x - p * 2), kf, x + p, by + bh * 0.5, C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    -- Picture.
    local nf, sf = self:Font(14, 700), self:Font(11)
    local nameH = draw.GetFontHeight(nf)
    local barH = math.max(2, math.floor(3 * s))
    local py = by + bh + math.floor(4 * s)
    local ph = y + h - p - barH - math.floor(6 * s) - nameH - math.floor(4 * s) - py
    if ph > 8 then Icons.Draw(def, x + p, py, w - p * 2, ph, false, out and 110 or 255) end

    -- Name, size, bar.
    local ny = y + h - p - barH - math.floor(6 * s)
    local size = strSize(def)
    surface.SetFont(sf)
    local sw = surface.GetTextSize(size)
    draw.SimpleText(size, sf, x + w - p, ny, C_LABEL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(fitText(def.name, nf, w - p * 3 - sw), nf, x + p, ny, out and C_OFF or C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    local barY = y + h - p - barH
    surface.SetDrawColor(C_INSET)
    surface.DrawRect(x + p, barY, w - p * 2, barH)
    surface.SetDrawColor(counted and col or C_GREYBAR)
    surface.DrawRect(x + p, barY, math.floor((w - p * 2) * share), barH)
end

function PANEL:PaintRegion(r, dragUid)
    local c = Inv.cont[r.cid]
    if not c then return end
    local s = self.s
    local _, worn = next(c.items)
    local hoverInst = self.hoverInst

    if r.slot and r.gear then
        -- A gear slot: dim if your model can't show it.
        local G = Rhylib.Gear
        local can = not (G and G.ModelHas) or G.ModelHas(LocalPlayer(), Items.WORN[r.cid].slot)
        local def = worn and Items.defs[worn.id]
        -- (a gear part the model can't show: worn, but greyed and doing nothing)
        local unseen = worn and not Items.CanWear(LocalPlayer(), def)
        local dragged = worn and dragUid == worn.uid and self.drag and not self.drag.fromExt
        local a = ((not can and not worn) or dragged) and 110 or 255
        local value = def and def.name or (can and "Empty" or "N/A")
        self:DrawTile(r.x, r.y, r.pw, r.ph, r.label, value, worn ~= nil, a, (unseen or dragged) and C_OFF or nil, worn and hoverInst == worn)
        if def then
            setCol(stripeOf(def), a)
            surface.DrawRect(r.x, r.y, r.pw, math.max(2, math.floor(2 * s)))
        end
        return
    elseif r.slot then
        -- Back slot.
        local def = worn and Items.defs[worn.id]
        local dragged = worn and dragUid == worn.uid and self.drag and not self.drag.fromExt
        local value = def and def.name or "Empty"
        self:DrawTile(r.x, r.y, r.pw, r.ph, r.label, value, worn ~= nil, dragged and 110 or 255, dragged and C_OFF or nil, worn and hoverInst == worn)
        if def then
            setCol(stripeOf(def), dragged and 110 or 255)
            surface.DrawRect(r.x, r.y, r.pw, math.max(2, math.floor(2 * s)))
            if def.carry then
                local ct = STR_CARRY[def.id]
                if not ct then ct = "+" .. def.carry .. " kg carry" STR_CARRY[def.id] = ct end
                local p = math.floor(9 * s)
                draw.SimpleText(ct, self:Font(11), r.x + r.pw - p, r.y + p, C_DIM, TEXT_ALIGN_RIGHT)
            end
        end
        return
    elseif r.shelves then
        local list = r.list
        local col = self.cols.ext
        if not (list and col) then return end
        local sel = self.selExt
        for i = 1, #list do
            local uid = list[i]
            local inst = c.items[uid]
            if inst then
                local x, y = self:ShelfPos(r, i)
                if y + self.shelfH >= col.top and y <= col.top + col.view then
                    self:DrawShelf(inst, x, y, self.shelfW, self.shelfH, sel == uid, hoverInst == inst)
                end
            end
        end
        self:PaintQuick(r, c)
        return
    end

    local isExt = r.cid == EXT
    self:PaintGridCells(r, isExt)
    if r.caption then
        self:Caption(r.x, r.y - self.cap * 0.5, self:SpanPx(r.gw) + math.floor(self.colGap * 0.6), r.caption, r.note, r.accent)
    end

    for uid, inst in pairs(c.items) do
        local x, y, pw, ph = self:ItemRect(r, inst)
        local dragged = dragUid == uid and self.drag and (self.drag.fromExt == isExt)
        self:DrawItemBox(inst, x, y, pw, ph, dragged and 70 or 255, nil, hoverInst == inst)
    end
    if isExt then self:PaintQuick(r, c) end
end

--------------------------------------------------------------------------
-- Right-click quick take: a short bar on the item, then it's taken.
-- Several right-clicks queue up (Ctrl: just one).
--------------------------------------------------------------------------

local QUICK_TIME = 0.35

function PANEL:QueueQuick(inst, single)
    self.quick = self.quick or {}
    if #self.quick >= 12 then return end
    self.quick[#self.quick + 1] = { uid = inst.uid, single = single }
    if #self.quick == 1 then
        self.quickStart = RealTime()
        surface.PlaySound("ui/buttonrollover.wav")
    end
end

function PANEL:ThinkQuick()
    local q = self.quick
    if not q or #q == 0 then return end
    local c = Inv.cont[EXT]
    local head = q[1]
    local inst = c and c.items[head.uid]
    if not inst or RealTime() - self.quickStart >= QUICK_TIME then
        if inst then Inv.RequestQuickTake(inst, head.single) end
        table.remove(q, 1)
        self.quickStart = RealTime()
    end
    if not c then self.quick = nil end
end

function PANEL:PaintQuick(r, c)
    local q = self.quick
    if not q or #q == 0 then return end
    local s = self.s
    for i, job in ipairs(q) do
        local inst = c.items[job.uid]
        if inst then
            local x, y, pw, ph = self:ItemRect(r, inst)
            if x then
                local bh = math.max(3, math.floor(5 * s))
                local by = y + ph - bh - math.floor(3 * s)
                local bx, bw = x + math.floor(4 * s), pw - math.floor(8 * s)
                surface.SetDrawColor(C_QUICK_BACK)
                surface.DrawRect(bx, by, bw, bh)
                local f = i == 1 and math.Clamp((RealTime() - self.quickStart) / QUICK_TIME, 0, 1) or 0
                surface.SetDrawColor(C_BLUE)
                surface.DrawRect(bx, by, bw * f, bh)
                if i > 1 then
                    setCol(C_BLUE, 90)
                    surface.DrawOutlinedRect(bx, by, bw, bh)
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Buttons (drawn in Paint, remembered for OnMousePressed). fn(self, arg).
--------------------------------------------------------------------------

-- style: "primary" (filled blue), "danger" (red outline), else secondary.
function PANEL:Btn(x, y, w, h, text, fn, arg, enabled, style)
    local mx, my = self:CursorPos()
    local on = enabled ~= false
    local hover = on and mx >= x and mx <= x + w and my >= y and my <= y + h
    local a = on and 255 or 90
    local font = self:Font(13, style == "primary" and 700 or 500)
    if style == "primary" then
        setCol(hover and C_TEXT or C_BLUE, a)
        surface.DrawRect(x, y, w, h)
        draw.SimpleText(text, font, x + w * 0.5, y + h * 0.5, C_DARK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        local danger = style == "danger"
        if hover then
            surface.SetDrawColor(C_TILE)
            surface.DrawRect(x, y, w, h)
        end
        setCol(danger and C_DANGER_EDGE or (hover and C_HOVER_EDGE or C_BORDER), a)
        surface.DrawOutlinedRect(x, y, w, h)
        draw.SimpleText(text, font, x + w * 0.5, y + h * 0.5, on and (danger and C_DANGER_TEXT or C_TEXT) or C_OFF, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    if on then
        self.nb = self.nb + 1
        local b = self.buttons[self.nb]
        if not b then b = {} self.buttons[self.nb] = b end
        b.x, b.y, b.w, b.h, b.fn, b.arg = x, y, w, h, fn, arg
    end
end

local function actClose() Inv.Toggle() end
local function actCombine() Inv.RequestCombine() end
local function actHelmet()
    Rhylib.Net.Start("gear.helmet")
    net.SendToServer()
end
local function actLock() hook.Run("Rhylib.StorageControl", "lock") end
local function actUnclaim() hook.Run("Rhylib.StorageControl", "unclaim") end
local function actBulk(_, a) Inv.RequestBulk(a) end
local function actEmpty()
    Derma_Query("Delete everything in here? This can't be undone.", "Empty",
        "Delete all", function() Inv.RequestBulk(2) end, "Cancel")
end
local function actTab(self, g)
    self.shelfTab = g or nil
    self.scroll.ext = 0
    self:RebuildShelves()
end
local function actTake(self, single)
    local d = self.cardData
    local c = Inv.cont[EXT]
    local inst = d and d.inst and c and c.items[d.inst.uid]
    if inst then Inv.RequestQuickTake(inst, single) end
end

--------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------

function PANEL:Paint(pw, ph)
    if self:LayoutDirty() then self:Relayout() end
    local s = self.s
    self.nb = 0

    -- What's under the mouse (for the card and tile highlights).
    self.hoverInst = nil
    if not self.drag and self:IsHovered() then
        self.hoverInst = self:ItemAtCursor()
        if not self.hoverInst then
            local mx, my = self:CursorPos()
            local hb = self:HotbarAt(mx, my)
            if hb then self.hoverInst = Inv.HotbarItem(hb) end
        end
    end

    -- Page, worn column, header.
    surface.SetDrawColor(C_PAGE)
    surface.DrawRect(0, 0, pw, ph)
    surface.SetDrawColor(C_SIDE)
    surface.DrawRect(0, self.header, self.wornW, ph - self.header)
    surface.SetDrawColor(C_EDGE)
    surface.DrawRect(self.wornW, self.header, 1, ph - self.header)
    self:PaintHeader(pw)
    surface.SetDrawColor(C_EDGE)
    surface.DrawOutlinedRect(0, 0, pw, ph)

    self:PaintWorn()

    local dragUid = self.drag and self.drag.inst.uid
    local sx, sy = self:LocalToScreen(0, 0)
    for k, c in pairs(self.cols or {}) do
        -- Each column clipped to its view.
        render.SetScissorRect(sx + c.x - self.pad * 0.5, sy + c.top, sx + c.x + c.w + self.pad * 0.5, sy + c.top + c.view + 2, true)
        for _, r in ipairs(self.regions) do
            if r.col == k then self:PaintRegion(r, dragUid) end
        end
        if k == "own" and self.noPack then
            draw.SimpleText("No backpack worn", self:Font(13, 700), self.noPack.x, self.noPack.y, C_OFF, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        if k == "own" and self.cardRect then
            local cr = self.cardRect
            self:PaintCardAt(cr.x, cr.y, cr.w, cr.h)
        end
        render.SetScissorRect(0, 0, 0, 0, false)
        -- Scroll bar on the right edge.
        if c.content > c.view then
            local bx = c.x + c.w + math.floor(self.pad * 0.3)
            local bw = math.max(2, math.floor(3 * s))
            surface.SetDrawColor(C_FAINT)
            surface.DrawRect(bx, c.top, bw, c.view)
            local h = math.max(math.floor(c.view * c.view / c.content), math.floor(20 * s))
            local y = c.top + math.floor((c.view - h) * (self.scroll[k] or 0) / (c.content - c.view))
            surface.SetDrawColor(C_BLUE)
            surface.DrawRect(bx, y, bw, h)
        end
    end
    for _, r in ipairs(self.regions) do
        if not r.col and not r.slot then self:PaintRegion(r, dragUid) end
    end

    self:PaintExt()
    self:PaintHotbar()
    self:PaintFooter(pw, ph)
end

-- The drag (target, ghost) goes over the model preview too.
function PANEL:PaintOver()
    if self.drag then self:PaintDrag() end
end

-- Header: mark, title, trooper line, carry bar, close.
function PANEL:PaintHeader(pw)
    local s = self.s
    local hh = self.header
    surface.SetDrawColor(C_CARD)
    surface.DrawRect(0, 0, pw, hh)
    surface.SetDrawColor(C_EDGE)
    surface.DrawRect(0, hh - 1, pw, 1)

    -- A small diamond.
    local d = math.floor(8 * s)
    local cx, cy = self.pad + d, math.floor(hh * 0.5)
    surface.SetDrawColor(C_BLUE)
    for o = 0, 1 do
        surface.DrawLine(cx - d + o, cy, cx, cy - d + o)
        surface.DrawLine(cx, cy - d + o, cx + d - o, cy)
        surface.DrawLine(cx + d - o, cy, cx, cy + d - o)
        surface.DrawLine(cx, cy + d - o, cx - d + o, cy)
    end
    local tx = cx + d + math.floor(14 * s)
    draw.SimpleText("INVENTORY", self:Font(24, 800), tx, cy + math.floor(2 * s), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    local now = RealTime()
    if not self.who or now > (self.whoAt or 0) then
        local ply = LocalPlayer()
        local job = team.GetName(ply:Team())
        self.who = ply:Nick() .. ((job and job ~= "") and (" · " .. job) or "")
        self.whoAt = now + 1
    end
    draw.SimpleText(self.who, self:Font(12), tx, cy + math.floor(4 * s), C_DIM)

    -- Close.
    local bs = math.floor(40 * s)
    local bx, by = pw - self.pad - bs, math.floor((hh - bs) * 0.5)
    local mx, my = self:CursorPos()
    local hover = mx >= bx and mx <= bx + bs and my >= by and my <= by + bs
    surface.SetDrawColor(hover and C_HOVER_EDGE or C_BORDER)
    surface.DrawOutlinedRect(bx, by, bs, bs)
    local m = math.floor(bs * 0.34)
    surface.SetDrawColor(hover and C_TEXT or C_DIM)
    for o = 0, 1 do
        surface.DrawLine(bx + m + o, by + m, bx + bs - m + o, by + bs - m)
        surface.DrawLine(bx + bs - m + o, by + m, bx + m + o, by + bs - m)
    end
    self.nb = self.nb + 1
    local b = self.buttons[self.nb]
    if not b then b = {} self.buttons[self.nb] = b end
    b.x, b.y, b.w, b.h, b.fn, b.arg = bx, by, bs, bs, actClose, nil

    self:PaintWeight(bx - self.colGap)
end

-- Carried weight: "CARRYING 12.4 / 20 kg" and a word, over a bar up to the
-- weight ceiling: blue load, amber zone from stamina heavyFrom to the cap
-- ("Slower"), red zone past the cap ("No sprinting"), a mark at each.
-- Worked out from the local copy, so it updates the moment items move.
function PANEL:CarryNow()
    local now = RealTime()
    if self.carryAt and now < self.carryAt then return self.carryW, self.carryCap end
    local weight, cap = Items.Weight(Inv)
    local K = Rhylib.Skills
    if K and K.AdjustWeight then weight, cap = K.AdjustWeight(LocalPlayer(), Inv, weight, cap) end
    self.carryW, self.carryCap, self.carryAt = weight, cap, now + 0.1
    return weight, cap
end

local function barAt(x, barW, f, ceil) return x + math.floor(barW * math.Clamp(f / ceil, 0, 1)) end

function PANEL:PaintWeight(right)
    local s = self.s
    local weight, cap = self:CarryNow()
    local load = cap > 0 and weight / cap or 0
    local ceil = math.max(1, Rhylib.Config.Get("inventory", "weightCeiling") or 1.25)
    local slowFrom = (Rhylib.Config.defs.stamina and Rhylib.Config.Get("stamina", "heavyFrom")) or 0.75
    local over = load > 1
    local slow = load > slowFrom
    local col = over and C_RED or (slow and C_AMBER or C_GREEN)

    local barW = math.min(math.floor(380 * s), right - math.floor(self.wornW * 0.9))
    if barW < 60 then return end
    local x = right - barW
    local barH = math.max(4, math.floor(8 * s))
    local midY = math.floor(self.header * 0.5)
    -- Top line.
    local ty = midY - barH * 0.5 - math.floor(5 * s)
    local lf, nf, uf = self:Font(12, 700), self:Font(17, 700), self:Font(12)
    draw.SimpleText("CARRYING", lf, x, ty, C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    surface.SetFont(lf)
    local lx = x + surface.GetTextSize("CARRYING") + math.floor(8 * s)
    if self.wStrV ~= weight or self.wCapV ~= cap then
        self.wStrV, self.wCapV = weight, cap
        self.wStr, self.wCapStr = string.format("%.1f", weight), string.format("/ %d kg", cap)
    end
    draw.SimpleText(self.wStr, nf, lx, ty + math.floor(2 * s), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    surface.SetFont(nf)
    lx = lx + surface.GetTextSize(self.wStr) + math.floor(5 * s)
    draw.SimpleText(self.wCapStr, uf, lx, ty, C_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(over and "No sprinting" or (slow and "Slower" or "Sprinting OK"), uf, right, ty, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    -- Bar: track, zones, load, what a take would add, marks.
    local y = midY - math.floor(barH * 0.5)
    surface.SetDrawColor(C_INSET)
    surface.DrawRect(x, y, barW, barH)
    setCol(C_AMBER, 46)
    surface.DrawRect(barAt(x, barW, slowFrom, ceil), y, barAt(x, barW, 1, ceil) - barAt(x, barW, slowFrom, ceil), barH)
    setCol(C_RED, 46)
    surface.DrawRect(barAt(x, barW, 1, ceil), y, barAt(x, barW, ceil, ceil) - barAt(x, barW, 1, ceil), barH)
    surface.SetDrawColor(over and C_RED or (slow and C_AMBER or C_BLUE))
    surface.DrawRect(x, y, barAt(x, barW, load, ceil) - x, barH)
    local d = self.cardData
    local add = d and d.takeKg
    if add and cap > 0 then
        setCol(C_BLUE, 90)
        surface.DrawRect(barAt(x, barW, load, ceil), y, barAt(x, barW, load + add / cap, ceil) - barAt(x, barW, load, ceil), barH)
    end
    surface.SetDrawColor(C_BORDER)
    surface.DrawOutlinedRect(x, y, barW, barH)
    local mh = math.floor(3 * s)
    local mw = math.max(1, math.floor(2 * s))
    surface.SetDrawColor(C_AMBER)
    surface.DrawRect(barAt(x, barW, slowFrom, ceil), y - mh, mw, barH + mh * 2)
    surface.SetDrawColor(C_RED)
    surface.DrawRect(math.min(barAt(x, barW, 1, ceil), x + barW - mw), y - mh, mw, barH + mh * 2)

    -- Under it: the zone names, or what taking the item would add.
    local by = y + barH + math.floor(4 * s)
    local sf = self:Font(11)
    if add then
        draw.SimpleText(d.takeText, sf, x, by, C_BLUE)
    else
        draw.SimpleText("Slower", sf, barAt(x, barW, slowFrom, ceil) - math.floor(4 * s), by, C_LABEL)
        draw.SimpleText("No sprinting", sf, x + barW, by, C_LABEL, TEXT_ALIGN_RIGHT)
    end
end

-- Worn column: caption, model backdrop, helmet toggle, combine button
-- (the slots themselves are regions).
function PANEL:PaintWorn()
    local s = self.s
    draw.SimpleText("WORN", self:Font(13, 700), self.pad, self.top + self.cap * 0.5 - math.floor(4 * s), C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local m = self.modelRect
    if m then
        surface.SetDrawColor(C_MODEL)
        surface.DrawRect(m.x, m.y, m.w, m.h)
        surface.SetDrawColor(C_FAINT)
        surface.DrawOutlinedRect(m.x, m.y, m.w, m.h)
        local cf = self:Font(11)
        draw.SimpleText(fitText("Your trooper · drag to turn", cf, m.w - math.floor(8 * s)), cf, m.x + m.w * 0.5, m.y + m.h - math.floor(8 * s), C_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end
    local dragUid = self.drag and self.drag.inst.uid
    for _, r in ipairs(self.regions) do
        if r.slot then self:PaintRegion(r, dragUid) end
    end
    local pb = self.pouchBox
    if pb and Inv.cont[Items.CELLBELT] then
        surface.SetDrawColor(C_BORDER)
        surface.DrawOutlinedRect(pb.x, pb.y, pb.w, pb.h)
        local p = math.floor(9 * s)
        local lf = self:Font(10, 700)
        draw.SimpleText(fitText("BELT CELL POUCH", lf, pb.w - p * 2), lf, pb.x + p, pb.y + p, C_LABEL)
    end
    self:PaintHelmet()
    self:PaintCombine()
end

-- Helmet on/off (rhylib_gear): a tile at the top of the helmet side.
function PANEL:PaintHelmet()
    local r = self.helmetRect
    if not (r and r.y) then return end
    local on = not LocalPlayer():GetNW2Bool("rhylib_helmetOff", false)
    local mx, my = self:CursorPos()
    local hover = mx >= r.x and mx <= r.x + r.pw and my >= r.y and my <= r.y + r.ph
    self:DrawTile(r.x, r.y, r.pw, r.ph, "HELMET", on and "On" or "Off", true, 255, on and C_BLUE or C_DIM, hover)
    self.nb = self.nb + 1
    local b = self.buttons[self.nb]
    if not b then b = {} self.buttons[self.nb] = b end
    b.x, b.y, b.w, b.h, b.fn, b.arg = r.x, r.y, r.pw, r.ph, actHelmet, nil
end

-- Combine munitions: a button, or a progress bar while it runs.
function PANEL:PaintCombine()
    local r = self.combineRect
    if not r then return end
    local now = CurTime()
    if Inv.busyEnd and Inv.busyEnd > now then
        local total = math.max(Inv.busyEnd - (Inv.busyStart or now), 0.01)
        local frac = math.Clamp(1 - (Inv.busyEnd - now) / total, 0, 1)
        surface.SetDrawColor(C_INSET)
        surface.DrawRect(r.x, r.y, r.w, r.h)
        setCol(C_BLUE, 70)
        surface.DrawRect(r.x, r.y, math.floor(r.w * frac), r.h)
        surface.SetDrawColor(C_BORDER)
        surface.DrawOutlinedRect(r.x, r.y, r.w, r.h)
        draw.SimpleText("Combining…", self:Font(13, 500), r.x + r.w * 0.5, r.y + r.h * 0.5, C_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    self:Btn(r.x, r.y, r.w, r.h, "Combine munitions", actCombine)
end

-- Storage side: header (title, line, buttons), tabs, card.
function PANEL:PaintExt()
    local e = self.extRect
    local ext = Inv.ext
    if not (e and ext) then return end
    local s = self.s
    local c = Inv.cont[EXT]
    local x, y, w, hh = e.x, e.y, e.w, self.extHead
    -- (a line between your side and the storage)
    surface.SetDrawColor(C_EDGE)
    surface.DrawRect(x - self.colGap, self.header, 1, self.top + self.contentH - self.header)
    surface.SetDrawColor(C_CARD)
    surface.DrawRect(x, y, w, hh)
    surface.SetDrawColor(ext.depot and C_PURPLE or C_BLUE)
    surface.DrawRect(x, y, w, math.max(2, math.floor(3 * s)))
    local p = math.floor(14 * s)

    -- Buttons on the right: Lock / Unclaim (owned locker), or the bulk ones.
    local bh = math.floor(32 * s)
    local bw = math.floor(86 * s)
    local bx = x + w - p - bw
    local byy = y + math.floor((hh - bh) * 0.5) + math.floor(1 * s)
    local left = bx + bw
    if ext.bulk then
        local has = (c and next(c.items) ~= nil) and true or false
        self:Btn(bx, byy, bw, bh, "Take all", actBulk, 1, has, "primary")
        -- (one trip at a time: storing again only once it's empty)
        self:Btn(bx - bw - self.gap * 2, byy, bw, bh, "Store all", actBulk, 0, not (ext.bulkOnly and has))
        self:Btn(bx - (bw + self.gap * 2) * 2, byy, bw, bh, "Empty", actEmpty, nil, has, "danger")
        left = bx - (bw + self.gap * 2) * 2
    elseif ext.canLock then
        self:Btn(bx, byy, bw, bh, ext.locked and "Unlock" or "Lock", actLock)
        self:Btn(bx - bw - self.gap * 2, byy, bw, bh, "Unclaim", actUnclaim, nil, true, "danger")
        left = bx - bw - self.gap * 2
    end
    local tw = left - x - p * 2
    local tf = self:Font(20, 800)
    local title = self.extTitleSrc == ext.title and self.extTitle or nil
    if not title then
        title = string.upper(ext.title or "Storage")
        self.extTitle, self.extTitleSrc = title, ext.title
    end
    local midY = y + math.floor(hh * 0.5) + math.floor(1 * s)
    draw.SimpleText(fitText(title, tf, tw), tf, x + p, midY + math.floor(2 * s), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    local sub
    if ext.depot then
        sub = ext.counted and "Stock shared across the map · resupply crates refill it"
            or "Endless supply · what you take is issued"
    elseif ext.bulkOnly then
        sub = "Store all and Take all · one trip at a time"
    elseif ext.canLock then
        sub = ext.locked and "Your locker · locked" or "Your locker · unlocked"
    else
        if self.extSubFor ~= c then
            self.extSubFor = c
            self.extSub = c and (c.w .. " × " .. c.h) or ""
        end
        sub = self.extSub
    end
    local sf = self:Font(12)
    draw.SimpleText(fitText(sub, sf, tw), sf, x + p, midY + math.floor(4 * s), C_DIM)

    -- Group tabs.
    if self.tabs then
        local tf2, nf = self:Font(13, 600), self:Font(11)
        local mx, my = self:CursorPos()
        local cpad = math.floor(12 * s)
        for _, t in ipairs(self.tabs) do
            local on = (self.shelfTab or false) == t.g
            local hover = mx >= t.x and mx <= t.x + t.w and my >= t.y and my <= t.y + self.chipH
            if on then
                surface.SetDrawColor(C_TEXT)
                surface.DrawRect(t.x, t.y, t.w, self.chipH)
            else
                surface.SetDrawColor(hover and C_HOVER_EDGE or C_BORDER)
                surface.DrawOutlinedRect(t.x, t.y, t.w, self.chipH)
            end
            local cy = t.y + self.chipH * 0.5
            draw.SimpleText(t.label, tf2, t.x + cpad, cy, on and C_DARK or C_TABTEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(t.n, nf, t.x + t.w - cpad, cy, on and C_DARK or C_LABEL, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            if not on then
                self.nb = self.nb + 1
                local b = self.buttons[self.nb]
                if not b then b = {} self.buttons[self.nb] = b end
                b.x, b.y, b.w, b.h, b.fn, b.arg = t.x, t.y, t.w, self.chipH, actTab, t.g
            end
        end
    end

    -- The card, beside the shelves / grid.
    local cx = x + e.bodyW + self.colGap
    self:PaintCardAt(cx, e.bodyTop, self.cardW, e.cardH or self:SpanPx(4))
end

-- Hotbar keys along the bottom.
function PANEL:PaintHotbar()
    local s = self.s
    local hy = self.hotbarY
    self:Caption(self.hotbarX, hy - self.cap * 0.5, self.width - self.hotbarX - self.pad, "HOTBAR",
        "drag an item onto a key · right-click a key to empty it")
    local active = LocalPlayer():GetActiveWeapon()
    local activeClass = IsValid(active) and active:GetClass()
    local mx, my = self:CursorPos()
    local dropOn = self.drag and not self.drag.fromExt and self:HotbarAt(mx, my)
    local kf, nf, sf = self:Font(17, 800), self:Font(12, 500), self:Font(10)
    local p = math.floor(11 * s)
    local kw = math.floor(20 * s)
    for n = 1, self.hotbarN do
        local x = self.hotbarX + (n - 1) * (self.hbW + self.hbGap)
        local w, h = self.hbW, self.hbH
        local inst = Inv.HotbarItem(n)
        local info = self.hbInfo[n]
        if not info then info = {} self.hbInfo[n] = info end
        if info.inst ~= inst or not info.name then
            info.inst = inst
            local def = inst and Items.Get(inst.id)
            if def then
                info.name = def.name
                local kind = string.lower(kindOf(def))
                local extra
                if inst.count > 1 then extra = strX(inst.count)
                elseif def.rounds and def.rounds > 1 then extra = strRounds(math.floor((inst.data.fill or 1) * def.rounds + 0.5), def.rounds)
                elseif def.fill and def.rounds == nil then extra = strPct(math.ceil((inst.data.fill or 1) * 100)) end
                info.sub = extra and (kind .. " · " .. extra) or kind
                info.weapon = def.weapon
            else
                info.name, info.sub, info.weapon = "Empty", n > Items.HOTBAR and "backpack slot" or "", nil
            end
        end
        local held = inst and info.weapon and activeClass == info.weapon
        local dragged = inst and self.drag and self.drag.inst == inst
        local a = dragged and 90 or 255
        if inst then
            setCol(held and C_TEXT or C_CARD, a)
            surface.DrawRect(x, hy, w, h)
            setCol(dropOn == n and C_BLUE or C_BORDER, a)
            surface.DrawOutlinedRect(x, hy, w, h, dropOn == n and math.max(1, math.floor(2 * s)) or 1)
        else
            setCol(dropOn == n and C_BLUE or C_BORDER, a)
            if dropOn == n then
                surface.DrawOutlinedRect(x, hy, w, h, math.max(1, math.floor(2 * s)))
            else
                dashed(x, hy, w, h, math.max(3, math.floor(5 * s)), 1)
            end
        end
        local cy = hy + h * 0.5
        draw.SimpleText(strN(n), kf, x + p, cy, held and C_DARK or C_BLUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local tx = x + p + kw
        local tw = w - p * 2 - kw
        local hasSub = info.sub ~= ""
        draw.SimpleText(fitText(info.name, nf, tw), nf, tx, hasSub and (cy + math.floor(1 * s)) or cy, held and C_DARK or (inst and C_TEXT or C_OFF),
            TEXT_ALIGN_LEFT, hasSub and TEXT_ALIGN_BOTTOM or TEXT_ALIGN_CENTER)
        if hasSub then
            draw.SimpleText(fitText(info.sub, sf, tw), sf, tx, cy + math.floor(2 * s), held and C_DARK or C_LABEL)
        end
    end
end

-- Footer: the controls, and the last message from the server for a few
-- seconds.
function PANEL:PaintFooter(pw, ph)
    local y = ph - self.footer * 0.5
    local hf = self:Font(11)
    draw.SimpleText(fitText("Drag to move · Ctrl+drag takes one · R turns · Right-click for options (storage: quick take) · Drag out to drop",
        hf, pw - self.hotbarX - self.pad), hf, self.hotbarX, y, C_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if not Inv.note or RealTime() - (Inv.noteTime or 0) > 3 then return end
    C_NOTE.a = math.Clamp((3 - (RealTime() - Inv.noteTime)) * 255, 0, 255)
    local nf = self:Font(13, 500)
    surface.SetFont(nf)
    local tw = surface.GetTextSize(Inv.note)
    local x = pw - self.pad
    surface.SetDrawColor(C_PAGE)
    surface.DrawRect(x - tw - math.floor(12 * self.s), ph - self.footer, tw + math.floor(12 * self.s), self.footer - 1)
    draw.SimpleText(Inv.note, nf, x, y, C_NOTE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

--------------------------------------------------------------------------
-- The item card: what's under the mouse (else the picked storage item).
-- Built when the item changes (and every half second), not every frame.
--------------------------------------------------------------------------

function PANEL:CardItem()
    if self.hoverInst then return self.hoverInst end
    if self.drag then return self.drag.inst end
    -- (the mouse on the card itself: keep showing what it showed)
    local b, d = self.cardBox, self.cardData
    if b and d and d.inst and self:IsHovered() then
        local mx, my = self:CursorPos()
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            local still = Inv.byUid[d.inst.uid] == d.inst or (Inv.cont[EXT] and Inv.cont[EXT].items[d.inst.uid] == d.inst)
            if still then return d.inst end
        end
    end
    local c = Inv.cont[EXT]
    if self.selExt and c then return c.items[self.selExt] end
end

function PANEL:BuildCard(inst)
    local s = self.s
    local d = { inst = inst, at = RealTime() + 0.5 }
    local p = math.floor(14 * s)
    local iw = self.cardW - p * 2
    local f12, f11 = self:Font(12), self:Font(11)
    d.lines, d.hint, d.stats = {}, {}, {}
    local def = inst and Items.Get(inst.id)
    if not def then
        d.title = Inv.ext and Inv.ext.depot and "PICK A SHELF" or "NO ITEM"
        wrapInto(d.lines, Inv.ext and Inv.ext.depot and "Click a shelf to see its stock here, or point at any item."
            or "Point at an item to see it here.", f12, iw, C_DIM)
        wrapInto(d.hint, "Drag to move · Ctrl-drag takes one · R while dragging turns it · Right-click for options", f11, iw, C_LABEL)
        d.h = self:PaintCard(d, 0, 0, self.cardW, 1e9, true)
        return d
    end

    local isExt = inst.c == EXT and Inv.ext ~= nil
    local depot = isExt and Inv.ext.depot
    local stockCounted = depot and Inv.ext.counted and not (Inv.ext.endless and Inv.ext.endless[inst.uid])
    -- (a depot shelf: what one take gives, not the shelf's count)
    local count = depot and math.max(1, math.min(takeAmount(inst), stockCounted and math.max(1, inst.count) or 255)) or inst.count
    local kind, g = kindOf(def)
    d.title = string.upper(def.name)
    d.edge = stripeOf(def)
    local w, h = Items.Size(inst.id, inst.rot)
    d.kind = kind .. " · " .. w .. " × " .. h .. ((def.weight and def.weight > 0 and depot) and string.format(" · %.2f kg each", def.weight) or "")
    if inst.c == BACK then d.kind = d.kind .. " · in the backpack" end

    -- Stats the tooltip knows.
    local st = d.stats
    if def.rounds then
        if def.rounds > 1 then
            local left = depot and def.rounds or math.floor((inst.data.fill or 1) * def.rounds + 0.5)
            st[#st + 1] = { def.unit == "uses" and "USES" or "ROUNDS", left .. " / " .. def.rounds }
        end
    elseif def.fill then
        st[#st + 1] = { "CHARGE", (depot and 100 or math.ceil((inst.data.fill or 1) * 100)) .. "%" }
    end
    if def.stack > 1 and not depot then
        st[#st + 1] = { "STACK", inst.count .. " / " .. (isExt and def.stack or Items.StackFor(def, LocalPlayer())) }
    end
    local lines = d.lines
    if def.weight then
        local wkg = def.weight * count
        st[#st + 1] = { "WEIGHT", string.format("%.2f kg", wkg) }
        local pm = Rhylib.Config.Get("inventory", "backpackWeightMult")
        if inst.c == BACK and pm ~= 1 then wrapInto(lines, string.format("Counts as %.2f kg in the backpack", wkg * pm), f12, iw, C_DIM) end
        -- (in a storage: what taking it would do to your load)
        if isExt and def.weight > 0 then
            local cw, cap = self:CarryNow()
            local ceil = Rhylib.Config.Get("inventory", "weightCeiling") or 1.25
            if ceil > 0 and cw + def.weight > cap * ceil then
                wrapInto(lines, "Too heavy to take: you're carrying too much", f12, iw, C_AMBER)
            elseif cw + wkg > cap then
                wrapInto(lines, "Taking it puts you over your carry limit: no sprinting", f12, iw, C_AMBER)
            end
            if not (Inv.ext.bulkOnly) and not (stockCounted and inst.count <= 0) then
                d.takeKg = wkg
                d.takeText = string.format("+%.1f kg if you take the %s", wkg, def.name)
            end
        end
    end
    if def.carry then st[#st + 1] = { "CARRY", "+" .. def.carry .. " kg" } end
    if def.grid then st[#st + 1] = { "ADDS", def.grid[1] .. " × " .. def.grid[2] .. " cells" } end
    for i = #st, 5, -1 do st[i] = nil end   -- (four tiles at most)

    if def.desc then wrapInto(lines, def.desc, f12, iw, C_DIM) end
    if def.large then wrapInto(lines, "Too large for a backpack", f12, iw, C_DIM) end
    if def.carry then wrapInto(lines, "+" .. def.carry .. " kg carry cap when worn", f12, iw, C_DIM) end
    if def.grid then wrapInto(lines, "Adds " .. def.grid[1] .. " x " .. def.grid[2] .. " cells when worn", f12, iw, C_DIM) end
    if inst.data and inst.data.issued then wrapInto(lines, "Issued: if dropped, disappears after 5 minutes", f12, iw, C_DIM) end
    if inst.data and inst.data.hidden and not isExt then wrapInto(lines, "Hidden: a search may miss it", f12, iw, C_DIM) end
    if inst.data and inst.data.note and inst.data.note ~= "" then wrapInto(lines, inst.data.note, f12, iw, C_TEXT) end
    -- (other addons add lines; return nothing)
    local extra = { def.name }
    hook.Run("Rhylib.ItemTooltip", inst, extra)
    for i = 2, #extra do wrapInto(lines, tostring(extra[i]), f12, iw, C_DIM) end

    -- A depot shelf: its stock and the take buttons.
    if depot then
        d.shelf = true
        d.counted = stockCounted
        d.left = inst.count
        d.max = stockCounted and stockMax(inst.id)
        d.out = stockCounted and inst.count <= 0
        local share = (not stockCounted) and 1 or (d.max and math.Clamp(inst.count / d.max, 0, 1) or (d.out and 0 or 1))
        d.share = share
        d.barCol = not stockCounted and C_GREYBAR or (d.out and C_RED or ((d.max and share < 0.6) and C_AMBER or C_GREEN))
        if stockCounted then
            d.big = inst.count >= 255 and "255+" or tostring(inst.count)
            d.small = d.out and "left · out of stock" or (d.max and ("of " .. d.max .. " left") or "left")
        else
            d.big, d.small = "∞", "endless supply"
        end
        d.stockNote = {}
        wrapInto(d.stockNote, stockCounted and (d.out and "Out of stock: it comes back with a resupply."
            or "Shared by every cabinet of this kind. Hand issued gear back in and the stock goes up again.")
            or "Never runs out.", f11, iw - math.floor(24 * s), C_DIM)
    end
    if isExt and not Inv.ext.bulkOnly then
        d.take = true
        d.takeOk = not d.out
        local n = depot and (Items.Unique(def) and 1 or Items.StackFor(def, LocalPlayer())) or inst.count
        if stockCounted then n = math.min(n, math.max(1, inst.count)) end
        d.takeMulti = n > 1 and ("Take " .. (depot and "a stack" or "all") .. " (" .. strX(n) .. ")") or nil
    end

    -- Hint line.
    local hint
    if isExt and Inv.ext.bulkOnly then
        hint = "Comes back with Take all"
    elseif depot then
        hint = "Right-click a shelf to take at once (Ctrl: just one). Drag it into your pockets to place it."
    elseif isExt then
        hint = "Right-click: quick take (Ctrl: just one) · Drag it to your grids"
    else
        hint = (inst.hb and ("Hotbar " .. inst.hb) or "Right-click → Equip to put it on the hotbar")
            .. " · Right-click for options · R while dragging turns it · Ctrl-drag takes one"
    end
    wrapInto(d.hint, hint, f11, iw, C_LABEL)
    d.h = self:PaintCard(d, 0, 0, self.cardW, 1e9, true)
    return d
end

-- Card at x, y (at most maxH tall); builds it when needed.
function PANEL:PaintCardAt(x, y, w, maxH)
    local b = self.cardBox
    if not b then b = {} self.cardBox = b end
    b.x, b.y, b.w = x, y, w
    b.h = math.min(maxH, self.cardData and self.cardData.h or maxH)
    local inst = self:CardItem()
    local d = self.cardData
    if not d or d.inst ~= inst or RealTime() > d.at then
        d = self:BuildCard(inst)
        self.cardData = d
    end
    self:PaintCard(d, x, y, w, maxH, false)
end

-- Draws (or with dry, only measures) the card; returns its height.
function PANEL:PaintCard(d, x, y, w, maxH, dry)
    local s = self.s
    local p = math.floor(14 * s)
    local bottom = y + maxH
    local iw = w - p * 2
    local ix = x + p
    if not dry then
        surface.SetDrawColor(C_CARD)
        surface.DrawRect(x, y, w, math.min(d.h or maxH, maxH))
        surface.SetDrawColor(d.edge or C_BLUE)
        surface.DrawRect(x, y, w, math.max(2, math.floor(3 * s)))
    end
    local cy = y + math.floor(3 * s) + p
    local tf = self:Font(20, 800)
    if not dry then draw.SimpleText(fitText(d.title, tf, iw), tf, ix, cy, C_TEXT) end
    cy = cy + draw.GetFontHeight(tf) + math.floor(2 * s)
    if d.kind then
        local kf = self:Font(12)
        if not dry then draw.SimpleText(fitText(d.kind, kf, iw), kf, ix, cy, C_DIM) end
        cy = cy + draw.GetFontHeight(kf)
    end
    cy = cy + math.floor(10 * s)

    -- Shelf stock box.
    if d.shelf then
        local bp = math.floor(12 * s)
        local nf = self:Font(26, 800)
        local nh = draw.GetFontHeight(nf)
        local lh = draw.GetFontHeight(self:Font(11)) + 1
        local bh = bp * 2 + nh + math.floor(14 * s) + #d.stockNote * lh
        if not dry and cy + bh <= bottom then
            surface.SetDrawColor(C_INSET)
            surface.DrawRect(ix, cy, iw, bh)
            draw.SimpleText(d.big, nf, ix + bp, cy + bp, d.out and C_RED or C_TEXT)
            surface.SetFont(nf)
            local bw = surface.GetTextSize(d.big)
            draw.SimpleText(d.small, self:Font(12), ix + bp + bw + math.floor(7 * s), cy + bp + nh - math.floor(4 * s), C_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            local by = cy + bp + nh + math.floor(2 * s)
            local barH = math.max(3, math.floor(6 * s))
            surface.SetDrawColor(C_FAINT)
            surface.DrawRect(ix + bp, by, iw - bp * 2, barH)
            surface.SetDrawColor(d.barCol)
            surface.DrawRect(ix + bp, by, math.floor((iw - bp * 2) * d.share), barH)
            local ly = by + barH + math.floor(6 * s)
            for _, l in ipairs(d.stockNote) do
                draw.SimpleText(l.t, l.font, ix + bp, ly, l.col)
                ly = ly + lh
            end
        end
        cy = cy + bh + math.floor(10 * s)
    end

    -- Take buttons (storage items).
    if d.take then
        if not dry and cy + self.btnH <= bottom then
            self:Btn(ix, cy, iw, self.btnH, "Take one", actTake, true, d.takeOk, "primary")
        end
        cy = cy + self.btnH + math.floor(8 * s)
        if d.takeMulti then
            if not dry and cy + self.btnH <= bottom then
                self:Btn(ix, cy, iw, self.btnH, d.takeMulti, actTake, false, d.takeOk)
            end
            cy = cy + self.btnH + math.floor(8 * s)
        end
        cy = cy + math.floor(2 * s)
    end

    -- Stat tiles, two a row.
    local st = d.stats
    if #st > 0 then
        local tg = math.floor(6 * s)
        local tw = math.floor((iw - tg) * 0.5)
        local th = math.floor(40 * s)
        local lf, vf = self:Font(10, 700), self:Font(14, 700)
        for i, kv in ipairs(st) do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            local tx, ty = ix + col * (tw + tg), cy + row * (th + tg)
            if not dry and ty + th <= bottom then
                surface.SetDrawColor(C_INSET)
                surface.DrawRect(tx, ty, tw, th)
                local q = math.floor(8 * s)
                draw.SimpleText(kv[1], lf, tx + q, ty + math.floor(6 * s), C_LABEL)
                draw.SimpleText(fitText(kv[2], vf, tw - q * 2), vf, tx + q, ty + th - math.floor(5 * s), C_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            end
        end
        cy = cy + math.ceil(#st / 2) * (th + tg) + math.floor(4 * s)
    end

    -- Notes, then the hint.
    for _, l in ipairs(d.lines) do
        local lh = draw.GetFontHeight(l.font) + 2
        if not dry then
            if cy + lh > bottom then break end
            draw.SimpleText(l.t, l.font, ix, cy, l.col)
        end
        cy = cy + lh
    end
    if #d.hint > 0 then cy = cy + math.floor(6 * s) end
    for _, l in ipairs(d.hint) do
        local lh = draw.GetFontHeight(l.font) + 2
        if not dry then
            if cy + lh > bottom then break end
            draw.SimpleText(l.t, l.font, ix, cy, l.col)
        end
        cy = cy + lh
    end
    return cy - y + p
end

--------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------

-- Where the dragged item would land: region, x, y (or nil). d.offX/offY:
-- which cell of the item you grabbed.
function PANEL:DragTarget(d)
    local mx, my = self:CursorPos()
    local r, cx, cy = self:HitTest(mx, my, self.step * 0.5)
    if not r then return nil end
    if r.slot or r.shelves then return r, 0, 0 end
    return r, cx - d.offX, cy - d.offY
end

-- Would dropping drag d at region r, x, y do anything?
function PANEL:DropAllowed(d, r, tx, ty)
    local c = Inv.cont[r.cid]
    if not c then return false end
    local toExt, fromExt = r.cid == EXT, d.fromExt
    local probe = { uid = -1, id = d.inst.id, count = d.inst.count, data = d.inst.data }

    if toExt and Inv.ext and Inv.ext.depot then
        -- Anything can be handed in (and is gone): no walking to the
        -- right cabinet just to get rid of something.
        if fromExt then return false end
        return Items.CanLeave(Inv, d.inst) and true or false
    end
    if toExt and fromExt then
        return Items.MergeTarget(c.items, d.inst, tx, ty) ~= nil
            or Items.Fits(c.w, c.h, c.items, d.inst.id, tx, ty, d.rot, not d.single and d.inst.uid or nil)
    end
    if toExt then
        if not Items.CanLeave(Inv, d.inst) then return false end
        return Items.MergeTarget(c.items, probe, tx, ty) ~= nil or Items.Fits(c.w, c.h, c.items, d.inst.id, tx, ty, d.rot)
    end
    if r.gear and not Items.CanWear(LocalPlayer(), Items.defs[d.inst.id]) then return false end
    if fromExt then
        return (not r.slot and Items.MergeTarget(c.items, probe, tx, ty, LocalPlayer()) ~= nil)
            or Items.CanPlace(Inv, d.inst.id, r.cid, tx, ty, d.rot)
    end
    if d.fromHotbar then return false end
    local ok = Items.CanLeave(Inv, d.inst) or r.cid == d.inst.c
    return ok and ((not r.slot and Items.MergeTarget(c.items, d.inst, tx, ty, LocalPlayer()) ~= nil)
        or Items.CanPlace(Inv, d.inst.id, r.cid, tx, ty, d.rot, not d.single and d.inst.uid or nil))
end

function PANEL:PaintDrag()
    local d = self.drag
    local s = self.s
    local r, tx, ty = self:DragTarget(d)
    local t2 = math.max(1, math.floor(2 * s))

    if r and Inv.cont[r.cid] then
        local ok = self:DropAllowed(d, r, tx, ty)
        local x, y, pw, ph
        if r.slot then
            x, y, pw, ph = r.x, r.y, r.pw, r.ph
        elseif r.shelves then
            local c = self.cols.ext
            x, y, pw, ph = r.x, c.top, r.pw, c.view
        else
            local w, h = Items.Size(d.inst.id, d.rot)
            x, y, pw, ph = r.x + tx * self.step, r.y + ty * self.step, self:SpanPx(w), self:SpanPx(h)
        end
        setCol(ok and C_BLUE or C_RED, ok and 22 or 50)
        surface.DrawRect(x, y, pw, ph)
        if ok then
            surface.SetDrawColor(C_BLUE)
            dashed(x, y, pw, ph, math.max(3, math.floor(6 * s)), t2)
        else
            surface.SetDrawColor(C_RED)
            surface.DrawOutlinedRect(x, y, pw, ph, t2)
        end
        if ok and r.cid == EXT and Inv.ext and Inv.ext.depot then
            draw.SimpleTextOutlined("HAND IN (DISCARD)", self:Font(13, 700), x + pw * 0.5, y + ph * 0.5, C_BLUE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, C_TEXT_EDGE)
        end
    elseif not d.fromExt and not d.fromHotbar then
        -- not over a grid or slot: letting go drops it
        local mx, my = self:CursorPos()
        if not self:HotbarAt(mx, my) then
            draw.SimpleTextOutlined("DROP", self:Font(14, 700), mx, my - math.floor(30 * s), C_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, C_TEXT_EDGE)
        end
    end

    -- The item follows the cursor.
    local mx, my = self:CursorPos()
    local w, h = Items.Size(d.inst.id, d.rot)
    local gc = d.single and 1 or d.inst.count
    -- (from a depot you take one stack, not the shelf's count)
    if d.fromExt and Inv.ext and Inv.ext.depot then gc = math.max(1, math.min(gc, takeAmount(d.inst))) end
    local ghost = self.ghost
    if not ghost then ghost = {} self.ghost = ghost end
    ghost.id, ghost.rot, ghost.count, ghost.data, ghost.c = d.inst.id, d.rot, gc, d.inst.data, nil
    self:DrawItemBox(ghost, mx - d.offX * self.step - self.cell * 0.5, my - d.offY * self.step - self.cell * 0.5,
        self:SpanPx(w), self:SpanPx(h), 200)
end

--------------------------------------------------------------------------
-- Mouse
--------------------------------------------------------------------------

function PANEL:OnMousePressed(code)
    local mx, my = self:CursorPos()
    if code == MOUSE_LEFT then
        for i = 1, self.nb do
            local b = self.buttons[i]
            if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
                b.fn(self, b.arg)
                return
            end
        end
    end

    -- Hotbar row: right-click empties a slot, left-drag moves or removes it.
    local hb = self:HotbarAt(mx, my)
    if hb then
        local inst = Inv.HotbarItem(hb)
        if not inst then return end
        if code == MOUSE_RIGHT then
            Inv.RequestHotbar(nil, hb)
        elseif code == MOUSE_LEFT then
            self.drag = { inst = inst, rot = inst.rot, offX = 0, offY = 0, fromHotbar = hb, single = false }
            self:MouseCapture(true)
        end
        return
    end

    local inst, r, cx, cy = self:ItemAtCursor()
    if not inst then return end
    local fromExt = r.cid == EXT
    -- (bulk-only storages: just the buttons)
    if fromExt and Inv.ext and Inv.ext.bulkOnly then
        Inv.note, Inv.noteTime = "Use Take all", RealTime()
        return
    end

    if code == MOUSE_LEFT then
        local offX, offY = 0, 0
        if not r.slot and not r.shelves then offX, offY = cx - inst.x, cy - inst.y end
        if fromExt then self.selExt = inst.uid end   -- (the card keeps showing it)
        local single = ctrlDown() and (inst.count > 1 or (fromExt and Inv.ext and Inv.ext.depot))
        self.drag = { inst = inst, rot = inst.rot, offX = offX, offY = offY, fromExt = fromExt, single = single or false }
        self:MouseCapture(true)
    elseif code == MOUSE_RIGHT and fromExt then
        self:QueueQuick(inst, ctrlDown())
    elseif code == MOUSE_RIGHT and not fromExt then
        local def = Items.Get(inst.id)
        local menu = DermaMenu()
        if inst.count > 1 then
            menu:AddOption("Split stack", function() Inv.RequestSplit(inst) end)
        end
        -- Equip = put it on the hotbar (first free slot); Unequip = take it off.
        -- (worn weapons, e.g. a riot shield on the back slot, still go on the hotbar)
        if def and (def.weapon or (not Items.IsWorn(inst.c) and not def.slot)) then
            if inst.hb then
                menu:AddOption("Unequip", function() Inv.RequestHotbar(nil, inst.hb) end)
            else
                menu:AddOption("Equip", function()
                    local free
                    for n = 1, Items.HotbarSize(Inv) do
                        if not Inv.HotbarItem(n) then free = n break end
                    end
                    if not free then
                        Inv.note, Inv.noteTime = "Hotbar full: empty a slot first", RealTime()
                        return
                    end
                    Inv.RequestHotbar(inst, free)
                end)
            end
        end
        local wearCid = def and def.slot and Items.WORN_BY_SLOT[def.slot]
        if wearCid and inst.c ~= wearCid then
            local okWear, why = Items.CanWear(LocalPlayer(), def)
            if okWear then
                menu:AddOption("Wear", function() Inv.RequestMove(inst, wearCid, 0, 0, false) end)
            else
                menu:AddOption("Can't wear: " .. (why or "not on your model"), function() end)
            end
        elseif wearCid and inst.c == wearCid and not def.slotOnly then   -- (slot-only: nowhere else to put it; drop it instead)
            menu:AddOption("Take off", function()
                -- First free spot in the main grid, then the backpack.
                for _, cid in ipairs({ MAIN, BACK }) do
                    local c = Inv.cont[cid]
                    if c then
                        for y = 0, c.h - 1 do
                            for x = 0, c.w - 1 do
                                for _, rot in ipairs({ false, true }) do
                                    if Items.CanPlace(Inv, inst.id, cid, x, y, rot) then
                                        Inv.RequestMove(inst, cid, x, y, rot)
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
                Inv.ShowNote("No room to take it off")
            end)
        end
        -- Give to the player you're looking at (look at them, then open the inventory).
        local target = Inv.GiveTarget()
        if target then
            if inst.count > 1 then
                menu:AddOption("Give 1 to " .. target:Nick(), function() Inv.RequestGive(inst, true, target) end)
                menu:AddOption("Give all to " .. target:Nick(), function() Inv.RequestGive(inst, false, target) end)
            else
                menu:AddOption("Give to " .. target:Nick(), function() Inv.RequestGive(inst, false, target) end)
            end
        end
        -- Contraband can be hidden from searches (up to Items.HIDE_MAX).
        if Items.IsContraband(inst.id) and not Items.IsWorn(inst.c) then
            if inst.data and inst.data.hidden then
                menu:AddOption("Unhide", function() Inv.RequestHide(inst) end)
            else
                local n = 0
                for _, o in pairs(Inv.byUid) do if o.data and o.data.hidden then n = n + 1 end end
                if n < Items.HIDE_MAX then
                    menu:AddOption("Hide (" .. n .. "/" .. Items.HIDE_MAX .. " hidden)", function() Inv.RequestHide(inst) end)
                end
            end
        end
        hook.Run("Rhylib.ItemMenu", inst, menu)   -- (other addons add options; return nothing)
        if LocalPlayer():IsAdmin() and Icons.OpenEditor then
            -- (staff: tune this item's picture for everyone, cl_15_icons)
            menu:AddOption("Adjust picture", function() Icons.OpenEditor(inst.id) end)
        end
        menu:AddOption("Drop", function() Inv.RequestDrop(inst) end)
        menu:Open()
    end
end

function PANEL:OnMouseReleased(code)
    if code ~= MOUSE_LEFT or not self.drag then return end
    self:MouseCapture(false)
    local d = self.drag
    self.drag = nil
    local mx, my = self:CursorPos()
    local pw, ph = self:GetSize()
    local outside = mx < 0 or my < 0 or mx > pw or my > ph

    -- Onto the hotbar: put it in that slot. A slot dragged anywhere else empties.
    local hb = not d.fromExt and self:HotbarAt(mx, my)
    if hb then
        if hb ~= d.fromHotbar then Inv.RequestHotbar(d.inst, hb) end
        return
    end
    if d.fromHotbar then
        Inv.RequestHotbar(nil, d.fromHotbar)
        return
    end

    if d.fromExt then
        local c = Inv.cont[EXT]
        if outside or not c or not c.items[d.inst.uid] then return end
        local r, tx, ty = self:DragTarget(d)
        if not r then return end
        if r.cid ~= EXT then
            Inv.RequestTake(d.inst, r.cid, tx, ty, d.rot, d.single)
        elseif not Inv.ext.depot and (tx ~= d.inst.x or ty ~= d.inst.y or d.rot ~= d.inst.rot) then
            Inv.RequestExtMove(d.inst, tx, ty, d.rot, d.single)
        end
        return
    end

    if not Inv.byUid[d.inst.uid] then return end
    if outside then
        Inv.RequestDrop(d.inst, d.single)
        return
    end

    local r, tx, ty = self:DragTarget(d)
    if not r then
        -- (let go anywhere that isn't a grid or slot, inside the window
        -- too, and it's dropped)
        Inv.RequestDrop(d.inst, d.single)
        return
    end
    if r.cid ~= d.inst.c or tx ~= d.inst.x or ty ~= d.inst.y or d.rot ~= d.inst.rot then
        Inv.RequestMove(d.inst, r.cid, tx, ty, d.rot, d.single)
    end
end

function PANEL:Think()
    -- R rotates the item being dragged.
    local r = input.IsKeyDown(KEY_R)
    if r and not self.rDown and self.drag then
        local d = self.drag
        local w, h = Items.Size(d.inst.id, d.rot)
        if w ~= h then
            d.rot = not d.rot
            d.offX, d.offY = math.min(d.offY, h - 1), math.min(d.offX, w - 1)
        end
    end
    self.rDown = r

    -- (another storage, or none: forget the picked one)
    local ec = Inv.cont[EXT]
    if self.selFor ~= ec then
        self.selFor = ec
        if not (ec and self.selExt and ec.items[self.selExt]) then self.selExt = nil end
    end
    self:ThinkQuick()
    if not LocalPlayer():Alive() then self:Remove() end
end

-- Closing the window closes the locker / armoury too.
function PANEL:OnRemove()
    Inv.CloseExt()
end

vgui.Register("RhylibInventory", PANEL, "EditablePanel")

--------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------

-- Inv.Toggle(): opens or closes the window (not while dead or locked).
-- The window lets you keep walking (keyboard not captured).
function Inv.Toggle()
    if IsValid(Inv.panel) then
        Inv.panel:Remove()
        return
    end
    if not LocalPlayer():Alive() then return end
    if hook.Run("Rhylib.InventoryLocked", LocalPlayer()) == true then return end  -- cuffed, stunned (rhylib_mp)
    local p = vgui.Create("RhylibInventory")
    p:Center()
    p:MakePopup()
    p:SetKeyboardInputEnabled(false)  -- you can keep walking with it open
    Inv.panel = p
end

concommand.Add("rhylib_inventory", Inv.Toggle)

local keyWasDown = false
Rhylib.Hook.Add("Think", "inventory.key", function()
    local code = input.GetKeyCode(keyVar:GetString())
    local down = code and code > 0 and input.IsKeyDown(code)
    if down and not keyWasDown then
        local blocked = gui.IsGameUIVisible() or gui.IsConsoleVisible() or LocalPlayer():IsTyping() or IsValid(vgui.GetKeyboardFocus())
        if not blocked then Inv.Toggle() end
    end
    keyWasDown = down
end)

-- Interaction wheel (rhylib_menus): give opens the inventory; right-click
-- an item there to hand it over.
Rhylib.Hook.Add("Rhylib.WheelOptions", "inventory.wheel", function(t, me, add)
    local Med = Rhylib.Medical
    if Med and Med.IsDown and Med.IsDown(t) then
        add("Give an item", nil, { order = 40, disabled = "Not while they're down" })
        return
    end
    add("Give an item", function(x)
        Inv.giveTo, Inv.giveToAt = x, RealTime()   -- (Inv.GiveTarget prefers them for a while)
        if not IsValid(Inv.panel) then Inv.Toggle() end
        Inv.note, Inv.noteTime = "Right-click an item: Give to " .. x:Nick(), RealTime()
    end, { order = 40, sub = "Opens your inventory" })
end)
