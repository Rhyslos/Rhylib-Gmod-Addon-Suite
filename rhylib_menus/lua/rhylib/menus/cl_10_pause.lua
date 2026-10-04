--[[
    The pause menu. Esc opens it instead of Garry's Mod's menu; Shift + Esc
    (or the "Game menu" button) opens Garry's Mod's own. Esc again, or
    Resume, closes it. Esc also closes any other Rhylib window that's open
    (inventory, F4) instead of opening a menu.

    Pages (Settings, Commands, ...) register themselves:
        Rhylib.Menus.AddPage("settings", {
            title = "Settings", order = 10,
            visible = function() return true end,      -- optional
            build = function(panel) ... end,            -- fill the page panel
        })
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

Menus.pages = Menus.pages or {}
function Menus.AddPage(id, page)
    page.id = id
    Menus.pages[id] = page
end

local function sortedPages()
    local list = {}
    for _, p in pairs(Menus.pages) do
        if not p.visible or p.visible() then list[#list + 1] = p end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    return list
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
    for _, p in ipairs(sortedPages()) do
        nav(p.title, function() self:ShowPage(p.id) end, { selected = function() return self.pageId == p.id end })
    end

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

    -- The page area.
    local page = vgui.Create("DPanel", self)
    self.page = page
    page:SetPos(s(380), s(90))
    page:SetSize(math.min(ScrW() - s(440), s(980)), ScrH() - s(180))
    page:DockPadding(s(16), s(46), s(16), s(16))
    function page.Paint(p, w, h)
        local pg = self.pageId and Menus.pages[self.pageId]
        if not pg then return end
        K.Plate(0, 0, w, h, { title = pg.title, sub = pg.sub, ticks = "all", header = s(34) })
    end

    local first = sortedPages()[1]
    if Menus.lastPage and Menus.pages[Menus.lastPage] then
        self:ShowPage(Menus.lastPage)
    elseif first then
        self:ShowPage(first.id)
    end
end

function PANEL:ShowPage(id)
    local pg = Menus.pages[id]
    if not pg then return end
    self.pageId = id
    Menus.lastPage = id
    self.page:Clear()
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
