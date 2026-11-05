--[[
    Battalion computer / medical holotable window (client): the window,
    shared helpers and the tab registry. Opens on dp.term (E on the
    computer); closes when you walk out of useRange. Needs the UI kit
    (Rhylib.UI.Kit). Every request starts with the computer entity
    (T.Send); the server checks range and rights again.

    Layout: a full-screen terminal in the datapad's teal-on-black look
    (the medical holotable uses a red accent).
      header   battalion badge (its colour, D.BnColor) with the prefix,
               the battalion name, a caps line (computer / holotable,
               members online); on the right "N notes on your datapad"
               + Upload notes, Set battalion (admins, no battalion yet),
               close.
      tab bar  the registered tabs, teal underline on the shown one,
               small count badges (def.badge).
      body     the shown tab. Each tab is its own file and keeps its own state:
      cl_21_term_logs.lua      Logs / Records: search, reader, moderation
      cl_22_term_board.lua     Board: post cards with filters, battalion
                               card, next sessions, open orders
      cl_23_term_stats.lua     Stats: totals and members for a period
      cl_24_term_unit.lua      Orders, LOA, Applications, Apply; the
                               "you got accepted" popup (dp.uprompt)
      cl_25_term_people.lua    Personnel files
      cl_26_term_missions.lua  Missions: current one and the archive
      Bans                     (here) moderators: who can't upload
    The medical holotable has Records (and Bans) only.

    D.Term (T) is the shared table:
      T.term (last dp.term), T.panel, T.tab (shown tab id), T.unit and
      T.people (unit data and member list, shared by several tabs),
      T.Build(), T.Send(name, fn), T.K(), T.when(t), T.Countdown, T.ParseDate,
      T.OPAQUE, T.C (the window colours), and the widgets: T.Btn, T.Chips,
      T.Card, T.FitTall, T.Heading, T.Title, T.ReaderTitle, T.ListRow,
      T.Label, T.Columns, T.FootRow, T.FootButton, T.Empty. T.DrawNotices:
      while the window is open, Rhylib.Notify lines (hook Rhylib.NotifyShow,
      id "datapad.term.notices") also show in it, top right, 6 s each.
    D.TermAddTab(id, { name = string or fn(term), order, has = fn(term),
      build = fn(body), badge = fn(term) -> number or nil, accent = fn(term),
      reset = fn(), onTerm = fn(term) })
      adds a tab: has decides whether it shows; badge is the small count
      next to its name (amber when accent says so); reset runs when a
      different computer is opened; onTerm after every dp.term.
    Each tab asks for its data the first time it is shown; replies for
    another computer are ignored.
]]

local D = Rhylib.Datapad

D.Term = D.Term or {}
local T = D.Term
T.tabs = T.tabs or {}
T.tab = T.tab or "logs"

function T.K() return Rhylib.UI and Rhylib.UI.Kit end
local K = T.K
T.OPAQUE = Color(5, 12, 13, 255)
function T.when(t) return t and t > 0 and os.date("%d %b %Y %H:%M", t) or "" end

--------------------------------------------------------------------------
-- Colours (teal terminal; T.SetMedical swaps the accent to red)
--------------------------------------------------------------------------

local TEAL, TEAL_EDGE, TEAL_ON = Color(127, 216, 230), Color(31, 90, 98), Color(16, 51, 58)
local RED, RED_EDGE, RED_ON = Color(226, 75, 74), Color(90, 42, 42), Color(58, 21, 22)
T.C = T.C or {}
local C = T.C
C.ground = Color(5, 12, 13)
C.header = Color(10, 26, 29)
C.bar = Color(7, 19, 21)
C.card = Color(11, 29, 32)
C.hover = Color(14, 38, 42)
C.edge = Color(18, 53, 58)
C.text = Color(228, 227, 220)
C.body = Color(195, 217, 220)
C.dim = Color(159, 199, 205)
C.caps = Color(95, 154, 163)
C.dark = Color(7, 18, 20)
C.good = Color(151, 196, 89)
C.warn = Color(239, 159, 39)
C.bad = Color(226, 75, 74)
C.dangerEdge = Color(90, 42, 42)
C.dangerText = Color(240, 149, 149)
C.dangerFill = Color(42, 18, 18)
C.shine = Color(255, 255, 255, 30)
C.accent, C.accentEdge, C.accentOn = C.accent or TEAL, C.accentEdge or TEAL_EDGE, C.accentOn or TEAL_ON

