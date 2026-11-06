--[[
    Datapad window (client). Left click with the datapad out opens it
    (asks dp.open; the server's dp.state opens the window).

    Drawn as a tablet: a dark bezel with rounded corners round a
    teal-on-black screen. While the window paints, the kit's colours are
    swapped for the screen's (PAD below), so kit widgets inside (text
    boxes, scroll bars, rows, other addons' tabs) match it.

      Left strip   tabs in groups: IN THE FIELD (Quick response, Notes,
                   Mission: officers always, live editor), FROM THE
                   COMPUTER (Board, Orders, Logs, LOA, Stats, My file:
                   read from the last download, each shown only once it
                   has something), MANUALS (EOD manual, rhylib_eod: opens
                   Learn), MORE (tabs other addons add), MILITARY POLICE
                   (Records, Officer logs, Arrest). Badges: Quick response
                   "N NEW" (calls for you waiting), Board "N NEW" (posts
                   the last download brought), Orders (new orders for you).
      Top bar      battalion (colour chip) and your name, the sync light
                   and text, SYNC, the clock.
      Quick resp.  the calls (config "calls") as large two-column buttons
                   (icon in the call's colour, who it reaches, ACCEPT FIRST
                   or SENDS POSITION), the resupply picker, the current
                   mission card; right column YOUR CALLS (who's coming,
                   Cancel) and CALLS FOR YOU (Accept / Respond).
    Needs the UI kit (rhylib_core).

    Sync: SYNC sends dp.dl and shows a random 3-15 s progress bar; the
    copy (D.sync) is shown once the bar is done and dp.dldata, dp.dlx and
    dp.dlm have arrived (dp.dlx/dlm: 5 s more at most). The light blinks
    green ("New data on the computer") when dp.ver says the computer is
    newer than D.sync. After your own change (mission, order status) a
    quiet download runs with no bar, so your own pad doesn't flash it.

    Also shared helpers for the computer window (cl_20): D.BnColor,
    D.ReadMission, D.ReadOrders, D.OrderTo/OrderSub/OrderColor/
    OrderStatusMenu, D.IsMPBattalion.
]]

local D = Rhylib.Datapad

local function K() return Rhylib.UI and Rhylib.UI.Kit end
local function when(t) return t and t > 0 and os.date("%d %b %H:%M", t) or "" end

-- Screen colours: theme tokens "datapad.<key>" (Rhylib.UI.Col), read when drawing.
local COL = {}
do
    local def = {
        bezel = { 35, 38, 42 }, bezelEdge = { 58, 63, 69 }, notch = { 21, 23, 26 },
        screen = { 7, 18, 20 }, screenEdge = { 14, 42, 46 }, bar = { 10, 26, 29 }, edge = { 18, 53, 58 },
        card = { 11, 29, 32 }, hover = { 14, 38, 42 }, sel = { 16, 51, 58 },
        accent = { 127, 216, 230 }, accentHi = { 184, 238, 246 }, dim = { 159, 199, 205 }, label = { 95, 154, 163 },
        btnEdge = { 31, 90, 98 }, text = { 228, 227, 220 }, dark = { 7, 18, 20 },
        good = { 151, 196, 89 }, amber = { 239, 159, 39 }, amberHi = { 246, 190, 100 }, amberEdge = { 107, 82, 32 },
        dangerEdge = { 90, 42, 42 }, dangerText = { 240, 149, 149 }, dangerHover = { 40, 18, 18 },
        -- (kit colours of the screen, below)
        rowAlt = { 13, 34, 37 }, rowHover = { 16, 44, 49 }, edgeLight = { 127, 216, 230, 20 },
        tick = { 95, 154, 163, 150 }, buttonHover = { 16, 44, 49 },
    }
    for key, v in pairs(def) do COL[key] = Rhylib.UI.Col("datapad." .. key, v[1], v[2], v[3], v[4]) end
end

-- Kit colours swapped in while the window paints (put back in PaintOver).
local PAD = {
    bg = COL.screen, header = COL.bar, row = COL.card, rowAlt = COL.rowAlt, rowHover = COL.rowHover,
    edgeDark = COL.edge, edgeLight = COL.edgeLight, tick = COL.tick, label = COL.label,
    button = COL.card, buttonHover = COL.buttonHover, buttonDown = COL.sel, textDim = COL.dim, accent = COL.accent,
}
local saved, swapped = {}, false
local function swapIn()
    local k = K()
    if swapped or not k then return end
    swapped = true
    for key, v in pairs(PAD) do saved[key] = k.C[key] k.C[key] = v end
end
local function swapOut()
    local k = K()
    if not swapped or not k then return end
    swapped = false
    for key in pairs(PAD) do k.C[key] = saved[key] end
end

-- Line icons for the calls and the strip (K.Icon shapes, 24 x 24 grid).
-- Added again whenever they're missing (a kit refresh replaces K.ICONS);
-- called at load and each time the window opens.
local function ensureIcons()
    local k = K()
    if k and k.ICONS and not k.ICONS["dp.plus"] then
        k.ICONS["dp.plus"] = { { 12, 5, 12, 19 }, { 5, 12, 19, 12 } }
        k.ICONS["dp.warn"] = { { 12, 3, 21, 19, 3, 19, closed = true }, { 12, 9, 12, 13.5 }, { 12, 16, 12, 16.8 } }
        k.ICONS["dp.box"] = { { 3, 7, 12, 3, 21, 7, 21, 17, 12, 21, 3, 17, closed = true }, { 3, 7, 12, 11, 21, 7 }, { 12, 11, 12, 21 } }
        k.ICONS["dp.diamond"] = { { 12, 3, 21, 12, 12, 21, 3, 12, closed = true } }
        k.ICONS["dp.ext"] = { { 7, 17, 17, 7 }, { 9, 7, 17, 7, 17, 15 } }
    end
end
ensureIcons()
local CALL_ICON = { medic = "dp.plus", eod = "dp.warn", reinf = "players", supply = "dp.box", mp = "battalion" }
local CALL_REACH = { mp = "MPs on duty", medic = "Medics on duty", battalion = "Your battalion", eod = "The bomb squad", all = "Everyone" }

D.state = D.state or nil
D.boardNew = D.boardNew or 0   -- posts the last download brought (Board badge)
local panel, content, navList
local tab = "board"      -- open tab id (TABS below)
local view = {}          -- what the current tab shows (set by replies); reset on tab change
local wantOpen = false
local topText = ""       -- top bar: "BATTALION  ·  name"
local buildTab, buildNav, tabOk

local function send(name, fn)
    Rhylib.Net.Start(name)
    if fn then fn() end
    net.SendToServer()
end

-- D.BnColor(bn): a battalion's colour (its DarkRP job category, else the
-- colour of a job in it), brightened so the strongest channel is at least
-- 150 to read as an accent. nil if unknown. Cached per name.
-- Example: Rhylib.UI.Kit.Tint(panel, function() return D.BnColor("212th") end)
local bnColors = {}
function D.BnColor(bn)
    if not bn or bn == "" then return nil end
    local c = bnColors[bn]
    if c ~= nil then return c or nil end
    c = false
    local cats = DarkRP and DarkRP.getCategories and DarkRP.getCategories()
    for _, cat in ipairs(cats and cats.jobs or {}) do
        if cat.name == bn and IsColor(cat.color) then c = cat.color end
    end
    if not c then
        for _, j in pairs(RPExtraTeams or {}) do
            if j.category == bn and IsColor(j.color) then c = j.color break end
        end
    end
    if c then
        local m = math.max(c.r, c.g, c.b, 1)
        local f = m < 150 and 150 / m or 1
        c = Color(math.min(255, c.r * f), math.min(255, c.g * f), math.min(255, c.b * f), 255)
    end
    bnColors[bn] = c
    return c or nil
end

-- D.ReadMission(): read a mission written by D.WriteMission:
-- { title, date, obj, sub, info, by, t, active, started, npeople, people }, or nil.
function D.ReadMission()
    if not net.ReadBool() then return nil end
    local m = { title = net.ReadString(), date = net.ReadString(), obj = net.ReadString(), sub = net.ReadString(),
        info = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32), active = net.ReadBool(),
        started = net.ReadUInt(32), people = {} }
    m.npeople = net.ReadUInt(8)
    for i = 1, net.ReadUInt(6) do m.people[i] = net.ReadString() end
    return m
end

-- Orders (shared by the computer and the datapad; written by D.WriteOrders).
-- Same list as the server's D.ORDER_STATUS; ORDER_TAG = short list tags.
D.ORDER_STATUS = { "Issued", "In progress", "Completed", "Success", "Failed", "Cancelled" }
D.ORDER_TAG = { "New", "Active", "Done", "Success", "Failed", "Cancelled" }

-- D.ReadOrders(): read a list written by D.WriteOrders: { { id, title, text,
-- by, t, st, sb, stt, all, nto, to = {names}, mine, canSet } }.

function D.ReadOrders()
    local out = {}
    for i = 1, net.ReadUInt(6) do
        local o = { id = net.ReadUInt(16), title = net.ReadString(), text = net.ReadString(), by = net.ReadString(),
            t = net.ReadUInt(32), st = net.ReadUInt(3), sb = net.ReadString(), stt = net.ReadUInt(32), all = net.ReadBool(), to = {} }
        o.nto = net.ReadUInt(7)
        for j = 1, net.ReadUInt(4) do o.to[j] = net.ReadString() end
        o.mine = net.ReadBool()
        o.canSet = net.ReadBool()
        if o.st < 1 or o.st > #D.ORDER_STATUS then o.st = 1 end
        out[i] = o
    end
    return out
