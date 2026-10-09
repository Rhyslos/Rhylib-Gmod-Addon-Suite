--[[
    Datapad window. Left click with the datapad out opens it.
    Tabs: Quick response (first, for combat); Notes; Board (opens on it when it
    has posts), Orders, Logs, LOA, Stats, My file - read from the last
    download of your battalion computer (Sync, top right), each shown only
    once the download has something for it; MPs: Records, Officer
    logs, Arrest.
]]

local D = Rhylib.Datapad

local function K() return Rhylib.Menus and Rhylib.Menus.Kit end
local function when(t) return t and t > 0 and os.date("%d %b %H:%M", t) or "" end
local OPAQUE = Color(14, 16, 15, 255)   -- solid background: readable over anything

D.state = D.state or nil
local panel, content, nav
local tab = "board"
local view = {}          -- what the current tab shows (set by replies)
local wantOpen = false

local function send(name, fn)
    Rhylib.Net.Start(name)
    if fn then fn() end
    net.SendToServer()
end

-- A battalion's colour (its DarkRP job category), brightened enough to
-- read as an accent. nil if unknown.
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

-- A mission (written by D.WriteMission), or nil.
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
D.ORDER_STATUS = { "Issued", "In progress", "Completed", "Success", "Failed", "Cancelled" }
D.ORDER_TAG = { "New", "Active", "Done", "Success", "Failed", "Cancelled" }

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
    local C = Rhylib.Menus.Kit.C
    if st == 4 or st == 3 then return C.good end
    if st == 5 then return C.bad end
    if st == 6 then return C.textDim end
    return C.warn
end

-- A menu of the statuses this player may pick; onPick(status).
function D.OrderStatusMenu(o, full, onPick)
    local m = Rhylib.Menus.Kit.Menu()
    for st, name in ipairs(D.ORDER_STATUS) do
        if st ~= o.st and (full or st == 2 or st == 3) then
            m:AddOption(name, function() onPick(st) end)
        end
    end
    m:Open()
end

-- Is this the military police battalion (its jobs have mp = true)?
function D.IsMPBattalion(bn)
    for _, j in pairs(RPExtraTeams or {}) do
        if j.category == bn and j.mp then return true end
    end
    return false
end

--------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------

local function clear()
    if IsValid(content) then content:Clear() end
end

