--[[
    Battalion computer window, Personnel tab (client; sv_70_personnel):
    the member list on the left (online / seen, commendations, strikes),
    the open file in a card on the right: name and rank, service record
    tiles, qualification chips, commendations, strikes and NCO notes as
    entries with a coloured edge. The member list is shared (T.people: the order
    editor picks from it, T.WantPeople asks for it); the rest is in P.
    Registered with D.TermAddTab.
      dp.plist -> dp.pmembers   dp.pget -> dp.pfile   dp.pqual, dp.pcom,
      dp.pstrike, dp.pdel, dp.pnote
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)
local C = T.C

local P = { personSel = nil, pfile = nil, pAsked = nil, notesEdit = false, pMissing = nil }   -- (pMissing: a file that didn't come: left the battalion, ...)

-- Members for picking (the Personnel list).
function T.WantPeople()
    if T.people or T.peopleAsked then return end
    T.peopleAsked = true
    T.Send("dp.plist")
    timer.Simple(5, function() if not T.people then T.peopleAsked = nil end end)
end

-- A boxed entry: dim header line, text, optional button on the right.
local function entry(parent, head, text, btnText, btnFn, stripe)
    local k = T.K()
    local s = k.S
    local e = vgui.Create("DPanel", parent)
    e:Dock(TOP)
    e:DockMargin(0, 0, s(8), s(4))
    e:DockPadding(s(12), s(6), s(10), s(6))
    e:SetTall(s(48))
    function e:Paint(w, h)
        T.SetCol(C.bar)
        surface.DrawRect(0, 0, w, h)
        T.SetCol(C.edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        if stripe then
            T.SetCol(stripe)
            surface.DrawRect(0, 0, s(3), h)
        end
    end
    if btnText then
        local holder = vgui.Create("DPanel", e)
        holder:Dock(RIGHT)
        holder:SetWide(s(96))
        holder:DockMargin(s(8), 0, 0, 0)
        holder.Paint = nil
        local b = T.Btn(holder, btnText, btnFn, { small = true, danger = true })
        b:Dock(TOP)
    end
    local hl = k.Label(e, head, 12, 400, C.caps)
    hl:Dock(TOP)
    local tl = k.Label(e, text, 14, 400, C.body)
    tl:Dock(TOP)
    function e:PerformLayout(w, h)
        local want = s(12) + hl:GetTall() + tl:GetTall()
        if math.abs(want - h) > 1 then self:SetTall(want) end
    end
    return e
end

-- A heading with an optional button at its right end.
local function headRow(parent, text, btnText, btnFn)
    local k = T.K()
    local s = k.S
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(s(32))
    row:DockMargin(0, s(10), s(8), s(6))
    row.Paint = nil
    if btnText then
        local b = T.Btn(row, btnText, btnFn, { small = true })
        b:Dock(RIGHT)
        b:DockMargin(s(8), 0, 0, 0)
    end
    local h = T.Heading(row, text)
    h:Dock(FILL)
    return row
end


local function askFile(id)
    if P.pAsked == id or P.pMissing == id then return end
    P.pAsked = id
    T.Send("dp.pget", function() net.WriteString(id) end)
    timer.Simple(5, function()
        if P.pAsked == id then
            P.pAsked, P.pMissing = nil, id
            if IsValid(T.panel) and T.tab == "people" then T.Build() end
        end
    end)
end

local function personFile(parent)
    local k = T.K()
    local s = k.S
    if not P.personSel then
        T.Empty(parent, "Pick a member to open their file.")
        return
    end
    local f = P.pfile and P.pfile.id == P.personSel and P.pfile
    if not f and P.pMissing == P.personSel then
        T.Empty(parent, "This file isn't available (no longer in the battalion?).")
        return
    end
    if not f then
        T.Empty(parent, "Loading…")
        askFile(P.personSel)
        return
    end
    T.Heading(parent, "Personnel file", f.on and C.good or nil):Dock(TOP)
    local h = T.ReaderTitle(parent, f.name)
    h:DockMargin(0, s(8), 0, 0)
    local sub = T.Label(parent, f.rank .. "  ·  " .. (f.on and "online now" or ("last seen " .. (f.seen > 0 and T.when(f.seen) or "never"))))
    sub:DockMargin(0, s(4), 0, s(6))
    local sp = k.Scroll(parent)
    sp:Dock(FILL)
    local id = f.id

    -- Service record (all time, this battalion).
    headRow(sp, "Service record")
    local keys = table.Copy(D.STAT_RECORD)
    keys[#keys + 1] = D.IsMPBattalion(T.term.bn) and "ar" or "jd"
    local vals, names = {}, {}
    for i, key in ipairs(keys) do
        vals[i] = D.StatText(key, f.stats[key])
        names[i] = string.upper(D.STAT_NAMES[key] or key)
    end
    local tiles = vgui.Create("DPanel", sp)
    tiles:Dock(TOP)
    tiles:SetTall(s(58))
    tiles:DockMargin(0, 0, s(8), 0)
    local fV, fK = k.Font(18, 700), k.Font(10, 600)
    function tiles:Paint(w, h)
        local n = #vals
        local gap = s(6)
        local tw = (w - gap * (n - 1)) / n
        for i = 1, n do
            local x = math.floor((i - 1) * (tw + gap))
            T.SetCol(C.bar)
            surface.DrawRect(x, 0, math.floor(tw), h)
            draw.SimpleText(vals[i], fV, x + s(10), s(8), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(names[i], fK, x + s(10), h - s(8), C.caps, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end
    end

    -- Qualifications.
    headRow(sp, "Qualifications")
    if f.discipline then
        local grid = vgui.Create("DPanel", sp)
        grid:Dock(TOP)
        grid:DockMargin(0, 0, s(8), 0)
        grid.Paint = nil
        local btns = {}
        for _, q in ipairs(f.quals) do
            btns[#btns + 1] = T.Btn(grid, q.name, function()
                T.Send("dp.pqual", function()
                    net.WriteString(id)
                    net.WriteString(q.id)
                    net.WriteBool(not q.has)
                end)
            end, { small = true, selected = function() return q.has end,
                tooltip = q.has and "Qualified. Click to remove." or "Not qualified. Click to qualify." })
        end
        function grid:PerformLayout(w)
            local cols, gap, bh = 3, s(6), s(32)
            local bw = (w - gap * (cols - 1)) / cols
            for i, b in ipairs(btns) do
                b:SetPos(((i - 1) % cols) * (bw + gap), math.floor((i - 1) / cols) * (bh + gap))
                b:SetSize(bw, bh)
            end
            local want = math.ceil(#btns / cols) * (bh + gap)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
        local hint = T.Label(sp, "Highlighted ones are held. Click to give or take one; they unlock armoury gear and jobs.", nil, 12)
        hint:DockMargin(0, s(4), s(8), 0)
    else
        local held = {}
        for _, q in ipairs(f.quals) do
            if q.has then held[#held + 1] = q.name end
        end
        T.Label(sp, #held > 0 and table.concat(held, ", ") or "None yet.", #held > 0 and C.text or nil, 13)
    end

    -- Commendations.
    headRow(sp, "Commendations (" .. #f.coms .. ")", f.commend and "Commend" or nil, function()
        k.Prompt("Commendation", "What is " .. f.name .. " commended for?", "", function(t)
            T.Send("dp.pcom", function()
                net.WriteString(id)
                net.WriteString(string.sub(t or "", 1, 600))
            end)
        end)
    end)
    if #f.coms == 0 then T.Label(sp, "None yet.") end
    for _, x in ipairs(f.coms) do
        entry(sp, T.when(x.t) .. "  ·  " .. x.by .. (x.bn ~= "" and ("  ·  " .. x.bn) or ""), x.txt,
            f.discipline and "Remove" or nil, function()
                T.Send("dp.pdel", function()
                    net.WriteString(id)
                    net.WriteUInt(0, 1)
                    net.WriteUInt(x.id, 16)
                end)
            end, C.good)
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
                T.Send("dp.pstrike", function()
                    net.WriteString(id)
                    net.WriteString(string.sub(t or "", 1, 600))
                end)
            end)
        end)
        if #f.strikes == 0 then T.Label(sp, "None.") end
        for _, x in ipairs(f.strikes) do
            local on = x.exp > now
            entry(sp, T.when(x.t) .. "  ·  " .. x.by .. "  ·  " .. (on and ("active until " .. os.date("%d %b", x.exp)) or "expired"), x.txt,
                f.discipline and "Pardon" or nil, function()
                    T.Send("dp.pdel", function()
                        net.WriteString(id)
                        net.WriteUInt(1, 1)
                        net.WriteUInt(x.id, 16)
                    end)
                end, on and C.bad or nil)
        end
    end

    -- NCO notes.
    if f.seeNotes then
        headRow(sp, "NCO notes", (f.discipline and not P.notesEdit) and "Edit notes" or nil, function()
            P.notesEdit = true
            T.Build()
        end)
        if P.notesEdit and f.discipline then
            local te = k.TextEntry(sp, "Notes only sergeants and up can read")
            te:SetMultiline(true)
            te:Dock(TOP)
            te:SetTall(s(140))
            te:DockMargin(0, 0, s(8), s(6))
            te:SetText(f.notes.txt)
            local row = vgui.Create("DPanel", sp)
            row:Dock(TOP)
            row:SetTall(s(32))
            row:DockMargin(0, 0, s(8), 0)
            row.Paint = nil
            local save = T.Btn(row, "Save notes", function()
                T.Send("dp.pnote", function()
                    net.WriteString(id)
                    net.WriteString(string.sub(te:GetText() or "", 1, 4000))
                end)
                P.notesEdit = false
            end, { small = true, primary = true })
            save:Dock(RIGHT)
            local cancel = T.Btn(row, "Cancel", function()
                P.notesEdit = false
                T.Build()
            end, { small = true })
            cancel:Dock(RIGHT)
            cancel:DockMargin(0, 0, s(6), 0)
        elseif f.notes.txt ~= "" then
            entry(sp, "Last edited by " .. f.notes.by .. "  ·  " .. T.when(f.notes.t), f.notes.txt)
        else
            T.Label(sp, "No notes.")
        end
    end
end

local function personnelTab(body)
    local k = T.K()
    local s = k.S
    if not T.people then
        T.Empty(body, "Loading…")
        if not T.peopleAsked then
            T.peopleAsked = true
            T.Send("dp.plist")
            timer.Simple(5, function()
                if not T.people and T.peopleAsked then
                    T.peopleAsked = nil
                    T.people = {}   -- no answer: show an empty list
                    if IsValid(T.panel) and T.tab == "people" then T.Build() end
                end
            end)
        end
        return
    end
    local left, right = T.Columns(body)
    local bar = vgui.Create("DPanel", left)
    bar:Dock(TOP)
    bar:SetTall(s(40))
    bar:DockMargin(0, 0, s(8), s(12))
    bar.Paint = nil
    T.Title(bar, "Personnel"):Dock(LEFT)
    local nOn = 0
    for _, m in ipairs(T.people) do
        if m.on then nOn = nOn + 1 end
    end
    local h = T.Heading(left, "Members · " .. #T.people .. "  ·  " .. nOn .. " online")
    h:Dock(TOP)
    h:DockMargin(0, 0, s(8), s(8))
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #T.people == 0 then T.Empty(sp, "Nobody on the roster yet.") end
    for _, m in ipairs(T.people) do
        local bits = { m.on and "Online" or ("Seen " .. (m.seen > 0 and os.date("%d %b", m.seen) or "never")) }
        if m.coms > 0 then bits[#bits + 1] = m.coms .. " commendation" .. (m.coms == 1 and "" or "s") end
        if m.strikes > 0 then bits[#bits + 1] = m.strikes .. " strike" .. (m.strikes == 1 and "" or "s") end
        if m.note ~= "" then bits[#bits + 1] = m.note end
        T.ListRow(sp, m.name, table.concat(bits, "  ·  "), function() return P.personSel == m.id end, function()
            P.personSel = m.id
            P.pMissing = nil
            P.notesEdit = false
            T.Build()
        end, m.strikes >= 3 and "!" or (m.on and "On" or nil), m.strikes >= 3 and C.bad or C.good)
    end
    personFile(right)
end

Rhylib.Net.Receive("dp.pmembers", function()
    local ent = net.ReadEntity()
    local list = {}
    for i = 1, net.ReadUInt(8) do
        list[i] = { id = net.ReadString(), name = net.ReadString(), r = net.ReadUInt(8), on = net.ReadBool(),
            seen = net.ReadUInt(32), coms = net.ReadUInt(8), strikes = net.ReadUInt(4), note = net.ReadString() }
    end
    T.peopleAsked = nil
    if not T.term or T.term.ent ~= ent then return end
    T.people = list
    if IsValid(T.panel) and (T.tab == "people" or T.tab == "orders" or T.tab == "board") then T.Build() end
end)

Rhylib.Net.Receive("dp.pfile", function()
    local ent = net.ReadEntity()
    local f = { quals = {}, coms = {}, strikes = {} }
    f.id, f.name, f.rank = net.ReadString(), net.ReadString(), net.ReadString()
    f.on, f.seen = net.ReadBool(), net.ReadUInt(32)
    f.commend, f.discipline = net.ReadBool(), net.ReadBool()
    for i = 1, net.ReadUInt(5) do
        f.quals[i] = { id = net.ReadString(), name = net.ReadString(), has = net.ReadBool() }
    end
    f.stats = D.ReadStatRow()
    for i = 1, net.ReadUInt(8) do
        f.coms[i] = { id = net.ReadUInt(16), t = net.ReadUInt(32), by = net.ReadString(), bn = net.ReadString(), txt = net.ReadString() }
    end
    f.seeStrikes = net.ReadBool()
    for i = 1, net.ReadUInt(8) do
        f.strikes[i] = { id = net.ReadUInt(16), t = net.ReadUInt(32), exp = net.ReadUInt(32), by = net.ReadString(), txt = net.ReadString() }
    end
    f.seeNotes = net.ReadBool()
    f.notes = { txt = net.ReadString(), by = net.ReadString(), t = net.ReadUInt(32) }
    P.pAsked = nil
    if not T.term or T.term.ent ~= ent then return end
    P.pfile = f
    if IsValid(T.panel) and T.tab == "people" and P.personSel == f.id then T.Build() end
end)

D.TermAddTab("people", {
    order = 60, name = "Personnel",
    has = function(tm) return not tm.med end,
    build = personnelTab,
    reset = function()
        T.people, T.peopleAsked = nil, nil
        P.personSel, P.pfile, P.pAsked, P.notesEdit = nil, nil, nil, false
    end,
})
