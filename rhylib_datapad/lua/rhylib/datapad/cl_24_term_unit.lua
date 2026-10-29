--[[
    Battalion computer window, unit tabs (client; sv_60_unit): Orders
    (to the battalion or named members, with a status; managers issue
    them), LOA (who is away; members file their own), Applications
    (managers accept or decline) and Apply (troopers outside the
    battalion). Also the "you got accepted" popup and dp.uprompt, which
    work anywhere. The unit data is shared (T.unit: the board's sign-ups
    read it too); the rest is in U. Registered with D.TermAddTab.
      dp.uopen -> dp.unit   dp.uorder, dp.ustatus, dp.uodel, dp.uloa,
      dp.uloadel, dp.udecide, dp.uappget -> dp.uappinfo, dp.uapply,
      dp.uwithdraw, dp.uanswer
]]

local D = Rhylib.Datapad
local T = D.Term   -- (cl_20_terminal.lua: shared helpers, the window, the tab registry)

local U = { appSel = nil, orderDraft = nil, orderSel = nil, appInfo = {}, appAsked = nil }   -- (appInfo[application id] = the applicant's record)
local APP_STATUS = { [0] = "Pending", [1] = "Accepted", [2] = "Declined", [3] = "Withdrawn" }

function T.AskUnit()
    if T.unit or T.unitAsked == T.term.ent then return end
    local ent = T.term.ent
    T.unitAsked = ent
    T.Send("dp.uopen")
    -- No answer (walked away mid-check): allow asking again.
    timer.Simple(5, function() if T.unitAsked == ent and not T.unit then T.unitAsked = nil end end)
end

local function orderById(id)
    for _, o in ipairs(T.unit.orders) do
        if o.id == id then return o end
    end
end

local function orderEditor(body)
    local k = T.K()
    local s = k.S
    local d = U.orderDraft
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
        T.Build()
    end)
    ch:Dock(LEFT)
    ch:SetWide(s(330))
    local foot = T.FootRow(body)
    T.FootButton(foot, "Issue order", function()
        local ids = {}
        if not d.all then
            for id in pairs(d.sel) do ids[#ids + 1] = id end
            if #ids == 0 then
                Derma_Message("Pick at least one member, or order the whole battalion.", "Orders", "OK")
                return
            end
        end
        T.Send("dp.uorder", function()
            net.WriteString(string.sub(d.ti or "", 1, 200))
            net.WriteString(string.sub(d.b or "", 1, 1200))
            local n = math.min(#ids, 127)
            net.WriteUInt(n, 7)
            for i = 1, n do net.WriteString(ids[i]) end
        end)
        U.orderDraft = nil
        T.Build()
    end, { accent = true })
    T.FootButton(foot, "Cancel", function()
        U.orderDraft = nil
        T.Build()
    end)
    -- Member picker.
    if not d.all then
        T.WantPeople()
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
        if not T.people then T.Label(sp, "Loading members…") end
        for _, m in ipairs(T.people or {}) do
            local b = k.Button(sp, m.name, function()
                d.sel[m.id] = not d.sel[m.id] or nil
                T.Build()
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
    local k = T.K()
    local s = k.S
    if not T.unit then T.Label(body, "Loading…") return end
    if U.orderDraft and T.unit.manager then orderEditor(body) return end
    local left, right = T.Columns(body)
    if T.unit.manager then
        local new = k.Button(left, "New order", function()
            U.orderDraft = { ti = "", b = "", all = true, sel = {} }
            T.Build()
        end, { small = true, accent = true })
        new:Dock(TOP)
        new:DockMargin(0, 0, s(8), s(8))
    end
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #T.unit.orders == 0 then T.Label(sp, "No orders yet.") end
    local lastOpen
    for _, o in ipairs(T.unit.orders) do
        local open = o.st <= 2
        if lastOpen ~= open then
            local hd = k.Heading(sp, open and "Open orders" or "Closed")
            hd:Dock(TOP)
            hd:DockMargin(0, s(4), s(8), s(4))
            lastOpen = open
        end
        T.ListRow(sp, o.title, D.OrderSub(o), function() return U.orderSel == o.id end, function()
            U.orderSel = o.id
            T.Build()
        end, D.ORDER_TAG[o.st])
    end

    local o = U.orderSel and orderById(U.orderSel)
    if not o then
        T.Label(right, T.unit.manager and "Pick an order, or issue a new one." or "Pick an order to read it.")
        return
    end
    local h = k.Heading(right, o.title)
    h:Dock(TOP)
    local by = T.Label(right, "From " .. o.by .. "  ·  " .. T.when(o.t))
    by:DockMargin(0, s(4), 0, s(2))
    T.Label(right, "To: " .. D.OrderTo(o), k.C.text)
    local stl = T.Label(right, "Status: " .. D.ORDER_STATUS[o.st] .. (o.sb ~= "" and ("  (" .. o.sb .. ", " .. T.when(o.stt) .. ")") or ""),
        D.OrderColor(o.st))
    stl:DockMargin(0, s(2), 0, s(8))
    if o.canSet or T.unit.manager then
        local foot = T.FootRow(right)
        T.FootButton(foot, "Set status ▾", function()
            D.OrderStatusMenu(o, T.unit.manager, function(st)
                T.Send("dp.ustatus", function()
                    net.WriteUInt(o.id, 16)
                    net.WriteUInt(st, 3)
                end)
            end)
        end, { accent = true })
        if T.unit.manager then
            T.FootButton(foot, "Delete", function()
                T.Send("dp.uodel", function() net.WriteUInt(o.id, 16) end)
                U.orderSel = nil
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
    local k = T.K()
    local s = k.S
    if not T.unit then T.Label(body, "Loading…") return end
    local left, right = T.Columns(body)
    local h = k.Heading(left, "On LOA (" .. #T.unit.leave .. ")")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #T.unit.leave == 0 then T.Label(sp, "Nobody is on LOA.") end
    local now = os.time()
    for _, e in ipairs(T.unit.leave) do
        local range = os.date("%d %b", e.from) .. " – " .. os.date("%d %b %Y", e.to) .. (e.from <= now and "  (now)" or "")
        local r = k.Row(sp, e.name, range .. (e.why ~= "" and ("  ·  " .. e.why) or ""))
        r:Dock(TOP)
        r:DockMargin(0, 0, s(8), s(3))
        if e.mine or T.unit.manager then
            r.right:SetWide(s(100))
            local b = k.Button(r.right, e.mine and "Cancel" or "Remove", function()
                T.Send("dp.uloadel", function() net.WriteUInt(e.id, 16) end)
            end, { small = true, danger = true })
            b:Dock(FILL)
        end
    end

    local rh = k.Heading(right, "File a leave of absence")
    rh:Dock(TOP)
    if not T.unit.member then
        T.Label(right, "Only members of the battalion can file leave.")
        return
    end
    local hint = T.Label(right, "Going away for a while? Your battalion sees it here and on the roster. A new one replaces your old one (at most 120 days).")
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
        local a, b = T.ParseDate(from:GetText(), false), T.ParseDate(to:GetText(), true)
        if not (a and b) or b < a then
            Derma_Message("Write the dates as YYYY-MM-DD, with the end after the start.", "LOA", "OK")
            return
        end
        T.Send("dp.uloa", function()
            net.WriteUInt(math.max(0, a), 32)
            net.WriteUInt(math.max(0, b), 32)
            net.WriteString(string.sub(why:GetText() or "", 1, 200))
        end)
    end, { accent = true })
    go:Dock(TOP)
end

local function appById(id)
    for _, a in ipairs(T.unit.apps) do
        if a.id == id then return a end
    end
end

local function appsTab(body)
    local k = T.K()
    local s = k.S
    if not T.unit then T.Label(body, "Loading…") return end
    local left, right = T.Columns(body)
    local h = k.Heading(left, "Applications")
    h:Dock(TOP)
    local sp = k.Scroll(left)
    sp:Dock(FILL)
    if #T.unit.apps == 0 then T.Label(sp, "No applications yet.") end
    for _, a in ipairs(T.unit.apps) do
        local sub = APP_STATUS[a.st] .. (a.by ~= "" and (" by " .. a.by) or "") .. "  ·  " .. T.when(a.t)
        T.ListRow(sp, a.name, sub, function() return U.appSel == a.id end, function()
            U.appSel = a.id
            T.Build()
        end, a.st == 0 and "New" or nil)
    end

    local a = U.appSel and appById(U.appSel)
    if not a then
        T.Label(right, "Pick an application to read it. Applying is optional: you can still add a trooper straight from the Battalion page.")
        return
    end
    local rh = k.Heading(right, a.name)
    rh:Dock(TOP)
    local by = T.Label(right, APP_STATUS[a.st] .. (a.by ~= "" and (" by " .. a.by) or "") .. "  ·  applied " .. T.when(a.t))
    by:DockMargin(0, s(4), 0, s(8))
    if a.st == 0 then
        local foot = T.FootRow(right)
        local function decide(ok)
            T.Send("dp.udecide", function()
                net.WriteUInt(a.id, 16)
                net.WriteBool(ok)
            end)
        end
        T.FootButton(foot, "Accept", function() decide(true) end, { accent = true })
        T.FootButton(foot, "Decline", function() decide(false) end, { danger = true })
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
    local info = U.appInfo[a.id]
    if not info then
        if U.appAsked ~= a.id then
            U.appAsked = a.id
            T.Send("dp.uappget", function() net.WriteUInt(a.id, 16) end)
        end
        T.Label(tsp, "Loading their record…")
        return
    end
    sub("Service record (all time)")
    local parts = {}
    local keys = table.Copy(D.STAT_RECORD)
    keys[#keys + 1] = "ar"
    for _, key in ipairs(keys) do
        parts[#parts + 1] = (key == "ar" and "Arrests made" or D.STAT_NAMES[key]) .. " " .. D.StatText(key, info.stats[key])
    end
    local st = T.Label(tsp, table.concat(parts, "   ·   "), k.C.text, 13)
    st:DockMargin(0, 0, s(10), s(4))
    T.Label(tsp, "Qualifications: " .. (#info.quals > 0 and table.concat(info.quals, ", ") or "none"), k.C.text, 13)
    T.Label(tsp, info.coms .. " commendation" .. (info.coms == 1 and "" or "s") .. "  ·  " .. info.strikes .. " active strike" .. (info.strikes == 1 and "" or "s"),
        info.strikes > 0 and k.C.bad or k.C.text, 13)
    sub("Arrest record (" .. #info.arrests .. ")")
    if #info.arrests == 0 then T.Label(tsp, "Never arrested.", k.C.good, 13) end
    for _, j in ipairs(info.arrests) do
        local l = T.Label(tsp, os.date("%d %b %Y", j.t) .. "  ·  " .. j.min .. " min  ·  by " .. j.by, nil, 12)
        l:DockMargin(0, s(4), s(10), 0)
        local w = k.Label(tsp, j.why ~= "" and j.why or "No reason given", 14, 500, k.C.bad)
        w:Dock(TOP)
        w:DockMargin(0, 0, s(10), s(2))
    end
end

-- For troopers outside the battalion: apply, or see how it went.
function T.ApplyPanel(body)
    local k = T.K()
    local s = k.S
    if not T.unit then
        T.AskUnit()
        T.Label(body, "Loading…")
        return
    end
    local h = k.Heading(body, "Join the " .. T.term.bn)
    h:Dock(TOP)
    h:DockMargin(0, s(16), 0, s(6))
    if T.unit.myBn == T.term.bn and T.unit.mySt == 1 then
        T.Label(body, "Your application was accepted.", k.C.good, 14)
        local row = vgui.Create("DPanel", body)
        row:Dock(TOP)
        row:SetTall(s(34))
        row:DockMargin(0, s(8), 0, 0)
        row.Paint = nil
        local function answer(join)
            Rhylib.Net.Start("dp.uanswer")
            net.WriteBool(join)
            net.SendToServer()
            T.unit = nil
            T.unitAsked = nil
            timer.Simple(0.5, function() if IsValid(T.panel) then T.Build() end end)
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
    if T.unit.myBn ~= "" and T.unit.myBn ~= T.term.bn and T.unit.mySt == 1 then
        T.Label(body, "The " .. T.unit.myBn .. " accepted your application. Answer that first (at their computer, or the prompt when you join).", nil, 14)
        return
    end
    if T.unit.myBn ~= "" and T.unit.mySt == 0 then
        T.Label(body, T.unit.myBn == T.term.bn and "Your application is pending. Check back here for its status."
            or ("You already have a pending application with the " .. T.unit.myBn .. "."), nil, 14)
        if T.unit.myBn == T.term.bn then
            local w = k.Button(body, "Withdraw application", function()
                T.Send("dp.uwithdraw")
                T.unit, T.unitAsked = nil, nil
            end, { small = true, danger = true })
            w:Dock(TOP)
            w:SetWide(s(220))
            w:DockMargin(0, s(8), 0, 0)
        end
        return
    end
    if not T.unit.canApply then
        T.Label(body, "Only clone troopers without a battalion can apply.", nil, 14)
        return
    end
    local hint = T.Label(body, "Tell the battalion about yourself. Their sergeants and up will see it here. Applying is optional: an NCO can also add you straight away.")
    hint:DockMargin(0, 0, 0, s(8))
    local foot = T.FootRow(body)
    local txt = k.TextEntry(body, "Why do you want to join?")
    txt:SetMultiline(true)
    txt:Dock(FILL)
    T.FootButton(foot, "Apply", function()
        T.Send("dp.uapply", function() net.WriteString(string.sub(txt:GetText() or "", 1, 1200)) end)
        T.unit = nil
        T.unitAsked = nil
    end, { accent = true })
end

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
    T.unitAsked = nil
    if not T.term or T.term.ent ~= ent then return end
    T.unit = u
    if U.appSel and not appById(U.appSel) then U.appSel = nil end
    if IsValid(T.panel) then T.Build() end
end)

--------------------------------------------------------------------------
-- Application prompts (on join, or when a manager decides)
--------------------------------------------------------------------------

local popup

local function acceptedPopup(bn, by)
    local k = T.K()
    if not k then return end
    if IsValid(popup) then popup:Remove() end
    local s = k.S
    popup = vgui.Create("EditablePanel")
    popup:SetSize(s(460), s(220))
    popup:Center()
    popup:MakePopup()
    popup:DockPadding(s(18), s(52), s(18), s(18))
    function popup:Paint(w, h)
        k.Plate(0, 0, w, h, { title = "You got accepted", sub = bn, ticks = "all", header = s(38), bg = T.OPAQUE })
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

-- Esc closes the popup (rhylib_core Rhylib.UI.RegisterCloser).
if Rhylib.UI and Rhylib.UI.RegisterCloser then
    Rhylib.UI.RegisterCloser("datapad.accepted", function()
        if IsValid(popup) then popup:Remove() return true end
        return false
    end)
end

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
    if IsValid(T.panel) and T.term and not T.term.med then
        T.unit, T.unitAsked = nil, nil
        T.Build()
    end
end)

Rhylib.Net.Receive("dp.uappinfo", function()
    local id = net.ReadUInt(16)
    local info = { quals = {}, arrests = {} }
    info.stats = D.ReadStatRow()
    for i = 1, net.ReadUInt(5) do info.quals[i] = net.ReadString() end
    info.coms = net.ReadUInt(8)
    info.strikes = net.ReadUInt(8)
    for i = 1, net.ReadUInt(6) do
        info.arrests[i] = { t = net.ReadUInt(32), by = net.ReadString(), min = net.ReadUInt(10), why = net.ReadString() }
    end
    U.appInfo[id] = info
    if U.appAsked == id then U.appAsked = nil end
    if IsValid(T.panel) and T.tab == "apps" and U.appSel == id then T.Build() end
end)

local function pendingApps()
    local n = 0
    for _, a in ipairs(T.unit and T.unit.apps or {}) do
        if a.st == 0 then n = n + 1 end
    end
    return n
end

D.TermAddTab("orders", { order = 30, name = "Orders", has = function(tm) return not tm.med end, build = ordersTab })
D.TermAddTab("leave", { order = 50, name = "LOA", has = function(tm) return not tm.med end, build = leaveTab })
D.TermAddTab("apps", {
    order = 80,
    name = function() local n = pendingApps() return n > 0 and ("Applications (" .. n .. ")") or "Applications" end,
    has = function(tm) return not tm.med and T.unit ~= nil and T.unit.manager end,
    accent = function() return pendingApps() > 0 end,
    build = appsTab,
})
-- MPs/admins outside the battalion can see it, and can still apply.
D.TermAddTab("apply", {
    order = 90, name = "Apply",
    has = function(tm) return not tm.med and T.unit ~= nil and not T.unit.member and (T.unit.canApply or T.unit.myBn ~= "") end,
    build = T.ApplyPanel,
    reset = function()
        T.unit, T.unitAsked = nil, nil
        U.appSel, U.orderDraft, U.orderSel = nil, nil, nil
        U.appInfo, U.appAsked = {}, nil
    end,
})