-- A clickable list row: left text, dim right text. reserve: width kept
-- free on the right (for buttons docked into the row).
local function row(parent, left, right, onClick, tag, reserve)
    local k = K()
    local s = k.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(s(34))
    b:Dock(TOP)
    b:DockMargin(0, 0, s(8), s(3))
    function b:Paint(w, h)
        k.SetCol(self:IsHovered() and onClick and k.C.rowHover or k.C.row)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(k.C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local x = s(12)
        if tag then
            k.Caps(tag, x, h * 0.5, k.C.accent)
            x = x + s(52)
        end
        -- Right text sits left of any reserved space (buttons docked there).
        local rw = reserve or 0
        if right and right ~= "" then
            surface.SetFont(k.Font(12))
            draw.SimpleText(right, k.Font(12), w - rw - s(12), h * 0.5, k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            rw = rw + surface.GetTextSize(right) + s(24)
        end
        draw.SimpleText(k.Fit(left, k.Font(14, 500), w - x - rw - s(12)), k.Font(14, 500), x, h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
    p:SetTall(k.S(30))
    p:DockMargin(0, 0, 0, k.S(8))
    p.Paint = nil
    return p
end

local function barButton(p, text, fn, opts)
    local k = K()
    local b = k.Button(p, text, fn, opts or { small = true })
    b:Dock(LEFT)
    surface.SetFont(k.Font(12, 700))
    b:SetWide(surface.GetTextSize(string.upper(text)) + k.S(30))
    b:DockMargin(0, 0, k.S(6), 0)
    return b
end

local function heading(text)
    local k = K()
    local h = k.Heading(content, text)
    h:Dock(TOP)
    h:DockMargin(0, 0, 0, k.S(6))
    return h
end

local function label(parent, text, col)
    local k = K()
    local l = k.Label(parent, text, 13, 400, col or k.C.textDim)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(8), k.S(6))
    return l
end

-- Read-only text: title, by-line, body.
local function reader(title, by, body, back)
    clear()
    local k = K()
    local b = bar(content)
    barButton(b, "Back", back)
    heading(title)
    label(content, by)
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local l = k.Label(sp, body ~= "" and body or "(empty)", 14, 400, k.C.text)
    l:Dock(TOP)
    l:DockMargin(0, 0, k.S(10), 0)
end

--------------------------------------------------------------------------
-- Notes
--------------------------------------------------------------------------

local buildTab

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

    local title = k.TextEntry(content, "Title")
    title:Dock(TOP)
    title:DockMargin(0, 0, k.S(8), k.S(6))
    title:SetText(note and note.title or "")
    local foot = vgui.Create("DPanel", content)
    foot:Dock(BOTTOM)
    foot:SetTall(k.S(32))
    foot.Paint = nil
    local body = k.TextEntry(content, "Write here…")
    body:SetMultiline(true)
    body:Dock(FILL)
    body:DockMargin(0, 0, k.S(8), k.S(8))
    view.body = body
    if i > 0 then send("dp.get", function() net.WriteUInt(i, 16) end) end
    local save = k.Button(foot, "Save", function()
        send("dp.save", function()
            net.WriteUInt(i, 16)
            net.WriteUInt(isMed and D.KIND_MED or D.KIND_LOG, 1)
            net.WriteString(string.sub(title:GetText() or "", 1, 400))
            net.WriteString(string.sub(body:GetText() or "", 1, 8000))
            net.WriteEntity(IsValid(patient) and patient or NULL)
        end)
        view.edit = nil
    end, { accent = true })
    save:Dock(RIGHT)
    save:SetWide(k.S(120))
    if i > 0 then
        local del = k.Button(foot, "Delete", function()
            send("dp.del", function() net.WriteUInt(i, 16) end)
            view.edit = nil
        end, { danger = true })
        del:Dock(LEFT)
        del:SetWide(k.S(120))
    end
end

local function notesTab()
    local k = K()
    local st = D.state
    local b = bar(content)
    local full = st.limit > 0 and #st.notes >= st.limit
    barButton(b, "New log", function() editor(0, D.KIND_LOG) end,
        { small = true, accent = true, enabled = not full and not st.banned })
    if st.medic then
        barButton(b, "New medical record", function()
            local m = k.Menu()
            for _, p in ipairs(player.GetAll()) do
                m:AddOption(p:Nick(), function() editor(0, D.KIND_MED, p) end)
            end
            m:Open()
        end, { small = true, enabled = not full })
    end
    heading("Notes on this datapad")
    local where = st.bn ~= "" and ("the " .. st.bn .. " computer") or "your battalion computer"
    if st.limit > 0 then
        label(content, string.format("%d / %d notes. When it's full, upload at %s.", #st.notes, st.limit, where),
            full and k.C.warn or nil)
    else
        label(content, "No note limit. Upload logs at " .. where .. (st.medic and ", medical records at the medical holotable." or "."))
    end
    if st.banned then label(content, "You're banned from your battalion's logs.", k.C.bad) end
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
    local h1 = k.Heading(sp, "Arrests (" .. #rec.jails .. ")")
    h1:Dock(TOP)
    if #rec.jails == 0 then label(sp, "No arrests on file.") end
    for _, j in ipairs(rec.jails) do
        row(sp, j.why ~= "" and j.why or "No reason given", j.min .. " min · by " .. j.by .. "  " .. when(j.t))
    end
    local h2 = k.Heading(sp, "Logs they wrote (" .. #rec.logs .. ")")
    h2:Dock(TOP)
    h2:DockMargin(0, k.S(10), 0, 0)
    if #rec.logs == 0 then label(sp, "No uploaded logs.") end
    logList(sp, rec.logs, recordView)
end

local function recordsTab()
    local k = K()
    if view.record then recordView() return end
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
    barButton(b, "Search", go, { small = true, accent = true })
    heading("Records")
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
    heading("Logs written by MPs")
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
    heading("Cuffed prisoners near you")
    label(content, "Search them, or jail them straight from the datapad.")
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local any = false
    for _, p in ipairs(st.cuffed) do
        if IsValid(p) then
            any = true
            local r = row(sp, p:Nick(), "", nil, nil, k.S(200))
            local jail = k.Button(r, "Jail", function()
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
            end, { small = true, accent = true })
            jail:Dock(RIGHT)
            jail:SetWide(k.S(90))
            jail:DockMargin(0, k.S(4), k.S(4), k.S(4))
            local search = k.Button(r, "Search", function()
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

D.sync = D.sync or nil      -- { bn, v, at, logs, posts } (kept until you leave)
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

-- A quiet download right after your own change (posting a mission,
-- setting an order's status), so your own pad doesn't flash "new data".
local qdl   -- { data, extra, more }
local buildNav

local function quietSync()
    if dl or qdl or not D.state or D.state.bn == "" then return end
    qdl = {}
    send("dp.dl")
    timer.Simple(10, function() qdl = nil end)   -- (gave up)
end

local function tryQuiet()
    if not (qdl and qdl.data and qdl.extra and qdl.more) then return end
    D.sync = qdl.data
    D.sync.x = qdl.extra
    D.sync.x.info = qdl.more.info
    D.sync.x.mission = qdl.more.mission
    D.sync.at = os.time()
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
        label(content, "Nothing downloaded yet. Press Sync at the top right to download the " .. st.bn ..
            " computer: board, orders, logs, LOA, stats and your file. Uploading still happens at the computer.")
        return nil
    end
    label(content, "Downloaded " .. os.date("%d %b %H:%M", sy.at) .. (hasNew() and "  ·  the computer has newer changes" or "  ·  up to date"),
        hasNew() and k.C.good or nil)
    return sy
end

local function sub(sp, text)
    local k = K()
    local h = k.Heading(sp, text)
    h:Dock(TOP)
    h:DockMargin(0, k.S(6), k.S(8), k.S(4))
end

-- Read a post (kind 1) or log (kind 0) from the computer.
local function openRead(kind, id, title, by)
    view.read = { kind = kind, id = id, title = title, by = by }
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
    local s = k.S
    local st = D.state
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
            end, { small = true, accent = true })
        end
        heading(o.title)
        label(content, "From " .. o.by .. " · " .. when(o.t) .. "   ·   To: " .. D.OrderTo(o))
        label(content, "Status: " .. D.ORDER_STATUS[o.st] .. (o.sb ~= "" and ("  (" .. o.sb .. ", " .. when(o.stt) .. ")") or ""), D.OrderColor(o.st))
        local sp = k.Scroll(content)
        sp:Dock(FILL)
        local l = k.Label(sp, o.text ~= "" and o.text or "(no details)", 14, 400, k.C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(10), 0)
        return
    end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    if #x.orders == 0 then label(sp, "No orders.") end
    local function list(title, test)
        local first = true
        for _, it in ipairs(x.orders) do
            if test(it) then
                if first then sub(sp, title) first = false end
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

local STAT_NAMES = { kd = "Droid kills", kp = "Player kills", de = "Deaths", rv = "Revives", he = "Heals",
    ar = "Arrests", mi = "Hours", mo = "Money", at = "Attended", jd = "Arrested", ev = "Events" }
local STAT_KEYS = { "kd", "kp", "de", "rv", "he", "ar", "mi", "mo", "at", "jd", "ev" }   -- server order

local function statText(key, v)
    if key == "mi" then return string.format("%.1f", (v or 0) / 60) end
    if key == "mo" then return string.Comma and string.Comma(v or 0) or tostring(v or 0) end
    return tostring(v or 0)
end

local function statsTab()
    local k = K()
    local s = k.S
    heading("Stats")
    local sy = synced()
    if not sy or not sy.x then return end
    local x = sy.x
    local mp = D.IsMPBattalion(sy.bn)
    local keys = {}
    for _, key in ipairs(STAT_KEYS) do
        if not ((mp and key == "jd") or (not mp and key == "ar")) then keys[#keys + 1] = key end
    end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local function table3(title, cols)
        sub(sp, title)
        local head = vgui.Create("DPanel", sp)
        head:Dock(TOP)
        head:SetTall(s(22))
        head:DockMargin(0, 0, s(8), 0)
        function head:Paint(w, h)
            local cw = (w - s(160)) / #cols
            for i, c in ipairs(cols) do
                k.Caps(c[1], s(160) + cw * i - s(8), h * 0.5, k.C.label, TEXT_ALIGN_RIGHT)
            end
        end
        for i, key in ipairs(keys) do
            local r = vgui.Create("DPanel", sp)
            r:Dock(TOP)
            r:SetTall(s(24))
            r:DockMargin(0, 0, s(8), s(1))
            function r:Paint(w, h)
                k.SetCol(i % 2 == 0 and k.C.rowAlt or k.C.row)
                surface.DrawRect(0, 0, w, h)
                draw.SimpleText(STAT_NAMES[key], k.Font(13, 600), s(10), h * 0.5, k.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local cw = (w - s(160)) / #cols
                for c, col in ipairs(cols) do
                    draw.SimpleText(statText(key, col[2][key]), k.Font(13), s(160) + cw * c - s(8), h * 0.5, k.C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
    table3("This week", { { "Battalion", x.weekAll }, { "You", x.weekMe }, { "You, all time", x.allMe } })
end

local function fileTab()
    local k = K()
    local s = k.S
    heading("My file")
    local sy = synced()
    if not sy or not sy.x then return end
    local f = sy.x.file
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    sub(sp, "Qualifications")
    label(sp, #f.quals > 0 and table.concat(f.quals, ", ") or "None yet.", #f.quals > 0 and k.C.text or nil)
    sub(sp, "Commendations (" .. f.ncom .. ")")
    if #f.coms == 0 then label(sp, "None yet.") end
    for _, c in ipairs(f.coms) do
        label(sp, os.date("%d %b %Y", c.t) .. " · " .. c.by)
        local l = k.Label(sp, c.txt, 14, 400, k.C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(8), s(8))
    end
    sub(sp, "Active strikes (" .. #f.strikes .. ")")
    if #f.strikes == 0 then label(sp, "None.") end
    for _, x in ipairs(f.strikes) do
        label(sp, os.date("%d %b %Y", x.t) .. " · " .. x.by .. " · until " .. os.date("%d %b", x.exp), k.C.bad)
        local l = k.Label(sp, x.txt, 14, 400, k.C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(8), s(8))
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
    local s = k.S
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local h = k.Heading(sp, m.title)
    h:Dock(TOP)
    h:DockMargin(0, 0, s(8), s(4))
    label(sp, (m.date ~= "" and (m.date .. "  ·  ") or "") .. "by " .. m.by)
    label(sp, missionStatus(m), m.active and k.C.good or k.C.warn)
    local function part(title, txt)
        if txt == "" then return end
        sub(sp, title)
        local l = k.Label(sp, txt, 14, 400, k.C.text)
        l:Dock(TOP)
        l:DockMargin(0, 0, s(8), s(6))
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
    end, { small = true, accent = true })
    if m and not m.active then
        barButton(b, "Start", function()
            view.misAction = true
            send("dp.mstart")
        end, { small = true, accent = true })
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
        end, { small = true, danger = true })
    end
    if m then
        label(content, missionStatus(m), m.active and k.C.good or k.C.warn)
    else
        label(content, "No mission yet. Fill it in and post it; troopers get it when they sync.")
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
    date:DockMargin(s(6), 0, s(8), 0)
    date:SetText(d.date)
    function date:OnChange() d.date = self:GetText() or "" end
    local function box(key, hint, tall)
        local e = k.TextEntry(content, hint)
        e:SetMultiline(true)
        if tall then e:Dock(FILL) else e:Dock(TOP) e:SetTall(s(80)) end
        e:DockMargin(0, 0, s(8), s(6))
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

-- Quick response: ask for help, see who's coming, answer others' calls.
local function commsTab()
    local k = K()
    local s = k.S
    local defs = D.Cfg("calls") or {}
    local items = D.Cfg("supplyItems") or {}
    heading("Quick response")
    -- Resupply picker.
    if view.supply then
        local pick = view.supply
        label(content, "What do you need? Pick one or more, then send.")
        local grid = vgui.Create("DPanel", content)
        grid:Dock(TOP)
        grid:DockMargin(0, 0, s(8), s(8))
        grid.Paint = nil
        local btns = {}
        for i, name in ipairs(items) do
            btns[#btns + 1] = k.Button(grid, name, function() pick.sel[i] = not pick.sel[i] or nil end,
                { small = true, selected = function() return pick.sel[i] ~= nil end })
        end
        function grid:PerformLayout(w)
            local cols, gap, bh = 3, s(6), s(30)
            local bw = (w - gap * (cols - 1)) / cols
            for i, b in ipairs(btns) do
                b:SetPos(((i - 1) % cols) * (bw + gap), math.floor((i - 1) / cols) * (bh + gap))
                b:SetSize(bw, bh)
            end
            local want = math.ceil(#btns / cols) * (bh + gap)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
        local b = bar(content)
        barButton(b, "Back", function() view.supply = nil buildTab() end)
        barButton(b, "Send request", function()
            local mask = 0
            for i in pairs(pick.sel) do mask = mask + 2 ^ (i - 1) end
            if mask == 0 then return end
            D.SendCall(pick.kind, mask)
            view.supply = nil
            buildTab()
        end, { small = true, accent = true })
        return
    end
    -- Request buttons.
    local grid = vgui.Create("DPanel", content)
    grid:Dock(TOP)
    grid:DockMargin(0, 0, s(8), s(10))
    grid.Paint = nil
    local btns = {}
    for i, def in ipairs(defs) do
        btns[#btns + 1] = k.Button(grid, def.name, function()
            if def.items then
                view.supply = { kind = i, sel = {} }
                buildTab()
            else
                D.SendCall(i, 0)
            end
        end, { accent = true, enabled = function() return D.CanCall and D.CanCall(i) end,
            tooltip = def.accept and "Others accept it before they see where you are" or "Sends your location straight away" })
    end
    function grid:PerformLayout(w)
        local cols, gap, bh = 2, s(8), s(40)
        local bw = (w - gap * (cols - 1)) / cols
        for i, b in ipairs(btns) do
            b:SetPos(((i - 1) % cols) * (bw + gap), math.floor((i - 1) / cols) * (bh + gap))
            b:SetSize(bw, bh)
        end
        local want = math.ceil(#btns / cols) * (bh + gap)
        if self:GetTall() ~= want then self:SetTall(want) end
    end

    if D.state.bn ~= "" and not (D.sync and D.sync.bn == D.state.bn) then
        label(content, "Press Sync (top right) to download the " .. D.state.bn .. " computer: its board, orders, logs and more show up as tabs.")
    end
    local sp = k.Scroll(content)
    sp:Dock(FILL)
    local mine, incoming = {}, {}
    for _, c in pairs(D.calls or {}) do
        if c.role == 2 then mine[#mine + 1] = c else incoming[#incoming + 1] = c end
    end
    table.sort(mine, function(a, b) return a.id > b.id end)
    table.sort(incoming, function(a, b) return a.id > b.id end)
    sub(sp, "Your calls")
    if #mine == 0 then label(sp, "None open.") end
    for _, c in ipairs(mine) do
        local r = row(sp, D.CallTitle(c), #c.resp > 0 and D.CallInbound(c) or "waiting for a response", nil, nil, s(110))
        local x = k.Button(r, "Cancel", function() D.CancelCall(c.id) end, { small = true, danger = true })
        x:Dock(RIGHT)
        x:SetWide(s(100))
        x:DockMargin(0, s(4), s(4), s(4))
    end
    sub(sp, "Calls for you")
    if #incoming == 0 then label(sp, "Nobody needs you right now.") end
    for _, c in ipairs(incoming) do
        local right = c.role == 1 and "you're responding" or (c.showPos and D.CallDistance(c) or "")
        local r = row(sp, D.CallTitle(c) .. "  ·  " .. c.name, right, nil, nil, s(110))
        if c.role == 0 then
            local x = k.Button(r, "Respond", function() D.RespondCall(c.id) end, { small = true, accent = true })
            x:Dock(RIGHT)
            x:SetWide(s(100))
            x:DockMargin(0, s(4), s(4), s(4))
        end
    end
end

-- Rebuild if this tab is open (sv calls / cl_30_calls use it).
function D.PadRebuild(id)
    if IsValid(panel) and tab == id and not view.edit and not view.supply then buildTab() end
end

-- The downloaded copy for your battalion, if any.
local function cur()
    local sy = D.sync
    return (sy and D.state and sy.bn == D.state.bn) and sy or nil
end
local function curX() local sy = cur() return sy and sy.x end

local function anyStat(t)
    for _, v in pairs(t or {}) do
        if v > 0 then return true end
    end
    return false
end

-- has: shown only once the download holds something for it.
local TABS = {
    { id = "comms", name = "Quick response", build = commsTab },
    { id = "notes", name = "Notes", build = notesTab },
    { id = "mission", name = "Mission", build = missionTab, bn = true, has = function()
        if isOfficer() then return true end
        local x = curX()
        return x and x.mission ~= nil end },
    { id = "board", name = "Board", build = boardTab, bn = true, has = function()
        local sy = cur()
        return sy and (#sy.posts > 0 or (sy.x and sy.x.info and sy.x.info.txt ~= "")) end },
    { id = "orders", name = "Orders", build = ordersTab, bn = true, has = function() local x = curX() return x and #x.orders > 0 end },
    { id = "logs", name = "Logs", build = logsTab, bn = true, has = function() local sy = cur() return sy and #sy.logs > 0 end },
    { id = "loa", name = "LOA", build = loaTab, bn = true, has = function() local x = curX() return x and #x.leave > 0 end },
    { id = "stats", name = "Stats", build = statsTab, bn = true, has = function() local x = curX() return x and (anyStat(x.weekAll) or anyStat(x.allMe)) end },
    { id = "file", name = "My file", build = fileTab, bn = true, has = function()
        local x = curX()
        return x and (#x.file.quals > 0 or x.file.ncom > 0 or #x.file.strikes > 0)
    end },
    -- EOD bomb manual (rhylib_eod, Field technician skill "Bomb manual")
    { id = "eod", name = "EOD manual", build = function()
        if D.EodManualBuild then D.EodManualBuild(content, K()) end
    end, has = function() return D.EodManualBuild ~= nil and D.HasEodManual ~= nil and D.HasEodManual() end },
    { id = "records", name = "Records", build = recordsTab, mp = true },
    { id = "ologs", name = "Officer logs", build = ologsTab, mp = true },
    { id = "arrest", name = "Arrest", build = arrestTab, mp = true },
}

local function allowed(t)
    return (not t.mp or D.state.mp) and (not t.bn or D.state.bn ~= "") and (not t.has or t.has() and true or false)
end

local function tabOk(id)
    for _, t in ipairs(TABS) do
        if t.id == id then return allowed(t) end
    end
    return false
end

-- The tab list (rebuilt after a download: new data shows new tabs).
function buildNav()
    if not IsValid(nav) then return end
    local k = K()
    local s = k.S
    nav:Clear()
    for _, t in ipairs(TABS) do
        if allowed(t) then
            local b = k.Button(nav, t.name, function()
                tab = t.id
                view = {}
                buildTab()
            end, { align = "left", accent = t.id == "comms", selected = function() return tab == t.id end })
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, s(4))
        end
    end
    local close = k.Button(nav, "Close", function() panel:Remove() end, { small = true })
    close:Dock(BOTTOM)
    if not tabOk(tab) then
        tab = tabOk("board") and "board" or "comms"
        view = {}
    end
end

function buildTab()
    if not IsValid(content) or not D.state then return end
    clear()
    for _, t in ipairs(TABS) do
        if t.id == tab then t.build() return end
    end
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local function openWindow()
    local k = K()
    if not k then return end
    if IsValid(panel) then panel:Remove() end
    local s = k.S
    panel = vgui.Create("EditablePanel")
    panel:SetSize(s(960), s(620))
    panel:Center()
    panel:MakePopup()
    panel:DockPadding(s(14), s(52), s(14), s(14))
    function panel:Paint(w, h)
        local st = D.state
        k.Plate(0, 0, w, h, { title = "Datapad", ticks = "all", header = s(38), bg = OPAQUE })
        local right = w - s(14) - s(132) - s(12)
        if dl then
            -- Download progress, left of the refresh light.
            local f = math.Clamp((RealTime() - dl.start) / dl.dur, 0, dl.data and 1 or 0.97)
            local bw = s(200)
            local bx, by = right - bw, s(15)
            k.SetCol(k.C.row)
            surface.DrawRect(bx, by, bw, s(8))
            k.SetCol(k.C.good)
            surface.DrawRect(bx, by, bw * f, s(8))
            draw.SimpleText("Downloading " .. math.floor(f * 100) .. "%", k.Font(11), bx - s(8), by + s(4), k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        elseif st and st.bn ~= "" then
            draw.SimpleText(st.bn, k.Font(13), right, s(19), k.C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    function panel:Think()
        local ply = LocalPlayer()
        if not ply:Alive() or not D.Holding(ply) then self:Remove() return end
        -- Download finished: show it.
        -- (waits for both parts; gives up on the second after 5 s more)
        if dl and dl.data and RealTime() - dl.start >= dl.dur and ((dl.extra and dl.more) or RealTime() - dl.start >= dl.dur + 5) then
            D.sync = dl.data
            D.sync.x = dl.extra
            if D.sync.x then
                local more = dl.more or {}
                D.sync.x.info = more.info or { txt = "", by = "", t = 0 }
                D.sync.x.mission = more.mission
            end
            D.sync.at = os.time()
            dl = nil
            surface.PlaySound("buttons/button14.wav")
            local was = tab
            buildNav()
            if was ~= tab or (not view.read and not view.order) then buildTab() end
        end
    end
    function panel:OnRemove() dl = nil end   -- closing the pad cancels a download

    -- The sync button: a panel button with a round status light.
    -- Light: off when up to date, blinking green when the computer has
    -- something new, amber pulsing while downloading.
    local refresh = vgui.Create("DButton", panel)
    refresh:SetText("")
    refresh:SetSize(s(132), s(28))
    refresh:SetPos(s(960) - s(14) - s(132), s(5))
    refresh:SetTooltip("Download the board and logs from the battalion computer")
    function refresh:Paint(w, h)
        local st = D.state
        if not st or st.bn == "" then return true end
        local C = k.C
        local new = hasNew()
        -- Body, like a kit button.
        local body = C.button
        if not dl and self:IsDown() then body = C.buttonDown elseif not dl and self:IsHovered() then body = C.buttonHover end
        k.SetCol(body)
        surface.DrawRect(0, 0, w, h)
        k.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        k.SetCol(C.edgeLight)
        surface.DrawLine(1, 1, w - 1, 1)
        -- The light.
        local r = math.floor(h * 0.24)
        local cx, cy = s(8) + r + s(2), math.floor(h * 0.5)
        local lit, col = 0, C.good
        if dl then
            col = Color(235, 170, 60)
            lit = 0.55 + 0.45 * math.sin(RealTime() * 9)
        elseif new then
            lit = (math.floor(RealTime() * 2.2) % 2 == 0) and 1 or 0.08
        end
        -- Bezel, then the lamp (dark when off), then a glow and a highlight.
        draw.RoundedBox(r + 2, cx - r - 2, cy - r - 2, (r + 2) * 2, (r + 2) * 2, C.edgeDark)
        local off = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 255)
        local on = Color(Lerp(lit, off.r, col.r), Lerp(lit, off.g, col.g), Lerp(lit, off.b, col.b), 255)
        draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, on)
        if lit > 0.3 then
            local g = r * 2
            draw.RoundedBox(g, cx - g, cy - g, g * 2, g * 2, Color(col.r, col.g, col.b, 40 * lit))
        end
        local hr = math.max(1, math.floor(r * 0.35))
        draw.RoundedBox(hr, cx - r * 0.45 - hr, cy - r * 0.45 - hr, hr * 2, hr * 2, Color(255, 255, 255, 40 + 60 * lit))
        -- Label.
        local text = dl and "Syncing" or (new and "New data" or "Sync")
        draw.SimpleText(string.upper(text), k.Font(12, 700), cx + r + s(10), h * 0.5, dl and C.textDim or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    function refresh:DoClick() startDownload() end
    -- Your battalion's colour as the accent.
    k.Tint(panel, function() return D.state and D.BnColor(D.state.bn) or nil end)
    if Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("datapad", function()
            if IsValid(panel) then panel:Remove() return true end
            return false
        end)
    end
    nav = vgui.Create("DPanel", panel)
    nav:Dock(LEFT)
    nav:SetWide(s(170))
    nav:DockMargin(0, 0, s(14), 0)
    nav.Paint = nil
    content = vgui.Create("DPanel", panel)
    content:Dock(FILL)
    content.Paint = nil
    tab = tabOk("board") and "board" or (tabOk(tab) and tab or "comms")
    buildNav()
    view = {}
    buildTab()
end

-- Left click with the datapad out.
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
    for _, key in ipairs(STAT_KEYS) do x.weekAll[key] = net.ReadUInt(32) end
    for _, key in ipairs(STAT_KEYS) do x.weekMe[key] = net.ReadUInt(32) end
    for _, key in ipairs(STAT_KEYS) do x.allMe[key] = net.ReadUInt(32) end
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
