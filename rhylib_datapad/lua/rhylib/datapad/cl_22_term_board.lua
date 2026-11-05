--[[
    Battalion computer window, Board tab (client). Left: BOARD title,
    filter chips (All / Info / Sessions / After action, the last two only
    when the board has such posts), New post; then the posts as cards:
    kind chip, title, NEW (posted since you last opened this board, kept
    in a cookie per battalion), time, the start of the text, author and a
    meta line. The battalion info is the first card; old Info/Plans posts
    sit under "Older posts". Groups: pinned, upcoming sessions (soonest
    first), after-action reports, past sessions, older posts. Click a card
    to open it in place: the whole text, session sign-ups and check-in,
    Write AAR on a past session (fills in a template), Edit / Pin /
    Delete. Writing or editing a post (or the info) replaces the feed.
    Right column: the battalion card (online, members, on leave), next
    sessions (your sign-up once known) and open orders (click: Orders tab).
    Post texts go through one queue (about 3 a second; the open card
    first, then the first few cards; no reply in 3 s: asked again). State in BD;
    registered with D.TermAddTab.
      dp.bopen -> dp.board   dp.bget -> dp.bbody   dp.bsave, dp.bdel,
      dp.bpin, dp.binfo, dp.ursvp, dp.ucheck
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)
local C = T.C

local BD = { board = nil, boardSel = nil, boardBodies = {}, editing = nil, boardMeta = {}, filter = "all", seen = nil, asked = {}, queue = {}, cards = {}, scroll = nil }
-- (boardMeta[post id] = { rv = {{name, s}}, mine, ci = {names}, checked }; seen = newest post time
-- seen before this visit; asked[id] = RealTime it was asked for; queue = ids still to ask; cards[id] = its card panel)

local SECTIONS = { "Info", "Plans", "Session", "AAR" }
local KIND = { "INFO", "PLANS", "SESSION", "AFTER ACTION" }
local OUTCOMES = { "Success", "Partial success", "Failure" }
local RSVP = { "Attending", "Maybe", "Can't" }
local RSVP_UP = { "GOING", "MAYBE", "CAN'T" }
local PREFETCH = 6

local function kindCol(sec)
    if sec == 1 then return C.good end
    if sec == 3 then return C.accent end
    if sec == 4 then return C.warn end
    return C.dim
end

local function postById(id)
    if not BD.board then return nil end
    for _, p in ipairs(BD.board.posts) do
        if p.id == id then return p end
    end
end

-- "today 20:12", "yesterday 18:30", "03 Nov 14:00".
local function relTime(t)
    if not t or t <= 0 then return "" end
    local d, today = os.date("*t", t), os.date("*t")
    if d.year == today.year and d.yday == today.yday then return "today " .. os.date("%H:%M", t) end
    local y = os.date("*t", os.time() - 86400)
    if d.year == y.year and d.yday == y.yday then return "yesterday " .. os.date("%H:%M", t) end
    return os.date("%d %b %H:%M", t)
end

-- The first lines of a text (cut on a character boundary).
local function preview(txt)
    txt = string.Trim(txt or "")
    local cut = #txt
    local lines = 0
    for i = 1, #txt do
        if string.byte(txt, i) == 10 then
            lines = lines + 1
            if lines >= 3 then cut = i - 1 break end
        end
    end
    if cut > 280 then cut = 280 end
    if cut >= #txt then return txt end
    while cut > 0 do
        local b = string.byte(txt, cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    return string.sub(txt, 1, cut) .. "…"
end

local function isNew(t, mine)
    return BD.seen and BD.seen > 0 and t > BD.seen and not mine
end

local function newCount()
    if not BD.board or BD.board.loading then return 0 end
    local n = 0
    for _, p in ipairs(BD.board.posts) do
        if isNew(p.t, p.mine) then n = n + 1 end
    end
    if BD.board.info and isNew(BD.board.info.t) then n = n + 1 end
    return n
end

-- May I edit or delete this post? (the server checks again)
local function canChange(p)
    return BD.board.canPost or (BD.board.canAAR and p.sec == 4 and p.mine)
end

-- Post texts go through one queue, about 3 a second (the server allows
-- 4 a second): the open card or the post being edited first, then the
-- first cards of the feed. A request with no reply after 3 s may go again.
local QUEUE_TIMER = "rhylib_dp_boardfetch"
local function recentlyAsked(id)
    local a = BD.asked[id]
    return a and RealTime() - a < 3
end

local function wanted()
    if isnumber(BD.boardSel) then return BD.boardSel end
    if isnumber(BD.editing) and BD.editing ~= 0 then return BD.editing end
end

local function pump()
    if not IsValid(T.panel) or not T.term or T.tab ~= "board" or not BD.board or BD.board.loading then
        BD.queue = {}
        timer.Remove(QUEUE_TIMER)
        return
    end
    local function send(id)
        BD.asked[id] = RealTime()
        T.Send("dp.bget", function() net.WriteUInt(id, 16) end)
    end
    local want = wanted()
    if want and BD.boardBodies[want] then want = nil end
    if want and not recentlyAsked(want) then send(want) return end
    while #BD.queue > 0 do
        local id = table.remove(BD.queue, 1)
        if not BD.boardBodies[id] and not recentlyAsked(id) then send(id) return end
    end
    if not want then timer.Remove(QUEUE_TIMER) end   -- (an open card still waiting keeps it going, to retry)
end

local function startPump()
    if not timer.Exists(QUEUE_TIMER) then timer.Create(QUEUE_TIMER, 0.34, 0, pump) end
end

-- askBody(): the open card or the editor needs its text (the queue sends it).
local function askBody(id)
    if BD.boardBodies[id] then return end
    startPump()
end

-- A new AAR for a past session, filled in from its sign-ups and check-ins.
local function aarDraft(p)
    local m = BD.boardMeta[p.id]
    local present = (m and #m.ci > 0) and table.concat(m.ci, ", ") or "-"
    return {
        sec = 4, oc = 1, ses = p.id,
        title = "AAR: " .. p.title,
        body = "Objective:\n\nWhat happened:\n\nCasualties:\n\nNotable conduct:\n\nLessons learned:\n\nPresent (checked in): " .. present,
    }
end

local function rowPanel(parent, tall, top)
    local s = T.K().S
    local r = vgui.Create("DPanel", parent)
    r:Dock(TOP)
    r:SetTall(s(tall or 32))
    r:DockMargin(0, s(top or 0), 0, s(8))
    r.Paint = nil
    return r
end

--------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------

-- p: post being edited, or a draft table (new post with presets), or nil.
local function editor(parent, p)
    local k = T.K()
    local s = k.S
    -- Editing a post: wait for its text first.
    if p and p.id and not BD.boardBodies[p.id] then
        T.Empty(parent, "Loading…")
        askBody(p.id)
        return
    end
    local fresh = not p or not p.id
    local sec = p and p.sec or (BD.board.canPost and 3 or 4)
    local oc = (p and p.oc and p.oc > 0) and p.oc or 1
    local ses = p and p.ses or 0
    T.Heading(parent, fresh and (sec == 4 and "New after-action report" or "New post") or "Edit post"):Dock(TOP)
    local secRow = rowPanel(parent, 32, 10)
    local whenRow, ocRow
    local function relayout()
        if IsValid(whenRow) then whenRow:SetVisible(sec == 3) end
        if IsValid(ocRow) then ocRow:SetVisible(sec == 4) end
        parent:InvalidateLayout()
    end
    local secOpts = BD.board.canPost and { { 3, "Session" }, { 4, "After action" } } or { { 4, "After action" } }
    if p and p.id and p.sec < 3 then table.insert(secOpts, 1, { p.sec, SECTIONS[p.sec] }) end   -- (an old Info/Plans post)
    local secs = T.Chips(secRow, secOpts, function() return sec end, function(v)
        sec = v
        relayout()
    end)
    secs:Dock(LEFT)
    local title = k.TextEntry(parent, "Title")
    title:Dock(TOP)
    title:SetTall(s(34))
    title:SetText(p and p.title or "")
    title:DockMargin(0, 0, 0, s(8))

    -- Session time, in your own time zone.
    whenRow = rowPanel(parent, 34)
    local at = (p and (p.at or 0) > 0) and p.at or (os.time() + 86400)
    local date = k.TextEntry(whenRow, "YYYY-MM-DD")
    date:Dock(LEFT)
    date:SetWide(s(140))
    date:SetText(os.date("%Y-%m-%d", at))
    local clock = k.TextEntry(whenRow, "HH:MM")
    clock:Dock(LEFT)
    clock:SetWide(s(90))
    clock:DockMargin(s(6), 0, 0, 0)
    clock:SetText(os.date("%H:%M", at))
    local hint = k.Label(whenRow, "your local time", 12, 400, C.caps)
    hint:Dock(LEFT)
    hint:DockMargin(s(10), s(10), 0, 0)
    hint:SetWide(s(160))

    -- AAR outcome.
    ocRow = rowPanel(parent, 32)
    local ocs = T.Chips(ocRow, { { 1, OUTCOMES[1] }, { 2, OUTCOMES[2] }, { 3, OUTCOMES[3] } }, function() return oc end, function(v) oc = v end)
    ocs:Dock(LEFT)
    relayout()

    local foot = T.FootRow(parent)
    local body = k.TextEntry(parent, "Write here…")
    body:SetMultiline(true)
    body:Dock(FILL)
    if p and p.id then body:SetText(BD.boardBodies[p.id] or "") else body:SetText(p and p.body or "") end
    T.FootButton(foot, "Post", function()
        local t = 0
        if sec == 3 then
            local y, mo, d = string.match(date:GetText() or "", "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
            local hh, mm = string.match(clock:GetText() or "", "^%s*(%d%d?):(%d%d)%s*$")
            if not (y and hh) then
                Derma_Message("Write the date as YYYY-MM-DD and the time as HH:MM.", "Session time", "OK")
                return
            end
            -- os.time on the client = the poster's own time zone; every viewer sees it in theirs.
            t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = 0 }) or 0
        end
        T.Send("dp.bsave", function()
            net.WriteUInt(p and p.id or 0, 16)
            net.WriteUInt(sec, 3)
            net.WriteString(string.sub(title:GetText() or "", 1, 400))
            net.WriteString(string.sub(body:GetText() or "", 1, 8000))
            net.WriteUInt(math.max(0, t), 32)
            net.WriteUInt(sec == 4 and oc or 0, 2)
            net.WriteUInt(sec == 4 and ses or 0, 16)
        end)
        BD.editing = nil
    end, { primary = true })
    T.FootButton(foot, "Cancel", function()
        BD.editing = nil
        T.Build()
    end)
end

-- The battalion info editor: one text, edited over time.
local function infoEditor(parent)
    local k = T.K()
    local s = k.S
    local info = BD.board.info
    T.Heading(parent, "Edit battalion info"):Dock(TOP)
    local hint = T.Label(parent, "Whatever is useful right now: who leads what, SOPs, callsigns, what to bring. Everyone reads it here and on their datapad.")
    hint:DockMargin(0, s(8), 0, s(10))
    local foot = T.FootRow(parent)
    local te = k.TextEntry(parent, "Battalion info…")
    te:SetMultiline(true)
    te:Dock(FILL)
    te:SetText(info.txt)
    T.FootButton(foot, "Save", function()
        T.Send("dp.binfo", function() net.WriteString(string.sub(te:GetText() or "", 1, 12000)) end)
        BD.editing = nil
    end, { primary = true })
    T.FootButton(foot, "Cancel", function()
        BD.editing = nil
        T.Build()
    end)
end

--------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------

-- Sign-ups and check-in for a session (the data comes with its text).
local function sessionStrip(parent, p)
    local k = T.K()
    local s = k.S
    local m = BD.boardMeta[p.id]
    if not m then return end
    local names = { {}, {}, {} }
    for _, r in ipairs(m.rv) do
        if names[r.s] then table.insert(names[r.s], r.name) end
    end
    if T.unit and T.unit.member then
        local row = rowPanel(parent, 32, 10)
        for i, txt in ipairs(RSVP) do
            local b = T.Btn(row, txt .. " (" .. #names[i] .. ")", function()
                T.Send("dp.ursvp", function()
                    net.WriteUInt(p.id, 16)
                    net.WriteUInt(i, 2)
                end)
            end, { small = true, selected = function() return m.mine == i end })
            b:Dock(LEFT)
            b:DockMargin(0, 0, s(6), 0)
        end
        local open = os.time() >= p.at - 15 * 60 and os.time() <= p.at + 3600
        local ci = T.Btn(row, m.checked and "Checked in" or "Check in", function()
            T.Send("dp.ucheck", function() net.WriteUInt(p.id, 16) end)
        end, { small = true, primary = true, enabled = not m.checked and open,
            tooltip = "Opens 15 minutes before the session, closes an hour after it starts" })
        ci:Dock(RIGHT)
    end
    for i, txt in ipairs(RSVP) do
        if #names[i] > 0 then
            T.Label(parent, txt .. ": " .. table.concat(names[i], ", "), nil, 12)
        end
    end
    if #m.ci > 0 then
        local l = T.Label(parent, "Checked in (" .. #m.ci .. "): " .. table.concat(m.ci, ", "), C.good, 12)
        l:DockMargin(0, s(2), 0, 0)
    end
end

-- A card: the top line (kind chip, title, NEW, time), text, by / meta line.
-- d = { key, sec, title, when, by, meta, new, text (nil: not loaded), open }.
local function card(parent, d)
    local k = T.K()
    local s = k.S
    local open = d.open
    local c = T.Card(parent, { fit = true, hi = function() return d.new or open end, bar = open and C.accent or nil })
    c:Dock(TOP)
    c:DockMargin(0, 0, s(8), s(10))
    c:SetCursor("hand")
    function c:OnMousePressed(mc)
        if mc ~= MOUSE_LEFT then return end
        surface.PlaySound("ui/buttonclick.wav")
        BD.boardSel = (BD.boardSel ~= d.key) and d.key or nil
        T.Build()
    end

    local fChip, fTitle, fWhen, fNew = k.Font(10, 700), k.Font(16, 700), k.Font(12), k.Font(10, 700)
    local kind = KIND[d.sec] or "POST"
    local kc = kindCol(d.sec)
    surface.SetFont(fChip)
    local chipW = surface.GetTextSize(kind) + s(16)
    surface.SetFont(fNew)
    local newW = surface.GetTextSize("NEW") + s(12)
    surface.SetFont(fWhen)
    local whenW = surface.GetTextSize(d.when) + s(8)
    local top = vgui.Create("DPanel", c)
    top:Dock(TOP)
    top:SetTall(s(24))
    top:SetMouseInputEnabled(false)
    local lw, fit, titleW
    function top:Paint(w, h)
        T.SetCol(kc)
        surface.DrawOutlinedRect(0, h * 0.5 - s(10), chipW, s(20))
        draw.SimpleText(kind, fChip, chipW * 0.5, h * 0.5, kc, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if lw ~= w then
            lw = w
            fit = k.Fit(d.title, fTitle, w - chipW - s(10) - whenW - (d.new and newW + s(10) or 0))
            surface.SetFont(fTitle)
            titleW = surface.GetTextSize(fit)
        end
        local x = chipW + s(10)
        draw.SimpleText(fit, fTitle, x, h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if d.new then
            x = x + titleW + s(10)
            T.SetCol(C.good)
            surface.DrawRect(x, h * 0.5 - s(8), newW, s(16))
            draw.SimpleText("NEW", fNew, x + newW * 0.5, h * 0.5, C.dark, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(d.when, fWhen, w, h * 0.5, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local txt = k.Label(c, "", 13, 400, C.body)
    txt:Dock(TOP)
    txt:SetMouseInputEnabled(false)
    txt:DockMargin(0, s(8), 0, 0)
    function c:SetBody(t)
        t = open and t or preview(t)
        txt:SetText(t)
        txt:SetVisible(t ~= "")
        self:InvalidateLayout()
    end
    if d.text then c:SetBody(d.text) else
        txt:SetText(open and "Loading…" or "")
        txt:SetVisible(open)
    end

    local foot = vgui.Create("DPanel", c)
    foot:Dock(TOP)
    foot:SetTall(s(18))
    foot:DockMargin(0, s(8), 0, 0)
    foot:SetMouseInputEnabled(false)
    local fFoot = k.Font(12)
    function foot:Paint(w, h)
        draw.SimpleText(d.by, fFoot, 0, h * 0.5, C.caps, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(d.meta, fFoot, w, h * 0.5, C.caps, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    return c
end

-- A row of actions inside an open card.
local function actionRow(c)
    local row = rowPanel(c, 32, 12)
    row:DockMargin(0, T.K().S(12), 0, 0)
    local function btn(text, fn, opts)
        local b = T.Btn(row, text, fn, opts or { small = true })
        b:Dock(LEFT)
        b:DockMargin(0, 0, T.K().S(6), 0)
        return b
    end
    return row, btn
end

local function infoCard(sp)
    local info = BD.board.info
    local open = BD.boardSel == "info"
    local c = card(sp, {
        key = "info", sec = 1, title = "Battalion info", when = relTime(info.t),
        by = info.txt ~= "" and ("Last edited by " .. info.by) or "Nothing written yet",
        meta = "datapad too", new = isNew(info.t), text = info.txt, open = open,
    })
    if open and BD.board.canPost then
        local _, btn = actionRow(c)
        btn("Edit", function()
            BD.editing = "info"
            T.Build()
        end, { small = true, primary = true })
    end
end

local function postCard(sp, p)
    local now = os.time()
    local open = BD.boardSel == p.id
    local meta = {}
    if p.pin then meta[#meta + 1] = "pinned" end
    local when = relTime(p.t)
    if p.sec == 3 and p.at > 0 then
        when = os.date("%a %d %b %H:%M", p.at)
        meta[#meta + 1] = p.at > now and T.Countdown(p.at) or "past"
    elseif p.sec == 4 and OUTCOMES[p.oc] then
        meta[#meta + 1] = OUTCOMES[p.oc]
    end
    local m = BD.boardMeta[p.id]
    local by = p.author
    if p.sec == 4 and p.ses > 0 then
        local ses = postById(p.ses)
        if ses then by = by .. "  ·  on " .. ses.title end
    end
    if m and p.sec == 3 and #m.ci > 0 then by = by .. "  ·  " .. #m.ci .. " checked in" end
    local c = card(sp, {
        key = p.id, sec = p.sec, title = p.title, when = when, by = by,
        meta = table.concat(meta, "  ·  "), new = isNew(p.t, p.mine), text = BD.boardBodies[p.id], open = open,
    })
    BD.cards[p.id] = c
    if not open then return end
    if not BD.boardBodies[p.id] then askBody(p.id) end
    if p.sec == 3 then sessionStrip(c, p) end
    local past = p.sec == 3 and p.at > 0 and p.at < now
    local ses = p.sec == 4 and p.ses > 0 and postById(p.ses)
    if not (ses or canChange(p) or (past and BD.board.canAAR)) then return end
    local _, btn = actionRow(c)
    if ses then
        btn("Report on: " .. ses.title, function()
            BD.boardSel = ses.id
            T.Build()
        end, { small = true, quiet = true })
    end
    if past and BD.board.canAAR then
        btn("Write AAR", function()
            BD.editing = aarDraft(p)
            T.Build()
        end, { small = true, primary = true })
    end
    if canChange(p) then
        btn("Edit", function()
            BD.editing = p.id
            T.Build()
        end)
        if BD.board.canPost then
            btn(p.pin and "Unpin" or "Pin", function() T.Send("dp.bpin", function() net.WriteUInt(p.id, 16) end) end)
        end
        btn("Delete", function()
            T.Send("dp.bdel", function() net.WriteUInt(p.id, 16) end)
            BD.boardSel = nil
        end, { small = true, danger = true })
    end
end

--------------------------------------------------------------------------
-- Right column
--------------------------------------------------------------------------

local function capsLine(parent, text)
    local k = T.K()
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(k.S(20))
    local up, f = string.upper(text), k.Font(12, 600)
    function p:Paint(w, h)
        draw.SimpleText(up, f, 0, h * 0.5, C.caps, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

local function upcoming()
    local now, out = os.time(), {}
    for _, p in ipairs(BD.board and BD.board.posts or {}) do
        if p.sec == 3 and p.at > now - 3600 then out[#out + 1] = p end   -- a session stays "upcoming" for its first hour
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

local function aside(parent)
    local k = T.K()
    local s = k.S
    local now = os.time()
    T.WantPeople()

    -- Battalion numbers.
    local bn = T.Card(parent, { fit = true, top = D.BnColor(T.term.bn) or C.accent, padY = s(14) })
    bn:Dock(TOP)
    bn:DockMargin(0, 0, 0, s(14))
    capsLine(bn, "Battalion")
    local online = T.OnlineCount()
    local leave
    if T.unit then
        leave = 0
        for _, e in ipairs(T.unit.leave) do
            if e.from <= now and e.to >= now then leave = leave + 1 end
        end
    end
    local tiles = {
        { online and tostring(online) or "–", "online" },
        { T.people and tostring(#T.people) or "–", "members" },
        { leave and tostring(leave) or "–", "on leave" },
    }
    local tp = vgui.Create("DPanel", bn)
    tp:Dock(TOP)
    tp:SetTall(s(62))
    tp:DockMargin(0, s(8), 0, 0)
    local fV, fK = k.Font(22, 700), k.Font(11)
    function tp:Paint(w, h)
        local gap = s(8)
        local tw = (w - gap * 2) / 3
        for i = 1, 3 do
            local x = math.floor((i - 1) * (tw + gap))
            T.SetCol(C.bar)
            surface.DrawRect(x, 0, math.floor(tw), h)
            draw.SimpleText(tiles[i][1], fV, x + s(10), s(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(tiles[i][2], fK, x + s(10), h - s(8), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end
    end
    local ses = upcoming()
    local nOpen = 0
    for _, o in ipairs(T.unit and T.unit.orders or {}) do
        if o.st <= 2 then nOpen = nOpen + 1 end
    end
    local line = T.Label(bn, nOpen .. " open order" .. (nOpen == 1 and "" or "s") .. "  ·  " .. #ses .. " upcoming session" .. (#ses == 1 and "" or "s"), C.body, 13)
    line:DockMargin(0, s(10), 0, 0)

    -- Next sessions.
    local sc = T.Card(parent, { fit = true, padY = s(14) })
    sc:Dock(TOP)
    sc:DockMargin(0, 0, 0, s(14))
    capsLine(sc, "Next sessions")
    if #ses == 0 then
        local l = T.Label(sc, "No sessions planned.", C.caps, 13)
        l:DockMargin(0, s(6), 0, 0)
    end
    local fDay, fTime, fName, fHost, fIn = k.Font(11), k.Font(16, 700), k.Font(14, 700), k.Font(12), k.Font(11, 700)
    for i = 1, math.min(#ses, 4) do
        local p = ses[i]
        local day, tm = string.upper(os.date("%a", p.at)), os.date("%H:%M", p.at)
        local cd = p.at > now and string.upper(T.Countdown(p.at)) or "NOW"
        local r = vgui.Create("DButton", sc)
        r:SetText("")
        r:Dock(TOP)
        r:SetTall(s(58))
        r:DockMargin(0, s(6), 0, 0)
        local lw, fitN, fitH
        function r:Paint(w, h)
            T.SetCol(C.edge)
            surface.DrawRect(0, 0, w, 1)
            if self:IsHovered() then
                T.SetCol(C.hover)
                surface.DrawRect(0, 1, w, h - 1)
            end
            local bx, bw, by, bh = 0, s(56), s(8), h - s(14)
            T.SetCol(C.bar)
            surface.DrawRect(bx, by, bw, bh)
            draw.SimpleText(day, fDay, bw * 0.5, by + s(4), C.caps, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(tm, fTime, bw * 0.5, by + bh - s(3), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            -- My sign-up once its text has come (else the countdown).
            local m = BD.boardMeta[p.id]
            local st, col = cd, C.dim
            if m and m.checked then st, col = "CHECKED IN", C.good
            elseif m and RSVP_UP[m.mine] then st, col = RSVP_UP[m.mine], m.mine == 1 and C.good or (m.mine == 2 and C.warn or C.dim) end
            surface.SetFont(fIn)
            local sw = surface.GetTextSize(st)
            draw.SimpleText(st, fIn, w - s(4), h * 0.5, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            if lw ~= w then
                lw = w
                fitN = k.Fit(p.title, fName, w - bw - s(28) - s(80))
                fitH = k.Fit(p.author, fHost, w - bw - s(28) - s(80))
            end
            local x = bw + s(12)
            draw.SimpleText(fitN, fName, x, h * 0.5 - s(1), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText(fitH, fHost, x, h * 0.5 + s(2), C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            return true
        end
        function r:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            BD.filter, BD.boardSel, BD.editing = "all", p.id, nil
            T.Build()
        end
    end

    -- Open orders.
    local oc = T.Card(parent, { fit = true, padY = s(14) })
    oc:Dock(TOP)
    capsLine(oc, "Open orders")
    if not T.unit then
        T.Label(oc, "Loading…", C.caps, 13):DockMargin(0, s(6), 0, 0)
        return
    end
    local shown = 0
    local fO, fSt = k.Font(13), k.Font(11, 700)
    for _, o in ipairs(T.unit.orders) do
        if o.st <= 2 and shown < 5 then
            shown = shown + 1
            local col = D.OrderColor(o.st)
            local st = string.upper(D.ORDER_STATUS[o.st] or "")
            surface.SetFont(fSt)
            local stW = surface.GetTextSize(st)
            local r = vgui.Create("DButton", oc)
            r:SetText("")
            r:Dock(TOP)
            r:SetTall(s(30))
            r:DockMargin(0, s(4), 0, 0)
            local lw, fit
            function r:Paint(w, h)
                if self:IsHovered() then
                    T.SetCol(C.hover)
                    surface.DrawRect(0, 0, w, h)
                end
                T.SetCol(col)
                surface.DrawRect(s(2), h * 0.5 - s(4), s(8), s(8))
                if lw ~= w then
                    lw = w
                    fit = k.Fit((o.mine and "● " or "") .. o.title, fO, w - s(28) - stW - s(12))
                end
                draw.SimpleText(fit, fO, s(20), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(st, fSt, w - s(4), h * 0.5, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                return true
            end
            function r:DoClick()
                surface.PlaySound("ui/buttonclick.wav")
                if T.OpenOrder then T.OpenOrder(o.id) end
            end
        end
    end
    if shown == 0 then T.Label(oc, "No open orders.", C.caps, 13):DockMargin(0, s(6), 0, 0) end
end

--------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------

-- The first cards' texts: replaces what was still waiting (a rebuild doesn't add more).
local function prefetch(ids)
    local q = {}
    for _, id in ipairs(ids) do
        if #q >= PREFETCH then break end
        if not BD.boardBodies[id] and not recentlyAsked(id) then q[#q + 1] = id end
    end
    BD.queue = q
    if #q > 0 or wanted() then startPump() end
end

local function boardTab(body)
    local k = T.K()
    local s = k.S
    if not BD.board then
        T.Empty(body, "Loading the board…")
        BD.board = { posts = {}, canPost = false, canAAR = false, loading = true }
        T.Send("dp.bopen")
        return
    end
    if BD.board.loading then
        T.Empty(body, "Loading the board…")
        return
    end
    BD.cards = {}

    local right = vgui.Create("DPanel", body)
    right:Dock(RIGHT)
    right:SetWide(math.Clamp(math.floor(body:GetWide() * 0.28), s(340), s(420)))
    right:DockMargin(s(20), 0, 0, 0)
    right.Paint = nil
    aside(right)

    local left = vgui.Create("DPanel", body)
    left:Dock(FILL)
    left.Paint = nil

    -- Writing replaces the feed.
    if BD.editing then
        local ed = T.Card(left, { padX = s(20), padY = s(16) })
        ed:Dock(FILL)
        if BD.editing == "info" then
            infoEditor(ed)
            return
        end
        if istable(BD.editing) then
            editor(ed, BD.editing)
            return
        end
        local p = BD.editing ~= 0 and postById(BD.editing) or nil
        if BD.editing == 0 or p then
            editor(ed, p)
            return
        end
        BD.editing = nil   -- deleted meanwhile
        ed:Remove()
    end

    -- Group: pinned, upcoming sessions (soonest first), AARs, past sessions, old Info/Plans posts.
    local now = os.time()
    local hasSes, hasAAR = false, false
    local groups = { { "Pinned", {} }, { "Upcoming sessions", {} }, { "Older posts", {} }, { "After-action reports", {} }, { "Past sessions", {} } }
    for _, p in ipairs(BD.board.posts) do
        local g
        if p.sec == 3 then hasSes = true elseif p.sec == 4 then hasAAR = true end
        if p.pin then g = 1
        elseif p.sec == 3 then g = p.at > now - 3600 and 2 or 5
        elseif p.sec == 4 then g = 4
        else g = 3 end
        table.insert(groups[g][2], p)
    end
    table.sort(groups[2][2], function(a, b) return a.at < b.at end)
    table.sort(groups[5][2], function(a, b) return a.at > b.at end)
    groups = { groups[1], groups[2], groups[4], groups[5], groups[3] }

    local opts = { { "all", "All" }, { "info", "Info" } }
    if hasSes then opts[#opts + 1] = { "ses", "Sessions" } end
    if hasAAR then opts[#opts + 1] = { "aar", "After action" } end
    local okFilter = false
    for _, o in ipairs(opts) do
        if o[1] == BD.filter then okFilter = true end
    end
    if not okFilter then BD.filter = "all" end
    local f = BD.filter
    local function passes(p)
        if f == "all" then return true end
        if f == "info" then return p.sec < 3 end
        if f == "ses" then return p.sec == 3 end
        return p.sec == 4
    end

    local bar = vgui.Create("DPanel", left)
    bar:Dock(TOP)
    bar:SetTall(s(40))
    bar:DockMargin(0, 0, 0, s(12))
    bar.Paint = nil
    T.Title(bar, "Board"):Dock(LEFT)
    local chips = T.Chips(bar, opts, function() return BD.filter end, function(v)
        BD.filter = v
        T.Build()
    end)
    chips:Dock(LEFT)
    chips:DockMargin(s(4), s(4), 0, s(4))
    if BD.board.canPost or BD.board.canAAR then
        local new = T.Btn(bar, BD.board.canPost and "New post" or "New after-action report", function()
            BD.editing = BD.board.canPost and 0 or { sec = 4, oc = 1, ses = 0, title = "AAR: ", body = "" }
            T.Build()
        end)
        new:Dock(RIGHT)
    end

    local sp = k.Scroll(left)
    sp:Dock(FILL)
    BD.scroll = sp
    if f == "all" or f == "info" then infoCard(sp) end
    local ids = {}
    for _, g in ipairs(groups) do
        local list = {}
        for _, p in ipairs(g[2]) do
            if passes(p) then list[#list + 1] = p end
        end
        if #list > 0 then
            local hd = T.Heading(sp, g[1])
            hd:Dock(TOP)
            hd:DockMargin(0, s(2), s(8), s(8))
            for _, p in ipairs(list) do
                postCard(sp, p)
                ids[#ids + 1] = p.id
            end
        end
    end
    if #ids == 0 and f ~= "all" and f ~= "info" then T.Empty(sp, "Nothing here yet.") end
    prefetch(ids)
end

Rhylib.Net.Receive("dp.board", function()
    local ent = net.ReadEntity()
    local b = { canPost = net.ReadBool(), canAAR = net.ReadBool(), posts = {} }
    for i = 1, net.ReadUInt(8) do
        b.posts[i] = { id = net.ReadUInt(16), sec = net.ReadUInt(3), title = net.ReadString(), author = net.ReadString(),
            t = net.ReadUInt(32), at = net.ReadUInt(32), pin = net.ReadBool(), oc = net.ReadUInt(2), ses = net.ReadUInt(16),
            mine = net.ReadBool() }
    end
    b.info = { txt = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32) }
    if not T.term or T.term.ent ~= ent then return end
    BD.board = b
    BD.boardBodies = {}   -- posts may have been edited
    BD.boardMeta = {}
    BD.asked = {}
    BD.queue = {}
    -- NEW: newer than the newest post seen on an earlier visit (per battalion, this computer).
    local key = "rhylib_dp_board_" .. T.term.bn
    local stored = cookie.GetNumber(key, 0)
    if BD.seen == nil then BD.seen = stored end
    local newest = b.info.t
    for _, p in ipairs(b.posts) do
        if p.t > newest then newest = p.t end
    end
    if newest > stored then cookie.Set(key, tostring(newest)) end
    if BD.boardSel and BD.boardSel ~= "info" and not postById(BD.boardSel) then BD.boardSel = nil end
    if IsValid(T.panel) and T.tab == "board" then T.Build() end
end)

Rhylib.Net.Receive("dp.bbody", function()
    local id = net.ReadUInt(16)
    BD.boardBodies[id] = net.ReadString()
    local m = { rv = {}, ci = {} }
    for i = 1, net.ReadUInt(8) do m.rv[i] = { name = net.ReadString(), s = net.ReadUInt(2) } end
    m.mine = net.ReadUInt(2)
    for i = 1, net.ReadUInt(8) do m.ci[i] = net.ReadString() end
    m.checked = net.ReadBool()
    BD.boardMeta[id] = m
    BD.asked[id] = nil
    if not IsValid(T.panel) or T.tab ~= "board" then return end
    if BD.boardSel == id or BD.editing == id then
        T.Build()
    elseif IsValid(BD.cards[id]) then
        BD.cards[id]:SetBody(BD.boardBodies[id])   -- a closed card: just its text
        -- (the feed's scroll range follows once the card has grown)
        timer.Create("rhylib_dp_boardscroll", 0.1, 1, function()
            if IsValid(BD.scroll) then BD.scroll:InvalidateLayout() end
        end)
    end
end)

D.TermAddTab("board", {
    order = 20, name = "Board",
    has = function(tm) return not tm.med end,
    badge = function() local n = newCount() return n > 0 and n or nil end,
    build = boardTab,
    reset = function()
        BD.board, BD.boardSel, BD.boardBodies, BD.editing, BD.boardMeta = nil, nil, {}, nil, {}
        BD.filter, BD.seen, BD.asked, BD.queue, BD.cards = "all", nil, {}, {}, {}
    end,
})
