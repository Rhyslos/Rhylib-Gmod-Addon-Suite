--[[
    Jail terminal window (MPs). Left: cuffed prisoners at the terminal,
    with sentence minutes and a reason. Right: who is in jail now, time
    left (or awaiting processing), Release / Process, and their evidence:
    Withhold keeps an item from being returned; contraband never is.
    Client only. Needs the UI kit (Rhylib.UI.Kit, rhylib_core). Opened by net mp.term
    (sv_30_jail has the layout); buttons send mp.jail, mp.release and
    mp.destroy. Closes when you walk more than MP.TERM_USE away.
    Look: the header plate (JAIL TERMINAL, Military police); two columns
    under bands with a diamond and a count. Left: prisoners as cards (the
    picked one with a blue edge; none: a dashed box), Sentence slider,
    Reason box, Jail. Right: a card per prisoner (name, a chip with the
    time left in blue or AWAITING PROCESSING in amber with the auto
    timer, the reason, Release / Process) and their evidence rows under
    it with CONTRABAND · KEPT (red) / WITHHELD (amber) chips and
    Withhold / Return it.
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
local DIA = { {}, {}, {}, {} }
local GRAD = Material("vgui/gradient-l")

-- A chip (caps text on a tinted box) in a Paint; x is its left edge, cy
-- its middle. Returns its width.
local function chip(K, text, x, cy, col)
    local s = K.S
    local cf = K.Font(10, 700)
    surface.SetFont(cf)
    local cw, ch = surface.GetTextSize(text) + s(12), s(16)
    K.SetCol(col, 35)
    surface.DrawRect(x, cy - ch * 0.5, cw, ch)
    K.SetCol(col, 150)
    surface.DrawOutlinedRect(x, cy - ch * 0.5, cw, ch)
    draw.SimpleText(text, cf, x + cw * 0.5, cy, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return cw
end

local function dashed(K, w, h)
    local s = K.S
    K.SetCol(K.C.tick, 140)
    local dash, gap = s(6), s(4)
    for i = 0, w - 1, dash + gap do
        local len = math.min(dash, w - i)
        surface.DrawRect(i, 0, len, 1)
        surface.DrawRect(i, h - 1, len, 1)
    end
    for j = 0, h - 1, dash + gap do
        local len = math.min(dash, h - j)
        surface.DrawRect(0, j, 1, len)
        surface.DrawRect(w - 1, j, 1, len)
    end
end

-- A band: tint, thick edge, diamond, caps title, right text (getRight()).
local function band(K, parent, title, getRight)
    local s, C = K.S, K.C
    local p = vgui.Create("DPanel", parent)
    p:SetTall(s(32))
    local cap = string.upper(title)
    function p:Paint(w, h)
        K.SetCol(C.accent, 35)
        surface.SetMaterial(GRAD)
        surface.DrawTexturedRect(0, 0, w * 0.7, h)
        K.SetCol(C.accent)
        surface.DrawRect(0, 0, s(4), h)
        local cx, cy, r = s(18), h * 0.5, s(5)
        DIA[1].x, DIA[1].y = cx, cy - r
        DIA[2].x, DIA[2].y = cx + r, cy
        DIA[3].x, DIA[3].y = cx, cy + r
        DIA[4].x, DIA[4].y = cx - r, cy
        draw.NoTexture()
        K.SetCol(C.accent)
        surface.DrawPoly(DIA)
        draw.SimpleText(cap, K.Font(15, 700), s(32), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local right = getRight and getRight()
        if right then draw.SimpleText(right, K.Font(12), w - s(10), h * 0.5, C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
    end
    return p
end

function MP.ShowTerminal(term, cand, jailed)

    local K = Rhylib.UI and Rhylib.UI.Kit
    if not K then return end
    local C, s = K.C, K.S
    if IsValid(MP.termPanel) then MP.termPanel:Remove() end
    local f = vgui.Create("EditablePanel")
    MP.termPanel = f
    f:SetSize(math.min(s(940), ScrW() - s(40)), math.min(s(600), ScrH() - s(40)))
    f:Center()
    f:MakePopup()
    f:DockPadding(s(14), s(52), s(14), s(14))
    function f:Paint(w, h)
        K.Plate(0, 0, w, h, { title = "Jail terminal", sub = "Military police", ticks = "all", header = s(38) })
    end
    function f:Think()
        if not IsValid(term) or LocalPlayer():GetPos():DistToSqr(term:GetPos()) > MP.TERM_USE * MP.TERM_USE then self:Remove() end
    end
    local UI = Rhylib.UI
    if UI and UI.RegisterCloser then
        UI.RegisterCloser("mp.term", function()
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
    local nCand = #cand
    local h1 = band(K, left, "Jail a prisoner", function() return nCand == 1 and "1 at the terminal" or (nCand .. " at the terminal") end)
    h1:Dock(TOP)
    h1:DockMargin(0, 0, 0, s(6))
    local picked = cand[1]
    local list = K.Scroll(left)
    list:Dock(TOP)
    list:SetTall(s(200))
    if #cand == 0 then
        local p = vgui.Create("DPanel", list)
        p:Dock(TOP)
        p:DockMargin(0, 0, s(8), 0)
        p:DockPadding(s(14), s(10), s(14), s(10))
        local l = K.Label(p, "No cuffed prisoner here. Bring them to the terminal (escort with handcuffs, R).", 13, 400, C.textDim)
        l:Dock(TOP)
        function p:Think()
            local want = l:GetTall() + s(20)
            if self:GetTall() ~= want then self:SetTall(want) end
        end
        function p:Paint(w, h) dashed(K, w, h) end
    end
    for i, p in ipairs(cand) do
        local b = vgui.Create("DButton", list)
        b:SetText("")
        b:SetTall(s(36))
        b:Dock(TOP)
        b:DockMargin(0, 0, s(8), s(3))
        local alt = i % 2 == 0
        function b:Paint(w, h)
            local sel = picked == p
            K.SetCol(sel and C.buttonDown or (self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row)))
            surface.DrawRect(0, 0, w, h)
            K.SetCol(sel and C.accent or C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            if sel then
                K.SetCol(C.accent)
                surface.DrawRect(0, 0, s(3), h)
            end
            local nf = K.Font(14, 700)
            draw.SimpleText(K.Fit(IsValid(p) and p:Nick() or "?", nf, w - s(110)), nf, s(14), h * 0.5, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if sel then K.Caps("Picked", w - s(12), h * 0.5, C.accent, TEXT_ALIGN_RIGHT) else K.Caps("Cuffed", w - s(12), h * 0.5, C.label, TEXT_ALIGN_RIGHT) end
            return true
        end
        function b:DoClick()
            surface.PlaySound("ui/buttonclick.wav")
            picked = p
        end
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
    local nJailed = #jailed
    local h2 = band(K, right, "In jail", function() return nJailed == 1 and "1 prisoner" or (nJailed .. " prisoners") end)
    h2:Dock(TOP)
    h2:DockMargin(0, 0, 0, s(6))
    local sp = K.Scroll(right)
    sp:Dock(FILL)
    if #jailed == 0 then
        local p = vgui.Create("DPanel", sp)
        p:Dock(TOP)
        p:SetTall(s(56))
        p:DockMargin(0, 0, s(8), 0)
        function p:Paint(w, h)
            dashed(K, w, h)
            draw.SimpleText("Nobody is in jail.", K.Font(13), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    for _, j in ipairs(jailed) do
        local p = j.ply
        local head = vgui.Create("DPanel", sp)
        head:Dock(TOP)
        head:SetTall(s(54))
        head:DockMargin(0, s(6), s(8), s(2))
        function head:Paint(w, h)
            K.SetCol(C.header)
            surface.DrawRect(0, 0, w, h)
            K.SetCol(C.edgeDark)
            surface.DrawOutlinedRect(0, 0, w, h)
            K.SetCol(C.edgeLight)
            surface.DrawLine(1, 1, w - 1, 1)
            K.SetCol(j.awaiting and C.warn or C.accent)
            surface.DrawRect(0, 0, s(3), h)
            if not IsValid(p) then return end
            local nf = K.Font(15, 700)
            local maxW = w - s(140)
            local name = K.Fit(p:Nick(), nf, maxW * 0.55)
            draw.SimpleText(name, nf, s(12), s(17), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            surface.SetFont(nf)
            local cx = s(12) + surface.GetTextSize(name) + s(8)
            if j.awaiting then
                chip(K, (cx > maxW * 0.45 and "AWAITING (AUTO IN " or "AWAITING PROCESSING (AUTO IN ") .. fmt(j.processAt - CurTime()) .. ")", cx, s(17), C.warn)
            else
                chip(K, fmt(MP.JailLeft(p)) .. " LEFT", cx, s(17), C.accent)
            end
            draw.SimpleText(K.Fit(j.why, K.Font(12), maxW), K.Font(12), s(12), s(38), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local rel = K.Button(head, j.awaiting and "Process" or "Release", function()
            Rhylib.Net.Start("mp.release")
            net.WriteEntity(term)
            net.WriteEntity(p)
            net.SendToServer()
        end, { small = true, accent = j.awaiting })
        rel:Dock(RIGHT)
        rel:SetWide(s(100))
        rel:DockMargin(0, s(14), s(10), s(14))
        for idx, e in ipairs(j.evidence) do
            local name = (e.def and e.def.name or "Item") .. (e.count > 1 and (" x" .. e.count) or "")
            local row = vgui.Create("DPanel", sp)
            row:Dock(TOP)
            row:SetTall(s(36))
            row:DockMargin(s(16), 0, s(8), s(2))
            row:DockPadding(0, s(5), s(8), s(5))
            local alt = idx % 2 == 0
            local tag = e.contraband and "CONTRABAND · KEPT" or (e.withheld and "WITHHELD" or nil)
            local tagCol = e.contraband and C.bad or C.warn
            function row:Paint(w, h)
                K.SetCol(self:IsHovered() and C.rowHover or (alt and C.rowAlt or C.row))
                surface.DrawRect(0, 0, w, h)
                K.SetCol(C.edgeDark)
                surface.DrawOutlinedRect(0, 0, w, h)
                if tag then
                    K.SetCol(tagCol)
                    surface.DrawRect(0, 0, s(3), h)
                end
                local nf = K.Font(13, 600)
                local fit = K.Fit(name, nf, w - s(130) - (tag and s(130) or 0))
                draw.SimpleText(fit, nf, s(12), h * 0.5, e.contraband and C.textDim or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if tag then
                    surface.SetFont(nf)
                    chip(K, tag, s(12) + surface.GetTextSize(fit) + s(8), h * 0.5, tagCol)
                end
            end
            local b = K.Button(row, e.withheld and "Return it" or "Withhold", function()
                Rhylib.Net.Start("mp.destroy")
                net.WriteEntity(term)
                net.WriteEntity(p)
                net.WriteUInt(idx, 6)
                net.WriteUInt(e.netId or 0, Items and Items.NET_BITS or 10)
                net.WriteUInt(e.count, 8)
                net.SendToServer()
            end, { small = true, danger = not e.withheld, enabled = function() return not e.contraband end })
            b:Dock(RIGHT)
            b:SetWide(s(110))
        end
    end
end
