--[[
    Character creator: shown on first join (roster.need), can't be closed
    until a character is saved. A large centred window over a dimmed
    screen: on the left the clone preview (helmet off, cl_15_look.lua) with
    the name it will get underneath in big letters (CC-1234 Nickname); on
    the right the clone number (with a CC- prefix box) and nickname, the
    looks (hair, hair colour, facial hair, skin), a status line (what's
    wrong, or "Looks good") and the Enlist button.
    Client only. Needs the UI kit (Rhylib.UI.Kit, rhylib_core); without it no
    window opens. Sends roster.create (number, nickname, looks via
    R.WriteLook); the server answers roster.created (ok, message).
    Registers a closer so Esc can't close it.

    Also adds R.Draw, small drawing helpers the roster windows share (this
    is the first client file): Diamond, Dashed, Chip, Glow, Band, Banner,
    Menu (K.Menu with styled spacers and sub menus) and Confirm (a yes / no
    box in the house style).
]]

local R = Rhylib.Roster
local panel

local function K() return Rhylib.UI and Rhylib.UI.Kit end

-- Theme tokens (dark defaults).
local COL_BACKDROP = Rhylib.UI.Col("roster.backdrop", 4, 5, 5, 215)
local COL_STAGE = Rhylib.UI.Col("roster.stage", 18, 21, 20, 255)

--------------------------------------------------------------------------
-- R.Draw: shared drawing helpers (call them in a Paint unless noted)
--------------------------------------------------------------------------

R.Draw = R.Draw or {}
local D = R.Draw
local GRAD_L, GRAD_R, GRAD_U = Material("vgui/gradient-l"), Material("vgui/gradient-r"), Material("vgui/gradient-u")

-- D.Diamond(cx, cy, r, col, a): a small filled diamond.
local DIA = { {}, {}, {}, {} }
function D.Diamond(cx, cy, r, col, a)
    DIA[1].x, DIA[1].y = cx, cy - r
    DIA[2].x, DIA[2].y = cx + r, cy
    DIA[3].x, DIA[3].y = cx, cy + r
    DIA[4].x, DIA[4].y = cx - r, cy
    draw.NoTexture()
    K().SetCol(col, a)
    surface.DrawPoly(DIA)
end

-- D.Dashed(x, y, w, h, col, a): a dashed outline (empty slots).
function D.Dashed(x, y, w, h, col, a)
    local k = K()
    k.SetCol(col, a)
    local dash, gap = k.S(6), k.S(4)
    for i = x, x + w - 1, dash + gap do
        local l = math.min(dash, x + w - i)
        surface.DrawRect(i, y, l, 1)
        surface.DrawRect(i, y + h - 1, l, 1)
    end
    for j = y, y + h - 1, dash + gap do
        local l = math.min(dash, y + h - j)
        surface.DrawRect(x, j, 1, l)
        surface.DrawRect(x + w - 1, j, 1, l)
    end
end

