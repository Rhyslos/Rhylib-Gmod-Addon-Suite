--[[
    Jail terminal window (MPs). Left: cuffed prisoners at the terminal,
    with sentence minutes and a reason. Right: who is in jail now, time
    left (or awaiting processing), Release / Process, and their evidence:
    Withhold keeps an item from being returned; contraband never is.
    Client only. Needs rhylib_menus (Menus.Kit). Opened by net mp.term
    (sv_30_jail has the layout); buttons send mp.jail, mp.release and
    mp.destroy. Closes when you walk more than MP.TERM_USE away.
]]

local MP = Rhylib.MP

local function fmt(sec)
    sec = math.max(0, math.ceil(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

Rhylib.Net.Receive("mp.term", function()
    local term = net.ReadEntity()
    local cand = {}
    for i = 1, net.ReadUInt(5) do cand[i] = net.ReadEntity() end
    local jailed = {}
    local Items = Rhylib.Items
    for i = 1, net.ReadUInt(6) do
        local p = net.ReadEntity()
        local why = net.ReadString()
        local awaiting = net.ReadBool()
        local processAt = net.ReadFloat()
        local ev = {}
        for j = 1, net.ReadUInt(6) do
            local netId = net.ReadUInt(Items and Items.NET_BITS or 10)
            ev[j] = { netId = netId, def = Items and Items.FromNet(netId), count = net.ReadUInt(8),
                withheld = net.ReadBool(), contraband = net.ReadBool() }
        end
        jailed[i] = { ply = p, why = why, awaiting = awaiting, processAt = processAt, evidence = ev }
    end
    MP.ShowTerminal(term, cand, jailed)
end)

-- MP.ShowTerminal(term, cand, jailed): builds the terminal window.
-- cand = list of players; jailed = { ply, why, awaiting, processAt,
-- evidence = { netId, def, count, withheld, contraband } }. Client only.
-- Note: `Items` below is not a local in this function (it is local to the
-- net.Receive above), so the Withhold button writes the net id with the
-- fallback 10 bits. Items.NET_BITS is 10 today, so it matches.
function MP.ShowTerminal(term, cand, jailed)

    local K = Rhylib.Menus and Rhylib.Menus.Kit
    if not K then return end
    local s = K.S
    if IsValid(MP.termPanel) then MP.termPanel:Remove() end
    local f = vgui.Create("EditablePanel")
    MP.termPanel = f
    f:SetSize(s(900), s(580))
    f:Center()
    f:MakePopup()
    f:DockPadding(s(14), s(52), s(14), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Jail terminal", sub = "Military police", ticks = "all", header = s(38) })
    end
    function f:Think()
        if not IsValid(term) or LocalPlayer():GetPos():DistToSqr(term:GetPos()) > MP.TERM_USE * MP.TERM_USE then self:Remove() end
    end
    if Rhylib.Menus.RegisterCloser then
        Rhylib.Menus.RegisterCloser("mp.term", function()
            if IsValid(MP.termPanel) then MP.termPanel:Remove() return true end
            return false
        end)
    end
    local closeBtn = K.Button(f, "Close", function() f:Remove() end, { small = true })
    closeBtn:Dock(BOTTOM)
    closeBtn:DockMargin(0, s(10), 0, 0)

    -- Left: jail someone.
    local left = vgui.Create("DPanel", f)
    left:Dock(LEFT)
    left:SetWide(s(400))
    left.Paint = nil
    local h1 = K.Heading(left, "Jail a prisoner")
    h1:Dock(TOP)
    h1:DockMargin(0, 0, 0, s(6))
    local picked = cand[1]
    local list = K.Scroll(left)
    list:Dock(TOP)
    list:SetTall(s(200))
    if #cand == 0 then
        local l = K.Label(list, "No cuffed prisoner here. Bring them to the terminal (escort with handcuffs, R).", 13, 400, K.C.textDim)
        l:Dock(TOP)
    end
    for _, p in ipairs(cand) do
        local b = K.Button(list, IsValid(p) and p:Nick() or "?", function() picked = p end,
            { small = true, align = "left", selected = function() return picked == p end })
        b:Dock(TOP)
        b:DockMargin(0, 0, s(8), s(3))
    end
    local minutes = 5
    local rowM = K.Row(left, "Sentence (minutes)")
    rowM:Dock(TOP)
    rowM.right:SetWide(s(190))   -- (the default width ran over the title)
    rowM:DockMargin(0, s(10), 0, s(4))
    local sl = K.Slider(rowM.right, 1, MP.Cfg("maxSentence"), 0, function() return minutes end, function(v) minutes = v end)
    sl:Dock(FILL)
    local reason = K.TextEntry(left, "Reason")
    reason:Dock(TOP)
    reason:DockMargin(0, s(4), 0, s(8))
    local go = K.Button(left, "Jail", function()
        if not IsValid(picked) then return end
        Rhylib.Net.Start("mp.jail")
        net.WriteEntity(term)
        net.WriteEntity(picked)
        net.WriteUInt(math.Clamp(minutes, 1, 127), 7)
        net.WriteString(string.sub(reason:GetText() or "", 1, 80))
        net.SendToServer()
    end, { accent = true, enabled = function() return IsValid(picked) end })
    go:Dock(TOP)

    -- Right: who's in jail.
    local right = vgui.Create("DPanel", f)
    right:Dock(FILL)
    right:DockMargin(s(16), 0, 0, 0)
    right.Paint = nil
    local h2 = K.Heading(right, "In jail")
    h2:Dock(TOP)
    h2:DockMargin(0, 0, 0, s(6))
    local sp = K.Scroll(right)
    sp:Dock(FILL)
    if #jailed == 0 then
        local l = K.Label(sp, "Nobody is in jail.", 13, 400, K.C.textDim)
        l:Dock(TOP)
    end
    for _, j in ipairs(jailed) do
        local p = j.ply
        local head = vgui.Create("DPanel", sp)
        head:Dock(TOP)
        head:SetTall(s(48))
        head:DockMargin(0, s(4), s(8), s(2))
        function head:Paint(w, h)
            K.SetCol(K.C.header)
            surface.DrawRect(0, 0, w, h)
            if not IsValid(p) then return end
            local state = j.awaiting and ("AWAITING PROCESSING (auto in " .. fmt(j.processAt - CurTime()) .. ")") or fmt(MP.JailLeft(p))
            draw.SimpleText(p:Nick() .. "   " .. state, K.Font(15, 700), s(10), s(14), K.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(j.why, K.Font(12), s(10), s(34), K.C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local rel = K.Button(head, j.awaiting and "Process" or "Release", function()
            Rhylib.Net.Start("mp.release")
            net.WriteEntity(term)
            net.WriteEntity(p)
            net.SendToServer()
        end, { small = true })
        rel:Dock(RIGHT)
        rel:SetWide(s(100))
        rel:DockMargin(0, s(10), s(8), s(10))
        for idx, e in ipairs(j.evidence) do
            local name = (e.def and e.def.name or "Item") .. (e.count > 1 and (" x" .. e.count) or "")
            local row = K.Row(sp, name .. (e.contraband and "   (contraband: kept)" or e.withheld and "   (withheld)" or ""))
            row:Dock(TOP)
            row:DockMargin(s(16), 0, s(8), s(2))
            row.right:SetWide(s(110))
            local b = K.Button(row.right, e.withheld and "Return it" or "Withhold", function()
                Rhylib.Net.Start("mp.destroy")
                net.WriteEntity(term)
                net.WriteEntity(p)
                net.WriteUInt(idx, 6)
                net.WriteUInt(e.netId or 0, Items and Items.NET_BITS or 10)
                net.WriteUInt(e.count, 8)
                net.SendToServer()
            end, { small = true, danger = not e.withheld, enabled = function() return not e.contraband end })
            b:Dock(FILL)
        end
    end
end
