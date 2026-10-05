--[[
    A small UI kit in the house style (same as the HUD, chat and inventory):
    dark plates, black outlines, a faint light line along the top, small
    corner ticks, caps labels, an accent stripe on buttons.

        local K = Rhylib.Menus.Kit
        K.Plate(x, y, w, h, { title = "Settings", ticks = true })   -- in a Paint
        K.Button(parent, "Resume", fn, { accent = true })
        K.Scroll(parent)
        K.Label(parent, "text", size, weight, color)

    Sizes are given at 1080p and scaled with K.S(n).
]]

local UI = Rhylib.UI
local Menus = Rhylib.Menus
Menus.Kit = Menus.Kit or {}
local K = Menus.Kit

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

function K.Scale() return ScrH() / 1080 end
function K.S(n) return math.floor(n * ScrH() / 1080 + 0.5) end
function K.Font(size, weight) return UI.Font(size, weight) end

local scratch = Color(0, 0, 0)
local function setCol(col, a)
    scratch.r, scratch.g, scratch.b, scratch.a = col.r, col.g, col.b, (col.a or 255) * (a or 255) / 255
    surface.SetDrawColor(scratch)
end
K.SetCol = setCol

-- Corner ticks (bottom corners, or all four).
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

-- Small caps label drawn in a Paint.
function K.Caps(text, x, y, col, align)
    draw.SimpleText(string.upper(text), K.Font(12, 700), x, y, col or C.label, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- Cut text to fit a width (cached; cut by whole UTF-8 characters).
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

-- Give a window its own accent colour: its Paint swaps the accent in and
-- PaintOver (after the children) puts it back. getCol() returns a Color or nil.
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

-- A button. opts: accent (filled stripe), danger (red stripe), small,
-- enabled (function or bool), tooltip, align ("left"), icon text.
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
        local stripe = self.opts.danger and C.bad or C.accent
        setCol(stripe, on and (self.opts.accent and 255 or 200) or 60)
        surface.DrawRect(1, 1, math.max(2, K.S(3)), h - 2)
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

-- A text label panel (auto-sized height).
function K.Label(parent, text, size, weight, col)
    local l = vgui.Create("DLabel", parent)
    l:SetFont(K.Font(size or 14, weight))
    l:SetTextColor(col or C.text)
    l:SetText(text or "")
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    return l
end

-- A section heading: caps text with a rule under it.
function K.Heading(parent, text)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(K.S(32))
    function p:Paint(w, h)
        draw.SimpleText(string.upper(text), K.Font(14, 700), 0, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        setCol(C.accent, 120)
        surface.DrawRect(0, h - 2, w, 1)
    end
    return p
end

-- A scroll panel with a thin bar in the house style.
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

-- A row with a label (and a dim description) on the left and a control
-- on the right. Returns the row; put the control in row.right.
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

-- A row of mutually exclusive choice buttons. options = { { value, label }, ... }.
-- get() returns the current value, set(value) changes it.
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

-- An on/off switch bound to get/set.
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

-- A number slider bound to get/set (whole numbers unless decimals given).
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

-- A one-line text box in the house style.
function K.TextEntry(parent, placeholder)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont(K.Font(14))
    e:SetPlaceholderText(placeholder or "")
    e:SetTall(K.S(30))
    e:SetPaintBackground(false)
    function e:Paint(w, h)
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

-- A small dropdown menu in the house style (DMenu with painted options).
function K.Menu()
    local m = DermaMenu()
    function m:Paint(w, h)
        setCol(C.bg)
        surface.DrawRect(0, 0, w, h)
        setCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local add = m.AddOption
    function m:AddOption(text, fn)
        local o = add(self, text, fn)
        o:SetTextColor(C.text)
        o:SetFont(K.Font(13))
        function o:Paint(w, h)
            if self:IsHovered() then
                setCol(C.buttonHover)
                surface.DrawRect(0, 0, w, h)
            end
        end
        return o
    end
    return m
end

-- Ask for text (a reason, a number). onOk(text) is called when confirmed.
Menus.prompts = Menus.prompts or {}
function K.Prompt(title, desc, default, onOk)
    local f = vgui.Create("EditablePanel")
    Menus.prompts[f] = true
    f.OnRemove = function(self) Menus.prompts[self] = nil end
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

-- Close every Rhylib menu that is open (pause, F4, scoreboard mouse).
-- Returns true if something was closed.
Menus.closers = Menus.closers or {}
Menus.closers.prompts = function()
    local any = false
    for p in pairs(Menus.prompts) do
        if IsValid(p) then p:Remove() any = true end
    end
    Menus.prompts = {}
    return any
end
function Menus.RegisterCloser(id, fn) Menus.closers[id] = fn end
function Menus.CloseAll()
    local closed = false
    for _, fn in pairs(Menus.closers) do
        if fn() then closed = true end
    end
    return closed
end