-- T.SetMedical(med): red accent for the holotable, teal otherwise.
function T.SetMedical(med)
    C.accent, C.accentEdge, C.accentOn = med and RED or TEAL, med and RED_EDGE or TEAL_EDGE, med and RED_ON or TEAL_ON
end

-- Kit widgets inside the window (text boxes, scroll bars, menus' parents)
-- draw with these while the window paints; PaintOver puts the kit's back.
local SKIN = {
    bg = C.card, header = C.header, row = C.bar, rowAlt = Color(9, 24, 27), rowHover = TEAL_ON,
    edgeDark = C.edge, edgeLight = Color(127, 216, 230, 22), tick = C.caps, label = C.caps,
    button = C.card, buttonHover = TEAL_ON, buttonDown = Color(20, 66, 74), textDim = C.dim,
}
local saved, swapped = {}, false
local function skinOn()
    if swapped then return end   -- (twice in a row would save the teal ones)
    swapped = true
    local kc = K().C
    for key, v in pairs(SKIN) do
        saved[key] = kc[key]
        kc[key] = v
    end
    saved.accent = kc.accent
    kc.accent = C.accent
end
local function skinOff()
    if not swapped then return end
    swapped = false
    local kc = K().C
    for key, v in pairs(saved) do
        kc[key] = v
        saved[key] = nil
    end
end

-- D.TermAddTab(id, def): register (or replace) a computer window tab.
function D.TermAddTab(id, def)
    def.id = id
    T.tabs[id] = def
end

-- T.Send(name, fn): a computer message: the computer entity first, then fn() writes the rest.
function T.Send(name, fn)
    Rhylib.Net.Start(name)
    net.WriteEntity(T.term.ent)
    if fn then fn() end
    net.SendToServer()
end
local send = T.Send

function T.Countdown(at)
    local d = at - os.time()
    if d <= 0 then return "now" end
    if d < 3600 then return "in " .. math.ceil(d / 60) .. " min" end
    if d < 86400 then return string.format("in %d h %d min", math.floor(d / 3600), math.floor(d % 3600 / 60)) end
    return string.format("in %d d %d h", math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

-- "YYYY-MM-DD" -> os.time (start or end of that day), or nil.
function T.ParseDate(txt, endOfDay)
    local y, mo, d = string.match(txt or "", "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = 0 })
end

--------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------

local function setCol(c) surface.SetDrawColor(c.r, c.g, c.b, c.a or 255) end
T.SetCol = setCol

-- T.Btn(parent, text, fn, opts): a terminal button, sentence case. 40 px tall
-- (32 small); width fits the text unless you set it. opts: primary (or
-- accent) = filled accent with dark text, danger = red outline, selected =
-- fn -> bool (drawn picked), enabled = bool or fn, small, quiet (dim text),
-- align = "left", tooltip.
function T.Btn(parent, text, fn, opts)
    opts = opts or {}
    local k = K()
    local s = k.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.label = text
    b.opts = opts
    b.font = k.Font(opts.small and 12 or 13, 700)
    b:SetTall(opts.small and s(32) or s(40))
    if opts.tooltip then b:SetTooltip(opts.tooltip) end
    if isstring(text) then
        surface.SetFont(b.font)
        b:SetWide(surface.GetTextSize(text) + s(opts.small and 24 or 32))
    end
    function b:IsOn()
        local en = self.opts.enabled
        if en == nil then return true end
        if isfunction(en) then return en() and true or false end
        return en and true or false
    end
    function b:Paint(w, h)
        local o = self.opts
        local on = self:IsOn()
        local hov = on and self:IsHovered()
        local tc
        if o.primary or o.accent then
            setCol(on and C.accent or C.accentEdge)
            surface.DrawRect(0, 0, w, h)
            if hov then
                setCol(C.shine)
                surface.DrawRect(0, 0, w, h)
            end
            tc = on and C.dark or C.dim
        elseif o.danger then
            if hov then
                setCol(C.dangerFill)
                surface.DrawRect(0, 0, w, h)
            end
            setCol(C.dangerEdge)
            surface.DrawOutlinedRect(0, 0, w, h)
            tc = on and C.dangerText or C.caps
        else
            local sel = o.selected and o.selected()
            if sel then
                setCol(C.accentOn)
                surface.DrawRect(0, 0, w, h)
            elseif hov then
                setCol(C.hover)
                surface.DrawRect(0, 0, w, h)
            end
            setCol(sel and C.accent or (on and C.accentEdge or C.edge))
            surface.DrawOutlinedRect(0, 0, w, h)
            tc = not on and C.caps or (sel and C.text or (o.quiet and C.dim or C.accent))
        end
        local label = isfunction(self.label) and self.label() or self.label
        if o.align == "left" then
            draw.SimpleText(label, self.font, s(12), h * 0.5, tc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(label, self.font, w * 0.5, h * 0.5, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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

-- T.Chips(parent, options, get, set): filter chips left to right
-- ({ { value, label }, ... }); the picked one is filled. Returns a panel
-- already sized to its chips (dock it LEFT).
function T.Chips(parent, options, get, set)
    local k = K()
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    p.Paint = nil
    local font, fontOn = k.Font(12, 500), k.Font(12, 700)
    local total = 0
    for i, o in ipairs(options) do
        local b = vgui.Create("DButton", p)
        b:SetText("")
        b:Dock(LEFT)
        b:DockMargin(0, 0, s(6), 0)
        surface.SetFont(fontOn)
        local bw = surface.GetTextSize(o[2]) + s(24)
        b:SetWide(bw)
        total = total + bw + s(6)
        function b:Paint(w, h)
            local on = get() == o[1]
            if on then
                setCol(C.accent)
                surface.DrawRect(0, 0, w, h)
            else
                if self:IsHovered() then
                    setCol(C.hover)
                    surface.DrawRect(0, 0, w, h)
                end
                setCol(C.accentEdge)
                surface.DrawOutlinedRect(0, 0, w, h)
            end
            draw.SimpleText(o[2], on and fontOn or font, w * 0.5, h * 0.5, on and C.dark or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return true
        end
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            set(o[1])
        end
    end
    p:SetWide(total)
    p:SetTall(s(32))
    return p
end

-- T.FitTall(panel, padBottom): the panel's height follows its TOP-docked children.
function T.FitTall(p, padB)
    function p:PerformLayout(w, h)
        local maxB = 0
        for _, c in ipairs(self:GetChildren()) do
            if c:IsVisible() then
                local _, y = c:GetPos()
                local _, _, _, mb = c:GetDockMargin()
                local b = y + c:GetTall() + mb
                if b > maxB then maxB = b end
            end
        end
        local want = maxB + (padB or 0)
        if math.abs(want - h) > 1 then self:SetTall(want) end
    end
end

-- T.Card(parent, opts): a card (#0b1d20, edge outline). opts: top = Color
-- or fn -> Color (3 px top edge), bar = Color or fn (3 px left bar),
-- hi = fn -> bool (brighter edge), pad (inner padding, default 16 / 12),
-- fit = true (height follows the content; dock TOP).
function T.Card(parent, opts)
    opts = opts or {}
    local s = K().S
    local p = vgui.Create("DPanel", parent)
    local px, py = opts.padX or s(16), opts.padY or s(12)
    p:DockPadding(px, py + (opts.top and s(3) or 0), px, py)
    function p:Paint(w, h)
        setCol(C.card)
        surface.DrawRect(0, 0, w, h)
        setCol((opts.hi and opts.hi()) and C.accentEdge or C.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        local top = opts.top
        if isfunction(top) then top = top() end
        if top then
            setCol(top)
            surface.DrawRect(0, 0, w, s(3))
        end
        local bar = opts.bar
        if isfunction(bar) then bar = bar() end
        if bar then
            setCol(bar)
            surface.DrawRect(0, 0, s(3), h)
        end
    end
    if opts.fit then T.FitTall(p, py) end
    return p
end

-- T.Heading(parent, text, col): a small caps section label with a faint
-- rule under it (30 px; dock TOP). col colours a square before it.
function T.Heading(parent, text, col)
    local k = K()
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    p:SetTall(s(30))
    local up = string.upper(text)
    local font = k.Font(12, 700)
    function p:Paint(w, h)
        local x = 0
        if col then
            setCol(col)
            surface.DrawRect(0, h * 0.5 - s(4), s(8), s(8))
            x = s(16)
        end
        draw.SimpleText(up, font, x, h * 0.5, C.caps, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        setCol(C.edge)
        surface.DrawRect(0, h - 1, w, 1)
    end
    return p
end

-- T.Title(parent, text): a big bold caps title ("BOARD"); 40 px, dock it.
function T.Title(parent, text)
    local k = K()
    local p = vgui.Create("DPanel", parent)
    p:SetTall(k.S(40))
    local up = string.upper(text)
    local font = k.Font(22, 800)
    surface.SetFont(font)
    p:SetWide(surface.GetTextSize(up) + k.S(16))
    function p:Paint(w, h)
        draw.SimpleText(up, font, 0, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

-- T.ReaderTitle(parent, text): a reader's big title (wraps; docked TOP).
function T.ReaderTitle(parent, text)
    local l = K().Label(parent, text, 20, 700, C.text)
    l:Dock(TOP)
    return l
end

function T.Label(parent, text, col, size)
    local l = K().Label(parent, text, size or 13, 400, col or C.dim)
    l:Dock(TOP)
    return l
end

-- T.Empty(parent, text): a quiet centred note in an empty pane.
function T.Empty(parent, text)
    local l = T.Label(parent, text, C.caps, 14)
    l:DockMargin(0, K().S(8), 0, 0)
    return l
end

-- A two-line list row: title, dim line under it; tag = small chip before
-- the title (tagCol, default the accent). isSel() draws it picked (accent bar).
function T.ListRow(parent, title, sub, isSel, onClick, tag, tagCol)
    local k = K()
    local s = k.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(s(54))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(4))
    local fT, fS, fTag = k.Font(14, 700), k.Font(12), k.Font(10, 700)
    local tagUp = tag and string.upper(tag)
    local tagW = 0
    if tagUp then
        surface.SetFont(fTag)
        tagW = surface.GetTextSize(tagUp) + s(12)
    end
    local lw, fitT, fitS
    function b:Paint(w, h)
        local sel = isSel and isSel()
        setCol(sel and C.accentOn or (self:IsHovered() and C.hover or C.card))
        surface.DrawRect(0, 0, w, h)
        setCol(sel and C.accentEdge or C.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        if sel then
            setCol(C.accent)
            surface.DrawRect(0, 0, s(3), h)
        end
        if lw ~= w then
            lw = w
            fitT = k.Fit(title, fT, w - s(28) - (tagUp and tagW + s(8) or 0))
            fitS = k.Fit(sub, fS, w - s(28))
        end
        local x, ty = s(14), s(17)
        if tagUp then
            local tc = tagCol or C.accent
            setCol(tc)
            surface.DrawOutlinedRect(x, ty - s(8), tagW, s(16))
            draw.SimpleText(tagUp, fTag, x + tagW * 0.5, ty, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            x = x + tagW + s(8)
        end
        draw.SimpleText(fitT, fT, x, ty, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(fitS, fS, s(14), h - s(15), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        if onClick then onClick(self) end
    end
    return b
end

-- T.Columns(body): a list column on the left and a reader card filling the rest.
function T.Columns(body)
    local s = K().S
    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(math.Clamp(math.floor(body:GetWide() * 0.36), s(400), s(520)))
    left.Paint = nil
    local right = T.Card(body, { padX = s(20), padY = s(16) })
    right:Dock(FILL)
    right:DockMargin(s(20), 0, 0, 0)
    return left, right
end

function T.FootRow(parent)
    local s = K().S
    local row = vgui.Create("DPanel", parent)
    row:Dock(BOTTOM)
    row:SetTall(s(40))
    row:DockMargin(0, s(10), 0, 0)
    row.Paint = nil
    return row
end

function T.FootButton(row, text, fn, opts)
    local s = K().S
    local b = T.Btn(row, text, fn, opts)
    b:Dock(RIGHT)
    b:SetWide(math.max(b:GetWide(), s(130)))
    b:DockMargin(s(8), 0, 0, 0)
    return b
end

--------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------

local function bansTab(body)
    local k = K()
    local s = k.S
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(40))
    top:DockMargin(0, 0, 0, s(12))
    top.Paint = nil
    T.Title(top, "Banned from uploading"):Dock(LEFT)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #T.term.bans == 0 then T.Empty(sp, "Nobody is banned.") end
    for _, b in ipairs(T.term.bans) do
        local r = T.Card(sp, { padY = s(10) })
        r:Dock(TOP)
        r:SetTall(s(60))
        r:DockMargin(0, 0, s(8), s(6))
        local u = T.Btn(r, "Unban", function()
            send("dp.tunban", function() net.WriteString(b.sid) end)
        end, { small = true })
        u:Dock(RIGHT)
        u:SetWide(s(110))
        u:DockMargin(0, s(4), 0, s(4))
        local n = k.Label(r, b.name, 15, 700, C.text)
        n:Dock(TOP)
        local id = k.Label(r, b.sid, 12, 400, C.caps)
        id:Dock(TOP)
    end
end

D.TermAddTab("bans", {
    order = 100,
    name = "Bans",
    badge = function(tm) return #tm.bans > 0 and #tm.bans or nil end,
    has = function(tm) return tm.mod end,
    build = bansTab,
})

--------------------------------------------------------------------------
-- Notices: the opaque window hides the HUD notice and the chat feed, so
-- while it is open the last few Rhylib.Notify lines also show in it (top
-- right, under the tab bar, 6 s each). The normal notice and chat line
-- still happen.
--------------------------------------------------------------------------

local NOTE_LIFE, NOTE_MAX = 6, 3
T.notes = T.notes or {}

Rhylib.Hook.Add("Rhylib.NotifyShow", "datapad.term.notices", function(tag, text, kind)
    if not IsValid(T.panel) then return end
    local k = K()
    if not k then return end
    local font = k.Font(13, 600)
    surface.SetFont(font)
    local line = (tag ~= "" and ("[" .. tag .. "] ") or "") .. text
    table.insert(T.notes, 1, { text = line, kind = kind, at = RealTime(), font = font, w = surface.GetTextSize(line) })
    for i = #T.notes, NOTE_MAX + 1, -1 do T.notes[i] = nil end
end, -100)   -- (early, before a HUD addon that draws notices itself; returns nothing)

function T.DrawNotices(w)
    local n = #T.notes
    if n == 0 then return end
    local s = K().S
    local now = RealTime()
    local y = s(76) + s(52) + s(10)
    local right = w - s(28)
    for i = 1, n do
        local nt = T.notes[i]
        if nt and now - nt.at < NOTE_LIFE then
            local col = nt.kind == "bad" and C.bad or (nt.kind == "good" and C.good or C.accent)
            local bw, bh = math.min(nt.w + s(28), w - s(56)), s(34)
            local x = right - bw
            setCol(C.header)
            surface.DrawRect(x, y, bw, bh)
            setCol(C.edge)
            surface.DrawOutlinedRect(x, y, bw, bh)
            setCol(col)
            surface.DrawRect(x, y, s(3), bh)
            draw.SimpleText(nt.text, nt.font, x + s(14), y + bh * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            y = y + bh + s(6)
        end
    end
    -- Drop old ones (from the end; no table made).
    for i = n, 1, -1 do
        if now - T.notes[i].at >= NOTE_LIFE then T.notes[i] = nil else break end
    end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

-- The tabs this player gets, in order: { id, label, build(body), highlight, badge }.
local function tabs()
    local list = {}
    for _, def in pairs(T.tabs) do
        if not def.has or def.has(T.term) then list[#list + 1] = def end
    end
    table.sort(list, function(a, b) return (a.order or 50) < (b.order or 50) end)
    local out = {}
    for i, def in ipairs(list) do
        local name = isfunction(def.name) and def.name(T.term) or def.name or def.id
        out[i] = { def.id, name, def.build, def.accent and def.accent(T.term) or nil, def.badge and def.badge(T.term) or nil }
    end
    return out
end

-- The battalion's short tag for the badge: its leading number, else its first letters.
local function prefix(bn)
    local n = string.match(bn, "^%s*(%d+)")
    if n then return n end
    local w = string.match(bn, "(%w+)") or ""
    return string.upper(string.sub(w, 1, 3))
end

-- Members of this battalion on the server now (nil when it has none set).
function T.OnlineCount()
    if not T.term or T.term.med or T.term.bn == "" then return nil end
    local n = 0
    for _, p in ipairs(player.GetAll()) do
        if D.Battalion(p) == T.term.bn then n = n + 1 end
    end
    return n
end

local function buildHeader(parent, pad)
    local k = K()
    local s = k.S
    local tm = T.term
    local bnCol = (not tm.med and D.BnColor(tm.bn)) or C.accent
    local badgeBg = Color(bnCol.r * 0.18, bnCol.g * 0.18, bnCol.b * 0.18, 255)
    local tag = tm.med and "MED" or (tm.bn ~= "" and prefix(tm.bn) or "--")
    local name = string.upper(tm.med and "Medical holotable" or (tm.bn ~= "" and tm.bn or "Battalion computer"))
    local bits = { tm.med and "MEDICAL HOLOTABLE · MEDICAL RECORDS" or "BATTALION COMPUTER" }
    if tm.foreign then bits[#bits + 1] = "ADMIN INSPECTION" end
    local on = T.OnlineCount()
    if on then bits[#bits + 1] = on .. (on == 1 and " MEMBER ONLINE" or " MEMBERS ONLINE") end
    local capsLine = table.concat(bits, "  ·  ")
    local fBadge, fName, fCaps = k.Font(14, 700), k.Font(26, 800), k.Font(12, 500)

    local h = vgui.Create("DPanel", parent)
    h:Dock(TOP)
    h:SetTall(s(76))
    h:DockPadding(pad, 0, pad, 0)
    function h:Paint(w, hh)
        setCol(C.header)
        surface.DrawRect(0, 0, w, hh)
        setCol(C.edge)
        surface.DrawRect(0, hh - 1, w, 1)
        local bs = s(40)
        local by = math.floor((hh - bs) * 0.5)
        setCol(badgeBg)
        surface.DrawRect(pad, by, bs, bs)
        setCol(bnCol)
        surface.DrawOutlinedRect(pad, by, bs, bs)
        draw.SimpleText(tag, fBadge, pad + bs * 0.5, by + bs * 0.5, bnCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local x = pad + bs + s(16)
        draw.SimpleText(name, fName, x, hh * 0.5 + s(3), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        draw.SimpleText(capsLine, fCaps, x, hh * 0.5 + s(6), C.caps, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local close = T.Btn(h, "", function() if IsValid(T.panel) then T.panel:Remove() end end, { quiet = true, tooltip = "Close" })
    close:Dock(RIGHT)
    close:SetWide(s(44))
    close:DockMargin(s(10), s(16), 0, s(16))
    local paintBtn = close.Paint
    function close:Paint(w, hh)
        paintBtn(self, w, hh)
        local c = self:IsHovered() and C.text or C.dim
        local r = s(7)
        surface.SetDrawColor(c.r, c.g, c.b, 255)
        surface.DrawLine(w * 0.5 - r, hh * 0.5 - r, w * 0.5 + r, hh * 0.5 + r)
        surface.DrawLine(w * 0.5 + r, hh * 0.5 - r, w * 0.5 - r, hh * 0.5 + r)
        surface.DrawLine(w * 0.5 - r + 1, hh * 0.5 - r, w * 0.5 + r + 1, hh * 0.5 + r)
        surface.DrawLine(w * 0.5 + r + 1, hh * 0.5 - r, w * 0.5 - r + 1, hh * 0.5 + r)
        return true
    end

    -- Upload your notes (or records at the holotable).
    local n = tm.upload
    local up = T.Btn(h, "Upload " .. (tm.med and "records" or "notes"), function() send("dp.tup") end,
        { primary = true, enabled = n > 0 and not tm.banned })
    up:Dock(RIGHT)
    up:DockMargin(s(10), s(18), 0, s(18))
    local what = tm.med and "record" or "note"
    local note = tm.banned and "You're banned from uploading here"
        or ((n > 0 and n or "No") .. " " .. what .. (n == 1 and "" or "s") .. " on your datapad")
    local nl = vgui.Create("DPanel", h)
    nl:Dock(RIGHT)
    local fNote = k.Font(12, tm.banned and 700 or 400)
    surface.SetFont(fNote)
    nl:SetWide(surface.GetTextSize(note) + s(6))
    function nl:Paint(w, hh)
        draw.SimpleText(note, fNote, w, hh * 0.5, tm.banned and C.bad or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Admins: give a new computer its battalion.
    if tm.admin and not tm.med and tm.bn == "" then
        local set = T.Btn(h, "Set battalion", function()
            local m = k.Menu()
            local cats = DarkRP and DarkRP.getCategories and DarkRP.getCategories().jobs or {}
            for _, c in ipairs(cats) do
                if c.name then
                    m:AddOption(c.name, function() send("dp.tset", function() net.WriteString(c.name) end) end)
                end
            end
            m:AddOption("Type a name…", function()
                k.Prompt("Battalion", "The DarkRP job category this computer belongs to", tm.bn, function(t)
                    send("dp.tset", function() net.WriteString(t) end)
                end)
            end)
            m:Open()
        end)
        set:Dock(RIGHT)
        set:DockMargin(s(10), s(18), s(10), s(18))
    end
end

local function buildTabBar(parent, list)
    local k = K()
    local s = k.S
    local bar = vgui.Create("DPanel", parent)
    bar:Dock(TOP)
    bar:SetTall(s(52))
    bar:DockPadding(s(24), 0, s(24), 0)
    function bar:Paint(w, h)
        setCol(C.bar)
        surface.DrawRect(0, 0, w, h)
        setCol(C.edge)
        surface.DrawRect(0, h - 1, w, 1)
    end
    local fOn, fOff, fBadge = k.Font(14, 700), k.Font(14, 500), k.Font(11, 700)
    for _, t in ipairs(list) do
        local id, label, warn = t[1], t[2], t[4]
        local badge = t[5] and tostring(t[5]) or nil
        surface.SetFont(fOn)
        local tw = surface.GetTextSize(label)
        local bw = 0
        if badge then
            surface.SetFont(fBadge)
            bw = surface.GetTextSize(badge) + s(8)
        end
        local b = vgui.Create("DButton", bar)
        b:SetText("")
        b:Dock(LEFT)
        b:DockMargin(0, 0, s(2), 0)
        b:SetWide(tw + bw + s(32))
        function b:Paint(w, h)
            local on = T.tab == id
            if on then
                setCol(C.accentOn)
                surface.DrawRect(0, 0, w, h)
                setCol(C.accent)
                surface.DrawRect(0, h - s(3), w, s(3))
            elseif self:IsHovered() then
                setCol(C.hover)
                surface.DrawRect(0, 0, w, h)
            end
            draw.SimpleText(label, on and fOn or fOff, s(16), h * 0.5, on and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if badge then
                draw.SimpleText(badge, fBadge, s(16) + tw + s(8), h * 0.5, on and C.accent or (warn and C.warn or C.good), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            return true
        end
        function b:DoClick()
            if T.tab == id then return end
            surface.PlaySound("ui/buttonclick.wav")
            T.tab = id
            T.Build()
        end
    end
end

-- A centred message card in the body (no access, no battalion yet...).
local function notice(body, text, col)
    local s = K().S
    local c = T.Card(body, { fit = true, padX = s(20), padY = s(16) })
    c:Dock(TOP)
    T.Label(c, text, col or C.text, 15)
    return c
end

function T.Build()
    local k = K()
    if not IsValid(T.panel) or not T.term then return end
    local s = k.S
    T.SetMedical(T.term.med)
    T.panel:Clear()
    local pad = s(28)
    local tm = T.term

    local list = {}
    if tm.view and (tm.med or tm.bn ~= "") then
        if not tm.med and T.AskUnit then T.AskUnit() end
        list = tabs()
        local valid = false
        for _, t in ipairs(list) do
            if t[1] == T.tab then valid = true end
        end
        if not valid then T.tab = "logs" end
    end

    buildHeader(T.panel, pad)
    buildTabBar(T.panel, list)

    -- Body: wide screens keep the content to a readable width.
    local body = vgui.Create("DPanel", T.panel)
    body:Dock(FILL)
    local side = math.max(pad, math.floor((ScrW() - s(1920)) * 0.5))
    body:DockPadding(side, s(22), side, s(22))
    body.Paint = nil
    body:SetSize(ScrW() - side * 2, ScrH() - s(128))   -- (size before layout, for tabs that measure it)
    T.panel.body = body

    if not tm.med and tm.bn == "" then
        notice(body, "This computer has no battalion yet. An admin sets it with Set battalion.", C.warn)
        return
    end
    if not tm.view then
        notice(body, tm.med and "Medical records are for medics only." or
            ("This is the " .. tm.bn .. " battalion's computer. Only its members can read it."))
        if not tm.med and T.ApplyPanel then
            local c = T.Card(body, { padX = s(20), padY = s(16) })
            c:Dock(FILL)
            c:DockMargin(0, s(14), 0, 0)
            T.ApplyPanel(c)
        end
        return
    end

    for _, t in ipairs(list) do
        if t[1] == T.tab then t[3](body) end
    end
end

local function open()
    local k = K()
    if not k then return end
    if not IsValid(T.panel) then
        T.panel = vgui.Create("EditablePanel")
        T.panel:SetSize(ScrW(), ScrH())
        T.panel:SetPos(0, 0)
        T.panel:MakePopup()
        -- Fully opaque: the text must stay readable whatever is behind the screen.
        function T.panel:Paint(w, h)
            skinOn()
            setCol(C.ground)
            surface.DrawRect(0, 0, w, h)
        end
        function T.panel:PaintOver(w)
            skinOff()
            T.DrawNotices(w)
        end
        function T.panel:OnRemove()
            skinOff()
            T.notes = {}
        end
        function T.panel:Think()
            local r = D.Cfg("useRange") + 20
            if not T.term or not IsValid(T.term.ent) or LocalPlayer():GetPos():DistToSqr(T.term.ent:GetPos()) > r * r then self:Remove() end
        end
        local reg = (Rhylib.UI and Rhylib.UI.RegisterCloser) or (Rhylib.Menus and Rhylib.Menus.RegisterCloser)
        if reg then
            reg("datapad.term", function()
                if IsValid(T.panel) then T.panel:Remove() return true end
                return false
            end)
        end
    end
    T.Build()
end

Rhylib.Net.Receive("dp.term", function()
    local t = { entries = {}, bans = {} }
    t.ent = net.ReadEntity()
    t.bn = net.ReadString()
    t.view = net.ReadBool()
    t.mod = net.ReadBool()
    t.admin = net.ReadBool()
    t.foreign = net.ReadBool()
    t.banned = net.ReadBool()
    t.upload = net.ReadUInt(8)
    for i = 1, net.ReadUInt(8) do
        t.entries[i] = { id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), pn = net.ReadString(), t = net.ReadUInt(32), mp = net.ReadBool() }
    end
    for i = 1, net.ReadUInt(8) do
        t.bans[i] = { sid = net.ReadString(), name = net.ReadString() }
    end
    if not IsValid(t.ent) then return end
    t.med = t.ent:GetClass() == "rhylib_med_holotable"
    -- A different computer (or newly opened): every tab starts fresh.
    if not T.term or T.term.ent ~= t.ent or not IsValid(T.panel) then
        T.tab = "logs"
        for _, def in pairs(T.tabs) do
            if def.reset then def.reset() end
        end
    end
    T.term = t
    for _, def in pairs(T.tabs) do
        if def.onTerm then def.onTerm(t) end
    end
    open()
end)
