--[[
    Spawn window (Menus.Spawn): our restyled Q menu, opened from the
    toolgun's R (rhylib_toolgun). Tabs: other addons' first (the toolgun
    adds "Rhy's"), then Props (spawnlists), Entities, Weapons, NPCs,
    Vehicles and Tools (with the tool's own settings panel). Everything
    spawns through the normal sandbox commands, so the server's spawn
    rights still apply.

    Look (the house style): one plate with corner ticks, "SPAWN" and the
    key hints on its header (pick mode: "PICK A MODEL", an amber rule and
    an accent outline); a tab strip under it (caps tabs, the shown one
    with an accent underline; they narrow when there are many) with the
    search box on its right. Each tab: a side column plate (categories /
    the props tree / the tool list as rows alternating C.row / C.rowAlt,
    counts right-aligned, the picked row with an accent bar, folders with
    a drawn arrow) and a content plate whose header names what's shown
    and how many. Tiles are cards: the icon on a dark well, the name on a
    header strip, hover C.rowHover, picked = accent edge, ADMIN as an
    amber chip. Spawnlist headers are bands with a diamond; empty results
    a dashed box. The hover preview is a ticked plate.
    The Tools tab hosts sandbox's own control panels (DForm): they keep
    the default skin inside our plate.

    Kept between openings (hidden, not removed), so tabs, scroll and the
    chosen tool stay. The mouse is free but the keyboard stays with the
    game (walk while it's open) until you click a text box.

    Menus.Spawn.AddTab(id, { title, order, build(body), onShow(body),
        search(body, text) }) adds a tab; Open / Close / IsOpen.
      title   tab button text        order   left to right (low first;
                                             Rhy's 0, Props 10, Entities 20,
                                             Weapons 30, NPCs 40, Vehicles 50,
                                             Tools 60)
      build   fills body the first time the tab is shown (errors are caught
              and shown in the tab)
      onShow  every time the tab is shown again (optional)
      search  called as the search box (top right) changes (optional)
    Adding a new tab id rebuilds the window the next time it opens.

    Other helpers: SP.Tile, SP.ModelTile, SP.CatalogueTab (a ready-made
    categories + tiles tab), SP.Preview (hover preview), SP.ModelOf,
    SP.AddToolOption / SP.PickForTool (set by rhylib_toolgun),
    SP.PickModel / SP.TakePick (pick mode for the Server settings page),
    SP.NpcWeapon, SP.IconMat, SP.L, SP.BG (the window's background token).

    Hook Rhylib.SpawnTabItems(tabId, items) runs each time the Entities
    ("entities") or NPCs ("npcs") tab builds its tiles: add items or change
    them (fields as SP.Tile: cat, name, extra, tip, mat, model, run, menu,
    spec, admin, selected). rhylib_toolgun puts the droid spawner there.

    Colours: kit tokens (K.C) and "spawn.bg" (the window's background).

    Client only. Spawning uses the sandbox commands gm_spawn, gm_spawnsent,
    gm_giveswep, gm_spawnswep, gmod_spawnnpc and gm_spawnvehicle.
]]

local Menus = Rhylib.Menus
Menus.Spawn = Menus.Spawn or {}
local SP = Menus.Spawn
SP.tabs = SP.tabs or {}

local K = Menus.Kit
local C = K.C

-- SP.L(s): "#tool.weld.name" style names to text (language phrases).
local function L(s)
    s = tostring(s or "")
    if string.sub(s, 1, 1) == "#" then return language.GetPhrase(string.sub(s, 2)) end
    return s
end
SP.L = L

local function lower(s) return string.lower(L(s)) end

-- SP.IconMat(paths): the first of the given material paths that exists, as
-- a Material, or nil. Cached (false = none).
local mats = {}
local function iconMat(paths)
    for _, p in ipairs(paths) do
        if p and p ~= "" then
            local m = mats[p]
            if m == nil then
                local mat = Material(p, "smooth")
                m = (mat and not mat:IsError()) and mat or false
                mats[p] = m
            end
            if m then return m end
        end
    end
    return nil
end
SP.IconMat = iconMat

-- The window's background (a theme token): the house dark, near solid.
SP.BG = Rhylib.UI.Col("spawn.bg", 14, 16, 15, 250)

--------------------------------------------------------------------------
-- Drawing helpers (house look)
--------------------------------------------------------------------------

local GRAD_L = Material("vgui/gradient-l")

-- (one vertex table, filled per draw: no tables made in Paint)
local DIA = { {}, {}, {}, {} }
local function diamond(cx, cy, r, col)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    K.SetCol(col)
    surface.DrawPoly(DIA)
end

-- A dashed outline (empty results).
local function dashed(x, y, w, h, col, a)
    local d, g = K.S(6), K.S(4)
    K.SetCol(col, a)
    for i = x, x + w - 1, d + g do
        local l = math.min(d, x + w - i)
        surface.DrawRect(i, y, l, 1)
        surface.DrawRect(i, y + h - 1, l, 1)
    end
    for j = y, y + h - 1, d + g do
        local l = math.min(d, y + h - j)
        surface.DrawRect(x, j, 1, l)
        surface.DrawRect(x + w - 1, j, 1, l)
    end
end

-- A chip: caps text (give it upper case) on a pill tinted in col; x is
-- its right edge, y its centre.
local function chipRight(text, x, y, col)
    local S = K.S
    local f = K.Font(10, 700)
    surface.SetFont(f)
    local w, h = surface.GetTextSize(text) + S(10), S(15)
    K.SetCol(C.bg, 220)
    surface.DrawRect(x - w, y - h * 0.5, w, h)
    K.SetCol(col, 45)
    surface.DrawRect(x - w, y - h * 0.5, w, h)
    K.SetCol(col, 160)
    surface.DrawOutlinedRect(x - w, y - h * 0.5, w, h)
    draw.SimpleText(text, f, x - w * 0.5, y, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- A plate column (side list / content): K.Plate with a header that reads
-- getTitle() / getSub() when drawn. Children dock inside under the header.
local COL_HEAD = 30
local function column(parent, getTitle, getSub)
    local S = K.S
    local p = vgui.Create("DPanel", parent)
    p:DockPadding(1, S(COL_HEAD) + 1, 1, 1)
    function p:Paint(w, h)
        local sub = getSub and getSub() or nil
        if sub then sub = K.Fit(sub, K.Font(13), math.max(S(40), w * 0.5)) end
        K.Plate(0, 0, w, h, { bg = C.bg, title = getTitle(), sub = sub, header = S(COL_HEAD) })
    end
    return p
end

-- A row of a side list (categories, the props tree, tools). opts: text,
-- count (dim, right-aligned), depth (indent), arrow() -> "right" / "down"
-- / nil, selected() -> bool, group (a bold band row with a diamond), alt
-- (the darker of the alternating rows), fn (click). Returns the DButton.
local function sideRow(parent, opts)
    local S = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(opts.group and S(32) or S(28))
    local caps = opts.group and isstring(opts.text) and string.upper(opts.text) or nil
    function b:Paint(w, h)
        local sel = opts.selected and opts.selected()
        local hov = self:IsHovered()
        local x = S(10) + S(14) * (opts.depth or 0)
        if opts.group then
            K.SetCol(hov and C.rowHover or C.header)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.accent, 40)
            surface.SetMaterial(GRAD_L)
            surface.DrawTexturedRect(0, 0, w * 0.7, h)
            K.SetCol(C.accent)
            surface.DrawRect(0, 0, S(3), h)
        else
            K.SetCol(sel and C.buttonDown or (hov and C.rowHover or (opts.alt and C.rowAlt or C.row)))
            surface.DrawRect(0, 0, w, h)
            if sel then
                K.SetCol(C.accent)
                surface.DrawRect(0, 0, S(3), h)
            end
        end
        local ar = opts.arrow and opts.arrow()
        if ar then
            K.Arrow(x + S(4), h * 0.5, S(8), ar, (sel or hov) and C.text or C.textDim)
            x = x + S(14)
        elseif opts.group then
            diamond(x + S(4), h * 0.5, S(4), C.accent)
            x = x + S(14)
        end
        local right = w - S(10)
        if opts.count then
            local f = K.Font(11, 700)
            draw.SimpleText(opts.count, f, right, h * 0.5, sel and C.text or C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            surface.SetFont(f)
            right = right - surface.GetTextSize(opts.count) - S(8)
        end
        local text = isfunction(opts.text) and opts.text() or opts.text
        local f = opts.group and K.Font(13, 700) or K.Font(13, sel and 700 or 500)
        if caps then text = caps end
        draw.SimpleText(K.Fit(text, f, right - x), f, x, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        K.SetCol(C.edgeDark, 160)
        surface.DrawRect(0, h - 1, w, 1)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        if opts.fn then opts.fn() end
    end
    return b
end

-- A non-clickable caps line in a side list (a tool category).
local function sideCaps(parent, text)
    local S = K.S
    local p = vgui.Create("DPanel", parent)
    p:SetTall(S(24))
    local t = string.upper(text)
    function p:Paint(w, h)
        K.Caps(K.Fit(t, K.Font(12, 700), w - S(16)), S(10), h * 0.5 + S(2))
    end
    return p
end

-- Panels on their own line in a DIconLayout keep its width.
local function fullLine(p, layout)
    p.OwnLine = true
    p:SetWide(math.max(1, layout:GetWide()))
    function p:Think()
        local lw = layout:GetWide()
        if lw > 0 and self:GetWide() ~= lw then self:SetWide(lw) end
    end
end

-- A band (spawnlist header) on its own line: diamond, caps text, rule.
local function bandLine(layout, text)
    local S = K.S
    local h = vgui.Create("DPanel", layout)
    fullLine(h, layout)
    h:SetTall(S(30))
    local t = string.upper(text or "")
    function h:Paint(w, hh)
        K.SetCol(C.accent, 30)
        surface.SetMaterial(GRAD_L)
        surface.DrawTexturedRect(0, S(2), w * 0.6, hh - S(6))
        K.SetCol(C.accent)
        surface.DrawRect(0, S(2), S(3), hh - S(6))
        diamond(S(16), hh * 0.5 - S(1), S(5), C.accent)
        draw.SimpleText(K.Fit(t, K.Font(13, 700), w - S(40)), K.Font(13, 700), S(28), hh * 0.5 - S(1), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        K.SetCol(C.accent, 90)
        surface.DrawRect(0, hh - S(4), w, 1)
    end
    return h
end

-- An empty-result box on its own line: dashed outline, dim text.
local function emptyLine(layout, text)
    local S = K.S
    local p = vgui.Create("DPanel", layout)
    fullLine(p, layout)
    p:SetTall(S(64))
    function p:Paint(w, h)
        K.SetCol(C.row, 120)
        surface.DrawRect(0, 0, w, h)
        dashed(0, 0, w, h, C.edgeLight, 200)
        local f = K.Font(14)
        draw.SimpleText(K.Fit(text, f, w - S(24)), f, w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return p
end

-- SP.AddTab(id, def): adds or replaces a tab (see the header).
function SP.AddTab(id, def)
    def.id = id
    if not SP.tabs[id] then SP.dirty = true end   -- (a re-add of the same tab needs no rebuild)
    SP.tabs[id] = def
end

--------------------------------------------------------------------------
-- Tiles and catalogue tabs
--------------------------------------------------------------------------

-- SP.Tile(parent, it): a tile (SP.TILE_W x SP.TILE_H): icon (or initials) and a two-line name.
-- it = { name, mat (Material), model (path: a 3D picture when there's no
-- mat, and the hover preview), run() on click, menu(m) adds right-click
-- options, spec (for "Spawn with Rhy's toolgun"), admin (ADMIN tag),
-- selected() (accent outline), tip (tooltip), extra (shown in the preview,
-- and searched) }. In pick mode a click hands the tile's model over instead.
-- Returns the DButton (add it to a DIconLayout).
-- Tile size (1080p units): big icons and two lines for the name, so a
-- tile reads at a glance.
SP.TILE_W, SP.TILE_H, SP.TILE_NAME = 148, 156, 40

-- (a name on up to two lines that fit w: word wrap, the rest cut with …)
local function twoLines(name, font, w)
    surface.SetFont(font)
    if surface.GetTextSize(name) <= w then return name, nil end
    local words, a = string.Explode(" ", name), ""
    local i = 1
    while i <= #words do
        local try = a == "" and words[i] or (a .. " " .. words[i])
        if surface.GetTextSize(try) > w then break end
        a = try
        i = i + 1
    end
    if a == "" then return K.Fit(name, font, w), nil end
    return a, K.Fit(table.concat(words, " ", i), font, w)
end

function SP.Tile(parent, it)
    local S = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetSize(S(SP.TILE_W), S(SP.TILE_H))
    if it.tip then b:SetTooltip(it.tip) end
    local name = L(it.name)
    local initials = string.upper(string.sub(name, 1, 2))
    function b:Paint(w, h)
        local sel = it.selected and it.selected()
        local hov = self:IsHovered()
        K.SetCol(hov and C.rowHover or C.row)
        surface.DrawRect(0, 0, w, h)
        local nh = S(SP.TILE_NAME)
        local is = h - nh - S(2)
        -- (the icon's dark well)
        K.SetCol(C.bg)
        surface.DrawRect(S(4), S(4), w - S(8), is - S(4))
        if it.mat then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(it.mat)
            local pad = S(8)
            surface.DrawTexturedRect((w - is) * 0.5 + pad, pad, is - pad * 2, is - pad * 2)
        elseif self.modelPic then
            -- (the 3D picture is a child panel, drawn over this)
        else
            draw.SimpleText(initials, K.Font(26, 700), w * 0.5, is * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        K.SetCol(C.header)
        surface.DrawRect(0, h - nh, w, nh)
        K.SetCol(sel and C.accent or C.edgeDark)
        surface.DrawRect(0, h - nh, w, sel and 2 or 1)
        local f = K.Font(13, 600)
        if self.nameW ~= w then self.nameW, self.l1, self.l2 = w, twoLines(name, f, w - S(10)) end
        if self.l2 then
            draw.SimpleText(self.l1, f, w * 0.5, h - nh * 0.72, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(self.l2, f, w * 0.5, h - nh * 0.30, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(self.l1, f, w * 0.5, h - nh * 0.5, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        K.SetCol(sel and C.accent or (hov and C.edgeLight or C.edgeDark), (hov and not sel) and 140 or 255)
        surface.DrawOutlinedRect(0, 0, w, h, sel and 2 or 1)
        if not sel then
            K.SetCol(C.edgeLight)
            surface.DrawLine(1, 1, w - 1, 1)
        end
        return true
    end
    -- (drawn over the 3D picture child too)
    if it.admin then
        function b:PaintOver(w, h) chipRight("ADMIN", w - K.S(5), K.S(12), C.warn) end
    end
    -- No icon image but a model (our own toolgun entries): the engine's
    -- spawn icon of it, made once and kept on disk like the Q menu's.
    if not it.mat and isstring(it.model) and it.model ~= "" then
        local pad = S(8)
        local is = S(SP.TILE_H) - S(SP.TILE_NAME) - S(2)
        local mi = vgui.Create("ModelImage", b)
        mi:SetMouseInputEnabled(false)
        util.PrecacheModel(it.model)   -- (loaded first, or its spawn icon comes out empty)
        mi:SetModel(it.model)
        mi:SetPos(pad, pad)
        mi:SetSize(is - pad * 2 + S(10), is - pad * 2)
        mi:SetPos((S(SP.TILE_W) - mi:GetWide()) * 0.5, pad)
        b.modelPic = mi
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclickrelease.wav")
        if SP.pick then
            local m = SP.ModelOf(it)
            if m then SP.TakePick(m) else surface.PlaySound("buttons/button10.wav") end
            return
        end
        if it.run then it.run() end
    end
    local entered = b.OnCursorEntered
    function b:OnCursorEntered(...)
        if entered then entered(self, ...) end
        SP.Preview(self, { model = SP.ModelOf(it), mat = it.mat, title = name, sub = it.extra or (it.spec and it.spec.name) })
    end
    function b:DoRightClick()
        if not (it.menu or (it.spec and SP.PickForTool)) then return end
        local m = K.Menu()
        SP.AddToolOption(m, it.spec)
        if it.menu then it.menu(m) end
        m:Open()
    end
    return b
end

-- "Spawn with Rhy's toolgun" (rhylib_toolgun sets SP.PickForTool):
-- spec = { kind = prop|entity|npc|vehicle|weapon, name, skin, body, wep, label }.
function SP.AddToolOption(m, spec)
    if not (spec and SP.PickForTool) then return end
    m:AddOption("Spawn with Rhy's toolgun", function() SP.PickForTool(spec) end)
    m:AddSpacer()
end

-- SP.ModelTile(parent, model, skin, body, run): a model tile (props): the
-- engine's spawn icon with our outline. body = bodygroup digits string.
-- run() on click (not in pick mode). Right-click: toolgun / copy path.
function SP.ModelTile(parent, model, skin, body, run)
    local S = K.S
    local ic = vgui.Create("SpawnIcon", parent)
    ic:SetSize(S(84), S(84))
    ic:SetModel(model, skin or 0, body ~= "" and body or nil)
    ic:SetTooltip(model)
    ic.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        if SP.TakePick(model) then return end
        run()
    end
    ic.OpenMenu = function()
        local m = K.Menu()
        SP.AddToolOption(m, { kind = "prop", name = model, skin = skin or 0, body = body or "", label = string.GetFileFromFilename(model) })
        m:AddOption("Copy model path", function() SetClipboardText(model) end)
        m:Open()
    end
    function ic:PaintOver(w, h)
        local hov = self:IsHovered()
        K.SetCol(hov and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h, hov and 2 or 1)
        if not hov then
            K.SetCol(C.edgeLight)
            surface.DrawLine(1, 1, w - 1, 1)
        end
    end
    local entered = ic.OnCursorEntered
    function ic:OnCursorEntered(...)
        if entered then entered(self, ...) end
        SP.Preview(self, { model = model, skin = skin, body = body, title = string.GetFileFromFilename(model), sub = model })
    end
    return ic
end

--------------------------------------------------------------------------
-- Hover preview (helps find the right model): after a
-- short hover, a big turning view of the model under the mouse (or the
-- tile's icon, enlarged, when there's no model) next to the cursor.
-- One panel, drawn on top, never takes the mouse; a Think hook exists
-- only while something is hovered.
--------------------------------------------------------------------------

local PREVIEW_DELAY = 0.18

-- The model behind a tile, if we can find one (weapons, NPCs, vehicles,
-- entities that name a model).
function SP.ModelOf(it)
    if it.model then return it.model end
    local sp = it.spec
    if not sp then return nil end
    local m
    if sp.kind == "weapon" then
        local w = weapons.Get(sp.name)
        m = w and (w.PropModel or w.WorldModel)
    elseif sp.kind == "npc" then
        m = sp.npc and sp.npc.Model
    elseif sp.kind == "vehicle" then
        local v = (list.Get("Vehicles") or {})[sp.name]
        m = v and v.Model
    elseif sp.kind == "entity" then
        local e = scripted_ents.GetStored(sp.name)
        m = e and e.t and e.t.Model
    end
    -- (file check: IsValidModel is false on clients for models not loaded yet)
    if isstring(m) and m ~= "" and (util.IsValidModel(m) or file.Exists(m, "GAME")) then return m end
    return nil
end

local function previewPanel()
    if IsValid(SP.pv) then return SP.pv end
    local S = K.S
    local p = vgui.Create("DPanel")
    p:SetDrawOnTop(true)
    p:SetMouseInputEnabled(false)
    p:SetKeyboardInputEnabled(false)
    p:SetVisible(false)
    p:SetSize(S(340), S(392))
    local view = S(328)
    local mdl = vgui.Create("DModelPanel", p)
    mdl:SetMouseInputEnabled(false)
    mdl:SetPos(S(6), S(6))
    mdl:SetSize(view, view)
    mdl:SetFOV(35)
    -- the camera circles the model (turning the model would swing it
    -- about its origin, off centre)
    function mdl:LayoutEntity(ent)
        local c, d = p.center, p.dist
        if not c then return end
        local a = math.rad((RealTime() - (p.shownAt or 0)) * 40 + 35)
        self:SetCamPos(c + Vector(math.cos(a), math.sin(a), 0.45):GetNormalized() * d)
        self:SetLookAt(c)
    end
    p.mdl = mdl
    function p:Paint(w, h)
        K.Plate(0, 0, w, h, { bg = SP.BG, ticks = "all" })
        K.SetCol(C.bg)
        surface.DrawRect(S(6), S(6), view, view)
        local info = self.info
        if not info then return end
        if not info.model and info.mat then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(info.mat)
            surface.DrawTexturedRect(S(6) + S(24), S(6) + S(24), view - S(48), view - S(48))
        elseif not info.model then
            draw.SimpleText("No preview", K.Font(16, 600), S(6) + view * 0.5, S(6) + view * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        K.SetCol(C.accent, 180)
        surface.DrawRect(S(6), S(6) + view + S(1), view, 2)
        draw.SimpleText(K.Fit(info.title or "", K.Font(14, 700), w - S(16)), K.Font(14, 700), S(10), S(6) + view + S(18), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if info.sub then
            draw.SimpleText(K.Fit(info.sub, K.Font(12), w - S(16)), K.Font(12), S(10), S(6) + view + S(37), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    function p:PaintOver(w, h)
        surface.SetDrawColor(C.edgeDark)
        surface.DrawOutlinedRect(S(6), S(6), view, view)
    end
    SP.pv = p
    return p
end

local function hidePreview()
    SP.pvOwner, SP.pvInfo = nil, nil
    if IsValid(SP.pv) then
        SP.pv:SetVisible(false)
        SP.pv.info = nil
    end
    Rhylib.Hook.Remove("Think", "menus.spawnpreview")
end
SP.HidePreview = hidePreview

local function placePreview(p)
    local mx, my = input.GetCursorPos()
    local w, h = p:GetSize()
    local gap = K.S(22)
    local x, y = mx + gap, my + gap
    if x + w > ScrW() then x = mx - gap - w end
    if y + h > ScrH() then y = ScrH() - h - K.S(4) end
    p:SetPos(math.max(0, x), math.max(0, y))
end

local function previewThink()
    local o = SP.pvOwner
    -- (owners outside the spawn window, e.g. Server settings model pictures, work while it's shut)
    local inWin = IsValid(o) and IsValid(SP.win) and o:HasParent(SP.win)
    if not (IsValid(o) and o:IsVisible() and o:IsHovered() and (not inWin or SP.IsOpen())) then hidePreview() return end
    if RealTime() - SP.pvAt < PREVIEW_DELAY then return end
    local p = previewPanel()
    local info = SP.pvInfo
    if p.info ~= info then
        p.info = info
        p.center = nil
        if info.model then
            p.mdl:SetVisible(true)
            util.PrecacheModel(info.model)
            p.mdl:SetModel(info.model)
            local ent = p.mdl.Entity
            if IsValid(ent) then
                ent:SetSkin(tonumber(info.skin) or 0)
                if info.body and info.body ~= "" then ent:SetBodyGroups(info.body) end
                local mn, mx = ent:GetRenderBounds()
                local size = math.max(mx:Distance(mn), 1)
                p.center = (mn + mx) * 0.5
                p.dist = size * 1.6
                if p.mdl.SetFarZ then p.mdl:SetFarZ(p.dist * 4 + 512) end
            end
        else
            p.mdl:SetVisible(false)
        end
        p.shownAt = RealTime()
        p:SetVisible(true)
        p:MoveToFront()
    end
    placePreview(p)
end

-- SP.Preview(owner, info): start (or switch) the preview for a hovered
-- panel. info = { model, skin, body, mat, title, sub }. It hides itself
-- once owner is no longer hovered. Usable from any panel, not only tiles
-- (the Server settings pictures use it).
-- Example: function pnl:OnCursorEntered() Rhylib.Menus.Spawn.Preview(self, { model = mdl, title = "Locker" }) end
function SP.Preview(owner, info)
    SP.pvOwner, SP.pvInfo, SP.pvAt = owner, info, RealTime()
    if IsValid(SP.pv) and SP.pv:IsVisible() then SP.pvAt = 0 end   -- (already showing: switch at once)
    Rhylib.Hook.Add("Think", "menus.spawnpreview", previewThink)
end

-- SP.CatalogueTab(getItems, catOrder): returns a tab def (build + search)
-- with categories on the left and tiles on the right. Set title/order on
-- it, then SP.AddTab it.
-- getItems() = { { cat, name, ...SP.Tile fields } } (built when first shown).
-- A search shows matches from every category.
-- catOrder (optional): category names that come first, in that order;
-- the rest follow alphabetically.
function SP.CatalogueTab(getItems, catOrder)
    local tab = {}
    function tab.build(body)
        local S = K.S
        local items = getItems()
        local cats, order = {}, {}
        for _, it in ipairs(items) do
            local c = L(it.cat or "Other")
            if not cats[c] then cats[c] = {} order[#order + 1] = c end
            table.insert(cats[c], it)
        end
        local rank = {}
        for i, c in ipairs(catOrder or {}) do rank[L(c)] = i end
        table.sort(order, function(a, b)
            local ra, rb = rank[a] or 1000, rank[b] or 1000
            if ra ~= rb then return ra < rb end
            return string.lower(a) < string.lower(b)
        end)
        for _, c in ipairs(order) do
            table.sort(cats[c], function(a, b) return lower(a.name) < lower(b.name) end)
        end

        local chosen = order[1]
        local query = ""
        local subText = ""   -- (the content header's count, made in fill)
        local catCount = tostring(#order)

        local sideCol = column(body, function() return "Categories" end, function() return catCount end)
        sideCol:Dock(LEFT)
        sideCol:SetWide(S(240))
        sideCol:DockMargin(0, 0, S(10), 0)
        local side = K.Scroll(sideCol)
        side:Dock(FILL)
        side:DockMargin(S(4), S(4), S(2), S(4))
        local gridCol = column(body, function()
            if query ~= "" then return "Search" end
            return chosen or "Nothing installed"
        end, function() return subText end)
        gridCol:Dock(FILL)
        local grid = K.Scroll(gridCol)
        grid:Dock(FILL)
        grid:DockMargin(S(8), S(8), S(2), S(8))
        local layout = vgui.Create("DIconLayout", grid)
        layout:Dock(TOP)
        layout:SetSpaceX(S(6))
        layout:SetSpaceY(S(6))
        layout:DockMargin(0, 0, S(8), 0)

        local function fill()
            layout:Clear()
            local n = 0
            for _, c in ipairs(order) do
                if query ~= "" or c == chosen then
                    for _, it in ipairs(cats[c]) do
                        if query == "" or string.find(lower(it.name), query, 1, true)
                            or (it.extra and string.find(string.lower(it.extra), query, 1, true)) then
                            layout:Add(SP.Tile(layout, it))
                            n = n + 1
                        end
                    end
                end
            end
            if query ~= "" then subText = n .. (n == 1 and " match" or " matches")
            else subText = n .. (n == 1 and " item" or " items") end
            if n == 0 then
                layout:Add(emptyLine(layout, query ~= "" and "Nothing matches." or "Nothing here."))
            end
            layout:InvalidateLayout(true)
            grid:GetVBar():SetScroll(0)
        end
        for i, c in ipairs(order) do
            local b = sideRow(side, { text = c, count = tostring(#cats[c]), alt = i % 2 == 0,
                selected = function() return query == "" and chosen == c end,
                fn = function()
                    chosen = c
                    fill()
                end })
            b:Dock(TOP)
            b:DockMargin(0, 0, S(8), 0)
        end
        if #order == 0 then K.Label(side, "Nothing installed.", 13, nil, C.textDim):Dock(TOP) end
        body.search = function(q)
            query = string.lower(q or "")
            fill()
        end
        fill()
    end
    function tab.search(body, q) if body.search then body.search(q) end end
    return tab
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- The window is kept in SP.win (not a local), so a Lua refresh doesn't orphan it.

local function sortedTabs()
    local list = {}
    for _, t in pairs(SP.tabs) do list[#list + 1] = t end
    table.sort(list, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then return (a.order or 50) < (b.order or 50) end
        return a.id < b.id
    end)
    return list
end

local function build()
    if IsValid(SP.win) then
        -- (hand tool settings panels back first: sandbox keeps them and
        -- would hand out a removed panel otherwise)
        for _, b in pairs(SP.win.bodies or {}) do
            if IsValid(b) and IsValid(b.panelScroll) then
                for _, ch in ipairs(b.panelScroll:GetCanvas():GetChildren()) do
                    if ch.ClassName == "ControlPanel" or ch.GetInitialized then
                        ch:SetVisible(false)
                        ch:SetParent(vgui.GetWorldPanel())
                    end
                end
            end
        end
        SP.win:Remove()
    end
    local S = K.S
    local f = vgui.Create("EditablePanel")
    SP.win = f
    f:SetSize(math.min(S(1500), ScrW() - S(80)), math.min(S(900), ScrH() - S(80)))
    f:Center()
    f:SetVisible(false)
    f:DockPadding(S(12), S(46), S(12), S(12))
    f.bodies = {}
    function f:Paint(w, h)
        if SP.pick then
            K.Plate(0, 0, w, h, { bg = SP.BG, title = "Pick a model", sub = "For " .. (SP.pick.label or "the setting") .. " · click any model or entity · Esc: cancel", ticks = "all", header = S(34), rule = C.warn })
            K.SetCol(C.accent)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
            return
        end
        K.Plate(0, 0, w, h, { bg = SP.BG, title = "Spawn", sub = "R: close · hold R: peek · R twice: the old Q menu · Esc: close", ticks = "all", header = S(34) })
    end
    -- (clicking the window takes the keyboard back from a text box)
    function f:OnMousePressed()
        local fp = vgui.GetKeyboardFocus()
        if IsValid(fp) then fp:KillFocus() end
        self:SetKeyboardInputEnabled(false)
    end

    -- The tab strip: caps tabs (accent underline on the shown one), the
    -- search box on the right.
    local bar = vgui.Create("DPanel", f)
    bar:Dock(TOP)
    bar:SetTall(S(48))
    bar:DockMargin(0, 0, 0, S(10))
    function bar:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
    end
    local search
    search = K.Search(bar, "Search this tab...", function(v)
        local body = f.bodies[f.tabId]
        local def = SP.tabs[f.tabId]
        if not (IsValid(body) and def and def.search) then return end
        if v == (body.lastSearch or "") then return end
        body.lastSearch = v
        def.search(body, v)
    end)
    search:Dock(RIGHT)
    search:SetWide(S(300))
    f.searchBox = search

    local content = vgui.Create("DPanel", f)
    content:Dock(FILL)
    content.Paint = nil

    local function show(id)
        f.tabId = id
        for tid, b in pairs(f.bodies) do b:SetVisible(tid == id) end
        local def = SP.tabs[id]
        if not def then return end
        local body = f.bodies[id]
        if not IsValid(body) then
            body = vgui.Create("DPanel", content)
            body:Dock(FILL)
            body.Paint = nil
            f.bodies[id] = body
            local ok, err = pcall(def.build, body)
            if not ok then
                K.Label(body, "This tab failed to build: " .. tostring(err), 13, nil, C.bad):Dock(TOP)
                ErrorNoHalt("[Rhylib] spawn tab " .. id .. ": " .. tostring(err) .. "\n")
            end
        end
        body:SetVisible(true)
        if def.onShow then def.onShow(body) end
        search:SetText(body.lastSearch or "")
    end
    f.ShowTab = show

    local tabs = {}
    for _, def in ipairs(sortedTabs()) do
        local t = vgui.Create("DButton", bar)
        t:SetText("")
        t.caps = string.upper(def.title or def.id)
        local id = def.id
        function t:Paint(w, h)
            local on = f.tabId == id
            if on then
                K.SetCol(C.buttonDown, 140)
                surface.DrawRect(0, 1, w, h - 2)
                K.SetCol(C.accent)
                surface.DrawRect(S(4), h - S(3), w - S(8), S(3))
            elseif self:IsHovered() then
                K.SetCol(C.buttonHover, 120)
                surface.DrawRect(0, 1, w, h - 2)
            end
            local font = K.Font(16, 700)
            draw.SimpleText(K.Fit(self.caps, font, w - S(8)), font, w * 0.5, h * 0.5, (on or self:IsHovered()) and C.text or C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            K.SetCol(C.edgeDark, 160)
            surface.DrawRect(w - 1, S(8), 1, h - S(16))
            return true
        end
        function t:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            show(id)
        end
        tabs[#tabs + 1] = t
    end
    -- (tabs left to right; narrower when many don't fit beside the search)
    function bar:PerformLayout(w, h)
        local room = w - search:GetWide() - S(12)
        surface.SetFont(K.Font(16, 700))
        local widths, total = {}, 0
        for i, t in ipairs(tabs) do
            widths[i] = surface.GetTextSize(t.caps)
            total = total + widths[i]
        end
        local pad = S(40)
        if #tabs > 0 and total + pad * #tabs > room then pad = math.max(S(8), math.floor((room - total) / #tabs)) end
        local x = 0
        for i, t in ipairs(tabs) do
            local tw = widths[i] + pad
            if total + pad * #tabs > room then tw = math.floor(room / #tabs) end
            t:SetPos(x, 0)
            t:SetSize(tw, h)
            x = x + tw
        end
    end
    SP.dirty = false
    show((SP.lastTab and SP.tabs[SP.lastTab]) and SP.lastTab or sortedTabs()[1].id)
end

-- SP.IsOpen(): true while the window is shown.
function SP.IsOpen() return IsValid(SP.win) and SP.win:IsVisible() end

-- SP.Open(): shows the window (built on first use, after a new tab was
-- added, or when the screen size changed). The mouse is free; the
-- keyboard stays with the game.

function SP.Open()
    if not IsValid(SP.win) or SP.dirty or SP.win.builtW ~= ScrW() or SP.win.builtH ~= ScrH() then
        build()
        SP.win.builtW, SP.win.builtH = ScrW(), ScrH()
    end
    SP.win:SetVisible(true)
    SP.win:MakePopup()
    SP.win:SetKeyboardInputEnabled(false)
    local def = SP.tabs[SP.win.tabId]
    if def and def.onShow and IsValid(SP.win.bodies[SP.win.tabId]) then def.onShow(SP.win.bodies[SP.win.tabId]) end
end

-- SP.Close(): hides it (and ends pick mode). True if it was open.
function SP.Close()
    SP.pick = nil
    if not SP.IsOpen() then return false end
    SP.lastTab = SP.win.tabId
    CloseDermaMenus()
    local fp = vgui.GetKeyboardFocus()
    if IsValid(fp) and fp:HasParent(SP.win) then fp:KillFocus() end
    SP.win:SetKeyboardInputEnabled(false)
    SP.win:SetMouseInputEnabled(false)
    SP.win:SetVisible(false)
    hidePreview()
    return true
end

-- SP.PickModel(cb, label): pick mode (Server settings > Models): the window
-- opens on Props and the next model or entity clicked goes to cb(path)
-- instead of spawning. label is shown in the title ("For <label>").
-- Close / Esc cancels (cb is not called).
-- Example: Rhylib.Menus.Spawn.PickModel(function(path) entry:SetText(path) end, "Locker model")
function SP.PickModel(cb, label)
    SP.Open()
    SP.pick = { cb = cb, label = label }
    if IsValid(SP.win) and SP.win.ShowTab and SP.tabs.props then SP.win.ShowTab("props") end
end

-- A tile was clicked in pick mode: hand the model over. True if it was.
function SP.TakePick(model)
    local p = SP.pick
    if not (p and isstring(model) and model ~= "") then return false end
    SP.Close()
    p.cb(model)
    return true
end

-- Esc closes it first.
Menus.RegisterCloser("spawn", function() return SP.Close() end)

-- Text boxes inside (search, tool settings) get the keyboard while focused.
Rhylib.Hook.Add("OnTextEntryGetFocus", "menus.spawn", function(p)
    if SP.IsOpen() and IsValid(p) and p:HasParent(SP.win) then SP.win:SetKeyboardInputEnabled(true) end
end)
Rhylib.Hook.Add("OnTextEntryLoseFocus", "menus.spawn", function(p)
    if SP.IsOpen() and IsValid(p) and p:HasParent(SP.win) then SP.win:SetKeyboardInputEnabled(false) end
end)

--------------------------------------------------------------------------
-- The sandbox tabs
--------------------------------------------------------------------------

local function adminOnly(t) return t.AdminOnly and true or false end

-- SP.NpcWeapon(n): the weapon to give a spawned NPC (n = its list.Get("NPC")
-- row): the player's gmod_npcweapon choice, else one of its own (as sandbox).
function SP.NpcWeapon(n)
    local wcv = GetConVar("gmod_npcweapon")
    local w = wcv and wcv:GetString() or ""
    if w == "" and n and istable(n.Weapons) and #n.Weapons > 0 then w = table.Random(n.Weapons) or "" end
    return w
end

SP.AddTab("entities", SP.CatalogueTab(function()
    local items = {}
    for class, e in pairs(list.Get("SpawnableEntities") or {}) do
        local cls = e.ClassName or class
        items[#items + 1] = {
            cat = e.Category or "Other", name = e.PrintName or cls, extra = cls, admin = adminOnly(e), tip = cls,
            mat = iconMat({ e.IconOverride, "entities/" .. cls .. ".png", "vgui/entities/" .. cls }),
            run = function() RunConsoleCommand("gm_spawnsent", class) end,
            spec = { kind = "entity", name = class, label = L(e.PrintName or cls) },
            menu = function(m) m:AddOption("Copy class name", function() SetClipboardText(cls) end) end,
        }
    end
    hook.Run("Rhylib.SpawnTabItems", "entities", items)
    return items
end))
SP.tabs.entities.title, SP.tabs.entities.order = "Entities", 20

SP.AddTab("weapons", SP.CatalogueTab(function()
    local items = {}
    for _, w in pairs(list.Get("Weapon") or {}) do
        if w.Spawnable and w.ClassName then
            local cls = w.ClassName
            items[#items + 1] = {
                cat = w.Category or "Other", name = w.PrintName or cls, extra = cls, admin = adminOnly(w), tip = cls .. "\nClick: give · right-click: more",
                mat = iconMat({ w.IconOverride, "entities/" .. cls .. ".png", "vgui/entities/" .. cls }),
                run = function() RunConsoleCommand("gm_giveswep", cls) end,
                spec = { kind = "weapon", name = cls, label = L(w.PrintName or cls) },
                menu = function(m)
                    m:AddOption("Give to me", function() RunConsoleCommand("gm_giveswep", cls) end)
                    m:AddOption("Spawn on the ground", function() RunConsoleCommand("gm_spawnswep", cls) end)
                    m:AddOption("Copy class name", function() SetClipboardText(cls) end)
                end,
            }
        end
    end
    return items
end))
SP.tabs.weapons.title, SP.tabs.weapons.order = "Weapons", 30

SP.AddTab("npcs", SP.CatalogueTab(function()
    local items = {}
    for key, n in pairs(list.Get("NPC") or {}) do
        items[#items + 1] = {
            cat = n.Category or "Other", name = n.Name or key, extra = key, admin = adminOnly(n), tip = key,
            mat = iconMat({ n.IconOverride, "entities/" .. key .. ".png", "vgui/entities/" .. key }),
            run = function() RunConsoleCommand("gmod_spawnnpc", key, SP.NpcWeapon(n)) end,
            spec = { kind = "npc", name = key, label = L(n.Name or key), npc = n },
        }
    end
    hook.Run("Rhylib.SpawnTabItems", "npcs", items)
    return items
end))
SP.tabs.npcs.title, SP.tabs.npcs.order = "NPCs", 40

SP.AddTab("vehicles", SP.CatalogueTab(function()
    local items = {}
    for key, v in pairs(list.Get("Vehicles") or {}) do
        items[#items + 1] = {
            cat = v.Category or "Other", name = v.Name or key, extra = key, admin = adminOnly(v), tip = key,
            mat = iconMat({ v.IconOverride, "entities/" .. key .. ".png", "vgui/entities/" .. key }),
            run = function() RunConsoleCommand("gm_spawnvehicle", key) end,
            spec = { kind = "vehicle", name = key, label = L(v.Name or key) },
        }
    end
    return items
end))
SP.tabs.vehicles.title, SP.tabs.vehicles.order = "Vehicles", 50

-- Props: a tree with two groups, collapsible: "Base game" (the spawnlists
-- and the mounted games' model folders) and "Workshop & addons" (every
-- mounted Workshop addon with models, and local addons in addons/).
local open = SP.propsOpen or { base = true, work = true, lists = true }
SP.propsOpen = open
local modelCache = {}   -- [node id] = { models } (addons, listed once)

local MAX_TILES = 600

-- Every .mdl under a folder (path ID), up to a cap.
local function findModels(folder, pathId, out, cap)
    out = out or {}
    if #out >= cap then return out end
    local files, dirs = file.Find(folder .. "*", pathId)
    for _, f in ipairs(files or {}) do
        if string.sub(f, -4) == ".mdl" then
            out[#out + 1] = folder .. f
            if #out >= cap then return out end
        end
    end
    for _, d in ipairs(dirs or {}) do findModels(folder .. d .. "/", pathId, out, cap) end
    return out
end

-- Models in one folder only (games are browsed folder by folder).
local function folderModels(folder, pathId)
    local out = {}
    local files = file.Find(folder .. "*.mdl", pathId)
    for _, f in ipairs(files or {}) do out[#out + 1] = folder .. f end
    return out
end

local function folderNode(id, label, folder, pathId)
    return {
        id = id, label = label,
        kids = function()
            local _, dirs = file.Find(folder .. "*", pathId)
            local list = {}
            for _, d in ipairs(dirs or {}) do
                list[#list + 1] = folderNode(id .. "/" .. d, d, folder .. d .. "/", pathId)
            end
            return list
        end,
        models = function() return folderModels(folder, pathId) end,
    }
end

-- One spawnlist table as a tree (ids are only unique within a table).
local function listTree(tbl, prefix, all)
    local lists = {}
    for _, sl in pairs(tbl or {}) do
        lists[#lists + 1] = sl
        all[#all + 1] = sl
    end
    local kids, roots = {}, {}
    for _, sl in ipairs(lists) do
        local p = tonumber(sl.parentid) or 0
        if p == 0 then roots[#roots + 1] = sl else kids[p] = kids[p] or {} table.insert(kids[p], sl) end
    end
    local function byId(x, y) return (tonumber(x.id) or 0) < (tonumber(y.id) or 0) end
    local seen = {}
    local function make(sl)
        if seen[sl] then return nil end   -- (a broken parent loop)
        seen[sl] = true
        local ch = kids[tonumber(sl.id) or -1]
        local node = { id = prefix .. tostring(sl.id) .. ":" .. tostring(sl.name), label = L(sl.name or "?"), sl = sl }
        if ch then
            table.sort(ch, byId)
            local list = {}
            for _, c in ipairs(ch) do list[#list + 1] = make(c) end   -- (nil from a loop just ends the list)
            node.kids = list
        end
        return node
    end
    table.sort(roots, byId)
    local out = {}
    for _, r in ipairs(roots) do out[#out + 1] = make(r) end
    return out
end

local function spawnlistNodes()
    local all = {}
    -- (filled when the Q menu is first shown; that's off here, so ask)
    local okT, tbl = pcall(spawnmenu.GetPropTable)
    if okT and istable(tbl) and next(tbl) == nil then
        pcall(hook.Run, "PopulatePropMenu")
        okT, tbl = pcall(spawnmenu.GetPropTable)
    end
    local nodes = listTree(okT and tbl or {}, "s:", all)
    if spawnmenu.GetCustomPropTable then
        local okC, ctbl = pcall(spawnmenu.GetCustomPropTable)
        local custom = listTree(okC and ctbl or {}, "c:", all)
        if #custom > 0 then nodes[#nodes + 1] = { id = "addonlists", label = "Addon spawnlists", kids = custom } end
    end
    return nodes, all
end

local function gameNodes()
    local out = {}
    local ok, games = pcall(engine.GetGames)
    for _, g in ipairs(ok and games or {}) do
        if g.mounted and g.folder then
            out[#out + 1] = folderNode("g:" .. g.folder, L(g.title or g.folder), "models/", g.folder)
        end
    end
    table.sort(out, function(x, y) return string.lower(x.label) < string.lower(y.label) end)
    return out
end

local function addonNodes()
    local out = {}
    local ok, addons = pcall(engine.GetAddons)
    for _, a in ipairs(ok and addons or {}) do
        if a.mounted and (tonumber(a.models) or 0) > 0 and a.title then
            local title = a.title
            out[#out + 1] = {
                id = "w:" .. tostring(a.wsid or title), label = title, count = tostring(a.models), search = true,
                models = function() return findModels("models/", title, nil, MAX_TILES * 4) end,
            }
        end
    end
    -- Local (legacy) addons: folders in addons/ with models.
    local _, dirs = file.Find("addons/*", "MOD")
    for _, d in ipairs(dirs or {}) do
        local base = "addons/" .. d .. "/"
        local _, md = file.Find(base .. "models", "MOD")
        if md and #md > 0 then
            out[#out + 1] = {
                id = "l:" .. d, label = d, count = "LOCAL", search = true,
                models = function()
                    local list = findModels(base .. "models/", "MOD", nil, MAX_TILES * 4)
                    -- (spawn by the game path, not the addon's folder)
                    for i, m in ipairs(list) do list[i] = string.sub(m, #base + 1) end
                    return list
                end,
            }
        end
    end
    table.sort(out, function(x, y) return string.lower(x.label) < string.lower(y.label) end)
    return out
end

SP.AddTab("props", {
    title = "Props", order = 10,
    build = function(body)
        local S = K.S
        modelCache = {}   -- (re-listed each build: addons can mount later)
        local slNodes, allLists = spawnlistNodes()
        local workKids
        local tree = {
            { id = "base", label = "Base game", group = true, kids = {
                { id = "lists", label = "Spawnlists", kids = slNodes },
                { id = "games", label = "Games", kids = gameNodes },
            } },
            { id = "work", label = "Workshop & addons", group = true, kids = function()
                workKids = workKids or addonNodes()
                return workKids
            end },
        }

        local chosen = slNodes[1]
        local query = ""
        local subText = ""   -- (the content header's count, made in fill)

        local sideCol = column(body, function() return "Browse" end)
        sideCol:Dock(LEFT)
        sideCol:SetWide(S(270))
        sideCol:DockMargin(0, 0, S(10), 0)
        local side = K.Scroll(sideCol)
        side:Dock(FILL)
        side:DockMargin(S(4), S(4), S(2), S(4))
        local gridCol = column(body, function()
            if query ~= "" then return "Search" end
            return chosen and chosen.label or "Props"
        end, function() return subText end)
        gridCol:Dock(FILL)
        local grid = K.Scroll(gridCol)
        grid:Dock(FILL)
        grid:DockMargin(S(8), S(8), S(2), S(8))
        local layout = vgui.Create("DIconLayout", grid)
        layout:Dock(TOP)
        layout:SetSpaceX(S(4))
        layout:SetSpaceY(S(4))
        layout:DockMargin(0, 0, S(8), 0)

        local function kidsOf(node)
            if isfunction(node.kids) then
                node.kidsCache = node.kidsCache or node.kids()
                return node.kidsCache
            end
            return node.kids
        end
        local function modelsOf(node)
            if not node.models then return nil end
            modelCache[node.id] = modelCache[node.id] or node.models()
            return modelCache[node.id]
        end

        local function note(text)
            layout:Add(emptyLine(layout, text))
        end
        local function header(text)
            layout:Add(bandLine(layout, text))
        end
        local function modelTile(model, skin, bg)
            layout:Add(SP.ModelTile(layout, model, skin, bg, function()
                RunConsoleCommand("gm_spawn", model, tostring(skin or 0), bg or "")
            end))
        end

        -- Spawnlist contents in key order, as sandbox reads them.
        local function ordered(sl)
            local keys, out = {}, {}
            for k in pairs(sl.contents or {}) do keys[#keys + 1] = k end
            table.sort(keys, function(x, y) return (tonumber(x) or 0) < (tonumber(y) or 0) end)
            for _, k in ipairs(keys) do out[#out + 1] = sl.contents[k] end
            return out
        end
        local CMD = { entity = "gm_spawnsent", weapon = "gm_giveswep", npc = "gmod_spawnnpc", vehicle = "gm_spawnvehicle" }
        local function addSpawnlist(sl, n)
            for _, c in ipairs(ordered(sl)) do
                if n >= MAX_TILES then return n end
                if c.type == "model" and c.model then
                    if query == "" or string.find(string.lower(c.model), query, 1, true) then
                        -- (saved bodygroups are "B" .. digits)
                        modelTile(c.model, c.skin, c.body and string.Trim(tostring(c.body), "B") or "")
                        n = n + 1
                    end
                elseif c.type == "header" and query == "" then
                    header(L(c.text))
                elseif CMD[c.type] and c.spawnname then
                    local name = L(c.nicename or c.spawnname)
                    if query == "" or string.find(string.lower(name), query, 1, true) then
                        local sn, kind = c.spawnname, c.type
                        local npc = kind == "npc" and (list.Get("NPC") or {})[sn] or nil
                        layout:Add(SP.Tile(layout, { name = name, tip = sn,
                            mat = iconMat({ c.material, "entities/" .. sn .. ".png" }),
                            spec = { kind = kind, name = sn, label = name, npc = npc },
                            run = function()
                                if kind == "npc" then RunConsoleCommand(CMD[kind], sn, SP.NpcWeapon(npc))
                                else RunConsoleCommand(CMD[kind], sn) end
                            end }))
                        n = n + 1
                    end
                end
            end
            return n
        end
        local function addModels(list, n)
            for _, m in ipairs(list or {}) do
                if n >= MAX_TILES then return n end
                if query == "" or string.find(string.lower(m), query, 1, true) then
                    modelTile(m, 0, "")
                    n = n + 1
                end
            end
            return n
        end

        local function fill()
            layout:Clear()
            local n = 0
            if query ~= "" then
                -- (spawnlists and every Workshop/local addon; game folders are too big)
                for _, sl in ipairs(allLists) do n = addSpawnlist(sl, n) end
                workKids = workKids or addonNodes()
                for _, node in ipairs(workKids) do
                    if n >= MAX_TILES then break end
                    n = addModels(modelsOf(node), n)
                end
                if n == 0 then note("No model matches. (Search covers the spawnlists and addons; games: open their folders.)") end
            elseif chosen and chosen.sl then
                n = addSpawnlist(chosen.sl, n)
                if n == 0 and next(chosen.sl.contents or {}) == nil then note("This spawnlist is empty.") end
            elseif chosen and chosen.models then
                local list = modelsOf(chosen)
                n = addModels(list, n)
                if n == 0 then note(chosen.kids and "No models in this folder: open a folder below it." or "No models found.") end
            end
            subText = n .. (n == 1 and " model" or " models") .. (n >= MAX_TILES and (" (first " .. MAX_TILES .. ")") or "")
            if n >= MAX_TILES then note("Showing the first " .. MAX_TILES .. ". Search to narrow it down.") end
            layout:InvalidateLayout(true)
            grid:GetVBar():SetScroll(0)
        end

        local buildSide
        local rowN = 0
        local function addRow(node, depth)
            local hasKids = istable(node.kids) and #node.kids > 0
                or (isfunction(node.kids) and (node.kidsCache == nil or #node.kidsCache > 0))
            rowN = rowN + 1
            local b = sideRow(side, {
                text = node.label, count = node.count, depth = node.group and 0 or depth,
                group = node.group, alt = rowN % 2 == 0,
                arrow = hasKids and function() return open[node.id] and "down" or "right" end or nil,
                selected = function() return query == "" and chosen == node end,
                fn = function()
                    -- (a click opens a closed node; clicking the shown one again closes it)
                    if hasKids and (chosen == node or not open[node.id] or not (node.sl or node.models)) then
                        open[node.id] = not open[node.id]
                    end
                    if node.sl or node.models then
                        chosen = node
                        if query == "" then fill() end
                    end
                    if hasKids then buildSide() end
                end,
            })
            b:Dock(TOP)
            b:DockMargin(0, node.group and depth == 0 and rowN > 1 and S(6) or 0, S(8), 0)
            if hasKids and open[node.id] then
                for _, k in ipairs(kidsOf(node) or {}) do addRow(k, depth + 1) end
            end
        end
        buildSide = function()
            local y = side:GetVBar():GetScroll()
            side:Clear()
            rowN = 0
            for _, node in ipairs(tree) do addRow(node, 0) end
            side:InvalidateLayout(true)
            timer.Simple(0, function() if IsValid(side) then side:GetVBar():SetScroll(y) end end)
        end
        buildSide()

        -- (after a short pause in typing: a search can list a lot)
        body.search = function(q)
            query = string.lower(q or "")
            timer.Create("Rhylib.Spawn.PropSearch", 0.35, 1, function() if IsValid(layout) then fill() end end)
        end
        -- (headers need the grid's width, known after the first layout)
        timer.Simple(0, function() if IsValid(layout) then fill() end end)
    end,
    search = function(body, q) if body.search then body.search(q) end end,
})

-- Tools: the tool list on the left, the chosen tool's own settings panel
-- (the same panel the Q menu shows) on the right.
SP.AddTab("tools", {
    title = "Tools", order = 60,
    build = function(body)
        local S = K.S
        local pickedName, pickedText
        local sideCol = column(body, function() return "Tools" end)
        sideCol:Dock(LEFT)
        sideCol:SetWide(S(270))
        sideCol:DockMargin(0, 0, S(10), 0)
        local side = K.Scroll(sideCol)
        side:Dock(FILL)
        side:DockMargin(S(4), S(4), S(2), S(4))
        -- (sandbox's own settings panel keeps its default look inside this plate)
        local right = column(body, function() return "Tool settings" end, function() return pickedText end)
        right:Dock(FILL)
        local panelScroll = K.Scroll(right)
        panelScroll:Dock(FILL)
        panelScroll:DockMargin(S(8), S(8), S(2), S(8))
        body.panelScroll = panelScroll
        local hint = vgui.Create("DPanel", panelScroll)
        hint:SetTall(S(64))
        hint:DockMargin(0, 0, S(8), 0)
        function hint:Paint(w, h)
            K.SetCol(C.row, 120)
            surface.DrawRect(0, 0, w, h)
            dashed(0, 0, w, h, C.edgeLight, 200)
            local f = K.Font(14)
            draw.SimpleText(K.Fit("Pick a tool on the left. Its settings show here, like in the Q menu.", f, w - S(24)), f, w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        hint:Dock(TOP)

        local current
        local function attach(cp)
            if not IsValid(cp) then return end
            -- (hand the old one back, as the Q menu does, so it isn't removed)
            for _, ch in ipairs(panelScroll:GetCanvas():GetChildren()) do
                if ch ~= cp and ch ~= hint then
                    ch:SetVisible(false)
                    ch:SetParent(vgui.GetWorldPanel())
                end
            end
            hint:SetVisible(false)
            if cp:GetParent() ~= panelScroll:GetCanvas() then panelScroll:AddItem(cp) end
            cp:Dock(TOP)
            cp:DockMargin(0, 0, S(8), 0)
            cp:SetVisible(true)
            current = cp
        end
        body.reattach = function() if IsValid(current) then attach(current) end end

        local function pick(item)
            pickedName = item.ItemName
            pickedText = L(item.Text or item.ItemName)
            if item.Command and item.Command ~= "" then LocalPlayer():ConCommand(item.Command) end
            if not (controlpanel and controlpanel.Get) then return end
            local ok, cp = pcall(controlpanel.Get, item.ItemName)
            if not (ok and IsValid(cp)) then return end
            if cp.GetInitialized and not cp:GetInitialized() and cp.FillViaTable then
                pcall(cp.FillViaTable, cp, { Text = item.Text, ControlPanelBuildFunction = item.CPanelFunction, Controls = item.Controls })
            end
            attach(cp)
        end

        local rows = {}
        local okT, tabs = pcall(spawnmenu.GetTools)
        for ti, t in ipairs(okT and tabs or {}) do
            local h = sideRow(side, { text = L(t.Label or t.Name or "Tools"), group = true })
            h:SetMouseInputEnabled(false)
            h:Dock(TOP)
            h:DockMargin(0, ti > 1 and S(6) or 0, S(8), 0)
            rows[#rows + 1] = { head = h }
            for _, cat in ipairs(t.Items or {}) do
                local cl = sideCaps(side, L(cat.Text or cat.ItemName or ""))
                cl:Dock(TOP)
                cl:DockMargin(0, S(4), S(8), 0)
                rows[#rows + 1] = { head = cl }
                local items = {}
                for _, item in ipairs(cat) do items[#items + 1] = item end
                table.sort(items, function(a, b) return lower(a.Text) < lower(b.Text) end)
                for i, item in ipairs(items) do
                    local text = L(item.Text or item.ItemName)
                    local b = sideRow(side, { text = text, depth = 1, alt = i % 2 == 0, fn = function() pick(item) end, selected = function()
                        if item.Command and string.find(item.Command, "gmod_tool", 1, true) then
                            local w = LocalPlayer():GetActiveWeapon()
                            local cv = GetConVar("gmod_toolmode")
                            return IsValid(w) and w:GetClass() == "gmod_tool" and cv and cv:GetString() == item.ItemName
                        end
                        return pickedName == item.ItemName
                    end })
                    b:Dock(TOP)
                    b:DockMargin(0, 0, S(8), 0)
                    rows[#rows + 1] = { btn = b, text = string.lower(text) }
                end
            end
        end
        if #rows == 0 then K.Label(side, "No tools found.", 13, nil, C.textDim):Dock(TOP) end
        body.search = function(q)
            q = string.lower(q or "")
            for _, r in ipairs(rows) do
                if r.head then r.head:SetVisible(q == "") end
                if r.btn then r.btn:SetVisible(q == "" or string.find(r.text, q, 1, true) ~= nil) end
            end
            side:InvalidateLayout()
            side:GetCanvas():InvalidateLayout()
        end
    end,
    -- (the real Q menu may have taken the settings panel meanwhile)
    onShow = function(body) if body.reattach then body.reattach() end end,
    search = function(body, q) if body.search then body.search(q) end end,
})