-- D.Chip(text, x, cy, col, align): small caps text on a pill tinted in
-- col, vertically centred on cy. Pass the text in capitals. align
-- TEXT_ALIGN_RIGHT puts its right edge at x. Returns the chip's width.
function D.Chip(text, x, cy, col, align)
    local k = K()
    local f = k.Font(11, 700)
    surface.SetFont(f)
    local tw = surface.GetTextSize(text)
    local w, h = tw + k.S(14), k.S(20)
    if align == TEXT_ALIGN_RIGHT then x = x - w end
    local y = math.floor(cy - h * 0.5)
    k.SetCol(col, 38)
    surface.DrawRect(x, y, w, h)
    k.SetCol(col, 130)
    surface.DrawOutlinedRect(x, y, w, h)
    draw.SimpleText(text, f, x + k.S(7), y + h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    return w
end

-- D.Glow(x, y, w, h, col, a): a soft glow in the middle of a box, fading
-- to the sides and to the top (into the stage colour, roster.stage).
D.STAGE = COL_STAGE
function D.Glow(x, y, w, h, col, a)
    local k = K()
    k.SetCol(col, a)
    surface.SetMaterial(GRAD_R)
    surface.DrawTexturedRect(x, y, math.ceil(w * 0.5), h)
    surface.SetMaterial(GRAD_L)
    surface.DrawTexturedRect(x + math.floor(w * 0.5), y, math.ceil(w * 0.5), h)
    k.SetCol(COL_STAGE, 255)
    surface.SetMaterial(GRAD_U)
    surface.DrawTexturedRect(x, y, w, math.floor(h * 0.45))
end

-- D.Band(parent, title, col, getRight): a category band panel (36 px):
-- a tint from the left, a thick left edge and a diamond in col (a Color,
-- or nil for the accent), the caps title and getRight() dim on the right.
-- Returns the panel (dock it TOP). Not for a Paint.
function D.Band(parent, title, col, getRight)
    local k = K()
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    p:SetTall(s(36))
    local caps = string.upper(title or "")
    function p:Paint(w, h)
        local c = col or k.C.accent
        k.SetCol(k.C.header)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(c, 46)
        surface.SetMaterial(GRAD_L)
        surface.DrawTexturedRect(0, 0, math.floor(w * 0.7), h)
        k.SetCol(c)
        surface.DrawRect(0, 0, s(4), h)
        D.Diamond(s(20), h * 0.5, s(6), c)
        local right = getRight and getRight() or ""
        draw.SimpleText(right, k.Font(12), w - s(12), h * 0.5, k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        surface.SetFont(k.Font(12))
        local rw = surface.GetTextSize(right)
        draw.SimpleText(k.Fit(caps, k.Font(15, 700), w - s(60) - rw), k.Font(15, 700), s(34), h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

-- D.Banner(parent, text, kind): a message strip (good / bad / warn / dim):
-- tinted, with a coloured left edge and wrapping text. Returns the panel
-- (dock it TOP). Not for a Paint.
local function kindCol(kind)
    local C = K().C
    if kind == "good" then return C.good elseif kind == "bad" then return C.bad
    elseif kind == "warn" then return C.warn end
    return C.textDim
end
D.KindCol = kindCol
function D.Banner(parent, text, kind)
    local k = K()
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    p:DockPadding(s(16), s(8), s(12), s(8))
    function p:Paint(w, h)
        local c = kindCol(kind)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(c, 26)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(c)
        surface.DrawRect(0, 0, s(3), h)
        k.SetCol(k.C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local l = k.Label(p, text, 13, 600, kindCol(kind))
    l:Dock(TOP)
    function p:PerformLayout()
        local want = l:GetTall() + s(16)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    p:SetTall(s(34))
    return p
end

-- D.Menu(): K.Menu with its spacers and sub menus in the house style too.
-- AddSubMenu returns a sub menu whose AddOption is styled the same way.
local function styleMenu(m)
    local k = K()
    local C = k.C
    function m:Paint(w, h)
        k.SetCol(C.bg)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    local add, spacer, sub = m.AddOption, m.AddSpacer, m.AddSubMenu
    function m:AddOption(text, fn)
        local o = add(self, text, fn)
        k.ThemedText(o, C.text, 13)
        function o:Paint(w, h)
            if self:IsHovered() and self:IsEnabled() then
                k.SetCol(C.buttonHover)
                surface.DrawRect(0, 0, w, h)
            end
        end
        -- (greyed when switched off)
        local setEnabled = o.SetEnabled
        function o:SetEnabled(on)
            setEnabled(self, on)
            self.rhylibTextCol = on and C.text or C.textDim
            self:SetTextColor(self.rhylibTextCol)
        end
        return o
    end
    function m:AddSpacer()
        local p = spacer(self)
        if IsValid(p) then
            function p:Paint(w, h)
                k.SetCol(C.edgeLight)
                surface.DrawRect(k.S(8), math.floor(h * 0.5), w - k.S(16), 1)
            end
        end
        return p
    end
    function m:AddSubMenu(text, fn)
        local sm, opt = sub(self, text, fn)
        if sm then styleMenu(sm) end
        if IsValid(opt) then
            k.ThemedText(opt, C.text, 13)
            function opt:Paint(w, h)
                if self:IsHovered() or (IsValid(self.SubMenu) and self.SubMenu:IsVisible()) then
                    k.SetCol(C.buttonHover)
                    surface.DrawRect(0, 0, w, h)
                end
            end
        end
        if IsValid(opt) and IsValid(opt.SubMenuArrow) then
            function opt.SubMenuArrow:Paint(w, h) k.Arrow(w * 0.5, h * 0.5, k.S(8), "right", C.textDim) end
        end
        return sm, opt
    end
    return m
end
function D.Menu()
    return styleMenu(DermaMenu())
end

-- D.Confirm(title, text, okLabel, onOk, danger): a yes / no box (OK runs
-- onOk; Cancel or Esc just closes it). Kept in UI.prompts.
function D.Confirm(title, text, okLabel, onOk, danger)
    local k = K()
    if not k then return end
    local UI = Rhylib.UI
    local s = k.S
    local f = vgui.Create("EditablePanel")
    UI.prompts[f] = true
    f.OnRemove = function(self) UI.prompts[self] = nil end
    f:SetSize(s(480), s(196))
    f:Center()
    f:MakePopup()
    f:DoModal()
    f:DockPadding(s(18), s(30) + s(16), s(18), s(16))
    function f:Paint(w, h)
        k.Plate(0, 0, w, h, { title = title, ticks = "all", rule = danger and k.C.bad or nil })
    end
    local l = k.Label(f, text, 14, 400, k.C.text)
    l:Dock(TOP)
    local row = vgui.Create("DPanel", f)
    row:Dock(BOTTOM)
    row:SetTall(s(34))
    row.Paint = nil
    local ok = k.Button(row, okLabel or "OK", function() f:Remove() onOk() end, { accent = not danger, danger = danger })
    ok:Dock(RIGHT)
    ok:SetWide(s(130))
    local cancel = k.Button(row, "Cancel", function() f:Remove() end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(110))
    cancel:DockMargin(0, 0, s(8), 0)
    return f
end

--------------------------------------------------------------------------
-- The creator
--------------------------------------------------------------------------

-- A field: caps label and a dim hint over a text box. Returns the box.
local function field(parent, label, hint, placeholder, prefix)
    local k = K()
    local s = k.S
    local C = k.C
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(s(70))
    p:DockMargin(0, 0, 0, s(10))
    p:DockPadding(0, s(24), 0, 0)
    function p:Paint(w, h)
        k.Caps(label, 0, s(10))
        draw.SimpleText(hint, k.Font(12), w, s(10), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    if prefix then
        local pre = vgui.Create("DPanel", p)
        pre:Dock(LEFT)
        pre:SetWide(s(62))
        function pre:Paint(w, h)
            k.SetCol(C.header)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(prefix, k.Font(20, 700), w * 0.5, h * 0.5, C.label, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    local e = k.TextEntry(p, placeholder)
    e:Dock(FILL)
    k.ThemedText(e, C.text, 20, 600)
    return e
end

local function open()
    local k = K()
    if not k then return end
    if IsValid(panel) then panel:Remove() end
    local s = k.S
    local C = k.C
    -- A full-screen backdrop (dims the game) holding the window.
    panel = vgui.Create("EditablePanel")
    panel:SetSize(ScrW(), ScrH())
    panel:SetPos(0, 0)
    panel:MakePopup()
    panel.err = ""
    function panel:Paint(w, h)
        k.SetCol(COL_BACKDROP)
        surface.DrawRect(0, 0, w, h)
    end
    local frame = vgui.Create("EditablePanel", panel)
    frame:SetSize(math.min(ScrW() - s(60), s(1200)), math.min(ScrH() - s(60), s(740)))
    frame:Center()
    local headH = s(40)
    frame:DockPadding(s(20), headH + s(20), s(20), s(20))
    function frame:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "New recruit", sub = "Create your clone", ticks = "all", header = headH })
    end

    local look = { hair = "hair_reg", fhair = "", hcol = 0, skin = 0 }

    -- Left: the preview with the name under it.
    local stage = vgui.Create("DPanel", frame)
    stage:Dock(LEFT)
    stage:SetWide(math.floor(frame:GetWide() * 0.42))
    function stage:Paint(w, h)
        k.SetCol(COL_STAGE)
        surface.DrawRect(0, 0, w, h)
        D.Glow(0, 0, w, h, C.accent, 34)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        k.Ticks(0, 0, w, h, true)
        k.Caps("Preview", s(14), s(18))
        draw.SimpleText("Helmet off", k.Font(12), w - s(14), s(18), C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local num, nick
    local function state()
        local n = num:GetText() or ""
        local nk = R.CleanNick(nick:GetText())
        local okN, whyN = R.ValidNumber(n)
        local okK, whyK = R.ValidNick(nk)
        return n, nk, okN and okK, (not okN and n ~= "" and whyN) or (not okK and nk ~= "" and whyK) or nil
    end

    local namePlate = vgui.Create("DPanel", stage)
    namePlate:Dock(BOTTOM)
    namePlate:SetTall(s(118))
    function namePlate:Paint(w, h)
        local n, nk, ok = state()
        k.SetCol(C.header)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.accent, 180)
        surface.DrawRect(0, 0, w, 1)
        k.Caps("Your name", s(18), s(22))
        local name = "CC-" .. (n ~= "" and n or "????") .. " " .. (nk ~= "" and nk or "Nickname")
        local f = k.Font(34, 800)
        draw.SimpleText(k.Fit(name, f, w - s(36)), f, s(18), s(58), ok and C.text or C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Cadet  ·  CT after basic training, a rank in a battalion", k.Font(12), s(18), s(94), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local lookPrev = R.LookPreview and R.LookPreview(stage, function() return look end)
    if IsValid(lookPrev) then
        lookPrev:Dock(FILL)
        lookPrev:DockMargin(1, s(34), 1, 0)
    end

    -- Right: the fields, looks, status and Enlist.
    local side = vgui.Create("DPanel", frame)
    side:Dock(FILL)
    side:DockMargin(s(22), 0, 0, 0)
    side.Paint = nil

    local intro = k.Label(side, "Pick your clone number and a nickname. You start as a cadet; basic training makes you a clone trooper, and a battalion gives you a rank.", 14, 400, C.textDim)
    intro:Dock(TOP)
    intro:DockMargin(0, 0, 0, s(12))

    local h1 = k.Heading(side, "Identity")
    h1:Dock(TOP)
    h1:DockMargin(0, 0, 0, s(10))
    num = field(side, "Clone number", "4 digits, e.g. 0411 or 2187", "1234", "CC-")
    num:SetNumeric(true)
    nick = field(side, "Nickname", "What your squad calls you", "Nickname")

    local h2 = k.Heading(side, "Looks")
    h2:Dock(TOP)
    h2:DockMargin(0, s(4), 0, s(8))
    if R.LookControls then R.LookControls(side, look) end

    -- Bottom: Enlist, and the status over it.
    local save = vgui.Create("DButton", side)
    save:SetText("")
    save:Dock(BOTTOM)
    save:SetTall(s(52))
    function save:Paint(w, h)
        local _, _, ok = state()
        if ok then
            k.SetCol(C.accent, self:IsDown() and 200 or (self:IsHovered() and 255 or 225))
            surface.DrawRect(0, 0, w, h)
        else
            k.SetCol(C.button)
            surface.DrawRect(0, 0, w, h)
        end
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        k.Ticks(0, 0, w, h, true, ok and 120 or 255)
        draw.SimpleText("ENLIST", k.Font(20, 800), w * 0.5, h * 0.5, ok and C.bg or C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
    function save:DoClick()
        local n, nk, ok = state()
        if not ok then return end
        surface.PlaySound("ui/buttonclick.wav")
        Rhylib.Net.Start("roster.create")
        net.WriteString(n)
        net.WriteString(nk)
        if R.WriteLook then
            R.WriteLook(look)
        else
            net.WriteString(look.hair)
            net.WriteString(look.fhair)
            net.WriteUInt(0, 4)
            net.WriteUInt(0, 4)
        end
        net.SendToServer()
    end

    local status = vgui.Create("DPanel", side)
    status:Dock(BOTTOM)
    status:SetTall(s(38))
    status:DockMargin(0, s(8), 0, s(8))
    function status:Paint(w, h)
        local n, nk, ok, why = state()
        local msg, col
        if panel.err ~= "" then msg, col = panel.err, C.bad
        elseif why then msg, col = why, C.bad
        elseif ok then msg, col = "Looks good", C.good
        else msg, col = (n == "" and nk == "") and "Fill in your clone number and a nickname" or "Almost there", C.textDim end
        k.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(col, 22)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(col)
        surface.DrawRect(0, 0, s(3), h)
        draw.RoundedBox(s(4), s(14), h * 0.5 - s(4), s(8), s(8), col)
        draw.SimpleText(k.Fit(msg, k.Font(14, 600), w - s(40)), k.Font(14, 600), s(30), h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Keep the number to 4 digits.
    function num:OnChange()
        local t = string.gsub(self:GetText() or "", "%D", "")
        if #t > 4 then t = string.sub(t, 1, 4) end
        if t ~= self:GetText() then
            self:SetText(t)
            self:SetCaretPos(#t)
        end
        panel.err = ""
    end
    function nick:OnChange() panel.err = "" end
    function nick:OnEnter() save:DoClick() end
    num:RequestFocus()
end

-- Esc doesn't close it (it can't be skipped).
local function registerCloser()
    local UI = Rhylib.UI
    local reg = (UI and UI.RegisterCloser) or (Rhylib.Menus and Rhylib.Menus.RegisterCloser)
    if reg then
        reg("roster.creator", function() return IsValid(panel) end)
    end
end
registerCloser()

-- Once loaded: register, and ask the server whether we still need a character
-- (and keep asking now and then while we have none and no window is open).
Rhylib.Hook.Add("InitPostEntity", "roster.creator", function()
    registerCloser()
    timer.Create("Rhylib.Roster.Hello", 6, 0, function()
        local ply = LocalPlayer()
        if not IsValid(ply) or ply:GetNW2Bool("rhylib_char", false) then return end
        if IsValid(panel) then return end
        Rhylib.Net.Start("roster.hello")
        net.SendToServer()
    end)
end)

Rhylib.Net.Receive("roster.need", function()
    -- Wait for the UI kit if the game is still loading (the hello timer retries).
    timer.Simple(0.5, function()
        if not IsValid(panel) then open() end
    end)
end)

Rhylib.Net.Receive("roster.created", function()
    local ok, msg = net.ReadBool(), net.ReadString()
    if not IsValid(panel) then return end
    if ok then
        panel:Remove()
        -- (a new character: the getting-started card, cl_15_welcome.lua)
        timer.Simple(0.6, function() if R.ShowWelcome then R.ShowWelcome() end end)
    else
        panel.err = msg
    end
end)
