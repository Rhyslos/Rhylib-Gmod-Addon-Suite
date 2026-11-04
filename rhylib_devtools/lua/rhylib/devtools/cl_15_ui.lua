--[[
    Editor windows in the house style (Rhylib.UI.Kit), for the dev tools:
    tabs down the left, the page in the middle, the orbit camera on the
    right. Nothing is laid out past the page's edge: rows of buttons wrap
    onto more lines, long labels are cut with "…" only as a last resort.

        local DU = Rhylib.Devtools.UI
        local win = DU.Window("Pose editor", { camera = { bone = "ValveBiped.Bip01_Spine2", dist = 110 } })
        win:AddTab("Pose", function(pg) pg:Heading("Pose") pg:Buttons({ { "Save", fn } }) end)
        win:Show("Pose")

    Window(title, opts) -> win (an EditablePanel, made popup). opts.camera
      = { bone, dist, head } adds the camera column (Rhylib.Devtools.orbit,
      cl_10_weapon_editors.lua's CalcView). win:AddTab(name, build) adds a
      tab, built the first time it's shown; win:Show(name); win.onKey(code)
      gets W / E / Q / Z presses (not while typing in a field). Esc closes
      an open list, then the window (a kit prompt over it first).
    A page (pg) has, each a full-width row docked in order:
      pg:Heading(text)                    pg:Note(text or fn)
      pg:Buttons({ { text|fn, fn, opts }, ... }, { wrap })   opts: accent,
          danger, selected = fn, enabled = fn, tip; one under the other
          (wrap = true: side by side, onto more lines when they don't fit)
      pg:Number(label, step, lo, hi, get, set, ctx)    - [value] +, hold
          repeats (DU.repeating while it does); typed values apply on
          Enter / leaving the field, only if changed
      pg:Toggle(label, get, set)
      pg:Choice(label, options|fn, get, set)      options { { value, text } };
          a button opening a list (with a filter box over 20 entries)
      pg:Slider(label, min, max, decimals, get, set)   min / max may be fns
      pg:Text(placeholder, get, set)              set on every key
      pg:Chips(options|fn, isOn, toggle)          wrapping on / off chips
      pg:List(columns, rows fn, selected fn, onPick, tall)
          rows fn -> { { id, { col1, col2, ... } }, ... }
      pg:Space(n)
]]

Rhylib.Devtools = Rhylib.Devtools or {}
local DT = Rhylib.Devtools
DT.UI = DT.UI or {}
local DU = DT.UI

local K = Rhylib.UI and Rhylib.UI.Kit
if not K then return end
local C = K.C
local S = K.S

local function fitText(text, font, w)
    return K.Fit(text, font, math.max(10, w))
end

--------------------------------------------------------------------------
-- A page: a scroll panel of full-width rows
--------------------------------------------------------------------------
local PAGE = {}

local function row(pg, tall)
    local r = vgui.Create("DPanel", pg.canvas)
    r:Dock(TOP)
    r:DockMargin(0, 0, S(8), S(4))
    r:SetTall(tall or S(30))
    r.Paint = nil
    return r
end

function PAGE:Space(n)
    row(self, S(n or 8))
end

function PAGE:Heading(text)
    local h = K.Heading(self.canvas, text)
    h:Dock(TOP)
    h:DockMargin(0, S(6), S(8), S(6))
    return h
end

function PAGE:Note(text)
    local l = vgui.Create("DLabel", self.canvas)
    l:Dock(TOP)
    l:DockMargin(S(2), 0, S(8), S(6))
    l:SetFont(K.Font(13))
    l:SetTextColor(C.textDim)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:SetText(isfunction(text) and text() or text)
    if isfunction(text) then
        local base = baseclass.Get("DLabel")
        function l:Think()
            local t = text()
            if t ~= self:GetText() then self:SetText(t) end
            -- (the base Think grows it to fit the wrapped text)
            if base and base.Think then base.Think(self) end
        end
    end
    return l
end

-- A button that fits its text into its width (cut only if it must).
local function button(parent, text, fn, opts)
    opts = opts or {}
    local b = K.Button(parent, "", fn, { small = true, accent = opts.accent, danger = opts.danger, selected = opts.selected, enabled = opts.enabled, tooltip = opts.tip })
    b.label = function()
        local t = isfunction(text) and text() or text
        return fitText(string.upper(t), K.Font(12, 700), b:GetWide() - S(16))
    end
    b.rhylibText = text
    return b
end
DU.Button = button

local function textW(t)
    surface.SetFont(K.Font(12, 700))
    return (surface.GetTextSize(string.upper(t))) + S(26)
end

-- Buttons one under the other, full width (opts.wrap: side by side,
-- onto more lines when they don't fit, each line sharing its width).
function PAGE:Buttons(list, bopts)
    local wrap = bopts and bopts.wrap
    local holder = row(self, S(26))
    local btns = {}
    for _, d in ipairs(list) do btns[#btns + 1] = button(holder, d[1], d[2], d[3]) end
    local lastW, lastKey
    local function layout()
        local W = holder:GetWide()
        if W <= 0 then return end
        local key = W
        for _, b in ipairs(btns) do
            local t = isfunction(b.rhylibText) and b.rhylibText() or b.rhylibText
            key = key .. "|" .. #t
        end
        if key == lastKey then return end
        lastKey = key
        local gap, bh = S(4), S(26)
        local lines, line, used = {}, {}, 0
        for _, b in ipairs(btns) do
            local t = isfunction(b.rhylibText) and b.rhylibText() or b.rhylibText
            local need = math.min(W, textW(t))
            if #line > 0 and (not wrap or used + gap + need > W) then
                lines[#lines + 1] = line
                line, used = {}, 0
            end
            line[#line + 1] = { b = b, need = need }
            used = used + (#line > 1 and gap or 0) + need
        end
        if #line > 0 then lines[#lines + 1] = line end
        for li, ln in ipairs(lines) do
            local total = 0
            for _, it in ipairs(ln) do total = total + it.need end
            local spare = W - total - gap * (#ln - 1)
            local x = 0
            for i, it in ipairs(ln) do
                local w = it.need + math.floor(spare * it.need / math.max(1, total))
                if i == #ln then w = W - x end
                it.b:SetPos(x, (li - 1) * (bh + gap))
                it.b:SetSize(w, bh)
                x = x + w + gap
            end
        end
        holder:SetTall(#lines * bh + (#lines - 1) * gap)
    end
    function holder:PerformLayout() layout() end
    function holder:Think()
        if self:GetWide() ~= lastW then lastW = self:GetWide() lastKey = nil end
        layout()
    end
    return holder, btns
end

-- A label on the left (40% of the row), the control on the right.
local function labelled(pg, label, tall)
    local r = row(pg, tall or S(30))
    local l = vgui.Create("DPanel", r)
    l:Dock(LEFT)
    l.Paint = function(s, w, h)
        local t = isfunction(label) and label() or label
        draw.SimpleText(fitText(t, K.Font(13), w - S(6)), K.Font(13), 0, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    function r:PerformLayout(w) l:SetWide(math.floor(w * 0.4)) end
    local right = vgui.Create("DPanel", r)
    right:Dock(FILL)
    right.Paint = nil
    return r, right
end

-- ctx (optional): a function whose value is taken when you start typing
-- and handed to set(v, ctx) (e.g. which bone the field was for).
function PAGE:Number(label, step, lo, hi, get, set, ctx)
    local _, right = labelled(self, label)
    local win = self.win
    local function apply(v, c)
        if not v then return end
        set(math.Clamp(v, lo, hi), c)
    end
    local minus = button(right, "-", function() apply(get() - step, ctx and ctx()) end)
    minus:Dock(LEFT)
    minus:SetWide(S(30))
    local plus = button(right, "+", function() apply(get() + step, ctx and ctx()) end)
    plus:Dock(RIGHT)
    plus:SetWide(S(30))
    local e = K.TextEntry(right, "")
    e:Dock(FILL)
    e:DockMargin(S(4), 0, S(4), 0)
    e:SetNumeric(true)
    -- (only a typed change is applied, once, to what it was typed for)
    local base = baseclass.Get("DTextEntry")
    function e:OnGetFocus()
        self.rhylibFrom = self:GetText()
        self.rhylibCtx = ctx and ctx()
        if base and base.OnGetFocus then base.OnGetFocus(self) end
    end
    local function commit(s)
        if s.rhylibFrom ~= nil and s:GetText() ~= s.rhylibFrom then apply(tonumber(s:GetValue()), s.rhylibCtx) end
        s.rhylibFrom = nil
    end
    e.OnEnter = function(s)
        commit(s)
        -- (Enter hands focus back to the window, so W / E / Q work again)
        timer.Simple(0, function()
            local fp = vgui.GetKeyboardFocus()
            if IsValid(fp) and fp.KillFocus then fp:KillFocus() end
            if IsValid(win) then win:RequestFocus() end
        end)
    end
    e.OnLoseFocus = function(s)
        commit(s)
        if base and base.OnLoseFocus then base.OnLoseFocus(s) end
    end
    function e:Think()
        if not self:HasFocus() then
            local t = tostring(math.Round(get(), 3))
            if self:GetText() ~= t then self:SetText(t) end
        end
    end
    -- (held: keeps stepping after a short wait)
    -- (DU.repeating is true while a held button repeats: one undo step per
    -- hold is enough; letting go doesn't step once more)
    for _, pair in ipairs({ { minus, -step }, { plus, step } }) do
        local btn, d = pair[1], pair[2]
        local click = btn.DoClick
        function btn:DoClick()
            if self.rhylibRepeated then self.rhylibRepeated = nil return end
            click(self)
        end
        function btn:Think()
            if self:IsDown() then
                local t = RealTime()
                if not self.rhylibHeld then
                    self.rhylibHeld = t + 0.35
                elseif t >= self.rhylibHeld then
                    self.rhylibHeld = t + 0.04
                    self.rhylibRepeated = true
                    DU.repeating = true
                    apply(get() + d, ctx and ctx())
                end
            else
                if self.rhylibHeld then DU.repeating = nil end
                self.rhylibHeld = nil
            end
        end
    end
end

-- (the label wraps onto more lines in a narrow page; the row grows to fit)
function PAGE:Toggle(label, get, set)
    local r = row(self, S(30))
    local tg = K.Toggle(r, get, set)
    tg:Dock(RIGHT)
    tg:SetTall(S(30))
    local l = vgui.Create("DLabel", r)
    l:Dock(FILL)
    l:DockMargin(0, 0, S(6), 0)
    l:SetFont(K.Font(13))
    l:SetTextColor(C.text)
    l:SetWrap(true)
    l:SetContentAlignment(4)
    l:SetMouseInputEnabled(true)
    l:SetCursor("hand")
    l:SetText(isfunction(label) and label() or label)
    function l:OnMousePressed() tg:DoClick() end
    function r:PerformLayout(w)
        local t = isfunction(label) and label() or label
        if l:GetText() ~= t then l:SetText(t) end
        surface.SetFont(K.Font(13))
        local lw = math.max(10, w - tg:GetWide() - S(6))
        local tw, th = surface.GetTextSize(t)
        local lines = math.max(1, math.ceil(tw / lw))
        local want = math.max(S(30), lines * th + S(8))
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    return r
end

-- A list to pick from, under the mouse (with a filter box for long lists).
local function pickList(options, onPick, owner, opener)
    if IsValid(DU.openList) then DU.openList:Remove() end
    local f = vgui.Create("EditablePanel")
    DU.openList = f
    f.rhylibOpener = opener
    f:SetSize(S(320), S(360))
    local x, y = gui.MousePos()
    f:SetPos(math.Clamp(x - S(20), 0, ScrW() - S(320)), math.Clamp(y, 0, ScrH() - S(360)))
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f:DockPadding(S(6), S(6), S(6), S(6))
    function f:Paint(w, h) K.Plate(0, 0, w, h, { ticks = "all" }) end
    -- (closes on a fresh click outside it, or when its window goes)
    function f:Think()
        if owner ~= nil and not IsValid(owner) then self:Remove() return end
        local down = input.IsMouseDown(MOUSE_LEFT)
        if down and not self.rhylibWasDown and RealTime() > (self.rhylibT or 0) then
            local h = vgui.GetHoveredPanel()
            local inside = IsValid(h) and (h == self or self:IsOurChild(h))
            if not inside and h ~= opener then self:Remove() end
        end
        self.rhylibWasDown = down
    end
    f.rhylibT = RealTime() + 0.1
    local filter
    if #options > 20 then
        filter = K.TextEntry(f, "filter…")
        filter:Dock(TOP)
        filter:DockMargin(0, 0, 0, S(4))
        filter:SetUpdateOnType(true)
        filter:RequestFocus()
    end
    local sc = K.Scroll(f)
    sc:Dock(FILL)
    local function fill()
        sc:Clear()
        local q = filter and string.lower(filter:GetValue() or "") or ""
        for _, o in ipairs(options) do
            if q == "" or string.find(string.lower(o[2]), q, 1, true) then
                local b = button(sc, o[2], function()
                    f:Remove()
                    if owner == nil or IsValid(owner) then onPick(o[1]) end
                end)
                b:Dock(TOP)
                b:DockMargin(0, 0, S(8), S(2))
                b.opts.align = "left"
            end
        end
    end
    if filter then filter.OnValueChange = fill end
    fill()
    return f
end
DU.PickList = pickList

function PAGE:Choice(label, options, get, set)
    local r, right
    if label then r, right = labelled(self, label) else r = row(self, S(30)) right = r end
    local function opts() return isfunction(options) and options() or options end
    local win = self.win
    -- (the label is looked up when the value changes, or every second)
    local lastV, lastT, text = {}, 0, "—"
    local b
    b = button(right, function()
        local cur = get()
        if cur ~= lastV or RealTime() > lastT then
            lastV, lastT, text = cur, RealTime() + 1, "—"
            for _, o in ipairs(opts()) do if o[1] == cur then text = o[2] break end end
        end
        return text .. "  ▾"
    end, function()
        -- (a second click on it closes the open list)
        if IsValid(DU.openList) and DU.openList.rhylibOpener == b then DU.openList:Remove() return end
        pickList(opts(), set, win or false, b)
    end)
    b:Dock(FILL)
    return r
end

-- min / max may be functions (the bar then always spans them).
function PAGE:Slider(label, min, max, decimals, get, set)
    local _, right = labelled(self, label)
    local s
    if isfunction(min) or isfunction(max) then
        local function lo() return isfunction(min) and min() or min end
        local function hi() return math.max(lo() + 0.001, isfunction(max) and max() or max) end
        s = K.Slider(right, 0, 1, 3, function() return math.Clamp((get() - lo()) / (hi() - lo()), 0, 1) end, function(fr)
            local v = lo() + fr * (hi() - lo())
            local m = 10 ^ (decimals or 0)
            set(math.floor(v * m + 0.5) / m)
        end)
        local val = s:GetChildren()[1]
        if IsValid(val) then
            function val:Paint(w, h)
                draw.SimpleText(string.format("%." .. (decimals or 0) .. "f", get()), K.Font(13, 700), w, h * 0.5, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    else
        s = K.Slider(right, min, max, decimals, get, set)
    end
    s:Dock(FILL)
    return s
end

function PAGE:Text(placeholder, get, set)
    local r = row(self, S(30))
    local e = K.TextEntry(r, placeholder)
    e:Dock(FILL)
    e:SetText(get() or "")
    e:SetUpdateOnType(true)
    e.OnValueChange = function(s, v) set(v) end
    function e:Think()
        if not self:HasFocus() and self:GetText() ~= (get() or "") then self:SetText(get() or "") end
    end
    return e
end

-- On / off chips, wrapping.
function PAGE:Chips(options, isOn, toggle)
    local holder = row(self, S(24))
    local made, lastW, lastKey = {}, nil, nil
    local function list() return isfunction(options) and options() or options end
    function holder:Think()
        local opts = list()
        local W = self:GetWide()
        local key = W .. "|" .. #opts
        for _, o in ipairs(opts) do key = key .. "|" .. o[1] end
        if key == lastKey then return end
        lastKey = key
        for _, b in ipairs(made) do b:Remove() end
        made = {}
        local x, y, gap, bh = 0, 0, S(4), S(24)
        for _, o in ipairs(opts) do
            local b = button(self, o[2], function() toggle(o[1]) end, { selected = function() return isOn(o[1]) end })
            local w = math.min(W, textW(o[2]))
            if x > 0 and x + w > W then x, y = 0, y + bh + gap end
            b:SetPos(x, y)
            b:SetSize(w, bh)
            x = x + w + gap
            made[#made + 1] = b
        end
        self:SetTall(y + bh)
    end
    return holder
end

-- A list with columns; click a row to pick it.
function PAGE:List(columns, rows, selected, onPick, tall)
    local holder = row(self, tall or S(120))
    function holder:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local head = vgui.Create("DPanel", holder)
    head:Dock(TOP)
    head:SetTall(S(20))
    function head:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        local x = S(6)
        for _, c in ipairs(columns) do
            local cw = (w - S(8)) * c[2]
            K.Caps(fitText(c[1], K.Font(12, 700), cw - S(6)), x, h * 0.5)
            x = x + cw
        end
    end
    local sc = K.Scroll(holder)
    sc:Dock(FILL)
    local lastKey
    function holder:Think()
        local rs = rows()
        local key = tostring(#rs)
        for _, r in ipairs(rs) do key = key .. "|" .. tostring(r[1]) .. table.concat(r[2], ",") end
        if key == lastKey then return end
        lastKey = key
        sc:Clear()
        for _, r in ipairs(rs) do
            local line = vgui.Create("DButton", sc)
            line:SetText("")
            line:Dock(TOP)
            line:SetTall(S(22))
            function line:Paint(w, h)
                local on = selected() == r[1]
                K.SetCol(on and C.buttonDown or (self:IsHovered() and C.rowHover or C.row))
                surface.DrawRect(0, 0, w, h)
                local x = S(6)
                for i, c in ipairs(columns) do
                    local cw = (w - S(8)) * c[2]
                    draw.SimpleText(fitText(tostring(r[2][i] or ""), K.Font(13), cw - S(6)), K.Font(13), x, h * 0.5, on and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    x = x + cw
                end
                return true
            end
            function line:DoClick() onPick(r[1]) end
        end
    end
    return holder
end

--------------------------------------------------------------------------
-- The camera column (the orbit camera from cl_10_weapon_editors.lua)
--------------------------------------------------------------------------
local function cameraColumn(win, col, cam)
    local orbit = DT.orbit
    orbit.frame = win
    orbit.on = true
    orbit.bone = cam.bone
    orbit.pan = Vector()
    orbit.baseYaw = nil
    orbit.ent = nil
    orbit.dist = cam.dist or orbit.dist
    local pg = setmetatable({ canvas = col, win = win }, { __index = PAGE })
    pg:Heading(cam.head or "Camera")
    pg:Buttons({
        { "Front", function() orbit.on = true orbit.yaw, orbit.pitch = 0, 5 end },
        { "Back", function() orbit.on = true orbit.yaw, orbit.pitch = 180, 5 end },
        { "Left", function() orbit.on = true orbit.yaw, orbit.pitch = 90, 5 end },
        { "Right", function() orbit.on = true orbit.yaw, orbit.pitch = -90, 5 end },
        { "Top", function() orbit.on = true orbit.yaw, orbit.pitch = 0, -85 end },
        { "Below", function() orbit.on = true orbit.yaw, orbit.pitch = 0, 60 end },
    }, { wrap = true })
    local bottom = vgui.Create("DPanel", col)
    bottom:Dock(BOTTOM)
    bottom:SetTall(S(110))
    bottom.Paint = nil
    local bp = setmetatable({ canvas = bottom, win = win }, { __index = PAGE })
    bp:Buttons({ { "Reset view", function()
        orbit.pan = Vector()
        orbit.dist, orbit.yaw, orbit.pitch = cam.dist or 45, 30, 10
        orbit.baseYaw = nil
        orbit.on = true
    end } })
    bp:Slider("Zoom", 15, 250, 0, function() return orbit.dist end, function(v) orbit.dist = v orbit.on = true end)
    bp:Toggle("Orbit camera", function() return orbit.on end, function(v) orbit.on = v end)
    local pad = vgui.Create("DPanel", col)
    pad:Dock(FILL)
    pad:DockMargin(0, S(4), S(8), S(4))
    pad:SetCursor("sizeall")
    function pad:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.Ticks(0, 0, w, h, true, 120)
        draw.SimpleText("LEFT DRAG TURN · RIGHT DRAG PAN", K.Font(12, 700), w * 0.5, h * 0.46, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("yaw %d · pitch %d · %d", orbit.yaw, orbit.pitch, orbit.dist), K.Font(12), w * 0.5, h * 0.54, C.label, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    function pad:OnMousePressed(code)
        if code ~= MOUSE_LEFT and code ~= MOUSE_RIGHT then return end
        self.drag = { gui.MouseX(), gui.MouseY() }
        self.pan = code == MOUSE_RIGHT
        self:MouseCapture(true)
    end
    function pad:OnMouseReleased()
        self.drag = nil
        self:MouseCapture(false)
    end
    function pad:Think()
        if not self.drag then return end
        local x, y = gui.MouseX(), gui.MouseY()
        local dx, dy = x - self.drag[1], y - self.drag[2]
        self.drag = { x, y }
        orbit.on = true
        if self.pan then
            local view = Angle(orbit.pitch, (orbit.baseYaw or 0) + orbit.yaw, 0)
            local k = orbit.dist * 0.004
            orbit.pan = orbit.pan + view:Right() * (dx * k) - view:Up() * (dy * k)
        else
            orbit.yaw = math.NormalizeAngle(orbit.yaw - dx * 0.5)
            orbit.pitch = math.Clamp(orbit.pitch + dy * 0.4, -89, 89)
        end
    end
    function pad:OnMouseWheeled(d)
        orbit.dist = math.Clamp(orbit.dist - d * 5, 15, 250)
        orbit.on = true
        return true
    end
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------
function DU.Window(title, opts)
    opts = opts or {}
    local W = math.min(ScrW() - S(40), S(opts.camera and 680 or 440))
    local H = math.min(ScrH() - S(80), S(opts.tall or 760))
    local win = vgui.Create("EditablePanel")
    win:SetSize(W, H)
    win:SetPos(S(20), math.floor((ScrH() - H) * 0.5))
    win:MakePopup()
    win:DockPadding(S(8), S(38), S(8), S(8))
    win.tabs, win.pages, win.order = {}, {}, {}
    DU.windows = DU.windows or {}
    DU.windows[win] = true
    DU.count = (DU.count or 0) + 1
    win.rhylibOrder = DU.count
    function win:OnRemove() DU.windows[self] = nil end
    function win:Paint(w, h)
        K.Plate(0, 0, w, h, { title = title, sub = opts.sub, ticks = "all" })
    end
    -- (drag by the title bar)
    function win:OnMousePressed(code)
        if code == MOUSE_LEFT and select(2, self:CursorPos()) < S(32) then
            self.drag = { gui.MouseX() - self.x, gui.MouseY() - self.y }
            self:MouseCapture(true)
        end
    end
    function win:OnMouseReleased() self.drag = nil self:MouseCapture(false) end
    local keysDown = {}
    function win:Think()
        -- (a kit prompt open over it: Esc closes that, not the window)
        local UI = Rhylib.UI
        for p in pairs(UI.prompts or {}) do if IsValid(p) then DU.promptFrame = FrameNumber() break end end
        -- (W / E / Q... reach onKey wherever the focus is, except while typing)
        local fp = vgui.GetKeyboardFocus()
        local typing = IsValid(fp) and fp:GetClassName() == "TextEntry"
        for _, k in ipairs({ KEY_W, KEY_E, KEY_Q, KEY_Z }) do
            local d = input.IsKeyDown(k)
            if d and not keysDown[k] and not typing and self.onKey and (not IsValid(fp) or fp == self or self:IsOurChild(fp)) then self.onKey(k) end
            keysDown[k] = d
        end
        if self.drag then
            self:SetPos(math.Clamp(gui.MouseX() - self.drag[1], 0, ScrW() - self:GetWide()), math.Clamp(gui.MouseY() - self.drag[2], 0, ScrH() - S(40)))
        end
    end
    function win:OnKeyCodePressed(code)
        if code == KEY_ESCAPE then self:Remove() end
    end
    local close = button(win, "✕", function() win:Remove() end, { danger = true })
    close:SetSize(S(30), S(24))
    function win:PerformLayout(w) close:SetPos(w - S(36), S(4)) end

    local tabCol = vgui.Create("DPanel", win)
    tabCol:Dock(LEFT)
    tabCol:SetWide(S(104))
    tabCol:DockMargin(0, 0, S(8), 0)
    tabCol.Paint = nil
    if opts.camera then
        local camCol = vgui.Create("DPanel", win)
        camCol:Dock(RIGHT)
        camCol:SetWide(S(230))
        camCol:DockMargin(S(8), 0, 0, 0)
        camCol.Paint = nil
        cameraColumn(win, camCol, opts.camera)
    end
    local body = vgui.Create("DPanel", win)
    body:Dock(FILL)
    function body:Paint(w, h)
        K.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    body:DockPadding(S(8), S(6), S(2), S(6))

    function win:AddTab(name, build)
        local b = button(tabCol, name, function() self:Show(name) end, { selected = function() return self.current == name end })
        b:Dock(TOP)
        b:SetTall(S(30))
        b:DockMargin(0, 0, 0, S(4))
        b.opts.align = "left"
        self.tabs[name] = { build = build, button = b }
        self.order[#self.order + 1] = name
        return b
    end
    function win:Show(name)
        local t = self.tabs[name]
        if not t then return end
        for n, pnl in pairs(self.pages) do pnl:SetVisible(n == name) end
        if not self.pages[name] then
            local sc = K.Scroll(body)
            sc:Dock(FILL)
            self.pages[name] = sc
            local pg = setmetatable({ canvas = sc, win = self }, { __index = PAGE })
            t.build(pg)
        end
        self.current = name
        if self.onShow then self.onShow(name) end
    end
    return win
end

DU.Page = PAGE

-- Esc: an open list first, then the newest editor window (after any kit
-- prompt over it has had its turn). Through rhylib_menus' Esc handling
-- (UI.CloseAll), or on its own without Rhy's Menus.
local function closeTop()
    if IsValid(DU.openList) then DU.openList:Remove() return true end
    if DU.promptFrame and FrameNumber() - DU.promptFrame <= 2 then return false end
    local newest
    for w in pairs(DU.windows or {}) do
        if IsValid(w) and (not newest or w.rhylibOrder > newest.rhylibOrder) then newest = w end
    end
    if newest then newest:Remove() return true end
    return false
end
if Rhylib.UI and Rhylib.UI.RegisterCloser then Rhylib.UI.RegisterCloser("devtools.ui", closeTop) end
Rhylib.Hook.Add("OnPauseMenuShow", "devtools.ui", function()
    if Rhylib.Menus then return end
    if closeTop() then return false end
end)
