--[[
    The UI kit in the house style (same as the HUD, chat and inventory):
    dark plates, black outlines, a faint light line along the top, small
    corner ticks, caps labels, an accent stripe on buttons.

        local K = Rhylib.UI.Kit          (also Rhylib.Menus.Kit, the old name)
        K.Plate(x, y, w, h, { title = "Settings", ticks = true })   -- in a Paint
        K.Button(parent, "Resume", fn, { accent = true })
        K.Scroll(parent)
        K.Label(parent, "text", size, weight, color)

    Sizes are given at 1080p and scaled with K.S(n).

    Client only, in rhylib_core (it used to be rhylib_menus' cl_00_kit.lua),
    so windows of every addon (datapad, radio, skills, EOD...) work without
    rhylib_menus. rhylib_menus keeps Rhylib.Menus.Kit pointing here.

    What's here (all on Rhylib.UI.Kit, "K"):
      K.C                    the colour set (K.C.accent etc.)
      K.S / K.Scale / K.Font sizes and fonts
      K.SetCol, K.Ticks, K.Plate, K.Caps, K.Fit     drawing helpers (use in Paint)
      K.Tint                 give a window its own accent colour
      K.Button, K.Label, K.Heading, K.Scroll, K.Row panels
      K.ThemedText           a label's colour / font that follow a theme switch
      K.Choices, K.Toggle, K.Slider, K.TextEntry    controls bound to get/set
      K.Dropdown, K.Number, K.Search, K.Fold, K.Swatches   a select box, a
                             number (bar + typed box + unit), a search box,
                             a section that folds, colour squares + mixer
      K.Icon, K.Arrow        a line icon by name (K.ICONS) and a small triangle, drawn in a Paint
      K.Menu, K.Prompt       a right-click menu (submenus too) and a text question popup
      K.Confirm              a yes / no popup
    Also UI.prompts / UI.closers / UI.RegisterCloser / UI.CloseAll (what Esc
    closes first; rhylib_menus' Menus.prompts etc. are the same tables).
    The guide (docs/addons/rhylib_menus.md) has an example for each widget.
]]

Rhylib.UI = Rhylib.UI or {}
local UI = Rhylib.UI
UI.Kit = UI.Kit or {}
local K = UI.Kit
-- (rhylib_menus sets Rhylib.Menus.Kit = UI.Kit too; if the menus table
-- already exists, point it here now)
if Rhylib.Menus then Rhylib.Menus.Kit = K end

-- K.C: the house colours. text/textDim/accent/good/warn/bad start as
-- Rhylib.UI.Colors (rhylib_core), so they match the HUD in the dark theme. K.Tint and the
-- skills' command orders swap C.accent for a while; read it each frame.
K.C = {
    dim = Color(0, 0, 0, 170),
    bg = Color(14, 16, 15, 242),
    header = Color(22, 25, 23, 255),
    row = Color(20, 23, 21, 255),
    rowAlt = Color(24, 27, 25, 255),
    rowHover = Color(32, 40, 48, 255),
    edgeDark = Color(0, 0, 0, 230),
    edgeLight = Color(170, 176, 180, 70),
    tick = Color(170, 176, 180, 150),
    label = Color(140, 142, 136),
    button = Color(26, 29, 27),
    buttonHover = Color(38, 50, 64),
    buttonDown = Color(48, 64, 82),
    text = UI.Colors.text,
    textDim = UI.Colors.textDim,
    accent = UI.Colors.accent,
    good = UI.Colors.good,
    warn = UI.Colors.warn,
    bad = UI.Colors.bad,
}
local C = K.C
-- The kit colours are theme tokens "kit.<key>" (cl_11_theme.lua). text,
-- textDim, accent, good, warn and bad start as the HUD's UI.Colors values
-- but are their own tokens, so a theme recolours windows without the HUD.
if UI.Col then
    for k, col in pairs(C) do C[k] = UI.Col("kit." .. k, col.r, col.g, col.b, col.a) end
end

-- K.Scale(): screen height / 1080. K.S(n): n pixels at 1080p, scaled to
-- this screen and rounded. K.Font(size, weight): Rhylib.UI.Font (sizes at
-- 1080p, scaled for you; weight 400 normal, 700 bold).
-- Example: panel:SetTall(K.S(34))  draw.SimpleText("Hi", K.Font(14, 700), ...)
function K.Scale() return ScrH() / 1080 end
function K.S(n) return math.floor(n * ScrH() / 1080 + 0.5) end
function K.Font(size, weight) return UI.Font(size, weight) end

local scratch = Color(0, 0, 0)
local function setCol(col, a)
    scratch.r, scratch.g, scratch.b, scratch.a = col.r, col.g, col.b, (col.a or 255) * (a or 255) / 255
    surface.SetDrawColor(scratch)
end
-- K.SetCol(col, a): surface.SetDrawColor with an extra alpha (0-255)
-- multiplied in, without making a new Color. Example: K.SetCol(K.C.accent, 120)
K.SetCol = setCol

-- K.Ticks(x, y, w, h, all, a): small corner ticks (bottom corners, or all
-- four when all is true). a = alpha. Draw in a Paint.
function K.Ticks(x, y, w, h, all, a)
    local t = K.S(7)
    setCol(C.tick, a)
    surface.DrawRect(x, y + h - 2, t, 2)
    surface.DrawRect(x, y + h - t, 2, t)
    surface.DrawRect(x + w - t, y + h - 2, t, 2)
    surface.DrawRect(x + w - 2, y + h - t, 2, t)
    if all then
        surface.DrawRect(x, y, t, 2)
        surface.DrawRect(x, y, 2, t)
        surface.DrawRect(x + w - t, y, t, 2)
        surface.DrawRect(x + w - 2, y, 2, t)
    end
end

--[[
    A plate. opts: bg, title, sub (dim text on the header's right),
    header (height, default 30 at 1080p when titled), rule (colour),
    ticks (true: bottom corners, "all": all four), alpha.
    Returns the y where the content starts.
    Example (in a Paint):
        local top = K.Plate(0, 0, w, h, { title = "Armoury", sub = "6 items", ticks = "all" })
]]
function K.Plate(x, y, w, h, opts)
    opts = opts or {}
    local a = opts.alpha or 255
    setCol(opts.bg or C.bg, a)
    surface.DrawRect(x, y, w, h)
    local top = y
    if opts.title then
        local hh = opts.header or K.S(30)
        setCol(C.header, a)
        surface.DrawRect(x, y, w, hh)
        setCol(opts.rule or C.accent, a * 0.7)
        surface.DrawRect(x, y + hh - 1, w, 1)
        draw.SimpleText(string.upper(opts.title), K.Font(15, 700), x + K.S(12), y + hh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if opts.sub then
            draw.SimpleText(opts.sub, K.Font(13), x + w - K.S(12), y + hh * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        top = y + hh
    end
    setCol(C.edgeDark, a)
    surface.DrawOutlinedRect(x, y, w, h)
    setCol(C.edgeLight, a)
    surface.DrawLine(x + 1, y + 1, x + w - 1, y + 1)
    if opts.ticks then K.Ticks(x, y, w, h, opts.ticks == "all", a) end
    return top
end

-- K.Caps(text, x, y, col, align): small upper-case label drawn in a Paint
-- (vertically centred on y). Default colour C.label, left aligned.
function K.Caps(text, x, y, col, align)
    draw.SimpleText(string.upper(text), K.Font(12, 700), x, y, col or C.label, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- K.Icon(name, x, y, size, col, a): a line icon drawn in a Paint, its top
-- left at x, y, size pixels square. Names: trooper, skills, jobs, shop,
-- battalion, radio, class, settings, staffhome, players, maps, server,
-- editor, quiz, profiler, commands, inventory, resume, power, menu,
-- search, learn, lock. Unknown names draw nothing. K.ICONS holds the shapes (lists of
-- strokes on a 24 x 24 grid: { x1, y1, x2, y2, ... }, or { arc = { cx, cy,
-- r, from, to } } in degrees, 0 = right, 90 = down; closed = true joins
-- the ends). Example: K.Icon("skills", 8, 8, K.S(18), K.C.accent)
local function arcPts(cx, cy, r, a0, a1)
    local out, n = {}, math.max(4, math.ceil(math.abs(a1 - a0) / 20))
    for i = 0, n do
        local a = math.rad(a0 + (a1 - a0) * i / n)
        out[#out + 1] = cx + math.cos(a) * r
        out[#out + 1] = cy + math.sin(a) * r
    end
    return out
end
K.ICONS = {
    trooper = { { arc = { 12, 8, 4, 0, 360 } }, { arc = { 12, 21, 8, 180, 360 } } },
    skills = { { 12, 3, 14.5, 8.5, 20, 9.2, 16, 13, 17, 19, 12, 16.3, 7, 19, 8, 13, 4, 9.2, 9.5, 8.5, closed = true } },
    jobs = { { 4, 8, 20, 8, 20, 20, 4, 20, closed = true }, { 9, 8, 9, 5, 15, 5, 15, 8 }, { 4, 13, 20, 13 } },
    shop = { { 5, 9, 19, 9, 18, 21, 6, 21, closed = true }, { arc = { 12, 9, 3.5, 180, 360 } } },
    battalion = { { 12, 3, 20, 7, 20, 12, 17, 17.5, 12, 21, 7, 17.5, 4, 12, 4, 7, closed = true } },
    radio = { { arc = { 12, 12, 7, 200, 340 } }, { arc = { 12, 12, 3.5, 200, 340 } }, { 12, 12, 12, 21 } },
    class = { { arc = { 12, 12, 7, 0, 360 } }, { 12, 2, 12, 7 }, { 12, 17, 12, 22 }, { 2, 12, 7, 12 }, { 17, 12, 22, 12 } },
    settings = { { 4, 6, 20, 6 }, { 4, 12, 20, 12 }, { 4, 18, 20, 18 }, { 14, 4, 14, 8 }, { 8, 10, 8, 14 }, { 16, 16, 16, 20 } },
    staffhome = { { 3, 11, 12, 4, 21, 11, 21, 20, 15, 20, 15, 14, 9, 14, 9, 20, 3, 20, closed = true } },
    players = { { arc = { 9, 8, 3, 0, 360 } }, { arc = { 9, 20, 6, 180, 360 } }, { arc = { 16, 8, 3, 270, 450 } }, { arc = { 15, 20, 6, 270, 360 } } },
    maps = { { 3, 6, 9, 4, 15, 6, 21, 4, 21, 18, 15, 20, 9, 18, 3, 20, closed = true }, { 9, 4, 9, 18 }, { 15, 6, 15, 20 } },
    server = { { arc = { 12, 12, 3, 0, 360 } }, { arc = { 12, 12, 7, 0, 360 } }, { 12, 2, 12, 5 }, { 12, 19, 12, 22 }, { 2, 12, 5, 12 }, { 19, 12, 22, 12 },
        { 4.9, 4.9, 7, 7 }, { 17, 17, 19.1, 19.1 }, { 4.9, 19.1, 7, 17 }, { 17, 7, 19.1, 4.9 } },
    editor = { { 4, 20, 8, 20, 18, 10, 14, 6, 4, 16, closed = true }, { 12.5, 7.5, 16.5, 11.5 } },
    quiz = { { arc = { 12, 8.5, 4, 180, 420 } }, { 14, 12, 12, 13.5, 12, 15.5 }, { 12, 19, 12, 20 } },
    profiler = { { 3, 12, 7, 12, 10, 4, 14, 20, 17, 12, 21, 12 } },
    commands = { { 3, 5, 21, 5, 21, 19, 3, 19, closed = true }, { 7, 9, 10, 12, 7, 15 }, { 12, 15, 17, 15 } },
    inventory = { { 5, 8, 19, 8, 19, 21, 5, 21, closed = true }, { 9, 8, 9, 5, 15, 5, 15, 8 }, { 9, 13, 15, 13 } },
    resume = { { 8, 5, 19, 12, 8, 19, closed = true } },
    power = { { arc = { 12, 13, 7, 300, 600 } }, { 12, 3, 12, 11 } },
    menu = { { 4, 6, 20, 6 }, { 4, 12, 20, 12 }, { 4, 18, 20, 18 } },
    search = { { arc = { 10, 10, 6, 0, 360 } }, { 14.5, 14.5, 20, 20 } },
    lock = { { 5, 11, 19, 11, 19, 21, 5, 21, closed = true }, { arc = { 12, 11, 4.5, 180, 360 } } },
    learn = { { 12, 6, 12, 20 }, { 12, 6, 8, 4.5, 3, 4.5, 3, 18.5, 8, 18.5, 12, 20 }, { 12, 6, 16, 4.5, 21, 4.5, 21, 18.5, 16, 18.5, 12, 20 } },
}
local iconCache, iconCount = {}, 0
local function thickSeg(out, x1, y1, x2, y2, t)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    dx, dy = dx / len * t * 0.5, dy / len * t * 0.5
    -- (square caps: each end pushed out half the width, so joints close)
    x1, y1, x2, y2 = x1 - dx, y1 - dy, x2 + dx, y2 + dy
    local nx, ny = -dy, dx
    local a, b, c, d = { x = x1 + nx, y = y1 + ny }, { x = x2 + nx, y = y2 + ny }, { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny }
    -- (DrawPoly wants clockwise on screen, y down: positive cross product)
    local cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    out[#out + 1] = cross > 0 and { a, b, c, d } or { d, c, b, a }
end
local function iconPolys(name, x, y, size)
    local byName = iconCache[name]
    if not byName then byName = {} iconCache[name] = byName end
    local key = (size * 8192 + x) * 8192 + y   -- (a number key: no string made per frame)
    local c = byName[key]
    if c then return c end
    local def = K.ICONS[name]
    if not def then return nil end
    local k = size / 24
    local t = math.max(1.5, size / 12)
    c = {}
    for _, st in ipairs(def) do
        local p = st.arc and arcPts(st.arc[1], st.arc[2], st.arc[3], st.arc[4], st.arc[5]) or st
        local n = math.floor(#p / 2)
        for i = 1, n - 1 do
            thickSeg(c, x + p[i * 2 - 1] * k, y + p[i * 2] * k, x + p[i * 2 + 1] * k, y + p[i * 2 + 2] * k, t)
        end
        if st.closed and n > 2 then
            thickSeg(c, x + p[n * 2 - 1] * k, y + p[n * 2] * k, x + p[1] * k, y + p[2] * k, t)
        end
    end
    iconCount = iconCount + 1
    if iconCount > 400 then iconCache, iconCount = {}, 0 byName = {} iconCache[name] = byName end
    byName[key] = c
    return c
end
function K.Icon(name, x, y, size, col, a)
    local polys = iconPolys(name, math.floor(x), math.floor(y), math.floor(size))
    if not polys then return end
    draw.NoTexture()
    setCol(col or C.text, a)
    for i = 1, #polys do surface.DrawPoly(polys[i]) end
end

-- K.Arrow(cx, cy, size, dir, col): a small filled triangle centred on cx,
-- cy pointing "down" or "right" (drawn, so no font glyph is needed).
local arrowPts = { {}, {}, {} }
function K.Arrow(cx, cy, size, dir, col)
    local r = size * 0.5
    local a, b, c = arrowPts[1], arrowPts[2], arrowPts[3]
    if dir == "right" then
        a.x, a.y = cx - r * 0.6, cy - r
        b.x, b.y = cx + r * 0.6, cy
        c.x, c.y = cx - r * 0.6, cy + r
    else
        a.x, a.y = cx - r, cy - r * 0.6
        b.x, b.y = cx + r, cy - r * 0.6
        c.x, c.y = cx, cy + r * 0.6
    end
    draw.NoTexture()
    setCol(col or C.textDim)
    surface.DrawPoly(arrowPts)
end

-- K.Fit(text, font, maxW): returns text cut to fit maxW pixels with "…" at
-- the end (or the text as is when it fits). Cached; cut by whole UTF-8
-- characters. Example: draw.SimpleText(K.Fit(name, f, w - 20), f, 10, 10, C.text)
local fitCache, fitCount = {}, 0
function K.Fit(text, font, maxW)
    text = tostring(text or "")
    local key = text .. "|" .. font .. "|" .. math.floor(maxW)
    local cached = fitCache[key]
    if cached then return cached end
    surface.SetFont(font)
    local out = text
    if surface.GetTextSize(text) > maxW then
        out = "…"
        local n = utf8.len(text)
        for i = (n or #text) - 1, 1, -1 do
            -- (GMod's utf8.offset can return nil; fall back to bytes)
            local o = n and utf8.offset(text, i + 1)
            local cut = o and (o - 1) or i
            local try = string.sub(text, 1, cut) .. "…"
            if surface.GetTextSize(try) <= maxW then out = try break end
        end
    end
    if fitCount > 4000 then fitCache, fitCount = {}, 0 end
    fitCache[key] = out
    fitCount = fitCount + 1
    return out
end

--------------------------------------------------------------------------
-- Panels
--------------------------------------------------------------------------

-- K.Tint(panel, getCol): give a window its own accent colour: its Paint swaps
-- the accent in and PaintOver (after the children) puts it back, so every
-- Kit widget inside draws with it. getCol() returns a Color or nil (= normal).
-- Call it after setting the panel's own Paint. Used by the datapad.
-- Example: K.Tint(frame, function() return Color(230, 130, 40) end)
function K.Tint(panel, getCol)
    local paint, over = panel.Paint, panel.PaintOver
    function panel:Paint(w, h)
        self.rhylibAccent = C.accent
        local c = getCol()
        if c then C.accent = c end
        if paint then return paint(self, w, h) end
    end
    function panel:PaintOver(w, h)
        if over then over(self, w, h) end
        if self.rhylibAccent then
            C.accent = self.rhylibAccent
            self.rhylibAccent = nil
        end
    end
end

-- K.Button(parent, text, fn, opts): a DButton in the house style. Returns it
-- (size and dock it yourself; height is set: 34, or 26 when small).
-- text: a string or a function returning one (redrawn every frame).
-- fn(button): called on click (not when disabled). opts:
--   accent   bright stripe          danger   red stripe
--   small    26 px tall, small font enabled  bool or function -> bool (dim + no click when false)
--   selected function -> bool: drawn pressed (tabs, choices)
--   col      Color: colour-coded button (faint wash + wide strip)
--   tooltip  text                   align    "left" (default centred)
-- Example: K.Button(panel, "Save", function() save() end, { accent = true }):Dock(BOTTOM)
function K.Button(parent, text, fn, opts)
    opts = opts or {}
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.label = text
    b.opts = opts
    b:SetTall(opts.small and K.S(26) or K.S(34))
    if opts.tooltip then b:SetTooltip(opts.tooltip) end
    function b:IsOn()
        local en = self.opts.enabled
        if en == nil then return true end
        if isfunction(en) then return en() and true or false end
        return en and true or false
    end
    function b:Paint(w, h)
        local on = self:IsOn()
        local col = C.button
        if on and self:IsDown() then col = C.buttonDown elseif on and self:IsHovered() then col = C.buttonHover end
        if self.opts.selected and self.opts.selected() then col = C.buttonDown end
        setCol(col)
        surface.DrawRect(0, 0, w, h)
        setCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        setCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        -- opts.col: a colour-coded button (a faint wash and a wider strip)
        local cc = self.opts.col
        if cc then
            setCol(cc, on and 18 or 8)
            surface.DrawRect(1, 1, w - 2, h - 2)
        end
        local stripe = self.opts.danger and C.bad or (cc or C.accent)
        setCol(stripe, on and ((self.opts.accent or cc) and 255 or 200) or 60)
        surface.DrawRect(1, 1, math.max(2, K.S(cc and 5 or 3)), h - 2)
        local label = isfunction(self.label) and self.label() or self.label
        local font = K.Font(self.opts.small and 12 or 13, 700)
        local tc = on and C.text or C.textDim
        if self.opts.align == "left" then
            draw.SimpleText(string.upper(label), font, K.S(14), h * 0.5, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(string.upper(label), font, w * 0.5, h * 0.5, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return true
    end
    function b:DoClick()
        if not self:IsOn() then return end
        surface.PlaySound("ui/buttonclick.wav")
        if fn then fn(self) end
    end
    return b
end

-- K.Label(parent, text, size, weight, col): a wrapping DLabel whose height
-- follows its text (dock it TOP). size/weight as K.Font, col default C.text.
function K.Label(parent, text, size, weight, col)
    local l = vgui.Create("DLabel", parent)
    l:SetText(text or "")
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    K.ThemedText(l, col or C.text, size or 14, weight)
    return l
end

-- K.ThemedText(panel, col, size, weight): a DLabel-like panel's text colour
-- and font that follow a theme switch (a DLabel copies its colour when
-- set, so it is set again after a switch). col is a token Color.
-- Example: K.ThemedText(myLabel, C.textDim, 13)
function K.ThemedText(l, col, size, weight)
    l.rhylibTextCol, l.rhylibFontSize, l.rhylibFontWeight = col, size, weight
    l:SetTextColor(col)
    if size then l:SetFont(K.Font(size, weight)) end
    l.rhylibStamp = UI.themeStamp or 0
    local think = l.Think
    function l:Think(...)
        if self.rhylibStamp ~= (UI.themeStamp or 0) then
            self.rhylibStamp = UI.themeStamp or 0
            self:SetTextColor(self.rhylibTextCol)
            if self.rhylibFontSize then self:SetFont(K.Font(self.rhylibFontSize, self.rhylibFontWeight)) end
        end
        if think then return think(self, ...) end
    end
end

-- K.Heading(parent, text, col): a section heading panel (32 px): caps text
-- with a rule under it. Returns the panel (dock it TOP).
-- col (optional): a colour-coded section (a chip before the title, the
-- title and rule in that colour).
function K.Heading(parent, text, col)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(K.S(32))
    function p:Paint(w, h)
        local x = 0
        if col then
            local c = K.S(10)
            setCol(col)
            surface.DrawRect(0, h * 0.5 - c * 0.5, c, c)
            x = c + K.S(8)
        end
        draw.SimpleText(string.upper(text), K.Font(14, 700), x, h * 0.5, col or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        setCol(col or C.accent, col and 160 or 120)
        surface.DrawRect(0, h - 2, w, col and 2 or 1)
    end
    return p
end

-- K.Scroll(parent): a DScrollPanel with a thin bar in the house style.
-- Dock children TOP inside it. Leave ~10 px right margin on them for the bar.
function K.Scroll(parent)
    local sp = vgui.Create("DScrollPanel", parent)
    local bar = sp:GetVBar()
    bar:SetWide(K.S(6))
    bar:SetHideButtons(true)
    function bar:Paint(w, h)
        setCol(C.row)
        surface.DrawRect(0, 0, w, h)
    end
    function bar.btnGrip:Paint(w, h)
        setCol(self:IsHovered() and C.accent or C.tick)
        surface.DrawRect(0, 0, w, h)
    end
    return sp
end

-- K.Row(parent, title, desc): a row with a label (and a dim description) on
-- the left and a control on the right. Returns the row; put the control in
-- row.right (320 px wide; change with row.right:SetWide). 40 px tall, 52
-- with a description.
function K.Row(parent, title, desc)
    local row = vgui.Create("DPanel", parent)
    row:SetTall(desc and K.S(52) or K.S(40))
    row:DockPadding(K.S(12), K.S(6), K.S(12), K.S(6))
    function row:Paint(w, h)
        setCol(self:IsHovered() and C.rowAlt or C.row)
        surface.DrawRect(0, 0, w, h)
        setCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(title, K.Font(14, 500), K.S(12), desc and h * 0.36 or h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if desc then
            draw.SimpleText(desc, K.Font(12), K.S(12), h * 0.70, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    row.right = vgui.Create("DPanel", row)
    row.right:Dock(RIGHT)
    row.right:SetWide(K.S(320))
    row.right.Paint = nil
    return row
end

-- K.Choices(parent, options, get, set): a row of mutually exclusive buttons.
-- options = { { value, label }, ... } (left to right). get() returns the
-- current value (that button is drawn pressed), set(value) is called on a
-- click. Returns a panel with no size of its own: Dock(FILL) it in a row.
function K.Choices(parent, options, get, set)
    local p = vgui.Create("DPanel", parent)
    p.Paint = nil
    for i, o in ipairs(options) do
        local b = K.Button(p, o[2], function() set(o[1]) end, { small = true, selected = function() return get() == o[1] end })
        b:Dock(RIGHT)
        b:DockMargin(K.S(4), 0, 0, 0)
        surface.SetFont(K.Font(12, 700))
        b:SetWide(surface.GetTextSize(string.upper(o[2])) + K.S(26))
        b:SetZPos(-i)  -- keep the given order left to right
    end
    return p
end

-- K.Toggle(parent, get, set): an ON/OFF switch, 64 px wide. get() -> bool,
-- set(newBool) on click. Returns the DButton (dock it RIGHT in a row).
function K.Toggle(parent, get, set)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetWide(K.S(64))
    function b:Paint(w, h)
        local on = get()
        local bh = K.S(22)
        local y = math.floor((h - bh) * 0.5)
        setCol(on and C.buttonDown or C.button)
        surface.DrawRect(0, y, w, bh)
        setCol(C.edgeDark)
        surface.DrawOutlinedRect(0, y, w, bh)
        local kw = math.floor(w * 0.5) - 2
        setCol(on and C.accent or C.tick)
        surface.DrawRect(on and (w - kw - 2) or 2, y + 2, kw, bh - 4)
        draw.SimpleText(on and "ON" or "OFF", K.Font(11, 700), on and K.S(8) or w - K.S(8), y + bh * 0.5, C.textDim,
            on and TEXT_ALIGN_LEFT or TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        set(not get())
    end
    return b
end

-- K.Slider(parent, min, max, decimals, get, set): a drag bar with the value
-- on its right. Whole numbers unless decimals is given. set(v) runs only
-- when the rounded value changes. Returns a panel (Dock(FILL) it).
function K.Slider(parent, min, max, decimals, get, set)
    local p = vgui.Create("DPanel", parent)
    p.Paint = nil
    local val = vgui.Create("DPanel", p)
    val:Dock(RIGHT)
    val:SetWide(K.S(48))
    function val:Paint(w, h)
        draw.SimpleText(string.format("%." .. (decimals or 0) .. "f", get()), K.Font(13, 700), w, h * 0.5, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local bar = vgui.Create("DPanel", p)
    bar:Dock(FILL)
    bar:DockMargin(0, 0, K.S(10), 0)
    bar:SetCursor("hand")
    local function setFrom(x, w)
        local f = math.Clamp(x / math.max(1, w), 0, 1)
        local v = min + (max - min) * f
        local m = 10 ^ (decimals or 0)
        v = math.floor(v * m + 0.5) / m
        if v ~= get() then set(v) end  -- only when it changes, not every frame
    end
    function bar:OnMousePressed() self.dragging = true self:MouseCapture(true) setFrom(self:CursorPos(), self:GetWide()) end
    function bar:OnMouseReleased() self.dragging = false self:MouseCapture(false) end
    function bar:Think() if self.dragging then setFrom(self:CursorPos(), self:GetWide()) end end
    function bar:Paint(w, h)
        local y = math.floor(h * 0.5) - 2
        setCol(C.button)
        surface.DrawRect(0, y, w, 4)
        local f = math.Clamp((get() - min) / (max - min), 0, 1)
        setCol(C.accent)
        surface.DrawRect(0, y, w * f, 4)
        local kx = math.floor(w * f)
        setCol(C.text)
        surface.DrawRect(math.Clamp(kx - 3, 0, w - 6), y - 5, 6, 14)
    end
    return p
end

-- K.TextEntry(parent, placeholder): a one-line DTextEntry in the house style
-- (30 px tall; accent outline while focused). Use its normal methods:
-- GetValue, SetText, OnEnter, OnChange, SetUpdateOnType + OnValueChange.
function K.TextEntry(parent, placeholder)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont(K.Font(14))
    e.rhylibFont, e.rhylibStamp = e:GetFont(), UI.themeStamp or 0
    e:SetPlaceholderText(placeholder or "")
    e:SetTall(K.S(30))
    e:SetPaintBackground(false)
    function e:Paint(w, h)
        -- (a theme switch with another font family: the kit font again,
        -- unless the caller picked its own)
        if self.rhylibStamp ~= (UI.themeStamp or 0) then
            self.rhylibStamp = UI.themeStamp or 0
            if self:GetFont() == self.rhylibFont then
                self:SetFont(K.Font(14))
                self.rhylibFont = self:GetFont()
            end
        end
        setCol(C.row)
        surface.DrawRect(0, 0, w, h)
        setCol(self:HasFocus() and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if self:GetText() == "" and not self:HasFocus() then
            draw.SimpleText(self:GetPlaceholderText(), self:GetFont(), K.S(4), h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return e
end

--------------------------------------------------------------------------
-- More controls: dropdown, number, search, fold, swatches
--------------------------------------------------------------------------

-- The one open dropdown list (closed by a click outside it, Esc, or a pick).
local openList
local function closeList()
    if IsValid(openList) then openList:Remove() end
    openList = nil
end
K.CloseDropdown = closeList
-- K.DropdownOpen(): true while a dropdown list or colour mixer is open, or
-- one was closed by Esc a moment ago (the pause menu's Esc handler then
-- leaves the menu open).
local escClosedAt = 0
function K.DropdownOpen() return IsValid(openList) or RealTime() - escClosedAt < 0.3 end
local function escClose()
    escClosedAt = RealTime()
    closeList()
end

-- K.Dropdown(parent, options, get, set, opts): a select box. options =
-- { { value, label, sub? }, ... } or a function returning that (asked each
-- time it opens). get() -> current value, set(value) on a pick. Shows the
-- current option's label and a drawn arrow; a click opens the list under it (with a
-- filter box when there are more than 12). opts: placeholder (shown when
-- nothing matches), width. Returns the DButton (dock it RIGHT in a row).
-- Example: K.Dropdown(row.right, { { "f5", "F5" }, { "real", "Realistic" } }, getLayout, setLayout):Dock(RIGHT)
function K.Dropdown(parent, options, get, set, opts)
    opts = opts or {}
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetWide(opts.width or K.S(220))
    local function list()
        local o = options
        if isfunction(o) then o = o() end
        return o or {}
    end
    -- (the label is drawn every frame: a function's list is asked at most
    -- twice a second for it, and every time the list opens)
    local cached, cachedAt = nil, 0
    local function labelOf(v)
        local l = cached
        if not l or not isfunction(options) or RealTime() - cachedAt > 0.5 then
            l = list()
            cached, cachedAt = l, RealTime()
        end
        for _, o in ipairs(l) do
            if o[1] == v then return o[2] end
        end
        if v == nil or v == "" then return opts.placeholder or "—" end
        return tostring(v)
    end
    function b:Paint(w, h)
        local bh = math.min(h, K.S(34))
        local y = math.floor((h - bh) * 0.5)
        setCol(C.row)
        surface.DrawRect(0, y, w, bh)
        setCol((self:IsHovered() or openList and openList.owner == self) and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, y, w, bh)
        local f = K.Font(14, 500)
        draw.SimpleText(K.Fit(labelOf(get()), f, w - K.S(36)), f, K.S(10), y + bh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        K.Arrow(w - K.S(15), y + bh * 0.5, K.S(9), "down", C.textDim)
        return true
    end
    function b:DoClick()
        if openList and openList.owner == self then closeList() return end
        closeList()
        surface.PlaySound("ui/buttonclick.wav")
        local items = list()
        local x, y = self:LocalToScreen(0, self:GetTall())
        local rowH = K.S(32)
        local filter = #items > 12
        local shown = math.min(#items, 10)
        local w = math.max(self:GetWide(), K.S(220))
        local p = vgui.Create("EditablePanel")
        openList = p
        p.owner = self
        p:SetDrawOnTop(true)
        p:MakePopup()
        p:SetKeyboardInputEnabled(filter)
        local hgt = shown * rowH + (filter and K.S(38) or 0) + 4
        if y + hgt > ScrH() then y = math.max(0, y - self:GetTall() - hgt) end
        p:SetPos(math.min(x, ScrW() - w), y + 2)
        p:SetSize(w, hgt)
        p:DockPadding(2, 2, 2, 2)
        function p:Paint(pw, ph)
            setCol(C.bg)
            surface.DrawRect(0, 0, pw, ph)
            setCol(C.edgeLight)
            surface.DrawOutlinedRect(0, 0, pw, ph)
        end
        -- (a click anywhere outside closes it)
        p.wasDown = true
        function p:Think()
            local down = input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT)
            if down and not self.wasDown then
                local mx, my = gui.MousePos()
                local px, py = self:GetPos()
                -- (a click on the box itself: its DoClick closes the list, so
                -- closing here too would make that click open it again)
                local outside = mx < px or my < py or mx > px + self:GetWide() or my > py + self:GetTall()
                if outside and vgui.GetHoveredPanel() ~= b then closeList() return end
            end
            self.wasDown = down
            if input.IsKeyDown(KEY_ESCAPE) then escClose() return end
            if not IsValid(b) or not b:IsVisible() then closeList() end
        end
        local scroll = K.Scroll(p)
        local function fill(q)
            scroll:Clear()
            q = string.lower(q or "")
            for _, o in ipairs(items) do
                local text = tostring(o[2])
                if q == "" or string.find(string.lower(text), q, 1, true) then
                    local r = vgui.Create("DButton", scroll)
                    r:SetText("")
                    r:Dock(TOP)
                    r:SetTall(rowH)
                    function r:Paint(rw, rh)
                        local cur = get() == o[1]
                        if cur then setCol(C.buttonDown) surface.DrawRect(0, 0, rw, rh)
                        elseif self:IsHovered() then setCol(C.buttonHover) surface.DrawRect(0, 0, rw, rh) end
                        if cur then setCol(C.accent) surface.DrawRect(0, 0, 3, rh) end
                        draw.SimpleText(K.Fit(text, K.Font(14, cur and 700 or 500), rw - K.S(20)), K.Font(14, cur and 700 or 500), K.S(10), o[3] and rh * 0.36 or rh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        if o[3] then draw.SimpleText(K.Fit(o[3], K.Font(11), rw - K.S(20)), K.Font(11), K.S(10), rh * 0.74, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
                        return true
                    end
                    function r:DoClick()
                        surface.PlaySound("ui/buttonclick.wav")
                        closeList()
                        set(o[1])
                    end
                end
            end
        end
        if filter then
            local e = K.TextEntry(p, "Type to filter…")
            e:Dock(TOP)
            e:DockMargin(2, 2, 2, 4)
            e:SetUpdateOnType(true)
            function e:OnValueChange(v) fill(v) end
            e:RequestFocus()
        end
        scroll:Dock(FILL)
        fill("")
    end
    function b:OnRemove() if openList and openList.owner == self then closeList() end end
    return b
end

-- K.Number(parent, opts, get, set): a number control. With opts.min and
-- opts.max: a drag bar plus a box you can type in; without: just the box
-- with - / +. opts: min, max, step (default 1, or 10^-decimals),
-- decimals, unit (text after the box, e.g. "metres"), width. set(v) only
-- when the value changes (clamped to min / max when given). Returns a panel
-- (dock it RIGHT / FILL in a row).
function K.Number(parent, opts, get, set)
    opts = opts or {}
    local dec = opts.decimals or 0
    local step = opts.step or (10 ^ -dec)
    local function clamp(v)
        if opts.min then v = math.max(opts.min, v) end
        if opts.max then v = math.min(opts.max, v) end
        local m = 10 ^ dec
        return math.floor(v * m + 0.5) / m
    end
    local function fmt(v) return string.format("%." .. dec .. "f", tonumber(v) or 0) end
    local p = vgui.Create("DPanel", parent)
    p.Paint = nil
    p:SetWide(opts.width or K.S(320))
    if opts.unit then
        local u = vgui.Create("DPanel", p)
        u:Dock(RIGHT)
        surface.SetFont(K.Font(12))
        u:SetWide(math.min(K.S(110), surface.GetTextSize(opts.unit) + K.S(10)))
        function u:Paint(w, h) draw.SimpleText(opts.unit, K.Font(12), K.S(8), h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end
    local e = K.TextEntry(p, "")
    e:Dock(RIGHT)
    e:SetWide(K.S(70))
    e:DockMargin(0, K.S(4), 0, K.S(4))
    e:SetText(fmt(get()))
    local function apply(v)
        v = clamp(v)
        if v ~= get() then set(v) end
        e:SetText(fmt(get()))
    end
    function e:OnEnter() local v = tonumber(self:GetValue()) if v then apply(v) else self:SetText(fmt(get())) end end
    function e:OnLoseFocus() self:OnEnter() end
    function e:Think()
        if not self:HasFocus() then
            local t = fmt(get())
            if self:GetValue() ~= t then self:SetText(t) end
        end
    end
    if opts.min and opts.max and opts.max > opts.min then
        local bar = vgui.Create("DPanel", p)
        bar:Dock(FILL)
        bar:DockMargin(0, 0, K.S(12), 0)
        bar:SetCursor("hand")
        local function from(x, w) apply(opts.min + (opts.max - opts.min) * math.Clamp(x / math.max(1, w), 0, 1)) end
        function bar:OnMousePressed() self.drag = true self:MouseCapture(true) from(self:CursorPos(), self:GetWide()) end
        function bar:OnMouseReleased() self.drag = false self:MouseCapture(false) end
        function bar:Think() if self.drag then from(self:CursorPos(), self:GetWide()) end end
        function bar:Paint(w, h)
            local y = math.floor(h * 0.5) - 2
            setCol(C.button)
            surface.DrawRect(0, y, w, 4)
            local f = math.Clamp(((tonumber(get()) or 0) - opts.min) / (opts.max - opts.min), 0, 1)
            setCol(C.accent)
            surface.DrawRect(0, y, w * f, 4)
            setCol(C.text)
            local kx = math.Clamp(math.floor(w * f) - 4, 0, w - 8)
            surface.DrawRect(kx, y - 5, 8, 14)
        end
    else
        for _, d in ipairs({ { "+", 1 }, { "-", -1 } }) do
            local btn = K.Button(p, d[1], function() apply((tonumber(get()) or 0) + step * d[2]) end, { small = true })
            btn:Dock(RIGHT)
            btn:SetWide(K.S(30))
            btn:DockMargin(K.S(4), K.S(7), 0, K.S(7))
        end
    end
    return p
end

-- K.Search(parent, placeholder, onChange): a search box with a magnifier
-- (36 px tall). onChange(text) on every key. Returns the DTextEntry.
function K.Search(parent, placeholder, onChange)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont(K.Font(15))
    e:SetPlaceholderText(placeholder or "Search…")
    e:SetTall(K.S(38))
    e:SetPaintBackground(false)
    e:SetUpdateOnType(true)
    e:SetTextInset(K.S(34), 0)
    function e:OnValueChange(v) if onChange then onChange(v) end end
    function e:Paint(w, h)
        setCol(C.row)
        surface.DrawRect(0, 0, w, h)
        setCol(self:HasFocus() and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        -- (a magnifier: a ring and a handle)
        local cx, cy, r = K.S(16), h * 0.5 - 1, K.S(6)
        setCol(C.textDim)
        for a = 0, 330, 30 do
            local r1, r2 = math.rad(a), math.rad(a + 30)
            surface.DrawLine(cx + math.cos(r1) * r, cy + math.sin(r1) * r, cx + math.cos(r2) * r, cy + math.sin(r2) * r)
        end
        surface.DrawLine(cx + r * 0.7, cy + r * 0.7, cx + r * 1.6, cy + r * 1.6)
        self:DrawTextEntryText(C.text, C.accent, C.text)
        if self:GetText() == "" and not self:HasFocus() then
            draw.SimpleText(self:GetPlaceholderText(), self:GetFont(), K.S(34), h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return e
end

-- K.Fold(parent, title, opts): a section that folds open and shut. Returns
-- the fold; put rows in fold.body (Dock TOP). opts: open (default true),
-- count (dim number after the title), dashed (a quieter look, for
-- "Advanced"), onToggle(open). The fold sizes itself to its rows.
function K.Fold(parent, title, opts)
    opts = opts or {}
    local f = vgui.Create("DPanel", parent)
    f.open = opts.open ~= false
    function f:Paint(w, h)
        setCol(opts.dashed and C.bg or C.row)
        surface.DrawRect(0, 0, w, h)
        setCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local head = vgui.Create("DButton", f)
    head:SetText("")
    head:Dock(TOP)
    head:SetTall(K.S(42))
    function head:Paint(w, h)
        setCol(self:IsHovered() and C.rowHover or C.header)
        surface.DrawRect(0, 0, w, h)
        local font = K.Font(14, opts.dashed and 500 or 700)
        K.Arrow(K.S(18), h * 0.5, K.S(9), f.open and "down" or "right", C.textDim)
        surface.SetFont(font)
        local tw = surface.GetTextSize(f.title or title)
        draw.SimpleText(f.title or title, font, K.S(32), h * 0.5, opts.dashed and C.textDim or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if f.count then draw.SimpleText(f.count, K.Font(13), K.S(40) + tw, h * 0.5, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        return true
    end
    f.count = opts.count
    f.body = vgui.Create("DPanel", f)
    f.body:Dock(TOP)
    f.body.Paint = nil
    function f.body:PerformLayout() self:SizeToChildren(false, true) end
    function f:PerformLayout()
        self.body:SetVisible(self.open)
        local h = head:GetTall()
        if self.open then
            self.body:InvalidateLayout(true)
            h = h + self.body:GetTall()
        end
        self:SetTall(h + 1)
    end
    function head:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        f.open = not f.open
        f:InvalidateLayout(true)
        if IsValid(f:GetParent()) then f:GetParent():InvalidateLayout() end
        if opts.onToggle then opts.onToggle(f.open) end
    end
    return f
end

-- K.Swatches(parent, swatches, get, set): colour squares to pick from, and a
-- last one that opens a colour mixer. swatches = { Color, ... }; get() ->
-- Color, set(Color). Returns a panel (Dock(RIGHT) / FILL it).
function K.Swatches(parent, swatches, get, set)
    local p = vgui.Create("DPanel", parent)
    p.Paint = nil
    local size, gap = K.S(26), K.S(6)
    p:SetWide((#swatches + 1) * (size + gap))
    local function same(a, b) return a and b and a.r == b.r and a.g == b.g and a.b == b.b end
    for i, col in ipairs(swatches) do
        local s = vgui.Create("DButton", p)
        s:SetText("")
        s:SetSize(size, size)
        function s:Paint(w, h)
            surface.SetDrawColor(col.r, col.g, col.b, 255)
            surface.DrawRect(2, 2, w - 4, h - 4)
            setCol(same(get(), col) and C.accent or C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h, same(get(), col) and 2 or 1)
            return true
        end
        function s:DoClick() surface.PlaySound("ui/buttonclick.wav") set(Color(col.r, col.g, col.b)) end
    end
    local custom = vgui.Create("DButton", p)
    custom:SetText("")
    custom:SetSize(size, size)
    custom:SetTooltip("Pick any colour")
    -- (the squares are placed by the panel, so they follow its height)
    function p:PerformLayout(w, h)
        for i, ch in ipairs(self:GetChildren()) do ch:SetPos((i - 1) * (size + gap), math.floor((h - size) * 0.5)) end
    end
    function custom:Paint(w, h)
        local c = get() or C.text
        local isCustom = true
        for _, s in ipairs(swatches) do if same(c, s) then isCustom = false end end
        for i = 0, 5 do
            local hc = HSVToColor(i * 60, 0.75, 0.95)
            surface.SetDrawColor(hc.r, hc.g, hc.b)
            surface.DrawRect(2 + math.floor((w - 4) * i / 6), 2, math.ceil((w - 4) / 6), h - 4)
        end
        if isCustom then surface.SetDrawColor(c.r, c.g, c.b) surface.DrawRect(w * 0.25, h * 0.25, w * 0.5, h * 0.5) end
        setCol(isCustom and C.accent or C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h, isCustom and 2 or 1)
        return true
    end
    function custom:OnRemove() if openList and openList.owner == self then closeList() end end
    function custom:DoClick()
        -- (a second click on the square closes the mixer)
        if openList and openList.owner == self then closeList() return end
        closeList()
        local x, y = self:LocalToScreen(0, self:GetTall())
        local f = vgui.Create("EditablePanel")
        openList = f
        f.owner = self
        f:SetDrawOnTop(true)
        f:MakePopup()
        f:SetSize(K.S(260), K.S(230))
        f:SetPos(math.min(x, ScrW() - f:GetWide()), math.min(y + 2, ScrH() - f:GetTall()))
        f:DockPadding(K.S(8), K.S(8), K.S(8), K.S(8))
        function f:Paint(w, h) setCol(C.bg) surface.DrawRect(0, 0, w, h) setCol(C.edgeLight) surface.DrawOutlinedRect(0, 0, w, h) end
        f.wasDown = true
        function f:Think()
            local down = input.IsMouseDown(MOUSE_LEFT)
            if down and not self.wasDown then
                local mx, my = gui.MousePos()
                local px, py = self:GetPos()
                local outside = mx < px or my < py or mx > px + self:GetWide() or my > py + self:GetTall()
                if outside and vgui.GetHoveredPanel() ~= custom then closeList() return end
            end
            self.wasDown = down
            if input.IsKeyDown(KEY_ESCAPE) then escClose() return end
            if not IsValid(custom) or not custom:IsVisible() then closeList() end
        end
        local mix = vgui.Create("DColorMixer", f)
        mix:Dock(FILL)
        mix:SetPalette(false)
        mix:SetAlphaBar(false)
        mix:SetWangs(true)
        mix:SetColor(get() or C.text)
        -- (dragging: at most ten changes a second, the last one always sent)
        local last, wantC
        function mix:ValueChanged(c)
            wantC = Color(c.r, c.g, c.b)
            if timer.Exists("Rhylib.Kit.SwatchMix") then return end
            timer.Create("Rhylib.Kit.SwatchMix", 0.1, 1, function()
                if wantC and not (last and last.r == wantC.r and last.g == wantC.g and last.b == wantC.b) then
                    last = wantC
                    set(wantC)
                end
            end)
        end
    end
    return p
end

-- K.Menu(): a DermaMenu in the house style. AddOption(text, fn),
-- AddSpacer() and AddSubMenu(text) are restyled (submenus too, all the way
-- down). Call m:Open() to show it at the mouse.
local function styleMenu(m)
    function m:Paint(w, h)
        setCol(C.bg)
        surface.DrawRect(0, 0, w, h)
        setCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local function styleOption(o)
        K.ThemedText(o, C.text, 13)
        function o:Paint(w, h)
            if self:IsHovered() or (IsValid(self.SubMenu) and self.SubMenu:IsVisible()) then
                setCol(C.buttonHover)
                surface.DrawRect(0, 0, w, h)
            end
        end
        if IsValid(o.SubMenuArrow) then
            function o.SubMenuArrow:Paint(w, h) K.Arrow(w * 0.5, h * 0.5, K.S(8), "right", C.textDim) end
        end
    end
    local add, spacer, subm = m.AddOption, m.AddSpacer, m.AddSubMenu
    function m:AddOption(text, fn)
        local o = add(self, text, fn)
        styleOption(o)
        return o
    end
    if spacer then
        function m:AddSpacer(...)
            local sp = spacer(self, ...)
            if IsValid(sp) then
                function sp:Paint(w, h)
                    setCol(C.edgeLight)
                    surface.DrawRect(K.S(6), math.floor(h / 2), w - K.S(12), 1)
                end
            end
            return sp
        end
    end
    if subm then
        function m:AddSubMenu(text, fn)
            local sub, o = subm(self, text, fn)
            if IsValid(o) then styleOption(o) end
            if IsValid(sub) then styleMenu(sub) end
            return sub, o
        end
    end
    return m
end
function K.Menu()
    return styleMenu(DermaMenu())
end

-- K.Confirm(title, desc, yesText, onYes, opts): a small modal yes / no box
-- in the house style (Esc or Cancel closes it). opts.danger: the yes button
-- has the red stripe; opts.noText: the cancel button's text. Returns the frame.
-- Example: K.Confirm("Delete post", "This can't be undone.", "Delete", function() del() end, { danger = true })
function K.Confirm(title, desc, yesText, onYes, opts)
    opts = opts or {}
    local f = vgui.Create("EditablePanel")
    UI.prompts[f] = true
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(K.S(440), K.S(150))
    f:Center()
    f:MakePopup()
    f:DoModal()
    f:DockPadding(K.S(14), K.S(42), K.S(14), K.S(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title, ticks = "all" })
    end
    local d = K.Label(f, desc or "", 13, nil, C.textDim)
    d:Dock(TOP)
    local row = vgui.Create("DPanel", f)
    row:Dock(BOTTOM)
    row:SetTall(K.S(32))
    row.Paint = nil
    local yes = K.Button(row, yesText or "OK", function() f:Remove() if onYes then onYes() end end,
        { accent = not opts.danger, danger = opts.danger })
    yes:Dock(RIGHT)
    yes:SetWide(K.S(120))
    local no = K.Button(row, opts.noText or "Cancel", function() f:Remove() end)
    no:Dock(RIGHT)
    no:SetWide(K.S(100))
    no:DockMargin(0, 0, K.S(8), 0)
    return f
end

-- K.Prompt(title, desc, default, onOk): a small modal box asking for text (a
-- reason, a number). onOk(text) is called on OK or Enter; Cancel or Esc
-- just closes it. Returns the frame. Open prompts are kept in UI.prompts
-- (Esc closes them first).
UI.prompts = UI.prompts or {}
function K.Prompt(title, desc, default, onOk)
    local f = vgui.Create("EditablePanel")
    UI.prompts[f] = true
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(K.S(420), K.S(170))
    f:Center()
    f:MakePopup()
    f:DoModal()
    f:DockPadding(K.S(14), K.S(42), K.S(14), K.S(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title, ticks = "all" })
        draw.SimpleText(desc or "", K.Font(13), K.S(14), K.S(54), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local e = K.TextEntry(f, "")
    e:Dock(TOP)
    e:DockMargin(0, K.S(26), 0, K.S(12))
    e:SetText(default or "")
    e:RequestFocus()
    local row = vgui.Create("DPanel", f)
    row:Dock(BOTTOM)
    row:SetTall(K.S(32))
    row.Paint = nil
    local ok = K.Button(row, "OK", function() local t = e:GetText() f:Remove() onOk(t) end, { accent = true })
    ok:Dock(RIGHT)
    ok:SetWide(K.S(100))
    local cancel = K.Button(row, "Cancel", function() f:Remove() end)
    cancel:Dock(RIGHT)
    cancel:SetWide(K.S(100))
    cancel:DockMargin(0, 0, K.S(8), 0)
    e.OnEnter = function() ok:DoClick() end
    return f
end

-- Closers: what Esc closes before the pause menu opens (rhylib_menus
-- cl_10_pause.lua).
-- UI.RegisterCloser(id, fn): fn() closes your window if it's open and
-- returns true if it closed something. Same id = replaced (refresh-safe).
-- Example: Rhylib.UI.RegisterCloser("mywindow", function()
--              if IsValid(myFrame) then myFrame:Remove() return true end
--              return false
--          end)
-- UI.CloseAll(): runs every closer (pause, F4, scoreboard mouse, prompts,
-- inventory, spawn window...). Returns true if something was closed.
-- (The tables are never replaced: rhylib_menus' Menus.prompts and
-- Menus.closers are these same tables.)
UI.closers = UI.closers or {}
UI.closers.prompts = function()
    local any = false
    for p in pairs(UI.prompts) do
        if IsValid(p) then p:Remove() any = true end
        UI.prompts[p] = nil
    end
    return any
end
UI.closers.dropdown = function()
    if IsValid(openList) then closeList() return true end
    return false
end
function UI.RegisterCloser(id, fn) UI.closers[id] = fn end
function UI.CloseAll()
    local closed = false
    for _, fn in pairs(UI.closers) do
        if fn() then closed = true end
    end
    return closed
end