end

-- D.OrderTo(o): "whole battalion" or the names ("+N" for names not sent).
-- D.OrderSub(o): the line under an order in a list. D.OrderColor(st): status colour.
function D.OrderTo(o)
    if o.all then return "whole battalion" end
    local s = table.concat(o.to, ", ")
    if o.nto > #o.to then s = s .. " +" .. (o.nto - #o.to) end
    return s
end

function D.OrderSub(o)
    return (o.mine and "You  ·  " or "") .. "To " .. D.OrderTo(o) .. "  ·  " .. o.by .. "  ·  " .. os.date("%d %b %H:%M", o.t)
end

function D.OrderColor(st)
    local C = Rhylib.UI.Kit.C
    if st == 4 or st == 3 then return C.good end
    if st == 5 then return C.bad end
    if st == 6 then return C.textDim end
    return C.warn
end

-- D.OrderStatusMenu(o, full, onPick): a menu of the statuses this player
-- may pick (full = manager: any; else In progress / Completed); onPick(status).
function D.OrderStatusMenu(o, full, onPick)
    local m = Rhylib.UI.Kit.Menu()
    for st, name in ipairs(D.ORDER_STATUS) do
        if st ~= o.st and (full or st == 2 or st == 3) then
            m:AddOption(name, function() onPick(st) end)
        end
    end
    m:Open()
end

-- D.IsMPBattalion(bn): is this the military police battalion (a job in that
-- category has mp = true)? Its stats show arrests made instead of times arrested.
function D.IsMPBattalion(bn)
    for _, j in pairs(RPExtraTeams or {}) do
        if j.category == bn and j.mp then return true end
    end
    return false
end

--------------------------------------------------------------------------
-- Building blocks (screen style)
--------------------------------------------------------------------------

local function clear()
    if IsValid(content) then content:Clear() end
end

