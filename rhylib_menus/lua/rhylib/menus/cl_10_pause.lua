--[[
    The pause menu. Esc opens it instead of Garry's Mod's menu; Shift + Esc
    (or the "Game menu" button) opens Garry's Mod's own. Esc again, or
    Resume, closes it. Esc also closes any other Rhylib window that's open
    (inventory, F4) instead of opening a menu.

    Pages (Settings, Commands, ...) register themselves:
        Rhylib.Menus.AddPage("skills", {
            title = "Skills", order = 10,
            group = "character",                        -- optional submenu
            visible = function() return true end,      -- optional
            build = function(panel) ... end,            -- fill the page panel
        })
    Groups (Menus.AddGroup) are submenus in the side bar: clicking one
    opens it (and its first page); a group with one page is a plain
    button. Pages without a group are plain buttons too.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

Menus.pages = Menus.pages or {}
-- page: { title, order, group, visible, build, wide (use the full width) }
function Menus.AddPage(id, page)
    page.id = id
    Menus.pages[id] = page
end

-- Submenus, in side bar order (owner: the flat list was messy).
Menus.groups = Menus.groups or {}
function Menus.AddGroup(id, g)
    g.id = id
    Menus.groups[id] = g
end
Menus.AddGroup("play", { title = "Jobs & shop", order = 10 })
Menus.AddGroup("character", { title = "Character", order = 20 })
Menus.AddGroup("unit", { title = "Unit", order = 30 })
Menus.AddGroup("settings", { title = "Settings", order = 40 })
Menus.AddGroup("staff", { title = "Staff", order = 50 })

-- Old page ids still used by other code (and saved as the last page).
Menus.PAGE_ALIAS = { settings = function() return Menus.SettingsPageId and Menus.SettingsPageId(Menus.settingsTab) end }

local function visible(p) return not p.visible or p.visible() end

local function sortedPages()
    local list = {}
    for _, p in pairs(Menus.pages) do
        if visible(p) then list[#list + 1] = p end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    return list
end

-- Side bar entries: { group = g, pages = {...} } or { page = p }, in order.
local function navEntries()
    local byGroup, entries = {}, {}
    for _, p in ipairs(sortedPages()) do
        local g = p.group and Menus.groups[p.group]
        if g then
            if not byGroup[g.id] then
                byGroup[g.id] = { group = g, pages = {}, order = g.order or 50 }
                entries[#entries + 1] = byGroup[g.id]
            end
            local list = byGroup[g.id].pages
            list[#list + 1] = p
        else
            entries[#entries + 1] = { page = p, order = p.order or 50 }
        end
    end
    table.sort(entries, function(a, b) return a.order < b.order end)
    return entries
end

local function title()
    local t = Rhylib.Config.Get("menus", "title")
    if not t or t == "" then t = GetHostName() end
    return t
end

local PANEL = {}

function PANEL:Init()
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self.opened = SysTime()
    local s = K.S

    local side = vgui.Create("DPanel", self)
    self.side = side
    side:SetPos(s(60), s(90))
    side:SetSize(s(300), ScrH() - s(180))
    side:DockPadding(s(16), s(96), s(16), s(16))
    function side:Paint(w, h)
        K.Plate(0, 0, w, h, { ticks = "all" })
        draw.SimpleText(K.Fit(title(), K.Font(20, 700), w - s(32)), K.Font(20, 700), s(16), s(32), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(game.GetMap() .. "  ·  " .. player.GetCount() .. " / " .. game.MaxPlayers() .. " players", K.Font(13), s(16), s(56), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        K.SetCol(C.accent, 170)
        surface.DrawRect(s(16), s(76), w - s(32), 1)
    end

    local function nav(text, fn, opts)
        local b = K.Button(side, text, fn, opts)
        b:Dock(TOP)
        b:DockMargin(0, 0, 0, s(6))
        b.opts.align = "left"
        return b
    end

    nav("Resume", function() Menus.ClosePause() end, { accent = true })
    local bottom = vgui.Create("DPanel", side)
    bottom:Dock(BOTTOM)
    bottom:SetTall(s(34) * 2 + s(6))
    bottom.Paint = nil
    local quit = K.Button(bottom, "Disconnect", function()
        RunConsoleCommand("disconnect")
    end, { danger = true, align = "left" })
    quit:Dock(BOTTOM)
    local gm = K.Button(bottom, "Game menu  (Shift + Esc)", function()
        Menus.ClosePause()
        Menus.passGameUI = true  -- let this one through the hook below
        gui.ActivateGameUI()
    end, { align = "left" })
    gm:Dock(BOTTOM)
    gm:DockMargin(0, 0, 0, s(6))

    -- The page buttons live in their own panel (made after the bottom buttons so FILL leaves them room), rebuilt when a submenu opens.
    local navBox = vgui.Create("DPanel", side)
    navBox:Dock(FILL)
    navBox.Paint = nil
    self.navBox = navBox

    -- The page area.
    local page = vgui.Create("DPanel", self)
    self.page = page
    page:SetPos(s(380), s(90))
    page:SetSize(math.min(ScrW() - s(440), s(980)), ScrH() - s(180))
    page:DockPadding(s(16), s(46), s(16), s(16))
    function page.Paint(p, w, h)
        local pg = self.pageId and Menus.pages[self.pageId]
        if not pg then return end
        -- (in a submenu: "Group · Page")
        local g = pg.group and Menus.groups[pg.group]
        local t = pg.title
        if g and g.title ~= pg.title then
            local n = 0
            for _, p in pairs(Menus.pages) do if p.group == pg.group and visible(p) then n = n + 1 end end
            if n > 1 then t = g.title .. "  ·  " .. pg.title end
        end
        K.Plate(0, 0, w, h, { title = t, sub = pg.sub, ticks = "all", header = s(34) })
    end

    local first = sortedPages()[1]
    local last = Menus.lastPage and self:Resolve(Menus.lastPage)
    if last and Menus.pages[last] and visible(Menus.pages[last]) then
        self:ShowPage(last)
    elseif first then
        self:ShowPage(first.id)
    else
        self:BuildNav()
    end
end

function PANEL:Resolve(id)
    local a = Menus.PAGE_ALIAS[id]
    if isfunction(a) then return a() or id end
    return a or id
end

-- Side bar: groups (open = their pages listed under them) and pages.
function PANEL:BuildNav()
    local box = self.navBox
    if not IsValid(box) then return end
    box:Clear()
    local s = K.S
    local me = self
    local cur = self.pageId and Menus.pages[self.pageId]
    for _, e in ipairs(navEntries()) do
        if e.page or #e.pages == 1 then
            -- A page, or a group with one page: one button.
            local p = e.page or e.pages[1]
            local b = K.Button(box, e.page and p.title or e.group.title, function() me:ShowPage(p.id) end,
                { align = "left", selected = function() return me.pageId == p.id end })
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, s(6))
        else
            local g = e.group
            local open = self.openGroup == g.id
            local b = K.Button(box, g.title, function()
                if me.openGroup == g.id then
                    me.openGroup = nil
                    me:BuildNav()
                else
                    -- (opening a submenu shows its first page)
                    me.openGroup = g.id
                    local inside = cur and cur.group == g.id
                    if inside then me:BuildNav() else me:ShowPage(e.pages[1].id) end
                end
            end, { align = "left", selected = function() local c = me.pageId and Menus.pages[me.pageId] return c and c.group == g.id end })
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, open and s(4) or s(6))
            function b:PaintOver(w, h)
                draw.SimpleText(open and "-" or "+", K.Font(16, 700), w - s(14), h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            if open then
                for i, p in ipairs(e.pages) do
                    local sb = K.Button(box, p.title, function() me:ShowPage(p.id) end,
                        { align = "left", small = true, selected = function() return me.pageId == p.id end })
                    sb:Dock(TOP)
                    sb:DockMargin(s(18), 0, 0, i == #e.pages and s(10) or s(4))
                end
            end
        end
    end
end

function PANEL:ShowPage(id)
    id = self:Resolve(id)
    local pg = Menus.pages[id]
    if not pg then return end
    -- (a refresh of the same page keeps a submenu the player closed shut)
    if pg.group and id ~= self.pageId then self.openGroup = pg.group end
    self.pageId = id
    Menus.lastPage = id
    self:BuildNav()
    self.page:Clear()
    -- Pages with `wide = true` (skill trees, keyboard layout, profiler) use
    -- the whole width right of the side bar; the rest stay at 980.
    local avail = ScrW() - K.S(440)
    self.page:SetWide(pg.wide and avail or math.min(avail, K.S(980)))
    self.page:InvalidateLayout(true)
    local ok, err = pcall(pg.build, self.page)
    if not ok then Rhylib.Error("menus", "page %s: %s", id, tostring(err)) end
end

-- HUD preview: while the mouse is on a setting marked `preview` (HUD
-- shape sliders), the game isn't dimmed or blurred, and while dragging it
-- the menu fades so the HUD behind it shows.
function Menus.PreviewHover()
    local p = vgui.GetHoveredPanel()
    for _ = 1, 8 do
        if not IsValid(p) then return false end
        if p.rhylibPreview then return true end
        p = p:GetParent()
    end
    return false
end

function PANEL:Think()
    local hover = Menus.PreviewHover()
    self.previewing = hover
    local want = (hover and input.IsMouseDown(MOUSE_LEFT)) and 60 or 255
    for _, pnl in ipairs({ self.side, self.page }) do
        if IsValid(pnl) then
            local a = pnl:GetAlpha()
            if a ~= want then pnl:SetAlpha(math.Approach(a, want, FrameTime() * 1200)) end
        end
    end
end

function PANEL:Paint(w, h)
    if self.previewing then return end
    -- Dim and blur the game behind.
    Derma_DrawBackgroundBlur(self, self.opened)
    K.SetCol(C.dim)
    surface.DrawRect(0, 0, w, h)
end

vgui.Register("RhylibPauseMenu", PANEL, "EditablePanel")

function Menus.OpenPause()
    if IsValid(Menus.pause) then return end
    Menus.pause = vgui.Create("RhylibPauseMenu")
    Menus.pause:MakePopup()
    Menus.pause:SetKeyboardInputEnabled(true)
end

function Menus.ClosePause()
    if IsValid(Menus.pause) then
        Menus.pause:Remove()
        return true
    end
    return false
end

-- Rebuild an open pause menu (after a page's content changed a lot).
function Menus.RefreshPause()
    if IsValid(Menus.pause) and Menus.pause.pageId then
        Menus.pause:ShowPage(Menus.pause.pageId)
    end
end

Menus.RegisterCloser("pause", Menus.ClosePause)
Menus.RegisterCloser("inventory", function()
    local Inv = Rhylib.Inventory
    if Inv and IsValid(Inv.panel) then
        Inv.panel:Remove()
        return true
    end
    return false
end)

-- Esc: our menu (or close what's open). Shift + Esc: Garry's Mod's menu.
Rhylib.Hook.Add("OnPauseMenuShow", "menus.pause", function()
    if Menus.passGameUI then
        Menus.passGameUI = false
        return
    end
    if input.IsShiftDown() then return end
    -- Esc while setting a key in the settings: cancels that, nothing else.
    if Menus.keyTrapping then return false end
    if Menus.CloseAll() then return false end
    Menus.OpenPause()
    return false
end)

concommand.Add("rhylib_menu", function()
    if not Menus.ClosePause() then Menus.OpenPause() end
end)
