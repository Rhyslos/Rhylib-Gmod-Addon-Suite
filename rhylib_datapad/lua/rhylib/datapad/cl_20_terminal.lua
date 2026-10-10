--[[
    Battalion computer / medical holotable window (client). Opens on
    dp.term (E on the computer); closes when you walk out of useRange.
    Needs rhylib_menus (Kit). Every request starts with the computer
    entity (send() below); the server checks range and rights again.

    Top: upload your notes; admins set the battalion. Tabs:
      Logs     search (title, text, author, patient), time filter;
               reader; moderators delete entries and ban authors
      Board    battalion computers: the battalion info, Session and AAR
               posts (old Info/Plans posts under "Older posts"), pinned
               first, upcoming sessions with a countdown, past ones archived;
               "Write AAR" on a past session fills in a template
      Missions the current mission (run from officers' datapads) and the
               archive of ended ones (officers delete)
      Orders   orders to the battalion or named members, with a status;
               managers issue them
      Leave    who is away; members file their own
      Personnel  member files: service record, qualifications,
               commendations, strikes, NCO notes
      Stats    battalion totals and members for a period
      Apps     managers: applications to accept or decline
      Bans     moderators: who can't upload
    Outsiders (CTs without a battalion) can apply here instead.
    Session posts get sign-ups (attending / maybe / can't) and a check-in.
    The medical holotable has Records (and Bans) only.
    Each tab asks for its data the first time it is shown; replies are
    ignored if they are for another computer. The application popup
    (dp.uprompt) also lives here and works anywhere.
]]

local D = Rhylib.Datapad

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local OPAQUE = Color(14, 16, 15, 255)
local function when(t) return t and t > 0 and os.date("%d %b %Y %H:%M", t) or "" end

local panel
local term            -- last dp.term
local tab = "logs"
local selected        -- selected log id
local bodies = {}     -- [log id] = text
local filter = { q = "", days = 0, mp = false, ids = nil }   -- ids: set from the last search
local board, boardSel, boardBodies, editing = nil, nil, {}, nil
local statsPeriod, statsData, statsSort = 2, nil, "mi"
local boardMeta = {}  -- [post id] = { rv = {{name, s}}, mine, ci = {names}, checked }
local unit, unitAsked, appSel, orderDraft, orderSel = nil, nil, nil, nil, nil
local appInfo, appAsked = {}, nil   -- [application id] = the applicant's record
local missions, missionsAsked, missionSel, missionFull = nil, nil, nil, {}
local people, peopleAsked, personSel, pfile, pAsked, notesEdit = nil, nil, nil, nil, nil, false

local SECTIONS = { "Info", "Plans", "Session", "AAR" }
local OUTCOMES = { "Success", "Partial success", "Failure" }
local STAT_NAMES = {
    kd = "Droid kills", kp = "Player kills", de = "Deaths", rv = "Revives",
    he = "Heals", ar = "Arrests", mi = "Hours", mo = "Money", at = "Attended", jd = "Arrested", ev = "Events",
}
local STAT_KEYS = { "kd", "kp", "de", "rv", "he", "ar", "mi", "mo", "at", "jd", "ev" }   -- same order as the server
local RSVP = { "Attending", "Maybe", "Can't" }
local APP_STATUS = { [0] = "Pending", [1] = "Accepted", [2] = "Declined", [3] = "Withdrawn" }
local PERIOD_NAMES = { "Today", "This week", "Last week", "This month", "All time" }

-- Send a computer message: the computer entity first, then fn() writes the rest.
local function send(name, fn)
    Rhylib.Net.Start(name)
    net.WriteEntity(term.ent)
    if fn then fn() end
    net.SendToServer()
end

local build
local sessionStrip

-- Stats shown: MP battalions count arrests made, the others times arrested.
local function shownKeys()
    local mp = D.IsMPBattalion(term and term.bn or "")
    local out = {}
    for _, key in ipairs(STAT_KEYS) do
        if not ((mp and key == "jd") or (not mp and key == "ar")) then out[#out + 1] = key end
    end
    return out
end

local function statText(k, v)
    if k == "mi" then return string.format("%.1f", (v or 0) / 60) end
    if k == "mo" then return string.Comma and string.Comma(v or 0) or tostring(v or 0) end
    return tostring(v or 0)
end

local function countdown(at)
    local d = at - os.time()
    if d <= 0 then return "now" end
    if d < 3600 then return "in " .. math.ceil(d / 60) .. " min" end
    if d < 86400 then return string.format("in %d h %d min", math.floor(d / 3600), math.floor(d % 3600 / 60)) end
    return string.format("in %d d %d h", math.floor(d / 86400), math.floor(d % 86400 / 3600))
end

-- A two-line list row: title, dim line under it.
local function listRow(parent, title, sub, isSel, onClick, tag)
    local k = K()
    local s = k.S
    local b = k.Button(parent, "", onClick, { small = true, align = "left", selected = isSel })
    b:SetTall(s(44))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(3))
    local paint = b.Paint
    function b:Paint(w, hh)
        paint(self, w, hh)
        local x = s(14)
        if tag then
            k.Caps(tag, x, s(14), k.C.accent)
            surface.SetFont(k.Font(12, 700))
            x = x + surface.GetTextSize(string.upper(tag)) + s(8)
        end
        draw.SimpleText(k.Fit(title, k.Font(14, 600), w - x - s(12)), k.Font(14, 600), x, s(6), k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(k.Fit(sub, k.Font(11), w - s(26)), k.Font(11), s(14), hh - s(6), k.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        return true
    end
    return b
end

local function label(parent, text, col, size)
    local k = K()
    local l = k.Label(parent, text, size or 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    return l
end

local function columns(body)
    local k = K()
    local s = k.S
    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(s(430))
    left.Paint = nil
    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)
    right:DockMargin(s(16), 0, 0, 0)
    right.Paint = nil
    return left, right
end

--------------------------------------------------------------------------
-- Logs
--------------------------------------------------------------------------

local function entryById(id)
    for _, e in ipairs(term.entries) do
        if e.id == id then return e end
    end
end

local function logReader(parent)
    local k = K()
    local s = k.S
    local e = selected and entryById(selected)
    if not e then
        label(parent, "Pick an entry to read it.")
        return
    end
    local h = k.Heading(parent, e.title)
    h:Dock(TOP)
    local by = label(parent, "By " .. e.author .. (e.pn ~= "" and (" · patient " .. e.pn) or "") .. " · " .. when(e.t))
    by:DockMargin(0, s(4), 0, s(8))
    if term.mod then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local del = k.Button(row, "Delete entry", function()
            send("dp.tdel", function() net.WriteUInt(e.id, 20) end)
            selected = nil
        end, { small = true, danger = true })
        del:Dock(LEFT)
        del:SetWide(s(140))
        local ban = k.Button(row, "Ban author", function()
            send("dp.tban", function() net.WriteUInt(e.id, 20) end)
        end, { small = true, danger = true })
        ban:Dock(LEFT)
        ban:SetWide(s(140))
        ban:DockMargin(s(6), 0, 0, 0)
    end
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, bodies[e.id] or "Loading…", 14, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
    if not bodies[e.id] then send("dp.tread", function() net.WriteUInt(e.id, 20) end) end
end

local function runSearch()
    if filter.q == "" and filter.days == 0 then
        filter.ids = nil
        build()
        return
    end
    send("dp.tfind", function()
        net.WriteString(string.sub(filter.q, 1, 64))
        net.WriteUInt(filter.days, 10)
    end)
end

local function logsTab(body)
    local k = K()
    local s = k.S
    -- Search bar.
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(30))
    bar:DockMargin(0, 0, 0, s(8))
    bar.Paint = nil
    local q = k.TextEntry(bar, "Search title, text or author")
    q:Dock(LEFT)
    q:SetWide(s(300))
    q:SetText(filter.q)
    q.OnEnter = function(self)
        filter.q = string.Trim(self:GetText() or "")
        runSearch()
    end
    local go = k.Button(bar, "Search", function() q:OnEnter() end, { small = true, accent = true })
    go:Dock(LEFT)
    go:SetWide(s(80))
    go:DockMargin(s(6), 0, s(12), 0)
    local days = k.Choices(bar, { { 0, "Any time" }, { 1, "Today" }, { 7, "Week" }, { 30, "Month" } },
        function() return filter.days end,
        function(v)
            filter.days = v
            filter.q = string.Trim(q:GetText() or "")
            runSearch()
        end)
    days:Dock(FILL)

    local left, right = columns(body)
    local shown = {}
    for _, e in ipairs(term.entries) do
        if not filter.ids or filter.ids[e.id] then shown[#shown + 1] = e end
    end
    local h = k.Heading(left, (term.med and "Medical records" or "Logs") .. " (" .. #shown .. (#shown ~= #term.entries and (" of " .. #term.entries) or "") .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #shown == 0 then label(sp, #term.entries == 0 and "Nothing uploaded yet." or "Nothing matches.") end
    for _, e in ipairs(shown) do
        local sub = e.author .. (e.pn ~= "" and (" → " .. e.pn) or "") .. "  ·  " .. when(e.t)
        listRow(sp, e.title, sub, function() return selected == e.id end, function()
            selected = e.id
            build()
        end, e.mp and "MP" or nil)
    end
    logReader(right)
end

--------------------------------------------------------------------------
-- Board
--------------------------------------------------------------------------

local function postById(id)
    if not board then return nil end
    for _, p in ipairs(board.posts) do
        if p.id == id then return p end
    end
end

local function postSub(p)
    local s = p.author .. "  ·  " .. when(p.t)
    if p.sec == 3 and p.at > 0 then
        s = when(p.at) .. (p.at > os.time() and ("  (" .. countdown(p.at) .. ")") or "  (past)") .. "  ·  " .. p.author
    elseif p.sec == 4 and OUTCOMES[p.oc] then
        s = OUTCOMES[p.oc] .. "  ·  " .. s
    end
    return s
end

local function postTag(p)
    if p.sec == 3 then return "Session" end
    if p.sec == 4 then return "AAR" end
    return nil
end

-- May I edit or delete this post? (the server checks again)
local function canChange(p)
    return board.canPost or (board.canAAR and p.sec == 4 and p.mine)
end

-- A new AAR for a past session, filled in from its sign-ups and check-ins.
local function aarDraft(p)
    local m = boardMeta[p.id]
    local present = (m and #m.ci > 0) and table.concat(m.ci, ", ") or "-"
    return {
        sec = 4, oc = 1, ses = p.id,
        title = "AAR: " .. p.title,
        body = "Objective:\n\nWhat happened:\n\nCasualties:\n\nNotable conduct:\n\nLessons learned:\n\nPresent (checked in): " .. present,
    }
end

-- p: post being edited, or a draft table (new post with presets), or nil.
local function editor(parent, p)
    local k = K()
    local s = k.S
    -- Editing a post: wait for its text first.
    if p and p.id and not boardBodies[p.id] then
        label(parent, "Loading…")
        send("dp.bget", function() net.WriteUInt(p.id, 16) end)
        return
    end
    local isNew = not p or not p.id
    local sec = p and p.sec or (board.canPost and 3 or 4)
    local oc = (p and p.oc and p.oc > 0) and p.oc or 1
    local ses = p and p.ses or 0
    local h = k.Heading(parent, isNew and (sec == 4 and "New after-action report" or "New post") or "Edit post")
    h:Dock(TOP)
    local secRow = vgui.Create("DPanel", parent)
    secRow:Dock(TOP)
    secRow:SetTall(s(30))
    secRow:DockMargin(0, s(6), 0, s(6))
    secRow.Paint = nil
    local whenRow, ocRow
    local function relayout()
        if IsValid(whenRow) then whenRow:SetVisible(sec == 3) end
        if IsValid(ocRow) then ocRow:SetVisible(sec == 4) end
        parent:InvalidateLayout()
    end
    local secOpts = board.canPost and { { 3, "Session" }, { 4, "AAR" } } or { { 4, "AAR" } }
    if p and p.id and p.sec < 3 then table.insert(secOpts, 1, { p.sec, SECTIONS[p.sec] }) end   -- (an old Info/Plans post)
    local secs = k.Choices(secRow, secOpts, function() return sec end, function(v)
        sec = v
        relayout()
    end)
    secs:Dock(LEFT)
    secs:SetWide(s(board.canPost and 300 or 100))
    local title = k.TextEntry(parent, "Title")
    title:Dock(TOP)
    title:SetText(p and p.title or "")
    title:DockMargin(0, 0, 0, s(6))

    -- Session time, in your own time zone.
    whenRow = vgui.Create("DPanel", parent)
    whenRow:Dock(TOP)
    whenRow:SetTall(s(30))
    whenRow:DockMargin(0, 0, 0, s(6))
    whenRow.Paint = nil
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
    local hint = k.Label(whenRow, "your local time", 12, 400, k.C.textDim)
    hint:Dock(LEFT)
    hint:DockMargin(s(10), s(8), 0, 0)
    hint:SetWide(s(160))

    -- AAR outcome.
    ocRow = vgui.Create("DPanel", parent)
    ocRow:Dock(TOP)
    ocRow:SetTall(s(30))
    ocRow:DockMargin(0, 0, 0, s(6))
    ocRow.Paint = nil
    local ocs = k.Choices(ocRow, { { 1, OUTCOMES[1] }, { 2, OUTCOMES[2] }, { 3, OUTCOMES[3] } }, function() return oc end, function(v) oc = v end)
    ocs:Dock(LEFT)
    ocs:SetWide(s(360))
    relayout()

    local foot = vgui.Create("DPanel", parent)
    foot:Dock(BOTTOM)
    foot:SetTall(s(32))
    foot:DockMargin(0, s(8), 0, 0)
    foot.Paint = nil
    local body = k.TextEntry(parent, "Write here…")
    body:SetMultiline(true)
    body:Dock(FILL)
    if p and p.id then body:SetText(boardBodies[p.id] or "") else body:SetText(p and p.body or "") end
    local save = k.Button(foot, "Post", function()
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
        send("dp.bsave", function()
            net.WriteUInt(p and p.id or 0, 16)
            net.WriteUInt(sec, 3)
            net.WriteString(string.sub(title:GetText() or "", 1, 400))
            net.WriteString(string.sub(body:GetText() or "", 1, 8000))
            net.WriteUInt(math.max(0, t), 32)
            net.WriteUInt(sec == 4 and oc or 0, 2)
            net.WriteUInt(sec == 4 and ses or 0, 16)
        end)
        editing = nil
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(120))
    local cancel = k.Button(foot, "Cancel", function()
        editing = nil
        build()
    end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(120))
    cancel:DockMargin(0, 0, s(6), 0)
end

-- Sign-ups and check-in for a session (the data comes with its text).
function sessionStrip(parent, p)
    local k = K()
    local s = k.S
    local m = boardMeta[p.id]
    if not m then return end
    local names = { {}, {}, {} }
    for _, r in ipairs(m.rv) do
        if names[r.s] then table.insert(names[r.s], r.name) end
    end
    if unit and unit.member then
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:SetTall(s(28))
        row:DockMargin(0, 0, 0, s(6))
        row.Paint = nil
        for i, txt in ipairs(RSVP) do
            local b = k.Button(row, txt .. " (" .. #names[i] .. ")", function()
                send("dp.ursvp", function()
                    net.WriteUInt(p.id, 16)
                    net.WriteUInt(i, 2)
                end)
            end, { small = true, selected = function() return m.mine == i end })
            b:Dock(LEFT)
            b:SetWide(s(130))
            b:DockMargin(0, 0, s(6), 0)
        end
        local open = os.time() >= p.at - 15 * 60 and os.time() <= p.at + 3600
        local ci = k.Button(row, m.checked and "Checked in" or "Check in", function()
            send("dp.ucheck", function() net.WriteUInt(p.id, 16) end)
        end, { small = true, accent = true, enabled = not m.checked and open,
            tooltip = "Opens 15 minutes before the session, closes an hour after it starts" })
        ci:Dock(RIGHT)
        ci:SetWide(s(130))
    end
    for i, txt in ipairs(RSVP) do
        if #names[i] > 0 then
            label(parent, txt .. ": " .. table.concat(names[i], ", "), nil, 12)
        end
    end
    if #m.ci > 0 then
        local l = label(parent, "Checked in (" .. #m.ci .. "): " .. table.concat(m.ci, ", "), k.C.good, 12)
        l:DockMargin(0, 0, 0, s(6))
    end
end

-- The battalion info: one text, edited over time.
local function infoReader(parent)
    local k = K()
    local s = k.S
    local info = board.info
    if editing == "info" then
        local h = k.Heading(parent, "Edit battalion info")
        h:Dock(TOP)
        local hint = label(parent, "Whatever is useful right now: who leads what, SOPs, callsigns, what to bring. Everyone reads it here and on their datapad.")
        hint:DockMargin(0, s(4), 0, s(8))
        local foot = vgui.Create("DPanel", parent)
        foot:Dock(BOTTOM)
        foot:SetTall(s(32))
        foot:DockMargin(0, s(8), 0, 0)
        foot.Paint = nil
        local te = k.TextEntry(parent, "Battalion info…")
        te:SetMultiline(true)
        te:Dock(FILL)
        te:SetText(info.txt)
        local save = k.Button(foot, "Save", function()
            send("dp.binfo", function() net.WriteString(string.sub(te:GetText() or "", 1, 12000)) end)
            editing = nil
        end, { accent = true })
        save:Dock(RIGHT)
        save:SetWide(s(120))
        local cancel = k.Button(foot, "Cancel", function()
            editing = nil
            build()
        end)
        cancel:Dock(RIGHT)
        cancel:SetWide(s(120))
        cancel:DockMargin(0, 0, s(6), 0)
        return
    end
    local h = k.Heading(parent, "Battalion info")
    h:Dock(TOP)
    local by = label(parent, info.txt ~= "" and ("Last edited by " .. info.by .. "  ·  " .. when(info.t)) or "Nothing written yet.")
    by:DockMargin(0, s(4), 0, s(8))
    if board.canPost then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local b = k.Button(row, "Edit", function()
            editing = "info"
            build()
        end, { small = true, accent = true })
        b:Dock(LEFT)
        b:SetWide(s(110))
    end
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, info.txt, 15, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
end

local function boardReader(parent)
    local k = K()
    local s = k.S
    if boardSel == "info" then infoReader(parent) return end
    local p = boardSel and postById(boardSel)
    if not p then
        label(parent, (board.canPost or board.canAAR) and "Pick a post, or write a new one." or "Pick a post to read it.")
        return
    end
    local h = k.Heading(parent, (p.pin and "★ " or "") .. p.title)
    h:Dock(TOP)
    local by = label(parent, SECTIONS[p.sec] .. "  ·  " .. postSub(p))
    by:DockMargin(0, s(4), 0, s(8))
    if p.sec == 4 and p.ses > 0 then
        local ses = postById(p.ses)
        if ses then
            local link = k.Button(parent, "Report on: " .. ses.title, function()
                boardSel = ses.id
                build()
            end, { small = true, align = "left" })
            link:Dock(TOP)
            link:DockMargin(0, 0, 0, s(6))
        end
    end
    if p.sec == 3 then sessionStrip(parent, p) end
    local past = p.sec == 3 and p.at > 0 and p.at < os.time()
    if canChange(p) or (past and board.canAAR) then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local function btn(text, fn, opts, wide)
            local b = k.Button(row, text, fn, opts or { small = true })
            b:Dock(LEFT)
            b:SetWide(s(wide or 110))
            b:DockMargin(0, 0, s(6), 0)
        end
        if past and board.canAAR then
            btn("Write AAR", function()
                editing = aarDraft(p)
                build()
            end, { small = true, accent = true }, 130)
        end
        if canChange(p) then
            btn("Edit", function()
                editing = p.id
                build()
            end)
            if board.canPost then
                btn(p.pin and "Unpin" or "Pin", function() send("dp.bpin", function() net.WriteUInt(p.id, 16) end) end)
            end
            btn("Delete", function()
                send("dp.bdel", function() net.WriteUInt(p.id, 16) end)
                boardSel = nil
            end, { small = true, danger = true })
        end
    end
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, boardBodies[p.id] or "Loading…", 14, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
    if not boardBodies[p.id] then send("dp.bget", function() net.WriteUInt(p.id, 16) end) end
end

local function boardTab(body)
    local k = K()
    local s = k.S
    if not board then
        label(body, "Loading the board…")
        board = { posts = {}, canPost = false, canAAR = false, loading = true }
        send("dp.bopen")
        return
    end
    if board.loading then
        label(body, "Loading the board…")
        return
    end
    local left, right = columns(body)
    if board.canPost or board.canAAR then
        local new = k.Button(left, board.canPost and "New post" or "New after-action report", function()
            editing = board.canPost and 0 or { sec = 4, oc = 1, ses = 0, title = "AAR: ", body = "" }
            build()
        end, { small = true, accent = true })
        new:Dock(TOP)
        new:DockMargin(0, 0, s(8), s(8))
    end
    local sp = k.Scroll(left)
    sp:Dock(FILL)

    -- Battalion info first.
    listRow(sp, "Battalion info", board.info.txt ~= "" and ("Edited " .. when(board.info.t) .. " by " .. board.info.by) or "Not written yet",
        function() return boardSel == "info" end, function()
            boardSel = "info"
            editing = nil
            build()
        end, "Info")

    -- Group: pinned, upcoming sessions (soonest first), AARs, archive, old Info/Plans posts.
    local now = os.time()
    local groups = { { "Pinned", {} }, { "Upcoming sessions", {} }, { "Older posts", {} }, { "Older posts", {} },
        { "After-action reports", {} }, { "Past sessions", {} } }
    for _, p in ipairs(board.posts) do
        local g
        if p.pin then g = 1
        elseif p.sec == 3 then g = p.at > now - 3600 and 2 or 6   -- a session stays "upcoming" for its first hour
        elseif p.sec == 4 then g = 5
        else g = 3 end
        table.insert(groups[g][2], p)
    end
    table.sort(groups[2][2], function(a, b) return a.at < b.at end)
    table.sort(groups[6][2], function(a, b) return a.at > b.at end)
    -- Older posts last.
    groups = { groups[1], groups[2], groups[5], groups[6], groups[3] }
    local any = false
    for _, g in ipairs(groups) do
        if #g[2] > 0 then
            any = true
            local hd = k.Heading(sp, g[1])
            hd:Dock(TOP)
            hd:DockMargin(0, s(4), s(8), s(4))
            for _, p in ipairs(g[2]) do
                listRow(sp, p.title, postSub(p), function() return boardSel == p.id end, function()
                    boardSel = p.id
                    editing = nil
                    build()
                end, postTag(p))
            end
        end
    end
    if editing == "info" then
        infoReader(right)
    elseif editing then
        if istable(editing) then
            editor(right, editing)
        else
            local p = editing ~= 0 and postById(editing) or nil
            if editing ~= 0 and not p then
                editing = nil   -- deleted meanwhile
                boardReader(right)
            else
                editor(right, p)
            end
        end
    else
        boardReader(right)
    end
end

--------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------

local function statsTab(body)
    local k = K()
    local s = k.S
    local bar = vgui.Create("DPanel", body)
    bar:Dock(TOP)
    bar:SetTall(s(30))
    bar:DockMargin(0, 0, 0, s(10))
    bar.Paint = nil
    local opts = {}
    for i, n in ipairs(PERIOD_NAMES) do opts[i] = { i, n } end
    local ch = k.Choices(bar, opts, function() return statsPeriod end, function(v)
        statsPeriod = v
        statsData = nil
        build()
    end)
    ch:Dock(LEFT)
    ch:SetWide(s(560))

    if not statsData or statsData.period ~= statsPeriod then
        label(body, "Loading…")
        if not (statsData and statsData.pending == statsPeriod) then
            statsData = { pending = statsPeriod }
            send("dp.stats", function() net.WriteUInt(statsPeriod, 3) end)
        end
        return
    end

    local STAT_KEYS = shownKeys()   -- (this tab only)

    -- Totals: one tile per stat.
    local tiles = vgui.Create("DPanel", body)
    tiles:Dock(TOP)
    tiles:SetTall(s(64))
    tiles:DockMargin(0, 0, 0, s(12))
    function tiles:Paint(w, h)
        local n = #STAT_KEYS
        local gap = s(6)
        local tw = (w - gap * (n - 1)) / n
        for i, key in ipairs(STAT_KEYS) do
            local x = (i - 1) * (tw + gap)
            k.Plate(x, 0, tw, h, {})
            draw.SimpleText(statText(key, statsData.totals[key]), k.Font(20, 700), x + tw * 0.5, h * 0.42, k.C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            k.Caps(STAT_NAMES[key], x + tw * 0.5, h * 0.78, k.C.label, TEXT_ALIGN_CENTER)
        end
    end

    -- Members: click a column to sort by it.
    local head = vgui.Create("DPanel", body)
    head:Dock(TOP)
    head:SetTall(s(26))
    head.Paint = nil
    local nameW = s(200)
    local function colX(i, w) return nameW + (i - 1) * ((w - nameW) / #STAT_KEYS) end
    local nameBtn = vgui.Create("DButton", head)
    nameBtn:SetText("")
    nameBtn:SetPos(0, 0)
    nameBtn:SetSize(nameW, s(26))
    nameBtn.Paint = function(_, w, h)
        k.Caps("Member", s(8), h * 0.5, statsSort == "name" and k.C.accent or k.C.label)
        return true
    end
    nameBtn.DoClick = function()
        statsSort = "name"
        build()
    end
    function head:PerformLayout(w, h)
        for i, key in ipairs(STAT_KEYS) do
            local b = self["c" .. i]
            if not IsValid(b) then
                b = vgui.Create("DButton", self)
                b:SetText("")
                b.Paint = function(_, bw, bh)
                    k.Caps(STAT_NAMES[key], bw - s(8), bh * 0.5, statsSort == key and k.C.accent or k.C.label, TEXT_ALIGN_RIGHT)
                    return true
                end
                b.DoClick = function()
                    statsSort = key
                    build()
                end
                self["c" .. i] = b
            end
            local x0, x1 = colX(i, w), colX(i + 1, w)
            b:SetPos(x0, 0)
            b:SetSize(x1 - x0, h)
        end
    end

    local rows = {}
    for _, m in ipairs(statsData.members) do rows[#rows + 1] = m end
    table.sort(rows, function(a, b)
        if statsSort == "name" then return string.lower(a.name) < string.lower(b.name) end
        return (a[statsSort] or 0) > (b[statsSort] or 0)
    end)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #rows == 0 then label(sp, "Nothing recorded for this period yet.") end
    for i, m in ipairs(rows) do
        local r = vgui.Create("DPanel", sp)
        r:Dock(TOP)
        r:SetTall(s(26))
        r:DockMargin(0, 0, s(8), s(2))
        function r:Paint(w, h)
            k.SetCol(i % 2 == 0 and k.C.rowAlt or k.C.row)
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(k.Fit(m.name, k.Font(13, 600), nameW - s(12)), k.Font(13, 600), s(8), h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            for c, key in ipairs(STAT_KEYS) do
                draw.SimpleText(statText(key, m[key]), k.Font(13), colX(c + 1, w) - s(8), h * 0.5, statsSort == key and k.C.text or k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end
end

--------------------------------------------------------------------------
-- Unit: orders, leave, applications (sv_60_unit)
--------------------------------------------------------------------------

local function askUnit()
    if unit or unitAsked == term.ent then return end
    local ent = term.ent
    unitAsked = ent
    send("dp.uopen")
    -- No answer (walked away mid-check): allow asking again.
    timer.Simple(5, function() if unitAsked == ent and not unit then unitAsked = nil end end)
end

local function footRow(parent)
    local s = K().S
    local row = vgui.Create("DPanel", parent)
    row:Dock(BOTTOM)
    row:SetTall(s(32))
    row:DockMargin(0, s(8), 0, 0)
    row.Paint = nil
    return row
end

local function footButton(row, text, fn, opts)
    local s = K().S
    local b = K().Button(row, text, fn, opts)
    b:Dock(RIGHT)
    b:SetWide(s(150))
    b:DockMargin(s(6), 0, 0, 0)
    return b
end

-- "YYYY-MM-DD" -> os.time (start or end of that day), or nil.
local function parseDate(txt, endOfDay)
    local y, mo, d = string.match(txt or "", "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
    if not y then return nil end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = endOfDay and 23 or 0, min = endOfDay and 59 or 0, sec = 0 })
end

-- Members for picking (the Personnel list).
local function wantPeople()
    if people or peopleAsked then return end
    peopleAsked = true
    send("dp.plist")
    timer.Simple(5, function() if not people then peopleAsked = nil end end)
end

local function orderById(id)
    for _, o in ipairs(unit.orders) do
        if o.id == id then return o end
    end
end

local function orderEditor(body)
    local k = K()
    local s = k.S
    local d = orderDraft
    local h = k.Heading(body, "New order")
    h:Dock(TOP)
    local title = k.TextEntry(body, "What (short)")
    title:Dock(TOP)
    title:DockMargin(0, s(8), 0, s(6))
    title:SetText(d.ti)
    function title:OnChange() d.ti = self:GetText() or "" end
    local who = vgui.Create("DPanel", body)
    who:Dock(TOP)
    who:SetTall(s(30))
    who:DockMargin(0, 0, 0, s(6))
    who.Paint = nil
    local ch = k.Choices(who, { { true, "Whole battalion" }, { false, "Specific members" } }, function() return d.all end, function(v)
        d.all = v
        build()
    end)
    ch:Dock(LEFT)
    ch:SetWide(s(330))
    local foot = footRow(body)
    footButton(foot, "Issue order", function()
        local ids = {}
        if not d.all then
            for id in pairs(d.sel) do ids[#ids + 1] = id end
            if #ids == 0 then
                Derma_Message("Pick at least one member, or order the whole battalion.", "Orders", "OK")
                return
            end
        end
        send("dp.uorder", function()
            net.WriteString(string.sub(d.ti or "", 1, 200))
            net.WriteString(string.sub(d.b or "", 1, 1200))
            local n = math.min(#ids, 127)
            net.WriteUInt(n, 7)
            for i = 1, n do net.WriteString(ids[i]) end
        end)
        orderDraft = nil
        build()
    end, { accent = true })
    footButton(foot, "Cancel", function()
        orderDraft = nil
        build()
    end)
    -- Member picker.
    if not d.all then
        wantPeople()
        local pick = vgui.Create("DPanel", body)
        pick:Dock(RIGHT)
        pick:SetWide(s(320))
        pick:DockMargin(s(10), 0, 0, 0)
        pick.Paint = nil
        local n = 0
        for _ in pairs(d.sel) do n = n + 1 end
        local ph = k.Heading(pick, "Ordered (" .. n .. ")")
        ph:Dock(TOP)
        local sp = k.Scroll(pick)
        sp:Dock(FILL)
        if not people then label(sp, "Loading members…") end
        for _, m in ipairs(people or {}) do
            local b = k.Button(sp, m.name, function()
                d.sel[m.id] = not d.sel[m.id] or nil
                build()
            end, { small = true, align = "left", selected = function() return d.sel[m.id] ~= nil end })
            b:Dock(TOP)
            b:DockMargin(0, 0, s(8), s(3))
        end
    end
    local txt = k.TextEntry(body, "Details: where, when, how…")
    txt:SetMultiline(true)
    txt:Dock(FILL)
    txt:SetText(d.b)
    function txt:OnChange() d.b = self:GetText() or "" end
end

local function ordersTab(body)
    local k = K()
    local s = k.S
    if not unit then label(body, "Loading…") return end
    if orderDraft and unit.manager then orderEditor(body) return end
    local left, right = columns(body)
    if unit.manager then
        local new = k.Button(left, "New order", function()
            orderDraft = { ti = "", b = "", all = true, sel = {} }
            build()
        end, { small = true, accent = true })
        new:Dock(TOP)
        new:DockMargin(0, 0, s(8), s(8))
    end
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #unit.orders == 0 then label(sp, "No orders yet.") end
    local lastOpen
    for _, o in ipairs(unit.orders) do
        local open = o.st <= 2
        if lastOpen ~= open then
            local hd = k.Heading(sp, open and "Open orders" or "Closed")
            hd:Dock(TOP)
            hd:DockMargin(0, s(4), s(8), s(4))
            lastOpen = open
        end
        listRow(sp, o.title, D.OrderSub(o), function() return orderSel == o.id end, function()
            orderSel = o.id
            build()
        end, D.ORDER_TAG[o.st])
    end

    local o = orderSel and orderById(orderSel)
    if not o then
        label(right, unit.manager and "Pick an order, or issue a new one." or "Pick an order to read it.")
        return
    end
    local h = k.Heading(right, o.title)
    h:Dock(TOP)
    local by = label(right, "From " .. o.by .. "  ·  " .. when(o.t))
    by:DockMargin(0, s(4), 0, s(2))
    label(right, "To: " .. D.OrderTo(o), k.C.text)
    local stl = label(right, "Status: " .. D.ORDER_STATUS[o.st] .. (o.sb ~= "" and ("  (" .. o.sb .. ", " .. when(o.stt) .. ")") or ""),
        D.OrderColor(o.st))
    stl:DockMargin(0, s(2), 0, s(8))
    if o.canSet or unit.manager then
        local foot = footRow(right)
        footButton(foot, "Set status ▾", function()
            D.OrderStatusMenu(o, unit.manager, function(st)
                send("dp.ustatus", function()
                    net.WriteUInt(o.id, 16)
                    net.WriteUInt(st, 3)
                end)
            end)
        end, { accent = true })
        if unit.manager then
            footButton(foot, "Delete", function()
                send("dp.uodel", function() net.WriteUInt(o.id, 16) end)
                orderSel = nil
            end, { danger = true })
        end
    end
    local tsp = k.Scroll(right)
    tsp:Dock(FILL)
    local t = k.Label(tsp, o.text ~= "" and o.text or "(no details)", 15, 400, k.C.text)
    t:Dock(TOP)
    t:DockMargin(0, 0, s(10), 0)
end

local function leaveTab(body)
    local k = K()
    local s = k.S
    if not unit then label(body, "Loading…") return end
    local left, right = columns(body)
    local h = k.Heading(left, "On LOA (" .. #unit.leave .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #unit.leave == 0 then label(sp, "Nobody is on LOA.") end
    local now = os.time()
    for _, e in ipairs(unit.leave) do
        local range = os.date("%d %b", e.from) .. " – " .. os.date("%d %b %Y", e.to) .. (e.from <= now and "  (now)" or "")
        local r = k.Row(sp, e.name, range .. (e.why ~= "" and ("  ·  " .. e.why) or ""))
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        if e.mine or unit.manager then
            r.right:SetWide(s(100))
            local b = k.Button(r.right, e.mine and "Cancel" or "Remove", function()
                send("dp.uloadel", function() net.WriteUInt(e.id, 16) end)
            end, { small = true, danger = true })
            b:Dock(FILL)
        end
    end

    local rh = k.Heading(right, "File a leave of absence")
    rh:Dock(TOP)
    if not unit.member then
        label(right, "Only members of the battalion can file leave.")
        return
    end
    local hint = label(right, "Going away for a while? Your battalion sees it here and on the roster. A new one replaces your old one (at most 120 days).")
    hint:DockMargin(0, s(4), 0, s(10))
    local function dateRow(title, t)
        local r = k.Row(right, title, "YYYY-MM-DD")
        r:Dock(TOP)
        r:DockMargin(0, 0, 0, s(6))
        r.right:SetWide(s(160))
        local e = k.TextEntry(r.right, "YYYY-MM-DD")
        e:Dock(FILL)
        e:SetText(os.date("%Y-%m-%d", t))
        return e
    end
    local from = dateRow("From", now)
    local to = dateRow("Until", now + 7 * 86400)
    local why = k.TextEntry(right, "Reason (optional)")
    why:Dock(TOP)
    why:DockMargin(0, 0, 0, s(10))
    local go = k.Button(right, "File LOA", function()
        local a, b = parseDate(from:GetText(), false), parseDate(to:GetText(), true)
        if not (a and b) or b < a then
            Derma_Message("Write the dates as YYYY-MM-DD, with the end after the start.", "LOA", "OK")
            return
        end
        send("dp.uloa", function()
            net.WriteUInt(math.max(0, a), 32)
            net.WriteUInt(math.max(0, b), 32)
            net.WriteString(string.sub(why:GetText() or "", 1, 200))
        end)
    end, { accent = true })
    go:Dock(TOP)
end

local function appById(id)
    for _, a in ipairs(unit.apps) do
        if a.id == id then return a end
    end
end

local function appsTab(body)
    local k = K()
    local s = k.S
    if not unit then label(body, "Loading…") return end
    local left, right = columns(body)
    local h = k.Heading(left, "Applications")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #unit.apps == 0 then label(sp, "No applications yet.") end
    for _, a in ipairs(unit.apps) do
        local sub = APP_STATUS[a.st] .. (a.by ~= "" and (" by " .. a.by) or "") .. "  ·  " .. when(a.t)
        listRow(sp, a.name, sub, function() return appSel == a.id end, function()
            appSel = a.id
            build()
        end, a.st == 0 and "New" or nil)
    end

    local a = appSel and appById(appSel)
    if not a then
        label(right, "Pick an application to read it. Applying is optional: you can still add a trooper straight from the Battalion page.")
        return
    end
    local rh = k.Heading(right, a.name)
    rh:Dock(TOP)
    local by = label(right, APP_STATUS[a.st] .. (a.by ~= "" and (" by " .. a.by) or "") .. "  ·  applied " .. when(a.t))
    by:DockMargin(0, s(4), 0, s(8))
    if a.st == 0 then
        local foot = footRow(right)
        local function decide(ok)
            send("dp.udecide", function()
                net.WriteUInt(a.id, 16)
                net.WriteBool(ok)
            end)
        end
        footButton(foot, "Accept", function() decide(true) end, { accent = true })
        footButton(foot, "Decline", function() decide(false) end, { danger = true })
        local note = k.Label(foot, "Accepted troopers get a prompt to join (or turn it down).", 12, 400, k.C.textDim)
        note:Dock(FILL)
    end
    local tsp = k.Scroll(right)
    tsp:Dock(FILL)
    local function sub(text)
        local hd = k.Heading(tsp, text)
        hd:Dock(TOP)
        hd:DockMargin(0, s(8), s(10), s(4))
    end
    -- The application itself, in a box so it stands out.
    sub("Application")
    local box = vgui.Create("DPanel", tsp)
    box:Dock(TOP)
    box:DockMargin(0, 0, s(10), 0)
    box:DockPadding(s(12), s(10), s(12), s(10))
    function box:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(k.C.accent)
        surface.DrawRect(0, 0, s(3), h)
    end
    local t = k.Label(box, a.txt, 15, 400, k.C.text)
    t:Dock(TOP)
    function box:PerformLayout(w, h)
        local want = t:GetTall() + s(20)
        if math.abs(want - h) > 1 then self:SetTall(want) end
    end

    -- Their record (asked for once per application).
    local info = appInfo[a.id]
    if not info then
        if appAsked ~= a.id then
            appAsked = a.id
            send("dp.uappget", function() net.WriteUInt(a.id, 16) end)
        end
        label(tsp, "Loading their record…")
        return
    end
    sub("Service record (all time)")
    local parts = {}
    for _, key in ipairs({ "mi", "ev", "at", "kd", "kp", "de", "rv", "he", "ar" }) do
        parts[#parts + 1] = (key == "ar" and "Arrests made" or STAT_NAMES[key]) .. " " .. statText(key, info.stats[key])
    end
    local st = label(tsp, table.concat(parts, "   ·   "), k.C.text, 13)
    st:DockMargin(0, 0, s(10), s(4))
    label(tsp, "Qualifications: " .. (#info.quals > 0 and table.concat(info.quals, ", ") or "none"), k.C.text, 13)
    label(tsp, info.coms .. " commendation" .. (info.coms == 1 and "" or "s") .. "  ·  " .. info.strikes .. " active strike" .. (info.strikes == 1 and "" or "s"),
        info.strikes > 0 and k.C.bad or k.C.text, 13)
    sub("Arrest record (" .. #info.arrests .. ")")
    if #info.arrests == 0 then label(tsp, "Never arrested.", k.C.good, 13) end
    for _, j in ipairs(info.arrests) do
        local l = label(tsp, os.date("%d %b %Y", j.t) .. "  ·  " .. j.min .. " min  ·  by " .. j.by, nil, 12)
        l:DockMargin(0, s(4), s(10), 0)
        local w = k.Label(tsp, j.why ~= "" and j.why or "No reason given", 14, 500, k.C.bad)
        w:Dock(TOP)
        w:DockMargin(0, 0, s(10), s(2))
    end
end

-- For troopers outside the battalion: apply, or see how it went.
local function applyPanel(body)
    local k = K()
    local s = k.S
    if not unit then
        askUnit()
        label(body, "Loading…")
        return
    end
    local h = k.Heading(body, "Join the " .. term.bn)
    h:Dock(TOP)
    h:DockMargin(0, s(16), 0, s(6))
    if unit.myBn == term.bn and unit.mySt == 1 then
        label(body, "Your application was accepted.", k.C.good, 14)
        local row = vgui.Create("DPanel", body)
        row:Dock(TOP)
        row:SetTall(s(34))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local function answer(join)
            Rhylib.Net.Start("dp.uanswer")
            net.WriteBool(join)
            net.SendToServer()
            unit = nil
            unitAsked = nil
            timer.Simple(0.5, function() if IsValid(panel) then build() end end)
        end
        local j = k.Button(row, "Join battalion", function() answer(true) end, { accent = true })
        j:Dock(LEFT)
        j:SetWide(s(180))
        local r = k.Button(row, "Reject", function() answer(false) end, { danger = true })
        r:Dock(LEFT)
        r:SetWide(s(140))
        r:DockMargin(s(6), 0, 0, 0)
        return
    end
    if unit.myBn ~= "" and unit.myBn ~= term.bn and unit.mySt == 1 then
        label(body, "The " .. unit.myBn .. " accepted your application. Answer that first (at their computer, or the prompt when you join).", nil, 14)
        return
    end
    if unit.myBn ~= "" and unit.mySt == 0 then
        label(body, unit.myBn == term.bn and "Your application is pending. Check back here for its status."
            or ("You already have a pending application with the " .. unit.myBn .. "."), nil, 14)
        if unit.myBn == term.bn then
            local w = k.Button(body, "Withdraw application", function()
                send("dp.uwithdraw")
                unit, unitAsked = nil, nil
            end, { small = true, danger = true })
            w:Dock(TOP)
            w:SetWide(s(220))
            w:DockMargin(0, s(8), 0, 0)
        end
        return
    end
    if not unit.canApply then
        label(body, "Only clone troopers without a battalion can apply.", nil, 14)
        return
    end
    local hint = label(body, "Tell the battalion about yourself. Their sergeants and up will see it here. Applying is optional: an NCO can also add you straight away.")
    hint:DockMargin(0, 0, 0, s(8))
    local foot = footRow(body)
    local txt = k.TextEntry(body, "Why do you want to join?")
    txt:SetMultiline(true)
    txt:Dock(FILL)
    footButton(foot, "Apply", function()
        send("dp.uapply", function() net.WriteString(string.sub(txt:GetText() or "", 1, 1200)) end)
        unit = nil
        unitAsked = nil
    end, { accent = true })
end

--------------------------------------------------------------------------
-- Personnel files (sv_70_personnel)
--------------------------------------------------------------------------

-- A boxed entry: dim header line, text, optional button on the right.
local function entry(parent, head, text, btnText, btnFn, stripe)
    local k = K()
    local s = k.S
    local e = vgui.Create("DPanel", parent)
    e:Dock(TOP)
    e:DockMargin(0, 0, s(8), s(4))
    e:DockPadding(s(12), s(6), s(10), s(6))
    e:SetTall(s(48))
    function e:Paint(w, h)
        k.SetCol(k.C.row)
        surface.DrawRect(0, 0, w, h)
        if stripe then
            k.SetCol(stripe)
            surface.DrawRect(0, 0, s(3), h)
        end
    end
    if btnText then
        local holder = vgui.Create("DPanel", e)
        holder:Dock(RIGHT)
        holder:SetWide(s(96))
        holder:DockMargin(s(8), 0, 0, 0)
        holder.Paint = nil
        local b = k.Button(holder, btnText, btnFn, { small = true, danger = true })
        b:Dock(TOP)
    end
    local hl = k.Label(e, head, 12, 400, k.C.textDim)
    hl:Dock(TOP)
    local tl = k.Label(e, text, 14, 400, k.C.text)
    tl:Dock(TOP)
    function e:PerformLayout(w, h)
        local want = s(12) + hl:GetTall() + tl:GetTall()
        if math.abs(want - h) > 1 then self:SetTall(want) end
    end
    return e
end

-- A heading with an optional button at its right end.
local function headRow(parent, text, btnText, btnFn)
    local k = K()
    local s = k.S
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(s(32))
    row:DockMargin(0, s(10), s(8), s(6))
    row.Paint = nil
    if btnText then
        local b = k.Button(row, btnText, btnFn, { small = true, accent = true })
        b:Dock(RIGHT)
        b:SetWide(s(150))
        b:DockMargin(s(8), s(3), 0, s(3))
    end
    local h = k.Heading(row, text)
    h:Dock(FILL)
    return row
end

local pMissing   -- a file that didn't come (left the battalion, ...)
local function askFile(id)
    if pAsked == id or pMissing == id then return end
    pAsked = id
    send("dp.pget", function() net.WriteString(id) end)
    timer.Simple(5, function()
        if pAsked == id then
            pAsked, pMissing = nil, id
            if IsValid(panel) and tab == "people" then build() end
        end
    end)
end

local function personFile(parent)
    local k = K()
    local s = k.S
    if not personSel then
        label(parent, "Pick a member to open their file.")
        return
    end
    local f = pfile and pfile.id == personSel and pfile
    if not f and pMissing == personSel then
        label(parent, "This file isn't available (no longer in the battalion?).")
        return
    end
    if not f then
        label(parent, "Loading…")
        askFile(personSel)
        return
    end
    local h = k.Heading(parent, f.name)
    h:Dock(TOP)
    local sub = label(parent, f.rank .. "  ·  " .. (f.on and "online now" or ("last seen " .. (f.seen > 0 and when(f.seen) or "never"))))
    sub:DockMargin(0, s(4), 0, s(6))
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local id = f.id

    -- Service record (all time, this battalion).
    headRow(sp, "Service record")
    local parts = {}
    for _, key in ipairs({ "mi", "ev", "at", "kd", "kp", "de", "rv", "he", D.IsMPBattalion(term.bn) and "ar" or "jd" }) do
        parts[#parts + 1] = STAT_NAMES[key] .. " " .. statText(key, f.stats[key])
    end
    local st = label(sp, table.concat(parts, "   ·   "), k.C.text, 13)
    st:DockMargin(0, 0, s(8), 0)

    -- Qualifications.
    headRow(sp, "Qualifications")
    if f.discipline then
        local grid = vgui.Create("DPanel", sp)
        grid:Dock(TOP)
        grid:DockMargin(0, 0, s(8), 0)
        grid.Paint = nil
        local btns = {}
        for _, q in ipairs(f.quals) do
            btns[#btns + 1] = k.Button(grid, q.name, function()
                send("dp.pqual", function()
                    net.WriteString(id)
                    net.WriteString(q.id)
                    net.WriteBool(not q.has)
                end)
            end, { small = true, selected = function() return q.has end,
                tooltip = q.has and "Qualified. Click to remove." or "Not qualified. Click to qualify." })
        end
        function grid:PerformLayout(w)
            local cols, gap, bh = 3, s(6), s(26)
            local bw = (w - gap * (cols - 1)) / cols
            for i, b in ipairs(btns) do
                b:SetPos(((i - 1) % cols) * (bw + gap), math.floor((i - 1) / cols) * (bh + gap))
                b:SetSize(bw, bh)
            end
            local want = math.ceil(#btns / cols) * (bh + gap)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
        local hint = label(sp, "Highlighted ones are held. Click to give or take one; they unlock armoury gear and jobs.", nil, 12)
        hint:DockMargin(0, s(4), s(8), 0)
    else
        local held = {}
        for _, q in ipairs(f.quals) do
            if q.has then held[#held + 1] = q.name end
        end
        label(sp, #held > 0 and table.concat(held, ", ") or "None yet.", #held > 0 and k.C.text or nil, 13)
    end

    -- Commendations.
    headRow(sp, "Commendations (" .. #f.coms .. ")", f.commend and "Commend" or nil, function()
        k.Prompt("Commendation", "What is " .. f.name .. " commended for?", "", function(t)
            send("dp.pcom", function()
                net.WriteString(id)
                net.WriteString(string.sub(t or "", 1, 600))
            end)
        end)
    end)
    if #f.coms == 0 then label(sp, "None yet.") end
    for _, x in ipairs(f.coms) do
        entry(sp, when(x.t) .. "  ·  " .. x.by .. (x.bn ~= "" and ("  ·  " .. x.bn) or ""), x.txt,
            f.discipline and "Remove" or nil, function()
                send("dp.pdel", function()
                    net.WriteString(id)
                    net.WriteUInt(0, 1)
                    net.WriteUInt(x.id, 16)
                end)
            end, k.C.good)
    end

    -- Strikes.
    if f.seeStrikes then
        local now = os.time()
        local active = 0
        for _, x in ipairs(f.strikes) do
            if x.exp > now then active = active + 1 end
        end
        headRow(sp, "Strikes (" .. active .. " active)", f.discipline and "Give strike" or nil, function()
            k.Prompt("Strike", "Why does " .. f.name .. " get a strike?", "", function(t)
                send("dp.pstrike", function()
                    net.WriteString(id)
                    net.WriteString(string.sub(t or "", 1, 600))
                end)
            end)
        end)
        if #f.strikes == 0 then label(sp, "None.") end
        for _, x in ipairs(f.strikes) do
            local on = x.exp > now
            entry(sp, when(x.t) .. "  ·  " .. x.by .. "  ·  " .. (on and ("active until " .. os.date("%d %b", x.exp)) or "expired"), x.txt,
                f.discipline and "Pardon" or nil, function()
                    send("dp.pdel", function()
                        net.WriteString(id)
                        net.WriteUInt(1, 1)
                        net.WriteUInt(x.id, 16)
                    end)
                end, on and k.C.bad or nil)
        end
    end

    -- NCO notes.
    if f.seeNotes then
        headRow(sp, "NCO notes", (f.discipline and not notesEdit) and "Edit notes" or nil, function()
            notesEdit = true
            build()
        end)
        if notesEdit and f.discipline then
            local te = k.TextEntry(sp, "Notes only sergeants and up can read")
            te:SetMultiline(true)
            te:Dock(TOP)
            te:SetTall(s(140))
            te:DockMargin(0, 0, s(8), s(6))
            te:SetText(f.notes.txt)
            local row = vgui.Create("DPanel", sp)
            row:Dock(TOP)
            row:SetTall(s(30))
            row:DockMargin(0, 0, s(8), 0)
            row.Paint = nil
            local save = k.Button(row, "Save notes", function()
                send("dp.pnote", function()
                    net.WriteString(id)
                    net.WriteString(string.sub(te:GetText() or "", 1, 4000))
                end)
                notesEdit = false
            end, { small = true, accent = true })
            save:Dock(RIGHT)
            save:SetWide(s(130))
            local cancel = k.Button(row, "Cancel", function()
                notesEdit = false
                build()
            end, { small = true })
            cancel:Dock(RIGHT)
            cancel:SetWide(s(100))
            cancel:DockMargin(0, 0, s(6), 0)
        elseif f.notes.txt ~= "" then
            entry(sp, "Last edited by " .. f.notes.by .. "  ·  " .. when(f.notes.t), f.notes.txt)
        else
            label(sp, "No notes.")
        end
    end
end

local function personnelTab(body)
    local k = K()
    local s = k.S
    if not people then
        label(body, "Loading…")
        if not peopleAsked then
            peopleAsked = true
            send("dp.plist")
            timer.Simple(5, function()
                if not people and peopleAsked then
                    peopleAsked = nil
                    people = {}   -- no answer: show an empty list
                    if IsValid(panel) and tab == "people" then build() end
                end
            end)
        end
        return
    end
    local left, right = columns(body)
    local h = k.Heading(left, "Members (" .. #people .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #people == 0 then label(sp, "Nobody on the roster yet.") end
    for _, m in ipairs(people) do
        local bits = { m.on and "Online" or ("Seen " .. (m.seen > 0 and os.date("%d %b", m.seen) or "never")) }
        if m.coms > 0 then bits[#bits + 1] = m.coms .. " commendation" .. (m.coms == 1 and "" or "s") end
        if m.strikes > 0 then bits[#bits + 1] = m.strikes .. " strike" .. (m.strikes == 1 and "" or "s") end
        if m.note ~= "" then bits[#bits + 1] = m.note end
        listRow(sp, m.name, table.concat(bits, "  ·  "), function() return personSel == m.id end, function()
            personSel = m.id
            pMissing = nil
            notesEdit = false
            build()
        end, m.strikes >= 3 and "!" or nil)
    end
    personFile(right)
end

--------------------------------------------------------------------------
-- Missions (sv_90_missions): the current one and the archive
--------------------------------------------------------------------------

local function missionsTab(body)
    local k = K()
    local s = k.S
    if not missions then
        label(body, "Loading…")
        if not missionsAsked then
            missionsAsked = true
            send("dp.mlist")
            timer.Simple(5, function() missionsAsked = nil end)
        end
        return
    end
    local left, right = columns(body)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    local cur = missions.current
    if cur then
        local hd = k.Heading(sp, "Current")
        hd:Dock(TOP)
        hd:DockMargin(0, 0, s(8), s(4))
        listRow(sp, cur.title, (cur.active and "Active" or "Posted") .. "  ·  " .. cur.by, function() return missionSel == "cur" end, function()
            missionSel = "cur"
            build()
        end, cur.active and "Live" or "Posted")
    end
    local hd = k.Heading(sp, "Archive (" .. #missions.list .. ")")
    hd:Dock(TOP)
    hd:DockMargin(0, s(4), s(8), s(4))
    if #missions.list == 0 then label(sp, "No finished missions yet.") end
    for _, x in ipairs(missions.list) do
        listRow(sp, x.title, (x.date ~= "" and (x.date .. "  ·  ") or "") .. x.n .. " took part  ·  " .. x.by,
            function() return missionSel == x.id end, function()
                missionSel = x.id
                build()
            end)
    end

    -- Reader.
    if missionSel == "cur" and cur then
        local h = k.Heading(right, cur.title)
        h:Dock(TOP)
        label(right, (cur.date ~= "" and (cur.date .. "  ·  ") or "") .. "by " .. cur.by .. "  ·  " ..
            (cur.active and ("active since " .. when(cur.started)) or "not started"), cur.active and k.C.good or k.C.warn)
        local r = k.Scroll(right)
        r:Dock(FILL)
        local function part(title, txt)
            if txt == "" then return end
            local ph = k.Heading(r, title)
            ph:Dock(TOP)
            ph:DockMargin(0, s(6), s(10), s(4))
            local l = k.Label(r, txt, 14, 400, k.C.text)
            l:Dock(TOP)
            l:DockMargin(0, 0, s(10), 0)
        end
        part("Objectives", cur.obj)
        part("Sub objectives", cur.sub)
        part("Info", cur.info)
        if cur.npeople > 0 then part("Taking part (" .. cur.npeople .. ")", table.concat(cur.people, ", ")) end
        label(r, "Officers run it from their datapad (Mission tab).", nil, 12)
        return
    end
    local x
    for _, it in ipairs(missions.list) do
        if it.id == missionSel then x = it end
    end
    if not x then
        label(right, "Pick a mission to read it. Officers post, start and end missions from their datapad; ended ones land here.")
        return
    end
    local h = k.Heading(right, x.title)
    h:Dock(TOP)
    local by = label(right, (x.date ~= "" and (x.date .. "  ·  ") or "") .. "by " .. x.by .. "  ·  " ..
        (x.started > 0 and (when(x.started) .. " – ") or "not started – ") .. when(x.ended))
    by:DockMargin(0, s(4), 0, s(6))
    if missions.canDelete then
        local foot = footRow(right)
        footButton(foot, "Delete", function()
            send("dp.mdel", function() net.WriteUInt(x.id, 16) end)
            missionSel = nil
        end, { danger = true })
    end
    local full = missionFull[x.id]
    local r = k.Scroll(right)
    r:Dock(FILL)
    if not full then
        label(r, "Loading…")
        if not missionFull["asked" .. x.id] then
            missionFull["asked" .. x.id] = true
            send("dp.mread", function() net.WriteUInt(x.id, 16) end)
        end
        return
    end
    local function part(title, txt)
        if txt == "" then return end
        local ph = k.Heading(r, title)
        ph:Dock(TOP)
        ph:DockMargin(0, s(6), s(10), s(4))
        local l = k.Label(r, txt, 14, 400, k.C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(10), 0)
    end
    part("Objectives", full.obj)
    part("Sub objectives", full.sub)
    part("Info", full.info)
    part("Took part (" .. #full.people .. ")", #full.people > 0 and table.concat(full.people, ", ") or "nobody")
    if full.endedBy ~= "" then label(r, "Ended by " .. full.endedBy, nil, 12) end
end

--------------------------------------------------------------------------
-- Bans
--------------------------------------------------------------------------

local function bansTab(body)
    local k = K()
    local s = k.S
    local h = k.Heading(body, "Banned from uploading")
    h:Dock(TOP)
    local sp = k.Scroll(body)
    sp:Dock(FILL)
    if #term.bans == 0 then label(sp, "Nobody is banned.") end
    for _, b in ipairs(term.bans) do
        local r = k.Row(sp, b.name, b.sid)
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        r.right:SetWide(s(110))
        local u = k.Button(r.right, "Unban", function()
            send("dp.tunban", function() net.WriteString(b.sid) end)
        end, { small = true })
        u:Dock(FILL)
    end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

-- The tabs this player gets: { id, label, build(body), highlight }.
local function tabs()
    local list = { { "logs", term.med and "Records" or "Logs", logsTab } }
    if not term.med then
        list[#list + 1] = { "board", "Board", boardTab }
        list[#list + 1] = { "orders", "Orders", ordersTab }
        list[#list + 1] = { "missions", "Missions", missionsTab }
        list[#list + 1] = { "leave", "LOA", leaveTab }
        list[#list + 1] = { "people", "Personnel", personnelTab }
        list[#list + 1] = { "stats", "Stats", statsTab }
        if unit and unit.manager then
            local n = 0
            for _, a in ipairs(unit.apps) do
                if a.st == 0 then n = n + 1 end
            end
            list[#list + 1] = { "apps", n > 0 and ("Applications (" .. n .. ")") or "Applications", appsTab, n > 0 }
        end
        -- MPs/admins outside the battalion can see it, and can still apply.
        if unit and not unit.member and (unit.canApply or unit.myBn ~= "") then
            list[#list + 1] = { "apply", "Apply", applyPanel }
        end
    end
    if term.mod then list[#list + 1] = { "bans", "Bans (" .. #term.bans .. ")", bansTab } end
    return list
end

function build()
    local k = K()
    if not IsValid(panel) or not term then return end
    local s = k.S
    panel.body:Clear()
    local body = panel.body

    -- Top bar: upload, set battalion; tabs on the right.
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(32))
    top:DockMargin(0, 0, 0, s(10))
    top.Paint = nil
    local function topButton(text, fn, opts, side)
        local b = k.Button(top, text, fn, opts)
        b:Dock(side or LEFT)
        surface.SetFont(k.Font(13, 700))
        b:SetWide(surface.GetTextSize(string.upper(text)) + s(34))
        if side == RIGHT then b:DockMargin(s(6), 0, 0, 0) else b:DockMargin(0, 0, s(6), 0) end
        return b
    end
    local n = term.upload
    topButton(n > 0 and ("Upload " .. n .. " note" .. (n == 1 and "" or "s")) or "Nothing to upload", function()
        send("dp.tup")
    end, { accent = true, enabled = n > 0 and not term.banned })
    if term.admin and not term.med and term.bn == "" then
        topButton("Set battalion", function()
            local m = k.Menu()
            local cats = DarkRP and DarkRP.getCategories and DarkRP.getCategories().jobs or {}
            for _, c in ipairs(cats) do
                if c.name then
                    m:AddOption(c.name, function() send("dp.tset", function() net.WriteString(c.name) end) end)
                end
            end
            m:AddOption("Type a name…", function()
                k.Prompt("Battalion", "The DarkRP job category this computer belongs to", term.bn, function(t)
                    send("dp.tset", function() net.WriteString(t) end)
                end)
            end)
            m:Open()
        end)
    end
    if term.banned then
        local l = k.Label(top, "You're banned from uploading here", 13, 700, k.C.bad)
        l:Dock(LEFT)
        l:DockMargin(s(8), s(8), 0, 0)
        l:SetWide(s(260))
    end

    if not term.med and term.bn == "" then
        label(body, "This computer has no battalion yet. An admin sets it with Set battalion.", k.C.warn, 14)
        return
    end
    if not term.view then
        label(body, term.med and "Medical records are for medics only." or
            ("This is the " .. term.bn .. " battalion's computer. Only its members can read it."), nil, 14)
        if not term.med then applyPanel(body) end
        return
    end
    if not term.med then askUnit() end

    local list = tabs()
    local valid = false
    for _, t in ipairs(list) do
        if t[1] == tab then valid = true end
    end
    if not valid then tab = "logs" end
    for i = #list, 1, -1 do
        local t = list[i]
        topButton(t[2], function()
            tab = t[1]
            build()
        end, { selected = function() return tab == t[1] end, accent = t[4] }, RIGHT)
    end

    for _, t in ipairs(list) do
        if t[1] == tab then t[3](body) end
    end
end

local function open()
    local k = K()
    if not k then return end
    local s = k.S
    if not IsValid(panel) then
        panel = vgui.Create("EditablePanel")
        panel:SetSize(s(1180), s(680))
        panel:Center()
        panel:MakePopup()
        panel:DockPadding(s(14), s(52), s(14), s(14))
        function panel:Paint(w, h)
            if not term then return end
            local title = term.med and "Medical holotable" or (term.bn ~= "" and (term.bn .. " computer") or "Battalion computer")
            -- Fully opaque: the text must stay readable whatever is behind the screen.
            k.Plate(0, 0, w, h, { title = title, sub = term.foreign and "Admin inspection" or (term.med and "Medical records" or "Battalion"),
                ticks = "all", header = s(38), bg = OPAQUE })
        end
        -- The battalion's colour as the accent.
        k.Tint(panel, function() return term and not term.med and D.BnColor(term.bn) or nil end)
        function panel:Think()
            local r = D.Cfg("useRange") + 20
            if not term or not IsValid(term.ent) or LocalPlayer():GetPos():DistToSqr(term.ent:GetPos()) > r * r then self:Remove() end
        end
        local close = k.Button(panel, "Close", function() panel:Remove() end, { small = true })
        close:Dock(BOTTOM)
        close:DockMargin(0, s(10), 0, 0)
        panel.body = vgui.Create("DPanel", panel)
        panel.body:Dock(FILL)
        panel.body.Paint = nil
        if Rhylib.Menus.RegisterCloser then
            Rhylib.Menus.RegisterCloser("datapad.term", function()
                if IsValid(panel) then panel:Remove() return true end
                return false
            end)
        end
    end
    build()
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
    -- A different computer (or newly opened): start fresh.
    if not term or term.ent ~= t.ent or not IsValid(panel) then
        selected, bodies, tab = nil, {}, "logs"
        filter = { q = "", days = 0, mp = false, ids = nil }
        board, boardSel, boardBodies, editing = nil, nil, {}, nil
        boardMeta = {}
        statsData = nil
        unit, unitAsked, appSel, orderDraft, orderSel = nil, nil, nil, nil, nil
        appInfo, appAsked = {}, nil
        missions, missionsAsked, missionSel, missionFull = nil, nil, nil, {}
        people, peopleAsked, personSel, pfile, pAsked, notesEdit = nil, nil, nil, nil, nil, false
    end
    term = t
    if selected and not entryById(selected) then selected = nil end
    open()
end)

Rhylib.Net.Receive("dp.tbody", function()
    local id = net.ReadUInt(20)
    bodies[id] = net.ReadString()
    if IsValid(panel) and selected == id and tab == "logs" then build() end
end)

Rhylib.Net.Receive("dp.tfound", function()
    local ids = {}
    for _ = 1, net.ReadUInt(8) do ids[net.ReadUInt(20)] = true end
    filter.ids = ids
    if IsValid(panel) and tab == "logs" then build() end
end)

Rhylib.Net.Receive("dp.board", function()
    local ent = net.ReadEntity()
    local b = { canPost = net.ReadBool(), canAAR = net.ReadBool(), posts = {} }
    for i = 1, net.ReadUInt(8) do
        b.posts[i] = { id = net.ReadUInt(16), sec = net.ReadUInt(3), title = net.ReadString(), author = net.ReadString(),
            t = net.ReadUInt(32), at = net.ReadUInt(32), pin = net.ReadBool(), oc = net.ReadUInt(2), ses = net.ReadUInt(16),
            mine = net.ReadBool() }
    end
    b.info = { txt = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32) }
    if not term or term.ent ~= ent then return end
    board = b
    boardBodies = {}   -- posts may have been edited
    boardMeta = {}
    if boardSel and boardSel ~= "info" and not postById(boardSel) then boardSel = nil end
    if IsValid(panel) and tab == "board" then build() end
end)

Rhylib.Net.Receive("dp.bbody", function()
    local id = net.ReadUInt(16)
    boardBodies[id] = net.ReadString()
    local m = { rv = {}, ci = {} }
    for i = 1, net.ReadUInt(8) do m.rv[i] = { name = net.ReadString(), s = net.ReadUInt(2) } end
    m.mine = net.ReadUInt(2)
    for i = 1, net.ReadUInt(8) do m.ci[i] = net.ReadString() end
    m.checked = net.ReadBool()
    boardMeta[id] = m
    if IsValid(panel) and tab == "board" and (boardSel == id or editing == id) then build() end
end)

Rhylib.Net.Receive("dp.statsr", function()
    local d = { period = net.ReadUInt(3), totals = {}, members = {} }
    for _, k in ipairs(STAT_KEYS) do d.totals[k] = net.ReadUInt(32) end
    for i = 1, net.ReadUInt(7) do
        local m = { name = net.ReadString() }
        for _, k in ipairs(STAT_KEYS) do m[k] = net.ReadUInt(32) end
        d.members[i] = m
    end
    statsData = d
    if IsValid(panel) and tab == "stats" then build() end
end)

Rhylib.Net.Receive("dp.unit", function()
    local ent = net.ReadEntity()
    local u = { leave = {}, apps = {} }
    u.member, u.manager, u.officer, u.canApply = net.ReadBool(), net.ReadBool(), net.ReadBool(), net.ReadBool()
    u.myBn, u.mySt = net.ReadString(), net.ReadUInt(2)
    u.orders = D.ReadOrders()
    for i = 1, net.ReadUInt(6) do
        u.leave[i] = { id = net.ReadUInt(16), name = net.ReadString(), from = net.ReadUInt(32), to = net.ReadUInt(32),
            why = net.ReadString(), mine = net.ReadBool() }
    end
    for i = 1, net.ReadUInt(6) do
        u.apps[i] = { id = net.ReadUInt(16), name = net.ReadString(), txt = net.ReadString(), t = net.ReadUInt(32),
            st = net.ReadUInt(2), by = net.ReadString() }
    end
    unitAsked = nil
    if not term or term.ent ~= ent then return end
    unit = u
    if appSel and not appById(appSel) then appSel = nil end
    if IsValid(panel) then build() end
end)

--------------------------------------------------------------------------
-- Application prompts (on join, or when a manager decides)
--------------------------------------------------------------------------

local popup

local function acceptedPopup(bn, by)
    local k = K()
    if not k then return end
    if IsValid(popup) then popup:Remove() end
    local s = k.S
    popup = vgui.Create("EditablePanel")
    popup:SetSize(s(460), s(220))
    popup:Center()
    popup:MakePopup()
    popup:DockPadding(s(18), s(52), s(18), s(18))
    function popup:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "You got accepted", sub = bn, ticks = "all", header = s(38), bg = OPAQUE })
    end
    local l = k.Label(popup, (by ~= "" and by or "An officer") .. " accepted your application to the " .. bn ..
        ". Join now, or turn it down if you've changed your mind.", 14, 400, k.C.text)
    l:Dock(TOP)
    local row = vgui.Create("DPanel", popup)
    row:Dock(BOTTOM)
    row:SetTall(s(34))
    row.Paint = nil
    local function answer(join)
        Rhylib.Net.Start("dp.uanswer")
        net.WriteBool(join)
        net.SendToServer()
        popup:Remove()
    end
    local later = k.Button(row, "Later", function() popup:Remove() end, { tooltip = "Decide at the battalion computer, or when you next join" })
    later:Dock(RIGHT)
    later:SetWide(s(90))
    later:DockMargin(s(6), 0, 0, 0)
    local rej = k.Button(row, "Reject", function()
        local m = k.Menu()
        m:AddOption("Turn down the " .. bn, function() answer(false) end)
        m:Open()
    end, { danger = true })
    rej:Dock(RIGHT)
    rej:SetWide(s(110))
    rej:DockMargin(s(6), 0, 0, 0)
    local join = k.Button(row, "Join battalion", function() answer(true) end, { accent = true })
    join:Dock(FILL)
end

-- Esc closes the popup (Menus.RegisterCloser).
-- (rhylib_menus loads after this module, so register once everything has)
local function registerAcceptedCloser()
    if Rhylib.Menus and Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("datapad.accepted", function()
            if IsValid(popup) then popup:Remove() return true end
            return false
        end)
    end
end
registerAcceptedCloser()
Rhylib.Hook.Add("InitPostEntity", "datapad.acceptedcloser", registerAcceptedCloser)

Rhylib.Net.Receive("dp.uprompt", function()
    local kind, bn, by = net.ReadUInt(2), net.ReadString(), net.ReadString()
    local tag = Color(120, 200, 255)
    if kind == 0 then
        chat.AddText(tag, "[" .. bn .. "] ", color_white, "Check your application status at the battalion computer.")
    elseif kind == 1 then
        chat.AddText(tag, "[" .. bn .. "] ", color_white, "You got accepted! Join the battalion, or turn it down.")
        acceptedPopup(bn, by)
    elseif kind == 2 then
        chat.AddText(tag, "[" .. bn .. "] ", color_white, "Your application was declined" .. (by ~= "" and (" by " .. by) or "") .. ".")
    end
    -- At the computer: show the new status.
    if IsValid(panel) and term and not term.med then
        unit, unitAsked = nil, nil
        build()
    end
end)

Rhylib.Net.Receive("dp.pmembers", function()
    local ent = net.ReadEntity()
    local list = {}
    for i = 1, net.ReadUInt(8) do
        list[i] = { id = net.ReadString(), name = net.ReadString(), r = net.ReadUInt(8), on = net.ReadBool(),
            seen = net.ReadUInt(32), coms = net.ReadUInt(8), strikes = net.ReadUInt(4), note = net.ReadString() }
    end
    peopleAsked = nil
    if not term or term.ent ~= ent then return end
    people = list
    if IsValid(panel) and (tab == "people" or tab == "orders") then build() end
end)

Rhylib.Net.Receive("dp.pfile", function()
    local ent = net.ReadEntity()
    local f = { quals = {}, stats = {}, coms = {}, strikes = {} }
    f.id, f.name, f.rank = net.ReadString(), net.ReadString(), net.ReadString()
    f.on, f.seen = net.ReadBool(), net.ReadUInt(32)
    f.commend, f.discipline = net.ReadBool(), net.ReadBool()
    for i = 1, net.ReadUInt(5) do
        f.quals[i] = { id = net.ReadString(), name = net.ReadString(), has = net.ReadBool() }
    end
    for _, key in ipairs(STAT_KEYS) do f.stats[key] = net.ReadUInt(32) end
    for i = 1, net.ReadUInt(8) do
        f.coms[i] = { id = net.ReadUInt(16), t = net.ReadUInt(32), by = net.ReadString(), bn = net.ReadString(), txt = net.ReadString() }
    end
    f.seeStrikes = net.ReadBool()
    for i = 1, net.ReadUInt(8) do
        f.strikes[i] = { id = net.ReadUInt(16), t = net.ReadUInt(32), exp = net.ReadUInt(32), by = net.ReadString(), txt = net.ReadString() }
    end
    f.seeNotes = net.ReadBool()
    f.notes = { txt = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32) }
    pAsked = nil
    if not term or term.ent ~= ent then return end
    pfile = f
    if IsValid(panel) and tab == "people" and personSel == f.id then build() end
end)

Rhylib.Net.Receive("dp.uappinfo", function()
    local id = net.ReadUInt(16)
    local info = { stats = {}, quals = {}, arrests = {} }
    for _, key in ipairs(STAT_KEYS) do info.stats[key] = net.ReadUInt(32) end
    for i = 1, net.ReadUInt(5) do info.quals[i] = net.ReadString() end
    info.coms = net.ReadUInt(8)
    info.strikes = net.ReadUInt(8)
    for i = 1, net.ReadUInt(6) do
        info.arrests[i] = { t = net.ReadUInt(32), by = net.ReadString(), min = net.ReadUInt(10), why = net.ReadString() }
    end
    appInfo[id] = info
    if appAsked == id then appAsked = nil end
    if IsValid(panel) and tab == "apps" and appSel == id then build() end
end)

Rhylib.Net.Receive("dp.mlistr", function()
    local ent = net.ReadEntity()
    local d = { list = {} }
    d.canDelete = net.ReadBool()
    d.current = D.ReadMission()
    for i = 1, net.ReadUInt(7) do
        d.list[i] = { id = net.ReadUInt(16), title = net.ReadString(), date = net.ReadString(), by = net.ReadString(),
            started = net.ReadUInt(32), ended = net.ReadUInt(32), n = net.ReadUInt(8) }
    end
    missionsAsked = nil
    if not term or term.ent ~= ent then return end
    missions = d
    if IsValid(panel) and tab == "missions" then build() end
end)

Rhylib.Net.Receive("dp.mfull", function()
    local id = net.ReadUInt(16)
    local f = { obj = net.ReadString(), sub = net.ReadString(), info = net.ReadString(), endedBy = net.ReadString(), people = {} }
    for i = 1, net.ReadUInt(8) do f.people[i] = net.ReadString() end
    missionFull[id] = f
    if IsValid(panel) and tab == "missions" and missionSel == id then build() end
end)