-- A screen button. opts: kind ("ghost" outline, default; "primary" filled
-- teal; "amber" filled amber; "danger" red outline), small, enabled (bool
-- or fn), selected (fn: drawn picked), tooltip.
local function pbtn(parent, text, fn, opts)
    opts = opts or {}
    local k = K()
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(k.S(opts.small and 30 or 34))
    if opts.tooltip then b:SetTooltip(opts.tooltip) end
    local kind = opts.kind or "ghost"
    local filled = kind == "primary" or kind == "amber"
    function b:IsOn()
        local en = opts.enabled
        if en == nil then return true end
        if isfunction(en) then return en() and true or false end
        return en and true or false
    end
    function b:Paint(w, h)
        local on = self:IsOn()
        local a = on and 255 or 90
        local hov = on and self:IsHovered()
        local tc
        if filled then
            local fill = kind == "amber" and COL.amber or COL.accent
            k.SetCol(hov and (kind == "amber" and COL.amberHi or COL.accentHi) or fill, a)
            surface.DrawRect(0, 0, w, h)
            tc = COL.dark
        elseif kind == "danger" then
            if hov then k.SetCol(COL.dangerHover) surface.DrawRect(0, 0, w, h) end
            k.SetCol(COL.dangerEdge, a)
            surface.DrawOutlinedRect(0, 0, w, h)
            tc = on and COL.dangerText or COL.label
        else
            local sel = opts.selected and opts.selected()
            if sel then k.SetCol(COL.sel) surface.DrawRect(0, 0, w, h)
            elseif hov then k.SetCol(COL.hover) surface.DrawRect(0, 0, w, h) end
            k.SetCol(sel and COL.accent or COL.btnEdge, a)
            surface.DrawOutlinedRect(0, 0, w, h)
            tc = on and (sel and COL.text or COL.accent) or COL.label
        end
        draw.SimpleText(text, k.Font(12, filled and 700 or 500), w * 0.5, h * 0.5, tc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        if not self:IsOn() then return end
        surface.PlaySound("ui/buttonclick.wav")
        if fn then fn(self) end
    end
    return b
end

local function pbtnW(text)
    local k = K()
    surface.SetFont(k.Font(12, 700))
    return surface.GetTextSize(text) + k.S(32)
end

-- A clickable list row: left text, dim right text. reserve: width kept
-- free on the right (for buttons docked into the row).
local function row(parent, left, right, onClick, tag, reserve)
    local k = K()
    local s = k.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(s(38))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(4))
    local tagU = tag and string.upper(tag)
    function b:Paint(w, h)
        local hov = self:IsHovered() and onClick
        k.SetCol(hov and COL.hover or COL.card)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(hov and COL.btnEdge or COL.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        local x = s(12)
        if tagU then
            draw.SimpleText(tagU, k.Font(11, 700), x, h * 0.5, COL.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            x = x + s(52)
        end
        -- Right text sits left of any reserved space (buttons docked there).
        local rw = reserve or 0
        if right and right ~= "" then
            surface.SetFont(k.Font(12))
            draw.SimpleText(right, k.Font(12), w - rw - s(12), h * 0.5, COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            rw = rw + surface.GetTextSize(right) + s(24)
        end
        draw.SimpleText(k.Fit(left, k.Font(14, 500), w - x - rw - s(12)), k.Font(14, 500), x, h * 0.5, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        if not onClick then return end
        surface.PlaySound("ui/buttonclick.wav")
        onClick()
    end
    return b
end

local function bar(parent)
    local k = K()
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(k.S(32))
    p:DockMargin(0, 0, k.S(8), k.S(10))
    p.Paint = nil
    return p
end

-- opts as before: accent -> primary, danger -> danger, else outline.
local function barButton(p, text, fn, opts)
    local k = K()
    opts = opts or {}
    local b = pbtn(p, text, fn, { kind = opts.accent and "primary" or (opts.danger and "danger" or "ghost"),
        enabled = opts.enabled, small = true })
    b:Dock(LEFT)
    b:SetWide(pbtnW(text))
    b:DockMargin(0, 0, k.S(6), 0)
    return b
end

-- The tab's title: big bold caps.
local function heading(text, parent)
    local k = K()
    local p = vgui.Create("DPanel", parent or content)
    p:Dock(TOP)
    p:SetTall(k.S(38))
    p:DockMargin(0, 0, k.S(8), k.S(2))
    local up = string.upper(text)
    local font = k.Font(28, 700)
    function p:PerformLayout(w) self.txt = k.Fit(up, font, w) end
    function p:Paint(w, h)
        draw.SimpleText(self.txt or up, font, 0, h * 0.5, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

-- An item's title (a log, an order, a mission): bold, wraps.
local function title(parent, text)
    local k = K()
    local l = k.Label(parent, text, 20, 700, COL.text)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(8), k.S(4))
    return l
end

local function label(parent, text, col)
    local k = K()
    local l = k.Label(parent, text, 13, 400, col or COL.dim)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(8), k.S(6))
    return l
end

local function bodyText(parent, text)
    local k = K()
    local l = k.Label(parent, text, 14, 400, COL.text)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(10), k.S(8))
    return l
end

-- A section label: small caps in the label colour.
local function sub(parent, text, top)
    local k = K()
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(k.S(24))
    p:DockMargin(0, top or k.S(8), k.S(8), k.S(4))
    local up = string.upper(text)
    function p:Paint(w, h)
        draw.SimpleText(up, k.Font(12, 500), 0, h * 0.5, COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

-- A card that grows to fit what's docked in it.
local function card(parent, border)
    local k = K()
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(0, 0, s(8), s(10))
    p:DockPadding(s(14), s(10), s(14), s(10))
    function p:Paint(w, h)
        k.SetCol(self.hot and self:IsHovered() and COL.hover or COL.card)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(border or COL.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
    end
    function p:PerformLayout()
        local bottom = 0
        for _, c in ipairs(self:GetChildren()) do
            if c:IsVisible() then
                local _, y = c:GetPos()
                bottom = math.max(bottom, y + c:GetTall())
            end
        end
        local want = bottom + s(10)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
    return p
end

-- Read-only text: title, by-line, body.
local function reader(head, by, body, back)
    clear()
    local k = K()
    local b = bar(content)
    barButton(b, "Back", back)
    title(content, head)
    label(content, by)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    bodyText(sp, body ~= "" and body or "(empty)")
end

--------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------

-- i = note id (0 = new).
local function editor(i, kind, patient)
    clear()
    local k = K()
    local st = D.state
    local note
    for _, n in ipairs(st.notes) do
        if n.id == i then note = n end
    end
    if i > 0 and not note then buildTab() return end
    view.edit = i
    local b = bar(content)
    barButton(b, "Back", function() view.edit = nil buildTab() end)
    local isMed = (note and note.kind or kind) == D.KIND_MED
    heading(i == 0 and (isMed and "New medical record" or "New log") or "Edit note")
    local pn = note and note.pn or (IsValid(patient) and patient:Nick() or "")
    if isMed then label(content, "Patient: " .. pn .. " · upload at the medical holotable") end

    local ti = k.TextEntry(content, "Title")
    ti:Dock(TOP)
    ti:DockMargin(0, 0, k.S(8), k.S(8))
    ti:SetText(note and note.title or "")
    local foot = vgui.Create("DPanel", content)
    foot:Dock(BOTTOM)
    foot:SetTall(k.S(34))
    foot.Paint = nil
    local body = k.TextEntry(content, "Write here…")
    body:SetMultiline(true)
    body:Dock(FILL)
    body:DockMargin(0, 0, k.S(8), k.S(10))
    view.body = body
    if i > 0 then send("dp.get", function() net.WriteUInt(i, 16) end) end
    local save = pbtn(foot, "Save", function()
        send("dp.save", function()
            net.WriteUInt(i, 16)
            net.WriteUInt(isMed and D.KIND_MED or D.KIND_LOG, 1)
            net.WriteString(string.sub(ti:GetText() or "", 1, 400))
            net.WriteString(string.sub(body:GetText() or "", 1, 8000))
            net.WriteEntity(IsValid(patient) and patient or NULL)
        end)
        view.edit = nil
    end, { kind = "primary" })
    save:Dock(RIGHT)
    save:SetWide(k.S(120))
    save:DockMargin(0, 0, k.S(8), 0)
    if i > 0 then
        local del = pbtn(foot, "Delete", function()
            send("dp.del", function() net.WriteUInt(i, 16) end)
            view.edit = nil
        end, { kind = "danger" })
        del:Dock(LEFT)
        del:SetWide(k.S(120))
    end
end

local function notesTab()
    local k = K()
    local st = D.state
    heading("Notes")
    local where = st.bn ~= "" and ("the " .. st.bn .. " computer") or "your battalion computer"
    local full = st.limit > 0 and #st.notes >= st.limit
    if st.limit > 0 then
        label(content, string.format("%d / %d notes on this datapad. When it's full, upload at %s.", #st.notes, st.limit, where),
            full and k.C.warn or nil)
    else
        label(content, "No note limit. Upload logs at " .. where .. (st.medic and ", medical records at the medical holotable." or "."))
    end
    if st.banned then label(content, "You're banned from your battalion's logs.", k.C.bad) end
    local b = bar(content)
    barButton(b, "New log", function() editor(0, D.KIND_LOG) end,
        { accent = true, enabled = not full and not st.banned })
    if st.medic then
        barButton(b, "New medical record", function()
            local m = k.Menu()
            for _, p in ipairs(player.GetAll()) do
                m:AddOption(p:Nick(), function() editor(0, D.KIND_MED, p) end)
            end
            m:Open()
        end, { enabled = not full })
    end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if #st.notes == 0 then label(sp, "Nothing written yet.") end
    for _, n in ipairs(st.notes) do
        local tag = n.kind == D.KIND_MED and "MED" or "LOG"
        row(sp, n.title .. (n.pn ~= "" and ("  ·  " .. n.pn) or ""), when(n.t), function() editor(n.id) end, tag)
    end
end

--------------------------------------------------------------------------
-- MP tabs
--------------------------------------------------------------------------

local function logList(parent, list, back)
    for _, r in ipairs(list) do
        row(parent, r.title .. "  ·  " .. r.author, r.bn .. "  " .. when(r.t), function()
            view.readBack = back
            send("dp.lread", function()
                net.WriteString(r.bn)
                net.WriteUInt(r.id, 20)
            end)
        end)
    end
end

local function recordView()
    clear()
    local k = K()
    local rec = view.record
    local b = bar(content)
    barButton(b, "Back", function() view.record = nil buildTab() end)
    heading(rec.name)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    sub(sp, "Arrests (" .. #rec.jails .. ")", 0)
    if #rec.jails == 0 then label(sp, "No arrests on file.") end
    for _, j in ipairs(rec.jails) do
        row(sp, j.why ~= "" and j.why or "No reason given", j.min .. " min · by " .. j.by .. "  " .. when(j.t))
    end
    sub(sp, "Logs they wrote (" .. #rec.logs .. ")", k.S(12))
    if #rec.logs == 0 then label(sp, "No uploaded logs.") end
    logList(sp, rec.logs, recordView)
end

local function recordsTab()
    local k = K()
    if view.record then recordView() return end
    heading("Records")
    local b = bar(content)
    local q = k.TextEntry(b, "Search by name")
    q:Dock(LEFT)
    q:SetWide(k.S(320))
    q:DockMargin(0, 0, k.S(6), 0)
    q:SetText(view.query or "")
    local function go()
        view.query = q:GetText()
        send("dp.find", function() net.WriteString(string.sub(view.query, 1, 64)) end)
    end
    q.OnEnter = go
    barButton(b, "Search", go, { accent = true })
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if not view.found then
        label(sp, "Find anyone on file: arrests and the logs they uploaded.")
        return
    end
    if #view.found == 0 then label(sp, "Nobody found.") end
    for _, f in ipairs(view.found) do
        row(sp, f.name, f.arrests .. " arrest" .. (f.arrests == 1 and "" or "s"), function()
            send("dp.rec", function() net.WriteString(f.sid) end)
        end)
    end
end

local function ologsTab()
    local k = K()
    heading("Officer logs")
    label(content, "Logs written by MPs.")
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if not view.ologs then
        label(sp, "Loading…")
        send("dp.olog")
        view.ologs = {}
        view.ologsPending = true
        return
    end
    if #view.ologs == 0 and not view.ologsPending then label(sp, "No MP logs uploaded yet.") end
    logList(sp, view.ologs, function() buildTab() end)
end

local function arrestTab()
    local k = K()
    local st = D.state
    local MP = Rhylib.MP
    heading("Arrest")
    label(content, "Cuffed prisoners near you. Search them, or jail them straight from the datapad.")
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local any = false
    for _, p in ipairs(st.cuffed) do
        if IsValid(p) then
            any = true
            local r = row(sp, p:Nick(), "", nil, nil, k.S(200))
            local jail = pbtn(r, "Jail", function()
                local minutes = 5
                local f = k.Prompt("Jail " .. p:Nick(), "Reason (sentence is set next)", "", function(why)
                    k.Prompt("Sentence", "Minutes (1-" .. (MP and MP.Cfg("maxSentence") or 60) .. ")", "5", function(m)
                        minutes = math.Clamp(math.floor(tonumber(m) or 5), 1, 127)
                        send("dp.jail", function()
                            net.WriteEntity(p)
                            net.WriteUInt(minutes, 7)
                            net.WriteString(string.sub(why, 1, 120))
                        end)
                    end)
                end)
                return f
            end, { kind = "primary", small = true })
            jail:Dock(RIGHT)
            jail:SetWide(k.S(90))
            jail:DockMargin(0, k.S(4), k.S(4), k.S(4))
            local search = pbtn(r, "Search", function()
                if MP and MP.OpenSearch then MP.OpenSearch(p) end  -- opens on top of the datapad
            end, { small = true })
            search:Dock(RIGHT)
            search:SetWide(k.S(90))
            search:DockMargin(0, k.S(4), k.S(4), k.S(4))
        end
    end
    if not any then label(sp, "Nobody cuffed nearby. Cuff them first, or escort them here.") end
end

--------------------------------------------------------------------------
-- Battalion: what was last downloaded from the battalion computer
--------------------------------------------------------------------------

D.sync = D.sync or nil      -- { bn, v, at, logs, posts, x = { dp.dlx parts, info, mission } } (kept until you leave)
D.latest = D.latest or {}   -- [battalion] = newest version the server told us about
local dl                    -- a download in progress: { start, dur, data }

local function latestVer()
    local st = D.state
    if not st or st.bn == "" then return 0 end
    return math.max(D.latest[st.bn] or 0, st.ver or 0)
end

local function hasNew()
    local st = D.state
    if not st or st.bn == "" then return false end
    local mine = (D.sync and D.sync.bn == st.bn) and D.sync.v or 0
    return latestVer() > mine
end

-- Keep a finished download; count posts the last one didn't have (Board badge).
local function takeSync(d)
    local old = D.sync
    if old and old.bn == d.bn then
        local seen = {}
        for _, p in ipairs(old.posts or {}) do seen[p.id] = true end
        local n = 0
        for _, p in ipairs(d.posts) do
            if not seen[p.id] then n = n + 1 end
        end
        D.boardNew = (D.boardNew or 0) + n
    else
        D.boardNew = 0
    end
    if IsValid(panel) and tab == "board" then D.boardNew = 0 end
    D.sync = d
end

-- A quiet download right after your own change (posting a mission,
-- setting an order's status), so your own pad doesn't flash "new data".
local qdl   -- { data, extra, more }

local function quietSync()
    if dl or qdl or not D.state or D.state.bn == "" then return end
    qdl = {}
    send("dp.dl")
    timer.Simple(10, function() qdl = nil end)   -- (gave up)
end

local function tryQuiet()
    if not (qdl and qdl.data and qdl.extra and qdl.more) then return end
    local d = qdl.data
    d.x = qdl.extra
    d.x.info = qdl.more.info
    d.x.mission = qdl.more.mission
    d.at = os.time()
    takeSync(d)
    qdl = nil
    if IsValid(panel) and buildNav then buildNav() end
end

local function startDownload()
    if dl or not D.state or D.state.bn == "" then return end
    dl = { start = RealTime(), dur = math.Rand(3, 15) }
    send("dp.dl")
    surface.PlaySound("buttons/button24.wav")
end

local function countdown(at)
    local d = at - os.time()
    if d <= 0 then return "now" end
    if d < 3600 then return "in " .. math.ceil(d / 60) .. " min" end
    if d < 86400 then return string.format("in %d h %d min", math.floor(d / 3600), math.floor(d % 3600 / 60)) end
    return string.format("in %d d %d h", math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

-- The downloaded copy, or a note saying there's none (returns nil).
local function synced()
    local k = K()
    local st = D.state
    local sy = D.sync
    if not sy or sy.bn ~= st.bn then
        label(content, "Nothing downloaded yet. Press SYNC at the top right to download the " .. st.bn ..
            " computer: board, orders, logs, LOA, stats and your file. Uploading still happens at the computer.")
        return nil
    end
    label(content, "Downloaded " .. os.date("%d %b %H:%M", sy.at) .. (hasNew() and "  ·  the computer has newer changes" or "  ·  up to date"),
        hasNew() and k.C.good or nil)
    return sy
end

-- Read a post (kind 1) or log (kind 0) from the computer.
local function openRead(kind, id, head, by)
    view.read = { kind = kind, id = id, title = head, by = by }
    send("dp.dread", function()
        net.WriteUInt(kind, 1)
        net.WriteUInt(id, 20)
    end)
    buildTab()
end

local function showRead()
    local r = view.read
    if not r then return false end
    reader(r.title, r.by, r.body or "Loading…", function() view.read = nil buildTab() end)
    return true
end

local function boardTab()
    local k = K()
    if showRead() then return end
    heading(D.state.bn .. " board")
    local sy = synced()
    if not sy then return end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    -- Battalion info (comes whole with the download).
    local info = sy.x and sy.x.info
    if info and info.txt ~= "" then
        row(sp, "Battalion info", "edited " .. when(info.t), function()
            view.read = { kind = -1, title = "Battalion info", by = "Last edited by " .. info.by .. " · " .. when(info.t), body = info.txt }
            buildTab()
        end, "INFO")
    end
    local now = os.time()
    local groups = { { "Pinned", {} }, { "Upcoming sessions", {} }, { "After-action reports", {} }, { "Older posts", {} } }
    for _, p in ipairs(sy.posts) do
        local g
        if p.pin then g = 1
        elseif p.sec == 3 then g = p.at > now - 3600 and 2 or nil
        elseif p.sec == 4 then g = 3
        else g = 4 end
        if g then table.insert(groups[g][2], p) end
    end
    table.sort(groups[2][2], function(a, b) return a.at < b.at end)
    local any = false
    for _, g in ipairs(groups) do
        if #g[2] > 0 then
            any = true
            sub(sp, g[1])
            for _, p in ipairs(g[2]) do
                local right = p.sec == 3 and (when(p.at) .. "  (" .. countdown(p.at) .. ")") or when(p.t)
                local tag = p.sec == 3 and "SES" or (p.sec == 4 and (({ "WIN", "MIX", "FAIL" })[p.oc] or "AAR")) or nil
                row(sp, p.title, right, function() openRead(1, p.id, p.title, "By " .. p.author .. " · " .. right) end, tag)
            end
        end
    end
    if not any then label(sp, "Nothing posted.") end
end

local function ordersTab()
    local k = K()
    heading("Orders")
    local sy = synced()
    if not sy then return end
    local x = sy.x or { orders = {} }
    -- Reading one.
    local o
    for _, it in ipairs(x.orders) do
        if it.id == view.order then o = it end
    end
    if o then
        clear()
        local b = bar(content)
        barButton(b, "Back", function() view.order = nil buildTab() end)
        if o.canSet then
            barButton(b, "Set status ▾", function()
                D.OrderStatusMenu(o, x.manager, function(newSt)
                    send("dp.ostatus", function()
                        net.WriteUInt(o.id, 16)
                        net.WriteUInt(newSt, 3)
                    end)
                    -- Shown at once; a quiet sync follows (no "new data" for your own change).
                    o.st, o.sb, o.stt = newSt, LocalPlayer():Nick(), os.time()
                    timer.Simple(0.6, quietSync)
                    buildTab()
                end)
            end, { accent = true })
        end
        title(content, o.title)
        label(content, "From " .. o.by .. " · " .. when(o.t) .. "   ·   To: " .. D.OrderTo(o))
        label(content, "Status: " .. D.ORDER_STATUS[o.st] .. (o.sb ~= "" and ("  (" .. o.sb .. ", " .. when(o.stt) .. ")") or ""), D.OrderColor(o.st))
        local sp = k.Scroll(content)
        sp:Dock(FILL)
        bodyText(sp, o.text ~= "" and o.text or "(no details)")
        return
    end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if #x.orders == 0 then label(sp, "No orders.") end
    local function list(head, test)
        local first = true
        for _, it in ipairs(x.orders) do
            if test(it) then
                if first then sub(sp, head) first = false end
                row(sp, it.title, D.ORDER_STATUS[it.st] .. "  ·  " .. (it.all and "battalion" or (it.mine and "you" or it.nto .. " named")),
                    function() view.order = it.id buildTab() end, it.mine and "YOU" or nil)
            end
        end
    end
    list("For you", function(it) return it.st <= 2 and it.mine end)
    list("Open", function(it) return it.st <= 2 and not it.mine end)
    list("Closed", function(it) return it.st > 2 end)
end

local function logsTab()
    local k = K()
    if showRead() then return end
    heading(D.state.bn .. " logs")
    local sy = synced()
    if not sy then return end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if #sy.logs == 0 then label(sp, "No logs.") end
    for _, e in ipairs(sy.logs) do
        row(sp, e.title .. "  ·  " .. e.author, when(e.t), function() openRead(0, e.id, e.title, "By " .. e.author .. " · " .. when(e.t)) end)
    end
end

local function loaTab()
    local k = K()
    heading("Leave of absence")
    local sy = synced()
    if not sy then return end
    local x = sy.x or { leave = {} }
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if #x.leave == 0 then label(sp, "Nobody is on LOA. File yours at the battalion computer.") end
    local now = os.time()
    for _, e in ipairs(x.leave) do
        local range = os.date("%d %b", e.from) .. " – " .. os.date("%d %b", e.to) .. (e.from <= now and "  (now)" or "")
        row(sp, e.name .. (e.why ~= "" and ("  ·  " .. e.why) or ""), range)
    end
end

local STAT_NAMES = D.STAT_NAMES   -- (sh_00_config.lua)
local statText = D.StatText

local function statsTab()
    local k = K()
    local s = k.S
    heading("Stats")
    local sy = synced()
    if not sy or not sy.x then return end
    local x = sy.x
    local mp = D.IsMPBattalion(sy.bn)
    local keys = D.StatKeysShown(mp)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local function table3(head, cols)
        sub(sp, head)
        local hp = vgui.Create("DPanel", sp)
        hp:Dock(TOP)
        hp:SetTall(s(24))
        hp:DockMargin(0, 0, s(8), 0)
        local names = {}
        for i, c in ipairs(cols) do names[i] = string.upper(c[1]) end
        function hp:Paint(w, h)
            local cw = (w - s(180)) / #cols
            for i = 1, #names do
                draw.SimpleText(names[i], k.Font(11, 700), s(180) + cw * i - s(10), h * 0.5, COL.label, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        for i, key in ipairs(keys) do
            local r = vgui.Create("DPanel", sp)
            r:Dock(TOP)
            r:SetTall(s(28))
            r:DockMargin(0, 0, s(8), s(1))
            function r:Paint(w, h)
                k.SetCol(i % 2 == 0 and PAD.rowAlt or COL.card)
                surface.DrawRect(0, 0, w, h)
                draw.SimpleText(STAT_NAMES[key], k.Font(13, 600), s(12), h * 0.5, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local cw = (w - s(180)) / #cols
                for c, col in ipairs(cols) do
                    draw.SimpleText(statText(key, col[2][key]), k.Font(13), s(180) + cw * c - s(10), h * 0.5, c == 1 and COL.dim or COL.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
    table3("This week", { { "Battalion", x.weekAll }, { "You", x.weekMe }, { "You, all time", x.allMe } })
end

local function fileTab()
    local k = K()
    heading("My file")
    local sy = synced()
    if not sy or not sy.x then return end
    local f = sy.x.file
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    sub(sp, "Qualifications", 0)
    label(sp, #f.quals > 0 and table.concat(f.quals, ", ") or "None yet.", #f.quals > 0 and COL.text or nil)
    sub(sp, "Commendations (" .. f.ncom .. ")")
    if #f.coms == 0 then label(sp, "None yet.") end
    for _, c in ipairs(f.coms) do
        local cd = card(sp)
        label(cd, os.date("%d %b %Y", c.t) .. " · " .. c.by)
        bodyText(cd, c.txt)
    end
    sub(sp, "Active strikes (" .. #f.strikes .. ")")
    if #f.strikes == 0 then label(sp, "None.") end
    for _, x in ipairs(f.strikes) do
        local cd = card(sp, COL.dangerEdge)
        label(cd, os.date("%d %b %Y", x.t) .. " · " .. x.by .. " · until " .. os.date("%d %b", x.exp), k.C.bad)
        bodyText(cd, x.txt)
    end
end

-- Am I an officer of my battalion (rank boardRank+)? (the server checks again)
local function isOfficer()
    local R = Rhylib.Roster
    local st = D.state
    if not R or not st or st.bn == "" then return false end
    local c = R.Get(LocalPlayer())
    local need = R.RankIndex(R.Cfg("boardRank")) or 6
    return c.bn == st.bn and c.rank >= need
end

local function missionStatus(m)
    if not m.active then return "Posted, not started" end
    return "Active since " .. os.date("%H:%M", m.started) .. "  ·  " .. m.npeople .. " trooper" .. (m.npeople == 1 and "" or "s") .. " taking part"
end

-- Read-only view of a mission.
local function missionView(m, parent)
    local k = K()
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    title(sp, m.title)
    label(sp, (m.date ~= "" and (m.date .. "  ·  ") or "") .. "by " .. m.by)
    label(sp, missionStatus(m), m.active and k.C.good or k.C.warn)
    local function part(head, txt)
        if txt == "" then return end
        sub(sp, head)
        bodyText(sp, txt)
    end
    part("Objectives", m.obj)
    part("Sub objectives", m.sub)
    part("Info", m.info)
    if #m.people > 0 then
        sub(sp, "Taking part (" .. m.npeople .. ")")
        label(sp, table.concat(m.people, ", ") .. (m.npeople > #m.people and (" +" .. (m.npeople - #m.people)) or ""))
    end
end

-- Officers: post, edit, start and end the battalion's mission.
local function missionEditor()
    local k = K()
    local s = k.S
    local cur = view.mis   -- from dp.mcur
    if not cur then
        heading("Mission")
        label(content, "Loading…")
        if not view.misAsked then
            view.misAsked = true
            send("dp.mget")
            local v = view
            timer.Simple(5, function() v.misAsked = nil end)
        end
        return
    end
    local m = cur.m
    local d = view.misDraft
    if not d then
        d = m and { title = m.title, date = m.date, obj = m.obj, sub = m.sub, info = m.info }
            or { title = "", date = os.date("%d %b %Y"), obj = "", sub = "", info = "" }
        view.misDraft = d
    end
    heading("Mission")
    if m then
        label(content, missionStatus(m), m.active and k.C.good or k.C.warn)
    else
        label(content, "No mission yet. Fill it in and post it; troopers get it when they sync.")
    end
    -- Buttons.
    local b = bar(content)
    barButton(b, m and "Save changes" or "Post mission", function()
        view.misAction = true
        send("dp.msave", function()
            -- (the server clips by characters; these only stop huge pastes)
            net.WriteString(string.sub(d.title, 1, 1000))
            net.WriteString(string.sub(d.date, 1, 400))
            net.WriteString(string.sub(d.obj, 1, 8000))
            net.WriteString(string.sub(d.sub, 1, 8000))
            net.WriteString(string.sub(d.info, 1, 16000))
        end)
    end, { accent = true })
    if m and not m.active then
        barButton(b, "Start", function()
            view.misAction = true
            send("dp.mstart")
        end, { accent = true })
    end
    if m then
        barButton(b, "End mission", function()
            local menu = k.Menu()
            menu:AddOption("End it (moves it to the computer's archive)", function()
                view.misAction = true
                send("dp.mend")
                view.misDraft = nil
            end)
            menu:Open()
        end, { danger = true })
    end
    -- Fields.
    local top = bar(content)
    local ti = k.TextEntry(top, "Title")
    ti:Dock(FILL)
    ti:SetText(d.title)
    function ti:OnChange() d.title = self:GetText() or "" end
    local date = k.TextEntry(top, "Date")
    date:Dock(RIGHT)
    date:SetWide(s(160))
    date:DockMargin(s(6), 0, 0, 0)
    date:SetText(d.date)
    function date:OnChange() d.date = self:GetText() or "" end
    local function box(key, hint, tall)
        local e = k.TextEntry(content, hint)
        e:SetMultiline(true)
        if tall then e:Dock(FILL) else e:Dock(TOP) e:SetTall(s(80)) end
        e:DockMargin(0, 0, s(8), s(8))
        e:SetText(d[key])
        function e:OnChange() d[key] = self:GetText() or "" end
    end
    box("obj", "Objectives")
    box("sub", "Sub objectives")
    box("info", "Info: anything else (where, kit, callsigns…)", true)
end

local function missionTab()
    -- The server has the last word: not an officer there -> read only.
    if isOfficer() and not (view.mis and not view.mis.can) then
        missionEditor()
        return
    end
    heading("Mission")
    local m
    if view.mis then
        m = view.mis.m   -- (fetched live)
    else
        local sy = synced()
        if not sy then return end
        m = sy.x and sy.x.mission
    end
    if not m then
        label(content, "No mission right now.")
        return
    end
    missionView(m, content)
end

-- The downloaded copy for your battalion, if any.
local function cur()
    local sy = D.sync
    return (sy and D.state and sy.bn == D.state.bn) and sy or nil
end
local function curX() local sy = cur() return sy and sy.x end

--------------------------------------------------------------------------
-- Quick response: ask for help, see who's coming, answer others' calls
--------------------------------------------------------------------------

local function callDef(kind) return (D.Cfg("calls") or {})[kind] or {} end
local function callCol(kind) return D.CallColor and D.CallColor(kind) or COL.accent end

-- A large call button: icon square, name, who it reaches, tag.
local function callButton(parent, i, def)
    local k = K()
    local s = k.S
    local col = callCol(i)
    local tint = Color(0, 0, 0)   -- (the call colour, darkened: worked out when drawn)
    local name = def.name or "Call"
    local reach = def.items and "Pick what you need, then send" or (CALL_REACH[def.to] or "Everyone")
    local tag = def.accept and "ACCEPT FIRST" or "SENDS POSITION"
    local tagCol = def.accept and COL.amber or COL.label
    local icon = CALL_ICON[def.id] or "radio"
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTooltip(def.accept and "Others accept it before they see where you are" or "Sends your location straight away")
    function b:IsOn() return D.CanCall and D.CanCall(i) and true or false end
    function b:PerformLayout(w)
        local tw = w - s(94) - s(12)
        self.nameFit = k.Fit(name, k.Font(16, 700), tw)
        self.reachFit = k.Fit(reach, k.Font(12), tw)
    end
    function b:Paint(w, h)
        local on = self:IsOn()
        local a = on and 255 or 110
        local hov = on and self:IsHovered()
        k.SetCol(hov and COL.hover or COL.card)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(hov and COL.btnEdge or COL.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        local sz = s(48)
        local ix, iy = s(16), math.floor((h - sz) * 0.5)
        tint.r, tint.g, tint.b = math.floor(col.r * 0.17 + 4), math.floor(col.g * 0.17 + 8), math.floor(col.b * 0.17 + 9)
        k.SetCol(tint, a)
        surface.DrawRect(ix, iy, sz, sz)
        k.SetCol(col, a)
        surface.DrawOutlinedRect(ix, iy, sz, sz)
        k.Icon(icon, ix + s(12), iy + s(12), s(24), col, a)
        local tx, cy = ix + sz + s(14), h * 0.5
        draw.SimpleText(self.nameFit or name, k.Font(16, 700), tx, cy - s(16), on and COL.text or COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(self.reachFit or reach, k.Font(12), tx, cy + s(3), COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(on and tag or "SENT · WAIT A MOMENT", k.Font(10, 700), tx, cy + s(20), on and tagCol or COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function b:DoClick()
        if not self:IsOn() then return end
        surface.PlaySound("ui/buttonclick.wav")
        if def.items then
            view.supply = { kind = i, sel = {} }
            buildTab()
        else
            D.SendCall(i, 0)
        end
    end
    return b
end

-- Lay out children in cols columns of height bh; the panel takes their height.
local function gridLayout(p, btns, cols, bh, gap)
    function p:PerformLayout(w)
        local bw = math.floor((w - gap * (cols - 1)) / cols)
        for i, b in ipairs(btns) do
            b:SetPos(((i - 1) % cols) * (bw + gap), math.floor((i - 1) / cols) * (bh + gap))
            b:SetSize(bw, bh)
        end
        local want = math.ceil(#btns / cols) * (bh + gap)
        if self:GetTall() ~= want then self:SetTall(want) end
    end
end

-- One of your own open calls: colour dot, who's coming, Cancel.
local function myCallCard(parent, c)
    local k = K()
    local s = k.S
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(s(60))
    p:DockMargin(0, 0, s(8), s(8))
    local col = callCol(c.kind)
    local head = D.CallTitle(c)
    local items = D.CallItems and D.CallItems(c)
    if items then head = head .. " · " .. items end
    local line = #c.resp > 0 and D.CallInbound(c) or "Waiting for a response…"
    local lineCol = #c.resp > 0 and COL.good or COL.dim
    local x = pbtn(p, "Cancel", function() D.CancelCall(c.id) end, { kind = "danger", small = true })
    x:Dock(RIGHT)
    x:SetWide(s(76))
    x:DockMargin(0, s(15), s(12), s(15))
    function p:PerformLayout(w)
        local tw = w - s(30) - s(100)
        self.headFit = k.Fit(head, k.Font(14, 700), tw)
        self.lineFit = k.Fit(line, k.Font(12), tw)
    end
    function p:Paint(w, h)
        k.SetCol(COL.card)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(COL.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        local r = s(4)
        draw.RoundedBox(r, s(12), h * 0.5 - r, r * 2, r * 2, col)
        draw.SimpleText(self.headFit or head, k.Font(14, 700), s(30), h * 0.5 - s(9), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(self.lineFit or line, k.Font(12), s(30), h * 0.5 + s(10), lineCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

-- Someone's call for you: what, how long ago, who and where; Accept /
-- Respond (both answer it; Accept for calls that hide the caller until then).
local function incomingCard(parent, c)
    local k = K()
    local s = k.S
    local d = callDef(c.kind)
    local waiting = c.role == 0
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(waiting and s(100) or s(64))
    p:DockMargin(0, 0, s(8), s(8))
    local head = D.CallTitle(c)
    local items = D.CallItems and D.CallItems(c)
    if items then head = head .. " · " .. items end
    local col = callCol(c.kind)
    local border = (waiting and d.accept) and COL.amberEdge or COL.edge
    if waiting then
        local bt = d.accept and "Accept" or "Respond"
        local b = pbtn(p, bt, function() D.RespondCall(c.id) end, { kind = d.accept and "amber" or "primary", small = true })
        b:SetSize(pbtnW(bt) + s(8), s(32))
        function p:PerformLayout(w, h) b:SetPos(s(12), h - s(12) - b:GetTall()) end
    end
    function p:Think()
        local now = RealTime()
        if now < (self.next or 0) then return end
        self.next = now + 0.5
        local a = math.max(0, math.floor(now - c.born))
        self.age = string.format("%d:%02d", math.floor(a / 60), a % 60)
        local where = c.showPos and D.CallDistance(c) or "accept to see where"
        local who = c.name .. (where ~= "" and ("  ·  " .. where) or "")
        if c.role == 1 then who = who .. "  ·  you're responding" end
        if who ~= self.who then self.who, self.whoFit = who, nil end
    end
    function p:Paint(w, h)
        k.SetCol(COL.card)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(border)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(col)
        surface.DrawRect(0, 0, s(3), h)
        if self.fitW ~= w then self.fitW, self.headFit, self.whoFit = w, k.Fit(head, k.Font(14, 700), w - s(70)), nil end
        if self.who and not self.whoFit then self.whoFit = k.Fit(self.who, k.Font(12), w - s(24)) end
        draw.SimpleText(self.headFit, k.Font(14, 700), s(12), s(18), COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if self.age then draw.SimpleText(self.age, k.Font(11), w - s(12), s(18), COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        if self.whoFit then draw.SimpleText(self.whoFit, k.Font(12), s(12), s(40), c.role == 1 and COL.good or COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    end
end

-- The right column: your calls, then calls for you.
local function fillCalls(col)
    if not IsValid(col) then return end
    col:Clear()
    local mine, incoming = {}, {}
    for _, c in pairs(D.calls or {}) do
        if c.role == 2 then mine[#mine + 1] = c else incoming[#incoming + 1] = c end
    end
    table.sort(mine, function(a, b) return a.id > b.id end)
    table.sort(incoming, function(a, b) return a.id > b.id end)
    sub(col, "Your calls", 0)
    if #mine == 0 then label(col, "None open.") end
    for _, c in ipairs(mine) do myCallCard(col, c) end
    sub(col, "Calls for you", K().S(14))
    if #incoming == 0 then label(col, "Nobody needs you right now.") end
    for _, c in ipairs(incoming) do incomingCard(col, c) end
end

-- The mission card under the calls (from the last download).
local function missionCard(parent, m)
    local k = K()
    local cd = card(parent)
    sub(cd, "Current mission", 0)
    local t = k.Label(cd, m.title ~= "" and m.title or "Mission", 16, 700, COL.text)
    t:Dock(TOP)
    t:DockMargin(0, 0, 0, k.S(4))
    local l = k.Label(cd, m.obj ~= "" and m.obj or missionStatus(m), 13, 400, COL.dim)
    l:Dock(TOP)
    if tabOk("mission") then
        cd.hot = true
        cd:SetCursor("hand")
        function cd:OnMousePressed(code)
            if code ~= MOUSE_LEFT then return end
            surface.PlaySound("ui/buttonclick.wav")
            tab = "mission"
            view = {}
            buildTab()
        end
    end
end

local function supplyPicker(left)
    local k = K()
    local s = k.S
    local pick = view.supply
    local items = D.Cfg("supplyItems") or {}
    heading(callDef(pick.kind).name or "Request resupply", left)
    label(left, "What do you need? Pick one or more, then send.")
    local grid = vgui.Create("DPanel", left)
    grid:Dock(TOP)
    grid:DockMargin(0, s(4), s(8), s(12))
    grid.Paint = nil
    local btns = {}
    for i, name in ipairs(items) do
        btns[#btns + 1] = pbtn(grid, name, function() pick.sel[i] = not pick.sel[i] or nil end,
            { selected = function() return pick.sel[i] ~= nil end })
    end
    gridLayout(grid, btns, 3, s(36), s(8))
    local b = bar(left)
    barButton(b, "Back", function() view.supply = nil buildTab() end)
    barButton(b, "Send request", function()
        local mask = 0
        for i in pairs(pick.sel) do mask = mask + 2 ^ (i - 1) end
        if mask == 0 then return end
        D.SendCall(pick.kind, mask)
        view.supply = nil
        buildTab()
    end, { accent = true, enabled = function() return next(pick.sel) ~= nil end })
end

local function commsTab()
    local k = K()
    local s = k.S
    local right = k.Scroll(content)
    right:Dock(RIGHT)
    right:SetWide(s(330))
    right:DockMargin(s(18), 0, 0, 0)
    view.callsCol = right
    local left = k.Scroll(content)
    left:Dock(FILL)
    fillCalls(right)
    -- Resupply picker.
    if view.supply then supplyPicker(left) return end
    heading("Quick response", left)
    label(left, "One tap sends it. Calls marked \"Accept first\" only show your position to whoever takes them.")
    -- Call buttons.
    local grid = vgui.Create("DPanel", left)
    grid:Dock(TOP)
    grid:DockMargin(0, s(6), s(8), s(14))
    grid.Paint = nil
    local btns = {}
    for i, def in ipairs(D.Cfg("calls") or {}) do btns[#btns + 1] = callButton(grid, i, def) end
    gridLayout(grid, btns, 2, s(84), s(10))
    if D.state.bn ~= "" and not cur() then
        label(left, "Press SYNC (top right) to download the " .. D.state.bn .. " computer: its board, orders, logs and more show up as tabs.")
    end
    local x = curX()
    if x and x.mission then missionCard(left, x.mission) end
end

-- D.PadRebuild(id): rebuild the window if tab id is open (and nothing is
-- being typed). cl_30_calls calls it when a call changes: on Quick response
-- only the calls column is rebuilt (the resupply picker stays as it is).
function D.PadRebuild(id)
    if not IsValid(panel) or tab ~= id or view.edit then return end
    if id == "comms" and IsValid(view.callsCol) then fillCalls(view.callsCol) return end
    if not view.supply then buildTab() end
end

local function anyStat(t)
    for _, v in pairs(t or {}) do
        if v > 0 then return true end
    end
    return false
end

-- The datapad's tabs, in order. grp: the strip's group; bn: needs a
-- battalion; mp: MPs only; has: shown only once the download holds
-- something for it.
local G_FIELD, G_PC, G_MAN, G_MORE, G_MP = "In the field", "From the computer", "Manuals", "More", "Military police"
local TABS = {
    { id = "comms", name = "Quick response", build = commsTab, grp = G_FIELD },
    { id = "notes", name = "Notes", build = notesTab, grp = G_FIELD },
    { id = "mission", name = "Mission", build = missionTab, grp = G_FIELD, bn = true, has = function()
        if isOfficer() then return true end
        local x = curX()
        return x and x.mission ~= nil end },
    { id = "board", name = "Board", build = boardTab, grp = G_PC, bn = true, has = function()
        local sy = cur()
        return sy and (#sy.posts > 0 or (sy.x and sy.x.info and sy.x.info.txt ~= "")) end },
    { id = "orders", name = "Orders", build = ordersTab, grp = G_PC, bn = true, has = function() local x = curX() return x and #x.orders > 0 end },
    { id = "logs", name = "Logs", build = logsTab, grp = G_PC, bn = true, has = function() local sy = cur() return sy and #sy.logs > 0 end },
    { id = "loa", name = "LOA", build = loaTab, grp = G_PC, bn = true, has = function() local x = curX() return x and #x.leave > 0 end },
    { id = "stats", name = "Stats", build = statsTab, grp = G_PC, bn = true, has = function() local x = curX() return x and (anyStat(x.weekAll) or anyStat(x.allMe)) end },
    { id = "file", name = "My file", build = fileTab, grp = G_PC, bn = true, has = function()
        local x = curX()
        return x and (#x.file.quals > 0 or x.file.ncom > 0 or #x.file.strikes > 0)
    end },
    -- EOD bomb manual (rhylib_eod, Field technician skill "Bomb manual"):
    -- rhylib_eod sets D.EodManualBuild(content, kit) and D.HasEodManual().
    { id = "eod", name = "EOD manual", grp = G_MAN, build = function()
        if D.EodManualBuild then D.EodManualBuild(content, K()) end
    end, has = function() return D.EodManualBuild ~= nil and D.HasEodManual ~= nil and D.HasEodManual() end },
    { id = "records", name = "Records", build = recordsTab, grp = G_MP, mp = true },
    { id = "ologs", name = "Officer logs", build = ologsTab, grp = G_MP, mp = true },
    { id = "arrest", name = "Arrest", build = arrestTab, grp = G_MP, mp = true },
}

-- Tabs other addons add: D.AddTab({ id, name, build = fn(content, kit),
-- has = fn() -> bool, order }) (client). They come after the built-in ones
-- (by order, default 50), before the MP tabs, in the strip's MORE group.
-- Same id = replaced.
-- Example (rhylib_bounty): Rhylib.Datapad.AddTab({ id = "bounty", name = "Bounties",
--     build = function(content, k) ... end, has = function() return true end })
D.extraTabs = D.extraTabs or {}
function D.AddTab(t)
    for i, o in ipairs(D.extraTabs) do
        if o.id == t.id then D.extraTabs[i] = t return end
    end
    D.extraTabs[#D.extraTabs + 1] = t
    table.sort(D.extraTabs, function(a, b) return (a.order or 50) < (b.order or 50) end)
end

-- The built-in tabs with the extra ones before the MP tabs.
local function allTabs()
    if #D.extraTabs == 0 then return TABS end
    local out = {}
    for _, t in ipairs(TABS) do
        if t.id == "records" then
            for _, e in ipairs(D.extraTabs) do
                out[#out + 1] = { id = e.id, name = e.name, has = e.has, grp = G_MORE, build = function() e.build(content, K()) end }
            end
        end
        out[#out + 1] = t
    end
    return out
end

local function allowed(t)
    return (not t.mp or D.state.mp) and (not t.bn or D.state.bn ~= "") and (not t.has or t.has() and true or false)
end

function tabOk(id)
    for _, t in ipairs(allTabs()) do
        if t.id == id then return allowed(t) end
    end
    return false
end

-- Badges on the strip: text and colour, or nil.
local BADGES = {
    comms = function()
        local n = 0
        for _, c in pairs(D.calls or {}) do
            if c.role == 0 then n = n + 1 end
        end
        if n > 0 then return n .. " NEW", COL.amber end
    end,
    board = function()
        if (D.boardNew or 0) > 0 then return D.boardNew .. " NEW", COL.good end
    end,
    orders = function()
        local x = curX()
        if not x then return end
        local n = 0
        for _, o in ipairs(x.orders) do
            if o.mine and o.st == 1 then n = n + 1 end
        end
        if n > 0 then return tostring(n), COL.accent end
    end,
}

local function openTab(id)
    tab = id
    view = {}
    if id == "board" then D.boardNew = 0 end
    buildTab()
end

local function navHead(parent, text)
    local k = K()
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(k.S(30))
    local up = string.upper(text)
    function p:Paint(w, h)
        draw.SimpleText(up, k.Font(11, 500), k.S(10), h - k.S(9), COL.label, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

local function navTab(parent, t)
    local k = K()
    local s = k.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:Dock(TOP)
    b:SetTall(s(36))
    b:DockMargin(0, 0, 0, s(2))
    local ext = t.id == "eod" and Rhylib.Menus and Rhylib.Menus.OpenLearn
    local badgeFn = BADGES[t.id]
    if ext then b:SetTooltip("Opens the bomb manual on the Learn page") end
    function b:Think()
        if not badgeFn then return end
        local now = RealTime()
        if now < (self.next or 0) then return end
        self.next = now + 0.5
        self.badge, self.badgeCol = badgeFn()
    end
    function b:Paint(w, h)
        local on = tab == t.id
        if on then
            k.SetCol(COL.sel)
            surface.DrawRect(0, 0, w, h)
            k.SetCol(COL.accent)
            surface.DrawRect(0, 0, s(3), h)
        elseif self:IsHovered() then
            k.SetCol(COL.hover)
            surface.DrawRect(0, 0, w, h)
        end
        local font = k.Font(13, on and 700 or 500)
        draw.SimpleText(t.name, font, s(12), h * 0.5, on and COL.text or COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if ext then
            if not self.tw then surface.SetFont(k.Font(13, 700)) self.tw = surface.GetTextSize(t.name) end
            k.Icon("dp.ext", s(12) + self.tw + s(6), h * 0.5 - s(6), s(12), COL.label)
        end
        if self.badge then
            draw.SimpleText(self.badge, k.Font(10, 700), w - s(10), h * 0.5, self.badgeCol or COL.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        return true
    end
    function b:DoClick()
        surface.PlaySound("ui/buttonclick.wav")
        openTab(t.id)
    end
    b:Think()
end

-- The tab strip (rebuilt after a download: new data shows new tabs).
function buildNav()
    if not IsValid(navList) or not D.state then return end
    navList:Clear()
    local lastGrp
    for _, t in ipairs(allTabs()) do
        if allowed(t) then
            local g = t.grp or G_MORE
            if g ~= lastGrp then
                navHead(navList, g)
                lastGrp = g
            end
            navTab(navList, t)
        end
    end
    local st = D.state
    topText = (st.bn ~= "" and (string.upper(st.bn) .. "  ·  ") or "") .. LocalPlayer():Nick()
    if not tabOk(tab) then
        tab = tabOk("board") and "board" or "comms"
        view = {}
    end
    if tab == "board" then D.boardNew = 0 end
end

function buildTab()
    if not IsValid(content) or not D.state then return end
    clear()
    for _, t in ipairs(allTabs()) do
        if t.id == tab then t.build() return end
    end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

-- A round status light. lit 0-1 (0 = dark).
local lampCol, glowCol = Color(0, 0, 0), Color(0, 0, 0)
local function lamp(cx, cy, r, col, lit)
    if lit > 0.3 then
        glowCol.r, glowCol.g, glowCol.b, glowCol.a = col.r, col.g, col.b, 45 * lit
        draw.RoundedBox(r * 2, cx - r * 2, cy - r * 2, r * 4, r * 4, glowCol)
    end
    lampCol.r = Lerp(lit, col.r * 0.22, col.r)
    lampCol.g = Lerp(lit, col.g * 0.22, col.g)
    lampCol.b = Lerp(lit, col.b * 0.22, col.b)
    draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, lampCol)
end

-- Top bar: battalion and name, the sync light and text, SYNC, clock.
local function topBar(parent, k)
    local s = k.S
    local top = vgui.Create("DPanel", parent)
    top:Dock(TOP)
    top:SetTall(s(56))
    local clock = vgui.Create("DPanel", top)
    clock:Dock(RIGHT)
    clock:SetWide(s(56))
    clock:DockMargin(s(12), 0, s(20), 0)
    function clock:Think()
        local now = os.time()
        if now ~= self.t then self.t, self.text = now, os.date("%H:%M", now) end
    end
    function clock:Paint(w, h)
        draw.SimpleText(self.text or "", k.Font(15, 500), w, h * 0.5, COL.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local sync = pbtn(top, "SYNC", function() startDownload() end, { enabled = function() return not dl end,
        tooltip = "Download the board, orders, logs and more from the battalion computer" })
    sync:Dock(RIGHT)
    sync:SetWide(s(76))
    sync:DockMargin(0, s(10), 0, s(10))
    function top:Think()
        local want = D.state and D.state.bn ~= "" or false
        if sync:IsVisible() ~= want then sync:SetVisible(want) end
    end
    function top:Paint(w, h)
        draw.RoundedBoxEx(s(8), 0, 0, w, h, COL.bar, false, true, false, false)
        k.SetCol(COL.edge)
        surface.DrawRect(0, h - 1, w, 1)
        local st = D.state
        local x = s(20)
        local bc = st and D.BnColor(st.bn)
        if bc then
            k.SetCol(bc)
            surface.DrawRect(x, h * 0.5 - s(5), s(10), s(10))
            x = x + s(18)
        end
        draw.SimpleText(topText, k.Font(13, 500), x, h * 0.5, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if not st or st.bn == "" then return end
        -- Sync state, right-aligned left of SYNC.
        local rx = sync:GetPos() - s(14)
        local cy = math.floor(h * 0.5)
        local r = s(4)
        if dl then
            local f = math.Clamp((RealTime() - dl.start) / dl.dur, 0, dl.data and 1 or 0.97)
            local bw = s(140)
            local bx = rx - bw
            k.SetCol(COL.card)
            surface.DrawRect(bx, cy - s(3), bw, s(6))
            k.SetCol(COL.amber)
            surface.DrawRect(bx, cy - s(3), bw * f, s(6))
            local txt = "Downloading " .. math.floor(f * 100) .. "%"
            surface.SetFont(k.Font(12))
            local tw = surface.GetTextSize(txt)
            draw.SimpleText(txt, k.Font(12), bx - s(10), cy, COL.amber, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            lamp(bx - s(10) - tw - s(12), cy, r, COL.amber, 0.55 + 0.45 * math.sin(RealTime() * 9))
            return
        end
        local txt, col, lit
        if hasNew() then
            txt, col = "New data on the computer", COL.good
            lit = (math.floor(RealTime() * 2.2) % 2 == 0) and 1 or 0.08
        elseif cur() then
            txt, col, lit = "Synced", COL.dim, 1
        else
            txt, col, lit = "Not synced", COL.label, 0
        end
        surface.SetFont(k.Font(12))
        local tw = surface.GetTextSize(txt)
        draw.SimpleText(txt, k.Font(12), rx, cy, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        lamp(rx - tw - s(12), cy, r, col == COL.dim and COL.accent or col, lit)
    end
    return top
end

local function openWindow()
    local k = K()
    if not k then return end
    if IsValid(panel) then panel:Remove() end
    ensureIcons()
    local s = k.S
    local bz = s(22)
    panel = vgui.Create("EditablePanel")
    panel:SetSize(math.min(ScrW() - s(40), s(1240)), math.min(ScrH() - s(40), s(780)))
    panel:Center()
    panel:MakePopup()
    panel:DockPadding(bz, bz, bz, bz)
    -- The tablet: bezel, notch, screen; then the screen colours for the children.
    function panel:Paint(w, h)
        draw.RoundedBox(s(18), 0, 0, w, h, COL.bezelEdge)
        draw.RoundedBox(s(16), 2, 2, w - 4, h - 4, COL.bezel)
        draw.RoundedBox(2, math.floor(w * 0.5) - s(30), s(8), s(60), s(5), COL.notch)
        draw.RoundedBox(s(8), bz - 1, bz - 1, w - bz * 2 + 2, h - bz * 2 + 2, COL.screenEdge)
        draw.RoundedBox(s(8), bz, bz, w - bz * 2, h - bz * 2, COL.screen)
        swapIn()
    end
    function panel:PaintOver() swapOut() end
    function panel:Think()
        local ply = LocalPlayer()
        if not ply:Alive() or not D.Holding(ply) then self:Remove() return end
        -- Download finished: show it.
        -- (waits for both parts; gives up on the second after 5 s more)
        if dl and dl.data and RealTime() - dl.start >= dl.dur and ((dl.extra and dl.more) or RealTime() - dl.start >= dl.dur + 5) then
            local d = dl.data
            d.x = dl.extra
            if d.x then
                local more = dl.more or {}
                d.x.info = more.info or { txt = "", by = "", t = 0 }
                d.x.mission = more.mission
            end
            d.at = os.time()
            takeSync(d)
            dl = nil
            surface.PlaySound("buttons/button14.wav")
            local was = tab
            buildNav()
            if was ~= tab or (not view.read and not view.order) then buildTab() end
        end
    end
    function panel:OnRemove()
        dl = nil   -- closing the pad cancels a download
        swapOut()
    end
    if Rhylib.UI and Rhylib.UI.RegisterCloser then
        Rhylib.UI.RegisterCloser("datapad", function()
            if IsValid(panel) then panel:Remove() return true end
            return false
        end)
    end

    -- Left strip.
    local nav = vgui.Create("DPanel", panel)
    nav:Dock(LEFT)
    nav:SetWide(s(210))
    nav:DockPadding(s(10), s(14), s(10), s(12))
    function nav:Paint(w, h)
        draw.RoundedBoxEx(s(8), 0, 0, w, h, COL.bar, true, false, true, false)
        k.SetCol(COL.edge)
        surface.DrawRect(w - 1, 0, 1, h)
    end
    local brand = vgui.Create("DPanel", nav)
    brand:Dock(TOP)
    brand:SetTall(s(30))
    function brand:Paint(w, h)
        k.Icon("dp.diamond", s(6), h * 0.5 - s(9), s(18), COL.accent)
        draw.SimpleText("DATAPAD", k.Font(16, 500), s(32), h * 0.5, COL.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local close = pbtn(nav, "Close", function() panel:Remove() end, { small = true })
    close:Dock(BOTTOM)
    close:DockMargin(0, s(8), 0, 0)
    navList = k.Scroll(nav)
    navList:Dock(FILL)

    -- Right: top bar, then the tab.
    local main = vgui.Create("DPanel", panel)
    main:Dock(FILL)
    main.Paint = nil
    topBar(main, k)
    content = vgui.Create("DPanel", main)
    content:Dock(FILL)
    content:DockPadding(s(22), s(18), s(22), s(16))
    content.Paint = nil
    tab = tabOk("board") and "board" or (tabOk(tab) and tab or "comms")
    buildNav()
    view = {}
    buildTab()
end

-- Left click with the datapad out (no cursor showing): ask the server for
-- dp.state, which opens the window. Swallows the attack (0.5 s between asks).
local nextOpen = 0
Rhylib.Hook.Add("PlayerBindPress", "datapad.open", function(ply, bind, pressed)
    if not pressed or not string.find(bind, "+attack", 1, true) or string.find(bind, "+attack2", 1, true) then return end
    if not D.Holding(ply) or vgui.CursorVisible() then return end
    if CurTime() >= nextOpen then
        nextOpen = CurTime() + 0.5
        wantOpen = true
        send("dp.open")
    end
    return true
end)

--------------------------------------------------------------------------
-- Replies
--------------------------------------------------------------------------

Rhylib.Net.Receive("dp.state", function()
    local st = { notes = {}, cuffed = {} }
    st.bn = net.ReadString()
    st.mp = net.ReadBool()
    st.medic = net.ReadBool()
    st.banned = net.ReadBool()
    st.limit = net.ReadUInt(8)
    st.ver = net.ReadUInt(32)
    for i = 1, net.ReadUInt(8) do
        st.notes[i] = { id = net.ReadUInt(16), kind = net.ReadUInt(1), title = net.ReadString(), pn = net.ReadString(), t = net.ReadUInt(32) }
    end
    for i = 1, net.ReadUInt(4) do st.cuffed[i] = net.ReadEntity() end
    D.state = st
    if wantOpen then
        wantOpen = false
        openWindow()
    elseif IsValid(panel) and not view.edit and not (tab == "mission" and view.misDraft) then
        buildNav()   -- (battalion or MP status may have changed)
        buildTab()
    end
end)

Rhylib.Net.Receive("dp.body", function()
    local i = net.ReadUInt(16)
    local body = net.ReadString()
    if view.edit == i and IsValid(view.body) then view.body:SetText(body) end
end)

Rhylib.Net.Receive("dp.found", function()
    local list = {}
    for i = 1, net.ReadUInt(5) do
        list[i] = { sid = net.ReadString(), name = net.ReadString(), arrests = net.ReadUInt(8) }
    end
    view.found = list
    if IsValid(panel) and tab == "records" then buildTab() end
end)

local function readLogs()
    local out = {}
    for i = 1, net.ReadUInt(7) do
        out[i] = { bn = net.ReadString(), id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), t = net.ReadUInt(32) }
    end
    return out
end

Rhylib.Net.Receive("dp.record", function()
    local rec = { sid = net.ReadString(), name = net.ReadString(), jails = {} }
    for i = 1, net.ReadUInt(6) do
        rec.jails[i] = { t = net.ReadUInt(32), by = net.ReadString(), min = net.ReadUInt(10), why = net.ReadString() }
    end
    rec.logs = readLogs()
    view.record = rec
    if IsValid(panel) and tab == "records" then recordView() end
end)

Rhylib.Net.Receive("dp.ologs", function()
    view.ologs = readLogs()
    view.ologsPending = nil
    if IsValid(panel) and tab == "ologs" then buildTab() end
end)

Rhylib.Net.Receive("dp.lbody", function()
    local author, title, t, body = net.ReadString(), net.ReadString(), net.ReadUInt(32), net.ReadString()
    if not IsValid(panel) then return end
    local back = view.readBack or buildTab
    reader(title, "By " .. author .. " · " .. when(t), body, back)
end)

Rhylib.Net.Receive("dp.ver", function()
    local bn, v = net.ReadString(), net.ReadUInt(32)
    D.latest[bn] = v
end)

Rhylib.Net.Receive("dp.dldata", function()
    local d = { logs = {}, posts = {} }
    d.bn = net.ReadString()
    d.v = net.ReadUInt(32)
    for i = 1, net.ReadUInt(8) do
        d.logs[i] = { id = net.ReadUInt(20), author = net.ReadString(), title = net.ReadString(), t = net.ReadUInt(32), mp = net.ReadBool() }
    end
    for i = 1, net.ReadUInt(7) do
        d.posts[i] = { id = net.ReadUInt(16), sec = net.ReadUInt(3), title = net.ReadString(), author = net.ReadString(),
            t = net.ReadUInt(32), at = net.ReadUInt(32), pin = net.ReadBool(), oc = net.ReadUInt(2) }
    end
    D.latest[d.bn] = math.max(D.latest[d.bn] or 0, d.v)
    if dl then
        dl.data = d   -- shown when the progress bar is done
    elseif qdl then
        qdl.data = d
        tryQuiet()
    end
end)

Rhylib.Net.Receive("dp.dlx", function()
    local x = { orders = {}, leave = {}, weekAll = {}, weekMe = {}, allMe = {}, file = { quals = {}, coms = {}, strikes = {} } }
    x.bn = net.ReadString()
    x.manager = net.ReadBool()
    x.orders = D.ReadOrders()
    for i = 1, net.ReadUInt(6) do
        x.leave[i] = { name = net.ReadString(), from = net.ReadUInt(32), to = net.ReadUInt(32), why = net.ReadString() }
    end
    x.weekAll = D.ReadStatRow()
    x.weekMe = D.ReadStatRow()
    x.allMe = D.ReadStatRow()
    local f = x.file
    for i = 1, net.ReadUInt(5) do f.quals[i] = net.ReadString() end
    f.ncom = net.ReadUInt(8)
    for i = 1, net.ReadUInt(4) do f.coms[i] = { t = net.ReadUInt(32), by = net.ReadString(), txt = net.ReadString() } end
    for i = 1, net.ReadUInt(4) do f.strikes[i] = { t = net.ReadUInt(32), exp = net.ReadUInt(32), by = net.ReadString(), txt = net.ReadString() } end
    if dl then
        dl.extra = x
    elseif qdl then
        qdl.extra = x
        tryQuiet()
    end
end)

Rhylib.Net.Receive("dp.dlm", function()
    local info = { txt = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32) }
    local mission = D.ReadMission()
    if dl then
        dl.more = { info = info, mission = mission }
    elseif qdl then
        qdl.more = { info = info, mission = mission }
        tryQuiet()
    end
end)

Rhylib.Net.Receive("dp.dbody", function()
    local kind, id, body = net.ReadUInt(1), net.ReadUInt(20), net.ReadString()
    local r = view.read
    if r and r.kind == kind and r.id == id then
        r.body = body ~= "" and body or "(empty)"
        if IsValid(panel) then buildTab() end
    end
end)

Rhylib.Net.Receive("dp.mcur", function()
    local can = net.ReadBool()
    local m = D.ReadMission()
    if view.misAction then
        view.misAction = nil
        quietSync()
    end
    view.mis = { can = can, m = m }
    view.misAsked = nil
    if not m then view.misDraft = nil end
    if IsValid(panel) and tab == "mission" then buildTab() end
end)

-- A theme switch may change the font: build the open window's strip and tab again.
Rhylib.Hook.Add("Rhylib.ThemeChanged", "datapad.pad", function()
    if IsValid(panel) and IsValid(content) then
        buildNav()
        buildTab()
    end
end)
