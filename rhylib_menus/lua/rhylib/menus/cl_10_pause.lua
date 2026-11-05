--[[
    The pause menu. Esc opens it instead of Garry's Mod's menu; Shift + Esc
    (or the "Game menu" button) opens Garry's Mod's own. Esc again, or
    Resume, closes it. Esc also closes any other Rhylib window that's open
    (inventory, F4) instead of opening a menu.

    Pages (Settings, Commands, ...) register themselves:
        Rhylib.Menus.AddPage("skills", {
            title = "Skills", order = 20,
            section = "you",                           -- side bar section
            icon = "skills",                           -- a K.Icon name
            badge = function() return 3 end,           -- optional count
            key = "M",                                 -- optional key hint
            visible = function() return true end,      -- optional
            build = function(panel) ... end,            -- fill the page panel
        })

    The side bar is one flat list in three sections: You, Options, Staff
    (Menus.SECTIONS). A page in a tab group (Menus.AddGroup with tabs =
    true: Trooper) is not listed itself: the group has one entry,
    and its pages show as tabs along the page's header.

    page fields: title, order (lower = higher up; default 50), section
    ("you" / "options" / "staff"; default from the group, else "you"),
    group (a Menus.AddGroup id), icon, badge() (a number or short text in a
    pill on the entry; nil / 0 hides it), key (text or function: a dim key
    hint on the entry), visible() (hidden when it returns false),
    build(panel) (called every time the page is shown, into a cleared
    panel; errors are caught and printed), sub (optional dim text on the
    page's header; may be set by build), beforeLeave(go) (optional: return
    false to stay on the page when another is picked, and call go() later
    to switch after all).
    group fields: title, order, section, icon, key, tabs (true: one side
    bar entry, pages as header tabs). The old groups play / character /
    unit / staff only give their pages a section now.

    Client only. Adds: Menus.AddPage, Menus.AddGroup, Menus.pages,
    Menus.groups, Menus.SECTIONS, Menus.PAGE_ALIAS, Menus.OpenPause,
    Menus.ClosePause, Menus.RefreshPause, Menus.PreviewHover, Menus.pause
    (the open panel, a "RhylibPauseMenu"), Menus.lastPage, Menus.lastTab. Console command:
    rhylib_menu. Hook: OnPauseMenuShow "menus.pause" (decides what Esc does).
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

-- Menus.AddPage(id, page): adds (or replaces) a pause menu page. See the
-- header for the fields. Safe to call again on a Lua refresh.
-- Example: Rhylib.Menus.AddPage("mypage", { title = "My page", section = "you", icon = "jobs", order = 40,
--              build = function(p) Rhylib.Menus.Kit.Label(p, "Hello", 14):Dock(TOP) end })
Menus.pages = Menus.pages or {}
function Menus.AddPage(id, page)
    page.id = id
    Menus.pages[id] = page
end

-- Side bar sections, in order.
Menus.SECTIONS = {
    { id = "you", title = "You" },
    { id = "options", title = "Options" },
    { id = "staff", title = "Staff" },
}

-- Menus.AddGroup(id, { title, order, section, icon, key, tabs }): a group
-- of pages. With tabs = true it is one side bar entry and its pages are
-- tabs on the page header.
Menus.groups = Menus.groups or {}
function Menus.AddGroup(id, g)
    g.id = id
    Menus.groups[id] = g
end
Menus.AddGroup("play", { title = "Jobs & shop", order = 10, section = "you" })
Menus.AddGroup("character", { title = "Character", order = 20, section = "you" })
Menus.AddGroup("unit", { title = "Unit", order = 30, section = "you" })
Menus.AddGroup("trooper", { title = "Trooper", order = 10, section = "you", icon = "trooper", tabs = true })
Menus.AddGroup("staff", { title = "Staff", order = 200, section = "staff" })

-- Old page ids still used by other code (and saved as the last page).
-- id -> new id, or a function returning it. ShowPage resolves through it.
Menus.PAGE_ALIAS = { settings = function() return Menus.SettingsPageId and Menus.SettingsPageId(Menus.settingsTab) end }

local function visible(p) return not p.visible or p.visible() end

local function sortedPages()
    local list = {}
    for _, p in pairs(Menus.pages) do
        if visible(p) then list[#list + 1] = p end
    end
    table.sort(list, function(a, b)
        local oa, ob = a.order or 50, b.order or 50
        if oa ~= ob then return oa < ob end
        return a.id < b.id
    end)
    return list
end

local function tabGroup(p)
    local g = p and p.group and Menus.groups[p.group]
    return g and g.tabs and g or nil
end

-- The visible pages of a tab group, in order.
local function groupPages(gid)
    local out = {}
    for _, p in ipairs(sortedPages()) do
        if p.group == gid then out[#out + 1] = p end
    end
    return out
end

local function sectionOf(p)
    if p.section then return p.section end
    local g = p.group and Menus.groups[p.group]
    return g and g.section or "you"
end

-- Side bar entries by section: { [sectionId] = { entry, ... } }, each
-- entry { title, icon, key, badge, target = page id, group = id or nil }.
local function navEntries()
    local bySection, seen = {}, {}
    for _, p in ipairs(sortedPages()) do
        local g = tabGroup(p)
        local e
        if g then
            if not seen[g.id] then
                seen[g.id] = true
                e = { title = g.title, icon = g.icon, key = g.key, target = p.id, group = g.id, order = g.order or p.order or 50,
                    section = g.section or sectionOf(p) }
            end
        else
            e = { title = p.title, icon = p.icon, key = p.key, badge = p.badge, target = p.id, order = p.order or 50, section = sectionOf(p) }
        end
        if e then
            local list = bySection[e.section]
            if not list then list = {} bySection[e.section] = list end
            list[#list + 1] = e
        end
    end
    for _, list in pairs(bySection) do
        table.sort(list, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.target < b.target
        end)
    end
    return bySection
end

local function title()
    local t = Rhylib.Config.Get("menus", "title")
    if not t or t == "" then t = GetHostName() end
    return t
end

local function textOf(v)
    if isfunction(v) then
        local ok, r = pcall(v)
        v = ok and r or nil
    end
    if v == nil or v == false or v == 0 or v == "" then return nil end
    return tostring(v)
end

-- A side bar entry: icon, label, a badge pill and a dim key hint.
local function navItem(parent, e, isOn, onClick)
    local s = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(s(36))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(2))   -- (room for the scroll bar)
    function b:Paint(w, h)
        local on = isOn()
        if on then
            K.SetCol(C.buttonDown)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.accent)
            surface.DrawRect(0, 0, s(3), h)
        elseif self:IsHovered() then
            K.SetCol(C.buttonHover, 160)
            surface.DrawRect(0, 0, w, h)
        end
        local ic = s(18)
        K.Icon(e.icon or "menu", s(12), (h - ic) * 0.5, ic, on and C.accent or C.textDim)
        local right = w - s(10)
        -- (badge and key text asked a few times a second, not every frame)
        local now = RealTime()
        if not self.textAt or now > self.textAt then
            self.textAt = now + 0.25
            local k = textOf(e.key)
            self.keyText = k and string.upper(k) or nil
            self.badgeText = textOf(e.badge)
        end
        local key = self.keyText
        if key then
            local f = K.Font(11, 700)
            surface.SetFont(f)
            local tw = surface.GetTextSize(key)
            local bw = tw + s(10)
            K.SetCol(C.edgeLight, 120)
            surface.DrawOutlinedRect(right - bw, h * 0.5 - s(9), bw, s(18))
            draw.SimpleText(key, f, right - bw * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            right = right - bw - s(6)
        end
        local badge = self.badgeText
        if badge then
            local f = K.Font(12, 700)
            surface.SetFont(f)
            local tw = surface.GetTextSize(badge)
            local bw = math.max(s(20), tw + s(10))
            K.SetCol(C.warn)
            surface.DrawRect(right - bw, h * 0.5 - s(9), bw, s(18))
            draw.SimpleText(badge, f, right - bw * 0.5, h * 0.5, C.bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            right = right - bw - s(6)
        end
        local f = K.Font(15, on and 700 or 500)
        local x = s(40)
        draw.SimpleText(K.Fit(e.title, f, right - x), f, x, h * 0.5, on and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        onClick()
    end
    return b
end

-- A plain side bar action (Resume, Game menu, Disconnect).
local function actionItem(parent, text, icon, col, fn)
    local s = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(s(34))
    function b:Paint(w, h)
        K.SetCol(self:IsHovered() and C.buttonHover or C.button)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(col or C.accent, 220)
        surface.DrawRect(1, 1, s(3), h - 2)
        local ic = s(16)
        K.Icon(icon, s(13), (h - ic) * 0.5, ic, col or C.accent)
        draw.SimpleText(string.upper(text), K.Font(13, 700), s(40), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        fn()
    end
    return b
end

-- The pause menu panel ("RhylibPauseMenu"): full screen. Left: the side
-- bar (server title, Resume, the sections, Game menu, Disconnect). Right:
-- the page area (the same width for every page). Opens on the last page
-- shown (Menus.lastPage), else the first page.
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

    local resume = actionItem(side, "Resume", "resume", C.accent, function() Menus.ClosePause() end)
    resume:Dock(TOP)
    resume:DockMargin(0, 0, 0, s(6))
    local bottom = vgui.Create("DPanel", side)
    bottom:Dock(BOTTOM)
    bottom:SetTall(s(34) * 2 + s(6))
    bottom.Paint = nil
    local quit = actionItem(bottom, "Disconnect", "power", C.bad, function()
        RunConsoleCommand("disconnect")
    end)
    quit:Dock(BOTTOM)
    local gm = actionItem(bottom, "Game menu  (Shift + Esc)", "menu", C.textDim, function()
        Menus.ClosePause()
        Menus.passGameUI = true  -- let this one through the hook below
        gui.ActivateGameUI()
    end)
    gm:Dock(BOTTOM)
    gm:DockMargin(0, 0, 0, s(6))

    -- The entries live in their own scroll panel (made after the bottom
    -- buttons so FILL leaves them room).
    local navBox = K.Scroll(side)
    navBox:Dock(FILL)
    navBox:DockMargin(0, s(4), 0, s(8))
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
        local g = tabGroup(pg)
        local sub = pg.sub
        if sub and self.tabEnd then sub = K.Fit(sub, K.Font(13), w - self.tabEnd - s(24)) end
        K.Plate(0, 0, w, h, { title = g and g.title or pg.title, sub = sub, ticks = "all", header = s(34) })
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

-- Old id -> current id (Menus.PAGE_ALIAS).
function PANEL:Resolve(id)
    local a = Menus.PAGE_ALIAS[id]
    if isfunction(a) then return a() or id end
    return a or id
end

-- Side bar: section headings and their entries.
function PANEL:BuildNav()
    local box = self.navBox
    if not IsValid(box) then return end
    box:Clear()
    local s = K.S
    local me = self
    local bySection = navEntries()
    local firstSection = true
    for _, sec in ipairs(Menus.SECTIONS) do
        local list = bySection[sec.id]
        if list and #list > 0 then
            local head = vgui.Create("DPanel", box)
            head:Dock(TOP)
            head:SetTall(s(firstSection and 22 or 30))
            local label = sec.title
            function head:Paint(w, h)
                K.Caps(label, s(4), h - s(10), C.label)
            end
            firstSection = false
            for _, e in ipairs(list) do
                navItem(box, e, function()
                    local cur = me.pageId and Menus.pages[me.pageId]
                    if e.group then return cur ~= nil and cur.group == e.group end
                    return me.pageId == e.target
                end, function()
                    -- (a tab group opens on the tab last shown in it)
                    local target = e.target
                    if e.group and Menus.lastTab and Menus.lastTab[e.group] then
                        local t = Menus.pages[Menus.lastTab[e.group]]
                        if t and visible(t) and t.group == e.group then target = t.id end
                    end
                    me:ShowPage(target)
                end)
            end
        end
    end
end

-- The tabs of a tab group, in the page header right of the title.
function PANEL:BuildTabs(pg)
    self.tabEnd = nil
    local g = tabGroup(pg)
    if not g then return end
    local s = K.S
    local me = self
    local pages = groupPages(g.id)
    if #pages < 2 then return end
    surface.SetFont(K.Font(15, 700))
    local x = s(12) + surface.GetTextSize(string.upper(g.title)) + s(22)
    local f = K.Font(13, 600)
    surface.SetFont(f)
    for _, p in ipairs(pages) do
        local w = surface.GetTextSize(p.title) + s(24)
        local t = vgui.Create("DButton", self.page)
        t:SetText("")
        t:SetPos(x, 0)
        t:SetSize(w, s(34))
        local id = p.id
        function t:Paint(tw, th)
            local on = me.pageId == id
            if self:IsHovered() and not on then
                K.SetCol(C.buttonHover, 120)
                surface.DrawRect(0, 0, tw, th - 1)
            end
            if on then
                K.SetCol(C.accent)
                surface.DrawRect(s(4), th - s(3), tw - s(8), s(3))
            end
            draw.SimpleText(p.title, f, tw * 0.5, th * 0.5, on and C.text or C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return true
        end
        function t:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            me:ShowPage(id)
        end
        x = x + w
    end
    self.tabEnd = x
end

-- PANEL:ShowPage(id): shows a page (rebuilds it from scratch).
-- Example: Rhylib.Menus.pause:ShowPage("skills")
function PANEL:ShowPage(id)
    id = self:Resolve(id)
    local pg = Menus.pages[id]
    if not pg then return end
    -- (the page being left may hold the switch: beforeLeave(go) returns
    -- false and calls go() later, e.g. after "Apply / Discard / Stay")
    local cur = self.pageId and Menus.pages[self.pageId]
    if cur and cur.beforeLeave and id ~= self.pageId and not self.leaving then
        local me = self
        local ok, res = pcall(cur.beforeLeave, function()
            if not IsValid(me) then return end
            me.leaving = true
            me:ShowPage(id)
            me.leaving = false
        end)
        if ok and res == false then return end
    end
    self.pageId = id
    Menus.lastPage = id
    if pg.group then
        Menus.lastTab = Menus.lastTab or {}
        Menus.lastTab[pg.group] = id
    end
    self:BuildNav()
    self.page:Clear()
    local ok, err = pcall(pg.build, self.page)
    if not ok then Rhylib.Error("menus", "page %s: %s", id, tostring(err)) end
    self:BuildTabs(pg)
end

-- HUD preview: while the mouse is on a setting marked `preview` (HUD
-- shape sliders), the game isn't dimmed or blurred, and while dragging it
-- the menu fades so the HUD behind it shows.
-- Menus.PreviewHover(): the rhylibPreview value (true, or a kind such as
-- "thirdperson") while the hovered panel (or one of up to 8 parents) has
-- it set (cl_20_settings sets it on preview rows), else false. While the
-- left mouse is held after pressing on such a row (dragging a slider)
-- it keeps that value even if the mouse slips off.
local dragPreview
function Menus.PreviewHover()
    if dragPreview and input.IsMouseDown(MOUSE_LEFT) then return dragPreview end
    dragPreview = nil
    local p = vgui.GetHoveredPanel()
    for _ = 1, 8 do
        if not IsValid(p) then return false end
        if p.rhylibPreview then
            if input.IsMouseDown(MOUSE_LEFT) then dragPreview = p.rhylibPreview end
            return p.rhylibPreview
        end
        p = p:GetParent()
    end
    return false
end

function PANEL:Think()
    local hover = Menus.PreviewHover()
    self.previewing = hover
    -- (dragging a preview row: the menu fades; a camera row fades it on
    -- hover too, so your trooper behind it shows)
    local want = ((hover and input.IsMouseDown(MOUSE_LEFT)) and 60) or (hover == "thirdperson" and 90) or 255
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

-- Menus.OpenPause() / Menus.ClosePause(): open or close the pause menu.
-- ClosePause returns true if it was open.
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
-- Returning false stops GMod's menu; returning nothing lets it open.
-- Order: the Game menu button's pass, Shift, key rebinding (Esc cancels it),
-- model pick mode in the spawn window, any open Rhylib window (closers),
-- else our pause menu.
Rhylib.Hook.Add("OnPauseMenuShow", "menus.pause", function()
    if Menus.passGameUI then
        Menus.passGameUI = false
        return
    end
    if input.IsShiftDown() then return end
    -- Esc while setting a key in the settings: cancels that, nothing else.
    if Menus.keyTrapping then return false end
    -- Esc while picking a model for the Server settings page: cancels the
    -- pick only (the page stays open behind it).
    local SP = Menus.Spawn
    if SP and SP.pick and SP.Close and SP.Close() then return false end
    -- Esc with a dropdown list (or colour mixer) open closes only that.
    if K.DropdownOpen and K.DropdownOpen() then
        if K.CloseDropdown then K.CloseDropdown() end
        return false
    end
    if Menus.CloseAll() then return false end
    Menus.OpenPause()
    return false
end)

-- rhylib_menu: toggles the pause menu (for binds and testing).
concommand.Add("rhylib_menu", function()
    if not Menus.ClosePause() then Menus.OpenPause() end
end)
