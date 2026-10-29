--[[
    Battalion computer window, Board tab (client): the battalion info,
    Session and AAR posts (old Info/Plans posts under "Older posts"),
    pinned first, upcoming sessions with a countdown, past ones archived;
    "Write AAR" on a past session fills in a template; session sign-ups
    and check-in. State in BD; registered with D.TermAddTab.
      dp.bopen -> dp.board   dp.bget -> dp.bbody   dp.bsave, dp.bdel,
      dp.bpin, dp.binfo, dp.ursvp, dp.ucheck
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)

local BD = { board = nil, boardSel = nil, boardBodies = {}, editing = nil, boardMeta = {} }   -- (boardMeta[post id] = { rv = {{name, s}}, mine, ci = {names}, checked })

local SECTIONS = { "Info", "Plans", "Session", "AAR" }
local OUTCOMES = { "Success", "Partial success", "Failure" }
local RSVP = { "Attending", "Maybe", "Can't" }

local sessionStrip

local function postById(id)
    if not BD.board then return nil end
    for _, p in ipairs(BD.board.posts) do
        if p.id == id then return p end
    end
end

local function postSub(p)
    local s = p.author .. "  ·  " .. T.when(p.t)
    if p.sec == 3 and p.at > 0 then
        s = T.when(p.at) .. (p.at > os.time() and ("  (" .. T.Countdown(p.at) .. ")") or "  (past)") .. "  ·  " .. p.author
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
    return BD.board.canPost or (BD.board.canAAR and p.sec == 4 and p.mine)
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

-- p: post being edited, or a draft table (new post with presets), or nil.
local function editor(parent, p)
    local k = T.K()
    local s = k.S
    -- Editing a post: wait for its text first.
    if p and p.id and not BD.boardBodies[p.id] then
        T.Label(parent, "Loading…")
        T.Send("dp.bget", function() net.WriteUInt(p.id, 16) end)
        return
    end
    local isNew = not p or not p.id
    local sec = p and p.sec or (BD.board.canPost and 3 or 4)
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
    local secOpts = BD.board.canPost and { { 3, "Session" }, { 4, "AAR" } } or { { 4, "AAR" } }
    if p and p.id and p.sec < 3 then table.insert(secOpts, 1, { p.sec, SECTIONS[p.sec] }) end   -- (an old Info/Plans post)
    local secs = k.Choices(secRow, secOpts, function() return sec end, function(v)
        sec = v
        relayout()
    end)
    secs:Dock(LEFT)
    secs:SetWide(s(BD.board.canPost and 300 or 100))
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
    if p and p.id then body:SetText(BD.boardBodies[p.id] or "") else body:SetText(p and p.body or "") end
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
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(s(120))
    local cancel = k.Button(foot, "Cancel", function()
        BD.editing = nil
        T.Build()
    end)
    cancel:Dock(RIGHT)
    cancel:SetWide(s(120))
    cancel:DockMargin(0, 0, s(6), 0)
end

-- Sign-ups and check-in for a session (the data comes with its text).
function sessionStrip(parent, p)
    local k = T.K()
    local s = k.S
    local m = BD.boardMeta[p.id]
    if not m then return end
    local names = { {}, {}, {} }
    for _, r in ipairs(m.rv) do
        if names[r.s] then table.insert(names[r.s], r.name) end
    end
    if T.unit and T.unit.member then
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:SetTall(s(28))
        row:DockMargin(0, 0, 0, s(6))
        row.Paint = nil
        for i, txt in ipairs(RSVP) do
            local b = k.Button(row, txt .. " (" .. #names[i] .. ")", function()
                T.Send("dp.ursvp", function()
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
            T.Send("dp.ucheck", function() net.WriteUInt(p.id, 16) end)
        end, { small = true, accent = true, enabled = not m.checked and open,
            tooltip = "Opens 15 minutes before the session, closes an hour after it starts" })
        ci:Dock(RIGHT)
        ci:SetWide(s(130))
    end
    for i, txt in ipairs(RSVP) do
        if #names[i] > 0 then
            T.Label(parent, txt .. ": " .. table.concat(names[i], ", "), nil, 12)
        end
    end
    if #m.ci > 0 then
        local l = T.Label(parent, "Checked in (" .. #m.ci .. "): " .. table.concat(m.ci, ", "), k.C.good, 12)
        l:DockMargin(0, 0, 0, s(6))
    end
end

-- The battalion info: one text, edited over time.
local function infoReader(parent)
    local k = T.K()
    local s = k.S
    local info = BD.board.info
    if BD.editing == "info" then
        local h = k.Heading(parent, "Edit battalion info")
        h:Dock(TOP)
        local hint = T.Label(parent, "Whatever is useful right now: who leads what, SOPs, callsigns, what to bring. Everyone reads it here and on their datapad.")
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
            T.Send("dp.binfo", function() net.WriteString(string.sub(te:GetText() or "", 1, 12000)) end)
            BD.editing = nil
        end, { accent = true })
        save:Dock(RIGHT)
        save:SetWide(s(120))
        local cancel = k.Button(foot, "Cancel", function()
            BD.editing = nil
            T.Build()
        end)
        cancel:Dock(RIGHT)
        cancel:SetWide(s(120))
        cancel:DockMargin(0, 0, s(6), 0)
        return
    end
    local h = k.Heading(parent, "Battalion info")
    h:Dock(TOP)
    local by = T.Label(parent, info.txt ~= "" and ("Last edited by " .. info.by .. "  ·  " .. T.when(info.t)) or "Nothing written yet.")
    by:DockMargin(0, s(4), 0, s(8))
    if BD.board.canPost then
        local row = vgui.Create("DPanel", parent)
        row:Dock(BOTTOM)
        row:SetTall(s(30))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local b = k.Button(row, "Edit", function()
            BD.editing = "info"
            T.Build()
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
    local k = T.K()
    local s = k.S
    if BD.boardSel == "info" then infoReader(parent) return end
    local p = BD.boardSel and postById(BD.boardSel)
    if not p then
        T.Label(parent, (BD.board.canPost or BD.board.canAAR) and "Pick a post, or write a new one." or "Pick a post to read it.")
        return
    end
    local h = k.Heading(parent, (p.pin and "★ " or "") .. p.title)
    h:Dock(TOP)
    local by = T.Label(parent, SECTIONS[p.sec] .. "  ·  " .. postSub(p))
    by:DockMargin(0, s(4), 0, s(8))
    if p.sec == 4 and p.ses > 0 then
        local ses = postById(p.ses)
        if ses then
            local link = k.Button(parent, "Report on: " .. ses.title, function()
                BD.boardSel = ses.id
                T.Build()
            end, { small = true, align = "left" })
            link:Dock(TOP)
            link:DockMargin(0, 0, 0, s(6))
        end
    end
    if p.sec == 3 then sessionStrip(parent, p) end
    local past = p.sec == 3 and p.at > 0 and p.at < os.time()
    if canChange(p) or (past and BD.board.canAAR) then
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
        if past and BD.board.canAAR then
            btn("Write AAR", function()
                BD.editing = aarDraft(p)
                T.Build()
            end, { small = true, accent = true }, 130)
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
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local body = k.Label(sp, BD.boardBodies[p.id] or "Loading…", 14, 400, k.C.text)
    body:Dock(TOP)
    body:DockMargin(0, 0, s(10), 0)
    if not BD.boardBodies[p.id] then T.Send("dp.bget", function() net.WriteUInt(p.id, 16) end) end
end

local function boardTab(body)
    local k = T.K()
    local s = k.S
    if not BD.board then
        T.Label(body, "Loading the board…")
        BD.board = { posts = {}, canPost = false, canAAR = false, loading = true }
        T.Send("dp.bopen")
        return
    end
    if BD.board.loading then
        T.Label(body, "Loading the board…")
        return
    end
    local left, right = T.Columns(body)
    if BD.board.canPost or BD.board.canAAR then
        local new = k.Button(left, BD.board.canPost and "New post" or "New after-action report", function()
            BD.editing = BD.board.canPost and 0 or { sec = 4, oc = 1, ses = 0, title = "AAR: ", body = "" }
            T.Build()
        end, { small = true, accent = true })
        new:Dock(TOP)
        new:DockMargin(0, 0, s(8), s(8))
    end
    local sp = k.Scroll(left)
    sp:Dock(FILL)

    -- Battalion info first.
    T.ListRow(sp, "Battalion info", BD.board.info.txt ~= "" and ("Edited " .. T.when(BD.board.info.t) .. " by " .. BD.board.info.by) or "Not written yet",
        function() return BD.boardSel == "info" end, function()
            BD.boardSel = "info"
            BD.editing = nil
            T.Build()
        end, "Info")

    -- Group: pinned, upcoming sessions (soonest first), AARs, archive, old Info/Plans posts.
    local now = os.time()
    local groups = { { "Pinned", {} }, { "Upcoming sessions", {} }, { "Older posts", {} }, { "Older posts", {} },
        { "After-action reports", {} }, { "Past sessions", {} } }
    for _, p in ipairs(BD.board.posts) do
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
                T.ListRow(sp, p.title, postSub(p), function() return BD.boardSel == p.id end, function()
                    BD.boardSel = p.id
                    BD.editing = nil
                    T.Build()
                end, postTag(p))
            end
        end
    end
    if BD.editing == "info" then
        infoReader(right)
    elseif BD.editing then
        if istable(BD.editing) then
            editor(right, BD.editing)
        else
            local p = BD.editing ~= 0 and postById(BD.editing) or nil
            if BD.editing ~= 0 and not p then
                BD.editing = nil   -- deleted meanwhile
                boardReader(right)
            else
                editor(right, p)
            end
        end
    else
        boardReader(right)
    end
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
    if IsValid(T.panel) and T.tab == "board" and (BD.boardSel == id or BD.editing == id) then T.Build() end
end)

D.TermAddTab("board", {
    order = 20, name = "Board",
    has = function(tm) return not tm.med end,
    build = boardTab,
    reset = function() BD.board, BD.boardSel, BD.boardBodies, BD.editing, BD.boardMeta = nil, nil, {}, nil, {} end,
})
